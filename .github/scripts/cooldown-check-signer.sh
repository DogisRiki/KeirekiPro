#!/usr/bin/env bash
# =====================================================================
# 1つの部品の前の版と新しい版の、署名した者を比べる
# (check-dependency-cooldown.sh から呼ばれる)
#
# 判定: same(同じ者) / no-prior-signature(前の版に署名が無い) / different(違う者) /
#       no-new-signature(前の版に署名があり、新しい版に無い) / unknown(調べられなかった)。
#       変更を止めるかどうかは、このスクリプトではなく呼ぶ側が決める。
#
# npm の署名した者:
#   registry の署名(dist.signatures)と publish attestation は、どの部品にも
#   registry の同じ鍵で付くので、公開元を見分けられない。このスクリプトはこの2つを読まず、
#   SLSA の来歴(predicateType が https://slsa.dev/provenance/v1)だけを署名とみなす。
#   署名した者は、来歴の証明書の3つの拡張の組である。
#     1.3.6.1.4.1.57264.1.8  OIDC の発行元
#     1.3.6.1.4.1.57264.1.15 元のリポジトリの ID
#     1.3.6.1.4.1.57264.1.18 組み立ての設定の URI の @ より前の部分
#   @ より後ろはタグごとに変わるので比べない。
#
# maven の署名した者:
#   <配布元>/<group のパス>/<artifact>/<版>/<artifact>-<版>.pom.asc を署名とする。配布元は、
#   .pom を Maven Central で探し、404 なら Gradle Plugin Portal で探して、見つかった方にする。
#   Gradle Plugin Portal は別の URL へ転送して返すので、転送を追う。
#   公開鍵は、署名の発行者の指紋で鍵サーバから取る。発行者の指紋が無い署名(postgresql など)は、
#   発行者の鍵 ID で取る。鍵サーバが同じ鍵 ID の別の鍵を返しても、署名を検証できた鍵の主鍵の
#   指紋で比べるので、別の者を同じ者とみなさない。
#   署名した者は、gpg --verify の VALIDSIG の行の最後の欄にある主鍵の指紋である。
#   公開元が副鍵を替えても、主鍵が同じなら同じ者とみなす。
#   鍵は版ごとの使い捨ての GNUPGHOME に入れる。
#
# なぜ証明書を2か所から読むのか:
#   bundle の版 0.3 は verificationMaterial.certificate に、版 0.2 は
#   verificationMaterial.x509CertificateChain.certificates[0] に証明書を置く。
#   2026-11-02 に取った sigstore@3.0.0 と 3.1.0 の来歴は版 0.2 だった。
#
# なぜ3つの欄が同じでも gh attestation verify を通すのか:
#   証明書の欄は bundle に書かれた値であり、bundle が tgz の中身と合っていて、
#   正しく署名されていることは、検証しないと分からない。検証できなければ unknown にする。
#   検証の失敗は署名が中身と合わないことを含むので、different ではなく unknown にする。
#
# 問い合わせ: 打ち切りは60秒(tgz は300秒)、再試行は1回。404 は再試行しない。
#
# テスト: .github/scripts/tests/test-cooldown-check-signer.sh
# 使い方: cooldown-check-signer.sh <ecosystem> <名前> <前の版> <新しい版>
#   出力(標準出力): 1行目 result=<結果>、2行目 detail=<理由の説明>
#   <名前> は、npm なら部品の名前、maven なら <groupId>:<artifactId>
#   環境変数 NPM_REGISTRY_BASE(既定 https://registry.npmjs.org)、
#     MAVEN_CENTRAL_BASE(既定 https://repo1.maven.org/maven2)、
#     PLUGIN_PORTAL_BASE(既定 https://plugins.gradle.org/m2)、
#     KEYSERVER_BASE(既定 https://keyserver.ubuntu.com)
#   終了コード 0 = 判定できた(unknown を含む) / 2 = 引数の誤り
# =====================================================================
set -euo pipefail

usage() {
    echo "使い方: cooldown-check-signer.sh <ecosystem> <名前> <前の版> <新しい版>" >&2
    exit 2
}
[ "$#" -eq 4 ] || usage
ECO="$1"
NAME="$2"
PREV="$3"
NEW="$4"
[ -n "$NAME" ] && [ -n "$PREV" ] && [ -n "$NEW" ] || usage

NPM="${NPM_REGISTRY_BASE:-https://registry.npmjs.org}"
MAVEN_CENTRAL="${MAVEN_CENTRAL_BASE:-https://repo1.maven.org/maven2}"
PLUGIN_PORTAL="${PLUGIN_PORTAL_BASE:-https://plugins.gradle.org/m2}"
KEYSERVER="${KEYSERVER_BASE:-https://keyserver.ubuntu.com}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

answer() {
    echo "result=$1"
    echo "detail=$2"
    exit 0
}

# 使い方: fetch <URL> <答えのファイル> <打ち切りの秒>。HTTP の状態の番号を出す(取れなければ 000)
# 転送は追う(Gradle Plugin Portal は .pom と .pom.asc を別の URL へ転送して返す)
fetch() {
    local code attempt
    for attempt in 1 2; do
        code=$(curl -sSL --max-time "$3" -o "$2" -w '%{http_code}' "$1" 2>/dev/null) || code=000
        case "$code" in 200 | 404) break ;; esac
        echo "取得に失敗しました(${attempt}回目、HTTP ${code}): $1" >&2
    done
    echo "$code"
}

# --- npm ----------------------------------------------------------------------------

# 使い方: npm_provenance <版> <bundle を書くファイル>
# 戻り値 0 = SLSA の来歴がある / 1 = 無い(404 か、SLSA の来歴が無い) / 2 = 読めなかった
npm_provenance() {
    local code
    code=$(fetch "${NPM}/-/npm/v1/attestations/${NAME}@$1" "$TMP/att.json" 60)
    case "$code" in
    404) return 1 ;;
    200) ;;
    *) return 2 ;;
    esac
    jq -e '.attestations | type == "array"' "$TMP/att.json" >/dev/null 2>&1 || return 2
    jq -e -c 'first(.attestations[] | select(.predicateType == "https://slsa.dev/provenance/v1")
        | .bundle | select(type == "object"))' "$TMP/att.json" >"$2" 2>/dev/null || return 1
}

# 使い方: cert_ext <DER の証明書> <拡張の OID>。拡張の UTF8String の値を出す
# 拡張の値は OCTET STRING の中の UTF8String なので、OID の次の行の位置を -strparse で開く。
# 読む側は途中で終わらず最後まで読む(pipefail のもとで、書く側が SIGPIPE で終わらないように)
cert_ext() {
    local off
    off=$(openssl asn1parse -inform DER -in "$1" 2>/dev/null |
        awk -v oid=":$2" 'want && off == "" { split($0, a, ":"); off = a[1] + 0 }
            { want = 0 }
            /OBJECT/ && substr($0, length($0) - length(oid) + 1) == oid { want = 1 }
            END { print off }') || return 1
    [ -n "$off" ] || return 1
    openssl asn1parse -inform DER -in "$1" -strparse "$off" 2>/dev/null |
        perl -ne 'if (!$done && /^\s*0:d=0\s.*?prim:\s*UTF8STRING\s*:(.*)$/) { print $1; $done = 1 }'
}

# 使い方: npm_signer <bundle のファイル> <書くファイル>
# 4行を書く: OIDC の発行元 / 元のリポジトリの ID / 組み立ての設定の URI の @ より前 / 元のリポジトリの URI
npm_signer() {
    local der="$TMP/cert.der" issuer repo_id workflow repo_uri
    jq -r '.verificationMaterial
        | (.certificate.rawBytes // .x509CertificateChain.certificates[0].rawBytes // empty)' "$1" |
        base64 -d >"$der" 2>/dev/null || return 1
    [ -s "$der" ] || return 1
    issuer=$(cert_ext "$der" 1.3.6.1.4.1.57264.1.8) || return 1
    repo_id=$(cert_ext "$der" 1.3.6.1.4.1.57264.1.15) || return 1
    workflow=$(cert_ext "$der" 1.3.6.1.4.1.57264.1.18) || return 1
    repo_uri=$(cert_ext "$der" 1.3.6.1.4.1.57264.1.12) || return 1
    [ -n "$issuer" ] && [ -n "$repo_id" ] && [ -n "$workflow" ] && [ -n "$repo_uri" ] || return 1
    printf '%s\n%s\n%s\n%s\n' "$issuer" "$repo_id" "${workflow%%@*}" "$repo_uri" >"$2"
}

check_npm() {
    local rc=0 code tarball integrity digest repo
    npm_provenance "$PREV" "$TMP/prev.json" || rc=$?
    case "$rc" in
    1) answer no-prior-signature "前の版 ${PREV} に SLSA の来歴がありません。" ;;
    2) answer unknown "前の版 ${PREV} の来歴を registry から読めませんでした。" ;;
    esac
    rc=0
    npm_provenance "$NEW" "$TMP/new.json" || rc=$?
    case "$rc" in
    1) answer no-new-signature "前の版 ${PREV} に SLSA の来歴があり、新しい版 ${NEW} にはありません。" ;;
    2) answer unknown "新しい版 ${NEW} の来歴を registry から読めませんでした。" ;;
    esac

    npm_signer "$TMP/prev.json" "$TMP/prev.signer" ||
        answer unknown "前の版 ${PREV} の来歴の証明書から、署名した者の欄を読めませんでした。"
    npm_signer "$TMP/new.json" "$TMP/new.signer" ||
        answer unknown "新しい版 ${NEW} の来歴の証明書から、署名した者の欄を読めませんでした。"
    if [ "$(head -n 3 "$TMP/prev.signer")" != "$(head -n 3 "$TMP/new.signer")" ]; then
        answer different "来歴の証明書の、OIDC の発行元か、元のリポジトリの ID か、組み立ての設定が、前の版 ${PREV}($(head -n 3 "$TMP/prev.signer" | paste -sd ' ' -))と新しい版 ${NEW}($(head -n 3 "$TMP/new.signer" | paste -sd ' ' -))で違います。"
    fi

    # 新しい版の来歴を、tgz の中身と照らして検証する
    code=$(fetch "${NPM}/${NAME//\//%2f}" "$TMP/doc.json" 60)
    [ "$code" = 200 ] || answer unknown "部品の文書を registry から読めませんでした(HTTP ${code})。"
    tarball=$(jq -r --arg v "$NEW" '.versions[$v].dist.tarball // empty' "$TMP/doc.json" 2>/dev/null) || tarball=""
    integrity=$(jq -r --arg v "$NEW" '[(.versions[$v].dist.integrity // "") | splits(" +")
        | select(startswith("sha512-")) | ltrimstr("sha512-")] | first // empty' "$TMP/doc.json" 2>/dev/null) ||
        integrity=""
    [ -n "$tarball" ] && [ -n "$integrity" ] ||
        answer unknown "部品の文書に、新しい版 ${NEW} の tgz の URL か sha512 の dist.integrity がありません。"
    code=$(fetch "$tarball" "$TMP/pkg.tgz" 300)
    [ "$code" = 200 ] || answer unknown "新しい版 ${NEW} の tgz を取れませんでした(HTTP ${code})。"
    digest=$(openssl dgst -sha512 -binary "$TMP/pkg.tgz" | base64 | tr -d '\n')
    [ "$digest" = "$integrity" ] ||
        answer unknown "新しい版 ${NEW} の tgz が、部品の文書の dist.integrity と合いません。"

    repo=$(sed -n 4p "$TMP/prev.signer")
    repo="${repo#https://github.com/}"
    case "$repo" in
    */*) ;;
    *) answer unknown "前の版 ${PREV} の元のリポジトリが GitHub のリポジトリではありません。" ;;
    esac
    local attempt
    for attempt in 1 2; do
        if gh attestation verify "$TMP/pkg.tgz" --bundle "$TMP/new.json" \
            --digest-alg sha512 --repo "$repo" >"$TMP/verify.out" 2>&1; then
            answer same "来歴の証明書の、OIDC の発行元と元のリポジトリの ID と組み立ての設定が前の版 ${PREV} と同じで、新しい版 ${NEW} の来歴を ${repo} の来歴として検証できました。"
        fi
        echo "gh attestation verify に失敗しました(${attempt}回目): $(head -c 300 "$TMP/verify.out")" >&2
    done
    answer unknown "新しい版 ${NEW} の来歴を gh attestation verify で検証できませんでした。"
}

# --- maven --------------------------------------------------------------------------

# 使い方: maven_signer <版> <置き場所の名前>
# 戻り値 0 = 署名を検証でき、主鍵の指紋を $TMP/<置き場所の名前>/signer に書いた /
#        1 = 署名が無い(.pom.asc が 404) / 2 = 調べられなかった(理由を WHY に入れる)
maven_signer() {
    local v="$1" dir="$TMP/$2" path base="" b code issuer signer
    mkdir -m 700 "$dir" "$dir/gnupg"
    path="${GROUP//.//}/${ARTIFACT}/${v}/${ARTIFACT}-${v}.pom"
    for b in "$MAVEN_CENTRAL" "$PLUGIN_PORTAL"; do
        code=$(fetch "${b}/${path}" "$dir/pom" 60)
        case "$code" in
        200)
            base="$b"
            break
            ;;
        404) ;;
        *)
            WHY="版 ${v} の .pom を ${b} から読めませんでした(HTTP ${code})。"
            return 2
            ;;
        esac
    done
    if [ -z "$base" ]; then
        WHY="版 ${v} の .pom が、Maven Central にも Gradle Plugin Portal にもありません。"
        return 2
    fi
    code=$(fetch "${base}/${path}.asc" "$dir/asc" 60)
    case "$code" in
    404) return 1 ;;
    200) ;;
    *)
        WHY="版 ${v} の .pom.asc を ${base} から読めませんでした(HTTP ${code})。"
        return 2
        ;;
    esac

    # 発行者の指紋を読み、無ければ発行者の鍵 ID を読む
    gpg --batch --homedir "$dir/gnupg" --list-packets "$dir/asc" >"$dir/packets" 2>/dev/null || true
    issuer=$(awk 'match($0, /issuer fpr v[45] [0-9A-F]+/) {
            s = substr($0, RSTART, RLENGTH); sub(/.* /, "", s); print s; exit }' "$dir/packets")
    if [ -z "$issuer" ]; then
        issuer=$(awk '/^:signature packet:/ && match($0, /keyid [0-9A-F]+/) {
                s = substr($0, RSTART, RLENGTH); sub(/.* /, "", s); print s; exit }' "$dir/packets")
    fi
    if [ -z "$issuer" ]; then
        WHY="版 ${v} の .pom.asc から、発行者の指紋も鍵 ID も読めませんでした。"
        return 2
    fi

    code=$(fetch "${KEYSERVER}/pks/lookup?op=get&options=mr&search=0x${issuer}" "$dir/key" 60)
    if [ "$code" != 200 ]; then
        WHY="版 ${v} の署名の公開鍵(0x${issuer})を鍵サーバから取れませんでした(HTTP ${code})。"
        return 2
    fi
    if ! gpg --batch --homedir "$dir/gnupg" --import "$dir/key" >/dev/null 2>&1; then
        WHY="鍵サーバから取った公開鍵(0x${issuer})を読めませんでした。"
        return 2
    fi
    gpg --batch --homedir "$dir/gnupg" --status-fd 1 --verify "$dir/asc" "$dir/pom" >"$dir/status" 2>/dev/null || true
    signer=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { f = $NF } END { print f }' "$dir/status")
    case "$signer" in
    "" | *[!0-9A-F]*)
        WHY="版 ${v} の .pom.asc を、鍵サーバから取った公開鍵(0x${issuer})で検証できませんでした。"
        return 2
        ;;
    esac
    echo "$signer" >"$dir/signer"
}

check_maven() {
    local rc=0 prev new
    WHY=""
    maven_signer "$PREV" prev || rc=$?
    case "$rc" in
    1) answer no-prior-signature "前の版 ${PREV} に .pom.asc がありません。" ;;
    2) answer unknown "$WHY" ;;
    esac
    rc=0
    maven_signer "$NEW" new || rc=$?
    case "$rc" in
    1) answer no-new-signature "前の版 ${PREV} に .pom.asc があり、新しい版 ${NEW} にはありません。" ;;
    2) answer unknown "$WHY" ;;
    esac
    prev=$(cat "$TMP/prev/signer")
    new=$(cat "$TMP/new/signer")
    if [ "$prev" = "$new" ]; then
        answer same "前の版 ${PREV} と新しい版 ${NEW} の .pom.asc を、同じ主鍵(指紋 ${prev})の鍵で検証できました。"
    fi
    answer different "前の版 ${PREV} の .pom.asc の主鍵の指紋 ${prev} と、新しい版 ${NEW} の ${new} が違います。"
}

case "$ECO" in
npm) check_npm ;;
maven)
    GROUP="${NAME%%:*}"
    ARTIFACT="${NAME#*:}"
    case "$NAME" in
    *:*:* | :* | *: | *[!A-Za-z0-9._:-]*) usage ;;
    *:*) ;;
    *) usage ;;
    esac
    check_maven
    ;;
*) usage ;;
esac
