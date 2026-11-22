#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix の prepare ジョブで、対象を読み直し、作業の起点のコードを作るスクリプト
# (design.md の claude-auto-fix-prepare.sh の節)
#
# 使い方: claude-auto-fix-prepare.sh <kind> <key> <reason> <pr>
#   kind   npm maven go-stdlib go-module codeql container dependabot
#   reason trigger manual retry red-check
#   pr     red-check では Claude の変更の PR の番号。そのほかは使わない(種類 dependabot の PR は key で読む)
#
# 今のフォルダは、このリポジトリの履歴をすべて持つ clone にする(checkout の fetch-depth: 0)。
# このスクリプトは、origin から実行の時点の main と、種類が dependabot のときは
# refs/pull/<番号>/head を取り込む。公開のリポジトリなので、取り込みにトークンは要らない。
#
# 環境変数:
#   RUNNER_TEMP          base.patch と一時のファイルを書くフォルダ(必須)
#   GITHUB_REPOSITORY    読むリポジトリ(owner/name。必須)
#   GH_TOKEN             gh が使うトークン(読むだけ。check-audit-dependabot-stuck.sh も求める)
#   TRIVY_RESULTS_DIR    種類が container のとき、main から作った2つのイメージの trivy-java.json と
#                        trivy-go.json のフォルダ(必須)
#   CAF_REQUIRED_CHECKS  期待一覧のファイル(既定は .github/audit/required-checks.json)
#   CAF_SUPPRESSIONS     コンテナの脆弱性の抑制の記録(既定は .github/container-scan-suppressions.json)
#
# 標準出力には、止めるときは次の2行だけを書く。
#   outcome=<skipped|gone>
#   cause=<理由の種類>
# 理由の種類:
#   skipped claude-pr-open    同じ key の Claude の変更の PR が開いている(red-check のほか)
#           pr-not-open       red-check で、その番号の Claude の変更の PR が開いていない
#           unfixed-issue     reason が trigger か retry で、状態が unfixed の知らせの Issue が開いている
#           not-stuck         dependabot で、PR が止まった PR の一覧に無い
#           no-fixable-check  dependabot で、直しても緑にならない5つの検査を除くと赤の検査が残らない
#           head-moved        dependabot で red-check でないとき、取り込んだ PR の head が、検査を読んだ head と違う
#           merge-conflict    dependabot で red-check でないとき、PR の head を main にマージするとぶつかる
# 知らせの Issue で止めるのは、reason が trigger か retry のときだけにする。requirements.md の要件4の4が
# 止めるのは要件1の1から4の4つのきっかけだけで、要件2の4の red-check は入らないためである。
# red-check も止めると、所有者が手で動かして作った PR が赤になったときに、Claude がその赤を直せない。
#   gone    target-gone       対象が消えた(design.md の「対象が消えたかの見分け方」の表)
#           gone-on-main      container で、main から作ったイメージに脆弱性の ID が無い。
#                             report ジョブが、ラベル container-vuln の Issue にコメントを書く
# 止めないときは、次の行を書く。
#   main_sha=<実行の時点の main のコミットの SHA>
#   base_sha=<red-check では PR の head のコミットの SHA、そのほかは main_sha>
#   base_sha256=<base.patch の SHA-256>
#   base_patch=<base.patch の場所($RUNNER_TEMP/claude-auto-fix-base.patch)>
#   checks=<赤の検査の名前の JSON の配列>(種類が dependabot で、reason が red-check でないときだけ)
# 起点のコードは、red-check では Claude の変更の PR の head のコミット(base_sha)で、base.patch は空にする。
# red-check の赤の検査は、Claude の変更の PR のもので、workflow の入力 checks で渡るので、checks を出さない。
# red-check でないときは、base.patch は起点のコードと main_sha の差である。種類が dependabot のときは、
# main に Dependabot の PR の head をマージしたコードとの差で、Dependabot の版上げが入る。そのほかは空にする。
#
# このスクリプトは GitHub の中身を読むだけで、変えない。
# 引数と環境の誤りは 2 で終わる。API が失敗したときと、判定できないときは 1 で終わる。
# =====================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/lib-claude-auto-fix.sh
. "$HERE/lib-claude-auto-fix.sh"

usage() {
    echo "::error::claude-auto-fix-prepare: $1" >&2
    echo "使い方: claude-auto-fix-prepare.sh <kind> <key> <reason> <pr>" >&2
    exit 2
}
fail() {
    echo "::error::claude-auto-fix-prepare: $1" >&2
    exit 1
}
stop() {
    printf 'outcome=%s\ncause=%s\n' "$1" "$2"
    exit 0
}
is_sha() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }

[ $# -eq 4 ] || usage "引数は4つです(${#}個でした)"
KIND="$1" KEY="$2" REASON="$3" PR="$4"
case "$KIND" in
npm | maven | go-stdlib | go-module | codeql | container | dependabot) ;;
*) usage "知らない種類です: ${KIND}" ;;
esac
case "$REASON" in
trigger | manual | retry | red-check) ;;
*) usage "知らない reason です: ${REASON}" ;;
esac
target_names "$KIND" "$KEY" >/dev/null || usage "key の形が違います"
if [ "$REASON" = red-check ] && ! [[ "$PR" =~ ^[1-9][0-9]*$ ]]; then
    usage "red-check の PR の番号の形が違います"
fi
[ -n "${RUNNER_TEMP:-}" ] && [ -d "$RUNNER_TEMP" ] || usage "RUNNER_TEMP のフォルダがありません"
REPO=$(_caf_repo) || usage "GITHUB_REPOSITORY がありません"
REQUIRED="${CAF_REQUIRED_CHECKS:-$HERE/../audit/required-checks.json}"
[ -f "$REQUIRED" ] || usage "期待一覧がありません: ${REQUIRED}"
SUPPRESSIONS="${CAF_SUPPRESSIONS:-$HERE/../container-scan-suppressions.json}"
if [ "$KIND" = container ]; then
    [ -n "${TRIVY_RESULTS_DIR:-}" ] && [ -d "$TRIVY_RESULTS_DIR" ] || usage "TRIVY_RESULTS_DIR のフォルダがありません"
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || usage "今のフォルダが Git のリポジトリではありません"
# 履歴の浅い clone では、main と PR の head の共通の祖先が無く、マージを作れない
[ "$(git rev-parse --is-shallow-repository)" = false ] || usage "履歴の浅い clone です(checkout を fetch-depth: 0 にします)"

PATCH="$RUNNER_TEMP/claude-auto-fix-base.patch"
rm -f -- "$PATCH"
TMP=$(mktemp -d "$RUNNER_TEMP/claude-auto-fix-prepare.XXXXXX") || fail "一時のフォルダを作れません"
trap 'rm -rf -- "$TMP"' EXIT

# --- 同じ key の Claude の変更の PR -----------------------------------------------
pr_json=$(claude_pr "$KIND" "$KEY") || fail "Claude の変更の PR を読めません"
BASE_SHA=""
if [ "$REASON" = red-check ]; then
    # red-check は、赤の検査を直す PR が開いていることを求める
    [ -n "$pr_json" ] && [ "$(jq -r .number <<<"$pr_json")" = "$PR" ] || stop skipped pr-not-open
    BASE_SHA=$(jq -r .head_sha <<<"$pr_json")
    is_sha "$BASE_SHA" || fail "PR #${PR} の head の SHA の形が違います"
else
    [ -z "$pr_json" ] || stop skipped claude-pr-open
fi

# --- 直せなかったことの知らせ ---------------------------------------------------------
# 知らせの Issue は、github-actions[bot] が起票し、本文に同じ key の目印を持つ、開いている Issue である。
# 状態は、本文とコメントの github-actions[bot] が書いた目印のうち最も新しいもので決まる
if [ "$REASON" = trigger ] || [ "$REASON" = retry ]; then
    issues=$(gh api --paginate --slurp "repos/${REPO}/issues?labels=${CAF_LABEL}&state=open&per_page=100") ||
        fail "ラベル ${CAF_LABEL} の Issue を読めません"
    numbers=$(jq -r --arg bot "$CAF_BOT_LOGIN" --arg mark "claude-auto-fix-issue key=${KIND}:${KEY} " "$_CAF_JQ_PAGES"'
        pages
        | .[] | select((has("pull_request") | not) and (.user.login? // "") == $bot
            and ((.body // "") | type) == "string" and ((.body // "") | contains($mark)))
        | .number | tostring' <<<"$issues" 2>/dev/null) || fail "ラベル ${CAF_LABEL} の Issue の形が違います"
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        [[ "$n" =~ ^[1-9][0-9]*$ ]] || fail "Issue の番号の形が違います"
        comments=$(gh api --paginate --slurp "repos/${REPO}/issues/${n}/comments?per_page=100") ||
            fail "Issue #${n} のコメントを読めません"
        # latest_marker は created_at が同じ項目を渡した順に並べるので、本文を先に、コメントを後ろに並べる
        list=$(jq -c --argjson n "$n" --slurpfile issues <(printf '%s' "$issues") "$_CAF_JQ_PAGES"'
            ($issues[0] | pages | map(select(.number == $n))[0:1]) + pages' <<<"$comments" 2>/dev/null) ||
            fail "Issue #${n} のコメントの形が違います"
        state=$(issue_state "$KIND" "$KEY" <<<"$list") || fail "Issue #${n} の状態を読めません"
        [ "$state" != unfixed ] || stop skipped unfixed-issue
    done <<<"$numbers"
fi

# --- 対象が消えたか -------------------------------------------------------------------
gone=$(target_gone "$KIND" "$KEY" "$REQUIRED") || fail "対象が消えたかを読めません"
case "$gone" in
true) stop gone target-gone ;;
false) ;;
*) fail "対象が消えたかの判定が true でも false でもありません" ;;
esac

# --- 種類ごとの読み直し ---------------------------------------------------------------
CHECKS=""
MERGE_HEAD=""
case "$KIND" in
dependabot)
    # 止まった PR の一覧で、その PR の実行の時点の赤の検査を読み直す。
    # 一覧のほかの報告は、prepare ジョブのまとめに書かない(標準出力は標準エラーに回す)
    rc=0
    STUCK_JSON_OUT="$TMP/stuck.json" GITHUB_STEP_SUMMARY=/dev/null \
        bash "$HERE/check-audit-dependabot-stuck.sh" "$REQUIRED" >&2 || rc=$?
    case "$rc" in
    0 | 1) ;;
    *) fail "止まった Dependabot の PR を判定できません(終わり方 ${rc})" ;;
    esac
    entry=$(jq -c --argjson n "$KEY" 'map(select(.number == $n)) | first // empty' "$TMP/stuck.json" 2>/dev/null) ||
        fail "止まった PR の一覧の形が違います"
    [ -n "$entry" ] || stop skipped not-stuck
    red=$(jq -c '[.red[].name] | unique' <<<"$entry" 2>/dev/null) || fail "PR #${KEY} の赤の検査の形が違います"
    CHECKS=$(fixable_red_checks "$REQUIRED" "$red") || fail "赤の検査から5つの検査を除けません"
    [ "$(jq 'length' <<<"$CHECKS")" -gt 0 ] || stop skipped no-fixable-check
    if [ "$REASON" = red-check ]; then
        # red-check の起点は Claude の変更の PR の head で、直す赤の検査はその PR のものである
        CHECKS=""
    else
        MERGE_HEAD=$(jq -r '.sha' <<<"$entry")
        is_sha "$MERGE_HEAD" || fail "PR #${KEY} の head の SHA の形が違います"
    fi
    ;;
container)
    # main から作った2つのイメージの Trivy の結果を、週次の検査と同じ report の形で判定する
    found=false
    for image in java go; do
        f="$TRIVY_RESULTS_DIR/trivy-${image}.json"
        [ -f "$f" ] || fail "trivy-${image}.json がありません"
        rc=0
        GITHUB_STEP_SUMMARY=/dev/null bash "$HERE/check-container-scan.sh" "$f" arm64 "$SUPPRESSIONS" report \
            "$TMP/blocking-${image}.json" "$TMP/detected-${image}.json" >&2 || rc=$?
        case "$rc" in
        0 | 1) ;;
        *) fail "trivy-${image}.json を判定できません(終わり方 ${rc})" ;;
        esac
        hit=$(jq -r --arg id "$KEY" 'if type == "array" then any(.[]; .id == $id) else error("x") end' \
            "$TMP/detected-${image}.json" 2>/dev/null) || fail "trivy-${image}.json の判定の結果の形が違います"
        [ "$hit" = false ] || found=true
    done
    [ "$found" = true ] || stop gone gone-on-main
    ;;
esac

# --- 起点のコード ---------------------------------------------------------------------
git fetch --no-tags --quiet origin "+refs/heads/main:refs/remotes/origin/main" || fail "main を取り込めません"
MAIN_SHA=$(git rev-parse --verify --quiet "refs/remotes/origin/main^{commit}") || fail "main のコミットを読めません"
: >"$PATCH" || fail "base.patch を書けません"
if [ -n "$MERGE_HEAD" ]; then
    git fetch --no-tags --quiet origin "+refs/pull/${KEY}/head:refs/remotes/origin/claude-auto-fix-pr" ||
        fail "PR #${KEY} の head を取り込めません"
    fetched=$(git rev-parse --verify --quiet "refs/remotes/origin/claude-auto-fix-pr^{commit}") ||
        fail "PR #${KEY} の head のコミットを読めません"
    # 検査を読んだあとに head が進んでいれば、読んだ赤の検査は今の head のものではない
    [ "$fetched" = "$MERGE_HEAD" ] || stop skipped head-moved
    rc=0
    merged=$(git merge-tree --write-tree --no-messages "$MAIN_SHA" "$MERGE_HEAD") || rc=$?
    case "$rc" in
    0) ;;
    1) stop skipped merge-conflict ;;
    *) fail "main と PR #${KEY} の head をマージできません" ;;
    esac
    tree=$(head -n 1 <<<"$merged")
    git diff --binary --no-ext-diff --no-color "$MAIN_SHA" "$tree" >"$PATCH" || fail "base.patch を書けません"
fi
[ -n "$BASE_SHA" ] || BASE_SHA="$MAIN_SHA"
SUM=$(sha256sum "$PATCH" | cut -d' ' -f1)

printf 'main_sha=%s\nbase_sha=%s\nbase_sha256=%s\nbase_patch=%s\n' "$MAIN_SHA" "$BASE_SHA" "$SUM" "$PATCH"
[ -z "$CHECKS" ] || printf 'checks=%s\n' "$CHECKS"
