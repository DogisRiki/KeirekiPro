# shellcheck shell=bash
# =====================================================================
# claude-auto-fix の仕組みのスクリプトが source して使う共通の関数
# (design.md の lib-claude-auto-fix.sh の節。読み込むと関数を定義するだけで、何も動かさない)
#
# 関数:
#   target_key <種類> <組の JSON>
#       対象の種類と組から、対象を見分ける key を出す
#   target_names <種類> <key> [<PR の番号> <head の SHA>]
#       ブランチ名と、ワークフローの実行の表示名を、JSON {branch, run_name} で出す
#   marker_line <目印の名前> [<欄>=<値> ...]
#       HTML コメントの目印の1行を出す
#   latest_marker <目印の名前> [<欄>=<値> ...]  < 本文とコメントの一覧の JSON
#       github-actions[bot] が書いた目印のうち、欄の値が合う最も新しい目印の欄を JSON で出す
#   issue_state <種類> <key>  < 本文とコメントの一覧の JSON
#       知らせの Issue の状態(unfixed か unavailable)を出す。目印が無ければ空を出す
#   fixable_red_checks <期待一覧のファイル> <赤の検査の名前の JSON の配列>
#       直しても緑にならない検査を除いた、赤の検査の名前の JSON の配列を出す
#   claude_prs
#       開いている Claude の変更の PR の一覧を JSON の配列で出す
#   claude_pr <種類> <key>
#       同じ key の開いている Claude の変更の PR を JSON で出す。無ければ空を出す
#   recent_outcomes
#       直近4日の対象ごとの実行の結果のファイルを JSON の配列で出す
#   key_issues [<閉じた日時の下限>]  < Issue の一覧の JSON
#       鍵の取り替えを求める Issue の番号を出す
#   target_gone <種類> <key> [<期待一覧のファイル>]
#       対象が消えたかを true か false で出す
#   cooldown_needed <ci-tool-versions.json> <変えたパスを1行に1つ書いたファイル>
#       公開からの時間の3つの判定が要るかを true か false で出す
#   cooldown_outcome <依存の判定の終わり方> <Go の判定の終わり方> <CI の道具の判定の終わり方>
#       3つの判定の終わり方から、ship か blocked か fail を出す
#
# どの関数も、失敗したときは標準エラーに理由を書き、標準出力には何も出さずに1を返す。
#
# ブランチ名を今の vuln-fix のブランチ名に合わせる理由:
#   vuln-fix の種類の Claude の変更のブランチ名は、今の frontend-vuln-fix.sh と
#   backend-vuln-fix.sh が作る `chore/...-vuln-fix-...` のブランチ名から `chore/` を除き、
#   `fix/claude-auto-fix-` を前に付けたものにする。key に使う `@` と、今のスクリプトが
#   名前と版をつなぐ `-` は、どちらも slug で `-` になるので、key から同じ slug ができる。
#
# なぜ github-actions[bot] が書いた目印だけを読むか:
#   誰でも Issue のコメントに同じ目印を書ける。書いた人を問わずに読むと、第三者が目印を
#   書くだけで Issue の状態を変えられる。本文とコメントの一覧は REST で読む。REST は
#   作成者を .user.login に github-actions[bot] と返す(lib-notice-comment.sh と同じ)。
# =====================================================================

CAF_BOT_LOGIN="github-actions[bot]"

# Go の版を読むファイルの見分け方は、Go の版の公開からの時間の検査と同じ関数を使う。
# 写しを持つと、検査の側だけが変わったときに、判定が要る変更を見落とすためである
if ! declare -F go_release_is_target >/dev/null 2>&1; then
    # shellcheck source=.github/scripts/lib-go-release.sh
    . "$(dirname "${BASH_SOURCE[0]}")/lib-go-release.sh" ||
        echo "lib-claude-auto-fix: lib-go-release.sh を読み込めませんでした" >&2
fi

# 依存の版を宣言する6つのファイル
CAF_COOLDOWN_DEP_FILES=(
    frontend/package.json
    frontend/pnpm-lock.yaml
    frontend/pnpm-workspace.yaml
    backend/gradle/libs.versions.toml
    backend/go.mod
    backend/go.sum
)

_caf_fail() {
    printf 'lib-claude-auto-fix: %s\n' "$1" >&2
    return 1
}

# key に使える文字。目印とブランチ名とワークフローの実行の表示名に入るので、空白と > を入れない
_caf_valid_key() {
    [[ "$1" =~ ^[A-Za-z0-9@/._:+~-]+$ ]]
}

# backend-vuln-fix.sh の slug と同じ作り方
_caf_slug_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//'
}

# frontend-vuln-fix.sh のブランチ名の slug と同じ作り方(大文字を小文字にせず、末尾の - を残す)
_caf_slug_frontend() {
    printf '%s' "$1" | tr -c 'a-z0-9' '-' | sed -E 's/-+/-/g; s/^-//'
}

target_key() {
    local kind="$1" group="$2" key
    jq -e 'type == "object"' >/dev/null 2>&1 <<<"$group" || {
        _caf_fail "組が JSON のオブジェクトではありません(種類 ${kind})"
        return 1
    }
    case "$kind" in
    npm | maven) key=$(jq -r 'if (.name | type) == "string" and (.version | type) == "string" and .name != "" and .version != "" then "\(.name)@\(.version)" else empty end' <<<"$group") ;;
    go-stdlib) key=$(jq -r 'if (.version | type) == "string" and .version != "" then .version else empty end' <<<"$group") ;;
    go-module) key=$(jq -r 'if (.module | type) == "string" and (.version | type) == "string" and .module != "" and .version != "" then "\(.module)@\(.version)" else empty end' <<<"$group") ;;
    codeql | dependabot) key=$(jq -r '.number | if type == "number" and . == floor and . > 0 then tostring else empty end' <<<"$group") ;;
    container) key=$(jq -r 'if (.id | type) == "string" then .id else empty end' <<<"$group") ;;
    *)
        _caf_fail "知らない種類です: ${kind}"
        return 1
        ;;
    esac
    if [ -z "$key" ] || ! _caf_valid_key "$key"; then
        _caf_fail "組から key を作れません(種類 ${kind})"
        return 1
    fi
    printf '%s\n' "$key"
}

target_names() {
    local kind="$1" key="$2" pr="${3:-}" sha="${4:-}" prefix slug run_name
    if [ -z "$key" ] || ! _caf_valid_key "$key"; then
        _caf_fail "key の形が違います(種類 ${kind})"
        return 1
    fi
    case "$kind" in
    npm) prefix="frontend-vuln-fix-" slug=$(_caf_slug_frontend "$key") ;;
    maven) prefix="backend-vuln-fix-" slug=$(_caf_slug_lower "$key") ;;
    go-stdlib) prefix="backend-vuln-fix-go-stdlib-" slug=$(_caf_slug_lower "$key") ;;
    go-module) prefix="backend-vuln-fix-go-" slug=$(_caf_slug_lower "$key") ;;
    codeql | dependabot)
        [[ "$key" =~ ^[1-9][0-9]*$ ]] || {
            _caf_fail "${kind} の key が番号ではありません"
            return 1
        }
        if [ "$kind" = codeql ]; then prefix="codeql-"; else prefix="dependabot-pr-"; fi
        slug="$key"
        ;;
    container) prefix="container-" slug=$(_caf_slug_lower "$key") ;;
    *)
        _caf_fail "知らない種類です: ${kind}"
        return 1
        ;;
    esac
    # 英数字を1つも含まない key からは、ブランチ名を作らない
    [[ "$slug" =~ [a-z0-9] ]] || {
        _caf_fail "key からブランチ名を作れません(種類 ${kind})"
        return 1
    }
    run_name="claude-auto-fix ${kind} ${key}"
    if [ -n "$pr" ] || [ -n "$sha" ]; then
        [[ "$pr" =~ ^[1-9][0-9]*$ ]] && [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || {
            _caf_fail "PR の番号か head の SHA の形が違います"
            return 1
        }
        run_name="${run_name} pr#${pr}@${sha:0:12}"
    fi
    jq -nc --arg branch "fix/claude-auto-fix-${prefix}${slug}" --arg run_name "$run_name" '{branch: $branch, run_name: $run_name}'
}

# 目印の名前と欄の形を確かめる。値に空白と > を入れると、目印の終わりと区切りが崩れるので断る
_caf_check_marker_args() {
    local name="$1" field
    shift
    [[ "$name" =~ ^[a-z]+(-[a-z]+)*$ ]] || {
        _caf_fail "目印の名前の形が違います: ${name}"
        return 1
    }
    for field in "$@"; do
        [[ "$field" =~ ^[a-z_]+=[^[:space:]\>]+$ ]] || {
            _caf_fail "目印の欄の形が違います: ${field}"
            return 1
        }
    done
}

marker_line() {
    _caf_check_marker_args "$@" || return 1
    local name="$1"
    shift
    if [ "$#" -eq 0 ]; then
        printf '<!-- claude-auto-fix-%s -->\n' "$name"
    else
        printf '<!-- claude-auto-fix-%s %s -->\n' "$name" "$*"
    fi
}

latest_marker() {
    _caf_check_marker_args "$@" || return 1
    local name="$1" want out
    shift
    want=$(jq -nc '[$ARGS.positional[] | capture("^(?<k>[^=]+)=(?<v>.*)$") | {(.k): .v}] | add // {}' --args "$@") || return 1
    out=$(jq -r --arg name "$name" --arg bot "$CAF_BOT_LOGIN" --argjson want "$want" '
        if type != "array" then error("本文とコメントの一覧が配列ではありません") else . end
        | [.[] | select((.user.login? // "") == $bot) | select((.body | type) == "string")]
        | sort_by(.created_at // "")
        | [.[] | .body
            | scan("<!-- claude-auto-fix-" + $name + "((?: [a-z_]+=[^\\s>]+)*) -->")
            | .[0]
            | [splits(" ") | select(length > 0) | capture("^(?<k>[a-z_]+)=(?<v>.*)$") | {(.k): .v}]
            | add // {}]
        | map(select(. as $m | all($want | to_entries[]; $m[.key] == .value)))
        | last // empty
        | tojson') || {
        _caf_fail "本文とコメントの一覧を読めません(目印 ${name})"
        return 1
    }
    [ -z "$out" ] || printf '%s\n' "$out"
}

issue_state() {
    local kind="$1" key="$2" latest
    latest=$(latest_marker issue "key=${kind}:${key}") || return 1
    [ -z "$latest" ] || jq -r '.kind // empty' <<<"$latest"
}

fixable_red_checks() {
    local required="$1" red="$2" out
    [ -f "$required" ] || {
        _caf_fail "期待一覧がありません: ${required}"
        return 1
    }
    out=$(jq -c --argjson red "$red" '
        if (.checks | type) != "array" then error("期待一覧の checks が配列ではありません")
        elif ($red | type) != "array" or ($red | any(type != "string")) then error("赤の検査が文字列の配列ではありません")
        else $red - (["dependency-review"] + [.checks[] | select(.approval_gated == true) | .context])
        end' "$required" 2>&1) || {
        _caf_fail "直しても緑にならない検査を除けません: ${out}"
        return 1
    }
    printf '%s\n' "$out"
}

# ---------------------------------------------------------------------
# GitHub を読む関数(読むだけで、GitHub の中身を変えない)
# どれも環境変数 GITHUB_REPOSITORY(owner/name)のリポジトリを読む。
# ---------------------------------------------------------------------

CAF_LABEL="claude-auto-fix"
CAF_BRANCH_PREFIX="fix/claude-auto-fix-"
CAF_TARGET_WORKFLOW="claude-auto-fix-target.yaml"
# 対象ごとの実行を起動する専用のブランチ。claude-auto-fix-run-branch.sh が main の最新のコミットに合わせ、
# claude-auto-fix-dispatch.sh と claude-auto-fix-sweep.sh が gh workflow run --ref に渡す。
# fix/claude-auto-fix- で始まらないので、Claude の変更のブランチと vuln-fix のブランチの名前と重ならない
CAF_RUN_BRANCH="claude-auto-fix/run"
# container-scan-issue.sh が起票する Issue の題名の前の部分
CAF_CONTAINER_TITLE_PREFIX="コンテナ脆弱性: "
# 鍵の取り替えを求める Issue の題名と本文の目印。claude-auto-fix-report.sh が起票し、claude-auto-fix-dispatch.sh が読む
CAF_KEY_TITLE="Claude を動かす鍵を取り替えてください"
CAF_KEY_MARKER="<!-- claude-auto-fix-key -->"

# key_issues [<閉じた日時の下限>]  < Issue の一覧の JSON(gh api --paginate --slurp の応答)
#   github-actions[bot] が起票した鍵の Issue(題名が CAF_KEY_TITLE で、本文に CAF_KEY_MARKER を持つ Issue)の
#   番号を1行に1つ出す。利用者は同じ題名と目印で Issue を起票できるので、作成者も見る。
#   閉じた日時の下限を渡すと、その日時より後に閉じた Issue だけを出す。一覧の形が違えば失敗する
key_issues() {
    jq -r --arg bot "$CAF_BOT_LOGIN" --arg title "$CAF_KEY_TITLE" --arg mark "$CAF_KEY_MARKER" --arg since "${1:-}" \
        "$_CAF_JQ_PAGES"'
        pages
        | .[] | select((has("pull_request") | not) and (.user.login? // "") == $bot and .title? == $title
            and ((.body // "") | type) == "string" and ((.body // "") | contains($mark))
            and ($since == "" or (((.closed_at // "") | type) == "string" and (.closed_at // "") >= $since)))
        | .number | tostring' 2>/dev/null
}

_caf_repo() {
    [ -n "${GITHUB_REPOSITORY:-}" ] || {
        _caf_fail "GITHUB_REPOSITORY がありません"
        return 1
    }
    printf '%s\n' "$GITHUB_REPOSITORY"
}

# gh api --paginate --slurp の応答(ページごとの配列の配列)を1つの配列にする jq の定義
_CAF_JQ_PAGES='def pages: if type == "array" and all(type == "array") then add // [] else error("ページの配列ではありません") end;'

# 対象ごとの実行の一覧の1件が、このリポジトリの専用のブランチ CAF_RUN_BRANCH で、claude-auto-fix-target.yaml を
# 手で起動した実行かを見る jq の定義。使い方: own_run($repo)。fork の PR は、claude-auto-fix-target.yaml に
# pull_request のきっかけを足すと、同じワークフローの一覧に実行を残せる。その実行は、好きな表示名と結果のファイルを
# 持てるので、数えると、利用者が対象と入力を選べてしまう(要件1の6)。この仕組みは対象ごとの実行を
# gh workflow run --ref "$CAF_RUN_BRANCH" で起動する。専用のブランチのほかで起動された実行は、ref-check ジョブで
# 止まり、結果のファイルを書かないので、数えない
# (引数は jq の式で受ける。呼ぶ側で $repo を渡す)
_CAF_JQ_OWN_RUN='def own_run(repo): .event? == "workflow_dispatch" and .head_branch? == "'"$CAF_RUN_BRANCH"'"
    and (.repository.full_name? // "") == repo and (.head_repository.full_name? // "") == repo
    and (((.path? // "") | if type == "string" then split("@")[0] else "" end) == ".github/workflows/claude-auto-fix-target.yaml");'

# 版の大小を比べる jq の定義。backend-vuln-fix.sh の go_plan の vkey と同じ見方で、
# 先頭の go と v と + 以降を除き、数の3つの並びと、プレリリースかどうかで比べる
# (プレリリースは、同じ番号の正式な版より古い)
_CAF_JQ_VKEY='def vkey: ltrimstr("go") | ltrimstr("v") | split("+")[0] | split("-")
    | (((.[0] | split(".") | map(tonumber? // 0)) + [0, 0, 0])[0:3]) + [if length > 1 then 0 else 1 end];'

# claude_prs
#   開いている Claude の変更の PR を、JSON の配列 [{number, branch, head_sha, url, body}] で出す。
#   Claude の変更の PR とみなすのは、このリポジトリのブランチから出され、ブランチ名が
#   fix/claude-auto-fix- で始まり、ラベル claude-auto-fix を持つ PR だけである。
#   fork のブランチは誰でも同じ名前で作れるので、head のリポジトリがこのリポジトリであることも求める。
claude_prs() {
    local repo raw out
    repo=$(_caf_repo) || return 1
    raw=$(gh api --paginate --slurp "repos/${repo}/pulls?state=open&per_page=100") || {
        _caf_fail "開いている PR の一覧を読めません"
        return 1
    }
    out=$(jq -c --arg repo "$repo" --arg prefix "$CAF_BRANCH_PREFIX" --arg label "$CAF_LABEL" "$_CAF_JQ_PAGES"'
        pages
        | map(select(((.head.ref? // "") | type) == "string" and ((.head.ref? // "") | startswith($prefix))
            and (.head.repo.full_name? // "") == $repo
            and any(.labels[]?; .name? == $label)))
        | map({number, branch: .head.ref, head_sha: .head.sha, url: .html_url, body: (.body // "")})' <<<"$raw" 2>/dev/null) || {
        _caf_fail "開いている PR の一覧の形が違います"
        return 1
    }
    printf '%s\n' "$out"
}

# claude_pr <種類> <key>
#   同じ key の開いている Claude の変更の PR を、claude_prs の1件の JSON で出す。無ければ何も出さない
claude_pr() {
    local names branch prs
    names=$(target_names "$1" "$2") || return 1
    branch=$(jq -r .branch <<<"$names")
    prs=$(claude_prs) || return 1
    jq -c --arg b "$branch" 'map(select(.branch == $b)) | first // empty' <<<"$prs"
}

# _caf_outcome_from_run <実行の JSON>
#   取り消されて結果のファイルが無い実行を、表示名の種類と key から、結果が unavailable の結果のファイルの形にする
_caf_outcome_from_run() {
    jq -ce '
        (.title | capture("^claude-auto-fix (?<kind>npm|maven|go-stdlib|go-module|codeql|container|dependabot) (?<key>[A-Za-z0-9@/._:+~-]+)(?: pr#(?<pr>[1-9][0-9]*)@[0-9a-f]{12})?$")) as $t
        | {kind: $t.kind, key: $t.key,
           reason: (if $t.pr == null then null else "red-check" end),
           pr: (if $t.pr == null then null else ($t.pr | tonumber) end),
           checks: null, detail: null, result: "unavailable", cause: "cancelled",
           pr_url: null, run_url: .url, head_sha: null, finished_at: .finished_at}' <<<"$1" 2>/dev/null
}

# recent_outcomes
#   claude-auto-fix-target.yaml の、4日前より後に始まって終わった実行の結果のファイル(成果物 outcome)を、
#   実行の始まった順に JSON の配列で出す。結果のファイルに実行の URL が無ければ足す。
#   結果を書く前に取り消された実行は、結果のファイルが無いので、表示名から種類と key を読み、
#   結果を unavailable、理由を cancelled にした要素を出す。
#   取り消されていない実行に結果のファイルが無いときと、結果のファイルの形が違うときは失敗する。
recent_outcomes() {
    local repo cutoff raw runs run id conclusion count dir rec out="[]"
    repo=$(_caf_repo) || return 1
    cutoff=$(date -u -d "@$(($(date -u +%s) - 4 * 86400))" +%Y-%m-%dT%H:%M:%SZ) || {
        _caf_fail "4日前の日時を作れません"
        return 1
    }
    raw=$(gh api --paginate --slurp "repos/${repo}/actions/workflows/${CAF_TARGET_WORKFLOW}/runs?created=%3E%3D${cutoff}&per_page=100") || {
        _caf_fail "対象ごとの実行の一覧を読めません"
        return 1
    }
    runs=$(jq -c --arg cutoff "$cutoff" --arg repo "$repo" "$_CAF_JQ_OWN_RUN"'
        if type == "array" and all(type == "object" and (.workflow_runs | type) == "array") then [.[].workflow_runs[]]
        else error("実行の一覧の形が違います") end
        | map(select(type == "object" and own_run($repo) and (.created_at // "") >= $cutoff and .status == "completed"))
        | sort_by(.created_at, .id)
        | map({id, title: (.display_title // ""), conclusion, url: .html_url, finished_at: .updated_at})
        | .[]' <<<"$raw" 2>/dev/null) || {
        _caf_fail "対象ごとの実行の一覧の形が違います"
        return 1
    }
    while IFS= read -r run; do
        [ -n "$run" ] || continue
        id=$(jq -r .id <<<"$run")
        conclusion=$(jq -r '.conclusion // ""' <<<"$run")
        [[ "$id" =~ ^[0-9]+$ ]] || {
            _caf_fail "実行の ID の形が違います: ${id}"
            return 1
        }
        count=$(gh api "repos/${repo}/actions/runs/${id}/artifacts?name=outcome" |
            jq -e '.artifacts | if type == "array" then map(select(.name == "outcome" and (.expired | not))) | length else error("x") end' 2>/dev/null) || {
            _caf_fail "実行 ${id} の成果物の一覧を読めません"
            return 1
        }
        if [ "$count" -gt 0 ]; then
            dir=$(mktemp -d) || return 1
            if ! gh run download "$id" -R "$repo" -n outcome -D "$dir" >/dev/null 2>&1 ||
                ! rec=$(jq -ce --arg url "$(jq -r .url <<<"$run")" '
                    if type == "object"
                        and (.kind | IN("npm", "maven", "go-stdlib", "go-module", "codeql", "container", "dependabot"))
                        and ((.key | type) == "string" and (.key | test("^[A-Za-z0-9@/._:+~-]+$")))
                        and (.result | IN("pr", "unfixed", "unavailable", "key", "blocked", "gone", "skipped"))
                    then .run_url = (.run_url // $url) else error("x") end' "$dir/outcome.json" 2>/dev/null); then
                rm -rf "$dir"
                _caf_fail "実行 ${id} の結果のファイルを読めません"
                return 1
            fi
            rm -rf "$dir"
        elif [ "$conclusion" = cancelled ]; then
            rec=$(_caf_outcome_from_run "$run") || {
                _caf_fail "取り消された実行 ${id} の表示名から種類と key を読めません"
                return 1
            }
        else
            _caf_fail "実行 ${id} は取り消されていないのに結果のファイルがありません"
            return 1
        fi
        out=$(jq -c --argjson rec "$rec" '. + [$rec]' <<<"$out") || return 1
    done <<<"$runs"
    printf '%s\n' "$out"
}

# _caf_gomod_version <種類> <key>  < go.mod
#   go-stdlib では toolchain の行の版(無ければ go の行の版。Go は toolchain の行が無いとき go の行の版を使う)を、
#   go-module では require の部品の版を出す。部品が go.mod に無ければ何も出さない
_caf_gomod_version() {
    local kind="$1" key="$2"
    if [ "$kind" = go-stdlib ]; then
        awk '$1 == "toolchain" && t == "" { t = $2 } $1 == "go" && g == "" { g = $2 }
            END { if (t != "") print t; else if (g != "") print g; else exit 1 }'
    else
        awk -v m="${key%@*}" '
            /^require[[:space:]]*\(/ { blk = 1; next }
            blk && /^\)/ { blk = 0; next }
            blk && $1 == m { print $2; exit }
            !blk && $1 == "require" && $2 == m { print $3; exit }'
    fi
}

# target_gone <種類> <key> [<期待一覧のファイル>]
#   対象が消えたかを、消えていれば true、残っていれば false で出す(期待一覧は dependabot で使う)。
#   見分け方は design.md のデータの形の節の「対象が消えたかの見分け方」の表のとおり:
#     npm と maven            組(部品の名前と修正版)の Dependabot の警告が1つも開いていない
#     go-stdlib と go-module  main の go.mod の toolchain か部品の版が、組の修正版以上である
#     codeql                  警告の状態が open でない
#     container               ラベル container-vuln の、仕組みが起票した Issue が閉じている
#     dependabot              Dependabot の PR が閉じているかマージされたか、期待一覧で止めていない
#                             (state が active の)検査が head のコミットですべて通っている。
#                             同じ検査は最も新しい結論で見る
target_gone() {
    local kind="$1" key="$2" required="${3:-}" repo raw out pr state merged sha cur
    if [ -z "$key" ] || ! _caf_valid_key "$key"; then
        _caf_fail "key の形が違います(種類 ${kind})"
        return 1
    fi
    repo=$(_caf_repo) || return 1
    case "$kind" in
    npm | maven)
        [[ "$key" == ?*@?* ]] || {
            _caf_fail "${kind} の key に部品の名前と修正版がありません: ${key}"
            return 1
        }
        raw=$(gh api --paginate --slurp "repos/${repo}/dependabot/alerts?state=open&ecosystem=${kind}&per_page=100") || {
            _caf_fail "Dependabot の警告を読めません"
            return 1
        }
        out=$(jq -r --arg eco "$kind" --arg n "${key%@*}" --arg v "${key##*@}" "$_CAF_JQ_PAGES"'
            pages
            | any(.[]; .state? == "open" and .dependency.package.ecosystem? == $eco and .dependency.package.name? == $n
                and .security_vulnerability.first_patched_version.identifier? == $v)
            | not' <<<"$raw" 2>/dev/null) || {
            _caf_fail "Dependabot の警告の形が違います"
            return 1
        }
        ;;
    go-stdlib | go-module)
        if [ "$kind" = go-module ] && ! [[ "$key" == ?*@?* ]]; then
            _caf_fail "go-module の key に部品と修正版がありません: ${key}"
            return 1
        fi
        # 中身をそのまま受け取る(https://docs.github.com/en/rest/repos/contents#get-repository-content)
        raw=$(gh api -H "Accept: application/vnd.github.raw+json" "repos/${repo}/contents/backend/go.mod?ref=main") || {
            _caf_fail "main の backend/go.mod を読めません"
            return 1
        }
        cur=$(_caf_gomod_version "$kind" "$key" <<<"$raw") || {
            _caf_fail "main の backend/go.mod に go の版がありません"
            return 1
        }
        if [ -z "$cur" ]; then
            out=true
        else
            out=$(jq -nr --arg cur "$cur" --arg fix "${key##*@}" "$_CAF_JQ_VKEY"'($cur | vkey) >= ($fix | vkey)') || return 1
        fi
        ;;
    codeql)
        [[ "$key" =~ ^[1-9][0-9]*$ ]] || {
            _caf_fail "codeql の key が番号ではありません"
            return 1
        }
        raw=$(gh api "repos/${repo}/code-scanning/alerts/${key}") || {
            _caf_fail "CodeQL の警告 ${key} を読めません"
            return 1
        }
        out=$(jq -r 'if (.state | type) == "string" then .state != "open" else error("x") end' <<<"$raw" 2>/dev/null) || {
            _caf_fail "CodeQL の警告 ${key} の形が違います"
            return 1
        }
        ;;
    container)
        raw=$(gh api --paginate --slurp "repos/${repo}/issues?labels=container-vuln&state=open&per_page=100") || {
            _caf_fail "ラベル container-vuln の Issue を読めません"
            return 1
        }
        out=$(jq -r --arg title "${CAF_CONTAINER_TITLE_PREFIX}${key}" --arg bot "$CAF_BOT_LOGIN" "$_CAF_JQ_PAGES"'
            pages
            | any(.[]; (has("pull_request") | not) and (.user.login? // "") == $bot and .title? == $title)
            | not' <<<"$raw" 2>/dev/null) || {
            _caf_fail "ラベル container-vuln の Issue の形が違います"
            return 1
        }
        ;;
    dependabot)
        [[ "$key" =~ ^[1-9][0-9]*$ ]] || {
            _caf_fail "dependabot の key が番号ではありません"
            return 1
        }
        [ -n "$required" ] && [ -f "$required" ] || {
            _caf_fail "期待一覧がありません: ${required}"
            return 1
        }
        raw=$(gh api "repos/${repo}/pulls/${key}") || {
            _caf_fail "PR #${key} を読めません"
            return 1
        }
        pr=$(jq -r 'if (.state | type) == "string" and (.head.sha | type) == "string" then "\(.state) \(.merged == true) \(.head.sha)" else error("x") end' <<<"$raw" 2>/dev/null) || {
            _caf_fail "PR #${key} の形が違います"
            return 1
        }
        read -r state merged sha <<<"$pr"
        if [ "$state" != open ] || [ "$merged" = true ]; then
            out=true
        else
            [[ "$sha" =~ ^[0-9A-Za-z]+$ ]] || {
                _caf_fail "PR #${key} の head の SHA の形が違います"
                return 1
            }
            raw=$(gh api "repos/${repo}/commits/${sha}/check-runs?per_page=100") || {
                _caf_fail "PR #${key} の検査の結果を読めません"
                return 1
            }
            out=$(jq -r --slurpfile req "$required" '
                ($req[0].checks | if type == "array" then map(select(.state == "active") | .context) else error("x") end) as $need
                | if (.check_runs | type) != "array" then error("x") else . end
                | [.check_runs[] | select((.name | type) == "string" and (.name | IN($need[])))]
                | group_by(.name) | map(max_by([(.started_at // ""), (.id // 0)])) as $latest
                | all($need[]; . as $n | any($latest[]; .name == $n and (.conclusion | IN("success", "skipped", "neutral"))))' <<<"$raw" 2>/dev/null) || {
                _caf_fail "PR #${key} の検査の結果か期待一覧の形が違います"
                return 1
            }
        fi
        ;;
    *)
        _caf_fail "知らない種類です: ${kind}"
        return 1
        ;;
    esac
    printf '%s\n' "$out"
}

# 使い方: cooldown_needed <ci-tool-versions.json> <変えたパスを1行に1つ書いたファイル>
# 変えたパスに、依存の版を宣言するファイル、Go の版を書くファイル、CI の道具の版を書くファイルの
# どれかがあれば true を、無ければ false を出す。dependency-cooldown の検査の3つの判定の手順は、
# これらのファイルが変わったときに版を調べる。行の末尾の CR は除いて比べる
cooldown_needed() {
    [ "$#" -eq 2 ] || {
        _caf_fail "使い方: cooldown_needed <ci-tool-versions.json> <変えたパスの一覧のファイル>"
        return 1
    }
    local versions="$1" list="$2" tool_files path f
    [ -f "$versions" ] || {
        _caf_fail "ci-tool-versions.json がありません: ${versions}"
        return 1
    }
    [ -f "$list" ] || {
        _caf_fail "変えたパスの一覧のファイルがありません: ${list}"
        return 1
    }
    declare -F go_release_is_target >/dev/null 2>&1 || {
        _caf_fail "go_release_is_target がありません"
        return 1
    }
    tool_files=$(jq -r '
        if (.tools | type) != "object" then error("x") else . end
        | .tools[]
        | if (.ci | type) != "array" then error("x") else . end
        | (.ci[] | .file), (if has("dev") then .dev.file else empty end)
        | if type != "string" then error("x") else . end' "$versions" 2>/dev/null) || {
        _caf_fail "ci-tool-versions.json の形が違います: ${versions}"
        return 1
    }
    while IFS= read -r path || [ -n "$path" ]; do
        path="${path%$'\r'}"
        [ -n "$path" ] || continue
        for f in "${CAF_COOLDOWN_DEP_FILES[@]}"; do
            if [ "$path" = "$f" ]; then
                echo true
                return 0
            fi
        done
        if go_release_is_target "$path"; then
            echo true
            return 0
        fi
        while IFS= read -r f; do
            if [ -n "$f" ] && [ "$path" = "$f" ]; then
                echo true
                return 0
            fi
        done <<<"$tool_files"
    done <"$list"
    echo false
}

# 使い方: cooldown_outcome <依存の判定の終わり方> <Go の判定の終わり方> <CI の道具の判定の終わり方>
# 3つは check-dependency-cooldown.sh と check-go-release-age.sh と check-ci-tool-release-age.sh の
# 終わり方。判定できなかったスクリプトが1つでもあれば、ほかの終わり方によらず fail を出す。
# そうでなく、どれかが1(公開から時間が経っていない版がある)なら blocked を、そのほかは ship を出す
cooldown_outcome() {
    [ "$#" -eq 3 ] || {
        _caf_fail "使い方: cooldown_outcome <依存の判定の終わり方> <Go の判定の終わり方> <CI の道具の判定の終わり方>"
        return 1
    }
    case "$1" in 0 | 1 | 3) ;; *) echo fail && return 0 ;; esac
    case "$2" in 0 | 1) ;; *) echo fail && return 0 ;; esac
    case "$3" in 0 | 1) ;; *) echo fail && return 0 ;; esac
    if [ "$1" = 1 ] || [ "$2" = 1 ] || [ "$3" = 1 ]; then
        echo blocked
    else
        echo ship
    fi
}
