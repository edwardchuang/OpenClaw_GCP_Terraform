# ------------------------------------------------------------------------
# Private Google Access (PGA) Cloud DNS Configuration
# ------------------------------------------------------------------------
# In a strict "No Cloud NAT" environment, nodes must use the restricted Google VIP
# to access Google APIs (like GCR to pull container images). 
# We must use Cloud DNS to force *.googleapis.com to resolve to the restricted VIP.

locals {
  restricted_vip_ips = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]

  # The domains required for GKE to function (pull images, authenticate)
  pga_domains = [
    "googleapis.com.",
    "gcr.io.",
    "pkg.dev."
  ]
}

resource "google_dns_managed_zone" "pga_zone" {
  for_each    = toset(local.pga_domains)
  name        = "pga-${replace(each.value, ".", "-")}zone"
  dns_name    = each.value
  description = "Private DNS zone for PGA routing to ${each.value}"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc.id
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

# The A record for the base domain (e.g., googleapis.com)
resource "google_dns_record_set" "pga_a_record" {
  for_each     = toset(local.pga_domains)
  name         = each.value
  managed_zone = google_dns_managed_zone.pga_zone[each.value].name
  type         = "A"
  ttl          = 300
  rrdatas      = local.restricted_vip_ips
}

# ------------------------------------------------------------------------
# Application Internal DNS (For Bastion/VPC Access)
# ------------------------------------------------------------------------

resource "google_dns_managed_zone" "internal_app_zone" {
  name        = "openclaw-internal-zone"
  dns_name    = "openclaw.internal."
  description = "Private DNS zone for OpenClaw internal services"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc.id
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

# The A record pointing to the GKE Internal Load Balancer
resource "google_dns_record_set" "openclaw_ui_record" {
  name         = "ui.${google_dns_managed_zone.internal_app_zone.dns_name}"
  managed_zone = google_dns_managed_zone.internal_app_zone.name
  type         = "A"
  ttl          = 300

  # Dynamically pull the static IP reserved for the Load Balancer
  rrdatas = [google_compute_address.openclaw_ilb_ip.address]
}
# The CNAME record for all subdomains (e.g., *.googleapis.com)
resource "google_dns_record_set" "pga_cname_record" {
  for_each     = toset(local.pga_domains)
  name         = "*.${each.value}"
  managed_zone = google_dns_managed_zone.pga_zone[each.value].name
  type         = "CNAME"
  ttl          = 300
  rrdatas      = [each.value]
}

