# Generate a unique gateway token for THIS instance
resource "random_password" "gateway_token" {
  length  = 32
  special = false
}

# Create a dedicated Google Secret Manager secret for THIS instance
resource "google_secret_manager_secret" "gateway_token_secret" {
  secret_id = "openclaw-gateway-token-${var.environment}-${var.instance_name}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "gateway_token_version" {
  secret      = google_secret_manager_secret.gateway_token_secret.id
  secret_data = random_password.gateway_token.result
}

# Grant the OpenClaw Workload Identity SA permission to read THIS instance's secret
resource "google_secret_manager_secret_iam_binding" "gateway_token_accessor" {
  secret_id = google_secret_manager_secret.gateway_token_secret.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [
    "serviceAccount:${var.openclaw_sa_email}"
  ]
}

# SecretProviderClass tailored for THIS instance
resource "kubectl_manifest" "secret_provider_class" {
  yaml_body = yamlencode({
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "openclaw-gsm-secrets-${var.instance_name}"
      namespace = var.namespace
    }
    spec = {
      provider = "gke"
      parameters = {
        secrets = yamlencode([
          {
            resourceName = google_secret_manager_secret_version.gateway_token_version.name
            fileName     = "gateway_token"
          }
        ])
      }
      secretObjects = [
        {
          secretName = "openclaw-gateway-secret-${var.instance_name}"
          type       = "Opaque"
          data = [
            {
              objectName = "gateway_token"
              key        = "OPENCLAW_GATEWAY_TOKEN"
            }
          ]
        }
      ]
    }
  })
}
