# tasks のレビューへの対応

## サイクル1 往復1 への対応(2026-11-08)

- レビュー役のモデル: Fable 5.1
- レビュー役が使った量: 211988 トークン
- 審査の範囲: 全体

| ID | 処置 | 内容 |
|---|---|---|
| T1-1-1 | 修正 | `.github/workflows/terraform-plan.yaml` が `terraform plan` を動かさないことを確かめた(fmt・validate・tflint・checkov だけ)。タスク6.1と11.1の確かめ方を、`git diff origin/main -- terraform/` の差分と、所有者が `plan_only` を付けて動かした `terraform-apply.yaml` の「Terraform Plan (差分の事前表示)」の記録を Claude が `gh run view --log` で読む形に替えた。PR の本文に plan で変わるはずの資源と値を書くことも足した |
| T1-1-2 | 修正 | 直し方の案の (b) を採った。タスク1.10で `backend/api/openapi.yaml` を `.kiro/specs/backend-go-replacement/openapi.yaml` に移して PR 2-1 に入れ、タスク2.2で `git mv` で `backend/api/` に戻す形にした。退避用のブランチ (a) より、PR の差分に残り、所有者が中身を見られるため |
| T1-1-3 | 記録のみ | `_対象の部品:_` の名前の指摘。並行の衝突は無く、触るファイルは本文に書いてある |
| T1-1-4 | 記録のみ | 「4つのステップ」の数え方の指摘。実装のときに design.md の同じ語と照らせば決まる |
| T1-1-5 | 記録のみ | まとまりから操作への対応の読み方の指摘。大タスク3の実装で、progress.md か仕様書の `tags` のどちらかに決める |
| T1-1-6 | 記録のみ | design の「CI の仕事」の見分けと同じ形であり、design どおり。筋書きだけを変える会話の確認は、`make compat` を流すタスクの確かめ方で補われる |
| T1-1-7 | 記録のみ | 実装のメモの「PR の本文」の共通の決まりで2つの欄は書かれる。確かめ方の書きそろえの指摘 |
| T1-1-8 | 所有者判断待ち | design への指摘。design の「段階ごとの PR」の表の 4-1 と、「段階6の削除と書き換え」の表の 6-2 が所有者の承認を「要る」とするが、`terraform/main.tf` と `terraform/modules/` は CODEOWNERS の対象でなく、2つの PR は承認なしに自動で main に入る。spec-review の Step 6 のとおり往復を止め、所有者に尋ねる |

## サイクル2 往復1 への対応(2026-11-08)

- レビュー役のモデル: Fable 5.1
- レビュー役が使った量: 186233 トークン
- 審査の範囲: 前回からの差分

| ID | 処置 | 内容 |
|---|---|---|
| T2-1-1 | 記録のみ | 低の指摘。T2-1-2 の直しで design.md のフックの見分け方に `backend/go.mod` の条件を含むと書くので、タスク1.2 の「同じ形」は条件を含む形に読みが決まる |
| T2-1-2 | 修正 | design.md への指摘。条件は Claude が design に足したものなので、design.md の 6-1 の一覧に6つ目として足し、フックの見分け方の箇条に条件を含むことを書いた。design は未承認のまま、`/spec-review backend-go-replacement design changed` で審査し直す |
