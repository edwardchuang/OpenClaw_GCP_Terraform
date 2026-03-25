# ------------------------------------------------------------------------
# Enterprise Certificate Management: Google Private CA
# ------------------------------------------------------------------------
resource "random_id" "ca_suffix" {
  byte_length = 4
}

resource "google_privateca_ca_pool" "default" {
  name     = "openclaw-ca-pool-ent-${var.environment}-${random_id.ca_suffix.hex}"
  location = var.region
  tier     = "ENTERPRISE"

  depends_on = [google_project_service.enabled_apis]
}

resource "google_privateca_certificate_authority" "root_ca" {
  pool                     = google_privateca_ca_pool.default.name
  certificate_authority_id = "openclaw-root-ca-ent-${var.environment}-${random_id.ca_suffix.hex}"
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

  lifecycle {
    create_before_destroy = true
  }
}

# Create a Certificate Signing Request (CSR)
resource "tls_cert_request" "swp_csr" {
  private_key_pem = tls_private_key.swp_key.private_key_pem
  subject {
    common_name  = "swp.openclaw.internal"
    organization = "OpenClaw"
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Wait for CA propagation to prevent provider inconsistency errors
resource "time_sleep" "wait_for_ca" {
  depends_on      = [google_privateca_certificate_authority.root_ca]
  create_duration = "30s"
}

# Issue the certificate using the Private CA
resource "google_privateca_certificate" "swp_cert" {
  depends_on            = [time_sleep.wait_for_ca]
  pool                  = google_privateca_ca_pool.default.name
  location              = var.region
  certificate_authority = google_privateca_certificate_authority.root_ca.certificate_authority_id
  name                  = "openclaw-swp-cert-${var.environment}-${random_id.ca_suffix.hex}"
  pem_csr               = tls_cert_request.swp_csr.cert_request_pem
  lifetime              = "864000s" # 10 days (in production use auto-rotation)

  lifecycle {
    create_before_destroy = true
  }
}

# Map the issued certificate into Certificate Manager for the SWP
resource "google_certificate_manager_certificate" "swp_cert" {
  name        = "openclaw-swp-cert-${var.environment}-${random_id.ca_suffix.hex}"
  description = "Managed cert for SWP explicit proxy via Private CA"
  location    = var.region
  self_managed {
    pem_certificate = google_privateca_certificate.swp_cert.pem_certificate
    pem_private_key = tls_private_key.swp_key.private_key_pem
  }

  lifecycle {
    create_before_destroy = true
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

# SWP Rule: Block known malicious sources using Google Cloud Threat Intelligence
resource "google_network_security_gateway_security_policy_rule" "block_threat_intel_malicious" {
  name                    = "block-threat-intel-malicious"
  location                = var.region
  gateway_security_policy = google_network_security_gateway_security_policy.swp_policy.name
  enabled                 = true
  priority                = 200
  session_matcher         = "evaluateThreatIntelligence('iplist-known-malicious-ips')"
  basic_profile           = "DENY"
}

# SWP Rule: Block Crypto Miners
resource "google_network_security_gateway_security_policy_rule" "block_threat_intel_crypto" {
  name                    = "block-threat-intel-crypto"
  location                = var.region
  gateway_security_policy = google_network_security_gateway_security_policy.swp_policy.name
  enabled                 = true
  priority                = 201
  session_matcher         = "evaluateThreatIntelligence('iplist-crypto-miners')"
  basic_profile           = "DENY"
}

# SWP Rule: Block Anonymous Proxies & Tor
resource "google_network_security_gateway_security_policy_rule" "block_threat_intel_anon" {
  name                    = "block-threat-intel-anon"
  location                = var.region
  gateway_security_policy = google_network_security_gateway_security_policy.swp_policy.name
  enabled                 = true
  priority                = 202
  session_matcher         = "evaluateThreatIntelligence('iplist-anon-proxies') || evaluateThreatIntelligence('iplist-tor-exit-nodes')"
  basic_profile           = "DENY"
}

# SWP Rule: Default Allow for AI Web Surfing (We rely on gVisor and Model Armor for safety)
resource "google_network_security_gateway_security_policy_rule" "allow_all_web" {
  name                    = "allow-all-web"
  location                = var.region
  gateway_security_policy = google_network_security_gateway_security_policy.swp_policy.name
  enabled                 = true
  priority                = 9999
  session_matcher         = "true"
  basic_profile           = "ALLOW"
}

# The Secure Web Proxy Instance
resource "google_network_services_gateway" "swp" {
  name                                 = "openclaw-swp-${var.environment}"
  location                             = var.region
  type                                 = "SECURE_WEB_GATEWAY"
  ports                                = [443]
  network                              = google_compute_network.vpc.id
  subnetwork                           = google_compute_subnetwork.gke_subnet.id
  certificate_urls                     = [google_certificate_manager_certificate.swp_cert.id]
  gateway_security_policy              = google_network_security_gateway_security_policy.swp_policy.id
  delete_swg_autogen_router_on_destroy = true
}
