#!/bin/bash
# AWS CloudShell Script to Grant Permissions to Learnflow User
# Run this script in AWS CloudShell with an admin/root account

# Set variables
USER_NAME="Learnflow"
POLICY_NAME="DailyCoordinatorDeploymentPolicy"
ACCOUNT_ID="205366594583"

echo "Creating IAM policy for Daily Coordinator deployment..."

# Create the IAM policy
aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --description "Least-privilege policy for Daily Coordinator Terraform deployment" \
  --policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "IAMPermissions",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:TagRole",
        "iam:UntagRole"
      ],
      "Resource": [
        "arn:aws:iam::205366594583:role/daily-coordinator-*"
      ]
    },
    {
      "Sid": "LambdaPermissions",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:DeleteFunction",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:AddPermission",
        "lambda:RemovePermission",
        "lambda:TagResource",
        "lambda:UntagResource",
        "lambda:PublishVersion"
      ],
      "Resource": [
        "arn:aws:lambda:us-west-2:205366594583:function:daily-coordinator-*"
      ]
    },
    {
      "Sid": "DynamoDBPermissions",
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:DeleteTable",
        "dynamodb:DescribeTable",
        "dynamodb:DescribeContinuousBackups",
        "dynamodb:DescribeTimeToLive",
        "dynamodb:UpdateTable",
        "dynamodb:UpdateTimeToLive",
        "dynamodb:UpdateContinuousBackups",
        "dynamodb:TagResource",
        "dynamodb:UntagResource",
        "dynamodb:ListTagsOfResource"
      ],
      "Resource": [
        "arn:aws:dynamodb:us-west-2:205366594583:table/CoordinatorState"
      ]
    },
    {
      "Sid": "S3Permissions",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetEncryptionConfiguration",
        "s3:PutEncryptionConfiguration",
        "s3:PutBucketTagging",
        "s3:GetBucketTagging"
      ],
      "Resource": [
        "arn:aws:s3:::sas-ops-cache-daily-coordinator-001"
      ]
    },
    {
      "Sid": "CloudWatchLogsPermissions",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:DeleteRetentionPolicy",
        "logs:TagLogGroup",
        "logs:UntagLogGroup",
        "logs:ListTagsLogGroup"
      ],
      "Resource": [
        "arn:aws:logs:us-west-2:205366594583:log-group:/aws/lambda/daily-coordinator-*"
      ]
    },
    {
      "Sid": "EventBridgePermissions",
      "Effect": "Allow",
      "Action": [
        "events:PutRule",
        "events:DeleteRule",
        "events:DescribeRule",
        "events:EnableRule",
        "events:DisableRule",
        "events:PutTargets",
        "events:RemoveTargets",
        "events:TagResource",
        "events:UntagResource",
        "events:ListTagsForResource"
      ],
      "Resource": [
        "arn:aws:events:us-west-2:205366594583:rule/daily-coordinator-*"
      ]
    },
    {
      "Sid": "SNSPermissions",
      "Effect": "Allow",
      "Action": [
        "sns:CreateTopic",
        "sns:DeleteTopic",
        "sns:GetTopicAttributes",
        "sns:SetTopicAttributes",
        "sns:Subscribe",
        "sns:Unsubscribe",
        "sns:TagResource",
        "sns:UntagResource",
        "sns:ListTagsForResource"
      ],
      "Resource": [
        "arn:aws:sns:us-west-2:205366594583:daily-coordinator-*"
      ]
    },
    {
      "Sid": "SecretsManagerPermissions",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:CreateSecret",
        "secretsmanager:DeleteSecret",
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecret",
        "secretsmanager:TagResource",
        "secretsmanager:UntagResource"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-west-2:205366594583:secret:daily-coordinator-*"
      ]
    }
  ]
}'

echo ""
echo "Attaching policy to user $USER_NAME..."

# Attach the policy to the user
aws iam attach-user-policy \
  --user-name "$USER_NAME" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/$POLICY_NAME"

echo ""
echo "✅ Policy attached successfully!"
echo ""
echo "Verification - Listing attached policies for $USER_NAME:"
aws iam list-attached-user-policies --user-name "$USER_NAME"

echo ""
echo "========================================"
echo "SETUP COMPLETE!"
echo "========================================"
echo "The Learnflow user now has permissions to deploy Daily Coordinator infrastructure."
echo "You can now return to your local PowerShell terminal and run:"
echo "  cd 'c:\\Users\\_oloyouth\\Downloads\\Dailty Coord Agent'"
echo "  terraform apply tfplan"
