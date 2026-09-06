#!/usr/bin/env bash
# =====================================================================
# 滞留しているDependabot PRの検知(audit-weekly CI から実行)
#
# 判定: openのDependabot PR(author: dependabot[bot])ごとにheadコミットの
#       check-runsを集計し、期待一覧(required-checks.json)に載るcontextの
#       最新の結論を調べる。
#         approval_gated: false のcontextに failure → 滞留。1件以上で exit 1
#                          (対象のPR番号と失敗しているチェック名を列挙)
#         approval_gated: true のcontextの failure → 「承認待ち」として報告のみ
#         実行中(結論なし)・すべて緑・承認待ちのみ・open PRゼロ → exit 0
#         期待一覧のスキーマ不正・API失敗 → 判定不能として exit 1(fail closed)
#       件数のしきい値は持たない(失敗で止まっているPRの有無だけで判定する)。
#       チェック失敗以外の滞留(mainより遅れたまま緑で停止・自動更新の失敗・
#       マージ衝突等)は判定の対象にしない。
#
# なぜ必要か:
#   Dependabot PRが必須チェックの失敗で止まっても、GitHubの通知には「失敗
#   した実行」しか出ず、PRが止まり続けていることは一覧画面を開かないと
#   分からなかった(旧・週次6)。とくにdockerレーンの滞留はイメージの更新
#   停止を意味する。この検査がそれを置き換え、滞留を週次監査の赤にする。
#
# なぜ approval_gated のfailureを滞留にしないのか:
#   dependency-gate / escape-hatch / pre-merge-check は所有者の承認で緑になる
#   設計のチェックで、そのfailureは「承認待ち」という正常な停止。ただしこの
#   静的な分類では、これらのチェック自体の故障によるfailureも除外されて
#   しまう(受容済みの残余リスク)。緩和策として、承認待ちPRの一覧を
#   Job Summaryへ常時出力し、長期の滞留が人間の目に入るようにする。
#
# なぜ同一contextの複数check-runは最新で判定するのか:
#   再実行・イベントの多重発火で同じcontextのcheck-runが複数残るため。
#   古いfailureを拾うと再実行で直ったPRが偽赤になり、古いsuccessを拾うと
#   壊れたままのPRを見逃す。
#
# なぜ判定不能を赤にするのか:
#   判定できないまま通すと、検査があるのに守られていない状態が静かに続く。
#   判定不能の赤は、失敗したrunのre-runで再判定する。新規のworkflow_dispatch
#   で流し直すと、同じ週次監査内のスキップ検知の対象期間に未走査の穴が空く
#   ため、報告文面でre-runを指示する。
#
# テスト: .github/scripts/tests/test-check-audit-dependabot-stuck.sh
# 使い方: check-audit-dependabot-stuck.sh <期待一覧(required-checks.json)のパス>
#   環境変数 GH_TOKEN(必須) / GITHUB_REPOSITORY(必須)
# =====================================================================
set -euo pipefail

CHECKS_FILE="${1:?required checks file required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
: "${GH_TOKEN:?GH_TOKEN required}"

SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# 判定不能の報告と終了。API障害等の外部要因は同じrunの再実行で解消しうる。
report_undecidable() {
    local reason="$1"
    {
        echo "### :warning: Dependabot PRの滞留状況を確認できませんでした(判定不能)"
        echo ""
        echo "$reason"
        echo ""
        echo "**成功に倒さず赤にしています。**"
        echo "失敗したこのrunをre-run(同じrunの再実行)してください。"
        echo "新規の手動実行で流し直すと、スキップ検知の対象期間に未走査の穴が空きます。"
        echo "繰り返し失敗する場合は期待一覧とAPIの応答を人間が確認してください。"
        echo ""
    } >>"$SUMMARY"
    echo "Dependabot PRの滞留状況を確認できませんでした(判定不能): ${reason}" >&2
    exit 1
}

# --- 期待一覧のスキーマ検証 ------------------------------------------------------
# 判定の基準となるデータが壊れていたら、集計に進まず判定不能で止める。
# 欠落や未知の値を黙って読み飛ばすと、期待一覧の書き誤りが「検査されない
# context」として静かに素通りするため、fail closed にする。
if [ ! -f "$CHECKS_FILE" ]; then
    report_undecidable "期待一覧が見つかりません: ${CHECKS_FILE}"
fi

if ! jq -e '.' "$CHECKS_FILE" >/dev/null 2>&1; then
    report_undecidable "期待一覧(${CHECKS_FILE})をJSONとして解釈できませんでした。"
fi

# checks配列であること・context/mode/state/approval_gated の必須と値域・
# state: paused のときのみ reason/issue 必須・未知フィールドの拒否。
if ! jq -e '
    (.checks | type) == "array"
    and ([.checks[]
        | (type == "object")
          and ((keys - ["approval_gated", "context", "issue", "mode", "reason", "state"]) == [])
          and has("context") and has("mode") and has("state") and has("approval_gated")
          and ((.context | type) == "string")
          and (.mode == "always" or .mode == "conditional")
          and (.state == "active" or .state == "paused")
          and ((.approval_gated | type) == "boolean")
          and (if .state == "paused" then has("reason") and has("issue") else true end)
    ] | all)
' "$CHECKS_FILE" >/dev/null 2>&1; then
    report_undecidable "期待一覧(${CHECKS_FILE})がスキーマに適合しません(必須フィールドの欠落・未知の値・未知のフィールド)。"
fi

# context → approval_gated の対応表。以降の集計はこの表に載るcontextだけを見る
# (期待一覧に載らないチェックの結論は、必須チェックの滞留判定に使わない)。
expected_map=$(jq -c '.checks | map({key: .context, value: .approval_gated}) | from_entries' "$CHECKS_FILE") ||
    report_undecidable "期待一覧(${CHECKS_FILE})から対応表を作成できませんでした。"

# --- openのDependabot PR一覧の取得 -----------------------------------------------
# openのPR全件を取得してauthorで絞る。--paginate は100件を超えても取りこぼさ
# ないため。応答はページごとのJSON配列の連続になるため、slurpして連結する。
pulls_json=""
if ! pulls_json=$(gh api --paginate "repos/${REPO}/pulls?state=open&per_page=100" 2>/dev/null); then
    report_undecidable "PR一覧APIへの問い合わせに失敗しました。"
fi

# 応答が配列であること・number と head.sha が揃っていることを確かめてから使う。
# エラーメッセージのJSON(例: {"message":"Not Found"})を「PRゼロ」と誤読しないため。
pulls_list=""
if ! pulls_list=$(printf '%s' "$pulls_json" | jq -ces '
    if all(type == "array") then
        (add // [])
        | map(select((.user.login? // "") == "dependabot[bot]"))
        | if all(((.number | type) == "number") and ((.head.sha? | type) == "string")) then
              map({number: .number, sha: .head.sha})
          else empty end
    else empty end' 2>/dev/null); then
    report_undecidable "PR一覧APIの応答を解釈できませんでした。"
fi

# --- PRごとの集計 ---------------------------------------------------------------
stuck_report=""
waiting_report=""
pr_count=$(jq 'length' <<<"$pulls_list")

i=0
while [ "$i" -lt "$pr_count" ]; do
    number=$(jq -r ".[$i].number" <<<"$pulls_list")
    sha=$(jq -r ".[$i].sha" <<<"$pulls_list")

    # headコミットのcheck-runsを取得する。per_page=100 は必須チェック数+
    # 再実行分に対して十分な余裕がある(APIの既定 filter=latest が同一
    # スイート内の再実行を畳むため、通常はcontext数+α件しか返らない)。
    runs_json=""
    if ! runs_json=$(gh api "repos/${REPO}/commits/${sha}/check-runs?per_page=100" 2>/dev/null); then
        report_undecidable "PR #${number} のcheck-runs APIへの問い合わせに失敗しました。"
    fi

    # 期待一覧に載るcontextだけを対象に、同一contextの複数check-runは
    # started_at(同時刻はid)が最新のものの結論で判定し、failureだけを残す。
    failures_json=""
    if ! failures_json=$(printf '%s' "$runs_json" | jq -ce --argjson expected "$expected_map" '
        if (.check_runs | type) == "array" then
            [.check_runs[] | select(((.name? | type) == "string") and (.name as $n | $expected | has($n)))]
            | group_by(.name)
            | map(max_by([(.started_at // ""), (.id // 0)]))
            | map(select(.conclusion? == "failure"))
            | map({name: .name, gated: $expected[.name]})
            | sort_by(.name)
        else empty end' 2>/dev/null); then
        report_undecidable "PR #${number} のcheck-runs APIの応答を解釈できませんでした。"
    fi

    stuck_names=$(jq -r '[.[] | select(.gated | not) | .name] | join(", ")' <<<"$failures_json")
    waiting_names=$(jq -r '[.[] | select(.gated) | .name] | join(", ")' <<<"$failures_json")

    if [ -n "$stuck_names" ]; then
        stuck_report="${stuck_report}- #${number}: ${stuck_names}"$'\n'
    fi
    if [ -n "$waiting_names" ]; then
        waiting_report="${waiting_report}- #${number}: ${waiting_names}"$'\n'
    fi

    i=$((i + 1))
done

# --- 報告 -----------------------------------------------------------------------
# 承認待ちの一覧は判定結果にかかわらず常時出力する(approval_gated分類の
# 残余リスクの緩和策。長期の承認待ちが人間の目に入るようにする)。
emit_waiting_section() {
    {
        echo "#### 承認待ちで停止しているDependabot PR"
        echo ""
        if [ -n "$waiting_report" ]; then
            printf '%s' "$waiting_report"
            echo ""
            echo "承認で緑になる設計のチェック(approval_gated)のfailureのため、滞留とは扱いません。"
            echo "長く残っている場合は、承認の要否を人間が判断してください。"
        else
            echo "- なし"
        fi
        echo ""
    } >>"$SUMMARY"
}

if [ -n "$stuck_report" ]; then
    {
        echo "### :rotating_light: 必須チェックの失敗で止まっているDependabot PRがあります"
        echo ""
        printf '%s' "$stuck_report"
        echo ""
        echo "失敗しているチェックの原因を確認し、\`doc/開発フロー/監査手順.md\` の手順で対処してください。"
        echo ""
    } >>"$SUMMARY"
    emit_waiting_section
    echo "必須チェックの失敗で止まっているDependabot PRがあります:" >&2
    printf '%s' "$stuck_report" >&2
    exit 1
fi

emit_waiting_section
echo "必須チェックの失敗で止まっているDependabot PRはありません(open: ${pr_count}件)。"
exit 0
