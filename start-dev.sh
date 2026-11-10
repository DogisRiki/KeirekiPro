#!/usr/bin/env bash
# ローカル動作確認用。
# 止まっているコンテナを起動し、backend / frontend を起動して、それぞれ応答を返すまで待機する。
# 確認URL: http://localhost:5173
# Go 版の backend: http://localhost:8081(Java 版から切り替えるまで、Java 版と並べて動かす)
# API の説明画面: http://localhost:8082(Go 版の仕様書 backend/api/openapi.yaml から作る)
# 停止: docker compose restart frontend backend
# Go 版の backend は、コンテナを起動すると動き出す。コードを変えたあとは docker compose restart backend-go で組み立て直して起動し直す

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

# backend-goの待機上限。1周あたり約1.5秒(exec往復 + sleep 1)かかる。
# モジュールと組み立てのキャッシュが空の状態から、部品の取り込みと組み立てで実測12秒、起動して受け口を開くまで1秒未満のため、
# 取り込みの通信が遅いときの余裕を持たせて120周(約3分)待つ
BACKEND_GO_RETRY_MAX=120

# frontendの待機上限。1周あたり約1.3秒で、Viteが待ち受けを開始するまで数秒のため
# 60周(約80秒)で足りる
FRONTEND_RETRY_MAX=60

# 開発サーバの起動に要るサービス。backendとbackend-goは db・redis・localstack につながらないと起動できない。
# api-docs は API の説明画面で、ほかのサービスにつながらずに起動する。
# dind と terraform は開発サーバに使わないため起動しない
REQUIRED_SERVICES="backend backend-go api-docs frontend db redis localstack"

# 起動していないサービスがあれば起動する。起動できなければ終了する
ensure_containers() {
    local stopped="" service
    for service in $REQUIRED_SERVICES; do
        if [ -z "$(docker compose ps --status running -q "$service")" ]; then
            stopped="$stopped $service"
        fi
    done
    [ -z "$stopped" ] && return 0

    echo "[containers] starting:${stopped}"
    # shellcheck disable=SC2086
    if ! docker compose up -d $stopped; then
        echo "[containers] failed to start:${stopped}"
        exit 1
    fi
}

# backendの /actuator/health のHTTPステータスを返す。到達不能なら 000
backend_health_status() {
    docker compose exec -T -w /home/spring/app backend sh -lc \
        "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/actuator/health || true" || true
}

# Go 版の backend の /healthz のHTTPステータスを返す。到達不能なら 000。
# コンテナの中の 8080 番を見る(ホストの 8081 番につないである)
backend_go_health_status() {
    docker compose exec -T backend-go sh -c \
        "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/healthz || true" || true
}

# frontendの5173番が待ち受けていれば open、そうでなければ closed を返す。
# frontendコンテナにはcurlもwgetも無いためnodeを使う。
# HTTPリクエストではなくTCP接続で判定するのは、Viteが最初のHTTPリクエストで
# 依存の事前バンドルを行い、応答までに実測1分以上かかることがあるため
frontend_listening() {
    docker compose exec -T frontend node -e \
        'const s=require("net").connect(5173,"127.0.0.1");s.setTimeout(2000);const done=r=>{console.log(r);s.destroy()};s.on("connect",()=>done("open"));s.on("error",()=>done("closed"));s.on("timeout",()=>done("closed"))' || true
}

ensure_containers

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

# Go 版の backend は、コンテナの主のプロセスが go run で動く(compose.yaml の command)。
# コンテナを起動すると組み立てて起動するので、ここでは /healthz が 200 を返すまで待つだけにする。
# 起動に失敗するとプログラムが終わり、コンテナも止まるので、止まったら待たずにログを出して終わる
if [ "$(backend_go_health_status)" = "200" ]; then
    echo "[backend-go] already running: /healthz HTTP 200"
else
    echo "[backend-go] waiting for health..."
    for i in $(seq 1 "$BACKEND_GO_RETRY_MAX"); do
        if [ "$(backend_go_health_status)" = "200" ]; then
            echo "[backend-go] ready: /healthz HTTP 200 (http://localhost:8081)"
            break
        fi

        if [ -z "$(docker compose ps --status running -q backend-go)" ] || [ "$i" -eq "$BACKEND_GO_RETRY_MAX" ]; then
            echo "[backend-go] failed to start"
            docker compose logs --no-color --tail 120 backend-go || true
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

    # 依存の入れ直しを開発サーバの起動の前に済ませる。node_modules がlockfileより古いと、
    # pnpm は pnpm run dev の中で入れ直しを始める(verifyDepsBeforeRun の既定 install)。
    # 入れ直しは1分を超えることがあり、待機の上限に数えられて起動の失敗と判定されるため、
    # ここで出力を見せながら終わるまで待つ。最新なら数秒で終わる
    echo "[frontend] installing dependencies..."
    if ! docker compose exec -T -u node -w /home/node/app frontend pnpm install --frozen-lockfile; then
        echo "[frontend] failed to install dependencies"
        exit 1
    fi

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
