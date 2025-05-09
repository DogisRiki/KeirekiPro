#!/bin/bash
set -e

# Secrets Managerへシークレットを登録
echo "Setting OIDC secrets in localstack..."

declare -A SECRETS=(
    ["keirekipro/oidc/google"]="GOOGLE"
    ["keirekipro/oidc/github"]="GITHUB"
)

for secret_name in "${!SECRETS[@]}"; do
    prefix=${SECRETS[$secret_name]}
    client_id_var=${prefix}_CLIENT_ID
    client_secret_var=${prefix}_CLIENT_SECRET

    AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy \
    aws --endpoint-url=http://localhost:4566 \
        --region ap-northeast-1 \
        secretsmanager create-secret \
        --name "$secret_name" \
        --secret-string "{\"client_id\": \"${!client_id_var}\", \"client_secret\": \"${!client_secret_var}\"}" \
        || echo "Secret $secret_name already exists. Skipping."
done

# SESへ送信元メールアドレスを登録
echo "Registering SES sender identity..."

AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy \
aws --endpoint-url=http://localhost:4566 \
    --region ap-northeast-1 \
    ses verify-email-identity \
    --email-address no-reply@keirekipro.click \
    || echo "SES identity already exists or failed."

# S3バケットを作成
echo "Checking and creating S3 bucket..."

if ! AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy \
    aws --endpoint-url=http://localhost:4566 \
        --region ap-northeast-1 \
        s3api head-bucket --bucket keirekipro-storage 2>/dev/null; then
    AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy \
    aws --endpoint-url=http://localhost:4566 \
        --region ap-northeast-1 \
        s3api create-bucket \
        --bucket keirekipro-storage \
        --create-bucket-configuration LocationConstraint=ap-northeast-1
    echo "S3 bucket created: keirekipro-storage"
else
    echo "S3 bucket already exists. Skipping."
fi
