# GCP Provider Configuration
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Enable required GCP APIs
resource "google_project_service" "pubsub" {
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "firestore" {
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "firebase" {
  service            = "firebase.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudfunctions" {
  service            = "cloudfunctions.googleapis.com"
  disable_on_destroy = false
}

# Firestore Database
resource "google_firestore_database" "coordinator" {
  name        = "(default)"
  location_id = var.gcp_firestore_region
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.firestore]
}

# GCP Service Account for Pub/Sub Publishing
resource "google_service_account" "pubsub_publisher" {
  account_id   = "daily-coordinator-pubsub"
  display_name = "Daily Coordinator Pub/Sub Publisher"
  description  = "Service account for AWS Lambda to publish to GCP Pub/Sub"
}

# GCP Service Account Key (for Lambda authentication)
resource "google_service_account_key" "pubsub_publisher_key" {
  service_account_id = google_service_account.pubsub_publisher.name
}

# Store GCP service account key in AWS Secrets Manager
resource "aws_secretsmanager_secret" "gcp_pubsub_key" {
  name        = var.gcp_pubsub_secret_name
  description = "GCP service account key for Pub/Sub publishing from Lambda"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "gcp_pubsub_key" {
  secret_id     = aws_secretsmanager_secret.gcp_pubsub_key.id
  secret_string = base64decode(google_service_account_key.pubsub_publisher_key.private_key)
}

# GCP Pub/Sub Topic
resource "google_pubsub_topic" "coordinator_events" {
  name = var.gcp_pubsub_topic_name

  labels = {
    environment = var.environment
    managed_by  = "terraform"
    project     = "daily-coordinator"
  }

  message_retention_duration = "86400s" # 24 hours

  depends_on = [google_project_service.pubsub]
}

# GCP Pub/Sub Subscription (Pull-based)
resource "google_pubsub_subscription" "coordinator_processing" {
  name  = var.gcp_pubsub_subscription_name
  topic = google_pubsub_topic.coordinator_events.id

  # Message retention for 7 days
  message_retention_duration = "604800s"

  # Acknowledge deadline (how long subscriber has to ack message)
  ack_deadline_seconds = 20

  # Retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Expiration policy (subscription expires if inactive for 31 days)
  expiration_policy {
    ttl = "2678400s" # 31 days
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
    project     = "daily-coordinator"
  }

  depends_on = [google_pubsub_topic.coordinator_events]
}

# IAM binding for service account to publish to topic
resource "google_pubsub_topic_iam_member" "publisher" {
  topic  = google_pubsub_topic.coordinator_events.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.pubsub_publisher.email}"

  depends_on = [google_pubsub_topic.coordinator_events]
}

# IAM binding for service account to subscribe (for testing/monitoring)
resource "google_pubsub_subscription_iam_member" "subscriber" {
  subscription = google_pubsub_subscription.coordinator_processing.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.pubsub_publisher.email}"

  depends_on = [google_pubsub_subscription.coordinator_processing]
}

# Outputs for GCP resources
output "gcp_pubsub_topic_name" {
  description = "Name of the GCP Pub/Sub topic"
  value       = google_pubsub_topic.coordinator_events.name
}

output "gcp_pubsub_subscription_name" {
  description = "Name of the GCP Pub/Sub subscription"
  value       = google_pubsub_subscription.coordinator_processing.name
}

output "gcp_service_account_email" {
  description = "Email of the GCP service account"
  value       = google_service_account.pubsub_publisher.email
}

output "gcp_pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.coordinator_events.id
}
