#!/usr/bin/env bash
# =====================================================================
# mutation testing のスコアを台帳のIssueに1行追記する(mutation-report CI から実行)
#
# 処理: PIT(backend)の mutations.xml と Stryker(frontend)の mutation.json から
#       スコアを計算し、固定タイトルのIssue「メトリクス台帳: mutationスコア」の
#       本文の表に1行追記する。Issueが無ければ作成する。
#
# 終了コード:
#   0 = 追記した(スコアを取得できなかった側は「取得できず」として記録する)
#   2 = 台帳に書けなかった(引数・環境変数の不足、APIの失敗)
#
# なぜ台帳を測定側が書くのか:
#   月次の比較(監査手順の月次2)には過去のスコアが要るが、レポートの成果物は
#   保持期間が過ぎると消える。監査のワークフローは状態を持たない
#   (audit-automation の要件6-3)ため、記録は測定したワークフロー自身が行う
#   (#334、所有者の決定 2026-09-25)。
#
# なぜ取得できなかった回も1行書くのか:
#   測定が止まったことを台帳の上で見えるようにするため。行を書かないと、
#   止まった週と記録を忘れた週の区別が付かない。
#   実例: frontend の Stryker は導入以来一度もレポートを出していなかった(#372)。
#
# スコアの定義(各ツールの表示と同じ):
#   backend  = 検出数 / 生成数(PIT の "Killed N (x%)")。detected='true' を検出とする
#   frontend = (Killed + Timeout) / (Killed + Timeout + Survived + NoCoverage)
#              (Stryker の mutation score。CompileError / RuntimeError / Ignored は除く)
#
# テスト: .github/scripts/tests/test-record-mutation-metrics.sh
# 使い方: record-mutation-metrics.sh <mutations.xml のパス> <mutation.json のパス>
#   ファイルが無い場合もパスは渡す(「取得できず」として記録する)
#   環境変数 GH_TOKEN(必須) / GITHUB_REPOSITORY(必須) / GITHUB_RUN_ID(必須)
#   GITHUB_SERVER_URL(任意) / NOW_EPOCH(テスト用の時刻固定)
# =====================================================================
set -Eeuo pipefail
trap 'exit 2' ERR

if [ "$#" -lt 2 ]; then
    echo "::error::引数は2個必要です: <mutations.xml のパス> <mutation.json のパス>"
    exit 2
fi
for v in GH_TOKEN GITHUB_REPOSITORY GITHUB_RUN_ID; do
    if [ -z "${!v:-}" ]; then
        echo "::error::環境変数 ${v} が必要です"
        exit 2
    fi
done

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

row="| $(date -u -d "@${NOW_EPOCH}" +%Y-%m-%d) | ${backend} | ${frontend} | [実行](${RUN_URL}) |"
echo "追記する行: ${row}"

# --- 台帳のIssueへの追記 --------------------------------------------------------
# タイトルの完全一致で探す(検索は部分一致のため、jq で絞り込む)。閉じられていても
# 同じ台帳を使い続ける。
if ! issues_json=$(gh api --paginate "repos/${REPO}/issues?state=all&per_page=100" 2>/dev/null); then
    echo "::error::Issue一覧を取得できませんでした。"
    exit 2
fi
if ! number=$(printf '%s' "$issues_json" | jq -sr --arg t "$TITLE" '
    [.[][] | select(.pull_request == null and .title == $t) | .number] | min // empty' 2>/dev/null); then
    echo "::error::Issue一覧の応答を解釈できませんでした。"
    exit 2
fi

body_file=$(mktemp) || exit 2
if [ -z "$number" ]; then
    {
        echo "mutation testing のスコアの記録。\`mutation-report.yaml\` が実行のたびに1行追記する(#334)。"
        echo "人が編集しない。スコアの定義は \`.github/scripts/record-mutation-metrics.sh\` の冒頭を参照する。"
        echo ""
        echo "| 実行日(UTC) | backend(PIT) | frontend(Stryker) | 実行 |"
        echo "|---|---|---|---|"
        echo "$row"
    } >"$body_file"
    if ! gh issue create --repo "$REPO" --title "$TITLE" --body-file "$body_file" >/dev/null; then
        echo "::error::台帳のIssueを作成できませんでした。"
        exit 2
    fi
    echo "台帳のIssueを作成しました。"
    exit 0
fi

if ! body=$(gh api "repos/${REPO}/issues/${number}" --jq '.body // ""' 2>/dev/null); then
    echo "::error::台帳のIssue #${number} の本文を取得できませんでした。"
    exit 2
fi
printf '%s\n%s\n' "${body%$'\n'}" "$row" >"$body_file"
if ! gh issue edit "$number" --repo "$REPO" --body-file "$body_file" >/dev/null; then
    echo "::error::台帳のIssue #${number} に追記できませんでした。"
    exit 2
fi
echo "台帳のIssue #${number} に追記しました。"
exit 0
