# Daily Coordinator Agent - AWS Terraform Configuration

Complete AWS infrastructure setup for a Daily Coordinator agent using Terraform.

## Architecture Overview

```
EventBridge (Daily 8 AM PST)
    ↓
Lambda Function (Python 3.11, 256MB)
    ├→ DynamoDB (CoordinatorState)
    ├→ S3 (sas-ops-cache, versioned, encrypted)
    ├→ Secrets Manager (credentials + GCP key)
    ├→ SNS Topic (alerts)
    │      ↓
    │   Slack Poster Lambda → Slack Webhook
    └→ GCP Pub/Sub Topic → Subscription
    
CloudWatch Logs → Log Group (/aws/lambda/...)
```## Project Structure

```
.
├── main.tf                    # Core AWS resources
├── variables.tf               # Variable definitions with validation
├── iam.tf                     # IAM role and policies (least privilege)
├── outputs.tf                 # Output values
├── lambda/
│   ├── index.py              # Lambda function code
│   ├── slack_poster.py       # Slack poster Lambda code
│   └── gcp_pubsub.py         # GCP Pub/Sub publisher module
├── terraform.tfvars.example   # Variable values template
└── README.md                  # This file
```

## Features

✅ **Lambda Function**
- Python 3.11 runtime
- 256MB memory (configurable)
- CloudWatch Logs integration
- Environment variables for AWS resources

✅ **EventBridge Scheduling**
- Daily trigger at 8:00 AM PST (16:00 UTC)
- Configurable cron expression
- Automatic JSON payload

✅ **DynamoDB Table**
- On-demand billing (pay-per-request)
- Point-in-time recovery enabled
- Server-side encryption
- Global secondary index for status queries
- Stream ARN for event processing

✅ **S3 Bucket**
- Versioning enabled
- Server-side encryption (AES256)
- Public access blocked
- Lifecycle policy ready

✅ **IAM Security (Least Privilege)**
- Role-based access control
- Granular permissions by service
- Resource-scoped policies
- Secrets Manager access with conditions
- KMS key access for encryption

✅ **CloudWatch**
- Dedicated log group
- Configurable retention (default: 14 days)
- Automatic log streaming from Lambda

✅ **SNS Alerts**
- Topic for alert notifications
- Lambda publish permissions
- Custom alert messages

✅ **Slack Poster Lambda**
- Dedicated Lambda subscribes to the SNS alerts topic
- Fetches Slack webhook from Secrets Manager
- Posts "Task updated" summaries to the configured Slack channel

✅ **GCP Pub/Sub Integration**
- Cross-cloud messaging for hybrid AWS/GCP workflows
- Service account authentication via Secrets Manager
- Topic + subscription with 7-day retention
- IAM least-privilege publisher/subscriber roles
- Optional Lambda decorator for automatic event publishing

## Prerequisites

1. **Terraform** >= 1.0
2. **AWS CLI** configured with appropriate credentials
3. **AWS Account** with sufficient permissions
4. **Python 3.11** (for local testing)

## Installation & Deployment

### Step 1: Initialize the Project

```bash
# Clone or navigate to the project directory
cd daily-coordinator-agent

# Initialize Terraform
terraform init
```

### Step 2: Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
# IMPORTANT: Update s3_bucket_name to a globally unique name
```

### Step 3: Create Secrets in AWS Secrets Manager

```bash
# Create the secrets that Lambda will access
aws secretsmanager create-secret \
  --name daily-coordinator-secrets \
  --secret-string '{"api_key":"your-api-key","auth_token":"your-token"}' \
  --region us-west-2

# Slack webhook secret (stores the incoming webhook URL)
aws secretsmanager create-secret \
  --name daily-coordinator-slack-webhook \
  --secret-string '{"slack_webhook_url":"https://hooks.slack.com/services/XXX/YYY/ZZZ"}' \
  --region us-west-2

# Note: GCP service account key is auto-created and stored by Terraform
# in daily-coordinator-gcp-pubsub-key secret
```### Step 4: Plan the Deployment

```bash
terraform plan -out=tfplan
```

### Step 5: Apply the Configuration

```bash
terraform apply tfplan
```

### Step 6: Verify Deployment

```bash
# Get Lambda function details
terraform output lambda_function_name

# Check DynamoDB table
aws dynamodb describe-table \
  --table-name $(terraform output -raw dynamodb_table_name) \
  --region $(terraform output -raw aws_region)

# View CloudWatch logs
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

## Configuration Details

### Lambda Schedule (EventBridge)

The EventBridge rule triggers the Lambda function daily at **8:00 AM PST**.

- **Current cron**: `cron(0 16 ? * MON-FRI *)` (4 PM UTC, weekdays)
- To adjust for daylight savings or different times, modify the `schedule_expression` in `main.tf`

Example cron expressions:
- `cron(0 16 * * ? *)` - Every day at 4 PM UTC
- `cron(0 8 * * ? *)` - Every day at 8 AM UTC
- `cron(0 16 ? * MON-FRI *)` - Weekdays only at 4 PM UTC

### Lambda Function Environment

The Lambda function receives these environment variables:

```python
DYNAMODB_TABLE      # DynamoDB table name
S3_BUCKET          # S3 bucket name
SNS_TOPIC_ARN      # SNS topic ARN
SECRETS_MANAGER_ARN # Secrets Manager secret ARN
```

### Slack Poster Lambda

- Subscribed to the SNS alerts topic so every coordinator alert is mirrored to Slack.
- Secret `slack_webhook_url` is retrieved from `var.slack_webhook_secret_name` using Secrets Manager.
- Environment variables:

```python
SLACK_WEBHOOK_SECRET_NAME  # Secrets Manager secret name
SLACK_WEBHOOK_SECRET_KEY   # JSON key that stores the webhook URL
SLACK_CHANNEL              # Optional channel override (e.g., #daily-coordinator)
SLACK_USERNAME             # Display name for the bot
SLACK_ICON_EMOJI           # Emoji used as the bot icon
SLACK_MESSAGE_PREFIX       # Defaults to ":information_source: Task updated"
```

**Event flow**
1. `aws_lambda_function.coordinator` publishes an alert to SNS.
2. The SNS topic invokes the Slack poster Lambda.
3. The Slack Lambda formats a "Task updated" message and calls the Slack webhook.

### DynamoDB Schema

**Table**: `CoordinatorState`

**Primary Key**:
- Partition Key: `coordinator_id` (String)
- Sort Key: `timestamp` (Number)

**Attributes**:
- `status` (String) - Current state (pending/running/completed/failed)
- `data` (String) - JSON-encoded state data
- `updated_at` (String) - ISO timestamp of last update

**Global Secondary Index**:
- `status-timestamp-index` - Query by status

**Features**:
- Point-in-time recovery: Enabled
- Encryption: Server-side (AWS managed)
- Billing: On-demand

### S3 Bucket Configuration

**Bucket**: `sas-ops-cache-*`

**Features**:
- Versioning: Enabled
- Encryption: AES256 (server-side)
- Public Access: Blocked
- Lifecycle: Ready for configuration

**Expected Structure**:
```
s3://bucket-name/
├── cache/
│   └── coordinator-id/
│       └── YYYY-MM-DD.json
└── logs/
    └── ...
```

### IAM Policies

All policies follow the **principle of least privilege**:

1. **Lambda Basic Execution** (AWS Managed)
   - CloudWatch Logs write access

2. **S3 Policy** (Custom)
   - `s3:GetObject` - Read cache data
   - `s3:PutObject` - Upload cache data
   - `s3:ListBucket` - List objects

3. **DynamoDB Policy** (Custom)
   - `dynamodb:GetItem` - Read state
   - `dynamodb:PutItem` - Write state
   - `dynamodb:UpdateItem` - Update state
   - `dynamodb:Query` - Query by attributes

4. **Secrets Manager Policy** (Custom)
   - `secretsmanager:GetSecretValue` - Read secrets
   - Restricted to specific secret ARN

5. **SNS Policy** (Custom)
   - `sns:Publish` - Send alerts

6. **KMS Policy** (Custom)
   - `kms:Decrypt` - Decrypt encrypted data
   - Scoped to DynamoDB and Secrets Manager services

## Lambda Function Usage

### Basic Example

```python
import json
from index import coordinate_daily_tasks

# Execute coordination
results = coordinate_daily_tasks()
print(json.dumps(results, indent=2))
```

### Expected Output

```json
{
  "coordinator_id": "daily-coordinator-001",
  "timestamp": "2025-11-13T15:30:00.000000",
  "status": "success",
  "tasks_processed": 2,
  "errors": []
}
```

### Alert Notifications

The Lambda function publishes alerts to SNS on completion:

- **Success**: "Daily Coordinator - Success"
- **Partial Success**: "Daily Coordinator - Partial Success"
- **Failure**: "Daily Coordinator - Failed"

Subscribe to the SNS topic to receive notifications:

```bash
aws sns subscribe \
  --topic-arn $(terraform output -raw sns_topic_arn) \
  --protocol email \
  --notification-endpoint your-email@example.com
```

## Customization

### Modify Lambda Function

Edit `lambda/index.py` and reapply:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### Change Trigger Schedule

Update `schedule_expression` in `main.tf`:

```hcl
schedule_expression = "cron(0 18 * * ? *)"  # Change to 6 PM UTC
```

### Increase Lambda Memory

Update `lambda_memory_size` in `terraform.tfvars`:

```hcl
lambda_memory_size = 512  # Increase to 512MB
```

### Adjust DynamoDB Pricing

Change `billing_mode` in `main.tf` if predictable workload:

```hcl
billing_mode   = "PROVISIONED"
read_capacity_units  = 5
write_capacity_units = 5
```

## Monitoring & Logs

### CloudWatch Logs

```bash
# Tail logs in real-time
aws logs tail /aws/lambda/daily-coordinator-agent --follow

# Get last 50 log lines
aws logs tail /aws/lambda/daily-coordinator-agent --max-items 50
```

### DynamoDB Metrics

```bash
# Monitor consumed capacity
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedWriteCapacityUnits \
  --dimensions Name=TableName,Value=CoordinatorState \
  --start-time 2025-11-12T00:00:00Z \
  --end-time 2025-11-13T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

### Manual Lambda Invocation

```bash
aws lambda invoke \
  --function-name daily-coordinator-agent \
  --payload '{"source":"manual","action":"test"}' \
  response.json

cat response.json
```

## Cost Estimation

**Monthly costs (approximate, us-west-2)**:

| Service | Usage | Monthly Cost |
|---------|-------|--------------|
| Lambda | 30 invocations × 1 sec | $0.20 |
| DynamoDB (on-demand) | ~1 KB/day read+write | $1.00 |
| S3 | ~1 GB storage + requests | $0.50 |
| CloudWatch Logs | ~5 GB/month | $2.50 |
| SNS | 30 messages/month | $0.06 |
| **Total** | | **~$4.26** |

## Cleanup

To remove all resources:

```bash
terraform destroy
```

⚠️ **Warning**: S3 bucket versioning and DynamoDB backups may incur additional costs even after deletion.

## Troubleshooting

### Lambda Function Not Triggering

1. Check EventBridge rule is enabled:
   ```bash
   aws events describe-rule \
     --name daily-coordinator-schedule \
     --region us-west-2
   ```

2. Verify Lambda has EventBridge permissions:
   ```bash
   aws lambda get-policy \
     --function-name daily-coordinator-agent \
     --region us-west-2
   ```

### DynamoDB Access Denied

1. Verify IAM role is attached:
   ```bash
   aws iam get-role-policy \
     --role-name daily-coordinator-agent-role \
     --policy-name daily-coordinator-agent-dynamodb-policy
   ```

2. Check table exists:
   ```bash
   aws dynamodb list-tables --region us-west-2
   ```

### S3 Permission Denied

1. Verify bucket policy and object ACL
2. Confirm KMS key permissions if using customer-managed keys
3. Check Lambda execution role has S3 permissions

### Secrets Not Found

1. Verify secret exists:
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id daily-coordinator-secrets
   ```

2. Confirm Lambda role has Secrets Manager permissions

## Security Best Practices

✅ Implemented in this configuration:

- [x] IAM least privilege policies
- [x] Resource-level encryption (S3, DynamoDB)
- [x] Secrets Manager for sensitive data
- [x] CloudWatch Logs with retention
- [x] VPC integration ready (add in networking)
- [x] Resource tagging for cost tracking
- [x] Public access blocking on S3
- [x] KMS key scoping for encryption

## Variables Reference

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `aws_region` | string | us-west-2 | AWS region |
| `environment` | string | dev | Environment (dev/staging/prod) |
| `lambda_function_name` | string | daily-coordinator-agent | Lambda function name |
| `lambda_runtime` | string | python3.11 | Lambda runtime |
| `lambda_memory_size` | number | 256 | Lambda memory in MB |
| `lambda_timeout` | number | 300 | Lambda timeout in seconds |
| `eventbridge_rule_name` | string | daily-coordinator-schedule | EventBridge rule name |
| `dynamodb_table_name` | string | CoordinatorState | DynamoDB table name |
| `s3_bucket_name` | string | - | S3 bucket name (must be unique) |
| `sns_topic_name` | string | daily-coordinator-alerts | SNS topic name |
| `log_retention_days` | number | 14 | CloudWatch log retention |

## Outputs Reference

```bash
# Get all outputs
terraform output

# Get specific output
terraform output lambda_function_arn
terraform output dynamodb_table_name
terraform output s3_bucket_arn
```

## Support & Contributing

For issues or contributions, please:

1. Check existing documentation
2. Review AWS service limits
3. Verify IAM permissions
4. Check CloudWatch logs for errors

## License

This Terraform configuration is provided as-is for AWS infrastructure deployment.

---

**Last Updated**: November 13, 2025
**Terraform Version**: >= 1.0
**AWS Provider Version**: >= 5.0
