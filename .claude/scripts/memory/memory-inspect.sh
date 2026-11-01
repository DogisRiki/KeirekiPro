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

# Windows のタスク スケジューラは、Git の usr/bin を含まない Windows の PATH で bash を起動する。
# dirname と perl を見つけられるように、Windows では、PATH に無い /usr/bin と /bin を後ろに足す。
# ほかの OS の予定の仕組みは、/usr/bin と /bin を含む PATH で動かすので、PATH を変えない
case ${OSTYPE:-} in
msys* | cygwin*)
    case ":$PATH:" in *:/usr/bin:*) ;; *) PATH="$PATH:/usr/bin" ;; esac
    case ":$PATH:" in *:/bin:*) ;; *) PATH="$PATH:/bin" ;; esac
    ;;
esac

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

# 段の標準エラーを書いたファイルを、run.log に足すために標準エラーに出してから消し、最後に出た理由の1文を REASON に入れる。
# 段が失敗したのに理由が無ければ、段の名前と終了コードから理由を作る: stage_reason <ファイル> <終了コード> <段の名前>
REASON=''
stage_reason() {
    local line
    REASON=''
    if [ -f "$1" ]; then
        cat "$1" >&2
        while IFS= read -r line; do
            case "$line" in
            memory-inspect.sh:\ * | memory-inspect.pl:\ *) REASON=${line#*: } ;;
            esac
        done <"$1"
        rm -f "$1"
    fi
    if [ "$2" -ne 0 ] && [ -z "$REASON" ]; then
        REASON="${3}が、理由を出さずに終了コード ${2} で終わった。"
    fi
}

# 点検の1回のうち、前の回の後始末から点検のロックを外すまでを行い、点検が完了したら 0 を返す。run と run-now が使う:
# inspect_run <回の ID> <scheduled|now> <claude の場所>
# 呼ぶ側が、回の場所を作り、点検のロックをこの回で取ってから呼ぶ。どの段で失敗しても、finalize に理由を渡して
# その回を中断にし、点検のロックを外す。比べる材料はメモリの文を含むので、変数にだけ持ち、標準出力と標準エラーに出さない
inspect_run() {
    local run=$1 trigger=$2 claude=$3 err="$STATE/runs/$1/stage.err" material='' rc=0
    perl "$PL" finalize 2>"$err" || rc=$?
    stage_reason "$err" "$rc" "前の回の後始末"
    if [ "$rc" -eq 0 ]; then
        material=$(perl "$PL" prepare "$run" "$trigger" 2>"$err") || rc=$?
        stage_reason "$err" "$rc" "メモリの読み込み"
    fi
    if [ "$rc" -eq 0 ]; then
        inspect_with_claude "$run" "$material" "$claude" 2>"$err" || rc=$?
        stage_reason "$err" "$rc" "点検の中の Claude を呼ぶ部品"
    fi
    if [ "$rc" -ne 0 ]; then
        perl "$PL" finalize --run "$run" --reason "$REASON" || say_reason "回 $run を中断にできなかった。"
    fi
    run_lock_release "$run" || say_reason "回 $run の点検のロックを外せなかった。"
    if [ "$rc" -eq 0 ]; then
        printf '[memory-inspection] finished: %s completed\n' "$run"
    else
        printf '[memory-inspection] finished: %s interrupted\n' "$run"
    fi
    return "$rc"
}

# 決まった曜日と時刻の点検の流れ。標準出力と標準エラーは、呼ぶ側が run.log に足す:
# scheduled_run <回の ID> <claude の場所> <PATH>
# 点検のロックがほかの点検に取られていれば、KP_MEMORY_INSPECTION_RETRY_SEC の秒(テストが短くする)ごとに取り直して待つ
scheduled_run() {
    local run=$1 claude=${2:-claude} retry=${KP_MEMORY_INSPECTION_RETRY_SEC:-30} rc held waited=''
    case "$retry" in '' | *[!0-9]* | 0) retry=30 ;; esac
    # OS の予定の仕組みから動くと、ターミナルと同じ PATH を持たないので、enable が書いた PATH を使う
    if [ -n "$3" ]; then
        PATH=$3
        export PATH
    fi
    if ! mkdir -p "$STATE/runs"; then
        say_reason "点検の状態の場所 $STATE/runs を作れなかった。"
        return 1
    fi
    # 同じ回がもう動いていれば、回の場所を作れない
    mkdir "$STATE/runs/$run" 2>/dev/null || return 0
    printf '[memory-inspection] run-id: %s\n' "$run"
    while :; do
        held=$(run_lock_take "$run")
        rc=$?
        [ "$rc" -eq 0 ] && break
        if [ "$rc" -ne 3 ]; then
            rmdir "$STATE/runs/$run"
            say_reason "回 $run の点検のロックを取れなかった。"
            return 1
        fi
        if [ -z "$waited" ]; then
            printf '[memory-inspection] 点検のロックが空くのを待つ: %s\n' "$held"
            waited=1
        fi
        sleep "$retry"
    done
    inspect_run "$run" scheduled "$claude"
}

cmd_run() {
    local due run='' claude='' path='' log rc
    [ $# -eq 0 ] || usage
    locate
    log="$STATE/run.log"
    [ -f "$STATE/config.json" ] || return 0
    if ! due=$(perl "$PL" due 2>&1); then
        printf '%s\n' "$due" >>"$log"
        return 1
    fi
    [ -n "$due" ] || return 0
    {
        IFS= read -r run && IFS= read -r claude && IFS= read -r path
    } <<EOF
$due
EOF
    scheduled_run "$run" "$claude" "$path" >>"$log" 2>&1
    rc=$?
    perl "$PL" logtrim "$log"
    return "$rc"
}

# 点検をその場で1回行う。config.json の enabled と時刻を確かめず、config.json と OS の予定の仕組みを書き換えない。
# 点検が完了したら 0、中断したら 1、ほかの点検が動いていれば 3 で終わる
cmd_run_now() {
    local tools='' out run='' claude='' path='' held rc
    [ $# -eq 0 ] || usage
    locate
    ensure_state
    # config.json が無ければ、enable と同じ求め方で、今の PATH から claude の場所を求める
    if [ ! -f "$STATE/config.json" ]; then
        tools=$(tool_paths) || fail "claude と gh と bash の場所を求められなかった。"
    fi
    out=$(perl "$PL" nowrun "$tools") || fail "その場の点検の回の ID と claude の場所を求められなかった。"
    {
        IFS= read -r run && IFS= read -r claude && IFS= read -r path
    } <<EOF
$out
EOF
    if [ -n "$path" ]; then
        PATH=$path
        export PATH
    fi
    mkdir -p "$STATE/runs" || fail "点検の状態の場所 $STATE/runs を作れなかった。"
    mkdir "$STATE/runs/$run" || fail "回の場所 $STATE/runs/$run を作れなかった。"
    printf '[memory-inspection] run-id: %s\n' "$run"
    held=$(run_lock_take "$run")
    rc=$?
    if [ "$rc" -ne 0 ]; then
        rmdir "$STATE/runs/$run"
        [ "$rc" -eq 3 ] || fail "回 $run の点検のロックを取れなかった。"
        printf '[memory-inspection] 点検がすでに動いている: %s\n' "${held#held }"
        exit 3
    fi
    inspect_run "$run" now "${claude:-claude}" || exit 1
}

# enable の受け付ける形を、理由と一緒に標準エラーに出して、終了コード 2 で終わる: enable_usage <理由>
enable_usage() {
    printf 'memory-inspect.sh: %s\n' "$1" >&2
    printf '受け付ける形: enable [--day mon|tue|wed|thu|fri|sat|sun] [--time HH:MM](曜日の初期値は mon、時刻の初期値は 10:00)\n' >&2
    exit 2
}

# この PC の OS の予定の仕組みの名前(windows-task か launchd か cron)を出す。
# テストは KP_MEMORY_INSPECTION_OS(windows か macos か linux)で OS を替える
scheduler_kind() {
    local os=${KP_MEMORY_INSPECTION_OS:-}
    if [ -z "$os" ]; then
        case "$(uname -s 2>/dev/null)" in
        Linux) os=linux ;;
        Darwin) os=macos ;;
        MINGW* | MSYS* | CYGWIN*) os=windows ;;
        esac
    fi
    case "$os" in
    windows) printf 'windows-task\n' ;;
    macos) printf 'launchd\n' ;;
    linux) printf 'cron\n' ;;
    *) fail "この OS の予定の仕組みに対応していない。点検の予定は、Windows と macOS と Linux で登録できる。" ;;
    esac
}

# 利用者の今の crontab の中身を出す。crontab がまだ無いときは、何も出さない。locate のあとで呼ぶ
cron_list() {
    local err="$STATE/crontab.err" out rc=0
    out=$(crontab -l 2>"$err") || rc=$?
    if [ "$rc" -ne 0 ]; then
        if grep -q -i 'no crontab' "$err"; then
            rm -f "$err"
            return 0
        fi
        say_reason "crontab の中身を読めなかった。crontab の出力: $(cat "$err")"
        rm -f "$err"
        return 1
    fi
    rm -f "$err"
    printf '%s\n' "$out"
}

# 利用者の crontab を、印の付いた行を替えた中身で書き戻す。中身が変わらないときは書き戻さない:
# cron_write <ID8> [<曜日> <HH:MM> <スクリプトの場所>]
cron_write() {
    local current table out
    current=$(cron_list) || exit 1
    table=$(printf '%s\n' "$current" | perl "$PL" cron "$@" ${2:+"$STATE/run.log"}) || fail "crontab に書く中身を作れなかった。"
    [ "$table" != "$current" ] || return 0
    out=$(printf '%s\n' "$table" | crontab - 2>&1) || fail "crontab に予定を書けなかった。crontab の出力: $out"
}

# Linux の利用者の crontab に、印の付いた行を1行だけ置く: cron_enable <ID8> <曜日> <HH:MM> <スクリプトの場所>
cron_enable() {
    command -v crontab >/dev/null 2>&1 ||
        fail "crontab が見つからない。cron を入れてから(Debian と Ubuntu では sudo apt install cron、Fedora では sudo dnf install cronie)、enable を打ち直す。"
    cron_write "$@"
}

# Linux の利用者の crontab から、印の付いた行を消す。crontab が無ければ、予定も無いので何もしない: cron_disable <ID8>
cron_disable() {
    command -v crontab >/dev/null 2>&1 || return 0
    cron_write "$1"
}

# Windows のプログラムに渡す場所の形にする。cygpath が無い環境では、そのまま出す: win_path <場所>
win_path() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi
}

# 命令の文を、powershell.exe に -EncodedCommand で渡す。失敗したら、失敗したときの文に powershell.exe の出力を添えて終わる:
# powershell_run <失敗したときの文> <memory-inspect.pl の windows-task の引数>...
powershell_run() {
    local msg=$1 cmd out
    shift
    command -v powershell.exe >/dev/null 2>&1 ||
        fail "powershell.exe が見つからない。Windows の PowerShell を使える状態にしてから、打ち直す。"
    cmd=$(perl "$PL" windows-task "$@") || fail "powershell.exe に渡す命令の文を作れなかった。"
    out=$(powershell.exe -NoProfile -NonInteractive -EncodedCommand "$cmd" 2>&1) || fail "$msg powershell.exe の出力: $out"
}

# 起動用のプログラム windows-launcher.exe を試しに動かしてから、Windows のタスク スケジューラに、windows-launcher.exe が
# bash.exe でスクリプトの run を動かす予定を登録する。windows-launcher.exe が無いときと、本体の作業フォルダの
# windows-launcher.cs より古いときは、先に作り直す。同じ名前の予定は -Force で置き換わる:
# windows_enable <予定の名前> <曜日> <HH:MM> <スクリプトの場所>
windows_enable() {
    local b cs exe build=0
    b=$(command -v bash)
    if [ -f "$b.exe" ]; then b="$b.exe"; fi
    cs="$(dirname "$4")/windows-launcher.cs"
    exe="$STATE/windows-launcher.exe"
    [ -f "$cs" ] ||
        fail "本体の作業フォルダに $cs が無い。本体の作業フォルダを main に合わせてから、enable を打ち直す。"
    if [ ! -f "$exe" ] || [ "$exe" -ot "$cs" ]; then build=1; fi
    powershell_run "起動用のプログラム windows-launcher.exe を作れなかったか、試しに動かすと 0 でない終了コードで終わったので、予定を登録しなかった。セキュリティの道具が止めていないかを確かめてから、打ち直す。" \
        launcher "$build" "$(win_path "$cs")" "$(win_path "$exe")" "$(win_path "$b")"
    powershell_run "タスク スケジューラの予定を変えられなかった。" enable "$2" "$3" "$1" "$(win_path "$b")" "$(win_path "$4")" "$(win_path "$exe")"
}

# macOS の launchd に、plist を書いて読み込む。古い登録を外してから読み込むので、予定は1つだけになる:
# launchd_enable <ラベル> <曜日> <HH:MM> <スクリプトの場所>
launchd_enable() {
    local dir="$HOME/Library/LaunchAgents" gui out
    local plist="$dir/$1.plist"
    gui="gui/$(id -u)"
    mkdir -p "$dir" || fail "$dir を作れなかった。"
    if ! { perl "$PL" plist "$1" "$2" "$3" "$4" "$STATE/run.log" >"$plist.tmp" && mv -f "$plist.tmp" "$plist"; }; then
        rm -f "$plist.tmp"
        fail "$plist を書けなかった。"
    fi
    launchctl bootout "$gui/$1" >/dev/null 2>&1 || true
    out=$(launchctl bootstrap "$gui" "$plist" 2>&1) || {
        rm -f "$plist"
        fail "launchd に予定を読み込めなかった。launchctl の出力: $out"
    }
}

# macOS の launchd から予定を外し、plist を消す。予定が無くても何もしないで終わる: launchd_disable <ラベル>
launchd_disable() {
    launchctl bootout "gui/$(id -u)/$1" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/LaunchAgents/$1.plist"
}

# 点検の予定を登録し、config.json を書く。登録は、本体の作業フォルダのスクリプトを動かす。worktree は消されることがあるためである
cmd_enable() {
    local day=mon time=10:00 main_sh kind id tools name
    while [ $# -gt 0 ]; do
        case "$1" in
        --day | --time)
            [ $# -ge 2 ] || enable_usage "$1 のあとに値が無い。"
            if [ "$1" = --day ]; then day=$2; else time=$2; fi
            shift 2
            ;;
        *) enable_usage "知らない引数 $1 を受けた。" ;;
        esac
    done
    case "$day" in mon | tue | wed | thu | fri | sat | sun) ;; *) enable_usage "曜日 $day を受け付けない。" ;; esac
    case "$time" in [01][0-9]:[0-5][0-9] | 2[0-3]:[0-5][0-9]) ;; *) enable_usage "時刻 $time を受け付けない。" ;; esac
    locate
    main_sh="$MAIN/.claude/scripts/memory/memory-inspect.sh"
    [ -f "$main_sh" ] ||
        fail "本体の作業フォルダ $MAIN に .claude/scripts/memory/memory-inspect.sh が無い。本体の作業フォルダを main に合わせてから、enable を打ち直す。"
    kind=$(scheduler_kind) || exit 1
    id=$(perl "$PL" id8) || fail "予定の名前に付ける印を求められなかった。"
    tools=$(tool_paths) || fail "claude と gh と bash の場所を求められなかった。"
    ensure_state
    # 登録が失敗したら、各 OS の部分が理由を出して終わるので、config.json を書かない
    case "$kind" in
    windows-task)
        name="KeirekiPro memory inspection $id"
        windows_enable "$name" "$day" "$time" "$main_sh"
        ;;
    launchd)
        name="com.keirekipro.memory-inspection.$id"
        launchd_enable "$name" "$day" "$time" "$main_sh"
        ;;
    cron)
        name="KeirekiPro memory inspection $id"
        cron_enable "$id" "$day" "$time" "$main_sh"
        ;;
    esac
    perl "$PL" config enable "$day" "$time" "$kind" "$name" "$tools" || fail "予定を登録したが、config.json を書けなかった。"
    printf '[memory-inspection] 点検の予定を登録した: 毎週 %s の %s(%s)\n' "$day" "$time" "$kind"
}

# config.json の enabled を偽にしてから、点検の予定を外す。先に enabled を偽にするので、予定を外せなかったときも、
# 予定から動いた run は何もしない。予定が無くても成功で終わる。記録と、まだ示していない報告は消さない
cmd_disable() {
    local kind id
    [ $# -eq 0 ] || usage
    locate
    kind=$(scheduler_kind) || exit 1
    perl "$PL" config disable || fail "config.json の enabled を偽にできなかった。"
    id=$(perl "$PL" id8) || fail "予定の名前に付ける印を求められなかった。"
    ensure_state
    case "$kind" in
    windows-task) powershell_run "タスク スケジューラの予定を変えられなかった。" disable "KeirekiPro memory inspection $id" ;;
    launchd) launchd_disable "com.keirekipro.memory-inspection.$id" ;;
    cron) cron_disable "$id" ;;
    esac
    printf '[memory-inspection] 点検の予定を外した。\n'
}

# 会話の始めのフックが Claude の文脈に入れる文を出す。点検の中の Claude の会話では何も出さない。
# 会話の始めを止めないように、8秒で打ち切り(テストは KP_MEMORY_INSPECTION_CONTEXT_SEC で短くする)、失敗したときは何も出さずに 0 で終わる。gh と claude を呼ばない
cmd_session_context() {
    local out
    [ -z "${KP_MEMORY_INSPECTION_RUN:-}" ] || return 0
    out=$(perl "$PL" timed "${KP_MEMORY_INSPECTION_CONTEXT_SEC:-8}" perl "$PL" session-context "$@" 2>/dev/null) || return 0
    if [ -n "$out" ]; then printf '%s\n' "$out"; fi
    return 0
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
