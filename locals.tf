# Local configuration for shared values
locals {
  service_name = "daily-coordinator"
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Project     = "DailyCoordinator"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CreatedDate = timestamp()
      ServiceName = local.service_name
    },
    var.tags
  )

  # Resource naming conventions
  resource_prefix = "${local.service_name}-${var.environment}"

  # Lambda configuration
  lambda_config = {
    name            = var.lambda_function_name
    runtime         = var.lambda_runtime
    memory_size     = var.lambda_memory_size
    timeout_seconds = var.lambda_timeout
  }

  # DynamoDB configuration
  dynamodb_config = {
    table_name              = var.dynamodb_table_name
    billing_mode            = "PAY_PER_REQUEST"
    point_in_time_recovery  = var.enable_point_in_time_recovery
    encryption_enabled      = true
    stream_view_type        = "NEW_AND_OLD_IMAGES"
  }

  # S3 configuration
  s3_config = {
    bucket_name       = var.s3_bucket_name
    versioning        = var.s3_enable_versioning
    encryption        = "AES256"
    public_access     = false
  }

  # EventBridge schedule (8 AM PST = 4 PM UTC, weekdays only)
  # For daily (all days): cron(0 16 * * ? *)
  # For weekdays: cron(0 16 ? * MON-FRI *)
  # Adjust based on DST requirements
  eventbridge_schedule = "cron(0 16 ? * MON-FRI *)"
}
