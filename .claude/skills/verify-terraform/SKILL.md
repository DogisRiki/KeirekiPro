---
description: terraformの品質ゲート(fmt→validate→tflint→checkov)を順次実行し、結果を要約報告する。terraform配下を変更したら完了報告前に必ず実行する。
---

# verify-terraform

## Job

terraformの品質ゲートを規定の順序で直列実行し、PASS/FAILを判定する。ループの検証端点。

## Steps

以下を**この順で1つずつ**実行する(並列実行禁止)。

```
docker compose exec -w /workspace terraform terraform fmt -check -recursive
docker compose exec -w /workspace terraform terraform validate
docker compose exec -w /workspace terraform tflint --recursive
docker compose exec -w /workspace terraform checkov -d .
```

- fmtで差分が出たら `-check` を外して整形し、最初からやり直す

## Rules

- **`terraform apply` を実行しない**(applyは人間が手動実行するワークフローのみ。permissions/denyでもブロックされる)
- checkovの指摘を `.checkov.yaml` のskip追加で消さない。設定変更が必要なときは理由を添えて人間に提案する
- checkovが失敗したら、それは `terraform/.checkov.baseline` に無い新規の指摘なので直す。
  **baselineを作り直して消さない。** `.checkov.yaml` の `baseline:` が有効なまま
  `--create-baseline` を実行するとbaselineが空になり、凍結済みの既存指摘が
  すべて新規扱いに戻る。baselineの作り直しが必要なときは人間に提案する
- デプロイゲート・CI検証ステップを弱める変更をしない(`terraform/CLAUDE.md` の安全不変条件)

## Report

```
verify-terraform:
- fmt      -> PASS/FAIL
- validate -> PASS/FAIL
- tflint   -> PASS/FAIL (指摘数)
- checkov  -> PASS/FAIL (failed数)
```

FAILがある場合は、失敗ログの要点と修正方針を添える。
