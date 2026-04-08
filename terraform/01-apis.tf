locals {
  services = [
    "cloudresourcemanager.googleapis.com", # Cloud Resource Manager API (Required by Terraform)
    "serviceusage.googleapis.com",         # Service Usage API (Required by Terraform)
  ]

  app_services = [
    "compute.googleapis.com",              # Compute Engine (VPC, Bastion, LBs)
    "container.googleapis.com",            # Google Kubernetes Engine
    "aiplatform.googleapis.com",           # Vertex AI (Gemini)
    "iap.googleapis.com",                  # Identity-Aware Proxy
    "networksecurity.googleapis.com",      # Network Security (SWP)
    "networkservices.googleapis.com",      # Network Services (SWP)
    "certificatemanager.googleapis.com",   # Certificate Manager (if SWP TLS inspection is used)
    "privateca.googleapis.com",            # Google Private CA Service
    "dns.googleapis.com",                  # Cloud DNS (Required for PGA)
    "dlp.googleapis.com",                  # Sensitive Data Protection (SDP)
    "modelarmor.googleapis.com",           # Model Armor
    "secretmanager.googleapis.com",        # Secret Manager
    "logging.googleapis.com",              # Cloud Logging (Required for SWP Audit Logs)
    "artifactregistry.googleapis.com"      # Artifact Registry (For custom Docker images)
  ]
}

resource "google_project_service" "core_apis" {
  for_each           = toset(local.services)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service" "enabled_apis" {
  for_each           = toset(local.app_services)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
  
  # Ensure core APIs (ResourceManager & ServiceUsage) are enabled BEFORE trying to enable the rest.
  # This prevents 403 accessNotConfigured errors during parallel API activation.
  depends_on = [google_project_service.core_apis]
}
