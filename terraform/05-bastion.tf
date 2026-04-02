# Create a dedicated Service Account for the Bastion Host
resource "google_service_account" "bastion_sa" {
  account_id   = "openclaw-bastion-sa-${var.environment}"
  display_name = "Bastion Host Service Account"
  depends_on   = [google_project_service.enabled_apis]
}

# Grant the Bastion SA roles to manage GKE clusters
resource "google_project_iam_member" "bastion_gke_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.bastion_sa.email}"
}

# The Bastion Host VM
resource "google_compute_instance" "bastion" {
  name         = "openclaw-bastion-${var.environment}"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.gke_subnet.id
    # Notice: NO access_config block here. This ensures the VM gets NO public IP.
  }

  service_account {
    email  = google_service_account.bastion_sa.email
    scopes = ["cloud-platform"]
  }

  tags = ["bastion", "iap-ssh"]

  # Startup script to install tools using the Secure Web Proxy
  metadata_startup_script = <<-EOF
    #!/bin/bash
    # Set proxy for curl and wget
    export HTTP_PROXY="http://${google_network_services_gateway.swp.addresses[0]}:443"
    export HTTPS_PROXY="http://${google_network_services_gateway.swp.addresses[0]}:443"
    
    # Configure APT to use the proxy
    echo "Acquire::http::Proxy \"http://${google_network_services_gateway.swp.addresses[0]}:443\";" | sudo tee /etc/apt/apt.conf.d/proxy.conf
    echo "Acquire::https::Proxy \"http://${google_network_services_gateway.swp.addresses[0]}:443\";" | sudo tee -a /etc/apt/apt.conf.d/proxy.conf

    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubectl google-cloud-cli-gke-gcloud-auth-plugin jq
  EOF
}

# Allow SSH access to the Bastion *only* via Google Identity-Aware Proxy (IAP)
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "openclaw-allow-iap-ssh"
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  description = "Allow SSH from Identity-Aware Proxy (IAP) to Bastion"

  # Google's standard IAP IP range
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["iap-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Optional: Output the gcloud command to connect to the Bastion securely
output "bastion_ssh_command" {
  description = "Command to securely SSH into the Bastion host via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.bastion.name} --zone ${var.zone} --tunnel-through-iap --project ${var.project_id}"
}
