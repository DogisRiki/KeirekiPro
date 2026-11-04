#!/usr/bin/env bash
# =====================================================================
# lib-ci-tool-releases.sh の自動テスト(guardrails CI の escape-hatch から実行)
#
# PATH の先頭に偽の gh と curl を置き、URL の先頭を環境変数で差し替えて、
# 配布元の応答を場合ごとに返す。応答の形は、実際の配布元から1回取った答えに合わせた。
# 偽の gh と curl は、呼ばれた取り先を記録する。記録で、たどったページを確かめる。
# ライブラリは、呼び出し側と同じく bash で source して呼ぶ。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/lib-ci-tool-releases.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
N=0

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1 ($2)"
    FAILED=1
}

RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        return 0
    fi
    return 1
}

# --- 偽の gh と curl --------------------------------------------------------
# どちらも、FAKE_MAP の「取り先<TAB>HTTP の状態<TAB>応答のファイル」の行で応答を返し、
# 呼ばれた取り先を FAKE_LOG に1行ずつ書く。行の無い取り先には 404 を返す。

mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = api ] || { echo "偽の gh: 知らない呼び方です: $*" >&2; exit 9; }
key="gh $2"
printf '%s\n' "$key" >>"$FAKE_LOG"
row=$(awk -F '\t' -v k="$key" '$1 == k { print; exit }' "$FAKE_MAP")
if [ -z "$row" ]; then
    echo '{"message":"Not Found"}'
    echo "gh: Not Found (HTTP 404)" >&2
    exit 1
fi
st=$(printf '%s\n' "$row" | cut -f2)
cat "$(printf '%s\n' "$row" | cut -f3)"
if [ "$st" -ge 400 ]; then
    echo "gh: Server Error (HTTP ${st})" >&2
    exit 1
fi
SH
cat >"$WORK/bin/curl" <<'SH'
#!/usr/bin/env bash
out="" fmt="" url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
    -o) out="$2"; shift 2 ;;
    -w) fmt="$2"; shift 2 ;;
    --max-time | --retry) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
    esac
done
key="curl $url"
printf '%s\n' "$key" >>"$FAKE_LOG"
row=$(awk -F '\t' -v k="$key" '$1 == k { print; exit }' "$FAKE_MAP")
st=404 body=/dev/null
if [ -n "$row" ]; then
    st=$(printf '%s\n' "$row" | cut -f2)
    body=$(printf '%s\n' "$row" | cut -f3)
fi
[ -n "$fmt" ] && printf '%s' "$st"
if [ "$st" -ge 400 ]; then
    echo "curl: (22) The requested URL returned error: ${st}" >&2
    exit 22
fi
if [ -n "$out" ]; then cat "$body" >"$out"; else cat "$body"; fi
SH
chmod +x "$WORK/bin/gh" "$WORK/bin/curl"

export PATH="$WORK/bin:$PATH"
export CTR_NODE_DIST_URL="https://node.test/dist"
export CTR_NPM_REGISTRY="https://npm.test"
export CTR_HASHICORP_API="https://hc.test"
export FAKE_MAP FAKE_LOG

# 使い方: reset_fx。偽の応答と記録を空にする
reset_fx() {
    N=$((N + 1))
    FAKE_MAP="$WORK/map$N.tsv"
    FAKE_LOG="$WORK/log$N.txt"
    : >"$FAKE_MAP"
    : >"$FAKE_LOG"
}

# 使い方: fx <gh|curl> <取り先> <HTTP の状態> <応答の本文>
fx() {
    local f
    f="$WORK/fx$N-$(wc -l <"$FAKE_MAP" | tr -d ' ').json"
    printf '%s\n' "$4" >"$f"
    printf '%s %s\t%s\t%s\n' "$1" "$2" "$3" "$f" >>"$FAKE_MAP"
}

# 使い方: call <関数> [<引数>...]。標準出力を $WORK/out.txt に、標準エラーを
# $WORK/err.txt に、終了コードを $RC に入れる
call() {
    bash -c '. "$1" && shift && "$@"' _ "$LIB" "$@" >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
}

# 使い方: expect_out <説明> [<期待の行>...]。期待の行は「版|公開日時」の形で書く。
# 終了コードが 0 で、標準出力が期待の行と同じ並びで一致すれば通る
expect_out() {
    local desc="$1"
    shift
    if [ "$#" -eq 0 ]; then
        : >"$WORK/want.txt"
    else
        printf '%s\n' "$@" | tr '|' '\t' >"$WORK/want.txt"
    fi
    if [ "$RC" -eq 0 ] && cmp -s "$WORK/want.txt" "$WORK/out.txt"; then
        pass "$desc"
    else
        fail "$desc" "終了コード ${RC} / 出力: $(tr '\t' '|' <"$WORK/out.txt" | head -c 600) / 期待: $(tr '\t' '|' <"$WORK/want.txt" | head -c 600) / 標準エラー: $(head -c 300 "$WORK/err.txt")"
    fi
}

# 使い方: expect_err <説明> <終了コード> <標準エラーの行>。終了コードが一致し、
# 標準エラーにその行があれば通る
expect_err() {
    if [ "$RC" -eq "$2" ] && grep -qxF "$3" "$WORK/err.txt"; then
        pass "$1"
    else
        fail "$1" "終了コード ${RC} / 期待: $2 / 標準エラー: $(head -c 400 "$WORK/err.txt") / 期待の行: $3"
    fi
}

# 使い方: expect_log <説明> <取り先>...。偽の gh と curl が呼ばれた取り先が、並びも含めて一致すれば通る
expect_log() {
    local desc="$1"
    shift
    printf '%s\n' "$@" >"$WORK/want-log.txt"
    if cmp -s "$WORK/want-log.txt" "$FAKE_LOG"; then
        pass "$desc"
    else
        fail "$desc" "呼ばれた取り先: $(head -c 600 "$FAKE_LOG") / 期待: $(head -c 600 "$WORK/want-log.txt")"
    fi
}

# 使い方: node_rel <版> <published_at>。Node.js の GitHub のリリースの応答を足す
node_rel() {
    fx gh "repos/nodejs/node/releases/tags/v$1" 200 \
        "{\"tag_name\":\"v$1\",\"published_at\":\"$2\",\"created_at\":\"$2\",\"prerelease\":false,\"draft\":false}"
}

# 使い方: trivy_rel <tag_name> <published_at> <prerelease> <draft>。Trivy のリリースの1件の JSON を出す
trivy_rel() {
    printf '{"tag_name":"%s","published_at":"%s","prerelease":%s,"draft":%s}' "$1" "$2" "$3" "$4"
}

# 使い方: tf_rel <version> <timestamp_created> <is_prerelease>。Terraform のリリースの1件の JSON を出す
tf_rel() {
    printf '{"version":"%s","timestamp_created":"%s","timestamp_updated":"%s","is_prerelease":%s,"name":"terraform","builds":[]}' "$1" "$2" "$2" "$3"
}

TRIVY1="repos/aquasecurity/trivy/releases?per_page=100&page=1"
TRIVY2="repos/aquasecurity/trivy/releases?per_page=100&page=2"
TRIVY3="repos/aquasecurity/trivy/releases?per_page=100&page=3"
CODEX="https://npm.test/@openai%2fcodex"
TFLIST="https://hc.test/v1/releases/terraform?limit=20"

# --- ctr_list ----------------------------------------------------------------

if want list_no_prerelease; then
    reset_fx
    fx gh "$TRIVY1" 200 "[$(trivy_rel v0.78.0 2026-10-28T00:00:00Z true false),
        $(trivy_rel v0.77.0 2026-10-27T00:00:00Z false true),
        $(trivy_rel v0.76.2-rc1 2026-10-26T00:00:00Z false false),
        $(trivy_rel v0.76.1 2026-10-21T11:18:34Z false false),
        $(trivy_rel v0.76.0 2026-10-14T11:45:44Z false false)]"
    call ctr_list trivy 0.76.0
    expect_out "試作の版を出さない(Trivy の prerelease と draft と -rc の版)" "0.76.1|2026-10-21T11:18:34Z"

    reset_fx
    fx curl "https://hc.test/v1/releases/terraform/1.17.0" 200 "$(tf_rel 1.17.0 2026-10-21T17:33:56.648Z false)"
    fx curl "$TFLIST" 200 "[$(tf_rel 1.18.0 2026-10-29T00:00:00.000Z true),
        $(tf_rel 1.17.2-rc1 2026-10-28T19:00:00.000Z true),
        $(tf_rel 1.17.1 2026-10-28T18:03:57.170Z false),
        $(tf_rel 1.17.0 2026-10-21T17:33:56.648Z false),
        $(tf_rel 1.16.6 2026-10-14T09:32:40.591Z false)]"
    call ctr_list terraform 1.17.0
    expect_out "試作の版を出さない(Terraform の is_prerelease と -rc の版)" "1.17.1|2026-10-28T18:03:57Z"

    reset_fx
    fx curl "$CODEX" 200 '{"time":{"created":"2025-04-01T00:00:00.000Z","modified":"2026-10-30T00:00:00.000Z",
        "0.147.0":"2026-08-07T01:47:21.081Z","0.148.0-alpha.1":"2026-08-10T00:00:00.000Z",
        "0.148.0-alpha.1.1":"2026-08-11T00:00:00.000Z","0.148.0":"2026-08-14T09:00:00.000Z"}}'
    call ctr_list codex 0.147.0
    expect_out "試作の版を出さない(Codex CLI の -alpha の版)" "0.148.0|2026-08-14T09:00:00Z"
fi

if want list_codex_cpu; then
    reset_fx
    fx curl "$CODEX" 200 '{"time":{"created":"2025-04-01T00:00:00.000Z","modified":"2026-10-30T00:00:00.000Z",
        "0.147.0":"2026-08-07T01:47:21.081Z","0.147.0-linux-x64":"2026-08-07T01:46:00.000Z",
        "0.148.0-linux-x64":"2026-08-14T08:59:00.000Z","0.148.0-darwin-arm64":"2026-08-14T08:58:00.000Z",
        "0.148.0-win32-x64":"2026-08-14T08:57:00.000Z","0.148.0":"2026-08-14T09:00:00.000Z"}}'
    call ctr_list codex 0.147.0
    expect_out "Codex CLI の CPU ごとのパッケージの版を出さない" "0.148.0|2026-08-14T09:00:00Z"
fi

if want list_not_older; then
    reset_fx
    fx curl "https://node.test/dist/index.json" 200 '[
        {"version":"v24.23.0","date":"2026-10-30","lts":"Krypton"},
        {"version":"v24.22.10","date":"2026-10-29","lts":"Krypton"},
        {"version":"v24.22.2","date":"2026-10-28","lts":"Krypton"},
        {"version":"v24.22.1","date":"2026-10-21","lts":"Krypton"},
        {"version":"v24.22.0","date":"2026-10-14","lts":"Krypton"},
        {"version":"v24.9.0","date":"2026-01-14","lts":"Krypton"}]'
    node_rel 24.23.0 2026-10-30T10:00:00Z
    node_rel 24.22.10 2026-10-29T10:00:00Z
    node_rel 24.22.2 2026-10-28T10:00:00Z
    call ctr_list node 24.22.1
    expect_out "今の版以下の版を出さず、新しい順に並べる" \
        "24.23.0|2026-10-30T10:00:00Z" "24.22.10|2026-10-29T10:00:00Z" "24.22.2|2026-10-28T10:00:00Z"
fi

if want list_node_published; then
    reset_fx
    fx curl "https://node.test/dist/index.json" 200 '[
        {"version":"v24.22.2","date":"2026-10-20","lts":"Krypton"},
        {"version":"v24.22.1","date":"2026-10-14","lts":"Krypton"}]'
    node_rel 24.22.2 2026-10-21T10:38:25Z
    call ctr_list node 24.22.1
    expect_out "Node.js の公開日時に index.json の date ではなく GitHub の published_at を使う" \
        "24.22.2|2026-10-21T10:38:25Z"
    expect_log "Node.js の公開日時を GitHub の v<版> のリリースから取る" \
        "curl https://node.test/dist/index.json" "gh repos/nodejs/node/releases/tags/v24.22.2"
fi

if want list_terraform_after; then
    reset_fx
    fx curl "https://hc.test/v1/releases/terraform/1.16.0" 200 "$(tf_rel 1.16.0 2026-08-01T00:00:00.000Z false)"
    page1="" want1=()
    for i in $(seq 0 19); do
        v="1.17.$((19 - i))"
        d=$(printf '2026-10-%02dT00:00:00' $((28 - i)))
        page1+="${page1:+,}$(tf_rel "$v" "${d}.000Z" false)"
        want1+=("${v}|${d}Z")
    done
    page2="$(tf_rel 1.16.1 2026-09-01T00:00:00.000Z false),$(tf_rel 1.16.1-rc1 2026-08-20T00:00:00.000Z true)"
    for k in $(seq 18 -1 1); do
        page2+=",$(tf_rel "1.15.$k" "$(printf '2026-07-%02dT00:00:00.000Z' $((k + 10)))" false)"
    done
    fx curl "$TFLIST" 200 "[$page1]"
    fx curl "${TFLIST}&after=2026-10-09T00:00:00.000Z" 200 "[$page2]"
    call ctr_list terraform 1.16.0
    expect_out "Terraform の一覧を after= でたどり、今の版より新しい版をすべて出す" \
        "${want1[@]}" "1.16.1|2026-09-01T00:00:00Z"
    expect_log "Terraform の一覧を after= でたどり、今の版より古い版で止まる" \
        "curl https://hc.test/v1/releases/terraform/1.16.0" "curl $TFLIST" \
        "curl ${TFLIST}&after=2026-10-09T00:00:00.000Z"
fi

if want list_trivy_pages; then
    reset_fx
    fx gh "$TRIVY1" 200 "[$(trivy_rel v0.76.1 2026-10-21T11:18:34Z false false),
        $(trivy_rel v0.76.0 2026-10-14T11:45:44Z false false),
        $(trivy_rel v0.75.0 2026-10-01T13:34:13Z false false)]"
    fx gh "$TRIVY2" 200 "[$(trivy_rel v0.74.0 2026-09-20T00:00:00Z false false),
        $(trivy_rel v0.70.0 2026-07-01T00:00:00Z false false),
        $(trivy_rel v0.69.0 2026-06-01T00:00:00Z false false)]"
    fx gh "$TRIVY3" 200 "[$(trivy_rel v0.68.0 2026-05-01T00:00:00Z false false)]"
    call ctr_list trivy 0.70.0
    expect_out "Trivy の一覧を、今の版より古い版のあるページまでたどる" \
        "0.76.1|2026-10-21T11:18:34Z" "0.76.0|2026-10-14T11:45:44Z" "0.75.0|2026-10-01T13:34:13Z" \
        "0.74.0|2026-09-20T00:00:00Z"
    expect_log "Trivy の一覧を、今の版より古い版のあるページで止める" "gh $TRIVY1" "gh $TRIVY2"
fi

if want list_ts_format; then
    reset_fx
    fx curl "$CODEX" 200 '{"time":{"0.147.0":"2026-08-07T01:47:21.081Z","0.148.0":"2026-08-14T09:00:00.5Z"}}'
    call ctr_list codex 0.147.0
    expect_out "公開日時を YYYY-MM-DDTHH:MM:SSZ の形にそろえる(Codex CLI)" "0.148.0|2026-08-14T09:00:00Z"
    call ctr_published codex 0.147.0
    expect_out "ctr_published が公開日時を YYYY-MM-DDTHH:MM:SSZ の形で出す(Codex CLI)" "2026-08-07T01:47:21Z"

    reset_fx
    fx curl "https://hc.test/v1/releases/terraform/1.17.1" 200 "$(tf_rel 1.17.1 2026-10-28T18:03:57.170Z false)"
    call ctr_published terraform 1.17.1
    expect_out "公開日時を YYYY-MM-DDTHH:MM:SSZ の形にそろえる(Terraform)" "2026-10-28T18:03:57Z"

    reset_fx
    fx gh "repos/aquasecurity/trivy/releases/tags/v0.76.1" 200 "$(trivy_rel v0.76.1 2026-10-21T11:18:34Z false false)"
    call ctr_published trivy 0.76.1
    expect_out "ctr_published が Trivy の published_at をそのまま出す" "2026-10-21T11:18:34Z"
fi

if want list_other_major; then
    reset_fx
    fx curl "https://node.test/dist/index.json" 200 '[
        {"version":"v26.1.0","date":"2026-10-30","lts":false},
        {"version":"v25.0.0","date":"2026-10-29","lts":false},
        {"version":"v24.23.0","date":"2026-10-28","lts":"Krypton"},
        {"version":"v24.22.1","date":"2026-10-21","lts":"Krypton"}]'
    node_rel 24.23.0 2026-10-28T10:00:00Z
    node_rel 25.0.0 2026-10-29T10:00:00Z
    node_rel 26.1.0 2026-10-30T10:00:00Z
    call ctr_list node 24.22.1
    expect_out "メジャー版の違う版を出さない(Node.js)" "24.23.0|2026-10-28T10:00:00Z"

    reset_fx
    fx curl "$CODEX" 200 '{"time":{"0.147.0":"2026-08-07T01:47:21.081Z","1.0.0":"2026-09-01T00:00:00.000Z"}}'
    call ctr_list codex 0.147.0
    expect_out "メジャー版の違う版を出さない(Codex CLI)"
fi

# --- ctr_notes_url -----------------------------------------------------------

if want notes_url; then
    call ctr_notes_url node 24.22.2
    expect_out "道具ごとの変更点の文書の URL を出す(Node.js)" "https://github.com/nodejs/node/releases/tag/v24.22.2"
    call ctr_notes_url trivy 0.76.1
    expect_out "道具ごとの変更点の文書の URL を出す(Trivy)" "https://github.com/aquasecurity/trivy/releases/tag/v0.76.1"
    call ctr_notes_url codex v0.148.0
    expect_out "道具ごとの変更点の文書の URL を出す(Codex CLI)" "https://github.com/openai/codex/releases/tag/rust-v0.148.0"
    call ctr_notes_url terraform 1.17.1
    expect_out "道具ごとの変更点の文書の URL を出す(Terraform)" "https://github.com/hashicorp/terraform/releases/tag/v1.17.1"
fi

# --- 取れなかったとき -------------------------------------------------------

if want fetch_fail; then
    reset_fx
    fx curl "https://node.test/dist/index.json" 200 '[{"version":"v24.23.0","date":"2026-10-28"},{"version":"v24.22.1","date":"2026-10-21"}]'
    call ctr_list node 24.22.1
    expect_err "問い合わせが失敗したら、道具と版と取り先と理由を標準エラーに出して 1 で終わる(gh)" 1 \
        "node 24.23.0: GitHub の repos/nodejs/node/releases/tags/v24.23.0 から published_at を取れませんでした(HTTP 404)"

    reset_fx
    fx curl "https://hc.test/v1/releases/terraform/1.16.0" 503 '{"message":"unavailable"}'
    call ctr_list terraform 1.16.0
    expect_err "問い合わせが失敗したら、道具と版と取り先と理由を標準エラーに出して 1 で終わる(curl)" 1 \
        "terraform 1.16.0: https://hc.test/v1/releases/terraform/1.16.0 から timestamp_created を取れませんでした(HTTP 503)"

    reset_fx
    fx gh "$TRIVY1" 502 '{"message":"Bad Gateway"}'
    call ctr_list trivy 0.76.0
    expect_err "問い合わせが失敗したら、道具と版と取り先と理由を標準エラーに出して 1 で終わる(Trivy の一覧)" 1 \
        "trivy 0.76.0: GitHub の ${TRIVY1} から tag_name を取れませんでした(HTTP 502)"

    reset_fx
    fx curl "$CODEX" 200 '<html>not json</html>'
    call ctr_list codex 0.147.0
    expect_err "応答が JSON として読めなければ、理由を出して 1 で終わる" 1 \
        "codex 0.147.0: ${CODEX} から time を取れませんでした(応答が JSON として読めません)"
fi

if want field_missing; then
    reset_fx
    fx gh "repos/nodejs/node/releases/tags/v24.22.2" 200 '{"tag_name":"v24.22.2"}'
    call ctr_published node 24.22.2
    expect_err "応答に欄が無ければ、欄が無いことを理由に出して 1 で終わる(Node.js の published_at)" 1 \
        "node 24.22.2: GitHub の repos/nodejs/node/releases/tags/v24.22.2 から published_at を取れませんでした(応答に欄がありません)"

    reset_fx
    fx curl "$CODEX" 200 '{"time":{"0.147.0":"2026-08-07T01:47:21.081Z"}}'
    call ctr_published codex 0.148.0
    expect_err "応答に欄が無ければ、欄が無いことを理由に出して 1 で終わる(Codex CLI の time)" 1 \
        "codex 0.148.0: ${CODEX} から time.0.148.0 を取れませんでした(応答に欄がありません)"

    reset_fx
    fx curl "$CODEX" 200 '{"name":"@openai/codex"}'
    call ctr_list codex 0.147.0
    expect_err "応答に欄が無ければ、欄が無いことを理由に出して 1 で終わる(Codex CLI の一覧の time)" 1 \
        "codex 0.147.0: ${CODEX} から time を取れませんでした(応答に欄がありません)"

    reset_fx
    fx gh "$TRIVY1" 200 '[{"tag_name":"v0.76.1","prerelease":false,"draft":false},{"tag_name":"v0.76.0","published_at":"2026-10-14T11:45:44Z","prerelease":false,"draft":false}]'
    call ctr_list trivy 0.76.0
    expect_err "応答に欄が無ければ、欄が無いことを理由に出して 1 で終わる(Trivy の published_at)" 1 \
        "trivy 0.76.1: GitHub の ${TRIVY1} から published_at を取れませんでした(応答に欄がありません)"

    reset_fx
    fx curl "https://hc.test/v1/releases/terraform/1.16.0" 200 '{"version":"1.16.0"}'
    call ctr_list terraform 1.16.0
    expect_err "応答に欄が無ければ、欄が無いことを理由に出して 1 で終わる(Terraform の timestamp_created)" 1 \
        "terraform 1.16.0: https://hc.test/v1/releases/terraform/1.16.0 から timestamp_created を取れませんでした(応答に欄がありません)"
fi

if want list_page_cap; then
    reset_fx
    for p in $(seq 1 30); do
        fx gh "repos/aquasecurity/trivy/releases?per_page=100&page=${p}" 200 \
            "[$(trivy_rel "v0.$((200 - p)).0" 2026-10-21T11:18:34Z false false)]"
    done
    call ctr_list trivy 0.1.0
    expect_err "Trivy の一覧を30ページたどっても今の版に届かなければ、途中までの一覧を出さずに 1 で終わる" 1 \
        "trivy 0.1.0: GitHub の repos/aquasecurity/trivy/releases?per_page=100&page=30 から tag_name を取れませんでした(30 ページをたどっても今の版に届きません)"

    reset_fx
    fx curl "https://hc.test/v1/releases/terraform/1.0.0" 200 "$(tf_rel 1.0.0 2020-01-01T00:00:00.000Z false)"
    # どのページも、今の版より新しい20件を返す。2ページ目からは同じ after= の URL になる
    page=""
    for i in $(seq 1 20); do
        page+="${page:+,}$(tf_rel "1.$((100 - i)).0" 2026-10-28T18:03:57.170Z false)"
    done
    fx curl "$TFLIST" 200 "[$page]"
    fx curl "${TFLIST}&after=2026-10-28T18:03:57.170Z" 200 "[$page]"
    call ctr_list terraform 1.0.0
    expect_err "Terraform の一覧を50ページたどっても今の版に届かなければ、途中までの一覧を出さずに 1 で終わる" 1 \
        "terraform 1.0.0: ${TFLIST}&after=2026-10-28T18:03:57.170Z から version を取れませんでした(50 ページをたどっても今の版に届きません)"
    n=$(grep -c "^curl ${TFLIST}" "$FAKE_LOG")
    if [ "$n" -eq 50 ]; then
        pass "Terraform の一覧を50ページまでたどる"
    else
        fail "Terraform の一覧を50ページまでたどる" "たどったページ: ${n}"
    fi
fi

if want list_tf_field; then
    reset_fx
    fx curl "https://hc.test/v1/releases/terraform/1.16.0" 200 "$(tf_rel 1.16.0 2026-08-01T00:00:00.000Z false)"
    fx curl "$TFLIST" 200 '[{"version":"1.17.0","is_prerelease":false}]'
    call ctr_list terraform 1.16.0
    expect_err "Terraform の一覧の要素に timestamp_created が無ければ、その欄の名前を出して 1 で終わる" 1 \
        "terraform 1.16.0: ${TFLIST} から timestamp_created を取れませんでした(応答に欄がありません)"
fi

# --- ctr_image / ctr_age_ok / ctr_pass_at / ci_tool_age_check ------------------

export CTR_DOCKER_HUB="https://hub.test"
D1="sha256:c86ecead9e55a5210ac1727de38a4ca840bf03dcaf34dc9749addbf383b1920c"
D2="sha256:a5d5a5a892c98f60fcbfa81eac2a40fc19e7b3fa7719bccae10ff6111d22524a"
# 2026-11-04T00:00:00Z
NOW=1793750400

# 使い方: hub_tag <名前空間> <名前> <タグ> <digest> <tag_last_pushed>。Docker Hub のタグの応答を足す
hub_tag() {
    fx curl "https://hub.test/v2/namespaces/$1/repositories/$2/tags/$3" 200 \
        "{\"name\":\"$3\",\"digest\":\"$4\",\"media_type\":\"application/vnd.oci.image.index.v1+json\",\"last_updated\":\"$5\",\"tag_last_pulled\":\"2026-11-04T00:45:42.744566177Z\",\"tag_last_pushed\":\"$5\",\"tag_status\":\"active\",\"images\":[]}"
}

ROOT="$WORK/root"
mkdir -p "$ROOT/.github"
cat >"$ROOT/.github/ci-tool-versions.json" <<'JSON'
{
  "schema": 1,
  "tools": {
    "node": {
      "name": "Node.js", "inventory_name": "Node.js", "keys": ["node-version"],
      "ci": [{ "file": ".github/workflows/x.yaml", "key": "node-version" }],
      "dev": { "file": "docker/frontend/Dockerfile", "image": "node", "hub_repository": "library/node", "tag_suffix": "-bookworm-slim" }
    },
    "trivy": {
      "name": "Trivy", "inventory_name": "Trivy", "keys": ["TRIVY_VERSION"],
      "ci": [{ "file": ".github/workflows/x.yaml", "key": "TRIVY_VERSION" }]
    },
    "terraform": {
      "name": "Terraform", "inventory_name": "Terraform", "keys": ["TF_VERSION"],
      "ci": [{ "file": ".github/workflows/x.yaml", "key": "TF_VERSION" }],
      "dev": { "file": "docker/terraform/Dockerfile", "image": "hashicorp/terraform", "hub_repository": "hashicorp/terraform", "tag_suffix": "" }
    }
  },
  "excluded": []
}
JSON

if want image; then
    reset_fx
    hub_tag library node 24.22.2-bookworm-slim "$D1" 2026-10-28T23:40:10.627185Z
    call ctr_image library/node 24.22.2-bookworm-slim
    expect_out "ctr_image がタグの digest と、そろえた tag_last_pushed を出す" "${D1}|2026-10-28T23:40:10Z"
    expect_log "ctr_image が Docker Hub の名前空間と名前とタグの URL から取る" \
        "curl https://hub.test/v2/namespaces/library/repositories/node/tags/24.22.2-bookworm-slim"

    reset_fx
    fx curl "https://hub.test/v2/namespaces/hashicorp/repositories/terraform/tags/1.17.1" 200 '{"name":"1.17.1","tag_last_pushed":"2026-10-28T18:04:31.856032Z"}'
    call ctr_image hashicorp/terraform 1.17.1
    expect_err "ctr_image が、応答に digest が無ければ、欄が無いことを理由に出して 1 で終わる" 1 \
        "hashicorp/terraform 1.17.1: https://hub.test/v2/namespaces/hashicorp/repositories/terraform/tags/1.17.1 から digest を取れませんでした(応答に欄がありません)"
fi

if want age_72h; then
    # 公開日時 2026-10-28T23:40:10Z は 1793230810 秒。72時間は 259200 秒
    NOW_EPOCH=$((1793230810 + 259200)) call ctr_age_ok 2026-10-28T23:40:10Z
    expect_out "公開からちょうど72時間で通る"
fi

if want age_71h59m; then
    NOW_EPOCH=$((1793230810 + 259200 - 60)) call ctr_age_ok 2026-10-28T23:40:10Z
    if [ "$RC" -eq 1 ]; then pass "公開から71時間59分では通らない"; else fail "公開から71時間59分では通らない" "終了コード ${RC}"; fi
    NOW_EPOCH=$((1793230810 - 3600)) call ctr_age_ok 2026-10-28T23:40:10Z
    if [ "$RC" -eq 1 ]; then pass "公開日時が今より後なら通らない"; else fail "公開日時が今より後なら通らない" "終了コード ${RC}"; fi
fi

if want pass_at; then
    call ctr_pass_at 2026-10-28T23:40:10Z
    expect_out "通る日時に公開日時の72時間後を出す" "2026-10-31T23:40:10Z"
    call ctr_pass_at 2028-02-27T12:00:00Z
    expect_out "通る日時を、うるう年の2月29日をまたいで数える" "2028-03-01T12:00:00Z"
    call ctr_pass_at 2026-12-30T01:02:03Z
    expect_out "通る日時を、年をまたいで数える" "2027-01-02T01:02:03Z"
    call ctr_pass_at 2026-10-28
    expect_err "日時の形が違えば 2 で終わる" 2 "lib-ci-tool-releases: 日時の形が違います: 2026-10-28"
fi

if want check_ok; then
    reset_fx
    node_rel 24.22.2 2026-10-28T10:00:00Z
    hub_tag library node 24.22.2-bookworm-slim "$D1" 2026-10-28T23:40:10.627185Z
    NOW_EPOCH=$NOW call ci_tool_age_check "$ROOT" node 24.22.2 24.22.2 "$D1"
    expect_out "72時間経った CI の版と開発環境の版に ok を出し、0 で終わる" \
        "ci|24.22.2|2026-10-28T10:00:00Z|2026-10-31T10:00:00Z|ok|-" \
        "dev|24.22.2|2026-10-28T23:40:10Z|2026-10-31T23:40:10Z|ok|-"
fi

if want check_ng_times; then
    reset_fx
    node_rel 24.22.3 2026-11-01T01:00:00Z
    NOW_EPOCH=$NOW call ci_tool_age_check "$ROOT" node 24.22.3 - -
    if [ "$RC" -eq 1 ] && [ "$(cat "$WORK/out.txt")" = "$(printf 'ci\t24.22.3\t2026-11-01T01:00:00Z\t2026-11-04T01:00:00Z\tng\t公開から72時間経っていません')" ]; then
        pass "ng の行に公開日時と通る日時を出す"
    else
        fail "ng の行に公開日時と通る日時を出す" "終了コード ${RC} / 出力: $(tr '\t' '|' <"$WORK/out.txt")"
    fi
fi

# 使い方: expect_rows <説明> <終了コード> <期待の行>...。期待の行は欄を「|」で区切って書く
expect_rows() {
    local desc="$1" rc="$2"
    shift 2
    printf '%s\n' "$@" | tr '|' '\t' >"$WORK/want.txt"
    if [ "$RC" -eq "$rc" ] && cmp -s "$WORK/want.txt" "$WORK/out.txt"; then
        pass "$desc"
    else
        fail "$desc" "終了コード ${RC} / 期待: ${rc} / 出力: $(tr '\t' '|' <"$WORK/out.txt" | head -c 600) / 期待の出力: $(tr '\t' '|' <"$WORK/want.txt" | head -c 600)"
    fi
}

if want check_dev_young; then
    reset_fx
    node_rel 24.22.2 2026-10-20T10:00:00Z
    hub_tag library node 24.22.2-bookworm-slim "$D1" 2026-11-01T01:00:00.123456Z
    NOW_EPOCH=$NOW call ci_tool_age_check "$ROOT" node - 24.22.2 "$D1"
    expect_rows "タグの公開から72時間経っていない開発環境の版に ng を出す" 1 \
        "dev|24.22.2|2026-11-01T01:00:00Z|2026-11-04T01:00:00Z|ng|公開から72時間経っていません"
fi

if want check_dev_release_later; then
    reset_fx
    node_rel 24.22.2 2026-11-02T00:00:00Z
    hub_tag library node 24.22.2-bookworm-slim "$D1" 2026-10-28T23:40:10.627185Z
    NOW_EPOCH=$NOW call ci_tool_age_check "$ROOT" node - 24.22.2 "$D1"
    expect_rows "版の公開がタグの公開より遅い開発環境の版は、版の公開から72時間を数える" 1 \
        "dev|24.22.2|2026-11-02T00:00:00Z|2026-11-05T00:00:00Z|ng|公開から72時間経っていません"
fi

if want check_dev_digest; then
    reset_fx
    node_rel 24.22.2 2026-10-20T10:00:00Z
    hub_tag library node 24.22.2-bookworm-slim "$D1" 2026-10-28T23:40:10.627185Z
    NOW_EPOCH=$NOW call ci_tool_age_check "$ROOT" node - 24.22.2 "$D2"
    expect_rows "digest がタグの今の digest と違う開発環境の版に ng を出す" 1 \
        "dev|24.22.2|2026-10-28T23:40:10Z|2026-10-31T23:40:10Z|ng|digest が配布元のイメージのタグ library/node:24.22.2-bookworm-slim の今の digest ${D1} と違います"
fi

if want check_fetch_error; then
    reset_fx
    node_rel 24.22.2 2026-10-20T10:00:00Z
    NOW_EPOCH=$NOW call ci_tool_age_check "$ROOT" node 24.22.3 24.22.2 "$D1"
    expect_rows "問い合わせが失敗したら error を出し、公開日時と通る日時の欄を - にする" 1 \
        "ci|24.22.3|-|-|error|node 24.22.3: GitHub の repos/nodejs/node/releases/tags/v24.22.3 から published_at を取れませんでした(HTTP 404)" \
        "dev|24.22.2|-|-|error|library/node 24.22.2-bookworm-slim: https://hub.test/v2/namespaces/library/repositories/node/tags/24.22.2-bookworm-slim から digest を取れませんでした(HTTP 404。タグがありません)"
fi

if want check_no_tag; then
    reset_fx
    fx curl "https://hc.test/v1/releases/terraform/1.17.2" 200 "$(tf_rel 1.17.2 2026-10-20T00:00:00.000Z false)"
    NOW_EPOCH=$NOW call ci_tool_age_check "$ROOT" terraform - 1.17.2 "$D2"
    expect_rows "イメージのタグが無ければ error を出す" 1 \
        "dev|1.17.2|-|-|error|hashicorp/terraform 1.17.2: https://hub.test/v2/namespaces/hashicorp/repositories/terraform/tags/1.17.2 から digest を取れませんでした(HTTP 404。タグがありません)"
    expect_log "tag_suffix の空の道具では、版をそのままタグにして問い合わせる" \
        "curl https://hc.test/v1/releases/terraform/1.17.2" \
        "curl https://hub.test/v2/namespaces/hashicorp/repositories/terraform/tags/1.17.2"
fi

if want check_bad_args; then
    reset_fx
    call ci_tool_age_check "$ROOT" trivy - 0.76.1 -
    expect_err "データのファイルに開発環境の書き場所の無い道具に開発環境の版を渡すと 2 で終わる" 2 \
        "lib-ci-tool-releases: データのファイルに trivy の開発環境の書き場所がありません"
    call ci_tool_age_check "$ROOT" node - 24.22.2 sha256:xyz
    expect_err "digest の形が違えば 2 で終わる" 2 "lib-ci-tool-releases: digest の形が違います: sha256:xyz"
    call ci_tool_age_check "$ROOT" java 21.0.1 - -
    expect_err "道具の名前が違えば 2 で終わる" 2 "lib-ci-tool-releases: 道具の名前が違います: java"
    mkdir -p "$WORK/badhub/.github"
    jq '.tools.node.dev.hub_repository = ""' "$ROOT/.github/ci-tool-versions.json" >"$WORK/badhub/.github/ci-tool-versions.json"
    call ci_tool_age_check "$WORK/badhub" node - 24.22.2 "$D1"
    expect_err "データのファイルの hub_repository の形が違えば 2 で終わる" 2 \
        "lib-ci-tool-releases: データのファイルの node の hub_repository か tag_suffix の形が違います: hub_repository は「」、tag_suffix は「-bookworm-slim」です"
    if [ ! -s "$FAKE_LOG" ]; then pass "引数の形が違えば、配布元に問い合わせない"; else fail "引数の形が違えば、配布元に問い合わせない" "$(head -c 300 "$FAKE_LOG")"; fi
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    FAILED=1
fi

exit "$FAILED"
