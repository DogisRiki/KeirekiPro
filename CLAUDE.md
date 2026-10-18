# KeirekiPro

エンジニア向け職務経歴書の作成・管理を行うフルスタックWebアプリケーション。
開発は、人間がコードをレビューしないことを前提とした自律パイプラインで行う。
実装からマージまでを自律的に進め、品質は自動チェック(テスト・静的解析・カバレッジ閾値・
Codexによるクロスレビュー)で担保する。人間が関与するのは、作るものの決定(`/request` で始める壁打ちを経てAIが要望を起票)・specの承認・
影響の大きい変更の承認・デプロイ前確認・デプロイ実行のみ。

## リポジトリ構成

| パス | 内容 | スコープ別ガイド |
|---|---|---|
| `backend/` | Spring Boot API(Java 21 / オニオン+DDD+CQRS) | `backend/CLAUDE.md` |
| `frontend/` | React SPA(TS / Vite / bulletproof-react型) | `frontend/CLAUDE.md` |
| `terraform/` | AWS IaC | `terraform/CLAUDE.md` |
| `docker/` + `compose.yaml` | 開発環境(全コマンドはコンテナ内実行) | - |
| `.github/` | CI/CD・ガードレール(CODEOWNERS保護) | - |
| `.kiro/specs/` | spec(仕様書。監査証跡としてコミット) | - |
| `.kiro/steering/` | steering(プロジェクト知識) | - |
| `doc/` | 設計図(クラス図・ER図・インフラ設計等)と人間向けの運用文書 | - |

## 品質ゲート(すべて `run-check.sh` 経由。コマンドと順番は `/verify-frontend` `/verify-backend` `/verify-terraform` の各スキルに従う)

Claude は、1つのセッションの中では品質チェックを順に1つずつ動かす。セッションをまたぐ同時実行は `run-check.sh` が設定の数までに抑える。
`run-check.sh` は、そのセッションの作業フォルダを読み込んだ1回きりのコンテナでコマンドを動かす。

同時に走らせる数は、作業PCごとの設定 `keirekipro.parallelSlots`(初期値1)で決まる。所有者に数を変えるよう頼まれたら、Claude は次の順で設定する。

1. `docker info --format '{{.MemTotal}}'` で Docker に割り当てたメモリ(バイト)を読む
2. 目安の数を求める。目安は、(割り当てたメモリ − 約1GB)÷ 約4.2GB の小数点以下を切り捨てた数(最小1)。約1GBは共有のサービスの分、約4.2GBは backend の品質チェック1回分
3. 数と求め方を所有者に示してから、`git config keirekipro.parallelSlots <数>` で設定する

CI環境(GitHub Actions = Docker Compose無し)では `bash .claude/scripts/parallel/run-check.sh <領域>` を外し、
`frontend/` `backend/` 各ディレクトリでネイティブにコマンドを実行する。

## 自律動作の境界

- 作業は必ずfeatureブランチで行う。mainブランチではcommit/pushしない(hookでもブロックされる)
- ゲート設定ファイル(`.github/` `.claude/` `eslint.config.js` `vite.config.ts` `backend/gradle/quality.gradle` `backend/config/` ArchUnitテスト `CODEOWNERS`)は変更しない。変更が必要なときは理由を添えて人間に提案する
- 人間の承認が必要な変更: ライブラリの入手先と実行設定(`frontend/.npmrc` `.pnpmfile.cjs` `.pnpmfile.mjs` `pnpm-workspace.yaml`)の変更・backendのビルドスクリプト(`*.gradle` `*.gradle.kts`)の変更・DBスキーマ変更(マイグレーション)・ゲート設定の変更・リポジトリ外部へのデータ送信。これらを含むPRは承認まで自動マージされない(dependency-gate / CODEOWNERSが機械強制)
- 依存のバージョン宣言(`package.json` `pnpm-lock.yaml` `libs.versions.toml` `gradle-wrapper.properties`)は承認の対象外。dependency-review(新規の脆弱性)・dependency-cooldown(公開から72時間未満)・gradle-wrapper(配布元と公表チェックサム)が代わりに止める。**バージョンは `backend/gradle/libs.versions.toml` に集約し、`build.gradle` に直書きしない**(直書きすると承認が必要な側に戻る)
- テストのskip化・アサーション削除・カバレッジ/lint除外の追加で「見かけの合格」を作らない(escape-hatchチェックが機械検知)
- 必須チェックを新しく足すときは、期待一覧(`.github/audit/required-checks.json`)への登録も同じ変更に含めて人間に提案する。スキップのままマージされたことを週次監査が見つけられるのは、期待一覧に登録したチェックだけである(登録が漏れると、rulesetとの食い違いとして週次監査が報告する)
- **コンテナイメージの脆弱性の抑制(`.github/container-scan-suppressions.json`)を自分の判断で足さない。** これは `container-scan` を緑にする唯一の手段であり、「見かけの合格」を作る経路にあたる。追加が要ると判断したときは、脆弱性ごとに理由と期限を添えて人間に提案する。`.github/` 配下のためCODEOWNERSとescape-hatchが承認を機械強制する
- **`container-scan` の実行を自律側からキャンセルしない。** キャンセルされたジョブは `cancelled` として報告され、必須ステータスチェックは成功にならない(2026-08-20 実測。緑は残らない)。ただしその後に再検査を発火させるイベントが無いため、**再実行するまでPRは赤のまま進まなくなる。** 実行が長い(本番イメージの組み立てを含む)ことを理由に止めない
- 200行(実装のコード差分。テストとドキュメントは計上しない)を超えるPRは、spec駆動(Lane A)のPRとしてPR本文に `Spec: .kiro/specs/<feature>` を記載したものしか通らない(size-checkが機械判定する)。
- 本番デプロイ(release.yaml)・`terraform apply` は起動しない(人間の専権)
- DependabotのPRをcloseしない。とくにdockerレーンは、closeするとそのタグの更新が恒久的にブロックされ、復旧経路が限られる(Dependabot側の照合キーにdigestが含まれないため)。`@dependabot recreate` / `rebase` を自分の判断で打たない(クールダウン中はPRがcloseされる)。赤で止まっているPRの扱いは `doc/開発フロー/監査手順.md` に従う
- 同一の失敗が3回続いたら停止して人間に報告する(修正の無限ループを作らない)
- 依頼範囲外の問題を見つけたら報告のみ行う(勝手に直さない)
- `/loop` などの定期実行ループの中からはcommit/pushしない(出荷は明示的な `/ship` でのみ行う)

## Git規約

- 前提: ホストOSに **bash と perl(JSON::PP)が必要。jqには依存しない。**(`.claude/hooks/` のフックはこれらで実行される。シェルスクリプトは `.gitattributes` でLF強制)。
  **Windowsでは Git for Windows(Git Bash同梱)を入れることで満たす。** macOS / Linux は標準で満たす
- Git操作は、ホストOSで、そのセッションの作業フォルダの最上位で実行する(devcontainer内Gitは無効)
- Windows では、Claude の Bash は Git Bash の引数の書き換えを止めてある(`.claude/settings.json` の `env` の `MSYS2_ARG_CONV_EXCL`)。`git` `gh` `docker` などにパスを渡すときは、`C:/Users/…` のドライブ文字の形か、作業フォルダからの相対の形で書く。`/c/…` や、`mktemp` が返す `/tmp/…` の形は渡さない。`mktemp` の結果は `cd "$d" && pwd -W` でドライブ文字の形に直す。対象は Windows 向けのプログラムに渡す引数だけで、`>/dev/null` のようなリダイレクトは今までどおり書く
- ブランチ名は `.branch_name_template`、コミットメッセージは `.commit_template` に従う
- 人間はIssueを閉じない
- push先はfeatureブランチのみ。マージはauto-merge(ゲート全通過で自動)に任せる。auto-mergeは、PRが作られると仕組み(ワークフロー)が予約する。
  AIは予約の操作(`gh pr merge`)をせず、予約されたことを確かめる。予約が付かないときは自分で予約せず報告する
- 出荷手順(verify→commit→push→PR→auto-mergeの予約の確認)は `/ship` に従う

## 作業規約

- 依頼範囲外のファイルを変更しない。スタイル調整目的の全面書き換えをしない
- `.github/workflows/` のワークフローを追加・変更・削除したPRでは、READMEのワークフロー一覧表とMermaid図も更新する
- 外部技術の仕様は Context7 MCP または公式ドキュメントで現行版を確認してから使う
- 外部ツールの仕様やエラーは、記憶で判断せず公式ドキュメントとissueを調査してから実装・提案する(根拠URLを添える)
- ユーザーへの報告・PR本文・コミットメッセージは日本語(コミットprefix等の規約語は除く)
- テキストファイルはUTF-8。文字化けを検知したら保存せず停止して報告する(hookでもブロックされる)
- Think in English, generate responses in Japanese. `.kiro/` 配下に生成するMarkdown(requirements.md,
  design.md, tasks.md, research.md 等)は spec.json.language の設定言語(日本語)で書く

## spec駆動開発(cc-sdd / Kiro-style)

spec で進めるか(Lane A)、spec 無しで進めるか(Lane B)は、着手時に `/start` が決める。
AIがIssueの本文とその時点のコードを調べ、`/start` のスキル(`.claude/skills/start/SKILL.md`)の「観点の定義」の4つの観点で判断し、判断と観点ごとの理由を所有者に示す。spec が要らないと判断して返事を待たずに実装するときも、実装を始める前に示す。

- 変更の行数の見込みは、着手時の判断に使わない。200行の検査は、着手時の判断をすり抜けた変更を止める最後の網であり、着手時に spec の要否を決める基準ではない(全文は `.claude/skills/start/SKILL.md` の「Step 5: 判断する」)
- 観点ごとの定義(「当たる」「当たらない」、3つの材料、1回尋ねれば決まる)は、`.claude/skills/start/SKILL.md` の「Step 5: 判断する」の「観点の定義」の表と表の下の箇条のとおりとする

### パスと役割分担

- Steering: `.kiro/steering/`(プロジェクト全体の知識。`product.md` `tech.md` `structure.md`。
  作業規約はこのCLAUDE.mdとスコープ別CLAUDE.mdに書き、steeringと二重記述しない)
- Specs: `.kiro/specs/`(機能単位の要件・設計・タスク。進捗は `/kiro-spec-status {feature}`)
- spec の書き方の基準: `.kiro/settings/rules/spec-writing.md`(書き方の決まり・見本・見出しと目印の一覧・Issueの印)

### ワークフロー

- 要望の壁打ち: 人間が `/request` を打って始める。AIが聞き取りと決定の記録を行い、最後に要望のIssueを起票する
- 起票: `gh issue create` を実行する前に `.claude/skills/file-issue/SKILL.md` を読み、その決まりに従う(`/request` を通らない起票も同じ。監査の通知と振り返りはそれぞれの様式に従う)。
  Issueは本文だけにし、所有者が決めたことだけを書く。調べた事実・原因の調査結果・方式の案はIssueに書き残さない(方式は design で考え、事実は仕様づくりや実装のときに調べ直す)。
  spec-reviewer と codex-review は本文だけを判定の基準にする。Issueのコメントは要望として読まない。
  `/kiro-discovery` は使わない
- 着手: Issueへの着手は、所有者が `/start #N` を打って始める。所有者が「#N をやって」のように言葉で着手を頼んだときも、AIは `/start` に従う。
  spec が要らないと判断しても、所有者に尋ねる問いがあれば、AIは答えを待ち、答えをIssueの本文の「決めた方式」に書き足してから実装する。AIは、着手のときに、まとめたほうがよいほかのIssueを探し、あれば所有者に提案する(進め方ごとの手順の全文は `.claude/skills/start/SKILL.md` の「Step 5.5」「Step 6」「Step 7」)
- spec の各段階のコマンド(`/kiro-spec-init` `/kiro-spec-requirements` `/kiro-spec-design` `/kiro-spec-tasks` `/kiro-impl`)は所有者が打つ。
  AIは起動しない(`disable-model-invocation` により、AIからは起動できない)。必要なときは所有者に打つよう依頼する
- Phase 1(仕様化):
  - `/kiro-spec-init #N`(既存の spec を新しいIssueのために直すときは `/kiro-spec-init #N <feature>`)→ `/kiro-spec-requirements {feature}` → `/kiro-spec-design {feature}` → `/kiro-spec-tasks {feature}`
  - 審査役のモデルは、既定では Fable 5.1 で、所有者が spec ごとに Opus 5.5 を選べる。所有者は、spec を始めるときに、選んだモデルを会話で伝える。
    所有者が会話で審査役のモデルを伝えたら、実装セッションは、その spec の spec.json の `review_model` に `fable` か `opus` を書き、書いた値を所有者に1行で示す。
    spec.json がまだ無いとき(`/kiro-spec-init` の前)は、`/kiro-spec-init` が spec.json を作った直後に書く。
    所有者が spec の途中で選び直したときも、同じく `review_model` を書き換える。所有者が選んでいない spec では `review_model` を書かない
  - 既存コードとの整合確認: `/kiro-validate-gap {feature}`(任意)。これはレビューではなく design 前の事前調査(research.md の作成)である
  - `/kiro-validate-design` は使わない(`/spec-review` が置き換えた)。cc-sdd のスキルの出力で案内されても起動しない
- Phase 2(実装): `/kiro-impl {feature}`(タスクごとにsubagent実装+独立レビュー+最終検証)
  - 再検証のみ: `/kiro-validate-impl {feature}`
- 実装完了後の出荷は `/ship`(PR本文に `Spec: .kiro/specs/{feature}` と `Refs: #<Issue番号>` を記載)

### ルール

- 3段階承認: Requirements → Design → Tasks の各段階で人間の承認を得る。`-y` による自動承認は使用しない(/kiro-spec-batch 等による同等の自動承認も同様)。承認を記録するときは spec.json に承認者名と日時(`approved_by` / `approved_at`)を残す
- **次の段階へ進む前に、前の段階の記録の未解決を一覧で提示し、人間の了承を得る。** 未解決があっても機械的には止めない(判断は人間)
- **承認済みの段階の本文を再生成または修正する前に、その段階と後続の段階の承認を取り消す**(`approved: false` にし `approved_by` / `approved_at` を削除)。
  cc-sdd は既存の `approved_by` を上書きしないため、取り消さないと再生成した本文が承認済みのまま扱われる
- **承認を取り消す前に、取り消す段階のうち `approved` が `true` の段階ごとに、その承認を spec.json の `approval_history` に1つずつ追記する**(配列が無ければ作る)。
  要素は `stage` `approved_by` `approved_at` `issues`(その承認のときに spec が対象にしていたIssue。`issue` と、その時点の `additional_issues`)`revoked_at` `revoked_for`(取り消した理由)を持つ。
  `approval_history` は追記だけにし、書いてある要素を書き換えたり消したりしない。手順は spec-review の Step 6(差し戻し)と kiro-spec-init の更新の形(新しいIssueのための更新)にある
- 人間が承認前に spec を直した場合も `/spec-review` の対象になる。承認後に直す場合は、上のとおり承認を取り消してから直す(取り消せばレビューの対象に戻る)
- spec で進めている途中で、ごく小さい変更だと分かっても、spec の段階を省かず spec で最後まで進める。spec 無しへの切り替えを所有者に提案しない
- Skills は `.claude/skills/kiro-*/SKILL.md` と `.claude/skills/spec-review/SKILL.md`。適用可能性が1%でもあればスキルを起動する(spec の各段階のコマンドは除く。上のワークフローのとおり所有者が打つ)
- steeringは常に最新に保つ(`/kiro-steering` で更新)

# Compact instructions

Claude Code は、会話の要約を作るとき、次のことを必ず要約に残す。

- 実行中のスキルの名前と、その手順のどこにいるか(Step の番号)
- 進めている Issue の番号、spec の名前と段階、作業のブランチ、作った PR の番号
- `/spec-review` の往復の途中なら、CYCLE(審査のサイクルの番号)と ROUND(往復の番号)と CHANGED(本文を直したあとの審査かどうか)、その往復で受け入れた指摘と却下した指摘の ID、まだ記録に書いていない「直さなかった外れ」、Fable 5.1 から Opus 5.5 に替えたかどうか
- `/kiro-impl` の途中なら、検査のコマンド一式、確認役が差し戻した(REJECTED)往復の数、debug の補助役を動かした回数
- `/ship` の途中なら、同じ失敗が続いた回数
- 所有者に尋ねて答えを待っている問いの全文と、所有者が答えた内容のうち、まだ Issue の本文か spec.json に書いていないもの
- 所有者が会話で伝えたことのうち、まだ作業に使っていないもの(たとえば、審査役のモデルの選び)
- 補助役の会話なら、依頼文に書かれた識別の欄の全部(FEATURE・STAGE・CYCLE・ROUND・REVIEW_FILE、タスクの番号など)と、その時点までに出した判定

Claude Code は、要約のそれ以外の部分を短くする。Claude Code は、審査役・点検役・確認役に渡す材料(spec の本文、差分の全文)を要約で置き換えない。
