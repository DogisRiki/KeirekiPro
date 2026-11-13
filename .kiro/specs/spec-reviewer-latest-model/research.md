# 調査と設計の判断の記録

## 概要

- 機能: `spec-reviewer-latest-model`
- 調べの種類: 既存の仕組みの拡張(Extension)。Claude は、軽い調べ(design-discovery-light)で、つなぎ目と既存の作りと互換を調べた。
- 設計を決めた調べの結果:
  - Claude Code は、補助役の定義の `model` と、Agent ツールの起動時の `model` に、系統の別名(`fable` `opus`)を受け付け、別名をその Claude Code で使える最新のモデルに解決する。版の番号を仕組みのファイルから消せる。
  - 補助役が実際に動いたモデルは、補助役の会話の記録(`agent-<agentId>.jsonl`)の assistant の行の `message.model` に残る。記録の仕組みと Claude の両方が、この1か所から読める。
  - 作業の集計は、料金表に無いモデルを `report.json` の `totals.usd_unknown_models` に並べる。料金表の PR のきっかけは、この欄から作れる。料金表は、集計を作った作業フォルダの写しから読まれるので、main にすでに価格がある場合を外す必要がある。

## 今あるものについて確かめた文

- requirements.md はじめに「今の審査役は、所有者が Opus を選ばない限り Fable 5.1 で動き、所有者が Opus を選んだ spec では Opus 5.5 で動く」: .claude/skills/spec-review/SKILL.md 12行、110-112行、.claude/agents/spec-reviewer.md 5行
- requirements.md はじめに「審査役のモデルの版は、審査役の定義のファイルと、審査が済んだことを記録する仕組みのファイルに書き込まれている」: .claude/agents/spec-reviewer.md 5行(`model: claude-fable-5-1`)、.claude/hooks/record-spec-review.sh 84-93行(`claude-(fable-5-1|opus-5-5)` だけを受け入れる)
- requirements.md 範囲「料金表は `.claude/` の下にあるので、料金表を直す PR は、所有者が承認するまでマージされない」: .claude/scripts/usage/usage-config.json 1-10行(料金表の置き場所)、.github/CODEOWNERS 16行(`/.claude/` の所有者)
- requirements.md 範囲「モデルの公表価格の出どころは、Anthropic の公式の料金ページ」: .claude/scripts/usage/usage-config.json 3行(`prices.source`)
- requirements.md 要件1 理由「Fable 5.2 が出たあとも審査役が Fable 5.1 で動いていた」: .claude/agents/spec-reviewer.md 5行、.claude/skills/spec-review/SKILL.md 111行(`fable` ならモデルを指定せず定義の `claude-fable-5-1` を使わせる)
- requirements.md 要件1 1「この spec を書いた時点の Fable の最新のモデルは Fable 5.2 である」: 2026-11-13 に公式の料金ページ https://platform.claude.com/docs/en/about-claude/pricing を読み、料金の表の Fable の行が Fable 5.2、Fable 5.1、Fable 5 であることを確かめた。同じ日に、このリポジトリで、Agent ツールの起動時に `model: fable` を指定したサブエージェントが `claude-fable-5-2` で動いたことを確かめた
- requirements.md 要件2 理由「今の手順は、Fable 5.1 の審査役が使用量の上限で止まったら、Opus 5.5 に替えて審査を続ける」: .claude/skills/spec-review/SKILL.md 169-178行
- requirements.md 要件4 理由と 2・3「往復ごとの審査の記録に、モデルと、Opus に替えた理由と、上限で止まった起動の量を書く」(今の書き方): .claude/skills/spec-review/SKILL.md 196-211行
- requirements.md 要件4 5「審査が終わったときに Claude が所有者に出す報告」: .claude/skills/spec-review/SKILL.md 259行、275-276行
- requirements.md 要件5 理由「仕組みは、審査役が審査を済ませたことを記録し、記録の無い段階の承認を所有者に求めようとすると、Claude を止める」: .claude/hooks/record-spec-review.sh 1-20行、.claude/hooks/spec-review-scan.sh 80行、133-135行(「証跡がない」)、.claude/hooks/check-spec-review-before-stop.sh(spec-review-scan.sh を読み込む)
- requirements.md 要件5 理由「今の仕組みは、Fable 5.1 か Opus 5.5 で動いた審査だけを記録する」: .claude/hooks/record-spec-review.sh 84-93行
- requirements.md 要件5 3「審査役が動いたモデルを仕組みが読み取れて」: .claude/hooks/record-spec-review.sh 84-93行(会話の記録が渡る経路だけでモデルを確かめ、渡らない経路では確かめを省く)
- requirements.md 要件6 理由「今の料金表には Fable 5.2 が無い」: .claude/scripts/usage/usage-config.json 8-27行(Fable の行は `claude-fable-5-1` と `claude-fable-5` だけ)
- requirements.md 要件6 理由「作業の集計は、Fable 5.2 で動いた審査役の使用料を「価格が分からない」とし、全体の使用料の合計にも入れない」: .claude/scripts/usage/report.pl 1027-1032行(`price_of`)、1417行、1439行、1454-1455行
- requirements.md 要件7 3「作業の集計が価格を確かめた日として示す日」: .claude/scripts/usage/report.pl 1442-1444行、.claude/scripts/usage/usage-config.json 4行(`prices.checked_on` は料金表の全体で1つ)、.kiro/specs/ai-work-usage-report/design.md 577行(価格を直すときは `prices.source` と `prices.checked_on` も同じ変更で直す)
- requirements.md 要件7 1「Claude が作業の集計を GitHub に出したとき」: .claude/skills/usage-report/SKILL.md 43-60行
- requirements.md 要件8 理由「CLAUDE.md と `/spec-review` の手順には、審査役のモデルを版の番号で書いた文がある」: CLAUDE.md 112行、142行、.claude/skills/spec-review/SKILL.md 12行、99行、171行、177-178行、198行、201行
- requirements.md 範囲「審査役が何を審査するか、往復の上限の数、指摘の扱いは spec `spec-review` が決めた」: .kiro/specs/spec-review/design.md 13-45行
- requirements.md 範囲「作業の集計の表の形と所見の書き方は spec `ai-work-usage-report` が決めた」: .kiro/specs/ai-work-usage-report/design.md 14-26行
- design.md 概要・審査役の定義「審査役の定義は `model: claude-fable-5-1` で、使える道具は Read、Grep、Glob、Write、Bash」: .claude/agents/spec-reviewer.md 4-5行
- design.md /spec-review の手順「手順4は、`fable` ならモデルを指定せず、`opus` なら `model: opus` を指定する」: .claude/skills/spec-review/SKILL.md 110-112行
- design.md /spec-review の手順「手順1は `review_model` を起動のたびに読み直し、上限で替えたときも書き換えない」: .claude/skills/spec-review/SKILL.md 95-99行
- design.md /spec-review の手順「審査の範囲は、控え `.reviewed.md` と本文を `git diff --no-index` で比べて決める」: .claude/skills/spec-review/SKILL.md 100-107行
- design.md /spec-review の手順「上限の判定は、`Agent terminated early due to an API error:` の行の詳細が `limit` を含み、`529` と `Overloaded` を含まないこと」: .claude/skills/spec-review/SKILL.md 148-151行
- design.md /spec-review の手順「上限のときの切り替えの節」: .claude/skills/spec-review/SKILL.md 169-178行
- design.md /spec-review の手順「response の節の表の前の3行と、上限で止まった起動の量の行、量は `<usage>` の `subagent_tokens`」: .claude/skills/spec-review/SKILL.md 196-211行
- design.md /spec-review の手順「Step 7 の報告の見本の、往復ごとのモデルの行」: .claude/skills/spec-review/SKILL.md 259行、275-276行
- design.md 記録のフック「報告を `last_assistant_message`、無ければ `tool_input.message` から読む」: .claude/hooks/record-spec-review.sh 39-41行
- design.md 記録のフック「構造化ブロックの必須の項目と値の検証と完了の印」: .claude/hooks/record-spec-review.sh 46-81行
- design.md 記録のフック「`agent_transcript_path` があり、記録に `"model":` があるときだけ、モデルを grep で確かめる」: .claude/hooks/record-spec-review.sh 83-93行
- design.md 記録のフック「証跡は recorded_at feature stage cycle round status review_hash の7行」: .claude/hooks/record-spec-review.sh 107-118行
- design.md 記録のフック「フックは SubagentStop(matcher `spec-reviewer`)と PostToolUse(matcher `SubagentHandback`)に登録され、timeout は20秒」: .claude/settings.json 166-176行、320-330行
- design.md 記録のフック「フックは、JSON の値を perl の JSON::PP で読む `extract` を持つ」: .claude/hooks/record-spec-review.sh 25-34行
- design.md 記録のフック「フックが自分の置き場所からスクリプトを探す先例」: .claude/hooks/restore-after-compact.sh 69行(`lib="$(dirname "$0")/../scripts/parallel/lib.sh"`)。記録のフックは settings.json 172行と326行で `bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/record-spec-review.sh"` として呼ばれる。テストは `CLAUDE_PROJECT_DIR` を一時フォルダに向ける: .claude/hooks/tests/test-record-spec-review.sh 5-7行、57-60行
- design.md 新しいスクリプト「会話の記録の置き場所の候補は、`$HOME` と、Windows では `$USERPROFILE` の `.claude/projects`」: .claude/scripts/usage/extract.pl 471-481行
- design.md 新しいスクリプト「補助役の記録は、本体の会話の記録と同じフォルダの `<sessionId>/subagents/agent-<agentId>.jsonl`」: .claude/scripts/usage/extract.pl 289-293行、2026-11-13 にこの会話の `~/.claude/projects/<project>/<sessionId>/subagents/` に `agent-<id>.jsonl` と `agent-<id>.meta.json` があることを ls で確かめた
- design.md 新しいスクリプト「`message.model` が `<synthetic>` の行は Claude Code が自分で作った行で、上限で止まったときは `error` が `rate_limit`」: .claude/scripts/usage/extract.pl 736-745行
- design.md 新しいスクリプト「`.claude/scripts/` の下に spec-review のフォルダは無い」: 2026-11-13 に `ls .claude/scripts/` で ci-tool-signature memory parallel ship usage vuln-watch だけであることを確かめた
- design.md テストの方針「記録のフックのテストは5つの場合を持ち、場合の名前で選んで流す形になっていない」: .claude/hooks/tests/test-record-spec-review.sh 10行、全体128行
- design.md テストの方針「圧縮のあとの戻しのテストは、spec-reviewer.md の model が `claude-fable-5-1` であることと、要約の決まりの行に `Opus 5.5` があることを確かめる」: .claude/hooks/tests/test-restore-after-compact.sh 465-475行、533-543行、582行
- design.md テストの方針「集計のテストは本物の料金表を読み、価格の無いモデルの例に `claude-fable-5-2` を使う」: .claude/scripts/usage/tests/test-report.sh 16行、474行、477-479行
- design.md 料金表「`claude-opus-5-5` は fast の価格を持ち、`claude-fable-5-1` は持たない。`prices.checked_on` は `2026-10-26`」: .claude/scripts/usage/usage-config.json 4行、9-14行
- design.md 料金表の PR「集計は、価格が分からないモデルを `report.json` の `totals.usd_unknown_models` に並べ、`prices` に source と checked_on を書く」: .claude/scripts/usage/report.pl 98-122行、978-981行
- design.md 料金表の PR「fast の行は料金表の `fast` を使い、無ければそのモデルを価格が分からないものにする」: .claude/scripts/usage/report.pl 995-1024行
- design.md 料金表の PR「`price_of` は ID の末尾の `-<8桁の日付>` を外した名前でも価格を探す」: .claude/scripts/usage/report.pl 1026-1032行
- design.md 料金表の PR「`usage.sh draft` は、集計を作った作業フォルダの写しの `usage-config.json` を読み、下書きを `drafts/<N>/` に書く」: .claude/scripts/usage/usage.sh 483-485行
- design.md 料金表の PR「`usage.sh publish` が0で終わると、URL などの1行を出す。下書きは消さない」: .claude/skills/usage-report/SKILL.md 49-51行、.claude/scripts/usage/usage.sh 571行以降
- design.md 料金表の PR「commit と push は、単独の `git commit -F <ファイル>`、`git push -u origin <ブランチ>`、`git push origin <ブランチ>` だけが通り、ブランチは入力の cwd で判定する」: .claude/hooks/protect-main.sh 1-18行、43-60行
- design.md 料金表の PR「`.claude/worktrees/` と `.claude/.state/` は git の追跡の外」: .gitignore 7行、11行
- design.md 料金表の PR「Stop フックは、入力の cwd の git の最上位のいまのブランチの PR を見届ける」: .claude/hooks/check-ship-watch-before-stop.sh 45-65行
- design.md 料金表の PR「/ship の手順6は予約の確認、手順7は CI の見届けで、承認待ちは `wait-approval.sh` で待つ」: .claude/skills/ship/SKILL.md 手順6、手順7
- design.md 料金表の PR「PR の本文の Closes を機械で求める検査は無い。CI が作る PR は `Refs: N/A` を書く」: `grep -rln Closes .github/workflows .github/scripts` が close-linked-issues の3ファイルだけ、.github/scripts/ci-tool-version-update.sh 378行、422行、.github/scripts/backend-vuln-fix.sh 96行
- design.md 料金表の PR「codex-review の判定の基準は、Spec: のパス、無ければ `Refs: #N` の Issue の本文、無ければ PR の本文」: .github/workflows/codex-review.yml 167-186行
- design.md 料金表の PR「Issue の起票は、起票の前に所有者に1回確かめる」: .claude/skills/file-issue/SKILL.md 99-110行
- design.md プロジェクトの決まり「size-check がテストとして外すのは `.github/scripts/tests/**`、`.claude/hooks/tests/**`、`.claude/scripts/parallel/tests/**`、`.claude/scripts/ship/tests/**`」: .github/workflows/guardrails.yaml 220-223行
- design.md CLAUDE.md「審査役のモデルの既定の文は112行、要約の決まりの /spec-review の行は142行」: CLAUDE.md 112-114行、142行
- design.md 設計を見直すきっかけ「settings.json に model と、モデルの別名の解決先を固定する環境変数は無い」: 2026-11-13 に `grep -n 'SUBAGENT_MODEL\|DEFAULT_OPUS\|DEFAULT_FABLE\|"model"' .claude/settings.json` が何も出さないことを確かめた
- design.md ファイルの構成「`.claude/hooks/` の下の3つのファイルは、Claude が書けない」: .claude/settings.json 74-75行(`Edit(.claude/hooks/**)` と `Write(.claude/hooks/**)` が deny)。置き方は、.kiro/specs/ai-work-usage-report/tasks.md 503-504行の前例に合わせた
- design.md 部品 spec-review の手順「Step 2 の手順4の FORCE の例外。今の settings.json の env に `CLAUDE_CODE_SUBAGENT_MODEL` と `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` は無い」: .claude/settings.json 3-6行(env は `MSYS2_ARG_CONV_EXCL` と `CLAUDE_CODE_AUTO_COMPACT_WINDOW` だけ)。2026-11-13 の design の作り直しで開き直した
- design.md 部品 spec-review の手順と CLAUDE.md「冒頭の説明、Step 2 の手順1と手順4、Step 3、Step 4、Step 7 と、CLAUDE.md の審査役のモデルの決まりと要約の決まりに版の番号がある」: .claude/skills/spec-review/SKILL.md 12行、99行、110-112行、171行、177-178行、198行、201行、208行、210行、259行、275-276行、CLAUDE.md 112-114行、142行。2026-11-13 の design の作り直しで開き直した
- design.md ファイルの構成とテストの方針「test-restore-after-compact.sh の535行・542行・582行が版の番号を期待の値に持つ」: .claude/hooks/tests/test-restore-after-compact.sh 533-536行、538-552行、582行。2026-11-13 の design の作り直しで開き直した
- design.md 使う既存の仕組み「別名が本体の会話のモデルと同じ系統なら、本体の会話のモデルで動く」「起動時の指定、定義、環境変数の順。`CLAUDE_CODE_SUBAGENT_MODEL_FORCE` を1にしたときだけ環境変数が先」: 2026-11-13 に https://code.claude.com/docs/en/sub-agents の「Choose a model」の節を読み直した

## 公式の料金ページで読んだ価格(2026-11-13)

出どころ: https://platform.claude.com/docs/en/about-claude/pricing。単位は 100万トークンあたりの米ドル。

| モデル | 入力 | 5分のキャッシュの書き込み | 1時間のキャッシュの書き込み | キャッシュの読み込み | 出力 | 速い出力の入力 | 速い出力の出力 |
|---|---|---|---|---|---|---|---|
| Fable 5.2 | 8 | 10 | 16 | 0.20 | 40 | 16 | 80 |
| Fable 5.1 | 10 | 12.50 | 20 | 0.25 | 50 | 載っていない | 載っていない |
| Opus 5.5 | 4 | 5 | 8 | 0.20 | 20 | 8 | 40 |

ページは、速い出力のキャッシュの価格を値で載せず、「Prompt caching multipliers apply on top of fast mode pricing.」と倍率で示している。キャッシュの倍率は、5分の書き込みが入力の1.25倍、1時間の書き込みが2倍、読み込みが0.025倍(Fable 5.2 の通常の価格 8 → 10、16、0.20 と一致する)。Fable 5.2 の速い出力のキャッシュは、入力16に倍率を掛けて、5分の書き込み20、1時間の書き込み32、読み込み0.4 になる。

## 調べたこと

### 審査役を系統の最新のモデルで起動する方法

- きっかけ: 要件1。版の番号をファイルに書かずに、系統の最新のモデルで審査役を起動したい。
- 調べた先: Claude Code の公式の文書 sub-agents.md と model-config.md(2026-11-13、claude-code-guide の補助役が読んだ)。この会話での実測。
- 分かったこと:
  - 補助役の定義の `model` は、別名(`fable` `opus` など)、完全な ID、`inherit` を受け付ける。
  - モデルの優先の順は、Agent ツールの起動時の `model` の指定、定義の `model`、環境変数 `CLAUDE_CODE_SUBAGENT_MODEL`、本体の会話のモデルの順である。
  - Agent ツールの `model` に渡せるのは別名だけである。
  - 別名 `opus` などは、その Claude Code で使える最新のモデルに解決される。環境変数 `ANTHROPIC_DEFAULT_OPUS_MODEL` などで解決先を固定できる。
  - 2026-11-13 に、起動時に `model: fable` を指定した補助役が `claude-fable-5-2` で動き、`model: opus` を指定した補助役が `claude-opus-5-5` で動いた。
- 設計への影響: 定義を `model: fable` にし、/spec-review が起動のたびに `model: fable` か `model: opus` を指定する。起動時の指定が最も強いので、定義が古いまま残っても、環境変数があっても、審査役は指定した系統で動く。所有者が環境変数で別名の解決先を固定すると、その版で動く。これは所有者の設定の結果なので、仕組みでは止めない(設計を見直すきっかけに書く)。

### 審査役が実際に動いたモデルを読む場所

- きっかけ: 要件4と要件5。記録とフックに、実際に動いたモデルを書く。
- 調べた先: Claude Code の公式の文書 hooks.md と sub-agents.md。この会話の補助役の記録の実物。
- 分かったこと:
  - SubagentStop の入力には `agent_id`、`agent_type`、`agent_transcript_path`、`last_assistant_message` がある。PostToolUse の入力の `agent_transcript_path` は文書に無い。
  - 補助役の記録は `~/.claude/projects/<project>/<sessionId>/subagents/agent-<agentId>.jsonl` に置かれる。記録の assistant の行に `"model":"claude-opus-5-5"` のように実際のモデルが残る。
  - 同じフォルダの `agent-<agentId>.meta.json` に `"model":"opus","pickedEffortModel":"claude-opus-5-5"` が残る。`pickedEffortModel` は公式の文書に無い欄である。
  - Agent ツールの結果の文には `agentId: <id>` があり、知らせの `<usage>` には `subagent_tokens` がある。
  - 上限で止まった応答は、`message.model` が `<synthetic>` の行として記録に残る。
- 設計への影響: 実際に動いたモデルは、補助役の記録の、最後の `<synthetic>` でない assistant の行の `message.model` から読む。フックは `agent_transcript_path` から、Claude は Agent ツールの結果の `agentId` から記録を探す。読み方は1つのスクリプトにまとめ、フックと Claude が同じ規則で読むようにする。

### 料金表の PR のきっかけと作り方

- きっかけ: 要件7。集計を出したあとに、価格が分からないモデルを見つけて PR を作る。
- 調べた先: .claude/scripts/usage/report.pl、usage.sh、.claude/skills/usage-report/SKILL.md、.claude/skills/ship/SKILL.md、.claude/hooks/protect-main.sh、.claude/hooks/check-ship-watch-before-stop.sh、.github/workflows/codex-review.yml、.claude/skills/file-issue/SKILL.md。
- 分かったこと:
  - `report.json` の `totals.usd_unknown_models` は、料金表に無いモデルと、要る種類の価格(fast など)が料金表に無いモデルの両方を並べる。モデルの名前を読めなかった応答は「不明」として並ぶ。
  - `usage.sh draft` は、集計を作った作業フォルダの写しの料金表を読む。その作業フォルダが main より古いと、main にはすでに価格があるモデルが並ぶ。
  - commit と push は、対象の作業フォルダを cwd にした単独のコマンドでしか通らない。
  - Stop フックは cwd のブランチの PR を見届ける。
  - PR の本文の Closes を機械で求める検査は無い。codex-review は、Refs の無い PR では PR の本文を判定の基準にする。
  - Issue の起票は所有者への確認を要する。
- 設計への影響: 料金表の PR は、Issue を起票せず、`Refs: N/A` の PR にする。PR は、origin/main から作った専用の worktree で作り、/ship の手順6と手順7で見届ける。比べる相手の料金表は origin/main の料金表にする。

## 比べた案

| 案 | 中身 | 良い点 | 危うさ・限り | 判断 |
|---|---|---|---|---|
| 定義を別名にし、起動のたびに系統を指定する | 定義 `model: fable`、/spec-review が `model: fable` か `model: opus` を渡す | 版の番号がファイルから消える。起動時の指定が最も強い | 環境変数で解決先を固定されると、その版で動く | 採る |
| 定義を `inherit` にする | 本体の会話のモデルで審査役を動かす | 定義を直さずに済む | 本体と同じモデルになり、別のモデルで審査する意味がなくなる | 採らない |
| 定義に完全な ID を書き、版が出るたびに直す | 今のやり方 | 実際のモデルがファイルで分かる | 要件1の3に反する | 採らない |
| モデルを記録の `message.model` から読む | 補助役の記録の最後の assistant の行 | 公式の文書にある記録の形。実際の応答のモデル | 記録の形が変わると読めなくなる | 採る |
| モデルを `meta.json` の `pickedEffortModel` から読む | 起動時に選ばれたモデル | 1行で読める | 公式の文書に無い欄。起動しようとしたモデルで、要件4の1の「実際に動いたモデル」と違うことがある | 採らない |
| 料金表の PR を本体の作業フォルダで作る | 集計を出した作業フォルダで branch を切る | worktree を作らずに済む | 集計を出す作業フォルダは、マージを見届けた feature ブランチか本体の main で、その作業フォルダの変更を巻き込む | 採らない |
| 料金表の PR を専用の worktree で作る | origin/main から `.claude/worktrees/` の下に作る | 作業フォルダの変更を巻き込まない。Stop フックが cwd で PR を見届けられる | worktree の片付けが要る | 採る |
| 料金表の PR のために Issue を起票する | Issue を立てて `Closes` で閉じる | /ship の手順5の決まりに合う | 起票の前に所有者の確認が要り、要件7の7に反する | 採らない |

## 設計の判断

### 判断: 系統の別名で審査役を起動する

- きっかけ: 要件1、要件8。
- 比べた案: 上の表の「定義を別名にし、起動のたびに系統を指定する」「定義を inherit にする」「完全な ID を書く」。
- 選んだ案: 定義を `model: fable` にし、/spec-review の Step 2 の手順4で、`review_model` が `fable` なら `model: fable`、`opus` なら `model: opus` を、起動のたびに指定する。上限のときの切り替えは `model: opus` のままにする。
- 理由: 起動時の指定は、定義と環境変数より優先される。定義と起動の両方に系統を書けば、どちらかが古くなっても系統は変わらない。
- 引き換え: 審査役がどの版で動くかは、起動するまで分からない。実際に動いたモデルは、記録から読んで書く(次の判断)。

### 判断: 本体の会話と同じ版で動くことを、手順書と CLAUDE.md の文に書く

- きっかけ: design の審査の D1-2-5 で requirements に差し戻し、要件1の5と要件8の1が足された。D1-2-1 で、手順書と CLAUDE.md に書く文が「いつも最新で動く」と読めることを指摘された。
- 比べた案: (1) 本体の会話と同じ版で動く動きを、手順書の冒頭の説明、Step 3、CLAUDE.md の決まり、版を付けて伝えられたときの返事に書く。(2) 審査役の定義に完全な ID を書き、本体の会話と違う版で動かす。(3) Claude が、審査役が最新でない版で動いたことを見つけたら、所有者に尋ねる。
- 選んだ案: (1)。
- 理由: (2) は、新しいモデルが出るたびに定義を直すことになり、要件1の3と食い違う。(3) は、要件1の5が往復を止めず所有者に尋ねないと決めている。Claude は実際に動いた版を往復ごとの審査の記録に書くので、所有者は記録で確かめられる。
- 引き換え: 本体の会話が古い版で動いていると、審査役も古い版で動き続ける。

### 判断: 実際に動いたモデルを1つのスクリプトで読む

- きっかけ: 要件4、要件5。
- 比べた案: フックと /spec-review の手順にそれぞれ読み方を書く案と、1つのスクリプトにまとめる案。
- 選んだ案: 新しいスクリプト `.claude/scripts/spec-review/agent-model.pl` を作る。フックは `--transcript <path>`、Claude は `--agent-id <id>` で呼ぶ。スクリプトは、モデルの ID、系統、表示の名前(例 `Fable 5.2`)を出す。
- 理由: 一般化の観点で、フックが確かめる「系統」と、Claude が記録に書く「表示の名前」は、同じ ID から作れる。読み方を2か所に書くと、片方だけ直したときに食い違う。perl(JSON::PP)は、フックと集計の仕組みがすでに前提にしている。
- 引き換え: スクリプトが1つ増える。新しいライブラリは足さない。
- あとで確かめること: 実装の日に、上限で止まった補助役の記録に `<synthetic>` でない assistant の行が残るかどうか。残らなければ、上限で止まった Fable のモデルは「読み取れなかった」と書く。

### 判断: 料金表の PR を、集計のスキルの手順として Claude が作る

- きっかけ: 要件7。
- 比べた案: 集計のスクリプト(usage.sh)が PR を作る案と、集計のスキルの手順で Claude が作る案。
- 選んだ案: 集計のスキルに「料金表に価格を足す手順」を足し、Claude が公式の料金ページを読み、専用の worktree で料金表を直し、PR を作る。
- 理由: 料金ページを読んで価格を読み取るのは、スクリプトでは作り切れない(ページの形が変わる、倍率で示された価格がある)。使う道具を既存の仕組み(/ship の手順6と手順7、Stop フック)にそろえれば、新しい見届けの仕組みが要らない。作るか採るかの観点で、PR の見届けは /ship の既存の手順を採る。
- 引き換え: 手順が長くなる。手順は Claude が読むので、手順の誤りはテストでは見つからない。

### 判断: 料金表のテストの価格の無いモデルを架空の ID に替える

- きっかけ: 要件6。料金表に `claude-fable-5-2` を足すと、test-report.sh の場合 #2003 の期待値(価格の無いモデルとして `claude-fable-5-2` を使う)が外れる。
- 選んだ案: 場合 #2003 の価格の無いモデルを、架空の ID `claude-fable-9-9` に替える。あわせて、`claude-fable-5-2` の通常の行と fast の行の使用料を確かめる場合を足す。
- 理由: 価格の無いモデルの扱いを確かめるという場合の目的は変わらない。test-report.sh はすでに `claude-unknown-9` のような架空の ID を使っている。
- 引き換え: 既存のテストの期待値を変えるので、PR の本文に `Test-Change-Justification` を書く。

### 簡単にしたこと

- 料金表の PR のきっかけは、`usd_unknown_models` の1つの欄だけにする。集計の表の形と report.pl は変えない。
- モデルの表示の名前は、スクリプトが ID から作る。モデルの名前と表示の名前の対応表は持たない。
- 記録のフックの証跡の形は変えない。spec-review-scan.sh と check-spec-review-before-stop.sh は変えない。

## 危うさと手当て

- PostToolUse(SubagentHandback)の入力に `agent_transcript_path` があるかは、公式の文書に書かれていない。手当て: その経路では、今までどおりモデルの確かめを省いて証跡を書く。読み取れたときだけ、系統で判定する。
- 所有者が環境変数で別名の解決先を固定すると、審査役が古い版で動く。手当て: 記録に実際に動いたモデルが残るので、所有者が気づける。設計を見直すきっかけに書く。
- Claude Code の記録の形が変わり、`message.model` が読めなくなる。手当て: スクリプトは読めなければ空を返し、記録には「読み取れなかった」と書く。フックは、読めなければ今までどおり証跡を書く。系統が違うと読めたときだけ書かない。
- 上限で止まった補助役の記録に、実際のモデルの行が残らない。手当て: 上限で止まった Fable のモデルは「読み取れなかった」と書く(要件4の4)。
- 料金ページの形が変わり、Claude が価格を読み違える。手当て: PR の本文に読んだページの場所と日と値を書き、所有者が承認のときに確かめられるようにする。集計のテストに Fable 5.2 の価格を確かめる場合を足す。
- 料金表の PR の CI が赤になる。手当て: /ship の手順7のとおり Claude が見届けて直す。同じ失敗が3回続いたら止めて報告する。

## 出どころ

- [Claude Code の補助役の文書](https://code.claude.com/docs/en/sub-agents) — 定義の `model` と、起動時の指定の優先の順、補助役の記録の置き場所
- [Claude Code のモデルの設定の文書](https://code.claude.com/docs/en/model-config) — 別名の解決と、解決先を固定する環境変数
- [Claude Code のフックの文書](https://code.claude.com/docs/en/hooks) — SubagentStop の入力の欄
- [Anthropic の公式の料金ページ](https://platform.claude.com/docs/en/about-claude/pricing) — 各モデルの公表価格と、速い出力のキャッシュの倍率
