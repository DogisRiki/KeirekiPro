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
for tool in curl wget docker skopeo crane regctl oras; do
    cat >"$WORK/bin/$tool" <<STUB
#!/usr/bin/env bash
printf '%s %s\n' "$tool" "\$*" >>"\${STUB_FORBIDDEN:?}"
exit 1
STUB
    chmod +x "$WORK/bin/$tool"
done
: >"$WORK/forbidden.log"
: >"$WORK/all-calls.log"

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
}

run() {
    : >"$WORK/calls.log"
    rm -rf "$WORK/posted"
    mkdir -p "$WORK/posted"
    PATH="$WORK/bin:$PATH" \
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
# 公開日時は GitHub のリリースだけから取る(全ての場面を通して)
# =====================================================================
if [ -s "$WORK/forbidden.log" ]; then
    echo "FAIL: GitHub の API 以外に問い合わせていない"
    sed 's/^/  /' "$WORK/forbidden.log"
    FAILED=1
else
    ok "GitHub の API 以外に問い合わせていない(curl・docker・skopeo 等を呼ばない)"
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
