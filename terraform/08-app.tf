# Retrieve the currently running cluster credentials so the kubernetes provider can deploy resources
data "google_client_config" "default" {}

# This tells the kubernetes provider how to connect to the private GKE cluster
provider "kubernetes" {
  host                   = "https://${google_container_cluster.openclaw_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.openclaw_cluster.master_auth[0].cluster_ca_certificate)
  # IMPORTANT: In a production private cluster with master authorized networks restricted
  # to the Bastion host, Terraform running locally or in CI/CD will NOT be able to connect
  # to the GKE control plane directly unless Terraform is running ON the Bastion host
  # or within a subnet allowed in master_authorized_networks_config. 
  # For the sake of this template, we assume Terraform has access.
}

# 1. ConfigMap for OpenClaw Configuration
resource "kubernetes_config_map" "openclaw_config" {
  metadata {
    name      = "openclaw-config"
    namespace = kubernetes_namespace.openclaw_namespace.metadata[0].name
  }

  data = {
    # Using the templatefile function to inject Terraform variables dynamically
    "openclaw.json" = templatefile("${path.module}/templates/openclaw.json.tpl", {
      project_id = var.project_id
      region     = var.region
      # The SWP explicit proxy URL injected directly into the config
      swp_proxy_url = "http://${google_network_services_gateway.swp.addresses[0]}:443"
    })
  }

  depends_on = [google_container_cluster.openclaw_cluster]
}

# 2. OpenClaw Deployment
resource "random_password" "gateway_token" {
  length  = 32
  special = false
}

resource "kubernetes_deployment" "openclaw_deployment" {
  metadata {
    name      = "openclaw-agent"
    namespace = kubernetes_namespace.openclaw_namespace.metadata[0].name
    labels = {
      app = "openclaw"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "openclaw"
      }
    }

    template {
      metadata {
        labels = {
          app = "openclaw"
        }
      }

      spec {
        # Bind the pod to the Workload Identity Service Account created in Phase 3
        service_account_name = kubernetes_service_account.openclaw_ksa.metadata[0].name

        # Enforce GKE Agent Sandbox (gVisor) for enhanced isolation of the AI Agent
        runtime_class_name = "gvisor"

        # Init Container to copy the read-only ConfigMap to the writable emptyDir volume
        init_container {
          name = "init-config"
          # We can pull from Docker Hub now that Cloud NAT is enabled
          image = "busybox:1.36"
          command = [
            "sh",
            "-c",
            "cp /etc/openclaw-template/* /workspace/ && mkdir -p /workspace/agents/main/agent && echo '{\"version\": 1, \"profiles\": {\"google-vertex:default\": {\"provider\": \"google-vertex\", \"mode\": \"api_key\", \"apiKey\": \"<authenticated>\"}}}' > /workspace/agents/main/agent/auth-profiles.json && chown -R 1000:1000 /workspace/"
          ]

          security_context {
            allow_privilege_escalation = false
          }

          volume_mount {
            name       = "config-template"
            mount_path = "/etc/openclaw-template"
            read_only  = true
          }

          volume_mount {
            name       = "config-writable"
            mount_path = "/workspace"
          }
        }

        # Main OpenClaw Application Container
        container {
          name = "openclaw"
          # We can pull from GitHub Container Registry now that Cloud NAT is enabled
          image = "ghcr.io/openclaw/openclaw:latest"

          # Force the container to run as the 'node' user (UID 1000)
          # and explicitly disable privilege escalation for GKE Autopilot
          security_context {
            run_as_user                = 1000
            allow_privilege_escalation = false
          }

          env {
            name  = "OPENCLAW_GATEWAY_BIND"
            value = "lan" # Listen on 0.0.0.0 instead of 127.0.0.1
          }
          env {
            name  = "OPENCLAW_GATEWAY_TOKEN"
            value = random_password.gateway_token.result # The token for the API
          }
          env {
            name  = "OPENCLAW_SANDBOX"
            value = "0" # Disable Docker-in-Docker sandboxing (we rely on gVisor)
          }
          env {
            name  = "GOOGLE_CLOUD_PROJECT"
            value = var.project_id
          }
          env {
            name  = "GOOGLE_CLOUD_LOCATION"
            value = var.region
          }
          env {
            name  = "GOOGLE_VERTEX_BASE_URL"
            value = "https://aiplatform.googleapis.com/"
          }
          # Inject SWP Proxy configuration via Environment Variables
          env {
            name  = "HTTPS_PROXY"
            value = "http://${google_network_services_gateway.swp.addresses[0]}:443"
          }
          env {
            name  = "HTTP_PROXY"
            value = "http://${google_network_services_gateway.swp.addresses[0]}:443"
          }
          env {
            name  = "NO_PROXY"
            value = "localhost,127.0.0.1,metadata.google.internal,169.254.169.254,10.0.0.0/8,.svc.cluster.local,.googleapis.com,googleapis.com"
          }

          port {
            name           = "gateway"
            container_port = 18789
          }
          port {
            name           = "console"
            container_port = 18791
          }

          # Mount the writable volume populated by the initContainer
          volume_mount {
            name       = "config-writable"
            mount_path = "/home/node/.openclaw"
          }
        }

        # Sidecar Proxy: OpenClaw hardcodes the Control Service (18791) to bind to 127.0.0.1.
        # Kubernetes services cannot route to 127.0.0.1. This sidecar listens on all interfaces (0.0.0.0)
        # on port 18793 and forwards the traffic to the local OpenClaw Control Service.
        container {
          name  = "console-proxy"
          image = "alpine/socat:latest"
          command = [
            "socat",
            "TCP-LISTEN:18793,fork,bind=0.0.0.0",
            "TCP:127.0.0.1:18791"
          ]

          port {
            name           = "proxy"
            container_port = 18793
            protocol       = "TCP"
          }

          security_context {
            allow_privilege_escalation = false
          }
        }

        # Volumes
        volume {
          name = "config-template"
          config_map {
            name = kubernetes_config_map.openclaw_config.metadata[0].name
          }
        }

        volume {
          name = "config-writable"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [kubernetes_config_map.openclaw_config]
}

# Reserve a static internal IP address for the OpenClaw Internal Load Balancer
resource "google_compute_address" "openclaw_ilb_ip" {
  name         = "openclaw-ilb-ip-${var.environment}"
  region       = var.region
  subnetwork   = google_compute_subnetwork.gke_subnet.id
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
}

# 3. Internal Service for OpenClaw
resource "kubernetes_service" "openclaw_service" {
  metadata {
    name      = "openclaw-svc"
    namespace = kubernetes_namespace.openclaw_namespace.metadata[0].name
    annotations = {
      # This annotation configures the service as an Internal HTTP(S) Load Balancer (ILB)
      "networking.gke.io/load-balancer-type"                         = "Internal"
      "cloud.google.com/load-balancer-type"                          = "Internal"
      "networking.gke.io/internal-load-balancer-allow-global-access" = "true"
    }
  }

  spec {
    # Assign the reserved static IP to this Load Balancer
    load_balancer_ip = google_compute_address.openclaw_ilb_ip.address

    selector = {
      app = "openclaw"
    }

    port {
      name        = "gateway"
      port        = 18789
      target_port = 18789
    }

    port {
      name        = "console"
      port        = 18791
      target_port = 18793 # Route to the socat sidecar
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_deployment.openclaw_deployment]
}
