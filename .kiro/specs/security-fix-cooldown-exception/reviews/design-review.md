## サイクル1 往復1(2026-11-02)

### 審査の範囲

範囲: 全体

### 申告

**1. Dependabot の PR を、すべて `dependency-cooldown` の対象にした** — 部品の「dependency-review.yaml の cooldown ジョブ」の「いつ動くか」、概要

- Issue の記載: 「最初の修正版に上げる変更は、誰が作ったかによらず」に当たる記載は要件1の7にある。Dependabot の版の更新の PR を72時間の待ちにかけるかは、Issue にも requirements にも無い
- 決めたこと: `github.event.pull_request.user.login != 'dependabot[bot]'` の条件を外し、Dependabot の PR も、最初の修正版の PR に限らず、72時間の待ちにかける
- 他にありえた選択肢: Dependabot の PR のうち、若い版を含むものだけを新しい判定にかけ、若い版が最初の修正版でなければ今と同じく通す。または、Dependabot の PR は今と同じく対象から外し、最初の修正版の例外だけを足す
- 外れていた場合: 今は通っている backend の Dependabot の PR(版の更新のまとめの PR を含む)が、推移的に入る若い部品で赤になり、再実行されるまで止まる。D1-1-1 のとおり、止まったことは週次監査で知らされない

**2. 所有者の承認を `dependency-cooldown` の中で求め、PR に記録のコメントが一度でも付けば、その後のどの head でも承認を求める** — 処理の流れの箇条の6つ目、research.md の「所有者の承認を、検査 dependency-cooldown の中で求める」

- Issue の記載: あり。「PR が自動で作られても、所有者が承認するまでマージされない」「承認を待つあいだに…72時間経っても…所有者が承認するまでマージされない」
- 決めたこと: 記録のコメントがあるかで承認の要否を決める。前の head の記録でも承認を求める
- 他にありえた選択肢: `dependency-gate` に判定させる。記録のある head だけで承認を求める
- 外れていた場合: 記録が付いた PR は、若い版を外す直しを push しても、所有者の承認が無いとマージされない

**3. backend の警告の scope を、依存グラフに `productionRuntimeClasspath` で scope を付けることで得る** — 部品の「dependency-graph.yaml と dependency-review.yaml の generate ジョブ」、設計を見直すきっかけの2つ目

- Issue の記載: なし(「本番で動く…部品」とだけある)
- 決めたこと: `DEPENDENCY_GRAPH_RUNTIME_INCLUDE_CONFIGURATIONS: productionRuntimeClasspath` を足し、送った scope が Dependabot の警告の `dependency.scope` に載ることを前提にする。載るかは文書で確かめられておらず、マージのあとに確かめる
- 他にありえた選択肢: 警告の `manifest_path` や、比較の API の scope など、ほかの材料で本番で動くかを決める
- 外れていた場合: 載らなければ、backend の版は1つも72時間待たずに入らず、Issue の「どうなれば解決か」の1つ目を backend で満たせない。止まる側に倒れるので、悪意のある版が入ることはない

**4. frontend で、若い版を除外の欄に足して急いで通す今のやり方が使えなくなる** — 部品の「check-dependency-cooldown.sh」、`frontend/pnpm-workspace.yaml` のコメントの書き直し

- Issue の記載: なし
- 決めたこと: `dependency-cooldown` が npm の部品も見るので、最初の修正版でない若い版は、除外の欄に足して `dependency-gate` で所有者が承認しても、72時間経つまで入らない
- 他にありえた選択肢: 最初の修正版でない若い版でも、除外の欄にあり所有者が承認すれば通す
- 外れていた場合: 所有者が今のやり方(`pnpm-workspace.yaml` のコメントの「急いで通す必要がある場合のみ minimumReleaseAgeExclude に対象を一時的に追加する」)で急ぎの変更を入れようとしても、入らない。要件2の1には合っている

**5. Maven の署名の公開鍵を keyserver.ubuntu.com だけから取る** — 部品の「cooldown-check-signer.sh」の「maven のとき」

- Issue の記載: なし
- 決めたこと: 鍵を keyserver.ubuntu.com だけから取り、取れなければ `unknown` にする
- 他にありえた選択肢: keys.openpgp.org など、ほかの鍵の置き場も順に引く
- 外れていた場合: keyserver.ubuntu.com に鍵を置いていない公開元の部品は、いつも72時間待つ。止まる側に倒れるので安全だが、backend で72時間待たずに入る版が思ったより少なくなる

**6. 週次監査の一覧を、Issue「週次監査: 逸脱あり」で届ける** — 部品の「check-audit-cooldown-exceptions.sh」

- Issue の記載: あり。「週次の監査の報告に一覧で載る」
- 決めたこと: 終了コード1(逸脱あり)を使い、決まりから外れていない一覧を「逸脱あり」の Issue で届ける
- 他にありえた選択肢: `audit-issue.sh` に「報告のみ」の結果を足す
- 外れていた場合: 72時間待たずに入れた版がある週は、ほかに逸脱が無くても「逸脱あり」の Issue が開き、実行の記録にも「逸脱を検知しました」と出る

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 高 | design.md 部品「required-checks.json」と「失敗したときの扱い」の3つ目 | 「失敗したときの扱い」は、Dependabot の PR が若い推移的な部品で止まり再実行されないときは、週次監査の `dependabot-stuck` が見つけると書く。しかし、設計は `required-checks.json` の `dependency-cooldown` を `approval_gated: true` にする。`check-audit-dependabot-stuck.sh` は、`approval_gated: true` のチェックの失敗を「承認待ち」として報告するだけで、逸脱に数えない(同スクリプトの9〜13行目)。そのため、72時間待ちで赤になった Dependabot の PR は、逸脱にも Issue にもならず、黙って止まったままになる。止まる PR には、親の部品が最初の修正版でないために止まった Dependabot のセキュリティの更新も含まれ、脆弱性の修正がかえって遅れる。テストの方針にもこの場合が無いので、実装しても誰も気づかない | 72時間待ちの赤と承認待ちの赤を `dependabot-stuck` が見分けられる作りにする(例: `dependency-cooldown` の check-run の出力の目印で分ける)か、`approval_gated` を `false` のままにして承認待ちの Dependabot の PR も滞留として知らせるか、72時間経った PR の `dependency-cooldown` を再実行する仕組みを足すかを決め、design に書く。決めた形をテストの方針に足す |
| D1-1-2 | 中 | design.md 移行の箇条の4つ目、性能の1つ目、処理の流れの図 | 移行では「次の Dependabot の PR の…実行の記録で、警告の API が 403 にならなかったこと」を確かめるとする。しかし処理の流れと性能の節のとおり、警告の API は若い版がある PR でしか呼ばれない。ふつうの Dependabot の PR と実装の PR では警告の API が呼ばれないので、この確認はできない。「プロジェクトの決まりを守っているか」の7つ目も、ワークフローの標準のトークンで警告を読めることを、このリポジトリでは確かめていない。読めないと分かるのは、本物の high か critical の警告が出て、最初の修正版が止まったときになる。止まる側に倒れるので安全だが、要件1の1の仕組みが動かないまま実装が終わる | 実装の PR と Dependabot の PR で必ず通る場所で、ジョブのトークンで警告の API を1回読む確認を足す(例: `cooldown` ジョブで若い版の有無によらず `dependabot/alerts?per_page=1` を読み、403 なら赤にするか報告に出す)。実際の環境で確認することの節と移行の節を、その確認に合わせて直す |
| D1-1-3 | 中 | design.md 部品「verify-ci-tool.sh」の出力、部品「ci-tool-fast-update のスキル」の手順5、データの形「CI の道具の記録」 | `verify-ci-tool.sh` は、記録の JSON を base64 にした目印の行を、`owner_instruction` を空にして出す。設計は「Claude が PR の本文に書くときに埋める」とするが、欄は base64 の中にあり、埋めるには解いて書き直して base64 に戻す必要がある。スキルの手順5は「スクリプトが出した…記録の目印の行を書く」だけで、埋める手順が無い。この手順どおりに動くと、要件5の3の「所有者が指示したこと」が記録に入らず、要件5の6の週次監査の一覧の理由の列も空になる。テストの方針もこの欄を見ていない | `verify-ci-tool.sh` に所有者の指示の要約を引数で渡し、スクリプトが欄を埋めて base64 にする形にする。スキルの手順2にその引数を足し、`test-verify-ci-tool.sh` に、欄が埋まっていることと、空の引数を拒むことの確認を足す |
| D1-1-4 | 低 | design.md データの形「検査の報告」の1段落目 | 悪意のある部品で止めたときに、入るようになる時刻の欄に「入らない」と書くとある。しかし範囲の「決めないこと」の8つ目と research.md の R3-2-1 の扱いのとおり、止めた変更は、すべての版が72時間経てば、悪意のある部品の確認なしに今の決まりで入る。「入らない」は事実と違い、読む人は放っておいても入らないと受け取る | 欄の文を「72時間経つと、この確認なしで入る。変更を取り下げること」のように、実際の動きに合わせる |
| D1-1-5 | 低 | design.md 「プロジェクトの決まりを守っているか」の「品質チェックの設定」 | ルートの CLAUDE.md は `.claude/` もゲート設定に数える。設計は `.claude/skills/ci-tool-fast-update/SKILL.md` と `.claude/scripts/ci-tool-signature/` の4つのファイルを作るが、この項目は `.github/` のファイルしか挙げていない。CODEOWNERS が承認を求めることは部品「trusted-signers.json」にだけ書いてある | この項目に `.claude/` の新しいファイルを足し、CODEOWNERS が承認を求めることを書く |
| D1-1-6 | 低 | design.md 部品「rerun-approval-gated-checks.yaml」と「dependency-review.yaml の cooldown ジョブ」の打ち切り | `rerun-approval-gated-checks.yaml` は、対象のチェックの完了を最大10分待ち、待ちきれないと、ほかの対象(`escape-hatch` など)も再実行せずに赤で終わる(同ファイルの59〜67行目)。対象に `dependency-cooldown` を足すと、`cooldown` ジョブの打ち切り(30分)より短い待ちの中で完了しないことがある。所有者が `Dependency Review` の実行中に承認したとき、ほかの承認待ちのチェックも手で再実行することになる | 待つ時間を `cooldown` ジョブの打ち切りに合わせて延ばすか、待ちきれないときの扱いを「失敗したときの扱い」に書く |
| D1-1-7 | 低 | design.md 「プロジェクトの決まりを守っているか」の「使う外部の機能がこのリポジトリで使えるか」 | 「API で読めることを確かめた(警告の番号209〜211)」「PR #637 と PR #670 で…確かめた」に、いつ、どのコマンドで確かめたかが無い。OSV、npm の来歴の置き場、keyserver.ubuntu.com を使えるかにも触れていない | 確かめた日付とコマンドを書き足し、ほかの外部のサービスについても使える根拠を1行ずつ足す |
| D1-1-8 | 低 | design.md 「使う技術」の CI の道具の署名の検証、部品「verify-ci-tool.sh」 | `gpg` のコンテナの土台の Debian slim のイメージと `cosign` のイメージを digest で固定するが、置き場が `.claude/scripts/ci-tool-signature/` とスクリプトの定数なので、Dependabot の docker の更新(`/docker/*`)にも棚卸しにも入らず、古くなっても誰も気づかない | 固定した digest を誰がいつ見直すかを書くか、棚卸しの対象に足すかを決める |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| D1-1-9 | requirements | 範囲の「この spec が前提にしていること」の2つ目 | 「72時間の待ちが、今、frontend と backend の部品に効いていること」を前提にしている。しかし design の概要のとおり、今の `dependency-cooldown` は Dependabot の PR を対象から外しており、backend の Dependabot の PR には72時間の待ちが効いていない。要件1の4、1の5、2の1、2の2の「今と同じく」は、Dependabot の PR では「待たない」を指すことになる。design はこれを「Dependabot の PR も待つ」に変えて進めている(申告1)。Dependabot の版の更新の PR まで72時間の待ちにかけるかは requirements で決まっていない |

- 往復: 1回目 / 高1 中2 低5

## サイクル1 往復2(2026-11-02)

### 審査の範囲

範囲: 差分

- design.md 概要、作らないもの、設計を見直すきっかけ、プロジェクトの決まりを守っているか、使う技術、処理の流れの箇条、権限、rerun-approval-gated-checks.yaml、required-checks.json、record-cooldown-exception.sh、dependency-graph.yaml、cooldown-check-signer.sh、cooldown-check-pnpm-exclude.sh、CLAUDE.md の1行、安全、性能: 書き方の点検の直しの行。意味が変わっていないか、消した文(CI の道具の版を機械で止めないこと、ジョブの30分の打ち切り、CLAUDE.md に1行を置く理由)がほかの節に残っているかを確かめた。作らないもの、cooldown ジョブの打ち切り、CLAUDE.md の節に残っている
- design.md 部品「check-audit-dependabot-stuck.sh」、ファイルの構成、失敗したときの扱い、テストの方針(D1-1-1 の直し): `record-cooldown-exception.sh exists` の名前で record-cooldown-exception.sh の節を、`approval_gated` の名前で required-checks.json の節と設計を見直すきっかけを読んだ。`.github/scripts/check-audit-dependabot-stuck.sh`、`.github/scripts/lib-notice-comment.sh`、`.github/scripts/audit-issue.sh`、`.github/workflows/audit-weekly.yaml` の権限、`.claude/skills/ship/SKILL.md` の手順7の4を読み、前提が成り立つかを確かめた
- design.md 部品「check-dependency-cooldown.sh」の役割と使う部品、性能、テストの方針、移行(D1-1-2 の直し): 「警告の API」の語で、cooldown-match-alerts.sh の節、処理の流れ、プロジェクトの決まりを守っているかの7つ目を読んだ
- design.md 部品「verify-ci-tool.sh」、「ci-tool-fast-update のスキル」、テストの方針(D1-1-3 の直し): `owner_instruction` の語で、データの形の CI の道具の記録を読んだ
- design.md 部品「cooldown ジョブ」の動かす条件(D1-1-9 の却下の根拠の書き足し): `.github/dependabot.yml` の冒頭のコメントを読み、却下の理由が事実として正しいかを確かめた。理由の(1)と(3)は事実のとおりで、指摘は出し直さない
- design.md 失敗したときの扱いの4つ目(`/ship` の扱いの書き足し): `.claude/skills/ship/SKILL.md` の手順7の4の5と Report の節を読んだ

### 申告

**1. Dependabot の PR の `dependency-cooldown` の赤を、記録のコメントの有無で、承認待ちと滞留に分ける** — 部品「check-audit-dependabot-stuck.sh」

- Issue の記載: なし(「所有者が承認するまでマージされない」とだけある)
- 決めたこと: 記録のコメントがある PR の赤はすべて承認待ち(終了コード 0。Issue は作らない)、無い PR の赤はすべて滞留(終了コード 1)に数える。経過時間は見ない
- 他にありえた選択肢: check-run の出力の目印(「所有者の承認待ち」の見出し)で分ける。若い版の公開から72時間経ったかで分ける
- 外れていた場合: 記録のある PR が別の理由で止まっても、週次監査の Issue にはならず、Job Summary の承認待ちの一覧にだけ出る。記録の無い PR は、72時間経つ前でも逸脱の Issue になる

**2. 警告の API を読めなくても、緑か赤かを変えない** — 部品「check-dependency-cooldown.sh」の使う部品

- Issue の記載: なし
- 決めたこと: `dependabot/alerts?per_page=1` を毎回1回読み、読めなければ `::warning::` と報告の1行だけを出す
- 他にありえた選択肢: 読めなければ赤にする
- 外れていた場合: 権限の設定が崩れて警告を読めなくなっても、検査は緑のままで、気づくのは報告を読んだ人だけになる。止まる側に倒れる(最初の修正版が72時間待つ)ので、悪意のある版が入ることはない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 中 | design.md 失敗したときの扱いの4つ目、部品「required-checks.json」の2段落目 | 「Claude が作った PR が72時間経っていない版で止まったときは、`/ship` は…承認待ちに数え、状態を報告して見届けを終える。…Claude は時刻のあとに再実行する」とある。`/ship` の手順7の4の5は、この赤を所有者の承認待ちとして扱い、Report に「人間の承認: 承認を待っている」「見届けを終えた理由: 承認待ち」と書く。記録の無い PR では所有者の承認で緑にならないので、所有者は承認しても進まない赤を承認待ちと伝えられる。承認すると `rerun-approval-gated-checks.yaml` が再実行し、まだ赤のままなのでそのワークフローも赤になる。また `/ship` は見届けを終えて会話を離れるので、「Claude は時刻のあとに再実行する」を行わせる部品が無い。ファイルの構成にも `.claude/skills/ship/SKILL.md` は無く(手順7の4の5の「今は `escape-hatch` `dependency-gate` `pre-merge-check`」の一覧も古いまま残る)、tasks に落ちないまま実装が終わる | `/ship` が `dependency-cooldown` の赤を、報告の見出し(「所有者の承認待ち」か「72時間の待ちで止めた部品」か)で分けて、72時間の待ちのときは入るようになる時刻を所有者への報告に書き、承認を求めない形にする。再実行は誰がいつ行うか(所有者が時刻のあとに再実行する、など)を書く。`.claude/skills/ship/SKILL.md` をファイルの構成に足す |
| D1-2-2 | 低 | design.md 失敗したときの扱いの3つ目と部品「check-audit-dependabot-stuck.sh」 | 失敗したときの扱いは「72時間経っても再実行されないときは…滞留として見つける」とするが、部品の節は、記録の無い PR の `dependency-cooldown` の赤を、経過時間によらず滞留に数える。週次監査の直前に開いた Dependabot の PR は、まだ待ちの途中でも「逸脱あり」の Issue になる | 失敗したときの扱いの文を部品の節の動きに合わせるか、監査手順.md に「入るようになる時刻の前なら待つ」と書くことを、ファイルの構成の監査手順.md の行に足す |
| D1-2-3 | 低 | design.md 部品「check-audit-dependabot-stuck.sh」の最後の段落 | 「この PR は、承認待ちの一覧に毎週出るので、止まったまま誰にも気づかれないことは無い」とある。承認待ちだけのときは終了コード 0 で、`audit-issue.sh` は結果 none として Issue を作らず、一覧は緑の実行の Job Summary にしか出ない。「気づかれないことは無い」は言い過ぎである | 「緑の実行の Job Summary の承認待ちの一覧に出る(Issue にはならない)」と事実のとおりに書く |

- 往復: 2回目 / 高0 中1 低2

## サイクル1 往復3(2026-11-02)

### 審査の範囲

範囲: 差分

- design.md 部品「ship のスキル」、ファイルの構成の `.claude/skills/ship/SKILL.md` の行、部品「required-checks.json」の2段落目、失敗したときの扱いの4つ目、部品「check-dependency-cooldown.sh」の出力(D1-2-1 の直し): 「`::error::`」の語で check-dependency-cooldown.sh の節を、`record-cooldown-exception.sh exists` の語で record-cooldown-exception.sh と check-audit-dependabot-stuck.sh の節を読んだ。`/ship` が開発者の PC でこのスクリプトを動かす前提が成り立つかを確かめるため、`.github/scripts/lib-notice-comment.sh`(`notice_last_kind` と `_notice_require`)、`.github/CLAUDE.md` のシェルのスクリプトのテストの節、ルートの CLAUDE.md の Git規約の前提、`.claude/skills/ship/SKILL.md` の手順7の4と Report の節、`.claude/settings.json` の `gh run` の許可を読んだ
- design.md 失敗したときの扱いの3つ目(監査手順.md に書く文の削除): 監査手順.md の扱いがほかに残るかを「監査手順」の語で探した。ファイルの構成の `doc/開発フロー/監査手順.md` の行と作るものの文書の一覧に残っている
- design.md 設計を見直すきっかけ(信頼する署名した者のデータのファイルを直す文の削除): 「trusted-signers」の語で探した。部品「trusted-signers.json」の役割に「配布元が鍵や身元を替えたときは、このファイルだけを直す」が残っている
- design.md 作らないもの(Terraform の言い換え)、cooldown ジョブの動かす条件と Dependabot の PR の扱い(箇条の分割)、cooldown-check-signer.sh の npm のとき、cooldown-check-pnpm-exclude.sh の読み方と終了コード、テストの方針の pnpm-exclude と結合テストの言い換え、dependency-graph.yaml の役割、check-audit-dependabot-stuck.sh の箇条、安全の3つ目、移行の1つ目: 書き方の点検の直しの行。差分の前と後で意味が変わっていないこと、言い換えた語(「流れの形」を「`[...]` の中に並べて書かれている」、「例外の版」を「72時間待たずに入れる版」)が、部品の節とテストの方針で同じ言い方にそろっていることを確かめた

### 申告

**1. 72時間の待ちで止まった Claude の PR は、`/ship` が見届けを終え、所有者が会話で頼んだときだけ再実行する** — 部品「ship のスキル」

- Issue の記載: なし
- 決めたこと: 記録のコメントが無い PR の `dependency-cooldown` の赤では、`/ship` は所有者に承認を求めず、入るようになる時刻を報告して見届けを終える。再実行は、所有者が時刻のあとに会話で頼んだときに Claude が行う
- 他にありえた選択肢: Claude が時刻まで待ちの道具で待って自分で再実行する。所有者が GitHub の画面から再実行する。若い版を外す直しを Claude が push する
- 外れていた場合: 所有者が時刻を覚えていて頼まないかぎり、PR は赤のまま残る。Claude の PR は週次監査の `dependabot-stuck` の対象ではないので、残っていることを知らせる仕組みは無い

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-3-1 | 中 | design.md 部品「ship のスキル」の使う部品と5つ目の箇条 | `/ship` は `record-cooldown-exception.sh exists` を開発者の PC で動かすとある。このスクリプトは `lib-notice-comment.sh` の `notice_last_kind` を使い、`notice_last_kind` は `_notice_require` で `jq` が無ければ `::error::jq が見つかりません。` を出して 1 を返す(`lib-notice-comment.sh` の57〜70行目)。ルートの CLAUDE.md の Git規約は、ホストの前提を bash と perl とし「jqには依存しない」とし、`.github/CLAUDE.md` も「ホストの前提は bash と perl だけで、`jq` が無いことがある」とする。`jq` の無い PC では、`/ship` は記録のコメントをいつも読めず、5つ目の箇条のとおり、記録のコメントがある PR(所有者の承認を待つ PR)も承認待ちに数えずに「読めなかった」と報告して見届けを終える。所有者は承認を求められず、要件1の2の承認待ちの PR が、承認待ちと伝えられないまま止まる。設計はこの前提を確かめておらず、実装して初めて `/ship` を使う場面で分かる | `/ship` が記録のコメントを、`jq` に頼らない方法で読むようにする。例: `gh api --paginate repos/<owner>/<repo>/issues/<PR番号>/comments --jq '<github-actions[bot] が書いた cooldown-exception-record の目印があるか>'` のように `gh` の組み込みの `--jq` で読む(`gh` の `--jq` は `jq` を入れずに動く)。または `record-cooldown-exception.sh` を `.github/CLAUDE.md` のテストと同じく `jq` を入れた1回きりのコンテナで動かす。どちらにするかを ship のスキルの節の使う部品に書き、見分け方が `check-audit-dependabot-stuck.sh` と同じ(作者が `github-actions[bot]`、目印の接頭辞が同じ)ことを書く |
| D1-3-2 | 低 | design.md 部品「ship のスキル」の2つ目と3つ目の箇条 | 記録のコメントが無い `dependency-cooldown` の赤は、承認待ちのゲートから外れるので、手順7の4の5の「承認待ちのゲートのほかに必須の検査の赤が無いとき」に当たらず、今の判定の順では4の6(赤を直して push する)に進む。設計は「見届けを終える」とするが、4の判定の順のどこにこの扱いを置くか(4の5の中か、4の6より前の新しい項か)と、CODEOWNERS の承認待ち(`reviewDecision` が `REVIEW_REQUIRED`)と重なったときにどちらを報告するかを書いていない。手順の書き手が4の6に落とすと、Claude が若い版を直そうとする | 4の5の中に「`dependency-cooldown` の赤で記録のコメントが無いときは、承認待ちに数えず、ほかに赤が無ければ時刻を報告して見届けを終える」の形で置くことと、`REVIEW_REQUIRED` と重なったときは両方を報告することを書く |

- 往復: 3回 / 未解決: 1件

## サイクル2 往復1(2026-11-02)

### 審査の範囲

範囲: 差分

- design.md 部品「ship のスキル」の2つ目の箇条と使う部品(D1-3-1 の直し。`record-cooldown-exception.sh exists` を `gh api --paginate … --jq` に替えた): 「記録のコメント」「`record-cooldown-exception.sh exists`」「`cooldown-exception-record`」の語で、record-cooldown-exception.sh、check-audit-dependabot-stuck.sh、check-audit-cooldown-exceptions.sh、データの形の記録のコメント、安全の2つ目を読んだ。見分け方が同じという主張を確かめるため `.github/scripts/lib-notice-comment.sh` の `_notice_author_comments` と `notice_last_kind`(作者の絞り方と目印の正規表現)を読んだ。開発者の PC で動くかを確かめるため `.claude/settings.json` の `gh` の許可と `.claude/skills/ship/SKILL.md` の手順7の4と Report の節を読んだ
- design.md 部品「check-dependency-cooldown.sh」の失敗したとき(「入るようになる時刻も書く」の書き足し)と、失敗したときの扱いの1つ目(赤と報告の文の削除): 「入るようになる時刻」「外部のサービス」の語で、データの形の検査の報告と requirements.md の要件7の2を読んだ
- design.md 全体(「若い版」の呼び名を外し「公開から72時間経っていない版」に置き換えた): 「若い」の語で design.md を検索し、残りが無いことを確かめた。置き換えた箇所の前後(処理の流れの図と箇条、cooldown-match-alerts.sh、cooldown-check-pnpm-exclude.sh、検査の報告の理由の表、テストの方針、性能、移行)で意味が変わっていないことを確かめた
- design.md 処理の流れの8つ目の箇条(「記録に載せた版が」の書き足し)、cooldown-check-malware.sh の役割(止めるかを判定しない文の書き足し)、データの形の記録のコメントの最後の段落、設計を見直すきっかけの2つ目(scope を送るワークフローの明記)、プロジェクトの決まりを守っているかの7つ目(箇条への分割)、cooldown ジョブの推移的な部品の言い換え、cooldown-check-signer.sh の OIDC の発行元の言い換え、check-audit-cooldown-exceptions.sh のいつ動くか、使う既存の仕組みの `/ship`: 書き方の点検の直しの行。差分の前と後で意味が変わっていないことと、ほかの節と食い違わないことを確かめた

### 申告

**1. `/ship` は記録のコメントを、`record-cooldown-exception.sh` とは別に `gh api` の `--jq` の式で読む** — 部品「ship のスキル」の使う部品

- Issue の記載: なし
- 決めたこと: CI の `record-cooldown-exception.sh exists`(`notice_last_kind` の正規表現)と、`/ship` の `gh api --jq` の式(`contains("<!-- cooldown-exception-record kind=exception")`)の2か所に、記録のコメントの見分け方を置く
- 他にありえた選択肢: `record-cooldown-exception.sh` を `jq` を入れた1回きりのコンテナで動かし、見分け方を1か所に保つ
- 外れていた場合: あとで目印の形(属性の順番や `kind` の値)を変えたときに片方だけを直すと、`/ship` と CI で記録のコメントの有無の判定が食い違う。`/ship` が承認待ちの PR を「72時間の待ち」と報告するか、その逆になる。今の目印の形(`kind=exception` が接頭辞の直後)では、2つの見分け方は同じ結果になる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 低 | design.md 失敗したときの扱いの1つ目 | 直しで「報告に、問い合わせられなかったことと入るようになる時刻を書く」の文を消したため、続く「変更を作った人は、時刻のあとか…再実行する」の「時刻」が、この箇条の中で何の時刻かを指す語を持たなくなった | 「時刻のあと」を「すべての版が公開から72時間経ったあと」に書き換える |
| D2-1-2 | 低 | design.md 部品「check-dependency-cooldown.sh」の失敗したとき | 書き足した「外部のサービスの失敗は…入るようになる時刻も書く」は、外部のサービスの失敗のすべてにかかる。しかし同じ段落の比較の API を読めないときと公開日時を読めないときは、公開日時が分からないので、入るようになる時刻を求められない。要件7の2の時刻は「その版の公開から72時間経つ時刻」なので、求められる版にだけ書くと読むのが自然で、実装は迷わない | 「入るようになる時刻を求められる版には、その時刻も書く」と、求められないときの扱いを書き分ける |
| D2-1-3 | 低 | design.md 部品「ship のスキル」の使う部品と4つ目の箇条 | `/ship` が使う `gh api --paginate …` と `gh run rerun … --failed` は、`.claude/settings.json` の許可の一覧(`gh run view` `gh run list` `gh run watch` などはある)に無い。許可の判定に回るため、所有者に確かめを求めるか、自動モードの判定で止まることがある。動かないわけではないが、設計はこのことに触れていない。許可を足すのはゲート設定の変更で、所有者への提案になる | 許可に足すことを所有者に提案するか、許可の判定に回ることを受け入れるかを、ship のスキルの節かプロジェクトの決まりを守っているかの「品質チェックの設定」に1行書く |

- 往復: 1回で収束 / 未解決: 0件

## サイクル3 往復1(2026-11-02)

### 審査の範囲

範囲: 差分

- design.md 作るもの、設計を見直すきっかけの最後の箇条、プロジェクトの決まりを守っているかの「品質チェックの設定」、ファイルの構成の `.github/actionlint.yaml` の行、部品「actionlint.yaml」、テストの方針の実際の環境で確認することの3つ目、移行の1つ目(actionlint の設定ファイルの書き足し): 「actionlint」「vulnerability-alerts」の語で design.md を検索し、cooldown ジョブの権限の節と cooldown-match-alerts.sh の権限の節を読んだ。前提が成り立つかを確かめるため、`.github/workflows/guardrails.yaml` の actionlint の呼び出し(44行目。版 1.7.12、設定ファイルを指す引数なし)と、`.github/scripts/check-escape-hatches.sh` のゲート設定の判定(196行目。`.github/` の変更を所有者の承認の対象にする)を読み、`.github/` の下に actionlint の設定ファイルが今は無いことを確かめた。actionlint の版を誰が見張るかを確かめるため、`.github/` の yml・yaml・json・sh を「actionlint」「1.7.12」で検索した。「対応する要件: 1.1」の当否を確かめるため、requirements.md の要件1の見出しを読んだ
- design.md 部品「verify-ci-tool.sh」の呼び出し方(任意の環境変数 `TRUSTED_SIGNERS_FILE` と JSON の読み方の書き足し): `trusted-signers.json` の語で部品「trusted-signers.json」と ci-tool-fast-update のスキルの手順2と4を、`perl`・`jq` の語でプロジェクトの決まりを守っているかの「新しいライブラリの追加」と、ルートの CLAUDE.md の Git規約の前提(bash と perl(JSON::PP))を読み、テストの方針の `test-verify-ci-tool.sh` の箇条(`docker` `curl` `gh` をスタブにする)と食い違わないことを確かめた
- design.md 作らないものの1つ目、cooldown ジョブの手順1〜4、check-dependency-cooldown.sh の使う部品の公開日時、cooldown-check-signer.sh の役割と maven のときと失敗したとき、check-audit-dependabot-stuck.sh の役割の最後の文、失敗したときの扱いの1つ目、テストの方針の前書きと各箇条の括弧の中の要件の言い換えの削除: 書き方の点検の直しの行。差分の前と後で意味が変わっていないことと、括弧の中の要件の番号が残っていることを確かめた。失敗したときの扱いの1つ目の「検査の報告に出た入るようになる時刻」は、D2-1-1 を受けた直しで、check-dependency-cooldown.sh の失敗したときの「入るようになる時刻も書く」と同じ時刻を指す(D2-1-2 の書き分けは記録のみで、本文は前のまま)

### 申告

なし。actionlint の1件の指摘を設定ファイルで無視させる方式は、起動の文のとおり所有者が選んだもので、AI が決めたことではない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-1-1 | 低 | design.md 設計を見直すきっかけの最後の箇条 | 「actionlint が `vulnerability-alerts` の権限を知る版を出したとき」に `.github/actionlint.yaml` の無視の設定を消すとするが、actionlint の版は `guardrails.yaml` の `run` の中の `docker run … rhysd/actionlint:1.7.12` に直書きされており、Dependabot の更新の対象にも、`.github/` のほかのスクリプトの見張りにも入っていない。新しい版が出たことに気づく者がいないので、このきっかけは起きても誰にも見つからない。無視の設定は1つのファイルの1つの文だけを指すので、残ってもワークフローの誤りは隠れず、実装には影響しない | 「新しい版に気づく仕組みは無く、ほかの理由で actionlint の版を上げたときに見直す」と書き添えるか、見直すきっかけを「`guardrails.yaml` の actionlint の版を上げたとき」に言い換える |

- 往復: 1回で収束 / 未解決: 0件
