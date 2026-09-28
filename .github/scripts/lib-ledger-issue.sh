# shellcheck shell=bash
# =====================================================================
# 台帳のIssueを探す・作る・コメントする・担当者に割り当てる共通の関数
# (collect-inventory.sh / record-mutation-metrics.sh から source して使う)
#
# 台帳のIssue:
#   定期実行の結果を積み重ねて残すための、決まったタイトルのIssue。
#   監査のワークフローは Issue 以外に状態を持たないため、過去の記録と
#   所有者への通知の置き場として使う。
#     棚卸しの台帳     タイトル「棚卸し台帳: 版とサポート期限」、ラベル audit
#     mutation の台帳  タイトル「メトリクス台帳: mutationスコア」、ラベルなし
#
# なぜタイトルの完全一致で探すか:
#   台帳は決まったタイトルで他のIssueと区別する。前後に文字が付いたIssueや
#   同じタイトルのPRは台帳として扱わず、操作もしない。閉じられていても同じ台帳を
#   使い続ける。同じタイトルが複数あれば最小の番号(最初に作られたもの)を使う。
#
# なぜ担当者の割り当ての失敗を警告に留めるか:
#   通知はコメントの先頭行のメンションで既に届いている。ここで失敗にしても
#   届く経路は増えず、記録と通知が止まる方が悪い(audit-issue.sh と同じ扱い)。
#
# source しても何もしない。関数を定義するだけで、シェルの設定(set -e など)と
# trap を変えない。関数は exit せず、戻り値で成否を返す。関数の中の失敗しうる
# コマンドはすべて条件の中で扱うため、呼び出し側が set -Eeuo pipefail と
# ERR の trap を使っていても、警告で済ませる失敗が呼び出し側に漏れない。
#
# 関数と戻り値:
#   ledger_find_or_create <title> <initial_body_file> <label>
#     タイトルが完全一致するIssue(PRを除く、状態を問わない、最小の番号)を探し、
#     番号を標準出力に出す。無ければ本文のファイルとラベルで作る。ラベルが
#     空なら付けない。ラベルを付けるときは、無ければ作る(既にあれば失敗を無視)。
#     0 = 番号を出した / 1 = 探せなかった・作れなかった・引数や環境変数の不足
#   ledger_comment <issue_number> <body_file>
#     本文の先頭行の頭に「@<所有者> 」を付けてコメントし、所有者を担当者に
#     割り当てる。
#     0 = コメントした(担当者の割り当ての失敗は ::warning:: を出して 0)
#     1 = コメントできなかった・引数や環境変数の不足
#   ledger_assign_owner <issue_number>
#     所有者を担当者に割り当てる。ledger_comment が使う。失敗は警告だけで常に 0
#   ledger_append_body <issue_number> <text_file>
#     本文の末尾にテキストを追記する(コメントではないので通知は出ない)。
#     0 = 追記した / 1 = 本文を取れなかった・編集できなかった・引数や環境変数の不足
#
# 必須の環境変数: GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER
# 使い方: source .github/scripts/lib-ledger-issue.sh
# テスト: .github/scripts/tests/test-lib-ledger-issue.sh
# =====================================================================

# 環境変数と jq を確かめる。足りなければ gh を1度も呼ばずに 1 を返す。
_ledger_require() {
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

# 使い方: _ledger_valid_number <番号>
_ledger_valid_number() {
    if [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]; then
        return 0
    fi
    echo "::error::Issueの番号が不正です: '${1:-}'" >&2
    return 1
}

# 使い方: _ledger_readable_file <パス>
_ledger_readable_file() {
    if [ -n "${1:-}" ] && [ -f "$1" ] && [ -r "$1" ]; then
        return 0
    fi
    echo "::error::ファイルを読めません: '${1:-}'" >&2
    return 1
}

ledger_find_or_create() {
    local title="${1:-}" body_file="${2:-}" label="${3:-}"
    local repo issues_json number created_output
    local -a label_args=()
    if [ -z "$title" ]; then
        echo "::error::台帳のタイトルが空です。" >&2
        return 1
    fi
    _ledger_readable_file "$body_file" || return 1
    _ledger_require || return 1
    repo="$GITHUB_REPOSITORY"

    # gh issue list は既定30件で打ち切られ、検索は部分一致のため使わない。
    # --paginate(--slurp なし)はページごとの配列を続けて出すので、jq -s で束ねる。
    # Issues API は PR も返すため pull_request を持つ要素を除く。
    if ! issues_json=$(gh api --paginate "repos/${repo}/issues?state=all&per_page=100" 2>/dev/null); then
        echo "::error::Issue一覧を取得できませんでした。" >&2
        return 1
    fi
    if ! number=$(printf '%s' "$issues_json" | jq -sr --arg t "$title" '
        [.[][] | select(.pull_request == null and .title == $t) | .number] | min // empty' 2>/dev/null); then
        echo "::error::Issue一覧の応答を解釈できませんでした。" >&2
        return 1
    fi
    if [ -n "$number" ]; then
        printf '%s\n' "$number"
        return 0
    fi

    # ラベルの作成は台帳の作成に付随する操作として、作るときだけ行う。
    # 既にあれば gh label create は失敗するので、失敗は無視する。
    # 本当に作れていなければ、後の gh issue create --label が失敗して 1 になる。
    if [ -n "$label" ]; then
        gh label create "$label" --repo "$repo" >/dev/null 2>&1 || true
        label_args=(--label "$label")
    fi
    # 本文は --body-file で渡す(引数1つあたりの長さの上限を避ける)
    if ! created_output=$(gh issue create --repo "$repo" --title "$title" \
        "${label_args[@]}" --body-file "$body_file" 2>/dev/null); then
        echo "::error::台帳のIssueを作成できませんでした: ${title}" >&2
        return 1
    fi
    # gh issue create は成功時に作ったIssueのURLを標準出力に出す。
    # 他の行が混ざっても拾えるよう、…/issues/<番号> で終わる最後の行から取る。
    #   https://cli.github.com/manual/gh_issue_create
    number=$(printf '%s\n' "$created_output" |
        sed -n 's#^.*/issues/\([1-9][0-9]*\)[[:space:]]*$#\1#p' | tail -n 1)
    if [ -z "$number" ]; then
        echo "::error::作成した台帳のIssueの番号を読み取れませんでした: ${created_output}" >&2
        return 1
    fi
    echo "台帳のIssueを作成しました: #${number} ${title}" >&2
    printf '%s\n' "$number"
    return 0
}

# 所有者を担当者として追加し、応答を読み戻して確かめる。
# REST の担当者の追加は、push 権限の無い相手を黙って無視し、Issue 全体を
# assignees 付きで返す。応答の assignees に所有者がいるかで判定できる。
#   https://docs.github.com/en/rest/issues/assignees#add-assignees-to-an-issue
# gh api の -f 'key[]=value' は配列の要素として送られる。
#   https://cli.github.com/manual/gh_api
ledger_assign_owner() {
    local number="${1:-}" repo owner resp
    _ledger_valid_number "$number" || return 0
    _ledger_require || return 0
    repo="$GITHUB_REPOSITORY"
    owner="$GITHUB_REPOSITORY_OWNER"
    if ! resp=$(gh api -X POST "repos/${repo}/issues/${number}/assignees" \
        -f "assignees[]=${owner}" 2>/dev/null); then
        echo "::warning::担当者 ${owner} を #${number} に割り当てられませんでした(APIの失敗)。コメントのメンションで通知は届きます。"
        return 0
    fi
    if ! printf '%s' "$resp" | jq -e --arg o "$owner" \
        'any(.assignees[]?; .login == $o)' >/dev/null 2>&1; then
        echo "::warning::担当者 ${owner} が #${number} に付いていません(割り当てが無視された可能性)。コメントのメンションで通知は届きます。"
        return 0
    fi
    echo "担当者: #${number} ${owner}"
    return 0
}

ledger_comment() {
    local number="${1:-}" body_file="${2:-}" tmp rc=0
    _ledger_valid_number "$number" || return 1
    _ledger_readable_file "$body_file" || return 1
    _ledger_require || return 1

    # 渡されたファイルは書き換えず、メンションを付けた写しを送る
    if ! tmp=$(mktemp 2>/dev/null); then
        echo "::error::一時ファイルを作れませんでした。" >&2
        return 1
    fi
    if ! { printf '@%s ' "$GITHUB_REPOSITORY_OWNER" && cat "$body_file"; } >"$tmp"; then
        echo "::error::コメントの本文を組み立てられませんでした。" >&2
        rm -f "$tmp"
        return 1
    fi
    if gh issue comment "$number" --repo "$GITHUB_REPOSITORY" --body-file "$tmp" >/dev/null 2>&1; then
        echo "台帳のIssue #${number} にコメントしました。"
    else
        echo "::error::台帳のIssue #${number} にコメントできませんでした。" >&2
        rc=1
    fi
    rm -f "$tmp"
    [ "$rc" -eq 0 ] || return 1
    ledger_assign_owner "$number"
    return 0
}

ledger_append_body() {
    local number="${1:-}" text_file="${2:-}" body tmp rc=0
    _ledger_valid_number "$number" || return 1
    _ledger_readable_file "$text_file" || return 1
    _ledger_require || return 1

    # 本文を取れないまま編集すると、今の本文を追記の中身で上書きして消してしまう
    if ! body=$(gh api "repos/${GITHUB_REPOSITORY}/issues/${number}" --jq '.body // ""' 2>/dev/null); then
        echo "::error::台帳のIssue #${number} の本文を取得できませんでした。" >&2
        return 1
    fi
    if ! tmp=$(mktemp 2>/dev/null); then
        echo "::error::一時ファイルを作れませんでした。" >&2
        return 1
    fi
    # コマンド置換で本文の末尾の改行は落ちているので、改行を1つ足してから続ける
    if ! {
        if [ -n "$body" ]; then printf '%s\n' "$body"; fi
        cat "$text_file"
    } >"$tmp"; then
        echo "::error::追記後の本文を組み立てられませんでした。" >&2
        rm -f "$tmp"
        return 1
    fi
    if gh issue edit "$number" --repo "$GITHUB_REPOSITORY" --body-file "$tmp" >/dev/null 2>&1; then
        echo "台帳のIssue #${number} の本文に追記しました。"
    else
        echo "::error::台帳のIssue #${number} の本文に追記できませんでした。" >&2
        rc=1
    fi
    rm -f "$tmp"
    return "$rc"
}
