#!/usr/bin/env bash
# =====================================================================
# mutation testing のスコアを台帳のIssueに1行追記する(mutation-report CI から実行)
#
# 処理: PIT(backend)の mutations.xml と Stryker(frontend)の mutation.json から
#       スコアを計算し、固定タイトルのIssue「メトリクス台帳: mutationスコア」の
#       本文の表に、測定方式と合わせて1行追記する。Issueが無ければ作成する。
#       全件を測り直した回は、直前の全件の回との差とカバレッジを台帳のIssueに
#       コメントし、所有者にメンションする。前回の結果を使った回(差分)は
#       追記だけで、コメントしない。
#
# 終了コード:
#   0 = 追記した(全件の回はコメントも済んだ。スコアを取得できなかった側は
#       「取得できず」として記録する)
#   2 = 台帳に書けなかった・コメントできなかった(引数・環境変数の不足、APIの失敗)
#   スコアやカバレッジの良し悪しは判定しない。しきい値とも比べない。
#
# なぜ台帳を測定側が書くのか:
#   月次の比較(監査手順の定期作業)には過去のスコアが要るが、レポートの成果物は
#   保持期間が過ぎると消える。監査のワークフローは状態を持たない
#   (audit-automation の要件6-3)ため、記録は測定したワークフロー自身が行う
#   (#334、所有者の決定 2026-09-25)。
#
# なぜ取得できなかった回も1行書くのか:
#   測定が止まったことを台帳の上で見えるようにするため。行を書かないと、
#   止まった週と記録を忘れた週の区別が付かない。
#   実例: frontend の Stryker は導入以来一度もレポートを出していなかった(#372)。
#
# なぜ測定方式を行ごとに残し、全件の回どうしで比べるのか:
#   frontend の Stryker は、前回の結果を使える回は変更のあった部分だけを測り直す
#   (差分)。差分の回のスコアは測り方が違うため、全件の回と並べて比べると
#   差が測り方の違いを含んでしまう。比べる相手は、新しい表の中の直前の全件の行に
#   限る。backend の PIT は毎回全件を測る。
#   4列の古い表は測定方式を持たないため、比較に使わない。書き換えもしない。
#
# 台帳の本文:
#   見出し「## 記録(測定方式つき)」の下の5列の表に追記する。本文にこの見出しが
#   無ければ(測定方式の列ができる前の台帳)、末尾に見出しと表の頭を1回だけ足す。
#
# 測定方式(環境変数 MUTATION_MODE。mutation-report.yaml が決める):
#   full-scheduled    全件(月初の定期)
#   full-manual       全件(手動)
#   full-no-previous  全件(前回の結果なし)。前回の Stryker の結果が見つからない・
#                     取得に失敗した・frontend の job が出力を残さなかった回
#   incremental       差分
#
# スコアの定義(各ツールの表示と同じ):
#   backend  = 検出数 / 生成数(PIT の "Killed N (x%)")。detected='true' を検出とする
#   frontend = (Killed + Timeout) / (Killed + Timeout + Survived + NoCoverage)
#              (Stryker の mutation score。CompileError / RuntimeError / Ignored は除く)
# 差: 今回と前回の百分率の差(ポイント)。小数第1位、符号つき。0 は ±0.0
#
# テスト: .github/scripts/tests/test-record-mutation-metrics.sh
# 使い方: record-mutation-metrics.sh <mutations.xml のパス> <mutation.json のパス>
#   ファイルが無い場合もパスは渡す(「取得できず」として記録する)
#   環境変数 GH_TOKEN(必須) / GITHUB_REPOSITORY(必須) / GITHUB_REPOSITORY_OWNER(必須)
#   GITHUB_RUN_ID(必須) / MUTATION_MODE(必須。上の4値)
#   COVERAGE_FILE(任意。全件の回にコメントへ入れるカバレッジの Markdown。
#   collect-coverage.sh の出力。無い・空なら「取得できず」)
#   GITHUB_SERVER_URL(任意) / NOW_EPOCH(テスト用の時刻固定)
# =====================================================================
set -Eeuo pipefail
trap 'exit 2' ERR

if [ "$#" -lt 2 ]; then
    echo "::error::引数は2個必要です: <mutations.xml のパス> <mutation.json のパス>"
    exit 2
fi
for v in GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER GITHUB_RUN_ID MUTATION_MODE; do
    if [ -z "${!v:-}" ]; then
        echo "::error::環境変数 ${v} が必要です"
        exit 2
    fi
done

case "$MUTATION_MODE" in
full-scheduled)
    MODE_LABEL="全件(月初の定期)"
    FULL_REASON="月初の定期実行のため、frontend(Stryker)も前回の結果を使わずに全件を測り直しました。"
    ;;
full-manual)
    MODE_LABEL="全件(手動)"
    FULL_REASON="手動の実行で全件を指定したため、frontend(Stryker)も前回の結果を使わずに全件を測り直しました。"
    ;;
full-no-previous)
    MODE_LABEL="全件(前回の結果なし)"
    FULL_REASON="frontend(Stryker)の差分の測定に使う前回の結果が無かった(見つからない、または取得に失敗した)ため、全件を測り直しました。"
    ;;
incremental)
    MODE_LABEL="差分"
    FULL_REASON=""
    ;;
*)
    echo "::error::MUTATION_MODE は full-scheduled / full-manual / full-no-previous / incremental のいずれかで指定してください: ${MUTATION_MODE}"
    exit 2
    ;;
esac

PIT_XML="$1"
STRYKER_JSON="$2"
REPO="$GITHUB_REPOSITORY"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${REPO}/actions/runs/${GITHUB_RUN_ID}"
NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
if ! [[ "$NOW_EPOCH" =~ ^[1-9][0-9]{0,11}$ ]]; then
    echo "::error::NOW_EPOCH はエポック秒(先頭0なし・12桁まで)で指定してください: ${NOW_EPOCH}"
    exit 2
fi
TITLE="メトリクス台帳: mutationスコア"
UNAVAILABLE="取得できず"
HEADING="## 記録(測定方式つき)"
TABLE_HEADER="| 実行日(UTC) | 測定方式 | backend(PIT) | frontend(Stryker) | 実行 |"
TABLE_SEPARATOR="|---|---|---|---|---|"

# shellcheck source=.github/scripts/lib-ledger-issue.sh
if ! self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) ||
    ! source "${self_dir}/lib-ledger-issue.sh"; then
    echo "::error::lib-ledger-issue.sh を読み込めません"
    exit 2
fi

WORKDIR=$(mktemp -d) || exit 2
trap 'rm -rf "$WORKDIR"' EXIT

# 分子と分母から「xx.x%(分子/分母)」を作る。分母が0なら取得できず扱い。
format_score() {
    local num="$1" den="$2"
    if [ "$den" -eq 0 ]; then
        echo "$UNAVAILABLE"
        return
    fi
    # 小数第1位まで(四捨五入)。整数演算で求める
    local tenths=$(((num * 1000 + den / 2) / den))
    echo "$((tenths / 10)).$((tenths % 10))%(${num}/${den})"
}

# 「xx.x%(分子/分母)」から、百分率を10倍した整数を出す。読めなければ何も出さない。
score_tenths() {
    if [[ "$1" =~ ^([0-9]+)\.([0-9])% ]]; then
        echo "$((10#${BASH_REMATCH[1]} * 10 + BASH_REMATCH[2]))"
    fi
}

# 今回と前回の欄から差を作る。どちらかが読めなければ「比較対象なし」。
format_diff() {
    local cur prev diff sign="+"
    cur=$(score_tenths "$1")
    prev=$(score_tenths "$2")
    if [ -z "$cur" ] || [ -z "$prev" ]; then
        echo "比較対象なし"
        return
    fi
    diff=$((cur - prev))
    if [ "$diff" -lt 0 ]; then
        sign="-"
        diff=$((-diff))
    elif [ "$diff" -eq 0 ]; then
        sign="±"
    fi
    echo "${sign}$((diff / 10)).$((diff % 10))ポイント"
}

# --- backend(PIT) ----------------------------------------------------------------
# mutations.xml は1行に1つの <mutation detected='…' status='…' …> を持つ。
backend="$UNAVAILABLE"
if [ -r "$PIT_XML" ]; then
    total=$(grep -oE "<mutation detected='(true|false)'" "$PIT_XML" | wc -l | tr -d ' ') || total=0
    detected=$(grep -oE "<mutation detected='true'" "$PIT_XML" | wc -l | tr -d ' ') || detected=0
    backend=$(format_score "$detected" "$total")
fi

# --- frontend(Stryker) -----------------------------------------------------------
# mutation-testing-report-schema の JSON。files.<パス>.mutants[].status を数える。
frontend="$UNAVAILABLE"
if [ -r "$STRYKER_JSON" ]; then
    if counts=$(jq -er '
        [.files[]?.mutants[]?.status] as $s
        | ([$s[] | select(. == "Killed" or . == "Timeout")] | length) as $det
        | ([$s[] | select(. == "Survived" or . == "NoCoverage")] | length) as $und
        | "\($det) \($det + $und)"' "$STRYKER_JSON" 2>/dev/null); then
        frontend=$(format_score "${counts% *}" "${counts#* }")
    fi
fi

today=$(date -u -d "@${NOW_EPOCH}" +%Y-%m-%d)
row="| ${today} | ${MODE_LABEL} | ${backend} | ${frontend} | [実行](${RUN_URL}) |"
echo "追記する行: ${row}"

# --- 台帳のIssueを探す・作る ----------------------------------------------------
# 新しく作る台帳は、最初から新しい見出しと表の頭を持つ(行は後で追記する)。
# ラベルは付けない(既存の台帳を変えないため)。
{
    echo "mutation testing のスコアの記録。\`mutation-report.yaml\` が実行のたびに1行追記する(#334)。"
    echo "人が編集しない。スコアの定義と測定方式は \`.github/scripts/record-mutation-metrics.sh\` の冒頭を参照する。"
    echo "全件を測り直した回は、直前の全件の回との差をこのIssueにコメントする。"
    echo ""
    echo "$HEADING"
    echo ""
    echo "$TABLE_HEADER"
    echo "$TABLE_SEPARATOR"
} >"${WORKDIR}/initial.md"
if ! number=$(ledger_find_or_create "$TITLE" "${WORKDIR}/initial.md" ""); then
    echo "::error::台帳のIssueを探せない、または作れませんでした。"
    exit 2
fi

# --- 本文の読み取り(見出しの有無と、直前の全件の行) ------------------------------
if ! body=$(gh api "repos/${REPO}/issues/${number}" --jq '.body // ""' 2>/dev/null); then
    echo "::error::台帳のIssue #${number} の本文を取得できませんでした。"
    exit 2
fi

# 見出しより後ろの行だけを新しい表として読む。Web で編集された本文の CRLF も扱う。
# 列: 実行日 / 測定方式 / backend / frontend / 実行
row_re='^[|] ([0-9]{4}-[0-9]{2}-[0-9]{2}) [|] ([^|]+) [|] ([^|]+) [|] ([^|]+) [|] .* [|]$'
has_heading=0
prev_date=""
prev_backend=""
prev_frontend=""
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$line" = "$HEADING" ]; then
        has_heading=1
        continue
    fi
    if [ "$has_heading" -eq 1 ] && [[ "$line" =~ $row_re ]]; then
        if [[ "${BASH_REMATCH[2]}" == 全件* ]]; then
            prev_date="${BASH_REMATCH[1]}"
            prev_backend="${BASH_REMATCH[3]}"
            prev_frontend="${BASH_REMATCH[4]}"
        fi
    fi
done <<<"$body"

# --- 台帳への追記 ----------------------------------------------------------------
# 見出しが無ければ、空行・見出し・表の頭を足してから行を足す。既存の本文は変えない。
{
    if [ "$has_heading" -eq 0 ]; then
        echo ""
        echo "$HEADING"
        echo ""
        echo "$TABLE_HEADER"
        echo "$TABLE_SEPARATOR"
    fi
    echo "$row"
} >"${WORKDIR}/append.md"
if ! ledger_append_body "$number" "${WORKDIR}/append.md"; then
    echo "::error::台帳のIssue #${number} に追記できませんでした。"
    exit 2
fi

# --- 全件の回のコメント ------------------------------------------------------------
if [ "$MUTATION_MODE" = "incremental" ]; then
    echo "差分の回のため、コメントしません。"
    exit 0
fi

if [ -n "$prev_date" ]; then
    prev_heading="前回の全件(${prev_date})"
else
    prev_heading="前回の全件"
    prev_backend="記録なし"
    prev_frontend="記録なし"
fi

# カバレッジは collect-coverage.sh が作った Markdown をそのまま入れる。
# 渡されない・読めない・空白しか無いときは「取得できず」とする。
coverage_available=0
if [ -n "${COVERAGE_FILE:-}" ] && [ -f "$COVERAGE_FILE" ] && [ -r "$COVERAGE_FILE" ] &&
    grep -q '[^[:space:]]' "$COVERAGE_FILE" 2>/dev/null; then
    coverage_available=1
fi

# 1行目は説明の文にする(ledger_comment が1行目の頭にメンションを付けるため、
# 表から始めると表として表示されない)。
{
    echo "mutation スコアの全件の測定を記録しました(${today}、${MODE_LABEL})。直前の全件の回と比べた差は次のとおりです。"
    echo ""
    echo "| | 今回 | ${prev_heading} | 差 |"
    echo "|---|---|---|---|"
    echo "| backend(PIT) | ${backend} | ${prev_backend} | $(format_diff "$backend" "$prev_backend") |"
    echo "| frontend(Stryker) | ${frontend} | ${prev_frontend} | $(format_diff "$frontend" "$prev_frontend") |"
    echo ""
    echo "全件になった理由: ${FULL_REASON}backend(PIT)は毎回全件を測ります。"
    echo "差は、台帳の「${HEADING#\#\# }」の表の直前の全件の行との比較です。差分の回と、測定方式の列ができる前の行は比べません。"
    echo ""
    echo "### カバレッジ"
    echo ""
    if [ "$coverage_available" -eq 1 ]; then
        cat "$COVERAGE_FILE"
    else
        echo "カバレッジ: ${UNAVAILABLE}(カバレッジの読み取りの結果がありません)"
    fi
    echo ""
    echo "実行: [実行](${RUN_URL})"
} >"${WORKDIR}/comment.md"
if ! ledger_comment "$number" "${WORKDIR}/comment.md"; then
    echo "::error::台帳のIssue #${number} にコメントできませんでした。"
    exit 2
fi
exit 0
