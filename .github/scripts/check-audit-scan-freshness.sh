#!/usr/bin/env bash
# =====================================================================
# 定期スキャンの鮮度判定(audit-weekly CI から実行)
#
# 判定: 引数のワークフローの直近の成功実行を1件取得し、
#       成功が一度も存在しない → exit 1(赤)
#       直近の成功がしきい値日数以上前 → exit 1(最終成功日時を報告)
#       しきい値未満 → exit 0(緑)
#       API失敗・応答を解釈できない → 判定不能として exit 1(fail closed)
#
# なぜ必要か:
#   稼働中イメージの定期脆弱性スキャン(container-scan-scheduled.yaml)が
#   止まっても、GitHubの通知は「失敗した実行」にしか出ない。実行されなかった
#   ことは通知されないため、「起きなかったこと」を人間が画面を開いて確認して
#   いた(旧・週次8)。この検査がそれを置き換え、鮮度切れを週次監査の赤にする。
#
# なぜ8日ちょうどを赤にするのか:
#   スキャンは週1回のため、正常なら直近成功からの経過は7日+実行遅延に収まる。
#   8日空いたら1回分が丸ごと欠けたとみなす。「8日以上」=赤(境界を含む)。
#
# なぜ判定不能を赤にするのか:
#   判定できないまま通すと、検査があるのに守られていない状態が静かに続く。
#   判定不能の赤は、失敗したrunのre-runで再判定する。新規のworkflow_dispatch
#   で流し直すと、同じ週次監査内のスキップ検知の対象期間に未走査の穴が空く
#   ため、報告文面でre-runを指示する。
#
# テスト: .github/scripts/tests/test-check-audit-scan-freshness.sh
# 使い方: check-audit-scan-freshness.sh <workflow_file> <threshold_days>
#   環境変数 GH_TOKEN(必須) / GITHUB_REPOSITORY(必須)
#   NOW_EPOCH(テスト用の時刻固定)
# =====================================================================
set -euo pipefail

WORKFLOW_FILE="${1:?workflow file required}"
THRESHOLD_DAYS="${2:?threshold days required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
: "${GH_TOKEN:?GH_TOKEN required}"

NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
THRESHOLD_SECONDS=$((THRESHOLD_DAYS * 86400))

# 判定不能の報告と終了。API障害等の外部要因は同じrunの再実行で解消しうる。
report_undecidable() {
    local reason="$1"
    {
        echo "### :warning: 定期スキャンの稼働状況を確認できませんでした(判定不能)"
        echo ""
        echo "$reason"
        echo "対象: \`repos/${REPO}/actions/workflows/${WORKFLOW_FILE}/runs\`"
        echo ""
        echo "**成功に倒さず赤にしています。**"
        echo "失敗したこのrunをre-run(同じrunの再実行)してください。"
        echo "新規の手動実行で流し直すと、スキップ検知の対象期間に未走査の穴が空きます。"
        echo "繰り返し失敗する場合はAPIの応答を人間が確認してください。"
        echo ""
    } >>"$SUMMARY"
    echo "定期スキャンの稼働状況を確認できませんでした(判定不能): ${reason}" >&2
    exit 1
}

# --- 直近の成功実行の取得 -------------------------------------------------------
# status=success で絞り、最新1件だけを取る(1リクエスト)。
# 取得の失敗を「成功ゼロ」と混同しない。混同すると、API障害のたびに
# 「スキャンが止まった」という誤った報告になり、赤の意味が信用できなくなる。
runs_json=""
if ! runs_json=$(gh api \
    "repos/${REPO}/actions/workflows/${WORKFLOW_FILE}/runs?status=success&per_page=1" 2>/dev/null); then
    report_undecidable "実行一覧APIへの問い合わせに失敗しました。"
fi

# workflow_runs が配列であることを確かめてから件数を読む。エラーメッセージの
# JSON(例: {"message":"Not Found"})を「成功ゼロ」と誤読しないため。
count=""
if ! count=$(printf '%s' "$runs_json" | jq -er \
    'if (.workflow_runs | type) == "array" then (.workflow_runs | length) else empty end' 2>/dev/null); then
    report_undecidable "実行一覧APIの応答を解釈できませんでした。"
fi

if [ "$count" -eq 0 ]; then
    {
        echo "### :rotating_light: 定期スキャンに成功した実行が存在しません"
        echo ""
        echo "対象: \`${WORKFLOW_FILE}\`"
        echo ""
        echo "スキャンが一度も成功していないか、実行履歴が失われています。"
        echo "対象ワークフローの実行履歴と設定を人間が確認してください。"
        echo ""
    } >>"$SUMMARY"
    echo "定期スキャン(${WORKFLOW_FILE})に成功した実行が存在しません。" >&2
    exit 1
fi

created_at=$(printf '%s' "$runs_json" | jq -er '.workflow_runs[0].created_at' 2>/dev/null) ||
    report_undecidable "直近の成功実行から created_at を取得できませんでした。"

published=$(date -u -d "$created_at" +%s 2>/dev/null) ||
    report_undecidable "直近の成功日時の書式を解釈できません: ${created_at}"

# --- 鮮度の判定 -----------------------------------------------------------------
age=$((NOW_EPOCH - published))
last_success=$(date -u -d "@${published}" +'%Y-%m-%d %H:%M UTC')

if [ "$age" -ge "$THRESHOLD_SECONDS" ]; then
    {
        echo "### :rotating_light: 定期スキャンが止まっています"
        echo ""
        echo "対象: \`${WORKFLOW_FILE}\`"
        echo ""
        echo "直近の成功から ${THRESHOLD_DAYS} 日以上経過しています。"
        echo "**最終成功日時: ${last_success}**"
        echo ""
        echo "スケジュール実行が止まった原因(ワークフローの無効化・失敗の連続等)を"
        echo "対象ワークフローの実行履歴から人間が確認してください。"
        echo ""
    } >>"$SUMMARY"
    echo "定期スキャン(${WORKFLOW_FILE})の直近の成功から ${THRESHOLD_DAYS} 日以上経過しています。" >&2
    echo "最終成功日時: ${last_success}" >&2
    exit 1
fi

echo "定期スキャン(${WORKFLOW_FILE})は稼働しています(最終成功: ${last_success})。"
exit 0
