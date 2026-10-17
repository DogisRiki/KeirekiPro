# 調査と設計の判断の記録

## まとめ

- **Feature**: `claude-usage-reduction`
- **調べ方**: Extension(既存の Claude Code の設定・フック・スキルに足す)。公式文書と、過去2週間(2026-10-03〜2026-10-17)の会話の記録の実測をもとにした
- **主な発見**:
  - 使う量の大半は、長く育った親の会話を呼び出しのたびに読み直す分である。Opus 5.5 は既定で 1M の文脈を使い、自動の圧縮は約967Kまで起きない。上限を下げる設定は、今はどこにも無い
  - 会話を圧縮しても、文脈は約10万トークンから再開する。そのため、上限を設けたときの1回の呼び出しの平均は (10万+上限)/2 前後になり、上限だけでは全体の約2割しか減らない
  - 圧縮のあとも作業を続けるための材料(Issue・spec・審査の記録・tasks.md・並行作業の記録)は、ほとんどファイルにある。会話の中にしか無い状態は、審査の往復の途中の判断や、所有者への問いの答え待ちなど、限られている

## 調べたこと

### 使う量の内訳(過去2週間の会話の記録)

- **きっかけ**: Issue #566 の「やりたいこと」(全体を見て主な原因を見つける)
- **調べたもの**: `~/.claude/projects/` の下の、このリポジトリのすべての会話の記録(jsonl)。親の会話と、補助役(サブエージェント)の記録を、`message.id` と `requestId` で重複を除いて集計した。重みは API の料金の比率(入力1、キャッシュの書き込み 5分 1.25・1時間 2、キャッシュの読み込み 0.1、出力5)で付けた
- **分かったこと**:
  - モデル別: Opus 5.5 が 90.5%、Fable 5.1 が 9.3%
  - 役割別: 親の会話 62.4%、general-purpose の補助役(ほぼ `/kiro-impl` の実装役・確認役)19.3%、spec-reviewer(Fable)8.5%、kiro-implementer 3.1%、spec-style-checker 2.6%、spec-reviewer(Opus)2.4%
  - 重みの内訳: Opus のキャッシュの読み込みが 23.2億トークンで、全体の重みの約66%。出力は約6%
  - 親の会話の1回の呼び出しの文脈は、平均約31万、最大96.8万。親の会話の重みの54%が文脈40万超、79%が20万超の呼び出しから出ている
  - 上位7つの会話で全体の約70%。どれも1つの Issue を requirements から出荷まで1つの会話で進めたもの
  - キャッシュ切れの書き直し(10万超を書き直した呼び出し)は23回で、親の会話の7.1%。76万の書き直しが複数あった
  - 親の会話の重みを、そのとき動いていたスキルの段階で分けると、kiro-impl 20.5%、kiro-spec-tasks 15.3%、ship 14.5%、kiro-spec-design 13.1%、spec-review 9.1%、start 7.9%、kiro-spec-requirements 3.1%、その他
  - 補助役の呼び出しで文脈が20万を超えるものは少ない(重みで general-purpose 6.6%、spec-reviewer 13.9%、kiro-implementer 9.5%)
- **設計への影響**: 直す対象の中心は、親の会話の文脈の大きさである

### 圧縮のあとに文脈がどこから再開するか

- **きっかけ**: 上限を設けたときの効き目を見積もるため
- **調べたもの**: 過去に自動の圧縮が起きた4回の会話の記録(`compact_boundary` の記録と、その直後の呼び出しの文脈)
- **分かったこと**:
  - 圧縮の直後の文脈は 63,432 / 87,889 / 90,402 / 109,569 トークンだった。最新(2026-10-05)が 109,569 である
  - 親の会話の記録には、`"type":"system","subtype":"compact_boundary"` の行が残り、`compactMetadata` に `trigger`(`auto` など)、`preTokens`、`postTokens` が入る。圧縮の要約は `isCompactSummary: true` の発言として残る
  - 公式文書(context-window「What survives compaction」)によれば、圧縮のあとに戻るのは、システムの指示と道具、最上位の CLAUDE.md と auto memory(ディスクから読み直す)、起動したスキルの本文(1つ5,000トークン・合計25,000トークンまで)、最近触ったファイル最大5つ(1つ5,000トークンまで)である
- **設計への影響**: 圧縮の基底は約10万トークンで、これは上限の値では下げられない

### 上限の値ごとの試算

- **きっかけ**: 上限の値を決めるため(要件2の1)
- **調べたもの**: 親の会話の記録の呼び出しを順にたどり、文脈が上限を超えたら圧縮して基底に戻す形で、使う量を計算し直した。圧縮1回の費用(圧縮の直前の文脈を1回読む分、要約の出力1.5万、基底の書き直し)も足した
- **分かったこと**(基底10万のとき。全体に対する減り方は、親の会話が全体の62.4%であることから換算した):

  | 上限 | 親の会話の減り方 | 全体の減り方 | 圧縮の回数(2週間・69会話) |
  |---|---|---|---|
  | 15万 | 27.0% | 16.8% | 191 |
  | 20万 | 34.5% | 21.5% | 84 |
  | 25万 | 34.2% | 21.3% | 48 |
  | 30万 | 31.6% | 19.7% | 36 |

  基底を7万にすると、20万で全体の25.2%、25万で23.6%だった
- **設計への影響**: 20万と25万は、減り方がほぼ同じで、25万のほうが圧縮の回数が少ない。圧縮のたびに会話の一部を読み直せなくなるので、回数が少ないほうが要件3の危険が小さい

### Claude Code の設定とフック(公式文書)

- **きっかけ**: 上限と、圧縮のあとの続け方を、どの仕組みで作れるかを確かめるため
- **調べたもの**: code.claude.com/docs/en/ の settings-reference、model-config、env-vars、sub-agents、context-window、costs、how-claude-code-works、hooks、hooks-guide、skills、tools-reference、desktop、prompt-caching(2026-10-17 に取得)
- **分かったこと**:
  - `autoCompactWindow` は 100000〜1000000 のトークン数で、どの設定ファイル(プロジェクトの `.claude/settings.json` を含む)でも効く。同じファイルの中では `/autocompact` が保存する `modelSettings` の値が勝つ
  - 環境変数 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` は、設定の値・`/autocompact`・`--autocompact` のすべてより優先され、親の会話にもサブエージェントにも効く
  - サブエージェントも、自分の文脈が上限に達すると自動で圧縮される
  - CLAUDE.md に `# Compact instructions` の節を置くと、要約に残すものを指示できる(costs の例)
  - SessionStart のフックの matcher `compact` は、自動と手動の圧縮のあとに動き、標準出力か `hookSpecificOutput.additionalContext` で、圧縮のあとの文脈に文を足せる
  - `PreCompact` は圧縮を止められるが、要約に指示を足す方法は無い。`PostCompact` は結果を変えられない
  - `idleCompaction` は「対話型のターミナルのセッション」が条件で、Desktop で動くかは文書に無い
  - Desktop は「CLI と同じ設定ファイルを読む」とある。Desktop が起動するときの環境ですでに決まっている変数は、設定ファイルの `env` で上書きされない
  - クレジットで使うと、親の会話のキャッシュは1時間から5分に縮む(prompt-caching)
  - 補助役は所有者に尋ねる道具(AskUserQuestion)を使えない(sub-agents)
  - フックの共通の入力の欄(hooks、2026-10-17 に取得): `agent_id` は「Unique identifier for the subagent」で、フックが補助役の会話の中で動いたときに入る。`agent_type` は、会話の全体を `--agent` で動かしたときにも入る。設定ファイルのフックは補助役の会話の中でも動くが、文書が明記しているのは PreToolUse などの道具のイベントで、SessionStart が補助役の会話で動くかは書かれていない
- **設計への影響**: 上限は環境変数で置く。圧縮のあとの続け方は、CLAUDE.md の節と SessionStart(compact) のフックで作る

### このリポジトリで状態がどこにあるか

- **きっかけ**: 圧縮のあとに読み直せる状態と、会話にしか無い状態を分けるため(要件3)
- **調べたもの**: `.claude/settings.json`、`.claude/hooks/`、`.claude/scripts/parallel/`、`.claude/skills/{start,spec-review,kiro-impl,ship,kiro-spec-*}/SKILL.md`、`.github/CODEOWNERS`
- **分かったこと**:
  - ファイルにある状態: spec.json(段階と承認、`review_model`)、`reviews/{段階}-review.md` の `## サイクル<N> 往復<M>` の見出しと最終行、`reviews/{段階}-response.md` の処置の表、`.claude/.state/spec-review/` の控え(`.reviewed.md`・`.pending.md`・`.evidence`)、tasks.md の `[x]`、並行作業の記録 `<git common dir>/keirekipro-parallel/issues/<N>.json`(`folder` と `branch`)、Issue の本文の「決めた方式」
  - 会話にしか無い状態: spec-review の往復の途中の判断(指摘ごとの受け入れと却下を response.md に書く前)、点検で直さなかった外れの控え(style.md に書く前)、`CHANGED` の有無、Fable から Opus に替えた事実(response.md に書く前)、`/start` の問いの答え(Issue に書き足す前)とまとめる提案への答え、所有者が会話で伝えた審査役のモデル(spec.json に書く前)、tasks の承認の返事(spec.json に書く前)、kiro-impl の検査のコマンドと REJECTED・debug の回数、ship の「同じ失敗が3回」の回数
  - 今の SessionStart のフックは `session-registry.sh` だけで、matcher が無く compact でも動く。会話に差し込むのはセッションのIDの1文だけである。compact のときは `responding` を変えない
  - `.claude/settings.json` と `.claude/hooks/` は、permissions の deny で Claude が書けない。`.claude/` の下は CODEOWNERS で所有者の承認が要る。CLAUDE.md は承認の対象外である
  - フックのテスト(`.claude/hooks/tests/`)は CI では流れず、手元で流す。shellcheck は CI(guardrails.yaml)がすべての .sh にかける
- **設計への影響**: フックは、ファイルから読める状態を差し込む。会話にしか無い状態は、CLAUDE.md の要約の指示で要約に残させる

## 案の比べ方

| 案 | 中身 | よいところ | 危ないところ・限り | 判断 |
|---|---|---|---|---|
| A | 上限(環境変数)+要約の指示(CLAUDE.md)+圧縮のあとに状態を差し込むフック+ spec-review の再開の決まり | ターミナルと Desktop の両方に、操作を足さずに効く。リポジトリに入れるだけで全員に効く | 全体の減り方は約2割。圧縮のたびに会話の一部を読み直せなくなる | 採る |
| F | A に加え、段階のコマンドを `context: fork` で別の補助役の会話で動かす | 基底が約5.6万で、A より数ポイント多く減る(見込み24〜28%) | 補助役は所有者に尋ねられない。fork の考える深さが親と同じになるかは文書に無い。Desktop での動きが未確認。スキルの書き換えが大きい | 採らない |
| G | 所有者の案。Desktop の start_session で、段階ごとに新しい会話を開く | 段階の境目で区切れる | Desktop にしか無い機能で、ターミナルでは所有者が手で切り替える。並行作業の記録が前の会話を作業中と見て、所有者に「やめたか」を尋ねる | 採らない |
| Bash 出力の上限 | `bashOutputMaxChars` を小さくする | 会話の伸びが鈍る | 上限があると平均の文脈はほぼ (基底+上限)/2 で決まり、伸びの速さでは変わらない。圧縮の回数が減るだけ | 採らない |
| スキル本文の分割 | start(73KB)などを分ける | 圧縮の前の文脈が少し小さくなる | 圧縮のあとはスキルの本文が5,000トークンまでしか戻らないので、基底は変わらない | 採らない |
| CLAUDE.md の縮小、モデルや考える深さを下げる | 全呼び出しの固定分か、1回の重さを下げる | 減り方は大きい見込み | 判断の材料と判断の質に響き、要件4に反する | 採らない |

## 設計の判断

### 判断: 上限を環境変数 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` で 250000 にする

- **きっかけ**: 要件2(1回の呼び出しの上限)と要件5(全員に同じく効く)
- **比べた案**:
  1. `autoCompactWindow` の設定のキー — 同じファイルの `modelSettings` や参加者の `/autocompact` に負けることがある。サブエージェントに引き継がれるかが明記されていない
  2. `CLAUDE_CODE_AUTO_COMPACT_WINDOW` の環境変数 — すべてに優先し、サブエージェントにも効くと明記されている
  3. `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` — 200K の窓になるが、値を選べない
- **選んだもの**: 2。`.claude/settings.json` の `env` に置く。値は 250000
- **理由**: 試算で20万と25万の減り方はほぼ同じで、25万は圧縮の回数が約6割になる。補助役の会話も25万を超えることがまれになり、審査役の会話が途中で縮む場面が少ない
- **引き換え**: 参加者が自分の `/autocompact` で値を変えても、この値が勝つ
- **あとで確かめること**: Desktop の会話で上限が効くこと(要件6の確かめで見る)

### 判断: 圧縮のあとに続けるための材料を、ファイルから差し込み、会話にしか無いものは要約に残させる

- **きっかけ**: 要件3
- **比べた案**:
  1. 会話にしか無い状態を、すべてファイルに書く決まりをスキルごとに足す — スキルの書き換えが多く、書き忘れが残る
  2. 要約の指示とフックで補う — 1か所の指示と1つのフックで済む
- **選んだもの**: 2。あわせて、spec-review だけは、ファイルから往復の位置を決め直す決まりをスキルに足す。往復の位置を取り違えると、終えた審査をやり直すか、審査を飛ばすことになり、要件3の2に直接触れるためである
- **あとで確かめること**: 要約に、指示した項目が残ること(要件6の確かめで見る)

### 判断: 効き目の確かめは、仕組みを足さずに、マージのあとに Claude が会話の記録を1回読んで行う

- **きっかけ**: 要件6。一度きりの作業のために、リポジトリに仕組みを足さない
- **選んだもの**: 確かめの手順は tasks.md に書く。記録を読むスクリプトは、確かめるときに scratchpad に作る

## 危ないところと手当て

- 上限だけでは全体の約2割しか減らない — 所有者は要件1を直し、週の7日目は求めないと決めた。確かめの結果を所有者に示す
- 週次制限が使う量をどう数えているかは公開されていない — 試算は API の料金の比率による目安である。所有者は Claude の画面で効き目を見る
- 圧縮で、会話にしか無い判断が要約から落ちる — CLAUDE.md の要約の指示に項目を並べ、フックがファイルから読める状態を差し込む。要件6の確かめで、尋ね直しとやり直しが無いかを見る
- 圧縮のあと、スキルの本文は5,000トークンまでしか戻らない(spec-review は約22KB、start は約73KB) — フックの差し込みと要約の指示で、実行中のスキルの SKILL.md を読み直させる
- Desktop の worktree の会話は、本体の作業フォルダの設定とフックを読む(#539) — マージのあと、所有者が本体の作業フォルダを最新の main にしてから会話を始める(今の進め方のまま)。確かめの頼みで、このことを添える
- 古い Claude Code では環境変数が効かないおそれがある — 文書に最小の版の記載が無い。参加者の Claude Code は自動で更新される

## 参照

- [Settings reference](https://code.claude.com/docs/en/settings-reference) — `autoCompactWindow`、`idleCompaction`、`bashOutputMaxChars`
- [Model configuration](https://code.claude.com/docs/en/model-config) — 1M の窓と、既定の圧縮の時期(約967K)
- [Environment variables](https://code.claude.com/docs/en/env-vars) — `CLAUDE_CODE_AUTO_COMPACT_WINDOW`、`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
- [Subagents](https://code.claude.com/docs/en/sub-agents) — 補助役の自動の圧縮、入れ子、AskUserQuestion が使えないこと
- [Context window](https://code.claude.com/docs/en/context-window) — 圧縮のあとに残るもの
- [Manage costs](https://code.claude.com/docs/en/costs) — `# Compact instructions` の例
- [Hooks](https://code.claude.com/docs/en/hooks) と [Hooks guide](https://code.claude.com/docs/en/hooks-guide) — SessionStart の matcher `compact`、PreCompact、PostCompact
- [Prompt caching](https://code.claude.com/docs/en/prompt-caching) — クレジットのときの5分のキャッシュ
- [Desktop](https://code.claude.com/docs/en/desktop) — 設定ファイルの共有と `env` の扱い
- [Models, usage, and limits in Claude Code](https://support.claude.com/en/articles/14552983-models-usage-limits-in-claude-code) — 長い会話ほど使う量が増えること
