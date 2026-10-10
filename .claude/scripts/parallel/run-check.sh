#!/bin/bash
# =====================================================================
# 品質チェックのコマンドを1回きりのコンテナで動かすスクリプト(run-check.sh)
#
# 使い方: bash .claude/scripts/parallel/run-check.sh [--wait] <領域> <コマンド>...
#   <領域>     frontend / backend / terraform
#   <コマンド> 品質チェックのコマンド(例 pnpm run lint、./gradlew check、terraform fmt -check -recursive)
# 枠を取ってから、いまの作業フォルダを読み込んだ1回きりのコンテナ(docker compose -p keirekipro run)で
# コマンドを動かし、終わったら枠を返す。コマンドの中身は書き換えない。
#
# 終了コード: コマンドの終了コード、10(枠が埋まっていて待たなかった)、
#             69(検査の環境を用意できなかった)、75(待ちの上限に達した)。
# 最後の品質チェック(frontend の pnpm run coverage、backend の ./gradlew check、
# terraform の checkov で始まるコマンド)が0で終わったときだけ、作業フォルダの
# .claude/.state/gate-run-<領域>.txt に UNIX 秒を書く。
#
# 待ちの上限と取り直しの間隔(秒)は、環境変数 KP_WAIT_LIMIT_SECONDS(既定1800)と
# KP_WAIT_INTERVAL_SECONDS(既定5)で変えられる。
#
# 読み込んだ(source した)だけのときは本体の処理を動かさず、frontend の準備の関数
# kp_frontend_prepare と、枠のボリュームを用意する関数 kp_node_volume だけを使えるようにする(ui.sh が使う)。
# 前提: bash・perl(JSON::PP)・git・docker(Compose 2.24.0 以上)。jq には依存しない。
# =====================================================================

KP_RUN_CHECK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=.claude/scripts/parallel/lib.sh
. "$KP_RUN_CHECK_DIR/lib.sh"

# コンテナの中のコマンドの前にすること(pnpm install、terraform init)が失敗したときの終了コード。
# コマンド自身の終了コード(69 を含む)と見分けるための値で、外に返すときは69に読み替える。
KP_PRE_FAIL_CODE=197

# 枠のボリュームを node の持ち物で用意する: kp_node_volume <ボリューム> <枠の番号> <作業フォルダ> <コンテナの中の場所>
# ボリュームが無ければ作り、同じ枠のラベルを付けた root の1回きりのコンテナで持ち主を node にする
# (イメージに無い場所のボリュームは root の持ち物になるため)。
# 失敗したら理由を KP_FRONTEND_ERROR に入れて終了コード1。
kp_node_volume() {
    local vol="$1" k="$2" folder="$3" dest="$4" err
    docker volume inspect "$vol" >/dev/null 2>&1 && return 0
    if ! err=$(docker volume create "$vol" 2>&1); then
        KP_FRONTEND_ERROR="ボリューム $vol を作れない: $err"
        return 1
    fi
    if ! (cd "$folder" && docker compose -p keirekipro -f compose.yaml run --rm --no-deps -T -u root \
        --label "keirekipro.slot=$k" -v "$vol:$dest" --entrypoint chown frontend node:node "$dest"); then
        # 持ち主を変えられなかったボリュームを残すと、次から作り直されないので消す
        docker volume rm "$vol" >/dev/null 2>&1
        KP_FRONTEND_ERROR="ボリューム $vol の持ち主を node にできない"
        return 1
    fi
    return 0
}

# frontend の準備: kp_frontend_prepare <枠の番号>
# いまの作業フォルダの最上位で呼ぶ。
# 1. 枠のボリューム kp-pnpm-store-<k> を kp_node_volume で用意する
# 2. コンテナに渡す引数を KP_FRONTEND_ARGS(配列)に、コンテナの中でコマンドの前にすること
#    (node_modules の印 .kp-lock-hash が lock と違えば pnpm install して印を書き直す。
#    install に失敗したら終了コード KP_PRE_FAIL_CODE)を KP_FRONTEND_PRE に入れる
# 失敗したら理由を KP_FRONTEND_ERROR に入れて終了コード1。
kp_frontend_prepare() {
    local k="$1" folder key vol hash
    KP_FRONTEND_ARGS=()
    KP_FRONTEND_PRE=
    KP_FRONTEND_ERROR=
    folder=$(kp_folder 2>&1) || { KP_FRONTEND_ERROR=$folder; return 1; }
    key=$(kp_folder_key 2>&1) || { KP_FRONTEND_ERROR=$key; return 1; }
    vol="kp-pnpm-store-$k"
    kp_node_volume "$vol" "$k" "$folder" /pnpm-store || return 1
    if [ ! -f "$folder/frontend/pnpm-lock.yaml" ] || [ ! -f "$folder/frontend/package.json" ]; then
        KP_FRONTEND_ERROR="frontend/pnpm-lock.yaml か frontend/package.json が無い"
        return 1
    fi
    hash=$(cat "$folder/frontend/pnpm-lock.yaml" "$folder/frontend/package.json" | git hash-object --stdin) || {
        KP_FRONTEND_ERROR="pnpm-lock.yaml と package.json の値を求められない"
        return 1
    }
    KP_FRONTEND_ARGS=(-v "kp-nm-$key:/home/node/app/node_modules" -v "$vol:/pnpm-store" -e "KP_LOCK_HASH=$hash")
    # shellcheck disable=SC2016 # コンテナの中の sh が展開する
    KP_FRONTEND_PRE='if [ "$(cat node_modules/.kp-lock-hash 2>/dev/null)" != "$KP_LOCK_HASH" ]; then pnpm install --frozen-lockfile --store-dir /pnpm-store || exit '"$KP_PRE_FAIL_CODE"'; printf %s "$KP_LOCK_HASH" >node_modules/.kp-lock-hash || exit '"$KP_PRE_FAIL_CODE"'; fi'
    return 0
}

_kp_rc_fail69() {
    printf '[parallel] 検査できない: %s\n' "$*"
    exit 69
}

# 枠の持ち主の一覧を、順番待ちの知らせの形で出す
_kp_rc_print_holders() { # <設定の数>
    local n="$1" now k folder issue kind started label
    now=$(date +%s)
    # タブは IFS の空白の扱いで続いた区切りが1つにまとまり、空の欄(Issueの番号が無いとき)が消える。
    # 空白でない区切り(\037)に替えてから読み、空の欄を保つ
    while IFS=$'\037' read -r k folder issue kind started; do
        [ -n "$k" ] || continue
        case "$started" in '' | *[!0-9]*) started=$now ;; esac
        if [ -n "$issue" ]; then label="#$issue"; else label="Issue不明"; fi
        printf '[parallel] 順番待ち: 設定の数 %s の枠を、%s(%s、%s、%s分前から)が使っている\n' \
            "$n" "$label" "$folder" "$kind" "$(((now - started) / 60))"
    done < <(kp_slot_holders 2>/dev/null | tr '\t' '\037')
}

# 秒の環境変数を読む(1以上の整数でなければ既定の値)
_kp_rc_seconds() { # <値> <既定の値>
    case "$1" in
        '' | *[!0-9]*) printf '%s\n' "$2" ;;
        *) if [ "$((10#$1))" -ge 1 ]; then printf '%s\n' "$((10#$1))"; else printf '%s\n' "$2"; fi ;;
    esac
}

_kp_rc_release() {
    if [ -n "${KP_RC_SLOT:-}" ]; then
        (kp_slot_release "$KP_RC_SLOT") >/dev/null 2>&1
        KP_RC_SLOT=
    fi
}

# 最後の品質チェックかどうか
_kp_rc_is_final() { # <領域> <コマンド>...
    local area="$1"
    shift
    case "$area:$*" in
        "frontend:pnpm run coverage" | "frontend:pnpm run coverage "*) return 0 ;;
        "backend:./gradlew check" | "backend:./gradlew check "*) return 0 ;;
        "terraform:checkov" | "terraform:checkov "*) return 0 ;;
    esac
    return 1
}

kp_run_check_main() {
    set -u
    local wait=0 area service folder key n out rc main limit interval waited_from k
    local -a args
    local pre script

    if [ "${1:-}" = --wait ]; then
        wait=1
        shift
    fi
    area="${1:-}"
    shift || true
    case "$area" in
        frontend | backend | terraform) service=$area ;;
        *) _kp_rc_fail69 "領域 '$area' は frontend backend terraform のどれでもない(使い方: run-check.sh [--wait] <領域> <コマンド>...)" ;;
    esac
    [ $# -ge 1 ] || _kp_rc_fail69 "コマンドが無い(使い方: run-check.sh [--wait] <領域> <コマンド>...)"

    # 1. いまの作業フォルダの最上位へ移る
    folder=$(kp_folder 2>&1) || _kp_rc_fail69 "$folder"
    cd "$folder" || _kp_rc_fail69 "作業フォルダ $folder に移れない"
    key=$(kp_folder_key 2>&1) || _kp_rc_fail69 "$key"
    n=$(kp_slots 2>&1) || _kp_rc_fail69 "$n"

    # 2. backend は Testcontainers が使う本体のプロジェクトの dind が動いているかを確かめ、止まっていれば起こす
    if [ "$area" = backend ]; then
        out=$(docker compose -p keirekipro ps --status running -q dind 2>&1) \
            || _kp_rc_fail69 "dind が動いているかを確かめられない: $out"
        if [ -z "$out" ]; then
            main=$(kp_main_folder 2>&1) || _kp_rc_fail69 "$main"
            docker compose -p keirekipro --project-directory "$main" -f "$main/compose.yaml" up -d dind \
                || _kp_rc_fail69 "本体のプロジェクトの dind を起こせない"
        fi
    fi

    # 3. 枠を取る
    limit=$(_kp_rc_seconds "${KP_WAIT_LIMIT_SECONDS:-}" 1800)
    interval=$(_kp_rc_seconds "${KP_WAIT_INTERVAL_SECONDS:-}" 5)
    waited_from=$(date +%s)
    local told=0
    while :; do
        out=$(kp_slot_acquire check "$area $*" 2>&1)
        rc=$?
        if [ "$rc" = 0 ]; then
            k=${out##*$'\n'}
            case "$k" in
                '' | *[!0-9]*) _kp_rc_fail69 "枠の番号を読めない: $out" ;;
            esac
            break
        fi
        [ "$rc" = 69 ] && _kp_rc_fail69 "$out"
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
    KP_RC_SLOT=$k
    # 途中で止められても枠を返す
    trap '_kp_rc_release' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP

    # 4. Docker につながることと compose の読み込みを確かめてから、枠のラベルを付けた1回きりのコンテナで動かす
    #    (config -q は Docker が動いていなくても通るので、つながるかは別に確かめる)
    if ! out=$(docker version --format '{{.Server.Version}}' 2>&1); then
        # 空の行(サーバーの版の欄)を除き、エラーの文を1行にする
        out=$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tr '\n' ' ')
        _kp_rc_fail69 "Docker につながらない: ${out% }"
    fi
    out=$(docker compose -p keirekipro -f compose.yaml config -q 2>&1) \
        || _kp_rc_fail69 "compose の読み込みに失敗した: $out"
    args=()
    pre=
    case "$area" in
        frontend)
            kp_frontend_prepare "$k" || _kp_rc_fail69 "$KP_FRONTEND_ERROR"
            local workers=$((8 / n))
            [ "$workers" -ge 1 ] || workers=1
            args=("${KP_FRONTEND_ARGS[@]}" -e "VITEST_MAX_WORKERS=$workers")
            pre=$KP_FRONTEND_PRE
            ;;
        backend)
            args=(-v "kp-gradle-home-$k:/root/.gradle" -v "kp-gradle-project-$key:/home/spring/app/.gradle")
            ;;
        terraform)
            args=(-v "kp-tf-plugins-$k:/tf-plugin-cache" -e "TF_PLUGIN_CACHE_DIR=/tf-plugin-cache")
            pre="[ -d .terraform ] || terraform init -backend=false -input=false || exit $KP_PRE_FAIL_CODE"
            ;;
    esac
    # shellcheck disable=SC2016 # コンテナの中の sh が展開する
    script="${pre:+$pre; }"'exec "$@"'
    docker compose -p keirekipro -f compose.yaml run --rm --no-deps -T \
        --label "keirekipro.slot=$k" --label "keirekipro.folder=$key" \
        "${args[@]}" --entrypoint sh "$service" -c "$script" -- "$@"
    rc=$?

    # 5. 枠を返し、コマンドの終了コードを返す
    _kp_rc_release
    if [ "$rc" = "$KP_PRE_FAIL_CODE" ] && [ -n "$pre" ]; then
        printf '[parallel] 検査できない: コンテナの中の準備(%s)に失敗した\n' \
            "$([ "$area" = frontend ] && echo 'pnpm install' || echo 'terraform init')"
        rc=69
    fi

    # 6. 最後の品質チェックが0で終わったときだけ記録を書く
    if [ "$rc" = 0 ] && _kp_rc_is_final "$area" "$@"; then
        mkdir -p "$folder/.claude/.state" && date +%s >"$folder/.claude/.state/gate-run-$area.txt"
    fi
    exit "$rc"
}

# 読み込まれただけ(source)のときは本体の処理を動かさない
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    kp_run_check_main "$@"
fi
