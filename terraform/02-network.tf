resource "google_compute_network" "vpc" {
  name                    = "openclaw-vpc-${var.environment}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.enabled_apis]
}

# Main Subnet for GKE and Application Workloads
resource "google_compute_subnetwork" "gke_subnet" {
  name                     = "openclaw-gke-subnet-${var.environment}"
  ip_cidr_range            = "10.0.0.0/20"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  # Secondary ranges are required for GKE Alias IPs (Pods and Services)
  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "service-ranges"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# Proxy-only subnet required for Regional Internal HTTP(S) LBs and Secure Web Proxy
resource "google_compute_subnetwork" "proxy_subnet" {
  name          = "openclaw-proxy-subnet-${var.environment}"
  ip_cidr_range = "10.3.0.0/23"
  region        = var.region
  network       = google_compute_network.vpc.id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# ------------------------------------------------------------------------
# Cloud NAT Configuration
# ------------------------------------------------------------------------
# Added to allow GKE nodes to pull public images (ghcr.io, docker.io) 
# and to allow the AI Agent to interact with the public internet.

resource "google_compute_router" "router" {
  name    = "openclaw-router-${var.environment}"
  region  = var.region
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat" {
  name                               = "openclaw-nat-${var.environment}"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
