# ------------------------------------------------------------------------
# Enterprise Terraform State Storage
# ------------------------------------------------------------------------
# IMPORTANT: This file should ideally be applied in a separate, isolated 
# workspace before initializing the main project. 
# It creates the secure GCS bucket defined in `backend.tf`.

resource "google_storage_bucket" "terraform_state" {
  name          = "openclaw-tfstate-${var.project_id}-${var.environment}"
  location      = "US" # Multi-region for high availability
  force_destroy = false

  # Security Defaults
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Keep a history of state files to easily rollback infrastructure errors
  versioning {
    enabled = true
  }

  # Ensure the bucket is encrypted 
  # Note: For strict enterprise, replace with Customer Managed Encryption Key (CMEK)
  encryption {
    default_kms_key_name = "" # Empty implies Google-managed encryption keys
  }
}
