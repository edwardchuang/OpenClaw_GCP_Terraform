# ------------------------------------------------------------------------------
# Google Artifact Registry (GAR) for Custom OpenClaw Images
# ------------------------------------------------------------------------------

resource "google_artifact_registry_repository" "openclaw_repo" {
  location      = var.region
  repository_id = "openclaw-repo-${var.environment}"
  description   = "Docker repository for custom OpenClaw agent images with pre-installed skills"
  format        = "DOCKER"

  depends_on = [google_project_service.enabled_apis]
}

# Grant the GKE default service account permission to pull images from Artifact Registry
# Note: GKE Autopilot nodes use the default compute service account unless explicitly changed.
data "google_compute_default_service_account" "default" {
  depends_on = [google_project_service.enabled_apis]
}

resource "google_artifact_registry_repository_iam_member" "gke_pull_access" {
  project    = var.project_id
  location   = google_artifact_registry_repository.openclaw_repo.location
  repository = google_artifact_registry_repository.openclaw_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}
