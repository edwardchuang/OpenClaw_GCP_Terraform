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

provider "kubectl" {
  host                   = "https://${google_container_cluster.openclaw_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.openclaw_cluster.master_auth[0].cluster_ca_certificate)
  load_config_file       = false
}

# 1. OpenClaw Service Account Binding is handled in 06-identity-genai.tf, but the IAM binding for secrets will be handled per-instance.

# Deploy instances using the module
module "openclaw_instances" {
  source = "./modules/openclaw-instance"

  depends_on = [google_project_service.enabled_apis]

  providers = {
    kubernetes = kubernetes
    google     = google
    kubectl    = kubectl
  }

  for_each      = var.openclaw_instances
  instance_name = each.key
  namespace     = kubernetes_namespace.openclaw_namespace.metadata[0].name
  image         = "${var.region}-docker.pkg.dev/${var.project_id}/openclaw-repo-${var.environment}/openclaw-custom:${each.value.image_tag}"
  enable_persistence = each.value.enable_persistence
  storage_size       = each.value.storage_size
  project_id    = var.project_id
  region        = var.region
  swp_proxy_url     = "http://${google_network_services_gateway.swp.addresses[0]}:443"
  environment       = var.environment
  subnet_id         = google_compute_subnetwork.gke_subnet.id
  dns_zone_name     = google_dns_managed_zone.internal_app_zone.name
  dns_zone_dns_name = google_dns_managed_zone.internal_app_zone.dns_name
  openclaw_sa_email = google_service_account.openclaw_sa.email
}
