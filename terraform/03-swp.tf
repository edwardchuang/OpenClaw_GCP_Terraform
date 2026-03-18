# ------------------------------------------------------------------------
# Enterprise Certificate Management: Google Private CA
# ------------------------------------------------------------------------
resource "google_privateca_ca_pool" "default" {
  name     = "openclaw-ca-pool-${var.environment}"
  location = var.region
  tier     = "DEVOPS"

  depends_on = [google_project_service.enabled_apis]
}

resource "google_privateca_certificate_authority" "root_ca" {
  pool                     = google_privateca_ca_pool.default.name
  certificate_authority_id = "openclaw-root-ca-${var.environment}"
  location                 = var.region

  config {
    subject_config {
      subject {
        organization = "OpenClaw"
        common_name  = "OpenClaw Internal Root CA"
      }
    }
    x509_config {
      ca_options {
        is_ca                  = true
        max_issuer_path_length = 10
      }
      key_usage {
        base_key_usage {
          cert_sign = true
          crl_sign  = true
        }
        extended_key_usage {
          server_auth = true
        }
      }
    }
  }

  key_spec {
    algorithm = "RSA_PKCS1_4096_SHA256"
  }

  # Note: Set to false for demo/tear-down. Should be true in production.
  deletion_protection                    = false
  ignore_active_certificates_on_deletion = true
}

# Generate a private key for the proxy
resource "tls_private_key" "swp_key" {
  algorithm   = "RSA"
  ecdsa_curve = "P256"
}

# Create a Certificate Signing Request (CSR)
resource "tls_cert_request" "swp_csr" {
  private_key_pem = tls_private_key.swp_key.private_key_pem
  subject {
    common_name  = "swp.openclaw.internal"
    organization = "OpenClaw"
  }
}

# Issue the certificate using the Private CA
resource "google_privateca_certificate" "swp_cert" {
  pool                  = google_privateca_ca_pool.default.name
  location              = var.region
  certificate_authority = google_privateca_certificate_authority.root_ca.certificate_authority_id
  name                  = "openclaw-swp-cert-${var.environment}"
  pem_csr               = tls_cert_request.swp_csr.cert_request_pem
  lifetime              = "864000s" # 10 days (in production use auto-rotation)
}

# Map the issued certificate into Certificate Manager for the SWP
resource "google_certificate_manager_certificate" "swp_cert" {
  name        = "openclaw-swp-cert-${var.environment}"
  description = "Managed cert for SWP explicit proxy via Private CA"
  self_managed {
    pem_certificate = google_privateca_certificate.swp_cert.pem_certificate
    pem_private_key = tls_private_key.swp_key.private_key_pem
  }
}

# ------------------------------------------------------------------------
# Secure Web Proxy & Security Policies
# ------------------------------------------------------------------------

# Gateway Security Policy (Container for rules)
resource "google_network_security_gateway_security_policy" "swp_policy" {
  name        = "openclaw-swp-policy-${var.environment}"
  location    = var.region
  description = "Gateway security policy for OpenClaw Secure Web Proxy"
}

# Allow explicit egress for the Bastion to download apt packages
resource "google_network_security_gateway_security_policy_rule" "allow_debian_apt" {
  name                    = "allow-debian-apt"
  location                = var.region
  gateway_security_policy = google_network_security_gateway_security_policy.swp_policy.name
  enabled                 = true
  priority                = 100
  session_matcher         = "host() == 'deb.debian.org' || host() == 'packages.cloud.google.com' || host() == 'apt.kubernetes.io'"
  basic_profile           = "ALLOW"
}

# Allow explicit egress to GitHub (for OpenClaw Agent Skills)
resource "google_network_security_gateway_security_policy_rule" "allow_github" {
  name                    = "allow-github"
  location                = var.region
  gateway_security_policy = google_network_security_gateway_security_policy.swp_policy.name
  enabled                 = true
  priority                = 110
  session_matcher         = "host() == 'github.com' || host() == 'api.github.com'"
  basic_profile           = "ALLOW"
}

# SWP Rule: Deny all other external web traffic
resource "google_network_security_gateway_security_policy_rule" "deny_all" {
  name                    = "deny-all-web"
  location                = var.region
  gateway_security_policy = google_network_security_gateway_security_policy.swp_policy.name
  enabled                 = true
  priority                = 9999
  session_matcher         = "true"
  basic_profile           = "DENY"
}

# Allocate a static internal IP for the Proxy so the Bastion script can reliably target it
resource "google_compute_address" "swp_ip" {
  name         = "openclaw-swp-ip-${var.environment}"
  region       = var.region
  subnetwork   = google_compute_subnetwork.gke_subnet.id
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
}

# The Secure Web Proxy Instance
resource "google_network_services_gateway" "swp" {
  name                                 = "openclaw-swp-${var.environment}"
  location                             = var.region
  type                                 = "SECURE_WEB_GATEWAY"
  ports                                = [443]
  network                              = google_compute_network.vpc.id
  subnetwork                           = google_compute_subnetwork.gke_subnet.id
  addresses                            = [google_compute_address.swp_ip.id]
  certificate_urls                     = [google_certificate_manager_certificate.swp_cert.id]
  gateway_security_policy              = google_network_security_gateway_security_policy.swp_policy.id
  delete_swg_autogen_router_on_destroy = true
}
