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

GitHub Actions用IAMロールはAWSコンソールから手動で作成・管理する。Terraformでは管理しない。

**用途ごとに2本に分かれている。** 構築とデプロイの権限を持つロールは、mainブランチで production environment を経由したジョブだけが引き受けられる。production environment は承認者の承認が通るまでジョブを始めない。PRで動くジョブが引き受けられるロールは無い。理由は 3.5 に書く。

### 3.1 ロール設計

いずれも信頼されたエンティティは `token.actions.githubusercontent.com`（OIDC）。

| ロール名 | 用途 | 引き受けられる条件 |
|------|------|------|
| keirekipro-github-actions-role | 本番デプロイ、Terraform Apply | mainブランチで production environment を経由するジョブのみ |
| keirekipro-github-actions-scan-role | 週次のコンテナイメージ監視 | mainブランチのみ |

### 3.2 アタッチポリシー

| ロール名 | ポリシー名 | 種別 |
|------|-----------|------|
| keirekipro-github-actions-role | keirekipro-github-actions-policy | カスタム |
| keirekipro-github-actions-scan-role | keirekipro-container-scan-read | インライン |

**`keirekipro-container-scan-read`** は `ecs:DescribeServices` / `ecs:DescribeTaskDefinition`、`ecr:GetAuthorizationToken`、および `keirekipro-backend` からの取得（`ecr:BatchGetImage` / `GetDownloadUrlForLayer` / `BatchCheckLayerAvailability`）だけを持つ。

### 3.3 カスタムポリシー: keirekipro-github-actions-policy

> **この節に書いてあるのは設計上の最小権限であり、実物はこれより広い。** 2026-08-21 に実物を確認したところ、構築に必要な権限をまとめた Statement が含まれており、この文書の記述と一致していなかった。ロールがコード管理外のため、差が生じても機械では気づけない。
>
> **権限の実物はコンソールで確認する。** 被害範囲をそのまま公開しないため、ここには書かない。
>
> ```bash
> aws iam get-policy-version --policy-arn <ポリシーARN> >   --version-id $(aws iam get-policy --policy-arn <ポリシーARN> --query 'Policy.DefaultVersionId' --output text) >   --query 'PolicyVersion.Document'
> ```
>
> 最小権限へ寄せる作業は未着手。このロールを引き受けられるのは main からのみのため、緊急度は下がっている。


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

用途ごとにStatementを分け、引き受けられる条件を絞る。

| ロール | Statement | 条件 |
|---|---|---|
| keirekipro-github-actions-role | DeployFromMainProductionEnvironment | mainブランチで production environment を経由するジョブ（本番デプロイ、Terraform Apply） |
| keirekipro-github-actions-scan-role | ContainerScanFromMain | `repo:ORG/REPO:ref:refs/heads/main` |

`keirekipro-github-actions-role` の信頼ポリシーは、Statementを1つだけ持つ。

条件の組み立てには2つの制約がある。

1. **全Statementに `sub` が必要**。GitHubのOIDCプロバイダーを信頼するロールでは、IAMが
   信頼ポリシーの保存時に `token.actions.githubusercontent.com:sub` の存在を検査する。
   無い場合、またはワイルドカードだけの場合は保存が失敗する
   ([Create a role for OpenID Connect federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html))
2. **`sub` だけでは「mainブランチかつproduction環境」を表せない**。environmentを指定した
   ジョブの `sub` は `repo:ORG/REPO:environment:production` になり、refの情報が失われる

そのため、`sub` に `ref` を併用する。AWSはGitHubのOIDCトークンの
`repository` `ref` `environment` などを個別の条件キーとして扱える
([IAM and AWS STS condition context keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html)
の「Available keys for AWS OIDC federation」→ GitHubタブ)。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DeployFromMainProductionEnvironment",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:production",
          "token.actions.githubusercontent.com:ref": "refs/heads/main"
        }
      }
    }
  ]
}
```

`ref` 条件が、`sub` では表せない「mainブランチであること」を補う。
ワークフローから `environment: production` の行を消した実行は `sub` が
`repo:ORG/REPO:ref:refs/heads/main` になり、このStatementに一致しない。

### 3.5 構築の権限を承認の後ろに置く理由

**`pull_request` から引き受ける経路は、ブランチで絞れない。** GitHubのOIDCトークンの `sub` は、`pull_request` イベントでは `repo:ORG/REPO:pull_request` になり、**どのブランチのPRかという情報を持たない**（3.4 の制約2と同じ性質）。書き忘れではなく、条件として書けない。PRで動くジョブは、まだ承認されていないコードを動かす。

そのため、PRで動くジョブが引き受けられるロールを置かない。参照専用のロールも置かない。Planは状態ファイルと秘密の値を読むためである。PRでは本番のAWSに接続しない静的検査（terraform-plan.yaml の terraform-static）だけを行い、本番の状態との差分は、terraform-apply.yaml が承認のあと、適用の直前に出す。

**mainブランチであることだけを条件にしない。** mainで動くジョブには、承認を経ずに動くもの（定期実行など）もある。構築の権限は、production environment を経由し、承認者の承認が通ったジョブだけに渡す。本番の秘密（`TF_VAR_` で始まる値）も production environment の secrets に置き、同じ承認が通ったジョブだけに渡す。

## 4. OIDCプロバイダー設定

OIDCプロバイダーはAWSコンソールから手動で作成・管理する。Terraformでは管理しない。

| 項目 | 設定値 |
|------|--------|
| プロバイダーURL | https://token.actions.githubusercontent.com |
| 対象者（Audience） | sts.amazonaws.com |

## 5. Terraformバックエンド用IAMポリシー

### 5.1 ポリシー設計

| 項目 | 設定値 |
|------|--------|
| ポリシー名 | keirekipro-terraform-backend-policy |
| 用途 | Terraform状態管理 |

### 5.2 ポリシー定義

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

## 6. 開発者のIAMユーザーと変更用のロール

開発者のPCの `aws login` の認証情報は、その開発者のPCで動くプログラムからも使える。そのため、開発者のIAMユーザーには読む権限だけを持たせ、AWSを変えるときだけ、MFAのコードを入れて変更用のロールに切り替える。作り方は `doc/インフラ設計/手順書/手動作業手順.md` の 1.2 にある。

### 6.1 開発者のグループ

| 項目 | 設定値 |
|------|--------|
| グループ名 | keirekipro-developers |
| AWS管理ポリシー | ReadOnlyAccess、SignInLocalDevelopmentAccess |
| インラインポリシー | keirekipro-developers-inline |

インラインポリシーは、変更用のロールへの切り替えを許し、状態ファイルの読み取り(過去の版を含む)を拒否する。状態ファイルには本番の秘密の値が入るためである。`ReadOnlyAccess` は `secretsmanager:GetSecretValue` を含まないので、Secrets Manager の秘密の値も読めない。そのため、開発者は手元で `terraform plan` や `terraform state` を動かせない。

`ReadOnlyAccess` で読めるものには、次も含まれる。

- X-Origin-Verify の値(CloudFront のオリジンのヘッダーと ALB のリスナールールに入る)。CloudFront を通らずに ALB へ届く通信を止める用途の値で、差し替えは apply で行う
- アラートの通知先のメールアドレス(SNS の購読)と、CloudWatch Logs のログの本文
- 利用者がアップロードした画像(`keirekipro-storage` のバケットの中身)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SwitchToAdminRole",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/keirekipro-admin-role"
    },
    {
      "Sid": "DenyReadingTerraformState",
      "Effect": "Deny",
      "Action": ["s3:GetObject", "s3:GetObjectVersion"],
      "Resource": "arn:aws:s3:::keirekipro-terraform-state/*"
    }
  ]
}
```

### 6.2 変更用のロール

| 項目 | 設定値 |
|------|--------|
| ロール名 | keirekipro-admin-role |
| AWS管理ポリシー | AdministratorAccess |
| 最大セッション時間 | 1時間 |

信頼ポリシーは、MFAで認証してから60秒以内の引き受けだけを許す。切り替えのたびに6桁のコードを入れさせ、ログインしたままのPCの認証情報だけでは切り替えられないようにするためである。切り替えた認証情報は、有効期限(1時間)までそのPCで使える。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DevelopersWithFreshMfa",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "Bool": { "aws:MultiFactorAuthPresent": "true" },
        "NumericLessThan": { "aws:MultiFactorAuthAge": "60" }
      }
    }
  ]
}
```
