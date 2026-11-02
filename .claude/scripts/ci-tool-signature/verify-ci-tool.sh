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
#              ハッシュを照らす。CI の setup-node が入れるのは actions/node-versions が詰め直した
#              tarball なので、その tarball の bin/node のハッシュが、確かめた tarball の bin/node と
#              同じことも確かめる。公開日時は actions/node-versions のそのリリースの published_at
#   terraform: releases.hashicorp.com の terraform_<版>_SHA256SUMS を .sig で gpg で確かめ、
#              terraform_<版>_linux_amd64.zip のハッシュを照らす。公開日時は
#              api.releases.hashicorp.com の timestamp_created
#
# 署名した者:
#   gpg --verify の VALIDSIG の行の最後の欄にある主鍵の指紋である。公開鍵は、信頼する者の
#   指紋ごとに鍵サーバから取る。鍵サーバが別の鍵を返しても、署名を検証できた鍵の主鍵の指紋を
#   信頼する者の指紋と比べるので、別の者を信頼する者とみなさない。
#
# なぜ gpg をコンテナで動かすのか:
#   開発者の PC に gpg が無くても、同じ版の gpg で確かめられるようにするため。コンテナは、
#   このスクリプトの隣の Dockerfile から作り、ネットワークを外して1回きりで動かす。
#   鍵の置き場(GNUPGHOME)はコンテナの中に作る。gpg の補助の仕組みが置き場に作る
#   ソケットは、Windows の PC の作業フォルダの上では作れないことがあるため。
#
# 取得したファイルは、毎回新しく作る空の作業フォルダに置き、スクリプトの置き場とは分ける。
# 取得したファイルの中のスクリプトは動かさない。tarball は、bin/node を標準出力へ取り出して
# ハッシュを計るだけにする。
#
# 問い合わせ: 打ち切りは300秒、再試行は1回。404 は再試行しない。
#
# テスト: .claude/scripts/ci-tool-signature/test-verify-ci-tool.sh
# 使い方: verify-ci-tool.sh <node|terraform> <版> <所有者の指示の要約>
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
    echo "detail=使い方: verify-ci-tool.sh <node|terraform> <版> <所有者の指示の要約>"
    exit 2
}
[ "$#" -eq 3 ] || usage
TOOL="$1"
VERSION="$2"
OWNER_INSTRUCTION="$3"
case "$TOOL" in node | terraform) ;; *) usage ;; esac
case "$VERSION" in "" | *[!0-9A-Za-z.+-]*) usage ;; esac
[ -n "$OWNER_INSTRUCTION" ] || usage

HERE="$(cd "$(dirname "$0")" && pwd)"
SIGNERS="${TRUSTED_SIGNERS_FILE:-$HERE/trusted-signers.json}"
IMAGE="kp-ci-tool-gpg:local"
KEYSERVER="https://keyserver.ubuntu.com"

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

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{ print $1 }'
    else
        shasum -a 256 | awk '{ print $1 }'
    fi
}

# --- 信頼する署名した者 --------------------------------------------------------------

[ -f "$SIGNERS" ] || unknown "信頼する署名した者のファイルがありません: ${SIGNERS}"
if ! TRUSTED=$(perl -MJSON::PP -e '
    local $/;
    open my $f, "<", $ARGV[0] or die;
    my $d = decode_json(<$f>);
    my $l = $d->{$ARGV[1]}{fingerprints};
    die unless ref $l eq "ARRAY" && @$l;
    for (@$l) { die unless defined && !ref && /\A[0-9A-F]{40}\z/; print "$_\n" }
' "$SIGNERS" "$TOOL" 2>/dev/null); then
    unknown "信頼する署名した者のファイルから、${TOOL} の鍵の指紋を読めませんでした: ${SIGNERS}"
fi

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

if ! MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker build -q -t "$IMAGE" "$(host_path "$HERE")" >/dev/null 2>&1; then
    unknown "gpg を動かすコンテナのイメージを作れませんでした。Docker が動いているか確かめてください。"
fi

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

# 使い方: node_binary_hash <tarball>。最上位か、最上位の1つのフォルダの下の bin/node のハッシュを出す
# tar には標準入力で渡す。GNU tar は、C: のようにコロンを含むパスを別の機械の名前と読むため
node_binary_hash() {
    local entries
    entries=$(tar -tzf - <"$1" 2>/dev/null | grep -E '^(\./)?([^/]+/)?bin/node$' || true)
    [ -n "$entries" ] && [ "$(printf '%s\n' "$entries" | wc -l)" -eq 1 ] || return 1
    tar -xzOf - "$entries" <"$1" | sha256_of
}

# --- 道具ごとの確かめ方 ----------------------------------------------------------------

check_node() {
    local base="https://nodejs.org/dist/v${VERSION}" tarball="node-v${VERSION}-linux-x64.tar.gz"
    local code want got urls download_url release_url tag official repack
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

    must_fetch "https://raw.githubusercontent.com/actions/node-versions/main/versions-manifest.json" \
        "$TMP/manifest.json" "actions/node-versions の versions-manifest.json "
    if ! urls=$(perl -MJSON::PP -e '
        local $/;
        open my $f, "<", $ARGV[0] or die;
        my $d = decode_json(<$f>);
        for my $e (@$d) {
            next unless ref $e eq "HASH" && ($e->{version} // "") eq $ARGV[1];
            for my $x (@{ $e->{files} || [] }) {
                next unless ($x->{platform} // "") eq "linux" && ($x->{arch} // "") eq "x64";
                print "$x->{download_url}\n$e->{release_url}\n";
                exit 0;
            }
        }
        exit 1;
    ' "$TMP/manifest.json" "$VERSION" 2>/dev/null); then
        unknown "actions/node-versions の versions-manifest.json に、Node.js ${VERSION} の linux の x64 の tarball がありません。"
    fi
    download_url=$(printf '%s\n' "$urls" | sed -n 1p)
    release_url=$(printf '%s\n' "$urls" | sed -n 2p)
    tag="${release_url##*/tag/}"
    case "$download_url:$tag" in
    https://github.com/actions/node-versions/releases/download/*:* ) ;;
    *) unknown "versions-manifest.json の Node.js ${VERSION} の URL が、actions/node-versions のリリースではありません。" ;;
    esac
    case "$tag" in "" | */* | "$release_url") unknown "versions-manifest.json の Node.js ${VERSION} のリリースの URL を読めませんでした。" ;; esac
    must_fetch "$download_url" "$TMP/repack.tar.gz" "actions/node-versions の詰め直しの tarball "

    official=$(node_binary_hash "$TMP/official.tar.gz") || unverified "${tarball} の中に bin/node が1つだけ入っていません。"
    repack=$(node_binary_hash "$TMP/repack.tar.gz") || unverified "actions/node-versions の詰め直しの tarball の中に bin/node が1つだけ入っていません。"
    [ "$official" = "$repack" ] || unverified "actions/node-versions の詰め直しの tarball の bin/node が、確かめた ${tarball} の bin/node と違います。"

    if ! PUBLISHED=$(gh api "repos/actions/node-versions/releases/tags/${tag}" --jq .published_at 2>/dev/null) || [ -z "$PUBLISHED" ]; then
        unknown "actions/node-versions のリリース ${tag} の公開日時を読めませんでした。"
    fi
    METHOD="gpg --verify"
    HOW="nodejs.org の SHASUMS256.txt.asc の署名を gpg で確かめ、${tarball} のハッシュを照らし、actions/node-versions の詰め直しの tarball の bin/node のハッシュが同じことを確かめた"
    TOOL_NAME="Node.js"
}

check_terraform() {
    local base="https://releases.hashicorp.com/terraform/${VERSION}" zip="terraform_${VERSION}_linux_amd64.zip"
    local sums="terraform_${VERSION}_SHA256SUMS" code want got
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

SIGNER="" PUBLISHED="" METHOD="" HOW="" TOOL_NAME=""
case "$TOOL" in
node) check_node ;;
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
