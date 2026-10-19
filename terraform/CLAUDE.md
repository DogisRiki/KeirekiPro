# terraform ガイド(AWS IaC)

terraform配下・CI/CD(`.github/workflows/`)に関わる変更のとき常に適用する。

## 構成

| パス | 内容 |
|---|---|
| `modules/` | 再利用モジュール(VPC / ALB / ECS / RDS / CloudFront / WAF / SES 等) |
| `environments/` | 環境ごとのルートモジュール(本番のみ) |
| `keirekipro/` | アプリ固有の構成 |

## 安全不変条件(絶対に守る)

- **`terraform apply` をローカルで実行しない**。applyは人間が手動実行するワークフロー(terraform-apply.yaml)でのみ行う
- **PRで動くワークフローはAWSに接続しない**。PRで動く `terraform-plan.yaml` は静的検査だけを行い、
  AWSの権限も本番の秘密も持たない。本番の状態との差分(plan)は、承認が通ったあとに
  `terraform-apply.yaml` が適用の直前に出す。PRのジョブにAWSの認証や本番の秘密を足さない
- デプロイゲートを弱めない: release.yaml の手動トリガー構造、ブランチ保護のrequired checks、
  CI内の検証ステップを削除・緩和しない
- CIのbypass(`--no-verify`、requiredチェックのskip条件追加等)を仕込まない
- セキュリティ系リソース(WAF / IAM / SecurityGroup / Secrets)の権限を広げる変更は
  変更理由をPR本文に明記する
- ステートファイル・シークレット値をリポジトリに書かない

## 完了前コマンド(この順で直列実行)

```
bash .claude/scripts/parallel/run-check.sh terraform terraform fmt -check -recursive
bash .claude/scripts/parallel/run-check.sh terraform terraform validate
bash .claude/scripts/parallel/run-check.sh terraform tflint --recursive
bash .claude/scripts/parallel/run-check.sh terraform checkov -d .
```

fmtで差分が出た場合は `-check` を外して整形してから再実行する。
