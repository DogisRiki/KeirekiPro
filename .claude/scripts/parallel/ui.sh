#!/bin/bash
# =====================================================================
# 画面確認の開発サーバを1回きりのコンテナで動かすスクリプト(ui.sh)
#
# 使い方: bash .claude/scripts/parallel/ui.sh start [--wait] [--session <ID>]
#         bash .claude/scripts/parallel/ui.sh stop [--session <ID>]
# start は、種類 ui の枠 k を取り、いまの作業フォルダを読み込んだ backend と frontend の
# 開発サーバを1回きりのコンテナ(docker compose -p keirekipro run -d)で、枠ごとのポート
# (backend 18080+k、frontend 15173+k)で起動する。DB は作業フォルダごとの kp_<鍵> を使う。
# あわせて、所有者が作業PCのブラウザで開く frontend を、ポート 25173+k で起動する。この frontend は
# backend を localhost で呼ぶので、hosts ファイルの host.docker.internal の向き先に左右されない。
# 起動したら、画面確認の URL(http://host.docker.internal:<15173+k>)と backend の URL と、
# 所有者が開く URL(http://localhost:<25173+k>)を出す。
# 枠は stop まで持ち続ける。stop は、いまの作業フォルダの画面確認のコンテナだけを消し、枠を返す。
# --session の値は、セッションのID(KP_SESSION_ID)として lib.sh に渡す。
#
# 終了コード: 0、10(枠が埋まっていて待たなかった)、
#             69(起動しなかった、健康の確かめが上限に達した)、75(待ちの上限に達した)。
#
# 待ちの上限と取り直しの間隔(秒)は run-check.sh と同じく KP_WAIT_LIMIT_SECONDS(既定1800)と
# KP_WAIT_INTERVAL_SECONDS(既定5)で変えられる。健康の確かめの回数と間隔(秒)は
# KP_UI_BACKEND_TRIES(既定150)・KP_UI_BACKEND_INTERVAL_SECONDS(既定2)、
# KP_UI_FRONTEND_TRIES(既定60)・KP_UI_FRONTEND_INTERVAL_SECONDS(既定1)で変えられる。
#
# 読み込んだ(source した)だけのときは本体の処理を動かさない。
# 前提: bash・perl(JSON::PP、IO::Socket::INET)・git・docker(Compose 2.24.0 以上)・curl
#       (Windows では Git for Windows に同梱)。jq には依存しない。
# =====================================================================

KP_UI_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# frontend の準備(kp_frontend_prepare)と、順番待ちの知らせ・秒の読み方を run-check.sh と同じにするため読み込む。
# run-check.sh は lib.sh も読み込む
# shellcheck source=.claude/scripts/parallel/run-check.sh
. "$KP_UI_DIR/run-check.sh"

# 本体のプロジェクトの、画面確認が使う共有のサービス
KP_UI_SERVICES="db redis localstack dind"

_kp_ui_usage() {
    printf '[parallel] 使い方: ui.sh start [--wait] [--session <ID>] / ui.sh stop [--session <ID>]\n'
    exit 69
}

# 回数の環境変数を読む(1以上の整数でなければ既定の値)
_kp_ui_count() { # <値> <既定の値>
    _kp_rc_seconds "$1" "$2"
}

# 間隔の環境変数を読む(0以上の整数でなければ既定の値)
_kp_ui_interval() { # <値> <既定の値>
    case "$1" in
        '' | *[!0-9]*) printf '%s\n' "$2" ;;
        *) printf '%s\n' "$((10#$1))" ;;
    esac
}

# localhost:<ポート> に TCP でつながれば終了コード0
_kp_ui_tcp_open() { # <ポート>
    perl -MIO::Socket::INET -e '
        my $s = IO::Socket::INET->new(PeerAddr => "localhost", PeerPort => $ARGV[0], Proto => "tcp", Timeout => 2);
        exit($s ? 0 : 1);
    ' -- "$1"
}

# いまの作業フォルダの画面確認のコンテナの ID を出す
_kp_ui_containers() { # <鍵>
    local ids
    ids=$(docker ps -aq --filter "label=keirekipro.folder=$1" --filter label=keirekipro.kind=ui) || return 1
    printf '%s' "$ids" | tr -d '\r'
}

# いまの作業フォルダの画面確認のコンテナを消す。消せなければ終了コード1
_kp_ui_remove_containers() { # <鍵>
    local ids
    ids=$(_kp_ui_containers "$1") || return 1
    [ -n "$ids" ] || return 0
    # shellcheck disable=SC2086 # ID ごとに分ける
    docker rm -f $ids >/dev/null
}

# いまの作業フォルダが持つ ui の枠の番号を出す
_kp_ui_my_slots() { # <鍵>
    local state d k
    state=$(kp_state_dir) || return 1
    for d in "$state"/slots/*/; do
        [ -d "$d" ] || continue
        k=$(basename "$d")
        case "$k" in '' | *[!0-9]*) continue ;; esac
        [ "$(kp_json_get "$d/owner.json" kind 2>/dev/null)" = ui ] || continue
        [ "$(kp_json_get "$d/owner.json" folder_key 2>/dev/null)" = "$1" ] || continue
        printf '%s\n' "$k"
    done
}

# 起動の途中で止まったときの片付け: 自分のコンテナを消し、枠を返す
_kp_ui_cleanup() {
    if [ -n "${KP_UI_SLOT:-}" ]; then
        _kp_ui_remove_containers "$KP_UI_KEY" 2>/dev/null
        (kp_slot_release "$KP_UI_SLOT") >/dev/null 2>&1
        KP_UI_SLOT=
    fi
}

_kp_ui_fail69() {
    _kp_ui_cleanup
    printf '[parallel] 検査できない: %s\n' "$*"
    exit 69
}

# 健康の確かめが上限に達したとき: ログの末尾を出し、片付けて69で終わる
_kp_ui_health_fail() { # <理由>
    local name
    for name in "kp-ui-$KP_UI_SLOT-backend" "kp-ui-$KP_UI_SLOT-frontend" "kp-ui-$KP_UI_SLOT-frontend-owner"; do
        printf '[parallel] %s のログの末尾:\n' "$name"
        docker logs --tail 50 "$name" 2>&1
    done
    _kp_ui_fail69 "$1"
}

kp_ui_start() {
    local wait=0 folder key n main out rc s stopped limit interval waited_from told k
    local be_port fe_port own_port db exists json tries pause i
    while [ $# -gt 0 ]; do
        case "$1" in
            --wait) wait=1; shift ;;
            --session)
                [ -n "${2:-}" ] || _kp_ui_usage
                export KP_SESSION_ID="$2"
                shift 2
                ;;
            *) _kp_ui_usage ;;
        esac
    done

    folder=$(kp_folder 2>&1) || _kp_ui_fail69 "$folder"
    cd "$folder" || _kp_ui_fail69 "作業フォルダ $folder に移れない"
    key=$(kp_folder_key 2>&1) || _kp_ui_fail69 "$key"
    n=$(kp_slots 2>&1) || _kp_ui_fail69 "$n"
    KP_UI_KEY=$key

    # 1. 本体のプロジェクトの共有のサービスが動いているかを確かめ、止まっているものを本体フォルダで起こす
    stopped=
    for s in $KP_UI_SERVICES; do
        out=$(docker compose -p keirekipro ps --status running -q "$s" 2>&1) \
            || _kp_ui_fail69 "$s が動いているかを確かめられない: $out"
        [ -n "$out" ] || stopped="${stopped:+$stopped }$s"
    done
    if [ -n "$stopped" ]; then
        main=$(kp_main_folder 2>&1) || _kp_ui_fail69 "$main"
        # shellcheck disable=SC2086 # サービスごとに分ける
        docker compose -p keirekipro --project-directory "$main" -f "$main/compose.yaml" up -d $stopped \
            || _kp_ui_fail69 "本体のプロジェクトの $stopped を起こせない"
    fi

    # 2. 種類 ui の枠を取る(取れないときの扱いは run-check.sh と同じ)
    limit=$(_kp_rc_seconds "${KP_WAIT_LIMIT_SECONDS:-}" 1800)
    interval=$(_kp_rc_seconds "${KP_WAIT_INTERVAL_SECONDS:-}" 5)
    waited_from=$(date +%s)
    told=0
    while :; do
        out=$(kp_slot_acquire ui "ui start" 2>&1)
        rc=$?
        if [ "$rc" = 0 ]; then
            k=${out##*$'\n'}
            case "$k" in
                '' | *[!0-9]*) _kp_ui_fail69 "枠の番号を読めない: $out" ;;
            esac
            break
        fi
        [ "$rc" = 69 ] && _kp_ui_fail69 "$out"
        if [ "$told" = 0 ]; then
            _kp_rc_print_holders "$n"
            told=1
        fi
        [ "$wait" = 1 ] || exit 10
        if [ $(($(date +%s) - waited_from)) -ge "$limit" ]; then
            printf '[parallel] 待ちの上限(%s秒)に達した。待っていた枠:\n' "$limit"
            _kp_rc_print_holders "$n"
            exit 75
        fi
        sleep "$interval"
    done
    KP_UI_SLOT=$k
    # 起動を終える前に止められたら、自分のコンテナを消して枠を返す
    trap '_kp_ui_cleanup' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    be_port=$((18080 + k))
    fe_port=$((15173 + k))
    own_port=$((25173 + k))

    # 3. 前の画面確認のコンテナが残っていれば消す
    out=$(_kp_ui_remove_containers "$key" 2>&1) || _kp_ui_fail69 "前の画面確認のコンテナを消せない: $out"

    # 4. 作業フォルダごとの DB が無ければ作る
    db="kp_$key"
    exists=$(docker compose -p keirekipro exec -T db psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db'" 2>&1) \
        || _kp_ui_fail69 "DB $db があるかを確かめられない: $exists"
    exists=$(printf '%s' "$exists" | tr -d '\r\n[:space:]')
    if [ "$exists" != 1 ]; then
        out=$(docker compose -p keirekipro exec -T db psql -U postgres -c "CREATE DATABASE $db" 2>&1) \
            || _kp_ui_fail69 "DB $db を作れない: $out"
    fi

    # 5. backend を起動する(DB の接続先と、画面の URL と CORS の許可だけを上書きする)。
    #    CORS は、画面確認の frontend と所有者が開く frontend の両方を許す
    json='{"spring":{"datasource":{"url":"jdbc:postgresql://db:5432/'"$db"'"}},"frontend-base-url":"http://host.docker.internal:'"$fe_port"'","cors":{"allowed-origins":"http://host.docker.internal:'"$fe_port"',http://localhost:'"$own_port"'"}}'
    out=$(docker compose -p keirekipro -f compose.yaml run -d --no-deps --name "kp-ui-$k-backend" -p "$be_port:8080" \
        --label "keirekipro.slot=$k" --label "keirekipro.folder=$key" --label keirekipro.kind=ui \
        -v "kp-gradle-home-$k:/root/.gradle" -v "kp-gradle-project-$key:/home/spring/app/.gradle" \
        -e "SPRING_APPLICATION_JSON=$json" \
        backend ./gradlew bootRun --args=--spring.profiles.active=dev 2>&1) \
        || _kp_ui_fail69 "backend の開発サーバを起動できない: $out"

    # 6. frontend を起動する(pnpm のストアと node_modules の準備は run-check.sh と同じ)。
    #    所有者が開く frontend が node_modules/.vite に別のボリュームを重ねるので、その場所を
    #    先に node の持ち物で作っておく(無いと docker が root の持ち物で作り、この frontend が書けなくなる)
    kp_frontend_prepare "$k" || _kp_ui_fail69 "$KP_FRONTEND_ERROR"
    out=$(docker compose -p keirekipro -f compose.yaml run -d --no-deps --name "kp-ui-$k-frontend" -p "$fe_port:5173" \
        --label "keirekipro.slot=$k" --label "keirekipro.folder=$key" --label keirekipro.kind=ui \
        "${KP_FRONTEND_ARGS[@]}" -e "VITE_API_URL=http://host.docker.internal:$be_port/api/" \
        frontend sh -c "$KP_FRONTEND_PRE; mkdir -p node_modules/.vite; exec pnpm run dev" 2>&1) \
        || _kp_ui_fail69 "frontend の開発サーバを起動できない: $out"

    # 7. 健康の確かめ: backend は actuator/health が200を返すまで、frontend は TCP でつながるまで待つ
    tries=$(_kp_ui_count "${KP_UI_BACKEND_TRIES:-}" 150)
    pause=$(_kp_ui_interval "${KP_UI_BACKEND_INTERVAL_SECONDS:-}" 2)
    for ((i = 1; ; i++)); do
        curl -fsS "http://localhost:$be_port/actuator/health" --max-time 5 >/dev/null 2>&1 && break
        [ "$i" -lt "$tries" ] || _kp_ui_health_fail "backend の健康の確かめが上限($tries回)に達した"
        sleep "$pause"
    done
    tries=$(_kp_ui_count "${KP_UI_FRONTEND_TRIES:-}" 60)
    pause=$(_kp_ui_interval "${KP_UI_FRONTEND_INTERVAL_SECONDS:-}" 1)
    for ((i = 1; ; i++)); do
        _kp_ui_tcp_open "$fe_port" && break
        [ "$i" -lt "$tries" ] || _kp_ui_health_fail "frontend に TCP でつながるかの確かめが上限($tries回)に達した"
        sleep "$pause"
    done

    # 8. 所有者が開く frontend を起動する。画面確認の frontend が node_modules の準備を終えてから
    #    起動するので、pnpm install は重ならない。Vite の作業用の置き場(node_modules/.vite)は、
    #    2つの開発サーバが取り合わないよう、枠のボリューム kp-vite-owner-<k> を重ねて分ける。
    #    backend を localhost で呼ぶので、作業PCのブラウザから開ける
    kp_node_volume "kp-vite-owner-$k" "$k" "$folder" /vite-owner || _kp_ui_fail69 "$KP_FRONTEND_ERROR"
    out=$(docker compose -p keirekipro -f compose.yaml run -d --no-deps --name "kp-ui-$k-frontend-owner" -p "$own_port:5173" \
        --label "keirekipro.slot=$k" --label "keirekipro.folder=$key" --label keirekipro.kind=ui \
        "${KP_FRONTEND_ARGS[@]}" -v "kp-vite-owner-$k:/home/node/app/node_modules/.vite" \
        -e "VITE_API_URL=http://localhost:$be_port/api/" \
        frontend sh -c "$KP_FRONTEND_PRE; exec pnpm run dev" 2>&1) \
        || _kp_ui_fail69 "所有者が開く frontend の開発サーバを起動できない: $out"
    for ((i = 1; ; i++)); do
        _kp_ui_tcp_open "$own_port" && break
        [ "$i" -lt "$tries" ] || _kp_ui_health_fail "所有者が開く frontend に TCP でつながるかの確かめが上限($tries回)に達した"
        sleep "$pause"
    done

    # 9. 起動を終えたので、枠は stop まで持ち続ける
    KP_UI_SLOT=
    trap - EXIT INT TERM HUP
    printf '[parallel] 画面確認の URL: http://host.docker.internal:%s\n' "$fe_port"
    printf '[parallel] backend の URL: http://host.docker.internal:%s\n' "$be_port"
    printf '[parallel] 所有者が開く URL: http://localhost:%s\n' "$own_port"
    exit 0
}

kp_ui_stop() {
    local folder key out k
    while [ $# -gt 0 ]; do
        case "$1" in
            --session)
                [ -n "${2:-}" ] || _kp_ui_usage
                export KP_SESSION_ID="$2"
                shift 2
                ;;
            *) _kp_ui_usage ;;
        esac
    done
    folder=$(kp_folder 2>&1) || _kp_ui_fail69 "$folder"
    cd "$folder" || _kp_ui_fail69 "作業フォルダ $folder に移れない"
    key=$(kp_folder_key 2>&1) || _kp_ui_fail69 "$key"
    # いまの作業フォルダのラベルの画面確認のコンテナだけを消す(ほかのセッションの開発サーバは止めない)
    out=$(_kp_ui_remove_containers "$key" 2>&1) || _kp_ui_fail69 "画面確認のコンテナを消せない: $out"
    for k in $(_kp_ui_my_slots "$key"); do
        (kp_slot_release "$k") >/dev/null 2>&1
    done
    printf '[parallel] 画面確認の開発サーバを止めた\n'
    exit 0
}

kp_ui_main() {
    set -u
    KP_UI_SLOT=
    KP_UI_KEY=
    local sub="${1:-}"
    shift || true
    case "$sub" in
        start) kp_ui_start "$@" ;;
        stop) kp_ui_stop "$@" ;;
        *) _kp_ui_usage ;;
    esac
}

# 読み込まれただけ(source)のときは本体の処理を動かさない
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    kp_ui_main "$@"
fi
