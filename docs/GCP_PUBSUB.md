# GCP Pub/Sub Integration Guide

## Overview

The Daily Coordinator integrates with Google Cloud Platform (GCP) Pub/Sub for cross-cloud event distribution. AWS Lambda publishes coordinator events to a GCP Pub/Sub topic, enabling downstream GCP services (Cloud Functions, Cloud Run, etc.) to consume events asynchronously.

## Architecture

```
AWS Lambda (Coordinator)
    ↓
Publishes event via GCP SDK
    ↓
GCP Pub/Sub Topic (daily-coordinator-events)
    ↓
GCP Pub/Sub Subscription (coordinator-processing-sub)
    ↓
GCP Consumers (Cloud Functions, etc.)
```

## Prerequisites

1. **GCP Project**: Active GCP project with Pub/Sub API enabled
2. **GCP Billing**: Billing account linked to project
3. **Terraform**: Version >= 1.0 with GCP provider configured
4. **Service Account**: Created automatically by Terraform

## Setup Steps

### 1. Enable GCP Pub/Sub API

```bash
gcloud services enable pubsub.googleapis.com --project=daily-coordinator-sadc
```

### 2. Configure Terraform Variables

Edit `terraform.tfvars`:

```hcl
gcp_project_id               = "daily-coordinator-sadc"
gcp_region                   = "us-central1"
gcp_pubsub_topic_name        = "daily-coordinator-events"
gcp_pubsub_subscription_name = "coordinator-processing-sub"
```

### 3. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

Terraform will:
- Create GCP service account `daily-coordinator-pubsub@PROJECT_ID.iam.gserviceaccount.com`
- Generate service account key
- Store key in AWS Secrets Manager as `daily-coordinator-gcp-pubsub-key`
- Create Pub/Sub topic `daily-coordinator-events`
- Create subscription `coordinator-processing-sub`
- Configure IAM bindings (publisher + subscriber roles)

### 4. Add GCP SDK to Lambda Layer

The Lambda needs `google-cloud-pubsub` library. Create a Lambda layer:

```bash
mkdir -p python/lib/python3.11/site-packages
pip install google-cloud-pubsub -t python/lib/python3.11/site-packages
zip -r gcp-pubsub-layer.zip python
aws lambda publish-layer-version \
  --layer-name gcp-pubsub \
  --zip-file fileb://gcp-pubsub-layer.zip \
  --compatible-runtimes python3.11
```

Attach the layer to your Lambda in `main.tf`:

```hcl
resource "aws_lambda_function" "coordinator" {
  # ... existing config
  layers = ["arn:aws:lambda:REGION:ACCOUNT:layer:gcp-pubsub:1"]
}
```

## Usage

### Option 1: Decorator Pattern (Automatic Publishing)

Wrap your Lambda handler:

```python
from lambda.gcp_pubsub import lambda_handler_with_pubsub

@lambda_handler_with_pubsub
def lambda_handler(event, context):
    # Your existing logic
    results = coordinate_daily_tasks()
    
    return {
        'statusCode': 200,
        'body': json.dumps(results)
    }
```

### Option 2: Manual Publishing

```python
from lambda.gcp_pubsub import publish_to_pubsub

def lambda_handler(event, context):
    results = coordinate_daily_tasks()
    
    # Publish to Pub/Sub
    try:
        message_id = publish_to_pubsub(results)
        logger.info(f"Published to Pub/Sub: {message_id}")
    except Exception as e:
        logger.warning(f"Pub/Sub publish failed: {e}")
    
    return {'statusCode': 200, 'body': json.dumps(results)}
```

## Message Format

Published messages follow this schema:

```json
{
  "coordinator_id": "daily-coordinator-001",
  "timestamp": "2025-11-18T15:30:00Z",
  "status": "success",
  "tasks_processed": 5,
  "errors": []
}
```

Message attributes for filtering:

- `source`: `"daily-coordinator"`
- `event_type`: `success`, `failed`, `partial`
- `coordinator_id`: Unique coordinator identifier

## Consuming Events (GCP Side)

### Pull Subscription (Python)

```python
from google.cloud import pubsub_v1

project_id = "daily-coordinator-sadc"
subscription_id = "coordinator-processing-sub"

subscriber = pubsub_v1.SubscriberClient()
subscription_path = subscriber.subscription_path(project_id, subscription_id)

def callback(message):
    print(f"Received message: {message.data}")
    print(f"Attributes: {message.attributes}")
    message.ack()

streaming_pull_future = subscriber.subscribe(subscription_path, callback=callback)
print(f"Listening for messages on {subscription_path}...")

try:
    streaming_pull_future.result()
except KeyboardInterrupt:
    streaming_pull_future.cancel()
```

### Cloud Function (Push Subscription)

Convert subscription to push mode:

```bash
gcloud pubsub subscriptions modify coordinator-processing-sub \
  --push-endpoint=https://REGION-PROJECT_ID.cloudfunctions.net/processCoordinatorEvent
```

Cloud Function handler:

```python
import base64
import json

def process_coordinator_event(request):
    envelope = request.get_json()
    
    if not envelope:
        return ('Bad Request: no Pub/Sub message', 400)
    
    pubsub_message = envelope.get('message')
    if not pubsub_message:
        return ('Bad Request: invalid Pub/Sub message', 400)
    
    data = base64.b64decode(pubsub_message.get('data')).decode('utf-8')
    event = json.loads(data)
    
    print(f"Processing event: {event}")
    
    # Your processing logic here
    
    return ('OK', 200)
```

## Monitoring

### View Messages

```bash
# List topics
gcloud pubsub topics list

# View topic details
gcloud pubsub topics describe daily-coordinator-events

# List subscriptions
gcloud pubsub subscriptions list

# View subscription details
gcloud pubsub subscriptions describe coordinator-processing-sub

# Pull messages manually (for testing)
gcloud pubsub subscriptions pull coordinator-processing-sub --limit=5 --auto-ack
```

### Metrics

GCP Console → Pub/Sub → Topics/Subscriptions → Metrics tab

Key metrics:
- **Publish rate**: Messages/second published to topic
- **Unacknowledged messages**: Backlog size
- **Oldest unacknowledged message age**: Processing lag
- **Subscription throughput**: Messages delivered/second

## Cost Estimation

**GCP Pub/Sub Pricing (us-central1)**:

| Resource | Usage (monthly) | Cost |
|----------|----------------|------|
| Topic data ingress | 30 messages × 1 KB | $0.00 |
| Message storage | < 10 GB | $0.00 |
| Subscription throughput | 30 messages | $0.00 |
| **Total** | | **< $0.10/month** |

First 10 GB/month is free tier.

## Troubleshooting

### Lambda can't publish to Pub/Sub

1. Check service account key exists in Secrets Manager:
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id daily-coordinator-gcp-pubsub-key \
     --region us-west-2
   ```

2. Verify Lambda has Secrets Manager permissions:
   ```bash
   aws iam get-role-policy \
     --role-name daily-coordinator-agent-role \
     --policy-name daily-coordinator-agent-secrets-policy
   ```

3. Test GCP credentials locally:
   ```python
   from google.cloud import pubsub_v1
   from google.oauth2 import service_account
   
   creds = service_account.Credentials.from_service_account_file('key.json')
   client = pubsub_v1.PublisherClient(credentials=creds)
   topic_path = client.topic_path('PROJECT_ID', 'TOPIC')
   future = client.publish(topic_path, b'test')
   print(f"Message ID: {future.result()}")
   ```

### Messages not reaching subscription

1. Check topic permissions:
   ```bash
   gcloud pubsub topics get-iam-policy daily-coordinator-events
   ```

2. Verify subscription is attached to topic:
   ```bash
   gcloud pubsub subscriptions describe coordinator-processing-sub
   ```

3. Look for delivery errors:
   ```bash
   gcloud logging read \
     "resource.type=pubsub_subscription AND resource.labels.subscription_id=coordinator-processing-sub" \
     --limit 50
   ```

### Import errors in Lambda

- Ensure `google-cloud-pubsub` is in Lambda layer or deployment package
- Check layer Python version matches Lambda runtime (3.11)
- Verify layer ARN is attached in `main.tf`

## Security Best Practices

✅ **Implemented**:
- Service account with minimal `roles/pubsub.publisher` role
- Private key stored in AWS Secrets Manager (encrypted at rest)
- IAM resource-level permissions (topic-specific access)
- No public access to topic or subscription

🔒 **Recommended**:
- Rotate service account key quarterly
- Enable VPC Service Controls for GCP project
- Use Workload Identity if running on GKE
- Implement message encryption for sensitive data

## References

- [GCP Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [GCP IAM Best Practices](https://cloud.google.com/iam/docs/best-practices)
- [Python Client Library](https://googleapis.dev/python/pubsub/latest/)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
