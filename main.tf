terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.coordinator.function_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "slack_lambda_logs" {
  name              = "/aws/lambda/${var.slack_lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# Lambda Function
resource "aws_lambda_function" "coordinator" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE         = aws_dynamodb_table.coordinator_state.name
      S3_BUCKET              = aws_s3_bucket.sas_ops_cache.id
      SNS_TOPIC_ARN          = aws_sns_topic.alerts.arn
      SECRETS_MANAGER_ARN    = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.secrets_manager_secret_name}"
      GCP_PUBSUB_SECRET_NAME = var.gcp_pubsub_secret_name
      GCP_PROJECT_ID         = var.gcp_project_id
      GCP_PUBSUB_TOPIC       = var.gcp_pubsub_topic_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = local.common_tags
}

resource "aws_lambda_function" "slack_poster" {
  filename         = data.archive_file.slack_lambda_zip.output_path
  function_name    = var.slack_lambda_function_name
  role             = aws_iam_role.slack_lambda_role.arn
  handler          = "slack_poster.lambda_handler"
  runtime          = var.lambda_runtime
  memory_size      = 128
  timeout          = 30
  description      = "Posts Daily Coordinator task updates to Slack"
  source_code_hash = data.archive_file.slack_lambda_zip.output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_SECRET_NAME = var.slack_webhook_secret_name
      SLACK_WEBHOOK_SECRET_KEY  = var.slack_webhook_secret_key
      SLACK_CHANNEL             = var.slack_channel
      SLACK_USERNAME            = var.slack_username
      SLACK_ICON_EMOJI          = var.slack_icon_emoji
      SLACK_MESSAGE_PREFIX      = ":information_source: Task updated"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.slack_lambda_basic_execution,
    aws_iam_role_policy.slack_lambda_secrets_policy,
    aws_cloudwatch_log_group.slack_lambda_logs
  ]

  tags = local.common_tags
}

# EventBridge Rule - Daily 8:00 AM PST
resource "aws_cloudwatch_event_rule" "daily_schedule" {
  name                = var.eventbridge_rule_name
  description         = "Trigger Daily Coordinator agent at 8:00 AM PST"
  schedule_expression = "cron(0 16 ? * MON-FRI *)" # 8 AM PST = 4 PM UTC (adjust for daylight savings as needed)

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_schedule.name
  target_id = "CoordinatorLambda"
  arn       = aws_lambda_function.coordinator.arn

  input = jsonencode({
    source = "eventbridge"
    action = "daily_coordination"
  })
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.coordinator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_schedule.arn
}

resource "aws_lambda_permission" "allow_sns_to_invoke_slack" {
  statement_id  = "AllowSNSToInvokeSlackPoster"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_poster.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

# DynamoDB Table - CoordinatorState
resource "aws_dynamodb_table" "coordinator_state" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST" # On-demand pricing
  hash_key       = "coordinator_id"
  range_key      = "timestamp"

  attribute {
    name = "coordinator_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  attribute {
    name = "status"
    type = "S"
  }

  # GSI for querying by status
  global_secondary_index {
    name            = "status-timestamp-index"
    hash_key        = "status"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = local.common_tags
}

# S3 Bucket - sas-ops-cache
resource "aws_s3_bucket" "sas_ops_cache" {
  bucket = var.s3_bucket_name

  tags = local.common_tags
}

# S3 Versioning
resource "aws_s3_bucket_versioning" "sas_ops_cache_versioning" {
  bucket = aws_s3_bucket.sas_ops_cache.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "sas_ops_cache_encryption" {
  bucket = aws_s3_bucket.sas_ops_cache.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Block Public Access
resource "aws_s3_bucket_public_access_block" "sas_ops_cache_public_access" {
  bucket = aws_s3_bucket.sas_ops_cache.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = var.sns_topic_name

  tags = local.common_tags
}

# SNS Topic Policy (allow Lambda to publish)
resource "aws_sns_topic_policy" "alerts_policy" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "alerts_to_slack" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_poster.arn

  depends_on = [aws_lambda_permission.allow_sns_to_invoke_slack]
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/lambda_function.zip"
}

data "archive_file" "slack_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/slack_poster.py"
  output_path = "${path.module}/slack_lambda_function.zip"
}

# Local variables
locals {
  common_tags = {
    Project     = "DailyCoordinator"
    Environment = var.environment
    ManagedBy   = "Terraform"
    CreatedAt   = timestamp()
  }
}
