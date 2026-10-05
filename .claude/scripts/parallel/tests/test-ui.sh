#!/bin/bash
# =====================================================================
# ui.sh(画面確認の開発サーバを1回きりのコンテナで動かすスクリプト)のテスト
#
# 実行: bash .claude/scripts/parallel/tests/test-ui.sh
# 一時的な git のリポジトリ(本体)と worktree を作り、その中で ui.sh を呼ぶ。
# docker と curl は偽物(PATH の先頭に置く)に差し替える。偽物の docker は、呼ばれたフォルダと
# 引数を $FAKE_DOCKER_LOG に1行ずつ書き、コンテナを $FAKE_CONTAINERS のファイル(中身はラベル)
# として作る・探す・消す。次の環境変数とファイルで振る舞いを変える。
#   FAKE_SERVICES      動いている共有のサービスを表すフォルダ(compose ps / up)
#   FAKE_UP_RC         compose up の終了コード(既定0)
#   FAKE_DB_EXISTS     指定すると、鍵の DB があることにする
#   FAKE_PSQL_RC       DB があるかの確かめ(psql)の終了コード(既定0)
#   FAKE_RUN_RC_<サービス>  そのサービスの compose run -d の終了コード(既定0)
#   FAKE_CHOWN_RC      chown のコンテナの終了コード(既定0)
#   FAKE_VOLUMES       ボリュームの有無を表すフォルダ(volume inspect/create/rm)
# 偽物の curl は、$FAKE_CURL_OK のファイルがあるときだけ成功する。
# frontend の TCP の確かめ(_kp_ui_tcp_open)は、start の流れのテストでは、ui.sh を読み込んで
# $FAKE_TCP_OK のファイルを見る関数に差し替える。関数そのものは、本物の perl の待ち受けで確かめる。
# 前提: bash・perl(JSON::PP)・git。ホストの Git Bash から流す。本物の docker には触れない。
# =====================================================================
set -u

UI="$(cd "$(dirname "$0")/.." && pwd)/ui.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# git が返すパス(Windows では C:/...)と同じ形で比べられるようにする
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

# --- 偽物の docker と curl
mkdir -p "$WORK/bin" "$WORK/volumes" "$WORK/containers" "$WORK/services"
cat >"$WORK/bin/docker" <<'EOF'
#!/bin/bash
cwd=$(pwd -W 2>/dev/null || pwd)
printf '%s|%s\n' "$cwd" "$*" >>"$FAKE_DOCKER_LOG"
# ラベルをすべて持つコンテナの名前(偽物ではIDを兼ねる)を出す
list_containers() {
    local f l ok
    for f in "$FAKE_CONTAINERS"/*; do
        [ -f "$f" ] || continue
        ok=1
        for l in "$@"; do
            grep -qxF -- "$l" "$f" || { ok=0; break; }
        done
        [ "$ok" = 1 ] && basename "$f"
    done
    return 0
}
case "$1" in
    ps)
        shift
        labels=()
        while [ $# -gt 0 ]; do
            case "$1" in
                --filter)
                    case "$2" in label=*) labels+=("${2#label=}") ;; esac
                    shift 2
                    ;;
                *) shift ;;
            esac
        done
        list_containers "${labels[@]}"
        exit 0
        ;;
    rm)
        shift
        [ "$1" = -f ] && shift
        for id in "$@"; do rm -f "$FAKE_CONTAINERS/$id"; done
        exit 0
        ;;
    logs)
        printf 'fake log: %s\n' "${*: -1}"
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
    version) echo 29.0.0; exit 0 ;;
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
    ps)
        svc="${*: -1}"
        [ -f "$FAKE_SERVICES/$svc" ] && printf '%s-id\n' "$svc"
        exit 0
        ;;
    up)
        [ "${FAKE_UP_RC:-0}" = 0 ] || { echo "fake: 起こせない" >&2; exit "$FAKE_UP_RC"; }
        for s in "$@"; do
            case "$s" in -*) ;; *) : >"$FAKE_SERVICES/$s" ;; esac
        done
        exit 0
        ;;
    exec)
        case "$*" in
            *"SELECT 1 FROM pg_database"*)
                [ "${FAKE_PSQL_RC:-0}" = 0 ] || { echo "fake: psql に失敗した" >&2; exit "$FAKE_PSQL_RC"; }
                [ -n "${FAKE_DB_EXISTS:-}" ] && printf '1\r\n'
                exit 0
                ;;
        esac
        exit 0
        ;;
    run) ;;
    *) exit 0 ;;
esac
case " $* " in
    *" --entrypoint chown "*) exit "${FAKE_CHOWN_RC:-0}" ;;
esac
all=("$@")
name=
svc=
labels=()
while [ $# -gt 0 ]; do
    case "$1" in
        --name) name="$2"; shift 2 ;;
        --label | -l) labels+=("$2"); shift 2 ;;
        -p | -v | -e | -u | -w | --entrypoint) shift 2 ;;
        -*) shift ;;
        *) svc="$1"; break ;;
    esac
done
printf '%s\n' "${all[@]}" >"$FAKE_RUNS/$svc.args"
rcvar="FAKE_RUN_RC_$svc"
if [ "${!rcvar:-0}" != 0 ]; then
    echo "fake: $svc のコンテナを作れない" >&2
    exit "${!rcvar}"
fi
printf '%s\n' "${labels[@]}" >"$FAKE_CONTAINERS/$name"
printf '%s\n' "$name"
exit 0
EOF
cat >"$WORK/bin/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_CURL_LOG"
[ -f "$FAKE_CURL_OK" ] && exit 0
echo "curl: (7) Failed to connect" >&2
exit 7
EOF
chmod +x "$WORK/bin/docker" "$WORK/bin/curl"
# PATH は : 区切りなので、C: を含まない形のパスで先頭に置く
export PATH="$TMP_ROOT/bin:$PATH"
export FAKE_DOCKER_LOG="$WORK/docker.log"
export FAKE_CONTAINERS="$WORK/containers"
export FAKE_SERVICES="$WORK/services"
export FAKE_VOLUMES="$WORK/volumes"
export FAKE_RUNS="$WORK/runs"
export FAKE_CURL_LOG="$WORK/curl.log"
export FAKE_CURL_OK="$WORK/curl.ok"
export FAKE_TCP_LOG="$WORK/tcp.log"
export FAKE_TCP_OK="$WORK/tcp.ok"

# --- 一時的なリポジトリと worktree
MAIN_DIR="$WORK/RepoMain"
WT_DIR="$WORK/RepoWT"
git init -q "$MAIN_DIR"
git -C "$MAIN_DIR" checkout -q -B main
mkdir -p "$MAIN_DIR/frontend" "$MAIN_DIR/backend"
echo 'services: {}' >"$MAIN_DIR/compose.yaml"
echo 'lockfileVersion: 9.0' >"$MAIN_DIR/frontend/pnpm-lock.yaml"
echo '{"name":"x"}' >"$MAIN_DIR/frontend/package.json"
echo seed >"$MAIN_DIR/backend/seed.txt"
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
        f=$(printf '%s' "$f" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
    fi
    printf '%s' "$f" | git hash-object --stdin | cut -c1-12
}
lock_hash() { cat "$1/frontend/pnpm-lock.yaml" "$1/frontend/package.json" | git hash-object --stdin; }
now() { date +%s; }
KM=$(fkey "$MAIN_DIR")
KW=$(fkey "$WT_DIR")

# 記録の下書き(lib.sh の書き込みに頼らずに置く)
put_owner() { # <k> <folder> <folder_key> <kind> <started_at> <session_id>
    mkdir -p "$STATE/slots/$1"
    printf '{"command":"x","folder":"%s","folder_key":"%s","kind":"%s","session_id":"%s","started_at":%s}\n' \
        "$2" "$3" "$4" "$6" "$5" >"$STATE/slots/$1/owner.json"
}
put_session() { # <session_id> <folder> <folder_key>
    mkdir -p "$STATE/sessions"
    printf '{"folder":"%s","folder_key":"%s","last_seen":1,"session_id":"%s","started_at":1}\n' \
        "$2" "$3" "$1" >"$STATE/sessions/$1.json"
}
put_issue() { # <N> <folder> <branch>
    mkdir -p "$STATE/issues"
    printf '{"branch":"%s","folder":"%s","handed_over_from":[],"issue":%s,"session_id":"","updated_at":1}\n' \
        "$3" "$2" "$1" >"$STATE/issues/$1.json"
}
put_container() { # <名前> <ラベル>...
    local name="$1"
    shift
    printf '%s\n' "$@" >"$FAKE_CONTAINERS/$name"
}
owner_get() { # <k> <キー>
    perl -MJSON::PP -e 'open my $f, "<", $ARGV[0] or exit 1; local $/; my $d = decode_json(<$f>); print $d->{$ARGV[1]} // ""' \
        -- "$STATE/slots/$1/owner.json" "$2"
}
slots() { git -C "$MAIN_DIR" config keirekipro.parallelSlots "$1"; }

# ui <フォルダ> <ui.sh の引数>...: ui.sh を読み込み、TCP の確かめを偽物に差し替えて呼ぶ。
# 出力を $OUT、終了コードを $RC に入れる
ui() {
    local dir="$1"
    shift
    # shellcheck disable=SC2016 # 子の bash が展開する
    OUT=$(cd "$dir" && bash -c '
        . "$1" || exit 97
        shift
        _kp_ui_tcp_open() { printf "%s\n" "$1" >>"$FAKE_TCP_LOG"; [ -f "$FAKE_TCP_OK" ]; }
        kp_ui_main "$@"
    ' _ "$UI" "$@" 2>&1)
    RC=$?
}
# ui_direct <フォルダ> <ui.sh の引数>...: ui.sh をそのまま呼ぶ
ui_direct() {
    local dir="$1"
    shift
    OUT=$(cd "$dir" && bash "$UI" "$@" 2>&1)
    RC=$?
}
run_lines() { grep -E '\| ?compose .* run -d ' "$FAKE_DOCKER_LOG" || true; }
# 作られたコンテナの引数で、<印> の次の引数
arg_after() { awk -v m="$2" 'f { print; exit } $0 == m { f = 1 }' "$FAKE_RUNS/$1.args"; }

reset_state() {
    rm -rf "$STATE" "$FAKE_RUNS" "$WORK"/listen*
    rm -f "$FAKE_CONTAINERS"/* "$FAKE_SERVICES"/* "$FAKE_VOLUMES"/*
    : >"$FAKE_DOCKER_LOG"
    : >"$FAKE_CURL_LOG"
    : >"$FAKE_TCP_LOG"
    mkdir -p "$FAKE_RUNS"
    : >"$FAKE_CURL_OK"
    : >"$FAKE_TCP_OK"
    for s in db redis localstack dind; do : >"$FAKE_SERVICES/$s"; done
    git -C "$MAIN_DIR" config --unset keirekipro.parallelSlots 2>/dev/null
    unset FAKE_UP_RC FAKE_DB_EXISTS FAKE_PSQL_RC FAKE_RUN_RC_backend FAKE_RUN_RC_frontend FAKE_CHOWN_RC
    unset KP_WAIT_LIMIT_SECONDS KP_WAIT_INTERVAL_SECONDS KP_SESSION_ID
    unset KP_UI_BACKEND_TRIES KP_UI_BACKEND_INTERVAL_SECONDS KP_UI_FRONTEND_TRIES KP_UI_FRONTEND_INTERVAL_SECONDS
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
# 画面にそのセッションの変更が出る(要件2.2)
# =====================================================================
t_start_args() {
    local json be fe script s
    slots 2
    # 枠1はほかの作業フォルダの品質チェックが使っているので、枠2を取る
    put_owner 1 "$MAIN" "$KM" check "$(now)" s-main
    ui "$WT_DIR/frontend" start --session s-wt
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    for s in db redis localstack dind; do
        grep -qxF "$WT|compose -p keirekipro ps --status running -q $s" "$FAKE_DOCKER_LOG" \
            || die "共有のサービス $s が動いているかを確かめていない: $(cat "$FAKE_DOCKER_LOG")"
    done
    grep -qxF "$WT|compose -p keirekipro exec -T db psql -U postgres -tAc SELECT 1 FROM pg_database WHERE datname='kp_$KW'" "$FAKE_DOCKER_LOG" \
        || die "鍵の DB があるかを確かめていない: $(cat "$FAKE_DOCKER_LOG")"
    grep -qxF "$WT|compose -p keirekipro exec -T db psql -U postgres -c CREATE DATABASE kp_$KW" "$FAKE_DOCKER_LOG" \
        || die "鍵の DB を作っていない: $(cat "$FAKE_DOCKER_LOG")"
    json='{"spring":{"datasource":{"url":"jdbc:postgresql://db:5432/kp_'"$KW"'"}},"frontend-base-url":"http://host.docker.internal:15175","cors":{"allowed-origins":"http://host.docker.internal:15175"}}'
    be="$WT|compose -p keirekipro -f compose.yaml run -d --no-deps --name kp-ui-2-backend -p 18082:8080 --label keirekipro.slot=2 --label keirekipro.folder=$KW --label keirekipro.kind=ui -v kp-gradle-home-2:/root/.gradle -v kp-gradle-project-$KW:/home/spring/app/.gradle -e SPRING_APPLICATION_JSON=$json backend ./gradlew bootRun --args=--spring.profiles.active=dev"
    grep -qxF "$be" "$FAKE_DOCKER_LOG" || die "backend の起動の形が違う: $(run_lines)"
    grep -qxF -- "SPRING_APPLICATION_JSON=$json" "$FAKE_RUNS/backend.args" \
        || die "SPRING_APPLICATION_JSON が1つの引数で渡っていない: $(cat "$FAKE_RUNS/backend.args")"
    fe="$WT|compose -p keirekipro -f compose.yaml run -d --no-deps --name kp-ui-2-frontend -p 15175:5173 --label keirekipro.slot=2 --label keirekipro.folder=$KW --label keirekipro.kind=ui -v kp-nm-$KW:/home/node/app/node_modules -v kp-pnpm-store-2:/pnpm-store -e KP_LOCK_HASH=$(lock_hash "$WT_DIR") -e VITE_API_URL=http://host.docker.internal:18082/api/ frontend sh -c "
    case "$(grep -F -- '--name kp-ui-2-frontend' "$FAKE_DOCKER_LOG")" in
        "$fe"*) ;;
        *) die "frontend の起動の形が違う: $(run_lines)" ;;
    esac
    script=$(arg_after frontend -c)
    case "$script" in
        *"pnpm install --frozen-lockfile --store-dir /pnpm-store"*"pnpm run dev") ;;
        *) die "frontend のコンテナの中で node_modules を確かめてから pnpm run dev を動かしていない: '$script'" ;;
    esac
    grep -qF -- "-fsS http://localhost:18082/actuator/health" "$FAKE_CURL_LOG" || die "backend の健康を確かめていない: $(cat "$FAKE_CURL_LOG")"
    grep -qx 15175 "$FAKE_TCP_LOG" || die "frontend に TCP でつながるかを確かめていない: $(cat "$FAKE_TCP_LOG")"
    printf '%s\n' "$OUT" | grep -qxF '[parallel] 画面確認の URL: http://host.docker.internal:15175' || die "画面確認の URL が無い: $OUT"
    printf '%s\n' "$OUT" | grep -qF 'http://host.docker.internal:18082' || die "backend の URL が無い: $OUT"
    awk '/CREATE DATABASE/ { d = 1 } /kp-ui-2-backend/ && d { b = 1 } /kp-ui-2-frontend/ && b { ok = 1 } END { exit !ok }' "$FAKE_DOCKER_LOG" \
        || die "DB を作る・backend・frontend の順でない: $(cat "$FAKE_DOCKER_LOG")"
    # 起動したあとも枠を持ち続け、持ち主は --session のセッションになる
    [ "$(owner_get 2 kind)" = ui ] || die "枠2の種類が ui でない: $(cat "$STATE/slots/2/owner.json")"
    [ "$(owner_get 2 folder_key)" = "$KW" ] || die "枠2の持ち主が worktree でない"
    [ "$(owner_get 2 session_id)" = s-wt ] || die "--session の値が枠の持ち主に渡っていない: $(cat "$STATE/slots/2/owner.json")"
    [ -f "$FAKE_CONTAINERS/kp-ui-2-backend" ] && [ -f "$FAKE_CONTAINERS/kp-ui-2-frontend" ] || die "コンテナを残していない"
    if grep -q "^$MAIN|" "$FAKE_DOCKER_LOG"; then
        die "本体フォルダで docker を呼んだ: $(cat "$FAKE_DOCKER_LOG")"
    fi
}

t_store_volume_chown() {
    ui "$WT_DIR" start
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    grep -qxF "$WT|compose -p keirekipro -f compose.yaml run --rm --no-deps -T -u root --label keirekipro.slot=1 -v kp-pnpm-store-1:/pnpm-store --entrypoint chown frontend node:node /pnpm-store" "$FAKE_DOCKER_LOG" \
        || die "run-check.sh の準備の関数でストアのボリュームの持ち主を変えていない: $(cat "$FAKE_DOCKER_LOG")"
    [ -e "$FAKE_VOLUMES/kp-pnpm-store-1" ] || die "ストアのボリュームを作っていない"
}

t_db_exists() {
    export FAKE_DB_EXISTS=1
    ui "$WT_DIR" start
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    if grep -q 'CREATE DATABASE' "$FAKE_DOCKER_LOG"; then
        die "DB があるのに作ろうとした: $(cat "$FAKE_DOCKER_LOG")"
    fi
}

t_shared_services_up() {
    rm -f "$FAKE_SERVICES/redis" "$FAKE_SERVICES/localstack"
    ui "$WT_DIR" start
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    grep -qxF "$WT|compose -p keirekipro --project-directory $MAIN -f $MAIN/compose.yaml up -d redis localstack" "$FAKE_DOCKER_LOG" \
        || die "止まっている共有のサービスだけを本体フォルダで起こしていない: $(grep ' up ' "$FAKE_DOCKER_LOG")"
    # 起こせなければ69で、枠を取らずコンテナを作らない
    reset_state
    rm -f "$FAKE_SERVICES/db"
    export FAKE_UP_RC=1
    ui "$WT_DIR" start
    [ "$RC" = 69 ] || die "起こせないのに 期待 69 / 実際 $RC: $OUT"
    case "$OUT" in *"[parallel] 検査できない: "*db*) ;; *) die "理由の文が無い: $OUT" ;; esac
    [ -z "$(run_lines)" ] || die "共有のサービスを起こせないのにコンテナを作った"
    [ ! -d "$STATE/slots/1" ] || die "枠を取った"
}

t_leftover_removed() {
    slots 2
    # 前の画面確認で worktree が取った枠1と、そのとき残ったコンテナ
    put_owner 1 "$WT" "$KW" ui "$(now)" s-old
    put_container kp-ui-1-backend keirekipro.slot=1 "keirekipro.folder=$KW" keirekipro.kind=ui
    put_container kp-ui-1-frontend keirekipro.slot=1 "keirekipro.folder=$KW" keirekipro.kind=ui
    # ほかの作業フォルダの画面確認
    put_owner 2 "$MAIN" "$KM" ui "$(now)" s-main
    put_session s-main "$MAIN" "$KM"
    put_container kp-ui-2-backend keirekipro.slot=2 "keirekipro.folder=$KM" keirekipro.kind=ui
    ui "$WT_DIR" start --session s-wt
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    grep -qE "\|rm -f (kp-ui-1-backend kp-ui-1-frontend|kp-ui-1-frontend kp-ui-1-backend)$" "$FAKE_DOCKER_LOG" \
        || die "前の画面確認のコンテナを消していない: $(cat "$FAKE_DOCKER_LOG")"
    awk '/\|rm -f / { r = 1 } / run -d / && r { ok = 1 } / run -d / && !r { bad = 1 } END { exit !(ok && !bad) }' "$FAKE_DOCKER_LOG" \
        || die "消す前に起動した: $(cat "$FAKE_DOCKER_LOG")"
    grep -q -- '--name kp-ui-1-backend' "$FAKE_DOCKER_LOG" || die "同じ枠1を取り直していない: $(run_lines)"
    [ -f "$FAKE_CONTAINERS/kp-ui-2-backend" ] || die "ほかの作業フォルダの開発サーバを消した"
    [ "$(owner_get 2 folder_key)" = "$KM" ] || die "ほかの作業フォルダの枠を書き換えた"
}

# =====================================================================
# ほかのセッションの開発サーバを止めない(要件1.5)
# =====================================================================
t_stop_own_only() {
    slots 3
    put_owner 1 "$WT" "$KW" ui "$(now)" s-wt
    put_owner 2 "$MAIN" "$KM" ui "$(now)" s-main
    put_owner 3 "$WT" "$KW" check "$(now)" s-wt
    put_container kp-ui-1-backend keirekipro.slot=1 "keirekipro.folder=$KW" keirekipro.kind=ui
    put_container kp-ui-1-frontend keirekipro.slot=1 "keirekipro.folder=$KW" keirekipro.kind=ui
    put_container kp-ui-2-backend keirekipro.slot=2 "keirekipro.folder=$KM" keirekipro.kind=ui
    put_container kp-ui-2-frontend keirekipro.slot=2 "keirekipro.folder=$KM" keirekipro.kind=ui
    # 同じ作業フォルダの品質チェックのコンテナ(kind のラベルが無い)
    put_container keirekipro-frontend-run-1 keirekipro.slot=3 "keirekipro.folder=$KW"
    ui_direct "$WT_DIR/backend" stop
    [ "$RC" = 0 ] || die "終了コード $RC: $OUT"
    [ ! -f "$FAKE_CONTAINERS/kp-ui-1-backend" ] && [ ! -f "$FAKE_CONTAINERS/kp-ui-1-frontend" ] \
        || die "いまの作業フォルダの画面確認のコンテナを消していない: $(ls "$FAKE_CONTAINERS")"
    [ -f "$FAKE_CONTAINERS/kp-ui-2-backend" ] && [ -f "$FAKE_CONTAINERS/kp-ui-2-frontend" ] \
        || die "ほかの作業フォルダの開発サーバを消した"
    [ -f "$FAKE_CONTAINERS/keirekipro-frontend-run-1" ] || die "品質チェックのコンテナを消した"
    grep -qxF "$WT|ps -aq --filter label=keirekipro.folder=$KW --filter label=keirekipro.kind=ui" "$FAKE_DOCKER_LOG" \
        || die "いまの作業フォルダのラベルで探していない: $(cat "$FAKE_DOCKER_LOG")"
    [ ! -d "$STATE/slots/1" ] || die "ui の枠を返していない"
    [ -d "$STATE/slots/2" ] || die "ほかの作業フォルダの枠を返した"
    [ -d "$STATE/slots/3" ] || die "品質チェックの枠を返した"
    # 何も動いていなくても0で終わる
    ui_direct "$WT_DIR" stop
    [ "$RC" = 0 ] || die "2回目: 終了コード $RC: $OUT"
}

# =====================================================================
# 検査できないときは合格にしない(要件2.4)
# =====================================================================
t_health_limit() {
    local n
    slots 2
    put_owner 2 "$MAIN" "$KM" ui "$(now)" s-main
    put_session s-main "$MAIN" "$KM"
    put_container kp-ui-2-backend keirekipro.slot=2 "keirekipro.folder=$KM" keirekipro.kind=ui
    rm -f "$FAKE_CURL_OK"
    export KP_UI_BACKEND_TRIES=3 KP_UI_BACKEND_INTERVAL_SECONDS=0
    ui "$WT_DIR" start
    [ "$RC" = 69 ] || die "期待 69 / 実際 $RC: $OUT"
    n=$(grep -c 'actuator/health' "$FAKE_CURL_LOG")
    [ "$n" = 3 ] || die "健康の確かめの回数が上限どおりでない: $n"
    grep -qxF "$WT|logs --tail 50 kp-ui-1-backend" "$FAKE_DOCKER_LOG" || die "backend のログの末尾を出していない: $(cat "$FAKE_DOCKER_LOG")"
    grep -qxF "$WT|logs --tail 50 kp-ui-1-frontend" "$FAKE_DOCKER_LOG" || die "frontend のログの末尾を出していない"
    case "$OUT" in *"fake log: kp-ui-1-backend"*"[parallel] 検査できない: "*) ;; *) die "ログと理由の文が無い: $OUT" ;; esac
    case "$OUT" in *"画面確認の URL"*) die "起動しなかったのに URL を出した: $OUT" ;; esac
    [ ! -f "$FAKE_CONTAINERS/kp-ui-1-backend" ] && [ ! -f "$FAKE_CONTAINERS/kp-ui-1-frontend" ] \
        || die "自分のコンテナを消していない: $(ls "$FAKE_CONTAINERS")"
    [ -f "$FAKE_CONTAINERS/kp-ui-2-backend" ] || die "ほかの作業フォルダの開発サーバを消した"
    [ ! -d "$STATE/slots/1" ] || die "枠を返していない"
    [ -d "$STATE/slots/2" ] || die "ほかの作業フォルダの枠を返した"
    # frontend に TCP でつながらないときも同じ
    reset_state
    rm -f "$FAKE_TCP_OK"
    export KP_UI_FRONTEND_TRIES=2 KP_UI_FRONTEND_INTERVAL_SECONDS=0
    ui "$WT_DIR" start
    [ "$RC" = 69 ] || die "frontend: 期待 69 / 実際 $RC: $OUT"
    [ "$(grep -c . "$FAKE_TCP_LOG")" = 2 ] || die "TCP の確かめの回数が上限どおりでない: $(cat "$FAKE_TCP_LOG")"
    grep -qxF "$WT|logs --tail 50 kp-ui-1-frontend" "$FAKE_DOCKER_LOG" || die "frontend: ログの末尾を出していない"
    [ -z "$(ls "$FAKE_CONTAINERS")" ] || die "frontend: 自分のコンテナを消していない: $(ls "$FAKE_CONTAINERS")"
    [ ! -d "$STATE/slots/1" ] || die "frontend: 枠を返していない"
}

t_run_fail() {
    export FAKE_RUN_RC_frontend=1
    ui "$WT_DIR" start
    [ "$RC" = 69 ] || die "期待 69 / 実際 $RC: $OUT"
    case "$OUT" in *"[parallel] 検査できない: "*) ;; *) die "理由の文が無い: $OUT" ;; esac
    [ ! -f "$FAKE_CONTAINERS/kp-ui-1-backend" ] || die "起動した backend を消していない"
    [ ! -d "$STATE/slots/1" ] || die "枠を返していない"
    [ ! -s "$FAKE_CURL_LOG" ] || die "起動しなかったのに健康を確かめた"
    # DB を確かめられないときも、コンテナを作らずに69
    reset_state
    export FAKE_PSQL_RC=1
    ui "$WT_DIR" start
    [ "$RC" = 69 ] || die "DB: 期待 69 / 実際 $RC: $OUT"
    case "$OUT" in *"[parallel] 検査できない: "*"fake: psql に失敗した"*) ;; *) die "DB: 理由の文が無い: $OUT" ;; esac
    [ -z "$(run_lines)" ] || die "DB を確かめられないのにコンテナを作った"
    [ ! -d "$STATE/slots/1" ] || die "DB: 枠を返していない"
}

# =====================================================================
# 待つ、待ちを示す、待ちの上限で合格にしない(要件3.2・3.3・3.5)
# =====================================================================
t_full_no_wait() {
    local want
    put_issue 481 "$MAIN" feat/main-ui
    put_owner 1 "$MAIN" "$KM" ui "$(($(now) - 90))" s-main
    put_session s-main "$MAIN" "$KM"
    put_container kp-ui-1-backend keirekipro.slot=1 "keirekipro.folder=$KM" keirekipro.kind=ui
    ui_direct "$WT_DIR" start --session s-wt
    [ "$RC" = 10 ] || die "期待 10 / 実際 $RC: $OUT"
    want="[parallel] 順番待ち: 設定の数 1 の枠を、#481($MAIN、ui、1分前から)が使っている"
    [ "$OUT" = "$want" ] || die "持ち主の一覧が違う: '$OUT' / 期待 '$want'"
    [ -z "$(run_lines)" ] || die "コンテナを作った"
    if grep -q 'CREATE DATABASE\|rm -f' "$FAKE_DOCKER_LOG"; then
        die "枠を取れないのに DB やコンテナを変えた: $(cat "$FAKE_DOCKER_LOG")"
    fi
    [ -f "$FAKE_CONTAINERS/kp-ui-1-backend" ] || die "ほかのセッションの開発サーバを消した"
    [ "$(owner_get 1 folder_key)" = "$KM" ] || die "ほかの枠を書き換えた"
}

t_wait_limit() {
    local t0 t1
    put_issue 481 "$MAIN" feat/main-ui
    put_owner 1 "$MAIN" "$KM" check "$(now)" s-main
    export KP_WAIT_INTERVAL_SECONDS=1 KP_WAIT_LIMIT_SECONDS=2
    t0=$(now)
    ui_direct "$WT_DIR" start --wait
    t1=$(now)
    [ "$RC" = 75 ] || die "期待 75 / 実際 $RC: $OUT"
    [ $((t1 - t0)) -ge 2 ] || die "上限より早く終わった: $((t1 - t0))秒"
    [ "$(printf '%s\n' "$OUT" | grep -c '^\[parallel\] 順番待ち: 設定の数 1 の枠を、#481(')" -ge 2 ] \
        || die "最初と上限のときに待っていた枠の持ち主を出していない: $OUT"
    [ -z "$(run_lines)" ] || die "コンテナを作った"
    case "$OUT" in *"画面確認の URL"*) die "URL を出した" ;; esac
}

# =====================================================================
# frontend の TCP の確かめ
# =====================================================================
t_tcp_check() {
    local pid port i out
    # 本物の小さな TCP の待ち受け(空いているポートを OS に選ばせ、番号をファイルに書く)
    perl -MIO::Socket::INET -e '
        my $s = IO::Socket::INET->new(Listen => 5, LocalAddr => "127.0.0.1", LocalPort => 0, Proto => "tcp", ReuseAddr => 1) or die "listen: $!";
        open my $f, ">", "$ARGV[0].tmp" or die; print $f $s->sockport; close $f;
        rename "$ARGV[0].tmp", $ARGV[0];
        while (my $c = $s->accept) { close $c }
    ' "$WORK/listen.port" &
    pid=$!
    for i in $(seq 1 100); do
        [ -s "$WORK/listen.port" ] && break
        sleep 0.1
    done
    port=$(cat "$WORK/listen.port" 2>/dev/null)
    [ -n "$port" ] || { kill "$pid" 2>/dev/null; die "待ち受けが始まらない"; }
    # shellcheck disable=SC2016 # 子の bash が展開する
    out=$(bash -c '. "$1" || exit 97; _kp_ui_tcp_open "$2"' _ "$UI" "$port" 2>&1)
    i=$?
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    [ "$i" = 0 ] || die "待ち受けがあるのに偽になった: $i $out"
    # shellcheck disable=SC2016
    out=$(bash -c '. "$1" || exit 97; _kp_ui_tcp_open "$2"' _ "$UI" "$port" 2>&1)
    i=$?
    [ "$i" = 1 ] || die "待ち受けが無いのに真になった: $i $out"
}

t_usage() {
    ui_direct "$WT_DIR" restart
    [ "$RC" = 69 ] || die "期待 69 / 実際 $RC: $OUT"
    case "$OUT" in *"[parallel] "*"ui.sh start"*) ;; *) die "使い方の文が無い: $OUT" ;; esac
    [ ! -s "$FAKE_DOCKER_LOG" ] || die "docker を呼んだ"
}

echo "--- 画面にそのセッションの変更が出る(要件2.2)"
run_test "start で、枠 k のポートと鍵の DB と host.docker.internal の VITE_API_URL と SPRING_APPLICATION_JSON が docker に渡る" t_start_args
run_test "frontend の準備は run-check.sh の関数で、枠のラベルを付けた root のコンテナでストアのボリュームの持ち主を変える" t_store_volume_chown
run_test "鍵の DB があれば作らない" t_db_exists
run_test "止まっている共有のサービスだけを本体フォルダで起こし、起こせなければ終了コード69で枠を取らない" t_shared_services_up
run_test "前の画面確認のコンテナが残っていれば消してから、同じ枠で起動する" t_leftover_removed

echo "--- ほかのセッションの開発サーバを止めない(要件1.5)"
run_test "stop は、いまの作業フォルダのラベルの ui コンテナだけを消す" t_stop_own_only

echo "--- 検査できないときは合格にしない(要件2.4)"
run_test "健康の確かめが上限に達すると終了コード69で自分のコンテナを消し枠を返す" t_health_limit
run_test "コンテナを起動できないか DB を確かめられなければ終了コード69で自分のコンテナを消し枠を返す" t_run_fail

echo "--- 待つ、待ちを示す、待ちの上限で合格にしない(要件3.2・3.3・3.5)"
run_test "枠が埋まっていると終了コード10" t_full_no_wait
run_test "待ちの上限で終了コード75" t_wait_limit

echo "--- frontend の TCP の確かめと使い方"
run_test "frontend の TCP の確かめは perl で、待ち受けがあれば真、無ければ偽になる" t_tcp_check
run_test "start と stop のどちらでもなければ終了コード69で使い方を出す" t_usage

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
