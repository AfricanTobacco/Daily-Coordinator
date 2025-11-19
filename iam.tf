# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_role" {
  name               = "${var.lambda_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

# Lambda Assume Role Policy
data "aws_iam_policy_document" "lambda_assume_role" {
  version = "2012-10-17"

  statement {
    sid     = "AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Attach AWS managed policy for basic Lambda execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for S3 access (least privilege)
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name   = "${var.lambda_function_name}-s3-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_s3_policy.json
}

data "aws_iam_policy_document" "lambda_s3_policy" {
  version = "2012-10-17"

  statement {
    sid       = "S3BucketRead"
    effect    = "Allow"
    actions   = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetObjectVersion"
    ]
    resources = [
      aws_s3_bucket.sas_ops_cache.arn,
      "${aws_s3_bucket.sas_ops_cache.arn}/*"
    ]
  }

  statement {
    sid       = "S3BucketWrite"
    effect    = "Allow"
    actions   = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = ["${aws_s3_bucket.sas_ops_cache.arn}/*"]
  }

  statement {
    sid       = "S3BucketDelete"
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["${aws_s3_bucket.sas_ops_cache.arn}/*"]
  }
}

# Custom policy for DynamoDB access (least privilege)
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name   = "${var.lambda_function_name}-dynamodb-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_dynamodb_policy.json
}

data "aws_iam_policy_document" "lambda_dynamodb_policy" {
  version = "2012-10-17"

  statement {
    sid    = "DynamoDBRead"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem"
    ]
    resources = [
      aws_dynamodb_table.coordinator_state.arn,
      "${aws_dynamodb_table.coordinator_state.arn}/index/*"
    ]
  }

  statement {
    sid    = "DynamoDBWrite"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:BatchWriteItem"
    ]
    resources = [
      aws_dynamodb_table.coordinator_state.arn,
      "${aws_dynamodb_table.coordinator_state.arn}/index/*"
    ]
  }
}

# Custom policy for Secrets Manager access (least privilege)
resource "aws_iam_role_policy" "lambda_secrets_policy" {
  name   = "${var.lambda_function_name}-secrets-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_secrets_policy.json
}

data "aws_iam_policy_document" "lambda_secrets_policy" {
  version = "2012-10-17"

  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.secrets_manager_secret_name}*"
    ]
  }
}

# Custom policy for SNS publishing (least privilege)
resource "aws_iam_role_policy" "lambda_sns_policy" {
  name   = "${var.lambda_function_name}-sns-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_sns_policy.json
}

data "aws_iam_policy_document" "lambda_sns_policy" {
  version = "2012-10-17"

  statement {
    sid    = "SNSPublish"
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [
      aws_sns_topic.alerts.arn
    ]
  }
}

# Custom policy for KMS (if using customer-managed keys)
resource "aws_iam_role_policy" "lambda_kms_policy" {
  name   = "${var.lambda_function_name}-kms-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_kms_policy.json
}

data "aws_iam_policy_document" "lambda_kms_policy" {
  version = "2012-10-17"

  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "dynamodb.${var.aws_region}.amazonaws.com",
        "secretsmanager.${var.aws_region}.amazonaws.com"
      ]
    }
  }
}
