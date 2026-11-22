#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix の edit ジョブで、Claude に渡す材料を集めるスクリプト
# (design.md の claude-auto-fix-materials.sh の節)
#
# 使い方: claude-auto-fix-materials.sh <kind> <key> <reason> <pr> <checks> <detail>
#   kind   npm maven go-stdlib go-module codeql container dependabot
#   reason trigger manual retry red-check
#   pr     red-check では Claude の変更の PR の番号。そのほかは使わない(種類 dependabot の PR は key で読む)
#   checks 赤の検査の名前の JSON の配列(dependabot と red-check で使う)
#   detail vuln-fix の組の JSON(npm maven go-stdlib go-module で使う)
#
# 環境変数:
#   RUNNER_TEMP          材料のファイルを書くフォルダ(必須)
#   GITHUB_REPOSITORY    読むリポジトリ(owner/name。必須)
#   GH_TOKEN             gh が使うトークン(読むだけ)
#   TRIVY_RESULTS_DIR    種類が container のとき、prepare ジョブの trivy-java.json と trivy-go.json のフォルダ
#   CAF_REQUIRED_CHECKS  期待一覧のファイル(既定は .github/audit/required-checks.json)
#   CAF_SHIP_LOGIN       Claude の変更の PR を作る bot のアカウント(既定は DogisRiki-bot)
#
# 材料は $RUNNER_TEMP/claude-auto-fix-materials.txt に書き、標準出力には
# 「materials=<そのファイルの場所>」の1行だけを書く。材料の中身は標準出力にも標準エラーにも出さない。
# 種類が codeql の警告の中身を、公開されている実行の記録に出さないためである(要件 5.1)。
#
# 材料は、次の2行で始まりと終わりを示す。<合言葉> は実行ごとに作る16桁の16進数で、
# 材料の中に同じ行を書いても、区切りの行を偽れない。
#   ----- claude-auto-fix 材料の始まり <合言葉> <名前> -----
#   ----- claude-auto-fix 材料の終わり <合言葉> <名前> -----
#
# なぜ書き手を絞るか:
#   このリポジトリは公開されていて、誰でも Issue とコメントと fork の PR を書ける。
#   材料に入れるのは、github-actions[bot] が起票したコンテナの Issue の本文、
#   dependabot[bot] が作った PR の題名と本文、この仕組みの bot が作った Claude の変更の PR の本文だけにする。
#   Issue と PR のコメントは読まない。CAF_SHIP_LOGIN は ship ジョブが使う BOT_GITHUB_TOKEN のアカウントで、
#   Claude の変更の PR は、このリポジトリのブランチ fix/claude-auto-fix-… から、ラベル claude-auto-fix を付けて作られる。
#
# 材料を読めないときは、材料のファイルを残さずに 1 で終わる。引数の誤りは 2 で終わる。
# =====================================================================
set -euo pipefail

# shellcheck source=.github/scripts/lib-claude-auto-fix.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-claude-auto-fix.sh"

usage() {
    echo "claude-auto-fix-materials: $1" >&2
    echo "使い方: claude-auto-fix-materials.sh <kind> <key> <reason> <pr> <checks> <detail>" >&2
    exit 2
}
fail() {
    # 材料を集める関数はコマンド置換の中でも呼ぶので、知らせは標準エラーに書く(Actions は標準エラーの ::error:: も読む)
    echo "::error::claude-auto-fix-materials: $1" >&2
    exit 1
}

[ $# -eq 6 ] || usage "引数は6つです(${#}個でした)"
KIND="$1" KEY="$2" REASON="$3" PR="$4" CHECKS="$5" DETAIL="$6"
case "$KIND" in
npm | maven | go-stdlib | go-module | codeql | container | dependabot) ;;
*) usage "知らない種類です: ${KIND}" ;;
esac
case "$REASON" in
trigger | manual | retry | red-check) ;;
*) usage "知らない reason です: ${REASON}" ;;
esac
NAMES=$(target_names "$KIND" "$KEY") || usage "key の形が違います"
BRANCH=$(jq -r .branch <<<"$NAMES")
[ -n "${RUNNER_TEMP:-}" ] && [ -d "$RUNNER_TEMP" ] || usage "RUNNER_TEMP のフォルダがありません"
REPO=$(_caf_repo) || usage "GITHUB_REPOSITORY がありません"
REQUIRED="${CAF_REQUIRED_CHECKS:-$(dirname "${BASH_SOURCE[0]}")/../audit/required-checks.json}"
SHIP_LOGIN="${CAF_SHIP_LOGIN:-DogisRiki-bot}"
DEPENDABOT_LOGIN="dependabot[bot]"
LOG_LINES=400

OUT="$RUNNER_TEMP/claude-auto-fix-materials.txt"
TMP=$(mktemp -d "$RUNNER_TEMP/claude-auto-fix-materials.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
MAT="$TMP/materials.txt"
: >"$MAT"
NONCE=$(od -An -tx1 -N8 /dev/urandom | tr -d ' \n')
[[ "$NONCE" =~ ^[0-9a-f]{16}$ ]] || fail "区切りの合言葉を作れません"

# section <名前>  < 中身: 区切りの行で囲んで材料のファイルに足す
section() {
    {
        printf -- '----- claude-auto-fix 材料の始まり %s %s -----\n' "$NONCE" "$1"
        # 末尾に改行の無い中身でも、終わりの区切りを次の行に書く
        local body
        body=$(cat)
        [ -z "$body" ] || printf '%s\n' "$body"
        printf -- '----- claude-auto-fix 材料の終わり %s %s -----\n' "$NONCE" "$1"
    } >>"$MAT"
}

# api <説明> <gh api の引数…>: 応答を標準出力に出す。失敗したら止める
api() {
    local what="$1" raw
    shift
    raw=$(gh api "$@") || fail "${what}を読めません"
    printf '%s\n' "$raw"
}

# red_check_logs <head の SHA>: CHECKS の検査ごとに、最新の実行の失敗した手順の出力の末尾を足す
red_check_logs() {
    local sha="$1" runs name id log
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || fail "PR の head の SHA の形が違います"
    runs=$(api "PR の head の検査の結果" --paginate --slurp "repos/${REPO}/commits/${sha}/check-runs?per_page=100")
    jq -r '.[]' <<<"$CHECKS" | section red-checks
    while IFS= read -r name; do
        id=$(jq -r --arg n "$name" '
            [.[] | .check_runs[]? | select(.name? == $n and (.id | type) == "number")]
            | max_by([(.started_at // ""), .id]) // empty | .id' <<<"$runs" 2>/dev/null) || fail "検査の結果の形が違います"
        [ -n "$id" ] || fail "赤の検査 ${name} の実行がありません"
        log="$TMP/log-${id}.txt"
        gh run view --repo "$REPO" --job "$id" --log-failed >"$log" || fail "赤の検査 ${name} の実行の記録を読めません"
        tail -n "$LOG_LINES" "$log" | section "log ${name}"
    done < <(jq -r '.[]' <<<"$CHECKS")
}

# 赤の検査の名前は、改行と制御文字の無い文字列の、空でない配列に限る(区切りの行の名前に入るため)
check_names() {
    jq -e 'type == "array" and length > 0 and all(.[]; type == "string" and length > 0 and (test("[[:cntrl:]]") | not))' \
        >/dev/null 2>&1 <<<"$CHECKS" || fail "赤の検査の名前が、改行の無い文字列の空でない配列ではありません"
}

printf '種類: %s\nkey: %s\n' "$KIND" "$KEY" | section target

if [ "$REASON" = red-check ]; then
    # この仕組みが作った PR の本文と、赤の検査の記録
    [[ "$PR" =~ ^[1-9][0-9]*$ ]] || fail "red-check の PR の番号の形が違います"
    check_names
    pull=$(api "PR #${PR}" "repos/${REPO}/pulls/${PR}")
    jq -e --arg login "$SHIP_LOGIN" --arg repo "$REPO" --arg ref "$BRANCH" --arg label "$CAF_LABEL" '
        .state == "open" and .user.login? == $login and .head.repo.full_name? == $repo
        and .head.ref? == $ref and any(.labels[]?; .name? == $label)' >/dev/null 2>&1 <<<"$pull" ||
        fail "PR #${PR} は、この仕組みの bot が ${BRANCH} から作った開いている Claude の変更の PR ではありません"
    jq -r '.body // ""' <<<"$pull" | section claude-pr
    red_check_logs "$(jq -r '.head.sha // ""' <<<"$pull")"
else
    case "$KIND" in
    npm | maven)
        [ "$(target_key "$KIND" "$DETAIL" 2>/dev/null)" = "$KEY" ] || fail "組の JSON が key と合いません"
        jq . <<<"$DETAIL" | section group
        alerts=$(api "Dependabot の警告" --paginate --slurp "repos/${REPO}/dependabot/alerts?state=open&ecosystem=${KIND}&per_page=100")
        picked=$(jq -c --arg eco "$KIND" --argjson g "$DETAIL" "$_CAF_JQ_PAGES"'
            pages | .[]
            | select(.state? == "open" and .dependency.package.ecosystem? == $eco
                and .dependency.package.name? == $g.name
                and .security_vulnerability.first_patched_version.identifier? == $g.version)
            | {url: .html_url, severity: .security_advisory.severity, vulnerable_range: .security_vulnerability.vulnerable_version_range,
               patched: .security_vulnerability.first_patched_version.identifier, summary: .security_advisory.summary}' <<<"$alerts" 2>/dev/null) ||
            fail "Dependabot の警告の形が違います"
        [ -n "$picked" ] || fail "組の Dependabot の警告が1つも開いていません"
        printf '%s\n' "$picked" | section dependabot-alerts
        ;;
    go-stdlib | go-module)
        [ "$(target_key "$KIND" "$DETAIL" 2>/dev/null)" = "$KEY" ] || fail "組の JSON が key と合いません"
        jq -e '(.osv | type) == "array" and (.osv | length) > 0 and all(.osv[]; type == "string" and test("^GO-[0-9]{4}-[0-9]+$"))' \
            >/dev/null 2>&1 <<<"$DETAIL" || fail "組の OSV の ID が GO-<年>-<番号> の空でない配列ではありません"
        jq . <<<"$DETAIL" | section group
        while IFS= read -r osv; do
            raw=$(curl -fsSL --retry 2 --max-time 30 "https://vuln.go.dev/ID/${osv}.json") || fail "OSV ${osv} を読めません"
            jq -ce '{id, summary: (.summary // ""), details: (.details // "")}' <<<"$raw" 2>/dev/null >"$TMP/osv.json" ||
                fail "OSV ${osv} の形が違います"
            section "osv ${osv}" <"$TMP/osv.json"
        done < <(jq -r '.osv[]' <<<"$DETAIL")
        ;;
    codeql)
        alert=$(api "CodeQL の警告 ${KEY}" "repos/${REPO}/code-scanning/alerts/${KEY}")
        jq -er '
            if (.rule.id | type) != "string" or (.most_recent_instance.location.path | type) != "string" then error("x") else . end
            | .most_recent_instance as $i
            | "規則の ID: \(.rule.id)",
              "規則の説明: \(.rule.description // "")",
              "メッセージ: \($i.message.text // "")",
              "場所: \($i.location.path):\($i.location.start_line // "")-\($i.location.end_line // "")",
              "規則の help:",
              (.rule.help // "")' <<<"$alert" >"$TMP/codeql.txt" 2>/dev/null || fail "CodeQL の警告 ${KEY} の形が違います"
        section codeql-alert <"$TMP/codeql.txt"
        ;;
    container)
        [ -n "${TRIVY_RESULTS_DIR:-}" ] && [ -d "$TRIVY_RESULTS_DIR" ] || fail "TRIVY_RESULTS_DIR のフォルダがありません"
        issues=$(api "ラベル container-vuln の Issue" --paginate --slurp "repos/${REPO}/issues?labels=container-vuln&state=open&per_page=100")
        jq -r --arg title "${CAF_CONTAINER_TITLE_PREFIX}${KEY}" --arg bot "$CAF_BOT_LOGIN" "$_CAF_JQ_PAGES"'
            [pages | .[] | select((has("pull_request") | not) and .user.login? == $bot and .title? == $title)]
            | min_by(.number) // error("x") | .body // ""' <<<"$issues" >"$TMP/issue.txt" 2>/dev/null ||
            fail "github-actions[bot] が起票した ${KEY} の Issue がありません"
        # 本文のうち、脆弱性の ID の行と、部品・入っている版・修正版の行だけを渡す
        grep -E '^- (脆弱性: |`)' "$TMP/issue.txt" >"$TMP/issue-rows.txt" || fail "${KEY} の Issue の本文に脆弱性の行がありません"
        section container-issue <"$TMP/issue-rows.txt"
        : >"$TMP/trivy.txt"
        for image in java go; do
            f="$TRIVY_RESULTS_DIR/trivy-${image}.json"
            [ -f "$f" ] || fail "trivy-${image}.json がありません"
            jq -c --arg id "$KEY" --arg image "$image" '
                if (.Results // []) | type != "array" then error("x") else . end
                | .Results[]? | .Target as $t | .Vulnerabilities[]? | select(.VulnerabilityID == $id)
                | {image: $image, target: $t, id: .VulnerabilityID, package: .PkgName,
                   installed: .InstalledVersion, fixed: (.FixedVersion // ""), severity: .Severity}' "$f" >>"$TMP/trivy.txt" 2>/dev/null ||
                fail "trivy-${image}.json の形が違います"
        done
        section trivy <"$TMP/trivy.txt"
        ;;
    dependabot)
        jq -e 'type == "array"' >/dev/null 2>&1 <<<"$CHECKS" || fail "赤の検査の名前が JSON の配列ではありません"
        # dependency-review と承認待ちの4つの検査は、直しても緑にならないので、名前も記録も渡さない
        CHECKS=$(fixable_red_checks "$REQUIRED" "$CHECKS") || fail "直しても緑にならない検査を除けません"
        check_names
        pull=$(api "PR #${KEY}" "repos/${REPO}/pulls/${KEY}")
        jq -e --arg login "$DEPENDABOT_LOGIN" '.user.login? == $login' >/dev/null 2>&1 <<<"$pull" ||
            fail "PR #${KEY} は dependabot[bot] が作った PR ではありません"
        jq -r '"題名: \(.title // "")", "", "本文:", (.body // "")' <<<"$pull" | section dependabot-pr
        red_check_logs "$(jq -r '.head.sha // ""' <<<"$pull")"
        ;;
    esac
fi

mv "$MAT" "$OUT"
printf 'materials=%s\n' "$OUT"
