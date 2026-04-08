resource "kubernetes_persistent_volume_claim" "openclaw_pvc" {
  count = var.enable_persistence ? 1 : 0
  
  wait_until_bound = false

  metadata {
    name      = "openclaw-pvc-${var.instance_name}"
    namespace = var.namespace
    labels = {
      app      = "openclaw"
      instance = var.instance_name
    }
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.storage_size
      }
    }
    # Using standard storage class (which is backed by pd-standard or pd-balanced in GKE)
    storage_class_name = "standard-rwo"
  }
}

resource "kubernetes_config_map" "openclaw_config" {
  metadata {
    name      = "openclaw-config-${var.instance_name}"
    namespace = var.namespace
  }

  data = {
    "openclaw.json" = templatefile("${path.module}/../../templates/openclaw.json.tpl", {
      instance_name = var.instance_name
      project_id    = var.project_id
      region        = var.region
      swp_proxy_url = var.swp_proxy_url
    })
  }
}

resource "kubernetes_deployment" "openclaw_deployment" {
  # We set wait_for_rollout to false so Terraform doesn't hang indefinitely 
  # during initial deployment if the user hasn't pushed the custom Docker image yet.
  wait_for_rollout = false

  metadata {
    name      = "openclaw-agent-${var.instance_name}"
    namespace = var.namespace
    labels = {
      app      = "openclaw"
      instance = var.instance_name
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app      = "openclaw"
        instance = var.instance_name
      }
    }

    template {
      metadata {
        labels = {
          app      = "openclaw"
          instance = var.instance_name
        }
      }
      spec {
        service_account_name = "openclaw-app-ksa"
        # Removed gVisor because it prevents headless Chromium from running (syscall incompatibility).
        
        init_container {
          name    = "init-config"
          image   = "busybox:1.36"
          command = [
            "sh", 
            "-c", 
            "cp /etc/openclaw-template/* /workspace/ && mkdir -p /workspace/agents/main/agent && if [ ! -f /workspace/agents/main/agent/auth-profiles.json ]; then echo '{\"version\": 1, \"profiles\": {\"google-vertex:default\": {\"provider\": \"google-vertex\", \"mode\": \"api_key\", \"apiKey\": \"<authenticated>\"}}}' > /workspace/agents/main/agent/auth-profiles.json; fi && chown -R 1000:1000 /workspace/"
          ]
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

        container {
          name  = "openclaw"
          image = var.image
          image_pull_policy = "Always"
          security_context {
            run_as_user                = 1000
            allow_privilege_escalation = false
          }
          env {
            name  = "OPENCLAW_GATEWAY_BIND"
            value = "lan"
          }
          # Securely inject the Gateway Token from the CSI-synced Kubernetes Secret
          env {
            name  = "OPENCLAW_GATEWAY_TOKEN"
            value_from {
              secret_key_ref {
                name = "openclaw-gateway-secret-${var.instance_name}"
                key  = "OPENCLAW_GATEWAY_TOKEN"
              }
            }
          }
          env {
            name  = "OPENCLAW_SANDBOX"
            value = "0"
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
          env {
            name  = "PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH"
            value = "/usr/bin/chromium"
          }
          env {
            name  = "PUPPETEER_EXECUTABLE_PATH"
            value = "/usr/bin/chromium"
          }
          env {
            name  = "CHROME_BIN"
            value = "/usr/bin/chromium"
          }
          env {
            name  = "DEBUG"
            value = "openclaw:*,pw:api"
          }
          env {
            name  = "OPENCLAW_LOG_LEVEL"
            value = "trace"
          }
          env {
            name  = "HTTPS_PROXY"
            value = var.swp_proxy_url
          }
          
          env {
            name  = "HTTP_PROXY"
            value = var.swp_proxy_url
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
          volume_mount {
            name       = "config-writable"
            mount_path = "/home/node/.openclaw"
          }
          volume_mount {
            name       = "gsm-secrets"
            mount_path = "/mnt/secrets"
            read_only  = true
          }
        }
        container {
          name    = "console-proxy"
          image   = "alpine/socat:latest"
          command = ["socat", "TCP-LISTEN:18793,fork,bind=0.0.0.0", "TCP:127.0.0.1:18791"]
          port {
            name           = "proxy"
            container_port = 18793
          }
        }
        volume {
          name = "config-template"
          config_map {
            name = kubernetes_config_map.openclaw_config.metadata[0].name
          }
        }
        dynamic "volume" {
          for_each = var.enable_persistence ? [] : [1]
          content {
            name = "config-writable"
            empty_dir {}
          }
        }

        dynamic "volume" {
          for_each = var.enable_persistence ? [1] : []
          content {
            name = "config-writable"
            persistent_volume_claim {
              claim_name = kubernetes_persistent_volume_claim.openclaw_pvc[0].metadata[0].name
            }
          }
        }

        volume {
          name = "gsm-secrets"
          csi {
            driver    = "secrets-store-gke.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "openclaw-gsm-secrets-${var.instance_name}"
            }
          }
        }
      }
    }
  }
}

# Reserve a static internal IP address for this instance's Internal Load Balancer
resource "google_compute_address" "openclaw_ilb_ip" {
  name         = "openclaw-ilb-ip-${var.environment}-${var.instance_name}"
  region       = var.region
  subnetwork   = var.subnet_id
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
}

resource "kubernetes_service" "openclaw_service" {
  metadata {
    name      = "openclaw-svc-${var.instance_name}"
    namespace = var.namespace
    annotations = {
      "networking.gke.io/load-balancer-type"                         = "Internal"
      "cloud.google.com/load-balancer-type"                          = "Internal"
      "networking.gke.io/internal-load-balancer-allow-global-access" = "true"
    }
  }
  spec {
    load_balancer_ip = google_compute_address.openclaw_ilb_ip.address

    selector = {
      app      = "openclaw"
      instance = var.instance_name
    }
    port {
      name        = "gateway"
      port        = 18789
      target_port = 18789
    }
    port {
      name        = "console"
      port        = 18791
      target_port = 18793
    }
    type = "LoadBalancer"
  }
}

# The A record pointing to the GKE Internal Load Balancer for this instance
resource "google_dns_record_set" "openclaw_ui_record" {
  name         = "${var.instance_name}.ui.${var.dns_zone_dns_name}"
  managed_zone = var.dns_zone_name
  type         = "A"
  ttl          = 300

  # Dynamically pull the static IP reserved for the Load Balancer
  rrdatas = [google_compute_address.openclaw_ilb_ip.address]
}