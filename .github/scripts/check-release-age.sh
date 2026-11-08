#!/usr/bin/env bash
# =====================================================================
# 更新PRの自動マージを予約してよいかの判定(dependabot-auto-merge から実行)
#
# 判定: PR の差分に、下の対象の表にあるイメージの FROM 行の更新があるかを見る。
#   無い                     → reserve(今までどおり予約する)
#   版(タグ)が変わった       → GitHub のリリースの公開日時から72時間経っていれば reserve、
#                              経っていなければ wait(1日1回の見直しで確かめ直す)
#   公開日時を取れない       → notify(PR にコメントして所有者に知らせる。見直しは続ける)
#   版が同じで中身だけ変わった → notify(PR にコメントして所有者に知らせる)
#
# なぜ必要か:
#   Dependabot の既定の待ち期間(公開から一定時間は更新PRを作らない)は、公開日時を
#   取れる置き場でしか効かない。ghcr.io のイメージ(tflint)では公開日時を取れず、
#   Dependabot は待たずにPRを作る。公開直後の版が自動でマージされるのを防ぐため、
#   ここで72時間を数える。
#
# なぜ GitHub のリリースの published_at だけを使うのか:
#   GitHub が付ける値で、公開した側が後から書き換えられない。イメージの中の作成日時
#   (image config の created)や置き場の更新日時は、公開した側が自由に付けられるため使わない。
#
# なぜ中身だけの更新を知らせるのか:
#   同じ版の名前のまま中身(digest)が差し替えられた状態で、版の公開日時では待つかどうかを
#   決められない。人が確かめるまで予約しない。
#
# Go のモジュール(gomod)の更新:
#   PR の差分の go.mod で足された行から、モジュールと版の組を読む。組ごとに、Go のモジュールの
#   索引(index.golang.org)に初めて取り込まれた時刻を lib-gomod-index.sh で調べる。
#   公開の時刻の検査(check-dependency-cooldown.sh)と同じ調べ方である。
#     72時間経っていない組がある → wait(1日1回の見直しで確かめ直す)
#     すべて72時間経った         → reserve
#     索引を読めない             → notify(PR にコメントして所有者に知らせる。見直しは続ける)
#   go の行と toolchain の行は、モジュールの版ではなく Go の版の指定なので、照らさない。
#   go.sum は、go.mod の組の指紋を書くだけなので読まない。
#   公開の時刻の検査と同じ基準で、自動マージの予約も、公開から72時間経つまで付けない。
#
# 判定できないとき(終了コード 2):
#   差分を取れない、対象のイメージの行が差分にあるのにタグや digest を読み取れない、
#   go.mod の差分を読めない(差分が大きすぎる、足された行を読み取れない)、
#   知らせのコメントを確実に付けられない。予約してよいという判定を出さずに止める。
#
# テスト: .github/scripts/tests/test-check-release-age.sh
# 使い方: check-release-age.sh <PR番号>
#   環境変数 GH_TOKEN / GITHUB_REPOSITORY / GITHUB_REPOSITORY_OWNER(必須)
#   NOW_EPOCH(任意。テスト用の時刻固定)
#   GOMOD_INDEX_BASE(任意。テスト用の索引の差し替え。既定 https://index.golang.org)
# 出力: 標準出力に次の2行だけを出す($GITHUB_OUTPUT にそのまま足せる形)。
#   decision=reserve|wait|notify
#   reason=<理由>
# 終了コード: 0 = 判定できた / 2 = 判定できなかった
# =====================================================================
set -euo pipefail

# 対象の表: イメージ ⇔ 公開日時を読む GitHub のリポジトリ。
# Dependabot の待ち期間が効かない置き場(Docker Hub 以外)から入れるイメージが
# 増えたら、ここに足す。
TARGETS=(
    "ghcr.io/terraform-linters/tflint terraform-linters/tflint"
)
WAIT_SECONDS=259200 # 72時間

undecided() {
    echo "判定できませんでした: $1" >&2
    exit 2
}

PR="${1:-}"
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || undecided "使い方: check-release-age.sh <PR番号>"
REPO="${GITHUB_REPOSITORY:-}"
OWNER="${GITHUB_REPOSITORY_OWNER:-}"
[ -n "$REPO" ] || undecided "GITHUB_REPOSITORY がありません"
[ -n "$OWNER" ] || undecided "GITHUB_REPOSITORY_OWNER がありません"
[ -n "${GH_TOKEN:-}" ] || undecided "GH_TOKEN がありません"
NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW_EPOCH" =~ ^[0-9]+$ ]] || undecided "NOW_EPOCH が数字ではありません"

TMP=$(mktemp -d) || undecided "作業用のディレクトリを作れません"
trap 'rm -rf "$TMP"' EXIT

export GOMOD_INDEX_BASE="${GOMOD_INDEX_BASE:-https://index.golang.org}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.github/scripts/lib-gomod-index.sh
. "$SCRIPT_DIR/lib-gomod-index.sh"

# --- PR の差分 -------------------------------------------------------------------
# --paginate はページごとの配列を続けて出すため、jq -s でまとめて読む。
if ! gh api --paginate "repos/${REPO}/pulls/${PR}/files" >"$TMP/files.json" 2>"$TMP/files.err"; then
    cat "$TMP/files.err" >&2
    undecided "PR #${PR} のファイル一覧を取れません"
fi
if ! jq -s -e 'length > 0 and all(.[]; type == "array")' "$TMP/files.json" >/dev/null 2>&1; then
    undecided "PR #${PR} のファイル一覧の形が想定と違います"
fi

# 差分が大きすぎると patch が付かない。Dockerfile の patch が無ければ、
# 対象のイメージの行が変わったかを確かめられない。
# ファイル名は大文字小文字を区別せず、Containerfile(Podman 等の呼び名)も含める。
nopatch=$(jq -s -r '
    add | .[]
    | select((.patch | type) != "string")
    | .filename // ""
    | select(test("(^|/)[^/]*(dockerfile|containerfile)[^/]*$"; "i"))' "$TMP/files.json") ||
    undecided "PR #${PR} のファイル一覧を読めません"
if [ -n "$nopatch" ]; then
    undecided "差分が大きすぎて中身を読めない Dockerfile があります: $(printf '%s' "$nopatch" | tr '\n' ' ')"
fi

# --- 対象のイメージごとの判定 -------------------------------------------------------
# 結果は T_DECISION / T_REASON / T_KEY(知らせの目印)/ T_DETAIL(コメントの本文用)に入れる。
judge_target() {
    local image="$1" gh_repo="$2"
    local name="${image#*/}" # 例: terraform-linters/tflint
    local image_re="${image//./\\.}"
    local line_re="^([+-])[[:space:]]*[Ff][Rr][Oo][Mm][[:space:]]+${image_re}:([A-Za-z0-9][A-Za-z0-9._-]*)@sha256:([0-9a-f]{64})([[:space:]]+[Aa][Ss][[:space:]]+[A-Za-z0-9._-]+)?[[:space:]]*$"
    local lines line removed=() added=()

    T_DECISION="reserve"
    T_REASON="${name} の更新ではない"
    T_KEY=""
    T_DETAIL=""

    # 変更した行(+ と -)のうち、イメージの名前を含む行を全て取り出す。
    # 名前を含むのに読み取れない行が1つでもあれば、予約に倒さず判定できないとする。
    lines=$(jq -s -r --arg name "$name" '
        add | .[]
        | select((.patch | type) == "string")
        | .patch | split("\n") | .[]
        | rtrimstr("\r")
        | select(test("^[+-]"))
        | select(contains($name))' "$TMP/files.json") ||
        undecided "PR #${PR} の差分を読めません"
    [ -n "$lines" ] || return 0

    while IFS= read -r line; do
        if [[ "$line" =~ $line_re ]]; then
            if [ "${BASH_REMATCH[1]}" = "-" ]; then
                removed+=("${BASH_REMATCH[2]} ${BASH_REMATCH[3]}")
            else
                added+=("${BASH_REMATCH[2]} ${BASH_REMATCH[3]}")
            fi
        else
            undecided "${name} の行からタグと digest を読み取れません: ${line}"
        fi
    done <<<"$lines"

    if [ "${#removed[@]}" -ne 1 ] || [ "${#added[@]}" -ne 1 ]; then
        undecided "${name} の行の削除と追加が1つずつではありません(削除 ${#removed[@]}、追加 ${#added[@]})"
    fi

    local old_tag="${removed[0]% *}" old_digest="${removed[0]#* }"
    local new_tag="${added[0]% *}" new_digest="${added[0]#* }"

    if [ "$old_tag" = "$new_tag" ]; then
        if [ "$old_digest" = "$new_digest" ]; then
            T_REASON="${name} の版と中身は変わっていない"
            return 0
        fi
        T_DECISION="notify"
        T_REASON="中身だけの更新(${name} ${new_tag} の digest だけが変わった)"
        T_KEY="digest-only"
        T_DETAIL="${name} の版(${new_tag})の名前は変わらず、中身の指紋(digest)だけが変わっています。公開した側が同じ版の名前のまま中身を差し替えた可能性があり、版の公開日時では待つかどうかを決められません。"
        return 0
    fi

    # 版が変わった。GitHub のリリースの published_at だけを使う。
    local published_iso published ready_iso
    if ! gh api "repos/${gh_repo}/releases/tags/${new_tag}" >"$TMP/release.json" 2>"$TMP/release.err" ||
        ! published=$(jq -r '.published_at | if type == "string" then fromdateiso8601 | floor else error("published_at が無い") end' \
            "$TMP/release.json" 2>/dev/null) ||
        ! [[ "$published" =~ ^[0-9]+$ ]]; then
        cat "$TMP/release.err" >&2 2>/dev/null || true
        T_DECISION="notify"
        T_REASON="公開日時を取れない(${gh_repo} のリリース ${new_tag})"
        T_KEY="unavailable"
        T_DETAIL="GitHub の ${gh_repo} のリリース(${new_tag})の公開日時を読めなかったため、公開から72時間経ったかを確かめられません。"
        return 0
    fi
    published_iso=$(jq -r '.published_at' "$TMP/release.json")
    ready_iso=$(jq -n -r --argjson t "$((published + WAIT_SECONDS))" '$t | todate')

    if [ "$((NOW_EPOCH - published))" -ge "$WAIT_SECONDS" ]; then
        T_REASON="${name} ${new_tag} は公開から72時間経った(公開 ${published_iso})"
    else
        T_DECISION="wait"
        T_REASON="${name} ${new_tag} は公開から72時間経っていない(公開 ${published_iso}。${ready_iso} 以降の見直しで予約する)"
    fi
}

# --- Go のモジュールの更新の判定 ---------------------------------------------------
# 結果は judge_target と同じ T_DECISION / T_REASON / T_KEY / T_DETAIL に入れる。
# go.mod の足された行に組が1つも無ければ reserve にし、T_GOMOD を空にする。

# 使い方: gomod_unquote <モジュールの名前>。go.mod の書き方で囲んだ引用符(" か `)を外す
gomod_unquote() {
    local m="$1"
    case "$m" in
    \"*\" | \`*\`) m="${m:1:${#m}-2}" ;;
    esac
    printf '%s' "$m"
}

judge_gomod() {
    local nopatch lines line body rhs young first ready block=""
    local re_pair='^(require[[:space:]]+)?([^[:space:]()]+)[[:space:]]+(v[0-9][^[:space:]]*)$'
    local re_rhs='^([^[:space:]]+)[[:space:]]+(v[0-9][^[:space:]]*)$'
    # 版を照らさない指示: Go の版の指定(go と toolchain)、モジュールの名前、道具の指定、
    # GODEBUG の指定、使わない版の指定(exclude と retract)、Go の道具が見ないフォルダの指定(ignore)
    local re_skip='^(go|toolchain|module|tool|godebug|exclude|retract|ignore)([[:space:]]|$)'

    T_DECISION="reserve"
    T_REASON="Go のモジュールの更新ではない"
    T_KEY=""
    T_DETAIL=""
    T_GOMOD=""

    nopatch=$(jq -s -r '
        add | .[]
        | select((.patch | type) != "string")
        | .filename // ""
        | select(test("(^|/)go[.]mod$"))' "$TMP/files.json") ||
        undecided "PR #${PR} のファイル一覧を読めません"
    if [ -n "$nopatch" ]; then
        undecided "差分が大きすぎて中身を読めない go.mod があります: $(printf '%s' "$nopatch" | tr '\n' ' ')"
    fi
    # 足された行(+)と、ブロックの中かを知るための前後の行(空白で始まる行)を読む。
    # 差分のまとまりの境(@@ の行)では、ブロックの中かが分からないので、ブロックの外として読む
    lines=$(jq -s -r '
        add | .[]
        | select((.filename // "") | test("(^|/)go[.]mod$"))
        | .patch | split("\n") | .[]
        | rtrimstr("\r")
        | select(startswith("+") or startswith(" ") or startswith("@@"))' "$TMP/files.json") ||
        undecided "PR #${PR} の差分を読めません"
    [ -n "$lines" ] || return 0

    # 足された行からモジュールと版の組を読む。行の末尾の注釈(// indirect など)は外す。
    # replace の行は、置き換え先にモジュールと版があれば、その組を照らす(手元のフォルダへの置き換えは照らさない)。
    # exclude・retract・tool・godebug・ignore のブロックの中の行は照らさない。
    # モジュールの名前を引用符(" か `)で囲んだ行は、引用符を外して照らす。
    : >"$TMP/gomod-wanted.tsv"
    while IFS= read -r line; do
        if [ "${line:0:2}" = "@@" ]; then
            block=""
            continue
        fi
        body="${line:1}"
        body="${body%%//*}"
        body=$(printf '%s' "$body" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [[ "$body" =~ ^(require|replace|exclude|retract|tool|godebug|ignore)[[:space:]]*\($ ]]; then
            block="${BASH_REMATCH[1]}"
            continue
        fi
        if [ "$body" = ")" ]; then
            block=""
            continue
        fi
        [ "${line:0:1}" = "+" ] || continue
        [ -n "$body" ] || continue
        case "$block" in
        exclude | retract | tool | godebug | ignore) continue ;;
        esac
        case "$body" in
        *"=>"*)
            rhs=$(printf '%s' "${body#*=>}" | sed -e 's/^[[:space:]]*//')
            if [[ "$rhs" =~ $re_rhs ]]; then
                printf '%s\t%s\n' "$(gomod_unquote "${BASH_REMATCH[1]}")" "${BASH_REMATCH[2]}" >>"$TMP/gomod-wanted.tsv"
            elif ! [[ "$rhs" =~ ^[^[:space:]]+$ ]]; then
                undecided "go.mod の足された行を読み取れません: ${line}"
            fi
            continue
            ;;
        esac
        [[ "$body" =~ $re_skip ]] && continue
        if [[ "$body" =~ $re_pair ]]; then
            printf '%s\t%s\n' "$(gomod_unquote "${BASH_REMATCH[2]}")" "${BASH_REMATCH[3]}" >>"$TMP/gomod-wanted.tsv"
        else
            undecided "go.mod の足された行を読み取れません: ${line}"
        fi
    done <<<"$lines"
    [ -s "$TMP/gomod-wanted.tsv" ] || return 0
    T_GOMOD=1

    if ! gomod_index_ages "$TMP/gomod-wanted.tsv" "$TMP/gomod-ages.tsv"; then
        T_DECISION="notify"
        T_REASON="公開の時刻を取れない(Go のモジュールの索引 ${GOMOD_INDEX_BASE})"
        T_KEY="gomod-unavailable"
        T_DETAIL="Go のモジュールの索引(${GOMOD_INDEX_BASE})を読めなかったため、更新した Go のモジュールが公開から72時間経ったかを確かめられません。"
        return 0
    fi

    # 72時間経っていない組を「モジュール@版(取り込み <時刻>)」の形で並べる
    young=$(awk -F'\t' '$3 == "new" { print $1 "@" $2 "\t" $4 }' "$TMP/gomod-ages.tsv")
    if [ -z "$young" ]; then
        T_REASON="Go のモジュールの更新は、すべて公開から72時間経った"
        return 0
    fi
    first=$(printf '%s\n' "$young" | sort -t$'\t' -k2,2nr | head -n 1 | cut -f2)
    ready=$(jq -n -r --argjson t "$((first + WAIT_SECONDS))" '$t | todate')
    T_DECISION="wait"
    T_REASON="Go のモジュール $(printf '%s\n' "$young" | while IFS=$'\t' read -r pair t; do
        printf '%s(取り込み %s)、' "$pair" "$(jq -n -r --argjson t "$t" '$t | todate')"
    done | sed 's/、$//') は公開から72時間経っていない(${ready} 以降の見直しで予約する)"
}

# 対象が複数あるときは、知らせる > 待つ > 予約する の順に強い方を採る。
DECISION="reserve"
REASON=""
KEY=""
DETAIL=""
rank() {
    case "$1" in
    notify) echo 2 ;;
    wait) echo 1 ;;
    *) echo 0 ;;
    esac
}
for entry in "${TARGETS[@]}"; do
    judge_target "${entry% *}" "${entry#* }"
    if [ -z "$REASON" ] || [ "$(rank "$T_DECISION")" -gt "$(rank "$DECISION")" ]; then
        DECISION="$T_DECISION"
        REASON="$T_REASON"
        KEY="$T_KEY"
        DETAIL="$T_DETAIL"
    fi
done
# Go のモジュールの更新も、同じ順で強い方を採る。どちらも予約するときは、理由を並べる。
judge_gomod
if [ "$(rank "$T_DECISION")" -gt "$(rank "$DECISION")" ]; then
    DECISION="$T_DECISION"
    REASON="$T_REASON"
    KEY="$T_KEY"
    DETAIL="$T_DETAIL"
elif [ -n "$T_GOMOD" ] && [ "$DECISION" = "reserve" ]; then
    REASON="${REASON}、${T_REASON}"
fi

# --- 知らせ(notify のとき)---------------------------------------------------------
# 同じ目印のコメントが既にあれば重ねない。目印を数えるのは、このスクリプトが使う
# トークンの利用者(実運用では bot)が書いたコメントだけにする。他の人が同じ目印を
# 書いても、所有者への知らせは止めない。
# 利用者を確かめられない、既存のコメントを読めない、コメントを付けられないときは、
# 知らせを届けられたと言えないため判定できないとする。
if [ "$DECISION" = "notify" ]; then
    marker="<!-- release-age: ${KEY} -->"
    if ! gh api user >"$TMP/user.json" 2>"$TMP/user.err"; then
        cat "$TMP/user.err" >&2
        undecided "トークンの利用者を確かめられません"
    fi
    if ! self_login=$(jq -r '.login | if type == "string" and length > 0 then . else error("login が無い") end' \
        "$TMP/user.json" 2>/dev/null); then
        undecided "トークンの利用者の形が想定と違います"
    fi
    if ! gh api --paginate "repos/${REPO}/issues/${PR}/comments" >"$TMP/comments.json" 2>"$TMP/comments.err"; then
        cat "$TMP/comments.err" >&2
        undecided "PR #${PR} の既存のコメントを読めません"
    fi
    if ! exists=$(jq -s -r --arg m "$marker" --arg me "$self_login" '
        if all(.[]; type == "array") then . else error("形式が想定と違う") end
        | [.[][] | select((.user.login // "") == $me) | (.body // "") | contains($m)] | any' \
        "$TMP/comments.json" 2>/dev/null); then
        undecided "PR #${PR} の既存のコメントの形が想定と違います"
    fi

    if [ "$exists" != "true" ]; then
        if [ "$KEY" = "digest-only" ]; then
            ask="Claude Code に「PR #${PR} の tflint の中身だけの更新を調べて」と依頼してください。このPRは自動の見直しの対象から外れているため、調べ終わるまで自動ではマージされません。"
        elif [ "$KEY" = "gomod-unavailable" ]; then
            ask="何もしなくてかまいません。1日1回の見直しで Go のモジュールの索引をもう一度読み、公開から72時間経っていれば自動マージを予約します。数日たっても予約されないときは、Claude Code に「PR #${PR} の Go のモジュールの公開の時刻を取れない理由を調べて」と依頼してください。"
        else
            ask="何もしなくてかまいません。1日1回の見直しで公開日時をもう一度確かめ、公開から72時間経っていれば自動マージを予約します。数日たっても予約されないときは、Claude Code に「PR #${PR} の tflint のリリースの公開日時を取れない理由を調べて」と依頼してください。"
        fi
        {
            echo "@${OWNER}"
            echo ""
            echo "このPRの自動マージを予約していません。"
            echo ""
            echo "してほしいこと: ${ask}"
            echo ""
            echo "理由: ${DETAIL}"
            echo ""
            echo "$marker"
        } >"$TMP/comment.md"
        if ! gh pr comment "$PR" --repo "$REPO" --body-file "$TMP/comment.md" >&2; then
            undecided "PR #${PR} に知らせのコメントを付けられません"
        fi
    else
        echo "同じ知らせのコメントが既にあるため、コメントを重ねません。" >&2
    fi
fi

# 理由は1行にする($GITHUB_OUTPUT の key=value の形を崩さないため)
REASON=$(printf '%s' "$REASON" | tr -d '\r\n')
printf 'decision=%s\n' "$DECISION"
printf 'reason=%s\n' "$REASON"
