#!/usr/bin/env bash
# ローカル動作確認用。
# backend 起動後、/actuator/health が HTTP 200 になるまで待機する。
# 確認URL: http://localhost:5173
# 停止: docker compose restart frontend backend

set -euo pipefail

export MSYS_NO_PATHCONV=1

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "[backend] starting..."
docker compose exec -d -w /home/spring/app backend ./gradlew bootRun --args=--spring.profiles.active=dev

echo "[backend] waiting for health..."
for i in {1..60}; do
    status="$(
        docker compose exec -T -w /home/spring/app backend sh -lc \
            "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/actuator/health || true"
    )"

    if [ "$status" = "200" ]; then
        echo "[backend] ready: /actuator/health HTTP 200"
        break
    fi

    if [ "$i" -eq 60 ]; then
        echo "[backend] failed to start"
        docker compose logs --tail 120 backend
        exit 1
    fi

    sleep 1
done

echo "[frontend] starting..."
docker compose exec -d -u node -w /home/node/app frontend pnpm run dev

echo "[frontend] ready: http://localhost:5173"
