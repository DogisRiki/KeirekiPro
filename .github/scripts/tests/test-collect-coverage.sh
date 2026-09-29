#!/usr/bin/env bash
# =====================================================================
# collect-coverage.sh の自動テスト(mutation-report CI の自己テストから実行)
#
# gh を PATH の先頭の偽物に置き換え、次を確かめる。
#   - 成果物の選び方(main 以外・期限切れを除き、ページ送りの2ページ目まで
#     見て、最新の main の成果物を選ぶ)
#   - coverage-summary.json と JaCoCo の XML からの値の計算(小数第1位。
#     JaCoCo はレポート全体の counter、つまり末尾の counter を使う)
#   - 基準値の読み取り(今のリポジトリの vite.config.ts と quality.gradle が
#     読めること、今の書き方のまま値を変えたときに値が追えること、
#     読めないときの「読み取れず」)
#   - 2種類の「取得できず」(90日以内に main の成果物が無い、成果物に
#     カバレッジのファイルが無い。後者では古い成果物を探さない)
#   - 実行の日付・コミット(7文字)・実行へのリンク、表に入れる値の検査
#   - 終了コード(取得できずでも 0、引数・環境変数の不足と書けない出力先は 2)
#   - 良し悪しを判定しないこと
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
#
# 置き場所:
#   スクリプトはこのテストの1つ上のディレクトリから探す。今のリポジトリの
#   ファイル(基準値の設定)は、環境変数 REPO_ROOT があればそこから、
#   無ければこのテストの3つ上のディレクトリから読む。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/collect-coverage.sh"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
REAL_VITE="${REPO_ROOT}/frontend/vite.config.ts"
REAL_GRADLE="${REPO_ROOT}/backend/gradle/quality.gradle"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

if [ ! -f "$SCRIPT" ]; then
    echo "FAIL: ${SCRIPT} がありません"
    exit 1
fi
for f in "$REAL_VITE" "$REAL_GRADLE"; do
    if [ ! -f "$f" ]; then
        echo "FAIL: ${f} がありません(REPO_ROOT を確かめる)"
        exit 1
    fi
done

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1"
    FAILED=1
}

# 使い方: check_eq <期待> <実際> <説明>
check_eq() {
    if [ "$1" = "$2" ]; then
        pass "$3"
    else
        fail "$3"
        echo "     期待: $1"
        echo "     実際: $2"
    fi
}

# 使い方: check_rc <期待する戻り値> <実際の戻り値> <説明>
check_rc() {
    if [ "$1" -eq "$2" ]; then
        pass "$3"
    else
        fail "$3 (期待 $1 / 実際 $2)"
    fi
}

# 使い方: check_has <探す文字列> <対象の文字列> <説明>
check_has() {
    if printf '%s' "$2" | grep -qF -- "$1"; then
        pass "$3"
    else
        fail "$3"
        echo "     含むはず: $1"
        echo "     実際: $2"
    fi
}

# 使い方: check_not_has <探す文字列> <対象の文字列> <説明>
check_not_has() {
    if printf '%s' "$2" | grep -qF -- "$1"; then
        fail "$3"
        echo "     含まないはず: $1"
    else
        pass "$3"
    fi
}

# 使い方: row <出力> <種別>
# 表の中の種別の行を取り出す(例: "| lines | 95.6% | 80% |")
row() {
    printf '%s\n' "$1" | grep -E "^\| $2 \|" | head -n 1
}

# ---------------------------------------------------------------------
# 偽物の gh
#   gh api [--paginate] repos/<repo>/actions/artifacts?name=<name>&per_page=100
#     $FAKE/api/<name>/page1.json を出す。--paginate があれば page2.json も続けて出す
#     (gh の --paginate と同じく、ページの JSON を続けて出す)。
#     $FAKE/api-fail があれば失敗する
#   gh run download <run_id> ... -n <name> -D <dir>
#     $FAKE/runs/<run_id>/<name>/ の中身を <dir> に写す。無ければ失敗する
#   呼び出しは $FAKE/calls.log に1行ずつ残す
# ---------------------------------------------------------------------
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"${FAKE}/calls.log"
if [ "$1" = api ]; then
    shift
    paginate=0
    url=""
    for a in "$@"; do
        case "$a" in
            --paginate) paginate=1 ;;
            -*) ;;
            *) url="$a" ;;
        esac
    done
    [ -e "${FAKE}/api-fail" ] && { echo "HTTP 500" >&2; exit 1; }
    name=$(printf '%s' "$url" | sed -n 's/.*[?&]name=\([^&]*\).*/\1/p')
    dir="${FAKE}/api/${name}"
    if [ ! -f "${dir}/page1.json" ]; then
        echo '{"total_count":0,"artifacts":[]}'
        exit 0
    fi
    cat "${dir}/page1.json"
    if [ "$paginate" = 1 ] && [ -f "${dir}/page2.json" ]; then
        cat "${dir}/page2.json"
    fi
    exit 0
fi
if [ "$1" = run ] && [ "$2" = download ]; then
    run_id="$3"
    shift 3
    name=""
    dest="."
    while [ $# -gt 0 ]; do
        case "$1" in
            -n) name="$2"; shift 2 ;;
            -D) dest="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    src="${FAKE}/runs/${run_id}/${name}"
    [ -d "$src" ] || { echo "no artifact" >&2; exit 1; }
    mkdir -p "$dest"
    cp -R "${src}/." "$dest/"
    exit 0
fi
echo "unexpected gh call: $*" >&2
exit 1
EOF
chmod +x "$WORK/bin/gh"

# 使い方: artifact_json <run_id> <created_at> <head_branch> <expired> <head_sha>
artifact_json() {
    printf '{"id":%s0,"name":"x","expired":%s,"created_at":"%s","workflow_run":{"id":%s,"head_branch":"%s","head_sha":"%s"}}' \
        "$1" "$4" "$2" "$1" "$3" "$5"
}

# 使い方: page <artifact_json>...
page() {
    local IFS=,
    printf '{"total_count":99,"artifacts":[%s]}\n' "$*"
}

# 使い方: summary_json <statements> <branches> <functions> <lines>(pct の値。JSON の値として書く)
summary_json() {
    printf '{"total": {"lines":{"total":10,"covered":9,"skipped":0,"pct":%s},"statements":{"total":10,"covered":9,"skipped":0,"pct":%s},"functions":{"total":10,"covered":9,"skipped":0,"pct":%s},"branches":{"total":10,"covered":9,"skipped":0,"pct":%s},"branchesTrue":{"total":0,"covered":0,"skipped":0,"pct":100}}\n,"/home/node/app/src/a.tsx": {"lines":{"total":1,"covered":0,"skipped":0,"pct":0},"statements":{"total":1,"covered":0,"skipped":0,"pct":0},"functions":{"total":1,"covered":0,"skipped":0,"pct":0},"branches":{"total":1,"covered":0,"skipped":0,"pct":0}}\n}\n' \
        "$4" "$1" "$3" "$2"
}

# JaCoCo の XML(実物と同じく1行)。パッケージの counter の後に、
# レポート全体の counter(引数の値)を置く。パッケージの counter は
# レポート全体とは違う値にし、末尾の counter を使っていることを確かめる
# 使い方: jacoco_xml <INSTRUCTION missed> <covered> <BRANCH missed> <covered> <LINE missed> <covered>
jacoco_xml() {
    printf '%s' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><!DOCTYPE report PUBLIC "-//JACOCO//DTD Report 1.1//EN" "report.dtd"><report name="keireki-pro"><sessioninfo id="x" start="1" dump="2"/><package name="com/example/a"><class name="com/example/a/A" sourcefilename="A.java"><method name="f" desc="()V" line="3"><counter type="INSTRUCTION" missed="1" covered="1"/><counter type="LINE" missed="1" covered="1"/></method><counter type="INSTRUCTION" missed="1" covered="1"/><counter type="BRANCH" missed="1" covered="1"/><counter type="LINE" missed="1" covered="1"/></class><sourcefile name="A.java"><line nr="3" mi="0" ci="3" mb="0" cb="0"/><counter type="INSTRUCTION" missed="1" covered="1"/><counter type="BRANCH" missed="1" covered="1"/><counter type="LINE" missed="1" covered="1"/></sourcefile><counter type="INSTRUCTION" missed="1" covered="1"/><counter type="BRANCH" missed="1" covered="1"/><counter type="LINE" missed="1" covered="1"/><counter type="COMPLEXITY" missed="1" covered="1"/><counter type="METHOD" missed="1" covered="1"/><counter type="CLASS" missed="0" covered="1"/></package>'
    [ -n "$1" ] && printf '<counter type="INSTRUCTION" missed="%s" covered="%s"/>' "$1" "$2"
    [ -n "$3" ] && printf '<counter type="BRANCH" missed="%s" covered="%s"/>' "$3" "$4"
    [ -n "$5" ] && printf '<counter type="LINE" missed="%s" covered="%s"/>' "$5" "$6"
    printf '%s' '<counter type="COMPLEXITY" missed="400" covered="1137"/><counter type="METHOD" missed="38" covered="752"/><counter type="CLASS" missed="4" covered="234"/></report>'
}

# 使い方: put_frontend <run_id> <summary の内容>(空なら成果物にファイルを置かない)
put_frontend() {
    local d="${FAKE}/runs/$1/frontend-test-results"
    mkdir -p "$d/test-results"
    echo '<testsuites/>' >"$d/test-results/junit.xml"
    if [ -n "$2" ]; then
        mkdir -p "$d/coverage"
        printf '%s' "$2" >"$d/coverage/coverage-summary.json"
    fi
}

# 使い方: put_backend <run_id> <XML の内容>(空なら成果物にファイルを置かない)
put_backend() {
    local d="${FAKE}/runs/$1/backend-check-results"
    mkdir -p "$d/test-results/test"
    echo '<testsuite/>' >"$d/test-results/test/TEST-x.xml"
    if [ -n "$2" ]; then
        mkdir -p "$d/reports/jacoco/test"
        printf '%s' "$2" >"$d/reports/jacoco/test/jacocoTestReport.xml"
    fi
}

# 使い方: new_case <名前>。FAKE と基準値のリポジトリ(今のファイルの写し)を用意する
new_case() {
    FAKE="$WORK/$1"
    mkdir -p "$FAKE/api" "$FAKE/runs" "$FAKE/root/frontend" "$FAKE/root/backend/gradle"
    : >"$FAKE/calls.log"
    cp "$REAL_VITE" "$FAKE/root/frontend/vite.config.ts"
    cp "$REAL_GRADLE" "$FAKE/root/backend/gradle/quality.gradle"
    export FAKE
}

# 使い方: run_script [出力ファイル]。OUT と RC を設定する
run_script() {
    local out="${1:-$FAKE/out.md}"
    PATH="$WORK/bin:$PATH" GH_TOKEN=dummy GITHUB_REPOSITORY=o/r \
        GITHUB_SERVER_URL=https://github.example \
        COVERAGE_REPO_ROOT="$FAKE/root" \
        bash "$SCRIPT" "$out" >"$FAKE/stdout.log" 2>"$FAKE/stderr.log"
    RC=$?
    OUT=""
    [ -f "$out" ] && OUT=$(cat "$out")
}

SHA_A=aaaaaaa111111111111111111111111111111111
SHA_B=bbbbbbb222222222222222222222222222222222
SHA_C=ccccccc333333333333333333333333333333333
SHA_D=ddddddd444444444444444444444444444444444
SHA_E=eeeeeee555555555555555555555555555555555

# =====================================================================
echo "== 成果物の選び方と値の計算 =="
new_case select
mkdir -p "$FAKE/api/frontend-test-results" "$FAKE/api/backend-check-results"
# frontend: 1ページ目に main の古いもの・main 以外の新しいもの・期限切れの main、
# 2ページ目に最新の main(これを選ぶ)
page "$(artifact_json 101 2026-09-01T00:00:00Z main false "$SHA_A")" \
    "$(artifact_json 102 2026-09-25T00:00:00Z feat/x false "$SHA_B")" \
    "$(artifact_json 103 2026-09-27T00:00:00Z main true "$SHA_C")" \
    >"$FAKE/api/frontend-test-results/page1.json"
page "$(artifact_json 104 2026-09-20T05:06:07Z main false "$SHA_D")" \
    >"$FAKE/api/frontend-test-results/page2.json"
put_frontend 101 "$(summary_json 1 1 1 1)"
put_frontend 102 "$(summary_json 2 2 2 2)"
put_frontend 103 "$(summary_json 3 3 3 3)"
put_frontend 104 "$(summary_json 94.41 81.7 95.2 95.56)"
# backend: main の成果物が1つ
page "$(artifact_json 201 2026-09-21T00:00:00Z main false "$SHA_E")" \
    >"$FAKE/api/backend-check-results/page1.json"
put_backend 201 "$(jacoco_xml 904 19038 381 1078 242 4478)"
run_script
check_rc 0 "$RC" "値を読めたら終了コード 0"
check_has "--paginate" "$(grep 'api' "$FAKE/calls.log" | head -n 1)" "成果物の一覧をページ送りで取る"
check_has "actions/artifacts?name=frontend-test-results&per_page=100" "$(cat "$FAKE/calls.log")" "frontend の成果物を名前で探す"
check_has "actions/artifacts?name=backend-check-results&per_page=100" "$(cat "$FAKE/calls.log")" "backend の成果物を名前で探す"
check_has "run download 104" "$(cat "$FAKE/calls.log")" "2ページ目にある最新の main の成果物を取る"
check_not_has "run download 101" "$(cat "$FAKE/calls.log")" "古い main の成果物は取らない"
check_not_has "run download 102" "$(cat "$FAKE/calls.log")" "main 以外の成果物は取らない"
check_not_has "run download 103" "$(cat "$FAKE/calls.log")" "期限切れの成果物は取らない"
check_has "-n frontend-test-results" "$(grep 'run download 104' "$FAKE/calls.log")" "成果物の名前を指定して取る"
check_has "-R o/r" "$(grep 'run download 104' "$FAKE/calls.log")" "リポジトリを指定して取る"
check_eq "| statements | 94.4% |" "$(row "$OUT" statements | cut -d'|' -f1-3)|" "statements を小数第1位で出す"
check_eq "| branches | 81.7% |" "$(row "$OUT" branches | cut -d'|' -f1-3)|" "branches を出す"
check_eq "| functions | 95.2% |" "$(row "$OUT" functions | cut -d'|' -f1-3)|" "functions を出す"
check_eq "| lines | 95.6% |" "$(row "$OUT" lines | cut -d'|' -f1-3)|" "lines を小数第1位に丸める"
# INSTRUCTION 19038/19942=95.46…、BRANCH 1078/1459=73.88…、LINE 4478/4720=94.87…
check_eq "| INSTRUCTION | 95.5% |" "$(row "$OUT" INSTRUCTION | cut -d'|' -f1-3)|" "INSTRUCTION をレポート全体の counter から計算する"
check_eq "| BRANCH | 73.9% |" "$(row "$OUT" BRANCH | cut -d'|' -f1-3)|" "BRANCH をレポート全体の counter から計算する"
check_eq "| LINE | 94.9% |" "$(row "$OUT" LINE | cut -d'|' -f1-3)|" "LINE をレポート全体の counter から計算する"
check_has "2026-09-20" "$OUT" "frontend の実行の日付を添える"
check_has "\`ddddddd\`" "$OUT" "frontend のコミットを7文字で添える"
check_not_has "ddddddd4" "$OUT" "コミットは7文字に切る"
check_has "https://github.example/o/r/actions/runs/104" "$OUT" "frontend の実行へのリンクを添える"
check_has "2026-09-21" "$OUT" "backend の実行の日付を添える"
check_has "\`eeeeeee\`" "$OUT" "backend のコミットを添える"
check_has "https://github.example/o/r/actions/runs/201" "$OUT" "backend の実行へのリンクを添える"
check_not_has "取得できず" "$OUT" "全て読めたときは取得できずが無い"
check_eq "" "$(printf '%s' "$OUT" | head -n 1 | grep -E '^\|')" "1行目を表から始めない"
# 判定をしない(要件3-8)
for w in "未達" "下回" "達成" "OK" "NG" "✅" "❌" "⚠"; do
    check_not_has "$w" "$OUT" "良し悪しの言葉や記号を付けない($w)"
done

# =====================================================================
echo "== 今のリポジトリの基準値の読み取り =="
# 値は変わりうるため、数値として読めること(読み取れずにならないこと)だけを確かめる
for k in statements branches functions lines LINE BRANCH INSTRUCTION; do
    cell=$(row "$OUT" "$k" | cut -d'|' -f4 | sed 's/^ *//; s/ *$//')
    if printf '%s' "$cell" | grep -qE '^[0-9]+(\.[0-9]+)?%$'; then
        pass "今のファイルから $k の基準値を読める($cell)"
    else
        fail "今のファイルから $k の基準値を読める(実際: $cell)"
    fi
done
# 値を追えていることを、今の書き方のまま数値だけを変えた写しで確かめる
new_case thresholds
sed -E -i 's/(statements:[[:space:]]*)[0-9.]+/\111/; s/(branches:[[:space:]]*)[0-9.]+/\122.5/; s/(functions:[[:space:]]*)[0-9.]+/\133/; s/(lines:[[:space:]]*)[0-9.]+/\144/' \
    "$FAKE/root/frontend/vite.config.ts"
sed -E -i 's/(minimum[[:space:]]*=[[:space:]]*)[0-9.]+/\10.555/' "$FAKE/root/backend/gradle/quality.gradle"
run_script
check_rc 0 "$RC" "基準値だけでも終了コード 0"
check_eq "| statements | 取得できず | 11% |" "$(row "$OUT" statements)" "今の書き方の vite.config.ts から statements を読む"
check_eq "| branches | 取得できず | 22.5% |" "$(row "$OUT" branches)" "branches を読む(小数)"
check_eq "| functions | 取得できず | 33% |" "$(row "$OUT" functions)" "functions を読む"
check_eq "| lines | 取得できず | 44% |" "$(row "$OUT" lines)" "lines を読む"
check_eq "| LINE | 取得できず | 55.5% |" "$(row "$OUT" LINE)" "今の書き方の quality.gradle から LINE を読む(割合を%にする)"
check_eq "| BRANCH | 取得できず | 55.5% |" "$(row "$OUT" BRANCH)" "BRANCH を読む"
check_eq "| INSTRUCTION | 取得できず | 55.5% |" "$(row "$OUT" INSTRUCTION)" "INSTRUCTION を読む"

# counter と直後の minimum の対応(並びを今と変えた設定)
new_case gradle_order
cat >"$FAKE/root/backend/gradle/quality.gradle" <<'EOF'
jacocoTestCoverageVerification {
    violationRules {
        rule {
            limit {
                counter = 'INSTRUCTION'
                value = 'COVEREDRATIO'
                minimum = 0.91
            }
        }
        rule {
            limit {
                counter = 'LINE'
                value = 'COVEREDRATIO'
                minimum = 0.935
            }
        }
        rule {
            limit {
                counter = 'BRANCH'
                value = 'COVEREDRATIO'
                minimum = 0.7
            }
        }
    }
}
EOF
run_script
check_eq "| LINE | 取得できず | 93.5% |" "$(row "$OUT" LINE)" "counter の直後の minimum を LINE の基準値にする"
check_eq "| BRANCH | 取得できず | 70% |" "$(row "$OUT" BRANCH)" "BRANCH の基準値"
check_eq "| INSTRUCTION | 取得できず | 91% |" "$(row "$OUT" INSTRUCTION)" "INSTRUCTION の基準値"

# =====================================================================
echo "== 基準値を読めないとき =="
new_case unreadable
# lines を変数にし、type 宣言の number だけが残る形にする
sed -E -i 's/(lines:[[:space:]]*)[0-9.]+/\1coverageLines/' "$FAKE/root/frontend/vite.config.ts"
# BRANCH の counter の行を消す(直後の minimum を持つ counter が無くなる)
sed -i "/counter = 'BRANCH'/d" "$FAKE/root/backend/gradle/quality.gradle"
run_script
check_rc 0 "$RC" "基準値を読めなくても終了コード 0"
check_eq "| lines | 取得できず | 読み取れず |" "$(row "$OUT" lines)" "lines を読めないと読み取れず"
check_has "| statements | 取得できず | " "$(row "$OUT" statements)" "他の種別の行は続ける"
check_not_has "読み取れず" "$(row "$OUT" statements)" "他の種別は読める"
check_eq "| BRANCH | 取得できず | 読み取れず |" "$(row "$OUT" BRANCH)" "BRANCH を読めないと読み取れず"
check_not_has "読み取れず" "$(row "$OUT" LINE)" "LINE は読める"

new_case nofile
rm "$FAKE/root/frontend/vite.config.ts" "$FAKE/root/backend/gradle/quality.gradle"
run_script
check_rc 0 "$RC" "設定のファイルが無くても終了コード 0"
for k in statements branches functions lines LINE BRANCH INSTRUCTION; do
    check_eq "| $k | 取得できず | 読み取れず |" "$(row "$OUT" "$k")" "ファイルが無いと $k は読み取れず"
done

# =====================================================================
echo "== 90日以内に main の成果物が無いとき =="
new_case none
mkdir -p "$FAKE/api/frontend-test-results" "$FAKE/api/backend-check-results"
# main 以外と期限切れしか無い
page "$(artifact_json 301 2026-09-25T00:00:00Z feat/x false "$SHA_A")" \
    "$(artifact_json 302 2026-06-01T00:00:00Z main true "$SHA_B")" \
    >"$FAKE/api/frontend-test-results/page1.json"
put_frontend 301 "$(summary_json 1 1 1 1)"
put_frontend 302 "$(summary_json 1 1 1 1)"
# backend は一覧が空
run_script
check_rc 0 "$RC" "成果物が無くても終了コード 0"
check_has "frontend: 取得できず(90日以内に main でテストを実行したCIが無い)" "$OUT" "frontend に理由を併記する"
check_has "backend: 取得できず(90日以内に main でテストを実行したCIが無い)" "$OUT" "backend に理由を併記する"
check_not_has "run download" "$(cat "$FAKE/calls.log")" "成果物が無いときは取りに行かない"
check_has "| lines | 取得できず | " "$(row "$OUT" lines)" "値の欄は取得できず"
check_not_has "読み取れず" "$(row "$OUT" lines)" "取得できずでも基準値は並べる"
check_has "| LINE | 取得できず | " "$(row "$OUT" LINE)" "backend の値の欄も取得できず"

# =====================================================================
echo "== 成果物にカバレッジのファイルが無いとき =="
new_case missing
mkdir -p "$FAKE/api/frontend-test-results" "$FAKE/api/backend-check-results"
# 最新の main にはファイルが無い。古い main にはあるが、探さない
page "$(artifact_json 401 2026-09-01T00:00:00Z main false "$SHA_A")" \
    "$(artifact_json 402 2026-09-22T00:00:00Z main false "$SHA_B")" \
    >"$FAKE/api/frontend-test-results/page1.json"
put_frontend 401 "$(summary_json 50 50 50 50)"
put_frontend 402 ""
page "$(artifact_json 501 2026-09-02T00:00:00Z main false "$SHA_C")" \
    "$(artifact_json 502 2026-09-23T00:00:00Z main false "$SHA_D")" \
    >"$FAKE/api/backend-check-results/page1.json"
put_backend 501 "$(jacoco_xml 1 1 1 1 1 1)"
put_backend 502 ""
run_script
check_rc 0 "$RC" "ファイルが無くても終了コード 0"
check_has "frontend: 取得できず(成果物にカバレッジのファイルが無い)" "$OUT" "frontend に理由を併記する"
check_has "backend: 取得できず(成果物にカバレッジのファイルが無い)" "$OUT" "backend に理由を併記する"
check_not_has "run download 401" "$(cat "$FAKE/calls.log")" "frontend の古い成果物を探さない"
check_not_has "run download 501" "$(cat "$FAKE/calls.log")" "backend の古い成果物を探さない"
check_not_has "50.0%" "$OUT" "古い成果物の値を出さない"
check_has "https://github.example/o/r/actions/runs/402" "$OUT" "ファイルが無いときも実行へのリンクを添える"
check_has "\`ddddddd\`" "$OUT" "ファイルが無いときも backend のコミットを添える"

# =====================================================================
echo "== 値の一部を読めないとき =="
new_case partial
mkdir -p "$FAKE/api/frontend-test-results" "$FAKE/api/backend-check-results"
page "$(artifact_json 601 2026-09-20T00:00:00Z main false "$SHA_A")" \
    >"$FAKE/api/frontend-test-results/page1.json"
# pct が数でない種別(0件のときの "Unknown")
put_frontend 601 "$(summary_json 90 '"Unknown"' 90 90)"
page "$(artifact_json 602 2026-09-20T00:00:00Z main false "$SHA_B")" \
    >"$FAKE/api/backend-check-results/page1.json"
# レポート全体の BRANCH が無く、LINE は分母が0
put_backend 602 "$(jacoco_xml 10 90 '' '' 0 0)"
run_script
check_rc 0 "$RC" "一部を読めなくても終了コード 0"
check_has "| branches | 取得できず | " "$(row "$OUT" branches)" "pct が数でない種別は取得できず"
check_has "| statements | 90.0% | " "$(row "$OUT" statements)" "他の種別は出す"
check_has "| BRANCH | 取得できず | " "$(row "$OUT" BRANCH)" "レポート全体の counter が無い種別は取得できず(パッケージの値を使わない)"
check_has "| LINE | 取得できず | " "$(row "$OUT" LINE)" "分母が0の種別は取得できず"
check_has "| INSTRUCTION | 90.0% | " "$(row "$OUT" INSTRUCTION)" "INSTRUCTION は出す"

new_case badjson
mkdir -p "$FAKE/api/frontend-test-results"
page "$(artifact_json 701 2026-09-20T00:00:00Z main false "$SHA_A")" \
    >"$FAKE/api/frontend-test-results/page1.json"
put_frontend 701 "not json"
run_script
check_rc 0 "$RC" "JSON として読めなくても終了コード 0"
check_has "| lines | 取得できず | " "$(row "$OUT" lines)" "JSON として読めないと取得できず"

# =====================================================================
echo "== 一覧・取得の失敗 =="
new_case apifail
: >"$FAKE/api-fail"
run_script
check_rc 0 "$RC" "一覧を取れなくても終了コード 0"
check_has "frontend: 取得できず(成果物の一覧を取得できない)" "$OUT" "一覧の失敗を併記する"
check_has "backend: 取得できず(成果物の一覧を取得できない)" "$OUT" "backend も一覧の失敗を併記する"

new_case dlfail
mkdir -p "$FAKE/api/frontend-test-results"
# 取得先の run が無い(偽物の gh の run download が失敗する)
page "$(artifact_json 801 2026-09-20T00:00:00Z main false "$SHA_A")" \
    >"$FAKE/api/frontend-test-results/page1.json"
run_script
check_rc 0 "$RC" "取得に失敗しても終了コード 0"
check_has "frontend: 取得できず(成果物をダウンロードできない)" "$OUT" "取得の失敗を併記する"
check_has "https://github.example/o/r/actions/runs/801" "$OUT" "取得の失敗でも実行へのリンクを添える"

# =====================================================================
echo "== 表に入れる値の検査 =="
new_case inject
mkdir -p "$FAKE/api/frontend-test-results"
page "$(artifact_json 901 '2026-09-20T00:00:00Z|x' main false 'zz|<b>')" \
    >"$FAKE/api/frontend-test-results/page1.json"
put_frontend 901 "$(summary_json 90 90 90 90)"
run_script
check_rc 0 "$RC" "想定外の値でも終了コード 0"
check_not_has "<b>" "$OUT" "コミットの形でない値を出さない"
check_not_has "|x" "$OUT" "日付の後ろの余計な値を出さない"
check_has "コミット 不明" "$OUT" "コミットの形でない値は不明とする"
# 表の行以外に | が無い(値の中の | で表が崩れない)
check_eq "" "$(printf '%s\n' "$OUT" | grep -F '|' | grep -vE '^\| ' | grep -vE '^\|---')" "表の行の外に | を出さない"

# =====================================================================
echo "== 引数と環境変数、出力先 =="
new_case args
PATH="$WORK/bin:$PATH" GH_TOKEN=dummy GITHUB_REPOSITORY=o/r COVERAGE_REPO_ROOT="$FAKE/root" \
    bash "$SCRIPT" >/dev/null 2>&1
check_rc 2 $? "出力ファイルの引数が無いと終了コード 2"
PATH="$WORK/bin:$PATH" GH_TOKEN=dummy GITHUB_REPOSITORY='' COVERAGE_REPO_ROOT="$FAKE/root" \
    bash "$SCRIPT" "$FAKE/o.md" >/dev/null 2>&1
check_rc 2 $? "GITHUB_REPOSITORY が無いと終了コード 2"
PATH="$WORK/bin:$PATH" GH_TOKEN='' GITHUB_REPOSITORY=o/r COVERAGE_REPO_ROOT="$FAKE/root" \
    bash "$SCRIPT" "$FAKE/o.md" >/dev/null 2>&1
check_rc 2 $? "GH_TOKEN が無いと終了コード 2"
run_script "$FAKE/no-such-dir/out.md"
check_rc 2 "$RC" "出力ファイルに書けないと終了コード 2"

echo
if [ "$FAILED" -ne 0 ]; then
    echo "失敗したテストがあります"
    exit 1
fi
echo "全てのテストが通りました"
