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

# 2. Secret Management (Google Secret Manager)
resource "random_password" "gateway_token" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "gateway_token_secret" {
  secret_id = "openclaw-gateway-token-${var.environment}"
  replication {
    auto {}
  }
  depends_on = [google_project_service.enabled_apis]
}

resource "google_secret_manager_secret_version" "gateway_token_version" {
  secret      = google_secret_manager_secret.gateway_token_secret.id
  secret_data = random_password.gateway_token.result
}

# Grant the OpenClaw Workload Identity SA permission to read this specific secret
resource "google_secret_manager_secret_iam_binding" "gateway_token_accessor" {
  secret_id = google_secret_manager_secret.gateway_token_secret.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [
    "serviceAccount:${google_service_account.openclaw_sa.email}"
  ]
}

# 3. SecretProviderClass for CSI Driver
# This tells the CSI driver how to fetch the secret from GSM and sync it to a K8s Secret
resource "kubernetes_manifest" "secret_provider_class" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "openclaw-gsm-secrets"
      namespace = kubernetes_namespace.openclaw_namespace.metadata[0].name
    }
    spec = {
      provider = "gke"
      parameters = {
        secrets = yamlencode([
          {
            resourceName = google_secret_manager_secret_version.gateway_token_version.name
            fileName     = "gateway_token"
          }
        ])
      }
      secretObjects = [
        {
          secretName = "openclaw-gateway-secret"
          type       = "Opaque"
          data = [
            {
              objectName = "gateway_token" # Maps to the fileName above
              key        = "OPENCLAW_GATEWAY_TOKEN"
            }
          ]
        }
      ]
    }
  }

  depends_on = [google_container_cluster.openclaw_cluster]
}

# 4. OpenClaw Deployment

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
          image = "${var.region}-docker.pkg.dev/${var.project_id}/openclaw-repo-${var.environment}/openclaw-custom:v1.0.0"

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
          
          # Securely inject the Gateway Token from the CSI-synced Kubernetes Secret
          env {
            name = "OPENCLAW_GATEWAY_TOKEN"
            value_from {
              secret_key_ref {
                name = "openclaw-gateway-secret"
                key  = "OPENCLAW_GATEWAY_TOKEN"
              }
            }
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

          # Mount the CSI Secrets Store volume (this triggers the sync to K8s Secret)
          volume_mount {
            name       = "gsm-secrets"
            mount_path = "/mnt/secrets"
            read_only  = true
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

        # CSI Volume for Google Secret Manager
        volume {
          name = "gsm-secrets"
          csi {
            driver    = "secrets-store-gke.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "openclaw-gsm-secrets"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map.openclaw_config,
    kubernetes_manifest.secret_provider_class,
    google_secret_manager_secret_iam_binding.gateway_token_accessor
  ]
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
