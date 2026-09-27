# tasks レビュー記録: spec-review

## サイクル1 往復1(2026-09-27)

審査の材料: `tasks.md`(全文)/ `requirements.md`(全文。L11-15 の Boundary Context、要件1〜8 の受入基準すべて)/ `design.md`(全文。L25-54 の Boundary Commitments、L125-162 の File Structure Plan、L205-248 の Requirements Traceability と Components、L338-366 の Testing Strategy を重点)/ `spec.json`(requirements・design とも `approved_by: "DogisRiki"`、tasks は `generated: true` `approved: false`)/ Issue #193 本文と4本のコメント(`gh issue view --comments` で取得。§C の捨て spec の手順、§12 の分担、§15 の後で判断すること)/ steering 3本 / `.kiro/settings/templates/specs/tasks.md`(完了条件の4項目)/ `.claude/skills/kiro-spec-tasks/rules/tasks-generation.md`(§8 Code-Only Focus、`(P)` と `_Boundary:_` の規則)/ `.claude/skills/kiro-impl/SKILL.md`(`[x]` の扱い)/ `.claude/skills/kiro-spec-tasks/SKILL.md` L130-133(承認の尋ね方)/ 実装の実物: `.claude/skills/spec-review/SKILL.md` と `rules/` 4本、`.claude/agents/spec-reviewer.md`、`.claude/hooks/` の8本すべて(作業ツリーの版)、`.claude/settings.json`(フック登録5か所と deny)、`CLAUDE.md`(L68-81 と L94-128)、`README.md`(L332-337 と L397)/ `.github/workflows/codex-review.yml` L160-165 / `.github/scripts/tests/`(シェルテストの器の有無)/ `.claude/.state/spec-review/`(証跡2件とカウンタ)/ `.kiro/specs/` 配下の spec.json 6件(`zz-hook-probe` が残っていないこと)/ `reviews/requirements-review.md` と `requirements-response.md`(R1-1-10、R3-2-1〜R3-2-3)/ `reviews/design-review.md` と `design-response.md`(D2-1-4、D4-1-1、D4-2-1、サイクル4 往復2の項目15の独立確認)。`brief.md` は無い。

このレビュー役はシェルを実行できず `git diff` `gh pr view` も使えないため、「実際の成果物」は作業ツリーの現在の内容と、記録ファイルに書かれた実測の記述との突き合わせによる。tasks の初回であり、前回の記録と却下された指摘は無い。

### 依頼1: 要件カバレッジと design カバレッジ

**要件カバレッジ(欠落なし)**: 受入基準 1.1〜8.7 の全項目を `_Requirements:_` と突き合わせた。8.4 を除くすべてが少なくとも1つのタスクに現れ、8.4 は「意図的に対象外」の節に理由付きで書かれている。存在しない番号を参照するタスクは無い。後から足された 8.5〜8.7 は、8.5・8.6 がタスク6.1、8.6・8.7 がタスク6.2 に現れ、design の Requirements Traceability(L233-235)と Components の「既存フック4本」の行(L248)に対応する。

**design カバレッジ(欠落なし)**: design の8コンポーネント(スキル・レビュー役・rules・フック4本・既存フック4本)はタスク1〜3・6 に、Modified Files の4種(`settings.json` `CLAUDE.md` `README.md` 既存フック)はタスク3.5・4・6 に、契約(構造化ブロック・走査の出力形式・証跡の項目・カウンタ)はタスク1.3・3.1〜3.3 に、Testing Strategy の15項目はタスク5.1(1〜8)・5.2(9〜12)・6.2(13〜15)に割り当てられている。`_Boundary:_` はすべて File Structure Plan に載るファイルの範囲に収まる。

### 依頼2: 完了条件の4項目

4項目はすべて書かれている。2項目目(verify の実行)は「変更領域に該当する verify Skill が無い」ことと「フックにテストの器が無い」ことを理由に実機確認へ置き換えており、理由は妥当である(`.github/scripts/tests/` にはCIスクリプト用のシェルテスト17本があるが、`.claude/hooks/` 用のものは無い)。4項目目も「止まるべき状態で止まることを先に確かめる」形に置き換わっており、赤の確認と同じ趣旨を保っている。ただし、2項目目が求める「結果を記録する」の記録が見当たらない点を T1-1-1 で扱う。

### 依頼3: スコープ膨張

requirements の Out of scope(実装コードのレビュー、spec の生成、別ベンダー)、design の Non-Goals(同3点と偽装防止)、Out of Boundary(cc-sdd のスキル本体、`codex-review.yml` の判定ロジック、承認フラグの書き込み規則)のいずれにも当たる作業は無い。タスク5.2 が `codex-review.yml` に触れるのは読んで確かめるだけで、変更しない。タスク6 の既存フックと `CLAUDE.md` の Git規約は、requirements In scope(L13)と design This Spec Owns(L34)に入っている。膨張は無い。

### 依頼4: `[x]` の観測条件と実物の突き合わせ

| タスク | 観測条件 | 実物 | 一致 |
|---|---|---|---|
| 1.1 | `rules/common.md` にレベル・申告・ID・書式・処置 | すべて有る(L5-13、L41-52、L28-39、L58-92、L94-104) | 一致 |
| 1.2 | rules 3本に要件2.3〜2.6 の全項目 | requirements 8項目、design 8項目(2.6 は観点3)、tasks 9項目 | 一致 |
| 1.3 | `spec-reviewer.md` に6点 | `model:` L5、制約 L18-20、手順 L22-35、ブロック L37-50、却下の扱い L55 | 一致 |
| 2 | `SKILL.md` に Step 1〜7 と制約 | Step 1〜7(L23-106)、制約(L108-113) | 一致 |
| 3.1 | 本物のリポジトリで何も出力しない | 本 spec 自身の tasks 段階が `generated: true` `approved: false` のため、現在は1行出力される(T1-1-6) | 当時は一致、現在は不一致 |
| 3.2〜3.4 | 模擬入力での直接実行 | スクリプトは存在し design と一致。実行結果の記録は無い(T1-1-1) | 確認できない |
| 3.5 | `settings.json` に5か所 | L130-138、L150-158、L160-171、L172-182、L183-194 | 一致 |
| 4.1 | CLAUDE.md の spec駆動開発の節に6点 | L109-112、L121-126 | 一致 |
| 4.2 | README の2表 | L332-334 と L337、L397 | 一致 |
| 5.1 | 8項目すべて期待どおり、捨て spec が残っていない | 捨て spec は無い。8項目の結果の記録は無く、項目8 の `UserPromptExpansion` は design L64 が「未確認」のまま(T1-1-1、T1-1-4) | 後半は一致、前半は確認できない |
| 5.2 | レビューが走り、再レビューが要求され、3往復で未解決、新サイクルで数え直し | `requirements-review.md` サイクル1 往復3「未解決: 1件」→ サイクル2 往復1、`block-counter.txt` の存在、証跡2件 | 一致 |
| 6.1 | 「Git for Windows が必須」が残っていない、ハッシュ取得の順が一致 | 検索で該当は tasks.md 自身の条件文と review の引用のみ。`record-spec-review.sh` L98-104 と `spec-review-scan.sh` L140-146 は同一。ただしタスク本文の「フック6本」は実物の8本と合わない(T1-1-5) | 一致(本文に誤記) |
| 6.2 | epoch 秒が取れ、数字以外が弾かれる。全数確認で他に無い | `check-verify-before-stop.sh` L96-102。実測は `design-response.md` サイクル2 往復1 の末尾に記録。項目15 は design レビュー サイクル4 往復2で独立に確認済み | 一致 |

### 申告

**1. フック8本の自動テストを書かず、捨て spec と模擬入力による手作業の実機確認に置き換え、確認後に捨て spec を削除する** — tasks.md 完了条件2、タスク5.1、design.md Testing Strategy(L340、L366)

- Issue の記載: あり。4番目のコメント §C が「確認用の捨て spec を作って確認し、確認後に削除してコミットに含めない」と定めている
- 決めたこと: Issue §C のとおり。完了条件の verify Skill を実機確認(項目1〜15)に置き換え、結果を記録する(記録先は未定。T1-1-1)
- 他にありえた選択肢: `.github/scripts/tests/` に既にある形式(`test-check-*.sh`。17本)で `.claude/hooks/` のテストを書く。または `.claude/hooks/tests/` を新設し、捨て spec をフィクスチャとして残す。いずれも `.claude/` `.github/` 配下のため所有者の Approve が要るが、本 spec の成果物と同じ経路である
- 外れていた場合: フック8本(うち4本は品質ゲート未実行の検知・main の保護・文字化けの検知・ゲート実行の記録)に回帰テストが無いまま残り、次にフックへ手を入れるとき(別 OS の対応、Claude Code のフック入力の変更。design Revalidation Triggers L49-54)の確認が毎回手作業になる。今回の確認の証拠(捨て spec)も削除されるため、後から「何を確かめたか」を再現できない

**2. 受入基準 8.4 を成果物の無い「現状維持」として対象外にし、確認のタスクも置かない** — tasks.md「意図的に対象外とした受入基準」

- Issue の記載: あり。3番目のコメント §11「spec 自体を審査させない現状を維持する」
- 決めたこと: 変更する成果物が無いため、どのタスクにも紐づけない
- 他にありえた選択肢: タスク5.2 の確認項目に「`codex-review.yml` のプロンプトが spec の文面の不備の指摘を禁じたままである」を1行足す(読むだけで足りる)
- 外れていた場合: 影響は小さい。`codex-review.yml` は Out of Boundary であり、将来そのプロンプトが変わっても本 spec の範囲では検出しない、という状態が今と変わらない

テストを省略可能な印(`- [ ]*`)は使われていない。申告の対象になる決定は無い。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 中 | tasks.md 完了条件2(L6)、タスク3.2〜3.4 の観測条件(L67、L74、L81)、タスク5.1(L113-115)、タスク5.2(L119) | 完了条件2 は verify Skill の代わりに「実機確認(項目1〜12)を実施し、結果を記録する」と定め、タスク5.1 も「結果を記録する」と書いて `[x]` が付いているが、**記録がリポジトリのどこにも無く、記録先も定まっていない。** 実測の記述が残っているのは、design L64(`UserPromptSubmit` の発火、証跡の2経路、フルモデルID、Stop の2回=項目4・6 と 8 の一部)、`design-response.md` サイクル2 往復1 末尾(項目13・14)、`design-review.md` サイクル4 往復2(項目15)、および本 spec 自身の `reviews/`(項目9〜12)だけで、**項目1・2・3・5・7(走査の無出力、7条件それぞれで止まること、収束時に通ること、不正な値で証跡を書かないこと、モデル不一致で証跡を書かないこと)は結果が残っていない。** タスク3.2〜3.4 の観測条件(模擬入力での直接実行)も同じ項目に依っている。verify Skill なら `record-gate-run.sh` のスタンプと CI の結果が証拠になるが、置き換えた実機確認には証拠が無く、承認する所有者は `[x]` を確かめられない。捨て spec は design L366 のとおり削除されるため、後から再現もできない。tasks が自分の完了条件(結果を記録する)を満たしていない状態である | 記録先を1か所に定め、項目1〜15 の結果(何を入力し、何が出たか、日付)を書く。案: `tasks.md` のタスク5.1・5.2・6.2 の detail に項目ごとの結果を1行ずつ足す(spec は監査証跡としてコミットされるため所有者が読める)。結果が実装セッションの手元に無い項目は、承認の前に再実施して記録する。完了条件2 の文に「記録先: tasks.md の該当タスクの detail」を添える |
| T1-1-2 | 中 | tasks.md タスク7(L147「範囲外だが同じPRに含めた既存フックの変更を PR 本文で説明する」) | 既存フック4本と `CLAUDE.md` の Git規約の変更は、requirements In scope(L13)と要件8.5〜8.7、design This Spec Owns(L34)と Modified Files(L152-155)、そして同じ tasks.md のタスク6(`_Requirements: 8.5, 8.6, 8.7_`)が **本 spec の範囲内** と定めている。「範囲外」は design サイクル2 往復1の D2-1-4 への回答(当時は範囲外として PR 本文で説明する、と決めた)の名残で、その後の差し戻し D3-1-4 と requirements サイクル3で範囲に入れた結果が反映されていない。タスク7 は唯一の未完了タスクで、この文のまま実行されると PR 本文(監査証跡)に「spec の範囲外の変更」と書かれ、`Spec:` 行で指す requirements・design と食い違う。codex-review は PR 本文と spec の両方を判定材料にするため、範囲の記述が逆向きのまま届く | 「`.claude/settings.json` の変更と、既存フック4本および `CLAUDE.md` の Git規約の変更(要件8.5〜8.7。`.claude/hooks/**` と `settings.json` は所有者が手で置いたもの)を PR 本文で説明する」のように、範囲内の変更として、かつ所有者が手で置いた経緯を書く形に改める |
| T1-1-3 | 低 | tasks.md 完了条件2(L6「項目1〜12」) | design の Testing Strategy は15項目(13〜15 は design サイクル3〜4で追加)だが、共通の完了条件は「項目1〜12」のまま。タスク6.2 が個別に 13〜15 を引いているため実害は無いが、共通条件だけを読むと既存フックの確認が verify の代替に含まれていないように見える | 「項目1〜15」に改める |
| T1-1-4 | 低 | tasks.md タスク5.1(L113「項目1〜8」、L115「8項目すべてが期待どおり」、L116 の `_Requirements:_`) | 項目8 は「通知フックが承認にあたる入力の時点で一覧を出すこと(`UserPromptSubmit` は確認済み。`UserPromptExpansion` は未確認)」であり、design L64 は `UserPromptExpansion` の発火を「未確認のまま進め、Testing Strategy の項目として残す」としている。`design-response.md` D1-3-2 への回答も「どちらの経路に由来するかは見分けていない。切り分けは行わない」である。したがって「8項目すべてが期待どおり」は項目8 の括弧内(未確認の経路)を含めると実態より強く、未確認が `[x]` の下に隠れる。あわせて、項目8 は要件7.9 の確認だが、タスク5.1 の `_Requirements:_` に 7.9 が無い | L115 を「項目1〜7 と、項目8 のうち一覧が出ること(`UserPromptExpansion` の発火は design L64 のとおり未確認のまま)」に改め、`_Requirements:_` に 7.9 を足す。`UserPromptExpansion` を確認した事実があるなら、その方法と日付を T1-1-1 の記録に書く |
| T1-1-5 | 低 | tasks.md タスク6.1(L128「フック6本の前提コメント」、L130 の観測条件、L134 `_Depends: 5.2_`) | (1) 「フック6本」は実物と合わない。requirements R3-2-1(記録のみ)への回答で `notify-spec-review.sh` と `spec-review-scan.sh` にも前提の行を足し、8本すべてに揃えている(検索で8本の冒頭に「前提: bash と perl(JSON::PP)。jqには依存しない。」を確認)。(2) 要件8.5 の観測できる形「各フックの冒頭と CLAUDE.md に同じ文言」が観測条件に無く、「Git for Windows が必須」の不在とハッシュ順の一致だけを見ている。R3-2-1 の直し方の案(8本すべての冒頭に同じ行があることを完了条件に含める)が tasks に反映されていない。(3) タスク6.1 はタスク5(実機確認)の後に `record-spec-review.sh` と `spec-review-scan.sh` のハッシュ取得を変えるが、変更後に項目3・6(証跡の記録と照合)を再確認する項目が無い。現在の証跡2件(64桁の16進)と Stop フックが照合で止まっていないことから変更後も動いているが、tasks からは読めない。いずれも実物は正しく、実装への影響は無い | 「フック8本(source される `spec-review-scan.sh` を含む)」に改め、観測条件に「8本の冒頭と `CLAUDE.md` L70 に同じ文言がある」を足す。ハッシュ順を変えた後の再確認は T1-1-1 の記録に「変更後に項目3・6 を再実施」として1行書く |
| T1-1-6 | 低 | tasks.md タスク3.1(L58「本物のリポジトリで関数を実行して何も出力しないこと(全段階が人の承認済みのため)」) | この条件が成り立つのは本 spec の `spec.json` が存在しなかった時点に限られる。現在は本 spec の tasks 段階が `generated: true` `approved: false` のため、`spec_review_scan` は `spec-review|tasks|...` を1行出力する(承認前は常にそうなる)。承認する所有者が条件を再現しようとすると「不一致」になる | 「本 spec 以外の5 spec(全段階が人の承認済み)について何も出力しないこと」に改める。または design Testing Strategy 1 の文言に合わせて「人の承認済みの段階については出力しない」とする |
| T1-1-7 | 低 | tasks.md タスク7(L145-150) | (1) 出荷(PR 本文・auto-merge・Approve)は CLAUDE.md が `/ship` の手順と定め、他の5 spec の tasks.md に PR のタスクは無く、`tasks-generation.md` §8 も Deployment tasks を除外している。タスク7 に固有の内容は PR 本文に書く3点だけで、これは `/ship` への注記で足りる。(2) PR 本文の必須事項 `Refs: #193` と `Closes #193`(CLAUDE.md Git規約)に触れていない。`Closes #193` を付けると、design Non-Goals(L22)が「将来の判断として Issue #193 に残す」とする別ベンダー導入と、Issue 3番目のコメント §15「後で判断すること」の4件が、マージと同時に閉じた Issue の中に残る。(3) `_Requirements: 8.1_`(cc-sdd のスキルを変更しない)を引いているが、観測条件に「差分に `.claude/skills/kiro-*/` が含まれない」が無い | タスク7 を残すなら、観測条件に「PR 本文に `Spec:` `Refs: #193` `Closes #193` があり、差分に `.claude/skills/kiro-*/` が無い」を足し、§15 の残件を新しい Issue に移すか `Closes` を付けないかを所有者が決めて書く。タスクとして残さないなら、3点を「出荷時の注記」として tasks.md の末尾に置き、`/ship` に従う旨を書く |
| T1-1-8 | 低 | tasks.md 全体 | この tasks は実装(PR #376)の後に書かれ、承認前の時点で7タスク中6つに `[x]` が付いている。cc-sdd の通常の流れ(承認 → `/kiro-impl` が1タスクずつ `[x]` を付ける。`kiro-impl/SKILL.md` L116・L175)と異なるが、その経緯が tasks.md のどこにも無い。監査証跡として後から読む人は、承認前に `[x]` が付いた理由と、`[x]` を誰が確かめたか(実装セッションの自己申告と本レビュー)を本文から辿れない | 冒頭に1段落、「本 spec は Issue #193 の4番目のコメント『判定と次の手順』に従い、スキルとフックの実装と実機確認を先に行い(PR #376)、tasks は実際に行った作業を単位として事後に書いた。`[x]` は 2026-09-27 時点で完了した作業を示す」と書く |

### 前の段階への指摘

なし。実機確認の結果の記録先が design に無い点(T1-1-1)は、tasks の完了条件が「記録する」と定めた以上 tasks の側で記録先を決められるため、design への差し戻しにはしない。

- 往復: 1回目 / 高0 中2 低6

## サイクル1 往復2(2026-09-27)

この往復の依頼: 往復1の T1-1-1(中)と T1-1-2(中)の修正が指摘に対応できているか。とくに書き足された実施結果が、このリポジトリで確認できる事実と食い違っていないか。および新たな高・中があるか。

審査の材料: `tasks.md`(現在の全文。L58-59、L68-69、L76-77、L84-85、L117-120、L150-155 の変更箇所を重点)/ `requirements.md`(全文。要件7.1〜7.9、8.5〜8.7)/ `design.md`(全文。L64 の Compliance、L338-366 の Testing Strategy)/ `spec.json`(requirements・design とも `approved_by: "DogisRiki"`、tasks は `generated: true` `approved: false`)/ Issue #193 本文と4本のコメント(`gh issue view --comments` で取得)/ steering 3本 / `.claude/skills/spec-review/rules/common.md` と `rules/tasks.md` / 実物: `.claude/hooks/spec-review-scan.sh` `record-spec-review.sh` `check-spec-review-before-stop.sh` `notify-spec-review.sh` `check-verify-before-stop.sh`(作業ツリーの版。全文)、`CLAUDE.md` L60-129、`.claude/hooks/` 8本の冒頭の前提行と「Git for Windows」の検索(`.claude/` `CLAUDE.md` `README.md` `doc/` `.kiro/specs/spec-review/` を対象)/ `.kiro/specs/` 配下の spec.json 6件の `approved` `approved_by` / `.kiro/specs/zz-hook-probe/` の有無 / `.claude/.state/spec-review/` の3ファイル(証跡2件とカウンタ)/ `reviews/tasks-review.md`(往復1)と `tasks-response.md` / `reviews/design-response.md` L45-118 と `design-review.md` L287-319(項目13〜15 の記録の所在)/ `reviews/requirements-review.md` と `design-review.md` の節見出しと最終行(項目9〜12 の記録の所在)。却下された指摘は無い。

このレビュー役はシェルを実行できないため、実施結果の日付とスクリプトへの模擬入力そのものは再現できない。確認したのは、書かれた結果が実物のスクリプトの読解と、リポジトリに残る状態(ファイルの有無、spec.json の値、証跡の内容)と食い違わないかである。

### 往復1の修正の確認

- **T1-1-1(対応できている)**: 項目1〜8 の結果がタスク3.1〜3.4 と 5.1 の「実施結果(2026-09-26)」行に入った。それぞれを実物と突き合わせた。
  - タスク3.1(L59)「既存5spec に対して出力0件。本 spec の未承認段階だけが出力された」: 他の5 spec は全段階が `approved: true` `approved_by: "DogisRiki"` であり、`spec-review-scan.sh` L74 の条件(`approved` が true、`approved_by` が空でなく `:` を含まない)で対象外になる。本 spec は tasks が `approved: false` のため出力される。観測条件(L58)も「人の承認が無い段階だけが出力されること」に改まり、往復1の T1-1-6 で指摘した「現在は不一致」が解消した
  - タスク3.2(L69)「不正な3種で証跡を書かず、正常な値で書いた。両経路で書けた。モデル名を `claude-opus-5` に差し替えた記録では書かなかった」: `record-spec-review.sh` の L61-64(未知の段階)、L73-74(`REVIEW_FILE` が `.kiro/specs/<feature>/reviews/<stage>-review.md` と一致しない場合。`..` を含むパスはここで落ちる)、L56-58(項目の欠落)、L39-40(`last_assistant_message` と `tool_input.message` の両経路)、L87-92(記録に `"model":` があり `claude-fable-5-1` でなければ書かない)と一致する。現在の証跡2件(requirements: cycle=3 round=2 converged、design: cycle=4 round=2 converged)は、それぞれの review ファイルの最終節と一致しており、正常系が実運用でも動いている
  - タスク3.3(L77)「6状態で終了コード2、収束済みで0、同じ入力で2回止めて3回目に0、入力が変われば1回目から」: `check-spec-review-before-stop.sh` L56-58(ブロック理由が無ければ 0)、L60-73(`prompt_id` が一致すれば保存した回数を引き継ぎ、2以上なら 0)、L75-92(回数を1増やして exit 2)と一致する。現在の `block-counter.txt` は `count=1` で、tasks 段階が未収束の状態で1回止めた形になっている
  - タスク3.4(L85)「対象がある状態で一覧が出力された」: `notify-spec-review.sh` L31-58 と一致する
  - タスク5.1(L120)「項目1〜7 を確認済み(結果はタスク3.1〜3.4 に記載)。項目8 は `UserPromptSubmit` 経由の発火を確認。`UserPromptExpansion` は未確認で design の Compliance に明記。捨て spec は削除済み」: design L64 の記述と一致する。`.kiro/specs/zz-hook-probe/` は無く、`.claude/.state/spec-review/` にも `zz-hook-probe` の証跡は残っていない。観測条件(L119)も「項目8 を除く7項目が期待どおり」に改まり、往復1の T1-1-4 の前半(「8項目すべて」が実態より強い)が解消した
  - 項目9〜12 は本 spec の `reviews/` に(requirements サイクル1 往復3「未解決: 1件」→ サイクル2、design サイクル3 往復1 の差し戻しとサイクル4)、項目13・14 は `design-response.md` サイクル2 往復1 の末尾(L63)に、項目15 は `design-review.md` サイクル4 往復2(L300-302)に記録がある。往復1の直し方の案(項目1〜15 をすべて tasks.md に書く)とは形が異なるが、指摘の要点は「記録が無い項目がある」ことであり、今はすべての項目に読める記録がある
  - 記録の形式の細かい抜けは下の T1-2-1・T1-2-2 に低として書く
- **T1-1-2(対応できている)**: タスク7(L152)は「`.claude/settings.json` の変更と、既存フック4本および `CLAUDE.md` の Git規約の変更(要件8.5〜8.7。所有者が手で置いた分を含む)を PR 本文で説明する」に改まり、「範囲外」の語が消えた。requirements In scope(L13)、design This Spec Owns(L34)、タスク6 の `_Requirements: 8.5, 8.6, 8.7_` と向きが揃った

### 追加で確かめたこと

- タスク6.1 の観測条件「『Git for Windows が必須』の記述が残っていない」: `CLAUDE.md` L70-71 は「ホストOSに bash と perl(JSON::PP)が必要。jqには依存しない。Windowsでは Git for Windows(Git Bash同梱)を入れることで満たす」に改まっている。「Git for Windows」の語が残るのは、この L71 と、フック6本の冒頭の「Windowsでは Git for Windows(Git Bash同梱)がこれらを提供する」、design L46・L121、tasks.md L135 の条件文だけで、いずれも「必須」ではなく「Windows での満たし方」として書かれている。観測条件は成り立つ
- 要件8.5 の「各フックの冒頭に同じ文言」: 8本すべての冒頭に「前提: bash と perl(JSON::PP)。jqには依存しない。」がある(往復1の確認と変わらず)
- タスク6.1 の「フック6本」(T1-1-5)、完了条件2 の「項目1〜12」(T1-1-3)、タスク5.1 の `_Requirements:_` に 7.9 が無い点(T1-1-4 後半)、タスク7 の `Refs` `Closes`(T1-1-7)、承認前に `[x]` が付いた経緯(T1-1-8)は、記録のみの処置のとおり本文は変わっていない。低であり、再提出しない

### 申告

この往復で新たに申告する決定は無い。往復1の修正は、既に行った確認の結果を書き足したものと、タスク7 の範囲の記述の向きを直したもので、新しく選んだ選択肢は無い。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-2-1 | 低 | tasks.md タスク3.3 の実施結果(L77) | 止まることを確認した状態として6つ(レビュー未実施・完了の印なし・対応の記録なし・処置漏れ・review の改変・本文が新しい)を挙げているが、タスク3.1 が「ブロックの7条件を実装する」と書く要件7.5 の7条件のうち「証跡がない」(L134-135)と「最新往復に修正が残っている」(L129-130)がこの記述に無い。後者は項目10 としてタスク5.2 が実運用で確認している。前者は、捨て spec で「レビュー未実施」の状態を作れば証跡も無いため同時に踏まれる経路だが、記録からはそう読めない。design の Testing Strategy 項目2 も同じ6状態の列挙であり、実装は7条件を持つ(実物で確認)。実装への影響は無い | L77 に「証跡がない状態(レビュー未実施の状態で同時に確認)」を足す。または「修正が残っている状態は項目10(タスク5.2)で確認」と添える |
| T1-2-2 | 低 | tasks.md 完了条件2(L6)、タスク5.2(L123-129)、タスク6.2(L140-148) | 往復1の T1-1-1 への対応は「記録先を tasks.md の各タスクの detail に定めた」(`tasks-response.md`)だが、完了条件2 の文には記録先が書かれておらず、「実施結果」の行がそれにあたることは本文からは読み取れない。また、タスク5.2(項目9〜12)とタスク6.2(項目13〜15)には「実施結果」の行が無く、記録の所在(`reviews/` の各記録、`design-response.md` サイクル2 往復1 末尾、`design-review.md` サイクル4 往復2)が tasks.md から辿れない。記録自体は存在するため実装への影響は無い | 完了条件2 に「記録先: 各タスクの detail の『実施結果』行」を添える。タスク5.2 と 6.2 に「実施結果: `reviews/` の記録(項目9〜12)」「実施結果: `design-response.md` サイクル2 往復1(項目13・14)、`design-review.md` サイクル4 往復2(項目15)」を1行ずつ足す |

### 前の段階への指摘

なし。

- 往復: 2回目 / 高0 中0 低2
- 往復: 2回で収束 / 未解決: 0件
