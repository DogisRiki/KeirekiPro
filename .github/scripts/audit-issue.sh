#!/usr/bin/env bash
# =====================================================================
# 監査の結果を通知Issueに反映する(audit-weekly / canary-verify から実行)
#
# 判定: 状態遷移表どおりの操作をすべて終えれば exit 0。
#       引数・環境変数の不正、Issueの検索・起票・追記・クローズの
#       いずれかの失敗は exit 1(赤)。ラベル作成の失敗は無視する。
#       判定スクリプトの 0/1/2 とは契約が違う。このスクリプトは判定をせず、
#       受け取った結果をIssueに写すだけなので、成功か失敗かの2値で足りる。
#
# 何をするか:
#   監査の種類(kind)ごとに、逸脱のIssueと判定不能のIssueを1つずつ持つ。
#
#     結果          逸脱のIssue                 判定不能のIssue
#     none          開いていれば解消を追記し閉じる  開いていれば解消を追記し閉じる
#     deviation     無ければ起票、あれば追記       開いていれば解消を追記し閉じる
#     undecidable   触らない                    無ければ起票、あれば追記
#
#   判定不能のときに逸脱のIssueへ触らないのは、逸脱の有無が確定しないため。
#   ここで閉じると、逸脱が残ったまま「解消」の記録が付く。
#
# なぜ固定タイトルとラベルで区別するか:
#   監査は Issue 以外に状態を持たない。前回の結果を覚えておく場所が無いので、
#   「ラベル audit が付いた open のIssueのうち、タイトルが固定の4種に
#   完全一致するもの」を状態そのものとして扱う。
#   タイトルだけで探すと、人が立てた同名のIssueを閉じてしまう。
#   ラベルだけで探すと、同じラベルを付けた別件のIssueを閉じてしまう。
#   両方が一致したものだけを操作し、それ以外のIssueとPRには触らない。
#
# 何を捉えないか:
#   判定は行わない。結果は判定スクリプトと集約の手順が決める。
#   書き込みはIssueの起票・追記・クローズとラベル作成に限る。
#
# テスト: .github/scripts/tests/test-audit-issue.sh
# 使い方: audit-issue.sh <kind> <result> [report-file]
#   kind:        weekly | canary
#   result:      none | deviation | undecidable
#   report-file: 報告のMarkdown。deviation と undecidable では必須
#                (none では使わない)
#   環境変数 GH_TOKEN / GITHUB_REPOSITORY / GITHUB_REPOSITORY_OWNER /
#            GITHUB_SERVER_URL / GITHUB_RUN_ID(すべて必須)
# =====================================================================
set -euo pipefail

LABEL="audit"

die() {
    echo "::error::$1"
    exit 1
}

# --- 入力の検査 -------------------------------------------------------
# gh を1度も呼ばないうちに済ませる。不正な入力でラベルだけ作られたり、
# 途中まで操作して止まったりしないようにする。
KIND="${1:-}"
RESULT="${2:-}"
REPORT_FILE="${3:-}"

case "$KIND" in
    weekly) KIND_NAME="週次監査" ;;
    canary) KIND_NAME="カナリア照合" ;;
    *) die "監査の種類が不正です(weekly か canary): '${KIND}'" ;;
esac

case "$RESULT" in
    none) ;;
    deviation | undecidable)
        # 報告の無い起票・追記は、何が起きたかを伝えられない
        if [ -z "$REPORT_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
            die "報告ファイルがありません: '${REPORT_FILE}'"
        fi
        ;;
    *) die "結果が不正です(none / deviation / undecidable): '${RESULT}'" ;;
esac

for v in GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER GITHUB_SERVER_URL GITHUB_RUN_ID; do
    if [ -z "${!v:-}" ]; then
        die "環境変数 ${v} が必要です。"
    fi
done

if ! command -v jq >/dev/null 2>&1; then
    die "jq が見つかりません。この処理には jq が要ります。"
fi

REPO="$GITHUB_REPOSITORY"
OWNER="$GITHUB_REPOSITORY_OWNER"
RUN_URL="${GITHUB_SERVER_URL}/${REPO}/actions/runs/${GITHUB_RUN_ID}"

DEVIATION_TITLE="${KIND_NAME}: 逸脱あり"
UNDECIDABLE_TITLE="${KIND_NAME}: 判定不能"

# --- 本文 -------------------------------------------------------------
# 本文の組み立てはこの関数に閉じる。呼び出し側は「どの場面か」だけを渡す。
#   new      起票(title の種別で逸脱か判定不能かが決まる)
#   recheck  既存のIssueへの今回の内容の追記
#   resolved 解消の追記(閉じる直前)
# 使い方: build_body <mode> <title>
build_body() {
    local mode="$1" title="$2"
    case "$mode" in
        new | recheck)
            summary_line "$title"
            printf '\n- 実行: %s\n\n' "$RUN_URL"
            printf '## 報告\n\n'
            cat "$REPORT_FILE"
            printf '\n'
            ;;
        resolved)
            printf '今回の実行で解消を確認した。このIssueを閉じる。\n\n'
            printf -- '- 実行: %s\n' "$RUN_URL"
            ;;
    esac
}

# 使い方: summary_line <title>
summary_line() {
    if [ "$1" = "$DEVIATION_TITLE" ]; then
        printf '%sで逸脱が見つかった。\n' "$KIND_NAME"
    else
        printf '%sが判定できなかった(監査そのものの故障)。\n' "$KIND_NAME"
    fi
}

# --- 既存のIssueの検索 -------------------------------------------------
# ラベルが無いと起票時に失敗する。作成は冪等に行う。
# 既にあれば gh label create は非ゼロで終わるので、失敗は無視する。
# 本当に作成できていなければ、後続の gh issue create --label が失敗して赤になる。
gh label create "$LABEL" --description "監査の通知" --color D93F0B >/dev/null 2>&1 || true

# Issues API は PR も返すため pull_request キーを持つ要素を除く。
# gh issue list は --paginate を持たず既定30件で打ち切られるので使わない。
if ! raw_issues=$(gh api "repos/${REPO}/issues?labels=${LABEL}&state=open&per_page=100" --paginate --slurp 2>/dev/null); then
    die "オープンIssueの一覧を取得できませんでした。"
fi

# タイトルは完全一致だけを拾う。人手で書き足されたタイトルや、
# 他の種類の監査のタイトルは別物として扱い、操作しない。
if ! open_issues=$(printf '%s' "$raw_issues" | jq -c \
    --arg dev "$DEVIATION_TITLE" --arg und "$UNDECIDABLE_TITLE" \
    '[.[][] | select(has("pull_request") | not)
      | select(.title == $dev or .title == $und)
      | {number: .number, title: .title}]' 2>/dev/null); then
    die "オープンIssueの一覧を解析できませんでした。"
fi

# 使い方: numbers_for <title>
# 同じタイトルが複数開いていれば、すべての番号を返す。
# 1件だけ選ぶと残りが永久に閉じられず、毎回同じ操作が繰り返される。
numbers_for() {
    printf '%s' "$open_issues" | jq -r --arg t "$1" '.[] | select(.title == $t) | .number'
}

for t in "$DEVIATION_TITLE" "$UNDECIDABLE_TITLE"; do
    count=$(numbers_for "$t" | grep -c . || true)
    if [ "$count" -gt 1 ]; then
        echo "::warning::同じタイトルのオープンIssueが${count}件あります。すべてを操作します: ${t}"
    fi
done

# --- 操作 -------------------------------------------------------------
created=0
commented=0
closed=0

# 使い方: open_or_append <title>
# 開いていなければ起票し、開いていれば今回の内容を追記する。
open_or_append() {
    local title="$1" numbers number body url
    numbers=$(numbers_for "$title")
    if [ -z "$numbers" ]; then
        body=$(build_body new "$title")
        url=$(gh issue create \
            --title "$title" \
            --label "$LABEL" \
            --assignee "$OWNER" \
            --body "$body") || die "Issueを起票できませんでした: ${title}"
        echo "起票: ${title} ${url}"
        created=$((created + 1))
        return 0
    fi
    body=$(build_body recheck "$title")
    while IFS= read -r number; do
        [ -n "$number" ] || continue
        gh issue comment "$number" --body "$body" >/dev/null ||
            die "Issueに追記できませんでした: #${number} ${title}"
        echo "追記: #${number} ${title}"
        commented=$((commented + 1))
    done <<NUMBERS
${numbers}
NUMBERS
}

# 使い方: resolve_all <title>
# 開いていれば解消を追記して閉じる。追記に失敗したら閉じない。
# 記録の無いクローズは、なぜ閉じたかを後から辿れなくするため。
resolve_all() {
    local title="$1" numbers number body
    numbers=$(numbers_for "$title")
    [ -n "$numbers" ] || return 0
    body=$(build_body resolved "$title")
    while IFS= read -r number; do
        [ -n "$number" ] || continue
        gh issue comment "$number" --body "$body" >/dev/null ||
            die "Issueに解消を追記できませんでした: #${number} ${title}"
        gh issue close "$number" >/dev/null ||
            die "Issueを閉じられませんでした: #${number} ${title}"
        echo "クローズ: #${number} ${title}"
        closed=$((closed + 1))
    done <<NUMBERS
${numbers}
NUMBERS
}

case "$RESULT" in
    none)
        resolve_all "$DEVIATION_TITLE"
        resolve_all "$UNDECIDABLE_TITLE"
        ;;
    deviation)
        open_or_append "$DEVIATION_TITLE"
        resolve_all "$UNDECIDABLE_TITLE"
        ;;
    undecidable)
        # 逸脱のIssueには触らない(逸脱の有無が確定しないため)
        open_or_append "$UNDECIDABLE_TITLE"
        ;;
esac

echo "起票 ${created} 件 / 追記 ${commented} 件 / クローズ ${closed} 件"
