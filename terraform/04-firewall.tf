# To fully implement Zero-Trust egress, we need to block broad internet access 
# and only allow traffic to Private Google Access (PGA) and our Secure Web Proxy.

# Allow egress to Private Google Access IPs (restricted.googleapis.com)
resource "google_compute_firewall" "allow_pga_egress" {
  name        = "openclaw-allow-egress-pga"
  network     = google_compute_network.vpc.name
  direction   = "EGRESS"
  priority    = 1000
  description = "Allow egress to Google APIs via Private Google Access"

  # private.googleapis.com VIP range
  destination_ranges = ["199.36.153.8/30"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

# Allow egress to the Proxy-only subnet (for internal LBs and SWP routing)
resource "google_compute_firewall" "allow_proxy_subnet_egress" {
  name        = "openclaw-allow-egress-proxy"
  network     = google_compute_network.vpc.name
  direction   = "EGRESS"
  priority    = 1010
  description = "Allow egress to the Proxy-only subnet"

  destination_ranges = [google_compute_subnetwork.proxy_subnet.ip_cidr_range]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

# ------------------------------------------------------------------------
# CRITICAL GKE FIX: Allow Google Metadata Server Access
# ------------------------------------------------------------------------
# Nodes must contact 169.254.169.254:80 to fetch Workload Identity tokens 
# and authenticate to the GKE Master via gke-exec-auth-plugin.
resource "google_compute_firewall" "allow_metadata_egress" {
  name        = "openclaw-allow-metadata-egress"
  network     = google_compute_network.vpc.name
  direction   = "EGRESS"
  priority    = 800
  description = "Allow egress to Google Metadata Server for IAM, DNS, and NTP"

  destination_ranges = ["169.254.169.254/32"]

  allow {
    protocol = "tcp"
    ports    = ["80", "53"]
  }

  allow {
    protocol = "udp"
    ports    = ["53", "123"]
  }
}

# ------------------------------------------------------------------------
# Bastion to GKE Access (For IAP Tunnels)
# ------------------------------------------------------------------------
resource "google_compute_firewall" "allow_bastion_to_gke" {
  name        = "openclaw-allow-bastion-to-gke"
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  priority    = 950
  description = "Allow Bastion host to communicate with GKE nodes and pods (required for IAP port forwarding)"

  # Source is the internal IP of the Bastion VM
  source_ranges = ["${google_compute_instance.bastion.network_interface[0].network_ip}/32"]

  # Allow access to the entire GKE primary and secondary ranges
  # 10.0.0.0/20 (Nodes), 10.1.0.0/16 (Pods), 10.2.0.0/20 (Services)
  destination_ranges = [
    google_compute_subnetwork.gke_subnet.ip_cidr_range,
    google_compute_subnetwork.gke_subnet.secondary_ip_range[0].ip_cidr_range,
    google_compute_subnetwork.gke_subnet.secondary_ip_range[1].ip_cidr_range
  ]

  allow {
    protocol = "tcp"
    # Allow the specific gateway port and sidecar port
    ports = ["18789", "18793"]
  }
}

# ------------------------------------------------------------------------
# GCP Health Checks (Required for Internal Load Balancers)
# ------------------------------------------------------------------------
resource "google_compute_firewall" "allow_health_checks" {
  name        = "openclaw-allow-health-checks"
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  priority    = 960
  description = "Allow GCP health checks to reach GKE Load Balancers"

  # Google's standard health check IP ranges
  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]

  destination_ranges = [
    google_compute_subnetwork.gke_subnet.ip_cidr_range,
    google_compute_subnetwork.gke_subnet.secondary_ip_range[0].ip_cidr_range,
    google_compute_subnetwork.gke_subnet.secondary_ip_range[1].ip_cidr_range
  ]

  allow {
    protocol = "tcp"
    ports    = ["18789", "18793"]
  }
}

# ------------------------------------------------------------------------
# CRITICAL GKE FIX: Allow all internal VPC egress
# ------------------------------------------------------------------------
# In a "Deny All" egress architecture, we must explicitly allow GKE nodes, 
# pods, and services to talk to each other. Without this, health checks 
# (kube-dns, konnectivity) will fail and cluster provisioning will hang at 83%.

resource "google_compute_firewall" "allow_internal_egress" {
  name        = "openclaw-allow-internal-egress"
  network     = google_compute_network.vpc.name
  direction   = "EGRESS"
  priority    = 900
  description = "Allow all internal egress within the VPC (Node-to-Node, Pod-to-Pod)"

  # Allow egress to the entire 10.0.0.0/8 private space
  destination_ranges = ["10.0.0.0/8"]

  allow {
    protocol = "all"
  }
}

resource "google_compute_firewall" "allow_gke_master_egress" {
  name        = "openclaw-allow-gke-master-egress"
  network     = google_compute_network.vpc.name
  direction   = "EGRESS"
  priority    = 1020
  description = "Allow GKE nodes to communicate with the control plane"

  destination_ranges = ["172.16.0.0/28"]
  allow {
    protocol = "tcp"
    ports    = ["443", "10250"]
  }
}