#!/usr/bin/env bash
# =====================================================================
# 依存グラフのスナップショットが空でないことの検査
#
# 判定: 出力先が無い、JSONが1件も無い、解析できない、解決済みパッケージが
#       0件のいずれかで exit 1(赤)。
#
# なぜ必要か:
#   gradle/actions/dependency-submission は、依存解決が空または部分的な結果を
#   出しても exit 0 で終わる。空のスナップショットが送られると、
#   dependency-review と dependency-cooldown は「このPRで追加された依存は0件」と
#   判定して緑になり、正常系と区別がつかない。
#
#   backendのDependabotアラートも同じ生成機構に依存している。GitHubはGradleを
#   静的解析できず、送信しない限りMaven/Gradleのパッケージは1件も登録されない。
#   つまり「アラートが出ない」と「脆弱性が無い」が区別できなくなる。
#
# 何を捉えないか:
#   捉えるのは「空」まで。部分的に欠けたグラフは検知できない。
#   また送信より後の区間(GitHubへの取り込み・compare API・アドバイザリ照合)も
#   対象外で、そちらは月次のカナリアが受け持つ。
#
# 解析できない入力を通さないのは、jq の失敗を握りつぶすと
# 「0件」と「読めなかった」が同じ扱いになり、この検査自体が
# fail-open になるため。
#
# テスト: .github/scripts/tests/test-check-dependency-snapshot.sh
# 使い方: check-dependency-snapshot.sh <report_dir>
# =====================================================================
set -euo pipefail

REPORT_DIR="${1:?report dir required}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# jq が無いと解析できない。無いことを「解析失敗」と同じ扱いにすると、
# 原因が分からないまま赤が続くため、先に切り分けて報告する。
if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq が見つかりません。この検査には jq が要ります。"
    exit 1
fi

if [ ! -d "$REPORT_DIR" ]; then
    echo "::error::スナップショットの出力先が存在しません: ${REPORT_DIR}"
    exit 1
fi

files=$(find "$REPORT_DIR" -type f -name '*.json' | sort)

if [ -z "$files" ]; then
    echo "::error::スナップショットのJSONが1件もありません: ${REPORT_DIR}"
    exit 1
fi

total=0

while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! count=$(jq '[.manifests // {} | .[] | .resolved // {} | length] | add // 0' "$f" 2>/dev/null); then
        echo "::error::スナップショットを解析できません: ${f}"
        exit 1
    fi
    case "$count" in
        '' | *[!0-9]*)
            echo "::error::パッケージ数を数値として取得できません: ${f}"
            exit 1
            ;;
    esac
    echo "  ${f}: ${count}"
    total=$((total + count))
done <<EOF
${files}
EOF

echo "解決されたパッケージ数: ${total}"

{
    echo "### 依存グラフのスナップショット"
    echo ""
    echo "解決されたパッケージ数: ${total}"
    echo ""
} >>"$SUMMARY"

if [ "$total" -eq 0 ]; then
    echo "::error::依存グラフが空です。このまま送信すると、追加された依存が0件と判定され、脆弱性とクールダウンの検査が素通りします。"
    {
        echo ":no_entry: **依存グラフが空です。**"
        echo ""
        echo "このまま送信すると、追加された依存が0件と判定され、"
        echo "脆弱性とクールダウンの検査が素通りします。"
        echo ""
    } >>"$SUMMARY"
    exit 1
fi
