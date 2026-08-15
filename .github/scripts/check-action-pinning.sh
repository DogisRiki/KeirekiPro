#!/usr/bin/env bash
# =====================================================================
# アクション参照のSHA固定チェック(guardrails CI から実行)
#
# 判定: タグ参照などSHA以外の参照が1件でもあれば exit 1(赤)。無ければ exit 0(緑)
#
# 検査対象: .github/workflows/ 配下のワークフローと .github/actions/ 配下の
#   composite action の `uses:` 行。
#
# 許可する形式:
#   - uses: owner/repo@<40桁のSHA> # <バージョン>
#   - uses: owner/repo/path@<40桁のSHA> # <バージョン>
#   - uses: ./... (同一リポジトリ内のローカル参照。SHAで固定する対象ではない)
#
# なぜタグ参照を許さないのか:
#   タグは上流で差し替えが可能なため、こちらのコミットを一切変更しなくても実行される
#   内容が変わり得る。2025-03の tj-actions/changed-files はタグ上書きで全利用者が
#   影響を受けた事例で、CIが実行するコードの供給源としてnpm依存と同じ危険がある。
#
# なぜバージョンのコメントを必須にするのか:
#   SHAだけでは、どの版を使っているのか人間が読めない。またDependabotはこの形式を
#   認識して更新時にSHAとコメントの両方を書き換えるため、コメントが無いと
#   更新後にどの版へ上がったのかが追えなくなる。
#
# なぜ差分ではなく現在の状態を見るのか:
#   差分だけを見ると、このチェックが入る前から残っているタグ参照を見逃す。
#   ワークフローの本数は少なく全件走査の費用も小さいため、常に全体を検証する。
#
# テスト: .github/scripts/tests/test-check-action-pinning.sh
# 使い方: check-action-pinning.sh
# =====================================================================
set -euo pipefail

files=$(git ls-files \
    '.github/workflows/*.yml' '.github/workflows/*.yaml' \
    '.github/actions/**/action.yml' '.github/actions/**/action.yaml' || true)

if [ -z "$files" ]; then
    echo "検査対象のワークフローがありません。"
    exit 0
fi

# `uses:` は単独の行にも、リスト項目の先頭(`- uses:`)にも書ける。両方を拾う。
# -H はファイルが1つでも必ずファイル名を出すため(xargs の分割で件数が変わっても
# 出力の形式が変わらないようにする)。grep は -q 無しで全入力を読む
# (大量の入力でSIGPIPEにより見落とすことを避けるため)。
uses_lines=$(printf '%s\n' "$files" | tr '\n' '\0' |
    xargs -0 grep -HnE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[^[:space:]]' || true)

violations=""
while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    # entry の形式: <ファイル>:<行番号>:<行の中身>
    location="${entry%%:*}"
    rest="${entry#*:}"
    location="$location:${rest%%:*}"
    content="${rest#*:}"
    # 先頭の空白・リスト記号・`uses:` を取り除き、参照だけを取り出す
    ref="${content#"${content%%[![:space:]]*}"}"
    ref="${ref#- }"
    ref="${ref#"${ref%%[![:space:]]*}"}"
    ref="${ref#uses:}"
    ref="${ref#"${ref%%[![:space:]]*}"}"

    case "$ref" in
    ./*) continue ;;
    esac
    if printf '%s' "$ref" |
        grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._/-]+@[0-9a-fA-F]{40}[[:space:]]+#[[:space:]]*[^[:space:]]'; then
        continue
    fi
    violations+="$location: $ref"$'\n'
done <<<"$uses_lines"

if [ -z "$violations" ]; then
    echo "アクション参照のSHA固定チェック: 違反なし"
    exit 0
fi

{
    echo "### :pushpin: SHAで固定されていないアクション参照"
    echo ""
    echo '```'
    echo "$violations"
    echo '```'
    echo "\`uses: owner/repo@<40桁のSHA> # vX.Y.Z\` の形式にしてください。"
    echo "SHAの取得: \`gh api repos/<owner>/<repo>/commits/<tag> --jq .sha\`"
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

echo "::error::[SHAで固定されていないアクション参照] タグ参照は上流での差し替えにより実行内容が変わり得るため使えません。uses: owner/repo@<40桁のSHA> # vX.Y.Z の形式にしてください。"
echo "$violations"
exit 1
