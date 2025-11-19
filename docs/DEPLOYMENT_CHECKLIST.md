# Deployment Checklist: GCP Pub/Sub Integration

## Issues Fixed

### 1. ✅ Missing Pub/Sub API Enablement
**Problem**: `google_pubsub_topic` resource would fail because `pubsub.googleapis.com` API wasn't explicitly enabled.

**Fix**: Added `google_project_service.pubsub` resource.

### 2. ✅ Missing Dependency Chain
**Problem**: Pub/Sub topic could be created before API is enabled, causing deployment failures.

**Fix**: Added `depends_on = [google_project_service.pubsub]` to topic resource.

### 3. ✅ Incorrect Topic Reference in Subscription
**Problem**: Subscription used `.name` instead of `.id` for topic reference, causing potential issues with cross-project or fully-qualified topic names.

**Fix**: Changed `topic = google_pubsub_topic.coordinator_events.name` to `topic = google_pubsub_topic.coordinator_events.id`.

### 4. ✅ Missing IAM Dependency Chain
**Problem**: IAM bindings could fail if created before underlying resources.

**Fix**: Added explicit `depends_on` to both IAM member resources.

---

## Pre-Deployment Requirements

### GCP Prerequisites
- [ ] **GCP Project Created**: Run `gcloud projects create PROJECT_ID` or use Console
- [ ] **Billing Enabled**: Link billing account to project
- [ ] **gcloud CLI Installed**: Download from https://cloud.google.com/sdk/docs/install
- [ ] **Authenticated**: Run `gcloud auth application-default login`
- [ ] **Project Set**: Run `gcloud config set project PROJECT_ID`

### Terraform Prerequisites
- [ ] **Terraform Installed**: Download from https://www.terraform.io/downloads (v1.0+)
- [ ] **terraform.tfvars Created**: Copy `terraform.tfvars.example` and set `gcp_project_id`

### AWS Prerequisites
- [ ] **AWS CLI Configured**: Run `aws configure` with credentials
- [ ] **S3 Bucket Available**: Ensure `s3_bucket_name` in tfvars is globally unique

---

## Deployment Steps

### Step 1: Validate Configuration
```powershell
cd 'c:\Users\_oloyouth\Downloads\Dailty Coord Agent'
terraform fmt      # Format all .tf files
terraform validate # Check syntax
```

### Step 2: Initialize Terraform
```powershell
terraform init
```
**Expected Output**:
```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Finding hashicorp/google versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...
- Installing hashicorp/google v5.x.x...

Terraform has been successfully initialized!
```

### Step 3: Review Deployment Plan
```powershell
terraform plan -out=tfplan
```
**Check for**:
- 30+ resources to be created (AWS + GCP)
- No destruction of existing resources (unless expected)
- Correct variable values in plan output

### Step 4: Deploy Infrastructure
```powershell
terraform apply tfplan
```
**Expected Duration**: 3-5 minutes

**Watch for**:
- API enablement (30-60 seconds each)
- Service account key generation
- Secrets Manager storage
- Lambda function deployment

### Step 5: Verify GCP Resources
```powershell
# Verify Pub/Sub topic
gcloud pubsub topics describe daily-coordinator-events

# Expected output:
# name: projects/PROJECT_ID/topics/daily-coordinator-events
# messageRetentionDuration: 86400s

# Verify subscription
gcloud pubsub subscriptions describe coordinator-processing-sub

# Expected output:
# name: projects/PROJECT_ID/subscriptions/coordinator-processing-sub
# topic: projects/PROJECT_ID/topics/daily-coordinator-events
# ackDeadlineSeconds: 20

# Verify service account
gcloud iam service-accounts list --filter="email:daily-coordinator-pubsub@*"
```

### Step 6: Test Pub/Sub Publishing
```powershell
# Publish test message
gcloud pubsub topics publish daily-coordinator-events --message='{"test": "message", "source": "manual"}'

# Pull from subscription to verify
gcloud pubsub subscriptions pull coordinator-processing-sub --auto-ack --limit=1
```

**Expected Output**:
```
┌─────────────────────────────────┬─────────────────┬────────────┐
│              DATA               │   MESSAGE_ID    │ ATTRIBUTES │
├─────────────────────────────────┼─────────────────┼────────────┤
│ {"test": "message", "source":   │ 1234567890      │            │
│ "manual"}                       │                 │            │
└─────────────────────────────────┴─────────────────┴────────────┘
```

---

## Common Issues & Troubleshooting

### Issue 1: `terraform: command not found`
**Cause**: Terraform not installed or not in PATH.

**Fix**:
1. Download Terraform from https://www.terraform.io/downloads
2. Extract to `C:\terraform`
3. Add to PATH: `$env:Path += ";C:\terraform"`
4. Verify: `terraform version`

### Issue 2: `Error: google: could not find default credentials`
**Cause**: GCP authentication not configured.

**Fix**:
```powershell
gcloud auth application-default login
```

### Issue 3: `Error creating Topic: googleapi: Error 403: Pub/Sub API not enabled`
**Cause**: API enablement resource didn't complete before topic creation (race condition).

**Fix**: This is now prevented by explicit `depends_on` chains. If it still occurs:
```powershell
gcloud services enable pubsub.googleapis.com
terraform apply -replace=google_pubsub_topic.coordinator_events
```

### Issue 4: `Error: required variable "gcp_project_id" not set`
**Cause**: Missing `terraform.tfvars` file.

**Fix**:
```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set gcp_project_id = "your-project-id"
```

### Issue 5: `Error creating Subscription: topic does not exist`
**Cause**: Subscription created before topic (dependency issue).

**Fix**: Fixed by adding `depends_on = [google_pubsub_topic.coordinator_events]` to subscription resource.

### Issue 6: Lambda can't publish to Pub/Sub
**Symptoms**: Lambda logs show authentication errors.

**Debug**:
```powershell
# Check if secret exists in AWS Secrets Manager
aws secretsmanager describe-secret --secret-id daily-coordinator-gcp-pubsub-key

# Verify service account key format
aws secretsmanager get-secret-value --secret-id daily-coordinator-gcp-pubsub-key --query SecretString --output text | python -m json.tool

# Expected: Valid JSON with "type": "service_account"
```

**Fix**: Re-run Terraform to recreate service account key:
```powershell
terraform apply -replace=google_service_account_key.pubsub_publisher_key
```

---

## Post-Deployment Validation

### AWS Resources
```powershell
# Verify Lambda function
aws lambda get-function --function-name daily-coordinator-agent

# Check Lambda environment variables
aws lambda get-function-configuration --function-name daily-coordinator-agent --query 'Environment.Variables'

# Expected GCP variables:
# GCP_PUBSUB_SECRET_NAME: daily-coordinator-gcp-pubsub-key
# GCP_PROJECT_ID: your-project-id
# GCP_PUBSUB_TOPIC: daily-coordinator-events

# Test Lambda invocation
aws lambda invoke --function-name daily-coordinator-agent --payload '{"test": true}' output.json
cat output.json
```

### GCP Resources
```powershell
# Check topic permissions
gcloud pubsub topics get-iam-policy daily-coordinator-events

# Expected: roles/pubsub.publisher for service account

# Check subscription permissions
gcloud pubsub subscriptions get-iam-policy coordinator-processing-sub

# Expected: roles/pubsub.subscriber for service account

# Monitor messages in flight
gcloud pubsub subscriptions describe coordinator-processing-sub --format="value(numUndeliveredMessages)"
```

### Cross-Cloud Integration Test
```powershell
# 1. Invoke Lambda manually (should publish to Pub/Sub)
aws lambda invoke --function-name daily-coordinator-agent --payload '{"source": "test"}' output.json

# 2. Check Pub/Sub topic for messages (within 5 seconds)
gcloud pubsub subscriptions pull coordinator-processing-sub --auto-ack --limit=5

# 3. Expected: JSON payload from Lambda with coordinator state
```

---

## Terraform Outputs

After successful deployment, capture these values:

```powershell
terraform output -json | ConvertFrom-Json | ConvertTo-Json -Depth 10 > terraform-outputs.json
```

**Key Outputs**:
- `gcp_pubsub_topic_name`: Topic name for Lambda environment variable
- `gcp_pubsub_subscription_name`: Subscription for Cloud Function
- `gcp_service_account_email`: Service account for IAM grants
- `lambda_function_arn`: ARN for EventBridge rule target
- `sns_topic_arn`: SNS topic for Slack/WhatsApp subscriptions

---

## Rollback Procedure

If deployment fails critically:

```powershell
# Destroy GCP resources only
terraform destroy -target=google_pubsub_subscription.coordinator_processing
terraform destroy -target=google_pubsub_topic.coordinator_events
terraform destroy -target=google_service_account.pubsub_publisher

# Destroy all infrastructure
terraform destroy

# WARNING: This will delete DynamoDB data, S3 cache, and all AWS resources!
```

---

## Next Steps

After successful GCP Pub/Sub deployment:

1. **Deploy Cloud Function**: Follow `docs/MOBILE_OFFLINE_SETUP.md` Step 3
2. **Setup Firebase**: Follow `docs/MOBILE_OFFLINE_SETUP.md` Steps 1-2
3. **Deploy PWA**: Follow `docs/MOBILE_OFFLINE_SETUP.md` Step 4
4. **Configure WhatsApp**: Follow `docs/MOBILE_OFFLINE_SETUP.md` Step 5
5. **Run End-to-End Test**: Follow `docs/MOBILE_OFFLINE_SETUP.md` Step 6

---

## Cost Monitoring

GCP Free Tier (as of 2024):
- **Pub/Sub**: First 10 GB/month free
- **Firestore**: 1 GB storage + 50K reads/day + 20K writes/day
- **Cloud Functions**: 2M invocations/month

**Expected Monthly Cost** (SADC usage):
- GCP Pub/Sub: $0 (under free tier)
- Firestore: $0-$2 (under free tier for ~100 daily tasks)
- Cloud Functions: $0 (under free tier)
- **Total GCP**: ~$0-$2/month

**Monitor costs**:
```powershell
gcloud billing accounts list
gcloud billing projects link PROJECT_ID --billing-account=BILLING_ACCOUNT_ID

# View current month spending
gcloud billing projects describe PROJECT_ID --format="value(billingAccountName)"
```

Set up budget alerts in GCP Console: https://console.cloud.google.com/billing/budgets

---

## Security Checklist

- [x] Service account key stored in AWS Secrets Manager (encrypted at rest)
- [x] IAM permissions follow least-privilege (publisher/subscriber roles only)
- [x] Pub/Sub messages retain for 24 hours max (data minimization)
- [x] Lambda execution role scoped to specific secrets
- [ ] **TODO**: Enable VPC Service Controls for GCP (production)
- [ ] **TODO**: Rotate service account keys every 90 days
- [ ] **TODO**: Enable Cloud Audit Logs for Pub/Sub access tracking

---

## Support Resources

- **GCP Pub/Sub Documentation**: https://cloud.google.com/pubsub/docs
- **Terraform Google Provider**: https://registry.terraform.io/providers/hashicorp/google/latest/docs
- **GCP Free Tier**: https://cloud.google.com/free
- **Issue Tracker**: https://github.com/AfricanTobacco/Daily-Coordinator/issues
