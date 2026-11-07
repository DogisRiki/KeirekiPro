#!/usr/bin/env bash
# =====================================================================
# main に残った CodeQL の警告の数え方(audit-weekly CI から実行)
#
# 判定: コードスキャンの警告の一覧の API を、ref=refs/heads/main と tool_name=CodeQL で、
#       state=open と state=dismissed の2回読む。
#   開いたままの警告: rule.security_severity_level の critical / high / medium / low ごとの数と、
#                    重さの無い警告の数(重さなし)と、created_at が判定の時刻から7日以内の
#                    警告の数(直近7日)を書き、Security の画面の一覧へのリンクを書く(要件5.1)
#   却下した警告:     却下した人(dismissed_by.login)が所有者でない警告の、番号と
#                    却下した人のアカウントの名前だけを書く(要件5.2)。却下した人の無い
#                    却下も、所有者のほかの人の却下として書く。所有者の却下は書かない
#   開いたままの警告が0件で、所有者のほかの人の却下も0件 → exit 0(逸脱なし)
#   どちらかが1件以上 → 報告を書いて exit 1(逸脱あり)
#   API の失敗・応答を解釈できない → exit 2(判定不能。fail closed)
#
# 終了コード:
#   0 = 逸脱なし / 1 = 逸脱あり / 2 = 判定不能
#   1 は報告を書いたうえでの明示的な exit 1 だけが返す。環境変数の欠落と、
#   ガードしていないコマンドの想定外の失敗もすべて 2 に倒す。
#
# なぜ数だけを書くのか(要件5.3):
#   週次監査の Issue は誰でも読める。まだ直していない脆弱性の場所と中身を書くと、
#   攻撃の手がかりを公開することになる。そのため、ファイルの名前、行、クエリの ID、
#   規則の名前、警告の説明を、報告にも標準出力にも標準エラーにも出さない。
#   API の応答から読むのは、番号、重さ、作られた時刻、却下した人の名前だけにする。
#
# 所有者の読み方:
#   .github/CODEOWNERS の、最後の /.github/ の行の、@ で始まるアカウントの名前を所有者とする。
#   行の # から後ろは注釈として読まない。名前の大文字と小文字は区別しない。
#   check-codeql-pr-alerts.sh と codeql-recheck.yaml も同じ読み方をする。
#
# 一覧の数え方:
#   gh api の --paginate と --jq を併せると、jq の式がページごとに当たる。jq の式は
#   警告1件ごとに1行を出す形にし、件数は bash で行を数えて求める。
#
# テスト: .github/scripts/tests/test-check-audit-codeql-alerts.sh
# 使い方: check-audit-codeql-alerts.sh(引数なし)
#   環境変数 GH_TOKEN(必須) / GITHUB_REPOSITORY(必須)
#   NOW_EPOCH(テスト用の時刻固定)
# =====================================================================
set -Eeuo pipefail
trap 'exit 2' ERR

if [ "$#" -ne 0 ]; then
    echo "::error::引数は要りません: check-audit-codeql-alerts.sh"
    exit 2
fi
REPO="${GITHUB_REPOSITORY:-}"
# リンクに入るため、owner/repo の形を確かめる
if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "::error::環境変数 GITHUB_REPOSITORY が owner/repo の形ではありません"
    exit 2
fi
if [ -z "${GH_TOKEN:-}" ]; then
    echo "::error::環境変数 GH_TOKEN が必要です"
    exit 2
fi
NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
# 算術展開に入るため、形を確かめる(12桁まで)
if ! [[ "$NOW_EPOCH" =~ ^[1-9][0-9]{0,11}$ ]]; then
    echo "::error::NOW_EPOCH はエポック秒(先頭0なし・12桁まで)で指定してください: ${NOW_EPOCH}"
    exit 2
fi
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
RECENT_SECONDS=$((7 * 86400))
LIST_URL="https://github.com/${REPO}/security/code-scanning?query=is:open+tool:CodeQL+branch:main"

# 判定不能の報告と終了。API の障害は同じ run の再実行で解消しうる。
report_undecidable() {
    local reason="$1"
    {
        echo "### :warning: main の CodeQL の警告を数えられませんでした(判定不能)"
        echo ""
        echo "$reason"
        echo ""
        echo "**成功に倒さず赤にしています。**"
        echo "失敗したこのrunをre-run(同じrunの再実行)してください。"
        echo "新規の手動実行で流し直すと、スキップ検知の対象期間に未走査の穴が空きます。"
        echo "繰り返し失敗する場合はAPIの応答を人間が確認してください。"
        echo ""
    } >>"$SUMMARY"
    echo "main の CodeQL の警告を数えられませんでした(判定不能): ${reason}" >&2
    exit 2
}

CODEOWNERS="$(cd "$(dirname "$0")/.." && pwd)/CODEOWNERS"
if [ ! -r "$CODEOWNERS" ]; then
    report_undecidable "所有者を読む CODEOWNERS を読めませんでした。"
fi
owners=$(awk '
    { sub(/#.*/, "") }
    $1 == "/.github/" { line = $0 }
    END {
        n = split(line, f, /[ \t]+/)
        for (i = 1; i <= n; i++) if (f[i] ~ /^@[A-Za-z0-9][A-Za-z0-9-]*$/) print tolower(substr(f[i], 2))
    }' "$CODEOWNERS")
if [ -z "$owners" ]; then
    report_undecidable "CODEOWNERS の /.github/ の行に、所有者のアカウントがありません。"
fi

is_owner() {
    local login="${1,,}" owner
    [ -n "$login" ] || return 1
    while IFS= read -r owner; do
        [ "$owner" = "$login" ] && return 0
    done <<<"$owners"
    return 1
}

ALERTS="repos/${REPO}/code-scanning/alerts?ref=refs/heads/main&tool_name=CodeQL&per_page=100"

# 開いたままの警告: 番号|重さ|作られた時刻(エポック秒)
if ! open_rows=$(gh api --paginate "${ALERTS}&state=open" \
    --jq '.[] | [(.number | tostring), (.rule.security_severity_level // ""), (.created_at | fromdateiso8601 | tostring)] | join("|")'); then
    report_undecidable "開いたままの警告の一覧を読めませんでした。"
fi
# 却下した警告: 番号|却下した人
if ! dismissed_rows=$(gh api --paginate "${ALERTS}&state=dismissed" \
    --jq '.[] | [(.number | tostring), (.dismissed_by.login // "")] | join("|")'); then
    report_undecidable "却下した警告の一覧を読めませんでした。"
fi

critical=0 high=0 medium=0 low=0 none=0 recent=0 open_total=0
while IFS='|' read -r number severity created; do
    [ -n "$number" ] || continue
    if ! [[ "$number" =~ ^[0-9]+$ ]] || ! [[ "$created" =~ ^[0-9]{1,12}$ ]]; then
        report_undecidable "開いたままの警告の一覧の応答を解釈できませんでした。"
    fi
    open_total=$((open_total + 1))
    case "$severity" in
    critical) critical=$((critical + 1)) ;;
    high) high=$((high + 1)) ;;
    medium) medium=$((medium + 1)) ;;
    low) low=$((low + 1)) ;;
    "") none=$((none + 1)) ;;
    *) report_undecidable "開いたままの警告の一覧に、知らない重さがありました。" ;;
    esac
    if [ $((NOW_EPOCH - created)) -le "$RECENT_SECONDS" ]; then
        recent=$((recent + 1))
    fi
done <<<"$open_rows"

others=""
others_total=0
while IFS='|' read -r number login; do
    [ -n "$number" ] || continue
    if ! [[ "$number" =~ ^[0-9]+$ ]]; then
        report_undecidable "却下した警告の一覧の応答を解釈できませんでした。"
    fi
    # 名前は報告にそのまま入るため、GitHub のアカウントの名前の形に限る
    if [ -n "$login" ] && ! [[ "$login" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$ ]]; then
        report_undecidable "却下した警告の一覧に、アカウントの名前の形でない却下した人がありました。"
    fi
    if is_owner "$login"; then
        continue
    fi
    others_total=$((others_total + 1))
    others+="${number}|${login}"$'\n'
done <<<"$dismissed_rows"

if [ "$open_total" -eq 0 ] && [ "$others_total" -eq 0 ]; then
    echo "main に開いたままの CodeQL の警告と、所有者のほかの人の却下はありません。"
    exit 0
fi

{
    if [ "$open_total" -gt 0 ]; then
        echo "### :rotating_light: main に開いたままの CodeQL の警告があります"
        echo ""
        echo "開いたままの警告は ${open_total} 件です。重さごとの数は次のとおりです。"
        echo ""
        echo "- critical: ${critical} 件"
        echo "- high: ${high} 件"
        echo "- medium: ${medium} 件"
        echo "- low: ${low} 件"
        echo "- 重さなし: ${none} 件"
        echo ""
        echo "このうち、直近7日に見つかった警告は ${recent} 件です。"
        echo ""
        echo "警告の場所と中身は、この報告に書きません。一覧の画面で確かめてください: ${LIST_URL}"
        echo ""
    fi
    if [ "$others_total" -gt 0 ]; then
        echo "### :rotating_light: 所有者のほかの人が却下した CodeQL の警告があります"
        echo ""
        while IFS='|' read -r number login; do
            [ -n "$number" ] || continue
            if [ -n "$login" ]; then
                echo "- 警告の番号 ${number}: 却下した人 \`${login}\`"
            else
                echo "- 警告の番号 ${number}: 却下した人の記録がありません"
            fi
        done < <(printf '%s' "$others" | LC_ALL=C sort -n -t'|' -k1,1)
        echo ""
        echo "知らない却下があれば、所有者は警告の画面で却下を取り消してください。"
        echo ""
    fi
} >>"$SUMMARY"
echo "main の CodeQL の警告: 開いたまま ${open_total} 件、所有者のほかの人の却下 ${others_total} 件" >&2
exit 1
