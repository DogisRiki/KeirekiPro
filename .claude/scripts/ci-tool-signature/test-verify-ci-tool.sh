#!/usr/bin/env bash
# =====================================================================
# verify-ci-tool.sh の自動テスト(Claude が Git Bash で流す)
#
# docker と curl と gh をスタブし、Node.js と Terraform の版の確かめ方と、確かめられないときの
# 扱いを検証する。署名は、テストの中で作った使い捨ての鍵で作り、その鍵の指紋を
# TRUSTED_SIGNERS_FILE で渡す。docker のスタブは、コンテナの代わりに、この PC の gpg で
# 同じ手順を動かす。配布物の並びは、2026-11-02 に nodejs.org と actions/node-versions と
# releases.hashicorp.com から取った答えの形をもとにしてある。
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
#   build: $STUB_DIR/docker.fail があれば終了コード 1
#   run: -v <フォルダ>:/work のフォルダを読み、イメージの名前より後ろの引数の /work を
#     そのフォルダに置き換えて、この PC で動かす
cat >"$WORK/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "DOCKER $*" >>"${STUB_CALLS:?}"
cmd="$1"
shift
case "$cmd" in
build)
    [ -e "${STUB_DIR:?}/docker.fail" ] && exit 1
    echo "sha256:0"
    exit 0
    ;;
run)
    host=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --rm) shift ;;
        --network | --user | -w) shift 2 ;;
        -v) host="${2%:/work}"; shift 2 ;;
        *) break ;;
        esac
    done
    [ -n "$host" ] || exit 125
    shift
    args=()
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
#   api repos/actions/node-versions/releases/tags/<タグ> --jq .published_at: $STUB_DIR/gh/<タグ> を出す。
#   ファイルが無いか、$STUB_DIR/gh.fail があれば終了コード 1
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "GH $*" >>"${STUB_CALLS:?}"
[ -e "${STUB_DIR:?}/gh.fail" ] && { echo "HTTP 500" >&2; exit 1; }
case "$1 $2" in
"api repos/actions/node-versions/releases/tags/"*)
    f="${STUB_DIR}/gh/${2##*/tags/}"
    [ -f "$f" ] || { echo "HTTP 404" >&2; exit 1; }
    cat "$f"
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
printf '{"node":{"fingerprints":["%s"],"locations":[]},"terraform":{"fingerprints":["%s"],"locations":[]}}\n' \
    "$FT" "$FT" >"$WORK/signers.json"

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
    printf '%s\n' "$1" >"$STUB/gh/$TAG"
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
    rm -rf "${STUB:?}"/web/* "$STUB"/gh/* "$STUB/gh.fail" "$STUB/docker.fail"
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

# 使い方: expect_record <説明> <道具> <版> <公開日時>。記録の目印の行が1つだけあり、
# その JSON が、道具と版と公開日時と所有者の指示の要約と署名の結果を持つ
expect_record() {
    local data
    data=$(sed -n 's/^<!-- ci-tool-cooldown-exception data=\([A-Za-z0-9+\/=]*\) -->$/\1/p' "$WORK/out.txt")
    if [ "$(markers)" -eq 1 ] && [ -n "$data" ] && perl -MJSON::PP -MMIME::Base64 -e '
        my ($b64, $tool, $ver, $pub, $own, $signer) = @ARGV;
        utf8::decode($own);
        my $d = JSON::PP->new->utf8->decode(decode_base64($b64));
        my @k = sort keys %$d;
        my $e = $d->{entries}[0];
        my $s = $e->{signature};
        exit(("@k" eq "entries schema" && $d->{schema} == 1 && @{ $d->{entries} } == 1
            && $e->{tool} eq $tool && $e->{version} eq $ver && $e->{published_at} eq $pub
            && $e->{owner_instruction} eq $own
            && $s->{result} eq "verified" && $s->{method} eq "gpg --verify" && $s->{signer} eq $signer
            && $s->{checked_at} =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/) ? 0 : 1);
    ' "$data" "$2" "$3" "$4" "$INSTRUCTION" "$FT"; then
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
    expect_detail "知らない道具なら使い方が出る" "使い方: verify-ci-tool.sh <node|terraform> <版> <所有者の指示の要約>"
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
