output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.coordinator.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.coordinator.function_name
}

output "slack_lambda_function_arn" {
  description = "ARN of the Slack poster Lambda function"
  value       = aws_lambda_function.slack_poster.arn
}

output "slack_lambda_function_name" {
  description = "Name of the Slack poster Lambda function"
  value       = aws_lambda_function.slack_poster.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.daily_schedule.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.daily_schedule.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.coordinator_state.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.coordinator_state.name
}

output "dynamodb_table_stream_arn" {
  description = "ARN of the DynamoDB table stream"
  value       = aws_dynamodb_table.coordinator_state.stream_arn
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.sas_ops_cache.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.sas_ops_cache.id
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.sas_ops_cache.region
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.name
}

output "aws_region" {
  description = "AWS region used"
  value       = var.aws_region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "all_resource_ids" {
  description = "Summary of all created resource IDs"
  value = {
    lambda_function_name      = aws_lambda_function.coordinator.function_name
    dynamodb_table_name       = aws_dynamodb_table.coordinator_state.name
    s3_bucket_name            = aws_s3_bucket.sas_ops_cache.id
    sns_topic_name            = aws_sns_topic.alerts.name
    eventbridge_rule_name     = aws_cloudwatch_event_rule.daily_schedule.name
    cloudwatch_log_group_name = aws_cloudwatch_log_group.lambda_logs.name
  }
}
