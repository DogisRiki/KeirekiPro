## この guide の扱い

- この guide は Terraform と CI/CD の安全不変条件を書くものです。
- Docker/devcontainer と Playwright の手順は扱いません。
- workflow や Terraform の詳細仕様は、該当する実ファイルを正としてください。

## Terraform

- Terraform の正は `terraform/**/*.tf` と既存 module 境界に置いてください。
- 既存 resource name、module name、state key、provider alias、region、backend 設定を不用意に変更しないでください。
- `us-east-1` provider は CloudFront ACM / WAF など既存用途を確認して扱ってください。
- 既存 module 間の依存順序や circular dependency 回避コメントを尊重してください。
- secrets、credentials、`.tfvars`、state file、生成された plan file を commit しないでください。
- resource replacement、公開範囲拡大、権限拡大、production impact がある変更は報告してください。
- 新しい値を追加する場合は、variable、module input/output、workflow secret 注入、README 更新の必要性を確認してください。

## CI/CD

- workflow の正は `.github/workflows/*.yaml` に置き、guide に job/step を複製しないでください。
- trigger、paths filter、permissions、secrets、AWS role、region、deploy gate、artifact の変更は影響範囲を確認してください。
- PR での check と `main` push 後の deploy gate を弱めないでください。
- CI 成功を bypass する deploy trigger を追加しないでください。
- Terraform apply、backend deploy、frontend deploy の手動実行や trigger 変更は、明示依頼がある場合だけ扱ってください。
- workflow 変更後は、deploy 条件が意図せず広がっていないことを diff で確認してください。

## 完了前の確認

Terraform を変更した場合は順番に実行してください。

```bash
docker compose exec -w /workspace terraform terraform fmt -check -recursive
docker compose exec -w /workspace terraform terraform validate
docker compose exec -w /workspace terraform tflint --recursive
docker compose exec -w /workspace terraform checkov -d .
```
