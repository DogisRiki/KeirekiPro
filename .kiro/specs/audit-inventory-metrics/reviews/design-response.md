# design 対応記録: audit-inventory-metrics

## サイクル1 往復1 への対応(2026-09-29)

| ID | 処置 | 内容 |
|---|---|---|
| D1-1-1 | 修正 | collect-coverage.sh の backend の成果物の中のパスを `reports/jacoco/test/jacocoTestReport.xml` に直し、成果物の根が2つのパスの共通の親 `backend/build/` になる理由を併記した |
| D1-1-2 | 記録のみ | 低。`tag_pattern` と別名の除外(`2026.08.4`)の食い違いは、tasks で正規表現を `^[0-9]{4}\.[1-9][0-9]?\.[0-9]+$`(月の先頭の0を許さない)にして揃える |
| D1-1-3 | 記録のみ | 低。ラベルの作成は台帳の作成に付随する操作として扱う(audit-issue.sh と同じ)。tasks で明記する |
| D1-1-4 | 記録のみ | 低。成果物の探し方は tasks で `--paginate` にする |
| D1-1-5 | 記録のみ | 低。collect-coverage.sh の失敗時もコメントは「取得できず」で続ける扱いを tasks で決める |
| D1-1-6 | 記録のみ | 低。tflint の FROM 行に digest を付けるかは tasks で決める(Dependabot は digest 付きの行も更新する) |

## サイクル1 往復2 への対応(2026-09-29)

収束(高0 中0)。本文は直していない。

| ID | 処置 | 内容 |
|---|---|---|
| D1-2-1 | 記録のみ | 低。成果物はあるが中にカバレッジのファイルが無い場合(main でテストが失敗した run)は、tasks で「取得できず(成果物にカバレッジのファイルが無い)」とし、それより古い成果物は探さない扱いにする |

## 要件の改訂に合わせた再生成(2026-09-29)

サイクル1の収束後、requirements の要件4に4-5の追記と4-6〜4-9 が加わり(所有者の判断。requirements のサイクル3で収束し、所有者が承認)、design を合わせて直した。サイクル2でレビューする。

- `check-release-age.sh` と `dependabot-auto-merge.yaml` の変更(PR のイベントでの判定と、1日1回の見直しの `recheck` job)を足した。System Flows・Requirements Traceability(4.6〜4.9)・Components・Testing Strategy・Security Considerations を合わせて直した
- tflint の `FROM` 行を digest でも固定する形にした(要件4-5。D1-1-6 の扱いもこれで決まった)
- Security Considerations の「クールダウンが効かないことを残余リスクとして受け入れる」を、72時間の保留に置き換えた。残るのは「1日1回の見直しが止まると、保留したPRが開いたまま残る」こと
- サイクル1で記録のみとした低の指摘のうち、D1-1-2(`tag_pattern` を `^[0-9]{4}\.[1-9][0-9]?\.[0-9]+$` に)、D1-1-4(成果物の探し方に `--paginate`)、D1-1-5(collect-coverage.sh の失敗で記録を止めない)、D1-2-1(成果物にカバレッジのファイルが無いときの扱い)を、再生成にあわせて本文に反映した
- research.md の tflint の決定を、72時間の保留に書き換えた

## サイクル2 往復1 への対応(2026-09-29)

収束(高0 中0)。本文は直していない。

| ID | 処置 | 内容 |
|---|---|---|
| D2-1-1 | 記録のみ | 低。recheck は Dependabot の全PRを列挙するが、tflint 以外は `reserve` になるため、予約が一時的に付かなかったPRの付け直しにもなる。tasks で Out of Boundary の文言と揃える |
| D2-1-2 | 記録のみ | 低。tasks で安全側に倒す: 差分に対象のイメージの `FROM` 行があるのにタグや digest を読み取れないときは `notify`(理由「差分を読み取れない」)にする |
| D2-1-3 | 記録のみ | 低。tasks で `gh pr list` に `--limit` を十分な値で指定する |
| D2-1-4 | 記録のみ | 低。tasks で、digest は Dependabot が書く形(マルチアーキテクチャのイメージでは manifest list の digest)に合わせ、実装時に ghcr.io から取る |
| D2-1-5 | 記録のみ | 低。tasks で research.md の `tag_pattern` を design と揃える |
| D2-1-6 | 記録のみ | 低。tasks の Integration の確認の文言を、exit 2 のときの他のPRの扱いを含めて書く |
