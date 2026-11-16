#!/usr/bin/env bash
# =====================================================================
# main の最新に合わせる PR を選ぶ(update-pr-branches.yaml から実行)
#
# 判定: 開いている main 向けの PR のうち、次をすべて満たすものの番号を出す。
#   1. 対象の PR である(TARGET_FILTER の式。下書き・fork・カナリアPRを除く)
#   2. HEAD_SHA があるときは、最新のコミットが HEAD_SHA である
#   3. 最新のコミットで、数える検査がすべて通っている
#   4. main より古い
#
# 数える検査: 期待一覧(.github/audit/required-checks.json)のうち、state が active で
#   approval_gated が false の検査。同じ名前の結果が複数あるときは、最後に作られたものを読む。
#   結果が success・skipped・neutral なら通ったと数える。結果が無い・実行中・赤は通っていない。
#
# なぜ検査が通った PR だけを選ぶか:
#   main を取り込むと PR の検査が最初からやり直しになる。検査の途中や赤の PR は、取り込んでも
#   マージされないので、やり直しが無駄になる(#889)。検査が通ってから取り込めば、やり直しは
#   マージの直前の1回で済む。「main の最新を取り込んだ状態で検査を通った PR だけがマージ
#   される」決まりは、ブランチ保護が守る。
#
# なぜ承認で結果が変わる検査(approval_gated)を数えないか:
#   所有者の承認を待つ PR では、承認までこれらの検査が赤のままになる。承認のあとに取り込むと
#   承認が外れ、所有者が承認し直すことになる。承認の前に取り込んでおくため、数えない。
#
# 判定できない PR(問い合わせの失敗、応答の形が想定と違う)は選ばず、終了コード 1 にする。
# 選ばれなかった PR は古いまま残りマージされないので、誤って取り込まれることはない。
#
# テスト: .github/scripts/tests/test-select-prs-to-update.sh
# 使い方: select-prs-to-update.sh
#   環境変数(必須): GH_TOKEN / REPO(<所有者>/<名前>。TARGET_FILTER の式も読む)/
#                   TARGET_FILTER(PR 1件に当てる jq の式)
#   環境変数(任意): HEAD_SHA(このコミットが最新の PR だけを見る)
#                   REQUIRED_CHECKS_FILE(期待一覧の場所。テストで差し替える)
# 出力: 標準出力に、合わせる PR の番号を1行に1つ出す。経過と理由は標準エラーに出す。
# 終了コード: 0 = すべての PR を判定した / 1 = 判定できない PR がある、環境変数の不足
# =====================================================================
set -euo pipefail

die() {
    echo "::error::$1" >&2
    exit 1
}

log() {
    echo "$1" >&2
}

for v in GH_TOKEN REPO TARGET_FILTER; do
    [ -n "${!v:-}" ] || die "環境変数 ${v} が必要です。"
done
export REPO HEAD_SHA="${HEAD_SHA:-}"
[ -z "$HEAD_SHA" ] || [[ "$HEAD_SHA" =~ ^[0-9a-f]{40,64}$ ]] || die "HEAD_SHA がコミットの形ではありません: '${HEAD_SHA}'"
command -v jq >/dev/null 2>&1 || die "jq が見つかりません。"
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || die "スクリプトの場所を特定できません。"
CHECKS_FILE="${REQUIRED_CHECKS_FILE:-${SELF_DIR}/../audit/required-checks.json}"

# 欄の欠けた行を「数えない検査」と読むと、通っていない PR を選んでしまう。形が違えば失敗にする。
required=$(jq -c '.checks
    | if type == "array" and all(.[]; (.context | type) == "string" and (.state | type) == "string" and (.approval_gated | type) == "boolean")
      then map(select(.state == "active" and .approval_gated == false) | .context) else error("期待一覧の形が想定と違う") end
    | if length > 0 then . else error("数える検査が無い") end' "$CHECKS_FILE") || die "期待一覧を読めません: ${CHECKS_FILE}"

# --paginate には --slurp を併用する(ページ単位で jq が適用され判定を誤るため)。
pulls=$(gh api "repos/${REPO}/pulls?state=open&base=main&per_page=100" --paginate --slurp) || die "開いている PR の一覧を取れませんでした。"
candidates=$(jq -er "if type == \"array\" then . else error(\"一覧が配列でない\") end
    | [.[][] | ${TARGET_FILTER} | select(env.HEAD_SHA == \"\" or .head.sha == env.HEAD_SHA) | \"\(.number) \(.head.sha)\"] | join(\"\n\")" <<<"$pulls") ||
    die "開いている PR の一覧の応答の形が想定と違います。"

failed=0
undecidable() {
    log "::warning::#$1 を判定できませんでした: $2"
    failed=$((failed + 1))
}

# 一覧は fd 3 から読み、gh には標準入力を渡さない。
while read -r n sha <&3; do
    [ -n "$n" ] || continue
    if ! runs=$(gh api "repos/${REPO}/commits/${sha}/check-runs?per_page=100" --paginate --slurp </dev/null); then
        undecidable "$n" "検査の結果を取れない"
        continue
    fi
    # 通っていない検査の名前を「、」でつないで出す。応答が空のときは jq が何も出さず、
    # 「通っていない検査が無い」と読めてしまうため、-e で失敗にする。
    if ! pending=$(jq -er --argjson required "$required" '[.[].check_runs[]] as $runs
        | $required
        | map(. as $c | ($runs | map(select(.name == $c)) | max_by(.id)) as $r
            | select($r == null or $r.status != "completed" or ($r.conclusion | IN("success", "skipped", "neutral") | not)))
        | join("、")' <<<"$runs"); then
        undecidable "$n" "検査の結果の応答の形が想定と違う"
        continue
    fi
    if [ -n "$pending" ]; then
        log "#${n}: 検査が通っていないため、合わせません(${pending})"
        continue
    fi
    if ! behind=$(gh api "repos/${REPO}/compare/main...${sha}" </dev/null |
        jq -er '.behind_by | if type == "number" then . else error("behind_by が数でない") end'); then
        undecidable "$n" "main より古いかを調べられない"
        continue
    fi
    if [ "$behind" -eq 0 ]; then
        log "#${n}: すでに最新です"
        continue
    fi
    log "#${n}: 検査が通っていて main より古いため、合わせます"
    echo "$n"
done 3<<<"$candidates"

[ "$failed" -eq 0 ] || die "${failed} 件の PR を判定できませんでした。"
