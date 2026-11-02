#!/usr/bin/env bash
# =====================================================================
# install-verified-terraform.sh の自動テスト
#
# 使い捨ての鍵を2つ作り、本物の gpg で SHA256SUMS に署名した偽の配布物を、
# file:// の URL で読ませる。ネットワークも GitHub の権限も使わない。
#
# 失敗の場合は、終了コードに加えて、標準エラーの理由の文と、GITHUB_PATH に
# 何も足されていないことを確かめる。理由の文を見るのは、取りに行けなかったことや
# gpg が無いことでも終了コードは同じ 1 になり、終了コードだけでは、
# 署名の誤りを見つけたかどうかを区別できないため。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/install-verified-terraform.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
export GNUPGHOME="$WORK/signer-gnupg"
trap 'gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
mkdir -m 700 "$GNUPGHOME"
FAILED=0
VERSION=1.2.3
SUMS="terraform_${VERSION}_SHA256SUMS"
ZIP="terraform_${VERSION}_linux_amd64.zip"

new_key() {
    gpg --batch --quiet --passphrase '' --quick-gen-key "$1 <$1@example.invalid>" ed25519 sign never 2>/dev/null
    gpg --batch --with-colons --list-keys "$1@example.invalid" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'
}
TRUSTED_FPR=$(new_key trusted)
OTHER_FPR=$(new_key other)
[ -n "$TRUSTED_FPR" ] && [ -n "$OTHER_FPR" ] || { echo "FAIL テスト用の鍵を作れませんでした"; exit 1; }

# 使い方: pack <名前>。$WORK/<名前>/pkg の中身を zip に詰め直し、配布物の置き場に置く
pack() {
    rm -f "$WORK/$1/dist/${VERSION}/${ZIP}"
    (cd "$WORK/$1/pkg" && zip -q -r "$WORK/$1/dist/${VERSION}/${ZIP}" .)
}

# 使い方: build <名前>。偽の配布物と鍵を $WORK/<名前> に作り、信頼する鍵で署名する
build() {
    local d="$WORK/$1"
    mkdir -p "$d/dist/${VERSION}" "$d/pkg"
    printf '#!/bin/sh\necho fake-terraform\n' >"$d/pkg/terraform"
    chmod +x "$d/pkg/terraform"
    pack "$1"
    (cd "$d/dist/${VERSION}" && sha256sum "$ZIP" >"$SUMS")
    sign "$1" "$TRUSTED_FPR"
    gpg --batch --armor --export "$TRUSTED_FPR" >"$d/key.asc"
    printf '{"terraform":{"fingerprints":["%s"]}}\n' "$TRUSTED_FPR" >"$d/signers.json"
}

# 使い方: sign <名前> <鍵の指紋>。SHA256SUMS に、指定の鍵で署名し直す
sign() {
    gpg --batch --yes --local-user "$2" --detach-sign \
        --output "$WORK/$1/dist/${VERSION}/${SUMS}.sig" "$WORK/$1/dist/${VERSION}/${SUMS}" 2>/dev/null
}

# 使い方: run <名前> [版]。スクリプトを動かし、終了コードを RC に、標準エラーを $WORK/<名前>/err に置く
run() {
    local d="$WORK/$1"
    : >"$d/github_path"
    (
        unset GNUPGHOME
        TERRAFORM_DIST_BASE="file://$d/dist" TERRAFORM_KEY_URL="file://$d/key.asc" TRUSTED_SIGNERS_FILE="$d/signers.json" \
            TERRAFORM_INSTALL_DIR="$d/install" GITHUB_PATH="$d/github_path" \
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
if [ "$RC" -eq 0 ] && [ "$(cat "$WORK/good/github_path")" = "$WORK/good/install/${VERSION}" ] &&
    [ "$("$WORK/good/install/${VERSION}/terraform")" = fake-terraform ]; then
    ok "確かめられたら、展開した置き場を GITHUB_PATH に足す"
else
    ng "確かめられたら、展開した置き場を GITHUB_PATH に足す (exit=${RC} / 標準エラー: $(cat "$WORK/good/err"))"
fi

# 2. zip が、署名したあとに差し替えられた
build swapped
echo extra >>"$WORK/swapped/pkg/terraform"
pack swapped
run swapped
expect_fail swapped "zip のハッシュが署名された値と違えば失敗する" "のハッシュが、署名された ${SUMS} の値と違います"

# 3. 署名したあとに SHA256SUMS が書き換えられた
build tampered
echo extra >>"$WORK/tampered/pkg/terraform"
pack tampered
(cd "$WORK/tampered/dist/${VERSION}" && sha256sum "$ZIP" >"$SUMS")
run tampered
expect_fail tampered "署名したあとに SHA256SUMS が書き換えられたら失敗する" "${SUMS} の署名が正しくありません"

# 4. 公開鍵の置き場の鍵が、一覧に無い者の鍵に差し替えられ、その者が署名した
build otherkey
sign otherkey "$OTHER_FPR"
gpg --batch --armor --export "$OTHER_FPR" >"$WORK/otherkey/key.asc"
run otherkey
expect_fail otherkey "一覧に無い者の署名は失敗する" "が、信頼する署名者の一覧にありません"

# 5. 一覧に無い者が署名し、その者の鍵は取り込まれない
build unknownsigner
sign unknownsigner "$OTHER_FPR"
run unknownsigner
expect_fail unknownsigner "取り込んでいない鍵の署名は失敗する" "${SUMS} の署名が正しくありません"

# 6. 署名が無い
build unsigned
rm -f "$WORK/unsigned/dist/${VERSION}/${SUMS}.sig"
run unsigned
expect_fail unsigned "署名が無ければ失敗する" "取れませんでした"

# 7. 署名された SHA256SUMS に zip の行が無い
build noline
echo "0000000000000000000000000000000000000000000000000000000000000000  other.zip" >"$WORK/noline/dist/${VERSION}/${SUMS}"
sign noline "$TRUSTED_FPR"
run noline
expect_fail noline "zip の行が無ければ失敗する" "のハッシュがありません"

# 8. zip の中に terraform が無い
build nobinary
mv "$WORK/nobinary/pkg/terraform" "$WORK/nobinary/pkg/other"
pack nobinary
(cd "$WORK/nobinary/dist/${VERSION}" && sha256sum "$ZIP" >"$SUMS")
sign nobinary "$TRUSTED_FPR"
run nobinary
expect_fail nobinary "zip の中に terraform が無ければ失敗する" "の中に terraform がありません"

# 9. 公開鍵を取れない
build nokey
rm -f "$WORK/nokey/key.asc"
run nokey
expect_fail nokey "公開鍵を取れなければ失敗する" "取れませんでした"

# 10. 信頼する署名者の一覧が壊れている
build badlist
echo '{"terraform":{"fingerprints":[]}}' >"$WORK/badlist/signers.json"
run badlist
expect_fail badlist "信頼する署名者の一覧を読めなければ失敗する" "信頼する署名者の指紋を読めませんでした"
build badfpr
printf '{"terraform":{"fingerprints":["%s","../x"]}}\n' "$TRUSTED_FPR" >"$WORK/badfpr/signers.json"
run badfpr
expect_fail badfpr "指紋の形が違えば失敗する" "信頼する署名者の指紋を読めませんでした"

# 11. 版の形が違う
build badver
run badver "1.2.3;rm"
expect_fail badver "版の形が違えば失敗する" "版の形が違います"

if [ "$FAILED" -ne 0 ]; then
    echo "install-verified-terraform.sh のテストに失敗しました"
    exit 1
fi
echo "install-verified-terraform.sh のテストはすべて通りました"
