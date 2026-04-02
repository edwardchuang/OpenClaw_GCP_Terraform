# Get the local IP of the machine running Terraform
data "http" "my_ip" {
  url = "https://api.ipify.org"
}

resource "google_container_cluster" "openclaw_cluster" {
  name     = "openclaw-gke-${var.environment}-v2"
  location = var.region

  # Enable GKE Autopilot
  enable_autopilot    = true
  deletion_protection = false

  # Note: Autopilot enables the Secrets Store CSI Driver by default,
  # but the CRDs might not be immediately available via the Terraform Kubernetes provider
  # during the initial cluster creation run.
  secret_manager_config {
    enabled = true
  }

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.gke_subnet.id

  # Private Cluster Configuration
  private_cluster_config {
    enable_private_nodes = true
    # Set to false so Terraform can reach the control plane over the internet
    # (Traffic is still blocked by master_authorized_networks_config below)
    enable_private_endpoint = false
    # This range is used by the GKE control plane
    master_ipv4_cidr_block = "172.16.0.0/28"
  }

  # IP Allocation Policy for Pods and Services
  ip_allocation_policy {
    cluster_secondary_range_name  = "pod-ranges"
    services_secondary_range_name = "service-ranges"
  }

  # Enable Cloud DNS with VPC Scope so the Bastion host can resolve cluster.local
  dns_config {
    cluster_dns       = "CLOUD_DNS"
    cluster_dns_scope = "VPC_SCOPE"
  }

  # Master Authorized Networks Config
  # Allow access to the control plane from the Bastion host AND the Terraform runner's IP
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "${google_compute_instance.bastion.network_interface[0].network_ip}/32"
      display_name = "Bastion Host"
    }
    cidr_blocks {
      cidr_block   = "${chomp(data.http.my_ip.response_body)}/32"
      display_name = "Terraform Runner IP"
    }
  }

  # Ensure Workload Identity is enabled
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable Datapath Provider for advanced networking features
  datapath_provider = "ADVANCED_DATAPATH"

  # We use depends_on to ensure networking and APIs are fully ready
  depends_on = [
    google_project_service.enabled_apis,
    google_compute_subnetwork.gke_subnet,
    google_compute_subnetwork.proxy_subnet,
    google_dns_record_set.pga_cname_record
  ]
}

# Allow egress from GKE nodes to the Master Control Plane
# This is required because our catch-all deny rule would otherwise block the nodes
# from checking in with the Kubernetes API.


