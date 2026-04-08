# Create a dedicated Google Service Account (GSA) for the OpenClaw application
resource "google_service_account" "openclaw_sa" {
  account_id   = "openclaw-app-sa-${var.environment}"
  display_name = "OpenClaw Application Service Account"
  description  = "Service Account used by OpenClaw pods via Workload Identity"
  depends_on   = [google_project_service.enabled_apis]
}

# Grant the OpenClaw SA permission to use Vertex AI
resource "google_project_iam_member" "openclaw_vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.openclaw_sa.email}"
}

# The Kubernetes namespace where OpenClaw will be deployed
# We need to define this here so we can create the KSA and bind it to the GSA
resource "kubernetes_namespace" "openclaw_namespace" {
  metadata {
    name = "openclaw-system"
  }
  depends_on = [google_container_cluster.openclaw_cluster]
}

# Create a Kubernetes Service Account (KSA) for the application
resource "kubernetes_service_account" "openclaw_ksa" {
  metadata {
    name      = "openclaw-app-ksa"
    namespace = kubernetes_namespace.openclaw_namespace.metadata[0].name
    annotations = {
      # This annotation tells GKE which Google Service Account this KSA represents
      "iam.gke.io/gcp-service-account" = google_service_account.openclaw_sa.email
    }
  }
}

# Bind the Google Service Account (GSA) to the Kubernetes Service Account (KSA)
# This is the core of Workload Identity configuration
resource "google_service_account_iam_binding" "openclaw_workload_identity" {
  service_account_id = google_service_account.openclaw_sa.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace.openclaw_namespace.metadata[0].name}/${kubernetes_service_account.openclaw_ksa.metadata[0].name}]"
  ]
}

# Model Armor / Sensitive Data Protection Configuration

# 1. Create a Sensitive Data Protection (DLP) Inspection Template
# This defines what Model Armor should look for (e.g., Credit Card Numbers, Social Security Numbers)
resource "google_data_loss_prevention_inspect_template" "openclaw_sdp_template" {
  parent       = "projects/${var.project_id}/locations/global"
  display_name = "OpenClaw Sensitive Data Protection Template"
  description  = "DLP Inspection Template for Model Armor to scan prompts and responses"

  depends_on = [google_project_service.enabled_apis]

  inspect_config {
    # Specify the types of sensitive information to detect
    info_types {
      name = "CREDIT_CARD_NUMBER"
    }
    info_types {
      name = "US_SOCIAL_SECURITY_NUMBER"
    }
    info_types {
      name = "EMAIL_ADDRESS"
    }

    # Minimum likelihood to trigger a finding
    min_likelihood = "LIKELY"

    # Optional: Set limits on the number of findings
    limits {
      max_findings_per_request = 10
      max_findings_per_item    = 10
    }

    # Optional: Exclude certain words or phrases (e.g., test data)
    rule_set {
      info_types {
        name = "EMAIL_ADDRESS"
      }
      rules {
        exclusion_rule {
          dictionary {
            word_list {
              words = ["test@example.com", "dummy@domain.com"]
            }
          }
          matching_type = "MATCHING_TYPE_FULL_MATCH"
        }
      }
    }
  }
}

# 2. Set Model Armor Floor Settings
# This establishes the baseline security policy across the project, including Vertex AI.
# We configure it to use the SDP template we just created and enable Prompt Injection/Jailbreak detection.
# We use the REST API via a null_resource because there is no native google_model_armor_floor_setting resource yet.

resource "null_resource" "model_armor_floor_setting" {
  depends_on = [google_data_loss_prevention_inspect_template.openclaw_sdp_template]

  triggers = {
    project_id   = var.project_id
    sdp_template = google_data_loss_prevention_inspect_template.openclaw_sdp_template.id
  }

  provisioner "local-exec" {
    command = <<EOF
      # Get an access token
      TOKEN=$(gcloud auth print-access-token)
      
      # The API endpoint for Model Armor floor settings
      API_ENDPOINT="https://modelarmor.googleapis.com/v1/projects/${var.project_id}/locations/global/floorSetting"

      # Construct the JSON payload for the floor setting
      # We enable Prompt Injection, Malicious URI, and map our SDP inspection template
      PAYLOAD=$(cat <<JSON
      {
        "filterConfig": {
          "piAndJailbreakFilterSettings": {
            "filterEnforcement": "ENABLED"
          },
          "maliciousUriFilterSettings": {
            "filterEnforcement": "ENABLED"
          },
          "sdpSettings": {
            "advancedConfig": {
              "inspectTemplate": "${google_data_loss_prevention_inspect_template.openclaw_sdp_template.id}"
            }
          }
        },
        "enableFloorSettingEnforcement": true
      }
JSON
      )

      # Send the PATCH request to update the floor setting
      curl -s -X PATCH "$API_ENDPOINT" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD"
    EOF
  }
}
