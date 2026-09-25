#!/usr/bin/env bash
# =====================================================================
# 必須チェックの集合照合とスキップ検知(audit-weekly CI から実行)
#
# 判定は2段:
#   1. 集合照合: mainブランチのruleset(rules/branches/main)の
#      required_status_checks の context 集合と、期待一覧
#      (required-checks.json)の context 集合を双方向に比較する。
#      差分があれば exit 1(逸脱あり。差分を列挙)。状態(active/paused)は
#      この照合には使わない(照合は名前の集合のみで行う)。
#   2. スキップ検知: 対象期間内にmainへマージされたPRごとに、PRの
#      headコミット(pulls APIの head.sha)の check-runs を走査する。
#        mode: always かつ state: active の context に「実行の証拠」が
#          無い(全check-runがskipped、または1件も無い)→ 違反。
#          1件以上で exit 1(逸脱あり。PR番号+チェック名を列挙)
#        mode: always かつ state: paused の同状況 → 非違反。
#          「停止中(参照Issue)」として報告にのみ明示する
#        mode: conditional → 対象外(変更検知による正当なスキップ)
#   差分も違反も無ければ exit 0(逸脱なし)
#   期待一覧のスキーマ不正・API失敗 → exit 2(判定不能。fail closed)
#
# 終了コード:
#   0 = 逸脱なし / 1 = 逸脱あり / 2 = 判定不能
#   1 は集合の差分またはスキップ違反を報告したうえでの明示的な exit 1 だけが
#   返す。引数・必須環境変数の欠落と不正、ガードしていないコマンドの想定外の
#   失敗もすべて 2 に倒す。1 に混ぜると、判定が一度も完了していないのに
#   「逸脱あり」として扱われる。
#
# なぜ必要か:
#   必須チェックのスキップはGitHub上では成功として扱われるため、意図的に
#   止めたチェックと事故で止まったチェックが同じ見え方をする。実際に
#   codex-review が全実行skippedのまま検知されなかった(2026-09-03 実測)。
#   この検査は、事故による停止を「記録の無いスキップ」として赤にする。
#
# 対象期間の決め方(なぜ現在のGITHUB_RUN_IDを除外するのか):
#   自ワークフロー(audit-weekly.yaml)の実行一覧から現在のrunを除いた
#   直近runの created_at を下限にする(存在しなければ7日前)。実行一覧の
#   先頭は現在のrun自身のため、除外しないと下限が現在時刻になり、
#   検知が恒久的に空振りする。
#
# なぜ head.sha を使い merge_commit_sha を使わないのか:
#   このリポジトリはsquashマージのため、マージコミット側にはPRの必須
#   チェックのcheck-runsが存在しない。merge_commit_sha を走査すると
#   全PRが「実行なし=違反」の偽赤になる(必須チェックはすべて
#   GitHub Actionsのcheck-runsで報告されることを実測済み)。
#
# なぜ「最新の結論」ではなく「実行の証拠の有無」で判定するのか:
#   guardrails.yaml は pull_request_review イベントでも発火し、承認操作の
#   あったPRでは同一head SHAに skipped のcheck-runが追加で残る。最新の
#   結論で判定すると、実行済みのチェックが後発のskippedに上書きされて
#   偽赤になる。skipped以外の結論を持つcheck-runが1件でもあれば
#   「実行された」と判定する。
#
# なぜ判定不能を赤にするのか:
#   判定できないまま通すと、検査があるのに守られていない状態が静かに続く。
#   判定不能の赤は、失敗したrunのre-runで再判定する。新規のworkflow_dispatch
#   で流し直すと対象期間の下限が前へ進み、未走査の穴が空いて検知の窓が
#   狭まるため、報告文面でre-runを指示する。
#
# テスト: .github/scripts/tests/test-check-audit-skipped-required.sh
# 使い方: check-audit-skipped-required.sh <期待一覧(required-checks.json)のパス>
#   環境変数 GH_TOKEN(必須) / GITHUB_REPOSITORY(必須) / GITHUB_RUN_ID(必須)
#   NOW_EPOCH(テスト用の時刻固定)
# =====================================================================
set -Eeuo pipefail
# ガードしていないコマンドの失敗は、逸脱(1)ではなく判定不能(2)にする。
# -E で関数・コマンド置換の中の失敗にも適用する。
trap 'exit 2' ERR

# 引数・環境変数の欠落を ${n:?} に任せると終了コード1(逸脱あり)になるため、
# 明示的に検査して判定不能(2)に倒す。
if [ "$#" -lt 1 ] || [ -z "$1" ]; then
    echo "::error::引数は1個必要です: <期待一覧(required-checks.json)のパス>"
    exit 2
fi
if [ -z "${GITHUB_REPOSITORY:-}" ]; then
    echo "::error::環境変数 GITHUB_REPOSITORY が必要です"
    exit 2
fi
if [ -z "${GITHUB_RUN_ID:-}" ]; then
    echo "::error::環境変数 GITHUB_RUN_ID が必要です"
    exit 2
fi
if [ -z "${GH_TOKEN:-}" ]; then
    echo "::error::環境変数 GH_TOKEN が必要です"
    exit 2
fi

CHECKS_FILE="$1"
REPO="$GITHUB_REPOSITORY"
RUN_ID="$GITHUB_RUN_ID"

NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
# 7日窓の下限の算術展開に入るため、APIへ問い合わせる前に形を確かめる。
# 英字は未定義変数、先頭0は8進数として扱われ、算術展開の誤りになるか
# (010 のように)別の値として黙って通る。桁数が多すぎると64ビットを
# 溢れて折り返す。先頭0なし・12桁までに限る。
if ! [[ "$NOW_EPOCH" =~ ^[1-9][0-9]{0,11}$ ]]; then
    echo "::error::NOW_EPOCH はエポック秒(先頭0なし・12桁まで)で指定してください: ${NOW_EPOCH}"
    exit 2
fi
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
AUDIT_WORKFLOW_FILE="audit-weekly.yaml"

# 判定不能の報告と終了。API障害等の外部要因は同じrunの再実行で解消しうる。
report_undecidable() {
    local reason="$1"
    {
        echo "### :warning: 必須チェックの構成とスキップ状況を確認できませんでした(判定不能)"
        echo ""
        echo "$reason"
        echo ""
        echo "**成功に倒さず赤にしています。**"
        echo "失敗したこのrunをre-run(同じrunの再実行)してください。"
        echo "新規の手動実行(workflow_dispatch)で流し直すと、スキップ検知の対象期間に"
        echo "未走査の穴が空き、検知の窓が狭まります。"
        echo "繰り返し失敗する場合は期待一覧とAPIの応答を人間が確認してください。"
        echo ""
    } >>"$SUMMARY"
    echo "必須チェックの構成とスキップ状況を確認できませんでした(判定不能): ${reason}" >&2
    exit 2
}

# --- 期待一覧のスキーマ検証 ------------------------------------------------------
# 判定の基準となるデータが壊れていたら、照合にも走査にも進まず判定不能で
# 止める。欠落や未知の値を黙って読み飛ばすと、期待一覧の書き誤りが
# 「検査されないcontext」として静かに素通りするため、fail closed にする。
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

# --- 集合照合(3.4) -------------------------------------------------------------
# rulesetの実効ルール一覧から required_status_checks ルールの context を集める。
# 状態(active/paused)は使わず、名前の集合の双方向差分だけを見る。
rules_json=""
if ! rules_json=$(gh api "repos/${REPO}/rules/branches/main" 2>/dev/null); then
    report_undecidable "rulesetのAPIへの問い合わせに失敗しました。"
fi

# 応答が配列であること・required_status_checks ルールの中身が期待の形で
# あることを確かめてから使う。エラーメッセージのJSON(例: {"message":"Not
# Found"})を「必須チェックゼロ」と誤読しないため。
ruleset_contexts=""
if ! ruleset_contexts=$(printf '%s' "$rules_json" | jq -ce '
    if type == "array" then
        [.[] | select(.type? == "required_status_checks")] as $rules
        | if ([$rules[]
              | ((.parameters.required_status_checks? | type) == "array")
                and ([.parameters.required_status_checks[] | (.context? | type) == "string"] | all)
          ] | all)
          then ([$rules[].parameters.required_status_checks[].context] | unique)
          else empty end
    else empty end' 2>/dev/null); then
    report_undecidable "rulesetのAPIの応答を解釈できませんでした。"
fi

expected_contexts=$(jq -c '[.checks[].context] | unique' "$CHECKS_FILE") ||
    report_undecidable "期待一覧(${CHECKS_FILE})からcontext集合を作成できませんでした。"

only_expected=$(jq -nr --argjson a "$expected_contexts" --argjson b "$ruleset_contexts" '($a - $b) | join(", ")')
only_ruleset=$(jq -nr --argjson a "$expected_contexts" --argjson b "$ruleset_contexts" '($b - $a) | join(", ")')

set_diff_red=0
if [ -n "$only_expected" ] || [ -n "$only_ruleset" ]; then
    set_diff_red=1
    {
        echo "### :rotating_light: 期待一覧とrulesetの必須チェックが一致しません"
        echo ""
        if [ -n "$only_expected" ]; then
            echo "- 期待一覧のみに存在: ${only_expected}"
        fi
        if [ -n "$only_ruleset" ]; then
            echo "- rulesetのみに存在: ${only_ruleset}"
        fi
        echo ""
        echo "期待一覧(\`.github/audit/required-checks.json\`)とGitHub側のruleset設定の"
        echo "どちらが正かを人間が判断し、乖離を解消してください。"
        echo ""
    } >>"$SUMMARY"
    echo "期待一覧とrulesetの必須チェックが一致しません。" >&2
    if [ -n "$only_expected" ]; then echo "期待一覧のみに存在: ${only_expected}" >&2; fi
    if [ -n "$only_ruleset" ]; then echo "rulesetのみに存在: ${only_ruleset}" >&2; fi
fi

# --- 対象期間の決定(3.5) -------------------------------------------------------
# 自ワークフローの実行一覧から現在のrunを除いた直近runの created_at を下限に
# する。除外しないと下限が現在時刻になり、検知が恒久的に空振りする。
# 前回runが無ければ(初回・履歴消失)7日前を下限にする。
wfruns_json=""
if ! wfruns_json=$(gh api \
    "repos/${REPO}/actions/workflows/${AUDIT_WORKFLOW_FILE}/runs?per_page=100" 2>/dev/null); then
    report_undecidable "自ワークフローの実行一覧APIへの問い合わせに失敗しました。"
fi

prev_created=""
if ! prev_created=$(printf '%s' "$wfruns_json" | jq -er --arg rid "$RUN_ID" '
    if (.workflow_runs | type) == "array"
       and ([.workflow_runs[] | ((.id? | type) == "number") and ((.created_at? | type) == "string")] | all)
    then ([.workflow_runs[] | select((.id | tostring) != $rid)]
          | if length == 0 then "none" else (max_by(.created_at) | .created_at) end)
    else empty end' 2>/dev/null); then
    report_undecidable "自ワークフローの実行一覧APIの応答を解釈できませんでした。"
fi

if [ "$prev_created" = "none" ]; then
    boundary=$(date -u -d "@$((NOW_EPOCH - 7 * 86400))" +%Y-%m-%dT%H:%M:%SZ)
    window_desc="直近7日間(前回の週次監査の実行なし。${boundary} 以降)"
else
    date -u -d "$prev_created" +%s >/dev/null 2>&1 ||
        report_undecidable "前回実行の日時の書式を解釈できません: ${prev_created}"
    boundary="$prev_created"
    window_desc="前回の週次監査の実行(${boundary})以降"
fi

# --- 対象期間内にマージされたPRの取得 --------------------------------------------
# state=closed base=main で取得し、merged_at で絞る(merged_at が null の
# PRはマージされずcloseされたもので対象外)。GitHubのタイムスタンプは同一
# 書式のUTC(...Z)のため、下限との比較は文字列比較で行える。
# --paginate は100件を超えても取りこぼさないため。応答はページごとのJSON
# 配列の連続になるため、slurpして連結する。
pulls_json=""
if ! pulls_json=$(gh api --paginate "repos/${REPO}/pulls?state=closed&base=main&per_page=100" 2>/dev/null); then
    report_undecidable "PR一覧APIへの問い合わせに失敗しました。"
fi

pulls_list=""
if ! pulls_list=$(printf '%s' "$pulls_json" | jq -ces --arg boundary "$boundary" '
    if all(type == "array") then
        (add // [])
        | if all(((.number? | type) == "number") and ((.head.sha? | type) == "string")) then
              map(select(((.merged_at? | type) == "string") and (.merged_at >= $boundary)))
              | map({number: .number, sha: .head.sha})
          else empty end
    else empty end' 2>/dev/null); then
    report_undecidable "PR一覧APIの応答を解釈できませんでした。"
fi

# --- PRごとのスキップ走査(3.6-3.8) ----------------------------------------------
# 判定に使うcontextは mode: always のみ(conditional のスキップは変更検知に
# よる正当なもの=3.8)。always は state で違反(active)と停止中報告
# (paused)に分ける。
always_active=$(jq -c '[.checks[] | select(.mode == "always" and .state == "active") | .context]' "$CHECKS_FILE")
paused_map=$(jq -c '[.checks[] | select(.mode == "always" and .state == "paused")
    | {key: .context, value: .issue}] | from_entries' "$CHECKS_FILE")

violation_report=""
paused_report=""
pr_count=$(jq 'length' <<<"$pulls_list")

i=0
while [ "$i" -lt "$pr_count" ]; do
    number=$(jq -r ".[$i].number" <<<"$pulls_list")
    sha=$(jq -r ".[$i].sha" <<<"$pulls_list")

    # headコミットのcheck-runsを取得する。per_page=100 は必須チェック数+
    # イベント多重発火分に対して十分な余裕がある(APIの既定 filter=latest が
    # 同一スイート内の再実行を畳むため、通常はcontext数+α件しか返らない)。
    runs_json=""
    if ! runs_json=$(gh api "repos/${REPO}/commits/${sha}/check-runs?per_page=100" 2>/dev/null); then
        report_undecidable "PR #${number} のcheck-runs APIへの問い合わせに失敗しました。"
    fi

    # 「実行の証拠」= skipped以外の結論を持つcheck-runが1件でもあること。
    # 証拠の無い always+active は違反、always+paused は停止中として報告。
    result_json=""
    if ! result_json=$(printf '%s' "$runs_json" | jq -ce \
        --argjson active "$always_active" --argjson paused "$paused_map" '
        if (.check_runs | type) == "array" then
            ([.check_runs[]
              | select(((.name? | type) == "string")
                       and ((.conclusion? | type) == "string")
                       and (.conclusion != "skipped"))
              | .name] | unique) as $executed
            | {
                violations: ([$active[] | select(. as $c | $executed | index($c) | not)] | sort),
                paused: ([$paused | to_entries[]
                          | select(.key as $c | $executed | index($c) | not)
                          | "\(.key)(停止中: #\(.value))"] | sort)
              }
        else empty end' 2>/dev/null); then
        report_undecidable "PR #${number} のcheck-runs APIの応答を解釈できませんでした。"
    fi

    violated_names=$(jq -r '.violations | join(", ")' <<<"$result_json")
    paused_names=$(jq -r '.paused | join(", ")' <<<"$result_json")

    if [ -n "$violated_names" ]; then
        violation_report="${violation_report}- #${number}: ${violated_names}"$'\n'
    fi
    if [ -n "$paused_names" ]; then
        paused_report="${paused_report}- #${number}: ${paused_names}"$'\n'
    fi

    i=$((i + 1))
done

# --- 報告 -----------------------------------------------------------------------
# 停止中スキップの一覧は判定結果にかかわらず常時出力する。記録された停止は
# ここに現れ続け、記録の無い停止は違反の赤で現れる(記録の有無で見分ける)。
emit_scope_and_paused_sections() {
    {
        echo "#### スキップ検知の対象期間"
        echo ""
        echo "- ${window_desc}(対象のマージ済みPR: ${pr_count}件)"
        echo ""
        echo "#### 停止中と記録されている必須チェックのスキップ"
        echo ""
        if [ -n "$paused_report" ]; then
            printf '%s' "$paused_report"
            echo ""
            echo "期待一覧で停止中と記録されているため、違反とは扱いません。"
            echo "停止が長引いている場合は、参照Issueの状況を人間が確認してください。"
        else
            echo "- なし"
        fi
        echo ""
    } >>"$SUMMARY"
}

if [ -n "$violation_report" ]; then
    {
        echo "### :rotating_light: 必須チェックがスキップのままマージされたPRがあります"
        echo ""
        printf '%s' "$violation_report"
        echo ""
        echo "常時実行されるべきチェックが、実行されないままマージされています。"
        echo "スキップの原因(設定・変数・ワークフローの故障)を確認し、"
        echo "\`doc/開発フロー/監査手順.md\` の手順で対処してください。"
        echo ""
    } >>"$SUMMARY"
    emit_scope_and_paused_sections
    echo "必須チェックがスキップのままマージされたPRがあります:" >&2
    printf '%s' "$violation_report" >&2
    exit 1
fi

emit_scope_and_paused_sections

if [ "$set_diff_red" -ne 0 ]; then
    exit 1
fi

echo "必須チェックの集合は一致し、スキップのままマージされたPRはありません(対象PR: ${pr_count}件)。"
exit 0
