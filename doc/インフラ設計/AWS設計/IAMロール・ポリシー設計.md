# IAMロール・ポリシー設計書

## 1. ECSタスク実行ロール

### 1.1 ロール設計

| 項目 | 設定値 |
|------|--------|
| ロール名 | keirekipro-ecs-task-execution-role |
| 信頼されたエンティティ | ecs-tasks.amazonaws.com |

### 1.2 アタッチポリシー

| ポリシー名 | 種別 | 用途 |
|-----------|------|------|
| AmazonECSTaskExecutionRolePolicy | AWS管理 | ECS基本実行権限 |
| keirekipro-ecs-secrets-policy | カスタム | Secrets Manager読み取り |

### 1.3 カスタムポリシー: keirekipro-ecs-secrets-policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GetSecrets",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:ap-northeast-1:${AWS_ACCOUNT_ID}:secret:keirekipro/*"
    }
  ]
}
```

### 1.4 信頼ポリシー

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

## 2. ECSタスクロール

### 2.1 ロール設計

| 項目 | 設定値 |
|------|--------|
| ロール名 | keirekipro-ecs-task-role |
| 信頼されたエンティティ | ecs-tasks.amazonaws.com |

### 2.2 アタッチポリシー

| ポリシー名 | 種別 | 用途 |
|-----------|------|------|
| keirekipro-app-secrets-policy | カスタム | アプリからのSecrets Manager読み取り |
| keirekipro-s3-policy | カスタム | S3操作 |
| keirekipro-ses-policy | カスタム | メール送信 |

### 2.3 カスタムポリシー: keirekipro-app-secrets-policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GetSecrets",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:ap-northeast-1:${AWS_ACCOUNT_ID}:secret:keirekipro/*"
    }
  ]
}
```

### 2.4 カスタムポリシー: keirekipro-s3-policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ObjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::keirekipro-storage/*"
    }
  ]
}
```

### 2.5 カスタムポリシー: keirekipro-ses-policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SESSendEmail",
      "Effect": "Allow",
      "Action": "ses:SendEmail",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ses:FromAddress": "info@keirekipro.click"
        }
      }
    }
  ]
}
```

### 2.6 信頼ポリシー

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

## 3. GitHub Actions用IAMロール（OIDC連携）

### 3.1 ロール設計

| 項目 | 設定値 |
|------|--------|
| ロール名 | keirekipro-github-actions-role |
| 信頼されたエンティティ | token.actions.githubusercontent.com（OIDC） |

### 3.2 アタッチポリシー

| ポリシー名 | 種別 | 用途 |
|-----------|------|------|
| keirekipro-github-actions-policy | カスタム | CI/CDに必要な権限 |

### 3.3 カスタムポリシー: keirekipro-github-actions-policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAuth",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "ECRPush",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
      "Resource": "arn:aws:ecr:ap-northeast-1:${AWS_ACCOUNT_ID}:repository/keirekipro-backend"
    },
    {
      "Sid": "ECSDeployment",
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:RegisterTaskDefinition"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/keirekipro-ecs-task-execution-role",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/keirekipro-ecs-task-role"
      ]
    },
    {
      "Sid": "S3FrontendDeploy",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::keirekipro-frontend",
        "arn:aws:s3:::keirekipro-frontend/*"
      ]
    },
    {
      "Sid": "CloudFrontInvalidation",
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/*"
    }
  ]
}
```

### 3.4 信頼ポリシー

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
```

## 4. Terraformバックエンド用IAMポリシー

### 4.1 ポリシー設計

| 項目 | 設定値 |
|------|--------|
| ポリシー名 | keirekipro-terraform-backend-policy |
| 用途 | Terraform状態管理 |

### 4.2 ポリシー定義

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformS3Backend",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::keirekipro-terraform-state",
        "arn:aws:s3:::keirekipro-terraform-state/*"
      ]
    },
    {
      "Sid": "TerraformDynamoDBLock",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:ap-northeast-1:${AWS_ACCOUNT_ID}:table/keirekipro-terraform-lock"
    }
  ]
}
```

## 5. OIDCプロバイダー設定

| 項目 | 設定値 |
|------|--------|
| プロバイダーURL | https://token.actions.githubusercontent.com |
| 対象者（Audience） | sts.amazonaws.com |
