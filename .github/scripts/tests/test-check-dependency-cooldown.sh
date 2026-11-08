#!/usr/bin/env bash
# =====================================================================
# check-dependency-cooldown.sh の自動テスト(dependency-review CI から実行)
#
# gh と curl をスタブし、終了コードと報告の内容を検証する。
#   0 = 緑(通過) / 1 = 赤
#
# gh のスタブは、本体が渡す --jq のプログラムを実際の jq で評価する。
# 整形済みの結果を返すスタブにすると、対象の絞り込み(change_type と ecosystem)が
# 検証範囲から外れ、絞り込みを壊しても緑のままになる。
#
# 結合テスト: 本体が呼ぶスクリプト(警告に照らす、悪意のある部品の一覧に照らす、
# 署名した者を比べる、除外の欄を確かめる、記録のコメントを書き読む、コメントのライブラリ)は
# 本物を使い、外部のサービス(GitHub の API、npm の registry、OSV、配布元)だけをスタブにする。
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# 時刻は NOW_EPOCH で固定し、境界値を再現可能にする。
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。空ならすべてを流す。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-dependency-cooldown.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
RAN=0

# 判定の基準時刻。2026-01-10T00:00:00Z
NOW=1768003200
BASE_SHA="fedcba9876543210fedcba9876543210fedcba98"
HEAD_SHA="0123456789abcdef0123456789abcdef01234567"
OLD_HEAD="89abcdef0123456789abcdef0123456789abcdef"

mkdir -p "$WORK/bin" "$WORK/npm" "$WORK/alerts"

# --- gh のスタブ ---------------------------------------------------------------
# 呼ばれた引数は $STUB_GH_CALLS に1行で記録する。
# 比較の API: --jq の後ろに渡されたプログラムを実 jq で $STUB_COMPARE に適用する。
#   STUB_GH_FAIL が設定されているときは、標準出力を空にして異常終了する
#   (比較APIの応答が得られない状況の再現)。
# 警告の API(dependabot/alerts): STUB_ALERTS_FAIL があれば実際の gh と同じ形の
#   エラーの行を出して異常終了する。state=open の問い合わせ(--paginate --slurp)には、
#   $STUB_ALERTS_DIR/<ecosystem>_<URL のままの package>.json の警告を1ページで返し、
#   ファイルが無ければ空のページを返す。それ以外の問い合わせには空の一覧を返す。
# PR のコメント: 一覧には $STUB_COMMENTS を1ページで返し、書く呼び出しでは本文を
#   github-actions[bot] のコメントとして $STUB_COMMENTS に足す。
#   STUB_COMMENTS_FAIL に list か post を入れると、その呼び出しだけ失敗させる。
# 来歴の検証(gh attestation verify): STUB_ATTEST_FAIL があれば失敗する。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"${STUB_GH_CALLS:?}"
if [ "${1:-}" = attestation ]; then
    if [ -n "${STUB_ATTEST_FAIL:-}" ]; then
        echo "verification failed" >&2
        exit 1
    fi
    echo "Verification succeeded!"
    exit 0
fi
case " $* " in
" api --paginate repos/"*"/issues/"*"/comments ")
    if [ "${STUB_COMMENTS_FAIL:-}" = list ]; then
        echo "gh: Server Error (HTTP 500)" >&2
        exit 1
    fi
    cat "${STUB_COMMENTS:?}"
    exit 0
    ;;
" api -X POST repos/"*"/issues/"*"/comments -F body=@"*)
    if [ "${STUB_COMMENTS_FAIL:-}" = post ]; then
        echo "gh: Server Error (HTTP 500)" >&2
        exit 1
    fi
    body_file=""
    for a in "$@"; do
        case "$a" in body=@*) body_file="${a#body=@}" ;; esac
    done
    jq --rawfile b "$body_file" \
        '. + [{id: (length + 1), user: {login: "github-actions[bot]"}, created_at: "2026-01-10T00:00:00Z", body: $b}]' \
        "$STUB_COMMENTS" >"$STUB_COMMENTS.new" && mv "$STUB_COMMENTS.new" "$STUB_COMMENTS"
    echo '{"id": 999}'
    exit 0
    ;;
esac
for a in "$@"; do
    case "$a" in
    *dependabot/alerts*)
        if [ -n "${STUB_ALERTS_FAIL:-}" ]; then
            echo "gh: Resource not accessible by integration (HTTP 403)" >&2
            exit 1
        fi
        case "$a" in
        *state=open*)
            eco=""
            pkg=""
            IFS='&' read -ra kv <<<"${a#*\?}"
            for p in "${kv[@]}"; do
                case "$p" in
                ecosystem=*) eco="${p#ecosystem=}" ;;
                package=*) pkg="${p#package=}" ;;
                esac
            done
            f="${STUB_ALERTS_DIR:?}/${eco}_${pkg}.json"
            if [ -f "$f" ]; then
                printf '[['
                cat "$f"
                printf ']]\n'
            else
                echo '[[]]'
            fi
            ;;
        *) echo "[]" ;;
        esac
        exit 0
        ;;
    esac
done
# --include のときはヘッダだけを返す。スナップショット警告の有無を再現する。
for a in "$@"; do
    if [ "$a" = "--include" ]; then
        if [ -n "${STUB_HDR_FAIL:-}" ]; then
            echo "stub: header fetch failure" >&2
            exit 1
        fi
        echo "HTTP/2.0 200 OK"
        echo "Content-Type: application/json; charset=utf-8"
        printf 'X-Github-Dependency-Graph-Snapshot-Warnings: %s\r\n' "${STUB_WARN_B64:-}"
        echo ""
        exit 0
    fi
done
if [ -n "${STUB_GH_FAIL:-}" ]; then
    echo "stub: compare API failure" >&2
    exit 1
fi
prog=""
want=0
for a in "$@"; do
    if [ "$want" = 1 ]; then
        prog="$a"
        want=0
    fi
    [ "$a" = "--jq" ] && want=1
done
jq -r "$prog" "${STUB_COMPARE:?}"
STUB

# --- curl のスタブ ---------------------------------------------------------------
# maven: $STUB_TIMES の各行は "<pomパス>\t<Centralのコード>\t<Portalのコード>\t<Last-Modified>"。
# 該当行が無いパスは両方 404 を返す。
# npm: registry の URL の名前より後ろを <パス>.json として $STUB_NPM_DIR から探し、-o の先に写す。
#   部品の文書(<名前>)、来歴(-/npm/v1/attestations/<名前>@<版>)、tgz(<名前>/-/<ファイル>.tgz)の
#   どれも同じ形で探す。<パス>.code があればその HTTP の状態の番号を返す(000 は接続の失敗)。
# OSV: querybatch には、$STUB_OSV_MAL の各行 "<名前>@<版>\t<ID>" に当たる要素に、その ID を返す。
#   vulns/<ID> には、要約と URL を持つ項目を返す。要約は、STUB_OSV_SUMMARY があればその値にする。
#   STUB_OSV_FAIL があれば、どちらも 500 を返す。
# Go のモジュールの索引: URL の since の値を名前にしたファイルを $STUB_GOMOD_DIR から探し、-o の先に写す。
#   ファイルが無ければ、curl -f が HTTP の誤りの応答を受けたときと同じく 22 で終わる。
#   区間の長さ(GOMOD_INDEX_SEGMENT_HOURS)は73時間にして、索引を1つの区間で読ませる。
#   区間に分けて読む動きは test-lib-gomod-index.sh で確かめる。
# 呼ばれたURLは $STUB_CALLS に記録する。
cat >"$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
url=""
out=""
data=""
prev=""
for a in "$@"; do
    [ "$prev" = "-o" ] && out="$a"
    [ "$prev" = "--data-binary" ] && data="${a#@}"
    case "$a" in http*) url="$a" ;; esac
    prev="$a"
done
echo "$url" >>"${STUB_CALLS:?}"
case "$url" in
"${OSV_API_BASE}"/*)
    if [ -n "${STUB_OSV_FAIL:-}" ]; then
        echo '{}' >"${out:?}"
        printf 500
        exit 0
    fi
    case "$url" in
    */v1/querybatch)
        jq --rawfile mal "${STUB_OSV_MAL:?}" '
            ($mal | split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: .[1]})
                | from_entries) as $m
            | {results: [.queries[] | $m[.package.name + "@" + .version] as $id
                | if $id then {vulns: [{id: $id, modified: "2026-01-09T00:00:00Z"}]} else {} end]}' \
            "$data" >"${out:?}"
        ;;
    */v1/vulns/*)
        id="${url##*/}"
        jq -n --arg id "$id" --arg s "${STUB_OSV_SUMMARY:-}" '{id: $id,
            summary: (if $s != "" then $s else "Malicious code in package (" + $id + ")" end),
            references: [{type: "WEB", url: ("https://advisories.invalid/" + $id)}]}' >"${out:?}"
        ;;
    *) exit 6 ;;
    esac
    printf 200
    exit 0
    ;;
"${GOMOD_INDEX_BASE}"/*)
    since="${url#*since=}"
    since="${since%%&*}"
    if [ ! -f "${STUB_GOMOD_DIR:?}/${since}" ]; then
        echo "curl: (22) The requested URL returned error: 500" >&2
        exit 22
    fi
    cat "${STUB_GOMOD_DIR}/${since}" >"${out:?}"
    exit 0
    ;;
"${NPM_REGISTRY_BASE}"/*)
    key="${url#"${NPM_REGISTRY_BASE}"/}"
    code=404
    [ -f "${STUB_NPM_DIR:?}/${key}.json" ] && code=200
    [ -f "${STUB_NPM_DIR}/${key}.code" ] && code=$(cat "${STUB_NPM_DIR}/${key}.code")
    if [ "$code" = "000" ]; then exit 7; fi
    # 状態の番号が 200 でなくても、文書があれば本文として返す。本体が状態の番号を見ずに
    # 本文の time を使うと、テストが落ちるようにするためである。
    if [ -f "${STUB_NPM_DIR}/${key}.json" ]; then
        cat "${STUB_NPM_DIR}/${key}.json" >"${out:?}"
    else
        echo '{"error":"Not found"}' >"${out:?}"
    fi
    printf '%s' "$code"
    exit 0
    ;;
esac
code=404
lm=""
while IFS=$'\t' read -r p central portal l; do
    [ -n "$p" ] || continue
    case "$url" in
    *"$p")
        case "$url" in
        "${MAVEN_CENTRAL_BASE}"/*) code="$central" ;;
        "${PLUGIN_PORTAL_BASE}"/*) code="$portal" ;;
        esac
        lm="$l"
        ;;
    esac
done <"${STUB_TIMES:?}"
if [ "$code" = "000" ]; then exit 7; fi
if [ "$code" = "200" ]; then
    printf 'HTTP/2 200\r\nlast-modified: %s\r\n\r\n' "$lm"
fi
printf '\nHTTP_CODE:%s\n' "$code"
STUB

chmod +x "$WORK/bin/gh" "$WORK/bin/curl"

# 外部のサービスの状態を空にする。PR のコメントは無し、警告は無し、悪意のある部品は無し、
# 除外の欄は要素無し
reset_all() {
    rm -rf "$WORK/npm" "$WORK/alerts" "$WORK/gomod"
    mkdir -p "$WORK/npm" "$WORK/alerts" "$WORK/gomod"
    printf '[]\n' >"$WORK/comments.json"
    : >"$WORK/osv_mal.tsv"
    pnpm_exclude
}

# 使い方: run <compare.jsonの内容> <times.tsvの内容> [gh失敗] [警告base64] [ヘッダ取得失敗]
run() {
    printf '%s' "$1" >"$WORK/compare.json"
    printf '%s' "$2" >"$WORK/times.tsv"
    : >"$WORK/calls.log"
    : >"$WORK/gh_calls.log"
    : >"$WORK/summary.md"
    PATH="$WORK/bin:$PATH" \
        STUB_COMPARE="$WORK/compare.json" STUB_TIMES="$WORK/times.tsv" \
        STUB_CALLS="$WORK/calls.log" STUB_GH_CALLS="$WORK/gh_calls.log" \
        STUB_NPM_DIR="$WORK/npm" STUB_GH_FAIL="${3:-}" STUB_WARN_B64="${4:-}" \
        STUB_HDR_FAIL="${5:-}" STUB_ALERTS_DIR="$WORK/alerts" \
        STUB_COMMENTS="$WORK/comments.json" STUB_OSV_MAL="$WORK/osv_mal.tsv" \
        GITHUB_REPOSITORY="owner/repo" GITHUB_REPOSITORY_OWNER="owner" GH_TOKEN="dummy" \
        PR_NUMBER="${STUB_PR:-12}" OWNER_APPROVED="${OWNER_APPROVED:-}" NOW_EPOCH="$NOW" \
        MAVEN_CENTRAL_BASE="https://central.invalid/maven2" \
        PLUGIN_PORTAL_BASE="https://portal.invalid/m2" \
        NPM_REGISTRY_BASE="https://npm.invalid" \
        GOMOD_INDEX_BASE="https://gomod.invalid" STUB_GOMOD_DIR="$WORK/gomod" GOMOD_INDEX_SEGMENT_HOURS=73 \
        OSV_API_BASE="https://osv.invalid" \
        KEYSERVER_BASE="https://keys.invalid" \
        PNPM_WORKSPACE_FILE="$WORK/pnpm-workspace.yaml" \
        GITHUB_STEP_SUMMARY="$WORK/summary.md" \
        bash "$SCRIPT" "$BASE_SHA" "$HEAD_SHA" >"$WORK/out.log" 2>"$WORK/err.log"
}

# 使い方: check <期待exit> <説明> <compare.json> <times.tsv> [gh失敗] [警告base64] [ヘッダ取得失敗]
check() {
    local want="$1" name="$2" got
    run "$3" "$4" "${5:-}" "${6:-}" "${7:-}"
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit $want, got $got / 標準エラー: $(head -c 400 "$WORK/err.log"))"
        FAILED=1
    fi
}

check_summary() {
    if grep -qF -- "$1" "$WORK/summary.md"; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (Summaryに '$1' が現れない)"
        FAILED=1
    fi
}

check_no_summary() {
    if grep -qF -- "$1" "$WORK/summary.md"; then
        echo "FAIL: $2 (Summaryに '$1' が現れた)"
        FAILED=1
    else
        echo "PASS: $2"
    fi
}

check_out() {
    if grep -qF -- "$1" "$WORK/out.log"; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (標準出力に '$1' が現れない / 標準出力: $(head -c 400 "$WORK/out.log"))"
        FAILED=1
    fi
}

check_no_out() {
    if grep -qF -- "$1" "$WORK/out.log"; then
        echo "FAIL: $2 (標準出力に '$1' が現れた)"
        FAILED=1
    else
        echo "PASS: $2"
    fi
}

check_calls() {
    if grep -qF -- "$1" "$WORK/calls.log"; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (呼び出しログに '$1' が現れない)"
        FAILED=1
    fi
}

check_no_call_to() {
    if grep -qF -- "$1" "$WORK/calls.log"; then
        echo "FAIL: $2 ('$1' への問い合わせが発生した)"
        FAILED=1
    else
        echo "PASS: $2"
    fi
}

check_no_calls() {
    if [ ! -s "$WORK/calls.log" ]; then
        echo "PASS: $1"
    else
        echo "FAIL: $1 (外部への問い合わせが発生した)"
        FAILED=1
    fi
}

# 使い方: check_gh_count <gh の引数の全体> <期待の回数> <説明>
check_gh_count() {
    local got
    got=$(grep -cxF -- "$1" "$WORK/gh_calls.log")
    if [ "$got" -eq "$2" ]; then
        echo "PASS: $3"
    else
        echo "FAIL: $3 (引数が '$1' の gh の呼び出しが ${got} 回 / 期待 $2 回)"
        FAILED=1
    fi
}

# 使い方: check_gh_match <gh の引数の一部> <期待の回数> <説明>
check_gh_match() {
    local got
    got=$(grep -cF -- "$1" "$WORK/gh_calls.log")
    if [ "$got" -eq "$2" ]; then
        echo "PASS: $3"
    else
        echo "FAIL: $3 (引数に '$1' を含む gh の呼び出しが ${got} 回 / 期待 $2 回)"
        FAILED=1
    fi
}

# 使い方: check_records <期待の数> <説明>。PR にある記録のコメントの数を比べる
check_records() {
    local got
    got=$(jq '[.[] | select(.body | contains("<!-- cooldown-exception-record kind=exception head="))] | length' \
        "$WORK/comments.json")
    if [ "$got" -eq "$1" ]; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (記録のコメントが ${got} 個 / 期待 $1 個)"
        FAILED=1
    fi
}

# 使い方: check_record_json <jq の条件> <説明>。最後の記録のコメントの記録の JSON を調べる
check_record_json() {
    local data
    data=$(jq -r '[.[] | .body | capture("cooldown-exception-data data=(?<d>[A-Za-z0-9+/=]+)").d] | last // empty' \
        "$WORK/comments.json")
    if [ -n "$data" ] && printf '%s' "$data" | base64 -d | jq -e "$1" >/dev/null 2>&1; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (記録の JSON が '$1' を満たさない: $(printf '%s' "$data" | base64 -d 2>/dev/null | head -c 400))"
        FAILED=1
    fi
}

want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        echo "--- $1 ---"
        reset_all
        return 0
    fi
    return 1
}

# --- 比較APIの応答(canned) ------------------------------------------------------
entry() {
    printf '{"change_type":"%s","ecosystem":"%s","name":"%s","version":"%s","manifest":"backend/settings.gradle"}' \
        "$1" "$2" "$3" "$4"
}

# 使い方: npm_doc <URLの名前の部分> <registry の部品の文書>
npm_doc() {
    printf '%s' "$2" >"$WORK/npm/$1.json"
}

# 使い方: npm_pkg <名前> <版> <公開日時>。部品の文書に版の公開日時と tgz の URL と sha512 を足し、tgz を置く
npm_pkg() {
    local name="$1" ver="$2" base="${1##*/}" doc tgz
    doc="$WORK/npm/${name//\//%2f}.json"
    tgz="$WORK/npm/${name}/-/${base}-${ver}.tgz.json"
    mkdir -p "$(dirname "$tgz")"
    printf 'contents of %s@%s\n' "$name" "$ver" | gzip -c >"$tgz"
    [ -f "$doc" ] || jq -n --arg n "$name" '{name: $n, time: {}, versions: {}}' >"$doc"
    jq --arg v "$ver" --arg t "$3" --arg u "https://npm.invalid/${name}/-/${base}-${ver}.tgz" \
        --arg i "sha512-$(openssl dgst -sha512 -binary "$tgz" | base64 -w0)" \
        '.time[$v] = $t | .versions[$v] = {dist: {tarball: $u, integrity: $i}}' \
        "$doc" >"$doc.new" && mv "$doc.new" "$doc"
}

# 来歴の証明書の材料。署名した者は、OIDC の発行元と元のリポジトリの ID と組み立ての設定の組である
openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/key.pem" 2>/dev/null || exit 1

# 使い方: provenance <名前> <版> <元のリポジトリの ID>。SLSA の来歴を置く
provenance() {
    local f="$WORK/npm/-/npm/v1/attestations/$1@$2.json" cert
    openssl req -x509 -new -key "$WORK/key.pem" -subj "/CN=test" -days 1 -outform DER \
        -addext "1.3.6.1.4.1.57264.1.8=ASN1:UTF8String:https://token.actions.githubusercontent.com" \
        -addext "1.3.6.1.4.1.57264.1.15=ASN1:UTF8String:$3" \
        -addext "1.3.6.1.4.1.57264.1.18=ASN1:UTF8String:https://github.com/acme/widget/.github/workflows/release.yml@refs/heads/main" \
        -addext "1.3.6.1.4.1.57264.1.12=ASN1:UTF8String:https://github.com/acme/widget" \
        -out "$WORK/cert.der" 2>/dev/null || exit 1
    cert=$(base64 -w0 "$WORK/cert.der")
    mkdir -p "$(dirname "$f")"
    jq -n --arg cert "$cert" '{attestations: [{predicateType: "https://slsa.dev/provenance/v1",
        bundle: {mediaType: "application/vnd.dev.sigstore.bundle.v0.3+json",
            verificationMaterial: {certificate: {rawBytes: $cert}, tlogEntries: []},
            dsseEnvelope: {payload: "e30=", payloadType: "application/vnd.in-toto+json", signatures: []}}}]}' >"$f"
}

# 使い方: alert <ecosystem> <名前> <最初の修正版> [深刻度] [scope] [番号]。開いている警告を1つ置く
alert() {
    local f
    f="$WORK/alerts/${1}_$(jq -rn --arg n "$2" '$n | @uri').json"
    jq -n --arg e "$1" --arg n "$2" --arg fp "$3" --arg sev "${4:-high}" --arg sc "${5:-runtime}" \
        --argjson num "${6:-210}" '{number: $num, state: "open",
        html_url: "https://github.com/owner/repo/security/dependabot/\($num)",
        dependency: {package: {ecosystem: $e, name: $n}, scope: $sc},
        security_advisory: {ghsa_id: "GHSA-aaaa-bbbb-cccc", severity: $sev},
        security_vulnerability: {first_patched_version: {identifier: $fp}}}' >"$f"
}

# 使い方: pnpm_exclude [要素...]。除外の欄に要素を並べた pnpm-workspace.yaml を書く
pnpm_exclude() {
    {
        echo "packages:"
        echo "  - ."
        echo "minimumReleaseAge: 4320"
        echo "minimumReleaseAgeExclude:"
        for e in "$@"; do echo "  - '$e'"; done
        echo "overrides:"
        echo "  follow-redirects: \">=1.16.0\""
    } >"$WORK/pnpm-workspace.yaml"
}

# 使い方: record_comment <head>。github-actions[bot] が書いた記録のコメントを PR に置く
record_comment() {
    jq --arg b "### 公開から72時間待たずに入れる版

<!-- cooldown-exception-record kind=exception head=$1 -->" \
        '. + [{id: (length + 1), user: {login: "github-actions[bot]"}, created_at: "2026-01-09T00:00:00Z", body: $b}]' \
        "$WORK/comments.json" >"$WORK/comments.json.new" && mv "$WORK/comments.json.new" "$WORK/comments.json"
}

# 72時間待たずに入れてよい条件をすべて満たす変更: axios を 1.12.0 から、high の警告の最初の修正版
# 1.12.1(48時間前の公開)に上げる。前の版と新しい版は同じ者が署名し、除外の欄に版の要素がある
setup_eligible_axios() {
    npm_pkg axios 1.12.0 "$ISO_OLD"
    npm_pkg axios 1.12.1 "$ISO_48"
    provenance axios 1.12.0 495574555
    provenance axios 1.12.1 495574555
    alert npm axios 1.12.1
    pnpm_exclude 'axios@1.12.1'
}

# 2026-01-10T00:00:00Z ちょうど72時間前
LM_EXACTLY_72="Wed, 07 Jan 2026 00:00:00 GMT"
# 71時間59分前
LM_JUST_UNDER_72="Wed, 07 Jan 2026 00:01:00 GMT"
# 十分に古い
LM_OLD="Mon, 01 Dec 2025 00:00:00 GMT"
# 48時間前
LM_48="Thu, 08 Jan 2026 00:00:00 GMT"
# npm の registry の time の書式
ISO_48="2026-01-08T00:00:00.000Z"
ISO_EXACTLY_72="2026-01-07T00:00:00.000Z"
ISO_OLD="2025-12-01T00:00:00.000Z"

COMPARE_AXIOS="$(entry removed npm axios 1.12.0),$(entry added npm axios 1.12.1)"

# 止めた部品の表の見出しの行
BLOCKED_HEAD="| 部品 | 版 | 公開日時 | 止めた理由 | 入るようになる時刻 |"
# 使い方: axios_row <止めた理由> [入るようになる時刻]。48時間前に公開した axios 1.12.1 の、止めた部品の表の行
axios_row() {
    printf '| axios | 1.12.1 | 2026-01-08 00:00 UTC | %s | %s |' "$1" "${2:-2026-01-11 00:00 UTC}"
}
# 使い方: axios_cells <止めた理由の始まり>。止めた理由の欄の始まりまでの、axios 1.12.1 の表の行
axios_cells() {
    printf '| axios | 1.12.1 | 2026-01-08 00:00 UTC | %s' "$1"
}
EXTERNAL="外部のサービスに問い合わせられなかった"

if want snapshot; then
    # 実際のAPIが返した警告文をbase64にしたもの
    WARN_B64="VGhlIG51bWJlciBvZiBzbmFwc2hvdHMgY29tcGFyZWQgZm9yIHRoZSBiYXNlIFNIQSAoMSkgYW5kIHRoZSBoZWFkIFNIQSAoMCkgZG8gbm90IG1hdGNoLg=="
    check 1 "スナップショット数が一致しなければ赤にする" "[]" "" "" "$WARN_B64"
    check_summary "スナップショットが揃っていません" "取り込み不足の見出しが出る"
    check_summary "do not match" "APIの警告文がそのまま出る"
    check_summary "少し置いてから" "再実行で解消しうる旨が出る"
    check_no_calls "判定不能なら配布元へ問い合わせない"

    check 0 "警告ヘッダが空なら通常どおり判定する" "[]" "" "" ""

    check 1 "ヘッダの取得に失敗したら赤にする(fail closed)" "[]" "" "" "" "yes"
    check_summary "スナップショットの状況を確認できませんでした" "ヘッダ取得失敗が報告される"
    check_summary "外部要因による失敗です" "外部要因である旨が出る"
    check_no_calls "ヘッダ取得に失敗したら配布元へ問い合わせない"
fi

if want compare_fail; then
    check 1 "比較APIが失敗したら赤にする(fail closed)" "[]" "" "yes"
    check_summary "追加パッケージの一覧を取得できませんでした" "取得失敗が報告される"
    check_summary "外部要因による失敗です" "外部要因である旨が出る"
    check_summary "スナップショットが送信されていない" "未送信の可能性が示される"
fi

if want no_added; then
    check 0 "追加パッケージが0件なら成功する" "[]" ""
    check_no_calls "追加が0件なら配布元へ問い合わせない"
fi

if want filter; then
    check 0 "removed のエントリは対象にしない" \
        "[$(entry removed maven org.example:removed 9.9.9),$(entry removed npm left-pad 1.0.0)]" ""
    check_no_calls "removed だけなら配布元へ問い合わせない"

    check 0 "maven と npm と gomod 以外のエコシステムは対象にしない" \
        "[$(entry added github-actions actions/checkout v9.9.9),$(entry added pip requests 9.9.9)]" ""
    check_no_calls "maven と npm と gomod 以外だけなら配布元へ問い合わせない"

    check 1 "混在していても added かつ maven のものだけを見る" \
        "[$(entry added github-actions actions/checkout v9.9.9),$(entry removed maven org.example:old 1.0.0),$(entry added maven org.example:lib 1.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_JUST_UNDER_72
"
    check_summary "| org.example:lib | 1.0.0 |" "対象の1件だけが報告される"
fi

if want boundary; then
    check 0 "公開から72時間ちょうどなら通す" \
        "[$(entry added maven org.example:lib 1.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_EXACTLY_72
"
    check 1 "公開から71時間59分なら落とす" \
        "[$(entry added maven org.example:lib 1.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_JUST_UNDER_72
"
    check_summary "72時間の待ちで止めた部品" "クールダウンの見出しが出る"
    check_summary "$BLOCKED_HEAD" "止めた報告に、部品と版と理由と、公開日時に72時間を足した時刻が出る(表の列は、部品、版、公開日時、止めた理由、入るようになる時刻の順)"
    check_summary "| org.example:lib | 1.0.0 | 2026-01-07 00:01 UTC | 公開から72時間経っていない。開いている脆弱性の警告が無い | 2026-01-10 00:01 UTC |" \
        "止めた報告に、部品と版と理由と、公開日時に72時間を足した時刻が出る(maven の部品)"
    check_out "::error::72時間の待ちで止めた部品: org.example:lib 1.0.0。理由: 公開から72時間経っていない。開いている脆弱性の警告が無い。入るようになる時刻: 2026-01-10 00:01 UTC" \
        "止めた報告に、部品と版と理由と、公開日時に72時間を足した時刻が出る(止めた部品ごとに ::error:: の行が出る)"
    check_summary "時間の経過によって解消します" "時間で解消する旨が出る"
fi

if want unknown; then
    check 1 "公開時刻を取得できないものが1件でもあれば落とす" \
        "[$(entry added maven org.example:lib 1.0.0),$(entry added maven org.example:missing 2.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_OLD
"
    check_summary "判定不能" "判定不能の見出しが出る"
    check_summary "時間の経過では解消しません" "時間で解消しない旨が出る"
fi

if want unknown_young; then
    check 1 "公開時刻を取得できないものと、公開から72時間経っていないものが混ざれば落とす" \
        "[$(entry added maven org.example:lib 1.0.0),$(entry added maven org.example:missing 2.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_JUST_UNDER_72
"
    check_summary "判定不能" "判定不能の見出しが出る(混ざったとき)"
    check_summary "- org.example:lib:1.0.0(公開: 2026-01-07 00:01 UTC)" "72時間経っていないものも一覧に出る(混ざったとき)"
    check_summary "時間の経過によって解消します" "72時間経っていないものは時間で解消する旨が出る(混ざったとき)"
fi

if want fallback; then
    check 0 "Centralが404ならPortalへフォールバックする" \
        "[$(entry added maven com.github.spotbugs.snom:spotbugs-gradle-plugin 6.5.10)]" \
        "com/github/spotbugs/snom/spotbugs-gradle-plugin/6.5.10/spotbugs-gradle-plugin-6.5.10.pom	404	200	$LM_OLD
"
    check_calls "https://portal.invalid/m2" "Portal へ問い合わせている"

    check 1 "Centralが404以外の失敗ならフォールバックせず判定不能にする" \
        "[$(entry added maven org.example:lib 1.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	500	200	$LM_OLD
"
    check_no_call_to "https://portal.invalid/m2" "404以外ではPortalへ問い合わせない"

    check 1 "Centralへの問い合わせ自体が失敗したら判定不能にする" \
        "[$(entry added maven org.example:lib 1.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	000	200	$LM_OLD
"
fi

if want many; then
    check 1 "複数が該当したとき最も遅い待機明け時刻を出す" \
        "[$(entry added maven org.example:a 1.0.0),$(entry added maven org.example:b 1.0.0)]" \
        "org/example/a/1.0.0/a-1.0.0.pom	200	404	$LM_48
org/example/b/1.0.0/b-1.0.0.pom	200	404	$LM_JUST_UNDER_72
"
    check_summary "すべての版が入るようになる時刻: 2026-01-11 00:00 UTC" "最も遅い時刻が明示される"
    check_summary "| org.example:a | 1.0.0 | 2026-01-08 00:00 UTC | 公開から72時間経っていない。開いている脆弱性の警告が無い | 2026-01-11 00:00 UTC |" \
        "1つの変更で2つ以上の部品を止めたときは、止めたすべての部品が報告に出る(a)"
    check_summary "| org.example:b | 1.0.0 | 2026-01-07 00:01 UTC | 公開から72時間経っていない。開いている脆弱性の警告が無い | 2026-01-10 00:01 UTC |" \
        "1つの変更で2つ以上の部品を止めたときは、止めたすべての部品が報告に出る(b)"
fi

if want transitive; then
    check 0 "すべて経過していれば件数に関わらず通す" \
        "[$(entry added maven org.example:a 1.0.0),$(entry added maven org.example:b 2.0.0),$(entry added maven org.example:c 3.0.0)]" \
        "org/example/a/1.0.0/a-1.0.0.pom	200	404	$LM_OLD
org/example/b/2.0.0/b-2.0.0.pom	200	404	$LM_OLD
org/example/c/3.0.0/c-3.0.0.pom	200	404	$LM_OLD
"
fi

if want coords; then
    # 比較APIの実際の応答(2026-09-25、PR #362)。name は artifactId が小文字になり、
    # package_url は元の表記を保っている
    entry_purl() {
        printf '{"change_type":"added","ecosystem":"maven","name":"%s","version":"%s","package_url":"%s","manifest":"backend/settings.gradle"}' \
            "$1" "$2" "$3"
    }
    check 0 "name が小文字でも package_url の表記でパスを組み立てる" \
        "[$(entry_purl biz.aQute.bnd:biz.aqute.bnd.annotation 7.1.0 pkg:maven/biz.aQute.bnd/biz.aQute.bnd.annotation@7.1.0)]" \
        "biz/aQute/bnd/biz.aQute.bnd.annotation/7.1.0/biz.aQute.bnd.annotation-7.1.0.pom	200	404	$LM_OLD
"
    check_calls "/biz/aQute/bnd/biz.aQute.bnd.annotation/7.1.0/" "元の表記のパスへ問い合わせている"
    check_no_call_to "/biz.aqute.bnd.annotation/" "小文字のパスへは問い合わせない"

    check 0 "package_url に修飾子が付いていても座標を取り出す" \
        "[$(entry_purl org.example:lib 1.0.0 'pkg:maven/org.example/lib@1.0.0?type=jar')]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_OLD
"

    check 1 "package_url の座標でも72時間未満なら落とす" \
        "[$(entry_purl org.example:lib 1.0.0 pkg:maven/org.example/Lib@1.0.0)]" \
        "org/example/Lib/1.0.0/Lib-1.0.0.pom	200	404	$LM_JUST_UNDER_72
"
    check_summary "| org.example:Lib | 1.0.0 |" "package_url の表記で報告される"
fi

if want npm_time; then
    npm_doc axios "{\"name\":\"axios\",\"time\":{\"created\":\"$ISO_OLD\",\"1.12.0\":\"$ISO_OLD\",\"1.12.1\":\"$ISO_48\"}}"
    check 1 "npm の部品の公開日時を registry の time から読む(48時間前なら赤)" \
        "[$(entry added npm axios 1.12.1)]" ""
    check_calls "https://npm.invalid/axios" "npm の部品の公開日時を registry の time から読む(registry の部品の文書を読む)"
    check_summary "| axios | 1.12.1 | 2026-01-08 00:00 UTC |" "npm の部品の公開日時を registry の time から読む(報告に版と公開日時が出る)"
    check_no_call_to "central.invalid" "npm の部品の公開日時を registry の time から読む(Maven Central には問い合わせない)"

    check 0 "npm の部品の公開日時を registry の time から読む(十分に古ければ緑)" \
        "[$(entry added npm axios 1.12.0)]" ""

    npm_doc axios "{\"name\":\"axios\",\"time\":{\"1.12.1\":\"$ISO_EXACTLY_72\"}}"
    check 0 "npm の部品の公開日時を registry の time から読む(72時間ちょうどなら緑)" \
        "[$(entry added npm axios 1.12.1)]" ""
fi

if want npm_scoped; then
    npm_doc '@types%2fnode' "{\"name\":\"@types/node\",\"time\":{\"24.0.1\":\"$ISO_OLD\"}}"
    check 0 "スコープ付きの名前の / を %2f にして読む(十分に古ければ緑)" \
        "[$(entry added npm @types/node 24.0.1)]" ""
    check_calls "https://npm.invalid/@types%2fnode" "スコープ付きの名前の / を %2f にして読む(URL)"
    check_no_call_to "https://npm.invalid/@types/node" "スコープ付きの名前の / を %2f にして読む(/ のままでは問い合わせない)"
fi

if want npm_unknown; then
    check 1 "npm の部品の公開日時を読めなければ赤になる(registry が 404)" \
        "[$(entry added npm no-such-pkg 1.0.0)]" ""
    check_summary "判定不能" "npm の部品の公開日時を読めなければ赤になる(判定不能の見出しが出る)"
    check_summary "no-such-pkg@1.0.0" "npm の部品の公開日時を読めなければ赤になる(版が出る)"

    npm_doc axios "{\"name\":\"axios\",\"time\":{\"1.12.0\":\"$ISO_OLD\"}}"
    check 1 "npm の部品の公開日時を読めなければ赤になる(time に版が無い)" \
        "[$(entry added npm axios 1.12.1)]" ""
    check_summary "axios@1.12.1" "npm の部品の公開日時を読めなければ赤になる(time に版が無い版が出る)"

    npm_doc lodash "{\"name\":\"lodash\",\"time\":{\"4.17.22\":\"not-a-date\"}}"
    check 1 "npm の部品の公開日時を読めなければ赤になる(time の書式が違う)" \
        "[$(entry added npm lodash 4.17.22)]" ""

    npm_doc react "{\"name\":\"react\",\"time\":{\"19.0.0\":\"$ISO_OLD\"}}"
    printf '500' >"$WORK/npm/react.code"
    check 1 "npm の部品の公開日時を読めなければ赤になる(registry が 500)" \
        "[$(entry added npm react 19.0.0)]" ""

    printf '000' >"$WORK/npm/react.code"
    check 1 "npm の部品の公開日時を読めなければ赤になる(接続に失敗)" \
        "[$(entry added npm react 19.0.0)]" ""

    printf '{not json' >"$WORK/npm/vue.json"
    check 1 "npm の部品の公開日時を読めなければ赤になる(JSON でない)" \
        "[$(entry added npm vue 3.0.0)]" ""

    check 1 "npm の部品の公開日時を読めなければ赤になる(名前に使えない文字がある)" \
        "[$(entry added npm '../evil?x=1' 1.0.0)]" ""
    check_no_calls "npm の部品の公開日時を読めなければ赤になる(名前に使えない文字があれば問い合わせない)"
fi

if want alerts_readable; then
    check 0 "警告の API を読めれば報告に1行が出る(終了コード 0)" \
        "[$(entry added maven org.example:lib 1.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_OLD
"
    check_summary "脆弱性の警告を読めた" "警告の API を読めれば報告に1行が出る"
    check_gh_count "api repos/owner/repo/dependabot/alerts?per_page=1" 1 "警告の API を読めれば報告に1行が出る(警告の API を1回だけ読む)"
    check_no_out "::warning::" "警告の API を読めれば報告に1行が出る(::warning:: の行は出ない)"

    check 0 "警告の API を読めれば報告に1行が出る(追加が0件でも確かめる)" "[]" ""
    check_gh_count "api repos/owner/repo/dependabot/alerts?per_page=1" 1 "警告の API を読めれば報告に1行が出る(追加が0件でも1回読む)"
    check_summary "脆弱性の警告を読めた" "警告の API を読めれば報告に1行が出る(追加が0件でも1行が出る)"
fi

if want alerts_unreadable; then
    npm_doc axios "{\"name\":\"axios\",\"time\":{\"1.12.0\":\"$ISO_OLD\"}}"
    STUB_ALERTS_FAIL=yes check 0 "すべての版が72時間経っていれば、警告の API を読めなくても緑になり、::warning:: の行と報告の1行が出る" \
        "[$(entry added maven org.example:lib 1.0.0),$(entry added npm axios 1.12.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_OLD
"
    check_out "::warning::" "すべての版が72時間経っていれば、警告の API を読めなくても緑になり、::warning:: の行と報告の1行が出る(::warning:: の行)"
    check_summary "脆弱性の警告を読めなかった(HTTP 403)" "すべての版が72時間経っていれば、警告の API を読めなくても緑になり、::warning:: の行と報告の1行が出る(報告の1行に HTTP の状態の番号が入る)"
    check_no_summary "脆弱性の警告を読めた" "すべての版が72時間経っていれば、警告の API を読めなくても緑になり、::warning:: の行と報告の1行が出る(読めたの行は出ない)"
fi

if want prev_version; then
    npm_doc axios "{\"name\":\"axios\",\"time\":{\"1.12.1\":\"$ISO_OLD\"}}"
    npm_doc lodash "{\"name\":\"lodash\",\"time\":{\"4.17.22\":\"$ISO_OLD\"}}"
    check 0 "前の版は同じ名前の removed の部品のうち最も高い版になる(終了コード 0)" \
        "[$(entry removed npm axios 1.9.0),$(entry removed npm axios 1.12.0),$(entry removed npm axios 1.10.0),$(entry removed maven axios 9.9.9),$(entry removed npm axios-retry 9.9.9),$(entry added npm axios 1.12.1),$(entry added npm lodash 4.17.22),$(entry removed maven org.example:lib 1.0.0),$(entry removed maven org.example:lib 1.0.9),$(entry added maven org.example:lib 1.0.10)]" \
        "org/example/lib/1.0.10/lib-1.0.10.pom	200	404	$LM_OLD
"
    check_out "追加された部品: npm axios 1.12.1(前の版: 1.12.0)" "前の版は同じ名前の removed の部品のうち最も高い版になる(npm。版の数の大きさで比べ、ほかの ecosystem とほかの名前を混ぜない)"
    check_out "追加された部品: npm lodash 4.17.22(前の版: なし)" "前の版は同じ名前の removed の部品のうち最も高い版になる(removed が無ければ、なし)"
    check_out "追加された部品: maven org.example:lib 1.0.10(前の版: 1.0.9)" "前の版は同じ名前の removed の部品のうち最も高い版になる(maven)"
fi

# --- 72時間待たずに入れる版の判定(結合テスト) -------------------------------------

if want alerts_unreadable_young; then
    setup_eligible_axios
    STUB_ALERTS_FAIL=yes OWNER_APPROVED=true check 1 "公開から72時間経っていない版があり、警告の API を読めなければ赤になる" "[$COMPARE_AXIOS]" ""
    check_summary "$(axios_row "脆弱性の警告を読めなかった。$EXTERNAL")" "外部のサービスに問い合わせられなかったときは、その理由と時刻が出る(警告の API)"
    check_summary "**$EXTERNAL版があります。**" "公開から72時間経っていない版があり、警告の API を読めなければ赤になる(止めた理由が報告に出る)"
    check_records 0 "公開から72時間経っていない版があり、警告の API を読めなければ赤になる(記録を書かない)"
fi

if want bad_pr_number; then
    STUB_PR="12; x" check 1 "PR の番号の形でなければ赤になる" "[]" ""
    STUB_PR="012" check 1 "PR の番号の形でなければ赤になる(0 で始まる)" "[]" ""
    check_gh_match "issues/" 0 "PR の番号の形でなければ赤になる(コメントを読まない)"
    check_gh_match "compare" 0 "PR の番号の形でなければ赤になる(依存の差分を読む前に止まる)"
fi

if want mature_no_record; then
    npm_pkg axios 1.12.0 "$ISO_OLD"
    check 0 "すべての版が72時間経っていて記録のコメントが無ければ緑になり、警告の API を1回だけ読み、OSV と署名には問い合わせず、記録を書かない" \
        "[$(entry removed npm axios 1.11.0),$(entry added npm axios 1.12.0),$(entry added maven org.example:lib 1.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_OLD
"
    check_gh_match "dependabot/alerts" 1 "すべての版が72時間経っていて記録のコメントが無ければ緑になり、警告の API を1回だけ読み、OSV と署名には問い合わせず、記録を書かない(警告の API を1回だけ読む)"
    check_no_call_to "osv.invalid" "すべての版が72時間経っていて記録のコメントが無ければ緑になり、警告の API を1回だけ読み、OSV と署名には問い合わせず、記録を書かない(OSV に問い合わせない)"
    check_no_call_to "attestations" "すべての版が72時間経っていて記録のコメントが無ければ緑になり、警告の API を1回だけ読み、OSV と署名には問い合わせず、記録を書かない(署名を読まない)"
    check_gh_match "-X POST" 0 "すべての版が72時間経っていて記録のコメントが無ければ緑になり、警告の API を1回だけ読み、OSV と署名には問い合わせず、記録を書かない(記録を書かない)"
    check_gh_match "repos/owner/repo/issues/12/comments" 1 "すべての版が72時間経っていて記録のコメントが無ければ緑になり、警告の API を1回だけ読み、OSV と署名には問い合わせず、記録を書かない(記録のコメントの有無を読む)"
fi

if want record_unreadable; then
    STUB_COMMENTS_FAIL=list check 1 "記録のコメントの有無を読めなければ赤になる" \
        "[$(entry added maven org.example:lib 1.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_OLD
"
    STUB_COMMENTS_FAIL=list OWNER_APPROVED=true check 1 "記録のコメントの有無を読めなければ赤になる(所有者の承認があっても赤)" \
        "[]" ""
fi

if want record_exists_mature; then
    record_comment "$OLD_HEAD"
    check 1 "記録のコメントがあり公開から72時間経っていない版が無い head では、承認が無ければ赤になる" \
        "[$(entry added maven org.example:lib 1.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_OLD
"
    check_summary "所有者の承認待ち" "記録のコメントがあり公開から72時間経っていない版が無い head では、承認が無ければ赤になる(所有者の承認待ちが出る)"
    check_summary "版と理由になった警告は、この PR の記録のコメントにあります。" "記録のコメントがあり公開から72時間経っていない版が無い head では、承認が無ければ赤になる(版と警告の読み先が出る)"
    check_records 1 "記録のコメントがあり公開から72時間経っていない版が無い head では、承認が無ければ赤になる(記録を重ねて書かない)"
    OWNER_APPROVED=true check 0 "記録のコメントがあり公開から72時間経っていない版が無い head では、承認があれば緑になる" \
        "[$(entry added maven org.example:lib 1.0.0)]" \
        "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_OLD
"
    OWNER_APPROVED=yes check 1 "記録のコメントがあり公開から72時間経っていない版が無い head では、承認が無ければ赤になる(承認の値が true でなければ承認とみなさない)" \
        "[]" ""
fi

if want exception_approve; then
    setup_eligible_axios
    check 1 "確認がすべて通れば記録のコメントが書かれ、承認が無ければ赤になる" "[$COMPARE_AXIOS]" ""
    check_summary "所有者の承認待ち" "確認がすべて通れば記録のコメントが書かれ、承認が無ければ赤になる(所有者の承認待ちが出る)"
    check_summary "| 部品 | 版 | 公開日時 | 理由になった警告 |" "承認を待つときは、承認待ちの表に版と警告が出る(表の見出し)"
    check_summary "| axios | 1.12.1 | 2026-01-08 00:00 UTC | [#210](https://github.com/owner/repo/security/dependabot/210) GHSA-aaaa-bbbb-cccc high |" \
        "承認を待つときは、承認待ちの表に版と警告が出る"
    check_no_summary "72時間の待ちで止めた部品" "承認を待つときは、止めた部品の表を書かない"
    check_records 1 "確認がすべて通れば記録のコメントが書かれ、承認が無ければ赤になる(記録のコメントが1つ書かれる)"
    check_record_json ".pr == 12 and .head == \"$HEAD_SHA\" and .schema == 1" "確認がすべて通れば記録のコメントが書かれ、承認が無ければ赤になる(記録に PR と head が載る)"
    check_record_json '.entries == [{ecosystem: "npm", name: "axios", version: "1.12.1", published_at: "2026-01-08T00:00:00Z", alerts: [{number: 210, ghsa_id: "GHSA-aaaa-bbbb-cccc", severity: "high", html_url: "https://github.com/owner/repo/security/dependabot/210"}]}]' \
        "確認がすべて通れば記録のコメントが書かれ、承認が無ければ赤になる(記録に版と公開日時と理由の警告が載る)"
    check_record_json '.recorded_at == "2026-01-10T00:00:00Z"' "確認がすべて通れば記録のコメントが書かれ、承認が無ければ赤になる(記録の時刻は判定の時点)"
    check_calls "https://osv.invalid/v1/querybatch" "確認がすべて通れば記録のコメントが書かれ、承認が無ければ赤になる(OSV に照らす)"
    check_gh_match "attestation verify" 1 "確認がすべて通れば記録のコメントが書かれ、承認が無ければ赤になる(新しい版の来歴を検証する)"
    check_no_summary "時間の経過によって解消します" "確認がすべて通れば記録のコメントが書かれ、承認が無ければ赤になる(時間で解消するとは書かない)"

    OWNER_APPROVED=true check 0 "確認がすべて通れば記録のコメントが書かれ、承認があれば緑になる" "[$COMPARE_AXIOS]" ""
    check_records 1 "確認がすべて通れば記録のコメントが書かれ、承認があれば緑になる(同じ head では記録を重ねない)"
fi

if want approve_two_alerts; then
    setup_eligible_axios
    # 警告のスタブはファイルの中身を1ページの一覧の中に入れるので、2つの警告をカンマで並べる
    f="$WORK/alerts/npm_axios.json"
    jq -c '., (.number = 211 | .html_url = "https://github.com/owner/repo/security/dependabot/211"
        | .security_advisory = {ghsa_id: "GHSA-dddd-eeee-ffff", severity: "critical"})' "$f" | paste -sd, >"$f.new" &&
        mv "$f.new" "$f"
    check 1 "承認を待つときは、承認待ちの表に版と警告が出る(警告が2つなら赤になる)" "[$COMPARE_AXIOS]" ""
    check_summary "| axios | 1.12.1 | 2026-01-08 00:00 UTC | [#210](https://github.com/owner/repo/security/dependabot/210) GHSA-aaaa-bbbb-cccc high<br>[#211](https://github.com/owner/repo/security/dependabot/211) GHSA-dddd-eeee-ffff critical |" \
        "承認を待つときは、承認待ちの表に版と警告が出る(警告が2つなら、1つのマスに改行で並べる)"
fi

if want dependabot; then
    setup_eligible_axios
    GITHUB_ACTOR="dependabot[bot]" check 1 "Dependabot が作った PR でも同じ判定になる(承認が無ければ赤)" "[$COMPARE_AXIOS]" ""
    check_records 1 "Dependabot が作った PR でも同じ判定になる(記録のコメントが書かれる)"
    GITHUB_ACTOR="dependabot[bot]" OWNER_APPROVED=true check 0 "Dependabot が作った PR でも同じ判定になる(承認があれば緑)" "[$COMPARE_AXIOS]" ""
fi

if want others_young; then
    setup_eligible_axios
    npm_pkg lodash 4.17.21 "$ISO_OLD"
    npm_pkg lodash 4.17.22 "$ISO_48"
    OWNER_APPROVED=true check 1 "72時間待たずに入れる版と一緒に、ほかの公開から72時間経っていない版があれば赤になる" \
        "[$COMPARE_AXIOS,$(entry removed npm lodash 4.17.21),$(entry added npm lodash 4.17.22)]" ""
    check_summary "| lodash | 4.17.22 | 2026-01-08 00:00 UTC | 公開から72時間経っていない。開いている脆弱性の警告が無い | 2026-01-11 00:00 UTC |" "72時間待たずに入れる版と一緒に、ほかの公開から72時間経っていない版があれば赤になる(ほかの版が止めた理由とともに報告に出る)"
    check_summary "$(axios_row "この版は条件を満たすが、ほかの版を待つ")" "72時間待たずに入れる版と一緒に、ほかの公開から72時間経っていない版があれば、両方の版が報告に出て、条件を満たす版は waiting-others の文になる"
    check_records 0 "72時間待たずに入れる版と一緒に、ほかの公開から72時間経っていない版があれば赤になる(記録を書かない)"

    alert npm lodash 4.17.21
    OWNER_APPROVED=true check 1 "最初の修正版でない版があれば OSV と署名に問い合わせない(赤になる)" \
        "[$COMPARE_AXIOS,$(entry removed npm lodash 4.17.21),$(entry added npm lodash 4.17.22)]" ""
    check_summary "| lodash | 4.17.22 | 2026-01-08 00:00 UTC | 公開から72時間経っていない。警告の最初の修正版ではない(最初の修正版: 4.17.21) | 2026-01-11 00:00 UTC |" "最初の修正版でない版があれば OSV と署名に問い合わせない(止めた理由と最初の修正版が報告に出る)"
    check_no_call_to "osv.invalid" "最初の修正版でない版があれば OSV と署名に問い合わせない(OSV)"
    check_no_call_to "attestations" "最初の修正版でない版があれば OSV と署名に問い合わせない(署名)"
    check_records 0 "最初の修正版でない版があれば OSV と署名に問い合わせない(記録を書かない)"
fi

if want malware_mature; then
    setup_eligible_axios
    npm_pkg evil-dep 1.0.0 "$ISO_OLD"
    printf 'evil-dep@1.0.0\tMAL-2026-1\n' >"$WORK/osv_mal.tsv"
    OWNER_APPROVED=true check 1 "72時間待たずに入れる版と一緒に入る72時間経った部品が悪意のある部品なら赤になる" \
        "[$COMPARE_AXIOS,$(entry added npm evil-dep 1.0.0)]" ""
    check_summary "| evil-dep | 1.0.0 | 2025-12-01 00:00 UTC | 悪意のある部品として公表されている(MAL-2026-1 Malicious code in package (MAL-2026-1) https://advisories.invalid/MAL-2026-1) | 入らない |" "悪意のある部品のときは、時刻の欄が入らないになり、公表の記載の ID と要約と URL が出る"
    check_out "::error::72時間の待ちで止めた部品: evil-dep 1.0.0。理由: 悪意のある部品として公表されている(MAL-2026-1 Malicious code in package (MAL-2026-1) https://advisories.invalid/MAL-2026-1)。入るようになる時刻: 入らない" "悪意のある部品のときは、時刻の欄が入らないになり、公表の記載の ID と要約と URL が出る(::error:: の行)"
    check_no_summary "時間の経過によって解消します" "悪意のある部品のときは、時間で解消するとは書かない"
    check_summary "| evil-dep | 1.0.0 |" "72時間待たずに入れる版と一緒に入る72時間経った部品が悪意のある部品なら赤になる(悪意のある部品が公表の ID とともに報告に出る)"
    check_records 0 "72時間待たずに入れる版と一緒に入る72時間経った部品が悪意のある部品なら赤になる(記録を書かない)"
    check_no_call_to "attestations" "72時間待たずに入れる版と一緒に入る72時間経った部品が悪意のある部品なら赤になる(署名を読まない)"

    printf 'axios@1.12.1\tMAL-2026-2\n' >"$WORK/osv_mal.tsv"
    OWNER_APPROVED=true check 1 "72時間待たずに入れる版そのものが悪意のある部品なら赤になる" "[$COMPARE_AXIOS]" ""
    check_summary "$(axios_row "悪意のある部品として公表されている(MAL-2026-2 Malicious code in package (MAL-2026-2) https://advisories.invalid/MAL-2026-2)" 入らない)" "72時間待たずに入れる版そのものが悪意のある部品なら赤になる(止めた理由が報告に出る)"
    check_records 0 "72時間待たずに入れる版そのものが悪意のある部品なら赤になる(記録を書かない)"

    STUB_OSV_SUMMARY="50% | steals tokens" OWNER_APPROVED=true check 1 "公表の記載の要約に縦棒と % があっても、表と ::error:: の行が崩れない(赤になる)" "[$COMPARE_AXIOS]" ""
    check_summary "(MAL-2026-2 50% \| steals tokens https://advisories.invalid/MAL-2026-2) | 入らない |" \
        "公表の記載の要約に縦棒と % があっても、表と ::error:: の行が崩れない(表では縦棒を逃がす)"
    check_out "理由: 悪意のある部品として公表されている(MAL-2026-2 50%25 | steals tokens https://advisories.invalid/MAL-2026-2)。" \
        "公表の記載の要約に縦棒と % があっても、表と ::error:: の行が崩れない(::error:: の行では % を %25 と書く)"
fi

if want malware_unknown; then
    setup_eligible_axios
    STUB_OSV_FAIL=yes OWNER_APPROVED=true check 1 "OSV に照らせなければ赤になる" "[$COMPARE_AXIOS]" ""
    check_summary "$(axios_row "悪意のある部品の一覧に照らせなかった。$EXTERNAL")" "外部のサービスに問い合わせられなかったときは、その理由と時刻が出る(OSV)"
    check_records 0 "OSV に照らせなければ赤になる(記録を書かない)"
fi

if want signer_different; then
    setup_eligible_axios
    provenance axios 1.12.1 999999999
    OWNER_APPROVED=true check 1 "署名した者が違えば赤になる" "[$COMPARE_AXIOS]" ""
    check_summary "$(axios_cells "署名した者が前の版と違う(")" "署名した者が違えば赤になる(止めた理由が報告に出る)"
    check_records 0 "署名した者が違えば赤になる(記録を書かない)"

    setup_eligible_axios
    rm -f "$WORK/npm/-/npm/v1/attestations/axios@1.12.1.json"
    OWNER_APPROVED=true check 1 "前の版にある署名が新しい版に無ければ赤になる" "[$COMPARE_AXIOS]" ""
    check_summary "$(axios_cells "前の版にある署名が、この版に無い")" "前の版にある署名が新しい版に無ければ赤になる(止めた理由が報告に出る)"
    check_records 0 "前の版にある署名が新しい版に無ければ赤になる(記録を書かない)"
fi

if want signer_unknown; then
    setup_eligible_axios
    STUB_ATTEST_FAIL=yes OWNER_APPROVED=true check 1 "署名を調べられなければ赤になる(来歴を検証できない)" "[$COMPARE_AXIOS]" ""
    check_summary "$(axios_cells "署名を調べられなかった")" "署名を調べられなければ赤になる(止めた理由が報告に出る)"
    check_summary "$EXTERNAL | 2026-01-11 00:00 UTC |" "外部のサービスに問い合わせられなかったときは、その理由と時刻が出る(署名)"
    check_records 0 "署名を調べられなければ赤になる(記録を書かない)"

    printf '500' >"$WORK/npm/-/npm/v1/attestations/axios@1.12.0.code"
    OWNER_APPROVED=true check 1 "署名を調べられなければ赤になる(来歴を読めない)" "[$COMPARE_AXIOS]" ""
    check_records 0 "署名を調べられなければ赤になる(来歴を読めないときも記録を書かない)"
fi

if want no_prior_signature; then
    setup_eligible_axios
    rm -f "$WORK/npm/-/npm/v1/attestations/axios@1.12.0.json"
    check 1 "前の版に署名が無ければ止めない(記録が書かれ、承認待ちになる)" "[$COMPARE_AXIOS]" ""
    check_summary "所有者の承認待ち" "前の版に署名が無ければ止めない(所有者の承認待ちが出る)"
    check_records 1 "前の版に署名が無ければ止めない(記録のコメントが書かれる)"
    OWNER_APPROVED=true check 0 "前の版に署名が無ければ止めない(承認があれば緑)" "[$COMPARE_AXIOS]" ""
fi

if want no_prior_version; then
    setup_eligible_axios
    OWNER_APPROVED=true check 1 "同じ名前の removed の部品が無い版は赤になる" "[$(entry added npm axios 1.12.1)]" ""
    check_summary "$(axios_row "前の版が見つからない")" "前の版が無ければ、前の版が見つからないという理由が出る"
    check_records 0 "同じ名前の removed の部品が無い版は赤になる(記録を書かない)"
    check_no_call_to "attestations" "同じ名前の removed の部品が無い版は赤になる(署名を読まない)"
fi

if want pnpm_missing; then
    setup_eligible_axios
    pnpm_exclude 'axios' 'axios@1.12.0' 'vite@6.0.1'
    OWNER_APPROVED=true check 1 "frontend の版に除外の欄の要素が無ければ赤になる" "[$COMPARE_AXIOS]" ""
    check_summary "$(axios_row "除外の欄に、この版の要素が無い(足す1行: \`  - 'axios@1.12.1'\`)")" "除外の欄の要素が無ければ、足すべき1行が報告に出る"
    check_records 0 "frontend の版に除外の欄の要素が無ければ赤になる(記録を書かない)"

    pnpm_exclude 'axios@1.12.0 || 1.12.1'
    check 1 "frontend の版に除外の欄の要素があれば先に進む(承認待ちになる)" "[$COMPARE_AXIOS]" ""
    check_records 1 "frontend の版に除外の欄の要素があれば先に進む(記録のコメントが書かれる)"
fi

if want pnpm_unreadable; then
    setup_eligible_axios
    npm_pkg vite 6.0.0 "$ISO_OLD"
    npm_pkg vite 6.0.1 "$ISO_48"
    alert npm vite 6.0.1 critical runtime 211
    printf 'minimumReleaseAgeExclude: [axios@1.12.1, vite@6.0.1]\n' >"$WORK/pnpm-workspace.yaml"
    OWNER_APPROVED=true check 1 "除外の欄を読めなければ、frontend の公開から72時間経っていない版がすべて止まる" \
        "[$COMPARE_AXIOS,$(entry removed npm vite 6.0.0),$(entry added npm vite 6.0.1)]" ""
    check_summary "$(axios_row "除外の欄を読めなかった")" "除外の欄を読めなければ、除外の欄を読めなかったという理由が出る(axios)"
    check_summary "| vite | 6.0.1 | 2026-01-08 00:00 UTC | 除外の欄を読めなかった | 2026-01-11 00:00 UTC |" "除外の欄を読めなければ、除外の欄を読めなかったという理由が出る(vite)"
    check_records 0 "除外の欄を読めなければ、frontend の公開から72時間経っていない版がすべて止まる(記録を書かない)"
fi

if want reason_texts; then
    for p in low-dep dev-dep scope-dep; do
        npm_pkg "$p" 1.0.0 "$ISO_OLD"
        npm_pkg "$p" 1.0.1 "$ISO_48"
    done
    alert npm low-dep 1.0.1 moderate
    alert npm dev-dep 1.0.1 high development
    alert npm scope-dep 1.0.1 high unknown
    check 1 "警告の深刻度と scope で止めた版は、それぞれの理由の文が出る" \
        "[$(entry removed npm low-dep 1.0.0),$(entry added npm low-dep 1.0.1),$(entry removed npm dev-dep 1.0.0),$(entry added npm dev-dep 1.0.1),$(entry removed npm scope-dep 1.0.0),$(entry added npm scope-dep 1.0.1)]" ""
    check_summary "| low-dep | 1.0.1 | 2026-01-08 00:00 UTC | 公開から72時間経っていない。警告の深刻度が high でも critical でもない | 2026-01-11 00:00 UTC |" \
        "警告の深刻度と scope で止めた版は、それぞれの理由の文が出る(深刻度)"
    check_summary "| dev-dep | 1.0.1 | 2026-01-08 00:00 UTC | 公開から72時間経っていない。警告が、開発のときだけ使う部品を示している | 2026-01-11 00:00 UTC |" \
        "警告の深刻度と scope で止めた版は、それぞれの理由の文が出る(開発のときだけ使う部品)"
    check_summary "| scope-dep | 1.0.1 | 2026-01-08 00:00 UTC | 公開から72時間経っていない。警告に、本番で動くかが載っていない | 2026-01-11 00:00 UTC |" \
        "警告の深刻度と scope で止めた版は、それぞれの理由の文が出る(本番で動くかが載っていない)"
fi

if want record_post_fail; then
    setup_eligible_axios
    STUB_COMMENTS_FAIL=post OWNER_APPROVED=true check 1 "記録のコメントを書けなかったら赤になる(所有者の承認があっても赤)" "[$COMPARE_AXIOS]" ""
    check_records 0 "記録のコメントを書けなかったら赤になる(記録が無い)"
fi

# --- gomod(Go のモジュール)の部品 ----------------------------------------------------
# 索引を読み始める時刻。基準時刻の73時間前
GOMOD_SINCE="2026-01-06T23:00:00Z"
# 使い方: gomod_index <モジュール> <版> <取り込まれた時刻>。読み始めのページに索引の1行を足す
gomod_index() {
    printf '{"Path":"%s","Version":"%s","Timestamp":"%s"}\n' "$1" "$2" "$3" >>"$WORK/gomod/$GOMOD_SINCE"
}
GOMOD_INDEX_URL="https://gomod.invalid/index?since=${GOMOD_SINCE}&limit=2000"
COMPARE_GOTOOL="$(entry removed gomod github.com/Example/Tool 1.1.0),$(entry added gomod github.com/Example/Tool 1.2.0)"

if want gomod_young; then
    gomod_index github.com/Example/Tool v1.2.0 2026-01-08T00:00:00Z
    check 1 "gomod の部品が新しければ止める" "[$COMPARE_GOTOOL]" ""
    check_summary "| github.com/Example/Tool | 1.2.0 | 2026-01-08 00:00 UTC | 公開から72時間経っていない。開いている脆弱性の警告が無い | 2026-01-11 00:00 UTC |" \
        "gomod の部品が新しければ止める(索引に取り込まれた時刻と、それに72時間を足した時刻が表に出る)"
    check_out "::error::72時間の待ちで止めた部品: github.com/Example/Tool 1.2.0。理由: 公開から72時間経っていない。開いている脆弱性の警告が無い。入るようになる時刻: 2026-01-11 00:00 UTC" \
        "gomod の部品が新しければ止める(::error:: の行が出る)"
    check_calls "$GOMOD_INDEX_URL" "gomod の部品が新しければ止める(索引を判定の時刻の73時間前から読む)"
    check_gh_match "ecosystem=go&package=github.com%2FExample%2FTool" 1 "gomod の部品が新しければ止める(警告は go のエコシステムで問い合わせる)"
fi

if want gomod_mature; then
    # 72時間30分前に取り込まれた部品と、索引の読んだ範囲に無い部品
    gomod_index github.com/example/old v2.0.0 2026-01-06T23:30:00Z
    check 0 "gomod の部品が古ければ通す" \
        "[$(entry added gomod github.com/example/old 2.0.0),$(entry added gomod golang.org/x/text 0.22.0)]" ""
    check_out "追加された部品: gomod golang.org/x/text 0.22.0" "gomod の部品が古ければ通す(索引の読んだ範囲に無い部品も見る)"
    if [ "$(grep -cF 'https://gomod.invalid/' "$WORK/calls.log")" -eq 1 ]; then
        echo "PASS: gomod の部品が2つあっても、索引を1度だけ読む"
    else
        echo "FAIL: gomod の部品が2つあっても、索引を1度だけ読む ($(grep -cF 'https://gomod.invalid/' "$WORK/calls.log") 回読んだ)"
        FAILED=1
    fi
fi

if want gomod_unknown; then
    # 索引のページを置かないので、索引を読めない
    check 1 "索引を読めなければ、gomod の部品を判定不能にして赤にする" \
        "[$(entry added gomod github.com/example/a 1.0.0),$(entry added gomod github.com/example/b 2.0.0)]" ""
    check_summary "判定不能" "索引を読めなければ、gomod の部品を判定不能にして赤にする(判定不能の見出しが出る)"
    check_summary "- github.com/example/a@1.0.0(Go のモジュールの索引を読めませんでした)" \
        "索引を読めなければ、gomod の部品を判定不能にして赤にする(1つ目の部品が出る)"
    check_summary "- github.com/example/b@2.0.0(Go のモジュールの索引を読めませんでした)" \
        "索引を読めなければ、gomod の部品を判定不能にして赤にする(2つ目の部品が出る)"
    check_summary "https://gomod.invalid" "索引を読めなければ、gomod の部品を判定不能にして赤にする(問い合わせ先に索引が出る)"
fi

if want gomod_eligible; then
    gomod_index github.com/Example/Tool v1.2.0 2026-01-08T00:00:00Z
    # 警告の API は、Go のモジュールのエコシステムを go と呼ぶ。最初の修正版は、先頭の v の有無によらず照らす
    alert go github.com/Example/Tool v1.2.0
    check 1 "gomod の部品が警告の最初の修正版なら、記録を書いて所有者の承認を待つ" "[$COMPARE_GOTOOL]" ""
    check_summary "所有者の承認待ち" "gomod の部品が警告の最初の修正版なら、記録を書いて所有者の承認を待つ(承認待ちが出る)"
    check_record_json '.entries == [{ecosystem: "gomod", name: "github.com/Example/Tool", version: "1.2.0", published_at: "2026-01-08T00:00:00Z", alerts: [{number: 210, ghsa_id: "GHSA-aaaa-bbbb-cccc", severity: "high", html_url: "https://github.com/owner/repo/security/dependabot/210"}]}]' \
        "gomod の部品が警告の最初の修正版なら、記録を書いて所有者の承認を待つ(記録に版と公開日時と理由の警告が載る)"
    check_no_call_to "attestations" "gomod の部品が警告の最初の修正版なら、記録を書いて所有者の承認を待つ(npm の来歴を読まない)"
    OWNER_APPROVED=true check 0 "gomod の部品が警告の最初の修正版なら、承認があれば緑になる" "[$COMPARE_GOTOOL]" ""
fi

if want gomod_malicious; then
    # 索引の読んだ範囲に無い古い部品が、悪意のある部品として公表されている
    gomod_index github.com/Example/Tool v1.2.0 2026-01-08T00:00:00Z
    alert go github.com/Example/Tool 1.2.0
    printf 'github.com/evil/dep@1.0.0\tMAL-2026-3\n' >"$WORK/osv_mal.tsv"
    OWNER_APPROVED=true check 1 "gomod の部品が悪意のある部品なら赤になる" \
        "[$COMPARE_GOTOOL,$(entry added gomod github.com/evil/dep 1.0.0)]" ""
    check_summary "| github.com/evil/dep | 1.0.0 | 2026-01-06 23:00 UTC より前 | 悪意のある部品として公表されている(MAL-2026-3 Malicious code in package (MAL-2026-3) https://advisories.invalid/MAL-2026-3) | 入らない |" \
        "gomod の部品が悪意のある部品なら赤になる(索引の読んだ範囲に無い部品は、読み始めた時刻より前に公開したと出る)"
    check_records 0 "gomod の部品が悪意のある部品なら赤になる(記録を書かない)"
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
