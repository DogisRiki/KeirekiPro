#!/usr/bin/env bash
# =====================================================================
# install-verified-node.sh の自動テスト
#
# 使い捨ての鍵を2つ作り、本物の gpg で SHASUMS256.txt に署名した偽の配布物を、
# file:// の URL で読ませる。ネットワークも GitHub の権限も使わない。
#
# 失敗の場合は、終了コードに加えて、標準エラーの理由の文と、GITHUB_PATH に
# 何も足されていないことを確かめる。理由の文を見るのは、取りに行けなかったことや
# gpg が無いことでも終了コードは同じ 1 になり、終了コードだけでは、
# 署名の誤りを見つけたかどうかを区別できないため。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/install-verified-node.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
export GNUPGHOME="$WORK/signer-gnupg"
trap 'gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
mkdir -m 700 "$GNUPGHOME"
FAILED=0
VERSION=1.2.3
TARBALL="node-v${VERSION}-linux-x64.tar.gz"

new_key() {
    gpg --batch --quiet --passphrase '' --quick-gen-key "$1 <$1@example.invalid>" ed25519 sign never 2>/dev/null
    gpg --batch --with-colons --list-keys "$1@example.invalid" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'
}
TRUSTED_FPR=$(new_key trusted)
OTHER_FPR=$(new_key other)
[ -n "$TRUSTED_FPR" ] && [ -n "$OTHER_FPR" ] || { echo "FAIL テスト用の鍵を作れませんでした"; exit 1; }

# 使い方: build <名前>。偽の配布物と鍵の置き場を $WORK/<名前> に作り、信頼する鍵で署名する
build() {
    local d="$WORK/$1"
    mkdir -p "$d/dist/v${VERSION}" "$d/keys" "$d/pkg/node-v${VERSION}-linux-x64/bin"
    printf '#!/bin/sh\necho fake-node\n' >"$d/pkg/node-v${VERSION}-linux-x64/bin/node"
    chmod +x "$d/pkg/node-v${VERSION}-linux-x64/bin/node"
    tar -czf "$d/dist/v${VERSION}/${TARBALL}" -C "$d/pkg" "node-v${VERSION}-linux-x64"
    (cd "$d/dist/v${VERSION}" && sha256sum "$TARBALL" >SHASUMS256.txt)
    sign "$1" "$TRUSTED_FPR"
    gpg --batch --armor --export "$TRUSTED_FPR" >"$d/keys/${TRUSTED_FPR}.asc"
    printf '{"node":{"fingerprints":["%s"]}}\n' "$TRUSTED_FPR" >"$d/signers.json"
}

# 使い方: sign <名前> <鍵の指紋>。SHASUMS256.txt に、指定の鍵で署名し直す
sign() {
    gpg --batch --yes --local-user "$2" --clearsign \
        --output "$WORK/$1/dist/v${VERSION}/SHASUMS256.txt.asc" "$WORK/$1/dist/v${VERSION}/SHASUMS256.txt" 2>/dev/null
}

# 使い方: run <名前> [版]。スクリプトを動かし、終了コードを RC に、標準エラーを $WORK/<名前>/err に置く
run() {
    local d="$WORK/$1"
    : >"$d/github_path"
    (
        unset GNUPGHOME
        NODE_DIST_BASE="file://$d/dist" NODE_KEYS_BASE="file://$d/keys" TRUSTED_SIGNERS_FILE="$d/signers.json" \
            NODE_INSTALL_DIR="$d/install" GITHUB_PATH="$d/github_path" \
            bash "$SCRIPT" "${2:-$VERSION}" >/dev/null 2>"$d/err"
    )
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

# 1. 信頼する鍵の署名で、ハッシュも合う
build good
run good
if [ "$RC" -eq 0 ] && [ "$(cat "$WORK/good/github_path")" = "$WORK/good/install/v${VERSION}/bin" ] &&
    [ "$("$WORK/good/install/v${VERSION}/bin/node")" = fake-node ]; then
    ok "確かめられたら、展開した bin を GITHUB_PATH に足す"
else
    ng "確かめられたら、展開した bin を GITHUB_PATH に足す (exit=${RC} / 標準エラー: $(cat "$WORK/good/err"))"
fi

# 2. tarball が、署名したあとに差し替えられた
build swapped
echo extra >>"$WORK/swapped/pkg/node-v${VERSION}-linux-x64/bin/node"
tar -czf "$WORK/swapped/dist/v${VERSION}/${TARBALL}" -C "$WORK/swapped/pkg" "node-v${VERSION}-linux-x64"
run swapped
expect_fail swapped "tarball のハッシュが署名された値と違えば失敗する" "のハッシュが、署名された SHASUMS256.txt の値と違います"

# 3. SHASUMS256.txt.asc の署名した範囲の中身が書き換えられた
build tampered
sed -i "s/^[0-9a-f]\{8\}/00000000/" "$WORK/tampered/dist/v${VERSION}/SHASUMS256.txt.asc"
run tampered
expect_fail tampered "署名した範囲が書き換えられたら失敗する" "SHASUMS256.txt.asc の署名が正しくありません"

# 4. 鍵の置き場の鍵が、一覧に無い者の鍵に差し替えられ、その者が署名した
build otherkey
sign otherkey "$OTHER_FPR"
gpg --batch --armor --export "$OTHER_FPR" >"$WORK/otherkey/keys/${TRUSTED_FPR}.asc"
run otherkey
expect_fail otherkey "一覧に無い者の署名は失敗する" "が、信頼する署名者の一覧にありません"

# 5. 一覧に無い者が署名し、その者の鍵は取り込まれない
build unknownsigner
sign unknownsigner "$OTHER_FPR"
run unknownsigner
expect_fail unknownsigner "取り込んでいない鍵の署名は失敗する" "SHASUMS256.txt.asc の署名が正しくありません"

# 6. SHASUMS256.txt.asc に署名が無い
build unsigned
cp "$WORK/unsigned/dist/v${VERSION}/SHASUMS256.txt" "$WORK/unsigned/dist/v${VERSION}/SHASUMS256.txt.asc"
run unsigned
expect_fail unsigned "署名が無ければ失敗する" "SHASUMS256.txt.asc の署名が正しくありません"

# 7. 署名した範囲の外に、偽の tarball のハッシュが足された
build outside
echo extra >>"$WORK/outside/pkg/node-v${VERSION}-linux-x64/bin/node"
tar -czf "$WORK/outside/dist/v${VERSION}/${TARBALL}" -C "$WORK/outside/pkg" "node-v${VERSION}-linux-x64"
(cd "$WORK/outside/dist/v${VERSION}" && sha256sum "$TARBALL") >>"$WORK/outside/dist/v${VERSION}/SHASUMS256.txt.asc"
run outside
expect_fail outside "署名した範囲の外の行は使わない" "のハッシュが、署名された SHASUMS256.txt の値と違います"

# 8. 署名された SHASUMS256.txt に tarball の行が無い
build noline
echo "0000000000000000000000000000000000000000000000000000000000000000  other.tar.gz" >"$WORK/noline/dist/v${VERSION}/SHASUMS256.txt"
sign noline "$TRUSTED_FPR"
run noline
expect_fail noline "tarball の行が無ければ失敗する" "のハッシュがありません"

# 9. 公開鍵を取れない
build nokey
rm -f "$WORK/nokey/keys/${TRUSTED_FPR}.asc"
run nokey
expect_fail nokey "公開鍵を取れなければ失敗する" "取れませんでした"

# 10. 信頼する署名者の一覧が壊れている
build badlist
echo '{"node":{"fingerprints":[]}}' >"$WORK/badlist/signers.json"
run badlist
expect_fail badlist "信頼する署名者の一覧を読めなければ失敗する" "信頼する署名者の指紋を読めませんでした"
build badfpr
printf '{"node":{"fingerprints":["%s","../x"]}}\n' "$TRUSTED_FPR" >"$WORK/badfpr/signers.json"
run badfpr
expect_fail badfpr "指紋の形が違えば失敗する" "信頼する署名者の指紋を読めませんでした"

# 11. 版の形が違う
build badver
run badver "1.2.3;rm"
expect_fail badver "版の形が違えば失敗する" "版の形が違います"

if [ "$FAILED" -ne 0 ]; then
    echo "install-verified-node.sh のテストに失敗しました"
    exit 1
fi
echo "install-verified-node.sh のテストはすべて通りました"
