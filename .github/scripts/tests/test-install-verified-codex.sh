#!/usr/bin/env bash
# =====================================================================
# install-verified-codex.sh の自動テスト
#
# 偽の registry(部品の文書、tgz、来歴)を作り、file:// の URL で読ませる。
# gh attestation verify は、スタブが代わりに動く。スタブは、来歴の代わりの JSON に書いた
# tgz の sha512 と、リポジトリと、ワークフローと、タグが、渡された引数と合うときだけ通す。
# ネットワークも GitHub の権限も使わない。
#
# 失敗の場合は、終了コードに加えて、標準エラーの理由の文と、GITHUB_PATH に
# 何も足されていないことを確かめる。理由の文を見るのは、取りに行けなかったことや
# gh が無いことでも終了コードは同じ 1 になり、終了コードだけでは、
# 来歴の誤りを見つけたかどうかを区別できないため。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/install-verified-codex.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
VERSION=1.2.3
REPO=openai/codex
WORKFLOW=openai/codex/.github/workflows/rust-release.yml
REF="refs/tags/rust-v${VERSION}"
TARGET=x86_64-unknown-linux-musl

# --- gh のスタブ -------------------------------------------------------------
# gh attestation verify <tgz> --bundle <来歴> ... の代わりに、来歴の代わりの JSON の test の
# sha512 と repo と workflow と ref が、tgz と引数に合えば test の san を出す。合わなければ失敗する
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2" = "attestation verify" ] || exit 2
file=$3
shift 3
while [ $# -ge 2 ]; do
    case "$1" in
    --bundle) bundle=$2 ;;
    --repo) repo=$2 ;;
    --signer-workflow) workflow=$2 ;;
    --source-ref) ref=$2 ;;
    esac
    shift 2
done
digest=$(sha512sum "$file" | awk '{ print $1 }')
jq -e --arg d "$digest" --arg r "${repo:-}" --arg w "${workflow:-}" --arg s "${ref:-}" \
    '.test.sha512 == $d and .test.repo == $r and .test.workflow == $w and .test.ref == $s' \
    "${bundle:?}" >/dev/null 2>&1 || { echo "Error: verifying with issuer" >&2; exit 1; }
jq -r '.test.san' "$bundle"
STUB
chmod +x "$WORK/bin/gh"

# 使い方: integrity_of <ファイル>。npm の dist.integrity と同じ形(sha512-<base64>)のハッシュを出す
integrity_of() {
    local hex
    hex=$(sha512sum "$1" | awk '{ print $1 }')
    # shellcheck disable=SC2059 # 16進の並びを、printf の \x の形でバイトに戻す
    printf "$(printf '%s' "$hex" | sed 's/../\\x&/g')" | base64 | tr -d '\n' | sed 's/^/sha512-/'
}

# 使い方: publish <名前> <部品の版> <tgz の元の置き場> [来歴を作ったワークフロー] [来歴のタグ]。
#   tgz を詰め、部品の文書と来歴を偽の registry に置く。来歴の URL の %2F は、curl が
#   file:// の URL を開くときに / に戻すので、来歴は attestations/@openai/codex@<版> に置く
publish() {
    local d="$WORK/$1" ver="$2" src="$3" wf="${4:-$WORKFLOW}" ref="${5:-$REF}" reg tgz digest
    reg="$d/reg"
    tgz="$reg/@openai/codex/-/codex-${ver}.tgz"
    mkdir -p "$reg/@openai/codex/-" "$reg/-/npm/v1/attestations/@openai"
    tar -czf "$tgz" -C "$src" package
    digest=$(sha512sum "$tgz" | awk '{ print $1 }')
    printf '{"name":"@openai/codex","version":"%s","dist":{"tarball":"file://%s/@openai/codex/-/codex-%s.tgz","integrity":"%s"}}\n' \
        "$ver" "$reg" "$ver" "$(integrity_of "$tgz")" >"$reg/@openai/codex/${ver}"
    printf '{"attestations":[{"predicateType":"https://github.com/npm/attestation/tree/main/specs/publish/v0.1","bundle":{"test":{}}},{"predicateType":"https://slsa.dev/provenance/v1","bundle":{"test":{"sha512":"%s","repo":"%s","workflow":"%s","ref":"%s","san":"https://github.com/%s@%s"}}}]}\n' \
        "$digest" "$REPO" "$wf" "$ref" "$wf" "$ref" >"$reg/-/npm/v1/attestations/@openai/codex@${ver}"
}

# 使い方: build <名前>。本体と Linux 向けの部品を作って偽の registry に置き、信頼する者の一覧を書く
build() {
    local d="$WORK/$1"
    mkdir -p "$d/main/package/bin" "$d/linux/package/vendor/${TARGET}/bin"
    printf '#!/usr/bin/env node\n' >"$d/main/package/bin/codex.js"
    printf '{"name":"@openai/codex"}\n' >"$d/main/package/package.json"
    printf '#!/bin/sh\necho fake-codex\n' >"$d/linux/package/vendor/${TARGET}/bin/codex"
    chmod +x "$d/linux/package/vendor/${TARGET}/bin/codex"
    printf '{"name":"@openai/codex"}\n' >"$d/linux/package/package.json"
    publish "$1" "$VERSION" "$d/main"
    publish "$1" "${VERSION}-linux-x64" "$d/linux"
    printf '{"codex":{"repo":"%s","signer_workflow":"%s","packages":["@openai/codex@{version}","@openai/codex@{version}-linux-x64"]}}\n' \
        "$REPO" "$WORKFLOW" >"$d/signers.json"
}

# 使い方: run <名前> [版]。スクリプトを動かし、終了コードを RC に、標準エラーを $WORK/<名前>/err に置く
run() {
    local d="$WORK/$1"
    : >"$d/github_path"
    PATH="$WORK/bin:$PATH" NPM_REGISTRY="file://$d/reg" TRUSTED_SIGNERS_FILE="$d/signers.json" \
        CODEX_INSTALL_DIR="$d/install" GITHUB_PATH="$d/github_path" \
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

# 1. 2つの部品の来歴が、信頼するワークフローが版のタグから作った物で、ハッシュも合う
build good
run good
P="$WORK/good/install/${VERSION}"
if [ "$RC" -eq 0 ] && [ "$(cat "$WORK/good/github_path")" = "$P/path" ] &&
    [ "$(cd "$P/path" && readlink codex)" = ../bin/codex.js ] && [ -x "$P/bin/codex.js" ] &&
    [ "$("$P/vendor/${TARGET}/bin/codex")" = fake-codex ]; then
    ok "確かめられたら、本体と実行ファイルを置き、codex の置き場を GITHUB_PATH に足す"
else
    ng "確かめられたら、本体と実行ファイルを置き、codex の置き場を GITHUB_PATH に足す (exit=${RC} / 標準エラー: $(cat "$WORK/good/err"))"
fi

# 2. tgz が、部品の文書を書いたあとに差し替えられた
build swapped
echo extra >>"$WORK/swapped/linux/package/vendor/${TARGET}/bin/codex"
tar -czf "$WORK/swapped/reg/@openai/codex/-/codex-${VERSION}-linux-x64.tgz" -C "$WORK/swapped/linux" package
run swapped
expect_fail swapped "tgz のハッシュが部品の文書の値と違えば失敗する" "@openai/codex@${VERSION}-linux-x64 の tgz のハッシュが、部品の文書の値と違います"

# 3. tgz と部品の文書が差し替えられ、来歴は前の tgz のもののまま
build republished
cp "$WORK/republished/reg/-/npm/v1/attestations/@openai/codex@${VERSION}" "$WORK/republished/att"
echo extra >>"$WORK/republished/main/package/bin/codex.js"
publish republished "$VERSION" "$WORK/republished/main"
cp "$WORK/republished/att" "$WORK/republished/reg/-/npm/v1/attestations/@openai/codex@${VERSION}"
run republished
expect_fail republished "来歴が tgz のものでなければ失敗する" "@openai/codex@${VERSION} の来歴を、${WORKFLOW} が ${REF} から作った物として確かめられませんでした"

# 4. 来歴に署名したのが、信頼する者の一覧に無いワークフロー
build otherworkflow
publish otherworkflow "${VERSION}-linux-x64" "$WORK/otherworkflow/linux" openai/codex/.github/workflows/other.yml
run otherworkflow
expect_fail otherworkflow "一覧に無いワークフローの来歴は失敗する" "@openai/codex@${VERSION}-linux-x64 の来歴を、${WORKFLOW} が ${REF} から作った物として確かめられませんでした"

# 5. 来歴が、別の版のタグから作られた(同じワークフローが作った別の版の tgz への差し替え)
build otherref
publish otherref "$VERSION" "$WORK/otherref/main" "$WORKFLOW" refs/tags/rust-v1.2.2
run otherref
expect_fail otherref "別の版のタグから作られた来歴は失敗する" "gh の出力: Error: verifying with issuer"

# 6. 来歴に SLSA の来歴が無い
build noslsa
echo '{"attestations":[{"predicateType":"https://github.com/npm/attestation/tree/main/specs/publish/v0.1","bundle":{"test":{}}}]}' \
    >"$WORK/noslsa/reg/-/npm/v1/attestations/@openai/codex@${VERSION}"
run noslsa
expect_fail noslsa "SLSA の来歴が無ければ失敗する" "@openai/codex@${VERSION} の来歴に、SLSA の来歴がありません"

# 7. 来歴が無い
build noattestation
rm -f "$WORK/noattestation/reg/-/npm/v1/attestations/@openai/codex@${VERSION}-linux-x64"
run noattestation
expect_fail noattestation "来歴を取れなければ失敗する" "取れませんでした"

# 8. 部品の文書の tgz の URL が registry の外を指す
build outside
jq -c '.dist.tarball = "https://example.invalid/codex.tgz"' "$WORK/outside/reg/@openai/codex/${VERSION}" >"$WORK/outside/doc"
mv "$WORK/outside/doc" "$WORK/outside/reg/@openai/codex/${VERSION}"
run outside
expect_fail outside "tgz の URL が registry の外なら失敗する" "の tgz の URL が、npm の registry ではありません"

# 9. Linux 向けの部品に実行ファイルが無い
build nobinary
mv "$WORK/nobinary/linux/package/vendor/${TARGET}/bin/codex" "$WORK/nobinary/linux/package/vendor/${TARGET}/bin/other"
publish nobinary "${VERSION}-linux-x64" "$WORK/nobinary/linux"
run nobinary
expect_fail nobinary "実行ファイルが無ければ失敗する" "の Codex CLI の実行ファイルがありません"

# 10. 信頼する署名者の一覧が壊れている
build badlist
echo '{"codex":{"repo":"openai/codex","signer_workflow":"openai/codex/.github/workflows/rust-release.yml","packages":[]}}' \
    >"$WORK/badlist/signers.json"
run badlist
expect_fail badlist "部品の一覧が空なら失敗する" "codex の packages を読めませんでした"
build badrepo
printf '{"codex":{"repo":"openai/codex x","signer_workflow":"%s","packages":["@openai/codex@{version}"]}}\n' "$WORKFLOW" \
    >"$WORK/badrepo/signers.json"
run badrepo
expect_fail badrepo "リポジトリの形が違えば失敗する" "codex の repo を読めませんでした"

# 11. 版の形が違う
build badver
run badver "1.2.3;rm"
expect_fail badver "版の形が違えば失敗する" "版の形が違います"

if [ "$FAILED" -ne 0 ]; then
    echo "install-verified-codex.sh のテストに失敗しました"
    exit 1
fi
echo "install-verified-codex.sh のテストはすべて通りました"
