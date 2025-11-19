# Mobile & Offline-First Layer Setup

## Overview

This guide covers deploying the SADC-optimized mobile layer with Firebase/Firestore offline sync and WhatsApp alerting.

## Architecture

```
AWS Lambda → GCP Pub/Sub
                ↓
         Cloud Function
                ↓
         Firestore (offline-enabled)
                ↓
    PWA (offline-first, service worker)
                ↓
     SADC Operators (mobile/desktop)

SNS → WhatsApp Lambda → Twilio → WhatsApp Recipients
```

## Prerequisites

- GCP project with Firebase enabled
- Twilio account with WhatsApp Business API access
- Node.js/npm (for Firebase CLI)
- Firebase CLI: `npm install -g firebase-tools`

---

## Part 1: Firebase/Firestore Setup

### 1. Create Firebase Project

```bash
# Login to Firebase
firebase login

# Initialize Firebase in pwa/ directory
cd pwa
firebase init

# Select:
# - Firestore: Configure security rules and indexes
# - Hosting: Configure files for Firebase Hosting
# - Use existing project: daily-coordinator-sadc
```

### 2. Configure Firestore Security Rules

Edit `pwa/firestore.rules`:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Public read-only access to tasks (operators don't need auth)
    match /tasks/{taskId} {
      allow read: if true;
      allow write: if false;  // Only Cloud Function writes
    }
    
    match /coordinators/{coordinatorId} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

Deploy rules:

```bash
firebase deploy --only firestore:rules
```

### 3. Get Firebase Config

```bash
# Get web app config
firebase apps:sdkconfig web
```

Copy the config and update `pwa/index.html` (replace `firebaseConfig` object).

### 4. Deploy PWA to Firebase Hosting

```bash
cd pwa
firebase deploy --only hosting
```

Access at: `https://PROJECT_ID.web.app`

---

## Part 2: Cloud Function Deployment

### 1. Deploy Pub/Sub → Firestore Function

```bash
cd cloud-function

gcloud functions deploy pubsub-to-firestore \
  --runtime python311 \
  --trigger-topic daily-coordinator-events \
  --entry-point pubsub_to_firestore \
  --region us-central1 \
  --project daily-coordinator-sadc \
  --memory 256MB \
  --timeout 60s
```

### 2. Test Function

Publish test message:

```bash
gcloud pubsub topics publish daily-coordinator-events \
  --message '{"coordinator_id":"test-001","status":"success","tasks_processed":3,"errors":[],"timestamp":"2025-11-18T10:00:00Z"}' \
  --project daily-coordinator-sadc
```

Verify in Firestore Console or PWA.

---

## Part 3: WhatsApp Integration

### 1. Create Twilio Account

1. Sign up: https://www.twilio.com/try-twilio
2. Get trial WhatsApp sandbox number: https://console.twilio.com/us1/develop/sms/try-it-out/whatsapp-learn
3. Join sandbox by sending code to `+1 415 523 8886`

### 2. Store Twilio Credentials in Secrets Manager

```bash
aws secretsmanager create-secret \
  --name daily-coordinator-twilio-creds \
  --secret-string '{"account_sid":"ACXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX","auth_token":"your_auth_token"}' \
  --region us-west-2
```

### 3. Create WhatsApp Lambda Layer

```bash
mkdir -p python/lib/python3.11/site-packages
pip install twilio -t python/lib/python3.11/site-packages
zip -r twilio-layer.zip python

aws lambda publish-layer-version \
  --layer-name twilio-whatsapp \
  --zip-file fileb://twilio-layer.zip \
  --compatible-runtimes python3.11 \
  --region us-west-2
```

### 4. Deploy WhatsApp Lambda (Manual - Terraform coming)

```bash
cd lambda-whatsapp
zip whatsapp-function.zip whatsapp_sender.py

aws lambda create-function \
  --function-name daily-coordinator-whatsapp-sender \
  --runtime python3.11 \
  --role arn:aws:iam::ACCOUNT:role/daily-coordinator-agent-role \
  --handler whatsapp_sender.lambda_handler \
  --zip-file fileb://whatsapp-function.zip \
  --layers arn:aws:lambda:REGION:ACCOUNT:layer:twilio-whatsapp:1 \
  --environment Variables="{TWILIO_SECRET_NAME=daily-coordinator-twilio-creds,WHATSAPP_FROM=whatsapp:+14155238886,WHATSAPP_TO=whatsapp:+27821234567}" \
  --region us-west-2
```

### 5. Subscribe WhatsApp Lambda to SNS

```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:us-west-2:ACCOUNT:daily-coordinator-alerts \
  --protocol lambda \
  --notification-endpoint arn:aws:lambda:us-west-2:ACCOUNT:function:daily-coordinator-whatsapp-sender
```

Grant permission:

```bash
aws lambda add-permission \
  --function-name daily-coordinator-whatsapp-sender \
  --statement-id AllowSNSInvoke \
  --action lambda:InvokeFunction \
  --principal sns.amazonaws.com \
  --source-arn arn:aws:sns:us-west-2:ACCOUNT:daily-coordinator-alerts
```

---

## Testing End-to-End

### 1. Trigger Coordinator Lambda

```bash
aws lambda invoke \
  --function-name daily-coordinator-agent \
  --payload '{"source":"manual","action":"test"}' \
  response.json
```

### 2. Verify Flow

1. **DynamoDB**: Check `CoordinatorState` table for new entry
2. **S3**: Verify cache upload to `sas-ops-cache`
3. **SNS**: Confirm alert published to topic
4. **Slack**: Check channel for "Task updated" message
5. **Pub/Sub**: View messages in GCP Console
6. **Firestore**: See new document in `tasks` collection
7. **PWA**: Reload app, see task card appear
8. **WhatsApp**: Receive formatted alert on mobile

---

## Offline Testing

### 1. Enable Airplane Mode

- Open PWA in browser
- Turn on airplane mode (or disconnect Wi-Fi)
- Reload page - should still load from cache

### 2. Background Sync Test

- Keep PWA open while offline
- Turn connectivity back on
- Watch Firestore auto-sync new tasks without page refresh

---

## Cost Breakdown (SADC Region)

| Service | Monthly Usage | Cost (USD) |
|---------|--------------|------------|
| Firebase Hosting | 10 GB bandwidth | Free tier |
| Firestore | 1 GB storage, 50K reads | Free tier |
| Cloud Functions | 30 invocations | Free tier |
| Twilio WhatsApp | 30 messages | ~$0.15 |
| **Total** | | **< $0.50/month** |

---

## SADC-Specific Optimizations

### 1. Firestore Region

Use `africa-south1` (Johannesburg) for lowest latency:

```hcl
# In gcp.tf
resource "google_firestore_database" "coordinator" {
  location_id = "africa-south1"  # South Africa region
}
```

### 2. PWA Optimizations

**Aggressive caching** for intermittent connectivity:

```javascript
// In sw.js, increase cache expiration
const CACHE_EXPIRATION_DAYS = 30;  // vs. default 7 days
```

**Lazy image loading** for slow 3G:

```html
<img loading="lazy" src="icon.png" />
```

### 3. WhatsApp vs. SMS

WhatsApp penetration in SADC: **95%+**  
Cost comparison (South Africa):
- SMS: $0.05/message
- WhatsApp: $0.005/message (10x cheaper)

---

## Production Readiness Checklist

- [ ] Firebase project in production mode
- [ ] Firestore security rules hardened (read-only public)
- [ ] PWA manifest with custom icons (192×192, 512×512)
- [ ] Service worker cache versioning strategy
- [ ] Twilio account upgraded from trial (for non-sandbox numbers)
- [ ] WhatsApp recipient numbers verified
- [ ] Cloud Function error alerting (Stackdriver)
- [ ] PWA analytics (Firebase Analytics)
- [ ] Offline fallback UI for stale data
- [ ] Rate limiting on Cloud Function (prevent abuse)

---

## Troubleshooting

### PWA not updating

```bash
# Clear service worker cache
# In browser DevTools → Application → Service Workers → Unregister
# Then Storage → Clear site data
```

### Firestore permission denied

Check security rules allow public reads:

```bash
firebase firestore:rules:get
```

### WhatsApp not received

1. Verify Twilio sandbox joined: https://console.twilio.com/us1/develop/sms/try-it-out/whatsapp-learn
2. Check Lambda logs for Twilio errors
3. Confirm recipient number format: `whatsapp:+27XXXXXXXXX`

### Cloud Function timeout

Increase timeout in deployment:

```bash
--timeout 120s  # vs. default 60s
```

---

## Next Steps

1. **Push Notifications**: Add Firebase Cloud Messaging (FCM) for real-time alerts
2. **Authentication**: Implement Firebase Auth for operator login (PII compliance)
3. **Analytics**: Track PWA engagement with Firebase Analytics
4. **Asana Integration**: Sync tasks to Asana for project management
5. **SQLite Fallback**: Add local SQLite cache in PWA for full offline editing

---

## References

- [Firebase Hosting](https://firebase.google.com/docs/hosting)
- [Firestore Offline Persistence](https://firebase.google.com/docs/firestore/manage-data/enable-offline)
- [Twilio WhatsApp API](https://www.twilio.com/docs/whatsapp/api)
- [Progressive Web Apps](https://web.dev/progressive-web-apps/)
- [Service Workers](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API)
