# Implementation Plan

## KeirekiPro 完了条件(全タスク共通)

1. **acceptance criteria の引用とテスト対応付け**: 各タスクは対応する requirements.md の受入基準を引用し、それを検証する手段(実機確認の項目番号)を detail に持つ
2. **verify の実行**: 変更領域が `.claude/` と `.kiro/` と `CLAUDE.md` / `README.md` のみのため、既存の verify Skill(frontend / backend / terraform)は対象外。**代替として、design.md の Testing Strategy に定めた実機確認(項目1〜12)を実施し、結果を記録する**(フックはシェルスクリプトで、入力がJSON・副作用がファイルのため、既存のテストの器が無い)
3. **ゴールハック禁止**: 実機確認の項目を減らす、確認せずに完了とする、検知条件を緩めて通す、のいずれもしない
4. 新規のフックは、止まるべき状態を実際に作って止まることを確認してから、通るべき状態で通ることを確認する

## Tasks

- [x] 1. レビューの観点とレビュー役を定義する
- [x] 1.1 共通のルール(レベル・申告・指摘ID・記録の書式・処置)を作る
  - 高・中・低の定義を「承認後にどこまで戻るか」で書く(受入基準 3.1、3.2)
  - 申告の4項目と、選択肢が書けないものは申告しない規則を書く(受入基準 2.7、2.9)
  - 指摘IDの形式と、記録の書式、最終行の印を定める(受入基準 5.3、5.4)
  - 処置の5種類を定める(受入基準 3.5)
  - 完了の観測条件: `.claude/skills/spec-review/rules/common.md` が存在し、レベル・申告・ID・書式・処置のすべてを含む
  - _Requirements: 3.1, 3.2, 3.5, 2.7, 2.9, 5.3, 5.4_
  - _Boundary: rules/common.md_
- [x] 1.2 (P) 段階ごとの観点を作る
  - requirements・design・tasks の観点を、それぞれ requirements.md の 2.3〜2.6 の項目数に合わせて書く
  - 申告の対象を段階ごとに書き分ける(受入基準 2.8)
  - design の観点に、チェックリストの実測の根拠を見る項目を含める(受入基準 2.6)
  - 完了の観測条件: `rules/requirements.md` `rules/design.md` `rules/tasks.md` が存在し、要件2.3〜2.6 の全項目が現れる
  - _Requirements: 2.1, 2.3, 2.4, 2.5, 2.6, 2.8_
  - _Boundary: rules/requirements.md, rules/design.md, rules/tasks.md_
  - _Depends: 1.1_
- [x] 1.3 (P) レビュー役の定義を作る
  - モデルを `claude-fable-5-1` で固定する(受入基準 1.2)
  - spec 本文と response への書き込みを禁じ、書けるのは指定された review ファイルだけにする(受入基準 5.2)
  - 実行してよい Bash を `gh issue view` だけに限る
  - 材料を自分で読む手順を書く(受入基準 2.10)
  - 最終応答の構造化ブロックの形式を定める
  - 却下された指摘を、却下の理由が事実として誤っている場合を除き再提出しない規則を書く(受入基準 4.7)
  - 完了の観測条件: `.claude/agents/spec-reviewer.md` が存在し、上記6点をすべて含む
  - _Requirements: 1.2, 2.2, 2.10, 4.7, 5.2_
  - _Boundary: .claude/agents/spec-reviewer.md_
  - _Depends: 1.1_

- [x] 2. レビューの手順を spec-review スキルにする
  - サイクル番号の決め方、レビュー役の起動、構造化ブロックの読み取り、処置の記録、往復の判定、差し戻しの手順を書く
  - 起動時にモデルを指定しないことを明記する(起動時の指定が定義ファイルより優先されるため)
  - 渡すものを「直前1往復分の記録」と「そのサイクルの却下一覧(全往復分)」に定める(受入基準 4.6)
  - 高と中だけを直し、低は記録に残す手順を書く(受入基準 3.3、3.4)
  - 最終往復の後は本文を直さない規則を書く(受入基準 4.4)
  - 差し戻しの報告に、何回目かと2回目以降の選択肢を含める(受入基準 6.3、6.4)
  - 完了の観測条件: `.claude/skills/spec-review/SKILL.md` が存在し、Step 1〜7 と制約を含む
  - _Requirements: 1.1, 3.3, 3.4, 3.5, 4.1, 4.3, 4.4, 4.5, 4.6, 5.1, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_
  - _Boundary: .claude/skills/spec-review/SKILL.md_
  - _Depends: 1.1, 1.2, 1.3_

- [x] 3. レビューの実施を機械強制する
- [x] 3.1 走査の共通ライブラリを作る
  - 対象の判定(`phase: initialized` の除外、`generated` が true、人の承認の判定)を実装する(受入基準 7.7、7.8)
  - ブロックの7条件を実装する(受入基準 7.5)
  - 出力形式を `<feature>|<stage>|<理由>|<未解決件数>` に定める
  - 完了の観測条件: 本物のリポジトリで関数を実行し、人の承認が無い段階だけが出力されること
  - 実施結果(2026-09-26): 既存5spec(全段階が人の承認済み)に対して出力0件。本 spec の未承認段階だけが出力された
  - _Requirements: 7.5, 7.7, 7.8_
  - _Boundary: .claude/hooks/spec-review-scan.sh_
  - _Depends: 2_
- [x] 3.2 (P) 証跡を記録するフックを作る
  - 構造化ブロックを読み、値を検証してから証跡を書く(受入基準 7.1、7.2)
  - モデルを確認できる経路では指定モデル以外を書かない(受入基準 7.3)
  - `SubagentStop` と `PostToolUse(SubagentHandback)` の両経路に対応する
  - review ファイルのハッシュを証跡に含める
  - 完了の観測条件: スクリプトに模擬のJSONを直接流し、不正な値(パスに `..`、未知の段階、ブロック無し)で証跡を書かず、正常な値で書くこと。登録後の発火の確認はタスク5で行う
  - 実施結果(2026-09-26): 不正な3種で証跡を書かず、正常な値で書いた。`SubagentStop` と `PostToolUse(SubagentHandback)` の両経路で書けた。モデル名を `claude-opus-5` に差し替えた記録では書かなかった
  - _Requirements: 7.1, 7.2, 7.3, 7.4_
  - _Boundary: .claude/hooks/record-spec-review.sh_
  - _Depends: 3.1_
- [x] 3.3 (P) 停止をブロックするフックを作る
  - 走査ライブラリの結果でブロックする(受入基準 1.3、7.5)
  - `prompt_id` をキーに回数を保存し、2回まで止めて3回目は通す(受入基準 7.6)
  - 完了の観測条件: スクリプトを直接実行し、止まるべき状態で終了コード2、通るべき状態で0を返すこと。登録後の発火の確認はタスク5で行う
  - 実施結果(2026-09-26): レビュー未実施・完了の印なし・対応の記録なし・処置漏れ・reviewの改変・本文が新しい、の各状態で終了コード2。収束済みで0。同じ入力で2回止めて3回目に0、入力が変われば1回目から止めた
  - _Requirements: 1.3, 7.5, 7.6_
  - _Boundary: .claude/hooks/check-spec-review-before-stop.sh_
  - _Depends: 3.1_
- [x] 3.4 (P) 未解決とレビュー未完了を知らせるフックを作る
  - 承認にあたる入力の時点で一覧を出す(受入基準 7.9)
  - 出力は素のテキストとし、件数と識別子の要約にとどめる
  - 完了の観測条件: スクリプトを直接実行し、対象がある状態で一覧が標準出力に出ること。登録後の発火の確認はタスク5で行う
  - 実施結果(2026-09-26): 対象がある状態で一覧が出力された
  - _Requirements: 7.9_
  - _Boundary: .claude/hooks/notify-spec-review.sh_
  - _Depends: 3.1_
- [x] 3.5 フックを settings.json に登録する
  - `UserPromptExpansion` / `UserPromptSubmit` / `SubagentStop` / `PostToolUse` / `Stop` の5か所に登録する
  - `.claude/settings.json` は書き込みが禁止されているため、**所有者が手で追記する**。実装セッションは内容とコマンドを提示する
  - 完了の観測条件: `settings.json` に5か所の登録が入り、JSONとして読めること。発火の確認はタスク5で行う
  - _Requirements: 1.1, 1.3, 7.9_
  - _Boundary: .claude/settings.json_
  - _Depends: 3.2, 3.3, 3.4_

- [x] 4. 規約と文書を更新する
- [x] 4.1 CLAUDE.md を更新する
  - 生成直後のレビューの実行、レビュー完了まで承認を求めないこと(受入基準 1.1、1.5)
  - 次の段階へ進む前に未解決を提示して了承を得ること(受入基準 7.9)
  - 承認済みの段階を再生成または修正する前に承認を取り消すこと(受入基準 6.7)
  - `/kiro-validate-design` を使わないこと、`/kiro-validate-gap` が事前調査であること(受入基準 8.2、8.3)
  - 完了の観測条件: CLAUDE.md の spec 駆動開発の節に上記がすべて現れる
  - _Requirements: 1.1, 1.4, 1.5, 6.7, 7.9, 8.2, 8.3_
  - _Boundary: CLAUDE.md_
  - _Depends: 2_
- [x] 4.2 (P) README を更新する
  - 仕様づくりの表に、各段階で別のAIがレビューすることを書く
  - カスタムスキルの表に `/spec-review` を足す
  - 完了の観測条件: README の該当2表に記載がある
  - _Requirements: 1.1_
  - _Boundary: README.md_
  - _Depends: 2_

- [x] 5. 実機で確認する
- [x] 5.1 フックの動作を確認する
  - design.md の Testing Strategy の項目1〜8 を実施し、結果を記録する(項目の実施と記録の所有はこのタスクにある)
  - 捨て spec(`.kiro/specs/zz-hook-probe/`)を作り、確認後に削除してコミットに含めない
  - 完了の観測条件: 項目8 を除く7項目が期待どおりで、捨て spec がリポジトリに残っていない
  - 実施結果(2026-09-26): 項目1〜7 を確認済み(結果はタスク3.1〜3.4 に記載)。項目8 は `UserPromptSubmit` 経由の発火をこのセッションの実際のやり取りで確認した。`UserPromptExpansion` の発火は未確認で、design の Compliance に明記してある。捨て spec(`zz-hook-probe`)は削除済み
  - _Requirements: 1.3, 7.1, 7.2, 7.3, 7.5, 7.6, 7.7, 7.8_
  - _Depends: 3.5_
- [x] 5.2 スキルとレビュー役の動作を確認する
  - design.md の Testing Strategy の項目9〜12 を実施する
  - 実際の spec(この spec 自身)で、requirements と design のレビューを回す
  - 記録が実装コードのレビューの判定基準に混入しないことを確かめる(`codex-review.yml` の連結は `cat "$spec_path"/*.md` で再帰しないため、`reviews/` 配下は対象外。受入基準 5.5)
  - 完了の観測条件: レビューが走り、記録が残り、修正後に再レビューが要求され、3往復で未解決が記録され、新しいサイクルで往復が数え直される
  - _Requirements: 1.1, 1.2, 4.1, 4.2, 4.3, 4.4, 4.5, 5.1, 5.2, 5.3, 5.4, 5.5_
  - _Depends: 5.1_

- [x] 6. 環境への依存を外す
- [x] 6.1 OS を固定した記述を直す
  - `CLAUDE.md` の Git規約、フック6本の前提コメント、design.md の依存の記述を、POSIXシェルと perl を前提とする書き方に改める
  - ハッシュの取得を `sha256sum` → `shasum -a 256` → `cksum` の順にする(記録側と照合側で同じ順)
  - 完了の観測条件: リポジトリに「Git for Windows が必須」の記述が残っておらず、2つのフックのハッシュ取得の順が一致している
  - 根拠: design.md の Boundary Commitments「This Spec Owns」に、既存フック4本と CLAUDE.md の Git規約を同じ前提へ揃えることを明記している
  - _Requirements: 8.5, 8.6_
  - _Boundary: CLAUDE.md, .claude/hooks/*.sh_
  - _Depends: 5.2_
- [x] 6.2 既存フックの更新時刻の取得を両方式に対応させる
  - `check-verify-before-stop.sh` の `stat -c %Y`(GNU)に加え、`stat -f %m`(BSD)を試す
  - 取得した値が数字であることを確かめてから使う(GNU の `-f` は別の意味になり、数字以外を返して成功するため)
  - 根拠: design.md の Boundary Commitments に含まれる。本 spec のレビューで検出した欠陥である
  - `.claude/hooks/` の8本に同種の箇所が他に無いことを全数確認する(実機確認の項目15)
  - 完了の観測条件: この環境で epoch 秒が取れ、GNU 書式を失敗させた場合に数字以外が弾かれる。全数確認で他に該当が無い
  - _Requirements: 8.6, 8.7_
  - _Boundary: .claude/hooks/check-verify-before-stop.sh_
  - _Depends: 6.1_

- [ ] 7. PR を仕上げてマージする
  - PR 本文に `Spec: .kiro/specs/spec-review` を記載する(200行を超えるため spec の裏付けが要る)
  - `.claude/settings.json` の変更と、既存フック4本および `CLAUDE.md` の Git規約の変更(要件8.5〜8.7。所有者が手で置いた分を含む)を PR 本文で説明する
  - 完了の観測条件: size-check と escape-hatch が緑になり、所有者の Approve の後にマージされる
  - _Requirements: 8.1_
  - _Depends: 6.2_

## 意図的に対象外とした受入基準

- **8.4(PR段階のレビューは spec 自体の不備を審査しない現状を維持する)**: 現状維持が結論であり、変更する成果物が無い。`codex-review.yml` のプロンプトは spec.md の文面の不備を指摘することを既に禁じており、本 spec ではこれに手を入れない

