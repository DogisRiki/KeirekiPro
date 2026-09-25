#!/usr/bin/env bash
# =====================================================================
# Trivy の版の一致判定(audit-weekly CI から実行)
#
# 判定: 引数の各ワークフローの `env:` にある `TRIVY_VERSION: '<版>'` を読み、
#       すべて同じ版 → exit 0(逸脱なし)
#       版が食い違う → exit 1(逸脱あり。ファイルごとの版を報告)
#       ファイルが読めない・定義が無い・複数ある・版の形が不正
#         → exit 2(判定不能。fail closed)
#
# 終了コード:
#   0 = 逸脱なし / 1 = 逸脱あり / 2 = 判定不能
#   1 は食い違いを報告したうえでの明示的な exit 1 だけが返す。引数の欠落と、
#   ガードしていないコマンドの想定外の失敗もすべて 2 に倒す。
#   1 に混ぜると、判定が一度も完了していないのに「逸脱あり」として扱われる。
#
# なぜ必要か:
#   PRの検査(container-scan.yaml)と稼働中イメージの定期検査
#   (container-scan-scheduled.yaml)は、それぞれ TRIVY_VERSION を持つ。
#   片方だけ更新されると、同じイメージでも検出結果が変わり、PRでは緑なのに
#   定期検査でだけ検出される(またはその逆の)状態が静かに続く。
#   以前は月次の確認項目(月次4)として人間が見比べていた(#310、#334)。
#
# なぜ `env:` の行だけを読むのか:
#   2本とも、ワークフロー先頭の `env:` に2字下げで `TRIVY_VERSION: '<版>'` を
#   置き、各ステップは `${{ env.TRIVY_VERSION }}` で参照する形になっている。
#   それ以外の書き方に変わった場合は、読み違えて緑にしないよう判定不能にする。
#
# テスト: .github/scripts/tests/test-check-audit-trivy-version.sh
# 使い方: check-audit-trivy-version.sh <workflow_file> <workflow_file> [...]
#   外部への問い合わせは行わない。環境変数 GITHUB_STEP_SUMMARY(任意)
# =====================================================================
set -Eeuo pipefail
# ガードしていないコマンドの失敗は、逸脱(1)ではなく判定不能(2)にする。
trap 'exit 2' ERR

if [ "$#" -lt 2 ]; then
    echo "::error::引数は2個以上必要です: <workflow_file> <workflow_file> [...]"
    exit 2
fi

SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# 判定不能の報告と終了。
report_undecidable() {
    local reason="$1"
    {
        echo "### :warning: Trivy の版を確認できませんでした(判定不能)"
        echo ""
        echo "$reason"
        echo ""
        echo "**成功に倒さず赤にしています。**"
        echo "ワークフローの \`env:\` にある \`TRIVY_VERSION\` の書き方が変わっていないかを確認してください。"
        echo ""
    } >>"$SUMMARY"
    echo "Trivy の版を確認できませんでした(判定不能): ${reason}" >&2
    exit 2
}

# --- 各ファイルの版の取得 --------------------------------------------------------
files=()
versions=()
for f in "$@"; do
    if [ ! -r "$f" ]; then
        report_undecidable "ファイルを読めません: \`${f}\`"
    fi
    # grep は一致0件で終了コード1を返すため、ERR トラップに掛けないよう || で受ける
    matches=$(grep -E "^  TRIVY_VERSION:" "$f" || true)
    count=0
    if [ -n "$matches" ]; then
        count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
    fi
    if [ "$count" -ne 1 ]; then
        report_undecidable "\`${f}\` の \`env:\` に TRIVY_VERSION の定義が1件ではありません(${count}件)。"
    fi
    if ! [[ "$matches" =~ ^\ \ TRIVY_VERSION:\ \'([0-9]+\.[0-9]+\.[0-9]+)\'[[:space:]]*$ ]]; then
        report_undecidable "\`${f}\` の TRIVY_VERSION の形を解釈できません: \`${matches}\`"
    fi
    files+=("$f")
    versions+=("${BASH_REMATCH[1]}")
done

# --- 一致の判定 -----------------------------------------------------------------
mismatch=0
for v in "${versions[@]}"; do
    if [ "$v" != "${versions[0]}" ]; then
        mismatch=1
    fi
done

if [ "$mismatch" -ne 0 ]; then
    {
        echo "### :rotating_light: Trivy の版が食い違っています"
        echo ""
        for i in "${!files[@]}"; do
            echo "- \`${files[$i]}\`: ${versions[$i]}"
        done
        echo ""
        echo "PRの検査と稼働中イメージの定期検査で、検出結果が変わるおそれがあります。"
        echo "どちらかに揃えるPRを作るよう、Issueで指示してください。"
        echo ""
    } >>"$SUMMARY"
    echo "Trivy の版が食い違っています。" >&2
    exit 1
fi

echo "Trivy の版は一致しています(${versions[0]})。"
exit 0
