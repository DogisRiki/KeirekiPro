# Implementation Plan

> **成果物の渡し方**: `.github/` と `.claude/` はエージェントが書き込めないため、各タスクの
> 成果物は「配置用のファイル一式または実行コマンド」として人間に渡す。
>
> **verify Skill**: frontend / backend / terraform のいずれにも該当しないため、本specの検証は
> `actionlint` と `shellcheck v0.11.0`(CIと同じイメージ)で行う。
>
> **acceptance criteria とテストの対応付け**: 本specはワークフロー設定の変更であり、
> 単体テストで検証できる受け入れ基準を持たない。受け入れ基準の検証は 4.x の実地確認で行う。
>
> **2.x の完了条件について**: merge_group の実挙動はキューが有効になる 4.2 まで観測できない。
> 2.x の完了条件は作成時に検証できる静的条件に限り、実挙動の確認は 4.2 と 4.3 が担う。

- [ ] 1. 準備
- [x] 1.1 基盤構築手順に人間の設定作業を書く
  - ブランチ保護の設定表と必須チェックの一覧を切り替え後の実態に合わせる
  - 既存のずれ2点を解消する(`Require branches to be up to date` の記載、
    必須チェック一覧が15本)
  - 人間が実施する設定作業(merge queue の有効化、squash、タイムアウト60分、
    `up to date` を戻さない、Dependabot secrets への鍵登録と権限)を明示する
  - **このタスクを最初に行う。** 人間が鍵を登録できるようになるまで 4.1 に進めない
  - 完了条件: 記載された必須チェックが18本で Rulesets API の出力と一致し、
    鍵の登録手順を読んだ人間が作業を開始できる
  - _Requirements: 5.1, 5.6, 6.4, 6.5, 6.6_
  - _Boundary: 基盤構築手順.md_

- [x] 1.2 必須チェック一覧と対照表を突き合わせる
  - `gh api repos/:owner/:repo/rulesets/2986186` の `required_status_checks` を取得する
  - design.md の群の割り付け表と、名前・件数の両方が一致することを確認する
  - design.md の「群2の引き継ぎ理由」表に、群2の7本すべてについて再実行できない理由と
    残余リスクが記載されていることを確認する
  - 一致しない場合は design.md を先に直す
  - 完了条件: 18本すべてが群1(8) / 群2(7) / 群3(3)のいずれかに一意に割り当てられ、
    API の出力と差分が無いことを示せる
  - _Requirements: 1.2, 1.3, 3.4_

- [ ] 2. ワークフローの merge_group 対応
- [x] 2.1 ci.yaml を対応させる (P)
  - `on:` に `merge_group: types: [checks_requested]` を追加する
  - `paths-filter` は `merge_group` をネイティブに扱うため入力の追加は不要
  - concurrency は既に `|| github.run_id` のフォールバックを持つため変更しない
  - merge_group で実行されるジョブの `permissions` を明示する
  - 完了条件: `actionlint` がPASSし、`merge_group` トリガが追加され、
    concurrency と既存ジョブの条件式に変更が無い
  - _Requirements: 1.1, 2.1, 2.2, 5.3_
  - _Boundary: ci.yaml_

- [x] 2.2 terraform-plan.yaml を対応させる (P)
  - `on:` に `merge_group` を追加する
  - `terraform-plan` ジョブ(非必須)に `github.event_name != 'merge_group'` を付ける
  - 完了条件: `actionlint` がPASSし、`terraform-plan` ジョブにのみ merge_group 除外が付き、
    `detect-terraform-changes` と `terraform-static` には付いていない
  - _Requirements: 1.1, 2.1, 2.2_
  - _Boundary: terraform-plan.yaml_

- [x] 2.3 guardrails.yaml を対応させる (P)
  - `on:` に `merge_group` を追加する
  - `gradle-wrapper`(群1)は base/head を `merge_group` の値へ切り替える
  - `escape-hatch` `size-check`(群2)に `!= 'merge_group'` を足す。
    **既存の `pull_request_review` での発火条件は保持する**
  - `gitleaks` は既存の `== 'pull_request'` が merge_group を除外済みのため変更しない
  - concurrency に `|| github.run_id` のフォールバックを足す
  - merge_group で実行されるジョブの permissions が明示済みであることを確認する
  - 完了条件: `actionlint` がPASSし、`pull_request_review` のトリガと発火条件が
    ファイル上に残っており、`gradle-wrapper` の base/head が merge_group の値を
    参照している
  - _Requirements: 1.1, 2.1, 3.1, 3.2, 5.2, 5.3, 5.5_
  - _Boundary: guardrails.yaml_

- [x] 2.4 dependency-gate.yaml を対応させる (P)
  - `on:` に `merge_group` を追加し、ジョブに `!= 'merge_group'` を足す
  - `pull_request_review` の発火条件を保持する
  - concurrency にフォールバックを足す
  - 完了条件: `actionlint` がPASSし、ジョブの `if:` に `!= 'merge_group'` が
    既存の条件を保持したまま追加されている
  - _Requirements: 1.1, 3.1, 3.2, 5.2, 5.5_
  - _Boundary: dependency-gate.yaml_

- [x] 2.5 pre-merge-check.yaml を対応させる (P)
  - 2.4 と同じ形
  - 完了条件: `actionlint` がPASSし、ジョブの `if:` に `!= 'merge_group'` が
    既存の条件を保持したまま追加されている
  - _Requirements: 1.1, 3.1, 3.2, 5.2, 5.5_
  - _Boundary: pre-merge-check.yaml_

- [x] 2.6 codex-review.yml を対応させる (P)
  - `on:` に `merge_group` を追加し、ジョブに `!= 'merge_group'` を**明示的に**足す
  - `draft == false` は merge_group で `null == false` が true になるため、
    このガードが無いとジョブが実行されてキューを塞ぐ
  - concurrency にフォールバックを足す
  - 完了条件: `actionlint` がPASSし、`if:` の先頭に `github.event_name != 'merge_group'`
    が独立した条件として存在する
  - _Requirements: 1.1, 3.1, 3.2, 5.2_
  - _Boundary: codex-review.yml_

- [x] 2.7 dependency-review.yaml を対応させる (P)
  - `on:` に `merge_group` を追加する
  - submit の fork 判定を `github.event_name == 'merge_group' || 既存条件` に書き換える
  - cooldown に `github.event_name == 'pull_request'` を足す(群2)
  - `retry-on-snapshot-warnings-timeout: 600` を明示する
  - concurrency にフォールバックを足す
  - merge_group で実行されるジョブの permissions が明示済みであることを確認する
  - 完了条件: `actionlint` がPASSし、submit の `if:` が merge_group で真になる形になり、
    cooldown が `pull_request` に限定されている
  - _Requirements: 1.1, 4.1, 4.2, 4.3, 5.2, 5.3_
  - _Boundary: dependency-review.yaml_

- [x] 2.8 dependabot-auto-merge.yaml のトークンを切り替える (P)
  - `GH_TOKEN` を `secrets.BOT_GITHUB_TOKEN` にする
  - `--squash` は残す(キュー無効時に非対話でエラーになるため)
  - 完了条件: `actionlint` がPASSし、`GH_TOKEN` が `secrets.BOT_GITHUB_TOKEN` を
    参照し、`--squash` が残っている
  - _Requirements: 5.4_
  - _Boundary: dependabot-auto-merge.yaml_

- [ ] 3. 文書の更新
- [x] 3.1 監査手順を更新する (P)
  - 週次項目6の「Update branch を押す」を削除する
  - キューが詰まった場合の手順を追加する(Remove from queue、gh CLIでは取り出せない、
    キュー無効化後は `gh pr merge --auto --squash` で予約し直す)
  - カナリアPRがキューに入らないことを1行記載する
  - `--squash` の警告が無害であることを1行記載する
  - 完了条件: 削除対象の記述が残っておらず、キューが詰まった場合の手順が読める
  - _Requirements: 6.1, 6.3_
  - _Boundary: 監査手順.md_

- [x] 3.2 README を更新する (P)
  - ワークフロー一覧表とMermaid図を実態に合わせる
  - 完了条件: 図と表がマージ列を経由する流れを表している
  - _Requirements: 6.2_
  - _Boundary: README.md_

- [ ] 4. 切り替えと実地検証
- [ ] 4.1 トリガ先行の状態で非破壊を確認する
  - **前提**: 1.1 で `基盤構築手順.md` に書いた手順に従って、人間が
    `BOT_GITHUB_TOKEN` を Dependabot secrets に登録済みであること。
    未登録のままマージすると、Dependabot の予約が静かに止まる
  - 2.x と 3.x をマージした状態で、キューを有効にせずに通常のPRを1本通す
  - 完了条件: 必須チェック18本が従来どおり報告され、群2のスキップ条件が
    `pull_request` では発動していない
  - _Requirements: 1.1_
  - _Depends: 1.1, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 3.1, 3.2_

- [ ] 4.2 キューを有効化して1本通す
  - 人間が merge queue を有効化し、squash とタイムアウト60分を指定する
  - 検証用PRを1本キューに通す
  - `GITHUB_SHA` と `merge_group.head_sha` が一致することを出力して確認する
  - `dependency-review` が「No Dependency Changes found」で緑になっていないことを確認する
  - `detect-changes` と `detect-terraform-changes` が merge_group で必須チェックとして
    報告され、変更が無い領域のスキップが実行ログに残っていることを確認する
  - PR側の必須チェックが赤のPRがキューに到達しないことを確認する
  - マージ後、push 起点の `dependency-graph.yaml` が従来どおり成功していることを確認する
  - キュー解体後のスナップショットの扱いを compare API で2時点比較して記録する
  - 完了条件: 18本すべてが merge_group で報告され、PRがマージされる
  - _Requirements: 1.1, 1.4, 1.5, 2.1, 2.3, 2.4, 3.3, 4.1, 4.4, 5.1, 5.6_
  - _Depends: 4.1_

- [ ] 4.3 複数PR同時とDependabotを確認する
  - **前提**: Dependabot のPRが開いていること。開いていなければ人間が
    Insights → Dependency graph → Dependabot の「Check for updates」で実行を起動する
    (定期実行は gradle / docker が毎週月曜 09:00 JST、github-actions が月次)
  - 2本以上のPRを同時にキューへ入れ、順に自動マージされることを確認する
  - backendの依存を変えるPRを2本同時に入れ、後続の `dependency-review` が
    実際に比較していることを確認する
  - Dependabot のPRが人間の操作なしにキューへ入ることを確認する
  - 完了条件: concurrency が互いをキャンセルせず、人間の操作なしに順にマージされる
  - _Requirements: 5.2, 5.4_
  - _Depends: 4.2_

## Implementation Notes

- 2.1〜2.3: `escape-hatch` と `size-check` は元々ジョブレベルの `if:` が無く、
  `!= 'merge_group'` を足すだけで `pull_request` と `pull_request_review` の
  両方が保持される。`== 'pull_request'` に限定してはいけない
- 3.2: 改行コードの確認は `git ls-files --eol` を使う。`grep -c $''` は Git Bash の
  テキストモードが CR を剥がすため常に0を返し、判定に使えない。Python で書き出すときは
  `newline=""` で読み書きして元の改行を保つ(README だけが CRLF、他の文書は LF)
- 2.8: `GITHUB_TOKEN` は `env:` で明示的に渡さない限り環境変数として存在しない。
  `gh` が `GH_TOKEN` 空のとき `GITHUB_TOKEN` へフォールバックする挙動はあるが、
  このワークフローにはフォールバック先が無く、鍵未登録ならトークン未設定のエラーで止まる。
  `permissions: {}` は将来 `env:` に渡す変更が入ったときの保険
- 2.2: `terraform-plan` ジョブは AWS OIDC のため `id-token: write` を要し、
  ワークフローレベルの権限を継承したままでよい(merge_group では実行されない)

- 1.2: Rulesets API(id 2986186)の必須チェック18本と design.md の群の割り付け表が
  差分なしで一致。群2の引き継ぎ理由の表も7本すべてを覆っている。design.md の修正は不要だった
- 1.1: 基盤構築手順の設定画面の導線は Settings → Branches ではなく
  Settings → Rules → Rulesets。branch protection API は404を返し、保護の実体は
  ルールセットのみになっている
