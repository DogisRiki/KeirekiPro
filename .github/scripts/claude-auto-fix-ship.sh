#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix の ship ジョブで、確かめた差分をコミットして push し、PR を作るスクリプト
# (design.md の claude-auto-fix-ship.sh の節)
#
# 使い方: claude-auto-fix-ship.sh <kind> <key> <reason> <pr> <checks> <detail> <final.patch> <sha256> <起点のコミット>
#   起点のコミットは、ship ジョブが作業のフォルダに作り直した起点のコードのコミットである。
#   reason が red-check のときは PR の head のコミット、そのほかは main_sha に base.patch を当てたコミットである。
#
# 手順:
#   1. final.patch の SHA-256 が、verify ジョブの出力 <sha256> と同じであることを確かめる。違えば push しない
#   2. 一時の index で、起点のコミットに final.patch だけを当てた木を作り、その木を起点のコミットの子にした
#      コミットを作る。このコミットで claude-auto-fix-guard.sh <起点のコミット> <そのコミット> をもう一度呼ぶ。
#      0以外なら push せず、outcome=unfixed を書く。ガードは、このスクリプトと同じフォルダ(ワークフローの
#      コミットの main)のものを使い、作業のフォルダのコードを動かさない。
#      ガードを新しい PR のコミットで呼ばないのは、新しい PR のコミットが起点のコミットの子ではなく、
#      比べる範囲に base.patch が入るためである(種類が dependabot で、Dependabot の PR が
#      .github/workflows/ を変えると、Claude の変更に関係なくガードが止まる)
#   3. red-check のとき: PR のブランチの head が起点のコミットと同じことを確かめ、手順2のコミットを
#      force を付けずに push する。違えば push せず、outcome=skipped を書く
#      そのほかのとき: 同じブランチの開いている PR が無いことを確かめ、手順2の木を main_sha の子にした
#      1つのコミットを作って push し、gh pr create --base main --label claude-auto-fix で PR を作る
#   標準出力: outcome=pr と pr_url=<URL> の2行か、outcome=<unfixed|skipped> の1行を書く。
#   push か PR の作成に失敗したときは0以外で終わる。
#
# 題名と本文とコミットのメッセージは、決まった文と、種類と key と PR の番号と、赤の検査の名前と、
# 対象の URL と、変えたファイルの名前だけで書く。Claude が書いた文は入れない。種類が codeql のときは、
# 変えたファイルの名前も書かない(警告の中身が公開の文に残らないようにするため)。
# このスクリプトは、PR のマージ、auto-merge の予約、main への push、警告の却下、PR を閉じること、
# Dependabot へのコマンドを行わない。
#
# 環境変数:
#   GH_TOKEN           bot の PAT(secrets.BOT_GITHUB_TOKEN)。push と PR の作成に使う
#   GITHUB_REPOSITORY  <owner>/<repo>。必須
#   GITHUB_SERVER_URL  既定は https://github.com
#   CAF_TARGET_DIR     作業のフォルダ(起点のコミットを checkout したリポジトリ)。既定は target
#   CAF_MAIN_SHA       prepare ジョブの出力 main_sha。reason が red-check でないときは必須で、
#                      起点のコミットの祖先でなければならない
#
# テスト: .github/scripts/tests/test-claude-auto-fix-ship.sh
# =====================================================================
set -euo pipefail

CAF_SHIP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/lib-claude-auto-fix.sh
. "$CAF_SHIP_DIR/lib-claude-auto-fix.sh"

CAF_SHIP_BOT_NAME="claude-auto-fix-bot"
CAF_SHIP_BOT_EMAIL="claude-auto-fix-bot@users.noreply.github.com"

usage() {
    echo "::error::claude-auto-fix-ship: $1" >&2
    echo "使い方: claude-auto-fix-ship.sh <kind> <key> <reason> <pr> <checks> <detail> <final.patch> <sha256> <起点のコミット>" >&2
    exit 2
}
fail() {
    echo "::error::claude-auto-fix-ship: $1" >&2
    exit 1
}
# 使い方: stop <unfixed|skipped> <理由>
stop() {
    echo "claude-auto-fix-ship: $2" >&2
    printf 'outcome=%s\n' "$1"
    exit 0
}

# 対象を表す決まった文。使い方: subject <plain|md>。md のときは key をコードの形にする
# (npm の key の @ が、本文で人への呼びかけにならないようにするため)
subject() {
    local k="$KEY"
    [ "$1" != md ] || k="\`${KEY}\`"
    case "$KIND" in
    npm) printf 'npm の部品 %s の脆弱性' "$k" ;;
    maven) printf 'Maven の部品 %s の脆弱性' "$k" ;;
    go-stdlib) printf 'Go の標準ライブラリの脆弱性(Go %s で直る)' "$k" ;;
    go-module) printf 'Go の部品 %s の脆弱性' "$k" ;;
    codeql) printf 'CodeQL の警告 #%s' "$KEY" ;;
    container) printf 'コンテナの脆弱性 %s' "$k" ;;
    dependabot) printf 'Dependabot の PR #%s の赤の検査' "$KEY" ;;
    esac
}

title() {
    if [ "$REASON" = red-check ]; then
        printf 'fix: claude-auto-fix の PR #%s の赤の検査を直す' "$PR"
        return
    fi
    case "$KIND" in
    npm | maven | go-module | dependabot) printf 'fix: %sを直す' "$(subject plain)" ;;
    container) printf 'fix: コンテナの脆弱性 %s を直す' "$KEY" ;;
    go-stdlib) printf 'fix: Go の標準ライブラリの脆弱性を Go %s で直す' "$KEY" ;;
    codeql) printf 'fix: CodeQL の警告 #%s を直す' "$KEY" ;;
    esac
}

# 対象の URL を1行に1つ書く。このリポジトリの URL と、Go の脆弱性の公開の URL だけを書く
target_urls() {
    local base="${SERVER}/${REPO}" raw
    case "$KIND" in
    npm | maven)
        jq -r --arg prefix "${base}/security/dependabot/" '
            [.alerts[]?.html_url? | select(type == "string" and startswith($prefix)
                and (ltrimstr($prefix) | test("^[1-9][0-9]*$")))] | unique | .[]' <<<"$DETAIL" ||
            fail "detail の警告の URL を読めません"
        ;;
    go-stdlib | go-module)
        jq -r '.osv | if type == "array" and length > 0 and all(type == "string" and test("^GO-[0-9]{4}-[0-9]{4,}$"))
            then unique | .[] | "https://pkg.go.dev/vuln/" + . else error("x") end' <<<"$DETAIL" 2>/dev/null ||
            fail "detail の Go の脆弱性の ID の形が違います"
        ;;
    codeql) printf '%s/security/code-scanning/%s\n' "$base" "$KEY" ;;
    dependabot) printf '%s/pull/%s\n' "$base" "$KEY" ;;
    container)
        raw=$(gh api --paginate --slurp "repos/${REPO}/issues?labels=container-vuln&state=open&per_page=100") ||
            fail "ラベル container-vuln の Issue を読めません"
        jq -r --arg title "${CAF_CONTAINER_TITLE_PREFIX}${KEY}" --arg bot "$CAF_BOT_LOGIN" \
            --arg prefix "${base}/issues/" "$_CAF_JQ_PAGES"'
            [pages | .[] | select((has("pull_request") | not) and (.user.login? // "") == $bot and .title? == $title)]
            | min_by(.number) // error("x") | .html_url
            | if type == "string" and startswith($prefix) and (ltrimstr($prefix) | test("^[1-9][0-9]*$"))
              then . else error("x") end' <<<"$raw" 2>/dev/null ||
            fail "github-actions[bot] が起票した ${KEY} の Issue がありません"
        ;;
    esac
}

# 変えたファイルを、本文の一覧の行にして書く。バッククォートか制御文字を含む名前は、
# コードの形が崩れるので、決まった文に替える
file_rows() {
    local path
    while IFS= read -r -d '' path; do
        if [[ "$path" == *'`'* ]] || [[ "$path" =~ [[:cntrl:]] ]]; then
            echo "- (表示できない名前のファイル)"
        else
            printf -- "- \`%s\`\n" "$path"
        fi
    done <"$W/paths"
}

write_message() {
    local s
    s=$(subject plain)
    {
        title
        printf '\n\nChanges:\n'
        if [ "$REASON" = red-check ]; then
            printf -- '- PR #%s の赤の検査を直す変更を、claude-auto-fix の仕組みが確かめてコミットした\n' "$PR"
        else
            printf -- '- %s を直す変更を、claude-auto-fix の仕組みが確かめてコミットした\n' "$s"
        fi
        printf '\nReason:\n'
        if [ "$REASON" = red-check ]; then
            printf -- '- PR #%s の必須の検査を通すため\n' "$PR"
        else
            printf -- '- %s を、所有者の手を借りずに直すため\n' "$s"
        fi
        printf '\nBREAKING CHANGE: N/A\n'
        printf 'Related: %s\n' "$(paste -sd ' ' "$W/urls")"
        printf 'Refs: N/A\n\n'
        printf 'Claude-Auto-Fix-Key: %s %s\n' "$KIND" "$KEY"
        if [ "$REASON" = red-check ]; then
            jq -r '.[] | "Claude-Auto-Fix-Check: " + .' <<<"$CHECKS"
        fi
    } >"$W/message" || fail "コミットのメッセージを書けません"
}

write_body() {
    local marker
    marker=$(marker_line pr "kind=${KIND}" "key=${KEY}") || fail "PR の目印を作れません"
    {
        if [ "$KIND" = codeql ]; then
            echo "claude-auto-fix の仕組みが、CodeQL の警告を直すために作った PR です。中身は、仕組みが確かめた変更だけです。"
        else
            echo "claude-auto-fix の仕組みが、$(subject md)を直すために作った PR です。中身は、仕組みが確かめた変更だけです。"
        fi
        if [ "$KIND" = dependabot ]; then
            echo "Dependabot の PR の版上げも、この PR の1つのコミットに入っています。Dependabot の PR は閉じずに残します。"
        fi
        echo "$marker"
        if [ -n "$DETAIL" ]; then
            printf '<!-- claude-auto-fix-detail %s -->\n' "$(printf '%s' "$DETAIL" | base64 -w0)"
        fi
        printf '\n## 対象\n\n'
        sed 's/^/- /' "$W/urls"
        if [ "$KIND" != codeql ]; then
            printf '\n## 変えたファイル\n\n'
            file_rows
        fi
    } >"$W/body" || fail "PR の本文を書けません"
}

# 使い方: commit_on <木> <親> で、bot を作り手にしたコミットを作り、SHA を出す
commit_on() {
    GIT_AUTHOR_NAME="$CAF_SHIP_BOT_NAME" GIT_AUTHOR_EMAIL="$CAF_SHIP_BOT_EMAIL" \
        GIT_COMMITTER_NAME="$CAF_SHIP_BOT_NAME" GIT_COMMITTER_EMAIL="$CAF_SHIP_BOT_EMAIL" \
        git -C "$TARGET" -c commit.gpgsign=false commit-tree "$1" -p "$2" -F "$W/message"
}

# 使い方: push_ref <コミット> <ブランチ> [--force]
push_ref() {
    local src="$1:refs/heads/$2"
    [ "${3:-}" != --force ] || src="+${src}"
    git -C "$TARGET" -c core.hooksPath=/dev/null push -q origin "$src" </dev/null >&2 ||
        fail "ブランチ ${2} に push できません"
}

red_check() {
    local head
    head=$(git -C "$TARGET" ls-remote --exit-code origin "refs/heads/${BRANCH}" | cut -f1) ||
        fail "PR のブランチ ${BRANCH} の head を読めません"
    [ "$head" = "$BASE" ] || stop skipped "PR のブランチの head が起点のコミットと違います"
    gh auth setup-git >&2 || fail "push の準備ができません"
    push_ref "$G" "$BRANCH"
    printf 'outcome=pr\npr_url=%s/%s/pull/%s\n' "$SERVER" "$REPO" "$PR"
}

new_pr() {
    local open commit url
    open=$(gh api "repos/${REPO}/pulls?state=open&head=${REPO%%/*}:${BRANCH}&per_page=100") ||
        fail "開いている PR を読めません"
    jq -e 'type == "array" and length == 0' >/dev/null 2>&1 <<<"$open" ||
        fail "ブランチ ${BRANCH} の開いている PR があります"
    commit=$(commit_on "$TREE" "$MAIN_SHA") || fail "新しい PR のコミットを作れません"
    write_body
    gh auth setup-git >&2 || fail "push の準備ができません"
    push_ref "$commit" "$BRANCH" --force
    url=$(gh pr create --base main --head "$BRANCH" --title "$(title)" --body "$(cat "$W/body")" \
        --label "$CAF_LABEL" </dev/null) || fail "PR を作れません"
    url=$(printf '%s\n' "$url" | tail -n 1)
    [[ "$url" =~ ^"${SERVER}/${REPO}"/pull/[1-9][0-9]*$ ]] || fail "gh pr create が PR の URL を返しません"
    printf 'outcome=pr\npr_url=%s\n' "$url"
}

main() {
    [ "$#" -eq 9 ] || usage "引数の数が違います"
    KIND="$1"
    KEY="$2"
    REASON="$3"
    PR="$4"
    CHECKS="$5"
    DETAIL="$6"
    FINAL_PATCH="$7"
    SHA="$8"
    BASE="$9"
    case "$KIND" in
    npm | maven | go-stdlib | go-module | codeql | container | dependabot) ;;
    *) usage "知らない種類です: ${KIND}" ;;
    esac
    [ -n "$KEY" ] || usage "key が空です"
    BRANCH=$(target_names "$KIND" "$KEY" | jq -r .branch) || usage "key からブランチ名を作れません"
    [[ "$BRANCH" == "$CAF_BRANCH_PREFIX"?* ]] || usage "ブランチ名の形が違います"
    case "$REASON" in
    trigger | manual | retry) ;;
    red-check)
        [[ "$PR" =~ ^[1-9][0-9]*$ ]] || usage "red-check の PR の番号の形が違います"
        jq -e 'type == "array" and length > 0 and all(type == "string" and length > 0 and (test("[[:cntrl:]]") | not))' \
            >/dev/null 2>&1 <<<"$CHECKS" || usage "red-check の赤の検査の名前の JSON の形が違います"
        ;;
    *) usage "知らない reason です: ${REASON}" ;;
    esac
    if [ -n "$DETAIL" ]; then
        jq -e 'type == "object"' >/dev/null 2>&1 <<<"$DETAIL" || usage "detail が JSON のオブジェクトではありません"
    fi
    [[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || usage "sha256 の形が違います"
    [ -f "$FINAL_PATCH" ] && [ -r "$FINAL_PATCH" ] || usage "final.patch を読めません: ${FINAL_PATCH}"
    REPO="${GITHUB_REPOSITORY:-}"
    [[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || usage "GITHUB_REPOSITORY の形が違います"
    SERVER="${GITHUB_SERVER_URL:-https://github.com}"
    [[ "$SERVER" =~ ^https://[A-Za-z0-9.-]+$ ]] || usage "GITHUB_SERVER_URL の形が違います"
    TARGET="${CAF_TARGET_DIR:-target}"
    [ -d "$TARGET" ] || usage "作業のフォルダがありません: ${TARGET}"
    TARGET=$(cd "$TARGET" && pwd)
    git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || usage "作業のフォルダが Git のリポジトリではありません: ${TARGET}"
    BASE=$(git -C "$TARGET" rev-parse --verify --quiet "${BASE}^{commit}") || usage "起点のコミットを読めません: $9"
    if [ "$REASON" != red-check ]; then
        [ -n "${CAF_MAIN_SHA:-}" ] || usage "CAF_MAIN_SHA がありません"
        MAIN_SHA=$(git -C "$TARGET" rev-parse --verify --quiet "${CAF_MAIN_SHA}^{commit}") ||
            usage "CAF_MAIN_SHA のコミットを読めません"
        git -C "$TARGET" merge-base --is-ancestor "$MAIN_SHA" "$BASE" || usage "CAF_MAIN_SHA が起点のコミットの祖先ではありません"
    fi

    local sum
    sum=$(sha256sum <"$FINAL_PATCH" | cut -d' ' -f1) || fail "final.patch の SHA-256 を計算できません"
    [ "$sum" = "$SHA" ] || fail "final.patch の SHA-256 が verify ジョブの出力と違います"

    W=$(mktemp -d) || fail "一時のフォルダを作れません"
    trap 'rm -rf "$W"' EXIT

    target_urls >"$W/urls"
    [ -s "$W/urls" ] || fail "対象の URL がありません"

    GIT_INDEX_FILE="$W/index" git -C "$TARGET" read-tree "$BASE" || fail "起点のコミットの木を読めません"
    GIT_INDEX_FILE="$W/index" git -C "$TARGET" apply --cached --binary "$FINAL_PATCH" >&2 ||
        fail "final.patch を起点のコミットに当てられません"
    TREE=$(GIT_INDEX_FILE="$W/index" git -C "$TARGET" write-tree) || fail "最後の差分の木を作れません"

    write_message
    G=$(commit_on "$TREE" "$BASE") || fail "ガードに掛けるコミットを作れません"
    (cd "$TARGET" && CAF_KIND="$KIND" bash "$CAF_SHIP_DIR/claude-auto-fix-guard.sh" "$BASE" "$G") >&2 ||
        stop unfixed "push の前のガードを通りませんでした"
    git -C "$TARGET" diff --name-only --no-renames -z "$BASE" "$G" >"$W/paths" || fail "変えたファイルを読めません"

    if [ "$REASON" = red-check ]; then
        red_check
    else
        new_pr
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
