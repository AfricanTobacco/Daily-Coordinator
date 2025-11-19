# Daily Coordinator - Quick Start Guide

## Current Status ✅

- ✅ Terraform installed (v1.9.8)
- ✅ Terraform initialized with AWS + Google providers
- ✅ Configuration validated successfully
- ✅ 27 AWS resources ready to deploy
- ⚠️ GCP authentication needed (gcloud not installed)

## Deployment Plan Summary

Terraform is ready to create:
- **AWS Resources (27)**:
  - 2 Lambda functions (coordinator + Slack poster)
  - 1 DynamoDB table (CoordinatorState)
  - 1 S3 bucket (sas-ops-cache-daily-coordinator-001)
  - 1 SNS topic (daily-coordinator-alerts)
  - EventBridge schedule (8 AM PST weekdays)
  - CloudWatch log groups
  - IAM roles and policies
  - AWS Secrets Manager (for GCP service account key)

- **GCP Resources** (requires authentication):
  - Pub/Sub topic + subscription
  - Firestore database (africa-south1)
  - Service account with publisher/subscriber roles

---

## Option 1: Deploy AWS Only (Recommended for Quick Start)

If you want to deploy the AWS infrastructure immediately without GCP:

### Step 1: Temporarily Disable GCP Resources

```powershell
# Backup gcp.tf
Copy-Item gcp.tf gcp.tf.backup

# Rename to disable GCP resources
Rename-Item gcp.tf gcp.tf.disabled
```

### Step 2: Deploy AWS Infrastructure

```powershell
cd 'c:\Users\_oloyouth\Downloads\Dailty Coord Agent'
terraform plan -out=tfplan
terraform apply tfplan
```

**Duration**: 2-3 minutes  
**Cost**: ~$5-8/month (DynamoDB on-demand, Lambda free tier, S3 minimal)

### Step 3: Verify AWS Deployment

```powershell
# Check Lambda function
aws lambda get-function --function-name daily-coordinator-agent

# Check DynamoDB table
aws dynamodb describe-table --table-name CoordinatorState

# Check S3 bucket
aws s3 ls s3://sas-ops-cache-daily-coordinator-001

# Check EventBridge rule
aws events describe-rule --name daily-coordinator-schedule
```

### Step 4: Test Lambda Invocation

```powershell
# Manually invoke Lambda
aws lambda invoke --function-name daily-coordinator-agent --payload '{"test": true}' output.json
Get-Content output.json | ConvertFrom-Json | ConvertTo-Json -Depth 10

# Check CloudWatch Logs
aws logs tail /aws/lambda/daily-coordinator-agent --follow
```

### Step 5: Add Secrets (Slack Webhook)

```powershell
# Create Slack webhook secret (get webhook URL from Slack workspace settings)
$slackWebhookUrl = Read-Host "Enter your Slack webhook URL"
aws secretsmanager create-secret --name daily-coordinator-slack-webhook --description "Slack webhook for Daily Coordinator" --secret-string "{\"slack_webhook_url\": \"$slackWebhookUrl\"}"

# Test Slack Lambda
aws lambda invoke --function-name daily-coordinator-slack-poster --payload '{"message": "Test from Daily Coordinator"}' slack_output.json
Get-Content slack_output.json
```

---

## Option 2: Full AWS + GCP Deployment

If you want the complete multi-cloud setup with offline-first mobile capabilities:

### Step 1: Install Google Cloud SDK

```powershell
# Download and install gcloud CLI
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri "https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe" -OutFile "$env:TEMP\GoogleCloudSDKInstaller.exe"
Start-Process -FilePath "$env:TEMP\GoogleCloudSDKInstaller.exe" -Wait
```

After installation, restart PowerShell and verify:
```powershell
gcloud version
```

### Step 2: Authenticate with GCP

```powershell
# Login to Google Cloud
gcloud auth login

# Set up application default credentials
gcloud auth application-default login
```

### Step 3: Create GCP Project

```powershell
# Create new project (or use existing)
$gcpProjectId = "daily-coordinator-sadc"  # Change if needed
gcloud projects create $gcpProjectId --name="Daily Coordinator SADC"

# Set as active project
gcloud config set project $gcpProjectId

# Link billing account (required for API usage)
# Get billing account ID
gcloud billing accounts list

# Link billing (replace BILLING_ACCOUNT_ID)
gcloud billing projects link $gcpProjectId --billing-account=BILLING_ACCOUNT_ID
```

### Step 4: Update terraform.tfvars

```powershell
# Edit terraform.tfvars and update gcp_project_id if you used a different name
notepad terraform.tfvars
```

Ensure this line matches your project:
```hcl
gcp_project_id = "daily-coordinator-sadc"  # Or your project ID
```

### Step 5: Deploy All Infrastructure

```powershell
cd 'c:\Users\_oloyouth\Downloads\Dailty Coord Agent'

# If you disabled GCP earlier, re-enable it
if (Test-Path gcp.tf.backup) {
    Remove-Item gcp.tf -ErrorAction SilentlyContinue
    Copy-Item gcp.tf.backup gcp.tf
}

# Plan and deploy
terraform plan -out=tfplan
terraform apply tfplan
```

**Duration**: 5-7 minutes (includes GCP API enablement)  
**Cost**: ~$7-10/month total (AWS + GCP under free tiers)

### Step 6: Verify GCP Resources

```powershell
# Verify Pub/Sub topic
gcloud pubsub topics describe daily-coordinator-events

# Verify subscription
gcloud pubsub subscriptions describe coordinator-processing-sub

# Verify service account
gcloud iam service-accounts list --filter="email:daily-coordinator-pubsub@*"

# Test publishing to Pub/Sub
gcloud pubsub topics publish daily-coordinator-events --message='{"test": "from gcloud"}'

# Pull message from subscription
gcloud pubsub subscriptions pull coordinator-processing-sub --auto-ack --limit=1
```

### Step 7: Deploy Firebase/Firestore

Follow instructions in `docs/MOBILE_OFFLINE_SETUP.md`:

```powershell
# Install Firebase CLI
npm install -g firebase-tools

# Login and initialize
firebase login
cd pwa
firebase init
```

---

## Next Steps After Deployment

### 1. Configure Lambda Code (AWS Only)

The Lambda function needs actual implementation code. Currently it's a placeholder.

**Edit `main/index.py`** with your coordination logic, then:

```powershell
# Recreate Lambda ZIP
cd main
python -m zipfile -c ../lambda_function.zip *.py
cd ..

# Update Lambda function
aws lambda update-function-code --function-name daily-coordinator-agent --zip-file fileb://lambda_function.zip
```

### 2. Set Up Slack Integration

1. Go to https://api.slack.com/apps
2. Create new app → From scratch
3. Add "Incoming Webhooks" → Activate
4. Add New Webhook to Workspace → Select channel
5. Copy webhook URL
6. Store in AWS Secrets Manager (see Step 5 in Option 1)

### 3. Enable GCP Pub/Sub Lambda Layer (If Using GCP)

```powershell
# Create Lambda layer for google-cloud-pubsub
mkdir python\lib\python3.11\site-packages -Force
pip install google-cloud-pubsub -t python\lib\python3.11\site-packages
Compress-Archive -Path python -DestinationPath gcp-pubsub-layer.zip

# Publish layer
aws lambda publish-layer-version --layer-name gcp-pubsub --zip-file fileb://gcp-pubsub-layer.zip --compatible-runtimes python3.11

# Attach to Lambda (get layer ARN from previous command output)
aws lambda update-function-configuration --function-name daily-coordinator-agent --layers arn:aws:lambda:us-west-2:ACCOUNT_ID:layer:gcp-pubsub:1
```

### 4. Test End-to-End Flow

```powershell
# Manually trigger EventBridge rule
aws events put-events --entries file://test-event.json

# Create test-event.json:
@"
[
  {
    "Source": "aws.events",
    "DetailType": "Scheduled Event",
    "Detail": "{\"action\": \"daily_coordination\", \"source\": \"manual_test\"}"
  }
]
"@ | Out-File test-event.json

# Watch logs
aws logs tail /aws/lambda/daily-coordinator-agent --follow
```

### 5. Monitor Costs

```powershell
# Check AWS costs (current month)
aws ce get-cost-and-usage --time-period Start=2025-11-01,End=2025-11-30 --granularity MONTHLY --metrics BlendedCost

# GCP costs
gcloud billing accounts list
# Then view in console: https://console.cloud.google.com/billing
```

---

## Troubleshooting

### AWS CLI Not Configured

```powershell
aws configure
# Enter: Access Key ID, Secret Access Key, Region (us-west-2), Output format (json)
```

### Terraform State Locked

```powershell
# If Terraform crashes mid-apply
terraform force-unlock LOCK_ID
```

### Lambda Timeout

If Lambda times out (300s), check:
1. Network connectivity to external services
2. DynamoDB/S3 latency
3. Increase timeout in `terraform.tfvars`: `lambda_timeout = 600`

### GCP Quota Exceeded

```powershell
# Check quotas
gcloud compute project-info describe --project=$gcpProjectId

# Request quota increase in console
```

### S3 Bucket Name Already Exists

S3 bucket names are globally unique. Edit `terraform.tfvars`:
```hcl
s3_bucket_name = "sas-ops-cache-daily-coordinator-YOUR_ORG_NAME"
```

---

## Rollback Instructions

### Destroy All Infrastructure

```powershell
cd 'c:\Users\_oloyouth\Downloads\Dailty Coord Agent'
terraform destroy

# Confirm by typing 'yes'
```

**WARNING**: This deletes all data in DynamoDB, S3, and Firestore!

### Destroy AWS Only (Keep GCP)

```powershell
# Disable GCP resources first
Rename-Item gcp.tf gcp.tf.disabled
terraform destroy
```

### Destroy GCP Only (Keep AWS)

```powershell
# Target GCP resources
terraform destroy -target=google_pubsub_topic.coordinator_events -target=google_pubsub_subscription.coordinator_processing -target=google_service_account.pubsub_publisher
```

---

## Cost Estimates

### AWS Free Tier Eligible
- Lambda: 1M requests/month free (we use ~30/month)
- DynamoDB: 25 GB storage + 200M requests/month free
- S3: 5 GB storage + 20K GET/2K PUT free
- CloudWatch Logs: 5 GB ingestion/month free
- **Estimated**: $0-3/month (mostly CloudWatch after free tier)

### GCP Free Tier Eligible
- Pub/Sub: 10 GB/month free
- Firestore: 1 GB storage + 50K reads/20K writes per day free
- Cloud Functions: 2M invocations/month free
- **Estimated**: $0-2/month (under free tier for SADC usage)

### Total Monthly Cost
- **Development**: $0-5/month (under free tiers)
- **Production**: $5-15/month (with monitoring/logging)

---

## Documentation Reference

- **Main Setup**: `docs/DEPLOYMENT_CHECKLIST.md`
- **GCP Pub/Sub**: `docs/GCP_PUBSUB.md`
- **Mobile/Offline**: `docs/MOBILE_OFFLINE_SETUP.md`
- **Terraform Variables**: `terraform.tfvars.example`

---

## Support

- **GitHub Issues**: https://github.com/AfricanTobacco/Daily-Coordinator/issues
- **Terraform Docs**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **AWS Lambda**: https://docs.aws.amazon.com/lambda/
- **GCP Pub/Sub**: https://cloud.google.com/pubsub/docs

---

## Current Deployment Decision

**Recommended**: Start with **Option 1 (AWS Only)** to get infrastructure running immediately, then add GCP later when you're ready for the mobile/offline features.

Run this command now:
```powershell
cd 'c:\Users\_oloyouth\Downloads\Dailty Coord Agent'
Rename-Item gcp.tf gcp.tf.disabled
terraform plan -out=tfplan
terraform apply tfplan
```
