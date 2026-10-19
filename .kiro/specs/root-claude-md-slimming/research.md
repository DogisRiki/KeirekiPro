# 調査の記録

## 要約

- **機能**: `root-claude-md-slimming`
- **調べた範囲**: 既存の仕組みを広げる変更(Extension)として、Claude Code が文書を読み込む決まり、ルートの CLAUDE.md の記述の写しがある文書、PR の検査の作り、新しい会話で場面を動かす方法を調べた
- **主な発見**:
  - Claude Code がどの会話の始めにも読み込むリポジトリの文書は、ルートの CLAUDE.md、`.claude/CLAUDE.md`、`CLAUDE.local.md`、`paths` の前書きを持たない `.claude/rules/` の下の Markdown、それらが `@` で読み込みを指定した文書である。このリポジトリには、ルートの CLAUDE.md のほかのどれも無い
  - ルートの CLAUDE.md の記述 123 行を分けると、残す 80 行、短くして残す 21 行、移す 10 行、消す 12 行になる。移す行と消す行は、同じ決まりがスキルの本文か spec の書き方の基準にあり、その文書が要る場面で必ず読まれる。対応表のとおりに直すと、ルートの CLAUDE.md は 208 行・24,807 バイトから 141 行・17,917 バイトになる。PR #574 でマージしたときのルートの CLAUDE.md は、141 行・18,030 バイトである
  - `spec-need-triage` の要件10は、着手の判断の決まりをルートの CLAUDE.md に書くことを求める。そのため、着手の判断の決まりは、全文を `/start` のスキルに置いたまま、ルートの CLAUDE.md に短い文を残す(所有者が 2026-10-18 に選んだ。設計の審査の指摘 D1-1-10 への対応)
  - `claude -p` は、プロンプトの先頭の `/<スキル名>` を展開してスキルを動かす。そのため、Claude は、所有者が打つ spec の段階のコマンドも、使い捨ての写しの中の新しい会話で動かせる

## 調べたこと

### Claude Code が会話の始めと圧縮のあとに読み込む文書

- **出典**: https://code.claude.com/docs/en/memory (2026-10-18 に読んだ)
- **分かったこと**:
  - 会話の始めに読み込むのは、作業フォルダとその上のフォルダの `CLAUDE.md` と `CLAUDE.local.md`、`./.claude/CLAUDE.md`、`paths` の前書きを持たない `.claude/rules/` の下の Markdown(下のフォルダも含む)である。下のフォルダの CLAUDE.md(`backend/CLAUDE.md` など)は、Claude がそのフォルダのファイルを読んだときに読み込む
  - `@path` の読み込みは、読み込みを書いた文書から見た相対の道で解き、4段まで辿る。Markdown のコードの囲みとコードの区切り(バッククォート)の中の `@` は読み込みにならない。道に空白を含むときは、空白の前にバックスラッシュを置く
  - `AGENTS.md` は、既定では、CLAUDE.md が無いときだけ読み込む。参加者が設定の「Project instructions」を `claude-md-and-agents-md` にすると、CLAUDE.md と並べて `AGENTS.md` と `.claude/AGENTS.md` も読み込む
  - ブロックの HTML コメントは、文脈に入れる前に除かれる
  - 圧縮のあと、ルートの CLAUDE.md は読み直される。下のフォルダの CLAUDE.md と `paths` の前書きを持つ規則は、要るときにまた読み込まれる
  - 公式の文書は、1つの CLAUDE.md を200行より短くすることを勧めている
- **設計への影響**: PR の検査は、ルートの CLAUDE.md に加えて、ここに挙げた文書を、あれば測る。`AGENTS.md` は参加者の設定しだいで読み込まれるので、検査はあれば測る。HTML コメントは除かずに測る(測り方を単純にし、測った量を実際より小さく見せないため)

### 圧縮のあとにスキルの本文が戻る量

- **出典**: https://code.claude.com/docs/en/context-window の「What survives compaction」と、`.claude/hooks/restore-after-compact.sh`
- **分かったこと**: 圧縮のあと、実行中のスキルの本文は、1つのスキルにつき先頭の5,000トークン、全部で25,000トークンまでしか戻らない。このリポジトリでは、SessionStart のフック(`matcher: compact`)の `restore-after-compact.sh` が、決まり1として、実行中のスキルの SKILL.md を全文読み直させる
- **設計への影響**: 対応表は、スキルの本文に行き先がある決まりの「圧縮のあとにも読まれる理由」に、この決まり1を書く。圧縮のあとの場面は、この決まり1が実際に働くかを確かめる

### `claude -p` でスキルと圧縮を動かせるか

- **出典**: https://code.claude.com/docs/en/headless(2026-10-18 に読んだ)、https://code.claude.com/docs/en/commands
- **分かったこと**:
  - `-p` では、利用者が呼ぶスキルとカスタムのコマンドが動く。プロンプトに `/スキル名` を含めると、Claude Code がそれを展開してから動かす
  - `--resume <セッションID>` で、同じ会話を続けられる
  - `--output-format stream-json` は、出来事を1行1つの JSON で出す。補助役の出来事も `parent_tool_use_id` を持って流れる
  - コマンドの一覧は、`/compact` が `-p` で使えるかを書いていない
  - `CLAUDE_CODE_AUTO_COMPACT_WINDOW` は、会話がどれだけ埋まったら自動で圧縮するかを決める。このリポジトリは `.claude/settings.json` で 250000 にしている
- **設計への影響**: 場面を動かす仕組みは、最初に `claude -p --resume <ID> "/compact"` が圧縮を起こすかを試す。起こさなければ、`--settings` で `CLAUDE_CODE_AUTO_COMPACT_WINDOW` を下げて、自動の圧縮を起こす

### 場面の会話を決めた位置で止める方法と、CLI の引数

- **出典**: https://code.claude.com/docs/en/hooks の共通の JSON の出力(2026-10-18 に読んだ)、ホストの `claude --help`(2.1.292)
- **分かったこと**:
  - フックの出力の `continue` を `false` にすると、Claude はフックのあとに処理をすべてやめる。`continue` は、出来事ごとの判定の欄より優先される。`stopReason` は、利用者に見せる文である
  - 文書は、PreToolUse のフックが `continue: false` を返したときに、その道具が動くかを書いていない。そのため、止めるフックは、`continue: false` と一緒に、道具を断る判定(`permissionDecision` の `deny`)も返す
  - `claude --help` は、`--resume`、`--disallowedTools`、`--strict-mcp-config`(「--mcp-config の MCP のサーバーだけを使う」)、`--max-budget-usd` を挙げている。`--max-turns` は挙げていないので、場面を動かす仕組みは `--max-turns` に頼らない
  - InstructionsLoaded の出来事の `load_reason` は、圧縮のあとの読み込みで `compact` になる。SessionStart の `source` は、圧縮のあとに `compact` になる
- **設計への影響**: 圧縮のある場面は、本文を書く直前か、所有者に尋ねて止まったところで会話を止め、そこで圧縮する。そうすると、圧縮のあとの会話の動きで、移した決まりと消した決まりが行き先から読まれるかを確かめられる。頼る機能は、場面の前に1回ずつ試す(design.md の「頼る機能と試し方」)

### 同じ決まりの写しがある文書

- **出典**: リポジトリの中の文書(2026-10-18 の main)
- **分かったこと**:
  - 品質ゲートのコマンドは、`/verify-frontend` `/verify-backend` `/verify-terraform` の各スキルの「Steps」に、同じコマンドが同じ順で書いてある
  - spec の要否の4つの観点の表と「3つの材料」「1回尋ねれば決まる」の箇条は、`.claude/skills/start/SKILL.md` の「観点の定義」に同じ文で書いてある
  - PR 本文の `Refs:` と `Closes` の決まりは、`.claude/skills/ship/SKILL.md` の「Steps」の手順5と「Rules」に書いてある
  - 各段階の生成のあとに `/spec-review` を流す決まりは、cc-sdd の各スキルの「Right After Generation (before approval)」に書いてある
  - 残す決まりの写しが、`.claude/loop.md` の「制約:」、`.kiro/steering/tech.md` の「開発環境」と「品質基準」、verify のスキル、start のスキルにある
- **設計への影響**: 対応表(`mapping.md`)に、行ごとの行き先と、写しを消す箇所と、参照の直しを載せた

### PR の検査の作り

- **出典**: `.github/workflows/guardrails.yaml`、`.github/scripts/check-escape-hatches.sh`、`.github/CODEOWNERS`、`.github/audit/required-checks.json`
- **分かったこと**:
  - `guardrails.yaml` は、`pull_request`(main 向け)と `pull_request_review` で起動し、ワークフローの先頭の `env` に `PR_SIZE_LIMIT: '200'` を持つ。ジョブ `size-check` は、PR の head を checkout し、スクリプトのテストを流してから検査のスクリプトを呼ぶ
  - `.github/` と `.claude/` の下の変更は、CODEOWNERS の必須の承認と、`check-escape-hatches.sh` の節6(所有者の Approve が無ければ失敗)の2つで、所有者が承認するまでマージされない
  - 必須のチェックを足すときは、期待一覧にも登録する。登録したチェックだけを、週次の監査が、スキップのままマージされたかと、ブランチの決まりとの食い違いで確かめる
- **設計への影響**: 新しい検査は、`guardrails.yaml` の新しいジョブとして作り、上限の値を `env` に置く。上限の値と測り方は `.github/` の下にあるので、上げる変更と外す変更は、既存の仕組みのまま所有者の承認を待つ

## 構成の比べ方

| 案 | 中身 | よい点 | 困る点 | 結論 |
|---|---|---|---|---|
| A. `@` で別の文書に分ける | ルートの CLAUDE.md を、`@` で読み込む複数の文書に分ける | ルートのファイルは短くなる | 読み込んだ文書も会話の始めに読み込まれるので、文脈の量は減らない | 採らない |
| B. `paths` 付きの `.claude/rules/` に移す | 特定の場所のファイルを扱うときだけ要る決まりを、`paths` の前書きを持つ規則にする | 要るときだけ読み込まれる | ルートの CLAUDE.md には、特定の場所のファイルにだけ効く決まりが無い。規則が読み込まれるのは Read・Write・Edit のときだけで、スキルの場面とは合わない | 採らない |
| C. 要る場面で必ず読まれる既存の文書に移すか、同じ決まりがある文書に任せて消す | スキルの本文と spec の書き方の基準に行き先を決める | 要る場面でスキルの本文が読まれ、圧縮のあとも決まり1で全文が読み直される | 行き先がスキルの本文なので、`.claude/` の下の変更になり、所有者の承認が要る | 採る |

## 決めたこと

### 決めたこと: 移す先はスキルの本文と spec の書き方の基準に限る

- **背景**: 移した決まりは、要る場面で必ず読まれ、圧縮のあとにも読まれなければならない
- **比べた案**:
  1. steering(`.kiro/steering/`)に移す
  2. スキルの本文と `.kiro/settings/rules/spec-writing.md` に移す
- **選んだ案**: 2
- **理由**: steering は、スキルが読むよう指示したときだけ読まれ、圧縮のあとに読み直す仕組みが無い。スキルの本文は、そのスキルを動かしている間は読まれていて、圧縮のあとは決まり1が全文を読み直させる。`spec-writing.md` は、spec の各段階のスキルが Step 1 か Step 2 で読むよう指示している
- **引き換えにすること**: 移す決まりは、spec の書き方の基準に入る「Issueの印」の 10 行だけになり、ほかは「消す」「短くして残す」「残す」のどれかになる

### 決めたこと: ほかの spec が求める着手の判断の決まりは、短くして残す

- **背景**: 設計の1回目の審査(D1-1-10)が、着手の判断の決まり(観点の表、3つの材料、1回尋ねれば決まる、行数を判断に使わないこと、問いの答えを待つこと、まとめる相手を探すこと)を消すと、`spec-need-triage` の要件10の受入基準1と2(ルートの CLAUDE.md に書くこと)と食い違うと指摘した
- **比べた案**:
  1. 求められた中身を、ルートの CLAUDE.md に短い文で残し、全文は `/start` のスキルに置く
  2. 全文をルートの CLAUDE.md に残す
  3. `spec-need-triage` の要件を書き直し、ルートの CLAUDE.md から消す
- **選んだ案**: 1(所有者が 2026-10-18 に選んだ)
- **理由**: ほかの spec の本文を書き直さない(この spec の範囲)まま、求められた中身をルートの CLAUDE.md に置ける。全文は、着手のときに必ず読まれる `/start` のスキルにあり、圧縮のあとも決まり1で読み直される
- **引き換えにすること**: 短くして残す文の分だけ、ルートの CLAUDE.md が長くなる(案3に比べて約1,000バイト)

### 決めたこと: 上限は 19,000 バイトにする

- **背景**: 要件5の7は、軽くしたあとの量をもとに上限を決めることを求める
- **比べた案**:
  1. 行の数で測る(公式の文書の200行の目安)
  2. バイトの数で測る
- **選んだ案**: 2。上限は、軽くしたあとの 17,917 バイトに約1,000バイトのゆとりを足し、500バイトの単位に切り上げた 19,000 バイトにする。この値は、場面で確かめる前の下書きの量から決めた。PR #574 でマージしたときのルートの CLAUDE.md は 18,030 バイトで、上限の中にある。場面の結果で決まりを「残す」に戻したときは、同じ決め方で決め直す
- **理由**: このリポジトリの CLAUDE.md は1行が長く、行の数は文脈の量を表さない。バイトの数は、日本語の文の多いこの文書で文脈の量とほぼ比例する。ゆとりの約1,000バイトは、設計のあとに main で足される決まり(要件2の6)を、PR を出すまでに対応表へ取り込める量である
- **引き換えにすること**: 決まりを1つ足すたびに、ゆとりが減る。ゆとりが尽きたら、Claude は決まりを移すか短くするか、上限を上げる理由を添えて所有者に提案する

### 決めたこと: 場面は使い捨ての写しの中の `claude -p` で動かす

- **背景**: 要件3の7と8は、場面の会話が外へ何も送らず、所有者の作業フォルダとほかのセッションの記録を変えないことを求める
- **比べた案**:
  1. 今の作業フォルダで補助役(Agent ツール)に場面を動かさせる
  2. 使い捨ての写しの中で、新しい `claude -p` の会話を動かす
- **選んだ案**: 2
- **理由**: 補助役は、新しい会話の始めの読み込みを再現せず、スキルのコマンドも打てない。使い捨ての写しの中の会話は、変更後の文書を読み込んだ新しい会話になる。並行作業の記録は `git rev-parse --git-common-dir` の下に置かれるので、写しの中の会話の記録は、所有者の作業フォルダの記録と混ざらない
- **引き換えにすること**: ホストの `claude` に、所有者が一度ログインする必要がある(2026-10-18 に、ホストの Claude Code 2.1.292 はログインしていなかった)

## 危ないことと備え

- 移した決まりを、要る場面で Claude が読まない。備え: 要件3と要件4の場面で確かめ、不合格なら行き先か書き方を直す
- `/compact` が `-p` で動かない。備え: 自動の圧縮の閾値を下げる方法に切り替える
- 場面が頼る機能のどれかが、文書のとおりに動かない。備え: 場面の前に機能を1回ずつ試し、動かなければその場面を動かさずに所有者に報告する。Claude は合格の条件を自分で変えない
- 場面の会話が、所有者の作業フォルダかほかのセッションの記録を変える。備え: `run-scene.sh` が場面の前後で作業フォルダの状態を比べ、並行作業の記録に場面のセッションの ID と写しの道が無いことを確かめる
- 場面の会話が外へ送ろうとする。備え: 存在しない送り先、push を止めるフック、書き込みを断る `gh` の身代わり、外への道具の禁止を重ねる
- 検査がコードの区切りの中の `@` を読み込みと取り違える。備え: 検査のテストに、区切りの中の `@` を読み込みとしない場合を入れる(ルートの CLAUDE.md には `` `@dependabot recreate` `` がある)

## この spec の範囲の外で見つけたこと

次のことは、この spec では直さず、所有者に報告するだけにする。

- `.claude/loop.md` の手順5は push を含み、同じ文書の「制約:」の「このループからは commit/push しない」と食い違う
- `.claude/skills/kiro-spec-design/SKILL.md` の「If Design Approved」が、使わないことになっている `/kiro-validate-design` を勧める
- `.claude/skills/kiro-spec-init/SKILL.md` の Step 1 と `.claude/skills/kiro-spec-batch/SKILL.md` が、使わないことになっている `/kiro-discovery` に触れる
- `.claude/skills/kiro-spec-batch/SKILL.md` は、AI から起動できる形のままである
- ほかの spec の設計が、ルートの CLAUDE.md にあった決まりの置き場所を、今の場所のまま書いている。`spec-need-triage` の design.md(観点の表が `/start` と CLAUDE.md に同じ文である、という記述とそのテスト)、`spec-review` の design.md、`container-image-vulnerability-scanning` の design.md、`parallel-sessions` の design.md である。要件の範囲のとおり、この spec はほかの spec の本文を書き直さない

## 出典

- [How Claude remembers your project](https://code.claude.com/docs/en/memory): 会話の始めと圧縮のあとに読み込む文書、`@` の読み込み、`AGENTS.md`
- [Context window](https://code.claude.com/docs/en/context-window): 圧縮のあとに戻るもの
- [Run Claude Code programmatically](https://code.claude.com/docs/en/headless): `-p` でのスキルの呼び出し、`--resume`、`stream-json`
- [Commands](https://code.claude.com/docs/en/commands): `/compact`
