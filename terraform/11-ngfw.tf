# ------------------------------------------------------------------------
# Cloud Next Generation Firewall (NGFW) with Threat Intelligence
# ------------------------------------------------------------------------

# 1. Create a Global Network Firewall Policy
resource "google_compute_network_firewall_policy" "ngfw_policy" {
  name        = "openclaw-ngfw-policy-${var.environment}"
  description = "Global network firewall policy for OpenClaw VPC to enforce Threat Intelligence"
  project     = var.project_id
  depends_on  = [google_project_service.enabled_apis]
}

# 2. Attach the Firewall Policy to the VPC Network
resource "google_compute_network_firewall_policy_association" "vpc_association" {
  name              = "openclaw-ngfw-vpc-assoc-${var.environment}"
  attachment_target = google_compute_network.vpc.id
  firewall_policy   = google_compute_network_firewall_policy.ngfw_policy.id
  project           = var.project_id
}

# 3. Rule: Block Known Malicious IPs using Google Cloud Threat Intelligence
resource "google_compute_network_firewall_policy_rule" "block_malicious_ips" {
  firewall_policy = google_compute_network_firewall_policy.ngfw_policy.name
  rule_name       = "block-gcti-malicious-ips"
  description     = "Block outbound traffic to known malicious IPs identified by Google Cloud Threat Intelligence"
  priority        = 1000
  action          = "deny"
  direction       = "EGRESS"
  disabled        = false
  enable_logging  = true

  match {
    dest_threat_intelligences = [
      "iplist-known-malicious-ips",
      "iplist-tor-exit-nodes"
    ]
    layer4_configs {
      ip_protocol = "all"
    }
  }
}
