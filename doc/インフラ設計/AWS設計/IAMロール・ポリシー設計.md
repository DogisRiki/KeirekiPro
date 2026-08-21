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

**用途ごとに3本に分かれている（2026-08-21、Issue #222）。** 以前は1本が構築・デプロイ・Plan・週次監視を兼ねていたが、`pull_request` から引き受けられる経路に構築権限が付いた状態だったため分割した。分割の理由は 3.5 に書く。

### 3.1 ロール設計

いずれも信頼されたエンティティは `token.actions.githubusercontent.com`（OIDC）。

| ロール名 | 用途 | 引き受けられる条件 |
|------|------|------|
| keirekipro-github-actions-role | 本番デプロイ、Terraform Apply | mainブランチのみ |
| keirekipro-github-actions-plan-role | PRでのTerraform Plan | プルリクエストで動くジョブ |
| keirekipro-github-actions-scan-role | 週次のコンテナイメージ監視 | mainブランチのみ |

### 3.2 アタッチポリシー

| ロール名 | ポリシー名 | 種別 |
|------|-----------|------|
| keirekipro-github-actions-role | keirekipro-github-actions-policy | カスタム |
| keirekipro-github-actions-plan-role | ReadOnlyAccess | AWS管理 |
| keirekipro-github-actions-plan-role | keirekipro-terraform-plan-support | インライン |
| keirekipro-github-actions-scan-role | keirekipro-container-scan-read | インライン |

**`keirekipro-terraform-plan-support`** は、`ReadOnlyAccess` に無い2つを補う。状態ファイルのロックに要る `dynamodb:GetItem` / `PutItem` / `DeleteItem`（`keirekipro-terraform-lock` のみ）と、`secretsmanager:GetSecretValue`（`keirekipro/*` のみ）。

後者が要るのは、この構成が `aws_secretsmanager_secret_version` を**リソースとして管理**しており、Planの段階で現在の値の取得が発生するため。無いとPlanが `AccessDeniedException` で落ちる（2026-08-21 実測）。なお `ReadOnlyAccess` は状態ファイルの置き場（S3）の読み取りを許しており、状態ファイルには同じ値が保存されているため、ここを絞っても秘密情報の露出は変わらない。

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

`keirekipro-github-actions-role` の信頼ポリシーには2つのStatementがある。

| Statement | 用途 | 条件 |
|---|---|---|
| DeployFromMainProductionEnvironment | backend / frontend の本番デプロイ | mainブランチ、かつ production 環境を経由するジョブ |
| TerraformApplyFromMain | 手動のTerraform Apply | mainブランチで動くジョブ |

**`TerraformPlanOnPullRequest` は 2026-08-21 に削除した。** PRでのPlanは `keirekipro-github-actions-plan-role` が引き受ける。理由は 3.5 に書く。

参照専用の2本の信頼ポリシーは、それぞれStatementが1つだけ。

| ロール | Statement | `sub` の条件 |
|---|---|---|
| keirekipro-github-actions-plan-role | TerraformPlanOnPullRequest | `repo:ORG/REPO:pull_request` |
| keirekipro-github-actions-scan-role | ContainerScanFromMain | `repo:ORG/REPO:ref:refs/heads/main` |

条件の組み立てには2つの制約がある。

1. **全Statementに `sub` が必要**。GitHubのOIDCプロバイダーを信頼するロールでは、IAMが
   信頼ポリシーの保存時に `token.actions.githubusercontent.com:sub` の存在を検査する。
   無い場合、またはワイルドカードだけの場合は保存が失敗する
   ([Create a role for OpenID Connect federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html))
2. **`sub` だけでは「mainブランチかつproduction環境」を表せない**。environmentを指定した
   ジョブの `sub` は `repo:ORG/REPO:environment:production` になり、refの情報が失われる

そのため、デプロイ用のStatementでは `sub` に `ref` を併用する。AWSはGitHubのOIDCトークンの
`repository` `ref` `environment` などを個別の条件キーとして扱える
([IAM and AWS STS condition context keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html)
の「Available keys for AWS OIDC federation」→ GitHubタブ)。

Terraformの2つのStatementは `sub` だけで絞る。ワークフローを限定する `job_workflow_ref` は
再利用可能ワークフローを使うジョブにしか含まれないクレームであり、直接起動する
terraform-plan.yaml と terraform-apply.yaml のジョブでは条件が一致しない
([OIDC claims](https://docs.github.com/en/actions/reference/security/oidc))。
`workflow_ref` はAWSの条件キーとして提供されていないため代替にできない。

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
    },
    {
      "Sid": "TerraformApplyFromMain",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

1つ目のStatementの `ref` 条件が、`sub` では表せない「mainブランチであること」を補う。
ワークフローから `environment: production` の行を消した実行は `sub` が
`repo:ORG/REPO:ref:refs/heads/main` になり、1つ目のStatementに一致しない。

### 3.5 用途ごとに分けている理由

**`pull_request` から引き受ける経路は、ブランチで絞れない。** GitHubのOIDCトークンの `sub` は、`pull_request` イベントでは `repo:ORG/REPO:pull_request` になり、**どのブランチのPRかという情報を持たない**（3.4 の制約2と同じ性質）。書き忘れではなく、条件として書けない。

このため、1本のロールが構築権限を持ったまま `pull_request` を信頼していると、**リポジトリにブランチをpushできる者が、PRを出した時点で構築権限を持つジョブを動かせる。** CODEOWNERSはマージを止めるが、PRで動くワークフローの実行は止めない。

分割後は、`pull_request` から引き受けられるのが参照専用の `keirekipro-github-actions-plan-role` だけになる。構築権限を持つロールは main からしか引き受けられず、mainへの変更には所有者の承認が要る。

**残る露出は読み取りである。** Planは状態ファイルと秘密情報を読む必要があり（3.2 参照）、そこは分割しても塞がらない。塞がるのは作成・変更・削除の側。

| 操作 | plan-role での判定（2026-08-21 実測） |
|---|---|
| iam:CreateUser / iam:AttachRolePolicy | implicitDeny |
| ec2:TerminateInstances / rds:DeleteDBInstance | implicitDeny |
| ecs:UpdateService / ecr:PutImage / s3:DeleteObject | implicitDeny |
| secretsmanager:GetSecretValue（`keirekipro/*`） | allowed（Planに必要） |

確認は `aws iam simulate-principal-policy` で行う。

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
