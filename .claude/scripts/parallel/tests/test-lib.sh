#!/bin/bash
# =====================================================================
# lib.sh(記録の場所と枠の数え方をまとめた関数群)のテスト
#
# 実行: bash .claude/scripts/parallel/tests/test-lib.sh
# 一時的な git のリポジトリ(本体)と worktree を作り、lib.sh を読み込んで関数を呼ぶ。
# docker は、呼ばれた引数を記録するだけの偽物(PATH の先頭に置く)に差し替える。
# 偽物の docker ps の出力は、$FAKE_DOCKER_PS のファイルの中身で決める。
# 前提: bash・perl(JSON::PP)・git。ホストの Git Bash から流す。
# =====================================================================
set -u

LIB="$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# git が返すパス(Windows では C:/...)と同じ形で比べられるようにする
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

# --- 偽物の docker
mkdir -p "$WORK/bin"
cat >"$WORK/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_DOCKER_LOG"
if [ "$1" = ps ] && [ -f "$FAKE_DOCKER_PS" ]; then
    cat "$FAKE_DOCKER_PS"
fi
if [ "$1" = rm ] && [ -n "${FAKE_DOCKER_WATCH:-}" ]; then
    # rm が呼ばれた時点の枠の持ち主の記録を残す(取り戻す前に rm を呼んだかを確かめるため)
    if [ -f "$FAKE_DOCKER_WATCH" ]; then
        printf 'watch: %s\n' "$(tr -d '\n' <"$FAKE_DOCKER_WATCH")" >>"$FAKE_DOCKER_LOG"
    else
        printf 'watch: none\n' >>"$FAKE_DOCKER_LOG"
    fi
fi
if [ "$1" = rm ] && [ -n "${FAKE_DOCKER_RM_FAIL:-}" ]; then
    echo "Error response from daemon: fake rm failure" >&2
    exit 1
fi
exit 0
EOF
chmod +x "$WORK/bin/docker"
# PATH は : 区切りなので、C: を含まない形のパスで先頭に置く
export PATH="$TMP_ROOT/bin:$PATH"
export FAKE_DOCKER_LOG="$WORK/docker.log"
export FAKE_DOCKER_PS="$WORK/docker-ps.out"

# --- git worktree list だけを差し替える偽物の git(使うテストだけが PATH の先頭に置く)
# FAKE_GIT_WORKTREE_ONLY にパスがあればその作業フォルダだけを出して成功し、無ければ失敗する
REAL_GIT=$(command -v git)
export REAL_GIT
mkdir -p "$WORK/gitbin"
cat >"$WORK/gitbin/git" <<'EOF'
#!/bin/bash
if [ "$1" = worktree ] && [ "${2:-}" = list ]; then
    if [ -n "${FAKE_GIT_WORKTREE_ONLY:-}" ]; then
        printf 'worktree %s\nHEAD 0000000000000000000000000000000000000000\nbranch refs/heads/x\n' "$FAKE_GIT_WORKTREE_ONLY"
        exit 0
    fi
    echo "fatal: fake worktree list failure" >&2
    exit 128
fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$WORK/gitbin/git"

# --- 一時的なリポジトリ(大文字を含む名前にして core.ignorecase の分岐を確かめる)
MAIN_DIR="$WORK/RepoMain"
WT_DIR="$WORK/RepoWT"
OUTSIDE="$WORK/outside"
mkdir -p "$OUTSIDE"
git init -q "$MAIN_DIR"
git -C "$MAIN_DIR" checkout -q -B main
echo seed >"$MAIN_DIR/seed.txt"
git -C "$MAIN_DIR" add seed.txt
git -C "$MAIN_DIR" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m seed
git -C "$MAIN_DIR" worktree add -q "$WT_DIR" -b feat/wt
MAIN=$(git -C "$MAIN_DIR" rev-parse --show-toplevel)
WT=$(git -C "$WT_DIR" rev-parse --show-toplevel)
STATE="$(git -C "$MAIN_DIR" rev-parse --path-format=absolute --git-common-dir)/keirekipro-parallel"
ORIG_IGNORECASE=$(git -C "$MAIN_DIR" config --get core.ignorecase || true)

# 期待値の計算(lib.sh とは別に、design.md の規則どおりに求める)
fid() {
    local f
    f=$(git -C "$1" rev-parse --show-toplevel)
    if [ "$(git -C "$1" config --get core.ignorecase)" = true ]; then
        printf '%s' "$f" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
    else
        printf '%s' "$f"
    fi
}
fkey() { fid "$1" | git hash-object --stdin | cut -c1-12; }

# inside <フォルダ> <コード>: そのフォルダで lib.sh を読み込んでコードを動かす(別のサブシェル)
inside() {
    local dir="$1" code="$2"
    (
        cd "$dir" || exit 98
        # shellcheck disable=SC1090
        . "$LIB" || exit 97
        eval "$code"
    )
}

# 記録の下書き(lib.sh の書き込みに頼らずに置く)
put_owner() { # <k> <folder> <folder_key> <kind> <started_at> <session_id>
    mkdir -p "$STATE/slots/$1"
    printf '{"command":"x","folder":"%s","folder_key":"%s","kind":"%s","session_id":"%s","started_at":%s}\n' \
        "$2" "$3" "$4" "$6" "$5" >"$STATE/slots/$1/owner.json"
}
put_session() { # <session_id> <folder> <folder_key> <started_at>
    mkdir -p "$STATE/sessions"
    printf '{"folder":"%s","folder_key":"%s","last_seen":%s,"session_id":"%s","started_at":%s}\n' \
        "$2" "$3" "$4" "$1" "$4" >"$STATE/sessions/$1.json"
}
put_issue() { # <N> <folder> <branch>
    mkdir -p "$STATE/issues"
    printf '{"branch":"%s","folder":"%s","handed_over_from":[],"issue":%s,"session_id":"","updated_at":1}\n' \
        "$3" "$2" "$1" >"$STATE/issues/$1.json"
}
now() { date +%s; }

reset_state() {
    rm -rf "$STATE"
    git -C "$MAIN_DIR" config --unset keirekipro.parallelSlots 2>/dev/null
    if [ -n "$ORIG_IGNORECASE" ]; then
        git -C "$MAIN_DIR" config core.ignorecase "$ORIG_IGNORECASE"
    fi
    : >"$FAKE_DOCKER_LOG"
    rm -f "$FAKE_DOCKER_PS" "$WORK/go"
    unset FAKE_DOCKER_WATCH FAKE_DOCKER_RM_FAIL KP_SESSION_ID
    # 前のテストで消した worktree を、git の記録からも外す
    git -C "$MAIN_DIR" worktree prune
}

# 消した作業フォルダを作る: make_gone <名前> <rmdir|remove>
# worktree を作って最上位のパスと鍵を GONE と GONE_KEY に入れてから、
# rmdir はディレクトリだけを消し(git の一覧には prunable として残る)、remove は git worktree remove で消す。
make_gone() {
    local dir="$WORK/$1"
    git -C "$MAIN_DIR" worktree add -q "$dir" -b "feat/$1" || return 1
    GONE=$(git -C "$dir" rev-parse --show-toplevel)
    GONE_KEY=$(fkey "$dir")
    case "$2" in
        rmdir) rm -rf "$dir" ;;
        remove) git -C "$MAIN_DIR" worktree remove --force "$dir" ;;
    esac
    [ ! -d "$dir" ] || return 1
}
slots() { git -C "$MAIN_DIR" config keirekipro.parallelSlots "$1"; }

# 失敗の理由を出して、そのテストを終える(テストは run_test のサブシェルで動く)
die() {
    printf '%s\n' "$*"
    exit 1
}

pass=0
fail=0
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

# =====================================================================
# 設定の数
# =====================================================================
t_slots_default() {
    local got
    got=$(inside "$MAIN_DIR" 'kp_slots') || die "終了コード $?"
    [ "$got" = 1 ] || die "期待 1 / 実際 '$got'"
}

t_slots_three() {
    local got
    slots 3
    got=$(inside "$MAIN_DIR" 'kp_slots') || die "終了コード $?"
    [ "$got" = 3 ] || die "期待 3 / 実際 '$got'"
}

t_slots_invalid() {
    local v out rc
    for v in 0 abc 1.5; do
        slots "$v"
        out=$(inside "$MAIN_DIR" 'kp_slots' 2>&1)
        rc=$?
        [ "$rc" = 69 ] || die "値 $v: 期待 69 / 実際 $rc"
        case "$out" in
            *"keirekipro.parallelSlots の値 $v は1以上の整数ではない"*) ;;
            *) die "値 $v: 文が違う: $out" ;;
        esac
    done
}

t_same_state_and_config() {
    local a b
    slots 3
    a=$(inside "$MAIN_DIR" 'kp_state_dir') || die "本体: 終了コード $?"
    b=$(inside "$WT_DIR" 'kp_state_dir') || die "worktree: 終了コード $?"
    [ "$a" = "$b" ] || die "記録の置き場所が違う: '$a' / '$b'"
    [ "$a" = "$STATE" ] || die "記録の置き場所が本体の .git の下でない: '$a'"
    a=$(inside "$MAIN_DIR" 'kp_slots')
    b=$(inside "$WT_DIR" 'kp_slots')
    [ "$a" = 3 ] && [ "$b" = 3 ] || die "設定が違う: '$a' / '$b'"
    a=$(inside "$WT_DIR" 'kp_main_folder')
    [ "$a" = "$MAIN" ] || die "worktree から見た本体フォルダが違う: '$a'"
    a=$(inside "$MAIN_DIR" 'kp_main_folder')
    [ "$a" = "$MAIN" ] || die "本体から見た本体フォルダが違う: '$a'"
    a=$(inside "$WT_DIR" 'kp_folder')
    [ "$a" = "$WT" ] || die "worktree の作業フォルダが違う: '$a'"
}

# =====================================================================
# 作業フォルダと鍵
# =====================================================================
t_ignorecase_false() {
    local id key lower
    git -C "$MAIN_DIR" config core.ignorecase false
    id=$(inside "$MAIN_DIR" 'kp_folder_id')
    [ "$id" = "$MAIN" ] || die "false なのに作業フォルダが変わった: '$id'"
    case "$id" in *RepoMain*) ;; *) die "大文字が残っていない: '$id'" ;; esac
    key=$(inside "$MAIN_DIR" 'kp_folder_key')
    [ "$key" = "$(printf '%s' "$MAIN" | git hash-object --stdin | cut -c1-12)" ] || die "鍵が違う: '$key'"
    # 大文字と小文字だけが違う作業フォルダの枠は、自分の枠とみなさない
    lower=$(printf '%s' "$MAIN" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
    put_owner 1 "$lower" "$(printf '%s' "$lower" | git hash-object --stdin | cut -c1-12)" check "$(now)" s-x
    inside "$MAIN_DIR" 'kp_slot_release 1' >/dev/null 2>&1
    [ -d "$STATE/slots/1" ] || die "false なのに大文字と小文字が違う作業フォルダの枠を返した"
    # true にすると、小文字にして同じものとみなす
    git -C "$MAIN_DIR" config core.ignorecase true
    id=$(inside "$MAIN_DIR" 'kp_folder_id')
    [ "$id" = "$lower" ] || die "true なのに小文字になっていない: '$id'"
    inside "$MAIN_DIR" 'kp_slot_release 1' >/dev/null 2>&1
    [ ! -d "$STATE/slots/1" ] || die "true なのに大文字と小文字が違うだけの作業フォルダの枠を返せない"
}

t_folder_key() {
    local a b
    a=$(inside "$MAIN_DIR" 'kp_folder_key') || die "終了コード $?"
    b=$(inside "$WT_DIR" 'kp_folder_key') || die "終了コード $?"
    [ "$a" = "$(fkey "$MAIN_DIR")" ] || die "本体の鍵が違う: '$a'"
    [ "$b" = "$(fkey "$WT_DIR")" ] || die "worktree の鍵が違う: '$b'"
    [ "${#a}" = 12 ] || die "鍵が12文字でない: '$a'"
    [ "$a" != "$b" ] || die "本体と worktree の鍵が同じ"
}

t_outside_repo() {
    local rc f
    for f in kp_state_dir kp_folder kp_folder_key kp_main_folder; do
        (
            cd "$OUTSIDE" || exit 98
            export GIT_CEILING_DIRECTORIES="$WORK"
            # shellcheck source=/dev/null
            . "$LIB"
            "$f" >/dev/null 2>&1
        )
        rc=$?
        [ "$rc" = 69 ] || die "$f: 期待 69 / 実際 $rc"
    done
}

t_msys_no_pathconv() {
    local got
    # shellcheck disable=SC2016 # $1 などは子の bash の中で展開させる
    got=$(env -u MSYS_NO_PATHCONV bash -c '. "$1"; printf "%s" "${MSYS_NO_PATHCONV:-}"' _ "$LIB")
    [ "$got" = 1 ] || die "MSYS_NO_PATHCONV が '$got'"
}

# =====================================================================
# セッションのID
# =====================================================================
t_session_id() {
    local got
    got=$(inside "$MAIN_DIR" 'kp_session_id')
    [ -z "$got" ] || die "記録が無いのに '$got'"
    put_session s-new "$MAIN" "$(fkey "$MAIN_DIR")" 200
    put_session s-old "$MAIN" "$(fkey "$MAIN_DIR")" 100
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 50
    got=$(inside "$MAIN_DIR" 'kp_session_id')
    [ "$got" = s-old ] || die "本体: 期待 s-old / 実際 '$got'"
    got=$(inside "$WT_DIR" 'kp_session_id')
    [ "$got" = s-wt ] || die "worktree: 期待 s-wt / 実際 '$got'"
    got=$(inside "$MAIN_DIR" 'kp_session_id given-id')
    [ "$got" = given-id ] || die "渡した値: 期待 given-id / 実際 '$got'"
}

# =====================================================================
# 枠
# =====================================================================
t_full_cannot_acquire() {
    local a b c rc lines
    slots 2
    a=$(inside "$MAIN_DIR" 'kp_slot_acquire check "pnpm run lint"') || die "1つ目: 終了コード $?"
    b=$(inside "$WT_DIR" 'kp_slot_acquire check "./gradlew check"') || die "2つ目: 終了コード $?"
    [ "$a" = 1 ] && [ "$b" = 2 ] || die "番号: '$a' '$b'"
    c=$(inside "$MAIN_DIR" 'kp_slot_acquire check "pnpm test"')
    rc=$?
    [ "$rc" != 0 ] || die "埋まっているのに取れた: '$c'"
    [ -z "$c" ] || die "失敗なのに番号を出した: '$c'"
    lines=$(inside "$MAIN_DIR" 'kp_slot_holders' | wc -l)
    [ "$lines" -eq 2 ] || die "持ち主の一覧が2行でない: $lines"
    [ ! -d "$STATE/slots/3" ] || die "設定の数より大きい番号の枠を作った"
}

t_concurrent_acquire() {
    local round n r1 r2 o1 o2
    for n in 2 1; do
        for round in 1 2 3 4 5; do
            rm -rf "$STATE" "$WORK/go" "$WORK"/out* "$WORK"/rc*
            slots "$n"
            for i in 1 2; do
                (
                    cd "$MAIN_DIR" || exit 98
                    # shellcheck source=/dev/null
                    . "$LIB"
                    while [ ! -f "$WORK/go" ]; do sleep 0.05; done
                    kp_slot_acquire check "c$i" >"$WORK/out$i" 2>/dev/null
                    echo $? >"$WORK/rc$i"
                ) &
            done
            sleep 0.5
            : >"$WORK/go"
            wait
            r1=$(cat "$WORK/rc1")
            r2=$(cat "$WORK/rc2")
            o1=$(cat "$WORK/out1")
            o2=$(cat "$WORK/out2")
            if [ "$n" = 2 ]; then
                [ "$r1" = 0 ] && [ "$r2" = 0 ] || die "設定2 回$round: 終了コード $r1 $r2"
                [ "$o1" != "$o2" ] || die "設定2 回$round: 同じ枠 '$o1'"
                case "$o1$o2" in 12 | 21) ;; *) die "設定2 回$round: 番号 '$o1' '$o2'" ;; esac
            else
                if [ "$r1" = 0 ] && [ "$r2" = 0 ]; then
                    die "設定1 回$round: 2つとも取れた '$o1' '$o2'"
                fi
                [ "$r1" = 0 ] || [ "$r2" = 0 ] || die "設定1 回$round: どちらも取れない"
                [ "$o1$o2" = 1 ] || die "設定1 回$round: 番号 '$o1' '$o2'"
            fi
        done
    done
}

t_reclaim_old_check() {
    local got key
    slots 1
    put_owner 1 "$WT" "$(fkey "$WT_DIR")" check "$(($(now) - 300))" s-gone
    got=$(inside "$MAIN_DIR" 'kp_slot_acquire check "pnpm run lint"') || die "取れない: 終了コード $?"
    [ "$got" = 1 ] || die "番号: '$got'"
    # shellcheck disable=SC2016 # $(kp_state_dir) は inside が lib.sh を読み込んだサブシェルの中で展開させる
    key=$(inside "$MAIN_DIR" 'kp_json_get "$(kp_state_dir)/slots/1/owner.json" folder_key')
    [ "$key" = "$(fkey "$MAIN_DIR")" ] || die "持ち主が書き換わっていない: '$key'"
    grep -q 'ps .*label=keirekipro.slot=1.*status=running' "$FAKE_DOCKER_LOG" \
        || die "動いているコンテナを確かめていない: $(cat "$FAKE_DOCKER_LOG")"
}

t_keep_old_check_running() {
    local got rc
    slots 1
    put_owner 1 "$WT" "$(fkey "$WT_DIR")" check "$(($(now) - 300))" s-run
    echo cid-running >"$FAKE_DOCKER_PS"
    got=$(inside "$MAIN_DIR" 'kp_slot_acquire check x')
    rc=$?
    [ "$rc" != 0 ] || die "動いているコンテナがあるのに取れた: '$got'"
    grep -q '"session_id":"s-run"' "$STATE/slots/1/owner.json" || die "持ち主が書き換わった"
}

t_keep_young_check() {
    local got rc
    slots 1
    put_owner 1 "$WT" "$(fkey "$WT_DIR")" check "$(($(now) - 10))" s-young
    got=$(inside "$MAIN_DIR" 'kp_slot_acquire check x')
    rc=$?
    [ "$rc" != 0 ] || die "始めて10秒の枠を取り戻した: '$got'"
    grep -q '"session_id":"s-young"' "$STATE/slots/1/owner.json" || die "持ち主が書き換わった"
}

t_keep_ui_with_session() {
    local got rc
    slots 1
    put_session s-alive "$WT" "$(fkey "$WT_DIR")" 100
    put_owner 1 "$WT" "$(fkey "$WT_DIR")" ui "$(($(now) - 3000))" s-alive
    echo cid-ui >"$FAKE_DOCKER_PS"
    got=$(inside "$MAIN_DIR" 'kp_slot_acquire check x')
    rc=$?
    [ "$rc" != 0 ] || die "check で取れた: '$got'"
    got=$(inside "$MAIN_DIR" 'kp_slot_acquire ui x')
    rc=$?
    [ "$rc" != 0 ] || die "ほかの作業フォルダの ui で取れた: '$got'"
    if grep -q '^rm' "$FAKE_DOCKER_LOG"; then
        die "docker rm を呼んだ: $(cat "$FAKE_DOCKER_LOG")"
    fi
    grep -q '"session_id":"s-alive"' "$STATE/slots/1/owner.json" || die "持ち主が書き換わった"
}

t_reclaim_ui_without_session() {
    local got key
    slots 1
    put_owner 1 "$WT" "$(fkey "$WT_DIR")" ui "$(now)" s-closed
    echo cid-ui-1 >"$FAKE_DOCKER_PS"
    export FAKE_DOCKER_WATCH="$STATE/slots/1/owner.json"
    got=$(inside "$MAIN_DIR" 'kp_slot_acquire ui "ui.sh start"') || die "取れない: 終了コード $?"
    [ "$got" = 1 ] || die "番号: '$got'"
    grep -q 'ps .*label=keirekipro.slot=1.*label=keirekipro.kind=ui' "$FAKE_DOCKER_LOG" \
        || die "枠のラベルのコンテナを探していない: $(cat "$FAKE_DOCKER_LOG")"
    grep -q '^rm -f cid-ui-1$' "$FAKE_DOCKER_LOG" || die "docker rm -f を呼んでいない: $(cat "$FAKE_DOCKER_LOG")"
    grep -q '^watch: .*"session_id":"s-closed"' "$FAKE_DOCKER_LOG" \
        || die "取り戻したあとに rm を呼んだ: $(cat "$FAKE_DOCKER_LOG")"
    # shellcheck disable=SC2016 # $(kp_state_dir) は inside が lib.sh を読み込んだサブシェルの中で展開させる
    key=$(inside "$MAIN_DIR" 'kp_json_get "$(kp_state_dir)/slots/1/owner.json" folder_key')
    [ "$key" = "$(fkey "$MAIN_DIR")" ] || die "持ち主が書き換わっていない: '$key'"
}

t_reclaim_ui_gone_folder() {
    local mode got key
    slots 1
    for mode in rmdir remove; do
        reset_state
        slots 1
        make_gone "GoneUi-$mode" "$mode" || die "$mode: 消した作業フォルダを作れない"
        put_session s-gone "$GONE" "$GONE_KEY" 100
        put_owner 1 "$GONE" "$GONE_KEY" ui "$(now)" s-gone
        echo cid-ui-gone >"$FAKE_DOCKER_PS"
        export FAKE_DOCKER_WATCH="$STATE/slots/1/owner.json"
        got=$(inside "$MAIN_DIR" 'kp_slot_acquire ui "ui.sh start"') || die "$mode: 取れない: 終了コード $?"
        [ "$got" = 1 ] || die "$mode: 番号: '$got'"
        grep -q '^rm -f cid-ui-gone$' "$FAKE_DOCKER_LOG" \
            || die "$mode: docker rm -f を呼んでいない: $(cat "$FAKE_DOCKER_LOG")"
        grep -q '^watch: .*"session_id":"s-gone"' "$FAKE_DOCKER_LOG" \
            || die "$mode: 取り戻したあとに rm を呼んだ: $(cat "$FAKE_DOCKER_LOG")"
        # shellcheck disable=SC2016 # $(kp_state_dir) は inside が lib.sh を読み込んだサブシェルの中で展開させる
        key=$(inside "$MAIN_DIR" 'kp_json_get "$(kp_state_dir)/slots/1/owner.json" folder_key')
        [ "$key" = "$(fkey "$MAIN_DIR")" ] || die "$mode: 持ち主が書き換わっていない: '$key'"
        [ -f "$STATE/sessions/s-gone.json" ] || die "$mode: セッションの記録を消した"
    done
}

t_keep_ui_gone_rm_fails() {
    local got rc
    slots 1
    make_gone GoneRmFail rmdir || die "消した作業フォルダを作れない"
    put_session s-gone "$GONE" "$GONE_KEY" 100
    put_owner 1 "$GONE" "$GONE_KEY" ui "$(now)" s-gone
    echo cid-ui-stuck >"$FAKE_DOCKER_PS"
    export FAKE_DOCKER_RM_FAIL=1
    got=$(inside "$MAIN_DIR" 'kp_slot_acquire ui x' 2>/dev/null)
    rc=$?
    [ "$rc" != 0 ] || die "docker rm -f が失敗したのに取れた: '$got'"
    grep -q '^rm -f cid-ui-stuck$' "$FAKE_DOCKER_LOG" || die "docker rm -f を呼んでいない: $(cat "$FAKE_DOCKER_LOG")"
    grep -q '"session_id":"s-gone"' "$STATE/slots/1/owner.json" || die "持ち主が書き換わった"
}

t_keep_ui_list_unavailable() {
    local got rc
    slots 1
    put_session s-alive "$WT" "$(fkey "$WT_DIR")" 100
    put_owner 1 "$WT" "$(fkey "$WT_DIR")" ui "$(now)" s-alive
    echo cid-ui >"$FAKE_DOCKER_PS"
    got=$(PATH="$TMP_ROOT/gitbin:$PATH" inside "$MAIN_DIR" 'kp_slot_acquire ui x' 2>/dev/null)
    rc=$?
    [ "$rc" != 0 ] || die "作業フォルダの一覧を取れないのに取れた: '$got'"
    if grep -q '^rm' "$FAKE_DOCKER_LOG"; then
        die "docker rm を呼んだ: $(cat "$FAKE_DOCKER_LOG")"
    fi
    grep -q '"session_id":"s-alive"' "$STATE/slots/1/owner.json" || die "持ち主が書き換わった"
}

# =====================================================================
# 作業フォルダが無くなったかの判定(session.sh の prune と同じ判定)
# =====================================================================
t_live_folders() {
    local got want
    make_gone GoneList rmdir || die "消した作業フォルダを作れない"
    want=$(printf '%s\t%s\n%s\t%s' "$MAIN" "$(fkey "$MAIN_DIR")" "$WT" "$(fkey "$WT_DIR")")
    got=$(inside "$MAIN_DIR" 'kp_live_folders') || die "本体: 終了コード $?"
    [ "$got" = "$want" ] || die "本体からの一覧が違う: '$got'"
    got=$(inside "$WT_DIR" 'kp_live_folders') || die "worktree: 終了コード $?"
    [ "$got" = "$want" ] || die "worktree からの一覧が違う: '$got'"
}

t_folder_gone() {
    local rc lower live
    rc_of() { inside "$MAIN_DIR" "$1" >/dev/null 2>&1; echo $?; }
    make_gone GoneDir rmdir || die "rmdir: 作れない"
    [ "$(rc_of "kp_folder_gone '$GONE' '$GONE_KEY'")" = 0 ] || die "ディレクトリだけ消した worktree を無くなったとみなさない"
    [ "$(rc_of "kp_folder_gone '$GONE' ''")" = 0 ] || die "鍵が空の記録で無くなったとみなさない"
    make_gone GoneRemoved remove || die "remove: 作れない"
    [ "$(rc_of "kp_folder_gone '$GONE' '$GONE_KEY'")" = 0 ] || die "git worktree remove で消した worktree を無くなったとみなさない"
    # 作業フォルダか鍵のどちらかが当たれば残っている
    [ "$(rc_of "kp_folder_gone '$WT' 000000000000")" = 1 ] || die "作業フォルダが当たるのに無くなったとみなした"
    [ "$(rc_of "kp_folder_gone '$WORK/elsewhere' '$(fkey "$WT_DIR")'")" = 1 ] || die "鍵が当たるのに無くなったとみなした"
    [ "$(rc_of "kp_folder_gone '' '$(fkey "$MAIN_DIR")'")" = 1 ] || die "作業フォルダが空で鍵が当たるのに無くなったとみなした"
    [ "$(rc_of "kp_folder_gone '$MAIN' ''")" = 1 ] || die "本体フォルダを無くなったとみなした"
    [ "$(rc_of "kp_folder_gone '' ''")" = 1 ] || die "作業フォルダも鍵も空の記録を無くなったとみなした"
    # 大文字と小文字は core.ignorecase のとおりに比べる
    lower=$(printf '%s' "$WT" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
    git -C "$MAIN_DIR" config core.ignorecase true
    [ "$(rc_of "kp_folder_gone '$lower' 000000000000")" = 1 ] || die "true なのに小文字の作業フォルダを無くなったとみなした"
    git -C "$MAIN_DIR" config core.ignorecase false
    [ "$(rc_of "kp_folder_gone '$lower' 000000000000")" = 0 ] || die "false なのに小文字の作業フォルダを残っているとみなした"
    [ "$(rc_of "kp_folder_gone '$WT' 000000000000")" = 1 ] || die "false で作業フォルダが当たるのに無くなったとみなした"
    git -C "$MAIN_DIR" config core.ignorecase "${ORIG_IGNORECASE:-false}"
    # 一覧を渡せば、その一覧で判定する(渡した一覧に無い作業フォルダは無くなったとみなす)
    live=$(printf '%s\t%s' "$MAIN" "$(fkey "$MAIN_DIR")")
    [ "$(rc_of "kp_folder_gone '$WT' '$(fkey "$WT_DIR")' '$live'")" = 0 ] || die "渡した一覧で判定していない"
    [ "$(rc_of "kp_folder_gone '$MAIN' '' '$live'")" = 1 ] || die "渡した一覧に当たるのに無くなったとみなした"
    [ "$(rc_of "kp_folder_gone '$WT' '$(fkey "$WT_DIR")' ''")" = 2 ] || die "空の一覧で判定した"
}

t_folder_gone_list_unavailable() {
    local rc
    make_gone GoneNoList rmdir || die "作れない"
    PATH="$TMP_ROOT/gitbin:$PATH" inside "$MAIN_DIR" "kp_folder_gone '$GONE' '$GONE_KEY'" >/dev/null 2>&1
    rc=$?
    [ "$rc" = 2 ] || die "kp_folder_gone: 期待 2 / 実際 $rc"
    PATH="$TMP_ROOT/gitbin:$PATH" inside "$MAIN_DIR" 'kp_live_folders' >/dev/null 2>&1
    rc=$?
    [ "$rc" = 2 ] || die "kp_live_folders: 期待 2 / 実際 $rc"
    # 一覧にいまの作業フォルダが無いときも、一覧を取れないとみなす
    PATH="$TMP_ROOT/gitbin:$PATH" FAKE_GIT_WORKTREE_ONLY="$WT" \
        inside "$MAIN_DIR" "kp_folder_gone '$GONE' '$GONE_KEY'" >/dev/null 2>&1
    rc=$?
    [ "$rc" = 2 ] || die "いまの作業フォルダが無い一覧の kp_folder_gone: 期待 2 / 実際 $rc"
}

t_reacquire_own_ui() {
    local a b c rc
    slots 2
    put_session s-b "$WT" "$(fkey "$WT_DIR")" 100
    export KP_SESSION_ID=s-b
    a=$(inside "$WT_DIR" 'kp_slot_acquire ui "ui.sh start"') || die "1回目: 終了コード $?"
    unset KP_SESSION_ID
    b=$(inside "$MAIN_DIR" 'kp_slot_acquire check x') || die "check: 終了コード $?"
    [ "$a" = 1 ] && [ "$b" = 2 ] || die "番号: '$a' '$b'"
    export KP_SESSION_ID=s-b
    c=$(inside "$WT_DIR" 'kp_slot_acquire ui "ui.sh start"') || die "取り直し: 終了コード $?"
    [ "$c" = 1 ] || die "取り直しの番号: 期待 1 / 実際 '$c'"
    unset KP_SESSION_ID
    c=$(inside "$MAIN_DIR" 'kp_slot_acquire ui x')
    rc=$?
    [ "$rc" != 0 ] || die "ほかの作業フォルダが ui の枠を取れた: '$c'"
    if grep -q '^rm' "$FAKE_DOCKER_LOG"; then
        die "docker rm を呼んだ: $(cat "$FAKE_DOCKER_LOG")"
    fi
}

t_release_only_own() {
    local k
    k=$(inside "$WT_DIR" 'kp_slot_acquire check x') || die "終了コード $?"
    inside "$MAIN_DIR" "kp_slot_release $k" >/dev/null 2>&1
    [ -d "$STATE/slots/$k" ] || die "ほかの作業フォルダの枠を返した"
    inside "$WT_DIR" "kp_slot_release $k" || die "持ち主が返せない: 終了コード $?"
    [ ! -d "$STATE/slots/$k" ] || die "返したのに枠が残っている"
}

t_holders_issue() {
    local line want_start
    slots 2
    put_issue 481 "$WT" feat/x
    inside "$WT_DIR" 'kp_slot_acquire check "pnpm run lint"' >/dev/null || die "終了コード $?"
    line=$(inside "$MAIN_DIR" 'kp_slot_holders')
    want_start=$(printf '1\t%s\t481\tcheck\t' "$WT")
    case "$line" in
        "$want_start"[0-9]*) ;;
        *) die "一覧の行が違う: '$line'" ;;
    esac
}

t_shrink_slots() {
    local got rc lines
    slots 3
    inside "$MAIN_DIR" 'kp_slot_acquire check a; kp_slot_acquire check b; kp_slot_acquire check c' >/dev/null
    inside "$MAIN_DIR" 'kp_slot_release 2' || die "返せない"
    slots 1
    got=$(inside "$MAIN_DIR" 'kp_slot_acquire check d')
    rc=$?
    [ "$rc" != 0 ] || die "数より大きい番号の枠を取った: '$got'"
    lines=$(inside "$MAIN_DIR" 'kp_slot_holders' | wc -l)
    [ "$lines" -eq 2 ] || die "数より大きい番号の埋まっている枠を数えていない: $lines"
}

t_json_roundtrip() {
    local f got p
    mkdir -p "$STATE"
    f="$STATE/t.json"
    inside "$MAIN_DIR" "kp_json_write '$f' folder='C:/作業/フォルダ' started_at:=123 list:='[\"a\"]'" || die "書けない"
    inside "$MAIN_DIR" "kp_json_write '$f' branch=feat/x" || die "書き足せない"
    got=$(inside "$MAIN_DIR" "kp_json_get '$f' folder")
    [ "$got" = 'C:/作業/フォルダ' ] || die "文字列: '$got'"
    got=$(inside "$MAIN_DIR" "kp_json_get '$f' started_at")
    [ "$got" = 123 ] || die "数: '$got'"
    grep -q '"started_at":123' "$f" || die "数が数として書かれていない: $(cat "$f")"
    got=$(inside "$MAIN_DIR" "kp_json_get '$f' list")
    [ "$got" = '["a"]' ] || die "配列: '$got'"
    got=$(inside "$MAIN_DIR" "kp_json_get '$f' branch")
    [ "$got" = feat/x ] || die "書き足した値: '$got'"
    got=$(inside "$MAIN_DIR" "kp_json_get '$f' missing")
    [ -z "$got" ] || die "無いキー: '$got'"
    for p in "$STATE"/*; do
        [ -e "$p" ] || [ -L "$p" ] || continue
        [ "${p##*/}" = t.json ] || die "一時ファイルが残った: $(ls "$STATE")"
    done
}

echo "--- 設定の数(要件3.1)"
run_test "設定が無いときに1を返す" t_slots_default
run_test "3 を設定すると3を返す" t_slots_three
run_test "0 や abc では終了コード69になる" t_slots_invalid
run_test "worktree と本体フォルダのどちらから呼んでも、記録の置き場所と設定が同じになる" t_same_state_and_config

echo "--- 作業フォルダと鍵"
run_test "core.ignorecase が false なら大文字と小文字を区別したまま比べる" t_ignorecase_false
run_test "鍵は作業フォルダを git hash-object にかけた値の先頭12文字で、作業フォルダごとに違う" t_folder_key
run_test "git のリポジトリの外では終了コード69になる" t_outside_repo
run_test "読み込むと MSYS_NO_PATHCONV=1 が設定される" t_msys_no_pathconv
run_test "セッションのIDは、渡された値か、いまの作業フォルダの記録のうちいちばん古いもの" t_session_id

echo "--- 枠(要件3.2・3.4・1.5)"
run_test "設定の数の枠が埋まっていれば取れない" t_full_cannot_acquire
run_test "2つのプロセスが同時に取っても同じ枠を取らない" t_concurrent_acquire
run_test "動いているコンテナの無い古い check の枠を取り戻す" t_reclaim_old_check
run_test "動いているコンテナがある古い check の枠は取り戻さない" t_keep_old_check_running
run_test "始めて120秒以内の check の枠は取り戻さない" t_keep_young_check
run_test "持ち主のセッションの記録が残っている ui の枠は取り戻さず docker rm -f を呼ばない" t_keep_ui_with_session
run_test "持ち主の記録が無い ui の枠は docker rm -f を呼んでから取り戻す" t_reclaim_ui_without_session
run_test "持ち主のセッションの記録が残っていても、記録の作業フォルダが無くなっている ui の枠は docker rm -f を呼んでから取り戻す" t_reclaim_ui_gone_folder
run_test "記録の作業フォルダが無くなっている ui の枠でも、docker rm -f で消せなければ取り戻さない" t_keep_ui_gone_rm_fails
run_test "作業フォルダの一覧を取れないときは、記録が残っている ui の枠を取り戻さず docker rm -f を呼ばない" t_keep_ui_list_unavailable
run_test "いまの作業フォルダが持つ ui の枠は同じ番号で取り直せる" t_reacquire_own_ui
run_test "枠を返せるのは持ち主の作業フォルダだけ" t_release_only_own
run_test "枠の持ち主の一覧に、Issueの記録から引いたIssueの番号が出る" t_holders_issue
run_test "設定を減らすと、数より大きい番号の空いた枠は取らず、埋まっている枠は数える" t_shrink_slots

echo "--- 作業フォルダが無くなったかの判定"
run_test "残っている作業フォルダの一覧に、ディレクトリが無い worktree は出ない" t_live_folders
run_test "作業フォルダと鍵のどちらも一覧に当たらない記録だけを、無くなったとみなす" t_folder_gone
run_test "作業フォルダの一覧を取れないときと、一覧にいまの作業フォルダが無いときは、終了コード2で判定しない" t_folder_gone_list_unavailable

echo "--- JSON"
run_test "JSON の読み書きが往復し、一時ファイルを残さない" t_json_roundtrip

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
