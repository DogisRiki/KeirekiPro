# Implementation Plan

## KeirekiPro 完了条件(全タスク共通)

1. **acceptance criteria の引用とテスト対応付け**: 各タスクは対応する requirements.md の受入基準を検証するテスト(tests/ 配下のファイル名)を detail に持つ。テストが無い受け入れ基準を残さない
2. **verify の実行**: 変更領域が `.github/` 配下+README のみのため、既存の verify Skill(frontend/backend/terraform)は対象外。代替として、同梱テスト(`.github/scripts/tests/`)をコンテナ内で実行し全PASSであること
3. **ゴールハック禁止**: テストskip・アサーション削除で完了条件を満たさない(escape-hatch CIが機械検知する)
4. 新規テストは対象コードを一時的に壊して赤くなることを確認してから戻す

## Tasks

- [x] 1. 必須チェックの期待一覧ファイルを作成する
  - rulesetの現行19コンテキストを取得し、各チェックに mode(always/conditional)・state(active/paused)・approval_gated を分類して期待一覧を作る(スキーマは design.md の定義に従う)
  - codex-review は paused(reason と issue: 166 を記録)。approval_gated は dependency-gate / escape-hatch / pre-merge-check の3つ
  - 完了の観測条件: 一覧ファイルが存在し、19件全件がスキーマの必須フィールドを満たし、rulesetのコンテキスト集合と一致している
  - _Requirements: 2.3, 3.1, 3.2, 3.3_

- [ ] 2. 週次・月次の判定スクリプト
- [x] 2.1 (P) 定期スキャンの鮮度判定スクリプトとテストを作成する
  - 直近成功の取得、成功ゼロ=赤、8日以上=赤(最終成功日時を報告)、8日未満=緑、API失敗=判定不能で赤(受入基準 1.1〜1.4 を test-check-audit-scan-freshness.sh が検証)
  - テストは8日ちょうどの境界値を含む。新規テストは対象を一時的に壊して赤を確認してから戻す
  - 完了の観測条件: 対応するテストがコンテナ内で全PASS
  - _Requirements: 1.1, 1.2, 1.3, 1.4_
  - _Boundary: check-audit-scan-freshness.sh_
- [x] 2.2 (P) Dependabot滞留検知スクリプトとテストを作成する
  - openのDependabot PRのheadのcheck-runsを集計し、approval_gatedでないcontextのfailureがあれば赤(PR番号+チェック名を列挙)。approval_gatedのfailureは「承認待ち」として報告のみ。実行中・全緑は緑。しきい値なし(受入基準 2.1〜2.5 を test-check-audit-dependabot-stuck.sh が検証)
  - 期待一覧のスキーマ検証(必須フィールド欠落・未知の値=判定不能で赤)を自前で行う(共有ライブラリは作らず、一覧を読む各スクリプトが自己完結で検証する。2.3・2.4も同じ)
  - 新規テストは対象を一時的に壊して赤を確認してから戻す
  - 完了の観測条件: 対応するテストがコンテナ内で全PASS
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_
  - _Boundary: check-audit-dependabot-stuck.sh_
  - _Depends: 1_
- [x] 2.3 (P) 必須チェックの集合照合とスキップ検知のスクリプトとテストを作成する
  - 集合照合: rulesetと期待一覧のcontext集合の差分で赤(状態は照合に使わない)。期待一覧のスキーマ検証は自前で行う(受入基準 3.4〜3.8 を test-check-audit-skipped-required.sh が検証)
  - スキップ検知: 対象期間(現在のGITHUB_RUN_IDを除いた自ワークフローの直近実行以降、無ければ7日)にマージされたPRの head.sha のcheck-runsを走査。mode: always かつ state: active の skipped/実行なしで赤。pausedは非違反+停止中報告。conditionalは対象外。merge_commit_sha は使わない
  - 失敗時の報告文面に「判定不能の赤は失敗したrunのre-runで再実行する(新規dispatchは検知の窓を狭める)」の指示を含める
  - 新規テストは対象を一時的に壊して赤を確認してから戻す
  - 完了の観測条件: 対応するテストがコンテナ内で全PASS(現在run除外・head.sha使用・初回7日窓のテストを含む)
  - _Requirements: 3.4, 3.5, 3.6, 3.7, 3.8_
  - _Boundary: check-audit-skipped-required.sh_
  - _Depends: 1_
- [x] 2.4 (P) カナリア照合スクリプトとテストを作成する
  - 種別→期待チェック対応表(6種)を定数で持ち、当月ブランチのPRを特定して期待チェックの結論を3値判定(failure=正常 / success=判定側の故障 / skipped・実行なし=実行されていない)(受入基準 5.1〜5.8 を test-check-canary-results.sh が検証)
  - 6件未満は生成側異常として赤。期待一覧に無い期待チェックは稼働中とみなす。pausedは「停止中(記録済み)」として失敗と区別。書き込み操作なし。全種別の判定一覧を常に出力。期待一覧のスキーマ検証は自前で行う
  - 新規テストは対象を一時的に壊して赤を確認してから戻す
  - 完了の観測条件: 対応するテストがコンテナ内で全PASS(3値それぞれ・6件未満・paused区別・一覧に無い期待チェックのケースを含む)
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8_
  - _Boundary: check-canary-results.sh_
  - _Depends: 1_

- [ ] 3. ワークフローへの組み込み
- [x] 3.1 週次監査ワークフローを作成する
  - cron(毎週月曜)+workflow_dispatch、permissionsはread系のみ、secretsなし
  - ジョブ内で自テスト3本→本判定3本を全実行し、結果を集約して最後に失敗させる。期待一覧のpaused一覧をJob Summaryへ常時出力
  - 完了の観測条件: ワークフローファイルが存在し、判定3本の呼び出し・権限・トリガーが設計の契約どおりであること(レビューで突合)
  - _Requirements: 1.1, 2.1, 3.7, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_
  - _Depends: 2.1, 2.2, 2.3_
- [x] 3.2 (P) CIへ監査の死活ステップを追加する
  - detect-changesジョブ末尾に1ステップ。`if: github.event_name == 'pull_request'` 必須。actions: read 権限を追加
  - 成功ゼロ=pass(導入直後)、直近成功が10日以上前=::error::で失敗、10日未満=pass。API 1リクエスト(受入基準 4.1〜4.4)
  - 完了の観測条件: 本spec実装PR自身のCI(PRイベント)でステップが実行されpassすること、および `if` 条件が設計の契約どおりであること(レビュー突合)。push側の実測はマージ後の導入手順(design.mdのTesting Strategy)で行う
  - _Requirements: 4.1, 4.2, 4.3, 4.4_
  - _Boundary: ci.yaml detect-changes_
- [x] 3.3 (P) カナリア照合ワークフローを作成する
  - cron(毎月4日)+workflow_dispatch、permissionsはread系のみ。自テスト→本判定のパターン
  - 完了の観測条件: ワークフローファイルが存在し、判定の呼び出し・権限・トリガーが設計の契約どおりであること
  - _Requirements: 5.1, 6.1, 6.2, 6.3, 6.4, 6.5_
  - _Depends: 2.4_
- [x] 3.4 READMEのワークフロー一覧表とMermaid図へ2本を追記する
  - audit-weekly と canary-verify の行と図ノードを追加(作業規約: ワークフロー追加PRはREADMEも更新する)
  - 完了の観測条件: READMEの一覧表と図に2本が含まれ、既存の記載形式と一致している
  - _Requirements: 6.5_
  - _Depends: 3.1, 3.3_

- [x] 4. 判定スクリプト4本を実データ由来のフィクスチャでドライラン実行する
  - ホスト側の認証済みghで実APIレスポンス(現在のPR・runs・ruleset・check-runs)を取得してフィクスチャ化し、コンテナ内で既存テストと同じスタブ機構に流して4本を実行する(コンテナにghが無く、ホストにjqが無いという環境制約への対応)
  - 期待どおりの判定(現状は全緑+codex-review停止中の報告)になることを確認する
  - 完了の観測条件: 4本の実行結果と判定根拠が記録され、想定外の赤・緑が無い
  - _Requirements: 6.5_
  - _Depends: 3.1, 3.2, 3.3_

## Implementation Notes

- (Task 2.2) check-runs取得はper_page=100単発。イベント多重発火でスイートが100件を超えると101件目以降を見落とす(fail-open)。低確率だが次回触る際は --paginate を検討
- (Task 2.2) 滞留結論は所有者判断(2026-09-06「Aで」)により failure / cancelled / timed_out / action_required の4つに拡大済み(design.md改訂・スクリプト修正・再レビュー承認済み)。既存テスト2件の期待文字列を結論併記の新書式に更新したため、**PR本文に Test-Change-Justification が必要**(弱体化ではなく強化。レビューで確認済み)。requirements.md 2.2/2.3の「失敗」の文言は未同期(所有者判断で据え置き可)
- (Task 2.3) PR一覧走査は全closed PRを--paginateで取得(期間打ち切りなし)。PR総数に比例してAPI呼び出しが増えるため、将来は sort=updated&direction=desc による打ち切りが改善候補。conclusion null(実行中)のみのcontextは違反=赤(fail-closed。固定テストは無し)

- (Task 1) guardrails.yaml は pull_request_review イベントでも発火し、gitleaks等が同一head SHAに skipped のcheck-runを残す。タスク2.3のスキップ検知は「コンテキストごとに成功/完了の結論が存在するか」で判定しないと、承認操作のあったPRで偽赤になる
- (Task 1) codex-review は mode: always だが、そのif条件はDependabot PRも除外する。将来 paused を解除すると、マージ済みDependabot PRが2.3で違反扱いになる潜在偽赤がある(現状はpausedのため実害なし。解除時に期待一覧かスクリプトの扱いを見直すこと)
- (Task 1) dependency-cooldown / dependency-graph-submit の conditional は変更検知でなくactor/fork条件由来(cooldownはDependabot PRを除外)。分類としては運用上これが唯一正しい選択

- (Task 3.4) レビューのREJECTは `.claude/settings.json` の未コミット変更(deny 2行の一時解除)の出所確認のみが理由で、README自体は全項目合格。出所は所有者の明示指示(2026-09-06「解除した」)であり、コミットには含めない。**/ship後に所有者が2行を復元する**
- (Task 3.4) README.md は既存がCRLF主体(混在)。追記はCRLFで整合済み

- (Task 4) 2026-09-06実施のドライラン結果(実APIデータ由来・レビュアーが再実行でバイト一致を確認): 鮮度=緑(直近成功9/2、4.25日前)/ 滞留=緑(open 0件)/ 集合照合+スキップ検知=緑(19context一致、マージ済み9PRに違反なし、codex-review停止中報告)/ カナリア202609=緑(6件全て期待どおり。クローズ済みPRでも照合可能を実証)。audit-weekly runsのみ手製フィクスチャ(main未マージで404のため。初回=7日窓の経路を確認)

- (Task 3.2 追補) 出荷後のPR #331 のCIで死活ステップが赤になった(audit-weekly.yaml がmain未登録のためAPIが404→判定不能扱い)。404のみ「導入前の許容」として通過する分岐を追加し、5分岐をコンテナ実測で確認して修正(通信断・その他のAPI失敗は引き続き赤)。ドライラン(Task 4)で唯一手製フィクスチャに置き換えた箇所が実態と食い違っていた教訓: 実APIが404を返した時点でフィクスチャ化でなく仕様の穴を疑うべきだった

## マージ後の実測(2026-09-06)

- PR #331 は所有者Approve後にauto-mergeでマージ(マージコミット d64c2a38)。マージ後の dependency-graph.yaml も正常発火(bot名義予約)
- audit-weekly を workflow_dispatch で初回実行(run 34038432029)→ **success**。実測結果:
  - 自テスト3本: 全PASS(CI環境=ubuntuランナーでも成立)
  - scan-freshness: 「定期スキャン(container-scan-scheduled.yaml)は稼働しています(最終成功: 2026-09-02 07:57 UTC)」
  - dependabot-stuck: 「必須チェックが通らないまま止まっているDependabot PRはありません(open: 0件)」
  - skipped-required: 「必須チェックの集合は一致し、スキップのままマージされたPRはありません(対象PR: 10件)」(PR #331自身を含む10件を走査)
  - paused報告: codex-review(停止中: #166)をSummaryに常時表示
- これにより死活ステップ(要件4)の前提となる成功実行が存在する状態になった
- 出荷時に検知した不具合2件はマージ前に修正済み: (1) 死活ステップの404(導入前)未許容 → 許容分岐を追加(コミット ae2e31e)。(2) shellcheck SC2181 → 修正(コミット b6ea690)。escape-hatchジョブが .github/scripts のシェルスクリプトにshellcheckを流すことが判明(今後の実装知見)
- 残る実地確認は canary-verify の初発火(2026-10-04)のみ

## 補足

- マージ後の実地確認(workflow_dispatchでaudit-weeklyの成功を1件作る=死活ステップの前提。実施主体はbot。canary-verifyは次の月初サイクル10/1生成→10/4発火で確認)は、実装タスクではなく design.md の Testing Strategy(導入手順)に定義済みのため tasks.md には含めない。/ship後にbotが実施し、specへ実測を追記する
