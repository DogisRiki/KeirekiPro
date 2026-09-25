#!/usr/bin/env bash
# =====================================================================
# record-mutation-metrics.sh の自動テスト(mutation-report CI から実行)
#
# gh をスタブし、スコアの計算・台帳のIssueの作成と追記・失敗時の終了コードを検証する。
#   0 = 追記した / 2 = 台帳に書けなかった
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

mkdir -p "$WORK/bin"

# --- gh のスタブ ---------------------------------------------------------------
#   api --paginate repos/…/issues?…  → $STUB_ISSUES を返す(STUB_LIST_FAIL で失敗)
#   api repos/…/issues/<N> --jq <式> → $STUB_ISSUE に式を適用する(STUB_GET_FAIL で失敗)
#   issue create … --body-file <F>   → F を $WORK/created.md に写す(STUB_CREATE_FAIL で失敗)
#   issue edit <N> … --body-file <F> → F を $WORK/edited.md に写し、N を記録する(STUB_EDIT_FAIL で失敗)
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
api\ repos/*)
    [ -n "${STUB_GET_FAIL:-}" ] && exit 1
    jq -r "$jq_prog" "${STUB_ISSUE:?}"
    ;;
"issue create")
    [ -n "${STUB_CREATE_FAIL:-}" ] && exit 1
    cp "$body_file" "${STUB_DIR:?}/created.md"
    ;;
"issue edit")
    [ -n "${STUB_EDIT_FAIL:-}" ] && exit 1
    cp "$body_file" "${STUB_DIR:?}/edited.md"
    echo "$3" >"${STUB_DIR:?}/edited-number"
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

LEDGER_BODY="説明

| 実行日(UTC) | backend(PIT) | frontend(Stryker) | 実行 |
|---|---|---|---|
| 2026-01-03 | 70.0%(7/10) | 取得できず | [実行](https://github.com/owner/repo/actions/runs/1) |"

reset() {
    pit 7 2 1 0
    stryker "Killed,Killed,Killed,Survived,Timeout,CompileError,Ignored,RuntimeError"
    issues "[{\"number\": 3, \"title\": \"別のIssue\"}, {\"number\": 7, \"title\": \"${TITLE}\"}]"
    issue_body "$LEDGER_BODY"
    unset STUB_LIST_FAIL STUB_GET_FAIL STUB_CREATE_FAIL STUB_EDIT_FAIL
}

# 使い方: run [pitのパス] [strykerのパス]
run() {
    : >"$WORK/calls.log"
    rm -f "$WORK/created.md" "$WORK/edited.md" "$WORK/edited-number"
    PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_DIR="$WORK" \
        STUB_ISSUES="$WORK/issues.json" STUB_ISSUE="$WORK/issue.json" \
        GITHUB_REPOSITORY="owner/repo" GITHUB_RUN_ID="99" GH_TOKEN="dummy" NOW_EPOCH="$NOW" \
        bash "$SCRIPT" "${1-$WORK/mutations.xml}" "${2-$WORK/mutation.json}" >/dev/null 2>&1
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

check_no_file() {
    if [ ! -e "$WORK/$1" ]; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 ($1 が作られた)"
        FAILED=1
    fi
}

ROW_DATE="| 2026-01-10 |"
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
check_file_has created.md "| 実行日(UTC) | backend(PIT) | frontend(Stryker) | 実行 |" "表の見出しを作る"
check_file_has created.md "$ROW_DATE 70.0%(7/10) | 80.0%(4/5) |" "最初の行を書く"
check_no_file edited.md "新規作成のときは追記しない"
if grep -qF -- "--title ${TITLE}" "$WORK/calls.log"; then
    echo "PASS: 固定タイトルで作成する"
else
    echo "FAIL: 固定タイトルで作成する"
    FAILED=1
fi

reset
issues "[{\"number\": 5, \"title\": \"${TITLE}\", \"pull_request\": {}}]"
check 0 "同じタイトルのPRは台帳として扱わない"
check_file_has created.md "$ROW_DATE" "PRしか無ければ新しく作る"

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
reset
export STUB_EDIT_FAIL=1
check 2 "追記に失敗したら2を返す"
reset
issues '[]'
export STUB_CREATE_FAIL=1
check 2 "作成に失敗したら2を返す"

echo "--- 引数と環境変数 ---"
reset
# 使い方: check_args <説明> <コマンド...>
check_args() {
    local name="$1" got
    shift
    : >"$WORK/calls.log"
    PATH="$WORK/bin:$PATH" STUB_CALLS="$WORK/calls.log" "$@" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq 2 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit 2, got $got)"
        FAILED=1
    fi
}
check_args "引数が足りなければ2を返す" env GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 GH_TOKEN=x bash "$SCRIPT" "$WORK/mutations.xml"
check_args "GH_TOKEN が無ければ2を返す" env -u GH_TOKEN GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 bash "$SCRIPT" a b
check_args "GITHUB_RUN_ID が無ければ2を返す" env -u GITHUB_RUN_ID GITHUB_REPOSITORY=o/r GH_TOKEN=x bash "$SCRIPT" a b
check_args "NOW_EPOCH の形が不正なら2を返す" env GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 GH_TOKEN=x NOW_EPOCH=abc bash "$SCRIPT" a b
check_no_file created.md "引数・環境変数の不足では台帳を作らない"
check_no_file edited.md "引数・環境変数の不足では台帳に書かない"

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
