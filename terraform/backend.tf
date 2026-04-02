# NOTE: The GCS bucket must be created before initializing Terraform's remote backend.
# You can create it automatically by temporarily commenting out this block, running
# `terraform init`, and then `terraform apply -target=google_storage_bucket.terraform_state -var-file="terraform.tfvars"`.
# Alternatively, create it manually: gsutil mb -p <your-project-id> -l US gs://openclaw-tfstate-<your-project-id>-prod
# Once created, uncomment this block, replace YOUR_PROJECT_ID_HERE with your actual project ID, and run `terraform init` again.

terraform {
  backend "gcs" {
    bucket = "openclaw-tfstate-YOUR_PROJECT_ID_HERE-prod"
    prefix = "terraform/openclaw/state"
  }
}
