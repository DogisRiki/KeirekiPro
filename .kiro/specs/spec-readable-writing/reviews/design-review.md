# design レビューの記録(spec-readable-writing)

## サイクル1 往復1(2026-10-02)

design.md を、requirements.md(承認済み)、Issue #474 の本文、steering、リポジトリの実ファイルと突き合わせて審査した。実ファイルは作業ツリー(`feat/spec-need-triage` ブランチ)の版で確かめた。origin/main と差がありうるため、指摘の根拠は行番号ではなく中身で書いた。

確かめた事実: `spec-review-scan.sh` は `phase` が `initialized` の spec と人が承認した段階を飛ばし、本文とレビューの記録の新旧を `-nt` で比べる。`.claude/settings.json` の deny は `.claude/hooks/**` と `.claude/settings.json` の Edit/Write を塞ぎ、`.claude/skills/**` と `.claude/agents/**` は塞いでいない。`.github/CODEOWNERS` は `/.claude/` を所有者に割り当てている。`/kiro-spec-init` の更新の形は `## Project Description (Input)` に完全一致する行を目印にしている。`/kiro-impl` は `- [ ]` `[x]` の箱、`X.Y` の番号、`_Depends:_` `_Boundary:_` `_Blocked:_`、`(P)`、`## Implementation Notes` を読み書きする。`check-spec-backing.sh` が spec の中身から見るのは `\{\{[A-Z0-9_]+\}\}` のプレースホルダだけで、`codex-review.yml` は spec ディレクトリ直下の `*.md` を連結して読む(`reviews/` の下は読まない)。`/kiro-spec-quick` と `/kiro-spec-batch` は各段階のスキルを呼ぶ。`/kiro-spec-design` と `/kiro-spec-quick` は `/kiro-validate-design` を案内している。`.claude/hooks/tests/` には `test-protect-main.sh` だけがあり、CI はこのディレクトリのテストを実行していない(手で走らせる形)。これらは design の前提と合っている。

要件カバレッジ: 要件1〜7の受入基準はすべて「要件との対応」の表に現れ、対応する部品がある。ただし、要件6の1が点検の対象に含める「文書の組み立て」「design.md の書き方」「繰り返し」(要件3〜5)は、点検役の返す内容と記録の書式が文単位にしか対応しておらず、表でも点検役が3.x・4.x・5.x に対応していない(D1-1-3)。

決まりとの照合: ゲート設定の記載(`.claude/hooks/` の scan とテストを所有者が写す)は「ファイルの構成」と一致し、`.github/` のファイルは出てこない。依存追加なしは本文と矛盾しない。前提機能の利用可否は「当てはまらない」とあるが、design が頼る Claude Code の機能(Agent ツールで `.claude/agents/` の定義を起動すること、Stop フック、`-nt`)はすべて既存の `/spec-review` が使っているもので、新しく確かめる必要のある前提は点検役のモデルの既定だけである(D1-1-6)。

境界: 「受け持たないこと」に挙げた `/kiro-validate-design` の案内、古い雛形と `ears-format.md` の削除、今の書き方の spec の書き直しは、本文で扱っていない。「頼りにするもの」の2つのフックは本文でも変えていない。

### 申告

**1. spec ごとの新旧の見分けを、spec.json の `spec_format` の欄で行う** — 概要、新しい雛形の init.json、各部品の分岐

- Issue の記載: なし。Issue は「これから作る spec」とだけ書いている
- 決めたこと: 雛形の init.json に `"spec_format": 2` を足し、欄の無い spec を今の書き方として扱う。spec を書くスキル、`/spec-review`、点検役、scan、spec を読むスキルのすべてがこの欄で分岐する
- 他にありえた選択肢: `created_at` と変更が main に入った日時を比べる。requirements.md の見出し(`# 要件` か `# Requirements Document` か)で見分ける。欄を足さず、今の書き方の spec の名前を決まりのファイルに列挙する
- 外れていた場合: すべてのスキルと scan の分岐の条件を書き直す。spec.json の形が変わるので、spec.json を読む検査(`check-spec-backing.sh`、`/start`)への影響も見直す

**2. 点検を `/spec-review` の各往復の先頭に置き、本文を直すのはメインセッションにする** — 処理の流れ、`/spec-review` の点検の手順

- Issue の記載: 「所有者が承認のために読む前に、AIが見つけて直している(AIの提案を了承)」。いつ、誰が直すかは書いていない
- 決めたこと: 審査役を起動する前に毎回点検役を起動し、中身の変わらない案でメインセッションが本文を直し、`reviews/{段階}-style.md` に節を足す
- 他にありえた選択肢: 各生成スキルの自己点検に足す(審査の指摘で直した後の本文を見ない)。審査が収束した後に1回だけ点検する(既存の判定「本文がレビューより新しい」で止まる)。点検役に直接本文を直させる
- 外れていた場合: 往復ごとに点検役の起動が増え、審査の時間が延びる。順番を変えると scan の判定と干渉するので、scan とフックの判定を作り直すことになる

**3. tasks.md の目印も日本語にし、読む側のスキルに対応表を読ませる** — 新旧の見出しと目印の対応表、spec を読むスキル

- Issue の記載: 「英語と日本語が混ざった定型文」を困りごとに挙げている。機械が読む目印については書いていない
- 決めたこと: `_Requirements:_` `_Depends:_` `_Boundary:_` `_Blocked:_` `(P)` `## Implementation Notes` を `_要件:_` `_依存:_` `_範囲:_` `_保留:_` `(並行)` `## 実装のメモ` にし、`/kiro-impl` など8つのスキルと観点のファイルに「`spec_format` が2なら対応表の名前で読む」を足す。`/kiro-impl` は書き込みも新しい名前で行う
- 他にありえた選択肢: 目印は英語のまま残し(要件2の5の例外「書き換えると指すものが変わる名前」に含める)、読む側を変えない
- 外れていた場合: 読む側のスキル8つ分の指示と `/kiro-impl` の書き込みの指示を戻す。すでに新しい目印で書いた tasks.md がある spec は手で直す

**4. `/kiro-spec-tasks` の生成直後の承認の手順を、`spec_format` に関係なく取り除く** — spec を書くスキル

- Issue の記載: なし
- 決めたこと: 取り除く。今の書き方の途中の spec にも効く
- 他にありえた選択肢: `spec_format` が2のときだけ取り除く。取り除かずに「`/spec-review` が終わってから尋ねる」に直す
- 外れていた場合: 途中の spec の tasks の承認の流れが変わる。承認を spec.json に書く場所が無くなる件は D1-1-1

**5. 所有者が承認前に直した文も、点検で書き直す** — `/spec-review` の「決めたこと」

- Issue の記載: なし
- 決めたこと: 所有者が書いた文を区別せず、中身が変わらない範囲で直す
- 他にありえた選択肢: 所有者が本文を直したあとの `/spec-review` では、点検役の案で本文を直さず、要件6の4の形(文と理由を所有者に示す)にする。所有者が直したあとは点検を飛ばす
- 外れていた場合: 所有者が、自分の直しが変わった本文を読むことになる。見本は所有者が合格とした文章なので、所有者が書いた文を直す点検は、見本から離す方向に働くことがある。直すのは `/spec-review` の手順1か所

**6. 今の雛形を `specs-v1/` に写し、`specs/` を新しい雛形に置き換える** — ファイルの構成、移行

- Issue の記載: 「途中の spec は今の書き方のまま進める」
- 決めたこと: 新しい雛形が `specs/`、今の雛形が `specs-v1/`。`specs-v1/` に init.json は置かない
- 他にありえた選択肢: 新しい雛形を `specs-v2/` に置き、`specs/` を触らない
- 外れていた場合: `.kiro/settings/templates/specs/` を直接読むスキル(`/kiro-spec-quick` など)の参照先が変わる。途中の spec の design・tasks を書く間に雛形の場所を取り違えると、今の書き方の spec が新しい雛形で書かれる

**7. design.md の雛形から、部品の一覧表、Owner / Reviewers、依存の重要度(P0/P1/P2)、契約の種類の欄、要件との対応の Summary 列を消す** — 新しい雛形の design.md

- Issue の記載: 「技術の中身を削らず、設計として成り立たせたまま、書き方だけを分かりやすくする」「同じことの繰り返しを減らす」
- 決めたこと: 上の欄を、繰り返しか使われていない欄として消す
- 他にありえた選択肢: 欄の名前を日本語にして残し、「当てはまるときだけ書く」にする
- 外れていた場合: 依存の重要度や契約の種類を所有者が設計の技術の中身と見ているなら、雛形に戻す。すでに新しい雛形で書いた design.md には書き足す。節の取捨は D1-1-4

**8. 点検役の定義でモデルを指定しない** — `spec-style-checker` のモデル

- Issue の記載: なし
- 決めたこと: 審査役(`claude-fable-5-1` を指定)と違い、指定しない
- 他にありえた選択肢: 審査役と同じく別モデルを指定する
- 外れていた場合: 定義の1行を直すだけ。点検の結果の傾向が変わる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 高 | design.md 「spec を書くスキル」の `/kiro-spec-tasks`、「CLAUDE.md」 | design は `/kiro-spec-tasks` から「生成の直後に承認を尋ねる手順」を取り除くと書いている。しかし、その手順(SKILL.md の Step 4 の Approval)は、所有者が承認したときに spec.json の `approvals.tasks.approved: true` と `approved_by: "DogisRiki"` `approved_at` を書く唯一の場所である。requirements と design の承認は次の段階のスキル(`/kiro-spec-design` `/kiro-spec-tasks`)が書くが、tasks の承認を書くスキルは他に無い。`/kiro-impl` は Preflight で tasks の承認を確かめて無ければ止まり、`check-spec-backing.sh` も `approvals.tasks.approved` が true でなければ赤にする。design は、取り除いたあと、誰がいつ所有者に tasks の承認を尋ね、誰が spec.json に承認を書くかを決めていない。`/spec-review` の部品にも CLAUDE.md の部品にもその手順は無い。このまま実装すると、この spec の出荷後に作る最初の spec で tasks の承認を記録する手段が無くなり、`/kiro-impl` が止まる。この spec 自身の tasks は今の `/kiro-spec-tasks` で作るので、この spec の流れでは発覚しない。あわせて、CLAUDE.md の「`/kiro-spec-tasks` が生成直後に承認を尋ねる作りになっているが、`/spec-review` の完了後に尋ねる」の行が実態と合わなくなるが、CLAUDE.md の部品の3項目に含まれていない | 承認を尋ねて spec.json に書く手順の置き場所を決めて書く。例: `/kiro-spec-tasks` の Step 4 の Approval を消さず、「`/spec-review` が終わってから尋ねる」に直す。または `/spec-review` の Step 7 に、段階が tasks で収束したときは所有者に承認を尋ね、承認されたら `approvals.tasks` に `approved: true` `approved_by: "DogisRiki"` `approved_at` を書く手順を足す。どちらにしても、CLAUDE.md の該当行を直すことを CLAUDE.md の部品に足す |
| D1-1-2 | 中 | design.md 「spec を書くスキル」の `/kiro-spec-requirements` `/kiro-spec-design` `/kiro-spec-tasks`、「ファイルの構成」 | 要件7の1は、決まりと雛形から新しい書き方と食い違う指示を取り除くと定める。design が rules ファイルに加える変更は、`design-principles.md` の「雛形の見出しを保つ」の読み替え、`design-review-gate.md` の境界4節の名前と「省いてよい」の追記、`requirements-review-gate.md` の EARS の項目1つの読み替え、の3つだけである。しかし実ファイルには、新しい雛形と両立しない指示がほかにも残る。`design-principles.md`: 「Default flow: Overview → Goals/Non-Goals → Boundary Commitments → …」、「Begin with a summary table listing Component, Domain, Intent, Requirement coverage, key dependencies, and selected contracts」、「Dependencies table must … assign Criticality (P0/P1/P2)」、「Contracts: tick only the relevant types」、「Use the standard table (Requirement \| Summary \| Components \| Interfaces \| Flows)」(新しい雛形はこれらの表・欄・列を消す)。`design-review-gate.md`: 境界4節以外の「File Structure Plan」「traceability mapping」の名前での点検。`tasks-generation.md`: 「Avoid: File paths and directory structure」「`_Boundary:_` using design.md component/module names」(design の tasks.md の見本は `spec-review-scan.sh` などのファイル名と `_範囲: .claude/hooks/spec-review-scan.sh_` のパスを書く)、Checkbox Format の例(`_Requirements:` `(P)`)。`kiro-spec-requirements/SKILL.md`: Step 3「Apply EARS format to all acceptance criteria」、Step 4「EARS compliance」、「Choose appropriate subject for EARS statements」。`requirements-review-gate.md`: 「Every acceptance criterion must follow the EARS rules defined in `ears-format.md`」(design が読み替えると書いたのは Mechanical Checks の項目で、この行は別)。design は `tasks-generation.md` を変えるファイルに挙げているが、何を変えるかを書いていない。実装者は、これらを `spec_format` で分岐するのか、新しい書き方の指示に置き換えるのかを design から読めず、残せば次の spec の生成で雛形と rules が食い違い、要件7の1を満たさない | スキルごとに「`spec_format` が2のとき読まない、または読み替える指示」を列挙する。少なくとも、`design-principles.md` の Section Authoring Guidance のうち部品の一覧表・P0/P1/P2・Contracts・要件との対応の表の列の指示、`design-review-gate.md` の File Structure Plan と traceability の名前、`tasks-generation.md` の「ファイルパスを書かない」と `_Boundary:_` の規則と書式の例、`kiro-spec-requirements` の EARS の指示4か所。あわせて、`_範囲:_` に部品名とファイルパスのどちらを書くかを決め、見本と規則をそろえる |
| D1-1-3 | 中 | design.md 「`spec-style-checker`」の返す内容、「`/spec-review`」の点検の記録の書式、「要件との対応」 | 要件6の1は、点検の対象を「文の書き方、文書の組み立て、design.md の書き方、同じことの繰り返しの扱い」(要件2〜5)と定める。design の点検役は「外れた文ごとに、行番号と原文、決まりの名前、書き直しの案、中身が変わるか」を返し、記録は「書き直した文: N / 書き直さなかった文: N」を数える。この形は、1つの文の言い換えで直せる外れ(要件2)にしか合わない。組み立ての外れ(要件3: 理由の段落が無い、「受入基準」の小見出しがある、部品の節に対応する要件の行が無い)、design.md の書き方の外れ(要件4の1: 実装に要る情報が削られている)、繰り返し(要件5の1: 同じ決めごとが複数の節にある)は、どの行を何に書き直すかの形では返せず、「書き直した文の数」にも数えられない。要件との対応の表でも、`spec-style-checker` は 2.1〜2.8 と 6.x にだけ対応し、3.x・4.x・5.x の行に点検役が無い。このまま実装すると、点検役は文単位の外れだけを探す定義になり、要件6の1のうち組み立てと繰り返しの点検が仕組みから抜ける | 点検役の返す内容に、文の外れとは別に「組み立て・繰り返しの外れ」の形(該当する節の名前、何が足りないか・何と何が重複しているか、直し方の案、中身が変わるか)を足す。記録の書式に、その件数と扱いの行を足す。要件との対応の表の 3.x・4.x・5.x に `spec-style-checker` を足す |
| D1-1-4 | 中 | design.md 「新しい雛形」の design.md、「ファイルの構成」、この design 自身の「tasks.md の見本」「移行」の節 | design は新しい design.md の雛形の節を11個(概要〜テストの方針)に列挙し、減らす節と欄の理由を書いている。しかし今の雛形にある Technology Stack、Existing Architecture Analysis、Security Considerations、Performance & Scalability、Migration Strategy、Supporting References は、列挙にも減らす理由の一覧にも無い。要件4の1は「技術の中身を削らない」と定めるので、セキュリティや移行の節を雛形から黙って落とすと、認証や DB に触れる spec でその内容の置き場所が無くなる。一方で、この design 自身は列挙に無い「tasks.md の見本」と「移行」の節を持つ。雛形に無い節を足してよいのか、足すならどう扱うか(`design-review-gate.md` の「雛形の見出しを保つ」との関係、対応表に載せるか)が design から決まらない | 任意の節(セキュリティ、性能、移行、補足資料)を新しい名前で雛形に残し、「当てはまるときだけ書く」の注記に含める。または、雛形に無い節を足してよいと雛形と `design-review-gate.md` に書く。どちらにしても、対応表にその節の新旧の名前を足す |
| D1-1-5 | 中 | design.md 「テストの方針」の最後の項目 | 「新しい書き方の spec を、書いてから審査するまで通して動かす確かめ: この spec の tasks.md の審査で、点検の工程が働き、点検の記録が残ることを確かめる」とある。しかし、この spec の tasks.md の審査(`/spec-review spec-readable-writing tasks`)は、所有者が tasks を承認して `/kiro-impl` を打つ前に行う。点検の工程を持つ新しい `/spec-review` と `spec-style-checker` は、この spec の実装(`/kiro-impl` のあと)でできるものなので、tasks.md の審査の時点には存在しない。design.md の点検(`reviews/design-style.md`)も、点検役の仕組みが無いため general-purpose のサブエージェントに手で任せたと記録に書かれている。この項目は書かれたとおりには実行できず、新しい `/spec-review` の流れ(点検、記録、審査、修正、次の往復の点検)を通して動かす確かめが、どのタスクでも行われないまま出荷される | 通して動かす確かめの方法を、実行できる形で書く。例: 実装のタスクの中で、一時的な spec ディレクトリ(`spec_format` が2で、短い requirements.md を持つもの)を作り、新しい `/spec-review` を1往復流して、本文が直り `reviews/requirements-style.md` が残り、審査役が起動することを確かめ、終わったらそのディレクトリを消す。または、この spec の出荷後に作る最初の spec の requirements の審査を確かめの場とし、そう書く |
| D1-1-6 | 低 | design.md 「`spec-style-checker`」のモデル | 「定義でモデルを指定しない。点検役は、起動したセッションと同じモデルを使う」は、Claude Code のサブエージェント定義で `model` を省いたときの既定の動きについての主張だが、根拠が書かれていない。サブエージェントの定義には、セッションと同じモデルにするための `model: inherit` の指定があり、省いたときの既定が「セッションと同じ」かどうかは公式文書で確かめる必要がある。点検の質に関わる差は小さく、実装には影響しない | 「セッションと同じモデルを使う」が意図なら、公式文書を確かめたうえで `model: inherit` を明示する。既定に任せるなら、そう書き直す |
| D1-1-7 | 低 | design.md 「CLAUDE.md」の3項目目 | CLAUDE.md の「Issueの印」は `_Requirements:_` のほかに `(P)` も名指ししている(「`(P)` があればその後に `(#N)` を置く」)。design は `_要件:_` を添えることだけを書き、`(並行)` を添えることを書いていない。新しい書き方の spec を更新するときに印の置き場所が読めないだけで、実装には影響しない | 同じ箇所に、`(P)` が `(並行)` になることも添える |
| D1-1-8 | 低 | design.md 「`/spec-review`」の所有者への報告 | 「Step 7 の報告に、書き直した文の数と、書き直さなかった文を足す」が、往復が2回以上あるとき、最後の往復の分だけか全往復の合計かが書かれていない。要件6の4は承認を求めるときに書き直さなかった文を示すと定めるので、往復1で書き直さなかった文が往復3の報告から落ちると、所有者に示されない | 「そのサイクルの全往復の合計と、書き直さなかった文のすべて」と書く |

### 前の段階への指摘

なし。

- 往復: 1回目 / 高1 中4 低3

## サイクル1 往復2(2026-10-02)

往復1のあとに全体を書き直した design.md を、requirements.md(承認済み)、Issue #474 の本文、steering、リポジトリの実ファイルと突き合わせて審査した。往復1の指摘 D1-1-1〜D1-1-5 は、本文で直っていることを確かめた(D1-1-1: `/kiro-spec-tasks` の Step 4 を残して承認を尋ねる時点だけ直す、CLAUDE.md の該当行を書き直す。D1-1-2: 読み替える指示の一覧と `_範囲:_` の決め。D1-1-3: 点検役が返す外れを2種類にし、記録の書式と「対応する要件」の行を直した。D1-1-4: 安全・性能・移行の節を残し、雛形に無い節を足してよい注記を入れる。D1-1-5: 一時的な spec で通して動かす)。低の D1-1-7 と D1-1-8 も本文に反映されている。

この往復で確かめた事実: `/spec-review` の SKILL.md の Step 6 の3は、前の段階に戻って本文を直したあと「その段階について、`CYCLE` を 1 増やして Step 2 からやり直す」と書いている。`/kiro-spec-tasks` の Step 2 は `rules/tasks-generation.md` と `rules/tasks-parallel-analysis.md` の両方を読み、`tasks-parallel-analysis.md` は「Append `(P)` immediately after the numeric identifier」と例 `- [ ] 2.1 (P) Build background worker for emails`、`_Boundary:_` `_Depends: X.X_` の規則を持つ。`/kiro-spec-tasks` の SKILL.md 自身も、Step 2 の「Read `.kiro/settings/templates/specs/tasks.md` for format (supports `(P)` markers)」「Apply `(P)` markers」、Step 3 の「`_Depends:_`, `_Boundary:_`, and `(P)` markers」、Critical Constraints の「`_Boundary: ComponentName_`」「`_Depends: X.X_`」を持つ。`/kiro-spec-design` の SKILL.md の Step 4 は「Populate the File Structure Plan section」と節の名前で指示している。今の design.md の雛形の Supporting References は「長い型定義、ベンダーの選択肢の表、網羅的なスキーマの表」を design.md の中に置く節で、`design-principles.md` も「Lengthy type definitions … should be placed in the Supporting References section within design.md … Investigation notes stay in `research.md`」と区別している。`/kiro-impl` の Step 1 が読むのは spec.json・requirements.md・design.md・tasks.md で、research.md は読まない。`.claude/settings.json` の deny に `.claude/.state/` は無い。Stop フックと知らせるフックは `.kiro/specs/*/spec.json` をすべて走査する。`.github/scripts/tests/test-check-spec-backing.sh` は `.github/scripts/tests/` にある(`.claude/hooks/tests/` ではない)。

要件カバレッジ: 要件1〜7の受入基準は、各部品の「対応する要件」の行のどれかに現れ、実現する部品がある。要件2.6・2.8・3.3・7.2 は `spec-writing.md` の中身の節と見本の節が裏付ける。

決まりとの照合: 7項目のうちゲート設定と依存追加に記載があり、残る5項目は「当てはまらない項目」の1行にある。ゲート設定の記載(`.claude/hooks/` は所有者が写す、`.claude/skills/` `.claude/agents/` は CODEOWNERS で承認を経る)は「ファイルの構成」「置き方」と一致し、`.github/` のファイルは出てこない。依存追加なしは本文(bash と perl だけ)と矛盾しない。

境界: 「受け持たないこと」の5項目は本文で扱っていない。「頼りにするもの」の2つのフックは本文でも変えていない。「見直しが要る変更」の1つ目(`/spec-review` の往復の手順が変わったとき)は、D1-2-1 のとおり、今の手順の中にすでに点検を通らない経路がある。

### 申告

往復1の申告1・2・3・5・6・8は、書き直したあとの本文でも変わっていない。この往復では、書き直しで新しく決まったこと、または往復1の申告から変わったことだけを挙げる。

**1. `/kiro-spec-tasks` の承認を尋ねる時点の直しを、`spec_format` に関係なく行う** — 「spec を書くスキル」の `/kiro-spec-tasks`(往復1の申告4の差し替え)

- Issue の記載: なし
- 決めたこと: Step 4 を残し、生成の直後には承認を尋ねずに `/spec-review` を実行し、審査が終わってから承認を尋ねる。今の書き方の途中の spec(spec-need-triage、memory-contamination-check)の tasks にも効く
- 他にありえた選択肢: `spec_format` が2のときだけ時点を変える。スキルは変えず、CLAUDE.md の「完了後に尋ねる」の行だけで運用する(今の形)
- 外れていた場合: 途中の spec の tasks の承認の流れが、この変更が main に入った時点で変わる。直すのは Step 4 の1か所

**2. 要件との対応の表を、雛形とこの design から消し、各部品の「対応する要件」の行だけにする** — 「新しい雛形」の design.md、対応表の `## Requirements Traceability` の行、この design 全体

- Issue の記載: 「同じことが何度も書かれている」「同じことの繰り返しを減らす」
- 決めたこと: 表を消す。要件がどの部品で実現されるかは、部品ごとの行から逆引きする
- 他にありえた選択肢: 表を残して部品ごとの行を消す。表を残し、Summary 列だけ消す
- 外れていた場合: 所有者が「要件1つがどこで実現されるか」を一覧で読めなくなる。審査役と `design-review-gate.md` の機械的な点検(要件の番号が design に現れるか)は部品ごとの行でも働く。戻すときは雛形と対応表の1行

**3. design.md の雛形から Existing Architecture Analysis と Supporting References を消し、安全・性能・移行の節を残す** — 「新しい雛形」の design.md(往復1の申告7の差し替え)

- Issue の記載: 「技術の中身を削らず、設計として成り立たせたまま」
- 決めたこと: 2つの節を消し、研究の記録は research.md に書く。要る節は移行の節の前に足してよい
- 他にありえた選択肢: Supporting References を「補足」の名前で残し、当てはまるときだけ書く
- 外れていた場合: 長い型定義やスキーマの表の置き場所が雛形から消え、書き手が research.md に書くと `/kiro-impl` が読まない(D1-2-6)。戻すときは雛形と対応表の1行

**4. 通して動かす確かめを、`.kiro/specs/` の下の一時的な spec で行う** — 「テストの方針」の最後の項目

- Issue の記載: なし
- 決めたこと: `spec_format` が2で外れた文を混ぜた短い requirements.md を持つ一時的な spec を作り、直したあとの `/spec-review` を1往復流し、終わったら消す
- 他にありえた選択肢: この spec の出荷後に作る最初の spec の requirements の審査を確かめの場にする。点検役の起動と記録の書き込みだけを確かめ、審査役は起動しない
- 外れていた場合: 本物の審査役(Fable 5.1)を作り物の spec に1回使う。一時的な spec はフックの走査の対象になる(D1-2-4)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 中 | design.md 「`/spec-review`」の工程の置き場所、「処理の流れ」の最後の段落 | design は、点検の工程を Step 1 と Step 2 の間に置き、Step 5 で次の往復に進むときも点検に戻ると書き、「`/spec-review` が終わった時点では、点検の記録は本文より新しく」なると結論している。しかし `/spec-review` の SKILL.md には、本文を直したあとに Step 2 へ戻る経路がもう1つある。Step 6(前の段階への指摘)の3は、所有者が直すと判断したら「本文を直す」、そのあと「その段階について、`CYCLE` を 1 増やして Step 2 からやり直す」と書いている。design はこの経路に触れていないので、実装者は Step 6 を変えない。すると、戻った段階(たとえば requirements)の本文は中身を変える直しを受けたのに点検されないまま新しいサイクルの往復1に入り、往復1で収束すると、その段階の `reviews/requirements-style.md` は本文より古いままになる。scan は Stop のときに「本文が書き方の点検より新しい」を出して止め、Claude はもう1サイクル流すことになる。要件6の2(審査の指摘を受けて本文を直したあとも点検する)を、手順ではなくフックの止めで満たす形になり、design の結論もこの経路では成り立たない | 工程の置き場所に、Step 6 の3で新しいサイクルを始めるときも Step 2 ではなく点検の工程から始めると書く。あわせて、点検するのは戻った段階の本文であることを書く |
| D1-2-2 | 中 | design.md 「テストの方針」の3項目目、「`spec-writing.md`」の中身 | 「新しい雛形と `spec-writing.md` に『shall』『When』と英語の見出しが残っていないことを grep で確かめる」とある。しかし design は `spec-writing.md` の中身を、要件2の受入基準ごとに「外れた文の例と直した文の例を1組ずつ付ける」と決めており、要件2の5の外れた文の例は「The ○○ shall …」「When …, the ○○ shall …」の形そのものになる。さらに「新旧の見出しと目印の対応表」の「今の名前」の列には `# Requirements Document` `## Boundary Commitments` などの英語の見出しが並ぶ。つまり `spec-writing.md` には、design 自身の決めにより「shall」「When」と英語の見出しが必ず残る。この確かめは書かれたとおりには通らず、実装のタスクの完了条件にすると、タスクの中で確かめ方を作り直すことになる | grep の対象を雛形だけにする。または `spec-writing.md` については、見出しの行(`#` で始まる行)に英語の見出しが無いこと、決まりの本文(例と対応表を除く)に定型文が無いことのように、残ることが分かっている箇所を除いた確かめ方を書く |
| D1-2-3 | 中 | design.md 「ファイルの構成」の `/kiro-spec-tasks` の行、「spec を書くスキル」の「`spec_format` が2のときに読み替える指示」 | D1-1-2 で読み替える指示の一覧を足したが、まだ新しい雛形と食い違う指示が残る。(1) `.claude/skills/kiro-spec-tasks/rules/tasks-parallel-analysis.md` は、`/kiro-spec-tasks` の Step 2 が読み、SKILL.md の `shared-rules` にも載っているが、「ファイルの構成」にも読み替えの一覧にも無い。このファイルは「Append `(P)` immediately after the numeric identifier」、例 `- [ ] 2.1 (P) Build background worker for emails`、「Keep `(P)` outside of checkbox brackets」、`_Boundary:_` の確認、`_Depends: X.X_` の追加を指示している。新しい雛形は `(並行)` `_範囲:_` `_依存:_` なので、`spec_format` が2の spec の tasks を生成するとき、Claude は `(P)` と `(並行)` の両方の指示を読む。(2) `kiro-spec-tasks/SKILL.md` 自身の Step 2「Read `.kiro/settings/templates/specs/tasks.md` for format (supports `(P)` markers)」「Apply `(P)` markers to tasks that satisfy parallel criteria」、Step 3「`_Depends:_`, `_Boundary:_`, and `(P)` markers still match」、Critical Constraints「`_Boundary: ComponentName_`」「`_Depends: X.X_`」も同じ。(3) `kiro-spec-design/SKILL.md` の Step 4「Populate the File Structure Plan section」は節の名前で指示しており、新しい雛形の「ファイルの構成」と合わない。(4) `kiro-spec-requirements/SKILL.md` の Step 3「design = `Boundary Commitments`」「tasks = `_Boundary:_`」と `requirements-review-gate.md` の Boundary Continuity の同じ2行も、新しい名前と合わない。要件7の1は食い違う指示を取り除くと定めており、(1)は実装者が design から触る理由を読めないので、次の spec の tasks で `(P)` と `(並行)` が混ざって初めて分かる | 「ファイルの構成」の `/kiro-spec-tasks` の行に `rules/tasks-parallel-analysis.md` を足す。読み替えの一覧に、`tasks-parallel-analysis.md` の `(P)` `_Boundary:_` `_Depends:_` の規則と例、`kiro-spec-tasks/SKILL.md` の Step 2・Step 3・Critical Constraints の目印の名前、`kiro-spec-design/SKILL.md` の Step 4 の「File Structure Plan」、`kiro-spec-requirements/SKILL.md` と `requirements-review-gate.md` の「Boundary Commitments」「`_Boundary:_`」を足す |
| D1-2-4 | 低 | design.md 「テストの方針」の最後の項目 | 一時的な spec は `/spec-review` が `FEATURE` から `.kiro/specs/{FEATURE}` を組み立てるので、`.kiro/specs/` の下に置くことになるが、design はそう書いていない。そこに置くと、Stop フックと知らせるフックが本物の spec と同じく走査し(`generated` が true で未承認の段階として扱う)、確かめの途中で Claude の応答が終わると止める(2回まで)。審査役の証跡 `.claude/.state/spec-review/<一時的な名前>__requirements.evidence` も残る。審査役は spec.json の `issue` が無いまま起動する。どれも確かめの手順の中で扱えることで、実装には影響しない | 一時的な spec を `.kiro/specs/` の下に作ること、作ってから消すまでを1回の応答の中で終えること、証跡のファイルも消すこと、審査役に渡す Issue の番号(この spec の #474 など)を spec.json に書くことを書く |
| D1-2-5 | 低 | design.md 「tasks.md の見本」 | 見本では、題名の行 `- [ ] 3.1 点検の記録の判定を scan に足す` の直下に、空行も箇条書きの印も無しに2字下げで説明の文を置いている。Markdown では、この行は題名と同じ段落の続きになり、GitHub の表示では題名と説明が1行につながって見える(`/kiro-impl` は生の文字を読むので判定には影響しない)。あわせて、CLAUDE.md の「Issueの印」が「無ければ説明の末尾に `(#N)` を置く」と定める「説明」が、新しい形では題名の行と説明の行のどちらを指すかが決まらない | 説明の行を箇条書きの1項目(たとえば先頭の項目)にするか、題名の行と説明の行の間に空行を置く。`(#N)` を置く行がどちらかを、CLAUDE.md の部品の4項目目に添える |
| D1-2-6 | 低 | design.md 「新しい雛形」の design.md の5項目目、対応表の `### Existing Architecture Analysis`、`## Supporting References` の行 | 「Existing Architecture Analysis と Supporting References は、research.md と同じことを書く節」とあるが、今の雛形の Supporting References は「本文に置くと読みにくくなる長い型定義、ベンダーの選択肢の表、網羅的なスキーマの表」を design.md の中に置く節で、`design-principles.md` も「Lengthy type definitions … should be placed in the Supporting References section within design.md … Investigation notes stay in `research.md`」と research.md と区別している。`/kiro-impl` は research.md を読まないので、書き手がこの対応表に従って長い定義を research.md に書くと、実装者には届かない。design が雛形の注記で「雛形に無い節は移行の節の前に足してよい」と決めているため置き場所は無くならないが、`design-principles.md` のこの2行は読み替えの一覧に無く、新しい雛形と食い違ったまま残る | 対応表の Supporting References の行を「なし(要るときは移行の節の前に節を足す)」にし、理由の文を Existing Architecture Analysis だけのものに直す。`design-principles.md` の Supporting References の2行を読み替えの一覧に足す |

### 前の段階への指摘

なし。

- 往復: 2回目 / 高0 中3 低3

## サイクル1 往復3(2026-10-02)

往復2の指摘 D1-2-1〜D1-2-3 が本文で直っていることを確かめた(D1-2-1: 「工程の置き場所」に、Step 6 の3で本文を直して審査をやり直すときも点検の工程から始めることを足した。D1-2-2: grep の対象を新しい雛形の4ファイルにし、`spec-writing.md` は見出しの行だけを見る形にした。D1-2-3: 「ファイルの構成」に `tasks-parallel-analysis.md` を足し、読み替えの一覧に `kiro-spec-design/SKILL.md`・`kiro-spec-tasks/SKILL.md`・`tasks-parallel-analysis.md`・`kiro-spec-requirements` の境界の用語を足した)。往復2のあとの3つ目の点検(`reviews/design-style.md`)で直した移行の3も、本文のほかの節と矛盾していない。

この往復で確かめた事実: `compose.yaml` が bind mount するのは `./backend` `./frontend` `./terraform` の3つだけで、`.claude/` を見られるサービスは無い。`.devcontainer/` も無い。既存の `.claude/hooks/tests/test-protect-main.sh` は「実行: bash .claude/hooks/tests/test-protect-main.sh」とホストで走らせる前提で書かれ、`$(dirname "$0")/..` でフックを探す。`/kiro-spec-init` は `init.json` を読んでプレースホルダを置き換えて spec.json を書くので、`init.json` に欄を足せば新しい spec に入る。`check-spec-review-before-stop.sh` は prompt_id ごとに2回まで止めて3回目は通し、`notify-spec-review.sh` は scan の理由の文字列を解釈せずそのまま表示する。`/spec-review` の rules/design.md の観点3は「7項目すべてにチェックが入っているか。該当しない項目に N/A と理由が書かれているか」を見る。今の design.md の雛形は「各項目にチェックを入れ、該当しない場合は N/A と理由を書く」と定めている。tasks.md の雛形の完了条件の本文に「shall」「When」は無い。`.kiro/settings/rules/` は今は無く、`spec-writing.md` が最初のファイルになる。spec の見出しや目印を名前で参照している `.claude/` のファイルは22あり、design が挙げていないのは `/kiro-spec-quick` `/kiro-spec-batch`(受け持たないことに明記)と `/kiro-discovery`(CLAUDE.md が使わないと定めている)だけである。

要件カバレッジ: 往復2と同じ。要件1〜7の受入基準は、各部品の「対応する要件」の行のどれかに現れ、実現する部品がある。

決まりとの照合: 記載は本文と矛盾しない(往復2と同じ)。

境界: 「受け持たないこと」の項目は本文で扱っていない。「頼りにするもの」の2つのフックは本文でも変えていない。

### 申告

往復1と往復2の申告は、この往復の本文でも変わっていない。この往復で新しく挙げるのは次の1件。往復1と2で見落としていたもので、本文の変更で新しく決まったものではない。

**1. 決まりとの照合から、チェック欄と、当てはまらない項目の理由を省く** — 「新しい雛形」の design.md の4項目目、この design の「決まりとの照合」

- Issue の記載: なし。「同じことの繰り返しを減らす」はあるが、照合の形には触れていない
- 決めたこと: 当てはまる項目だけ1行ずつ書き、当てはまらない項目は「当てはまらない項目:」の1行に名前だけ並べる。今の雛形が求める「N/A と理由」を書かない
- 他にありえた選択肢: 当てはまらない項目にも1行ずつ理由を書く。少なくとも7項目目(前提機能の利用可否)だけは、当てはまらないとする理由を書く
- 外れていた場合: 所有者が「なぜ当てはまらないか」を本文から読めなくなる。とくに7項目目は、rules/design.md が「最も空いている」とする観点で、理由なしに「当てはまらない」と書ける形になる。戻すときは雛形の1節と、これから書く design の照合の節

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-3-1 | 中 | design.md 「新しい雛形」の design.md の4項目目、「spec を読むスキル」の `/spec-review` の rules の行 | design は、決まりとの照合を「当てはまる項目だけ1行ずつ書き、当てはまらない項目を1行にまとめる」形にする。一方、`/spec-review` の rules/design.md の観点3は「7項目すべてにチェックが入っているか。該当しない項目に N/A と理由が書かれているか」を見る。design が rules/design.md に加える変更は「`spec_format` が2なら見出しと目印を対応表の新しい名前で読む」の1文だけで、「これらのスキルの手順のうち、spec の中身の読み方以外は変えない」としている。チェック欄と理由の有無は名前の読み替えでは吸収できないので、新しい書き方で書かれた最初の design の審査で、審査役はこの観点を本文に当てられない(全項目を「チェックが無い」「理由が無い」と出すか、観点を黙って飛ばす)。あわせて、7項目目(前提機能の利用可否)を理由なしに「当てはまらない」と書けるかどうかが、雛形にも観点にも決まっていない。この design 自身も、5項目を理由なしに「当てはまらない項目」の1行に並べている | 「spec を読むスキル」の rules/design.md の行に、観点3の読み替えを書く。例: 「`spec_format` が2の spec では、7項目のうち当てはまる項目が1行ずつあり、残りが『当てはまらない項目:』の行に並んでいるかを見る」。当てはまらない理由を求めるなら、雛形の形にも理由の書き方を足す(少なくとも7項目目)。求めないなら、観点3の「理由」を新しい書き方では見ないと書く |
| D1-3-2 | 低 | design.md 「テストの方針」の1項目目 | 「`test-spec-review-scan.sh` をコンテナの中で bash と perl を使って走らせ」とあるが、`compose.yaml` のサービスはどれも `.claude/` を bind mount しておらず、`.devcontainer/` も無い。コンテナで走らせるなら、リポジトリを一時的に mount した `docker run`(`.github/scripts/tests` と同じ形)になる。フック自体はホストの bash と perl で動くので、ホストの Git Bash で走らせる方が実際の条件に近く、既存の `test-protect-main.sh` もその前提で書かれている。tasks で走らせ方を決めれば済み、設計の中身には影響しない | 「ホストの Git Bash(フックが動く環境)で走らせる」に直す。コンテナで走らせるなら、`docker run` でリポジトリを mount することを書く |
| D1-3-3 | 低 | design.md 「全体の構成」、「新しい雛形」の design.md の5項目目 | 新しい design.md の雛形は Technology Stack を「全体の構成」の「使う技術」の欄に移すが、この design 自身の「全体の構成」にその欄が無い(使う技術は「決まりとの照合」の依存追加の行に bash と perl として現れるだけ)。この design は新しい書き方の最初の見本になるので、雛形の形と自分の形が食い違う。実装には影響しない | 「全体の構成」に「使う技術: bash と perl(JSON::PP)。既存の scan と同じ」の1行を足す。または雛形の注記で、使う技術の欄も当てはまるときだけ書くと決める |

### 前の段階への指摘

なし。

- 往復: 3回目 / 高0 中1 低2
- 往復: 3回 / 未解決: 1件

## サイクル2 往復1(2026-10-02)

サイクル1で未解決として残った D1-3-1 を所有者が判断した(「関係のない項目は名前だけ並べる」)あと、見出しと項目の名前を普通の言葉に置き換え、境界の節を分け、`/spec-review` の rules/design.md の観点3の読み替えの1文を足した design.md を、requirements.md(承認済み)、Issue #474 の本文、steering、リポジトリの実ファイルと突き合わせて審査した。

D1-3-1 は本文で解消していることを確かめた。「spec を読むスキル」の部品に、観点3を「`spec_format` が2の spec では、関係のある項目に中身が書かれていること、関係のない項目が名前だけで並んでいること、7つの項目のすべてがどちらかに出ていることを確かめる」と読み替える1文があり、新しい雛形の design.md の説明(関係のある項目は1行ずつ、関係のない項目は名前だけを1行に)と一致する。この design 自身の「プロジェクトの決まりを守っているか」も、関係のある2項目(品質チェックの設定、新しいライブラリの追加)に中身があり、残る5項目が「関係のない項目:」の1行に名前だけで並び、合わせて7項目である。観点3の残りの2つ(記載と本文の矛盾、7項目目の確かめ方の記載)は、名前の読み替えだけで新しい書き方にも当てられる。

この往復で確かめた事実: `/start` の Step 5 は design.md の「This Spec Owns」を名前で読む。`/kiro-validate-impl` は `Boundary Commitments` `Out of Boundary` `Allowed Dependencies` `Revalidation Triggers` の4つと File Structure Plan と `## Implementation Notes` を、`/kiro-review` は `Boundary Commitments` と `## Implementation Notes` を、`/kiro-spec-status` は4つの節を、`/kiro-debug` は `## Implementation Notes` を、名前で読む。`/spec-review` の rules/requirements.md は requirements.md の節を名前で参照していない(「範囲」の節に当たる参照は無い)。rules/tasks.md は `_Requirements:_` `_Boundary:_` `(P)` `_Depends:_` `- [ ]*`、File Structure Plan、`Out of scope` `Non-Goals` `Out of Boundary`、雛形の完了条件の4項目を名前で参照する。`codex-review.yml` の指示は「要求・受け入れ基準」と一般の言葉で書かれ、節の名前を参照しない。`record-spec-review.sh` は SubagentStop(`spec-reviewer` に一致)と PostToolUse(SubagentHandback)の両方で動き、報告に構造化ブロックが無ければ何も書かずに終わるので、点検役の報告で証跡が書かれることは無い。`requirements-review-gate.md` の Boundary Continuity は `Boundary Candidates` `Boundary Commitments` `_Boundary:_` を名前で挙げている。今の design.md の雛形の7項目は、それぞれ確かめる内容の説明(ArchUnit、ESLint の境界、expand-contract、7項目目の「アカウント種別・プラン・可視性・地域」の軸と `gh api` での確かめ方)を持つ。`.claude/settings.json` の deny は `.claude/hooks/**` の Edit/Write だけで、`.claude/skills/` `.claude/agents/` は書ける。`.github/CODEOWNERS` は `/.claude/` を所有者に割り当てている。`spec-review-scan.sh` は `phase` が `initialized` の spec を飛ばし、`generated` が true で人の承認が無い段階だけを判定し、Stop フックは prompt_id ごとに2回まで止め、知らせるフックは UserPromptExpansion(kiro-spec-design|kiro-spec-tasks|kiro-impl)と UserPromptSubmit で動く。これらは design の前提と合っている。

要件カバレッジ: 往復3と同じ。要件1〜7の受入基準は、各部品の「対応する要件」の行のどれかに現れ、実現する部品がある。節の名前の変更で、部品と要件の対応は変わっていない。

決まりの照合(「プロジェクトの決まりを守っているか」): 品質チェックの設定の記載(`.claude/hooks/` の scan とテストは所有者が写す、`.claude/skills/` `.claude/agents/` は CODEOWNERS で承認を経る)は「ファイルの構成」「置き方」と一致し、`.github/` のファイルは出てこない。新しいライブラリの追加なしは本文(bash と perl だけ)と矛盾しない。

境界: 「作らないもの」の4項目は本文で扱っていない(`/kiro-spec-design` の案内の直しは、`/spec-review` を続けて実行する1文を足すだけで、`/kiro-validate-design` の案内には触れていない)。「使う既存の仕組み」の2つのフックは本文でも変えていない。「設計を見直すきっかけ」の2項目は、往復2で確かめた Step 6 の経路を含めて、今の本文と矛盾しない。

対応表の確認: 対応表の「今の名前」の列は、requirements.md・design.md・tasks.md の今の雛形の見出しと欄、各スキルが名前で読む目印と一致する。新しい名前の列は、この design 自身の節の名前、新しい雛形の節の並び、「spec を読むスキル」の読み替えの指示と一致する(D2-1-1 の1行を除く)。

### 申告

往復1〜3の申告は、この往復の本文でも変わっていない(往復3の申告1は、所有者の判断により「関係のない項目は名前だけ並べる」で確定した)。この往復で新しく挙げるのは、見出しの置き換えで新しく決まった次の2件。

**1. 境界の4節を、「作るものと作らないもの」の2つの小節と、「使う既存の仕組み」「設計を見直すきっかけ」の2つの独立した節に分ける** — 対応表の `## Boundary Commitments` 〜 `### Revalidation Triggers` の行、新しい雛形の design.md、「spec を読むスキル」

- Issue の記載: なし。所有者は見出しの造語を退けたが、節の分け方には触れていない
- 決めたこと: 今の `## Boundary Commitments` の下にある4つの小節を、`## 作るものと作らないもの`(`### 作るもの` `### 作らないもの`)、`## 使う既存の仕組み`、`## 設計を見直すきっかけ` の3つの `##` の節にする。Goals と Non-Goals もここに吸収する
- 他にありえた選択肢: 1つの `##` の節(たとえば「この spec の範囲」)の下に4つの小節を残す。「使う既存の仕組み」を「全体の構成」の欄にする
- 外れていた場合: 対応表の5行、新しい雛形の節の並び、`design-review-gate.md` と4つの読む側のスキルに足す読み替えの文を直す。すでに新しい雛形で書いた design.md の節の見出しも直す

**2. 「プロジェクトの決まりを守っているか」の7項目の名前を、確かめる内容が分かる言葉に置き換える(とくに「ゲート設定」を「品質チェックの設定」にする)** — 対応表の7項目の行、この design の「プロジェクトの決まりを守っているか」

- Issue の記載: なし
- 決めたこと: 「backend のコードを置く層」「frontend の機能ごとの境界」「frontend の状態の持ち方」「データベースの表の形」「新しいライブラリの追加」「品質チェックの設定」「使う外部の機能がこのリポジトリで使えるか」の7つ
- 他にありえた選択肢: 今の名前(backend層配置、ゲート設定など)のまま残す。「ゲート設定」を「変更に所有者の承認が要る設定」のように、CLAUDE.md の「ゲート設定ファイル」の範囲(`.github/` `.claude/` `eslint.config.js` `vite.config.ts` `quality.gradle` `backend/config/` ArchUnit テスト CODEOWNERS)がそのまま伝わる名前にする
- 外れていた場合: 「品質チェックの設定」の名前は、CLAUDE.md の「ゲート設定ファイル」のうち lint・テスト・カバレッジの設定を思わせ、`.github/` のワークフローや `.claude/` のスキルを含むことが名前から読めない。この design 自身は `.claude/` の変更をこの項目に書いているので、名前の指す範囲は雛形の項目の説明(D2-1-3)で補うことになる。戻すときは対応表の1行と雛形の1項目

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 低 | design.md 対応表の `## Overview`、`### Goals` の行、「新しい雛形と古い雛形」の design.md の1項目目 | 対応表は `### Goals` を `## 概要` に対応させているが、同じ design の「新しい雛形」の説明は「Goals と This Spec Owns、Non-Goals と Out of Boundary は、同じことを書く節である。Claude は、これらを『作るものと作らないもの』の節にまとめる」と書いており、Goals の行き先が節ごとに違う。Goals を名前で読むスキルは無く、`spec-writing.md` に写す対応表のこの1行がどちらになるかが変わるだけで、実装には影響しない | 対応表の `### Goals` を `### 作るもの` の行に移し、`## Overview` の行だけを `## 概要` に残す。または説明の文を「Goals は概要に、This Spec Owns と Non-Goals と Out of Boundary は『作るものと作らないもの』に」と直す |
| D2-1-2 | 低 | design.md 「spec を書くスキル」の「`spec_format` が2のときに読み替える指示」の `requirements-review-gate.md` の項目 | D1-2-3 の直しで `kiro-spec-requirements/SKILL.md` の境界の用語(`Boundary Candidates` `Boundary Commitments` `_Boundary:_`)は読み替えの一覧に入ったが、`requirements-review-gate.md` の Boundary Continuity の同じ3つの名前は、一覧の `requirements-review-gate.md` の項目(EARS の2か所だけ)に入っていない。この3行は段階ごとの用語を説明する文で、requirements.md に書く内容を指示する文ではないので、残っても新しい書き方の requirements.md の中身は変わらない | `requirements-review-gate.md` の項目に、Boundary Continuity の3つの名前を足し、代わりに従うのは対応表の新しい名前(「作るものと作らないもの」「`_対象の部品:_`」)であると書く |
| D2-1-3 | 低 | design.md 「新しい雛形と古い雛形」の design.md の4項目目 | 「7つの項目の名前を、名前だけで何を確かめるかが分かる言葉に直す。新しい名前は対応表に載せる」とあるが、今の雛形の各項目に付いている確かめる内容の説明(backend は ArchUnit の層・命名・配置、DB は expand-contract、7項目目は「アカウント種別・プラン・可視性・地域」の軸を公式の提供条件と `gh api repos/:owner/:repo` の両方で確かめること、など)を新しい雛形に残すかどうかが書かれていない。減らす節と欄の一覧にこの説明は無いので、残す読み方が自然だが、「名前だけで分かる言葉」の表現は説明を名前に置き換えると読むこともできる。説明を落とすと、書き手は7項目目で何をどう確かめればよいかを雛形から読めなくなり、審査役が観点3の3つ目(いつ何をどう確かめたかの記載)で止めるまで分からない。この spec の実装は影響を受けない | 4項目目に「各項目の確かめる内容の説明は、新しい名前の下に残す。spec の本文に書くのは、関係のある項目の1行と、関係のない項目の名前の1行だけである」のように、雛形に残すものと本文に書くものを分けて書く |

### 前の段階への指摘

なし。

- 往復: 1回目 / 高0 中0 低3
- 往復: 1回で収束 / 未解決: 0件

## サイクル3 往復1(2026-10-02)

サイクル2の収束後に所有者が design を承認し、そのあと tasks の組み立ての点検で見つかった食い違いを直すために承認を取り消して直した design.md を、requirements.md(承認済み)、Issue #474 の本文、steering、リポジトリの実ファイルと突き合わせて審査した。今回直したのは4か所(対応表の `### Goals` の行、tasks.md の見本と `(並行可)` `(#N)` の置き場所、`/spec-review` の観点のファイルが雛形の置き場所を挙げている件の例外、CLAUDE.md の「Issueの印」の項目)なので、その4か所を重点に、本文の全体をもう一度読んだ。

この往復で確かめた事実: `/spec-review` の rules/design.md の観点3は `.kiro/settings/templates/specs/design.md` を、rules/tasks.md の観点5は `.kiro/settings/templates/specs/tasks.md` を、パスで挙げて審査の基準にしている。`.claude/agents/` の下に、雛形のパスや spec の目印を名前で参照するファイルは無い。`/kiro-impl` の SKILL.md は `(P)` を「タスクの計画のための情報であり、実行の指示ではない」と扱い、タスクを1つずつ順に処理するので、印が番号の直後にあるか題名の末尾にあるかは判定に影響しない。CLAUDE.md の「Issueの印」の該当行は「tasks.md のタスクの行では、`(P)` があればその後に、無ければ説明の末尾に `(#N)` を置く。`_Requirements:_` の行には付けない」である。`kiro-spec-design/SKILL.md` は `.kiro/settings/templates/specs/research.md` を読む。

4か所の直しの確認:

- (1) 対応表の `### Goals`、`### This Spec Owns` の行が `### 作るもの` になり、`## Overview` の行だけが `## 概要` に残った。「新しい雛形と古い雛形」の design.md の1項目目(Goals と This Spec Owns、Non-Goals と Out of Boundary を「作るものと作らないもの」にまとめる)と一致する。D2-1-1 は解消した
- (2) tasks.md の見本は、小タスクの題名の末尾に `(並行可)` を持ち、題名の行と説明の文の間に空行があり、見本の説明に `(並行可)` と `(#N)` の置き場所(題名の末尾、`(並行可)` があればそのあと)が書かれている。D1-2-5 は解消した
- (3) 「spec を読むスキル」の例外1(審査役は `spec_format` の欄が無い spec では `specs-v1/` の雛形を、2の spec では `specs/` の雛形を基準にする)は、上で確かめた rules/design.md と rules/tasks.md の参照と合う。`specs-v1/` に写すのは design.md と tasks.md を含む4ファイルなので、2つの観点が参照する雛形はどちらにもある
- (4) CLAUDE.md の部品の4項目目は、見本の説明と同じ置き場所(`(#N)` は題名の末尾、`(並行可)` があればそのあと)を書いており、食い違いは無い

要件カバレッジ: サイクル2と同じ。要件1〜7の受入基準は、各部品の「対応する要件」の行のどれかに現れ、実現する部品がある。今回の直しで部品と要件の対応は変わっていない。

決まりの照合(「プロジェクトの決まりを守っているか」): サイクル2と同じ。記載は「ファイルの構成」「置き方」と矛盾しない。

境界: 「作らないもの」の4項目は本文で扱っていない。「使う既存の仕組み」の2つのフックは本文でも変えていない。

設計内の矛盾: 見本の `(並行可)` の付け方、見本の説明、CLAUDE.md の部品、対応表の `(P)` の行は互いに合っている。処理の流れと `/spec-review` の工程の置き場所も変わっていない。

### 申告

サイクル1・2の申告は、この往復の本文でも変わっていない。この往復で新しく挙げるのは、今回の直しで新しく決まった次の1件。

**1. `(並行可)` と `(#N)` を、タスクの題名の末尾に置く** — 「tasks.md の見本」の説明、「CLAUDE.md」の部品の4項目目

- Issue の記載: なし
- 決めたこと: 今の書き方では `(P)` を番号の直後(`- [ ] 2.1 (P) 題名`)に置くが、新しい書き方では題名の末尾に `(並行可)` を置き、追加の Issue の印 `(#N)` は `(並行可)` のあとに置く
- 他にありえた選択肢: 今と同じく番号の直後に `(並行可)` を置く
- 外れていた場合: `/kiro-impl` は `(P)` を情報として読むだけなので、判定は変わらない。直すのは見本の説明、新しい tasks.md の雛形、CLAUDE.md の1行と、すでに新しい書き方で書いた tasks.md の題名の行

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-1-1 | 低 | design.md 「spec を書くスキル」の役割、「新しい雛形と古い雛形」の init.json の項目、「ファイルの構成」 | 「spec を書くスキル」は「欄が無ければ、古い雛形と今の決まりのファイルを使う」と定め、「新しい雛形と古い雛形」は `specs-v1/` に init.json を置かない理由を書いている。しかし research.md の雛形については、「ファイルの構成」に「research.md は変えない」とあるだけで、`specs-v1/` に写すのか、新旧どちらの spec でも `specs/research.md` を読むのかが書かれていない。`kiro-spec-design/SKILL.md` は `.kiro/settings/templates/specs/research.md` を読むので、実装者が「欄が無ければ古い雛形」を雛形の全ファイルに当てはめて `specs-v1/research.md` を読む形にし、かつ research.md を写さないと、今の書き方の spec で `/kiro-spec-design` が雛形を見つけられない。tasks.md が「init.json と research.md を写さない」と決めており、読み替えの一覧にも research.md のパスは無いので、tasks のとおりに実装すれば起きない。設計の中身には影響しない | 「新しい雛形と古い雛形」の init.json の項目の隣に「research.md の雛形は `specs/` に1つだけ置き、新旧どちらの spec でも `/kiro-spec-design` はそこから読む」の1文を足す |

### 前の段階への指摘

なし。

- 往復: 1回目 / 高0 中0 低1
- 往復: 1回で収束 / 未解決: 0件
