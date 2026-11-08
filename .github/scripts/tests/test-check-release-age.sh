#!/usr/bin/env bash
# =====================================================================
# check-release-age.sh の自動テスト(dependabot-auto-merge から実行)
#
# gh を PATH の先頭の偽物で置き換え、判定の出力・終了コード・PRへのコメントを確かめる。
#   終了コード 0 = 判定できた(標準出力に decision= と reason=)
#   終了コード 2 = 判定できなかった(予約してよいという判定を出さない)
#
# gh の偽物は実APIの形のJSONをそのまま返し、応答の解釈は本体に任せる。
# 想定していない呼び出しは失敗させ、呼び出しの記録を残す。
# curl・docker など GitHub の API 以外に問い合わせる道具も偽物に置き換え、
# 呼ばれたら記録する(公開日時にイメージの中の作成日時を使わないことの確認)。
# ただし curl は、Go のモジュールの索引(偽の置き場 http://index.test)を読むときだけ、
# $STUB_GOMOD_PAGE の中身を返す。
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-release-age.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

mkdir -p "$WORK/bin"

# --- gh の偽物 -------------------------------------------------------------------
# 呼び出しの引数を $STUB_CALLS に1行ずつ記録する。
#   PR のファイル一覧: $STUB_FILES の中身(STUB_FAIL_FILES で失敗)
#   リリース: STUB_RELEASE_MODE(ok / 404 / 500 / invalid / missing / null)
#             ok のときは STUB_PUBLISHED を published_at に入れる
#   トークンの利用者: login が keirekipro-bot の利用者(STUB_USER_MODE が fail で失敗、
#             nologin で login の無い応答)
#   コメント一覧: $STUB_COMMENTS の中身(STUB_FAIL_COMMENTS で失敗)
#   コメントの投稿: 本文を $STUB_POSTED_DIR に連番で保存(STUB_FAIL_POST で失敗)
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
case "$*" in
"api --paginate repos/owner/repo/pulls/7/files")
    if [ -n "${STUB_FAIL_FILES:-}" ]; then
        echo "gh: Server Error (HTTP 500)" >&2
        exit 1
    fi
    cat "${STUB_FILES:?}"
    ;;
"api repos/terraform-linters/tflint/releases/tags/"*)
    last="${!#}"
    tag="${last##*/}"
    case "${STUB_RELEASE_MODE:?}" in
    ok)
        printf '{"tag_name":"%s","created_at":"2020-01-01T00:00:00Z","published_at":"%s","draft":false}\n' \
            "$tag" "${STUB_PUBLISHED:?}"
        ;;
    404)
        printf '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}\n'
        echo "gh: Not Found (HTTP 404)" >&2
        exit 1
        ;;
    500)
        echo "gh: Server Error (HTTP 500)" >&2
        exit 1
        ;;
    invalid)
        printf '<html><body>oops</body></html>\n'
        ;;
    missing)
        printf '{"tag_name":"%s","created_at":"2020-01-01T00:00:00Z"}\n' "$tag"
        ;;
    null)
        printf '{"tag_name":"%s","created_at":"2020-01-01T00:00:00Z","published_at":null}\n' "$tag"
        ;;
    esac
    ;;
"api user")
    case "${STUB_USER_MODE:-ok}" in
    fail)
        echo "gh: Resource not accessible by integration (HTTP 403)" >&2
        exit 1
        ;;
    nologin)
        printf '{"message":"unexpected"}\n'
        ;;
    *)
        printf '{"login":"keirekipro-bot","id":1001,"type":"User"}\n'
        ;;
    esac
    ;;
"api --paginate repos/owner/repo/issues/7/comments")
    if [ -n "${STUB_FAIL_COMMENTS:-}" ]; then
        echo "gh: Server Error (HTTP 500)" >&2
        exit 1
    fi
    cat "${STUB_COMMENTS:?}"
    ;;
"pr comment 7 --repo owner/repo --body-file "*)
    if [ -n "${STUB_FAIL_POST:-}" ]; then
        echo "gh: Forbidden (HTTP 403)" >&2
        exit 1
    fi
    n=$(find "${STUB_POSTED_DIR:?}" -type f | wc -l)
    cp "${!#}" "$STUB_POSTED_DIR/posted_$((n + 1)).md" || exit 1
    echo "https://github.com/owner/repo/pull/7#issuecomment-1"
    ;;
*)
    echo "stub: unexpected call: $*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$WORK/bin/gh"

# --- GitHub の API 以外に問い合わせる道具の偽物 -------------------------------------
# 呼ばれたら $STUB_FORBIDDEN に記録して失敗する。
for tool in wget docker skopeo crane regctl oras; do
    cat >"$WORK/bin/$tool" <<STUB
#!/usr/bin/env bash
printf '%s %s\n' "$tool" "\$*" >>"\${STUB_FORBIDDEN:?}"
exit 1
STUB
    chmod +x "$WORK/bin/$tool"
done
: >"$WORK/forbidden.log"
: >"$WORK/all-calls.log"

# curl の偽物: Go のモジュールの索引の問い合わせ(http://index.test/index?since=...)だけに答える。
#   呼び出しを $STUB_GOMOD_CALLS に記録し、$STUB_GOMOD_PAGE の中身を -o のファイルに書く。
#   STUB_GOMOD_FAIL があれば、索引を読めなかったとして失敗する。
#   索引ではない URL は $STUB_FORBIDDEN に記録して失敗する。
# 索引を区間に分けて読む動きと、ページをめくる動きは test-lib-gomod-index.sh で確かめる。
# ここでは区間の長さを73時間にして、索引を1度だけ読ませる。
cat >"$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
out="" url=""
while [ $# -gt 0 ]; do
    case "$1" in
    -o) out="$2"; shift 2 ;;
    --max-time | --retry) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
    esac
done
case "$url" in
http://index.test/index\?since=*)
    printf '%s\n' "$url" >>"${STUB_GOMOD_CALLS:?}"
    if [ -n "${STUB_GOMOD_FAIL:-}" ]; then
        echo "curl: (22) The requested URL returned error: 503" >&2
        exit 22
    fi
    cp "${STUB_GOMOD_PAGE:?}" "${out:?}"
    ;;
*)
    printf 'curl %s\n' "$url" >>"${STUB_FORBIDDEN:?}"
    exit 1
    ;;
esac
STUB
chmod +x "$WORK/bin/curl"

# --- 差分の材料 -------------------------------------------------------------------
# 今のリポジトリの docker/terraform/Dockerfile の1行目と同じ書き方
OLD_DIGEST="cef181224b4a9cea521d8f785d50957ea3215b449e2d97e7793f222e2808d188"
NEW_DIGEST="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
OLD_LINE="FROM ghcr.io/terraform-linters/tflint:v0.60.0@sha256:${OLD_DIGEST} AS tflint"
NEW_LINE="FROM ghcr.io/terraform-linters/tflint:v0.61.0@sha256:${NEW_DIGEST} AS tflint"
SAME_TAG_NEW_DIGEST_LINE="FROM ghcr.io/terraform-linters/tflint:v0.60.0@sha256:${NEW_DIGEST} AS tflint"
TF_OLD="FROM hashicorp/terraform:1.16.4@sha256:985c0000000000000000000000000000000000000000000000000000000000aa AS terraform"
TF_NEW="FROM hashicorp/terraform:1.16.5@sha256:985c0000000000000000000000000000000000000000000000000000000000bb AS terraform"

# tflint の行を入れ替える Dockerfile の差分(patch の形)
tflint_patch() {
    printf '@@ -1,4 +1,4 @@\n-%s\n+%s\n %s\n \n' "$1" "$2" "$TF_OLD"
}

# 使い方: files_json <ファイル名> <patch> [<ファイル名> <patch> ...]
# patch に "-" を渡すと patch の無い項目(大きすぎる差分)になる
files_json() {
    local args=() i=0
    local filter='['
    while [ $# -ge 2 ]; do
        if [ "$2" = "-" ]; then
            filter="${filter}{filename: \$f${i}, status: \"modified\", additions: 9000, deletions: 9000, changes: 18000},"
            args+=(--arg "f${i}" "$1")
        else
            filter="${filter}{filename: \$f${i}, status: \"modified\", patch: \$p${i}},"
            args+=(--arg "f${i}" "$1" --arg "p${i}" "$2")
        fi
        i=$((i + 1))
        shift 2
    done
    filter="${filter%,}]"
    jq -n "${args[@]}" "$filter"
}

iso_to_epoch() {
    jq -n --arg t "$1" '$t | fromdateiso8601'
}

PUBLISHED="2026-09-20T00:00:00Z"
PUB_EPOCH=$(iso_to_epoch "$PUBLISHED") || exit 1

# --- 実行の準備 -------------------------------------------------------------------
# 各場面の前に呼び、偽物の振る舞いを既定に戻す
reset_scenario() {
    files_json "README.md" "$(printf '@@ -1 +1 @@\n-a\n+b\n')" >"$WORK/files.json"
    echo '[]' >"$WORK/comments.json"
    RELEASE_MODE="ok"
    STUB_PUB="$PUBLISHED"
    NOW="$((PUB_EPOCH + 400000))"
    FAIL_FILES=""
    FAIL_COMMENTS=""
    FAIL_POST=""
    USER_MODE="ok"
    : >"$WORK/gomod-page.ndjson"
    GOMOD_FAIL=""
}

run() {
    : >"$WORK/calls.log"
    : >"$WORK/gomod-calls.log"
    rm -rf "$WORK/posted"
    mkdir -p "$WORK/posted"
    PATH="$WORK/bin:$PATH" \
        STUB_GOMOD_CALLS="$WORK/gomod-calls.log" STUB_GOMOD_PAGE="$WORK/gomod-page.ndjson" \
        STUB_GOMOD_FAIL="$GOMOD_FAIL" GOMOD_INDEX_BASE="http://index.test" GOMOD_INDEX_SEGMENT_HOURS=73 \
        STUB_CALLS="$WORK/calls.log" STUB_FORBIDDEN="$WORK/forbidden.log" \
        STUB_FILES="$WORK/files.json" STUB_COMMENTS="$WORK/comments.json" \
        STUB_POSTED_DIR="$WORK/posted" \
        STUB_RELEASE_MODE="$RELEASE_MODE" STUB_PUBLISHED="$STUB_PUB" \
        STUB_FAIL_FILES="$FAIL_FILES" STUB_FAIL_COMMENTS="$FAIL_COMMENTS" STUB_FAIL_POST="$FAIL_POST" \
        STUB_USER_MODE="$USER_MODE" \
        GITHUB_REPOSITORY="owner/repo" GITHUB_REPOSITORY_OWNER="owner-name" GH_TOKEN="dummy" \
        NOW_EPOCH="$NOW" \
        bash "$SCRIPT" 7 >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
    cat "$WORK/calls.log" >>"$WORK/all-calls.log"
    POSTED=$(find "$WORK/posted" -type f | wc -l | tr -d ' ')
}

# --- 確かめ方 ---------------------------------------------------------------------
ok() { echo "PASS: $1"; }
ng() {
    echo "FAIL: $1"
    echo "  --- 標準出力 ---"
    sed 's/^/  /' "$WORK/out.txt"
    echo "  --- 標準エラー ---"
    sed 's/^/  /' "$WORK/err.txt"
    FAILED=1
}

# 使い方: expect_decision <説明> <decision> <reason に含まれる文字列>
expect_decision() {
    local name="$1" want="$2" want_reason="$3"
    if [ "$RC" -ne 0 ]; then
        ng "$name (終了コード 0 のはずが $RC)"
        return
    fi
    if ! grep -qx "decision=${want}" "$WORK/out.txt"; then
        ng "$name (decision=${want} が無い)"
        return
    fi
    if ! grep -q "^reason=.*${want_reason}" "$WORK/out.txt"; then
        ng "$name (reason に「${want_reason}」が無い)"
        return
    fi
    ok "$name"
}

# 判定できなかったときは終了コード 2 で、判定の行を出さない
expect_undecided() {
    local name="$1"
    if [ "$RC" -ne 2 ]; then
        ng "$name (終了コード 2 のはずが $RC)"
        return
    fi
    if grep -q '^decision=' "$WORK/out.txt"; then
        ng "$name (判定できなかったのに decision= を出している)"
        return
    fi
    ok "$name"
}

expect_posted() {
    local name="$1" want="$2"
    if [ "$POSTED" -eq "$want" ]; then
        ok "$name"
    else
        echo "FAIL: $name (コメントの数 期待 $want、実際 $POSTED)"
        FAILED=1
    fi
}

# 使い方: expect_gomod_calls <説明> <索引を読んだ回数>
expect_gomod_calls() {
    local name="$1" want="$2" got
    got=$(wc -l <"$WORK/gomod-calls.log" | tr -d ' ')
    if [ "$got" -eq "$want" ]; then
        ok "$name"
    else
        echo "FAIL: $name (索引を読んだ回数 期待 $want、実際 $got)"
        FAILED=1
    fi
}

expect_no_release_call() {
    if grep -q 'releases' "$WORK/calls.log"; then
        echo "FAIL: $1 (リリースを問い合わせている)"
        FAILED=1
    else
        ok "$1"
    fi
}

# =====================================================================
# tflint 以外の更新は、今までどおり予約する
# =====================================================================
reset_scenario
files_json \
    "frontend/package.json" "$(printf '@@ -10 +10 @@\n-    "vite": "7.1.0",\n+    "vite": "7.1.1",\n')" \
    "frontend/pnpm-lock.yaml" "-" >"$WORK/files.json"
run
expect_decision "npm の更新(ロックファイルの差分が大きく patch が無い)は reserve" reserve "tflint の更新ではない"
expect_no_release_call "npm の更新ではリリースを問い合わせない"
expect_posted "npm の更新ではコメントしない" 0

reset_scenario
files_json "backend/gradle/libs.versions.toml" \
    "$(printf '@@ -3 +3 @@\n-spring-boot = "3.5.5"\n+spring-boot = "3.5.6"\n')" >"$WORK/files.json"
run
expect_decision "gradle の更新は reserve" reserve "tflint の更新ではない"

reset_scenario
files_json "docker/terraform/Dockerfile" \
    "$(printf '@@ -1,3 +1,3 @@\n %s\n-%s\n+%s\n \n' "$OLD_LINE" "$TF_OLD" "$TF_NEW")" >"$WORK/files.json"
run
expect_decision "同じ Dockerfile の他のイメージの更新(tflint の行は前後の文脈だけ)は reserve" reserve "tflint の更新ではない"
expect_no_release_call "他のイメージの更新ではリリースを問い合わせない"

reset_scenario
files_json "docker/frontend/Dockerfile" \
    "$(printf '@@ -1 +1 @@\n-FROM node:22.1.0-bookworm-slim@sha256:%s\n+FROM node:22.2.0-bookworm-slim@sha256:%s\n' "$OLD_DIGEST" "$NEW_DIGEST")" >"$WORK/files.json"
run
expect_decision "docker の他のイメージの更新は reserve" reserve "tflint の更新ではない"

# 出力は GITHUB_OUTPUT にそのまま足せる形(key=value の2行だけ)
if [ "$(wc -l <"$WORK/out.txt" | tr -d ' ')" -eq 2 ] &&
    [ "$(grep -cE '^(decision|reason)=[^[:cntrl:]]+$' "$WORK/out.txt")" -eq 2 ]; then
    ok "標準出力は decision= と reason= の2行だけ"
else
    ng "標準出力は decision= と reason= の2行だけ"
fi

# =====================================================================
# 版が変わった: GitHub のリリースの published_at から72時間を数える
# =====================================================================
reset_scenario
tflint_patch "$OLD_LINE" "$NEW_LINE" | { p=$(cat); files_json "docker/terraform/Dockerfile" "$p"; } >"$WORK/files.json"
NOW=$((PUB_EPOCH + 259200))
run
expect_decision "公開からちょうど72時間なら reserve" reserve "72時間"
if grep -qx 'api repos/terraform-linters/tflint/releases/tags/v0.61.0' "$WORK/calls.log"; then
    ok "新しい版のタグでリリースを問い合わせる"
else
    ng "新しい版のタグでリリースを問い合わせる"
fi
expect_posted "72時間経っていればコメントしない" 0

NOW=$((PUB_EPOCH + 259199))
run
expect_decision "公開から72時間に1秒足りなければ wait" wait "72時間"
expect_posted "wait ではコメントしない" 0

NOW=$((PUB_EPOCH + 3600))
run
expect_decision "公開から1時間なら wait(リリースの created_at が古くても使わない)" wait "72時間"

# ファイルの一覧が2ページに分かれ、tflint が2ページ目にあっても読む
reset_scenario
{
    files_json "README.md" "$(printf '@@ -1 +1 @@\n-a\n+b\n')"
    tflint_patch "$OLD_LINE" "$NEW_LINE" | { p=$(cat); files_json "docker/terraform/Dockerfile" "$p"; }
} >"$WORK/files.json"
NOW=$((PUB_EPOCH + 3600))
run
expect_decision "2ページ目にある tflint の更新も見つける" wait "72時間"

# =====================================================================
# 版が同じで中身だけが変わった: 予約せず、所有者に知らせる
# =====================================================================
reset_scenario
tflint_patch "$OLD_LINE" "$SAME_TAG_NEW_DIGEST_LINE" | { p=$(cat); files_json "docker/terraform/Dockerfile" "$p"; } >"$WORK/files.json"
run
expect_decision "版が同じで digest だけ変わったら notify" notify "中身だけの更新"
expect_no_release_call "中身だけの更新ではリリースを問い合わせない"
expect_posted "中身だけの更新ではコメントを1件付ける" 1
if [ "$POSTED" -ge 1 ]; then
    body="$WORK/posted/posted_1.md"
    if [ "$(head -n 1 "$body")" = "@owner-name" ]; then
        ok "コメントの1行目は所有者へのメンション"
    else
        echo "FAIL: コメントの1行目は所有者へのメンション (実際: $(head -n 1 "$body"))"
        FAILED=1
    fi
    if [ "$(grep -v '^[[:space:]]*$' "$body" | tail -n 1)" = "<!-- release-age: digest-only -->" ]; then
        ok "コメントの最後の行は中身だけの更新の目印"
    else
        echo "FAIL: コメントの最後の行は中身だけの更新の目印 (実際: $(tail -n 1 "$body"))"
        FAILED=1
    fi
    if grep -q 'Claude Code' "$body" && grep -q '中身' "$body"; then
        ok "コメントに理由と、Claude Code に調べさせる対処が書いてある"
    else
        echo "FAIL: コメントに理由と、Claude Code に調べさせる対処が書いてある"
        FAILED=1
    fi
fi

# 自分(トークンの利用者)が書いた同じ目印のコメントがあれば重ねない
printf '[{"id":1,"user":{"login":"someone"},"body":"別の話"}]\n[{"id":2,"user":{"login":"keirekipro-bot"},"body":"@owner-name\\n前回の知らせ\\n<!-- release-age: digest-only -->"}]\n' >"$WORK/comments.json"
run
expect_decision "同じ目印のコメントがあっても判定は notify" notify "中身だけの更新"
expect_posted "自分の同じ目印のコメントが2ページ目にあればコメントを重ねない" 0
if grep -qx 'api user' "$WORK/calls.log"; then
    ok "目印を数える前にトークンの利用者を確かめる"
else
    ng "目印を数える前にトークンの利用者を確かめる"
fi

# 別の利用者が同じ目印を書いていても、知らせは止めない
printf '[{"id":5,"user":{"login":"someone"},"body":"<!-- release-age: digest-only -->"},{"id":6,"body":"<!-- release-age: digest-only -->"}]\n' >"$WORK/comments.json"
run
expect_decision "別の利用者の目印があっても判定は notify" notify "中身だけの更新"
expect_posted "別の利用者(と書いた人の分からないコメント)が同じ目印を書いていてもコメントする" 1

# 別の理由の目印しか無ければコメントする
printf '[{"id":3,"user":{"login":"keirekipro-bot"},"body":"<!-- release-age: unavailable -->"}]\n' >"$WORK/comments.json"
run
expect_posted "自分の目印でも別の理由のものしか無ければコメントする" 1

# トークンの利用者を確かめられなければ、判定できない
echo '[]' >"$WORK/comments.json"
USER_MODE="fail"
run
expect_undecided "トークンの利用者を取れなければ判定できない"
expect_posted "トークンの利用者を取れなければコメントしない" 0
USER_MODE="nologin"
run
expect_undecided "トークンの利用者の応答に login が無ければ判定できない"
USER_MODE="ok"

# =====================================================================
# 公開日時を取れない: 予約せず、所有者に知らせる
# =====================================================================
for mode in 404 500 invalid missing null; do
    reset_scenario
    tflint_patch "$OLD_LINE" "$NEW_LINE" | { p=$(cat); files_json "docker/terraform/Dockerfile" "$p"; } >"$WORK/files.json"
    RELEASE_MODE="$mode"
    run
    expect_decision "リリースの取得が ${mode} なら notify" notify "公開日時を取れない"
    expect_posted "リリースの取得が ${mode} ならコメントを1件付ける" 1
done
body="$WORK/posted/posted_1.md"
if [ -f "$body" ] && [ "$(head -n 1 "$body")" = "@owner-name" ] &&
    [ "$(grep -v '^[[:space:]]*$' "$body" | tail -n 1)" = "<!-- release-age: unavailable -->" ] &&
    grep -q '1日1回' "$body"; then
    ok "公開日時を取れないコメントはメンション・毎日の見直し・目印を持つ"
else
    echo "FAIL: 公開日時を取れないコメントはメンション・毎日の見直し・目印を持つ"
    FAILED=1
fi

reset_scenario
tflint_patch "$OLD_LINE" "$NEW_LINE" | { p=$(cat); files_json "docker/terraform/Dockerfile" "$p"; } >"$WORK/files.json"
RELEASE_MODE="404"
printf '[{"id":4,"user":{"login":"keirekipro-bot"},"body":"@owner-name\\n<!-- release-age: unavailable -->"}]\n' >"$WORK/comments.json"
run
expect_decision "公開日時を取れない目印が既にあっても判定は notify" notify "公開日時を取れない"
expect_posted "公開日時を取れない目印が既にあればコメントを重ねない" 0

# =====================================================================
# 判定できない: 終了コード 2 で、予約してよいという判定を出さない
# =====================================================================
reset_scenario
tflint_patch "$OLD_LINE" "FROM ghcr.io/terraform-linters/tflint:v0.61.0 AS tflint" |
    { p=$(cat); files_json "docker/terraform/Dockerfile" "$p"; } >"$WORK/files.json"
run
expect_undecided "tflint の行に digest が無ければ判定できない"
expect_posted "判定できないときはコメントしない" 0

reset_scenario
tflint_patch "$OLD_LINE" "FROM --platform=linux/amd64 ghcr.io/terraform-linters/tflint:v0.61.0@sha256:${NEW_DIGEST} AS tflint" |
    { p=$(cat); files_json "docker/terraform/Dockerfile" "$p"; } >"$WORK/files.json"
run
expect_undecided "tflint の行が想定と違う書き方なら判定できない"

reset_scenario
tflint_patch "$OLD_LINE" "FROM ghcr.io/terraform-linters/tflint:v0.61.0/../x@sha256:${NEW_DIGEST} AS tflint" |
    { p=$(cat); files_json "docker/terraform/Dockerfile" "$p"; } >"$WORK/files.json"
run
expect_undecided "タグに使えない文字があれば判定できない"
expect_no_release_call "タグを読み取れないときはリリースを問い合わせない"

# 読める行の組がそろっていても、読めない行が別にあれば予約に倒さない
reset_scenario
files_json "docker/terraform/Dockerfile" \
    "$(printf '@@ -1,3 +1,4 @@\n-%s\n+%s\n+COPY --from=ghcr.io/terraform-linters/tflint:v0.61.0 /usr/local/bin/tflint /usr/local/bin/\n %s\n \n' "$OLD_LINE" "$NEW_LINE" "$TF_OLD")" >"$WORK/files.json"
NOW=$((PUB_EPOCH + 400000))
run
expect_undecided "読める行の組のほかに tflint を含む読めない行があれば判定できない"

reset_scenario
files_json "docker/terraform/Dockerfile" "$(printf '@@ -1,2 +1,3 @@\n+%s\n %s\n \n' "$NEW_LINE" "$TF_OLD")" >"$WORK/files.json"
run
expect_undecided "tflint の行が足されただけ(前の行が無い)なら判定できない"

reset_scenario
files_json "docker/terraform/Dockerfile" "-" >"$WORK/files.json"
run
expect_undecided "Dockerfile の差分に patch が無ければ判定できない"

reset_scenario
files_json "docker/terraform/dockerfile" "-" >"$WORK/files.json"
run
expect_undecided "小文字の dockerfile の差分に patch が無ければ判定できない"

reset_scenario
files_json "docker/terraform/Containerfile" "-" >"$WORK/files.json"
run
expect_undecided "Containerfile の差分に patch が無ければ判定できない"

reset_scenario
files_json "docker/tools/lint.containerfile" "-" >"$WORK/files.json"
run
expect_undecided "拡張子が containerfile のファイルの差分に patch が無ければ判定できない"

reset_scenario
FAIL_FILES=1
run
expect_undecided "PR のファイル一覧を取れなければ判定できない"

reset_scenario
printf '{"message":"Not Found"}\n' >"$WORK/files.json"
run
expect_undecided "PR のファイル一覧が配列でなければ判定できない"

reset_scenario
printf 'not json\n' >"$WORK/files.json"
run
expect_undecided "PR のファイル一覧が JSON でなければ判定できない"

# 知らせを確実に届けられないときも、判定できなかったことにする
reset_scenario
tflint_patch "$OLD_LINE" "$SAME_TAG_NEW_DIGEST_LINE" | { p=$(cat); files_json "docker/terraform/Dockerfile" "$p"; } >"$WORK/files.json"
FAIL_POST=1
run
expect_undecided "コメントの投稿に失敗したら判定できない"

reset_scenario
tflint_patch "$OLD_LINE" "$SAME_TAG_NEW_DIGEST_LINE" | { p=$(cat); files_json "docker/terraform/Dockerfile" "$p"; } >"$WORK/files.json"
FAIL_COMMENTS=1
run
expect_undecided "既存のコメントを読めなければ判定できない"
expect_posted "既存のコメントを読めなければコメントしない" 0

# =====================================================================
# Go のモジュール(gomod)の更新: 索引に取り込まれてから72時間を数える
# =====================================================================
# Dependabot の gomod の更新の差分(require のブロックの1行を入れ替える)
gomod_patch() {
    printf '@@ -5,7 +5,7 @@ go 1.25.0\n require (\n \tgithub.com/labstack/echo/v4 v4.13.4\n-\tgithub.com/jackc/pgx/v5 v5.7.5\n+\tgithub.com/jackc/pgx/v5 %s\n \tgolang.org/x/text v0.28.0 // indirect\n )\n' "$1"
}
# 使い方: gomod_index <モジュール> <版> <判定の時刻からさかのぼる秒> [...]
gomod_index() {
    : >"$WORK/gomod-page.ndjson"
    while [ $# -ge 3 ]; do
        jq -c -n --arg p "$1" --arg v "$2" --argjson t "$((NOW - $3))" \
            '{Path: $p, Version: $v, Timestamp: ($t | todate)}' >>"$WORK/gomod-page.ndjson"
        shift 3
    done
}
# 使い方: epoch_iso <1970-01-01T00:00:00Z からの秒>
epoch_iso() {
    jq -n -r --argjson t "$1" '$t | todate'
}

reset_scenario
files_json "backend/go.mod" "$(gomod_patch v5.7.6)" >"$WORK/files.json"
gomod_index github.com/jackc/pgx/v5 v5.7.6 3600
run
expect_decision "gomod の版が72時間より新しければ止める" wait "github.com/jackc/pgx/v5@v5.7.6"
expect_decision "gomod で止めた理由に、予約する見直しの時刻を書く" wait "$(epoch_iso "$((NOW - 3600 + 259200))") 以降の見直しで予約する"
expect_posted "gomod の版を待つときはコメントしない" 0
expect_gomod_calls "gomod の更新では索引を1度読む" 1
if grep -qxF "http://index.test/index?since=$(epoch_iso "$((NOW - 73 * 3600))")&limit=2000" "$WORK/gomod-calls.log"; then
    ok "索引は判定の時刻の73時間前から読む"
else
    echo "FAIL: 索引は判定の時刻の73時間前から読む (実際: $(cat "$WORK/gomod-calls.log"))"
    FAILED=1
fi

reset_scenario
files_json "backend/go.mod" "$(gomod_patch v5.7.6)" >"$WORK/files.json"
gomod_index github.com/jackc/pgx/v5 v5.7.6 "$((72 * 3600 + 60))"
run
expect_decision "gomod の版が古ければ通す" reserve "Go のモジュールの更新は、すべて公開から72時間経った"
expect_decision "gomod の版が古ければ、tflint の判定の理由も並べる" reserve "tflint の更新ではない、Go"
expect_posted "gomod の版が古ければコメントしない" 0

reset_scenario
files_json "backend/go.mod" "$(gomod_patch v5.7.6)" >"$WORK/files.json"
gomod_index github.com/jackc/pgx/v5 v5.7.6 "$((72 * 3600))"
run
expect_decision "gomod の版が取り込みからちょうど72時間なら通す" reserve "すべて公開から72時間経った"
gomod_index github.com/jackc/pgx/v5 v5.7.6 "$((72 * 3600 - 1))"
run
expect_decision "gomod の版が取り込みから72時間に1秒足りなければ止める" wait "github.com/jackc/pgx/v5@v5.7.6"

reset_scenario
files_json "backend/go.mod" "$(gomod_patch v5.7.6)" >"$WORK/files.json"
gomod_index github.com/other/mod v1.0.0 3600
run
expect_decision "索引の読んだ範囲に無い gomod の版は、73時間より前に取り込まれたとして通す" reserve "すべて公開から72時間経った"

# 版の先頭の v と、モジュールの名前の大文字と小文字は lib-gomod-index.sh が照らす
reset_scenario
files_json "backend/go.mod" "$(gomod_patch v5.7.6)" >"$WORK/files.json"
gomod_index github.com/Jackc/pgx/v5 v5.7.6 3600
run
expect_decision "モジュールの名前の大文字と小文字が違っても照らす" wait "github.com/jackc/pgx/v5@v5.7.6"

# 2つの go.mod の更新は、新しい方の取り込みの時刻で待つ
reset_scenario
files_json "backend/go.mod" "$(gomod_patch v5.7.6)" \
    "tools/go.mod" "$(printf '@@ -3,3 +3,3 @@\n require (\n-\tgolang.org/x/tools v0.36.0\n+\tgolang.org/x/tools v0.37.0\n )\n')" >"$WORK/files.json"
gomod_index github.com/jackc/pgx/v5 v5.7.6 7200 golang.org/x/tools v0.37.0 3600
run
expect_decision "複数の go.mod の新しい組をすべて理由に書く" wait "pgx/v5@v5.7.6.*golang.org/x/tools@v0.37.0"
expect_decision "複数の go.mod では、いちばん新しい取り込みから72時間で予約する" wait "$(epoch_iso "$((NOW - 3600 + 259200))") 以降"
expect_gomod_calls "複数の go.mod でも索引は1度だけ読む" 1

# replace の行は置き換え先の組を照らす。手元のフォルダへの置き換えは照らさない
reset_scenario
files_json "backend/go.mod" "$(printf '@@ -20,0 +20,2 @@\n+replace github.com/a/b => github.com/c/d v1.2.3\n+replace github.com/e/f v1.0.0 => ../local/f\n')" >"$WORK/files.json"
gomod_index github.com/c/d v1.2.3 60
run
expect_decision "replace の置き換え先の版が新しければ止める" wait "github.com/c/d@v1.2.3"
if grep -q 'github.com/e/f' "$WORK/out.txt"; then
    ng "手元のフォルダへの置き換えは照らさない"
else
    ok "手元のフォルダへの置き換えは照らさない"
fi

# go・toolchain の行と exclude のブロックの中の行は、使うモジュールの版ではないので照らさない
reset_scenario
files_json "backend/go.mod" "$(printf '@@ -1,8 +1,8 @@\n module example.com/m\n \n-go 1.25.0\n+go 1.25.1\n-toolchain go1.25.0\n+toolchain go1.25.1\n exclude (\n+\tgithub.com/z/z v1.0.0\n )\n')" >"$WORK/files.json"
run
expect_decision "go・toolchain・exclude の行だけの更新は、索引を読まずに通す" reserve "tflint の更新ではない"
expect_gomod_calls "go・toolchain・exclude の行だけの更新では索引を読まない" 0
if grep -q '^reason=.*Go のモジュール' "$WORK/out.txt"; then
    ng "照らす組が無ければ、Go のモジュールの判定の理由を並べない"
else
    ok "照らす組が無ければ、Go のモジュールの判定の理由を並べない"
fi

# 引用符で囲んだモジュールの名前は、引用符を外して照らす
reset_scenario
files_json "backend/go.mod" "$(printf '@@ -5,3 +5,4 @@\n require (\n \tgithub.com/labstack/echo/v4 v4.13.4\n+\t"example.com/quoted" v1.0.0\n+\t%sexample.com/raw%s v2.0.0\n )\n' "\`" "\`")" >"$WORK/files.json"
gomod_index example.com/quoted v1.0.0 3600 example.com/raw v2.0.0 3600
run
expect_decision "引用符で囲んだモジュールの名前も照らす" wait "example.com/quoted@v1.0.0.*example.com/raw@v2.0.0"

# ignore の指示は、使うモジュールの版ではないので照らさない
reset_scenario
files_json "backend/go.mod" "$(printf '@@ -3,0 +3,5 @@\n+ignore ./node_modules\n+ignore (\n+\t./tmp\n+\tthird_party/x v1\n+)\n')" >"$WORK/files.json"
run
expect_decision "ignore の行だけの更新は、索引を読まずに通す" reserve "tflint の更新ではない"
expect_gomod_calls "ignore の行だけの更新では索引を読まない" 0

# 行の末尾の注釈(// indirect)を外して組を読む
reset_scenario
files_json "backend/go.mod" "$(printf '@@ -5,3 +5,3 @@\n require (\n-\tgolang.org/x/text v0.28.0 // indirect\n+\tgolang.org/x/text v0.29.0 // indirect\n )\n')" >"$WORK/files.json"
gomod_index golang.org/x/text v0.29.0 3600
run
expect_decision "行の末尾に // indirect がある版も照らす" wait "golang.org/x/text@v0.29.0"

# exclude のブロックが閉じたあとの行は照らす
reset_scenario
files_json "backend/go.mod" "$(printf '@@ -8,4 +8,5 @@\n exclude (\n \tgithub.com/z/z v1.0.0\n )\n+require github.com/n/n v1.1.0\n')" >"$WORK/files.json"
gomod_index github.com/n/n v1.1.0 3600
run
expect_decision "exclude のブロックが閉じたあとの require の行は照らす" wait "github.com/n/n@v1.1.0"

# 差分のまとまり(@@ の行)が替わったら、前のまとまりのブロックの中かを持ち越さない
reset_scenario
files_json "backend/go.mod" "$(printf '@@ -8,2 +8,2 @@\n exclude (\n \tgithub.com/z/z v1.0.0\n@@ -20,3 +20,3 @@\n-\tgithub.com/n/n v1.0.0\n+\tgithub.com/n/n v1.1.0\n )\n')" >"$WORK/files.json"
gomod_index github.com/n/n v1.1.0 3600
run
expect_decision "前の差分のまとまりで始まった exclude のブロックを持ち越さない" wait "github.com/n/n@v1.1.0"

reset_scenario
files_json "backend/go.mod" "$(gomod_patch v5.7.6)" >"$WORK/files.json"
GOMOD_FAIL=1
run
expect_decision "索引を読めなければ notify" notify "公開の時刻を取れない(Go のモジュールの索引"
expect_posted "索引を読めなければコメントを1件付ける" 1
body="$WORK/posted/posted_1.md"
if [ -f "$body" ] && [ "$(head -n 1 "$body")" = "@owner-name" ] &&
    [ "$(grep -v '^[[:space:]]*$' "$body" | tail -n 1)" = "<!-- release-age: gomod-unavailable -->" ] &&
    grep -q '1日1回の見直しで Go のモジュールの索引をもう一度読み' "$body" &&
    grep -q 'PR #7 の Go のモジュールの公開の時刻を取れない理由を調べて' "$body"; then
    ok "索引を読めないコメントはメンション・毎日の見直し・調べさせる依頼・目印を持つ"
else
    echo "FAIL: 索引を読めないコメントはメンション・毎日の見直し・調べさせる依頼・目印を持つ"
    [ -f "$body" ] && sed 's/^/  /' "$body"
    FAILED=1
fi

# tflint の更新と gomod の更新が同じPRにあれば、強い方の判定を採る
reset_scenario
files_json "docker/terraform/Dockerfile" "$(tflint_patch "$OLD_LINE" "$NEW_LINE")" \
    "backend/go.mod" "$(gomod_patch v5.7.6)" >"$WORK/files.json"
gomod_index github.com/jackc/pgx/v5 v5.7.6 3600
run
expect_decision "tflint が経っていて gomod が新しければ止める" wait "github.com/jackc/pgx/v5@v5.7.6"

reset_scenario
files_json "docker/terraform/Dockerfile" "$(tflint_patch "$OLD_LINE" "$NEW_LINE")" \
    "backend/go.mod" "$(gomod_patch v5.7.6)" >"$WORK/files.json"
NOW="$((PUB_EPOCH + 3600))"
gomod_index github.com/jackc/pgx/v5 v5.7.6 "$((72 * 3600 + 60))"
run
expect_decision "tflint が新しくて gomod が経っていれば、tflint で止める" wait "tflint v0.61.0 は公開から72時間経っていない"

reset_scenario
files_json "docker/terraform/Dockerfile" "$(tflint_patch "$OLD_LINE" "$NEW_LINE")" \
    "backend/go.mod" "$(gomod_patch v5.7.6)" >"$WORK/files.json"
NOW="$((PUB_EPOCH + 3600))"
GOMOD_FAIL=1
run
expect_decision "tflint を待つ更新と索引を読めない更新が同じPRにあれば知らせる" notify "公開の時刻を取れない(Go のモジュールの索引"

# tflint だけの更新では索引を読まない
reset_scenario
files_json "docker/terraform/Dockerfile" "$(tflint_patch "$OLD_LINE" "$NEW_LINE")" >"$WORK/files.json"
run
expect_gomod_calls "tflint だけの更新では索引を読まない" 0

# go.mod を読めないときは判定できない
reset_scenario
files_json "backend/go.mod" "-" >"$WORK/files.json"
run
expect_undecided "差分が大きすぎて patch の無い go.mod があれば判定できない"
if grep -q '差分が大きすぎて中身を読めない go.mod があります: backend/go.mod' "$WORK/err.txt"; then
    ok "patch の無い go.mod の名前を理由に書く"
else
    ng "patch の無い go.mod の名前を理由に書く"
fi
expect_gomod_calls "patch の無い go.mod では索引を読まない" 0

reset_scenario
files_json "backend/go.mod" "$(printf '@@ -5,3 +5,3 @@\n require (\n-\tgithub.com/jackc/pgx/v5 v5.7.5\n+\tgithub.com/jackc/pgx/v5 latest\n )\n')" >"$WORK/files.json"
run
expect_undecided "go.mod の足された行に版が読み取れなければ判定できない"
expect_gomod_calls "読み取れない行があれば索引を読まない" 0
expect_posted "go.mod を読めないときはコメントしない" 0

# =====================================================================
# 使い方の誤り
# =====================================================================
check_invocation() {
    local name="$1" omit="$2"
    shift 2
    reset_scenario
    : >"$WORK/calls.log"
    local envs=() var
    for var in GITHUB_REPOSITORY=owner/repo GITHUB_REPOSITORY_OWNER=owner-name GH_TOKEN=dummy; do
        [ "${var%%=*}" = "$omit" ] || envs+=("$var")
    done
    env -u GITHUB_REPOSITORY -u GITHUB_REPOSITORY_OWNER -u GH_TOKEN "${envs[@]}" \
        PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_FORBIDDEN="$WORK/forbidden.log" \
        STUB_FILES="$WORK/files.json" STUB_COMMENTS="$WORK/comments.json" \
        STUB_POSTED_DIR="$WORK/posted" STUB_RELEASE_MODE=ok STUB_PUBLISHED="$PUBLISHED" \
        bash "$SCRIPT" "$@" >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
    expect_undecided "$name"
}
check_invocation "PR番号が無ければ判定できない" ""
check_invocation "PR番号が数字でなければ判定できない" "" "7;rm"
check_invocation "GITHUB_REPOSITORY が無ければ判定できない" GITHUB_REPOSITORY 7
check_invocation "GITHUB_REPOSITORY_OWNER が無ければ判定できない" GITHUB_REPOSITORY_OWNER 7
check_invocation "GH_TOKEN が無ければ判定できない" GH_TOKEN 7

# =====================================================================
# 公開日時は GitHub のリリースと Go のモジュールの索引だけから取る(全ての場面を通して)
# =====================================================================
if [ -s "$WORK/forbidden.log" ]; then
    echo "FAIL: GitHub の API と Go のモジュールの索引のほかに問い合わせていない"
    sed 's/^/  /' "$WORK/forbidden.log"
    FAILED=1
else
    ok "GitHub の API と Go のモジュールの索引のほかに問い合わせていない(docker・skopeo 等を呼ばない)"
fi
if grep -Eq 'ghcr\.io|manifests|/packages/|/blobs/|/config' "$WORK/all-calls.log"; then
    echo "FAIL: イメージの置き場や中身(image config)を読んでいない"
    grep -E 'ghcr\.io|manifests|/packages/|/blobs/|/config' "$WORK/all-calls.log" | sed 's/^/  /'
    FAILED=1
else
    ok "イメージの置き場や中身(image config)を読んでいない"
fi
if [ -s "$WORK/all-calls.log" ]; then
    ok "gh の呼び出しが記録されている(上の確認が空振りしていない)"
else
    echo "FAIL: gh の呼び出しが記録されている(上の確認が空振りしていない)"
    FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    echo "テストに失敗があります。"
    exit 1
fi
echo "全てのテストが通りました。"
