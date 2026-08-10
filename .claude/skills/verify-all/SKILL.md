---
description: 変更領域を判定して該当するverify(frontend/backend/terraform)を直列実行する。コミット・PR作成前の標準ゲート。
---

# verify-all

## Job

`git diff` から変更領域を判定し、該当する verify Skill を直列実行する。
コミット前・PR作成前(/ship)の標準ゲート。ゴールベースループ(/goal)の判定端点。

## Steps

1. 変更領域を判定する:

```
git status --porcelain
```

```
git diff --name-only origin/main...HEAD
```

   (未コミット変更とブランチ差分の両方を見る)

2. 変更されたパスに応じて、該当領域のverifyを**この順で直列**に実行する(並列実行禁止):
   - `frontend/` に変更あり → `/verify-frontend` の手順
   - `backend/` に変更あり → `/verify-backend` の手順
   - `terraform/` に変更あり → `/verify-terraform` の手順
   - 上記以外のみ(doc/.github等) → コマンド実行は不要。その旨を報告する

3. いずれかがFAILなら修正し、**修正した領域のverifyを最初から**やり直す。

## Rules

- 各verify Skillのゴールハック禁止則をすべて適用する
- 「時間がかかるから」という理由でcoverage/checkを省略しない(buildでの代替も不可)

## Report

```
verify-all(変更領域: frontend, backend):
- verify-frontend -> PASS/FAIL
- verify-backend  -> PASS/FAIL
- verify-terraform -> SKIP(変更なし)
```

各領域の詳細は該当verifyのReport形式に従って添える。
