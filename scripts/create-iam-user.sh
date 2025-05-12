#!/bin/bash

# Script to create IAM user for Innoscripta evaluation

set -e

# Variables
USER_NAME="innoscripta-evaluator"
POLICY_NAME="innoscripta-eks-ecr-policy"
AWS_REGION=${AWS_DEFAULT_REGION:-"us-east-1"}
CLUSTER_NAME="laravel-eks-dev"

echo "Creating IAM user for evaluation..."

# Create IAM user
aws iam create-user --user-name $USER_NAME

# Create access key
ACCESS_KEY_OUTPUT=$(aws iam create-access-key --user-name $USER_NAME)
ACCESS_KEY_ID=$(echo $ACCESS_KEY_OUTPUT | jq -r '.AccessKey.AccessKeyId')
SECRET_ACCESS_KEY=$(echo $ACCESS_KEY_OUTPUT | jq -r '.AccessKey.SecretAccessKey')

# Create policy document
cat > policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters",
                "eks:AccessKubernetesApi"
            ],
            "Resource": [
                "arn:aws:eks:$AWS_REGION:*:cluster/$CLUSTER_NAME",
                "arn:aws:eks:$AWS_REGION:*:cluster/laravel-eks-*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:DescribeRepositories",
                "ecr:ListImages"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:GetRole",
                "iam:PassRole"
            ],
            "Resource": "arn:aws:iam::*:role/laravel-eks-*"
        }
    ]
}
EOF

# Create IAM policy
POLICY_ARN=$(aws iam create-policy \
    --policy-name $POLICY_NAME \
    --policy-document file://policy.json \
    --query 'Policy.Arn' \
    --output text)

# Attach policy to user
aws iam attach-user-policy \
    --user-name $USER_NAME \
    --policy-arn $POLICY_ARN

# Create EKS cluster role mapping
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapUsers: |
    - userarn: arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):user/$USER_NAME
      username: $USER_NAME
      groups:
        - system:masters
EOF

# Save credentials
cat > evaluator-credentials.txt <<EOF
AWS Access Key ID: $ACCESS_KEY_ID
AWS Secret Access Key: $SECRET_ACCESS_KEY
Region: $AWS_REGION

To configure AWS CLI:
aws configure --profile innoscripta-evaluator

To access EKS cluster:
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION --profile innoscripta-evaluator
EOF

echo "IAM user created successfully!"
echo "Credentials saved to evaluator-credentials.txt"
echo "Please share this file securely with renardiarvy@gmail.com"

# Clean up
rm policy.json