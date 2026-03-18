# NOTE: The GCS bucket must be created before initializing Terraform.
# You can create it using: gsutil mb -p <your-project-id> -l us-central1 gs://<your-project-id>-tfstate
# Then, replace the bucket name below and run `terraform init`.

terraform {
  backend "gcs" {
    bucket = "claw-platform-01-tfstate"
    prefix = "terraform/openclaw/state"
  }
}
