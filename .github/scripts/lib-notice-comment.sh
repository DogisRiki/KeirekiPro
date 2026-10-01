# shellcheck shell=bash
# =====================================================================
# 目印つきの知らせのコメントを1回だけ付ける共通の関数
# (reserve-auto-merge.sh / close-linked-issues.sh から source して使う)
#
# 知らせ:
#   仕組みが所有者に対処を求めるときに、PR または Issue に付けるコメント。
#   本文の末尾に HTML コメントの目印を付け、同じ目印のコメントが既にあれば
#   重ねない。仕組みは保存場所を持たないため、「もう知らせたか」は目印つきの
#   コメントがあるかどうかで判定する。
#     予約の仕組み          <!-- auto-merge-notice kind=<種類> head=<SHA> -->
#     Issueクローズの仕組み  <!-- issue-close-notice pr=<PR番号> kind=<種類> -->
#
# なぜ知らせの作成者が書いたコメントだけを数えるか:
#   誰でもコメントに同じ目印を書ける。書いた人を問わずに数えると、第三者が
#   目印を書くだけで所有者への知らせを止められる。作成者の名前は NOTICE_AUTHOR
#   (既定は github-actions[bot])で、ワークフローの標準のトークンで付けた
#   コメントの作成者にあたる。
#
# なぜコメントの一覧を REST で読むか:
#   REST の Issue コメントの一覧は、作成者を .user.login に github-actions[bot] と
#   返す。GraphQL と gh pr view --json comments の author.login は github-actions に
#   なり、NOTICE_AUTHOR と一致しない。PR のコメントも同じ一覧で読める。
#     https://docs.github.com/en/rest/issues/comments#list-issue-comments
#
# なぜ一覧を読めないときに付けないか:
#   既にある知らせを確かめられないまま付けると、実行のたびに同じ知らせが増える。
#   読めない・応答の形が想定と違うときは、何も書き込まずに 1 を返す。
#
# source しても何もしない。関数を定義するだけで、シェルの設定(set -e など)と
# trap を変えない。関数は exit せず、戻り値で成否を返す。関数の中の失敗しうる
# コマンドはすべて条件の中で扱うため、呼び出し側が set -Eeuo pipefail と
# ERR の trap を使っていても、失敗が呼び出し側の trap に漏れない。
# 経過と失敗の説明は標準エラーに出す(呼び出し側は標準出力に result= の行を出す)。
#
# 関数と戻り値:
#   notice_post <番号> <目印> <本文のファイル> <mention: yes|no>
#     番号の PR・Issue に、目印を含むコメントが NOTICE_AUTHOR の名前で既にあれば
#     何もしない。無ければ、mention が yes のとき本文の先頭行の頭に「@<所有者> 」を
#     付け、末尾に目印を付けてコメントする。渡されたファイルは書き換えない。
#     0 = 付けた、または既にあった
#     1 = コメントの一覧を読めない・付けられない・引数や環境変数の不足
#   notice_last_kind <番号> <目印の接頭辞>
#     NOTICE_AUTHOR が書いた、接頭辞に一致する目印のコメントのうち、作成日時が
#     最新のものの kind を標準出力に出す。無ければ何も出さない。
#     接頭辞は目印の名前(auto-merge-notice / issue-close-notice)で、
#     英数字・ハイフン・下線だけを受け付ける。
#     0 = 読めた(無い場合を含む) / 1 = 読めない・引数や環境変数の不足
#
# 必須の環境変数: GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER
# 任意の環境変数: NOTICE_AUTHOR(知らせの作成者の名前。既定は github-actions[bot])
# 使い方: source .github/scripts/lib-notice-comment.sh
# テスト: .github/scripts/tests/test-lib-notice-comment.sh
# =====================================================================

# 環境変数と jq を確かめる。足りなければ gh を1度も呼ばずに 1 を返す。
_notice_require() {
    local v
    for v in GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER; do
        if [ -z "${!v:-}" ]; then
            echo "::error::環境変数 ${v} が必要です。" >&2
            return 1
        fi
    done
    if ! command -v jq >/dev/null 2>&1; then
        echo "::error::jq が見つかりません。" >&2
        return 1
    fi
    return 0
}

# 使い方: _notice_valid_number <番号>
_notice_valid_number() {
    if [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]; then
        return 0
    fi
    echo "::error::PR・Issueの番号が不正です: '${1:-}'" >&2
    return 1
}

# 使い方: _notice_author_comments <番号>
# 番号の PR・Issue のコメントのうち、NOTICE_AUTHOR が書いたものを
# [{at: <作成日時>, body: <本文>}] の形で標準出力に出す。
# 0 = 出した / 1 = 一覧を取れない・応答の形が想定と違う
_notice_author_comments() {
    local number="$1" author="${NOTICE_AUTHOR:-github-actions[bot]}" raw
    # --paginate(--slurp なし)はページごとの配列を続けて出すので、jq -s で束ねる。
    # コメントが1件も無いときも [] が1つ出る。何も出ない・配列でないものが
    # 混ざるときは、一覧を読めていないとみなす。
    if ! raw=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${number}/comments" 2>/dev/null); then
        echo "::error::#${number} のコメントの一覧を取得できませんでした。" >&2
        return 1
    fi
    # 作成者が消えたアカウントのコメントは user が null になりうるため、
    # 知らせの作成者ではないものとして読み飛ばす。それ以外の型の違いは失敗にする。
    if ! printf '%s' "$raw" | jq -cs --arg a "$author" '
        def str_or_null(what):
            if type == "string" then . elif . == null then "" else error(what + " の型が想定と違う") end;
        if length == 0 or any(.[]; type != "array") then error("一覧が配列でない") else . end
        | [.[][]
            | if type == "object" then . else error("コメントがオブジェクトでない") end
            | {login: (.user | if . == null then "" elif type == "object" then (.login | str_or_null("login")) else error("user の型が想定と違う") end),
               at: (.created_at | str_or_null("created_at")),
               body: (.body | str_or_null("body"))}
            | select(.login == $a)
            | {at, body}]' 2>/dev/null; then
        echo "::error::#${number} のコメントの一覧の応答を解釈できませんでした。" >&2
        return 1
    fi
    return 0
}

notice_post() {
    local number="${1:-}" marker="${2:-}" body_file="${3:-}" mention="${4:-}"
    local comments exists tmp body rc=0
    _notice_valid_number "$number" || return 1
    if [ -z "$marker" ]; then
        echo "::error::知らせの目印が空です。" >&2
        return 1
    fi
    if [ -z "$body_file" ] || [ ! -f "$body_file" ] || [ ! -r "$body_file" ]; then
        echo "::error::ファイルを読めません: '${body_file}'" >&2
        return 1
    fi
    if [ "$mention" != "yes" ] && [ "$mention" != "no" ]; then
        echo "::error::mention は yes か no で指定します: '${mention}'" >&2
        return 1
    fi
    _notice_require || return 1

    if ! comments=$(_notice_author_comments "$number"); then
        return 1
    fi
    if ! exists=$(printf '%s' "$comments" | jq -r --arg m "$marker" \
        'any(.[]; .body | contains($m))' 2>/dev/null); then
        echo "::error::#${number} の既存の知らせを確かめられませんでした。" >&2
        return 1
    fi
    if [ "$exists" = "true" ]; then
        echo "#${number} に同じ知らせのコメントが既にあるため、コメントを重ねません: ${marker}" >&2
        return 0
    fi

    # 渡されたファイルは書き換えず、メンションと目印を付けた写しを送る。
    # コマンド置換で本文の末尾の改行は落ちるので、空行を1つ挟んで目印を続ける。
    if ! tmp=$(mktemp 2>/dev/null); then
        echo "::error::一時ファイルを作れませんでした。" >&2
        return 1
    fi
    if ! body=$(cat "$body_file" 2>/dev/null) || ! {
        if [ "$mention" = "yes" ]; then printf '@%s ' "$GITHUB_REPOSITORY_OWNER"; fi
        printf '%s\n\n%s\n' "$body" "$marker"
    } >"$tmp"; then
        echo "::error::コメントの本文を組み立てられませんでした。" >&2
        rm -f "$tmp"
        return 1
    fi
    # 一覧と同じ REST の Issue コメントで付ける(PR にも Issue にも同じ形で付く)。
    # -F の値が @ で始まると、続きをファイル名として中身を値にする。
    #   https://cli.github.com/manual/gh_api
    #   https://docs.github.com/en/rest/issues/comments#create-an-issue-comment
    if gh api -X POST "repos/${GITHUB_REPOSITORY}/issues/${number}/comments" \
        -F "body=@${tmp}" >/dev/null 2>&1; then
        echo "#${number} に知らせのコメントを付けました: ${marker}" >&2
    else
        echo "::error::#${number} に知らせのコメントを付けられませんでした: ${marker}" >&2
        rc=1
    fi
    rm -f "$tmp"
    return "$rc"
}

notice_last_kind() {
    local number="${1:-}" prefix="${2:-}" comments kind
    _notice_valid_number "$number" || return 1
    # 接頭辞は正規表現に埋め込むため、記号を含むものは受け付けない
    if [[ ! "$prefix" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "::error::目印の接頭辞が不正です: '${prefix}'" >&2
        return 1
    fi
    _notice_require || return 1

    if ! comments=$(_notice_author_comments "$number"); then
        return 1
    fi
    # 目印の形: <!-- <接頭辞> [<名前>=<値> ...] kind=<種類> [<名前>=<値> ...] -->
    # 新旧は作成日時で比べる。sort_by は同じ日時の並びを保つので、同じ日時なら
    # 一覧で後ろにあるものを新しいとみなす。
    if ! kind=$(printf '%s' "$comments" | jq -r --arg p "$prefix" '
        ("<!-- " + $p + " (?:[^>]* )?kind=([A-Za-z0-9_-]+)(?: [^>]*)? -->") as $re
        | [.[] | select(.body | test($re))]
        | sort_by(.at) | last
        | if . == null then "" else ([.body | scan($re)] | last | .[0]) end' 2>/dev/null); then
        echo "::error::#${number} の知らせの種類を読み取れませんでした。" >&2
        return 1
    fi
    if [ -n "$kind" ]; then
        printf '%s\n' "$kind"
    fi
    return 0
}
