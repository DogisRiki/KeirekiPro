---
description: frontendの品質ゲート(format→lint→test→coverage)を順次実行し、結果を要約報告する。frontend配下を変更したら完了報告前に必ず実行する。
---

# verify-frontend

## Job

frontendの品質ゲートを規定の順序で直列実行し、PASS/FAILを判定する。ループの検証端点。

## Steps

以下を**この順で1つずつ**実行する(並列実行禁止)。途中で失敗したら、その失敗を修正してから**最初のコマンドからやり直す**。

```
docker compose exec -u node -w /home/node/app frontend pnpm run format
docker compose exec -u node -w /home/node/app frontend pnpm run lint
docker compose exec -u node -w /home/node/app frontend pnpm test
docker compose exec -u node -w /home/node/app frontend pnpm run coverage
```

- format失敗時は `pnpm run format:fix`、lint失敗時は `pnpm run lint:fix` で自動修正を先に試す
- CI環境(Docker Compose無し)では `docker compose exec ...` を外し `frontend/` でネイティブ実行する

## Rules(ゴールハック禁止則)

「見かけの合格」を作る次の行為を**絶対に行わない**(escape-hatch CIも機械検知する):

- テストへの `.skip` / `.only` / `xit` / `xdescribe` の追加
- 既存テストのアサーション削除・弱体化(意図的な変更はPR本文に `Test-Change-Justification:` を記載)
- `@ts-ignore` / `@ts-expect-error` / インライン `eslint-disable` の追加
- `vite.config.ts` のカバレッジ閾値・`eslint.config.js` のルールの変更(CODEOWNERS保護対象)
- カバレッジ不足を「テスト対象の削除」で解消すること

カバレッジ閾値に届かない場合は、**テストを追加して**満たす。
新規テストは対象コードを一時的に壊して赤くなることを確認してから戻す。

## Report

```
verify-frontend:
- format   -> PASS/FAIL
- lint     -> PASS/FAIL
- test     -> PASS/FAIL (件数)
- coverage -> PASS/FAIL (Stmts/Branch/Funcs/Lines の各%)
```

FAILがある場合は、失敗ログの要点(ファイル・テスト名・エラー概要)と修正方針を添える。
