---
description: terraformの品質ゲート(fmt→validate→tflint→checkov)を順次実行し、結果を要約報告する。terraform配下を変更したら完了報告前に必ず実行する。
---

# verify-terraform

## Job

terraformの品質ゲートを規定の順序で直列実行し、PASS/FAILを判定する。ループの検証端点。

## Steps

以下を**この順で1つずつ**実行する(並列実行禁止)。

```
bash .claude/scripts/parallel/run-check.sh terraform terraform fmt -check -recursive
bash .claude/scripts/parallel/run-check.sh terraform terraform validate
bash .claude/scripts/parallel/run-check.sh terraform tflint --recursive
bash .claude/scripts/parallel/run-check.sh terraform checkov -d .
```

- `run-check.sh` は、いまの作業フォルダ(worktree のセッションでは worktree の最上位)を読み込んだ1回きりのコンテナで、コマンドを動かす。Claude は、起動したままの常駐コンテナの中で品質チェックを動かさない
- 作業フォルダの `terraform/.terraform` が無ければ、`run-check.sh` が、コマンドの前に `terraform init -backend=false -input=false` を動かす
- fmtで差分が出たら `-check` を外して(`bash .claude/scripts/parallel/run-check.sh terraform terraform fmt -recursive`)整形し、最初からやり直す
- 単発の検査(`tflint --chdir=<ディレクトリ>` など)も、`bash .claude/scripts/parallel/run-check.sh terraform tflint --chdir=<ディレクトリ>` のように `run-check.sh` で打つ
- `checkov` で始まるコマンドが終了コード0で終わったときだけ、`run-check.sh` が作業フォルダの `.claude/.state/gate-run-terraform.txt` に品質チェックが通った時刻を書く
- CI環境では `bash .claude/scripts/parallel/run-check.sh terraform` を外し、`terraform/` でネイティブ実行する

## 順番待ちと検査できないとき

`run-check.sh` は、コマンドの終了コードをそのまま返す。ただし、次の3つの終了コードのときは、`run-check.sh` はコマンドを動かしていない。

- 終了コード10(枠が埋まっていて待たなかった): Claude は、出された `[parallel] 順番待ち:` の行(どのIssueのチェックを待つか)を所有者に伝え、同じコマンドに `--wait` を付けて(例 `bash .claude/scripts/parallel/run-check.sh --wait terraform checkov -d .`)、Bash の `run_in_background` で呼び直す。Claude は、このときの Bash の `timeout` を、待ちの上限(1800秒)とそのコマンドの実行時間の和より長くする(目安は3600000ミリ秒)。`--wait` は、待ったあとに同じ呼び出しの中でコマンドを動かすので、`run_in_background` の既定の30分では足りない。呼び直した結果の終了コードを、そのコマンドの結果として扱う
- 終了コード69(検査の環境を用意できなかった): Claude は、そのコマンドを不合格として扱い、出された `[parallel] 検査できない:` の理由を所有者に報告する。コードを直しても解けないので、Claude は修正の繰り返しに入らない
- 終了コード75(待ちの上限に達した): Claude は、そのコマンドを不合格として扱い、どのIssueのチェックを待っていたか(出された `[parallel] 順番待ち:` の行)を所有者に報告する。Claude は修正の繰り返しに入らない

これら以外の0でない終了コードは、コマンドそのものの失敗である。Claude は、上の手順のとおり修正してからやり直す。

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
