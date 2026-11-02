#!/usr/bin/env bash
# =====================================================================
# CI の道具の1つの版を、配布元の署名で確かめ、PR の本文に書く文と記録の目印の行を出す
# (Claude が、ci-tool-fast-update のスキルの手順の中で動かす)
#
# 信頼する署名した者は trusted-signers.json から読み、このスクリプトには書かない。
# このスクリプトは、ファイルの版を書き換えない。
#
# 道具ごとの確かめ方:
#   node:      nodejs.org の SHASUMS256.txt.asc を gpg で確かめ、node-v<版>-linux-x64.tar.gz の
#              ハッシュを照らす。CI はこの tarball をそのまま入れる(.github/scripts/install-verified-node.sh)。
#              公開日時は nodejs/node の GitHub のリリース v<版> の published_at
#   trivy:     GitHub のリリースの trivy_<版>_Linux-64bit.tar.gz を、同じ名前に .sigstore.json を
#              足した署名で、cosign verify-blob で確かめる。身元は trusted-signers.json の
#              identity_template の {version} に版を入れたもの。公開日時はリリースの published_at
#   codex:     trusted-signers.json の packages の2つの部品(@openai/codex の版と、その linux-x64 の版)の
#              tgz を npm の registry から取り、来歴の bundle を gh attestation verify で確かめる。
#              公開日時は、部品の文書の time の、1つ目の部品の版の値
#   terraform: releases.hashicorp.com の terraform_<版>_SHA256SUMS を .sig で gpg で確かめ、
#              terraform_<版>_linux_amd64.zip のハッシュを照らす。公開日時は
#              api.releases.hashicorp.com の timestamp_created
#
# 署名した者:
#   node と terraform: gpg --verify の VALIDSIG の行の最後の欄にある主鍵の指紋である。公開鍵は、信頼する者の
#   指紋ごとに鍵サーバから取る。鍵サーバが別の鍵を返しても、署名を検証できた鍵の主鍵の指紋を
#   信頼する者の指紋と比べるので、別の者を信頼する者とみなさない。
#   trivy: cosign に渡した身元。codex: gh attestation verify が返した証明書の身元
#   (subjectAlternativeName。来歴を作ったワークフローとタグ)。1つ目の部品のものを出す。
#
# なぜ gpg をコンテナで動かすのか:
#   開発者の PC に gpg が無くても、同じ版の gpg で確かめられるようにするため。コンテナは、
#   このスクリプトの隣の Dockerfile から作り、ネットワークを外して1回きりで動かす。
#   鍵の置き場(GNUPGHOME)はコンテナの中に作る。gpg の補助の仕組みが置き場に作る
#   ソケットは、Windows の PC の作業フォルダの上では作れないことがあるため。
#
# なぜ cosign はネットワークを外さないのか:
#   cosign は、署名の証明書と透明性ログの記録を確かめるために、Sigstore の信頼の起点のデータを
#   取りに行くため。cosign のコンテナには、作業フォルダを読むだけの形で渡す。
#
# 取得したファイルは、毎回新しく作る空の作業フォルダに置き、スクリプトの置き場とは分ける。
# 取得したファイルの中のスクリプトは動かさない。tarball は、ハッシュを計るだけにする。
#
# 問い合わせ: 打ち切りは300秒、再試行は1回。404 は再試行しない。
#
# テスト: .claude/scripts/ci-tool-signature/test-verify-ci-tool.sh
# 使い方: verify-ci-tool.sh <node|trivy|codex|terraform> <版> <所有者の指示の要約>
#   出力(標準出力): 1行目 result=verified / unverified / unknown
#     確かめられたとき: 2行目から PR の本文に書く Markdown の文。公開から72時間経っていなければ、
#       最後に記録の目印の行 <!-- ci-tool-cooldown-exception data=<base64> -->
#     確かめられなかったとき: 2行目 detail=<理由の説明>
#   環境変数 TRUSTED_SIGNERS_FILE(既定 このスクリプトの隣の trusted-signers.json)
#   終了コード 0 = 確かめられた / 1 = 署名が中身と合わない、署名が無い、署名した者が信頼する者と違う /
#     2 = 取りに行けなかった、Docker が動かない、引数の誤り
# =====================================================================
set -euo pipefail

usage() {
    echo "result=unknown"
    echo "detail=使い方: verify-ci-tool.sh <node|trivy|codex|terraform> <版> <所有者の指示の要約>"
    exit 2
}
[ "$#" -eq 3 ] || usage
TOOL="$1"
VERSION="$2"
OWNER_INSTRUCTION="$3"
case "$TOOL" in node | trivy | codex | terraform) ;; *) usage ;; esac
case "$VERSION" in "" | *[!0-9A-Za-z.+-]*) usage ;; esac
[ -n "$OWNER_INSTRUCTION" ] || usage

HERE="$(cd "$(dirname "$0")" && pwd)"
SIGNERS="${TRUSTED_SIGNERS_FILE:-$HERE/trusted-signers.json}"
IMAGE="kp-ci-tool-gpg:local"
KEYSERVER="https://keyserver.ubuntu.com"
NPM_REGISTRY="https://registry.npmjs.org"
# cosign のイメージ。digest で固定する(ghcr.io/sigstore/cosign/cosign:v3.1.4 の、2026-11-02 に読んだ値)
COSIGN_IMAGE="ghcr.io/sigstore/cosign/cosign@sha256:0f06154836d2de34f887a5c273506d52ca43edaa1d9e53e6510fa78a48f69c2d"

# Windows の Git Bash では C:/... の形のパスを返す。docker と、Windows 向けに作られた curl は、
# /tmp/... の形のパスを読めないため
host_path() {
    (cd "$1" && { pwd -W 2>/dev/null || pwd; })
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(host_path "$TMP")
mkdir "$TMP/keys"

unverified() {
    echo "result=unverified"
    echo "detail=$1"
    exit 1
}

unknown() {
    echo "result=unknown"
    echo "detail=$1"
    exit 2
}

# 使い方: fetch <URL> <答えのファイル>。HTTP の状態の番号を出す(取れなければ 000)
fetch() {
    local code attempt
    for attempt in 1 2; do
        code=$(curl -sSL --max-time 300 -o "$2" -w '%{http_code}' "$1" 2>/dev/null) || code=000
        case "$code" in 200 | 404) break ;; esac
        echo "取得に失敗しました(${attempt}回目、HTTP ${code}): $1" >&2
    done
    echo "$code"
}

# 使い方: must_fetch <URL> <答えのファイル> <何を取るか>。200 でなければ unknown で止まる
must_fetch() {
    local code
    code=$(fetch "$1" "$2")
    [ "$code" = 200 ] || unknown "${3}を取れませんでした(HTTP ${code}): $1"
}

# 使い方: last_line <ファイル>。空でない最後の行を出す
last_line() {
    grep -v '^[[:space:]]*$' "$1" 2>/dev/null | tail -n 1 | tr -d '\r' || true
}

# 使い方: integrity_of <ファイル>。npm の dist.integrity と同じ形(sha512-<base64>)のハッシュを出す
integrity_of() {
    perl -MDigest::SHA -MMIME::Base64 -e '
        open my $f, "<:raw", $ARGV[0] or die;
        my $s = Digest::SHA->new(512);
        $s->addfile($f);
        print "sha512-", encode_base64($s->digest, "");
    ' "$1"
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{ print $1 }'
    else
        shasum -a 256 | awk '{ print $1 }'
    fi
}

# --- 信頼する署名した者 --------------------------------------------------------------

[ -f "$SIGNERS" ] || unknown "信頼する署名した者のファイルがありません: ${SIGNERS}"

# 使い方: read_signers <欄の名前> <値の形の正規表現>。この道具の欄の値を1行に1つずつ出す。
# 欄は文字列か、文字列の空でない配列。欄が無いか、値が形に合わなければ終了コード 1
read_signers() {
    perl -MJSON::PP -e '
        local $/;
        open my $f, "<", $ARGV[0] or die;
        my $v = decode_json(<$f>)->{ $ARGV[1] }{ $ARGV[2] };
        my $re = qr/$ARGV[3]/;
        my @l = ref $v eq "ARRAY" ? @$v : ($v);
        die unless @l;
        for (@l) { die unless defined && !ref && /$re/; print "$_\n" }
    ' "$SIGNERS" "$TOOL" "$1" "$2" 2>/dev/null
}

# --- gpg のコンテナ --------------------------------------------------------------------

# コンテナの中で動かす手順。引数: <clear|detached> <署名のファイル> <中身か出力のファイル> <鍵のファイル>...
#   clear: 署名の付いた文書を確かめ、署名した範囲の文だけを出力のファイルに書く
#   detached: 分けて置いた署名で中身のファイルを確かめる
# gpg の状態の行を /work/status に、取り込めた鍵の指紋を /work/imported に書く
GPG_STEPS=$(cat <<'STEPS'
set -u
g=$(mktemp -d)
mode=$1 sig=$2 data=$3
shift 3
[ "$#" -eq 0 ] || gpg --batch --quiet --homedir "$g" --import "$@" 2>/dev/null || true
gpg --batch --homedir "$g" --with-colons --list-keys 2>/dev/null | awk -F: '$1 == "pub" { p = 1; next } p && $1 == "fpr" { print $10; p = 0 }' >/work/imported
case "$mode" in
clear) gpg --batch --yes --homedir "$g" --status-file /work/status --output "$data" --decrypt "$sig" >/dev/null 2>&1 || true ;;
detached) gpg --batch --homedir "$g" --status-file /work/status --verify "$sig" "$data" >/dev/null 2>&1 || true ;;
esac
exit 0
STEPS
)

# 使い方: prepare_gpg。信頼する者の鍵の指紋を TRUSTED に読み、gpg のコンテナのイメージを作る
prepare_gpg() {
    TRUSTED=$(read_signers fingerprints '\A[0-9A-F]{40}\z') ||
        unknown "信頼する署名した者のファイルから、${TOOL} の鍵の指紋を読めませんでした: ${SIGNERS}"
    if ! MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker build -q -t "$IMAGE" "$(host_path "$HERE")" >/dev/null 2>&1; then
        unknown "gpg を動かすコンテナのイメージを作れませんでした。Docker が動いているか確かめてください。"
    fi
}

# 使い方: verify_signature <clear|detached> <署名のファイル名> <中身か出力のファイル名> <理由に出す署名の名前>
# ファイル名は作業フォルダの中の名前。SIGNER に署名した者の主鍵の指紋を入れる
verify_signature() {
    local keyfiles=() fpr code missing=0 status good valid
    for fpr in $TRUSTED; do
        code=$(fetch "${KEYSERVER}/pks/lookup?op=get&options=mr&search=0x${fpr}" "$TMP/keys/${fpr}.asc")
        if [ "$code" = 200 ]; then
            keyfiles+=("/work/keys/${fpr}.asc")
        else
            echo "信頼する者の公開鍵(${fpr})を鍵サーバから取れませんでした(HTTP ${code})。" >&2
        fi
    done
    : >"$TMP/status"
    if ! MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm --network none \
        --user "$(id -u):$(id -g)" -v "$TMP:/work" -w /work "$IMAGE" \
        sh -c "$GPG_STEPS" sh "$1" "/work/$2" "/work/$3" ${keyfiles[@]+"${keyfiles[@]}"} >/dev/null 2>&1; then
        unknown "gpg を動かすコンテナを動かせませんでした。Docker が動いているか確かめてください。"
    fi
    for fpr in $TRUSTED; do
        grep -qx "$fpr" "$TMP/imported" 2>/dev/null || missing=$((missing + 1))
    done
    status="$TMP/status"
    if grep -q '^\[GNUPG:\] BADSIG ' "$status"; then
        unverified "${4} の署名が、中身と合いません。"
    fi
    valid=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' "$status")
    good=$(awk '$1 == "[GNUPG:]" && $2 == "GOODSIG" { n++ } END { print n + 0 }' "$status")
    if [ -z "$valid" ]; then
        if grep -q '^\[GNUPG:\] NODATA ' "$status"; then
            unverified "${4} に署名がありません。"
        fi
        if [ "$missing" -gt 0 ]; then
            unknown "${4} を確かめられませんでした。信頼する者の公開鍵のうち ${missing} 個を取れなかったため、署名した者が信頼する者かどうかを決められません。"
        fi
        if grep -Eq '^\[GNUPG:\] (ERRSIG|NO_PUBKEY) ' "$status"; then
            unverified "${4} の署名した者が、信頼する者の誰とも違います。"
        fi
        unverified "${4} の署名を確かめられませんでした。"
    fi
    for fpr in $valid; do
        if ! printf '%s\n' "$TRUSTED" | grep -qx "$fpr"; then
            unverified "${4} の署名した者(${fpr})が、信頼する者の誰とも違います。"
        fi
    done
    if [ "$good" -eq 0 ]; then
        unverified "${4} の署名した鍵の期限が切れているか、鍵が失効しています。"
    fi
    SIGNER=$(printf '%s\n' "$valid" | head -n 1)
}

# 使い方: listed_hash <ハッシュの一覧のファイル> <ファイル名>
listed_hash() {
    awk -v n="$2" '($2 == n || $2 == "*" n) && $1 ~ /^[0-9a-f]{64}$/ { print $1; exit }' "$1"
}

# --- 道具ごとの確かめ方 ----------------------------------------------------------------

check_node() {
    local base="https://nodejs.org/dist/v${VERSION}" tarball="node-v${VERSION}-linux-x64.tar.gz"
    local code want got
    prepare_gpg
    code=$(fetch "${base}/SHASUMS256.txt.asc" "$TMP/SHASUMS256.txt.asc")
    if [ "$code" = 404 ]; then
        code=$(fetch "${base}/SHASUMS256.txt" "$TMP/SHASUMS256.txt")
        [ "$code" = 200 ] || unknown "Node.js ${VERSION} の SHASUMS256.txt を取れませんでした(HTTP ${code})。版が無いかもしれません。"
        unverified "Node.js ${VERSION} の SHASUMS256.txt に、署名(SHASUMS256.txt.asc)がありません。"
    fi
    [ "$code" = 200 ] || unknown "Node.js ${VERSION} の SHASUMS256.txt.asc を取れませんでした(HTTP ${code})。"
    verify_signature clear SHASUMS256.txt.asc shasums.txt SHASUMS256.txt.asc

    want=$(listed_hash "$TMP/shasums.txt" "$tarball")
    [ -n "$want" ] || unverified "署名された SHASUMS256.txt に、${tarball} のハッシュがありません。"
    must_fetch "${base}/${tarball}" "$TMP/official.tar.gz" "${tarball} "
    got=$(sha256_of <"$TMP/official.tar.gz")
    [ "$got" = "$want" ] || unverified "${tarball} のハッシュが、署名された SHASUMS256.txt の値と違います。"

    if ! PUBLISHED=$(gh api "repos/nodejs/node/releases/tags/v${VERSION}" --jq .published_at 2>/dev/null) || [ -z "$PUBLISHED" ]; then
        unknown "nodejs/node のリリース v${VERSION} の公開日時を読めませんでした。"
    fi
    METHOD="gpg --verify"
    HOW="nodejs.org の SHASUMS256.txt.asc の署名を gpg で確かめ、${tarball} のハッシュを照らした"
    TOOL_NAME="Node.js"
}

check_terraform() {
    local base="https://releases.hashicorp.com/terraform/${VERSION}" zip="terraform_${VERSION}_linux_amd64.zip"
    local sums="terraform_${VERSION}_SHA256SUMS" code want got
    prepare_gpg
    must_fetch "${base}/${sums}" "$TMP/sums.txt" "${sums} "
    code=$(fetch "${base}/${sums}.sig" "$TMP/sums.sig")
    [ "$code" = 404 ] && unverified "${sums} に、署名(${sums}.sig)がありません。"
    [ "$code" = 200 ] || unknown "${sums}.sig を取れませんでした(HTTP ${code})。"
    verify_signature detached sums.sig sums.txt "${sums}.sig"

    want=$(listed_hash "$TMP/sums.txt" "$zip")
    [ -n "$want" ] || unverified "署名された ${sums} に、${zip} のハッシュがありません。"
    must_fetch "${base}/${zip}" "$TMP/terraform.zip" "${zip} "
    got=$(sha256_of <"$TMP/terraform.zip")
    [ "$got" = "$want" ] || unverified "${zip} のハッシュが、署名された ${sums} の値と違います。"

    must_fetch "https://api.releases.hashicorp.com/v1/releases/terraform/${VERSION}" "$TMP/release.json" \
        "Terraform ${VERSION} のリリースの情報"
    if ! PUBLISHED=$(perl -MJSON::PP -e '
        local $/;
        open my $f, "<", $ARGV[0] or die;
        my $t = decode_json(<$f>)->{timestamp_created};
        die unless defined $t && !ref $t && length $t;
        print $t;
    ' "$TMP/release.json" 2>/dev/null); then
        unknown "Terraform ${VERSION} のリリースの情報から、公開日時を読めませんでした。"
    fi
    METHOD="gpg --verify"
    HOW="releases.hashicorp.com の ${sums} の署名を gpg で確かめ、${zip} のハッシュを照らした"
    TOOL_NAME="Terraform"
}

check_trivy() {
    local base="https://github.com/aquasecurity/trivy/releases/download/v${VERSION}"
    local file="trivy_${VERSION}_Linux-64bit.tar.gz" issuer template identity code rc
    issuer=$(read_signers oidc_issuer '\Ahttps://[!-~]+\z') ||
        unknown "信頼する署名した者のファイルから、trivy の oidc_issuer を読めませんでした: ${SIGNERS}"
    template=$(read_signers identity_template '\Ahttps://[!-~]*\{version\}[!-~]*\z') ||
        unknown "信頼する署名した者のファイルから、trivy の identity_template を読めませんでした: ${SIGNERS}"
    identity="${template//\{version\}/$VERSION}"
    if ! MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker pull -q "$COSIGN_IMAGE" >/dev/null 2>&1; then
        unknown "cosign のコンテナのイメージを取れませんでした。Docker が動いているか確かめてください。"
    fi

    code=$(fetch "${base}/${file}.sigstore.json" "$TMP/trivy.sigstore.json")
    [ "$code" = 404 ] && unverified "${file} に、署名(${file}.sigstore.json)がありません。"
    [ "$code" = 200 ] || unknown "${file}.sigstore.json を取れませんでした(HTTP ${code})。"
    must_fetch "${base}/${file}" "$TMP/trivy.tar.gz" "${file} "

    rc=0
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm -v "$TMP:/work:ro" -w /work "$COSIGN_IMAGE" \
        verify-blob --bundle /work/trivy.sigstore.json --certificate-oidc-issuer "$issuer" \
        --certificate-identity "$identity" /work/trivy.tar.gz >/dev/null 2>"$TMP/cosign.err" || rc=$?
    case "$rc" in
    0) ;;
    125 | 126 | 127) unknown "cosign のコンテナを動かせませんでした。Docker が動いているか確かめてください。" ;;
    *) unverified "${file} の署名を、${identity} の署名として確かめられませんでした。cosign の出力: $(last_line "$TMP/cosign.err")" ;;
    esac

    if ! PUBLISHED=$(gh api "repos/aquasecurity/trivy/releases/tags/v${VERSION}" --jq .published_at 2>/dev/null) || [ -z "$PUBLISHED" ]; then
        unknown "aquasecurity/trivy のリリース v${VERSION} の公開日時を読めませんでした。"
    fi
    SIGNER="$identity"
    METHOD="cosign verify-blob"
    HOW="GitHub のリリースの ${file} の署名(${file}.sigstore.json)を cosign で確かめた"
    TOOL_NAME="Trivy"
}

check_codex() {
    local repo workflow packages pkg name ver n=0 meta tarball integrity code san first_name="" first_ver="" listed=""
    repo=$(read_signers repo '\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z') ||
        unknown "信頼する署名した者のファイルから、codex の repo を読めませんでした: ${SIGNERS}"
    workflow=$(read_signers signer_workflow '\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/[!-~]+\z') ||
        unknown "信頼する署名した者のファイルから、codex の signer_workflow を読めませんでした: ${SIGNERS}"
    packages=$(read_signers packages '\A(@[a-z0-9._-]+/)?[a-z0-9._-]+@[!-~]*\{version\}[!-~]*\z') ||
        unknown "信頼する署名した者のファイルから、codex の packages を読めませんでした: ${SIGNERS}"

    for pkg in $packages; do
        pkg="${pkg//\{version\}/$VERSION}"
        name="${pkg%@*}"
        ver="${pkg##*@}"
        n=$((n + 1))
        [ -n "$first_name" ] || { first_name="$name"; first_ver="$ver"; }
        must_fetch "${NPM_REGISTRY}/${name}/${ver}" "$TMP/codex-${n}.json" "${pkg} の部品の文書"
        if ! meta=$(perl -MJSON::PP -e '
            local $/;
            open my $f, "<", $ARGV[0] or die;
            my $d = decode_json(<$f>)->{dist};
            for (qw(tarball integrity)) { die unless defined $d->{$_} && !ref $d->{$_} && $d->{$_} =~ /\A[!-~]+\z/ }
            print "$d->{tarball}\n$d->{integrity}\n";
        ' "$TMP/codex-${n}.json" 2>/dev/null); then
            unknown "${pkg} の部品の文書から、tgz の URL とハッシュを読めませんでした。"
        fi
        tarball=$(printf '%s\n' "$meta" | sed -n 1p)
        integrity=$(printf '%s\n' "$meta" | sed -n 2p)
        case "$tarball" in "${NPM_REGISTRY}/"*) ;; *) unknown "${pkg} の tgz の URL が、npm の registry ではありません。" ;; esac

        code=$(fetch "${NPM_REGISTRY}/-/npm/v1/attestations/${name/\//%2f}@${ver}" "$TMP/codex-${n}-attestations.json")
        [ "$code" = 404 ] && unverified "${pkg} に、来歴がありません。"
        [ "$code" = 200 ] || unknown "${pkg} の来歴を取れませんでした(HTTP ${code})。"
        if ! perl -MJSON::PP -e '
            local $/;
            open my $f, "<", $ARGV[0] or die;
            for (@{ decode_json(<$f>)->{attestations} || [] }) {
                next unless ($_->{predicateType} // "") eq "https://slsa.dev/provenance/v1" && ref $_->{bundle} eq "HASH";
                print JSON::PP->new->utf8->canonical->encode($_->{bundle});
                exit 0;
            }
            exit 1;
        ' "$TMP/codex-${n}-attestations.json" >"$TMP/codex-${n}.bundle.json" 2>/dev/null; then
            unverified "${pkg} の来歴に、SLSA の来歴がありません。"
        fi

        must_fetch "$tarball" "$TMP/codex-${n}.tgz" "${pkg} の tgz "
        [ "$(integrity_of "$TMP/codex-${n}.tgz")" = "$integrity" ] ||
            unverified "${pkg} の tgz のハッシュが、部品の文書の値と違います。"
        if ! san=$(gh attestation verify "$TMP/codex-${n}.tgz" --bundle "$TMP/codex-${n}.bundle.json" \
            --digest-alg sha512 --repo "$repo" --signer-workflow "$workflow" \
            --format json --jq '.[0].verificationResult.signature.certificate.subjectAlternativeName' 2>"$TMP/gh.err"); then
            unverified "${pkg} の来歴を、${workflow} の署名として確かめられませんでした。gh の出力: $(last_line "$TMP/gh.err")"
        fi
        [ -n "$san" ] || unknown "${pkg} の来歴から、署名した者を読めませんでした。"
        [ -n "$SIGNER" ] || SIGNER="$san"
        listed="${listed:+${listed} と }${pkg}"
    done

    must_fetch "${NPM_REGISTRY}/${first_name/\//%2f}" "$TMP/codex-packument.json" "${first_name} の部品の文書"
    if ! PUBLISHED=$(perl -MJSON::PP -e '
        local $/;
        open my $f, "<", $ARGV[0] or die;
        my $t = decode_json(<$f>)->{time}{ $ARGV[1] };
        die unless defined $t && !ref $t && length $t;
        print $t;
    ' "$TMP/codex-packument.json" "$first_ver" 2>/dev/null); then
        unknown "${first_name} の部品の文書から、${first_ver} の公開日時を読めませんでした。"
    fi
    METHOD="gh attestation verify"
    HOW="npm の registry の ${listed} の tgz の来歴を gh で確かめた"
    TOOL_NAME="Codex CLI"
}

SIGNER="" PUBLISHED="" METHOD="" HOW="" TOOL_NAME=""
case "$TOOL" in
node) check_node ;;
trivy) check_trivy ;;
codex) check_codex ;;
terraform) check_terraform ;;
esac

# --- 出力 ------------------------------------------------------------------------------

CHECKED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if ! OUT=$(TOOL="$TOOL" VERSION="$VERSION" PUBLISHED="$PUBLISHED" OWNER_INSTRUCTION="$OWNER_INSTRUCTION" \
    METHOD="$METHOD" SIGNER="$SIGNER" CHECKED_AT="$CHECKED_AT" perl -MJSON::PP -MMIME::Base64 -MTime::Local -e '
    my %e = map { my $v = $ENV{$_}; utf8::decode($v); ($_ => $v) }
        qw(TOOL VERSION PUBLISHED OWNER_INSTRUCTION METHOD SIGNER CHECKED_AT);
    $e{PUBLISHED} =~ /\A(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d+)?(Z|([+-])(\d\d):?(\d\d))\z/ or die;
    my $t = timegm($6, $5, $4, $3, $2 - 1, $1);
    $t -= ($8 eq "+" ? 1 : -1) * ($9 * 3600 + $10 * 60) if $7 ne "Z";
    my $passed = time - $t >= 72 * 3600 ? "true" : "false";
    my $json = JSON::PP->new->utf8->canonical->encode({
        schema  => 1,
        entries => [{
            tool => $e{TOOL}, version => $e{VERSION}, published_at => $e{PUBLISHED},
            owner_instruction => $e{OWNER_INSTRUCTION},
            signature => {
                result => "verified", method => $e{METHOD}, signer => $e{SIGNER}, checked_at => $e{CHECKED_AT},
            },
        }],
    });
    print "passed=$passed\n", "data=", encode_base64($json, ""), "\n";
' 2>/dev/null); then
    unknown "公開日時(${PUBLISHED})を読めませんでした。"
fi
PASSED=$(printf '%s\n' "$OUT" | sed -n 's/^passed=//p')
DATA=$(printf '%s\n' "$OUT" | sed -n 's/^data=//p')

echo "result=verified"
echo "### CI の道具の版の署名の確認"
echo ""
echo "- 道具: ${TOOL_NAME}"
echo "- 版: ${VERSION}"
echo "- 公開日時: ${PUBLISHED}"
if [ "$PASSED" = true ]; then
    echo "- 公開から72時間: 経っている"
else
    echo "- 公開から72時間: 経っていない(所有者の指示で、72時間待たずに入れる)"
fi
echo "- 確かめ方: ${HOW}(${METHOD})"
echo "- 署名した者: ${SIGNER}"
echo "- 確かめた日時: ${CHECKED_AT}"
if [ "$PASSED" != true ]; then
    echo ""
    echo "<!-- ci-tool-cooldown-exception data=${DATA} -->"
fi
exit 0
