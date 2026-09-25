#!/usr/bin/env bash
# =====================================================================
# カナリア点検の照合(canary-verify CI から実行)
#
# 当月のカナリアPR6件について、種別ごとに定義された期待チェックの結論を
# 3値で照合する:
#   failure            → 正常(検査が問題を検知した)
#   success            → 実行されたが検知しなかった(判定側の故障)= 失敗
#   skipped・実行なし  → 検査が実行されていない = 失敗(故障と区別して報告)
# いずれかの種別が失敗判定なら exit 1(逸脱あり)。全種別が正常または
# 停止中(記録済み)なら exit 0(逸脱なし)。全種別の判定一覧は判定結果に
# かかわらず常にJob Summaryへ出力する。
#
# 終了コード:
#   0 = 逸脱なし / 1 = 逸脱あり / 2 = 判定不能
#   1 は失敗判定の種別(判定側の故障・実行されていない・想定外の結論・
#   PR欠落。6件そろっていない場合を含む)を報告したうえでの明示的な exit 1
#   だけが返す。引数・必須環境変数の欠落、対象年月の書式不正、ガードして
#   いないコマンドの想定外の失敗もすべて 2 に倒す。1 に混ぜると、判定が
#   一度も完了していないのに「逸脱あり」として扱われる。
#
# 種別→期待チェックの対応(生成側 create-canary-prs.sh の6種と対):
#   known-bug       → codex-review
#   assertless-test → frontend-test
#   skipped-test    → escape-hatch
#   backend-failure → backend-test
#   vulnerable-dep  → dependency-review
#   container-vuln  → container-scan
#
# PRの特定はブランチ名 canary/<type>-<YYYYMM>(生成側の命名)で行う。
# state=all で検索し、closeされたカナリアPRでも照合できるようにする。
# PRが見つからない種別は「PR欠落」として失敗。6件揃わない場合は生成側
# (create-canary-prs.sh)の異常である旨を明記する。
#
# 期待チェックが期待一覧(required-checks.json)で paused と記録されている
# 種別は、失敗と区別して「停止中(記録済み・参照Issue)」として報告する。
# 記録の無い停止は「実行されていない」の赤で見え続ける(記録の有無で
# 意図的な停止と事故による停止を見分ける)。
#
# 期待一覧に存在しない期待チェックは「稼働中」とみなして3値判定する。
# 期待一覧は必須チェックの写しであり、container-scan は必須チェック未登録
# (Issue #221 の解消待ち)のため一覧に無いのが正常。一覧へ足すと週次の
# 集合照合が毎週赤になるため、データ側でなくこの契約で吸収する。
#
# なぜ「最新の結論」で判定するのか:
#   guardrails.yaml 等は複数イベントで発火し、同一head SHAに skipped の
#   check-runが追加で残ることがある。skipped以外の結論を持つcheck-run
#   (=実行の証拠)のうち最新のものの結論で判定し、後発のskippedによる
#   偽判定を防ぐ。全てskippedまたは1件も無ければ「実行されていない」。
#
# なぜ判定不能を逸脱なしにしないのか:
#   判定できないまま通すと、ゲートの故障が翌月まで見えない。API失敗・
#   スキーマ不正は判定不能として exit 2(fail closed)。週次と違い対象
#   期間の窓が無いため、復旧はre-runでも新規のworkflow_dispatchでもよい。
#
# 書き込みAPI・PR操作(close・コメント等)は一切行わない(判定と報告のみ)。
#
# テスト: .github/scripts/tests/test-check-canary-results.sh
# 使い方: check-canary-results.sh <期待一覧(required-checks.json)のパス> [対象年月(YYYYMM。既定: 実行時のUTC年月)]
#   環境変数 GH_TOKEN(必須) / GITHUB_REPOSITORY(必須)
# =====================================================================
set -Eeuo pipefail
# ガードしていないコマンドの失敗は、逸脱(1)ではなく判定不能(2)にする。
# -E で関数・コマンド置換の中の失敗にも適用する。
trap 'exit 2' ERR

# 引数・環境変数の欠落を ${n:?} に任せると終了コード1(逸脱あり)になるため、
# 明示的に検査して判定不能(2)に倒す。
if [ "$#" -lt 1 ] || [ -z "$1" ]; then
    echo "::error::引数が必要です: <期待一覧(required-checks.json)のパス> [対象年月(YYYYMM)]"
    exit 2
fi
if [ -z "${GITHUB_REPOSITORY:-}" ]; then
    echo "::error::環境変数 GITHUB_REPOSITORY が必要です"
    exit 2
fi
if [ -z "${GH_TOKEN:-}" ]; then
    echo "::error::環境変数 GH_TOKEN が必要です"
    exit 2
fi

CHECKS_FILE="$1"
TARGET_MONTH="${2:-$(date -u +%Y%m)}"
REPO="$GITHUB_REPOSITORY"

OWNER="${REPO%%/*}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# 種別→期待チェックの対応表(スクリプト内定数。生成側の6種と一致させる)
CANARY_TYPES="known-bug assertless-test skipped-test backend-failure vulnerable-dep container-vuln"
expected_check_of() {
    case "$1" in
    known-bug) echo "codex-review" ;;
    assertless-test) echo "frontend-test" ;;
    skipped-test) echo "escape-hatch" ;;
    backend-failure) echo "backend-test" ;;
    vulnerable-dep) echo "dependency-review" ;;
    container-vuln) echo "container-scan" ;;
    *) return 1 ;;
    esac
}

# 判定不能の報告と終了。API障害等の外部要因は再実行で解消しうる。
# 週次のスキップ検知と違い対象期間の窓が無いため、re-runでも新規の
# workflow_dispatchでもよい。
report_undecidable() {
    local reason="$1"
    {
        echo "### :warning: カナリア点検の結果を照合できませんでした(判定不能)"
        echo ""
        echo "$reason"
        echo ""
        echo "**成功に倒さず赤にしています。**"
        echo "失敗したこのrunのre-run、またはworkflow_dispatchでの再実行で再判定してください。"
        echo "繰り返し失敗する場合は期待一覧とAPIの応答を人間が確認してください。"
        echo ""
    } >>"$SUMMARY"
    echo "カナリア点検の結果を照合できませんでした(判定不能): ${reason}" >&2
    exit 2
}

# --- 引数の検証 -----------------------------------------------------------------
# 対象年月はブランチ名に入る。6桁でも月が 01〜12 でなければ(202613 等)
# 存在しないブランチを探して全種別がPR欠落(逸脱)に化けるため、先に弾く。
if ! [[ "$TARGET_MONTH" =~ ^[0-9]{4}(0[1-9]|1[0-2])$ ]]; then
    report_undecidable "対象年月の書式が不正です(YYYYMM を期待): ${TARGET_MONTH}"
fi

# --- 期待一覧のスキーマ検証 ------------------------------------------------------
# 判定の基準となるデータが壊れていたら、照合に進まず判定不能で止める。
# スキーマは required-checks.json の定義(週次の検査スクリプトと同一)。
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

# 停止中と記録されたcontext→参照Issueの対応。一覧に無いcontextはここに
# 現れず、「稼働中」として3値判定される。
paused_map=$(jq -c '[.checks[] | select(.state == "paused")
    | {key: .context, value: .issue}] | from_entries' "$CHECKS_FILE")

# --- 種別ごとの照合(5.1-5.4/5.8) ------------------------------------------------
rows=""
fail_report=""
found_count=0
has_paused=0

for type in $CANARY_TYPES; do
    expected=$(expected_check_of "$type")
    branch="canary/${type}-${TARGET_MONTH}"

    # ブランチ名でPRを検索する。state=all はcloseされたカナリアPRでも照合
    # できるようにするため(openのまま残る運用だが、closeに依存しない)。
    prs_json=""
    if ! prs_json=$(gh api "repos/${REPO}/pulls?head=${OWNER}:${branch}&state=all&per_page=10" 2>/dev/null); then
        report_undecidable "カナリアPRの検索APIへの問い合わせに失敗しました(${branch})。"
    fi

    # 同一ブランチにPRが複数ある場合(作り直し等)は最新(番号最大)を採る。
    pr_info=""
    if ! pr_info=$(printf '%s' "$prs_json" | jq -ce '
        if type == "array"
           and ([.[] | ((.number? | type) == "number") and ((.head.sha? | type) == "string")] | all)
        then (if length == 0 then {found: false}
              else (max_by(.number) | {found: true, number: .number, sha: .head.sha}) end)
        else empty end' 2>/dev/null); then
        report_undecidable "カナリアPRの検索APIの応答を解釈できませんでした(${branch})。"
    fi

    # 取り出しを代入に分けるのは、失敗を ERR トラップ(判定不能)に通すため。
    # 比較の引数の中で置換すると、失敗が空文字として比較に流れ、PR欠落の
    # 逸脱に化ける。
    found=$(jq -r '.found' <<<"$pr_info")
    if [ "$found" != "true" ]; then
        rows="${rows}| ${type} | ${expected} | :rotating_light: PR欠落(ブランチ ${branch} のPRが見つからない) |"$'\n'
        fail_report="${fail_report}- ${type}: PR欠落(${branch})"$'\n'
        continue
    fi
    found_count=$((found_count + 1))
    number=$(jq -r '.number' <<<"$pr_info")
    sha=$(jq -r '.sha' <<<"$pr_info")

    # 期待チェックが停止中と記録されていれば、結論を見ずに「停止中」とする。
    # 判定は承認された記録で決まり、失敗とは区別する(5.8)。
    paused_issue=$(jq -r --arg c "$expected" '.[$c] // empty' <<<"$paused_map")
    if [ -n "$paused_issue" ]; then
        rows="${rows}| ${type} | ${expected} | :pause_button: 停止中(記録済み・#${paused_issue}) |"$'\n'
        has_paused=1
        continue
    fi

    # headコミットのcheck-runsから、期待チェックの最新の結論を取り出す。
    runs_json=""
    if ! runs_json=$(gh api "repos/${REPO}/commits/${sha}/check-runs?per_page=100" 2>/dev/null); then
        report_undecidable "PR #${number} のcheck-runs APIへの問い合わせに失敗しました。"
    fi

    conclusion=""
    if ! conclusion=$(printf '%s' "$runs_json" | jq -cer --arg name "$expected" '
        if (.check_runs | type) == "array" then
            ([.check_runs[]
              | select(((.name? | type) == "string") and (.name == $name)
                       and ((.conclusion? | type) == "string")
                       and (.conclusion != "skipped"))]
             | sort_by(.started_at // "")
             | if length == 0 then "none" else (last | .conclusion) end)
        else empty end' 2>/dev/null); then
        report_undecidable "PR #${number} のcheck-runs APIの応答を解釈できませんでした。"
    fi

    case "$conclusion" in
    failure)
        rows="${rows}| ${type} | ${expected} | :white_check_mark: 正常(検査が問題を検知した。PR #${number}) |"$'\n'
        ;;
    success)
        rows="${rows}| ${type} | ${expected} | :rotating_light: 実行されたが検知しなかった(判定側の故障。PR #${number}) |"$'\n'
        fail_report="${fail_report}- ${type}: ${expected} が success(判定側の故障。PR #${number})"$'\n'
        ;;
    none)
        rows="${rows}| ${type} | ${expected} | :rotating_light: 検査が実行されていない(skippedまたは実行なし。PR #${number}) |"$'\n'
        fail_report="${fail_report}- ${type}: ${expected} が実行されていない(PR #${number})"$'\n'
        ;;
    *)
        # 3値のいずれでもない結論(cancelled等)。成功に倒さず赤にする。
        rows="${rows}| ${type} | ${expected} | :rotating_light: 想定外の結論(${conclusion}。PR #${number}) |"$'\n'
        fail_report="${fail_report}- ${type}: ${expected} が想定外の結論 ${conclusion}(PR #${number})"$'\n'
        ;;
    esac
done

# --- 報告(5.5/5.6) -------------------------------------------------------------
# 判定一覧は結果にかかわらず常に出力する。
{
    if [ -n "$fail_report" ]; then
        echo "### :rotating_light: カナリア点検で期待どおりに赤にならなかった種別があります(対象: ${TARGET_MONTH})"
    else
        echo "### カナリア点検の照合結果(対象: ${TARGET_MONTH})"
    fi
    echo ""
    echo "| 種別 | 期待チェック | 判定 |"
    echo "|---|---|---|"
    printf '%s' "$rows"
    echo ""
    if [ "$found_count" -lt 6 ]; then
        echo "カナリアPRが6件揃っていません(見つかったのは ${found_count}件)。"
        echo "**生成側(create-canary-prs.sh / 毎月1日の自動生成)の異常です。**"
        echo "生成ワークフローの実行結果を人間が確認してください。"
        echo ""
    fi
    if [ -n "$fail_report" ]; then
        echo "検査が検知できていない(または実行されていない)ゲートがあります。"
        echo "\`doc/開発フロー/監査手順.md\` の手順で原因を調査してください。"
        echo ""
    fi
    if [ "$has_paused" -ne 0 ]; then
        echo "停止中(記録済み)の種別は、期待一覧の承認された記録に基づき失敗と区別しています。"
        echo "停止が長引いている場合は、参照Issueの状況を人間が確認してください。"
        echo ""
    fi
} >>"$SUMMARY"

if [ -n "$fail_report" ]; then
    echo "カナリア点検で期待どおりに赤にならなかった種別があります:" >&2
    printf '%s' "$fail_report" >&2
    exit 1
fi

echo "カナリア6件すべてが期待どおりの判定でした(対象: ${TARGET_MONTH})。"
exit 0
