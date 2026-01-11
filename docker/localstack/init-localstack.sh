#!/bin/bash
set -e

echo "=== LocalStack Initialization Start ==="

# AWS CLI が「Unable to locate credentials」にならないようにダミー資格情報を明示
export AWS_ACCESS_KEY_ID=dummy
export AWS_SECRET_ACCESS_KEY=dummy
export AWS_DEFAULT_REGION=ap-northeast-1

# -----------------------------------------------------------------------------
# Secrets Manager
# -----------------------------------------------------------------------------
echo "Setting secrets in Secrets Manager..."

# RDS接続情報
aws --endpoint-url=http://localhost:4566 --region ap-northeast-1 \
    secretsmanager create-secret \
    --name "keirekipro/rds" \
    --secret-string '{"host":"db","port":"5432","database":"keireki_pro","username":"postgres","password":"postgres"}' \
    || echo "Secret keirekipro/rds already exists. Skipping."

# Redis接続情報
aws --endpoint-url=http://localhost:4566 --region ap-northeast-1 \
    secretsmanager create-secret \
    --name "keirekipro/redis" \
    --secret-string '{"redis-host":"redis","redis-port":"6379","redis-password":""}' \
    || echo "Secret keirekipro/redis already exists. Skipping."

# JWT署名鍵
aws --endpoint-url=http://localhost:4566 --region ap-northeast-1 \
    secretsmanager create-secret \
    --name "keirekipro/jwt" \
    --secret-string '{"jwt-secret":"vh8JBWqYFC2mJwZ4XD9pE7TKq3mN5RxS2HnUcL7VfAy"}' \
    || echo "Secret keirekipro/jwt already exists. Skipping."

# OIDC Google
aws --endpoint-url=http://localhost:4566 --region ap-northeast-1 \
    secretsmanager create-secret \
    --name "keirekipro/oidc/google" \
    --secret-string "{\"client_id\":\"${GOOGLE_CLIENT_ID}\",\"client_secret\":\"${GOOGLE_CLIENT_SECRET}\"}" \
    || echo "Secret keirekipro/oidc/google already exists. Skipping."

# OIDC GitHub
aws --endpoint-url=http://localhost:4566 --region ap-northeast-1 \
    secretsmanager create-secret \
    --name "keirekipro/oidc/github" \
    --secret-string "{\"client_id\":\"${GITHUB_CLIENT_ID}\",\"client_secret\":\"${GITHUB_CLIENT_SECRET}\"}" \
    || echo "Secret keirekipro/oidc/github already exists. Skipping."

# -----------------------------------------------------------------------------
# SES
# -----------------------------------------------------------------------------
echo "Registering SES sender identity..."

aws --endpoint-url=http://localhost:4566 --region ap-northeast-1 \
    ses verify-email-identity \
    --email-address no-reply@keirekipro.click \
    || echo "SES identity already exists or failed."

# -----------------------------------------------------------------------------
# S3
# -----------------------------------------------------------------------------
echo "Checking and creating S3 bucket..."

if ! aws --endpoint-url=http://localhost:4566 --region ap-northeast-1 \
    s3api head-bucket --bucket keirekipro-storage 2>/dev/null; then
    aws --endpoint-url=http://localhost:4566 --region ap-northeast-1 \
        s3api create-bucket \
        --bucket keirekipro-storage \
        --create-bucket-configuration LocationConstraint=ap-northeast-1
    echo "S3 bucket created: keirekipro-storage"
else
    echo "S3 bucket already exists. Skipping."
fi

echo "=== LocalStack Initialization Complete ==="
