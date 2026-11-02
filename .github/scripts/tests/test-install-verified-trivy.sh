#!/usr/bin/env bash
# =====================================================================
# install-verified-trivy.sh の自動テスト
#
# 偽の配布物を file:// の URL で読ませ、docker を偽物に置き換える。ネットワークも
# GitHub の権限も使わない。本物の cosign は、署名した者の証明書を Sigstore の
# 認証局から受け取る必要があり、手元では署名を作れないためである。
#
# 偽の docker は、cosign verify-blob の代わりに、署名のファイルに書いた
# 「署名した tarball のハッシュ」「署名した者の身元」「発行者」が、渡された tarball と
# --certificate-identity と --certificate-oidc-issuer に合うかを確かめる。
# これで、スクリプトが、展開する tarball そのものを、一覧どおりの身元で
# 確かめているかを確かめる。
#
# 失敗の場合は、終了コードに加えて、標準エラーの理由の文と、GITHUB_PATH に
# 何も足されていないことを確かめる。取りに行けなかったときも終了コードは同じ 1 になり、
# 終了コードだけでは、署名の誤りを見つけたかどうかを区別できないため。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/install-verified-trivy.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
VERSION=1.2.3
TARBALL="trivy_${VERSION}_Linux-64bit.tar.gz"
ISSUER="https://token.actions.githubusercontent.com"
TEMPLATE="https://github.com/aquasecurity/trivy/.github/workflows/reusable-release.yaml@refs/tags/v{version}"
IDENTITY="${TEMPLATE//\{version\}/$VERSION}"

# 偽の docker。cosign verify-blob の引数を読み、署名のファイルの中身と照らす
mkdir -p "$WORK/bin"
cat >"$WORK/bin/docker" <<'EOF'
#!/usr/bin/env bash
if [ -n "${FAKE_DOCKER_RC:-}" ]; then
    echo "fake docker: cannot run" >&2
    exit "$FAKE_DOCKER_RC"
fi
src="" bundle="" issuer="" identity="" blob="" verify=0
while [ "$#" -gt 0 ]; do
    case "$1" in
    -v) src="${2%%:/work:ro}"; shift ;;
    verify-blob) verify=1 ;;
    --bundle) bundle="$2"; shift ;;
    --certificate-oidc-issuer) issuer="$2"; shift ;;
    --certificate-identity) identity="$2"; shift ;;
    *) blob="$1" ;;
    esac
    shift
done
[ "$verify" -eq 1 ] && [ -n "$src" ] || { echo "fake docker: unexpected args" >&2; exit 2; }
b="$src${bundle#/work}"
f="$src${blob#/work}"
[ -f "$b" ] && [ -f "$f" ] || { echo "fake cosign: file not found" >&2; exit 1; }
want_sha=$(sed -n 's/^sha=//p' "$b")
want_identity=$(sed -n 's/^identity=//p' "$b")
want_issuer=$(sed -n 's/^issuer=//p' "$b")
got_sha=$(sha256sum "$f" | awk '{ print $1 }')
[ "$got_sha" = "$want_sha" ] || { echo "fake cosign: invalid signature" >&2; exit 1; }
[ "$identity" = "$want_identity" ] || { echo "fake cosign: none of the expected identities matched" >&2; exit 1; }
[ "$issuer" = "$want_issuer" ] || { echo "fake cosign: issuer mismatch" >&2; exit 1; }
echo "Verified OK" >&2
EOF
chmod +x "$WORK/bin/docker"

# 使い方: build <名前>。偽の配布物を $WORK/<名前> に作り、一覧どおりの身元で署名する
build() {
    local d="$WORK/$1"
    mkdir -p "$d/dist/v${VERSION}" "$d/pkg/contrib"
    printf '#!/bin/sh\necho fake-trivy\n' >"$d/pkg/trivy"
    chmod +x "$d/pkg/trivy"
    echo template >"$d/pkg/contrib/html.tpl"
    tar -czf "$d/dist/v${VERSION}/${TARBALL}" -C "$d/pkg" trivy contrib
    sign "$1" "$IDENTITY" "$ISSUER"
    printf '{"trivy":{"oidc_issuer":"%s","identity_template":"%s"}}\n' "$ISSUER" "$TEMPLATE" >"$d/signers.json"
}

# 使い方: sign <名前> <身元> <発行者>。いまの tarball に、指定の身元で署名し直す
sign() {
    local dir="$WORK/$1/dist/v${VERSION}"
    printf 'sha=%s\nidentity=%s\nissuer=%s\n' "$(sha256sum "$dir/$TARBALL" | awk '{ print $1 }')" "$2" "$3" \
        >"$dir/${TARBALL}.sigstore.json"
}

# 使い方: run <名前> [版]。スクリプトを動かし、終了コードを RC に、標準エラーを $WORK/<名前>/err に置く
run() {
    local d="$WORK/$1"
    : >"$d/github_path"
    PATH="$WORK/bin:$PATH" TRIVY_RELEASE_BASE="file://$d/dist" TRUSTED_SIGNERS_FILE="$d/signers.json" \
        TRIVY_INSTALL_DIR="$d/install" GITHUB_PATH="$d/github_path" \
        bash "$SCRIPT" "${2:-$VERSION}" >/dev/null 2>"$d/err"
    RC=$?
}

ok() { echo "ok   $1"; }
ng() {
    echo "FAIL $1"
    FAILED=1
}

# 使い方: expect_fail <名前> <説明> <理由の文に含まれるはずの文字列>
expect_fail() {
    if [ "$RC" -eq 1 ] && grep -qF -- "$3" "$WORK/$1/err" && [ ! -s "$WORK/$1/github_path" ]; then
        ok "$2"
    else
        ng "$2 (exit=${RC} / 標準エラー: $(cat "$WORK/$1/err"))"
    fi
}

# 1. 一覧どおりの身元の署名で、tarball も署名したときのまま
build good
run good
if [ "$RC" -eq 0 ] && [ "$(cat "$WORK/good/github_path")" = "$WORK/good/install/v${VERSION}" ] &&
    [ "$("$WORK/good/install/v${VERSION}/trivy")" = fake-trivy ] &&
    [ -f "$WORK/good/install/v${VERSION}/contrib/html.tpl" ]; then
    ok "確かめられたら、展開した置き場を GITHUB_PATH に足す"
else
    ng "確かめられたら、展開した置き場を GITHUB_PATH に足す (exit=${RC} / 標準エラー: $(cat "$WORK/good/err"))"
fi

# 2. tarball が、署名したあとに差し替えられた
build swapped
echo extra >>"$WORK/swapped/pkg/trivy"
tar -czf "$WORK/swapped/dist/v${VERSION}/${TARBALL}" -C "$WORK/swapped/pkg" trivy contrib
run swapped
expect_fail swapped "署名したあとに差し替えた tarball は失敗する" "の署名として正しくありません"

# 3. 別のワークフローが署名した(一覧の身元と違う)
build otherworkflow
sign otherworkflow "https://github.com/attacker/trivy/.github/workflows/release.yaml@refs/tags/v${VERSION}" "$ISSUER"
run otherworkflow
expect_fail otherworkflow "一覧と違う身元の署名は失敗する" "の署名として正しくありません"

# 4. 別の版のタグで署名した物を、指定の版として出した
build othertag
sign othertag "${TEMPLATE//\{version\}/1.2.2}" "$ISSUER"
run othertag
expect_fail othertag "別の版のタグの署名は失敗する" "の署名として正しくありません"

# 5. 発行者が違う
build otherissuer
sign otherissuer "$IDENTITY" "https://accounts.example.invalid"
run otherissuer
expect_fail otherissuer "発行者が違う署名は失敗する" "の署名として正しくありません"

# 6. 署名が無い
build unsigned
rm -f "$WORK/unsigned/dist/v${VERSION}/${TARBALL}.sigstore.json"
run unsigned
expect_fail unsigned "署名が無ければ失敗する" "取れませんでした"

# 7. tarball を取れない
build notarball
rm -f "$WORK/notarball/dist/v${VERSION}/${TARBALL}"
run notarball
expect_fail notarball "tarball を取れなければ失敗する" "取れませんでした"

# 8. cosign のコンテナを動かせない
build nodocker
FAKE_DOCKER_RC=125 run nodocker
expect_fail nodocker "cosign を動かせなければ失敗する" "cosign のコンテナを動かせませんでした"

# 9. 署名した tarball に trivy が無い
build nobinary
tar -czf "$WORK/nobinary/dist/v${VERSION}/${TARBALL}" -C "$WORK/nobinary/pkg" contrib
sign nobinary "$IDENTITY" "$ISSUER"
run nobinary
expect_fail nobinary "trivy が無ければ失敗する" "の中に trivy がありません"

# 10. 信頼する署名者の一覧が壊れている
build badlist
echo '{"trivy":{"oidc_issuer":"https://token.actions.githubusercontent.com"}}' >"$WORK/badlist/signers.json"
run badlist
expect_fail badlist "身元の形を読めなければ失敗する" "identity_template を読めませんでした"
build noplaceholder
printf '{"trivy":{"oidc_issuer":"%s","identity_template":"%s"}}\n' "$ISSUER" "$IDENTITY" >"$WORK/noplaceholder/signers.json"
run noplaceholder
expect_fail noplaceholder "身元に版の置き場が無ければ失敗する" "identity_template を読めませんでした"
build badissuer
printf '{"trivy":{"oidc_issuer":"http://insecure.example","identity_template":"%s"}}\n' "$TEMPLATE" >"$WORK/badissuer/signers.json"
run badissuer
expect_fail badissuer "発行者の形が違えば失敗する" "oidc_issuer を読めませんでした"

# 11. 版の形が違う
build badver
run badver "1.2.3;rm"
expect_fail badver "版の形が違えば失敗する" "版の形が違います"
build vprefix
run vprefix "v${VERSION}"
expect_fail vprefix "v を付けた版は失敗する" "版の形が違います"

if [ "$FAILED" -ne 0 ]; then
    echo "install-verified-trivy.sh のテストに失敗しました"
    exit 1
fi
echo "install-verified-trivy.sh のテストはすべて通りました"
