#!/usr/bin/env bash
# =====================================================================
# 監査の結果を通知Issueに反映する(audit-weekly / canary-verify から実行)
#
# 判定: 状態遷移表どおりの操作をすべて終えれば exit 0。
#       引数・環境変数の不正、Issueの検索・起票・追記・クローズの
#       いずれかの失敗は exit 1(赤)。ラベル作成の失敗は無視する。
#       担当者を割り当てられなかったときは警告を出して exit 0。
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
#   書き込みはIssueの起票・追記・クローズ、担当者の割り当て、ラベル作成に限る。
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
# 監査手順書(main の doc/開発フロー/監査手順.md)。日本語のパスは
# パーセントエンコードしておく(URLとして自動リンクされる範囲を途切れさせない)
DOC_URL="${GITHUB_SERVER_URL}/${REPO}/blob/main/doc/%E9%96%8B%E7%99%BA%E3%83%95%E3%83%AD%E3%83%BC/%E7%9B%A3%E6%9F%BB%E6%89%8B%E9%A0%86.md"
DOC_SECTION="監査の通知Issueを受けたとき"

DEVIATION_TITLE="${KIND_NAME}: 逸脱あり"
UNDECIDABLE_TITLE="${KIND_NAME}: 判定不能"

# --- 報告の読み込みと切り詰め -------------------------------------------
# Issue本文の上限は 65,536 文字。報告以外の部分(要約・リンク・案内)の分を
# 残すため、報告は 60,000 文字で切る。
# 数えるのは「文字」(Unicode のコードポイント)で、バイトではない。
# bash の ${#var} はロケール次第でバイト数になり(C ロケールの alpine など)、
# head -c はバイトで切るので多バイト文字の途中で切れる。jq の文字列は
# コードポイント単位で length と .[:n] を扱うので、ロケールに依らない。
# GitHub が上限を何の単位で数えるかは公式に書かれていない。絵文字のような
# BMP 外の文字を UTF-16 で2つと数える場合でも、上限との差の 5,536 文字が
# その分の余裕になる。
REPORT_MAX_CHARS=60000
REPORT_TEXT=""
REPORT_TRUNCATED=0
if [ "$RESULT" != "none" ]; then
    if ! report_len=$(jq -Rs 'length' <"$REPORT_FILE" 2>/dev/null); then
        die "報告ファイルを読めませんでした: '${REPORT_FILE}'"
    fi
    if [ "$report_len" -gt "$REPORT_MAX_CHARS" ]; then
        REPORT_TRUNCATED=1
    fi
    # -j は末尾に改行を足さない。コマンド置換は末尾の改行を落とすので、
    # 目印の x を付けて読み、外す(報告の末尾の改行も保つ)
    if ! REPORT_TEXT=$(jq -Rsj --argjson max "$REPORT_MAX_CHARS" '.[:$max]' <"$REPORT_FILE" 2>/dev/null && printf x); then
        die "報告ファイルを読めませんでした: '${REPORT_FILE}'"
    fi
    REPORT_TEXT="${REPORT_TEXT%x}"
fi

# --- 本文 -------------------------------------------------------------
# 本文の組み立てはこの関数に閉じる。呼び出し側は「どの場面か」だけを渡す。
#   new      起票(title の種別で逸脱か判定不能かが決まる)
#   recheck  既存のIssueへの今回の内容の追記
#   resolved 解消の追記(閉じる直前)
#
# 起票と追記は同じ構成にする。追記にもメンションを付けるのは、追記が
# 「前回から逸脱・故障が続いている」ことを伝えるもので、所有者が購読を
# 外していても届けたいため。頻度は監査の周期(週1回・月1回)に限られる。
# 解消の追記には付けない。対処が要らない知らせで、購読していれば届く。
#
# 報告は最後に置く。切り詰めで Markdown の囲み(```)が閉じないまま
# 終わっても、後ろに続く案内やリンクが囲みに飲まれないようにするため。
# 使い方: build_body <mode> <title>
build_body() {
    local mode="$1" title="$2"
    case "$mode" in
        new | recheck)
            printf '@%s ' "$OWNER"
            summary_line "$title"
            printf '\n- 実行: %s\n\n' "$RUN_URL"
            printf '## 対処\n\n'
            printf '監査手順書の「%s」の節に従って対処する。\n\n' "$DOC_SECTION"
            printf -- '- 監査手順書: %s\n\n' "$DOC_URL"
            if [ "$title" = "$UNDECIDABLE_TITLE" ]; then
                printf '## 再実行の方法\n\n'
                rerun_guide
                printf '\n'
            fi
            printf '## 報告\n\n'
            if [ "$REPORT_TRUNCATED" -eq 1 ]; then
                printf '報告が%s文字を超えたため、先頭の%s文字だけを載せる。' "60,000" "60,000"
                printf '全文は実行の Job Summary を見ること: %s\n\n' "$RUN_URL"
            fi
            printf '%s\n' "$REPORT_TEXT"
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

# 判定不能のときの再実行の方法。監査の種類で異なる
rerun_guide() {
    case "$KIND" in
        weekly)
            printf '失敗した実行を Re-run で再実行する。新規の手動実行(workflow_dispatch)は使わない(skipped-required の対象期間に穴が空くため)。\n'
            ;;
        canary)
            printf 'Re-run と新規の手動実行のどちらでもよい。\n'
            ;;
    esac
}

# 本文は一時ファイルに書き、--body-file で渡す。
# 報告は最大 60,000 文字で、多バイト文字なら 180,000 バイトを超える。
# --body の引数で渡すと Linux の引数1つあたりの上限(MAX_ARG_STRLEN、128KiB)を
# 超えて起動できない。https://man7.org/linux/man-pages/man2/execve.2.html
BODY_FILE=$(mktemp) || die "一時ファイルを作れませんでした。"
trap 'rm -f "$BODY_FILE"' EXIT

# 使い方: write_body <mode> <title>
write_body() {
    build_body "$1" "$2" >"$BODY_FILE" || die "本文を組み立てられませんでした: $2"
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

# 使い方: assign_owner <gh issue create の出力>
# 起票したIssueに所有者を担当者として追加し、応答を読み戻して確かめる。
# 付かなかったとき・確かめられなかったときは警告だけ出して続行する。
# 通知は起票と本文のメンションで既に届いているので、ここで赤にしても
# 届く経路は増えない(research.md「担当者の割り当てとメンションを併用する」)。
#
# gh issue create --assignee を使わないのは、担当者を解決できないと
# 起票そのものが失敗しうるため。通知が失われる方がずっと悪い。
# REST の担当者の追加は、push 権限の無い相手を黙って無視し、Issue 全体を
# assignees 付きで返す。応答の assignees に所有者がいるかで判定できる。
#   https://docs.github.com/en/rest/issues/assignees#add-assignees-to-an-issue
# gh api の -f 'key[]=value' は配列の要素として送られる。
#   https://cli.github.com/manual/gh_api
assign_owner() {
    local created_output="$1" number resp
    # gh issue create は成功時に作ったIssueのURLを標準出力に出す
    #   https://cli.github.com/manual/gh_issue_create
    # 他の行が混ざっても拾えるよう、…/issues/<番号> で終わる最後の行から取る
    number=$(printf '%s\n' "$created_output" |
        sed -n 's#^.*/issues/\([1-9][0-9]*\)[[:space:]]*$#\1#p' | tail -n 1)
    if [ -z "$number" ]; then
        echo "::warning::起票したIssueの番号を読み取れず、担当者 ${OWNER} を割り当てられませんでした。起票は済んでいます: ${created_output}"
        return 0
    fi
    if ! resp=$(gh api -X POST "repos/${REPO}/issues/${number}/assignees" \
        -f "assignees[]=${OWNER}" 2>/dev/null); then
        echo "::warning::担当者 ${OWNER} を #${number} に割り当てられませんでした(APIの失敗)。本文のメンションで通知は届きます。"
        return 0
    fi
    if ! printf '%s' "$resp" | jq -e --arg o "$OWNER" \
        'any(.assignees[]?; .login == $o)' >/dev/null 2>&1; then
        echo "::warning::担当者 ${OWNER} が #${number} に付いていません(割り当てが無視された可能性)。本文のメンションで通知は届きます。"
        return 0
    fi
    echo "担当者: #${number} ${OWNER}"
}

# 使い方: open_or_append <title>
# 開いていなければ起票し、開いていれば今回の内容を追記する。
open_or_append() {
    local title="$1" numbers number url
    numbers=$(numbers_for "$title")
    if [ -z "$numbers" ]; then
        write_body new "$title"
        url=$(gh issue create \
            --title "$title" \
            --label "$LABEL" \
            --body-file "$BODY_FILE") || die "Issueを起票できませんでした: ${title}"
        echo "起票: ${title} ${url}"
        created=$((created + 1))
        assign_owner "$url"
        return 0
    fi
    write_body recheck "$title"
    while IFS= read -r number; do
        [ -n "$number" ] || continue
        gh issue comment "$number" --body-file "$BODY_FILE" >/dev/null ||
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
    local title="$1" numbers number
    numbers=$(numbers_for "$title")
    [ -n "$numbers" ] || return 0
    write_body resolved "$title"
    while IFS= read -r number; do
        [ -n "$number" ] || continue
        gh issue comment "$number" --body-file "$BODY_FILE" >/dev/null ||
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
