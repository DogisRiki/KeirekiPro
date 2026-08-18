#!/usr/bin/env bash
# =====================================================================
# 実行時の Trivy 本体のバージョンが、指定した値と一致することの検査
#
# 判定: 一致すれば exit 0、一致しない・取得できないのいずれかで exit 1(赤)。
#
# なぜ必要か:
#   setup-trivy の `version` 入力の既定値は 'latest' で、指定を省くと
#   Trivy 本体はまったく固定されず、実行のたびに最新版が入る。
#   2026-03-19 の供給網侵害(GHSA-69fq-xp46-6x23)では悪性の v0.69.4 が
#   配布されており、アクション側をSHA固定してもツール本体は固定されない。
#   ワークフローの `version:` 指定が意図どおり効いているかを実行時に確かめる。
#
#   取得できない場合も不一致と同じ扱いにする。切り分けられないまま緑にすると、
#   この検査自体が fail-open になるため。
#
# 何を捉えないか:
#   捉えるのは「指定した版が入ったか」まで。その版そのものが安全かどうかは
#   検証しない。採用版が侵害の影響範囲外であることの根拠は
#   .kiro/specs/container-image-vulnerability-scanning/design.md の
#   Security Considerations に記録する。
#
# トップレベルの .Version だけを見るのは、同じ出力に
# .VulnerabilityDB.Version と .JavaDB.Version も含まれるため。
# grep や再帰的な jq では誤爆する。
#
# 完全一致で比較するのは、部分一致にすると将来 0.74.10 が出たときに
# 0.74.1 の指定で誤って通るため。
#
# 比較の前に両側の先頭の v を落とすのは、setup-trivy の `version:` には
# v 付き(v0.74.0)を渡す一方、trivy --version の出力は v が付かない
# (0.74.0)ため。表記の違いだけで赤くしない。
#
# テスト: .github/scripts/tests/test-check-trivy-version.sh
# 使い方: check-trivy-version.sh <expected-version>
#   expected-version は v を含まないバージョン文字列(例: 0.74.0)
# =====================================================================
set -euo pipefail

# 先頭の v を落として突き合わせる。両側を同じ形に揃える。
EXPECTED="${1:?expected version required}"
EXPECTED="${EXPECTED#v}"
# v を落とした結果が空になる場合(引数が "v" だけ)もここで弾く。
# 空の期待値を通すと、trivy が空の Version を返したときに一致してしまう。
: "${EXPECTED:?expected version required}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq が見つかりません。この検査には jq が要ります。"
    exit 1
fi

# trivy 自体の失敗と、出力が JSON でない場合の双方をここで受ける
if ! raw=$(trivy --version --format json 2>/dev/null); then
    echo "::error::trivy のバージョンを取得できませんでした。"
    {
        echo "### Trivy のバージョン検証"
        echo ""
        echo ":no_entry: **trivy のバージョンを取得できませんでした。**"
        echo ""
    } >>"$SUMMARY"
    exit 1
fi

if ! actual=$(printf '%s' "$raw" | jq -er '.Version' 2>/dev/null); then
    echo "::error::trivy のバージョン出力を解析できませんでした。"
    {
        echo "### Trivy のバージョン検証"
        echo ""
        echo ":no_entry: **trivy のバージョン出力を解析できませんでした。**"
        echo ""
    } >>"$SUMMARY"
    exit 1
fi

actual="${actual#v}"

if [ "$actual" != "$EXPECTED" ]; then
    echo "::error::Trivy のバージョンが指定と一致しません。期待=${EXPECTED} 実際=${actual}"
    {
        echo "### Trivy のバージョン検証"
        echo ""
        echo ":no_entry: **Trivy のバージョンが指定と一致しません。**"
        echo ""
        echo "| 項目 | 値 |"
        echo "|---|---|"
        echo "| 期待 | \`${EXPECTED}\` |"
        echo "| 実際 | \`${actual}\` |"
        echo ""
    } >>"$SUMMARY"
    exit 1
fi

echo "Trivy のバージョンは指定と一致: ${actual}"
