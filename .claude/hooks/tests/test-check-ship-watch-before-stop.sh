#!/bin/bash
# =====================================================================
# check-ship-watch-before-stop.sh(/ship の見届けを終えてはいけない状態で終えないようにするフック)のテスト
#
# 実行: bash .claude/hooks/tests/test-check-ship-watch-before-stop.sh
# 一時的な git のリポジトリを作り、PATH の先頭に偽の gh を置いて、PR と必須の検査の状態を差し替える。
# フックに Claude Code の Stop フックの入力(JSON)を渡して、終了コード(0 は通す、2 は止める)と標準エラーを確かめる。
# 本物のリポジトリの記録(.claude/.state と .git/keirekipro-usage)と GitHub には触れない。
# 前提: bash・perl(JSON::PP)・git。ホストの Git Bash から流す。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

HOOK="$(cd "$(dirname "$0")/.." && pwd)/check-ship-watch-before-stop.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# git が返すパス(Windows では C:/...)と同じ形で比べられるようにする
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

REPO="$WORK/repo"
BIN="$WORK/bin"
FIX="$WORK/fixture"
GITC=(-c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
mkdir -p "$BIN" "$FIX"
git init -q "$REPO"
git -C "$REPO" checkout -q -B main
printf '.claude/.state/\n' >"$REPO/.gitignore"
mkdir -p "$REPO/.github/audit"
cat >"$REPO/.github/audit/required-checks.json" <<'JSON'
{
  "checks": [
    { "context": "size-check", "mode": "always", "state": "active", "approval_gated": false },
    { "context": "escape-hatch", "mode": "always", "state": "active", "approval_gated": true },
    { "context": "pre-merge-check", "mode": "always", "state": "active", "approval_gated": true }
  ]
}
JSON
git -C "$REPO" add -A
git -C "$REPO" "${GITC[@]}" commit -q -m seed
git -C "$REPO" checkout -q -b fix/x
USAGE_DIR="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/keirekipro-usage/issues"

# 偽の gh: fixture の pr.json と checks.json を出し、*.exit の終了コードで終わる。呼ばれた引数を calls.txt に残す
cat >"$BIN/gh" <<'GH'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_GH_DIR/calls.txt"
case "$1 $2" in
    "pr view") f=pr ;;
    "pr checks") f=checks ;;
    *) exit 1 ;;
esac
[ -f "$FAKE_GH_DIR/$f.json" ] && cat "$FAKE_GH_DIR/$f.json"
code=0
[ -f "$FAKE_GH_DIR/$f.exit" ] && code=$(cat "$FAKE_GH_DIR/$f.exit")
exit "$code"
GH
chmod +x "$BIN/gh"
export FAKE_GH_DIR="$FIX"
# PATH は : で区切るので、ドライブ文字の形(C:/...)ではなく mktemp が返した形で足す
export PATH="$TMP_ROOT/bin:$PATH"
[ "$(command -v gh)" = "$TMP_ROOT/bin/gh" ] || {
    printf '偽の gh が PATH の先頭に来ていない: %s\n' "$(command -v gh)"
    exit 1
}

pass=0
fail=0

die() {
    printf '%s\n' "$*"
    exit 1
}

reset_state() {
    rm -rf "${FIX:?}"/* "$REPO/.claude/.state" "$USAGE_DIR"
    git -C "$REPO" checkout -q fix/x
}

run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    reset_state
    if out=$("$fn" 2>&1); then
        pass=$((pass + 1))
        printf 'ok: %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

# PR の JSON を fixture に書く
set_pr() { # <state> <mergeStateStatus> <reviewDecision> <自動マージの予約 yes|no> [<本文>] [<head>] [<headRefName>]
    perl -MJSON::PP -e '
        my ($state, $mss, $rd, $am, $body, $sha, $head) = @ARGV;
        print JSON::PP->new->canonical->encode({
            number => 42, state => $state, mergeStateStatus => $mss, reviewDecision => $rd,
            autoMergeRequest => ($am eq "yes" ? { enabledAt => "2026-11-03T00:00:00Z" } : undef),
            body => $body, headRefOid => $sha, headRefName => $head,
        });
    ' -- "$1" "$2" "$3" "$4" "${5-}" "${6:-aaa111}" "${7:-fix/x}" >"$FIX/pr.json"
}

set_checks() { # <name>=<bucket>...
    perl -MJSON::PP -e '
        print JSON::PP->new->canonical->encode([ map { my ($n, $b) = split /=/, $_, 2; { name => $n, bucket => $b } } @ARGV ]);
    ' -- "$@" >"$FIX/checks.json"
}

# フックを動かし、終了コードを RC に、標準エラーを ERR に入れる
run_hook() { # [<prompt_id>] [<session_id>]
    local input
    input=$(perl -MJSON::PP -e '
        print JSON::PP->new->canonical->encode({ cwd => $ARGV[0], prompt_id => $ARGV[1], session_id => $ARGV[2],
            hook_event_name => "Stop", stop_hook_active => JSON::PP::false });
    ' -- "$REPO" "${1:-p-1}" "${2:-s-1}")
    ERR=$(printf '%s' "$input" | bash "$HOOK" 2>&1 >/dev/null)
    RC=$?
}

expect_rc() { # <期待する終了コード> <説明>
    [ "$RC" = "$1" ] || die "$2: 終了コードが $RC で、$1 ではない。標準エラー: $ERR"
}

expect_err() { # <含むはずの文字列>
    case "$ERR" in
        *"$1"*) ;;
        *) die "標準エラーに「$1」が無い: $ERR" ;;
    esac
}

t_pending_blocks_once() {
    set_pr OPEN BLOCKED APPROVED yes
    set_checks size-check=pass escape-hatch=pending escape-hatch=fail
    echo 8 >"$FIX/checks.exit"
    run_hook p-1
    expect_rc 2 "結果の出ていない検査がある"
    expect_err "PR #42 の必須の検査に、結果がまだ出ていないもの"
    expect_err "escape-hatch"
    expect_err "同じ状態では1回だけ止めます"
    expect_err "問いをもう一度全部書いてください"
    run_hook p-1
    expect_rc 0 "同じ返答の中で同じ状態の2回目"
    run_hook p-2
    expect_rc 2 "所有者の次の依頼の返答で同じ状態"
}

t_new_head_blocks_again() {
    set_pr OPEN BLOCKED APPROVED yes "" aaa111
    set_checks size-check=pending
    run_hook p-1
    expect_rc 2 "1つ目の head"
    set_pr OPEN BLOCKED APPROVED yes "" bbb222
    run_hook p-1
    expect_rc 2 "main を取り込んで head が変わった"
}

t_dirty_blocks() {
    set_pr OPEN DIRTY APPROVED yes
    run_hook
    expect_rc 2 "main と衝突している"
    expect_err "main と衝突しています"
}

t_merging_blocks() {
    set_pr OPEN BEHIND APPROVED yes
    set_checks size-check=pass gitleaks=skipping
    run_hook
    expect_rc 2 "検査がすべて通り予約がある"
    expect_err "マージされるまで見届けを続けて"
}

# 承認を待つスクリプトの心拍のファイルに、いまから <秒> 前の時刻を書く
set_beat() { # <秒>
    mkdir -p "$REPO/.claude/.state/ship-watch"
    echo $(($(date +%s) - $1)) >"$REPO/.claude/.state/ship-watch/approval-wait-42"
}

t_review_required_without_wait_blocks() {
    set_pr OPEN BLOCKED REVIEW_REQUIRED yes
    set_checks size-check=pass gitleaks=skipping
    run_hook p-1
    expect_rc 2 "承認待ちで承認を待つコマンドが動いていない"
    expect_err "PR #42 は所有者の承認を待っていますが"
    expect_err "bash .claude/scripts/ship/wait-approval.sh 42 を Bash の run_in_background で"
    run_hook p-1
    expect_rc 0 "同じ返答の中で同じ状態の2回目"
}

t_review_required_with_wait_passes() {
    set_pr OPEN BLOCKED REVIEW_REQUIRED yes
    set_checks size-check=pass gitleaks=skipping
    set_beat 30
    run_hook
    expect_rc 0 "承認を待つコマンドが動いている"
}

t_review_required_with_stale_wait_blocks() {
    set_pr OPEN BLOCKED REVIEW_REQUIRED yes
    set_checks size-check=pass
    set_beat 600
    run_hook
    expect_rc 2 "心拍が10分前で、承認を待つコマンドが止まっている"
    expect_err "承認を待つコマンドが動いていません"
}

t_gate_red_without_wait_blocks() {
    set_pr OPEN BLOCKED APPROVED yes
    set_checks size-check=pass escape-hatch=fail pre-merge-check=cancel
    echo 1 >"$FIX/checks.exit"
    run_hook
    expect_rc 2 "承認待ちのゲートだけが赤で、承認を待つコマンドが動いていない"
    expect_err "PR #42 は所有者の承認を待っていますが"
    set_beat 0
    run_hook p-2
    expect_rc 0 "承認を待つコマンドが動いている"
}

t_other_red_passes() {
    set_pr OPEN BLOCKED REVIEW_REQUIRED yes
    set_checks size-check=fail escape-hatch=fail
    echo 1 >"$FIX/checks.exit"
    run_hook
    expect_rc 0 "承認待ちのゲートのほかにも赤の検査がある"
}

t_unreadable_expected_list_treats_red_as_other() {
    rm -f "$REPO/.github/audit/required-checks.json"
    set_pr OPEN BLOCKED APPROVED yes
    set_checks size-check=pass escape-hatch=fail
    echo 1 >"$FIX/checks.exit"
    run_hook
    git -C "$REPO" checkout -q -- .github/audit/required-checks.json
    expect_rc 0 "期待一覧を読めないので、赤を承認待ちのゲートと見分けない"
}

t_no_reservation_passes() {
    set_pr OPEN CLEAN APPROVED no
    set_checks size-check=pass
    run_hook
    expect_rc 0 "自動マージの予約が無い"
}

t_unreadable_checks_passes() {
    set_pr OPEN BLOCKED APPROVED yes
    echo 1 >"$FIX/checks.exit"
    run_hook
    expect_rc 0 "必須の検査を読めない"
}

t_merged_unreported_blocks_once_per_session() {
    set_pr MERGED CLEAN APPROVED no "変更の説明
Closes #12
Refs: #12"
    run_hook p-1 s-1
    expect_rc 2 "集計がまだ出ていない"
    expect_err "Issue #12 の集計がまだ GitHub に出ていません"
    run_hook p-2 s-1
    expect_rc 0 "同じ会話の次の返答"
    run_hook p-3 s-2
    expect_rc 2 "別の会話"
}

t_merged_reported_passes() {
    set_pr MERGED CLEAN APPROVED no "Closes #12"
    mkdir -p "$USAGE_DIR"
    printf '{"reported_at":"2026-11-03T04:18:07Z"}' >"$USAGE_DIR/12.json"
    run_hook
    expect_rc 0 "集計を出し済み"
}

t_merged_skipped_passes() {
    set_pr MERGED CLEAN APPROVED no "Closes #12"
    mkdir -p "$USAGE_DIR"
    printf '{"skip":"no-pr","closed_at":"2026-11-03T04:18:07Z"}' >"$USAGE_DIR/12.json"
    run_hook
    expect_rc 0 "集計しない印がある"
}

t_merged_without_closes_passes() {
    set_pr MERGED CLEAN APPROVED no "Refs: #12"
    run_hook
    expect_rc 0 "Closes の行が無い"
}

t_closed_passes() {
    set_pr CLOSED CLEAN APPROVED no "Closes #12"
    run_hook
    expect_rc 0 "PR が閉じられた"
}

t_no_pr_passes() {
    echo 1 >"$FIX/pr.exit"
    run_hook
    expect_rc 0 "PR が無い"
}

t_other_branch_pr_passes() {
    set_pr OPEN DIRTY APPROVED yes "" aaa111 fix/other
    run_hook
    expect_rc 0 "別のブランチの PR"
}

t_main_branch_passes() {
    git -C "$REPO" checkout -q main
    set_pr OPEN DIRTY APPROVED yes "" aaa111 main
    run_hook
    expect_rc 0 "main にいる"
    [ ! -f "$FIX/calls.txt" ] || die "main にいるのに gh を呼んだ"
}

run_test "結果待ちの検査があれば、同じ返答の中で1回だけ止める" t_pending_blocks_once
run_test "head が変われば、同じ返答の中でもまた止める" t_new_head_blocks_again
run_test "main と衝突していれば止める" t_dirty_blocks
run_test "検査がすべて通り予約があれば止める" t_merging_blocks
run_test "承認待ちで、承認を待つコマンドが動いていなければ止める" t_review_required_without_wait_blocks
run_test "承認待ちで、承認を待つコマンドが動いていれば通す" t_review_required_with_wait_passes
run_test "承認待ちで、承認を待つコマンドの心拍が古ければ止める" t_review_required_with_stale_wait_blocks
run_test "承認待ちのゲートだけが赤で、承認を待つコマンドが動いていなければ止める" t_gate_red_without_wait_blocks
run_test "承認待ちのゲートのほかにも赤があれば通す" t_other_red_passes
run_test "期待一覧を読めなければ、赤の検査を承認待ちのゲートと見分けずに通す" t_unreadable_expected_list_treats_red_as_other
run_test "自動マージの予約が無ければ通す" t_no_reservation_passes
run_test "必須の検査を読めなければ通す" t_unreadable_checks_passes
run_test "マージ後に集計がまだなら、会話ごとに1回止める" t_merged_unreported_blocks_once_per_session
run_test "マージ後に集計を出し済みなら通す" t_merged_reported_passes
run_test "マージ後に集計しない印があれば通す" t_merged_skipped_passes
run_test "Closes の行が無いPRは、マージ後に通す" t_merged_without_closes_passes
run_test "閉じられたPRは通す" t_closed_passes
run_test "PRが無ければ通す" t_no_pr_passes
run_test "別のブランチのPRが返っても通す" t_other_branch_pr_passes
run_test "main にいれば gh を呼ばずに通す" t_main_branch_passes

printf '\n%d 件成功、%d 件失敗\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
