variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "us-west-2"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "lambda_function_name" {
  type        = string
  description = "Name of the Lambda function"
  default     = "daily-coordinator-agent"
}

variable "lambda_runtime" {
  type        = string
  description = "Lambda runtime environment"
  default     = "python3.11"

  validation {
    condition     = var.lambda_runtime == "python3.11"
    error_message = "Lambda runtime must be python3.11."
  }
}

variable "lambda_memory_size" {
  type        = number
  description = "Lambda memory allocation in MB"
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  type        = number
  description = "Lambda timeout in seconds"
  default     = 300
}

variable "eventbridge_rule_name" {
  type        = string
  description = "Name of the EventBridge rule"
  default     = "daily-coordinator-schedule"
}

variable "dynamodb_table_name" {
  type        = string
  description = "Name of the DynamoDB table for coordinator state"
  default     = "CoordinatorState"

  validation {
    condition     = length(var.dynamodb_table_name) >= 3 && length(var.dynamodb_table_name) <= 255
    error_message = "DynamoDB table name must be between 3 and 255 characters."
  }
}

variable "s3_bucket_name" {
  type        = string
  description = "Name of the S3 bucket for caching"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.s3_bucket_name))
    error_message = "S3 bucket name must start with lowercase letter or number, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "sns_topic_name" {
  type        = string
  description = "Name of the SNS topic for alerts"
  default     = "daily-coordinator-alerts"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch value."
  }
}

variable "secrets_manager_secret_name" {
  type        = string
  description = "Name of the Secrets Manager secret for credentials"
  default     = "daily-coordinator-secrets"
}

variable "slack_lambda_function_name" {
  type        = string
  description = "Name of the Slack poster Lambda function"
  default     = "daily-coordinator-slack-poster"
}

variable "slack_webhook_secret_name" {
  type        = string
  description = "Secrets Manager secret that stores the Slack webhook payload or URL"
  default     = "daily-coordinator-slack-webhook"
}

variable "slack_webhook_secret_key" {
  type        = string
  description = "Key inside the Slack webhook secret JSON payload that stores the webhook URL"
  default     = "slack_webhook_url"
}

variable "slack_channel" {
  type        = string
  description = "Optional Slack channel override for the webhook"
  default     = ""
}

variable "slack_username" {
  type        = string
  description = "Display name for the Slack bot"
  default     = "DailyCoordinatorBot"
}

variable "slack_icon_emoji" {
  type        = string
  description = "Emoji icon for the Slack bot"
  default     = ":spiral_calendar_pad:"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID for Pub/Sub resources"
}

variable "gcp_region" {
  type        = string
  description = "GCP region for Pub/Sub resources"
  default     = "us-central1"
}

variable "gcp_pubsub_topic_name" {
  type        = string
  description = "Name of the GCP Pub/Sub topic"
  default     = "daily-coordinator-events"
}

variable "gcp_pubsub_subscription_name" {
  type        = string
  description = "Name of the GCP Pub/Sub subscription"
  default     = "coordinator-processing-sub"
}

variable "gcp_pubsub_secret_name" {
  type        = string
  description = "AWS Secrets Manager secret name for GCP service account key"
  default     = "daily-coordinator-gcp-pubsub-key"
}

variable "gcp_firestore_region" {
  type        = string
  description = "GCP region for Firestore database"
  default     = "africa-south1"
}

variable "whatsapp_lambda_function_name" {
  type        = string
  description = "Name of the WhatsApp sender Lambda function"
  default     = "daily-coordinator-whatsapp-sender"
}

variable "twilio_secret_name" {
  type        = string
  description = "AWS Secrets Manager secret name for Twilio credentials"
  default     = "daily-coordinator-twilio-creds"
}

variable "whatsapp_from_number" {
  type        = string
  description = "Twilio WhatsApp-enabled phone number (format: whatsapp:+1234567890)"
  default     = "whatsapp:+14155238886"
}

variable "whatsapp_to_numbers" {
  type        = string
  description = "Comma-separated list of recipient WhatsApp numbers"
  default     = ""
}

variable "enable_point_in_time_recovery" {
  type        = bool
  description = "Enable DynamoDB point-in-time recovery"
  default     = true
}

variable "s3_enable_versioning" {
  type        = bool
  description = "Enable S3 versioning"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources"
  default     = {}
}
