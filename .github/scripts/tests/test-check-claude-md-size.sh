#!/usr/bin/env bash
# =====================================================================
# check-claude-md-size.sh の自動テスト(guardrails CI から実行)
#
# 一時ディレクトリに小さなリポジトリの形を作り、検査を動かして終了コードと
# 出力を検証する。作業フォルダの実物の文書は測らない。
#   0 = 合計が上限以下 / 1 = 合計が上限を超える / 2 = 読めない(判定不能)
#
# 各ケースは「seed → 文書を置く → run → 期待の確かめ」の順に書く。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-claude-md-size.sh"
# 一時領域の確保に失敗したまま進むと rm -rf が意図しない絶対パスを対象にするため、
# ディレクトリが実在することを確認してから trap を設定する
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

REPO="$WORK/repo"
OUT="$WORK/out.txt"
SUMMARY="$WORK/summary.md"
RC=0

seed() {
    rm -rf "$REPO" "$WORK/outside.md"
    mkdir -p "$REPO"
}

# 使い方: put <道> <中身>  リポジトリの形の中に文書を置く(中身は printf の書式)
put() {
    mkdir -p "$(dirname "$REPO/$1")"
    # 中身が「---」で始まる前書きでも書式として読ませるため -- を置く
    # shellcheck disable=SC2059 # 中身に改行の書式を渡すため
    printf -- "$2" >"$REPO/$1"
}

# 使い方: pad <道> <バイトの数>  文書の末尾に x を足し、ちょうどそのバイトの数にする
pad() {
    local f="$REPO/$1" want="$2" have
    mkdir -p "$(dirname "$f")"
    [ -e "$f" ] || : >"$f"
    have=$(($(wc -c <"$f")))
    if [ "$have" -gt "$want" ]; then
        echo "テストの用意の誤り: $1 は既に ${have} バイトある(求めたのは ${want})"
        exit 1
    fi
    head -c "$((want - have))" /dev/zero | tr '\0' 'x' >>"$f"
}

# 使い方: run <上限> [検査の引数...]  リポジトリの形をカレントにして検査を動かす
run() {
    local limit="$1"
    shift
    : >"$SUMMARY"
    (cd "$REPO" && CLAUDE_MD_SIZE_LIMIT="$limit" GITHUB_STEP_SUMMARY="$SUMMARY" bash "$SCRIPT" "$@") >"$OUT" 2>&1
    RC=$?
}

# 使い方: run_no_limit  上限の環境変数を持たないまま検査を動かす
run_no_limit() {
    : >"$SUMMARY"
    (cd "$REPO" && unset CLAUDE_MD_SIZE_LIMIT && GITHUB_STEP_SUMMARY="$SUMMARY" bash "$SCRIPT") >"$OUT" 2>&1
    RC=$?
}

ok() { printf 'ok   %s\n' "$1"; }
ng() {
    printf 'FAIL %s (%s)\n' "$1" "$2"
    sed 's/^/    | /' "$OUT"
    FAILED=1
}

expect_rc() {
    if [ "$RC" = "$1" ]; then ok "$2"; else ng "$2" "期待 exit=$1 / 実際 exit=$RC"; fi
}
# 出力に、この文字列とちょうど同じ行が1つだけある
expect_line() {
    local n
    n=$(grep -cxF -- "$1" "$OUT")
    if [ "$n" = 1 ]; then ok "$2"; else ng "$2" "出力に「$1」の行が1つだけあるはずが ${n} 個"; fi
}
# 出力に、この文字列を含む行がある
expect_text() {
    if grep -qF -- "$1" "$OUT"; then ok "$2"; else ng "$2" "出力に「$1」が無い"; fi
}
# 出力に、この文字列が無い
expect_no_text() {
    if grep -qF -- "$1" "$OUT"; then ng "$2" "出力に「$1」がある"; else ok "$2"; fi
}
# 出力に、::error:: で始まる行がある
expect_error_line() {
    if grep -q '^::error::' "$OUT"; then ok "$1"; else ng "$1" "出力に ::error:: の行が無い"; fi
}
# Summary に、この文字列を含む行がある
expect_summary() {
    if grep -qF -- "$1" "$SUMMARY"; then ok "$2"; else ng "$2" "Summaryに「$1」が無い"; fi
}

# --- 上限との比べ方 -----------------------------------------------------

seed
pad CLAUDE.md 100
pad AGENTS.md 30
run 200
expect_rc 0 "上限以下なら終了コード0"
expect_line "100 CLAUDE.md" "上限以下でも文書ごとの行を出す"
expect_line "合計 130 バイト / 上限 200 バイト" "上限以下なら合計と上限の行を出す"
expect_no_text "::error::" "上限以下なら ::error:: の行を出さない"

run 130
expect_rc 0 "合計が上限ちょうどなら終了コード0"
expect_line "合計 130 バイト / 上限 130 バイト" "上限ちょうどでも合計と上限の行を出す"

run 129
expect_rc 1 "合計が上限を1バイト超えたら終了コード1"
expect_line "100 CLAUDE.md" "上限を超えたら文書の一覧を出す(CLAUDE.md)"
expect_line "30 AGENTS.md" "上限を超えたら文書の一覧を出す(AGENTS.md)"
expect_line "合計 130 バイト / 上限 129 バイト" "上限を超えたら合計と上限の行を出す"
expect_error_line "上限を超えたら ::error:: の行を出す"
expect_text "スキルの本文などに移すか、短くして" "上限を超えたら決まりを移すか短くすることを Claude に言う"
expect_text "CLAUDE_MD_SIZE_LIMIT を上げる変更を、自分の判断で入れないでください" "上限を超えたら上限を自分で上げないことを Claude に言う"
expect_text "理由を添えて所有者に提案してください" "上限を超えたら上げる必要があるときは所有者に提案することを言う"
expect_text "バッククォートで囲んでください" "上限を超えたら @ の語をバッククォートで囲むことを言う"

# --- 測る文書 -----------------------------------------------------------

seed
pad CLAUDE.md 100
pad .claude/CLAUDE.md 110
pad CLAUDE.local.md 120
pad AGENTS.md 130
pad .claude/AGENTS.md 140
pad .claude/rules/general.md 150
put .claude/rules/sub/nested.md '---\ndescription: 全体の決まり\n---\n本文\n'
pad .claude/rules/sub/nested.md 160
put .claude/rules/body-paths.md '# 前書きの無い規則\n\npaths: 本文の中の行は前書きではない\n'
pad .claude/rules/body-paths.md 170
put .claude/rules/scoped.md '---\npaths:\n  - "backend/**"\n---\n本文\n'
pad .claude/rules/scoped.md 1000
put .claude/rules/sub/scoped-inline.md '---\ndescription: 一部の道だけ\npaths: ["frontend/**"]\n---\n'
pad .claude/rules/sub/scoped-inline.md 1000
pad .claude/rules/notes.txt 1000
pad backend/CLAUDE.md 1000
run 100000
expect_rc 0 "どの会話の始めにも読み込まれる文書を集めて測れる"
expect_line "110 .claude/CLAUDE.md" ".claude/CLAUDE.md を合計に入れる"
expect_line "120 CLAUDE.local.md" "CLAUDE.local.md を合計に入れる"
expect_line "130 AGENTS.md" "AGENTS.md を合計に入れる"
expect_line "140 .claude/AGENTS.md" ".claude/AGENTS.md を合計に入れる"
expect_line "150 .claude/rules/general.md" "前書きの無い .claude/rules/ の文書を合計に入れる"
expect_line "160 .claude/rules/sub/nested.md" "paths: の無い前書きを持つ下のフォルダの規則を合計に入れる"
expect_line "170 .claude/rules/body-paths.md" "本文の paths: の行は前書きとみなさず合計に入れる"
expect_no_text "scoped.md" "前書きに paths: のある規則を入れない"
expect_no_text "scoped-inline.md" "前書きに一行の paths: のある規則を入れない"
expect_no_text "notes.txt" ".claude/rules/ の .md でない文書を入れない"
expect_no_text "backend/CLAUDE.md" "backend/CLAUDE.md を入れない"
expect_line "合計 1080 バイト / 上限 100000 バイト" "集めた文書のバイトの数を合計する"

# --- @ の読み込み -------------------------------------------------------

seed
# バッククォートとバックスラッシュをそのまま書くため、引用符付きのヒアドキュメントで置く
cat >"$REPO/CLAUDE.md" <<'EOF'
# 決まり

@docs/a.md と @docs/a.md を読む
`@dependabot recreate` は打たない
``@double.md`` も読み込みではない
`gh x @span-missing.md` は読み込みではない
``a ` @double-span-missing.md`` も読み込みではない
`y`@after-span-missing.md も読み込みではない
メールは user@example.com に送る
@docs/with\ space.md
@chain/l1.md

```
@fenced-missing.md
```

~~~sh
@tilde-fenced-missing.md
~~~
EOF
pad CLAUDE.md 500
put AGENTS.md '@docs/a.md\n'
pad AGENTS.md 50
put docs/a.md '@b.md\n'
pad docs/a.md 60
put docs/b.md '@a.md\n'
pad docs/b.md 70
pad "docs/with space.md" 80
put chain/l1.md '@l2.md\n'
pad chain/l1.md 11
put chain/l2.md '@l3.md\n'
pad chain/l2.md 12
put chain/l3.md '@l4.md\n'
pad chain/l3.md 13
put chain/l4.md '@l5.md\n'
pad chain/l4.md 14
put chain/l5.md '@l6-missing.md\n'
pad chain/l5.md 1500
run 100000
expect_rc 0 "@ の読み込みを辿って測れる"
expect_line "60 docs/a.md" "読み込まれた文書を合計に入れ、2回指されても1回だけ数える"
expect_line "70 docs/b.md" "読み込みを書いた文書のフォルダから道を解き、読み込みの輪で止まる"
expect_line "80 docs/with space.md" "バックスラッシュを置いた空白を道に含める"
expect_line "11 chain/l1.md" "1段目の読み込みを辿る"
expect_line "14 chain/l4.md" "4段目の読み込みを辿る"
expect_no_text "chain/l5.md" "5段目の読み込みは辿らない"
expect_no_text "dependabot" "コードの区切りの中の @ を読み込みにしない"
expect_no_text "double.md" "バッククォート2つの区切りの中の @ を読み込みにしない"
expect_no_text "span-missing" "コードの区切りの中の、空白のあとの @ を読み込みにしない"
expect_no_text "double-span-missing" "バッククォート1つを含むバッククォート2つの区切りの中の @ を読み込みにしない"
expect_no_text "after-span-missing" "コードの区切りのすぐあとの @ を、空白のあととみなさない"
expect_no_text "example.com" "空白のあとでない @ を読み込みにしない"
expect_no_text "fenced-missing" "バッククォートのコードの囲みの中の @ を読み込みにしない"
expect_no_text "tilde-fenced-missing" "~ のコードの囲みの中の @ を読み込みにしない"
expect_line "合計 810 バイト / 上限 100000 バイト" "読み込まれた文書を含めて合計する"

# --- 呼び出し方と Summary ----------------------------------------------

seed
pad CLAUDE.md 100
: >"$SUMMARY"
(cd "$WORK" && CLAUDE_MD_SIZE_LIMIT=200 GITHUB_STEP_SUMMARY="$SUMMARY" bash "$SCRIPT" "$REPO") >"$OUT" 2>&1
RC=$?
expect_rc 0 "引数で渡したフォルダをリポジトリのルートにする"
expect_line "合計 100 バイト / 上限 200 バイト" "引数で渡したルートの文書を測る"
expect_summary "| 100 | \`CLAUDE.md\` |" "GITHUB_STEP_SUMMARY があれば文書ごとの行を表にして書く"
expect_summary "合計 100 バイト / 上限 200 バイト" "GITHUB_STEP_SUMMARY があれば合計と上限を書く"

(cd "$REPO" && unset GITHUB_STEP_SUMMARY && CLAUDE_MD_SIZE_LIMIT=200 bash "$SCRIPT") >"$OUT" 2>&1
RC=$?
expect_rc 0 "GITHUB_STEP_SUMMARY が無くても測れる"
expect_line "合計 100 バイト / 上限 200 バイト" "GITHUB_STEP_SUMMARY が無くても合計と上限の行を出す"

run 99
expect_summary "CLAUDE_MD_SIZE_LIMIT を上げる変更を、自分の判断で入れないでください" "上限を超えたら Summary にも Claude に向けた文を書く"

(cd "$WORK" && CLAUDE_MD_SIZE_LIMIT=200 GITHUB_STEP_SUMMARY="$SUMMARY" bash "$SCRIPT" "$WORK/no-such-dir") >"$OUT" 2>&1
RC=$?
expect_rc 2 "引数のフォルダが無いときは終了コード2"

# --- 上限を読めないとき -------------------------------------------------

seed
pad CLAUDE.md 10
run_no_limit
expect_rc 2 "上限が無いときは終了コード2"
expect_error_line "上限が無いときは ::error:: の行を出す"
expect_text "CLAUDE_MD_SIZE_LIMIT" "上限が無いときは何が読めなかったかを言う"
run ""
expect_rc 2 "上限が空のときは終了コード2"
run 0
expect_rc 2 "上限が0のときは終了コード2"
run abc
expect_rc 2 "上限が数でないときは終了コード2"
expect_error_line "上限が数でないときは ::error:: の行を出す"
run -5
expect_rc 2 "上限が負の数のときは終了コード2"
run 1.5
expect_rc 2 "上限が整数でないときは終了コード2"

# --- 測る文書を読めないとき ---------------------------------------------

seed
pad AGENTS.md 10
run 1000
expect_rc 2 "ルートの CLAUDE.md が無いときは終了コード2"
expect_error_line "ルートの CLAUDE.md が無いときは ::error:: の行を出す"
expect_text "CLAUDE.md" "ルートの CLAUDE.md が無いときは何が読めなかったかを言う"

seed
mkdir -p "$REPO/CLAUDE.md"
run 1000
expect_rc 2 "ルートの CLAUDE.md が読めない(フォルダ)ときは終了コード2"

seed
pad CLAUDE.md 10
mkdir -p "$REPO/CLAUDE.local.md"
run 1000
expect_rc 2 "測る文書が読めないときは終了コード2"
expect_text "CLAUDE.local.md" "測る文書が読めないときはその文書の道を言う"

# --- 読み込みの先を読めないとき -----------------------------------------

seed
put CLAUDE.md '# 決まり\n@nothing.md を読む\n'
run 1000
expect_rc 2 "読み込みの先が無いときは終了コード2"
expect_error_line "読み込みの先が無いときは ::error:: の行を出す"
expect_text "nothing.md" "読み込みの先が無いときは何が無いかを言う"
expect_text "バッククォートで囲んでください" "読み込みの先が無いときは @ の語をバッククォートで囲むよう促す"

seed
put CLAUDE.md '@docs/a.md\n'
put docs/a.md '@gone.md\n'
run 1000
expect_rc 2 "読み込まれた文書の読み込みの先が無いときも終了コード2"
expect_text "gone.md" "読み込まれた文書の無い読み込みの先を言う"

seed
put CLAUDE.md '@docs\n'
mkdir -p "$REPO/docs"
run 1000
expect_rc 2 "読み込みの先がフォルダのときは終了コード2"

seed
put CLAUDE.md '@../outside.md\n'
printf 'outside\n' >"$WORK/outside.md"
run 1000
expect_rc 2 "読み込みの先がリポジトリの外を指すときは終了コード2"
expect_text "リポジトリの外" "リポジトリの外を指すことを言う"

seed
put CLAUDE.md '@docs/../../outside.md\n'
mkdir -p "$REPO/docs"
printf 'outside\n' >"$WORK/outside.md"
run 1000
expect_rc 2 "途中の .. でリポジトリの外を指すときも終了コード2"

seed
put CLAUDE.md '@~/.claude/my-rules.md\n'
run 1000
expect_rc 2 "読み込みの先が ~ の道のときは終了コード2"
expect_text "~" "~ の道で書かれていることを言う"

seed
put CLAUDE.md '@/etc/hosts\n'
run 1000
expect_rc 2 "読み込みの先が絶対の道のときは終了コード2"
expect_text "絶対の道" "絶対の道で書かれていることを言う"

seed
put CLAUDE.md '@C:/rules.md\n'
run 1000
expect_rc 2 "読み込みの先がドライブ文字の絶対の道のときは終了コード2"

if [ "$FAILED" -ne 0 ]; then
    echo "::error::check-claude-md-size.sh のテストが失敗しました。"
    exit 1
fi
echo "全ケース成功。"
