#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix-run-branch.sh の自動テスト
#
# gh は PATH の先頭に置いた偽物に替える。偽の gh は、受け取った引数を1回の呼び出しにつき1行で CALLS に残し、
# 環境変数 FAKE_MAIN FAKE_PATCH FAKE_POST の値で応答を変える。
#   FAKE_MAIN   ok(main の参照を返す) / fail(HTTP 500 で失敗する)
#   FAKE_PATCH  ok / 404 / 422 / fail(HTTP 500 で失敗する)
#   FAKE_POST   ok / fail(HTTP 500 で失敗する)
# 知らない呼び出しは失敗にする。
#
# 場合の名前を KP_TEST_CASE に入れると、その場合だけを流す(例: KP_TEST_CASE=patch)。
# 名前は patch create_404 create_422 main_fail patch_fail post_fail summary main_untouched args。
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/claude-auto-fix-run-branch.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
RAN=0

ok() { echo "  ok: $1"; }
ng() { echo "  NG: $1" >&2; FAILED=1; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1(期待: [$3] 実際: [$2])"; fi; }
want() { if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then RAN=$((RAN + 1)); echo "[$1]"; return 0; fi; return 1; }

MAIN_SHA=0123456789abcdef0123456789abcdef01234567
BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALLS"
http_fail() {
    echo "gh: $2 (HTTP $1)" >&2
    exit 1
}
[ "${1:-}" = api ] || http_fail 400 "Unknown command"
shift
case "$*" in
"repos/o/r/git/ref/heads/main")
    [ "$FAKE_MAIN" = ok ] || http_fail 500 "Server Error"
    printf '{"ref": "refs/heads/main", "object": {"sha": "%s", "type": "commit"}}\n' "$MAIN_SHA"
    ;;
"-X PATCH repos/o/r/git/refs/heads/claude-auto-fix/run -f sha=$MAIN_SHA -F force=true")
    case "$FAKE_PATCH" in
    ok) printf '{"ref": "refs/heads/claude-auto-fix/run", "object": {"sha": "%s"}}\n' "$MAIN_SHA" ;;
    404) http_fail 404 "Not Found" ;;
    422) http_fail 422 "Reference does not exist" ;;
    *) http_fail 500 "Server Error" ;;
    esac
    ;;
"-X POST repos/o/r/git/refs -f ref=refs/heads/claude-auto-fix/run -f sha=$MAIN_SHA")
    [ "$FAKE_POST" = ok ] || http_fail 500 "Server Error"
    printf '{"ref": "refs/heads/claude-auto-fix/run", "object": {"sha": "%s"}}\n' "$MAIN_SHA"
    ;;
*)
    http_fail 400 "Unknown call"
    ;;
esac
EOF
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH" CALLS="$WORK/calls" MAIN_SHA GITHUB_REPOSITORY="o/r"

# スクリプトを動かす: run <FAKE_MAIN> <FAKE_PATCH> <FAKE_POST> [引数...]
run() {
    : >"$CALLS"
    rm -f "$WORK/summary"
    FAKE_MAIN="$1" FAKE_PATCH="$2" FAKE_POST="$3" GITHUB_STEP_SUMMARY="$WORK/summary" \
        bash "$SCRIPT" "${@:4}" >"$WORK/out" 2>"$WORK/err"
    RC=$?
}
# 呼ばれた API を、1回の呼び出しにつき1つ、| でつないで出す
calls() { paste -sd '|' - <"$CALLS"; }
PATCH_CALL="api -X PATCH repos/o/r/git/refs/heads/claude-auto-fix/run -f sha=$MAIN_SHA -F force=true"
POST_CALL="api -X POST repos/o/r/git/refs -f ref=refs/heads/claude-auto-fix/run -f sha=$MAIN_SHA"
MAIN_CALL="api repos/o/r/git/ref/heads/main"

if want patch; then
    run ok ok ok
    expect_eq "ブランチがあるときは0で終わる" "$RC" 0
    expect_eq "ブランチがあるときは main の最新のコミットの SHA と force=true を渡した PATCH だけを呼ぶ" "$(calls)" "${MAIN_CALL}|${PATCH_CALL}"
fi

if want create_404; then
    run ok 404 ok
    expect_eq "偽の gh が 404 を返したときは0で終わる" "$RC" 0
    expect_eq "偽の gh が 404 を返したときは ref=refs/heads/claude-auto-fix/run を渡した POST を呼ぶ" "$(calls)" "${MAIN_CALL}|${PATCH_CALL}|${POST_CALL}"
fi

if want create_422; then
    run ok 422 ok
    expect_eq "偽の gh が 422 を返したときは0で終わる" "$RC" 0
    expect_eq "偽の gh が 422 を返したときも同じ POST を呼ぶ" "$(calls)" "${MAIN_CALL}|${PATCH_CALL}|${POST_CALL}"
fi

if want main_fail; then
    run fail ok ok
    if [ "$RC" -ne 0 ] && grep -q '^::error::' "$WORK/err"; then ok "main を読めないときは0以外で終わる"; else ng "main を読めないときは0以外で終わる(終了コード $RC)"; fi
    expect_eq "main を読めないときはブランチを変える API を呼ばない" "$(calls)" "$MAIN_CALL"
fi

if want patch_fail; then
    run ok fail ok
    if [ "$RC" -ne 0 ] && grep -q '^::error::' "$WORK/err"; then ok "PATCH が失敗したときは0以外で終わる"; else ng "PATCH が失敗したときは0以外で終わる(終了コード $RC)"; fi
    expect_eq "PATCH が 404 と 422 のほかで失敗したときは POST を呼ばない" "$(calls)" "${MAIN_CALL}|${PATCH_CALL}"
fi

if want post_fail; then
    run ok 404 fail
    if [ "$RC" -ne 0 ] && grep -q '^::error::' "$WORK/err"; then ok "POST が失敗したときは0以外で終わる"; else ng "POST が失敗したときは0以外で終わる(終了コード $RC)"; fi
fi

if want summary; then
    run ok ok ok
    if [ -f "$WORK/summary" ] && grep -qF "$MAIN_SHA" "$WORK/summary" && grep -qF 'claude-auto-fix/run' "$WORK/summary"; then
        ok "合わせた SHA を GITHUB_STEP_SUMMARY に書く"
    else
        ng "合わせた SHA を GITHUB_STEP_SUMMARY に書く(書いた内容: [$(cat "$WORK/summary" 2>/dev/null)])"
    fi
fi

if want main_untouched; then
    # どの場合も、書く API(-X の付いた呼び出し)は、専用のブランチの参照を変えるか作るものだけにする
    all=""
    for s in "ok ok ok" "ok 404 ok" "ok 422 ok" "fail ok ok" "ok fail ok" "ok 404 fail"; do
        # shellcheck disable=SC2086 # 3つの値を別々の引数として渡すため
        run $s
        all+="$(cat "$CALLS")"$'\n'
    done
    bad=$(grep -E -- '-X ' <<<"$all" | grep -vxF -e "$PATCH_CALL" -e "$POST_CALL" || true)
    if [ -z "$bad" ] && ! grep -qE -- '-X [A-Z]+ repos/o/r/git/refs/heads/main( |$)|ref=refs/heads/main( |$)' <<<"$all"; then
        ok "どの場合も main の参照を変える API を呼ばない"
    else
        ng "どの場合も main の参照を変える API を呼ばない(呼んだ書く API: [$bad])"
    fi
fi

if want args; then
    run ok ok ok extra
    expect_eq "引数を渡すと2で終わる" "$RC" 2
    expect_eq "引数を渡すと API を呼ばない" "$(calls)" ""
    : >"$CALLS"
    FAKE_MAIN=ok FAKE_PATCH=ok FAKE_POST=ok env -u GITHUB_REPOSITORY bash "$SCRIPT" >/dev/null 2>&1
    expect_eq "GITHUB_REPOSITORY が無ければ2で終わる" "$?" 2
fi

if [ "$RAN" -eq 0 ]; then
    echo "KP_TEST_CASE の場合 [$CASE] はありません" >&2
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "test-claude-auto-fix-run-branch: 失敗がありました" >&2
    exit 1
fi
echo "test-claude-auto-fix-run-branch: すべて通りました(${RAN} の場合)"
