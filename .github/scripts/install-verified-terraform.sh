#!/usr/bin/env bash
# =====================================================================
# Terraform を releases.hashicorp.com から取り、配布元の署名を確かめてから PATH に足す
# (.github/actions/verified-terraform から呼ぶ)
#
# なぜ要るのか:
#   hashicorp/setup-terraform は zip を取るだけで、配布元の署名を確かめない。
#   terraform-apply.yaml は本番の AWS の権限と本番の秘密を扱うので、Terraform の配布元が
#   署名した物だけを使う。
#
# 確かめ方:
#   1. 信頼する署名者の鍵の指紋を、ci-tool-fast-update のスキルと同じ一覧
#      (.claude/scripts/ci-tool-signature/trusted-signers.json の terraform.fingerprints)から読む
#   2. 公開鍵を、HashiCorp が公開している場所(https://www.hashicorp.com/security)から取る。
#      HashiCorp は鍵の期限を延ばすたびにこの場所の鍵を差し替えるので、リポジトリに写しを
#      置かない。取った鍵の中身が違っていても、3 で署名した主鍵の指紋を一覧と比べるので、
#      一覧に無い者の署名は通らない
#   3. terraform_<版>_SHA256SUMS の署名(.sig)を gpg で確かめ、署名した主鍵の指紋が一覧に
#      あることを確かめる
#   4. zip のハッシュを、署名された SHA256SUMS の値と照らす
#   5. 照らした zip から terraform だけを展開し、その置き場を GITHUB_PATH に足す
#   どれかで確かめられなければ、Terraform を PATH に足さずに失敗で終わる。
#
# テスト: .github/scripts/tests/test-install-verified-terraform.sh
# 使い方: install-verified-terraform.sh <版>
#   環境変数 TERRAFORM_DIST_BASE TERRAFORM_KEY_URL TRUSTED_SIGNERS_FILE TERRAFORM_INSTALL_DIR は、
#   テストで取り先と置き場を差し替えるためのもの
# =====================================================================
set -euo pipefail

fail() {
    echo "::error::Terraform の署名を確かめられませんでした: $1" >&2
    exit 1
}

[ "$#" -eq 1 ] || fail "使い方: install-verified-terraform.sh <版>"
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "版の形が違います: ${VERSION}"
[ "$(uname -m)" = x86_64 ] || fail "x64 のランナーにだけ対応しています: $(uname -m)"
[ -n "${GITHUB_PATH:-}" ] || fail "GITHUB_PATH がありません。"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SIGNERS="${TRUSTED_SIGNERS_FILE:-$ROOT/.claude/scripts/ci-tool-signature/trusted-signers.json}"
KEY_URL="${TERRAFORM_KEY_URL:-https://www.hashicorp.com/.well-known/pgp-key.txt}"
DIST="${TERRAFORM_DIST_BASE:-https://releases.hashicorp.com/terraform}/${VERSION}"
SUMS="terraform_${VERSION}_SHA256SUMS"
ZIP="terraform_${VERSION}_linux_amd64.zip"
DEST="${TERRAFORM_INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/verified-terraform}/${VERSION}"

WORK=$(mktemp -d)
GNUPGHOME="$WORK/gnupg"
export GNUPGHOME
trap 'gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
mkdir -m 700 "$GNUPGHOME"

get() {
    curl -fsSL --retry 2 --max-time 300 -o "$2" "$1" || fail "取れませんでした: $1"
}

TRUSTED=$(jq -r '.terraform.fingerprints | if type == "array" and length > 0 then .[] else error("no fingerprints") end' \
    "$SIGNERS" 2>/dev/null) || fail "信頼する署名者の指紋を読めませんでした: ${SIGNERS}"
for fpr in $TRUSTED; do
    [[ "$fpr" =~ ^[0-9A-F]{40}$ ]] || fail "信頼する署名者の指紋を読めませんでした: ${SIGNERS}"
done

get "$KEY_URL" "$WORK/key.asc"
gpg --batch --quiet --import "$WORK/key.asc" >/dev/null 2>&1 || fail "公開鍵を取り込めませんでした: ${KEY_URL}"

get "${DIST}/${SUMS}" "$WORK/SHA256SUMS"
get "${DIST}/${SUMS}.sig" "$WORK/SHA256SUMS.sig"
gpg --batch --status-file "$WORK/status" --verify "$WORK/SHA256SUMS.sig" "$WORK/SHA256SUMS" >/dev/null 2>&1 ||
    fail "${SUMS} の署名が正しくありません。"
grep -q '^\[GNUPG:\] GOODSIG ' "$WORK/status" ||
    fail "${SUMS} に、期限内で失効していない鍵の署名がありません。"
SIGNERS_FOUND=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' "$WORK/status")
[ -n "$SIGNERS_FOUND" ] || fail "${SUMS} の署名した者を読めませんでした。"
for signer in $SIGNERS_FOUND; do
    printf '%s\n' "$TRUSTED" | grep -qx "$signer" || fail "署名した者(${signer})が、信頼する署名者の一覧にありません。"
done

want=$(awk -v n="$ZIP" '$2 == n && $1 ~ /^[0-9a-f]{64}$/ { print $1; exit }' "$WORK/SHA256SUMS")
[ -n "$want" ] || fail "署名された ${SUMS} に、${ZIP} のハッシュがありません。"
get "${DIST}/${ZIP}" "$WORK/${ZIP}"
got=$(sha256sum "$WORK/${ZIP}" | awk '{ print $1 }')
[ "$got" = "$want" ] || fail "${ZIP} のハッシュが、署名された ${SUMS} の値と違います。"

mkdir -p "$DEST"
unzip -q -o "$WORK/${ZIP}" terraform -d "$DEST" >/dev/null 2>&1 || fail "${ZIP} の中に terraform がありません。"
[ -x "$DEST/terraform" ] || fail "${ZIP} の中の terraform を動かせません。"
echo "$DEST" >>"$GITHUB_PATH"
echo "Terraform ${VERSION} を、署名した者 ${SIGNERS_FOUND} の署名で確かめてから入れました。"
