#!/usr/bin/env bash
# =====================================================================
# カバレッジの値と基準値の Markdown(mutation-report CI の記録から使う)
#
# main で最後にテストを実行した CI の成果物からカバレッジの値を、ゲート設定の
# ファイルから基準値を読み、並べた Markdown を出力ファイルに書く。
# カバレッジを測り直さない(要件3-4)。値と基準値の良し悪しは判定しない(要件3-8)。
#
# 使い方: collect-coverage.sh <出力ファイル>
#   環境変数 GH_TOKEN GITHUB_REPOSITORY(必須)、GITHUB_SERVER_URL(任意。
#   既定は https://github.com)、COVERAGE_REPO_ROOT(任意。基準値のファイルを
#   読むリポジトリのルート。既定はこのスクリプトの置き場所の2つ上)
#
# 成果物(ci.yaml の upload-artifact が作る):
#   frontend-test-results  coverage/coverage-summary.json の total.<種別>.pct
#   backend-check-results  reports/jacoco/test/jacocoTestReport.xml の末尾の counter
#                          (レポート全体の値)から covered / (missed + covered)
#   成果物の中のパスは、upload-artifact に渡した複数のパスの共通の親からの相対に
#   なる(frontend は frontend/、backend は backend/build/)。
#   gh api --paginate で一覧を全ページ取り、期限切れでなく
#   workflow_run.head_branch が main のものを created_at の新しい順に並べ、
#   先頭の1つだけを使う(mutation-report.yaml の前回の Stryker の結果の探し方と同じ)。
#   その成果物にカバレッジのファイルが無ければ、古い成果物は探さない。
#
# 基準値(ファイルは読むだけで変えない):
#   frontend/vite.config.ts        thresholds の中の statements branches functions lines
#   backend/gradle/quality.gradle  counter = '<種別>' と、その直後の minimum = <割合>
#   読めなければ「読み取れず」。
#
# 出力の形(台帳のコメントに埋め込むため、1行目は表にしない):
#   <1行の説明>
#   (空行)
#   frontend: <実行の日付・コミット・実行の記録>(または 取得できず(理由))
#   (空行)
#   | 種別 | 実測 | 基準値 |
#   ...
#   (空行)
#   backend: ...
#   値を読めない種別は、その行の実測を「取得できず」にする。
#   外部から来た値(日付・コミット・実行の番号)は形を確かめてから入れ、
#   形が違えば「不明」にする。表に入れる値からは `|` と改行を取り除く。
#
# 終了コード:
#   0 = Markdown を書けた(取得できず・読み取れずの欄があっても 0。要件3-6)
#   2 = 引数・環境変数の不足、出力ファイルに書けない
#   1 は使わない(良し悪しを判定しないため。要件3-8)
# =====================================================================
set -uo pipefail

NOT_FOUND="取得できず"
UNREADABLE="読み取れず"
REASON_NO_ARTIFACT="取得できず(90日以内に main でテストを実行したCIが無い)"
REASON_NO_FILE="取得できず(成果物にカバレッジのファイルが無い)"
REASON_LIST_FAILED="取得できず(成果物の一覧を取得できない)"
REASON_DOWNLOAD_FAILED="取得できず(成果物をダウンロードできない)"

FRONTEND_KINDS=(statements branches functions lines)
BACKEND_KINDS=(LINE BRANCH INSTRUCTION)

# 表に入れる値から `|` と改行を取り除く
sanitize() {
    printf '%s' "$1" | tr -d '|\r\n'
}

# 数(整数または小数)なら 0
is_number() {
    printf '%s' "$1" | grep -qE '^[0-9]+(\.[0-9]+)?$'
}

# 使い方: pct1 <百分率の数> → 小数第1位の「NN.N%」
pct1() {
    awk -v v="$1" 'BEGIN { printf "%.1f%%", v }'
}

# ---------------------------------------------------------------------
# 基準値
# ---------------------------------------------------------------------

# 使い方: frontend_threshold <vite.config.ts> <種別> → 「NN%」または「読み取れず」
# thresholds: { ... } の中で「<種別>: <数>」を探す。型の宣言(<種別>: number;)は
# 数でないため一致しない。
frontend_threshold() {
    local file="$1" kind="$2" v=""
    if [ -f "$file" ]; then
        v=$(tr '\r\n' '  ' <"$file" |
            grep -oE 'thresholds[[:space:]]*:[[:space:]]*\{[^}]*\}' |
            grep -oE "(^|[^A-Za-z0-9_])${kind}[[:space:]]*:[[:space:]]*[0-9]+(\.[0-9]+)?" |
            head -n 1 | grep -oE '[0-9]+(\.[0-9]+)?$')
    fi
    if is_number "$v"; then
        printf '%s%%' "$v"
    else
        printf '%s' "$UNREADABLE"
    fi
}

# 使い方: backend_threshold <quality.gradle> <種別> → 「NN%」または「読み取れず」
# counter = '<種別>' の後で最初に現れる minimum = <割合> を、百分率にして出す。
# 間に別の counter が現れたら、その種別の minimum とは見なさない。
backend_threshold() {
    local file="$1" kind="$2" v=""
    if [ -f "$file" ]; then
        v=$(awk -v kind="$kind" '
            {
                line = $0
                if (line ~ /counter[ \t]*=/) {
                    # 引用符を含めて、英大文字と _ 以外を取り除いた残りを種別とする
                    c = line
                    sub(/.*counter[ \t]*=[ \t]*/, "", c)
                    gsub(/[^A-Z_]/, "", c)
                    current = c
                    next
                }
                if (current == kind && match(line, /minimum[ \t]*=[ \t]*[0-9]+(\.[0-9]+)?/)) {
                    m = substr(line, RSTART, RLENGTH)
                    sub(/^minimum[ \t]*=[ \t]*/, "", m)
                    print m
                    exit
                }
            }' "$file")
    fi
    if is_number "$v"; then
        awk -v v="$v" 'BEGIN { printf "%g%%", v * 100 }'
    else
        printf '%s' "$UNREADABLE"
    fi
}

# ---------------------------------------------------------------------
# 実測の値
# ---------------------------------------------------------------------

# 使い方: frontend_value <coverage-summary.json> <種別> → 「NN.N%」または「取得できず」
frontend_value() {
    local v
    v=$(jq -r --arg k "$2" '.total[$k].pct | if type == "number" then tostring else empty end' "$1" 2>/dev/null)
    if is_number "$v"; then
        pct1 "$v"
    else
        printf '%s' "$NOT_FOUND"
    fi
}

# 使い方: backend_value <jacocoTestReport.xml> <種別> → 「NN.N%」または「取得できず」
# レポート全体の counter は XML の末尾(</report> の直前)にあるため、その種別の
# 最後の counter を使う。末尾の counter の並びにその種別が無い(レポート全体の
# 値が無い)ときは取得できずとし、パッケージなどの途中の値で代えない。
backend_value() {
    local file="$1" kind="$2" tail_part counter missed covered
    # 最後の </package>(または </group>)より後ろが、レポート全体の counter の並び
    tail_part=$(tr -d '\r\n' <"$file" | sed -E 's#.*</(package|group)>##')
    counter=$(printf '%s' "$tail_part" |
        grep -oE "<counter type=\"${kind}\" missed=\"[0-9]+\" covered=\"[0-9]+\"/>" | tail -n 1)
    missed=$(printf '%s' "$counter" | sed -nE 's/.*missed="([0-9]+)".*/\1/p')
    covered=$(printf '%s' "$counter" | sed -nE 's/.*covered="([0-9]+)".*/\1/p')
    if [ -z "$missed" ] || [ -z "$covered" ] || [ $((missed + covered)) -eq 0 ]; then
        printf '%s' "$NOT_FOUND"
        return
    fi
    awk -v m="$missed" -v c="$covered" 'BEGIN { printf "%.1f%%", c * 100 / (m + c) }'
}

# ---------------------------------------------------------------------
# 成果物
# ---------------------------------------------------------------------

# 使い方: latest_main_artifact <成果物の名前> → 「run_id<TAB>head_sha<TAB>created_at」
# 見つからなければ空。一覧を取れなければ戻り値 1
latest_main_artifact() {
    local name="$1" pages
    pages=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/actions/artifacts?name=${name}&per_page=100") || return 1
    printf '%s' "$pages" | jq -s -r '
        [.[].artifacts[]?
         | select(.expired | not)
         | select(.workflow_run.head_branch == "main")]
        | sort_by(.created_at) | last // empty
        | [(.workflow_run.id // "" | tostring), (.workflow_run.head_sha // ""), (.created_at // "")]
        | join("\u001f")' || return 1
}

# 使い方: run_info <run_id> <head_sha> <created_at> → 「実行の日付 …、コミット …、…」
run_info() {
    local run_id="$1" sha="$2" created="$3" date commit link
    date=$(sanitize "${created:0:10}")
    if ! printf '%s' "$date" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        date="不明"
    else
        date="${date}(UTC)"
    fi
    if printf '%s' "$sha" | grep -qE '^[0-9a-f]{7,64}$'; then
        commit="\`${sha:0:7}\`"
    else
        commit="不明"
    fi
    if printf '%s' "$run_id" | grep -qE '^[0-9]+$'; then
        link="[実行の記録](${SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${run_id})"
    else
        link="実行の記録 不明"
    fi
    printf '実行の日付 %s、コミット %s、%s' "$date" "$commit" "$link"
}

# 使い方: side_section <frontend|backend>
# 成果物を探して取り、見出しの行と表を出す
side_section() {
    local side="$1" name inner kinds found run_id sha created dir header file="" k value threshold
    if [ "$side" = frontend ]; then
        name=frontend-test-results
        inner=coverage/coverage-summary.json
        kinds=("${FRONTEND_KINDS[@]}")
    else
        name=backend-check-results
        inner=reports/jacoco/test/jacocoTestReport.xml
        kinds=("${BACKEND_KINDS[@]}")
    fi

    if ! found=$(latest_main_artifact "$name"); then
        header="${side}: ${REASON_LIST_FAILED}"
    elif [ -z "$found" ]; then
        header="${side}: ${REASON_NO_ARTIFACT}"
    else
        # 空の欄で詰まらないよう、空白でない区切り(US)で分ける
        IFS=$'\x1f' read -r run_id sha created <<<"$found"
        dir="${TMP_DIR}/${name}"
        if [ -z "$run_id" ] || ! gh run download "$run_id" -R "$GITHUB_REPOSITORY" -n "$name" -D "$dir" >/dev/null 2>&1; then
            header="${side}: ${REASON_DOWNLOAD_FAILED}。$(run_info "$run_id" "$sha" "$created")"
        elif [ ! -f "${dir}/${inner}" ]; then
            header="${side}: ${REASON_NO_FILE}。$(run_info "$run_id" "$sha" "$created")"
        else
            file="${dir}/${inner}"
            header="${side}: $(run_info "$run_id" "$sha" "$created")"
        fi
    fi

    printf '%s\n\n' "$header"
    printf '| 種別 | 実測 | 基準値 |\n|---|---|---|\n'
    for k in "${kinds[@]}"; do
        if [ -z "$file" ]; then
            value="$NOT_FOUND"
        elif [ "$side" = frontend ]; then
            value=$(frontend_value "$file" "$k")
        else
            value=$(backend_value "$file" "$k")
        fi
        if [ "$side" = frontend ]; then
            threshold=$(frontend_threshold "${ROOT}/frontend/vite.config.ts" "$k")
        else
            threshold=$(backend_threshold "${ROOT}/backend/gradle/quality.gradle" "$k")
        fi
        printf '| %s | %s | %s |\n' "$k" "$(sanitize "$value")" "$(sanitize "$threshold")"
    done
}

# ---------------------------------------------------------------------
# 本体
# ---------------------------------------------------------------------
OUT_FILE="${1:-}"
if [ -z "$OUT_FILE" ]; then
    echo "使い方: collect-coverage.sh <出力ファイル>" >&2
    exit 2
fi
if [ -z "${GH_TOKEN:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ]; then
    echo "環境変数 GH_TOKEN と GITHUB_REPOSITORY が必要です" >&2
    exit 2
fi
SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"
ROOT="${COVERAGE_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
TMP_DIR=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP_DIR"' EXIT

{
    printf 'カバレッジ(main で最後にテストを実行した CI の成果物の値と、vite.config.ts・quality.gradle の基準値。良し悪しは判定しない)\n\n'
    side_section frontend
    printf '\n'
    side_section backend
} >"$OUT_FILE" || {
    echo "出力ファイルに書けません: ${OUT_FILE}" >&2
    exit 2
}
exit 0
