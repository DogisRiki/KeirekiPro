#!/bin/bash
# =====================================================================
# check-verify-before-stop.sh(作業の終わりに品質チェックを済ませたかを確かめるフック)のテスト
#
# 実行: bash .claude/hooks/tests/test-check-verify-before-stop.sh
# 一時的な git のリポジトリ(本体)と worktree を作り、フックに Claude Code の Stop フックの入力(JSON)を渡して、
# 終了コード(0 は通す、2 は止める)と標準エラーを確かめる。
# 品質チェックが通った記録 .claude/.state/gate-run-<領域>.txt は、run-check.sh と同じく作業フォルダの最上位に置く。
# 本物のリポジトリの記録(.claude/.state と .git/keirekipro-parallel)には触れない。
# 前提: bash・perl(JSON::PP)・git・GNU touch(-d @<UNIX 秒>)。ホストの Git Bash から流す。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

HOOK="$(cd "$(dirname "$0")/.." && pwd)/check-verify-before-stop.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# git が返すパス(Windows では C:/...)と同じ形で比べられるようにする
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

# --- 一時的なリポジトリ(本体と worktree)
MAIN_DIR="$WORK/RepoMain"
WT_DIR="$WORK/RepoWT"
OUTSIDE_DIR="$WORK/outside"
GITC=(-c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
git init -q "$MAIN_DIR"
git -C "$MAIN_DIR" checkout -q -B main
for area in frontend backend terraform; do
    mkdir -p "$MAIN_DIR/$area/src"
    echo seed >"$MAIN_DIR/$area/src/a.txt"
done
echo seed >"$MAIN_DIR/README.md"
printf '.claude/.state/\n' >"$MAIN_DIR/.gitignore"
git -C "$MAIN_DIR" add -A
git -C "$MAIN_DIR" "${GITC[@]}" commit -q -m seed
git -C "$MAIN_DIR" worktree add -q "$WT_DIR" -b feat/wt
mkdir -p "$OUTSIDE_DIR"
MAIN=$(git -C "$MAIN_DIR" rev-parse --show-toplevel)
WT=$(git -C "$WT_DIR" rev-parse --show-toplevel)

# 変更の時刻と記録の時刻の基準(いまより十分前にして、いまの時刻と比べても食い違わないようにする)
T0=$(($(date +%s) - 100000))

pass=0
fail=0

die() {
    printf '%s\n' "$*"
    exit 1
}

# 2つの作業フォルダを、コミットした状態に戻し、記録を消す
reset_folders() {
    local d
    for d in "$MAIN" "$WT"; do
        git -C "$d" reset -q --hard
        git -C "$d" clean -q -fdx
    done
}

run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    reset_folders
    if out=$("$fn" 2>&1); then
        pass=$((pass + 1))
        printf 'ok: %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

# Stop フックの入力の JSON を作る(cwd が空なら cwd の欄を入れない)
payload() { # <cwd> [<追加のキー> <値>]...
    perl -MJSON::PP -e '
        my ($cwd, @rest) = @ARGV;
        my %d = (session_id => "s-1", hook_event_name => "Stop",
                 transcript_path => "/tmp/transcript.jsonl", permission_mode => "default",
                 stop_reason => "end_turn", last_assistant_message => "done");
        $d{cwd} = $cwd if length $cwd;
        while (@rest) {
            my $k = shift @rest; my $v = shift @rest;
            $d{$k} = $v eq "JSON_TRUE" ? JSON::PP::true : $v eq "JSON_FALSE" ? JSON::PP::false : $v;
        }
        print JSON::PP->new->canonical->encode(\%d);
    ' -- "$@"
}

# フックを呼ぶ。CLAUDE_PROJECT_DIR は第1引数の値にする(空なら設定しない)。
# 終了コードを $RC、標準エラーを $ERR に入れる
call_hook() { # <CLAUDE_PROJECT_DIR> <cwd> [<追加のキー> <値>]...
    local cpd="$1"
    shift
    if [ -n "$cpd" ]; then
        payload "$@" | CLAUDE_PROJECT_DIR="$cpd" bash "$HOOK" >"$WORK/stdout.txt" 2>"$WORK/stderr.txt"
    else
        payload "$@" | env -u CLAUDE_PROJECT_DIR bash "$HOOK" >"$WORK/stdout.txt" 2>"$WORK/stderr.txt"
    fi
    RC=$?
    ERR=$(cat "$WORK/stderr.txt")
}

# ファイルを書き換え、更新時刻を決めた時刻にする
change() { # <作業フォルダ> <パス> <UNIX 秒>
    mkdir -p "$(dirname "$1/$2")"
    echo "changed $3" >>"$1/$2"
    touch -d "@$3" "$1/$2"
}

# 品質チェックが通った記録を書く(run-check.sh の手順6と同じ場所と形)
stamp() { # <作業フォルダ> <領域> <中身>
    mkdir -p "$1/.claude/.state"
    printf '%s\n' "$3" >"$1/.claude/.state/gate-run-$2.txt"
}

expect_pass() {
    [ "$RC" = 0 ] || die "通すはずが止めた: 終了コード $RC($ERR)"
}

expect_block() { # <止める理由に出るはずの領域>...
    local a
    [ "$RC" = 2 ] || die "止めるはずが終了コード $RC だった($ERR)"
    case "$ERR" in
        *"品質ゲート未実行の変更があります"*) ;;
        *) die "止める理由の文が出ていない: $ERR" ;;
    esac
    for a in "$@"; do
        case "$ERR" in
            *"$a"*) ;;
            *) die "止める理由に $a が出ていない: $ERR" ;;
        esac
    done
}

expect_not_in_err() { # <出てはいけない領域>...
    local a
    for a in "$@"; do
        case "$ERR" in
            *"$a"*) die "止める理由に $a が出ている: $ERR" ;;
        esac
    done
}

# ---------------------------------------------------------------------
# 作業フォルダの決め方(要件2.5)

t_worktree_uses_worktree_changes_and_record() {
    # worktree の変更より worktree の記録が新しい。本体フォルダには記録が無く、本体フォルダの変更は記録より新しい
    change "$WT" frontend/src/a.txt $((T0 + 10))
    stamp "$WT" frontend $((T0 + 20))
    change "$MAIN" backend/src/a.txt $((T0 + 30))
    call_hook "$MAIN" "$WT"
    expect_pass
    # worktree の記録が無ければ、本体フォルダの記録がいくら新しくても止める
    rm -f "$WT/.claude/.state/gate-run-frontend.txt"
    stamp "$MAIN" frontend $((T0 + 99999))
    stamp "$MAIN" backend $((T0 + 99999))
    call_hook "$MAIN" "$WT"
    expect_block frontend
    expect_not_in_err backend
}

t_main_record_newer_but_worktree_change_newer_blocks() {
    stamp "$MAIN" frontend $((T0 + 99999))
    stamp "$WT" frontend $((T0 + 10))
    change "$WT" frontend/src/a.txt $((T0 + 20))
    call_hook "$MAIN" "$WT"
    expect_block frontend
}

t_main_changes_not_counted_from_worktree() {
    # 本体フォルダにだけ記録の無い変更がある。worktree はきれい
    change "$MAIN" frontend/src/a.txt $((T0 + 10))
    change "$MAIN" terraform/src/a.txt $((T0 + 10))
    call_hook "$MAIN" "$WT"
    expect_pass
    # 同じ状態でも、cwd が本体フォルダなら本体フォルダの変更で止める
    call_hook "$MAIN" "$MAIN"
    expect_block frontend terraform
}

t_main_folder_cwd_uses_main_record() {
    change "$MAIN" backend/src/a.txt $((T0 + 10))
    stamp "$MAIN" backend $((T0 + 20))
    # worktree の記録は古い。本体フォルダのセッションは本体フォルダの記録を見る
    stamp "$WT" backend $((T0 + 1))
    call_hook "$MAIN" "$MAIN"
    expect_pass
}

t_ignores_claude_project_dir_when_cwd_given() {
    # CLAUDE_PROJECT_DIR は本体フォルダ(セッションを始めた場所)のまま、cwd が worktree に移った
    change "$MAIN" frontend/src/a.txt $((T0 + 10))
    change "$WT" frontend/src/a.txt $((T0 + 10))
    stamp "$WT" frontend $((T0 + 20))
    call_hook "$MAIN" "$WT"
    expect_pass
    # 逆に、CLAUDE_PROJECT_DIR が worktree でも cwd が本体フォルダなら本体フォルダを見る
    call_hook "$WT" "$MAIN"
    expect_block frontend
}

t_subdir_and_backslash_cwd() {
    change "$WT" frontend/src/a.txt $((T0 + 20))
    stamp "$WT" frontend $((T0 + 10))
    # 下のディレクトリでも最上位の変更と記録を見る(git status のパスは最上位からの相対)
    call_hook "$MAIN" "$WT/frontend/src"
    expect_block frontend
    call_hook "$MAIN" "${WT//\//\\}\\backend"
    expect_block frontend
    stamp "$WT" frontend $((T0 + 30))
    call_hook "$MAIN" "$WT/frontend/src"
    expect_pass
    call_hook "$MAIN" "${WT//\//\\}\\backend"
    expect_pass
}

t_no_cwd_uses_claude_project_dir() {
    change "$WT" frontend/src/a.txt $((T0 + 20))
    stamp "$WT" frontend $((T0 + 10))
    # cwd が無いときは CLAUDE_PROJECT_DIR を使う
    call_hook "$WT" ""
    expect_block frontend
    call_hook "$MAIN" ""
    expect_pass
    # CLAUDE_PROJECT_DIR が下のディレクトリでも最上位を見る
    call_hook "$WT/frontend" ""
    expect_block frontend
}

t_cwd_unresolved_falls_back_to_project_dir() {
    # Claude が作業フォルダの外へ cd したまま終えても、CLAUDE_PROJECT_DIR の作業フォルダの変更で止める
    change "$MAIN" frontend/src/a.txt $((T0 + 20))
    # git のリポジトリの外
    call_hook "$MAIN" "$OUTSIDE_DIR"
    expect_block frontend
    # 無いディレクトリ
    call_hook "$MAIN" "$WORK/no-such-dir"
    expect_block frontend
    # CLAUDE_PROJECT_DIR が下のディレクトリでも最上位を見る
    call_hook "$MAIN/frontend/src" "$OUTSIDE_DIR"
    expect_block frontend
    # CLAUDE_PROJECT_DIR の作業フォルダの記録が新しければ通す
    stamp "$MAIN" frontend $((T0 + 30))
    call_hook "$MAIN" "$OUTSIDE_DIR"
    expect_pass
}

t_no_folder_passes() {
    change "$MAIN" frontend/src/a.txt $((T0 + 20))
    # cwd も CLAUDE_PROJECT_DIR も無い
    call_hook "" ""
    expect_pass
    # cwd がリポジトリの外で、CLAUDE_PROJECT_DIR が無い
    call_hook "" "$OUTSIDE_DIR"
    expect_pass
    # cwd が無いディレクトリで、CLAUDE_PROJECT_DIR もリポジトリの外
    call_hook "$OUTSIDE_DIR" "$WORK/no-such-dir"
    expect_pass
    # cwd が無く、CLAUDE_PROJECT_DIR がリポジトリの外または無いディレクトリ
    call_hook "$OUTSIDE_DIR" ""
    expect_pass
    call_hook "$WORK/no-such-dir" ""
    expect_pass
}

# ---------------------------------------------------------------------
# 今までの動きを変えていないこと

t_stop_hook_active_passes() {
    change "$WT" frontend/src/a.txt $((T0 + 20))
    call_hook "$MAIN" "$WT" stop_hook_active JSON_TRUE
    expect_pass
    call_hook "$MAIN" "$WT" stop_hook_active JSON_FALSE
    expect_block frontend
}

t_each_area_and_clean() {
    # 変更が無ければ通す
    call_hook "$MAIN" "$WT"
    expect_pass
    # 3つの領域の外の変更では止めない
    change "$WT" README.md $((T0 + 20))
    call_hook "$MAIN" "$WT"
    expect_pass
    # 記録の無い領域だけを挙げる
    change "$WT" backend/src/a.txt $((T0 + 20))
    change "$WT" terraform/src/new.txt $((T0 + 20))
    stamp "$WT" backend $((T0 + 30))
    call_hook "$MAIN" "$WT"
    expect_block terraform
    expect_not_in_err backend frontend
}

t_bad_record_blocks() {
    change "$WT" backend/src/a.txt $((T0 + 20))
    stamp "$WT" backend "2026-10-05 12:00"
    call_hook "$MAIN" "$WT"
    expect_block backend
    stamp "$WT" backend ""
    call_hook "$MAIN" "$WT"
    expect_block backend
}

t_japanese_and_renamed_paths() {
    stamp "$WT" frontend $((T0 + 10))
    change "$WT" "frontend/src/日本語 ファイル.txt" $((T0 + 20))
    call_hook "$MAIN" "$WT"
    expect_block frontend
    reset_folders
    # リネームの新しいパスの時刻で判定し、旧パスは読み飛ばす
    stamp "$WT" backend $((T0 + 10))
    git -C "$WT" mv backend/src/a.txt backend/src/b.txt
    touch -d "@$((T0 + 20))" "$WT/backend/src/b.txt"
    call_hook "$MAIN" "$WT"
    expect_block backend
    stamp "$WT" backend $((T0 + 30))
    call_hook "$MAIN" "$WT"
    expect_pass
}

# ---------------------------------------------------------------------

echo "--- 作業フォルダの決め方(要件2.5)"
run_test "cwd が worktree のとき worktree の変更と記録を見る" t_worktree_uses_worktree_changes_and_record
run_test "本体フォルダの記録が新しくても worktree の変更が新しければ止める" t_main_record_newer_but_worktree_change_newer_blocks
run_test "cwd が worktree のとき本体フォルダの変更を数えない" t_main_changes_not_counted_from_worktree
run_test "cwd が本体フォルダのとき本体フォルダの記録を見る" t_main_folder_cwd_uses_main_record
run_test "cwd があれば CLAUDE_PROJECT_DIR を使わない" t_ignores_claude_project_dir_when_cwd_given
run_test "cwd が下のディレクトリでも \\ 区切りでも最上位を見る" t_subdir_and_backslash_cwd
run_test "cwd が無いとき CLAUDE_PROJECT_DIR を使う" t_no_cwd_uses_claude_project_dir
run_test "cwd から作業フォルダが決まらなければ CLAUDE_PROJECT_DIR の作業フォルダで止める" t_cwd_unresolved_falls_back_to_project_dir
run_test "cwd からも CLAUDE_PROJECT_DIR からも決まらないときだけ通す" t_no_folder_passes

echo "--- 今までの動き"
run_test "stop_hook_active が真なら通す" t_stop_hook_active_passes
run_test "変更のある領域のうち記録の無い領域だけで止める" t_each_area_and_clean
run_test "記録が UNIX 秒で読めなければ止める" t_bad_record_blocks
run_test "日本語のファイル名とリネームの新しいパスで判定する" t_japanese_and_renamed_paths

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
