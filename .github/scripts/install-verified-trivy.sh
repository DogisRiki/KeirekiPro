#!/usr/bin/env bash
# =====================================================================
# Trivy を GitHub のリリースから取り、配布元の署名を確かめてから PATH に足す
# (.github/actions/verified-trivy から呼ぶ)
#
# なぜ要るのか:
#   aquasecurity/setup-trivy は、配布物のハッシュを同じリリースの checksums.txt と照らすだけで、
#   配布元の署名を確かめない。2026-03-19 の Trivy の事件(GHSA-69fq-xp46-6x23)のように
#   リリースそのものが偽物だと、照らしても通る。container-scan は本番に出すイメージの合否を
#   決め、定期の検査は AWS のロールを扱うので、配布元のリリースのワークフローが署名した物だけを使う。
#
# 確かめ方:
#   1. 信頼する署名者を、ci-tool-fast-update のスキルと同じ一覧
#      (.claude/scripts/ci-tool-signature/trusted-signers.json の trivy)から読む。
#      身元は identity_template の {version} に版を入れたもの。指定した版のタグで、
#      aquasecurity/trivy のリリースのワークフローが署名した物だけが通る
#   2. ランナーの CPU に合う trivy_<版>_Linux-64bit.tar.gz か trivy_<版>_Linux-ARM64.tar.gz と、
#      同じ名前に .sigstore.json を足した署名を取る。container-scan はイメージを arm64 の
#      ランナーで検査し、ほかのジョブは x64 のランナーで動くため、両方に対応する
#   3. cosign verify-blob で、2 の tarball の署名を確かめる。cosign は、verify-ci-tool.sh と
#      同じ digest で固定したコンテナのイメージで動かす
#   4. 確かめた tarball だけを展開し、その置き場を GITHUB_PATH に足す
#   どれかで確かめられなければ、Trivy を PATH に足さずに失敗で終わる。
#
# テスト: .github/scripts/tests/test-install-verified-trivy.sh
# 使い方: install-verified-trivy.sh <版>(v を付けない。例: 0.74.0)
#   環境変数 TRIVY_RELEASE_BASE TRUSTED_SIGNERS_FILE TRIVY_INSTALL_DIR は、
#   テストで取り先と置き場を差し替えるためのもの
# =====================================================================
set -euo pipefail

# .claude/scripts/ci-tool-signature/verify-ci-tool.sh の COSIGN_IMAGE と同じもの。替えるときは両方を替える
COSIGN_IMAGE="ghcr.io/sigstore/cosign/cosign@sha256:0f06154836d2de34f887a5c273506d52ca43edaa1d9e53e6510fa78a48f69c2d"

fail() {
    echo "::error::Trivy の署名を確かめられませんでした: $1" >&2
    exit 1
}

[ "$#" -eq 1 ] || fail "使い方: install-verified-trivy.sh <版>"
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "版の形が違います: ${VERSION}"
MACHINE="$(uname -m)"
case "$MACHINE" in
x86_64) ARCH=64bit ;;
aarch64 | arm64) ARCH=ARM64 ;;
*) fail "x64 と arm64 のランナーにだけ対応しています: ${MACHINE}" ;;
esac
[ -n "${GITHUB_PATH:-}" ] || fail "GITHUB_PATH がありません。"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SIGNERS="${TRUSTED_SIGNERS_FILE:-$ROOT/.claude/scripts/ci-tool-signature/trusted-signers.json}"
BASE="${TRIVY_RELEASE_BASE:-https://github.com/aquasecurity/trivy/releases/download}/v${VERSION}"
TARBALL="trivy_${VERSION}_Linux-${ARCH}.tar.gz"
DEST="${TRIVY_INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/verified-trivy}/v${VERSION}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

get() {
    curl -fsSL --retry 2 --max-time 300 -o "$2" "$1" || fail "取れませんでした: $1"
}

# 使い方: read_signer <欄の名前> <値の形>。trusted-signers.json の trivy の欄を、形を確かめてから読む
read_signer() {
    local value
    value=$(jq -r --arg k "$1" '.trivy[$k] | if type == "string" then . else error("not a string") end' \
        "$SIGNERS" 2>/dev/null) || fail "信頼する署名者の trivy の ${1} を読めませんでした: ${SIGNERS}"
    [[ "$value" =~ $2 ]] || fail "信頼する署名者の trivy の ${1} を読めませんでした: ${SIGNERS}"
    printf '%s' "$value"
}
ISSUER=$(read_signer oidc_issuer '^https://[!-~]+$')
TEMPLATE=$(read_signer identity_template '^https://[!-~]*\{version\}[!-~]*$')
IDENTITY="${TEMPLATE//\{version\}/$VERSION}"

get "${BASE}/${TARBALL}.sigstore.json" "$WORK/${TARBALL}.sigstore.json"
get "${BASE}/${TARBALL}" "$WORK/${TARBALL}"

rc=0
docker run --rm -v "$WORK:/work:ro" "$COSIGN_IMAGE" verify-blob \
    --bundle "/work/${TARBALL}.sigstore.json" \
    --certificate-oidc-issuer "$ISSUER" \
    --certificate-identity "$IDENTITY" \
    "/work/${TARBALL}" >/dev/null 2>"$WORK/cosign.err" || rc=$?
case "$rc" in
0) ;;
125 | 126 | 127) fail "cosign のコンテナを動かせませんでした: $(head -c 500 "$WORK/cosign.err")" ;;
*) fail "${TARBALL} の署名が、${IDENTITY} の署名として正しくありません: $(head -c 500 "$WORK/cosign.err")" ;;
esac

mkdir -p "$DEST"
tar -xzf "$WORK/${TARBALL}" -C "$DEST" --no-same-owner
[ -f "$DEST/trivy" ] && [ -x "$DEST/trivy" ] || fail "${TARBALL} の中に trivy がありません。"
echo "$DEST" >>"$GITHUB_PATH"
echo "Trivy ${VERSION} を、署名した者 ${IDENTITY} の署名で確かめてから入れました。"
