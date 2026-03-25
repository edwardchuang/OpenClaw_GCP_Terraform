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

# 1. Secret Management (Google Secret Manager)
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

# Deploy instances using the module
module "openclaw_instances" {
  source = "./modules/openclaw-instance"

  for_each      = var.openclaw_instances
  instance_name = each.key
  namespace     = kubernetes_namespace.openclaw_namespace.metadata[0].name
  image         = each.value.image
  gateway_token = each.value.gateway_token
  project_id    = var.project_id
  region        = var.region
  swp_proxy_url     = "http://${google_network_services_gateway.swp.addresses[0]}:443"
  environment       = var.environment
  subnet_id         = google_compute_subnetwork.gke_subnet.id
  dns_zone_name     = google_dns_managed_zone.internal_app_zone.name
  dns_zone_dns_name = google_dns_managed_zone.internal_app_zone.dns_name
}
