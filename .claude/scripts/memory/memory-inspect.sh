#!/bin/bash
# =====================================================================
# メモリの点検の入口のコマンド
#
# 使い方: bash .claude/scripts/memory/memory-inspect.sh <サブコマンド> [引数]
#   enable [--day mon|tue|wed|thu|fri|sat|sun] [--time HH:MM]
#     この PC の OS の予定の仕組みに、週に1回 run を動かす予定を登録し、config.json を書く
#   disable
#     予定を外し、config.json の enabled を偽にする
#   run
#     決まった曜日と時刻に、OS の予定の仕組みから点検を1回行う
#   run-now
#     点検をその場で1回行う
#   session-context
#     会話の始めのフックが Claude の文脈に入れる、まだ示していない報告と、点検が長く動いていないことを知らせる文を出す
#   show <回の ID> / shown <回の ID>
#     その回の報告を出す / その回の報告を示した印を書く
#   history
#     過去の点検を1回ずつ1行で出す
#   revert <回の ID> <直しの ID>
#     直しを戻す
#   answer <回の ID> <案の ID> declined|accepted [--issue <番号>]
#     案への答えを記録する
#   missed <汚染の種類> <メモリファイルの名前> <短い説明>
#     点検の見落としを記録する
# 本体の作業フォルダと点検の状態の場所は、このスクリプトの場所から求める。どのフォルダから呼んでも、
# OS の予定の仕組みから動いても、同じ場所になる。点検の状態の場所は <git の共通ディレクトリ>/keirekipro-memory-inspection/ である。
# 終了コード: 成功は 0、使い方の誤りは 2、失敗は 1(標準エラーに理由を日本語の1文で出す)
# 前提: bash 3.2 以上・perl(JSON::PP)・git。macOS で動く書き方だけを使う
# =====================================================================
set -u

# git に渡すので、Windows では C:/... の形にする。会話の中の Claude Code は Git Bash の引数の書き換えを止めるので、
# /c/... の形のままでは git が場所を見つけられない
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && { pwd -W 2>/dev/null || pwd -P; })
PL="$HERE/memory-inspect.pl"

fail() {
    printf 'memory-inspect.sh: %s\n' "$1" >&2
    exit 1
}

usage() {
    cat >&2 <<'EOF'
使い方: bash .claude/scripts/memory/memory-inspect.sh <サブコマンド> [引数]
  enable [--day mon|tue|wed|thu|fri|sat|sun] [--time HH:MM]
  disable
  run
  run-now
  session-context
  show <回の ID>
  shown <回の ID>
  history
  revert <回の ID> <直しの ID>
  answer <回の ID> <案の ID> declined|accepted [--issue <番号>]
  missed <汚染の種類> <メモリファイルの名前> <短い説明>
EOF
    exit 2
}

# 本体の作業フォルダと、点検の状態の場所と、メモリのディレクトリを、MAIN と STATE と MEMDIR に入れる
MAIN=
STATE=
MEMDIR=
locate() {
    local out
    out=$(perl "$PL" paths "$HERE") || fail "本体の作業フォルダを求められなかった。"
    {
        IFS= read -r MAIN && IFS= read -r STATE && IFS= read -r MEMDIR
    } <<EOF || fail "本体の作業フォルダを求められなかった。"
$out
EOF
    [ -n "$MAIN" ] && [ -n "$STATE" ] && [ -n "$MEMDIR" ] || fail "本体の作業フォルダを求められなかった。"
}

# 点検の状態の場所を作る。locate のあとで呼ぶ
ensure_state() {
    mkdir -p "$STATE" || fail "点検の状態の場所 $STATE を作れなかった。"
}

# claude と gh と bash の場所を command -v で求め、今の PATH と一緒に
# {"bin":{"bash":..,"claude":..,"gh":..},"path":..} の1行で出す。見つからないコマンドの場所は空にする。
# run-now と enable が同じ求め方で使う
tool_paths() {
    local c g b
    c=$(command -v claude 2>/dev/null) || c=
    g=$(command -v gh 2>/dev/null) || g=
    b=$(command -v bash 2>/dev/null) || b=
    perl "$PL" tools "$c" "$g" "$b" "$PATH"
}

# 点検のロックに書くプロセスの番号として、このシェルのプロセスの番号を出す。Windows では、Git Bash の
# /proc/<番号>/winpid から読んだ Windows のプロセスの番号を出す。点検は別の Git Bash から起動されることがあるためである
owner_pid() {
    cat "/proc/$$/winpid" 2>/dev/null || printf '%s\n' "$$"
}

# 点検のロックを、このシェルのプロセスの番号で取る: run_lock_take <回の ID>
# 取れたら taken を出して 0 を返し、ほかの回が取っていれば held <取っている回の ID> を出して 3 を返す
run_lock_take() {
    perl "$PL" lock take run "$1" "$(owner_pid)"
}

# その回が取っている点検のロックを外す: run_lock_release <回の ID>
run_lock_release() {
    perl "$PL" lock release run "$1"
}

# 理由を標準エラーに1文で出す。fail と違い、終わらない
say_reason() {
    printf 'memory-inspect.sh: %s\n' "$1" >&2
}

# 点検の中の Claude を、調べてほしいことに答えながら3回まで呼び、返った直し方を memory-inspect.pl apply に渡して、
# その終了コードを返す: inspect_with_claude <回の ID> <比べる材料の JSON> <claude の場所>
# 点検の中の Claude の作業フォルダは、点検の状態の場所の中の空の work/ で、終わったら消す。点検の中の Claude の出力と
# 直し方は、変数にだけ持ち、ファイルに書かない。失敗したときは、標準エラーに理由を1文で出して 0 でない値を返し、メモリを書き換えない
inspect_with_claude() {
    local work="$STATE/work" rc
    if ! { rm -rf "$work" && mkdir -p "$work"; }; then
        say_reason "点検の中の Claude の作業フォルダ $work を作れなかった。"
        return 1
    fi
    inspect_calls "$1" "$2" "$3" "$work"
    rc=$?
    rm -rf "$work"
    return "$rc"
}

# inspect_with_claude の呼び出しの繰り返し: inspect_calls <回の ID> <比べる材料の JSON> <claude の場所> <作業フォルダ>
# 1回の呼び出しの上限は KP_MEMORY_INSPECTION_CALL_SEC、全体の上限は KP_MEMORY_INSPECTION_TOTAL_SEC の秒で、テストが短くする
inspect_calls() {
    local run=$1 material=$2 claude=$3 work=$4 nl='
'
    local call=${KP_MEMORY_INSPECTION_CALL_SEC:-1200} total=${KP_MEMORY_INSPECTION_TOTAL_SEC:-3600}
    local prompt schema content deadline n=1 first=1 looked='' left limit allowed out rc res kind got
    case "$call" in '' | *[!0-9]* | 0) call=1200 ;; esac
    case "$total" in '' | *[!0-9]* | 0) total=3600 ;; esac
    deadline=$(($(date +%s) + total))
    prompt=$(cat "$HERE/inspect-prompt.md") || { say_reason "点検の指示 inspect-prompt.md を読めなかった。"; return 1; }
    schema=$(cat "$HERE/plan-schema.json") || { say_reason "直し方の形 plan-schema.json を読めなかった。"; return 1; }
    content=$(perl "$PL" content) || return 1
    while :; do
        left=$((deadline - $(date +%s)))
        if [ "$left" -le 0 ]; then
            say_reason "点検の全体の上限の ${total} 秒を超えたので、点検の中の Claude を呼ばずに止めた。"
            return 1
        fi
        limit=$call
        [ "$left" -lt "$limit" ] && limit=$left
        if [ "$n" -lt 3 ]; then
            allowed="この呼び出しで返してよいもの: この呼び出しは${n}回目です。調べてほしいことを lookups に並べて plan を null にするか、lookups を空の配列にして plan に直し方を書いて返してください。"
        else
            allowed="この呼び出しで返してよいもの: この呼び出しは3回目です。調べてほしいことは返せません。lookups を空の配列にし、plan に直し方を書いて返してください。確かめられていない汚染は、扱いを unverified にしてください。"
        fi
        out=$(printf '%s\n\n%s\n\n%s\n\n%s%s\n' "$prompt" "$material" "$content" "${looked:+$looked$nl$nl}" "$allowed" |
            perl "$PL" inspector "$limit" "$work" "$claude" -p --output-format json --json-schema "$schema" --tools "" \
                --permission-mode dontAsk --setting-sources user --settings '{"disableAllHooks": true}' --strict-mcp-config \
                --no-session-persistence --max-turns 4)
        rc=$?
        if [ "$rc" -eq 124 ]; then
            if [ "$limit" -lt "$call" ]; then
                say_reason "点検の全体の上限の ${total} 秒を超えたので、${n}回目の点検の中の Claude の呼び出しを止めた。"
            else
                say_reason "1回の呼び出しの上限の ${call} 秒を超えたので、${n}回目の点検の中の Claude の呼び出しを止めた。"
            fi
            return 1
        fi
        res=$(printf '%s\n' "$out" | perl "$PL" outcome "$n" "$rc") || return 1
        kind=${res%%"$nl"*}
        res=${res#*"$nl"}
        if [ "$kind" = plan ]; then
            printf '%s\n' "$res" | perl "$PL" apply "$run"
            return
        fi
        left=$((deadline - $(date +%s)))
        if [ "$left" -le 0 ]; then
            say_reason "点検の全体の上限の ${total} 秒を超えたので、調べてほしいことを調べずに止めた。"
            return 1
        fi
        got=$(printf '%s\n' "$res" | perl "$PL" timed "$left" perl "$PL" lookup "$run" "$first")
        rc=$?
        if [ "$rc" -eq 124 ]; then
            say_reason "点検の全体の上限の ${total} 秒を超えたので、調べてほしいことを調べている途中で止めた。"
            return 1
        fi
        [ "$rc" -eq 0 ] || return 1
        looked="$looked${looked:+$nl}$got"
        first=$((first + ${kind#lookups }))
        n=$((n + 1))
    done
}

# 会話の中の操作は、引数をそのまま memory-inspect.pl に渡す。引数の確かめは memory-inspect.pl が行う
cmd_show() { perl "$PL" show "$@"; }
cmd_shown() { perl "$PL" shown "$@"; }
cmd_history() { perl "$PL" history "$@"; }
cmd_revert() { perl "$PL" revert "$@"; }
cmd_answer() { perl "$PL" answer "$@"; }
cmd_missed() { perl "$PL" missed "$@"; }

main() {
    [ $# -gt 0 ] || usage
    local sub=$1
    shift
    case "$sub" in
    enable | disable | run | run-now | session-context | show | shown | history | revert | answer | missed)
        "cmd_${sub//-/_}" "$@"
        ;;
    *)
        printf 'memory-inspect.sh: 知らないサブコマンド %s を受けた。\n' "$sub" >&2
        usage
        ;;
    esac
}

# テストが source で読み込んだときは、サブコマンドを動かさない
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
