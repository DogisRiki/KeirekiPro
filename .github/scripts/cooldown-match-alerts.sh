#!/usr/bin/env bash
# =====================================================================
# 公開から72時間経っていない版を、Dependabot の脆弱性の警告に照らす
# (check-dependency-cooldown.sh から呼ばれる)
#
# 判定: 版ごとに、次の5つを満たす警告が1つでもあれば、72時間待たずに入れてよい
#       (eligible)。満たす警告が2つ以上あれば、すべてを理由の警告として返す。
#   - state が open
#   - dependency.package の ecosystem と name が、その版の部品と同じ
#   - security_advisory.severity が high か critical
#   - dependency.scope が runtime
#   - security_vulnerability.first_patched_version.identifier が、その版と同じ
#
# なぜ vulnerable_version_range を読まないのか:
#   警告は main の依存に対して開く。開いている警告があること自体が、このリポジトリが
#   今その部品の脆弱な版を使っていることを示す。72時間待たずに入れるのは最初の修正版
#   だけなので、版の範囲の解釈は要らない。
#
# なぜ scope と severity を API の絞り込みに使わないのか:
#   入れてはいけない理由を分けて報告するためである。1つの部品に条件を満たさない警告が
#   いくつかあるときは、最初の修正版の一致に最も近い理由を返す。近い順は
#   not-first-patched、no-scope、development、low-severity、no-alert である。
#
# 警告の API が失敗した部品は alerts-unreadable にして続ける。alerts-unreadable の版は
# 72時間待たずには入らないので、API の失敗で変更が入ることはない。
#
# テスト: .github/scripts/tests/test-cooldown-match-alerts.sh
# 使い方: cooldown-match-alerts.sh <入力のファイル>
#   入力: [{"ecosystem":"npm"|"maven","name","version"}]
#   出力(標準出力): 入力と同じ順の配列。要素は
#     {"ecosystem","name","version","eligible","alerts":[{"number","ghsa_id","severity","html_url"}],
#      "reason","first_patched":["<版>"]}
#   環境変数 GH_TOKEN(必須。vulnerability-alerts: read の権限) / GITHUB_REPOSITORY(必須)
#   終了コード 0 = 判定できた(alerts-unreadable を含む) / 2 = 引数か入力の誤り
# =====================================================================
set -euo pipefail

INPUT="${1:-}"
if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
    echo "使い方: cooldown-match-alerts.sh <入力のファイル>" >&2
    exit 2
fi
if [ -z "${GITHUB_REPOSITORY:-}" ] || [ -z "${GH_TOKEN:-}" ]; then
    echo "GITHUB_REPOSITORY と GH_TOKEN が要ります。" >&2
    exit 2
fi
REPO="$GITHUB_REPOSITORY"

if ! jq -e 'type == "array" and all(.[]; type == "object"
        and (.ecosystem | type) == "string" and (.name | type) == "string"
        and (.version | type) == "string")' "$INPUT" >/dev/null 2>&1; then
    echo "入力が [{\"ecosystem\",\"name\",\"version\"}] の形の JSON の配列ではありません: ${INPUT}" >&2
    exit 2
fi

# 1つの部品の警告(--paginate --slurp のページの配列)を、その版の判定にする。
# shellcheck disable=SC2016 # jq の変数であり、シェルの展開ではない
CLASSIFY='
($item.ecosystem | ascii_downcase) as $eco | $item.name as $name | $item.version as $ver
| [ .[] | if type == "array" then .[] else . end ] as $all
| [ $all[] | select(.state == "open")
    | select(((.dependency.package.ecosystem // "") | ascii_downcase) == $eco
        and .dependency.package.name == $name) ] as $alerts
| [ $alerts[]
    | ((.security_advisory.severity // "") | ascii_downcase) as $sev
    | .dependency.scope as $scope
    | (.security_vulnerability.first_patched_version.identifier // null) as $fp
    | { alert: {number, ghsa_id: .security_advisory.ghsa_id, severity: $sev, html_url},
        fp: $fp,
        class: (if ($sev == "high" or $sev == "critical") | not then "low-severity"
                elif $scope == "development" then "development"
                elif $scope != "runtime" then "no-scope"
                elif $fp != $ver then "not-first-patched"
                else "eligible" end) } ] as $c
| (first(("eligible", "not-first-patched", "no-scope", "development", "low-severity") as $o
         | select(any($c[]; .class == $o)) | $o) // "no-alert") as $reason
| { ecosystem: $item.ecosystem, name: $name, version: $ver,
    eligible: ($reason == "eligible"),
    alerts: (if $reason == "eligible" then [ $c[] | select(.class == "eligible") | .alert ] else [] end),
    reason: $reason,
    first_patched: (if $reason == "not-first-patched"
        then [ $c[] | select(.class == "not-first-patched") | .fp | select(. != null) ] | unique
        else [] end) }
'

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
: >"$TMP/results.jsonl"

count=$(jq 'length' "$INPUT")
for ((i = 0; i < count; i++)); do
    item=$(jq -c ".[$i]" "$INPUT")
    query=$(jq -r '"ecosystem=\(.ecosystem | ascii_downcase | @uri)&package=\(.name | @uri)"' <<<"$item")
    pages=""
    result=""
    # 答えが配列でないときと、要素が警告の形でなく判定の jq が失敗したときも、読めなかったものにする
    if pages=$(gh api --paginate --slurp \
        "repos/${REPO}/dependabot/alerts?state=open&${query}&per_page=100" 2>"$TMP/gh.err") &&
        jq -e 'type == "array"' <<<"$pages" >/dev/null 2>&1 &&
        result=$(jq -c --argjson item "$item" "$CLASSIFY" <<<"$pages" 2>>"$TMP/gh.err"); then
        echo "$result" >>"$TMP/results.jsonl"
    else
        echo "警告の API を読めませんでした: $(jq -r '"\(.ecosystem) \(.name)"' <<<"$item"): $(head -c 300 "$TMP/gh.err")" >&2
        jq -c '{ecosystem, name, version, eligible: false, alerts: [],
                reason: "alerts-unreadable", first_patched: []}' <<<"$item" >>"$TMP/results.jsonl"
    fi
done

jq -s . "$TMP/results.jsonl"
