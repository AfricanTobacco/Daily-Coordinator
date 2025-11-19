# AWS IAM Permissions Required for Deployment

## Issue
Your AWS IAM user `Learnflow` lacks permissions to create infrastructure resources.

## Solution Options

### Option 1: Use Administrator Access (Fastest)
If you have access to the AWS root account or an admin user:

1. **AWS Console** → **IAM** → **Users** → **Learnflow**
2. **Permissions** tab → **Add permissions** → **Attach policies directly**
3. Select **AdministratorAccess**
4. Click **Add permissions**

**Security Note**: This grants full AWS access. Remove after deployment or use Option 2 for production.

---

### Option 2: Attach Least-Privilege Policy (Recommended for Production)

#### Step 1: Create Custom Policy
```powershell
# Navigate to project directory
cd 'c:\Users\_oloyouth\Downloads\Dailty Coord Agent'

# Create the policy (replace ACCOUNT_ID if different)
aws iam create-policy `
  --policy-name DailyCoordinatorDeploymentPolicy `
  --policy-document file://docs/AWS_IAM_POLICY_REQUIRED.json `
  --description "Least-privilege policy for Daily Coordinator Terraform deployment"
```

#### Step 2: Attach to User
```powershell
# Get your AWS account ID
$ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)

# Attach policy to Learnflow user
aws iam attach-user-policy `
  --user-name Learnflow `
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/DailyCoordinatorDeploymentPolicy"
```

#### Step 3: Verify
```powershell
# List attached policies
aws iam list-attached-user-policies --user-name Learnflow
```

---

### Option 3: Use Different AWS Credentials (If Available)

If you have access to AWS credentials with admin permissions:

```powershell
# Configure different profile
aws configure --profile admin

# Export profile for Terraform
$env:AWS_PROFILE = "admin"

# Re-run deployment
cd 'c:\Users\_oloyouth\Downloads\Dailty Coord Agent'
terraform apply tfplan
```

---

## Required Permissions Summary

The policy grants permissions to create/manage:
- **IAM Roles** (for Lambda execution)
- **Lambda Functions** (coordinator + Slack poster)
- **DynamoDB Table** (CoordinatorState)
- **S3 Bucket** (sas-ops-cache)
- **CloudWatch Logs** (Lambda logging)
- **EventBridge Rules** (daily schedule)
- **SNS Topics** (alerts)
- **Secrets Manager** (credentials storage)

All permissions are scoped to resources starting with `daily-coordinator-*` for security.

---

## After Permissions Are Granted

Once you have the required permissions:

```powershell
cd 'c:\Users\_oloyouth\Downloads\Dailty Coord Agent'
terraform apply tfplan
```

Expected output:
```
Apply complete! Resources: 26 added, 0 changed, 0 destroyed.
```

Duration: ~2-3 minutes

---

## Troubleshooting

### Error: "Policy document is too large"
The JSON policy is under 6KB limit. If you get this error, verify the file content:
```powershell
Get-Content docs\AWS_IAM_POLICY_REQUIRED.json
```

### Error: "MalformedPolicyDocument"
Ensure `ACCOUNT_ID` in the policy matches your AWS account:
```powershell
aws sts get-caller-identity --query Account --output text
# Should return: 205366594583
```

### Error: "User does not have permissions to create policy"
You need IAM policy creation permissions. Use **Option 1** (Administrator Access) or contact your AWS account admin.

---

## Security Best Practices

1. **Temporary Admin Access**: If using Option 1, detach AdministratorAccess after deployment
2. **Least Privilege**: Use Option 2 for production environments
3. **Policy Cleanup**: After testing, you can narrow the policy further to only necessary actions
4. **Rotate Credentials**: If using access keys, rotate them every 90 days

---

## Contact Support

If you don't have permission to modify IAM policies, contact your AWS account administrator with this policy document:
- File: `docs/AWS_IAM_POLICY_REQUIRED.json`
- Purpose: Deploy Daily Coordinator serverless infrastructure
- Scope: Limited to `daily-coordinator-*` resources only
