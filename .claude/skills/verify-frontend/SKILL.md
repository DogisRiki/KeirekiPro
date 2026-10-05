---
description: frontendの品質ゲート(format→lint→typecheck→test→coverage)を順次実行し、結果を要約報告する。frontend配下を変更したら完了報告前に必ず実行する。
---

# verify-frontend

## Job

frontendの品質ゲートを規定の順序で直列実行し、PASS/FAILを判定する。ループの検証端点。

## Steps

以下を**この順で1つずつ**実行する(並列実行禁止)。途中で失敗したら、その失敗を修正してから**最初のコマンドからやり直す**。

```
bash .claude/scripts/parallel/run-check.sh frontend pnpm run format
bash .claude/scripts/parallel/run-check.sh frontend pnpm run lint
bash .claude/scripts/parallel/run-check.sh frontend pnpm run typecheck
bash .claude/scripts/parallel/run-check.sh frontend pnpm test
bash .claude/scripts/parallel/run-check.sh frontend pnpm run coverage
```

- `run-check.sh` は、いまの作業フォルダ(worktree のセッションでは worktree の最上位)を読み込んだ1回きりのコンテナで、コマンドを動かす。Claude は、起動したままの常駐コンテナの中で品質チェックを動かさない
- format失敗時は `pnpm run format:fix`、lint失敗時は `pnpm run lint:fix` で自動修正を先に試す。自動修正も `bash .claude/scripts/parallel/run-check.sh frontend pnpm run format:fix` のように `run-check.sh` で呼ぶ
- 単発のテストや検査(`npx vitest run <ファイル>` など)も、`bash .claude/scripts/parallel/run-check.sh frontend npx vitest run <ファイル>` のように `run-check.sh` で打つ
- vitestはテスト実行時に型を検査しない。型の誤りは `pnpm run typecheck`(`tsc -b`。CIの `pnpm run build` と同じ型検査)で検出する
- `pnpm run coverage` が終了コード0で終わったときだけ、`run-check.sh` が作業フォルダの `.claude/.state/gate-run-frontend.txt` に品質チェックが通った時刻を書く
- CI環境(Docker Compose無し)では `bash .claude/scripts/parallel/run-check.sh frontend` を外し `frontend/` でネイティブ実行する

## 順番待ちと検査できないとき

`run-check.sh` は、コマンドの終了コードをそのまま返す。ただし、次の3つの終了コードのときは、`run-check.sh` はコマンドを動かしていない。

- 終了コード10(枠が埋まっていて待たなかった): Claude は、出された `[parallel] 順番待ち:` の行(どのIssueのチェックを待つか)を所有者に伝え、同じコマンドに `--wait` を付けて(例 `bash .claude/scripts/parallel/run-check.sh --wait frontend pnpm run lint`)、Bash の `run_in_background` で呼び直す。Claude は、このときの Bash の `timeout` を、待ちの上限(1800秒)とそのコマンドの実行時間の和より長くする(目安は3600000ミリ秒)。`--wait` は、待ったあとに同じ呼び出しの中でコマンドを動かすので、`run_in_background` の既定の30分では足りない。呼び直した結果の終了コードを、そのコマンドの結果として扱う
- 終了コード69(検査の環境を用意できなかった): Claude は、そのコマンドを不合格として扱い、出された `[parallel] 検査できない:` の理由を所有者に報告する。コードを直しても解けないので、Claude は修正の繰り返しに入らない
- 終了コード75(待ちの上限に達した): Claude は、そのコマンドを不合格として扱い、どのIssueのチェックを待っていたか(出された `[parallel] 順番待ち:` の行)を所有者に報告する。Claude は修正の繰り返しに入らない

これら以外の0でない終了コードは、コマンドそのものの失敗である。Claude は、上の手順のとおり修正してからやり直す。

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
- typecheck -> PASS/FAIL
- test     -> PASS/FAIL (件数)
- coverage -> PASS/FAIL (Stmts/Branch/Funcs/Lines の各%)
```

FAILがある場合は、失敗ログの要点(ファイル・テスト名・エラー概要)と修正方針を添える。
