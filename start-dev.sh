#!/usr/bin/env bash
# ローカル動作確認用。
# backend / frontend を起動し、それぞれ応答を返すまで待機する。
# 確認URL: http://localhost:5173
# 停止: docker compose restart frontend backend

set -euo pipefail

export MSYS_NO_PATHCONV=1

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

# 起動プロセスの出力先(コンテナ内のパス)。
# 各コンテナのメインプロセスはbackendがjshell、frontendがnodeのため、
# exec で起動したプロセスの出力は docker compose logs には流れない。
# 起動失敗時の調査にはこれらのファイルを使う
BOOTRUN_LOG=/tmp/bootrun.log
VITE_LOG=/tmp/vite.log

# backendの待機上限。1周あたり約1.5秒(exec往復 + sleep 1)かかる。
# Gradleデーモンが停止した状態からHTTP 200になるまで実測85秒のため、余裕を持たせて約4分待つ
BACKEND_RETRY_MAX=150

# frontendの待機上限。1周あたり約1.3秒で、Viteが待ち受けを開始するまで数秒のため
# 60周(約80秒)で足りる
FRONTEND_RETRY_MAX=60

# 指定サービスのコンテナが起動していなければ終了する
require_container() {
    if [ -z "$(docker compose ps --status running -q "$1")" ]; then
        echo "[$1] container is not running. run: docker compose up -d"
        exit 1
    fi
}

# backendの /actuator/health のHTTPステータスを返す。到達不能なら 000
backend_health_status() {
    docker compose exec -T -w /home/spring/app backend sh -lc \
        "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/actuator/health || true" || true
}

# frontendの5173番が待ち受けていれば open、そうでなければ closed を返す。
# frontendコンテナにはcurlもwgetも無いためnodeを使う。
# HTTPリクエストではなくTCP接続で判定するのは、Viteが最初のHTTPリクエストで
# 依存の事前バンドルを行い、応答までに実測1分以上かかることがあるため
frontend_listening() {
    docker compose exec -T frontend node -e \
        'const s=require("net").connect(5173,"127.0.0.1");s.setTimeout(2000);const done=r=>{console.log(r);s.destroy()};s.on("connect",()=>done("open"));s.on("error",()=>done("closed"));s.on("timeout",()=>done("closed"))' || true
}

require_container backend
require_container frontend

if [ "$(backend_health_status)" = "200" ]; then
    echo "[backend] already running: /actuator/health HTTP 200"
else
    # 前回の失敗で残った bootRun を停止する。残したまま起動すると8080番ポートが衝突する。
    # パターンを [X] で囲むのは、pkill を実行するシェル自身のコマンドラインにマッチさせないため
    echo "[backend] cleaning up leftover bootRun..."
    docker compose exec -T backend sh -lc \
        "pkill -f '[G]radleWrapperMain' || true; pkill -f '[K]eirekiProApplication' || true" || true
    sleep 2

    echo "[backend] starting..."
    docker compose exec -d -w /home/spring/app backend sh -lc \
        "./gradlew bootRun --args=--spring.profiles.active=dev --console=plain > ${BOOTRUN_LOG} 2>&1"

    echo "[backend] waiting for health..."
    for i in $(seq 1 "$BACKEND_RETRY_MAX"); do
        if [ "$(backend_health_status)" = "200" ]; then
            echo "[backend] ready: /actuator/health HTTP 200"
            break
        fi

        if [ "$i" -eq "$BACKEND_RETRY_MAX" ]; then
            echo "[backend] failed to start"
            docker compose exec -T backend sh -lc "tail -n 120 ${BOOTRUN_LOG}" || true
            exit 1
        fi

        sleep 1
    done
fi

if [ "$(frontend_listening)" = "open" ]; then
    echo "[frontend] already running: http://localhost:5173"
else
    # 前回の失敗で残ったViteを停止する。残したまま起動すると5173番が埋まっていて5174番にずれる。
    # frontendコンテナには ps も pkill も無いため /proc を直接走査する。
    # パターンを [X] で囲むのは、この処理を実行するシェル自身にマッチさせないため。
    # ViteのプロセスはTERMで終了しないことがあるため、TERMの後にKILLを送る
    echo "[frontend] cleaning up leftover dev server..."
    docker compose exec -T frontend sh -lc '
        scan_kill() {
            for d in /proc/[0-9]*; do
                [ -r "$d/cmdline" ] || continue
                case "$(tr "\0" " " < "$d/cmdline")" in
                    *[v]ite*|*[p]npm*) kill "$1" "${d#/proc/}" 2>/dev/null || true ;;
                esac
            done
        }
        scan_kill -TERM
        sleep 3
        scan_kill -KILL
    ' || true
    sleep 1

    echo "[frontend] starting..."
    docker compose exec -d -u node -w /home/node/app frontend sh -lc \
        "pnpm run dev > ${VITE_LOG} 2>&1"

    echo "[frontend] waiting for dev server..."
    for i in $(seq 1 "$FRONTEND_RETRY_MAX"); do
        if [ "$(frontend_listening)" = "open" ]; then
            echo "[frontend] ready: http://localhost:5173"
            break
        fi

        if [ "$i" -eq "$FRONTEND_RETRY_MAX" ]; then
            echo "[frontend] failed to start"
            docker compose exec -T frontend sh -lc "tail -n 120 ${VITE_LOG}" || true
            exit 1
        fi

        sleep 1
    done
fi
