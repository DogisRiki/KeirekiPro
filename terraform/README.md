# Terraform 開発環境

## 概要

Terraformコードの開発・静的解析を行うためのdevcontainer環境。

## 含まれるツール

| ツール | バージョン | 用途 |
|--------|------------|------|
| Terraform | 1.14.3 | IaC 実行 |
| tflint | 0.60.0 | Terraform リンター |
| checkov | 最新 | セキュリティスキャナー |

## セットアップ

### AWS認証情報

このコンテナにはAWSの認証情報を渡さない。形式・構文・tflint・checkov の検査は認証情報を使わず、AWSへの操作(plan・apply)は GitHub Actions が OIDC で行う。

`terraform init` をやり直すときは、認証情報なしで初期化できる `terraform init -backend=false` を使う。

## フォーマット

### 自動フォーマット（推奨）

ファイル保存時（Ctrl+S）に自動でフォーマットが実行される。

VSCode 拡張機能「HashiCorp Terraform」により、以下が自動適用される。

- インデント: 2スペース
- `=` の位置揃え
- 末尾改行の挿入
- 末尾空白の削除

### 手動フォーマット
```bash
# チェックのみ（差分表示）
terraform fmt -check -diff

# フォーマット実行
terraform fmt
```

## 静的解析

### tflint

Terraformのベストプラクティス違反や非推奨構文を検出する。
```bash
tflint --config /root/.tflint.hcl
```

検出例:

- 未使用の変数・ローカル値
- 非推奨のリソース属性
- AWSリソースの設定ミス

### checkov

セキュリティ・コンプライアンス違反を検出する。
```bash
checkov -f <ファイル名>

# ディレクトリ全体をスキャン
checkov -d .
```

検出例:

- セキュリティグループの過剰な開放（0.0.0.0/0）
- S3バケットの暗号化・バージョニング未設定
- パブリックアクセスブロック未設定
