#!/bin/bash
# =====================================================================
# 点検のスクリプト(memory-inspect.sh と memory-inspect.pl と transcript-scan.pl)のテスト
#
# 実行: bash .claude/scripts/memory/tests/test-memory-inspect.sh
# テストの場合ごとに、一時のディレクトリ(newcase)に、origin/main を持つ偽の git のリポジトリと、その worktree と、
# 偽のホームと、偽のメモリのディレクトリと、偽の会話の記録の置き場所を作る。
# HOME と USERPROFILE を偽のホームに替え、所有者の本物のメモリと点検の状態の場所に触れない。
# PATH の先頭に偽の claude と偽の gh を置く。偽の powershell.exe と launchctl と crontab は、
# テストの場合が os_fake で求めたときだけ置く。今の時刻は KP_MEMORY_INSPECTION_NOW で与える。
# 前提: bash 3.2 以上・perl(JSON::PP)・git。macOS で動く書き方だけを使う
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# git が返すパス(Windows では C:/...、ほかではシンボリックリンクを解いた形)と同じ形で作る。
# macOS の mktemp が返す /var/folders/... の /var は、/private/var へのシンボリックリンクである
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd -P; })
BASE_PATH=$PATH

# 場所の英数字でない文字を1文字ずつ - に替えた名前を出す。Claude Code がプロジェクトのディレクトリの名前を作る決まりである
encname() { printf '%s' "$1" | perl -CS -pe 's/[^A-Za-z0-9]/-/g'; }
# テストするスクリプトのフォルダ。テストの場合ごとに、偽のリポジトリへ写してコミットする
SRC_DIR="$(cd "$HERE/.." && pwd)"

# 所有者の本物のメモリのディレクトリと、本物の点検の状態の場所。テストの前とあとで変わらないことを確かめる。
# git のリポジトリの外(検査用の写しやコンテナ)で流したときは、どちらも無い
REAL_MEMDIR=
REAL_STATE=
if real_common=$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    REAL_MEMDIR="$HOME/.claude/projects/$(encname "$(dirname "$real_common")")/memory"
    REAL_STATE="$real_common/keirekipro-memory-inspection"
fi
# 本物の会話の記録の置き場所を使わないように、Claude Code の設定の場所を外す。点検の中かを示す印も外す
unset CLAUDE_CONFIG_DIR KP_MEMORY_INSPECTION_RUN

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }

gitq() { git -c user.name=test -c user.email=test@example.com -C "$REPO" "$@"; }

# ---------------------------------------------------------------------
# 偽のコマンド。名前で起動するので、1行目は #!/usr/bin/env bash にする(bash:3.2 のイメージは /bin/bash を持たない)
# ---------------------------------------------------------------------

# 偽の claude: n 回目の呼び出しで、fake/claude/<n>.json を出す。<n>.sleep があれば先にその秒数だけ眠り、
# <n>.exit があればその終了コードで終わる。受けた引数を <n>.args.json に、標準入力を <n>.stdin に、
# 環境変数を <n>.env.json に、自分のプロセスの番号を <n>.pid に書き残す
write_fake_claude() {
    cat >"$1" <<'EOF'
#!/usr/bin/env bash
d="$KP_TEST_FAKE_DIR/claude"
n=$(($(cat "$d/count" 2>/dev/null || echo 0) + 1))
printf '%s\n' "$n" >"$d/count"
printf '%s\n' "$$" >"$d/$n.pid"
perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode([@ARGV])' -- "$@" >"$d/$n.args.json"
cat >"$d/$n.stdin"
perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({%ENV})' >"$d/$n.env.json"
# 眠っている間に止められたら、眠る子のプロセスも止める。残った子が標準出力を開いたままにしないためである
if [ -f "$d/$n.sleep" ]; then
    sp=
    trap '[ -n "$sp" ] && kill "$sp" 2>/dev/null; exit 143' TERM INT HUP
    sleep "$(cat "$d/$n.sleep")" &
    sp=$!
    wait "$sp"
    trap - TERM INT HUP
fi
if [ ! -f "$d/$n.json" ]; then
    printf '偽の claude: %s 回目に返す JSON が置かれていない\n' "$n" >&2
    exit 1
fi
cat "$d/$n.json"
exit "$(cat "$d/$n.exit" 2>/dev/null || echo 0)"
EOF
    chmod +x "$1"
}

# 偽の gh: 受けた引数を fake/gh/calls.jsonl に1行ずつ書き残す。issue view <N> には issue-<N>.json を、
# pr view <N> には pr-<N>.json を、issue list には issue-list.json を出す。置かれていなければ失敗する
write_fake_gh() {
    cat >"$1" <<'EOF'
#!/usr/bin/env bash
d="$KP_TEST_FAKE_DIR/gh"
perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode([@ARGV]), "\n"' -- "$@" >>"$d/calls.jsonl"
f=
case "${1-} ${2-}" in
"issue view") f="$d/issue-${3-}.json" ;;
"pr view") f="$d/pr-${3-}.json" ;;
"issue list") f="$d/issue-list.json" ;;
esac
if [ -z "$f" ] || [ ! -f "$f" ]; then
    printf '偽の gh: 返す JSON が置かれていない: %s\n' "$*" >&2
    exit 1
fi
cat "$f"
EOF
    chmod +x "$1"
}

# 偽の powershell.exe・launchctl・crontab: 受けた引数を fake/os/<名前>.calls.jsonl に1行ずつ書き残し、成功で終わる
write_fake_os() {
    cat >"$1" <<'EOF'
#!/usr/bin/env bash
perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode([@ARGV]), "\n"' -- "$@" >>"$KP_TEST_FAKE_DIR/os/${0##*/}.calls.jsonl"
EOF
    chmod +x "$1"
}

# ---------------------------------------------------------------------
# テストの場合の土台
# ---------------------------------------------------------------------

# テストの場合の一時のディレクトリを作る: newcase <名前>
# 作るもの:
#   CASE      テストの場合のディレクトリ
#   REPO      本体の作業フォルダ(main と、origin/main を持つ偽の git のリポジトリ)
#   WT        REPO の worktree(REPO/.claude/worktrees/wt1、ブランチ feat/wt1)
#   FHOME     偽のホーム。HOME と USERPROFILE にする
#   MEMDIR    偽のメモリのディレクトリ(FHOME/.claude/projects/<REPO の名前>/memory)。中身は空
#   TRANSDIR  REPO で動いた偽の会話の記録の置き場所(FHOME/.claude/projects/<REPO の名前>)
#   WTTRANSDIR WT で動いた偽の会話の記録の置き場所
#   STATE     点検の状態の場所(REPO/.git/keirekipro-memory-inspection)。作らない
#   FAKE      偽のコマンドの置いた答えと書き残しの場所。KP_TEST_FAKE_DIR にする
#   BIN       偽の claude と偽の gh を置くディレクトリ。PATH に入れるので、Windows でも C: の付かない形にする
#             (PATH の区切りの : と C: の : が見分けられないため)
#   SH PL     REPO にコミットした memory-inspect.sh と memory-inspect.pl
#   WTSH WTPL WT の memory-inspect.sh と memory-inspect.pl
#   TS        REPO にコミットした transcript-scan.pl
newcase() {
    CASE="$WORK/$1"
    REPO="$CASE/repo"
    WT="$REPO/.claude/worktrees/wt1"
    SH="$REPO/.claude/scripts/memory/memory-inspect.sh"
    PL="$REPO/.claude/scripts/memory/memory-inspect.pl"
    WTSH="$WT/.claude/scripts/memory/memory-inspect.sh"
    WTPL="$WT/.claude/scripts/memory/memory-inspect.pl"
    TS="$REPO/.claude/scripts/memory/transcript-scan.pl"
    FHOME="$CASE/home"
    TRANSDIR="$FHOME/.claude/projects/$(encname "$REPO")"
    WTTRANSDIR="$FHOME/.claude/projects/$(encname "$WT")"
    MEMDIR="$TRANSDIR/memory"
    STATE="$REPO/.git/keirekipro-memory-inspection"
    FAKE="$CASE/fake"
    BIN="$TMP_ROOT/$1/bin"
    mkdir -p "$BIN" "$FAKE/claude" "$FAKE/gh" "$FAKE/os" "$MEMDIR" "$WTTRANSDIR"
    write_fake_claude "$BIN/claude"
    write_fake_gh "$BIN/gh"

    git init -q "$REPO"
    gitq symbolic-ref HEAD refs/heads/main
    printf '.claude/worktrees/\n' >"$REPO/.gitignore"
    # 所有者の git の設定が改行を CRLF に替えて worktree に出さないように、改行を替えない
    printf '* -text\n' >"$REPO/.gitattributes"
    printf 'a\n' >"$REPO/README"
    mkdir -p "$REPO/.claude/scripts/memory"
    local f
    for f in "$SRC_DIR"/*; do
        if [ -f "$f" ]; then cp "$f" "$REPO/.claude/scripts/memory/"; fi
    done
    gitq add .gitignore .gitattributes README .claude/scripts
    GIT_COMMITTER_DATE="2026-10-01T00:00:00+09:00" gitq commit -q -m base
    gitq update-ref refs/remotes/origin/main HEAD
    gitq worktree add -q -b feat/wt1 "$WT" >/dev/null 2>&1 || ng "$1: worktree を作れない"

    HOME="$FHOME"
    USERPROFILE="$FHOME"
    KP_TEST_FAKE_DIR="$FAKE"
    KP_MEMORY_INSPECTION_NOW="2026-11-02T10:00:00+09:00"
    PATH="$BIN:$BASE_PATH"
    export HOME USERPROFILE KP_TEST_FAKE_DIR KP_MEMORY_INSPECTION_NOW PATH
    # 偽物が PATH の先頭に無いまま本物の claude と gh を動かさないように、テストを止める
    if [ "$(command -v claude)" != "$BIN/claude" ] || [ "$(command -v gh)" != "$BIN/gh" ]; then
        printf '偽の claude と偽の gh が PATH の先頭に無いので、テストを止める: %s\n' "$(command -v claude)" >&2
        exit 1
    fi
}

# 偽の powershell.exe・launchctl・crontab のうち、名前を挙げたものを PATH の先頭に置く: os_fake <名前>...
os_fake() {
    mkdir -p "$BIN-os"
    local name
    for name in "$@"; do write_fake_os "$BIN-os/$name"; done
    case ":$PATH:" in *":$BIN-os:"*) ;; *) PATH="$BIN-os:$PATH" ;; esac
    export PATH
}

# 偽の claude が次に返す JSON を置く: claude_returns <JSON> [<眠る秒数> [<終了コード>]]
claude_returns() {
    local d="$FAKE/claude" k
    k=$(($(cat "$d/queued" 2>/dev/null || echo 0) + 1))
    printf '%s\n' "$k" >"$d/queued"
    printf '%s\n' "$1" >"$d/$k.json"
    if [ -n "${2-}" ]; then printf '%s\n' "$2" >"$d/$k.sleep"; fi
    if [ -n "${3-}" ]; then printf '%s\n' "$3" >"$d/$k.exit"; fi
}
# 偽の claude が次に返す、形に合う JSON を structured_output に持つ成功の結果を置く: claude_ok <JSON> [<眠る秒数>]
claude_ok() {
    claude_returns "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":2,\"result\":\"\",\"structured_output\":$1,\"api_error_status\":null,\"terminal_reason\":\"completed\"}" "${2-}"
}
# 偽の claude が次に返す、is_error が真の結果を置く: claude_error <subtype> [<api_error_status>]
claude_error() {
    claude_returns "{\"type\":\"result\",\"subtype\":\"$1\",\"is_error\":true,\"num_turns\":1,\"result\":\"\",\"api_error_status\":${2:-null},\"terminal_reason\":\"error\"}"
}
# 偽の claude が呼ばれた回数を出す
claude_calls() { cat "$FAKE/claude/count" 2>/dev/null || printf 0; }
# 偽の claude の n 回目の呼び出しの引数を、1行に1つずつ出す: claude_args <n>
claude_args() { perl -MJSON::PP -e 'open my $f, "<", $ARGV[0] or exit 1; local $/; print map { "$_\n" } @{ JSON::PP->new->decode(<$f>) }' "$FAKE/claude/$1.args.json"; }
# 偽の claude の n 回目の呼び出しの標準入力を出す: claude_stdin <n>
claude_stdin() { cat "$FAKE/claude/$1.stdin"; }
# 偽の claude の n 回目の呼び出しが受けた環境変数の値を出す。無ければ <unset> を出す: claude_env <n> <名前>
claude_env() { perl -MJSON::PP -e 'open my $f, "<", $ARGV[0] or exit 1; local $/; my $e = JSON::PP->new->decode(<$f>); print exists $e->{$ARGV[1]} ? $e->{$ARGV[1]} : "<unset>"' "$FAKE/claude/$1.env.json" "$2"; }

# 偽の gh が返す JSON を置く: gh_issue <番号> <JSON>、gh_pr <番号> <JSON>、gh_issue_list <JSON>
gh_issue() { printf '%s\n' "$2" >"$FAKE/gh/issue-$1.json"; }
gh_pr() { printf '%s\n' "$2" >"$FAKE/gh/pr-$1.json"; }
gh_issue_list() { printf '%s\n' "$1" >"$FAKE/gh/issue-list.json"; }
# 偽の gh と、偽の powershell.exe・launchctl・crontab が受けた引数を、呼び出しごとに1行の JSON の配列で出す:
# gh_calls、os_calls <名前>
gh_calls() { cat "$FAKE/gh/calls.jsonl" 2>/dev/null; }
os_calls() { cat "$FAKE/os/$1.calls.jsonl" 2>/dev/null; }

# 場所を、Claude Code が会話の記録の cwd と file_path に書く形で出す: tpath <場所> [win|posix]
# win は、Git Bash で pwd -W が返す C:/... の区切りを \ に替えた C:\... の形である。pwd -W の無い環境では、win でも posix の形を出す。
# 場所はあらかじめ作っておく。ファイルの場所は、ディレクトリの部分だけを pwd -W で求める
tpath() {
    local p=$1 dir base
    if [ "${2:-win}" = posix ] || ! (cd / && pwd -W >/dev/null 2>&1); then
        printf '%s' "$p"
        return
    fi
    if [ -d "$p" ]; then
        dir=$p
        base=
    else
        dir=$(dirname "$p")
        base="/${p##*/}"
    fi
    printf '%s%s' "$(cd "$dir" && pwd -W)" "$base" | sed 's|/|\\|g'
}
# 文字列を JSON の文字列の形で出す: jstr <文字列>
jstr() { perl -MJSON::PP -e 'print JSON::PP->new->allow_nonref->encode($ARGV[0])' "$1"; }
# 偽の会話の記録に1行の JSON を足す: transcript_line <記録の置き場所> <会話の ID> <JSON>
transcript_line() { printf '%s\n' "$3" >>"$1/$2.jsonl"; }

# ディレクトリの中のファイルの名前と中身の検査和を出す。ディレクトリが無ければ absent を出す: sig_dir <ディレクトリ>
sig_dir() {
    if [ -z "$1" ] || [ ! -d "$1" ]; then
        printf 'absent\n'
        return
    fi
    (cd "$1" && find . -type f -exec cksum {} + | LC_ALL=C sort -k3)
}
# 偽のホームの外のファイルの名前と中身の検査和を出す。偽のホームと、偽のコマンドの書き残しと、点検の状態の場所は除く。
# git が状態の確かめで書き直す index も除く。所有者の本物のメモリのディレクトリと、本物の点検の状態の場所も加える
outside_sig() {
    (
        cd "$CASE" || exit 1
        find . \( -path ./home -o -path ./fake -o -path ./repo/.git/keirekipro-memory-inspection \
            -o -path ./repo/.git/index -o -path './repo/.git/worktrees/*/index' \) -prune \
            -o -type f -exec cksum {} + | LC_ALL=C sort -k3
    )
    printf 'real-memory:\n'
    sig_dir "$REAL_MEMDIR"
    printf 'real-state:\n'
    sig_dir "$REAL_STATE"
}

# ---------------------------------------------------------------------
# 土台のテスト
# ---------------------------------------------------------------------

newcase fake-claude
claude_returns '{"n":1}'
claude_returns '{"n":2}'
out1=$(printf 'first input\n' | claude -p --tools "" --json-schema '{"a": 1}' 'with space')
out2=$(printf 'second\ninput\n' | FOO_FOR_TEST=bar claude -p --max-turns 4)
check "偽の claude が置いた JSON を順に返し、受けた引数と標準入力を書き残す" \
    "$out1|$out2|$(claude_calls)|$(claude_args 1 | tr '\n' '|')|$(claude_stdin 1)|$(claude_stdin 2 | tr '\n' '|')|$(claude_env 2 FOO_FOR_TEST)|$(claude_env 1 FOO_FOR_TEST)" \
    '{"n":1}|{"n":2}|2|-p|--tools||--json-schema|{"a": 1}|with space||first input|second|input||bar|<unset>'

newcase fake-claude-fail
claude_error error_max_turns 529
claude_returns '{"late":true}' 1
claude_returns '{"exit":7}' "" 7
o1=$(claude -p </dev/null)
start=$(date +%s)
o2=$(claude -p </dev/null)
slept=$(($(date +%s) - start))
o3=$(claude -p </dev/null)
e3=$?
claude -p </dev/null >/dev/null 2>&1
e4=$?
check "偽の claude が、置いたときに is_error が真の結果を返し、眠ってから返し、置いた終了コードで終わり、置いていない回は失敗する" \
    "$(printf '%s' "$o1" | perl -MJSON::PP -e 'local $/; my $j = decode_json(<STDIN>); print(($j->{is_error} ? "err" : "ok"), " $j->{subtype} $j->{api_error_status}")')|$o2|$([ "$slept" -ge 1 ] && echo slept)|$o3 $e3|$e4" \
    'err error_max_turns 529|{"late":true}|slept|{"exit":7} 7|1'

newcase fake-claude-kill
claude_returns '{"slow":true}' 30
(
    claude -p </dev/null | cat >"$CASE/slow.out"
    printf 'done\n' >"$CASE/slow.done"
) &
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$FAKE/claude/1.pid" ] && [ -f "$FAKE/claude/1.env.json" ] && break; sleep 1; done
kill -TERM "$(cat "$FAKE/claude/1.pid")" 2>/dev/null
for _ in 1 2 3 4 5; do [ -f "$CASE/slow.done" ] && break; sleep 1; done
check "眠っている偽の claude を止めると、眠りの終わりを待たずに標準出力が閉じる" "$(cat "$CASE/slow.done" 2>/dev/null)|$(cat "$CASE/slow.out")" "done|"
wait

newcase fake-gh
gh_issue 12 '{"number":12,"state":"OPEN"}'
gh_pr 34 '{"number":34,"state":"MERGED"}'
gh_issue_list '[{"number":5}]'
g1=$(gh issue view 12 --json number,state)
g2=$(gh pr view 34 --json number)
g3=$(gh issue list --state all --search 'a b' --limit 20)
gh issue view 99 >/dev/null 2>&1
g4=$?
check "偽の gh が置いた Issue と PR の JSON を返し、受けた引数を書き残し、置いていない番号には失敗する" \
    "$g1|$g2|$g3|$g4|$(gh_calls | tr '\n' '|')" \
    '{"number":12,"state":"OPEN"}|{"number":34,"state":"MERGED"}|[{"number":5}]|1|["issue","view","12","--json","number,state"]|["pr","view","34","--json","number"]|["issue","list","--state","all","--search","a b","--limit","20"]|["issue","view","99"]|'

newcase fake-os
before=$(command -v crontab || printf none)
os_fake crontab launchctl powershell.exe
crontab -l
launchctl bootstrap "gui/501" /tmp/x.plist
powershell.exe -NoProfile -Command 'Get-Date'
check "偽の crontab・launchctl・powershell.exe は、os_fake で求めたあとだけ PATH の先頭にあり、受けた引数を書き残す" \
    "$([ "$before" != "$BIN-os/crontab" ] && echo before-real)|$(command -v crontab)|$(os_calls crontab)|$(os_calls launchctl)|$(os_calls powershell.exe)" \
    "before-real|$BIN-os/crontab|[\"-l\"]|[\"bootstrap\",\"gui/501\",\"/tmp/x.plist\"]|[\"-NoProfile\",\"-Command\",\"Get-Date\"]"

newcase fake-repo
check "偽のリポジトリは origin/main を持ち、worktree の git の共通ディレクトリが本体の .git であり、メモリと会話の記録の置き場所が偽のホームの中にある" \
    "$(gitq rev-parse origin/main >/dev/null 2>&1 && echo origin)|$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir)|$(git -C "$WT" rev-parse --abbrev-ref HEAD)|$([ -d "$MEMDIR" ] && echo mem)|$([ -d "$WTTRANSDIR" ] && echo wttrans)|$HOME|$USERPROFILE|$KP_MEMORY_INSPECTION_NOW" \
    "origin|$REPO/.git|feat/wt1|mem|wttrans|$FHOME|$FHOME|2026-11-02T10:00:00+09:00"

if (cd / && pwd -W >/dev/null 2>&1); then
    mkdir -p "$WT/sub"
    transcript_line "$WTTRANSDIR" s1 "{\"cwd\":$(jstr "$(tpath "$WT/sub")"),\"file_path\":$(jstr "$(tpath "$MEMDIR/MEMORY.md")")}"
    got=$(perl -MJSON::PP -ne 'my $j = decode_json($_); print "$j->{cwd}|$j->{file_path}"' "$WTTRANSDIR/s1.jsonl")
    want="$(cd "$WT/sub" && pwd -W | sed 's|/|\\|g')|$(cd "$MEMDIR" && pwd -W | sed 's|/|\\|g')\\MEMORY.md"
    check "偽の会話の記録の cwd と file_path を、C:\\ の区切りの形で作れる" "$got|$(printf '%s' "$got" | grep -c '^[A-Za-z]:[\]')" "$want|1"
else
    check "pwd -W の無い環境では、tpath が posix の形のままの場所を出す" "$(tpath "$WT")|$(tpath "$MEMDIR/MEMORY.md" posix)" "$WT|$MEMDIR/MEMORY.md"
fi

newcase outside
sig_before=$(outside_sig)
claude_returns '{"n":1}'
printf 'x\n' | claude -p >/dev/null
gh issue view 1 >/dev/null 2>&1
printf -- '- [a](a.md) — a\n' >"$MEMDIR/MEMORY.md"
mkdir -p "$STATE/runs/x"
printf '{}\n' >"$STATE/runs/x/record.json"
git -C "$WT" status --porcelain >/dev/null
gitq status --porcelain >/dev/null
check "偽のホームの外のファイルが変わらない" "$(outside_sig)" "$sig_before"

# ---------------------------------------------------------------------
# 入口のスクリプトの骨組みと、場所の求め方
# ---------------------------------------------------------------------

# JSON の1行から、bin.claude・bin.gh・bin.bash・path を | でつないで出す。欄が無ければ undef と出す
tool_fields() {
    perl -MJSON::PP -e 'my $j = JSON::PP->new->decode(do { local $/; <STDIN> });
        print join("|", map { defined $_ ? $_ : "undef" } $j->{bin}{claude}, $j->{bin}{gh}, $j->{bin}{bash}, $j->{path})'
}

newcase tools
got=$(bash -c '. "$1" && tool_paths' _ "$SH" | tool_fields)
check "claude gh bash の場所と今の PATH を返す" "$got" "$BIN/claude|$BIN/gh|$(command -v bash)|$PATH"
# gh だけが見つからない PATH を作る。perl と bash は、本物を呼ぶ小さなスクリプトを置く
MIN="$TMP_ROOT/tools/min"
mkdir -p "$MIN"
cp "$BIN/claude" "$MIN/claude"
for t in perl bash; do
    printf '#!%s\nexec %s "$@"\n' "$(command -v bash)" "$(command -v "$t")" >"$MIN/$t"
    chmod +x "$MIN/$t"
done
got=$(bash -c '. "$1" && PATH=$2 && tool_paths' _ "$SH" "$MIN" | tool_fields)
check "claude gh bash の場所と今の PATH を返し、見つからないコマンドの場所を空にして返す" "$got" "$MIN/claude||$MIN/bash|$MIN"

newcase locate
want=$(printf '%s\n%s\n%s' "$REPO" "$STATE" "$MEMDIR")
from_main=$(cd "$REPO" && perl "$PL" paths "$REPO/.claude/scripts/memory")
from_wt=$(cd "$CASE" && perl "$WTPL" paths)
from_wt_sh=$(cd "$WT" && bash -c '. "$1" && locate && printf "%s\n%s\n%s\n" "$MAIN" "$STATE" "$MEMDIR"' _ "$WTSH")
# do で読み込んだ memory-inspect.pl は何も出さず、関数を直に呼べる
from_wt_do=$(cd "$CASE" && perl -e 'do $ARGV[0]; die $@ if $@; print main_worktree($ARGV[1]), "\n", state_dir($ARGV[1]), "\n", memory_dir(main_worktree($ARGV[1]))' "$WTPL" "$WT")
check "worktree の中から求めても、本体の作業フォルダと状態の場所が本体から求めたときと同じになる" \
    "$from_main#$from_wt#$from_wt_sh#$from_wt_do" "$want#$want#$want#$want"

newcase "mem.dir_x 日本"
got=$(perl "$PL" paths "$REPO" | sed -n 3p)
check "メモリのディレクトリの名前が、本体の作業フォルダの場所の英数字でない文字を - に替えた名前になる" \
    "$got" "$FHOME/.claude/projects/$(encname "$WORK")-mem-dir-x----repo/memory"

newcase usage
out=$(bash "$SH" nosuch 2>&1)
rc=$?
bash "$SH" >/dev/null 2>&1
rc_none=$?
check "知らないサブコマンドに終了コード 2 で終わる" \
    "$rc|$(printf '%s\n' "$out" | grep -c 'nosuch')|$(printf '%s\n' "$out" | grep -c '^  missed <汚染の種類>')|$rc_none|$([ -d "$STATE" ] && echo made)" \
    "2|1|1|2|"

newcase gitstatus
(cd "$WT" && bash -c '. "$1" && locate && ensure_state && printf "{}\n" >"$STATE/config.json" &&
    mkdir -p "$STATE/runs/x" && printf "r\n" >"$STATE/runs/x/report.md"' _ "$WTSH")
check "状態の場所が git status に出ない" \
    "$([ -f "$STATE/config.json" ] && echo made)|$(gitq status --porcelain --untracked-files=all)|$(git -C "$WT" status --porcelain --untracked-files=all)" \
    "made||"

# ---------------------------------------------------------------------
# 会話の記録を読む部品
# ---------------------------------------------------------------------

SINCE="2026-10-01T00:00:00Z"
AFTER="2026-10-20T00:00:00.000Z"

# 場所の区切りの / を \ に替えて出す: bspath <場所>
bspath() { printf '%s' "$1" | sed 's|/|\\|g'; }
# 場所の英字を大文字にして出す: upath <場所>
upath() { perl -e 'print uc $ARGV[0]' "$1"; }
# 場所の C:/ の形を /c/ の形にして出す。ドライブの文字が無い場所はそのまま出す: drivepath <場所>
drivepath() { printf '%s' "$1" | perl -pe 's{\A([A-Za-z]):}{"/" . lc $1}e'; }
# 道具の呼び出しの行を、会話の記録に足す: tool_line <記録の置き場所> <会話の ID> <cwd> <時刻> <道具の名前> <file_path>
tool_line() {
    transcript_line "$1" "$2" "{\"type\":\"assistant\",\"cwd\":$(jstr "$3"),\"timestamp\":\"$4\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"$5\",\"input\":{\"file_path\":$(jstr "$6")}}]}}"
}
# 利用者の行を、会話の記録に足す: user_line <記録の置き場所> <会話の ID> <cwd> <時刻> <content の JSON> [<ほかの欄の JSON>]
user_line() {
    transcript_line "$1" "$2" "{\"type\":\"user\",\"cwd\":$(jstr "$3"),\"timestamp\":\"$4\",${6:+$6,}\"message\":{\"role\":\"user\",\"content\":$5}}"
}
# writes を、時刻 SINCE と偽のメモリのディレクトリで流す: scan_writes <ファイル名>...
scan_writes() { perl "$TS" writes --since "$SINCE" --memory-dir "$MEMDIR" "$@"; }
# utterances の結果の JSON から、記録があったかと、文ごとの「時刻=文」を | でつないで出す
utter_fields() {
    perl -MJSON::PP -e 'binmode STDOUT, ":encoding(UTF-8)"; my $j = JSON::PP->new->utf8->decode(do { local $/; <STDIN> });
        print $j->{found} ? "found" : "none", map { "|$_->{at}=$_->{text}" } @{ $j->{utterances} || [] }'
}
# utterances の結果の JSON が20KBに収まるかと、切ったかと、文の数と、文ごとに、元の文
# (<番号><文字>×<数>)のままか、元の文の頭の部分かを、| でつないで出す: limit_fields <文字> <数>
limit_fields() {
    perl -CA -MJSON::PP -e 'my $raw = do { local $/; <STDIN> }; $raw =~ s/\n\z//; my $j = JSON::PP->new->utf8->decode($raw);
        my @u = @{ $j->{utterances} };
        print join("|", length($raw) <= 20480 ? "fits" : "over", $j->{truncated} ? "truncated" : "whole", scalar(@u),
            map { my $t = $u[$_]{text}; my $full = ($_ + 1) . $ARGV[0] x $ARGV[1];
                $t eq $full ? "full" : length($t) && index($full, $t) == 0 ? "part" : "bad" } 0 .. $#u)' "$@"
}

newcase scan-writes
c=$(tpath "$REPO")
tool_line "$TRANSDIR" s1 "$c" "$AFTER" Write "$(bspath "$MEMDIR/a.md")"
tool_line "$TRANSDIR" s1 "$c" "$AFTER" Edit "$(upath "$MEMDIR/b.md")"
tool_line "$TRANSDIR" s1 "$c" "$AFTER" MultiEdit "$MEMDIR/c.md"
tool_line "$TRANSDIR" s1 "$c" "$AFTER" Read "$MEMDIR/d.md"
tool_line "$TRANSDIR" s1 "$c" "$AFTER" Write "$CASE/e.md"
check "Write と Edit と MultiEdit の呼び出しを、パスの区切りと大文字と小文字をそろえて見つける" \
    "$(scan_writes a.md b.md c.md d.md e.md)" '{"a.md":true,"b.md":true,"c.md":true,"d.md":false,"e.md":false}'

tool_line "$TRANSDIR" s2 "$c" "2026-09-30T23:59:59Z" Write "$MEMDIR/f.md"
tool_line "$TRANSDIR" s3 "$c" "$AFTER" Write "$MEMDIR/g.md"
touch -t 202609010000 "$TRANSDIR/s3.jsonl"
check "時刻より前の書き換えと、時刻より前に更新された記録の書き換えを数えない" "$(scan_writes f.md g.md)" '{"f.md":false,"g.md":false}'

mkdir -p "$TRANSDIR/s1/subagents"
tool_line "$TRANSDIR/s1/subagents" agent-x "$c" "$AFTER" Write "$MEMDIR/h.md"
check "サブエージェントの記録の書き換えも見つける" "$(scan_writes h.md)" '{"h.md":true}'

newcase scan-cwd
mkdir -p "$WT/sub"
tool_line "$WTTRANSDIR" s1 "$(tpath "$WT/sub")" "$AFTER" Write "$(tpath "$MEMDIR/a.md")"
user_line "$TRANSDIR" s2 "$(tpath "$REPO")" "$AFTER" '"はい"'
check "cwd が C:\\ の形で書かれた記録を、本体の作業フォルダの記録として使う" \
    "$(scan_writes a.md)|$(perl "$TS" utterances s2 | utter_fields)" "{\"a.md\":true}|found|$AFTER=はい"

newcase scan-drive
tool_line "$TRANSDIR" s1 "$(tpath "$REPO")" "$AFTER" Write "$(tpath "$MEMDIR/a.md")"
check "file_path が C:\\ の形で、メモリのディレクトリが /c/ の形でも、同じファイルとして見つける" \
    "$(perl "$TS" writes --since "$SINCE" --memory-dir "$(drivepath "$MEMDIR")" a.md)" '{"a.md":true}'

newcase scan-other
mkdir -p "$CASE/other" "$CASE/repox"
tool_line "$TRANSDIR" s1 "$(tpath "$CASE/other")" "$AFTER" Write "$MEMDIR/a.md"
tool_line "$TRANSDIR" s1 "$(tpath "$CASE/repox")" "$AFTER" Write "$MEMDIR/b.md"
user_line "$TRANSDIR" s2 "$(tpath "$CASE/other")" "$AFTER" '"ほかの文"'
check "cwd がほかのプロジェクトの記録を使わない" \
    "$(scan_writes a.md b.md)|$(perl "$TS" utterances s2)" '{"a.md":false,"b.md":false}|{"found":false}'

newcase scan-similar
mkdir -p "$CASE/repox" "$CASE/repo-x"
# repox のディレクトリの名前は、本体の名前の後ろに x が続く。repo-x のディレクトリの名前は、本体の名前の後ろに - が続く
d1="$FHOME/.claude/projects/$(encname "$CASE/repox")"
d2="$FHOME/.claude/projects/$(encname "$CASE/repo-x")"
mkdir -p "$d1" "$d2"
tool_line "$d1" s1 "$(tpath "$REPO")" "$AFTER" Write "$MEMDIR/a.md"
tool_line "$d2" s2 "$(tpath "$CASE/repo-x")" "$AFTER" Write "$MEMDIR/b.md"
user_line "$d1" s3 "$(tpath "$REPO")" "$AFTER" '"似た名前の文"'
check "名前が似たほかのプロジェクトのディレクトリの記録を使わない" \
    "$(scan_writes a.md b.md)|$(perl "$TS" utterances s3)" '{"a.md":false,"b.md":false}|{"found":false}'

newcase scan-utter
c=$(tpath "$REPO")
user_line "$TRANSDIR" s1 "$c" "2026-10-20T00:00:01Z" '"最初の文"' '"origin":{"kind":"human"},"promptSource":"typed"'
user_line "$TRANSDIR" s1 "$c" "2026-10-20T00:00:02Z" '[{"type":"tool_result","tool_use_id":"t1","content":"道具の結果"}]'
user_line "$TRANSDIR" s1 "$c" "2026-10-20T00:00:03Z" '"メタの文"' '"isMeta":true'
user_line "$TRANSDIR" s1 "$c" "2026-10-20T00:00:04Z" '"<task-notification>終わった</task-notification>"' '"origin":{"kind":"task-notification"}'
user_line "$TRANSDIR" s1 "$c" "2026-10-20T00:00:05Z" '"<system-reminder>知らせ</system-reminder>"'
user_line "$TRANSDIR" s1 "$c" "2026-10-20T00:00:06Z" '"This session is being continued"' '"isCompactSummary":true,"isVisibleInTranscriptOnly":true'
user_line "$TRANSDIR" s1 "$c" "2026-10-20T00:00:07Z" '"ほかの会話からの文"' '"origin":{"kind":"peer"}'
tool_line "$TRANSDIR" s1 "$c" "2026-10-20T00:00:08Z" Write "$MEMDIR/a.md"
user_line "$TRANSDIR" s1 "$c" "2026-10-20T00:00:09Z" '"<command-message>start</command-message>"'
check "utterances が道具の結果と isMeta の行と差し込まれた知らせの行を返さない" "$(perl "$TS" utterances s1 | utter_fields)" \
    "found|2026-10-20T00:00:01Z=最初の文|2026-10-20T00:00:09Z=<command-message>start</command-message>"

newcase scan-limit
c=$(tpath "$REPO")
for i in 1 2 3; do user_line "$TRANSDIR" s1 "$c" "$AFTER" "\"$i$(perl -e 'print "あ" x 3000')\""; done
user_line "$TRANSDIR" s2 "$c" "$AFTER" "\"1$(perl -e 'print "い" x 10000')\""
check "utterances が1件を20KBまでで切る" \
    "$(perl "$TS" utterances s1 | limit_fields あ 3000)/$(perl "$TS" utterances s2 | limit_fields い 10000)" \
    "fits|truncated|3|full|full|part/fits|truncated|1|part"

newcase scan-none
got=$(perl "$TS" utterances nosuch)
check "記録の無い会話に記録が無いと返す" "$got|$?" '{"found":false}|0'

newcase scan-config
cfgdir="$CASE/cfg/projects/$(encname "$REPO")"
mkdir -p "$cfgdir"
tool_line "$cfgdir" s1 "$(tpath "$REPO")" "$AFTER" Write "$MEMDIR/a.md"
tool_line "$TRANSDIR" s2 "$(tpath "$REPO")" "$AFTER" Write "$MEMDIR/b.md"
user_line "$cfgdir" s3 "$(tpath "$REPO")" "$AFTER" '"設定の下の文"'
check "CLAUDE_CONFIG_DIR があればその下の記録を読む" \
    "$(CLAUDE_CONFIG_DIR="$CASE/cfg" scan_writes a.md b.md)|$(CLAUDE_CONFIG_DIR="$CASE/cfg" perl "$TS" utterances s3 | utter_fields)" \
    "{\"a.md\":true,\"b.md\":false}|found|$AFTER=設定の下の文"

newcase scan-broken
c=$(tpath "$REPO")
printf 'not json\n{"type":"assistant",\n\n[1,2]\n{"cwd":["x"]}\n' >>"$TRANSDIR/s1.jsonl"
tool_line "$TRANSDIR" s1 "$c" "$AFTER" Write "$MEMDIR/a.md"
printf '\377\376 broken\n' >>"$TRANSDIR/s1.jsonl"
user_line "$TRANSDIR" s1 "$c" "$AFTER" '"読める文"'
check "読めない行を飛ばす" "$(scan_writes a.md)|$(perl "$TS" utterances s1 | utter_fields)" "{\"a.md\":true}|found|$AFTER=読める文"

# ---------------------------------------------------------------------
# 点検のロックとメモリのロック
# ---------------------------------------------------------------------

# 今のプロセスの番号を出す。Windows では、Git Bash の /proc/<番号>/winpid から読んだ Windows のプロセスの番号を出す
self_pid() { cat "/proc/$$/winpid" 2>/dev/null || printf '%s\n' "$$"; }
# もう無いプロセスの番号を出す。番号を出して終わった bash の番号である
dead_pid() { bash -c 'cat "/proc/$$/winpid" 2>/dev/null || printf "%s\n" "$$"'; }
# ロックを取る: lock_take <run|memory> <回の ID> <プロセスの番号>。出力と終了コードを「出力|終了コード」で出す
lock_take() {
    local out rc
    out=$(perl "$PL" lock take "$@")
    rc=$?
    printf '%s|%s' "$out" "$rc"
}
lock_state() { perl "$PL" lock state "$1"; }
# ロックの owner に書かれた欄を出す: lock_owner <run|memory>
lock_owner() {
    perl -MJSON::PP -e 'open my $f, "<", $ARGV[0] or exit 1; local $/; my $o = JSON::PP->new->decode(<$f>);
        print join("|", map { defined $_ ? $_ : "undef" } @$o{qw(pid run taken_at)})' "$STATE/locks/$1/owner"
}
# 今の時刻(newcase の KP_MEMORY_INSPECTION_NOW)から秒をずらした ISO 8601 の時刻を出す: shifted_now <秒>
NOW_EPOCH=$(perl -MTime::Local -e 'print timegm(0, 0, 1, 2, 10, 2026)')
shifted_now() { perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($ARGV[0] + $ARGV[1]))' "$NOW_EPOCH" "$1"; }
# ディレクトリの更新の時刻を、今の時刻から秒だけ前にする: age_dir <ディレクトリ> <秒>
age_dir() { perl -e 'my $t = $ARGV[1] - $ARGV[2]; utime $t, $t, $ARGV[0] or exit 1' "$1" "$NOW_EPOCH" "$2"; }

newcase lock-alive
alive=$(self_pid)
first=$(lock_take run r1 "$alive")
owner=$(lock_owner run)
second=$(lock_take run r2 "$alive")
state=$(lock_state run)
perl "$PL" lock release run r2
after_other=$(lock_state run)
perl "$PL" lock release run r1
check "生きているプロセスのロックを古いとみなさない" \
    "$first#$owner#$second#$state#$after_other#$(lock_state run)#$([ -d "$STATE/locks/run" ] && echo left)" \
    "taken|0#$alive|r1|2026-11-02T01:00:00Z#held r1|3#held r1#held r1#free#"

newcase lock-dead
gone=$(dead_pid)
lock_take run r1 "$gone" >/dev/null
state=$(lock_state run)
second=$(lock_take run r2 "$(self_pid)")
check "owner のプロセスが無いロックを古いとみなし、外して取る" \
    "$state#$second#$(lock_owner run)" "stale r1#taken|0#$(self_pid)|r2|2026-11-02T01:00:00Z"

newcase lock-old
lock_take run r1 "$(self_pid)" >/dev/null
at89=$(KP_MEMORY_INSPECTION_NOW=$(shifted_now 5340) lock_state run)
at91=$(KP_MEMORY_INSPECTION_NOW=$(shifted_now 5460) lock_state run)
second=$(KP_MEMORY_INSPECTION_NOW=$(shifted_now 5460) lock_take run r2 "$(self_pid)")
check "取った時刻から90分を過ぎたロックを古いとみなす" \
    "$at89#$at91#$second#$(lock_owner run)" "held r1#stale r1#taken|0#$(self_pid)|r2|$(shifted_now 5460)"

newcase lock-noowner
mkdir -p "$STATE/locks/run"
age_dir "$STATE/locks/run" 30
young=$(lock_state run)
young_take=$(lock_take run r2 "$(self_pid)")
age_dir "$STATE/locks/run" 61
old=$(lock_state run)
old_take=$(lock_take run r2 "$(self_pid)")
check "owner の無いロックは、作られてから1分以内なら古いとみなさず、1分を過ぎれば古いとみなす" \
    "$young#$young_take#$old#$old_take#$(lock_owner run)" "held #held |3#stale #taken|0#$(self_pid)|r2|2026-11-02T01:00:00Z"

newcase lock-memory
first=$(lock_take memory r1 "$(self_pid)")
second=$(lock_take memory r2 "$(self_pid)")
run_state=$(lock_state run)
perl "$PL" lock release memory r1
gone=$(dead_pid)
lock_take memory r3 "$gone" >/dev/null
check "メモリのロックも、点検のロックと別の場所に同じ決まりで取って外す" \
    "$first#$second#$run_state#$(lock_state memory)#$(lock_take memory r4 "$(self_pid)")" \
    "taken|0#held r1|3#free#stale r3#taken|0"

newcase lock-sh
# 入口のスクリプトを読み込んだ bash が、ロックを取り、自分のプロセスの番号を出し、生きている間に2つ目の回でロックを取ろうとする
inner=$(bash -c '. "$1" && run_lock_take r1 >/dev/null || exit 1
    me=$(cat "/proc/$$/winpid" 2>/dev/null || printf "%s" "$$")
    out=$(run_lock_take r2)
    printf "%s#%s|%s" "$me" "$out" "$?"' _ "$SH")
inner_pid=${inner%%#*}
sh_owner=$(lock_owner run)
after_exit=$(lock_state run)
bash -c '. "$1" && run_lock_release r1' _ "$SH"
check "入口のスクリプトは、自分のプロセスの番号で点検のロックを取り、取られていれば回の ID を出して終了コード 3 を返す" \
    "$inner#$sh_owner#$after_exit#$(lock_state run)" "$inner_pid#held r1|3#$inner_pid|r1|2026-11-02T01:00:00Z#stale r1#free"

newcase lock-usage
perl "$PL" lock take run r1 >/dev/null 2>&1
rc_args=$?
perl "$PL" lock take other r1 1 >/dev/null 2>&1
rc_kind=$?
perl "$PL" lock take run 'a/b' 1 >/dev/null 2>&1
rc_id=$?
check "ロックの引数の誤りに終了コード 2 で終わる" "$rc_args|$rc_kind|$rc_id|$([ -d "$STATE/locks" ] && echo made)" "2|2|2|"

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
