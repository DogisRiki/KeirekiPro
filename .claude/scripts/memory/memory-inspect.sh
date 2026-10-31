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

# 会話の中の操作は、引数をそのまま memory-inspect.pl に渡す。引数の確かめは memory-inspect.pl が行う
cmd_show() { perl "$PL" show "$@"; }
cmd_shown() { perl "$PL" shown "$@"; }
cmd_history() { perl "$PL" history "$@"; }
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
