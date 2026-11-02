#!/usr/bin/env bash
# =====================================================================
# verify-ci-tool.sh の自動テスト(Claude が Git Bash で流す)
#
# docker と curl と gh をスタブし、Node.js と Trivy と Codex CLI と Terraform の版の確かめ方と、
# 確かめられないときの扱いを検証する。gpg の署名は、テストの中で作った使い捨ての鍵で作り、
# その鍵の指紋を TRUSTED_SIGNERS_FILE で渡す。docker のスタブは、gpg のコンテナの代わりに、
# この PC の gpg で同じ手順を動かす。cosign と gh attestation verify は、スタブが、署名の代わりの
# ファイルの値を照らして代わりに答える。配布物の並びは、2026-11-02 に nodejs.org と
# actions/node-versions と releases.hashicorp.com と、Trivy の GitHub のリリースと、
# npm の registry の @openai/codex から取った答えの形をもとにしてある。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/verify-ci-tool.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'gpgconf --homedir "$WORK/gpg-maker" --kill all >/dev/null 2>&1; rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
STUB="$WORK/stub"
INSTRUCTION="2026-11-02 所有者が、脆弱性の修正のため72時間待たずに上げるよう指示した"

mkdir -p "$WORK/bin" "$STUB/web" "$STUB/gh" "$WORK/gtmp"

# --- docker と curl と gh のスタブ -----------------------------------------------------
# docker: 引数を $STUB_CALLS に "DOCKER <引数>" の1行で記録する。
#   build と pull: $STUB_DIR/docker.fail があれば終了コード 1
#   run: $STUB_DIR/docker-run.fail があれば終了コード 125。-v <フォルダ>:/work(:ro)のフォルダを読み、
#     イメージの名前より後ろの引数の /work をそのフォルダに置き換える。cosign のイメージでは、
#     身元の URL の /workflows を置き換えないよう、/work/ で始まる引数だけを置き換える。
#     cosign のイメージなら、cosign verify-blob の代わりに、--bundle のファイルの sha256= と
#     identity= と issuer= の行を、中身のファイルのハッシュと --certificate-identity と
#     --certificate-oidc-issuer の値に照らす。$STUB_DIR/cosign.fail があれば終了コード 1。
#     それ以外のイメージなら、置き換えた引数をこの PC で動かす
cat >"$WORK/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "DOCKER $*" >>"${STUB_CALLS:?}"
cmd="$1"
shift
case "$cmd" in
build | pull)
    [ -e "${STUB_DIR:?}/docker.fail" ] && exit 1
    echo "sha256:0"
    exit 0
    ;;
run)
    [ -e "${STUB_DIR:?}/docker-run.fail" ] && exit 125
    host=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --rm) shift ;;
        --network | --user | -w) shift 2 ;;
        -v) host="${2%:ro}"; host="${host%:}"; host="${host%:/work}"; shift 2 ;;
        *) break ;;
        esac
    done
    [ -n "$host" ] || exit 125
    image="$1"
    shift
    args=()
    case "$image" in
    ghcr.io/sigstore/cosign/cosign@*)
        for a in "$@"; do case "$a" in /work/*) args+=("$host${a#/work}") ;; *) args+=("$a") ;; esac; done
        [ -e "$STUB_DIR/cosign.fail" ] && { echo "Error: fetching trusted root failed" >&2; exit 1; }
        set -- "${args[@]}"
        [ "$1" = verify-blob ] || exit 1
        shift
        bundle="" identity="" issuer=""
        while [ "$#" -gt 1 ]; do
            case "$1" in
            --bundle) bundle="$2"; shift 2 ;;
            --certificate-identity) identity="$2"; shift 2 ;;
            --certificate-oidc-issuer) issuer="$2"; shift 2 ;;
            *) exit 1 ;;
            esac
        done
        [ "$(sha256sum "$1" | awk '{ print $1 }')" = "$(sed -n 's/^sha256=//p' "$bundle")" ] ||
            { echo "Error: invalid signature when validating ASN.1 encoded signature" >&2; exit 1; }
        [ "$identity" = "$(sed -n 's/^identity=//p' "$bundle")" ] &&
            [ "$issuer" = "$(sed -n 's/^issuer=//p' "$bundle")" ] ||
            { echo "Error: no matching CertificateIdentity found" >&2; exit 1; }
        echo "Verified OK" >&2
        exit 0
        ;;
    esac
    for a in "$@"; do args+=("${a//\/work/$host}"); done
    TMPDIR="${STUB_TMP:?}" exec "${args[@]}"
    ;;
esac
exit 1
STUB
chmod +x "$WORK/bin/docker"

# curl: 取った URL と --max-time の値を $STUB_CALLS に1行で記録する。
#   https://<ホスト>/<パス>: $STUB_DIR/web/<ホスト>/<パス>
#   鍵サーバの .../pks/lookup?...search=0x<指紋>: $STUB_DIR/web/keyserver.ubuntu.com/keys/<指紋>
#   ファイルの名前に .fail を足したファイルがあれば HTTP 500、.fail-once なら1回だけ 500。
#   ファイルが無ければ 404。
cat >"$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
url="" out="" maxt="" prev=""
for a in "$@"; do
    case "$prev" in
    -o) out="$a" ;;
    --max-time) maxt="$a" ;;
    esac
    case "$a" in https://*) url="$a" ;; esac
    prev="$a"
done
echo "GET ${url} max-time=${maxt}" >>"${STUB_CALLS:?}"
case "$url" in
https://keyserver.ubuntu.com/pks/lookup\?*) f="${STUB_DIR:?}/web/keyserver.ubuntu.com/keys/${url##*search=0x}" ;;
https://*) f="${STUB_DIR:?}/web/${url#https://}" ;;
*) exit 6 ;;
esac
if [ -e "${f}.fail-once" ]; then rm -f "${f}.fail-once"; printf 'error' >"$out"; printf 500; exit 0; fi
if [ -e "${f}.fail" ]; then printf 'error' >"$out"; printf 500; exit 0; fi
if [ -f "$f" ]; then cp "$f" "$out"; printf 200; exit 0; fi
printf 'not found' >"$out"
printf 404
STUB
chmod +x "$WORK/bin/curl"

# gh: 引数を $STUB_CALLS に "GH <引数>" の1行で記録する。
#   api repos/<所有者>/<リポジトリ>/releases/tags/<タグ> --jq .published_at:
#     $STUB_DIR/gh/<所有者>/<リポジトリ>/<タグ> を出す。ファイルが無ければ終了コード 1
#   attestation verify <tgz> --bundle <bundle> ... --repo <R> --signer-workflow <W> ...:
#     gh attestation verify の代わりに、bundle の JSON の test の sha512 と repo と workflow を、
#     tgz のハッシュ(dist.integrity の形)と --repo と --signer-workflow の値に照らし、
#     合えば test の san を出す。合わなければ終了コード 1
#   $STUB_DIR/gh.fail があれば、どの呼び出しも終了コード 1
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "GH $*" >>"${STUB_CALLS:?}"
[ -e "${STUB_DIR:?}/gh.fail" ] && { echo "HTTP 500" >&2; exit 1; }
case "$1 $2" in
"api repos/"*"/releases/tags/"*)
    f="${2#repos/}"
    f="${STUB_DIR}/gh/${f%%/releases/tags/*}/${2##*/tags/}"
    [ -f "$f" ] || { echo "HTTP 404" >&2; exit 1; }
    cat "$f"
    ;;
"attestation verify")
    tgz="$3" bundle="" repo="" workflow=""
    shift 3
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --bundle) bundle="$2"; shift 2 ;;
        --repo) repo="$2"; shift 2 ;;
        --signer-workflow) workflow="$2"; shift 2 ;;
        *) shift ;;
        esac
    done
    perl -MJSON::PP -MDigest::SHA -MMIME::Base64 -e '
        my ($tgz, $bundle, $repo, $workflow) = @ARGV;
        local $/;
        open my $f, "<", $bundle or exit 1;
        my $t = decode_json(<$f>)->{test} or exit 1;
        open my $g, "<:raw", $tgz or exit 1;
        my $s = Digest::SHA->new(512);
        $s->addfile($g);
        exit 1 unless $t->{sha512} eq "sha512-" . encode_base64($s->digest, "")
            && $t->{repo} eq $repo && $t->{workflow} eq $workflow;
        print "$t->{san}\n";
    ' "$tgz" "$bundle" "$repo" "$workflow" || { echo 'Error: verifying with issuer "sigstore.dev"' >&2; exit 1; }
    ;;
*) exit 1 ;;
esac
STUB
chmod +x "$WORK/bin/gh"

# --- テストの鍵 ------------------------------------------------------------------------
MAKER="$WORK/gpg-maker"
mkdir "$MAKER"
gpgm() { gpg --batch --homedir "$MAKER" --pinentry-mode loopback --passphrase '' "$@"; }
gpgm --quick-gen-key "Release <release@example.invalid>" ed25519 sign never 2>/dev/null || exit 1
gpgm --quick-gen-key "Other <other@example.invalid>" ed25519 sign never 2>/dev/null || exit 1
fpr_of() { gpgm --list-keys --with-colons "$1" 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }'; }
FT=$(fpr_of release@example.invalid)
FO=$(fpr_of other@example.invalid)
[ -n "$FT" ] && [ -n "$FO" ] || exit 1
TRIVY_ISSUER="https://issuer.example.invalid"
TRIVY_TEMPLATE="https://github.com/example/trivy/.github/workflows/release.yaml@refs/tags/v{version}"
CODEX_REPO="example/codex"
CODEX_WORKFLOW="example/codex/.github/workflows/release.yml"
cat >"$WORK/signers.json" <<JSON
{
  "node": {"fingerprints": ["$FT"], "locations": []},
  "trivy": {"oidc_issuer": "$TRIVY_ISSUER", "identity_template": "$TRIVY_TEMPLATE", "locations": []},
  "codex": {"repo": "$CODEX_REPO", "signer_workflow": "$CODEX_WORKFLOW",
            "packages": ["@openai/codex@{version}", "@openai/codex@{version}-linux-x64"], "locations": []},
  "terraform": {"fingerprints": ["$FT"], "locations": []}
}
JSON

# 使い方: at <今から何秒前か>。その時刻を ISO 8601 の UTC で出す
at() { perl -MPOSIX -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time - $ARGV[0]))' "$1"; }
sha() { sha256sum "$1" | awk '{ print $1 }'; }

# 使い方: publish_key <主鍵の指紋> <鍵サーバの search に使われる指紋>
publish_key() {
    mkdir -p "$STUB/web/keyserver.ubuntu.com/keys"
    gpgm --armor --export "$1" >"$STUB/web/keyserver.ubuntu.com/keys/$2" 2>/dev/null
}

V=24.99.1
NODE_DIST="$STUB/web/nodejs.org/dist/v$V"
TAG="$V-1234567890"
REPACK="$STUB/web/github.com/actions/node-versions/releases/download/$TAG/node-$V-linux-x64.tar.gz"

# 使い方: tarball <出力のファイル> <最上位のフォルダか .> <bin/node の中身>
tarball() {
    local d
    d=$(mktemp -d -p "$WORK")
    mkdir -p "$d/src/$2/bin" "$d/src/$2/lib"
    printf '%s' "$3" >"$d/src/$2/bin/node"
    printf 'lib' >"$d/src/$2/lib/readme"
    mkdir -p "$(dirname "$1")"
    (cd "$d/src" && tar -czf - "$2") >"$1"
    rm -rf "$d"
}

# 使い方: node_put <公開日時> [署名に使う鍵の指紋]
# 公式の tarball と SHASUMS256.txt と、その鍵で作った SHASUMS256.txt.asc と、
# versions-manifest.json と、詰め直しの tarball と、リリースの公開日時を置く
node_put() {
    local key="${2:-$FT}"
    tarball "$NODE_DIST/node-v$V-linux-x64.tar.gz" "node-v$V-linux-x64" "node binary $V"
    {
        echo "1111111111111111111111111111111111111111111111111111111111111111  node-v$V-darwin-arm64.tar.gz"
        echo "$(sha "$NODE_DIST/node-v$V-linux-x64.tar.gz")  node-v$V-linux-x64.tar.gz"
    } >"$NODE_DIST/SHASUMS256.txt"
    gpgm -u "$key!" --clearsign -o "$NODE_DIST/SHASUMS256.txt.asc" "$NODE_DIST/SHASUMS256.txt" 2>/dev/null || exit 1
    mkdir -p "$STUB/web/raw.githubusercontent.com/actions/node-versions/main"
    cat >"$STUB/web/raw.githubusercontent.com/actions/node-versions/main/versions-manifest.json" <<JSON
[
  {"version": "$V", "stable": true,
   "release_url": "https://github.com/actions/node-versions/releases/tag/$TAG",
   "files": [
     {"filename": "node-$V-darwin-arm64.tar.gz", "arch": "arm64", "platform": "darwin",
      "download_url": "https://github.com/actions/node-versions/releases/download/$TAG/node-$V-darwin-arm64.tar.gz"},
     {"filename": "node-$V-linux-x64.tar.gz", "arch": "x64", "platform": "linux",
      "download_url": "https://github.com/actions/node-versions/releases/download/$TAG/node-$V-linux-x64.tar.gz"}
   ]},
  {"version": "24.99.0", "stable": true, "release_url": "https://github.com/actions/node-versions/releases/tag/24.99.0-1", "files": []}
]
JSON
    tarball "$REPACK" "." "node binary $V"
    mkdir -p "$STUB/gh/actions/node-versions"
    printf '%s\n' "$1" >"$STUB/gh/actions/node-versions/$TAG"
}

TV=0.99.3
TRIVY_FILE="trivy_${TV}_Linux-64bit.tar.gz"
TRIVY_DIST="$STUB/web/github.com/aquasecurity/trivy/releases/download/v$TV"
TRIVY_IDENTITY="https://github.com/example/trivy/.github/workflows/release.yaml@refs/tags/v$TV"

# 使い方: trivy_put <公開日時> [署名の身元] [署名の発行者]
# tarball と、cosign のスタブが読む .sigstore.json と、リリースの公開日時を置く
trivy_put() {
    mkdir -p "$TRIVY_DIST" "$STUB/gh/aquasecurity/trivy"
    printf 'trivy tarball %s' "$TV" >"$TRIVY_DIST/$TRIVY_FILE"
    {
        echo "sha256=$(sha "$TRIVY_DIST/$TRIVY_FILE")"
        echo "identity=${2:-$TRIVY_IDENTITY}"
        echo "issuer=${3:-$TRIVY_ISSUER}"
    } >"$TRIVY_DIST/$TRIVY_FILE.sigstore.json"
    printf '%s\n' "$1" >"$STUB/gh/aquasecurity/trivy/v$TV"
}

CV=0.999.0
REG="$STUB/web/registry.npmjs.org"
CODEX_SAN="https://github.com/example/codex/.github/workflows/release.yml@refs/tags/rust-v$CV"
integrity() { perl -MDigest::SHA -MMIME::Base64 -e 'open my $f, "<:raw", $ARGV[0] or die; my $s = Digest::SHA->new(512); $s->addfile($f); print "sha512-", encode_base64($s->digest, "")' "$1"; }

# 使い方: codex_put <公開日時>
# 2つの部品(CV と CV-linux-x64)の tgz と部品の文書と来歴と、部品の文書の公開日時を置く。
# 2つ目の部品の来歴の署名した者は、1つ目と違う値にする(本文と記録に1つ目のものが出ることを確かめるため)。
# 来歴の一覧には、npm の publish attestation(合わない bundle)を先に置き、SLSA の来歴を後に置く
codex_put() {
    local p integ san="$CODEX_SAN"
    mkdir -p "$REG/@openai/codex/-" "$REG/-/npm/v1/attestations"
    for p in "$CV" "$CV-linux-x64"; do
        printf 'codex tgz %s' "$p" >"$REG/@openai/codex/-/codex-$p.tgz"
        integ=$(integrity "$REG/@openai/codex/-/codex-$p.tgz")
        [ "$p" = "$CV" ] || san="${CODEX_SAN}-linux-x64"
        printf '{"name":"@openai/codex","version":"%s","dist":{"tarball":"https://registry.npmjs.org/@openai/codex/-/codex-%s.tgz","integrity":"%s"}}\n' \
            "$p" "$p" "$integ" >"$REG/@openai/codex/$p"
        cat >"$REG/-/npm/v1/attestations/@openai%2fcodex@$p" <<JSON
{"attestations": [
  {"predicateType": "https://github.com/npm/attestation/tree/main/specs/publish/v0.1",
   "bundle": {"test": {"sha512": "sha512-x", "repo": "npm/cli", "workflow": "npm/cli/.github/workflows/publish.yml", "san": "npm"}}},
  {"predicateType": "https://slsa.dev/provenance/v1",
   "bundle": {"test": {"sha512": "$integ", "repo": "$CODEX_REPO", "workflow": "$CODEX_WORKFLOW",
                       "san": "$san"}}}
]}
JSON
    done
    printf '{"name":"@openai/codex","time":{"%s":"%s","%s-linux-x64":"2020-01-01T00:00:00Z"}}\n' "$CV" "$1" "$CV" \
        >"$REG/@openai%2fcodex"
}

TF=1.99.2
TF_DIST="$STUB/web/releases.hashicorp.com/terraform/$TF"

# 使い方: tf_put <公開日時> [署名に使う鍵の指紋]
tf_put() {
    local key="${2:-$FT}"
    mkdir -p "$TF_DIST" "$STUB/web/api.releases.hashicorp.com/v1/releases/terraform"
    printf 'terraform zip %s' "$TF" >"$TF_DIST/terraform_${TF}_linux_amd64.zip"
    {
        echo "2222222222222222222222222222222222222222222222222222222222222222  terraform_${TF}_darwin_arm64.zip"
        echo "$(sha "$TF_DIST/terraform_${TF}_linux_amd64.zip")  terraform_${TF}_linux_amd64.zip"
    } >"$TF_DIST/terraform_${TF}_SHA256SUMS"
    gpgm -u "$key!" --detach-sign -o "$TF_DIST/terraform_${TF}_SHA256SUMS.sig" "$TF_DIST/terraform_${TF}_SHA256SUMS" 2>/dev/null || exit 1
    printf '{"name":"terraform","version":"%s","timestamp_created":"%s"}\n' "$TF" "$1" \
        >"$STUB/web/api.releases.hashicorp.com/v1/releases/terraform/$TF"
}

reset() {
    rm -rf "${STUB:?}"/web/* "$STUB"/gh/* "$STUB/gh.fail" "$STUB/docker.fail" "$STUB/docker-run.fail" "$STUB/cosign.fail"
    : >"$WORK/calls.log"
    publish_key "$FT" "$FT"
}

# 使い方: run <引数>...。出力を $WORK/out.txt に、終了コードを $RC に入れる
run() {
    PATH="$WORK/bin:$PATH" STUB_DIR="$STUB" STUB_CALLS="$WORK/calls.log" STUB_TMP="$WORK/gtmp" \
        TRUSTED_SIGNERS_FILE="$WORK/signers.json" \
        bash "$SCRIPT" "$@" >"$WORK/out.txt" 2>"$WORK/err.log"
    RC=$?
}

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1 ($2)"
    FAILED=1
}
detail() { echo "終了コード ${RC} / 出力: $(head -c 600 "$WORK/out.txt") / 標準エラー: $(head -c 300 "$WORK/err.log")"; }

# 使い方: expect <説明> <終了コード> <1行目の result の値>
expect() {
    if [ "$RC" -eq "$2" ] && [ "$(sed -n 1p "$WORK/out.txt")" = "result=$3" ]; then pass "$1"; else fail "$1" "$(detail)"; fi
}

# 使い方: expect_line <説明> <行>。出力にその行がそのままある
expect_line() {
    if grep -qxF -- "$2" "$WORK/out.txt"; then pass "$1"; else fail "$1" "「$2」の行がありません / $(detail)"; fi
}

# 使い方: expect_detail <説明> <文字列>。2行目が detail= で始まり、その文字列を含む
expect_detail() {
    local second
    second=$(sed -n 2p "$WORK/out.txt")
    case "$second" in detail=*"$2"*) pass "$1" ;; *) fail "$1" "detail に「$2」がありません / $(detail)" ;; esac
}

# 使い方: expect_calls <説明> <grep の式> <回数>。スタブの記録に当たる行の数を比べる
expect_calls() {
    local n
    n=$(grep -c -- "$2" "$WORK/calls.log")
    if [ "$n" -eq "$3" ]; then pass "$1"; else fail "$1" "「$2」が ${n} 回(期待は $3 回)"; fi
}

markers() { grep -c '^<!-- ci-tool-cooldown-exception data=' "$WORK/out.txt"; }

# 使い方: expect_record <説明> <道具> <版> <公開日時> [確かめ方] [署名した者]。記録の目印の行が1つだけあり、
# その JSON が、道具と版と公開日時と所有者の指示の要約と署名の結果を持つ。
# 確かめ方の既定は gpg --verify、署名した者の既定はテストの信頼する鍵の指紋
expect_record() {
    local data
    data=$(sed -n 's/^<!-- ci-tool-cooldown-exception data=\([A-Za-z0-9+\/=]*\) -->$/\1/p' "$WORK/out.txt")
    if [ "$(markers)" -eq 1 ] && [ -n "$data" ] && perl -MJSON::PP -MMIME::Base64 -e '
        my ($b64, $tool, $ver, $pub, $own, $method, $signer) = @ARGV;
        utf8::decode($own);
        my $d = JSON::PP->new->utf8->decode(decode_base64($b64));
        my @k = sort keys %$d;
        my $e = $d->{entries}[0];
        my $s = $e->{signature};
        exit(("@k" eq "entries schema" && $d->{schema} == 1 && @{ $d->{entries} } == 1
            && $e->{tool} eq $tool && $e->{version} eq $ver && $e->{published_at} eq $pub
            && $e->{owner_instruction} eq $own
            && $s->{result} eq "verified" && $s->{method} eq $method && $s->{signer} eq $signer
            && $s->{checked_at} =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/) ? 0 : 1);
    ' "$data" "$2" "$3" "$4" "$INSTRUCTION" "${5:-gpg --verify}" "${6:-$FT}"; then
        pass "$1"
    else
        fail "$1" "記録の目印の行の JSON が違います / $(detail)"
    fi
}

RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        return 0
    fi
    return 1
}

# --- 場合(Node.js) ----------------------------------------------------------------------

if want node_ok; then
    reset
    PUB=$(at 3600)
    node_put "$PUB"
    run node "$V" "$INSTRUCTION"
    expect "Node.js の署名が合えば終了コード 0 になる" 0 verified
    expect_line "Node.js の署名が合えば本文の文が出る(道具)" "- 道具: Node.js"
    expect_line "Node.js の署名が合えば本文の文が出る(版)" "- 版: $V"
    expect_line "Node.js の署名が合えば本文の文が出る(公開日時は詰め直しのリリースの日時)" "- 公開日時: $PUB"
    expect_line "Node.js の署名が合えば本文の文が出る(72時間経っていない)" "- 公開から72時間: 経っていない(所有者の指示で、72時間待たずに入れる)"
    expect_line "Node.js の署名が合えば本文の文が出る(署名した者は主鍵の指紋)" "- 署名した者: $FT"
    expect_record "Node.js の署名が合えば記録の目印の行が出て、owner_instruction に3つ目の引数が入る" node "$V" "$PUB"
    expect_calls "Node.js の署名を、ネットワークを外したコンテナの gpg で確かめる" \
        "^DOCKER run --rm --network none .* kp-ci-tool-gpg:local sh -c " 1
    expect_calls "Node.js の署名を確かめる前に、gpg のコンテナのイメージを作る" "^DOCKER build -q -t kp-ci-tool-gpg:local " 1
    expect_calls "Node.js の取得の打ち切りは300秒" "^GET https://.* max-time=300$" 5
    expect_calls "Node.js の信頼する者の公開鍵を、指紋で鍵サーバから取る" \
        "^GET https://keyserver\.ubuntu\.com/pks/lookup?op=get&options=mr&search=0x${FT} " 1
    expect_calls "Node.js の公開日時を、詰め直しのリリースのタグで読む" \
        "^GH api repos/actions/node-versions/releases/tags/${TAG} --jq \.published_at$" 1
fi

if want node_old; then
    reset
    node_put "2020-01-02T03:04:05Z"
    run node "$V" "$INSTRUCTION"
    expect "公開から72時間経っていれば終了コード 0 になる" 0 verified
    expect_line "公開から72時間経っていれば、本文の文にそう出る" "- 公開から72時間: 経っている"
    if [ "$(markers)" -eq 0 ]; then pass "公開から72時間経っていれば記録の目印の行を出さない"; else fail "公開から72時間経っていれば記録の目印の行を出さない" "$(detail)"; fi
    reset
    node_put "$(at $((73 * 3600)))"
    run node "$V" "$INSTRUCTION"
    if [ "$RC" -eq 0 ] && [ "$(markers)" -eq 0 ]; then pass "公開から73時間なら記録の目印の行を出さない"; else fail "公開から73時間なら記録の目印の行を出さない" "$(detail)"; fi
    reset
    node_put "$(at $((71 * 3600)))"
    run node "$V" "$INSTRUCTION"
    if [ "$RC" -eq 0 ] && [ "$(markers)" -eq 1 ]; then pass "公開から71時間なら記録の目印の行を出す"; else fail "公開から71時間なら記録の目印の行を出す" "$(detail)"; fi
fi

if want node_badsig; then
    reset
    node_put "$(at 3600)"
    perl -pi -e 's/^1111/2111/' "$NODE_DIST/SHASUMS256.txt.asc"
    run node "$V" "$INSTRUCTION"
    expect "Node.js の署名が合わなければ終了コード 1 になる" 1 unverified
    expect_detail "Node.js の署名が合わなければ理由が出る" "SHASUMS256.txt.asc の署名が、中身と合いません。"
    expect_calls "Node.js の署名が合わなければ tarball を取らない" "\.tar\.gz max-time" 0
fi

if want node_nosig; then
    reset
    node_put "$(at 3600)"
    rm -f "$NODE_DIST/SHASUMS256.txt.asc"
    run node "$V" "$INSTRUCTION"
    expect "Node.js の署名が無ければ終了コード 1 になる" 1 unverified
    expect_detail "Node.js の署名が無ければ理由が出る" "署名(SHASUMS256.txt.asc)がありません。"
    reset
    node_put "$(at 3600)"
    printf 'not a signature\n' >"$NODE_DIST/SHASUMS256.txt.asc"
    run node "$V" "$INSTRUCTION"
    expect "SHASUMS256.txt.asc に署名が入っていなければ終了コード 1 になる" 1 unverified
    expect_detail "SHASUMS256.txt.asc に署名が入っていなければ理由が出る" "SHASUMS256.txt.asc に署名がありません。"
fi

if want node_untrusted; then
    reset
    node_put "$(at 3600)" "$FO"
    run node "$V" "$INSTRUCTION"
    expect "Node.js の署名した者が信頼する者と違えば終了コード 1 になる" 1 unverified
    expect_detail "Node.js の署名した者が信頼する者と違えば理由が出る" "信頼する者の誰とも違います。"
    reset
    node_put "$(at 3600)" "$FO"
    publish_key "$FO" "$FT"
    run node "$V" "$INSTRUCTION"
    expect "鍵サーバが信頼する者の指紋に別の鍵を返し、その鍵で署名されていれば終了コード 1 になる" 1 unverified
    expect_detail "鍵サーバが別の鍵を返したときは、署名した者の指紋が理由に出る" "の署名した者(${FO})が、信頼する者の誰とも違います。"
fi

if want node_fetch_fail; then
    reset
    node_put "$(at 3600)"
    : >"$NODE_DIST/SHASUMS256.txt.asc.fail"
    run node "$V" "$INSTRUCTION"
    expect "Node.js の署名を取得できなければ終了コード 2 になる" 2 unknown
    expect_detail "Node.js の署名を取得できなければ理由が出る" "SHASUMS256.txt.asc を取れませんでした(HTTP 500)。"
    expect_calls "Node.js の署名の取得は1回だけ再試行する" "SHASUMS256\.txt\.asc max-time=300$" 2
    reset
    node_put "$(at 3600)"
    : >"$NODE_DIST/SHASUMS256.txt.asc.fail-once"
    run node "$V" "$INSTRUCTION"
    expect "Node.js の署名の取得が1回目だけ失敗すれば、再試行して終了コード 0 になる" 0 verified
    reset
    node_put "$(at 3600)"
    rm -f "$NODE_DIST/SHASUMS256.txt.asc" "$NODE_DIST/SHASUMS256.txt"
    run node "$V" "$INSTRUCTION"
    expect "Node.js の版が無ければ終了コード 2 になる" 2 unknown
    expect_detail "Node.js の版が無ければ理由が出る" "版が無いかもしれません。"
    reset
    node_put "$(at 3600)"
    : >"$REPACK.fail"
    run node "$V" "$INSTRUCTION"
    expect "詰め直しの tarball を取得できなければ終了コード 2 になる" 2 unknown
    reset
    node_put "$(at 3600)"
    : >"$STUB/gh.fail"
    run node "$V" "$INSTRUCTION"
    expect "詰め直しのリリースの公開日時を読めなければ終了コード 2 になる" 2 unknown
    expect_detail "詰め直しのリリースの公開日時を読めなければ理由が出る" "リリース ${TAG} の公開日時を読めませんでした。"
fi

if want node_key_fail; then
    reset
    node_put "$(at 3600)" "$FO"
    : >"$STUB/web/keyserver.ubuntu.com/keys/$FT.fail"
    run node "$V" "$INSTRUCTION"
    expect "信頼する者の公開鍵を取れず、署名を確かめられなければ終了コード 2 になる" 2 unknown
    expect_detail "信頼する者の公開鍵を取れなければ理由が出る" "信頼する者の公開鍵のうち 1 個を取れなかった"
fi

if want node_repack_diff; then
    reset
    node_put "$(at 3600)"
    tarball "$REPACK" "." "tampered node binary"
    run node "$V" "$INSTRUCTION"
    expect "Node.js の詰め直しの tarball の bin/node が違えば終了コード 1 になる" 1 unverified
    expect_detail "Node.js の詰め直しの tarball の bin/node が違えば理由が出る" "詰め直しの tarball の bin/node が、確かめた node-v${V}-linux-x64.tar.gz の bin/node と違います。"
fi

if want node_tarball_hash; then
    reset
    node_put "$(at 3600)"
    tarball "$NODE_DIST/node-v$V-linux-x64.tar.gz" "node-v$V-linux-x64" "other node binary"
    run node "$V" "$INSTRUCTION"
    expect "Node.js の tarball のハッシュが署名された値と違えば終了コード 1 になる" 1 unverified
    expect_detail "Node.js の tarball のハッシュが違えば理由が出る" "node-v${V}-linux-x64.tar.gz のハッシュが、署名された SHASUMS256.txt の値と違います。"
fi

if want node_manifest; then
    reset
    node_put "$(at 3600)"
    perl -pi -e 's/"version": "\Q'"$V"'\E"/"version": "0.0.0"/' \
        "$STUB/web/raw.githubusercontent.com/actions/node-versions/main/versions-manifest.json"
    run node "$V" "$INSTRUCTION"
    expect "versions-manifest.json にその版が無ければ終了コード 2 になる" 2 unknown
    expect_detail "versions-manifest.json にその版が無ければ理由が出る" "linux の x64 の tarball がありません。"
    reset
    node_put "$(at 3600)"
    perl -pi -e 's{https://github.com/actions/node-versions/releases/download/\Q'"$TAG"'\E/node-\Q'"$V"'\E-linux-x64}{https://example.invalid/node-'"$V"'-linux-x64}' \
        "$STUB/web/raw.githubusercontent.com/actions/node-versions/main/versions-manifest.json"
    run node "$V" "$INSTRUCTION"
    expect "versions-manifest.json の URL が actions/node-versions のリリースでなければ終了コード 2 になる" 2 unknown
    expect_calls "versions-manifest.json の URL が actions/node-versions のリリースでなければ取りに行かない" "example\.invalid" 0
fi

# --- 場合(Terraform) --------------------------------------------------------------------

if want terraform_ok; then
    reset
    PUB=$(at 7200 | sed 's/Z$/.607Z/')
    tf_put "$PUB"
    run terraform "$TF" "$INSTRUCTION"
    expect "Terraform の署名が合えば終了コード 0 になる" 0 verified
    expect_line "Terraform の署名が合えば本文の文が出る(道具)" "- 道具: Terraform"
    expect_line "Terraform の署名が合えば本文の文が出る(版)" "- 版: $TF"
    expect_line "Terraform の署名が合えば本文の文が出る(公開日時)" "- 公開日時: $PUB"
    expect_line "Terraform の署名が合えば本文の文が出る(署名した者は主鍵の指紋)" "- 署名した者: $FT"
    expect_record "Terraform の署名が合えば記録の目印の行が出て、owner_instruction に3つ目の引数が入る" terraform "$TF" "$PUB"
    expect_calls "Terraform の署名を、ネットワークを外したコンテナの gpg で確かめる" \
        "^DOCKER run --rm --network none .* kp-ci-tool-gpg:local sh -c " 1
    expect_calls "Terraform の取得の打ち切りは300秒" "^GET https://.* max-time=300$" 5
    reset
    tf_put "2020-01-02T12:04:05+09:00"
    run terraform "$TF" "$INSTRUCTION"
    if [ "$RC" -eq 0 ] && [ "$(markers)" -eq 0 ]; then pass "Terraform の公開から72時間経っていれば記録の目印の行を出さない"; else fail "Terraform の公開から72時間経っていれば記録の目印の行を出さない" "$(detail)"; fi
    reset
    tf_put "$(perl -MPOSIX -e 'print strftime("%Y-%m-%dT%H:%M:%S+09:00", gmtime(time - 80 * 3600 + 9 * 3600))')"
    run terraform "$TF" "$INSTRUCTION"
    if [ "$RC" -eq 0 ] && [ "$(markers)" -eq 0 ]; then pass "公開日時の時差(+09:00)を引いて、80時間前の公開を72時間経っているとみなす"; else fail "公開日時の時差(+09:00)を引いて、80時間前の公開を72時間経っているとみなす" "$(detail)"; fi
fi

if want terraform_badsig; then
    reset
    tf_put "$(at 3600)"
    perl -pi -e 's/^2222/3222/' "$TF_DIST/terraform_${TF}_SHA256SUMS"
    run terraform "$TF" "$INSTRUCTION"
    expect "Terraform の署名が合わなければ終了コード 1 になる" 1 unverified
    expect_detail "Terraform の署名が合わなければ理由が出る" "terraform_${TF}_SHA256SUMS.sig の署名が、中身と合いません。"
fi

if want terraform_nosig; then
    reset
    tf_put "$(at 3600)"
    rm -f "$TF_DIST/terraform_${TF}_SHA256SUMS.sig"
    run terraform "$TF" "$INSTRUCTION"
    expect "Terraform の署名が無ければ終了コード 1 になる" 1 unverified
    expect_detail "Terraform の署名が無ければ理由が出る" "署名(terraform_${TF}_SHA256SUMS.sig)がありません。"
fi

if want terraform_untrusted; then
    reset
    tf_put "$(at 3600)" "$FO"
    run terraform "$TF" "$INSTRUCTION"
    expect "Terraform の署名した者が信頼する者と違えば終了コード 1 になる" 1 unverified
    expect_detail "Terraform の署名した者が信頼する者と違えば理由が出る" "信頼する者の誰とも違います。"
fi

if want terraform_zip_hash; then
    reset
    tf_put "$(at 3600)"
    printf 'other zip' >"$TF_DIST/terraform_${TF}_linux_amd64.zip"
    run terraform "$TF" "$INSTRUCTION"
    expect "Terraform の zip のハッシュが署名された値と違えば終了コード 1 になる" 1 unverified
    expect_detail "Terraform の zip のハッシュが違えば理由が出る" "terraform_${TF}_linux_amd64.zip のハッシュが、署名された terraform_${TF}_SHA256SUMS の値と違います。"
fi

if want terraform_fetch_fail; then
    reset
    tf_put "$(at 3600)"
    : >"$TF_DIST/terraform_${TF}_SHA256SUMS.fail"
    run terraform "$TF" "$INSTRUCTION"
    expect "Terraform の SHA256SUMS を取得できなければ終了コード 2 になる" 2 unknown
    expect_detail "Terraform の SHA256SUMS を取得できなければ理由が出る" "terraform_${TF}_SHA256SUMS を取れませんでした(HTTP 500)"
    reset
    tf_put "$(at 3600)"
    : >"$TF_DIST/terraform_${TF}_SHA256SUMS.sig.fail"
    run terraform "$TF" "$INSTRUCTION"
    expect "Terraform の署名を取得できなければ終了コード 2 になる" 2 unknown
    reset
    tf_put "$(at 3600)"
    printf '{"name":"terraform"}\n' >"$STUB/web/api.releases.hashicorp.com/v1/releases/terraform/$TF"
    run terraform "$TF" "$INSTRUCTION"
    expect "Terraform の公開日時を読めなければ終了コード 2 になる" 2 unknown
    expect_detail "Terraform の公開日時を読めなければ理由が出る" "公開日時を読めませんでした。"
fi

# --- 場合(共通) -------------------------------------------------------------------------

# --- 場合(Trivy) ------------------------------------------------------------------------

COSIGN_RE="ghcr\.io/sigstore/cosign/cosign@sha256:[0-9a-f]\{64\}"

if want trivy_ok; then
    reset
    PUB=$(at 3600)
    trivy_put "$PUB"
    run trivy "$TV" "$INSTRUCTION"
    expect "Trivy の署名が合えば終了コード 0 になる" 0 verified
    expect_line "Trivy の署名が合えば本文の文が出る(道具)" "- 道具: Trivy"
    expect_line "Trivy の署名が合えば本文の文が出る(版)" "- 版: $TV"
    expect_line "Trivy の署名が合えば本文の文が出る(公開日時はリリースの日時)" "- 公開日時: $PUB"
    expect_line "Trivy の署名が合えば本文の文が出る(署名した者は身元)" "- 署名した者: $TRIVY_IDENTITY"
    expect_record "Trivy の署名が合えば記録の目印の行が出て、owner_instruction に3つ目の引数が入る" \
        trivy "$TV" "$PUB" "cosign verify-blob" "$TRIVY_IDENTITY"
    expect_calls "cosign に渡す身元が identity_template の {version} に版を入れたものになる" \
        "^DOCKER run --rm -v .*:/work:ro -w /work ${COSIGN_RE} verify-blob --bundle /work/trivy\.sigstore\.json --certificate-oidc-issuer ${TRIVY_ISSUER} --certificate-identity https://github\.com/example/trivy/\.github/workflows/release\.yaml@refs/tags/v${TV} /work/trivy\.tar\.gz$" 1
    expect_calls "Trivy の署名を確かめる前に、digest で固定した cosign のイメージを取る" "^DOCKER pull -q ${COSIGN_RE}$" 1
    expect_calls "Trivy では gpg のコンテナのイメージを作らない" "^DOCKER build " 0
    expect_calls "Trivy の取得の打ち切りは300秒" "^GET https://github\.com/aquasecurity/trivy/releases/download/v${TV}/.* max-time=300$" 2
    expect_calls "Trivy の公開日時を、リリースのタグで読む" \
        "^GH api repos/aquasecurity/trivy/releases/tags/v${TV} --jq \.published_at$" 1
fi

if want trivy_badsig; then
    reset
    trivy_put "$(at 3600)"
    printf 'changed' >>"$TRIVY_DIST/$TRIVY_FILE"
    run trivy "$TV" "$INSTRUCTION"
    expect "cosign の検証が失敗したら終了コード 1 になる" 1 unverified
    expect_detail "cosign の検証が失敗したら理由と cosign の出力が出る" \
        "の署名として確かめられませんでした。cosign の出力: Error: invalid signature when validating ASN.1 encoded signature"
    reset
    trivy_put "$(at 3600)" "https://github.com/attacker/trivy/.github/workflows/release.yaml@refs/tags/v$TV"
    run trivy "$TV" "$INSTRUCTION"
    expect "署名の身元が信頼する身元と違えば終了コード 1 になる" 1 unverified
    expect_detail "署名の身元が信頼する身元と違えば理由が出る" "no matching CertificateIdentity found"
    reset
    trivy_put "$(at 3600)" "" "https://other-issuer.example.invalid"
    run trivy "$TV" "$INSTRUCTION"
    expect "署名の発行者が信頼する発行者と違えば終了コード 1 になる" 1 unverified
    reset
    trivy_put "$(at 3600)"
    : >"$STUB/cosign.fail"
    run trivy "$TV" "$INSTRUCTION"
    expect "cosign が信頼の起点を取れずに失敗しても verified にならず終了コード 1 になる" 1 unverified
fi

if want trivy_nosig; then
    reset
    trivy_put "$(at 3600)"
    rm -f "$TRIVY_DIST/$TRIVY_FILE.sigstore.json"
    run trivy "$TV" "$INSTRUCTION"
    expect "Trivy の .sigstore.json が無ければ終了コード 1 になる" 1 unverified
    expect_detail "Trivy の .sigstore.json が無ければ理由が出る" "${TRIVY_FILE} に、署名(${TRIVY_FILE}.sigstore.json)がありません。"
    expect_calls "Trivy の .sigstore.json が無ければ tarball を取らない" "\.tar\.gz max-time" 0
fi

if want trivy_fetch_fail; then
    reset
    trivy_put "$(at 3600)"
    : >"$TRIVY_DIST/$TRIVY_FILE.sigstore.json.fail"
    run trivy "$TV" "$INSTRUCTION"
    expect "Trivy の .sigstore.json を取得できなければ終了コード 2 になる" 2 unknown
    expect_detail "Trivy の .sigstore.json を取得できなければ理由が出る" "${TRIVY_FILE}.sigstore.json を取れませんでした(HTTP 500)。"
    expect_calls "Trivy の .sigstore.json の取得は1回だけやり直す" "\.sigstore\.json max-time" 2
    reset
    trivy_put "$(at 3600)"
    : >"$TRIVY_DIST/$TRIVY_FILE.fail"
    run trivy "$TV" "$INSTRUCTION"
    expect "Trivy の tarball を取得できなければ終了コード 2 になる" 2 unknown
    reset
    trivy_put "$(at 3600)"
    rm -f "$STUB/gh/aquasecurity/trivy/v$TV"
    run trivy "$TV" "$INSTRUCTION"
    expect "Trivy のリリースの公開日時を読めなければ終了コード 2 になる" 2 unknown
    expect_detail "Trivy のリリースの公開日時を読めなければ理由が出る" "aquasecurity/trivy のリリース v${TV} の公開日時を読めませんでした。"
    reset
    trivy_put "$(at 3600)"
    : >"$STUB/gh/aquasecurity/trivy/v$TV"
    run trivy "$TV" "$INSTRUCTION"
    expect "Trivy のリリースの公開日時が空なら終了コード 2 になる" 2 unknown
    expect_detail "Trivy のリリースの公開日時が空なら理由が出る" "aquasecurity/trivy のリリース v${TV} の公開日時を読めませんでした。"
    reset
    trivy_put "$(at 3600)"
    : >"$STUB/docker.fail"
    run trivy "$TV" "$INSTRUCTION"
    expect "cosign のイメージを取れなければ終了コード 2 になる" 2 unknown
    expect_detail "cosign のイメージを取れなければ理由が出る" "cosign のコンテナのイメージを取れませんでした。"
    expect_calls "cosign のイメージを取れなければ何も取りに行かない" "^GET " 0
    reset
    trivy_put "$(at 3600)"
    : >"$STUB/docker-run.fail"
    run trivy "$TV" "$INSTRUCTION"
    expect "cosign のコンテナを動かせなければ終了コード 2 になる" 2 unknown
    expect_detail "cosign のコンテナを動かせなければ理由が出る" "cosign のコンテナを動かせませんでした。"
fi

if want trivy_signers; then
    reset
    trivy_put "$(at 3600)"
    perl -pe 's/\{version\}//' "$WORK/signers.json" >"$WORK/bad-signers.json"
    PATH="$WORK/bin:$PATH" STUB_DIR="$STUB" STUB_CALLS="$WORK/calls.log" STUB_TMP="$WORK/gtmp" \
        TRUSTED_SIGNERS_FILE="$WORK/bad-signers.json" bash "$SCRIPT" trivy "$TV" "$INSTRUCTION" >"$WORK/out.txt" 2>"$WORK/err.log"
    RC=$?
    expect "identity_template に {version} が無ければ終了コード 2 になる" 2 unknown
    expect_detail "identity_template に {version} が無ければ理由が出る" "trivy の identity_template を読めませんでした"
fi

# --- 場合(Codex CLI) --------------------------------------------------------------------

if want codex_ok; then
    reset
    PUB=$(at 3600)
    codex_put "$PUB"
    run codex "$CV" "$INSTRUCTION"
    expect "Codex CLI の2つの tgz の来歴が合えば終了コード 0 になる" 0 verified
    expect_line "Codex CLI の来歴が合えば本文の文が出る(道具)" "- 道具: Codex CLI"
    expect_line "Codex CLI の来歴が合えば本文の文が出る(版)" "- 版: $CV"
    expect_line "Codex CLI の来歴が合えば本文の文が出る(公開日時は部品の文書の time の値)" "- 公開日時: $PUB"
    expect_line "Codex CLI の来歴が合えば本文の文が出る(署名した者は1つ目の部品の証明書の身元)" "- 署名した者: $CODEX_SAN"
    expect_line "Codex CLI の来歴が合えば本文の文が出る(確かめ方)" \
        "- 確かめ方: npm の registry の @openai/codex@${CV} と @openai/codex@${CV}-linux-x64 の tgz の来歴を gh で確かめた(gh attestation verify)"
    expect_record "Codex CLI の2つの tgz の来歴が合えば記録の目印の行が出て、owner_instruction に3つ目の引数が入る" \
        codex "$CV" "$PUB" "gh attestation verify" "$CODEX_SAN"
    expect_calls "Codex CLI の2つの tgz を、信頼する repo と signer_workflow で確かめる" \
        "^GH attestation verify .*/codex-[12]\.tgz --bundle .*/codex-[12]\.bundle\.json --digest-alg sha512 --repo ${CODEX_REPO} --signer-workflow ${CODEX_WORKFLOW} " 2
    expect_calls "Codex CLI の来歴は、名前の / を %2f にして取る" \
        "^GET https://registry\.npmjs\.org/-/npm/v1/attestations/@openai%2fcodex@${CV}\(-linux-x64\)\? " 2
    expect_calls "Codex CLI の取得の打ち切りは300秒" "^GET https://registry\.npmjs\.org/.* max-time=300$" 7
    expect_calls "Codex CLI では docker を使わない" "^DOCKER " 0
fi

if want codex_badprov; then
    for n in 1 2; do
        reset
        codex_put "$(at 3600)"
        p="$CV"
        [ "$n" -eq 2 ] && p="$CV-linux-x64"
        perl -pi -e 's/"repo": "example\/codex"/"repo": "attacker\/codex"/' "$REG/-/npm/v1/attestations/@openai%2fcodex@$p"
        run codex "$CV" "$INSTRUCTION"
        expect "Codex CLI の ${n} つ目の tgz の来歴が合わなければ終了コード 1 になる" 1 unverified
        expect_detail "Codex CLI の ${n} つ目の tgz の来歴が合わなければ理由と gh の出力が出る" \
            "@openai/codex@${p} の来歴を、${CODEX_WORKFLOW} の署名として確かめられませんでした。gh の出力: Error: verifying with issuer"
    done
fi

if want codex_noprov; then
    reset
    codex_put "$(at 3600)"
    rm -f "$REG/-/npm/v1/attestations/@openai%2fcodex@$CV-linux-x64"
    run codex "$CV" "$INSTRUCTION"
    expect "Codex CLI の tgz に来歴が無ければ終了コード 1 になる" 1 unverified
    expect_detail "Codex CLI の tgz に来歴が無ければ理由が出る" "@openai/codex@${CV}-linux-x64 に、来歴がありません。"
    reset
    codex_put "$(at 3600)"
    perl -0pi -e 's/,\s*\{"predicateType": "https:\/\/slsa\.dev\/provenance\/v1".*\]/\n]/s' "$REG/-/npm/v1/attestations/@openai%2fcodex@$CV"
    run codex "$CV" "$INSTRUCTION"
    expect "Codex CLI の来歴に SLSA の来歴が無ければ終了コード 1 になる" 1 unverified
    expect_detail "Codex CLI の来歴に SLSA の来歴が無ければ理由が出る" "@openai/codex@${CV} の来歴に、SLSA の来歴がありません。"
fi

if want codex_integrity; then
    reset
    codex_put "$(at 3600)"
    printf 'changed' >>"$REG/@openai/codex/-/codex-$CV.tgz"
    run codex "$CV" "$INSTRUCTION"
    expect "Codex CLI の tgz が部品の文書のハッシュと違えば終了コード 1 になる" 1 unverified
    expect_detail "Codex CLI の tgz が部品の文書のハッシュと違えば理由が出る" "@openai/codex@${CV} の tgz のハッシュが、部品の文書の値と違います。"
    reset
    codex_put "$(at 3600)"
    perl -pi -e 's/registry\.npmjs\.org\/\@openai/registry.example.invalid\/\@openai/' "$REG/@openai/codex/$CV"
    run codex "$CV" "$INSTRUCTION"
    expect "Codex CLI の tgz の URL が npm の registry でなければ終了コード 2 になる" 2 unknown
    expect_calls "Codex CLI の tgz の URL が npm の registry でなければ取りに行かない" "registry\.example\.invalid" 0
fi

if want codex_fetch_fail; then
    reset
    codex_put "$(at 3600)"
    : >"$REG/@openai/codex/$CV-linux-x64.fail"
    run codex "$CV" "$INSTRUCTION"
    expect "Codex CLI の部品の文書を取得できなければ終了コード 2 になる" 2 unknown
    reset
    codex_put "$(at 3600)"
    : >"$REG/-/npm/v1/attestations/@openai%2fcodex@$CV.fail"
    run codex "$CV" "$INSTRUCTION"
    expect "Codex CLI の来歴を取得できなければ終了コード 2 になる" 2 unknown
    expect_detail "Codex CLI の来歴を取得できなければ理由が出る" "@openai/codex@${CV} の来歴を取れませんでした(HTTP 500)。"
    reset
    codex_put "$(at 3600)"
    : >"$REG/@openai/codex/-/codex-$CV.tgz.fail"
    run codex "$CV" "$INSTRUCTION"
    expect "Codex CLI の tgz を取得できなければ終了コード 2 になる" 2 unknown
    reset
    codex_put "$(at 3600)"
    printf '{"name":"@openai/codex","time":{}}\n' >"$REG/@openai%2fcodex"
    run codex "$CV" "$INSTRUCTION"
    expect "Codex CLI の公開日時を読めなければ終了コード 2 になる" 2 unknown
    expect_detail "Codex CLI の公開日時を読めなければ理由が出る" "@openai/codex の部品の文書から、${CV} の公開日時を読めませんでした。"
fi

if want docker_fail; then
    reset
    node_put "$(at 3600)"
    : >"$STUB/docker.fail"
    run node "$V" "$INSTRUCTION"
    expect "gpg のコンテナのイメージを作れなければ終了コード 2 になる" 2 unknown
    expect_detail "gpg のコンテナのイメージを作れなければ理由が出る" "Docker が動いているか確かめてください。"
    expect_calls "gpg のコンテナのイメージを作れなければ何も取りに行かない" "^GET " 0
fi

if want args; then
    reset
    node_put "$(at 3600)"
    run node "$V"
    expect "3つ目の引数が無ければ終了コード 2 と result=unknown になる" 2 unknown
    run node "$V" ""
    expect "3つ目の引数が空なら終了コード 2 と result=unknown になる" 2 unknown
    run python "$V" "$INSTRUCTION"
    expect "知らない道具なら終了コード 2 と result=unknown になる" 2 unknown
    expect_detail "知らない道具なら使い方が出る" "使い方: verify-ci-tool.sh <node|trivy|codex|terraform> <版> <所有者の指示の要約>"
    run node "24.99.1/../x" "$INSTRUCTION"
    expect "版に使えない文字があれば終了コード 2 と result=unknown になる" 2 unknown
    expect_calls "引数の誤りなら何も取りに行かない" "^GET \|^DOCKER " 0
    printf '{"node":{"fingerprints":["abc"]}}\n' >"$WORK/bad-signers.json"
    PATH="$WORK/bin:$PATH" STUB_DIR="$STUB" STUB_CALLS="$WORK/calls.log" STUB_TMP="$WORK/gtmp" \
        TRUSTED_SIGNERS_FILE="$WORK/bad-signers.json" bash "$SCRIPT" node "$V" "$INSTRUCTION" >"$WORK/out.txt" 2>"$WORK/err.log"
    RC=$?
    expect "信頼する署名した者のファイルの指紋の形が違えば終了コード 2 になる" 2 unknown
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    FAILED=1
fi

exit "$FAILED"
