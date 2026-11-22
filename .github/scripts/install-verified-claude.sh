#!/usr/bin/env bash
# =====================================================================
# Claude Code の CLI を配布元から取り、配布元の署名を確かめてから PATH に足す
# (.github/actions/verified-claude から呼ぶ)
#
# なぜ要るのか:
#   claude-auto-fix-target.yaml の edit ジョブは、Claude を動かす鍵(CLAUDE_CODE_OAUTH_TOKEN)を扱う。
#   そのため、Claude Code の配布元が署名した物だけを使う。
#
# 確かめ方:
#   1. 配布元の GPG の公開鍵(<配布元>/keys/claude-code.asc)を取り込み、取り込んだ主鍵が
#      1つだけで、その指紋が下の CLAUDE_KEY_FPR であることを確かめる
#   2. 版の manifest.json の署名(manifest.json.sig)を gpg で確かめ、署名した主鍵の指紋が
#      CLAUDE_KEY_FPR であることを確かめる
#   3. 署名された manifest.json の version が入れる版であることを確かめ、
#      platforms.linux-x64.checksum を読む
#   4. linux-x64/claude の SHA-256 を、3 の値と照らす
#   5. 照らした claude を置いた場所を GITHUB_PATH に足す
#   どれかで確かめられなければ、CLI を PATH に足さずに失敗で終わる。
#
# テスト: .github/scripts/tests/test-install-verified-claude.sh
# 使い方: install-verified-claude.sh <版>
#   環境変数 CLAUDE_DIST_BASE CLAUDE_INSTALL_DIR は、テストで取り先と置き場を差し替えるためのもの
# =====================================================================
set -euo pipefail

# Claude Code の公式の文書が示す、配布元の署名の鍵の指紋
CLAUDE_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

fail() {
    echo "::error::Claude Code の CLI の署名を確かめられませんでした: $1" >&2
    exit 1
}

[ "$#" -eq 1 ] || fail "使い方: install-verified-claude.sh <版>"
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "版の形が違います: ${VERSION}"
[ "$(uname -m)" = x86_64 ] || fail "x64 のランナーにだけ対応しています: $(uname -m)"
[ -n "${GITHUB_PATH:-}" ] || fail "GITHUB_PATH がありません。"

BASE="${CLAUDE_DIST_BASE:-https://downloads.claude.ai}"
KEY_URL="${BASE}/keys/claude-code.asc"
DIST="${BASE}/claude-code-releases/${VERSION}"
PLATFORM=linux-x64
DEST="${CLAUDE_INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/verified-claude}/${VERSION}"

WORK=$(mktemp -d)
GNUPGHOME="$WORK/gnupg"
export GNUPGHOME
trap 'gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
mkdir -m 700 "$GNUPGHOME"

get() {
    curl -fsSL --retry 2 --max-time 600 -o "$2" "$1" || fail "取れませんでした: $1"
}

# 1. 公開鍵の指紋
get "$KEY_URL" "$WORK/key.asc"
gpg --batch --quiet --import "$WORK/key.asc" >/dev/null 2>&1 || fail "公開鍵を取り込めませんでした: ${KEY_URL}"
KEYS=$(gpg --batch --with-colons --list-keys 2>/dev/null |
    awk -F: '$1 == "pub" { p = 1; next } $1 == "fpr" && p { print $10; p = 0 }')
[ "$KEYS" = "$CLAUDE_KEY_FPR" ] ||
    fail "公開鍵の指紋が、配布元の鍵の指紋(${CLAUDE_KEY_FPR})と違います: $(printf '%s' "$KEYS" | tr '\n' ' ')"

# 2. manifest.json の署名
get "${DIST}/manifest.json" "$WORK/manifest.json"
get "${DIST}/manifest.json.sig" "$WORK/manifest.json.sig"
gpg --batch --status-file "$WORK/status" --verify "$WORK/manifest.json.sig" "$WORK/manifest.json" >/dev/null 2>&1 ||
    fail "manifest.json の署名が正しくありません。"
grep -q '^\[GNUPG:\] GOODSIG ' "$WORK/status" ||
    fail "manifest.json に、期限内で失効していない鍵の署名がありません。"
SIGNERS_FOUND=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' "$WORK/status")
[ -n "$SIGNERS_FOUND" ] || fail "manifest.json の署名した者を読めませんでした。"
for signer in $SIGNERS_FOUND; do
    [ "$signer" = "$CLAUDE_KEY_FPR" ] || fail "manifest.json の署名した者(${signer})が、配布元の鍵ではありません。"
done

# 3. 署名された manifest.json の版と SHA-256
got_version=$(jq -r '.version | strings' "$WORK/manifest.json" 2>/dev/null) || got_version=""
[ "$got_version" = "$VERSION" ] || fail "署名された manifest.json の版(${got_version})が、入れる版(${VERSION})と違います。"
want=$(jq -r --arg p "$PLATFORM" '.platforms[$p].checksum | strings' "$WORK/manifest.json" 2>/dev/null) || want=""
[[ "$want" =~ ^[0-9a-f]{64}$ ]] || fail "署名された manifest.json に、${PLATFORM} の SHA-256 がありません。"

# 4. 実行ファイルの SHA-256
get "${DIST}/${PLATFORM}/claude" "$WORK/claude"
got=$(sha256sum "$WORK/claude" | awk '{ print $1 }')
[ "$got" = "$want" ] || fail "${PLATFORM}/claude の SHA-256 が、署名された manifest.json の値と違います。"

# 5. 置いて PATH に足す
rm -rf "$DEST"
mkdir -p "$DEST"
mv "$WORK/claude" "$DEST/claude"
chmod +x "$DEST/claude"
echo "$DEST" >>"$GITHUB_PATH"
echo "Claude Code の CLI ${VERSION} を、配布元の鍵 ${CLAUDE_KEY_FPR} の署名で確かめてから入れました。"
