#!/usr/bin/env bash
# =====================================================================
# Javaテストのアサーション有無レポート(現状はレポートモード = 常に exit 0)
#
# @Test メソッドのうち、アサーション系トークン
# (assert* / verify / assertThat / assertThatThrownBy / fail 等)を
# 含まないものをヒューリスティックに検出して一覧化する。
#
# 昇格条件(週次監査で判定):
#   誤検知パターンの除外リスト整備完了 かつ 検出バックログゼロ
#   -> 満たした時点でこのスクリプトを exit 1(ブロックモード)へ昇格する
#
# 除外リスト: .github/scripts/java-assertion-exclusions.txt
#   (1行1エントリ「ファイルパス#メソッド名」。理由をコメントで併記すること)
# =====================================================================
set -uo pipefail

TEST_DIR="backend/src/test/java"
EXCLUSIONS_FILE=".github/scripts/java-assertion-exclusions.txt"

findings=$(find "$TEST_DIR" -name '*.java' -print0 2>/dev/null | xargs -0 awk '
    /@Test\b/ { pending=1 }
    pending && /(void|public)[ \t].*\(/ && !collecting {
        collecting=1; pending=0; depth=0; started=0; buf=""
        name=$0; sub(/\(.*/, "", name); sub(/.*[ \t]/, "", name)
    }
    collecting {
        buf = buf $0 "\n"
        n = gsub(/{/, "{"); depth += n; if (n > 0) started=1
        depth -= gsub(/}/, "}")
        if (started && depth <= 0) {
            if (buf !~ /assert[A-Za-z]*[ \t]*\(|verify[A-Za-z]*[ \t]*\(|\bfail[ \t]*\(|assertThatThrownBy|expectThrows|\.check\(/) {
                print FILENAME "#" name
            }
            collecting=0
        }
    }
' | sort -u)

# 除外リストの適用
if [ -f "$EXCLUSIONS_FILE" ]; then
    exclusions=$(grep -vE '^\s*(#|$)' "$EXCLUSIONS_FILE" | sort -u || true)
    findings=$(comm -23 <(echo "$findings") <(echo "$exclusions") || true)
fi

count=$(echo "$findings" | grep -c . || true)

{
    echo "### :mag: Javaテスト アサーション有無レポート(レポートモード)"
    echo ""
    echo "アサーションを含まない可能性のある @Test メソッド: **${count} 件**"
    if [ "$count" -gt 0 ]; then
        echo ""
        echo '```'
        echo "$findings"
        echo '```'
        echo ""
        echo "誤検知(ヘルパーメソッド内でアサーションを行う等)は理由を添えて ${EXCLUSIONS_FILE} に追加してください。"
    fi
    echo ""
    echo "> 昇格条件: 除外リスト整備完了かつバックログゼロでブロックモード(exit 1)へ昇格(週次監査で判定)"
} >>"${GITHUB_STEP_SUMMARY:-/dev/stdout}"

echo "Javaアサーションレポート: ${count} 件(レポートモードのため常に成功)"
exit 0
