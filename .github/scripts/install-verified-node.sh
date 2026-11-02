#!/usr/bin/env bash
# =====================================================================
# Node.js を nodejs.org から取り、配布元の署名を確かめてから PATH に足す
# (.github/actions/verified-node から呼ぶ)
#
# なぜ要るのか:
#   actions/setup-node は actions/node-versions が詰め直した tarball を入れ、配布元の署名を
#   確かめない。CI は本番に配る frontend のファイルを組み立て、秘密の値を扱うので、
#   Node.js の配布元が署名した物だけを使う。
#
# 確かめ方:
#   1. 信頼する署名者の鍵の指紋を、ci-tool-fast-update のスキルと同じ一覧
#      (.claude/scripts/ci-tool-signature/trusted-signers.json の node.fingerprints)から読む
#   2. 公開鍵を、nodejs/release-keys のコミットを固定した URL から取る。鍵サーバーが
#      止まっても CI が止まらないようにするため。取った鍵の中身が違っていても、3 で
#      署名した主鍵の指紋を一覧と比べるので、一覧に無い者の署名は通らない
#   3. SHASUMS256.txt.asc を gpg で確かめ、署名した主鍵の指紋が一覧にあることを確かめる
#   4. tarball のハッシュを、署名された範囲の SHASUMS256.txt の値と照らす
#   5. 照らした tarball だけを展開し、その bin を GITHUB_PATH に足す
#   どれかで確かめられなければ、Node.js を PATH に足さずに失敗で終わる。
#
# テスト: .github/scripts/tests/test-install-verified-node.sh
# 使い方: install-verified-node.sh <版>
#   環境変数 NODE_DIST_BASE NODE_KEYS_BASE TRUSTED_SIGNERS_FILE NODE_INSTALL_DIR は、
#   テストで取り先と置き場を差し替えるためのもの
# =====================================================================
set -euo pipefail

fail() {
    echo "::error::Node.js の署名を確かめられませんでした: $1" >&2
    exit 1
}

[ "$#" -eq 1 ] || fail "使い方: install-verified-node.sh <版>"
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "版の形が違います: ${VERSION}"
[ "$(uname -m)" = x86_64 ] || fail "x64 のランナーにだけ対応しています: $(uname -m)"
[ -n "${GITHUB_PATH:-}" ] || fail "GITHUB_PATH がありません。"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SIGNERS="${TRUSTED_SIGNERS_FILE:-$ROOT/.claude/scripts/ci-tool-signature/trusted-signers.json}"
# nodejs/release-keys の 2026-09-01 のコミット。一覧に署名者を足すときは、鍵があるコミットに替える
KEYS_BASE="${NODE_KEYS_BASE:-https://raw.githubusercontent.com/nodejs/release-keys/481637f813e912c4aa3622d7964ab426c97b8e8d/keys}"
DIST="${NODE_DIST_BASE:-https://nodejs.org/dist}/v${VERSION}"
TARBALL="node-v${VERSION}-linux-x64.tar.gz"
DEST="${NODE_INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/verified-node}/v${VERSION}"

WORK=$(mktemp -d)
GNUPGHOME="$WORK/gnupg"
export GNUPGHOME
trap 'gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
mkdir -m 700 "$GNUPGHOME"

get() {
    curl -fsSL --retry 2 --max-time 300 -o "$2" "$1" || fail "取れませんでした: $1"
}

TRUSTED=$(jq -r '.node.fingerprints | if type == "array" and length > 0 then .[] else error("no fingerprints") end' \
    "$SIGNERS" 2>/dev/null) || fail "信頼する署名者の指紋を読めませんでした: ${SIGNERS}"
for fpr in $TRUSTED; do
    [[ "$fpr" =~ ^[0-9A-F]{40}$ ]] || fail "信頼する署名者の指紋を読めませんでした: ${SIGNERS}"
done

for fpr in $TRUSTED; do
    get "${KEYS_BASE}/${fpr}.asc" "$WORK/${fpr}.asc"
    gpg --batch --quiet --import "$WORK/${fpr}.asc" >/dev/null 2>&1 || fail "公開鍵を取り込めませんでした: ${fpr}"
done

# 署名された範囲の文だけを SHASUMS256.txt に書く。範囲の外に足された行は読まない
get "${DIST}/SHASUMS256.txt.asc" "$WORK/SHASUMS256.txt.asc"
gpg --batch --status-file "$WORK/status" --output "$WORK/SHASUMS256.txt" \
    --decrypt "$WORK/SHASUMS256.txt.asc" >/dev/null 2>&1 || fail "SHASUMS256.txt.asc の署名が正しくありません。"
grep -q '^\[GNUPG:\] GOODSIG ' "$WORK/status" ||
    fail "SHASUMS256.txt.asc に、期限内で失効していない鍵の署名がありません。"
SIGNERS_FOUND=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' "$WORK/status")
[ -n "$SIGNERS_FOUND" ] || fail "SHASUMS256.txt.asc の署名した者を読めませんでした。"
for signer in $SIGNERS_FOUND; do
    printf '%s\n' "$TRUSTED" | grep -qx "$signer" || fail "署名した者(${signer})が、信頼する署名者の一覧にありません。"
done

want=$(awk -v n="$TARBALL" '$2 == n && $1 ~ /^[0-9a-f]{64}$/ { print $1; exit }' "$WORK/SHASUMS256.txt")
[ -n "$want" ] || fail "署名された SHASUMS256.txt に、${TARBALL} のハッシュがありません。"
get "${DIST}/${TARBALL}" "$WORK/${TARBALL}"
got=$(sha256sum "$WORK/${TARBALL}" | awk '{ print $1 }')
[ "$got" = "$want" ] || fail "${TARBALL} のハッシュが、署名された SHASUMS256.txt の値と違います。"

mkdir -p "$DEST"
tar -xzf "$WORK/${TARBALL}" -C "$DEST" --strip-components=1 --no-same-owner
[ -x "$DEST/bin/node" ] || fail "${TARBALL} の中に bin/node がありません。"
echo "$DEST/bin" >>"$GITHUB_PATH"
echo "Node.js ${VERSION} を、署名した者 ${SIGNERS_FOUND} の署名で確かめてから入れました。"
