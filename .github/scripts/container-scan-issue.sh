#!/usr/bin/env bash
# =====================================================================
# 稼働中イメージの検出結果をIssueに反映する
#
# 判定: すべての操作が成功すれば exit 0、いずれかが失敗するか
#       入力が不正なら exit 1(赤)。
#
# 何をするか:
#   ラベル container-vuln の付いたオープンIssueと、検出結果を
#   脆弱性識別子で突き合わせ、次のとおり操作する。
#
#     blocking にあり、オープンIssueが無い          -> 起票する
#     blocking にあり、オープンIssueがある          -> 今回の検出結果を追記する
#     Issueの ID が blocking に無いが detected にある -> 状況を追記する(閉じない)
#     Issueの ID が detected にも無い                -> 解消を記録して閉じる
#
#   2行目と3行目の追記は、状態が前回の記録から変わったときだけ行う(#820)。
#   状態とは、どちらの行に当たるかと、検出された箇所ごとの深刻度と
#   修正版の有無の組である。検査は毎日と、リリースのあとと、main への
#   マージのあとに動く。変わらない状態を毎回追記すると、同じ内容の
#   コメントが毎日並び、深刻度が上がった、修正版が出た、といった
#   読むべき変化が埋もれる。
#
#   状態は、起票の本文と追記の末尾に、画面に出ない HTML のコメント
#   「<!-- container-scan-state: <JSON> -->」として残す。前回の記録は、
#   このワークフローの利用者(github-actions[bot])が書いた本文と
#   コメントのうち、最後のものから読む。ほかの利用者のコメントは読まない。
#   公開のリポジトリでは誰でもコメントを書けるため、同じ形の文を
#   書き込んで追記を止める経路を作らないためである。
#   記録が無いIssue(この仕組みより前に起票したもの)には、1回追記する。
#
#   タイトルが「コンテナ脆弱性: <ID>」の形でないIssueは、誤クローズを避けるため
#   操作せず警告のみ出す。人手でタイトルに追記されたIssueが対象。
#
#   3行目が重要。修正版の情報が撤回されたり深刻度が格下げされたりすると、
#   その ID は blocking から外れるが脆弱性はイメージに残っている。
#   ここで閉じると、CLAUDE.md により人間はIssueを閉じない運用のため、
#   誤クローズが人間の目に触れないまま追跡が消える。
#   要件 2.4 の条件は「脆弱性が検出されなくなる」であり、detected からの消失。
#
# なぜ識別子だけをキーにするか:
#   対象イメージはデプロイのたびに変わる(backend-deploy.yaml が
#   github.sha でタグ付けし、ECRが IMMUTABLE)。キーに含めると
#   デプロイのたびに同じ脆弱性が再起票される。
#   イメージ参照はIssueの本文に残すが、突き合わせには使わない。
#
# 何を捉えないか:
#   判定は行わない。何が blocking かは check-container-scan.sh が決める。
#   このスクリプトはその出力を受け取るだけ。
#
# テスト: .github/scripts/tests/test-container-scan-issue.sh
# 使い方: container-scan-issue.sh <blocking-json> <detected-json> <image-reference>
#   環境変数 GITHUB_REPOSITORY が要る
# =====================================================================
set -euo pipefail

BLOCKING_JSON="${1:?blocking json required}"
DETECTED_JSON="${2:?detected json required}"
IMAGE_REF="${3:?image reference required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"

LABEL="container-vuln"
TITLE_PREFIX="コンテナ脆弱性: "
# 状態の記録を書く利用者。ワークフローは github.token で Issue を操作する。
BOT_LOGIN="github-actions[bot]"
STATE_PREFIX="<!-- container-scan-state: "
STATE_SUFFIX=" -->"
# 記録から状態の JSON を取り出す jq の式。入力は本文の文字列。
# 取り出せなければ何も出さない。
STATE_CAPTURE='capture("<!-- container-scan-state: (?<s>\\{[^\\n]*\\}) -->").s'

if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq が見つかりません。この処理には jq が要ります。"
    exit 1
fi

# 入力が配列であることを先に確かめる。空配列は正常。
# 配列でないものを通すと、以降の jq が黙って空を返して
# 「検出0件」と区別がつかなくなる。
for f in "$BLOCKING_JSON" "$DETECTED_JSON"; do
    if [ ! -f "$f" ]; then
        echo "::error::入力ファイルがありません: ${f}"
        exit 1
    fi
    if ! jq -e 'type == "array"' "$f" >/dev/null 2>&1; then
        echo "::error::入力が配列ではありません: ${f}"
        exit 1
    fi
    # id を欠く要素を通すと「コンテナ脆弱性: null」のIssueを起票してしまう
    if ! jq -e 'all(.id? // "" | test("^\\S+$"))' "$f" >/dev/null 2>&1; then
        echo "::error::id を持たない要素、または空白を含む id があります: ${f}"
        exit 1
    fi
done

blocking_ids=$(jq -r '[.[].id] | unique | .[]' "$BLOCKING_JSON")
detected_ids=$(jq -r '[.[].id] | unique | .[]' "$DETECTED_JSON")

# ラベルが無いと起票時に失敗する。作成は冪等に行う。
# ここで握りつぶしても、本当に作成できていなければ後続の
# gh issue create --label が失敗して赤になる。
gh label create "$LABEL" --description "コンテナイメージの脆弱性" --color B60205 >/dev/null 2>&1 || true

# Issues API は PR も返すため pull_request キーを持つ要素を除く。
# gh issue list は --paginate を持たず既定30件で打ち切られるので使わない。
# 取得や解析に失敗したときは終了コードを1に正規化する。呼び出し側は
# 0 / 1 / 2 で分岐するため、jq の失敗がそのまま漏れると契約外の値になる。
if ! raw_issues=$(gh api "repos/${REPO}/issues?labels=${LABEL}&state=open&per_page=100" --paginate --slurp 2>/dev/null); then
    echo "::error::オープンIssueの一覧を取得できませんでした。"
    exit 1
fi

# body_state は、このワークフローが起票した本文に残した状態の記録。
if ! all_matched=$(printf '%s' "$raw_issues" | jq --arg p "$TITLE_PREFIX" --arg bot "$BOT_LOGIN" \
    '[.[][] | select(has("pull_request") | not)
      | select(.title | startswith($p))
      | {id: (.title | ltrimstr($p)), number: .number, title: .title,
         body_state: (if (.user.login? // "") == $bot
                      then ([(.body // "") | '"$STATE_CAPTURE"'] | last // "")
                      else "" end)}]' 2>/dev/null); then
    echo "::error::オープンIssueの一覧を解析できませんでした。"
    exit 1
fi

# 接頭辞を外した残りが識別子の形(空白を含まない)でないものは操作しない。
# 人手で「(再発)」などを付け足されたIssueを別物として扱うと、
# 「検出されなくなった」と誤判定して閉じてしまう。
irregular=$(printf '%s' "$all_matched" | jq -r '.[] | select(.id | test("^\\S+$") | not) | "#\(.number) \(.title)"')
while IFS= read -r line; do
    [ -n "$line" ] || continue
    echo "::warning::タイトルが規約から外れたIssueは操作しません: ${line}"
done <<IRREGULAR
${irregular}
IRREGULAR

open_issues=$(printf '%s' "$all_matched" | jq '[.[] | select(.id | test("^\\S+$"))]')

# 同じ識別子のIssueが複数開いている場合は、そのすべてを対象にする。
# 1件だけ選ぶと残りが永久に閉じられず、毎週同じ操作が繰り返される。
dup=$(printf '%s' "$open_issues" | jq -r 'group_by(.id) | map(select(length > 1)) | .[] | .[0].id')
while IFS= read -r dup_id; do
    [ -n "$dup_id" ] || continue
    echo "::warning::同じ識別子のオープンIssueが複数あります: ${dup_id}"
done <<DUP
${dup}
DUP

# 使い方: numbers_for <id>
numbers_for() {
    printf '%s' "$open_issues" | jq -r --arg id "$1" '.[] | select(.id == $id) | .number'
}

# 今回の状態を1行の JSON で出す。
# 使い方: state_for <id> <recheck|downgraded> <json file>
# 並びを揃えて比べられるよう、unique で並べ替えて重複を除き、キーも並べ替える。
state_for() {
    jq -cS --arg id "$1" --arg kind "$2" '
        {kind: $kind,
         rows: ([.[] | select(.id == $id)
                 | {severity: (.severity // ""),
                    fixed: ((.fixedVersion // "") != "")}] | unique)}
    ' "$3"
}

# 前回の記録の状態を1行の JSON で出す。記録が無ければ空を出す。
# 使い方: last_state_for <number>
# このワークフローの利用者が書いたコメントのうち最後のものを使い、
# コメントに記録が無ければ起票の本文の記録を使う。
last_state_for() {
    local number="$1" comments state
    if ! comments=$(gh api "repos/${REPO}/issues/${number}/comments?per_page=100" --paginate --slurp 2>/dev/null); then
        echo "::error::Issue #${number} のコメントを取得できませんでした。" >&2
        return 1
    fi
    if ! state=$(printf '%s' "$comments" | jq -r --arg bot "$BOT_LOGIN" \
        '[.[][] | select((.user.login? // "") == $bot) | (.body // "") | '"$STATE_CAPTURE"'] | last // ""' 2>/dev/null); then
        echo "::error::Issue #${number} のコメントを解析できませんでした。" >&2
        return 1
    fi
    if [ -z "$state" ]; then
        state=$(printf '%s' "$open_issues" | jq -r --argjson n "$number" \
            '[.[] | select(.number == $n) | .body_state] | first // ""')
    fi
    # 書いたときと同じ形に揃える。JSON として読めない記録は、無いものとして扱う。
    if [ -n "$state" ]; then
        state=$(printf '%s' "$state" | jq -cS . 2>/dev/null || true)
    fi
    printf '%s' "$state"
}

# 使い方: comment_if_changed <number> <id> <recheck|downgraded> <json file> <説明>
comment_if_changed() {
    local number="$1" id="$2" kind="$3" file="$4" label="$5" current previous
    current=$(state_for "$id" "$kind" "$file")
    # 前回の記録を読めないときは、追記するかを決められないので止める。
    if ! previous=$(last_state_for "$number"); then
        exit 1
    fi
    if [ "$current" = "$previous" ]; then
        echo "変化なし: ${id} (#${number})"
        unchanged=$((unchanged + 1))
        return 0
    fi
    gh issue comment "$number" --body "$(build_body "$kind" "$id" "$current")" >/dev/null
    echo "${label}: ${id} (#${number})"
    commented=$((commented + 1))
}

# Issue の本文を組み立てる。
# 書式中のバッククォートは Markdown のコード表記で、展開させたくない。
# 関数全体に効かせるため、ここで1度だけ抑止する。
# shellcheck disable=SC2016
# 使い方: build_body <mode> <id> [状態の JSON]
# 状態の JSON を渡したときは、末尾に状態の記録を足す。
build_body() {
    local mode="$1" id="$2" state="${3:-}"
    case "$mode" in
        new)
            printf '稼働中の本番イメージから、修正版のある脆弱性が検出された。

'
            printf -- '- 脆弱性: `%s`
' "$id"
            printf -- '- 対象イメージ: `%s`

' "$IMAGE_REF"
            printf '## 検出された箇所

'
            rows_for "$id" "$BLOCKING_JSON"
            printf '

このIssueは稼働中イメージの定期監視が起票した。'
            printf '検出されなくなった時点で自動でクローズされる。
'
            ;;
        recheck)
            printf '再検査で、深刻度か修正版の有無が前回の記録から変わったため追記する。引き続き検出されている。

'
            printf -- '- 対象イメージ: `%s`

' "$IMAGE_REF"
            rows_for "$id" "$BLOCKING_JSON"
            printf '
'
            ;;
        downgraded)
            printf '再検査で、マージを止める条件から外れた。'
            printf '**脆弱性そのものは検出されている。**

'
            printf -- '- 対象イメージ: `%s`

' "$IMAGE_REF"
            printf '## 現在の状況

'
            rows_for "$id" "$DETECTED_JSON"
            printf '

深刻度の見直しか、修正版の情報の取り下げが起きた可能性がある。'
            printf 'このIssueは閉じない。
'
            ;;
        resolved)
            printf '再検査で検出されなくなった。解消とみなしてクローズする。

'
            printf -- '- 対象イメージ: `%s`
' "$IMAGE_REF"
            ;;
    esac
    if [ -n "$state" ]; then
        printf '\n%s%s%s\n' "$STATE_PREFIX" "$state" "$STATE_SUFFIX"
    fi
}

# 使い方: rows_for <id> <json file>
rows_for() {
    jq -r --arg id "$1" '
        .[] | select(.id == $id)
        | "- `\(.pkgName)` \(.installedVersion) — 深刻度 \(.severity) / 修正版 \(.fixedVersion // "なし")"
    ' "$2"
}

contains_id() {
    printf '%s
' "$2" | grep -qxF "$1"
}

created=0
commented=0
unchanged=0
closed=0

# --- blocking にあるもの ---------------------------------------------
while IFS= read -r id; do
    [ -n "$id" ] || continue
    numbers=$(numbers_for "$id")
    if [ -z "$numbers" ]; then
        # 起票の本文にも状態を残す。次の検査で同じ状態なら追記しないため。
        gh issue create \
            --title "${TITLE_PREFIX}${id}" \
            --label "$LABEL" \
            --body "$(build_body new "$id" "$(state_for "$id" recheck "$BLOCKING_JSON")")" >/dev/null
        echo "起票: ${id}"
        created=$((created + 1))
        continue
    fi
    # 同じ識別子のIssueが複数あればすべてを対象にする
    while IFS= read -r number; do
        [ -n "$number" ] || continue
        comment_if_changed "$number" "$id" recheck "$BLOCKING_JSON" "追記"
    done <<NUMBERS
${numbers}
NUMBERS
done <<BLOCKING
${blocking_ids}
BLOCKING

# --- オープンIssueのうち blocking に無いもの --------------------------
# 識別子ではなく (識別子, 番号) の組で回す。同じ識別子のIssueが
# 複数あるとき、1件だけ選ぶと残りが永久に閉じられないため。
# 番号を先に置く。番号は空白を含まないが、タイトル由来の id は
# 規約から外れていれば空白を含みうる。read は最後の変数に残り全部を入れるため、
# この順序なら id が空白を含んでも壊れない。
entries=$(printf '%s' "$open_issues" | jq -r '.[] | "\(.number) \(.id)"')
while IFS=' ' read -r number id; do
    [ -n "$id" ] || continue
    [ -n "$number" ] || continue
    contains_id "$id" "$blocking_ids" && continue

    if contains_id "$id" "$detected_ids"; then
        # 検出はされているが blocking の条件から外れた。
        # 脆弱性は残っているので閉じない。
        comment_if_changed "$number" "$id" downgraded "$DETECTED_JSON" "追記(条件から外れた)"
    else
        gh issue comment "$number" --body "$(build_body resolved "$id")" >/dev/null
        gh issue close "$number" >/dev/null
        echo "クローズ: ${id} (#${number})"
        closed=$((closed + 1))
    fi
done <<ENTRIES
${entries}
ENTRIES

echo "起票 ${created} 件 / 追記 ${commented} 件 / 変化なし ${unchanged} 件 / クローズ ${closed} 件"
