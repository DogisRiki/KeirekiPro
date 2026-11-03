#!/usr/bin/env bash
# =====================================================================
# 公開から72時間待たずに入れる版の記録のコメントを PR に書き、また、PR に記録の
# コメントがあるかを読む
# (check-dependency-cooldown.sh と check-audit-dependabot-stuck.sh から呼ばれる)
#
# 記録のコメント:
#   所有者が読む表と、機械が読む記録の JSON の行と、目印の行からなる。
#     <!-- cooldown-exception-data data=<記録の JSON を base64 にしたもの> -->
#     <!-- cooldown-exception-record kind=exception head=<head_sha> -->
#   head は PR のブランチの最新のコミットで、記録のコメントは head ごとに1つである。
#   記録のコメントは消さない。マージのあとも、週次監査がこのコメントを読む。
#
# なぜ記録の JSON を base64 にするのか:
#   部品の名前や警告の文に --> が入っても、HTML のコメントが途中で閉じないようにするため。
#
# なぜ github-actions[bot] が書いたコメントだけを数えるのか:
#   誰でもコメントに同じ目印を書ける。書いた者を問わずに数えると、第三者が目印を
#   書くだけで、記録を書かせないことも、記録があることにすることもできる。
#   書くことと読むことは lib-notice-comment.sh の関数に任せ、その関数が作成者で絞る。
#
# テスト: .github/scripts/tests/test-record-cooldown-exception.sh
# 使い方:
#   record-cooldown-exception.sh post <PR番号> <head_sha> <記録のファイル>
#     記録のファイルは、design のデータの形の節の記録の JSON。pr と head は引数と同じであること。
#     同じ head の記録のコメントが無ければ書く。
#     終了コード 0 = 書けた、または既にあった / 1 = 書けなかった(引数の誤りを含む)
#   record-cooldown-exception.sh exists <PR番号>
#     標準出力に exists=true か exists=false を出す。
#     終了コード 0 = 読めた / 1 = 読めなかった(引数の誤りを含む)
# 必須の環境変数: GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER
# =====================================================================
set -euo pipefail

usage() {
    echo "使い方: record-cooldown-exception.sh post <PR番号> <head_sha> <記録のファイル>" >&2
    echo "        record-cooldown-exception.sh exists <PR番号>" >&2
    exit 1
}

# shellcheck source=.github/scripts/lib-notice-comment.sh
source "$(cd "$(dirname "$0")" && pwd)/lib-notice-comment.sh"

PREFIX="cooldown-exception-record"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 使い方: post <PR番号> <head_sha> <記録のファイル>
post() {
    local pr="$1" head="$2" file="$3" table data
    # head は目印に入るので、SHA の形だけを受け付ける
    if [[ ! "$head" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
        echo "::error::head が SHA の形ではありません: '${head}'" >&2
        exit 1
    fi
    if [[ ! "$pr" =~ ^[1-9][0-9]*$ ]]; then
        echo "::error::PR の番号が不正です: '${pr}'" >&2
        exit 1
    fi
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        echo "::error::記録のファイルを読めません: '${file}'" >&2
        exit 1
    fi
    if ! jq -e --argjson pr "$pr" --arg head "$head" '
        def str: type == "string" and length > 0;
        .schema == 1 and .pr == $pr and .head == $head and (.recorded_at | str)
        and (.entries | type == "array" and length > 0)
        and all(.entries[];
            (.ecosystem | str) and (.name | str) and (.version | str) and (.published_at | str)
            and (.alerts | type == "array" and length > 0)
            and all(.alerts[]; (.number | type == "number") and (.ghsa_id | str)
                and (.severity | str) and (.html_url | str)))' "$file" >/dev/null 2>&1; then
        echo "::error::記録の JSON の形が違うか、PR の番号か head が引数と合いません: ${file}" >&2
        exit 1
    fi

    # 表のマスの中の | は表の区切りにならないように \| にする
    table=$(jq -r '
        def cell: gsub("\\|"; "\\|");
        .entries[]
        | "| `\(.name | cell)` | `\(.version | cell)` | `\(.published_at | cell)` | "
          + ([.alerts[] | "[#\(.number) \(.ghsa_id | cell)(\(.severity | cell))](\(.html_url | cell))"] | join("、"))
          + " |"' "$file")
    data=$(jq -c . "$file" | base64 | tr -d '\n')
    {
        echo "### 公開から72時間待たずに入れる版"
        echo
        echo "この PR は、次の版を、脆弱性の修正のために72時間待たずに入れます。所有者の承認のあとにマージされます。"
        echo
        echo "| 部品 | 版 | 公開日時 | 理由になった警告 |"
        echo "|---|---|---|---|"
        printf '%s\n' "$table"
        echo
        echo "<!-- cooldown-exception-data data=${data} -->"
    } >"$TMP/body.md"
    if ! notice_post "$pr" "<!-- ${PREFIX} kind=exception head=${head} -->" "$TMP/body.md" no; then
        echo "::error::#${pr} に記録のコメントを書けませんでした。" >&2
        exit 1
    fi
}

# 使い方: exists <PR番号>
exists() {
    local kind
    if ! kind=$(notice_last_kind "$1" "$PREFIX"); then
        echo "::error::#${1} の記録のコメントを読めませんでした。" >&2
        exit 1
    fi
    if [ "$kind" = exception ]; then
        echo "exists=true"
    else
        echo "exists=false"
    fi
}

case "${1:-}" in
post)
    [ "$#" -eq 4 ] || usage
    post "$2" "$3" "$4"
    ;;
exists)
    [ "$#" -eq 2 ] || usage
    exists "$2"
    ;;
*) usage ;;
esac
