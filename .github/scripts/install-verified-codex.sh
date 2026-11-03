#!/usr/bin/env bash
# =====================================================================
# Codex CLI を npm の registry から取り、配布元の来歴を確かめてから PATH に足す
# (.github/actions/verified-codex から呼ぶ)
#
# なぜ要るのか:
#   npm install -g は、registry が返した tgz をそのまま入れ、配布元が作った物かを確かめない。
#   codex-review は秘密の値(OPENAI_API_KEY)を扱うので、Codex CLI の配布元のリリースの
#   ワークフローが作った物だけを使う。
#
# 確かめ方:
#   1. 配布元のリポジトリと、来歴に署名したワークフローと、入れる部品を、ci-tool-fast-update の
#      スキルと同じ一覧(.claude/scripts/ci-tool-signature/trusted-signers.json の codex)から読む
#   2. 部品ごとに、registry の部品の文書から tgz の URL とハッシュ(dist.integrity)を読み、
#      tgz と SLSA の来歴を取る
#   3. tgz のハッシュを、部品の文書の値と照らす
#   4. gh attestation verify で、来歴が tgz のものであることと、来歴に署名したのが 1 の
#      リポジトリとワークフローで、版のタグ(refs/tags/rust-v<版>)から作られたことを確かめる。
#      タグまで確かめるのは、同じワークフローが作った別の版の tgz に差し替えられても通さないため
#   5. 確かめた tgz だけを展開する。1つ目の部品を本体として置き、ほかの部品の vendor
#      (Codex CLI の実行ファイル)を本体の vendor に置く。本体の bin/codex.js は、
#      Linux 向けの部品が node_modules に無いとき、本体の vendor から実行ファイルを探す
#   6. bin/codex.js を指す codex を置いた場所を GITHUB_PATH に足す
#   どれかで確かめられなければ、Codex CLI を PATH に足さずに失敗で終わる。
#
# なぜ npm install を使わないのか:
#   本体の部品は、Linux 向けの部品を optionalDependencies に持つ。npm install は、その部品を
#   registry から取り直し、来歴を確かめずに入れるため。展開だけで入れるので、部品の
#   install のスクリプトも動かない。
#
# テスト: .github/scripts/tests/test-install-verified-codex.sh
# 使い方: install-verified-codex.sh <版>
#   環境変数 NPM_REGISTRY TRUSTED_SIGNERS_FILE CODEX_INSTALL_DIR は、
#   テストで取り先と置き場を差し替えるためのもの
# =====================================================================
set -euo pipefail

fail() {
    echo "::error::Codex CLI の来歴を確かめられませんでした: $1" >&2
    exit 1
}

[ "$#" -eq 1 ] || fail "使い方: install-verified-codex.sh <版>"
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "版の形が違います: ${VERSION}"
[ "$(uname -m)" = x86_64 ] || fail "x64 のランナーにだけ対応しています: $(uname -m)"
[ -n "${GITHUB_PATH:-}" ] || fail "GITHUB_PATH がありません。"
command -v gh >/dev/null 2>&1 || fail "gh がありません。"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SIGNERS="${TRUSTED_SIGNERS_FILE:-$ROOT/.claude/scripts/ci-tool-signature/trusted-signers.json}"
REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org}"
DEST="${CODEX_INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/verified-codex}/${VERSION}"
# openai/codex は、版ごとに rust-v<版> のタグからリリースのワークフローを動かす
SOURCE_REF="refs/tags/rust-v${VERSION}"
TARGET=x86_64-unknown-linux-musl

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

get() {
    curl -fsSL --retry 2 --max-time 300 -o "$2" "$1" || fail "取れませんでした: $1"
}

# 使い方: read_signers <欄> <形>。trusted-signers.json の codex の欄を1行に1つずつ出す
read_signers() {
    local out
    out=$(jq -r --arg k "$1" '.codex[$k] | if type == "string" then . elif type == "array" and length > 0 then .[] else error("empty") end' \
        "$SIGNERS" 2>/dev/null) || return 1
    printf '%s\n' "$out" | grep -qvE "$2" && return 1
    printf '%s\n' "$out"
}
REPO=$(read_signers repo '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') ||
    fail "信頼する署名者の一覧から、codex の repo を読めませんでした: ${SIGNERS}"
WORKFLOW=$(read_signers signer_workflow '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/[!-~]+$') ||
    fail "信頼する署名者の一覧から、codex の signer_workflow を読めませんでした: ${SIGNERS}"
PACKAGES=$(read_signers packages '^(@[a-z0-9._-]+/)?[a-z0-9._-]+@[!-~]*\{version\}[!-~]*$') ||
    fail "信頼する署名者の一覧から、codex の packages を読めませんでした: ${SIGNERS}"
[ "$(printf '%s\n' "$REPO" | wc -l)" -eq 1 ] && [ "$(printf '%s\n' "$WORKFLOW" | wc -l)" -eq 1 ] ||
    fail "信頼する署名者の一覧の codex の repo と signer_workflow は、1つずつにしてください: ${SIGNERS}"

n=0
SIGNER=""
for pkg in $PACKAGES; do
    pkg="${pkg//\{version\}/$VERSION}"
    name="${pkg%@*}"
    ver="${pkg##*@}"
    n=$((n + 1))

    get "${REGISTRY}/${name}/${ver}" "$WORK/${n}.json"
    tarball=$(jq -r '.dist.tarball | strings' "$WORK/${n}.json" 2>/dev/null) || tarball=""
    integrity=$(jq -r '.dist.integrity | strings' "$WORK/${n}.json" 2>/dev/null) || integrity=""
    case "$tarball" in "${REGISTRY}/"*) ;; *) fail "${pkg} の tgz の URL が、npm の registry ではありません: ${tarball}" ;; esac
    [[ "$integrity" =~ ^sha512-[A-Za-z0-9+/]+=*$ ]] || fail "${pkg} の部品の文書から、tgz の sha512 のハッシュを読めませんでした。"

    # 新しい curl は %2f を %2F に書き換えて送るので、はじめから %2F で書く
    get "${REGISTRY}/-/npm/v1/attestations/${name/\//%2F}@${ver}" "$WORK/${n}-attestations.json"
    jq -c 'first(.attestations[]? | select(.predicateType == "https://slsa.dev/provenance/v1") | .bundle | objects) // empty' \
        "$WORK/${n}-attestations.json" >"$WORK/${n}.bundle.json" 2>/dev/null || true
    [ -s "$WORK/${n}.bundle.json" ] || fail "${pkg} の来歴に、SLSA の来歴がありません。"

    get "$tarball" "$WORK/${n}.tgz"
    want=$(printf '%s' "${integrity#sha512-}" | base64 -d 2>/dev/null | od -An -v -tx1 | tr -d ' \n')
    got=$(sha512sum "$WORK/${n}.tgz" | awk '{ print $1 }')
    [ -n "$want" ] && [ "$got" = "$want" ] || fail "${pkg} の tgz のハッシュが、部品の文書の値と違います。"

    if ! san=$(gh attestation verify "$WORK/${n}.tgz" --bundle "$WORK/${n}.bundle.json" --digest-alg sha512 \
        --repo "$REPO" --signer-workflow "$WORKFLOW" --source-ref "$SOURCE_REF" \
        --format json --jq '.[0].verificationResult.signature.certificate.subjectAlternativeName' 2>"$WORK/gh.err"); then
        fail "${pkg} の来歴を、${WORKFLOW} が ${SOURCE_REF} から作った物として確かめられませんでした。gh の出力: $(grep -v '^[[:space:]]*$' "$WORK/gh.err" | tail -n 1)"
    fi
    [ -n "$san" ] || fail "${pkg} の来歴から、署名した者を読めませんでした。"
    [ -n "$SIGNER" ] || SIGNER="$san"
done

# 確かめた tgz だけを展開する。1つ目は本体、ほかは vendor だけを本体の vendor に置く
rm -rf "$DEST"
mkdir -p "$DEST/vendor" "$DEST/path"
tar -xzf "$WORK/1.tgz" -C "$DEST" --strip-components=1 --no-same-owner
for i in $(seq 2 "$n"); do
    mkdir -p "$WORK/x${i}"
    tar -xzf "$WORK/${i}.tgz" -C "$WORK/x${i}" --no-same-owner
    [ -d "$WORK/x${i}/package/vendor" ] && cp -R "$WORK/x${i}/package/vendor/." "$DEST/vendor/"
done
[ -f "$DEST/bin/codex.js" ] || fail "本体の部品の中に bin/codex.js がありません。"
[ -x "$DEST/vendor/${TARGET}/bin/codex" ] || fail "部品の中に、${TARGET} の Codex CLI の実行ファイルがありません。"
chmod +x "$DEST/bin/codex.js"
ln -s ../bin/codex.js "$DEST/path/codex"
echo "$DEST/path" >>"$GITHUB_PATH"
echo "Codex CLI ${VERSION} を、${SIGNER} の来歴で確かめてから入れました。"
