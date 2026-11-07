#!/usr/bin/env bash
# =====================================================================
# PR が持ち込んだ CodeQL の警告でマージを止める判定(codeql.yaml の codeql-complete から実行)
#
# 判定: コードスキャンの警告の一覧の API を tool_name=CodeQL で2回読む。
#   main の一覧: ref=refs/heads/main。most_recent_instance.state が fixed でない警告を、
#                main にすでにある警告とする
#   PR の一覧:   ref=refs/pull/<PR の番号>/merge
#   PR の一覧の警告のうち、次の4つにすべて当てはまる警告を、マージを止める警告として数える。
#     1. main にすでにある警告ではない(要件3.2)
#     2. rule.security_severity_level が critical / high / medium のどれか(要件3.1、3.3)。
#        security_severity_level の無い警告は数えない
#     3. 所有者が却下した警告ではない。所有者が却下した警告とは、state が dismissed で、
#        dismissed_by.login が所有者の警告である。この条件を most_recent_instance.state
#        より先に見る(要件4.2)
#     4. state が dismissed である。または、most_recent_instance.state が open である(要件4.3)
#
# 終了コード:
#   0 = マージを止める警告が0件
#   1 = マージを止める警告が1件以上(警告の番号と重さだけを標準出力に1行ずつ書く)
#   2 = 判定不能(引数か環境変数の欠落、所有者を読めない、API の失敗、応答を解釈できない)
#   1 は警告を書いたうえでの明示的な exit 1 だけが返す。ガードしていないコマンドの
#   想定外の失敗も 2 に倒す。どちらも codeql-complete を赤にする。
#
# なぜ番号と重さだけを出すのか:
#   GitHub Actions の実行の記録は誰でも読める。まだ直していない脆弱性の場所と中身を
#   出さないよう、ファイルの名前、行、規則の名前、警告の説明を、標準出力にも
#   標準エラーにも出さない。Claude は、警告の番号から API で中身を読む。
#
# なぜ ruleset の code_scanning 規則を使わないのか:
#   GitHub の文書は、この規則が却下した人を区別するとは書いていない。Claude の
#   アカウントは警告を却下できるので、規則に任せると、Claude が却下した警告で
#   マージが止まらないおそれがある(要件4.3)。
#
# 所有者の読み方:
#   .github/CODEOWNERS の、最後の /.github/ の行の、@ で始まるアカウントの名前を所有者とする。
#   行の # から後ろは注釈として読まない。名前の大文字と小文字は区別しない(GitHub の
#   アカウントの名前と同じ)。check-audit-codeql-alerts.sh と codeql-recheck.yaml も同じ読み方をする。
#
# 一覧の数え方:
#   gh api の --paginate と --jq を併せると、jq の式がページごとに当たる。jq の式は
#   警告1件ごとに1行を出す形にし、件数は bash で行を数えて求める。
#
# テスト: .github/scripts/tests/test-check-codeql-pr-alerts.sh
# 使い方: check-codeql-pr-alerts.sh <PR の番号>
#   環境変数 GITHUB_REPOSITORY(必須)。gh は GH_TOKEN で認証する
# =====================================================================
set -Eeuo pipefail
trap 'exit 2' ERR

PR="${1:-}"
if ! [[ "$PR" =~ ^[1-9][0-9]*$ ]]; then
    echo "使い方: check-codeql-pr-alerts.sh <PR の番号>" >&2
    exit 2
fi
REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
    echo "環境変数 GITHUB_REPOSITORY がありません" >&2
    exit 2
fi

CODEOWNERS="$(cd "$(dirname "$0")/.." && pwd)/CODEOWNERS"
if [ ! -r "$CODEOWNERS" ]; then
    echo "所有者を読む CODEOWNERS を読めません" >&2
    exit 2
fi
owners=$(awk '
    { sub(/#.*/, "") }
    $1 == "/.github/" { line = $0 }
    END {
        n = split(line, f, /[ \t]+/)
        for (i = 1; i <= n; i++) if (f[i] ~ /^@[A-Za-z0-9][A-Za-z0-9-]*$/) print tolower(substr(f[i], 2))
    }' "$CODEOWNERS")
if [ -z "$owners" ]; then
    echo "CODEOWNERS の /.github/ の行に、所有者のアカウントがありません" >&2
    exit 2
fi

is_owner() {
    local login="${1,,}" owner
    [ -n "$login" ] || return 1
    while IFS= read -r owner; do
        [ "$owner" = "$login" ] && return 0
    done <<<"$owners"
    return 1
}

ALERTS="repos/${REPO}/code-scanning/alerts?tool_name=CodeQL&per_page=100"

if ! main_numbers=$(gh api --paginate "${ALERTS}&ref=refs/heads/main" \
    --jq '.[] | select(.most_recent_instance.state != "fixed") | .number'); then
    echo "main の CodeQL の警告の一覧を読めませんでした(判定不能)" >&2
    exit 2
fi
if ! pr_rows=$(gh api --paginate "${ALERTS}&ref=refs/pull/${PR}/merge" \
    --jq '.[] | [(.number | tostring), (.state // ""), (.dismissed_by.login // ""), (.most_recent_instance.state // ""), (.rule.security_severity_level // "")] | join("|")'); then
    echo "PR #${PR} の CodeQL の警告の一覧を読めませんでした(判定不能)" >&2
    exit 2
fi

declare -A ON_MAIN=()
while IFS= read -r number; do
    [ -n "$number" ] || continue
    if ! [[ "$number" =~ ^[0-9]+$ ]]; then
        echo "main の CodeQL の警告の一覧の応答を解釈できませんでした(判定不能)" >&2
        exit 2
    fi
    ON_MAIN[$number]=1
done <<<"$main_numbers"

blocking=""
while IFS='|' read -r number state dismissed_by instance_state severity; do
    [ -n "$number" ] || continue
    if ! [[ "$number" =~ ^[0-9]+$ ]]; then
        echo "PR #${PR} の CodeQL の警告の一覧の応答を解釈できませんでした(判定不能)" >&2
        exit 2
    fi
    [ -z "${ON_MAIN[$number]+set}" ] || continue
    case "$severity" in
    critical | high | medium) ;;
    *) continue ;;
    esac
    if [ "$state" = dismissed ] && is_owner "$dismissed_by"; then
        continue
    fi
    if [ "$state" = dismissed ] || [ "$instance_state" = open ]; then
        blocking+="${number} ${severity}"$'\n'
    fi
done <<<"$pr_rows"

if [ -z "$blocking" ]; then
    exit 0
fi
count=$(printf '%s' "$blocking" | grep -c .)
printf '%s' "$blocking" | LC_ALL=C sort -n -k1,1
echo "PR #${PR} が持ち込んだ、重さが中以上の CodeQL の警告が ${count} 件あります。警告の番号と重さを標準出力に書きました" >&2
exit 1
