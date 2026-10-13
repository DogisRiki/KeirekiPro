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
