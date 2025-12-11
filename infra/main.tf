variable "project_id" {
  description = "The Google Cloud Project ID"
  type        = string
  default = "festive-folio-470401-t1"
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

provider "google" {
  project = var.project_id
  region  = var.region
  
}

#Enable Required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com" # Needed for Terraform to check permissions
  ])
  service            = each.key
  disable_on_destroy = false
}

#Artifact Registry Repository
resource "google_artifact_registry_repository" "fastapi_repo" {
  location      = var.region
  repository_id = "fastapi-api-repo"
  description   = "Docker repository for FastAPI"
  format        = "DOCKER"
  
  # Ensure APIs are enabled before creating this
  depends_on = [google_project_service.apis]
}

# Service Accounts
# The identity the FastAPi App uses (Least Privilege: No roles by default)
resource "google_service_account" "fastapi_runtime" {
  account_id   = "fastapi-runtime"
  display_name = "Service Account for FastApi Runtime"
}

# The identity Cloud Build uses to deploy
resource "google_service_account" "cloudrun_deployer" {
  account_id   = "cloudrun-deployer"
  display_name = "Service Account for Cloud Run Deployments"
}

# IAM Hardening (The Security Handshake)

# Allow Deployer to be a "Cloud Run Developer" on the Project
resource "google_project_iam_member" "deployer_run_role" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.cloudrun_deployer.email}"
}

# Allow Deployer to write to the Artifact Registry
resource "google_artifact_registry_repository_iam_member" "deployer_artifact_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.fastapi_repo.location
  repository = google_artifact_registry_repository.fastapi_repo.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.cloudrun_deployer.email}"
}

# Allow Deployer to 'act as' the Runtime SA (Strict Scoping)
# This prevents the deployer from using any other Admin Service Accounts
resource "google_service_account_iam_member" "deployer_impersonation" {
  service_account_id = google_service_account.fastapi_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cloudrun_deployer.email}"
}

# Allow Deployer to access Cloud Build staging bucket (necessary for gcloud builds submit)
resource "google_project_iam_member" "deployer_storage_role" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.cloudrun_deployer.email}"
}

#Cloud Run Service (The Shell)
resource "google_cloud_run_v2_service" "default" {
  name     = "fastapi-service"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL" # Public ingress

  template {
    service_account = google_service_account.fastapi_runtime.email
    
    containers {
      # We start with a placeholder. Cloud Build will overwrite this later.
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }

  # CRITICAL: Ignore image changes so Terraform doesn't fight with Cloud Build
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version
    ]
  }
}

# Public Access (IAM)
# This makes the service publicly accessible on the internet
resource "google_cloud_run_service_iam_member" "public_access" {
  location = google_cloud_run_v2_service.default.location
  service  = google_cloud_run_v2_service.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Output the URL so we know where to click
output "service_url" {
  value = google_cloud_run_v2_service.default.uri
}