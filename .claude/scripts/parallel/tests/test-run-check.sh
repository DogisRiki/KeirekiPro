#!/bin/bash
# =====================================================================
# run-check.sh(品質チェックのコマンドを1回きりのコンテナで動かすスクリプト)のテスト
#
# 実行: bash .claude/scripts/parallel/tests/test-run-check.sh
# 一時的な git のリポジトリ(本体)と worktree を作り、その中で run-check.sh を呼ぶ。
# docker は偽物(PATH の先頭に置く)に差し替える。偽物は、呼ばれたフォルダと引数を
# $FAKE_DOCKER_LOG に1行ずつ書き、次の環境変数とファイルで振る舞いを変える。
#   FAKE_CONFIG_RC   compose config -q の終了コード(既定0)
#   FAKE_DIND_PS     compose ps の出力にするファイル(dind のコンテナのID)
#   FAKE_UP_RC       compose up の終了コード(既定0)
#   FAKE_CHOWN_RC    chown のコンテナの終了コード(既定0)
#   FAKE_RUN_RC      品質チェックのコンテナの終了コード(既定0)
#   FAKE_EXEC_DIR    指定すると、品質チェックのコンテナの代わりに、そのフォルダで
#                    --entrypoint sh 以降(-c '<前にすること>; exec "$@"' -- <コマンド>)を本当に動かす
#   FAKE_RUN_HOLD    指定すると、そのファイルができるまで品質チェックのコンテナが終わらない
#   FAKE_VOLUMES     ボリュームの有無を表すフォルダ(volume inspect/create/rm)
#   FAKE_DOCKER_PS   docker ps(枠の取り戻しの確かめ)の出力にするファイル
# 前提: bash・perl(JSON::PP)・git。ホストの Git Bash から流す。本物の docker には触れない。
# =====================================================================
set -u

RUN_CHECK="$(cd "$(dirname "$0")/.." && pwd)/run-check.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# git が返すパス(Windows では C:/...)と同じ形で比べられるようにする
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

# --- 偽物の docker と、コンテナの中で呼ばれる道具(pnpm、terraform)
mkdir -p "$WORK/bin" "$WORK/volumes"
cat >"$WORK/bin/docker" <<'EOF'
#!/bin/bash
cwd=$(pwd -W 2>/dev/null || pwd)
printf '%s|%s\n' "$cwd" "$*" >>"$FAKE_DOCKER_LOG"
case "$1" in
    ps)
        [ -f "${FAKE_DOCKER_PS:-}" ] && cat "$FAKE_DOCKER_PS"
        exit 0
        ;;
    volume)
        case "$2" in
            inspect) [ -f "$FAKE_VOLUMES/$3" ]; exit $? ;;
            create) : >"$FAKE_VOLUMES/$3"; printf '%s\n' "$3"; exit 0 ;;
            rm) rm -f "$FAKE_VOLUMES/$3"; exit 0 ;;
        esac
        exit 0
        ;;
    version)
        if [ -n "${FAKE_DAEMON_DOWN:-}" ]; then
            echo "fake: error during connect: Docker のデーモンにつながらない" >&2
            exit 1
        fi
        echo 29.0.0
        exit 0
        ;;
    compose) ;;
    *) exit 0 ;;
esac
shift
# compose の全体の引数(-p -f --project-directory)を飛ばしてサブコマンドを探す
while [ $# -gt 0 ]; do
    case "$1" in
        -p | -f | --project-directory) shift 2 ;;
        *) break ;;
    esac
done
sub="$1"
shift
case "$sub" in
    config)
        if [ "${FAKE_CONFIG_RC:-0}" != 0 ]; then
            echo "fake: compose.yaml を読み込めない" >&2
            exit "$FAKE_CONFIG_RC"
        fi
        exit 0
        ;;
    ps)
        [ -f "${FAKE_DIND_PS:-}" ] && cat "$FAKE_DIND_PS"
        exit 0
        ;;
    up) exit "${FAKE_UP_RC:-0}" ;;
    run) ;;
    *) exit 0 ;;
esac
case " $* " in
    *" --entrypoint chown "*) exit "${FAKE_CHOWN_RC:-0}" ;;
esac
printf '%s\n' "$@" >"$FAKE_LAST_RUN"
if [ -n "${FAKE_RUN_HOLD:-}" ]; then
    echo $$ >"$FAKE_RUN_HOLD.pid"
    while [ ! -f "$FAKE_RUN_HOLD" ]; do sleep 0.1; done
fi
if [ -n "${FAKE_EXEC_DIR:-}" ]; then
    envs=()
    ep=
    while [ $# -gt 0 ]; do
        case "$1" in
            -e) envs+=("$2"); shift 2 ;;
            --entrypoint) ep="$2"; shift 2 ;;
            -v | -l | --label | -u | --name | -p | -w) shift 2 ;;
            -*) shift ;;
            *) break ;;
        esac
    done
    shift # サービスの名前
    cd "$FAKE_EXEC_DIR" || exit 98
    env "${envs[@]}" "$ep" "$@"
    exit $?
fi
exit "${FAKE_RUN_RC:-0}"
EOF
cat >"$WORK/bin/pnpm" <<'EOF'
#!/bin/bash
printf 'pnpm %s\n' "$*" >>"$FAKE_TOOL_LOG"
exit "${FAKE_PNPM_RC:-0}"
EOF
cat >"$WORK/bin/terraform" <<'EOF'
#!/bin/bash
printf 'terraform %s\n' "$*" >>"$FAKE_TOOL_LOG"
if [ "$1" = init ]; then
    [ "${FAKE_TF_INIT_RC:-0}" = 0 ] || exit "$FAKE_TF_INIT_RC"
    mkdir -p .terraform
fi
exit 0
EOF
chmod +x "$WORK/bin/docker" "$WORK/bin/pnpm" "$WORK/bin/terraform"
# PATH は : 区切りなので、C: を含まない形のパスで先頭に置く
export PATH="$TMP_ROOT/bin:$PATH"
export FAKE_DOCKER_LOG="$WORK/docker.log"
export FAKE_DOCKER_PS="$WORK/docker-ps.out"
export FAKE_DIND_PS="$WORK/dind-ps.out"
export FAKE_LAST_RUN="$WORK/last-run.args"
export FAKE_TOOL_LOG="$WORK/tool.log"
export FAKE_VOLUMES="$WORK/volumes"

# --- 一時的なリポジトリと worktree
MAIN_DIR="$WORK/RepoMain"
WT_DIR="$WORK/RepoWT"
git init -q "$MAIN_DIR"
git -C "$MAIN_DIR" checkout -q -B main
mkdir -p "$MAIN_DIR/frontend" "$MAIN_DIR/backend" "$MAIN_DIR/terraform"
echo 'services: {}' >"$MAIN_DIR/compose.yaml"
echo 'lockfileVersion: 9.0' >"$MAIN_DIR/frontend/pnpm-lock.yaml"
echo '{"name":"x"}' >"$MAIN_DIR/frontend/package.json"
echo seed >"$MAIN_DIR/backend/seed.txt"
echo seed >"$MAIN_DIR/terraform/seed.txt"
git -C "$MAIN_DIR" add -A
git -C "$MAIN_DIR" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m seed
git -C "$MAIN_DIR" worktree add -q "$WT_DIR" -b feat/wt
MAIN=$(git -C "$MAIN_DIR" rev-parse --show-toplevel)
WT=$(git -C "$WT_DIR" rev-parse --show-toplevel)
STATE="$(git -C "$MAIN_DIR" rev-parse --path-format=absolute --git-common-dir)/keirekipro-parallel"

# 期待値の計算(design.md の規則どおりに求める)
fkey() {
    local f
    f=$(git -C "$1" rev-parse --show-toplevel)
    if [ "$(git -C "$1" config --get core.ignorecase)" = true ]; then
        f=$(printf '%s' "$f" | tr 'A-Z' 'a-z')
    fi
    printf '%s' "$f" | git hash-object --stdin | cut -c1-12
}
lock_hash() { cat "$1/frontend/pnpm-lock.yaml" "$1/frontend/package.json" | git hash-object --stdin; }
now() { date +%s; }

# 記録の下書き(lib.sh の書き込みに頼らずに置く)
put_owner() { # <k> <folder> <folder_key> <kind> <started_at>
    mkdir -p "$STATE/slots/$1"
    printf '{"command":"x","folder":"%s","folder_key":"%s","kind":"%s","session_id":"s-x","started_at":%s}\n' \
        "$2" "$3" "$4" "$5" >"$STATE/slots/$1/owner.json"
}
put_issue() { # <N> <folder> <branch>
    mkdir -p "$STATE/issues"
    printf '{"branch":"%s","folder":"%s","handed_over_from":[],"issue":%s,"session_id":"","updated_at":1}\n' \
        "$3" "$2" "$1" >"$STATE/issues/$1.json"
}
slots() { git -C "$MAIN_DIR" config keirekipro.parallelSlots "$1"; }

# rc <フォルダ> <run-check.sh の引数>...: そのフォルダで run-check.sh を呼び、出力を $OUT、終了コードを $RC に入れる
rc() {
    local dir="$1"
    shift
    OUT=$(cd "$dir" && bash "$RUN_CHECK" "$@" 2>&1)
    RC=$?
}
# 品質チェックのコンテナを作った行(chown のコンテナを除く)
run_lines() { grep -v -- '--entrypoint chown' "$FAKE_DOCKER_LOG" | grep -E '\| ?compose .* run ' || true; }
chown_lines() { grep -- '--entrypoint chown' "$FAKE_DOCKER_LOG" || true; }
# 最後の品質チェックのコンテナの引数で、<印> の次の引数
arg_after() { awk -v m="$1" 'f { print; exit } $0 == m { f = 1 }' "$FAKE_LAST_RUN"; }

reset_state() {
    rm -rf "$STATE" "$MAIN_DIR/.claude" "$WT_DIR/.claude" "$WORK/exec" "$WORK"/hold*
    rm -f "$WORK/volumes"/* "$FAKE_DOCKER_PS" "$FAKE_DIND_PS" "$FAKE_LAST_RUN"
    : >"$FAKE_DOCKER_LOG"
    : >"$FAKE_TOOL_LOG"
    git -C "$MAIN_DIR" config --unset keirekipro.parallelSlots 2>/dev/null
    unset FAKE_CONFIG_RC FAKE_UP_RC FAKE_CHOWN_RC FAKE_RUN_RC FAKE_EXEC_DIR FAKE_RUN_HOLD FAKE_PNPM_RC
    unset FAKE_DAEMON_DOWN FAKE_TF_INIT_RC
    unset KP_WAIT_LIMIT_SECONDS KP_WAIT_INTERVAL_SECONDS KP_SESSION_ID
    echo dind-id >"$FAKE_DIND_PS"
}

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
# そのセッションの作業フォルダを検査する(要件2.1)
# =====================================================================
t_worktree_run() {
    local line key
    key=$(fkey "$WT_DIR")
    rc "$WT_DIR/frontend" frontend pnpm run lint
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    line=$(run_lines)
    [ "$(printf '%s\n' "$line" | grep -c .)" = 1 ] || die "品質チェックのコンテナが1つでない: $(cat "$FAKE_DOCKER_LOG")"
    case "$line" in
        "$WT|compose -p keirekipro -f compose.yaml run --rm --no-deps -T --label keirekipro.slot=1 --label keirekipro.folder=$key "*) ;;
        *) die "worktree の最上位で -p keirekipro run --rm --no-deps と枠のラベルが渡っていない: $line" ;;
    esac
    case "$line" in
        *" --entrypoint sh frontend -c "*" -- pnpm run lint") ;;
        *) die "サービスとコマンドの形が違う: $line" ;;
    esac
    grep -q "^$WT|compose -p keirekipro -f compose.yaml config -q$" "$FAKE_DOCKER_LOG" \
        || die "worktree の最上位で compose の読み込みを確かめていない: $(cat "$FAKE_DOCKER_LOG")"
    [ ! -d "$STATE/slots/1" ] || die "終わったのに枠を返していない"
    if grep -q "^$MAIN|" "$FAKE_DOCKER_LOG"; then
        die "本体フォルダで docker を呼んだ: $(cat "$FAKE_DOCKER_LOG")"
    fi
}

t_unknown_area() {
    rc "$WT_DIR" web pnpm run lint
    [ "$RC" = 69 ] || die "期待 69 / 実際 $RC: $OUT"
    case "$OUT" in *"[parallel] 検査できない: "*) ;; *) die "理由の文が無い: $OUT" ;; esac
    [ -z "$(run_lines)" ] || die "コンテナを作った"
}

# =====================================================================
# 検査できないときは合格にしない(要件2.4)
# =====================================================================
t_config_fail() {
    export FAKE_CONFIG_RC=1
    rc "$WT_DIR" frontend pnpm run coverage
    [ "$RC" = 69 ] || die "期待 69 / 実際 $RC: $OUT"
    case "$OUT" in
        *"[parallel] 検査できない: "*"fake: compose.yaml を読み込めない"*) ;;
        *) die "理由と compose のエラーの文が無い: $OUT" ;;
    esac
    [ -z "$(run_lines)" ] || die "読み込みに失敗したのにコンテナを作った: $(run_lines)"
    [ ! -e "$WT_DIR/.claude/.state/gate-run-frontend.txt" ] || die "記録を書いた"
    [ ! -d "$STATE/slots/1" ] || die "枠を返していない"
}

t_daemon_down() {
    export FAKE_DAEMON_DOWN=1
    rc "$WT_DIR" terraform checkov -d .
    [ "$RC" = 69 ] || die "期待 69 / 実際 $RC: $OUT"
    case "$OUT" in
        *"[parallel] 検査できない: Docker につながらない: "*"error during connect"*) ;;
        *) die "理由と docker のエラーの文が無い: $OUT" ;;
    esac
    [ -z "$(run_lines)" ] || die "Docker につながらないのにコンテナを作ろうとした: $(run_lines)"
    [ ! -e "$WT_DIR/.claude/.state/gate-run-terraform.txt" ] || die "記録を書いた"
    [ ! -d "$STATE/slots/1" ] || die "枠を返していない"
}

t_dind_up() {
    local up
    : >"$FAKE_DIND_PS"
    rc "$WT_DIR" backend ./gradlew check
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    grep -q "^$WT|compose -p keirekipro ps --status running -q dind$" "$FAKE_DOCKER_LOG" \
        || die "dind が動いているかを確かめていない: $(cat "$FAKE_DOCKER_LOG")"
    up=$(grep '| *compose .* up ' "$FAKE_DOCKER_LOG")
    case "$up" in
        *"--project-directory $MAIN -f $MAIN/compose.yaml up -d dind") ;;
        *) die "本体フォルダで up -d dind を打っていない: $up" ;;
    esac
    [ -n "$(run_lines)" ] || die "dind を起こしたあとに品質チェックを動かしていない"
    # 起こせなければ69で、品質チェックを動かさない
    reset_state
    : >"$FAKE_DIND_PS"
    export FAKE_UP_RC=1
    rc "$WT_DIR" backend ./gradlew check
    [ "$RC" = 69 ] || die "起こせないのに 期待 69 / 実際 $RC: $OUT"
    case "$OUT" in *"[parallel] 検査できない: "*dind*) ;; *) die "理由の文が無い: $OUT" ;; esac
    [ -z "$(run_lines)" ] || die "dind を起こせないのにコンテナを作った"
    [ ! -e "$WT_DIR/.claude/.state/gate-run-backend.txt" ] || die "記録を書いた"
}

t_dind_running() {
    rc "$WT_DIR" backend ./gradlew check
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    if grep -q '| *compose .* up ' "$FAKE_DOCKER_LOG"; then
        die "dind が動いているのに up を打った"
    fi
}

t_chown_fail() {
    export FAKE_CHOWN_RC=1
    rc "$WT_DIR" frontend pnpm run lint
    [ "$RC" = 69 ] || die "期待 69 / 実際 $RC: $OUT"
    case "$OUT" in *"[parallel] 検査できない: "*kp-pnpm-store-1*) ;; *) die "理由の文が無い: $OUT" ;; esac
    [ -z "$(run_lines)" ] || die "持ち主を変えられないのに品質チェックを動かした"
    [ ! -e "$WORK/volumes/kp-pnpm-store-1" ] || die "持ち主を変えられなかったボリュームを残した(次から作り直されない)"
    [ ! -d "$STATE/slots/1" ] || die "枠を返していない"
}

# =====================================================================
# そのセッションの品質チェックだけを数える(要件2.5)
# =====================================================================
t_gate_record_frontend() {
    local f="$WT_DIR/.claude/.state/gate-run-frontend.txt" t0 v
    rc "$WT_DIR" frontend pnpm run lint
    [ "$RC" = 0 ] || die "lint: 終了コード $RC"
    [ ! -e "$f" ] || die "最後の品質チェックでないのに記録を書いた"
    export FAKE_RUN_RC=1
    rc "$WT_DIR" frontend pnpm run coverage
    [ "$RC" = 1 ] || die "coverage の失敗: 期待 1 / 実際 $RC"
    [ ! -e "$f" ] || die "coverage が失敗したのに記録を書いた"
    export FAKE_RUN_RC=0
    t0=$(now)
    rc "$WT_DIR" frontend pnpm run coverage
    [ "$RC" = 0 ] || die "coverage: 終了コード $RC"
    [ -f "$f" ] || die "coverage が0で終わったのに worktree に記録が無い"
    v=$(tr -d '\r\n' <"$f")
    case "$v" in '' | *[!0-9]*) die "記録が UNIX 秒でない: '$v'" ;; esac
    [ "$v" -ge "$t0" ] && [ "$v" -le "$(now)" ] || die "記録の時刻が違う: $v"
    [ ! -e "$MAIN_DIR/.claude/.state/gate-run-frontend.txt" ] || die "本体フォルダに記録を書いた"
}

t_gate_record_backend_terraform() {
    rc "$WT_DIR" backend ./gradlew spotlessApply
    [ ! -e "$WT_DIR/.claude/.state/gate-run-backend.txt" ] || die "spotlessApply で記録を書いた"
    rc "$WT_DIR" backend ./gradlew check
    [ "$RC" = 0 ] || die "check: 終了コード $RC"
    [ -f "$WT_DIR/.claude/.state/gate-run-backend.txt" ] || die "./gradlew check のあとに記録が無い"
    rc "$WT_DIR" terraform tflint --recursive
    [ ! -e "$WT_DIR/.claude/.state/gate-run-terraform.txt" ] || die "tflint で記録を書いた"
    rc "$WT_DIR" terraform checkov -d .
    [ "$RC" = 0 ] || die "checkov: 終了コード $RC"
    [ -f "$WT_DIR/.claude/.state/gate-run-terraform.txt" ] || die "checkov のあとに記録が無い"
    [ ! -d "$MAIN_DIR/.claude/.state" ] || die "本体フォルダに記録を書いた"
}

# =====================================================================
# 結果を上書きしない(要件2.6)
# =====================================================================
t_nm_volume_per_folder() {
    local km kw
    km=$(fkey "$MAIN_DIR")
    kw=$(fkey "$WT_DIR")
    [ "$km" != "$kw" ] || die "本体と worktree の鍵が同じ"
    rc "$MAIN_DIR" frontend pnpm test
    [ "$RC" = 0 ] || die "本体: 終了コード $RC"
    grep -qx -- "kp-nm-$km:/home/node/app/node_modules" "$FAKE_LAST_RUN" \
        || die "本体の node_modules のボリュームが違う: $(tr '\n' ' ' <"$FAKE_LAST_RUN")"
    rc "$WT_DIR" frontend pnpm test
    [ "$RC" = 0 ] || die "worktree: 終了コード $RC"
    grep -qx -- "kp-nm-$kw:/home/node/app/node_modules" "$FAKE_LAST_RUN" \
        || die "worktree の node_modules のボリュームが違う: $(tr '\n' ' ' <"$FAKE_LAST_RUN")"
    rc "$WT_DIR" backend ./gradlew check
    grep -qx -- "kp-gradle-project-$kw:/home/spring/app/.gradle" "$FAKE_LAST_RUN" \
        || die "Gradle のプロジェクトのキャッシュが作業フォルダごとでない: $(tr '\n' ' ' <"$FAKE_LAST_RUN")"
}

# =====================================================================
# 待つ、待ちを示す(要件3.2・3.3)
# =====================================================================
t_full_no_wait() {
    local want
    put_issue 481 "$WT" feat/wt
    put_owner 1 "$WT" "$(fkey "$WT_DIR")" check "$(($(now) - 90))"
    rc "$MAIN_DIR" frontend pnpm run lint
    [ "$RC" = 10 ] || die "期待 10 / 実際 $RC: $OUT"
    want="[parallel] 順番待ち: 設定の数 1 の枠を、#481($WT、check、1分前から)が使っている"
    [ "$OUT" = "$want" ] || die "持ち主の一覧が違う: '$OUT' / 期待 '$want'"
    [ ! -s "$FAKE_DOCKER_LOG" ] || die "docker を呼んだ: $(cat "$FAKE_DOCKER_LOG")"
    grep -q '"folder_key":"'"$(fkey "$WT_DIR")"'"' "$STATE/slots/1/owner.json" || die "ほかの枠を書き換えた"
}

t_full_no_wait_no_issue() {
    local want
    put_owner 1 "$WT" "$(fkey "$WT_DIR")" check "$(($(now) - 90))"
    rc "$MAIN_DIR" frontend pnpm run lint
    [ "$RC" = 10 ] || die "期待 10 / 実際 $RC: $OUT"
    want="[parallel] 順番待ち: 設定の数 1 の枠を、Issue不明($WT、check、1分前から)が使っている"
    [ "$OUT" = "$want" ] || die "持ち主の一覧が違う: '$OUT' / 期待 '$want'"
}

t_wait_then_run() {
    local pid out_file rc_file i
    put_issue 481 "$WT" feat/wt
    put_owner 1 "$WT" "$(fkey "$WT_DIR")" check "$(now)"
    export KP_WAIT_INTERVAL_SECONDS=1 KP_WAIT_LIMIT_SECONDS=60
    out_file="$WORK/wait.out"
    rc_file="$WORK/wait.rc"
    (
        cd "$MAIN_DIR" || exit 98
        bash "$RUN_CHECK" --wait frontend pnpm run lint >"$out_file" 2>&1
        echo $? >"$rc_file"
    ) &
    pid=$!
    sleep 3
    [ ! -f "$rc_file" ] || die "空く前に終わった: $(cat "$rc_file") $(cat "$out_file")"
    [ -z "$(run_lines)" ] || die "空く前にコンテナを作った"
    grep -q '^\[parallel\] 順番待ち: 設定の数 1 の枠を、#481(' "$out_file" || die "待ちの知らせが無い: $(cat "$out_file")"
    echo 'released' >>"$FAKE_DOCKER_LOG"
    rm -rf "$STATE/slots/1"
    for i in $(seq 1 100); do
        [ -f "$rc_file" ] && break
        sleep 0.1
    done
    wait "$pid"
    [ "$(cat "$rc_file" 2>/dev/null)" = 0 ] || die "空いたあとの終了コード: $(cat "$rc_file" 2>/dev/null) $(cat "$out_file")"
    [ -n "$(run_lines)" ] || die "空いたあとに動いていない"
    awk '/^released$/ { r = 1 } / run / && r { ok = 1 } END { exit !ok }' "$FAKE_DOCKER_LOG" \
        || die "空く前に動いた: $(cat "$FAKE_DOCKER_LOG")"
    [ ! -d "$STATE/slots/1" ] || die "終わったのに枠を返していない"
}

# =====================================================================
# 同時に走っても失敗しない(要件3.4)
# =====================================================================
t_vitest_workers() {
    local n want
    for n in 1:8 2:4 3:2 8:1 16:1; do
        slots "${n%%:*}"
        want="VITEST_MAX_WORKERS=${n##*:}"
        rc "$WT_DIR" frontend pnpm test
        [ "$RC" = 0 ] || die "設定 ${n%%:*}: 終了コード $RC: $OUT"
        grep -qx -- "$want" "$FAKE_LAST_RUN" || die "設定 ${n%%:*}: $want が無い: $(tr '\n' ' ' <"$FAKE_LAST_RUN")"
    done
}

t_gradle_home_per_slot() {
    slots 2
    rc "$WT_DIR" backend ./gradlew check
    grep -qx -- "kp-gradle-home-1:/root/.gradle" "$FAKE_LAST_RUN" \
        || die "枠1の Gradle のキャッシュが違う: $(tr '\n' ' ' <"$FAKE_LAST_RUN")"
    put_owner 1 "$MAIN" "$(fkey "$MAIN_DIR")" check "$(now)"
    rc "$WT_DIR" backend ./gradlew check
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    grep -qx -- "--label" "$FAKE_LAST_RUN" && grep -qx -- "keirekipro.slot=2" "$FAKE_LAST_RUN" \
        || die "枠2を取っていない: $(tr '\n' ' ' <"$FAKE_LAST_RUN")"
    grep -qx -- "kp-gradle-home-2:/root/.gradle" "$FAKE_LAST_RUN" \
        || die "枠2の Gradle のキャッシュが枠ごとでない: $(tr '\n' ' ' <"$FAKE_LAST_RUN")"
    if grep -qx -- "kp-gradle-home-1:/root/.gradle" "$FAKE_LAST_RUN"; then
        die "ほかの枠の Gradle のキャッシュを載せた"
    fi
}

# =====================================================================
# 待ちの上限で合格にしない(要件3.5)
# =====================================================================
t_wait_limit() {
    local t0 t1
    put_issue 481 "$WT" feat/wt
    put_owner 1 "$WT" "$(fkey "$WT_DIR")" check "$(now)"
    export KP_WAIT_INTERVAL_SECONDS=1 KP_WAIT_LIMIT_SECONDS=2
    t0=$(now)
    rc "$MAIN_DIR" --wait frontend pnpm run coverage
    t1=$(now)
    [ "$RC" = 75 ] || die "期待 75 / 実際 $RC: $OUT"
    [ $((t1 - t0)) -ge 2 ] || die "上限より早く終わった: $((t1 - t0))秒"
    [ "$(printf '%s\n' "$OUT" | grep -c '^\[parallel\] 順番待ち: 設定の数 1 の枠を、#481(')" -ge 2 ] \
        || die "最初と上限のときに待っていた枠の持ち主を出していない: $OUT"
    [ -z "$(run_lines)" ] || die "コンテナを作った"
    [ ! -e "$MAIN_DIR/.claude/.state/gate-run-frontend.txt" ] || die "記録を書いた"
}

# =====================================================================
# コンテナの中の準備と sh -c の形
# =====================================================================
t_store_volume_chown() {
    local c
    rc "$WT_DIR" frontend pnpm run lint
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    grep -q '|volume create kp-pnpm-store-1$' "$FAKE_DOCKER_LOG" || die "ボリュームを作っていない: $(cat "$FAKE_DOCKER_LOG")"
    c=$(chown_lines)
    case "$c" in
        "$WT|compose -p keirekipro -f compose.yaml run --rm --no-deps -T -u root --label keirekipro.slot=1 -v kp-pnpm-store-1:/pnpm-store --entrypoint chown frontend node:node /pnpm-store") ;;
        *) die "枠のラベルを付けた root のコンテナで chown していない: '$c'" ;;
    esac
    awk '/volume create/ { v = 1 } /--entrypoint chown/ && v { c = 1 } /--entrypoint sh/ && c { ok = 1 } END { exit !ok }' "$FAKE_DOCKER_LOG" \
        || die "作る・持ち主を変える・品質チェックの順でない: $(cat "$FAKE_DOCKER_LOG")"
    grep -qx -- "kp-pnpm-store-1:/pnpm-store" "$FAKE_LAST_RUN" || die "ストアのボリュームを載せていない"
    # ボリュームがあれば作らず、持ち主も変えない
    : >"$FAKE_DOCKER_LOG"
    rc "$WT_DIR" frontend pnpm run lint
    [ "$RC" = 0 ] || die "2回目: 終了コード $RC"
    if grep -q 'volume create' "$FAKE_DOCKER_LOG" || [ -n "$(chown_lines)" ]; then
        die "ボリュームがあるのに作り直した: $(cat "$FAKE_DOCKER_LOG")"
    fi
}

t_node_modules_check() {
    local exec_dir="$WORK/exec" h
    mkdir -p "$exec_dir/node_modules"
    export FAKE_EXEC_DIR="$exec_dir"
    h=$(lock_hash "$WT_DIR")
    rc "$WT_DIR" frontend pnpm run lint
    [ "$RC" = 0 ] || die "1回目: 終了コード $RC: $OUT"
    [ "$(cat "$FAKE_TOOL_LOG")" = "$(printf 'pnpm install --frozen-lockfile --store-dir /pnpm-store\npnpm run lint')" ] \
        || die "印が無いのに install してからコマンドを動かしていない: $(cat "$FAKE_TOOL_LOG")"
    [ "$(cat "$exec_dir/node_modules/.kp-lock-hash")" = "$h" ] || die "印を書いていない: $(cat "$exec_dir/node_modules/.kp-lock-hash" 2>/dev/null)"
    : >"$FAKE_TOOL_LOG"
    rc "$WT_DIR" frontend pnpm run lint
    [ "$(cat "$FAKE_TOOL_LOG")" = "pnpm run lint" ] || die "印が同じなのに install した: $(cat "$FAKE_TOOL_LOG")"
    # lock が変わると印と違うので install し直す
    echo 'lockfileVersion: 9.1' >"$WT_DIR/frontend/pnpm-lock.yaml"
    : >"$FAKE_TOOL_LOG"
    rc "$WT_DIR" frontend pnpm run lint
    git -C "$WT_DIR" checkout -q -- frontend/pnpm-lock.yaml
    grep -q '^pnpm install --frozen-lockfile --store-dir /pnpm-store$' "$FAKE_TOOL_LOG" \
        || die "lock が変わったのに install していない: $(cat "$FAKE_TOOL_LOG")"
    # install が失敗したら、コマンドを動かさず69(合格にしない)
    rm -f "$exec_dir/node_modules/.kp-lock-hash"
    export FAKE_PNPM_RC=1
    : >"$FAKE_TOOL_LOG"
    rc "$WT_DIR" frontend pnpm run coverage
    [ "$RC" = 69 ] || die "install の失敗: 期待 69 / 実際 $RC: $OUT"
    [ "$(cat "$FAKE_TOOL_LOG")" = "pnpm install --frozen-lockfile --store-dir /pnpm-store" ] \
        || die "install が失敗したのにコマンドを動かした: $(cat "$FAKE_TOOL_LOG")"
    [ ! -e "$exec_dir/node_modules/.kp-lock-hash" ] || die "install が失敗したのに印を書いた"
    [ ! -e "$WT_DIR/.claude/.state/gate-run-frontend.txt" ] || die "記録を書いた"
}

t_backend_empty_prelude() {
    local exec_dir="$WORK/exec"
    mkdir -p "$exec_dir"
    printf '#!/bin/sh\nprintf "gradlew %%s\\n" "$*" >>"$FAKE_TOOL_LOG"\nexit 3\n' >"$exec_dir/gradlew"
    chmod +x "$exec_dir/gradlew"
    export FAKE_EXEC_DIR="$exec_dir"
    rc "$WT_DIR" backend ./gradlew check --info
    [ "$(arg_after -c)" = 'exec "$@"' ] || die "前にすることが空のときの sh -c の中身が違う: '$(arg_after -c)'"
    [ "$(arg_after 'exec "$@"')" = -- ] || die "sh -c の区切りが無い: $(tr '\n' ' ' <"$FAKE_LAST_RUN")"
    [ "$(cat "$FAKE_TOOL_LOG")" = "gradlew check --info" ] || die "コマンドが引数どおりに動いていない: $(cat "$FAKE_TOOL_LOG")"
    [ "$RC" = 3 ] || die "コマンドの終了コードをそのまま返していない: $RC"
}

t_terraform_init() {
    local exec_dir="$WORK/exec"
    mkdir -p "$exec_dir"
    export FAKE_EXEC_DIR="$exec_dir"
    rc "$WT_DIR" terraform terraform validate
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    [ "$(cat "$FAKE_TOOL_LOG")" = "$(printf 'terraform init -backend=false -input=false\nterraform validate')" ] \
        || die ".terraform が無いのに init していない: $(cat "$FAKE_TOOL_LOG")"
    grep -qx -- "kp-tf-plugins-1:/tf-plugin-cache" "$FAKE_LAST_RUN" || die "プラグインのキャッシュが枠ごとでない"
    grep -qx -- "TF_PLUGIN_CACHE_DIR=/tf-plugin-cache" "$FAKE_LAST_RUN" || die "TF_PLUGIN_CACHE_DIR が無い"
    : >"$FAKE_TOOL_LOG"
    rc "$WT_DIR" terraform terraform validate
    [ "$(cat "$FAKE_TOOL_LOG")" = "terraform validate" ] || die ".terraform があるのに init した: $(cat "$FAKE_TOOL_LOG")"
    # init が失敗したら、コマンドを動かさず69(合格にしない)
    rm -r "$exec_dir/.terraform"
    export FAKE_TF_INIT_RC=1
    : >"$FAKE_TOOL_LOG"
    rc "$WT_DIR" terraform checkov -d .
    [ "$RC" = 69 ] || die "init の失敗: 期待 69 / 実際 $RC: $OUT"
    case "$OUT" in *"[parallel] 検査できない: コンテナの中の準備(terraform init)に失敗した"*) ;; *) die "理由の文が無い: $OUT" ;; esac
    [ "$(cat "$FAKE_TOOL_LOG")" = "terraform init -backend=false -input=false" ] \
        || die "init が失敗したのにコマンドを動かした: $(cat "$FAKE_TOOL_LOG")"
    [ ! -e "$WT_DIR/.claude/.state/gate-run-terraform.txt" ] || die "記録を書いた"
}

t_command_exit_code_as_is() {
    local code
    export FAKE_RUN_RC=69
    rc "$WT_DIR" frontend pnpm run lint
    [ "$RC" = 69 ] || die "frontend のコマンドの終了コード 69: 実際 $RC"
    case "$OUT" in *"準備"*) die "コマンド自身の 69 を準備の失敗と取り違えた: $OUT" ;; esac
    for code in 69 197; do
        export FAKE_RUN_RC=$code
        rc "$WT_DIR" backend ./gradlew test
        [ "$RC" = "$code" ] || die "backend(前にすることが空)のコマンドの終了コード $code: 実際 $RC"
        case "$OUT" in *"準備"*) die "前にすることが空なのに準備の失敗と出した: $OUT" ;; esac
    done
}

t_source_only() {
    local out
    out=$(cd "$WT_DIR" && bash -c '. "$1" && declare -F kp_frontend_prepare' _ "$RUN_CHECK" 2>&1) \
        || die "読み込めないか準備の関数が無い: $out"
    [ "$out" = kp_frontend_prepare ] || die "出力が違う: $out"
    [ ! -s "$FAKE_DOCKER_LOG" ] || die "読み込んだだけで docker を呼んだ: $(cat "$FAKE_DOCKER_LOG")"
    [ ! -d "$STATE/slots" ] || die "読み込んだだけで枠を取った"
}

t_prepare_for_ui() {
    local out
    out=$(cd "$WT_DIR" && bash -c '
        . "$1" || exit 97
        kp_frontend_prepare 2 || exit $?
        printf "%s\n" "${KP_FRONTEND_ARGS[@]}"
        printf "PRE=%s\n" "$KP_FRONTEND_PRE"
    ' _ "$RUN_CHECK" 2>&1) || die "準備の関数が失敗した: $out"
    printf '%s\n' "$out" | grep -qx -- "kp-nm-$(fkey "$WT_DIR"):/home/node/app/node_modules" || die "node_modules のボリュームが無い: $out"
    printf '%s\n' "$out" | grep -qx -- "kp-pnpm-store-2:/pnpm-store" || die "枠2のストアのボリュームが無い: $out"
    printf '%s\n' "$out" | grep -qx -- "KP_LOCK_HASH=$(lock_hash "$WT_DIR")" || die "lock の値が無い: $out"
    printf '%s\n' "$out" | grep -q -- '^PRE=.*pnpm install --frozen-lockfile --store-dir /pnpm-store' || die "前にすることが無い: $out"
    grep -q -- "--label keirekipro.slot=2 -v kp-pnpm-store-2:/pnpm-store --entrypoint chown" "$FAKE_DOCKER_LOG" \
        || die "枠2のラベルで chown していない: $(cat "$FAKE_DOCKER_LOG")"
}

# =====================================================================
# 途中で止められたとき
# =====================================================================
t_trap_release() {
    local pid i dpid
    export FAKE_RUN_HOLD="$WORK/hold"
    (cd "$WT_DIR" && exec bash "$RUN_CHECK" frontend pnpm run coverage >"$WORK/trap.out" 2>&1) &
    pid=$!
    for i in $(seq 1 100); do
        [ -f "$WORK/hold.pid" ] && break
        sleep 0.1
    done
    [ -f "$WORK/hold.pid" ] || die "品質チェックのコンテナが動き出さない: $(cat "$WORK/trap.out")"
    [ -d "$STATE/slots/1" ] || die "動いている間に枠を持っていない"
    dpid=$(cat "$WORK/hold.pid")
    kill -TERM "$pid" 2>/dev/null
    kill -TERM "$dpid" 2>/dev/null
    wait "$pid"
    : >"$WORK/hold"
    [ ! -d "$STATE/slots/1" ] || die "止められたのに枠を返していない"
    [ ! -e "$WT_DIR/.claude/.state/gate-run-frontend.txt" ] || die "止められたのに記録を書いた"
}

echo "--- そのセッションの作業フォルダを検査する(要件2.1)"
run_test "worktree で呼ぶとその最上位で -p keirekipro run --rm --no-deps と枠のラベルが渡る" t_worktree_run
run_test "領域が frontend backend terraform のどれでもなければ終了コード69になる" t_unknown_area

echo "--- 検査できないときは合格にしない(要件2.4)"
run_test "compose の読み込みに失敗すると終了コード69で記録を書かない" t_config_fail
run_test "Docker のデーモンにつながらなければ終了コード69で、コンテナを作らず記録を書かず枠を返す" t_daemon_down
run_test "backend で dind が止まっていれば本体フォルダで起こし、起こせなければ終了コード69になる" t_dind_up
run_test "backend で dind が動いていれば起こさない" t_dind_running
run_test "pnpm のストアのボリュームの持ち主を変えられなければ終了コード69でボリュームを残さない" t_chown_fail

echo "--- そのセッションの品質チェックだけを数える(要件2.5)"
run_test "coverage が0で終わったときだけ worktree の gate-run-frontend.txt を書き、本体フォルダには書かない" t_gate_record_frontend
run_test "backend は ./gradlew check、terraform は checkov が0で終わったときだけ記録を書く" t_gate_record_backend_terraform

echo "--- 結果を上書きしない(要件2.6)"
run_test "作業フォルダごとの node_modules のボリューム名が鍵で分かれる" t_nm_volume_per_folder

echo "--- 待つ、待ちを示す(要件3.2・3.3)"
run_test "枠が埋まっていて --wait が無ければ終了コード10と持ち主の一覧を出し、docker を呼ばない" t_full_no_wait
run_test "Issueの記録が無い作業フォルダが枠を持っていれば Issue不明 と出し、欄がずれない" t_full_no_wait_no_issue
run_test "--wait では空いたあとに動く" t_wait_then_run

echo "--- 同時に走っても失敗しない(要件3.4)"
run_test "VITEST_MAX_WORKERS が 8 ÷ 設定の数になる" t_vitest_workers
run_test "Gradle のユーザーのキャッシュのボリュームが枠ごとに分かれる" t_gradle_home_per_slot

echo "--- 待ちの上限で合格にしない(要件3.5)"
run_test "待ちの上限で終了コード75になり記録を書かない" t_wait_limit

echo "--- コンテナの中の準備と sh -c の形"
run_test "pnpm のストアのボリュームが無ければ作り、枠のラベルを付けた root のコンテナで持ち主を変える" t_store_volume_chown
run_test "node_modules の印が lock と違えば pnpm install してから動かし、install が失敗すれば終了コード69になる" t_node_modules_check
run_test "コマンドの前にすることが空の backend でも sh -c の区切りが壊れず、終了コードをそのまま返す" t_backend_empty_prelude
run_test "terraform は .terraform が無ければ init してから動かし、init が失敗すれば終了コード69になる" t_terraform_init
run_test "コマンド自身の終了コードは69でもそのまま返し、準備の失敗と取り違えない" t_command_exit_code_as_is
run_test "読み込んだだけでは本体の処理を動かさない" t_source_only
run_test "frontend の準備の関数を読み込んで呼ぶと、載せるボリュームと前にすることが返る" t_prepare_for_ui

echo "--- 途中で止められたとき"
run_test "途中で止められても枠を返し、記録を書かない" t_trap_release

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
