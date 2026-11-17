# Research Log: spec-review

## 調査の範囲

既存システムへの追加(Extension)として、統合点に絞って調査した。外部の実践については、方式を決める前に Issue #193 の検討の中で調査済みであり、その結論をここに要約する。

## 調査した項目と結論

### 1. cc-sdd の拡張点

- `docs/guides/customization-guide.md` が認めるカスタマイズは、テンプレート(生成する文書の構造)とルール(生成の判断基準)の2つだけ
- レビューの手順・フック・追加の検証を差し込む仕組みは記載が無い
- `--claude-skills` 形態では、ルールは `.claude/skills/kiro-*/rules/` に配られる
- **結論**: 本家に手順を差し込めないため、外側に独立したスキルを置く

### 2. 既存のレビューの仕組み

- `kiro-spec-tasks` の Step 3.5 に、新しいサブエージェントによる独立レビューが既にある。ただし親と同じモデルで、書く前に1回だけ走り、結果が残らない
- `kiro-impl` には実装役・レビュー役・デバッグ役の往復があり、上限つきで打ち切る
- `record-gate-run.sh` と `check-verify-before-stop.sh` が、実行の記録と検査を分ける形を実装している
- **結論**: 往復と上限は `kiro-impl` に、記録と検査は既存のフック2本に形を揃える

### 3. 他の spec 駆動の仕組みの状態管理

| 仕組み | 状態の持ち方 | 承認の記録 |
|---|---|---|
| OpenSpec | ファイルの有無と位置 | 無い |
| Backlog.md | タスク1件が1ファイル | 無い |
| Task Master | `tasks.json` に集約 | 無い |
| BMAD-METHOD | `sprint-status.yaml` に集約 | 無い |
| spec-workflow-mcp | `.spec-workflow/approvals/` の JSON | ある(ただし承認者を記録しない) |
| beads | Dolt(履歴を持つ SQL) | 人の判断を待つ関門がある |

- **結論**: 承認を偽装できない形で記録している仕組みは無かった。ファイルで状態を持つのは主流のやり方であり、今回はその形を採る。将来の選択肢として、承認を GitHub の事実(PR のマージや人の Approve)に委ねる案を Issue #193 に残した

### 4. Claude Code のフックとサブエージェントの仕様(公式ドキュメント)

- `SubagentStop` の入力は `agent_id` / `agent_type` / `agent_transcript_path` / `last_assistant_message`。モデルは含まない
- `SubagentHandback` は auto mode で v2.1.271 以降のサブエージェントに与えられ、`tools` から外しても `disallowedTools` に書いても付与される。使われた場合、報告は `last_assistant_message` ではなく `PostToolUse` の `tool_input.message` に入る
- `UserPromptExpansion` は人がスラッシュコマンドを直接打った経路で発火し、matcher はコマンド名。`UserPromptSubmit` がスラッシュコマンドで発火するかは本文に記載が無い
- 共通入力に `prompt_id` がある(v2.1.196 以降)
- Stop フックは8回続けてブロックすると Claude Code が上書きする
- サブエージェントの `model` はフルモデルIDを受け付け、優先順位は起動時の指定が定義ファイルより上
- **結論**: 報告は2経路から読む。通知は `UserPromptExpansion` を主に使い `UserPromptSubmit` を併用する。回数は `prompt_id` をキーにする。モデルは定義ファイルに固定し、起動時に指定しない

### 5. codex-review との干渉

- `codex-review.yml` は spec ディレクトリ直下の `*.md` を連結して spec 適合の判定基準にする
- レビューの記録をそこに置くと、却下した選択肢や未解決の指摘が「要求」として読まれる
- **結論**: 記録は `reviews/` サブディレクトリに置く。`*.md` は再帰しないため混入しない。既存の `research.md` と `brief.md` の混入は #341 で別途扱う

## 採らなかった案

| 案 | 採らなかった理由 |
|---|---|
| 生成スキル(cc-sdd)の中にレビューを組み込む | 本家の更新のたびに当て直しが要る。観点は頻繁に変えるため差分が複雑になる |
| 突き合わせは同一モデル、別モデルは design だけ | 現行の運用(3段階すべてで別モデル)より弱くなる。取り返しのつかなさは requirements が最大で、design だけに厚くする根拠が無い |
| 承認や状態を `spec.json` に追記する | 記録ファイルと spec.json で食い違いが生まれる。更新時刻の比較はどちらでも必要になり、優位が無い |
| レビュー役に `SubagentHandback` を禁止する | 定義ファイルでは禁止できない(公式に明記)。禁止に頼ると、付与される環境で証跡が一度も書けない |
| 低の指摘も往復の終了条件に数える | 新しいレビュー役が毎回別の表現を指摘するため収束しない。3往復を低で使い切る |

## リスクと対応

| リスク | 対応 |
|---|---|
| メインセッションが証跡や記録を偽造する | 既存の品質ゲートと同じ水準として受容する。review ファイルのハッシュ照合で、完了後の書き換えだけは検知する |
| モデルを確認できない経路がある | 制約として要件に明記した(7.4) |
| フックの誤検知でセッションが止まり続ける | 同じ入力に対して2回までとし、3回目は通す |
| 差し戻しが繰り返されて費用が膨らむ | 回数を報告に添え、2回目からは spec の分割と作り直しを選択肢として示す |

## Issue #559 のための調査(2026-10-13)(#559)

### 1. 上限に達したときの Agent ツールの結果

- 公式(https://code.claude.com/docs/en/errors.md): サブエージェントの API 要求が失敗して止まると、結果は `Agent terminated early due to an API error: <詳細>` になる。上限の詳細の例は `You've hit your session limit`、`weekly limit`、`monthly spend limit`。過負荷は `Repeated 529 Overloaded errors. The API is at capacity` で、公式は 529 を利用上限に数えないと明記している
- 未修正の issue(https://github.com/anthropics/claude-code/issues/82829): 上限で止まったサブエージェントの結果は、成功と同じ状態で返り、エラーの印が付かない。本文の文面でしか見分けられない。途中まで出力していたときは、`Everything below is PARTIAL output` に続いて途中の出力が付く
- このリポジトリでは実測していない。上限は狙って起こせない
- **結論**: 実装セッションは、結果の文面(`Agent terminated early due to an API error:` と、`limit` を含み `529` と `Overloaded` を含まない詳細)で上限を判定する。文面が変わったときは、上限以外の失敗として止まる側に倒す

### 2. モデルの指定と記録

- 公式(https://code.claude.com/docs/en/sub-agents.md、https://code.claude.com/docs/en/model-config.md): Agent ツールの `model` 引数は別名 `opus` `fable` などを受け付け、定義ファイルの `model:` より優先される。Anthropic API では `opus` は Opus 5.5、`fable` は Fable 5.1 を指す
- 実測(2026-10-13): `model: opus` で起動したサブエージェントの記録には `"model":"claude-opus-5-5"` が残った。いまの証跡のフックは `claude-fable-5-1` だけを受け入れるため、Opus 5.5 のレビューでは証跡が書かれなかった(`.claude/.state/spec-review/spec-review__requirements.evidence` はサイクル3のまま)
- **結論**: spec.json には別名(`fable` / `opus`)を記録し、Agent ツールにそのまま渡す。証跡のフックは2つのフルモデルIDを受け入れる

### 3. 使った量

- 実測(2026-10-13): Agent ツールの結果の末尾に `<usage>subagent_tokens: <数>` が載る。公式に定義の説明は無い(issue の生データでは `totalTokens`)。何を数えるか(入力・出力・キャッシュ)は確認できていない
- **結論**: 前後の比較には同じ値(`subagent_tokens`)だけを使う。数え方が分からなくても、同じ値どうしなら比べられる

### 4. 量を比べるための見本

比べる元は requirements のサイクル5 往復2(Opus 5.5、全体の審査、126,457 トークン)である。その往復の前に実装セッションが直したのは、要件9の5と6の2項目である。直す前の文は次のとおり。

```
5. 所有者が選んだモデルが Fable 5.1 で、Fable 5.1 が上限に達していてレビュー役が動かないときは、実装セッションは、所有者に尋ねずに、Opus 5.5 でレビュー役を起動し直してレビューを続ける。(#559)
6. 実装セッションが Fable 5.1 の上限のためにレビュー役のモデルを Opus 5.5 に替えるのは、そのときのレビュー役の起動に限る。実装セッションは、spec に記録した所有者の選んだモデルを Fable 5.1 のまま残す。次にレビュー役を起動するときは、Fable 5.1 の上限が解けているかもしれないので、実装セッションはまず Fable 5.1 でレビュー役を起動する。Fable 5.1 がまだ上限に達していれば、実装セッションは、またレビュー役のモデルを Opus 5.5 に替える。(#559)
```

直したあとの文は、承認された requirements.md の要件9の5と6である。

### 採らなかった案(#559)

| 案 | 採らなかった理由 |
|---|---|
| `/kiro-spec-init` に、モデルを選ぶ引数を足す | cc-sdd のスキルを変えない決まり(要件8.1)に当たる |
| 上限で替えたら spec.json の選んだモデルも Opus 5.5 に書き換える | 要件9.6 に反する。上限が解けても Fable 5.1 に戻らない |
| 本文の控えを `reviews/` に置いてコミットする | 本文の写しがリポジトリに残り続ける。作業フォルダをまたぐ続きは少なく、そのときは全体を審査すれば足りる |
| 差分を実装セッションの説明(どこを直したか)で渡す | 書き方の点検の直しが記録に残らず、審査されないまま承認に進む(R4-1-1) |

## Issue #900 のための調査(2026-11-17)(#900)

### 今あるものについて確かめた文

- requirements.md 要件13の段落「今は、食い違いが小さくても design の承認が取り消される」: `.claude/skills/spec-review/SKILL.md` 240-262行(Step 6 は前の段階への指摘で往復を止め、所有者が直すと判断したら戻る段階と後続の段階の承認を取り消す。食い違いの大きさで分けていない) / 合っていた
- requirements.md 要件13の9「承認済みの段階の本文を直す前にその段階と後続の段階の承認を取り消すという規約」: `CLAUDE.md` 129行 / 合っていた
- requirements.md 要件14の7「要件7の7は、判定する対象を、生成済みで人間の承認が無い段階に限っている」: requirements.md 要件7の7 / 合っていた
- design.md「spec-review-scan.sh」の節「段階ごとの出力 `<feature>|<stage>|<理由>|<未解決の件数>`」と「人の承認がある段階を対象から外す」: `.claude/hooks/spec-review-scan.sh` 27-58行(`_sr_targets` が全部の spec.json を1回の perl で読み、`<feature>|<段階の並び>` を出す。`approved` が true で `approved_by` が空でなく `:` を含まない段階を外す)と 176行 / 合っていた
- design.md「spec-review-scan.sh」の節「最新の往復の指摘に処置が無ければ止め、処置が修正なら再レビューを求める」: `.claude/hooks/spec-review-scan.sh` 60-75行(`_sr_latest_ids` は最新の節の見出しのサイクルと往復の番号で始まるIDを全部拾う。前の段階への指摘のIDも同じ記号で拾う)と 119-141行 / 合っていた
- design.md「spec-review-scan.sh」の節「本文がレビューより新しいかは、ファイルの変更日時で比べる」: `.claude/hooks/spec-review-scan.sh` 162-166行(`[ "$body" -nt "$review" ]`) / 合っていた
- design.md「check-spec-review-before-stop.sh」と「notify-spec-review.sh」の節「走査の出力の1行ずつを読み、理由の欄が空でない行で止めるか示す」: `.claude/hooks/check-spec-review-before-stop.sh` 45-54行、`.claude/hooks/notify-spec-review.sh` 31-46行 / 合っていた
- design.md「テストの方針」の「走査のテストは、場合の名前で選んで流す形になっていない」: `.claude/hooks/tests/test-spec-review-scan.sh` 全271行(`KP_TEST_CASE` の扱いが無く、場合は `echo "--- <番号>. ..."` で区切られ、全部が順に流れる) / 合っていた
- design.md「テストの方針」の「フックのテストは CI で流れない」: `.github/workflows/guardrails.yaml` 230行(`.claude/hooks/tests/**` を対象から外している。ほかのワークフローに `hooks/tests` を呼ぶ行は無い) / 合っていた
- design.md「プロジェクトの決まり」の「`.claude/hooks/**` と `.claude/settings.json` は Claude が書けない」: `.claude/settings.json` 70-75行 / 合っていた
- design.md「rules/common.md」の節「前の段階への指摘は別の節に書き、表は `| ID | 対象 | 該当箇所 | 内容 |` である」「メインセッションはこれを直さず、所有者に報告する」: `.claude/skills/spec-review/rules/common.md` 58-60行、112-118行 / 合っていた
- design.md「rules/common.md」の節「処置の『所有者判断待ち』は前の段階への指摘に使う」: `.claude/skills/spec-review/rules/common.md` 137-147行 / 合っていた
- design.md「rules/design.md と rules/tasks.md」の節「前の段階への指摘の観点は design では9、tasks では8である」: `.claude/skills/spec-review/rules/design.md` 76-78行、`.claude/skills/spec-review/rules/tasks.md` 56-58行 / 合っていた
- design.md「spec-reviewer」の節「STATUS は高と中の指摘が0件なら converged」「当該段階の本文と前の段階の本文を読む」: `.claude/agents/spec-reviewer.md` 32行、89行 / 合っていた
- design.md「spec-reviewer」の節「定義の model は系統の別名 fable」: `.claude/agents/spec-reviewer.md` 5行 / 合っていた
- design.md「spec-review スキル」の節「Step 4 は前の段階への指摘を直さず、処置を所有者判断待ちにして Step 6 へ進む」: `.claude/skills/spec-review/SKILL.md` 192-198行 / 合っていた
- design.md「spec-review スキル」の節「Step 2 は fable でも opus でも、起動のたびに model を指定する」: `.claude/skills/spec-review/SKILL.md` 113-115行 / 合っていた
- design.md「spec-review スキル」の節「差し戻しの回数は review ファイルの再レビューの節を数える」: `.claude/skills/spec-review/SKILL.md` 245行 / 合っていた
- design.md「spec-review スキル」の節「Step 6 は承認を approval_history に写してから取り消し、戻る段階を新しいサイクルで changed 付きで審査する」: `.claude/skills/spec-review/SKILL.md` 247-265行 / 合っていた
- design.md「record-spec-review.sh」の節「記録のフックは agent-model.pl で系統を読み、Fable と Opus の系統のレビューの証跡を版によらず書く」: `.claude/hooks/record-spec-review.sh` 85-97行 / 合っていた
- design.md「CLAUDE.md の spec 駆動開発の節」の「承認を取り消す前に approval_history に追記する決まり」: `CLAUDE.md` 131-133行 / 合っていた
- design.md「テストの方針」の「過去の回の記録は main にある」: `git show main:.kiro/specs/backend-go-users/spec.json` の `approval_history`(design を 2026-11-13T04:51:38Z に T1-1-4 と T1-1-5 で取り消した)と `reviews/tasks-review.md` 112-118行。`git show main:.kiro/specs/backend-go-master-resumes/spec.json` の `approval_history`(design を 2026-11-14T07:13:41Z に T1-1-6 と T1-1-7 で、2026-11-15T12:47:59Z に T3-1-4 と T3-1-5 で取り消した。2026-11-15T06:17:31Z の取り消しは所有者の決定による requirements への差し戻しで、tasks の審査によらない)と `reviews/tasks-review.md` 120-127行、369-376行 / 合っていた
- design.md「テストの方針」の「#725 の spec は、2026-11-17 の時点で main に無い」: `git ls-tree main --name-only .kiro/specs/` / 合っていた
- design.md「spec 無しのPRの食い違い」: `gh pr list --state merged --limit 1000` の結果(total 462、`- 食い違う spec: .kiro/specs/spec-review/` の行を持つPRは0件) / 合っていた
- design.md「作らないもの」の「審査役の版の選び方と、実際に動いた版の読み方は spec `spec-reviewer-latest-model` が決める」: `.kiro/specs/spec-reviewer-latest-model/design.md` 13-30行 / 合っていた
- design.md「失敗したときの扱い」の「今の `_sr_targets` は、読めない spec.json と JSON として読めない spec.json を飛ばす」: `.claude/hooks/spec-review-scan.sh` 25行のコメントと 37-41行(`next unless -f $f` `open ... or next` `next unless ref $d`) / 合っていた
- design.md「spec-review-scan.sh」の節「`spec_review_scan` は `_sr_targets` の行を `IFS='|' read -r feature stages` で読み、段階ごとに判定して1行を出す」: `.claude/hooks/spec-review-scan.sh` 85-176行 / 合っていた
- design.md「テストの方針」の「`KP_TEST_CASE` に空白で区切って書いた名前の場合だけを流し、知らない名前があれば何も流さずに失敗する形」: `.claude/scripts/spec-review/tests/test-agent-model.sh` 6-7行、24-25行、243行 / 合っていた
- design.md「作らないもの」の「今の書き方の点検は、いまの段階の本文だけを見る」: `.claude/skills/spec-review/SKILL.md` 62-75行(Step 1.5 は本文のパスに `.kiro/specs/{FEATURE}/{STAGE}.md` だけを渡す) / 合っていた
- design.md「テストの方針」の「backend-go-users は #771、backend-go-master-resumes は #772 の spec で、どちらも spec.json に `review_model` が無い」: `git show main:.kiro/specs/backend-go-users/spec.json` と `git show main:.kiro/specs/backend-go-master-resumes/spec.json`(`issue` が 771 と 772、`review_model` のキーが無い) / 合っていた
- design.md「CLAUDE.md の spec 駆動開発の節のルール」の「承認済みの段階の本文を再生成または修正する前に承認を取り消す決まりは129行目」: `CLAUDE.md` 129行 / 合っていた
- design.md「テストの方針」の「場合の名前は、`t_` で始まる関数の名前にする」: `.claude/scripts/spec-review/tests/test-agent-model.sh` 243-249行(`KP_TEST_CASE` の名前は `t_*` に合い、その名前の関数があるときだけ受け付ける)/ 合っていた
- design.md「CLAUDE.md の spec 駆動開発の節のルール」の「必須のチェック `claude-md-size` の上限は 21,700 バイトで、今の `CLAUDE.md` は 21,688 バイト」: `.github/workflows/guardrails.yaml` 24行(`CLAUDE_MD_SIZE_LIMIT: '21700'`)と、`wc -c CLAUDE.md` の結果(21688)/ 合っていた
- design.md「CLAUDE.md の spec 駆動開発の節のルール」の「`approval_history` の要素の欄の一覧は、`/spec-review` の Step 6 と `/kiro-spec-init` の更新の形に書いてある」: `.claude/skills/spec-review/SKILL.md` 247-262行、`.claude/skills/kiro-spec-init/SKILL.md` 76-84行 / 合っていた
- design.md「CLAUDE.md の spec 駆動開発の節のルール」の「2つの直しのあとの `CLAUDE.md` は約 21,682 バイト」: scratchpad の写しに例外の1行を足して132行目を消し、`wc -c` で、130行目の末尾に足す「。」の3バイトを合わせて 21,682 バイトを測った。例外の文は、直しを戻すときも覆う文(design-review のサイクル7 往復1 の D7-1-1) / 合っていた

### 調べたことと設計への影響

- 走査のライブラリは、人の承認がある段階を判定から外す。承認を残して直した段階は人の承認があるので、今のままでは、直したあとに審査されたかを判定できない。そこで、直したことを spec.json に機械で読める形で残し、`_sr_targets` がその記録を読む形にする
- 前の段階への指摘のIDは、後ろの段階の記号(`D` か `T`)で振られ、`_sr_latest_ids` に拾われる。そのため、承認を残して直した穴の処置を「修正」にすると、次の往復の審査が無い間は、今ある「修正後の再レビューがない」の理由で止まる。往復の途中で直した穴は、今の判定で足りる。足りないのは、往復が終わったあと(3往復目のあとに所有者が直すと決めたとき)に前の段階の本文を直した場合である
- 過去の回の design の本文は、出荷のときに1回だけコミットされたので、取り消した時点の design の本文は git に無い。過去の回の確かめでは、審査役は、記録(tasks の審査と対応の記録、`approval_history` の `revoked_for`、取り消したあとの design の審査と対応の記録)と、今の requirements と design から判定する
- 過去の記録で後ろの段階に回した食い違いは、決まった書き方で書かれていない。後ろの段階の審査役は、前の段階の記録を後ろの段階の名前(`design` `tasks`)で検索し、当たった行を読んで判断する。これからの記録では、メインセッションが対応の記録に決まった書き出しで書き、検索で拾いやすくする

### 採らなかった案(#900)

- 承認を残して直した段階の審査を、前の段階のレビューの新しいサイクルとして行う案: 前の段階の review のファイルに節が増え、所有者が承認した段階の記録が後から伸びる。後ろの段階の往復の中で直しを審査させれば、要件13の5の「次の往復で審査する」とそろい、往復の数も増えない
- 承認を残して直した記録を Markdown のファイルだけに書き、フックがそのファイルを読む案: フックが Markdown の書式に依存する。spec.json は走査のライブラリがすでに1回の perl で読んでいるので、そこに配列を足すほうが速く、壊れにくい
- 承認を残して直した段階の本文と承認の時点の本文を、ハッシュで比べる案: 承認の時点の本文のハッシュは今どこにも残っていない。今ある「本文がレビューより新しい」と同じ、ファイルの変更日時の比べ方にそろえる
- 作るものが変わるかどうかを、実装セッションが決めて審査役が確かめる案: 要件13の4が、本文を書いた実装セッションが自分で決めることを禁じている
