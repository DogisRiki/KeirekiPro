#!/usr/bin/env bash
# =====================================================================
# record-mutation-metrics.sh の自動テスト(mutation-report CI から実行)
#
# gh をスタブし、スコアの計算・測定方式の記録・台帳のIssueの作成と追記・
# 全件の回の差とコメント・失敗時の終了コードを検証する。
#   0 = 追記した(全件の回はコメントも済んだ) / 2 = 台帳に書けなかった
#
# gh のスタブは実APIの形のJSONを返し、--jq の指定は実 jq で評価する。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# 時刻は NOW_EPOCH で固定する。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/record-mutation-metrics.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# 2026-01-10T00:00:00Z
NOW=1768003200
TITLE="メトリクス台帳: mutationスコア"
HEADING="## 記録(測定方式つき)"
NEW_HEADER="| 実行日(UTC) | 測定方式 | backend(PIT) | frontend(Stryker) | 実行 |"

mkdir -p "$WORK/bin"

# --- gh のスタブ ---------------------------------------------------------------
#   api --paginate repos/…/issues?…  → $STUB_ISSUES を返す(STUB_LIST_FAIL で失敗)
#   api repos/…/issues/<N> --jq <式> → $STUB_ISSUE に式を適用する(STUB_GET_FAIL で失敗)
#   api -X POST …/assignees          → 所有者が付いた Issue を返す
#   issue create … --body-file <F>   → F を $WORK/created.md に写し、作ったIssueのURLを出す。
#                                      以後の本文の取得は F の中身を返す(STUB_CREATE_FAIL で失敗)
#   issue edit <N> … --body-file <F> → F を $WORK/edited.md に写し、N を記録する(STUB_EDIT_FAIL で失敗)
#   issue comment <N> … --body-file <F> → F を $WORK/commented.md に写す(STUB_COMMENT_FAIL で失敗)
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
body_file=""
jq_prog=""
prev=""
for a in "$@"; do
    [ "$prev" = "--body-file" ] && body_file="$a"
    [ "$prev" = "--jq" ] && jq_prog="$a"
    prev="$a"
done
case "$1 $2" in
"api --paginate")
    [ -n "${STUB_LIST_FAIL:-}" ] && exit 1
    cat "${STUB_ISSUES:?}"
    ;;
"api -X")
    printf '{"number":7,"assignees":[{"login":"owner"}]}'
    ;;
api\ repos/*)
    [ -n "${STUB_GET_FAIL:-}" ] && exit 1
    jq -r "$jq_prog" "${STUB_ISSUE:?}"
    ;;
"issue create")
    [ -n "${STUB_CREATE_FAIL:-}" ] && exit 1
    cp "$body_file" "${STUB_DIR:?}/created.md"
    jq -n --rawfile b "$body_file" '{number: 100, body: $b}' >"${STUB_ISSUE:?}"
    echo "https://github.com/owner/repo/issues/100"
    ;;
"issue edit")
    [ -n "${STUB_EDIT_FAIL:-}" ] && exit 1
    cp "$body_file" "${STUB_DIR:?}/edited.md"
    echo "$3" >"${STUB_DIR:?}/edited-number"
    ;;
"issue comment")
    [ -n "${STUB_COMMENT_FAIL:-}" ] && exit 1
    cp "$body_file" "${STUB_DIR:?}/commented.md"
    echo "$3" >"${STUB_DIR:?}/commented-number"
    ;;
*)
    echo "stub: unexpected call: $*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$WORK/bin/gh"

# --- 入力の組み立て ---------------------------------------------------------------
# 使い方: pit <KILLED数> <SURVIVED数> <NO_COVERAGE数> <TIMED_OUT数>
pit() {
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<mutations partial="true">'
        local i
        for ((i = 0; i < $1; i++)); do echo "<mutation detected='true' status='KILLED' numberOfTestsRun='1'><sourceFile>A.java</sourceFile></mutation>"; done
        for ((i = 0; i < $2; i++)); do echo "<mutation detected='false' status='SURVIVED' numberOfTestsRun='1'><sourceFile>A.java</sourceFile></mutation>"; done
        for ((i = 0; i < $3; i++)); do echo "<mutation detected='false' status='NO_COVERAGE' numberOfTestsRun='0'><sourceFile>A.java</sourceFile></mutation>"; done
        for ((i = 0; i < $4; i++)); do echo "<mutation detected='true' status='TIMED_OUT' numberOfTestsRun='1'><sourceFile>A.java</sourceFile></mutation>"; done
        echo '</mutations>'
    } >"$WORK/mutations.xml"
}

# 使い方: stryker <status をカンマ区切りで並べたもの>(2ファイルに分けて置く)
stryker() {
    jq -n --arg s "$1" '
        ($s | split(",")) as $all
        | ($all | length) as $n
        | {schemaVersion: "1", thresholds: {high: 80, low: 60},
           files: {
             "src/a.ts": {language: "typescript", source: "",
                          mutants: [$all[0:($n / 2 | floor)][] | {id: "x", mutatorName: "m", location: {}, status: .}]},
             "src/b.ts": {language: "typescript", source: "",
                          mutants: [$all[($n / 2 | floor):][] | {id: "y", mutatorName: "m", location: {}, status: .}]}
           }}' >"$WORK/mutation.json"
}

# 使い方: issues <JSON配列>  /  issue_body <本文>
issues() { printf '%s' "$1" >"$WORK/issues.json"; }
issue_body() { jq -n --arg b "$1" '{number: 7, body: $b}' >"$WORK/issue.json"; }

# 測定方式の列が無かったころの台帳(4列の表だけ)
LEDGER_BODY="説明

| 実行日(UTC) | backend(PIT) | frontend(Stryker) | 実行 |
|---|---|---|---|
| 2026-01-03 | 70.0%(7/10) | 取得できず | [実行](https://github.com/owner/repo/actions/runs/1) |"

# 新しい表を持つ台帳。古い表の行(2025-12-27)は全件の比較に使わない。
# 2026-01-03 は全件、2026-01-08 は差分(値を大きく変えてあり、比較に使うと差が変わる)
LEDGER_WITH_NEW="説明

| 実行日(UTC) | backend(PIT) | frontend(Stryker) | 実行 |
|---|---|---|---|
| 2025-12-27 | 10.0%(1/10) | 10.0%(1/10) | [実行](https://github.com/owner/repo/actions/runs/1) |

${HEADING}

${NEW_HEADER}
|---|---|---|---|---|
| 2026-01-03 | 全件(月初の定期) | 68.0%(68/100) | 82.5%(33/40) | [実行](https://github.com/owner/repo/actions/runs/2) |
| 2026-01-08 | 差分 | 99.0%(99/100) | 99.0%(99/100) | [実行](https://github.com/owner/repo/actions/runs/3) |"

# 新しい表に差分の行しか無い台帳
LEDGER_NEW_INCREMENTAL_ONLY="説明

| 実行日(UTC) | backend(PIT) | frontend(Stryker) | 実行 |
|---|---|---|---|
| 2026-01-03 | 50.0%(5/10) | 50.0%(5/10) | [実行](https://github.com/owner/repo/actions/runs/1) |

${HEADING}

${NEW_HEADER}
|---|---|---|---|---|
| 2026-01-08 | 差分 | 60.0%(6/10) | 60.0%(6/10) | [実行](https://github.com/owner/repo/actions/runs/3) |"

reset() {
    pit 7 2 1 0
    stryker "Killed,Killed,Killed,Survived,Timeout,CompileError,Ignored,RuntimeError"
    issues "[{\"number\": 3, \"title\": \"別のIssue\"}, {\"number\": 7, \"title\": \"${TITLE}\"}]"
    issue_body "$LEDGER_BODY"
    rm -f "$WORK/coverage.md"
    MODE="incremental"
    COVERAGE=""
    unset STUB_LIST_FAIL STUB_GET_FAIL STUB_CREATE_FAIL STUB_EDIT_FAIL STUB_COMMENT_FAIL
}

# 使い方: run [pitのパス] [strykerのパス]
# 測定方式は MODE、カバレッジのファイルは COVERAGE(空なら渡さない)で指定する
run() {
    : >"$WORK/calls.log"
    rm -f "$WORK/created.md" "$WORK/edited.md" "$WORK/edited-number" "$WORK/commented.md" "$WORK/commented-number"
    local -a cov=()
    if [ -n "$COVERAGE" ]; then
        cov=(COVERAGE_FILE="$COVERAGE")
    fi
    env PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_DIR="$WORK" \
        STUB_ISSUES="$WORK/issues.json" STUB_ISSUE="$WORK/issue.json" \
        GITHUB_REPOSITORY="owner/repo" GITHUB_REPOSITORY_OWNER="owner" GITHUB_RUN_ID="99" \
        GH_TOKEN="dummy" NOW_EPOCH="$NOW" MUTATION_MODE="$MODE" "${cov[@]}" \
        bash "$SCRIPT" "${1-$WORK/mutations.xml}" "${2-$WORK/mutation.json}" >"$WORK/out.log" 2>&1
}

check() {
    local want="$1" name="$2" got
    shift 2
    run "$@"
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit $want, got $got)"
        sed 's/^/    | /' "$WORK/out.log"
        FAILED=1
    fi
}

check_file_has() {
    if [ -f "$WORK/$1" ] && grep -qF -- "$2" "$WORK/$1"; then
        echo "PASS: $3"
    else
        echo "FAIL: $3 ($1 に '$2' が無い)"
        FAILED=1
    fi
}

check_file_lacks() {
    if [ -f "$WORK/$1" ] && ! grep -qF -- "$2" "$WORK/$1"; then
        echo "PASS: $3"
    else
        echo "FAIL: $3 ($1 が無いか、'$2' を含む)"
        FAILED=1
    fi
}

check_no_file() {
    if [ ! -e "$WORK/$1" ]; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 ($1 が作られた)"
        FAILED=1
    fi
}

# 使い方: check_count <ファイル> <固定文字列の行> <期待する行数> <説明>
check_count() {
    local got=0
    if [ -f "$WORK/$1" ]; then
        got=$(grep -cxF -- "$2" "$WORK/$1")
    fi
    if [ "$got" -eq "$3" ]; then
        echo "PASS: $4"
    else
        echo "FAIL: $4 ('$2' が $got 行。期待は $3 行)"
        FAILED=1
    fi
}

# 使い方: check_prefix <ファイル> <本文> <説明>
# ファイルの先頭が、本文(末尾に改行1つ)とバイト単位で一致すること
check_prefix() {
    local want="$WORK/prefix-want" n
    printf '%s\n' "$2" >"$want"
    n=$(wc -c <"$want" | tr -d ' ')
    if [ -f "$WORK/$1" ] && head -c "$n" "$WORK/$1" | cmp -s - "$want"; then
        echo "PASS: $3"
    else
        echo "FAIL: $3 ($1 の先頭が元の本文と一致しない)"
        FAILED=1
    fi
}

check_last_line() {
    local got=""
    if [ -f "$WORK/$1" ]; then
        got=$(tail -n 1 "$WORK/$1")
    fi
    if [ "$got" = "$2" ]; then
        echo "PASS: $3"
    else
        echo "FAIL: $3 (最後の行: '$got')"
        FAILED=1
    fi
}

ROW_DATE="| 2026-01-10 | 差分 |"
RUN_LINK="[実行](https://github.com/owner/repo/actions/runs/99)"

echo "--- 既存の台帳への追記 ---"
reset
check 0 "台帳があれば追記して0を返す"
check_file_has edited.md "$ROW_DATE 70.0%(7/10) | 80.0%(4/5) | ${RUN_LINK} |" "両方のスコアと実行へのリンクが1行で追記される"
check_file_has edited.md "| 2026-01-03 | 70.0%(7/10) |" "既存の行を残す"
check_file_has edited-number "7" "タイトルが完全一致するIssueに追記する"
check_no_file created.md "台帳があれば新しく作らない"
if [ "$(grep -c '^| 20' "$WORK/edited.md")" -eq 2 ]; then
    echo "PASS: 追記は1行だけ"
else
    echo "FAIL: 追記は1行だけ"
    FAILED=1
fi

echo "--- 測定方式の記録 ---"
reset
check 0 "新しい見出しが無い本文にも追記して0を返す"
check_prefix edited.md "$LEDGER_BODY" "既存の4列の表はバイト単位で変わらない"
check_count edited.md "$HEADING" 1 "新しい見出しを1つ足す"
check_count edited.md "$NEW_HEADER" 1 "5列の表の頭を1つ足す"
check_count edited.md "|---|---|---|---|---|" 1 "5列の表の区切りを1つ足す"
if [ -f "$WORK/edited.md" ] &&
    [ "$(grep -nxF -- "$HEADING" "$WORK/edited.md" | cut -d: -f1)" -lt "$(grep -nxF -- "$NEW_HEADER" "$WORK/edited.md" | cut -d: -f1)" ] 2>/dev/null; then
    echo "PASS: 見出しの下に表の頭を置く"
else
    echo "FAIL: 見出しの下に表の頭を置く"
    FAILED=1
fi
check_last_line edited.md "| 2026-01-10 | 差分 | 70.0%(7/10) | 80.0%(4/5) | ${RUN_LINK} |" "行は新しい表の末尾に入る"

reset
issue_body "$LEDGER_WITH_NEW"
check 0 "新しい見出しがある本文に追記して0を返す"
check_prefix edited.md "$LEDGER_WITH_NEW" "既存の本文は変わらない"
check_count edited.md "$HEADING" 1 "見出しを重ねて足さない"
check_count edited.md "$NEW_HEADER" 1 "表の頭を重ねて足さない"
check_last_line edited.md "| 2026-01-10 | 差分 | 70.0%(7/10) | 80.0%(4/5) | ${RUN_LINK} |" "新しい表の末尾に1行足す"
if [ "$(grep -c '^| 20' "$WORK/edited.md")" -eq 4 ]; then
    echo "PASS: 新しい表への追記も1行だけ"
else
    echo "FAIL: 新しい表への追記も1行だけ"
    FAILED=1
fi

# 使い方: check_mode <MUTATION_MODE> <測定方式の列の値>
check_mode() {
    reset
    issue_body "$LEDGER_WITH_NEW"
    MODE="$1"
    check 0 "${1} を記録して0を返す"
    check_last_line edited.md "| 2026-01-10 | ${2} | 70.0%(7/10) | 80.0%(4/5) | ${RUN_LINK} |" "${1} は測定方式の列に「${2}」と書く"
}
check_mode full-scheduled "全件(月初の定期)"
check_mode full-manual "全件(手動)"
check_mode full-no-previous "全件(前回の結果なし)"
check_mode incremental "差分"

echo "--- 全件の回の差とコメント ---"
reset
issue_body "$LEDGER_WITH_NEW"
MODE="full-scheduled"
check 0 "全件の回は記録とコメントをして0を返す"
check_file_has commented-number "7" "台帳のIssueにコメントする"
check_file_has commented.md "前回の全件(2026-01-03)" "比較する前回は直前の全件の行(差分の行と古い表の行は使わない)"
check_file_has commented.md "| backend(PIT) | 70.0%(7/10) | 68.0%(68/100) | +2.0ポイント |" "backend の今回・前回・差(符号つき、小数第1位)"
check_file_has commented.md "| frontend(Stryker) | 80.0%(4/5) | 82.5%(33/40) | -2.5ポイント |" "frontend の差は下がれば負の符号(判定はしない)"
check_file_has commented.md "月初の定期実行" "全件になった理由を書く(月初の定期)"
check_file_has commented.md "$RUN_LINK" "実行へのリンクを書く"
if [ -f "$WORK/commented.md" ] && head -n 1 "$WORK/commented.md" | grep -q '^@owner [^|[:space:]]'; then
    echo "PASS: 1行目は所有者へのメンションと説明の文(表から始めない)"
else
    echo "FAIL: 1行目は所有者へのメンションと説明の文(表から始めない)"
    FAILED=1
fi
if grep -q 'assignees' "$WORK/calls.log"; then
    echo "PASS: 所有者を担当者に割り当てる"
else
    echo "FAIL: 所有者を担当者に割り当てる"
    FAILED=1
fi
if [ "$(grep -n 'issue edit' "$WORK/calls.log" | cut -d: -f1)" -lt "$(grep -n 'issue comment' "$WORK/calls.log" | cut -d: -f1)" ] 2>/dev/null; then
    echo "PASS: 台帳への記録の後にコメントする"
else
    echo "FAIL: 台帳への記録の後にコメントする"
    FAILED=1
fi

reset
issue_body "$LEDGER_WITH_NEW"
MODE="full-manual"
check 0 "手動の全件もコメントして0を返す"
check_file_has commented.md "手動の実行で全件" "全件になった理由を書く(手動)"

reset
issue_body "$LEDGER_WITH_NEW"
MODE="full-no-previous"
check 0 "前回の結果なしの全件もコメントして0を返す"
check_file_has commented.md "前回の結果が無かった" "全件になった理由を書く(前回の結果なし)"

reset
issue_body "$LEDGER_WITH_NEW"
MODE="full-scheduled"
pit 68 32 0 0
stryker "Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Killed,Survived,Survived,Survived,Survived,Survived,Survived,Survived"
check 0 "スコアが変わらない全件の回"
check_file_has commented.md "| backend(PIT) | 68.0%(68/100) | 68.0%(68/100) | ±0.0ポイント |" "差が0のときは ±0.0"
check_file_has commented.md "| frontend(Stryker) | 82.5%(33/40) | 82.5%(33/40) | ±0.0ポイント |" "frontend も差が0なら ±0.0"

echo "--- 比較対象なし ---"
reset
MODE="full-scheduled"
check 0 "新しい表が無い台帳の全件の回"
check_file_has commented.md "| backend(PIT) | 70.0%(7/10) | 記録なし | 比較対象なし |" "直前の全件の行が無ければ backend は比較対象なし(古い表の行は使わない)"
check_file_has commented.md "| frontend(Stryker) | 80.0%(4/5) | 記録なし | 比較対象なし |" "直前の全件の行が無ければ frontend は比較対象なし"

reset
issue_body "$LEDGER_NEW_INCREMENTAL_ONLY"
MODE="full-manual"
check 0 "新しい表に差分の行しか無い台帳の全件の回"
check_file_has commented.md "| backend(PIT) | 70.0%(7/10) | 記録なし | 比較対象なし |" "差分の行は比較に使わない"

reset
issue_body "$(printf '%s\n%s' "$LEDGER_WITH_NEW" "| 2026-01-09 | 全件(手動) | 取得できず | 75.0%(3/4) | [実行](https://github.com/owner/repo/actions/runs/4) |")"
MODE="full-scheduled"
check 0 "直前の全件の行の片方が取得できずの全件の回"
check_file_has commented.md "前回の全件(2026-01-09)" "直前の全件の行は最後のもの"
check_file_has commented.md "| backend(PIT) | 70.0%(7/10) | 取得できず | 比較対象なし |" "前回が取得できずの側は比較対象なし"
check_file_has commented.md "| frontend(Stryker) | 80.0%(4/5) | 75.0%(3/4) | +5.0ポイント |" "もう片方は差を出す"

reset
issue_body "$LEDGER_WITH_NEW"
MODE="full-scheduled"
check 0 "今回の片方が取得できずの全件の回" "$WORK/missing.xml" "$WORK/mutation.json"
check_file_has commented.md "| backend(PIT) | 取得できず | 68.0%(68/100) | 比較対象なし |" "今回が取得できずの側は比較対象なし"
check_file_has commented.md "| frontend(Stryker) | 80.0%(4/5) | 82.5%(33/40) | -2.5ポイント |" "もう片方の報告は続ける"

echo "--- カバレッジ ---"
reset
issue_body "$LEDGER_WITH_NEW"
MODE="full-scheduled"
printf '| 種別 | 値 |\n|---|---|\n| frontend lines | 91.2%% |\n' >"$WORK/coverage.md"
COVERAGE="$WORK/coverage.md"
check 0 "カバレッジのファイルを渡した全件の回"
check_file_has commented.md "| frontend lines | 91.2% |" "カバレッジの Markdown をそのままコメントに入れる"
check_file_lacks commented.md "カバレッジ: 取得できず" "カバレッジがあるときは取得できずと書かない"

reset
issue_body "$LEDGER_WITH_NEW"
MODE="full-scheduled"
check 0 "カバレッジのファイルを渡さない全件の回"
check_file_has commented.md "カバレッジ: 取得できず" "COVERAGE_FILE が無ければ取得できず"

reset
issue_body "$LEDGER_WITH_NEW"
MODE="full-scheduled"
COVERAGE="$WORK/missing-coverage.md"
check 0 "カバレッジのファイルが存在しない全件の回"
check_file_has commented.md "カバレッジ: 取得できず" "ファイルが無ければ取得できず"

reset
issue_body "$LEDGER_WITH_NEW"
MODE="full-scheduled"
printf '\n  \n' >"$WORK/coverage.md"
COVERAGE="$WORK/coverage.md"
check 0 "カバレッジのファイルが空の全件の回"
check_file_has commented.md "カバレッジ: 取得できず" "空のファイルは取得できず"

echo "--- 差分の回 ---"
reset
issue_body "$LEDGER_WITH_NEW"
MODE="incremental"
printf 'カバレッジ\n' >"$WORK/coverage.md"
COVERAGE="$WORK/coverage.md"
check 0 "差分の回は記録だけして0を返す"
check_no_file commented.md "差分の回はコメントしない"
if grep -q 'issue comment\|assignees' "$WORK/calls.log"; then
    echo "FAIL: 差分の回はコメントも担当者の割り当ても呼ばない"
    FAILED=1
else
    echo "PASS: 差分の回はコメントも担当者の割り当ても呼ばない"
fi

echo "--- スコアの計算 ---"
reset
pit 781 145 80 0
check 0 "PITの実測値(2026-09-19)を表示と同じ値で記録する"
check_file_has edited.md "77.6%(781/1006)" "PITのスコアは検出数/生成数"

reset
pit 5 3 1 2
check 0 "TIMED_OUT も検出として数える"
check_file_has edited.md "63.6%(7/11)" "PITの TIMED_OUT を分子に含める"

reset
stryker "Killed,Timeout,Survived,NoCoverage,CompileError,RuntimeError,Ignored,Killed"
check 0 "Stryker は CompileError / RuntimeError / Ignored を分母から除く"
check_file_has edited.md "60.0%(3/5)" "Strykerのスコアは (Killed+Timeout)/(Killed+Timeout+Survived+NoCoverage)"

reset
pit 2 1 0 0
check 0 "小数第1位で四捨五入する"
check_file_has edited.md "66.7%(2/3)" "2/3 は 66.7%"

echo "--- 取得できない側 ---"
reset
check 0 "Strykerのレポートが無くても追記して0を返す" "$WORK/mutations.xml" "$WORK/missing.json"
check_file_has edited.md "$ROW_DATE 70.0%(7/10) | 取得できず |" "無い側は「取得できず」と記録する"

reset
check 0 "PITのレポートが無くても追記して0を返す" "$WORK/missing.xml" "$WORK/mutation.json"
check_file_has edited.md "$ROW_DATE 取得できず | 80.0%(4/5) |" "無い側は「取得できず」と記録する"

reset
check 0 "両方無くても1行記録して0を返す" "$WORK/missing.xml" "$WORK/missing.json"
check_file_has edited.md "$ROW_DATE 取得できず | 取得できず |" "止まったことが台帳に残る"

reset
printf 'not json' >"$WORK/mutation.json"
check 0 "StrykerのJSONを解釈できなければ「取得できず」とする"
check_file_has edited.md "| 取得できず | ${RUN_LINK}" "解釈できない側は「取得できず」"

reset
pit 0 0 0 0
check 0 "PITの変異が0件なら「取得できず」とする(0除算しない)"
check_file_has edited.md "$ROW_DATE 取得できず |" "0件は「取得できず」"

echo "--- 台帳の新規作成 ---"
reset
issues '[{"number": 3, "title": "メトリクス台帳: mutationスコア(旧)"}]'
check 0 "タイトルが完全一致するIssueが無ければ作成して0を返す"
check_count created.md "$HEADING" 1 "新しい台帳は最初から新しい見出しを持つ"
check_count created.md "$NEW_HEADER" 1 "新しい台帳は最初から5列の表の頭を持つ"
check_file_lacks created.md "| 実行日(UTC) | backend(PIT) | frontend(Stryker) | 実行 |" "新しい台帳に4列の表を作らない"
check_file_has edited-number "100" "作成したIssueの番号に追記する"
check_count edited.md "$HEADING" 1 "作成した台帳に見出しを重ねて足さない"
check_last_line edited.md "$ROW_DATE 70.0%(7/10) | 80.0%(4/5) | ${RUN_LINK} |" "最初の行を書く"
if grep -qF -- "--title ${TITLE}" "$WORK/calls.log"; then
    echo "PASS: 固定タイトルで作成する"
else
    echo "FAIL: 固定タイトルで作成する"
    FAILED=1
fi
if grep 'issue create' "$WORK/calls.log" | grep -q -- '--label'; then
    echo "FAIL: mutation の台帳にはラベルを付けない"
    FAILED=1
else
    echo "PASS: mutation の台帳にはラベルを付けない"
fi

reset
issues "[{\"number\": 5, \"title\": \"${TITLE}\", \"pull_request\": {}}]"
check 0 "同じタイトルのPRは台帳として扱わない"
check_file_has created.md "$HEADING" "PRしか無ければ新しく作る"
check_last_line edited.md "$ROW_DATE 70.0%(7/10) | 80.0%(4/5) | ${RUN_LINK} |" "作った台帳に行を書く"

echo "--- 台帳に書けない ---"
reset
export STUB_LIST_FAIL=1
check 2 "Issue一覧を取得できなければ2を返す"
reset
printf 'not json' >"$WORK/issues.json"
check 2 "Issue一覧を解釈できなければ2を返す"
reset
export STUB_GET_FAIL=1
check 2 "台帳の本文を取得できなければ2を返す"
check_no_file edited.md "本文を取得できなければ台帳を書き換えない"
reset
export STUB_EDIT_FAIL=1
check 2 "追記に失敗したら2を返す"
reset
issues '[]'
export STUB_CREATE_FAIL=1
check 2 "作成に失敗したら2を返す"
reset
issue_body "$LEDGER_WITH_NEW"
MODE="full-scheduled"
export STUB_COMMENT_FAIL=1
check 2 "全件の回のコメントに失敗したら2を返す"
check_file_has edited.md "| 2026-01-10 | 全件(月初の定期) |" "コメントに失敗しても記録は残る"
reset
issue_body "$LEDGER_WITH_NEW"
MODE="full-scheduled"
export STUB_EDIT_FAIL=1
check 2 "全件の回で追記に失敗したら2を返す"
check_no_file commented.md "記録できなかった回はコメントしない"

echo "--- 引数と環境変数 ---"
reset
rm -f "$WORK/created.md" "$WORK/edited.md"
: >"$WORK/calls.log"
# 使い方: check_args <説明> <コマンド...>
# gh の呼び出しの記録は消さずに積み重ね、最後にどの場合も呼ばなかったことを確かめる
check_args() {
    local name="$1" got
    shift
    PATH="$WORK/bin:$PATH" STUB_CALLS="$WORK/calls.log" "$@" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq 2 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit 2, got $got)"
        FAILED=1
    fi
}
check_args "引数が足りなければ2を返す" env GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_OWNER=o GITHUB_RUN_ID=1 GH_TOKEN=x MUTATION_MODE=incremental bash "$SCRIPT" "$WORK/mutations.xml"
check_args "GH_TOKEN が無ければ2を返す" env -u GH_TOKEN GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_OWNER=o GITHUB_RUN_ID=1 MUTATION_MODE=incremental bash "$SCRIPT" a b
check_args "GITHUB_RUN_ID が無ければ2を返す" env -u GITHUB_RUN_ID GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_OWNER=o GH_TOKEN=x MUTATION_MODE=incremental bash "$SCRIPT" a b
check_args "GITHUB_REPOSITORY_OWNER が無ければ2を返す" env -u GITHUB_REPOSITORY_OWNER GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 GH_TOKEN=x MUTATION_MODE=incremental bash "$SCRIPT" a b
check_args "MUTATION_MODE が無ければ2を返す" env -u MUTATION_MODE GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_OWNER=o GITHUB_RUN_ID=1 GH_TOKEN=x bash "$SCRIPT" a b
check_args "MUTATION_MODE が4値以外なら2を返す" env GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_OWNER=o GITHUB_RUN_ID=1 GH_TOKEN=x MUTATION_MODE=full bash "$SCRIPT" a b
check_args "MUTATION_MODE の大文字違いも2を返す" env GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_OWNER=o GITHUB_RUN_ID=1 GH_TOKEN=x MUTATION_MODE=Incremental bash "$SCRIPT" a b
check_args "NOW_EPOCH の形が不正なら2を返す" env GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_OWNER=o GITHUB_RUN_ID=1 GH_TOKEN=x MUTATION_MODE=incremental NOW_EPOCH=abc bash "$SCRIPT" a b
if [ -s "$WORK/calls.log" ]; then
    echo "FAIL: 引数・環境変数の不足では gh を呼ばない"
    FAILED=1
else
    echo "PASS: 引数・環境変数の不足では gh を呼ばない"
fi
check_no_file created.md "引数・環境変数の不足では台帳を作らない"
check_no_file edited.md "引数・環境変数の不足では台帳に書かない"

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
