#!/bin/bash
# =====================================================================
# extract.pl(会話の記録から数と名前だけを抜き出す部品)のテスト
#
# 実行: bash .claude/scripts/usage/tests/test-extract.sh
# HOME を一時フォルダに替え、その下の .claude/projects に作り物の会話の記録を置いて、
# extract.pl --all を呼ぶ。本物の会話の記録と本物の記録の置き場所は読まず、書かない。
# 一時的な git のリポジトリ(本体)と worktree を作り、git worktree list の見分けに使う。
# Windows の場所の見分けは、git worktree list だけを差し替える偽物の git で確かめる。
# 前提: bash・perl(JSON::PP)・git。
# =====================================================================
set -u

EXTRACT="$(cd "$(dirname "$0")/.." && pwd)/extract.pl"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# git が返すパス(Windows では C:/...)と同じ形で比べられるようにする
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

# Windows の Git Bash では USERPROFILE も記録の置き場所の候補になるので、両方を替える
HOME="$WORK/home"
USERPROFILE="$HOME"
# デスクトップアプリの手元の記録の置き場所の候補も、本物を読まないように替える
LOCALAPPDATA="$HOME/AppData/Local"
export HOME USERPROFILE LOCALAPPDATA
PROJ="$HOME/.claude/projects"
mkdir -p "$PROJ"

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }

# JSON のファイルの欄の値を1つ読む。$1 はファイル、$2 は欄の名前
jfile() {
    perl -MJSON::PP -e 'local $/; open my $f, "<", $ARGV[1] or do { print "nofile"; exit }; my $d = JSON::PP->new->utf8->decode(<$f>); my $v = $d->{$ARGV[0]}; print defined $v ? $v : "undef"' "$2" "$1"
}
# 抜き出した記録の、k が $2 の行の数。ファイルが無ければ nofile
kcount() {
    [ -f "$1" ] || { printf 'nofile'; return; }
    perl -MJSON::PP -ne 'BEGIN { $want = shift; $n = 0 } my $d = eval { decode_json($_) }; $n++ if $d && ($d->{k} // "") eq $want; END { print $n }' "$2" <"$1"
}
fsize() { perl -e 'print -s $ARGV[0]' "$1"; }
# 抜き出した記録の、k が $2 の行のうち $3 番目(1から)の行の、欄 $4 の値。真偽は true か false
kfield() {
    [ -f "$1" ] || { printf 'nofile'; return; }
    perl -MJSON::PP -ne 'BEGIN { ($want, $nth, $field) = splice @ARGV, 0, 3; $i = 0; binmode STDOUT, ":utf8" } my $d = eval { decode_json($_) } or next; next unless ($d->{k} // "") eq $want; next unless ++$i == $nth; my $v = $d->{$field}; print !defined $v ? "undef" : JSON::PP::is_bool($v) ? ($v ? "true" : "false") : $v; END { print "noline" if $i < $nth }' "$2" "$3" "$4" <"$1"
}

# 作り物の会話の記録を書く: mkrec <ファイル> <cwd> <cwd の無い行の数>
# 最初に cwd の無い行を置き、cwd を持つ user の行と assistant の行を続ける
mkrec() {
    mkdir -p "$(dirname "$1")"
    perl -MJSON::PP -e '
        my ($file, $cwd, $n) = @ARGV;
        utf8::decode($cwd);
        my $j = JSON::PP->new->utf8->canonical;
        (my $sid = $file) =~ s{.*/}{}; $sid =~ s{\.jsonl$}{};
        open my $f, ">", $file or die "$file: $!";
        print $f $j->encode({type => "permission-mode", permissionMode => "default", sessionId => $sid}), "\n" for 1 .. $n;
        print $f $j->encode({type => "user", cwd => $cwd, sessionId => $sid, timestamp => "2026-10-26T00:00:00.000Z", message => {role => "user", content => "hi"}}), "\n";
        print $f $j->encode({type => "assistant", cwd => $cwd, sessionId => $sid, timestamp => "2026-10-26T00:00:01.000Z", message => {id => "m1", model => "claude-opus-5-5", content => [], usage => {input_tokens => 1, output_tokens => 1}}}), "\n";
    ' "$1" "$2" "$3"
}
# 行を足す: addline <ファイル> <行>(改行を付ける)
addline() { printf '%s\n' "$2" >>"$1"; }

# --- 本体のリポジトリと、本体の外の worktree
REPO="$WORK/repo"
git init -q "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
OUTWT="$WORK/outside-wt"
git -C "$REPO" worktree add -q -b wt1 "$OUTWT" 2>/dev/null
OUTWT=$(git -C "$REPO" worktree list --porcelain | sed -n 's/^worktree //p' | grep -v "^$REPO\$" | head -n 1)

STATE="$WORK/state"
EX="$STATE/extract"
run_all() { perl "$EXTRACT" --state "$STATE" --all --skip-locked --repo "$REPO"; }

D="$PROJ/proj-a"
mkrec "$D/s-main.jsonl" "$REPO" 3
mkrec "$D/s-sub.jsonl" "$REPO/frontend/src" 0
mkrec "$D/s-outwt.jsonl" "$OUTWT" 2
mkrec "$D/s-gone.jsonl" "$REPO/.claude/worktrees/gone-worktree" 1
mkrec "$PROJ/proj-b/s-other.jsonl" "$WORK/other" 0
mkrec "$PROJ/proj-b/s-prefix.jsonl" "${REPO}-other" 0
# 最初の cwd は外で、あとの行の cwd が本体のもの: 最初の cwd で決まるので抜き出さない
mkrec "$PROJ/proj-b/s-later.jsonl" "$WORK/other" 0
addline "$PROJ/proj-b/s-later.jsonl" "{\"type\":\"user\",\"cwd\":\"$REPO\",\"sessionId\":\"s-later\"}"
# cwd の行が1つも無い記録は、まだ見分けられないので抜き出さない
mkdir -p "$PROJ/proj-c"
addline "$PROJ/proj-c/s-nocwd.jsonl" '{"type":"permission-mode","permissionMode":"default"}'
# 補助役の記録は、本体の会話として読まず、本体の会話の記録の鍵の下で読む
mkrec "$D/s-main/subagents/agent-a1.jsonl" "$REPO" 0

printf '== このリポジトリの会話の見分け方\n'
run_all
check "--all は 0 で終わる" "$?" "0"
check "最初の数行に cwd が無い記録を、cwd を持つ最初の行で見分ける" "$(kcount "$EX/s-main.jsonl" meta)" "1"
check "meta の行の session" "$(perl -MJSON::PP -ne 'my $d = decode_json($_); print $d->{session} if $d->{k} eq "meta"' "$EX/s-main.jsonl")" "s-main"
check "本体の作業フォルダの下の cwd の記録を抜き出す" "$(kcount "$EX/s-sub.jsonl" meta)" "1"
check "git worktree list に載った本体の外の worktree の記録を抜き出す" "$(kcount "$EX/s-outwt.jsonl" meta)" "1"
check "git worktree list に無い .claude/worktrees/<名前> の記録を抜き出す" "$(kcount "$EX/s-gone.jsonl" meta)" "1"
check "ほかの作業フォルダの記録を抜き出さない" "$(kcount "$EX/s-other.jsonl" meta)" "nofile"
check "本体の名前を頭に持つだけの別のフォルダの記録を抜き出さない" "$(kcount "$EX/s-prefix.jsonl" meta)" "nofile"
check "あとの行だけ cwd が本体の記録を抜き出さない" "$(kcount "$EX/s-later.jsonl" meta)" "nofile"
check "cwd の行が無い記録を抜き出さない" "$(kcount "$EX/s-nocwd.jsonl" meta)" "nofile"
check "見分けなかった記録に .pos を作らない" "$( [ -e "$EX/s-other.pos" ] && echo yes || echo no)" "no"
check "補助役の記録を本体の会話として読まず、本体の会話の記録の鍵の下で読む" "$( [ -e "$EX/agent-a1.pos" ] && echo yes || echo no)/$(kcount "$EX/s-main.agent-a1.jsonl" meta)" "no/1"
check ".pos の offset が記録の大きさ" "$(jfile "$EX/s-main.pos" offset)" "$(fsize "$D/s-main.jsonl")"
check ".pos の size が記録の大きさ" "$(jfile "$EX/s-main.pos" size)" "$(fsize "$D/s-main.jsonl")"
check ".pos の skipped が 0" "$(jfile "$EX/s-main.pos" skipped)" "0"
VER=$(jfile "$EX/s-main.pos" version)
check ".pos が版の番号を持つ" "$( [ "$VER" != undef ] && [ -n "$VER" ] && echo yes || echo no)" "yes"

printf '== Windows の区切りと大文字と小文字\n'
# 偽物の git: worktree list だけに、Windows の Git が返す / 区切りの場所で答える
mkdir -p "$TMP_ROOT/gitbin"
cat >"$TMP_ROOT/gitbin/git" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    if [ "$a" = worktree ]; then
        printf 'worktree C:/Users/T/Repo\nHEAD 0000000000000000000000000000000000000000\nbranch refs/heads/main\n\n'
        printf 'worktree D:/wt/Outside\nHEAD 0000000000000000000000000000000000000000\nbranch refs/heads/x\n'
        exit 0
    fi
done
echo "fatal: fake git" >&2
exit 1
EOF
chmod +x "$TMP_ROOT/gitbin/git"
WSTATE="$WORK/wstate"
WP="$WORK/whome/.claude/projects/C--Users-T-Repo"
mkrec "$WP/w-main.jsonl" 'C:\Users\T\REPO\src' 3
mkrec "$WP/w-outwt.jsonl" 'd:\WT\outside' 2
mkrec "$WP/w-outwt-not.jsonl" 'D:\wt\Outside-not' 0
mkrec "$WP/w-prefix.jsonl" 'C:\Users\T\Repository' 0
mkrec "$WP/w-gone.jsonl" 'c:\users\t\repo\.claude\worktrees\gone' 1
HOME="$WORK/whome" USERPROFILE="$WORK/whome" PATH="$TMP_ROOT/gitbin:$PATH" \
    perl "$EXTRACT" --state "$WSTATE" --all --wait --repo 'C:/Users/T/Repo'
check "--all --wait は 0 で終わる" "$?" "0"
check "\\ で区切り大文字の違う cwd を、/ で区切った本体と同じ作業フォルダと見分ける" "$(kcount "$WSTATE/extract/w-main.jsonl" meta)" "1"
check "\\ で区切った cwd を、git worktree list の / で区切った worktree と見分ける" "$(kcount "$WSTATE/extract/w-outwt.jsonl" meta)" "1"
check "Windows の場所でも、worktree の名前を頭に持つだけのフォルダを抜き出さない" "$(kcount "$WSTATE/extract/w-outwt-not.jsonl" meta)" "nofile"
check "Windows の場所でも、本体の名前を頭に持つだけのフォルダを抜き出さない" "$(kcount "$WSTATE/extract/w-prefix.jsonl" meta)" "nofile"
check "Windows の場所の、消した worktree の記録を抜き出す" "$(kcount "$WSTATE/extract/w-gone.jsonl" meta)" "1"

printf '== 本体の場所の文字と、記録の置き場所の候補\n'
# git worktree list に失敗したときも、日本語を含む本体の作業フォルダで見分ける
mkdir -p "$TMP_ROOT/failgit"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP_ROOT/failgit/git"
chmod +x "$TMP_ROOT/failgit/git"
JREPO="$WORK/リポジトリ"
mkrec "$WORK/jhome/.claude/projects/j/j-main.jsonl" "$JREPO/src" 0
HOME="$WORK/jhome" USERPROFILE="$WORK/jhome" PATH="$TMP_ROOT/failgit:$PATH" \
    perl "$EXTRACT" --state "$WORK/jstate" --all --wait --repo "$JREPO" 2>/dev/null
check "git worktree list に失敗しても 0 で終わる" "$?" "0"
check "日本語を含む本体の作業フォルダの下の cwd の記録を抜き出す" "$(kcount "$WORK/jstate/extract/j-main.jsonl" meta)" "1"
# Windows の Git Bash では、HOME と別の USERPROFILE の下の記録も読む
case "$(perl -e 'print $^O')" in msys | cygwin) IS_WIN=1 ;; *) IS_WIN=0 ;; esac
if [ "$IS_WIN" = 1 ]; then
    mkrec "$WORK/uprofile/.claude/projects/u/u-main.jsonl" "$REPO" 0
    mkdir -p "$WORK/uhome"
    HOME="$WORK/uhome" USERPROFILE="$WORK/uprofile" perl "$EXTRACT" --state "$WORK/ustate" --all --wait --repo "$REPO"
    check "Windows では USERPROFILE の下の会話の記録も読む" "$(kcount "$WORK/ustate/extract/u-main.jsonl" meta)" "1"
fi

printf '== 2回続けて呼ぶ・ファイルが短くなる\n'
addline "$D/s-main.jsonl" '{"type":"user","sessionId":"s-main","message":{"role":"user","content":"more"}}'
run_all
check "2回目も 0 で終わる" "$?" "0"
check "2回続けて呼んでも meta の行が重ならない" "$(kcount "$EX/s-main.jsonl" meta)" "1"
check "2回目は足した行の終わりまで読む" "$(jfile "$EX/s-main.pos" offset)" "$(fsize "$D/s-main.jsonl")"
run_all
check "足した行が無い3回目でも meta の行が重ならない" "$(kcount "$EX/s-main.jsonl" meta)" "1"
# 抜き出した記録に目印の行を足し、会話の記録に行を足して呼ぶ: 前に抜き出した記録に書き足す
addline "$EX/s-main.jsonl" '{"k":"keep"}'
addline "$D/s-main.jsonl" '{"type":"user","sessionId":"s-main","message":{"role":"user","content":"more2"}}'
run_all
check "続きを読むときは、前に抜き出した記録を消さずに書き足す" "$(kcount "$EX/s-main.jsonl" keep)/$(kcount "$EX/s-main.jsonl" meta)" "1/1"
# 書きかけの最後の行を残して読み、記録を読んだところより後ろで短くする: 前の size より小さいので読み直す
mkrec "$D/s-shrink.jsonl" "$REPO" 0
printf '%s' '{"type":"user","sessionId":"s-shrink","mess' >>"$D/s-shrink.jsonl"
run_all
SHRINK_OFF=$(jfile "$EX/s-shrink.pos" offset)
addline "$EX/s-shrink.jsonl" '{"k":"marker"}'
mkrec "$D/s-shrink.jsonl" "$REPO" 0
printf '%s' '{"t' >>"$D/s-shrink.jsonl"
check "(前提)短くした記録も、前に読んだところより大きい" "$( [ "$(fsize "$D/s-shrink.jsonl")" -gt "$SHRINK_OFF" ] && echo yes || echo no)" "yes"
run_all
check "前の size より小さくなった記録を最初から読み直す" "$(kcount "$EX/s-shrink.jsonl" marker)/$(kcount "$EX/s-shrink.jsonl" meta)" "0/1"
# 抜き出した記録に目印の行を足し、短くした会話の記録で呼ぶ: 記録が消えて最初から読み直される
addline "$EX/s-main.jsonl" '{"k":"marker"}'
mkrec "$D/s-main.jsonl" "$REPO" 0
run_all
check "短くなった記録を最初から読み直し、前に抜き出した記録を消す" "$(kcount "$EX/s-main.jsonl" marker)" "0"
check "読み直したあとの meta の行は1つ" "$(kcount "$EX/s-main.jsonl" meta)" "1"
check "読み直したあとの offset は短くなった記録の大きさ" "$(jfile "$EX/s-main.pos" offset)" "$(fsize "$D/s-main.jsonl")"
check "読み直したあとの size は短くなった記録の大きさ" "$(jfile "$EX/s-main.pos" size)" "$(fsize "$D/s-main.jsonl")"

printf '== 壊れた行\n'
mkrec "$D/s-broken.jsonl" "$REPO" 0
addline "$D/s-broken.jsonl" '{"type":"user", broken'
addline "$D/s-broken.jsonl" 'not json at all'
addline "$D/s-broken.jsonl" '[1,2,3]'
addline "$D/s-broken.jsonl" '{"type":"user","sessionId":"s-broken"}'
# 最後の行は書きかけ(改行が無い): まだ読まない
PART='{"type":"user","sessi'
printf '%s' "$PART" >>"$D/s-broken.jsonl"
run_all
check "壊れた行があっても 0 で終わる" "$?" "0"
check "壊れた行と知らない形の行の数を .pos に残す" "$(jfile "$EX/s-broken.pos" skipped)" "3"
check "書きかけの最後の行の手前で止まる" "$(jfile "$EX/s-broken.pos" offset)" "$(( $(fsize "$D/s-broken.jsonl") - ${#PART} ))"
printf 'onId":"s-broken"}\n' >>"$D/s-broken.jsonl"
run_all
check "書き終わった行を次の呼び出しで読む" "$(jfile "$EX/s-broken.pos" offset)" "$(fsize "$D/s-broken.jsonl")"
check "書き終わった行を壊れた行に数えない" "$(jfile "$EX/s-broken.pos" skipped)" "3"
check "壊れた行があっても meta の行は1つ" "$(kcount "$EX/s-broken.jsonl" meta)" "1"

printf '== 版の番号\n'
perl -MJSON::PP -i -0pe '$_ = do { my $d = decode_json($_); $d->{version} = "old-version"; encode_json($d) }' "$EX/s-sub.pos"
addline "$EX/s-sub.jsonl" '{"k":"marker"}'
run_all
check "版の番号が違う記録の鍵の、前に抜き出した記録を消す" "$(kcount "$EX/s-sub.jsonl" marker)" "0"
check "版の番号が違う記録の鍵を、最初から読み直す" "$(kcount "$EX/s-sub.jsonl" meta)" "1"
check "版の番号を今の番号に書き直す" "$(jfile "$EX/s-sub.pos" version)" "$VER"
check "読み直したあとの offset は記録の大きさ" "$(jfile "$EX/s-sub.pos" offset)" "$(fsize "$D/s-sub.jsonl")"
# 会話の記録のファイルが無い記録の鍵: 版の番号が違っても消さない
perl -MJSON::PP -i -0pe '$_ = do { my $d = decode_json($_); $d->{version} = "old-version"; encode_json($d) }' "$EX/s-outwt.pos"
addline "$EX/s-outwt.jsonl" '{"k":"marker"}'
rm -f "$D/s-outwt.jsonl"
run_all
check "記録のファイルが無い記録の鍵の、抜き出した記録が残る" "$(kcount "$EX/s-outwt.jsonl" marker)/$(kcount "$EX/s-outwt.jsonl" meta)" "1/1"
check "記録のファイルが無い記録の鍵の、.pos が残る" "$(jfile "$EX/s-outwt.pos" version)" "old-version"

printf '== 応答の行と、上限と再試行の行\n'
# 作り物の会話の記録: mkmsgrec <ファイル> <entrypoint>
# 会話の文・コマンドの文字列・ファイルの中身には SECRET を含む文字列を入れ、抜き出した記録に入らないことを確かめる
mkmsgrec() {
    mkdir -p "$(dirname "$1")"
    perl -MJSON::PP -e '
        my ($file, $cwd, $ep) = @ARGV;
        my $j = JSON::PP->new->utf8->canonical;
        (my $sid = $file) =~ s{.*/}{}; $sid =~ s{\.jsonl$}{};
        my %c = (cwd => $cwd, sessionId => $sid, entrypoint => $ep);
        my $u1 = {input_tokens => 10, cache_creation_input_tokens => 300, cache_read_input_tokens => 50, output_tokens => 7,
            cache_creation => {ephemeral_5m_input_tokens => 100, ephemeral_1h_input_tokens => 200},
            server_tool_use => {web_search_requests => 2, web_fetch_requests => 0}, speed => "fast", inference_geo => "us"};
        my $u2 = {input_tokens => 1, cache_creation_input_tokens => 0, cache_read_input_tokens => 0, output_tokens => 3,
            cache_creation => {ephemeral_5m_input_tokens => 0, ephemeral_1h_input_tokens => 0},
            server_tool_use => {web_search_requests => 0, web_fetch_requests => 0}, speed => "standard", inference_geo => "global"};
        my $z = {input_tokens => 0, cache_creation_input_tokens => 0, cache_read_input_tokens => 0, output_tokens => 0,
            cache_creation => {ephemeral_5m_input_tokens => 0, ephemeral_1h_input_tokens => 0}, speed => undef, inference_geo => undef};
        my @l = (
            {%c, type => "user", gitBranch => "feat/a", timestamp => "2026-10-26T00:00:00.000Z", message => {role => "user", content => "SECRET-USER-TEXT"}},
            {%c, type => "assistant", gitBranch => "feat/a", timestamp => "2026-10-26T00:00:01.500Z",
                message => {id => "msg_1", model => "claude-opus-5-5", role => "assistant", stop_reason => "tool_use", usage => $u1,
                    content => [{type => "tool_use", id => "toolu_1", name => "Bash", input => {command => "echo SECRET-COMMAND"}}]}},
            {%c, type => "assistant", gitBranch => "feat/a", timestamp => "2026-10-26T00:00:01.600Z",
                message => {id => "msg_1", model => "claude-opus-5-5", role => "assistant", stop_reason => "tool_use", usage => $u1,
                    content => [{type => "text", text => "SECRET-ASSISTANT-TEXT"}]}},
            {%c, type => "user", gitBranch => "feat/a", timestamp => "2026-10-26T00:00:02.000Z",
                message => {role => "user", content => [{type => "tool_result", tool_use_id => "toolu_1", content => "SECRET-FILE-CONTENT"}]}},
            {%c, type => "assistant", gitBranch => "feat/b", timestamp => "2026-10-26T00:00:03.000Z",
                message => {id => "msg_2", model => "claude-fable-5-1", role => "assistant", stop_reason => "end_turn", usage => $u2,
                    content => [{type => "text", text => "SECRET-ASSISTANT-TEXT"}]}},
            {%c, type => "assistant", gitBranch => "feat/b", timestamp => "2026-10-26T00:00:04.000Z", error => "rate_limit", isApiErrorMessage => JSON::PP::true,
                quotaLimits => {resetsAt => 1792990800, rateLimitType => "five_hour", status => "rejected"},
                message => {id => "syn_1", model => "<synthetic>", role => "assistant", stop_reason => "stop_sequence", usage => $z,
                    content => [{type => "text", text => "SECRET-LIMIT-TEXT"}]}},
            {%c, type => "assistant", gitBranch => "feat/b", timestamp => "2026-10-26T00:00:05.000Z", error => "server_error", isApiErrorMessage => JSON::PP::true,
                message => {id => "syn_2", model => "<synthetic>", role => "assistant", stop_reason => "stop_sequence", usage => $z,
                    content => [{type => "text", text => "SECRET-ERROR-TEXT"}]}},
            {%c, type => "system", subtype => "api_error", gitBranch => "feat/b", timestamp => "2026-10-26T00:00:06.250Z",
                retryInMs => 603, retryAttempt => 1, maxRetries => 10, level => "error", error => {message => "SECRET-ERROR-TEXT"}},
            {type => "pr-link", sessionId => $sid, timestamp => "2026-10-26T00:00:07.000Z", prNumber => 626,
                prRepository => "o/r", prUrl => "https://github.com/o/r/pull/626", message => {}},
        );
        open my $f, ">", $file or die "$file: $!";
        print $f $j->encode($_), "\n" for @l;
    ' "$1" "$REPO" "$2"
}
mkmsgrec "$D/s-msg.jsonl" cli
mkmsgrec "$D/s-desk.jsonl" claude-desktop
run_all
check "応答の行を抜き出して 0 で終わる" "$?" "0"
M="$EX/s-msg.jsonl"
check "同じ message.id の2行と synthetic の行から、トークン数を1回だけ抜き出す" "$(kcount "$M" msg)" "2"
check "msg の時刻は UNIX 秒" "$(kfield "$M" msg 1 ts)" "1792972801.5"
check "msg の id" "$(kfield "$M" msg 1 id)" "msg_1"
check "msg のモデル" "$(kfield "$M" msg 1 model)/$(kfield "$M" msg 2 model)" "claude-opus-5-5/claude-fable-5-1"
check "msg の入力と読み込みと出力のトークン数" "$(kfield "$M" msg 1 in)/$(kfield "$M" msg 1 cr)/$(kfield "$M" msg 1 out)" "10/50/7"
check "書き込みのトークン数を5分と1時間に分ける" "$(kfield "$M" msg 1 cw5)/$(kfield "$M" msg 1 cw1h)" "100/200"
check "Web 検索の回数" "$(kfield "$M" msg 1 ws)/$(kfield "$M" msg 2 ws)" "2/0"
check "speed と inference_geo が fast と us になる" "$(kfield "$M" msg 1 fast)/$(kfield "$M" msg 1 us)" "true/true"
check "standard と global は fast と us にならない" "$(kfield "$M" msg 2 fast)/$(kfield "$M" msg 2 us)" "false/false"
check "end_turn が msg.end になる" "$(kfield "$M" msg 1 end)/$(kfield "$M" msg 2 end)" "false/true"
check "上限の印を抜き出す" "$(kcount "$M" limit)/$(kfield "$M" limit 1 ts)/$(kfield "$M" limit 1 resets_at)" "1/1792972804/1792990800"
check "API の再試行の時間を抜き出す" "$(kcount "$M" retry)/$(kfield "$M" retry 1 ts)/$(kfield "$M" retry 1 ms)" "1/1792972806.25/603"
check "gitBranch が変わった時刻と値を抜き出す" "$(kcount "$M" branch)/$(kfield "$M" branch 1 name)/$(kfield "$M" branch 2 name)/$(kfield "$M" branch 2 ts)" "2/feat/a/feat/b/1792972803"
check "prNumber を抜き出す" "$(kcount "$M" pr)/$(kfield "$M" pr 1 number)/$(kfield "$M" pr 1 ts)" "1/626/1792972807"
check "抜き出した記録に、会話の文、コマンドの文字列、ファイルの中身が入らない" "$(grep -c SECRET "$M")" "0"
check "entrypoint が cli の記録と claude-desktop の記録から、同じ形の行を抜き出す" \
    "$(grep -v '"k":"meta"' "$M" | cksum)" "$(grep -v '"k":"meta"' "$EX/s-desk.jsonl" | cksum)"
# 続きを読む: 同じ message.id の行と、同じ gitBranch の行を足しても、行は重ならない
addline "$D/s-msg.jsonl" "$(sed -n '5p' "$D/s-msg.jsonl" | sed 's/00:00:03.000Z/00:00:03.100Z/')"
run_all
check "前の呼び出しで抜き出した message.id の行を、続きで重ねて抜き出さない" "$(kcount "$M" msg)" "2"
check "gitBranch が変わらない続きの行で、branch の行を足さない" "$(kcount "$M" branch)" "2"
addline "$D/s-msg.jsonl" "$(sed -n '5p' "$D/s-msg.jsonl" | sed 's/msg_2/msg_3/')"
run_all
check "新しい message.id の行を続きで抜き出す" "$(kcount "$M" msg)/$(kfield "$M" msg 3 id)" "3/msg_3"
# 書き足したあと .pos を書く前に止まった状態をまねる: .pos の offset を1行目の直後に戻す
# 読み直す行には、同じ message.id の行、gitBranch が変わる行、上限と再試行と PR の行が入る
setoffset() { perl -MJSON::PP -i -pe 'my $d = decode_json($_); $d->{offset} = $ENV{OFF}; $_ = encode_json($d) . "\n"' "$1"; }
before=$(cksum <"$M")
OFF=$(head -n 1 "$D/s-msg.jsonl" | wc -c | tr -d ' ') setoffset "$EX/s-msg.pos"
run_all
check "止まったあとに読み直しても、抜き出した記録に行が重ならない" "$(cksum <"$M")" "$before"
check "止まったあとに読み直しても、行の数が変わらない" \
    "$(kcount "$M" msg)/$(kcount "$M" branch)/$(kcount "$M" limit)/$(kcount "$M" retry)/$(kcount "$M" pr)" "3/2/1/1/1"
# 書き足しの途中で止まった状態をまねる: 抜き出した記録の最後の15バイトを切り、書きかけの行を残す
perl -e 'truncate($ARGV[0], (-s $ARGV[0]) - 15) or exit 1' "$M"
OFF=$(head -n 1 "$D/s-msg.jsonl" | wc -c | tr -d ' ') setoffset "$EX/s-msg.pos"
run_all
check "書きかけの行が残っていても、読み直したあとの抜き出した記録は止まる前と同じ" "$(cksum <"$M")" "$before"
check "書きかけの行が残っていても、抜き出した記録の行はすべて JSON として読める" \
    "$(perl -MJSON::PP -ne 'eval { decode_json($_); 1 } or $n++; END { print $n // 0 }' "$M")" "0"
# 読み直す位置の直前の gitBranch が、64KB より長い行にあっても読める
big=$(perl -e 'print "x" x 100000')
addline "$D/s-big.jsonl" "{\"type\":\"user\",\"cwd\":\"$REPO\",\"sessionId\":\"s-big\",\"gitBranch\":\"feat/big\",\"timestamp\":\"2026-10-26T00:00:00.000Z\",\"message\":{\"role\":\"user\",\"content\":\"$big\"}}"
addline "$D/s-big.jsonl" "{\"type\":\"user\",\"cwd\":\"$REPO\",\"sessionId\":\"s-big\",\"gitBranch\":\"feat/big\",\"timestamp\":\"2026-10-26T00:00:01.000Z\",\"message\":{\"role\":\"user\",\"content\":\"y\"}}"
run_all
OFF=$(head -n 1 "$D/s-big.jsonl" | wc -c | tr -d ' ') setoffset "$EX/s-big.pos"
run_all
check "長い行の gitBranch を読み、読み直しで branch の行を足さない" "$(kcount "$EX/s-big.jsonl" branch)" "1"
# キャッシュの書き込みの内訳が無い usage では、書き込みの全部を5分に数える
addline "$D/s-nocc.jsonl" "{\"type\":\"assistant\",\"cwd\":\"$REPO\",\"sessionId\":\"s-nocc\",\"timestamp\":\"2026-10-26T00:00:01.000Z\",\"message\":{\"id\":\"msg_n\",\"model\":\"claude-opus-5-5\",\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":1,\"cache_creation_input_tokens\":40,\"output_tokens\":2}}}"
run_all
check "内訳の無い書き込みは5分に数える" "$(kfield "$EX/s-nocc.jsonl" msg 1 cw5)/$(kfield "$EX/s-nocc.jsonl" msg 1 cw1h)" "40/0"

printf '== 会話の相手と道具の行\n'
# 抜き出した記録の、k が $2 の行の欄 $3 の値を、行の順に , でつなぐ。欄の無い行は undef
kall() {
    [ -f "$1" ] || { printf 'nofile'; return; }
    perl -MJSON::PP -ne 'BEGIN { ($want, $field) = splice @ARGV, 0, 2; binmode STDOUT, ":utf8" } my $d = eval { decode_json($_) } or next; next unless ($d->{k} // "") eq $want; my $v = $d->{$field}; push @v, !exists $d->{$field} ? "undef" : !defined $v ? "null" : JSON::PP::is_bool($v) ? ($v ? "true" : "false") : $v; END { print join ",", @v }' "$2" "$3" <"$1"
}
# 作り物の会話の記録: mktoolrec <ファイル>
# 会話の文・コマンドの文字列・道具の引数と結果の中身には SECRET を含む文字列を入れる
mktoolrec() {
    mkdir -p "$(dirname "$1")"
    perl -MJSON::PP -e '
        my ($file, $cwd) = @ARGV;
        my $j = JSON::PP->new->utf8->canonical;
        (my $sid = $file) =~ s{.*/}{}; $sid =~ s{\.jsonl$}{};
        my $n = 0;
        my $c = sub { $n++; return (cwd => $cwd, sessionId => $sid, timestamp => sprintf("2026-10-26T00:01:%02d.000Z", $n)) };
        my $u = sub { my ($origin, $content) = @_; return {$c->(), type => "user", (defined $origin ? (turnOrigin => $origin) : ()), message => {role => "user", content => $content}} };
        my $call = sub { my ($mid, $id, $name, $input) = @_; return {$c->(), type => "assistant",
            message => {id => $mid, model => "claude-opus-5-5", role => "assistant", stop_reason => "tool_use", usage => {input_tokens => 1, output_tokens => 1},
                content => [{type => "tool_use", id => $id, name => $name, input => $input}]}} };
        my $res = sub { my ($id, %o) = @_; return {$c->(), type => "user",
            ($o{perm} ? (permissionDecision => {decision => "allow", source => $o{perm}}) : ()),
            ($o{tur} ? (toolUseResult => $o{tur}) : ()),
            message => {role => "user", content => [{type => "tool_result", tool_use_id => $id, content => "SECRET-FILE-CONTENT", ($o{err} ? (is_error => JSON::PP::true) : ())}]}} };
        my @l = (
            $u->("human", "SECRET-USER-TEXT"),
            $u->("peer", "SECRET-PEER-TEXT"),
            $u->("scheduled", "SECRET-SCHEDULED-TEXT"),
            $u->("sdk", "SECRET-SDK-TEXT"),
            $u->("task_notification", "<task-notification>\n<task-id>a0123456789abcdef</task-id>\nSECRET-NOTICE-TEXT</task-notification>"),
            $u->("task_notification", [{type => "text", text => "[resume-after-usage-limit] SECRET-RESUME-TEXT"}]),
            $u->("brand_new-1", "SECRET-NEW-TEXT"),
            $u->("y" x 40, "SECRET-40-TEXT"),
            $u->("z" x 41, "SECRET-41-TEXT"),
            $u->("has space!", "SECRET-SPACE-TEXT"),
            $u->(undef, "<command-name>/model</command-name>"),
            $call->("msg_t1", "toolu_a", "Bash", {command => "bash .claude/scripts/parallel/run-check.sh frontend pnpm test SECRET-COMMAND"}),
            $res->("toolu_a", perm => "user_temporary"),
            $call->("msg_t2", "toolu_b", "Bash", {command => "sleep 30 # SECRET-COMMAND", run_in_background => JSON::PP::true}),
            $res->("toolu_b", perm => "config", tur => {backgroundTaskId => "b12345678", stdout => "SECRET-FILE-CONTENT"}),
            $call->("msg_t3", "toolu_c", "Agent", {prompt => "SECRET-PROMPT", run_in_background => "true", subagent_type => "general-purpose"}),
            $res->("toolu_c", tur => {agentId => "a0123456789abcdef", status => "async_launched"}),
            $call->("msg_t4", "toolu_d", "AskUserQuestion", {questions => "SECRET-QUESTION"}),
            $call->("msg_t4", "toolu_e", "Monitor", {command => "SECRET-COMMAND"}),
            $call->("msg_t4", "toolu_f", "SomeNewTool", {}),
            $res->("toolu_d", err => 1),
            $res->("toolu_e", perm => "hook"),
            $res->("toolu_f"),
            $call->("msg_t5", "toolu_g", "ExitPlanMode", {plan => "SECRET-PLAN"}),
            $call->("msg_t5", "toolu_h", "PowerShell", {command => "docker compose ps # SECRET-COMMAND"}),
            $res->("toolu_h"),
            $res->("toolu_g", perm => "user_permanent"),
            {$c->(), type => "assistant", message => {id => "msg_t6", model => "claude-opus-5-5", role => "assistant", stop_reason => "end_turn",
                usage => {input_tokens => 1, output_tokens => 1}, content => [{type => "text", text => "SECRET-ASSISTANT-TEXT"}]}},
        );
        open my $f, ">", $file or die "$file: $!";
        print $f $j->encode($_), "\n" for @l;
    ' "$1" "$REPO"
}
mktoolrec "$D/s-tool.jsonl"
run_all
check "会話の相手と道具の行を抜き出して 0 で終わる" "$?" "0"
T="$EX/s-tool.jsonl"
check "turnOrigin の3つの値が owner・peer・notice になり、一覧に無い値が unknown と raw になり、41文字以上と記号を含む値の raw が空になる" \
    "$(kall "$T" turn from)|$(kall "$T" turn raw)" \
    "owner,peer,notice,notice,notice,limit,unknown,unknown,unknown,unknown|undef,undef,undef,undef,undef,undef,brand_new-1,$(perl -e 'print "y" x 40'),,"
check "turn の時刻は UNIX 秒" "$(kfield "$T" turn 1 ts)" "1792972861"
check "task_notification の知らせの元の仕事の識別子が turn.job になる" "$(kall "$T" turn job)" "null,null,null,null,a0123456789abcdef,null,null,null,null,null"
check "turnOrigin が task_notification で文が [resume-after-usage-limit] を含む行が、turn.from が limit の行になり、文が手元の記録に残らない" \
    "$(kfield "$T" turn 6 from)/$(grep -c -e SECRET-RESUME-TEXT -e 'resume-after-usage-limit' "$T")" "limit/0"
check "permissionDecision.source が user_ で始まる道具の perm が user になる" "$(kall "$T" tool perm)" "user,other,other,other,other,other,other,user"
check "品質チェックのコマンドの道具が、その分類の名前で抜き出され、コマンドの文字列が残らない" \
    "$(kfield "$T" tool 1 cat)/$(grep -c -e SECRET-COMMAND -e 'run-check' "$T")" "品質チェック/0"
check "待ちの分類の名前が、道具の種類とコマンドで決まる" "$(kall "$T" tool cat)" "品質チェック,待つだけのコマンド,,,待つだけの道具,,Docker,"
check "道具の名前が tool.kind になり、知らない名前が other になり、裏で動かした仕事の識別子が抜き出される" \
    "$(kall "$T" tool kind)|$(kall "$T" result job)|$(kall "$T" result job_kind)" \
    "shell,shell,agent,ask,wait,other,shell,ask|null,b12345678,a0123456789abcdef,null,null,null,null,null|null,other,agent,null,null,null,null,null"
check "道具の行は結果が届いた順に並び、tool_use_id を持つ" "$(kall "$T" tool id)" "toolu_a,toolu_b,toolu_c,toolu_d,toolu_e,toolu_f,toolu_h,toolu_g"
check "裏で動かしたかどうかが tool.bg になる" "$(kall "$T" tool bg)" "false,true,true,false,false,false,false,false"
check "tool の時刻は呼び出しの時刻、result の時刻は結果の時刻" "$(kfield "$T" tool 1 ts)/$(kfield "$T" result 1 ts)" "1792972872/1792972873"
check "失敗した道具の結果が result.err になる" "$(kall "$T" result err)" "false,false,false,true,false,false,false,false"
check "抜き出した行に、元の欄の名前が残らない" \
    "$(grep -c -e SECRET -e turnOrigin -e permissionDecision -e tool_use -e tool_result -e toolUseResult -e run_in_background -e agentId -e backgroundTaskId -e is_error -e task_notification -e human -e '"Bash"' -e '"Agent"' -e AskUserQuestion -e Monitor -e ExitPlanMode -e PowerShell -e SomeNewTool -e user_temporary -e '"source"' "$T")" "0"
# 1行ずつ書き足しながら呼ぶ: 呼び出しと結果が別の呼び出しで読まれても、一度に読んだときと同じ行になる
FULL="$D/s-tool.jsonl"
lines=$(wc -l <"$FULL" | tr -d ' ')
i=1
while [ "$i" -le "$lines" ]; do
    head -n "$i" "$FULL" | sed 's/"s-tool"/"s-inc"/g' >"$D/s-inc.jsonl"
    run_all
    i=$((i + 1))
done
check "1行ずつ書き足しながら読んでも、一度に読んだときと同じ行になる" \
    "$(grep -v '"k":"meta"' "$EX/s-inc.jsonl" | cksum)" "$(grep -v '"k":"meta"' "$T" | cksum)"
before=$(cksum <"$T")
OFF=$(head -n 13 "$FULL" | wc -c | tr -d ' ') setoffset "$EX/s-tool.pos"
run_all
check "止まったあとに道具の結果の行から読み直しても、抜き出した記録が変わらない" "$(cksum <"$T")" "$before"
# v2.1.275 までの記録: turnOrigin が無く、同じ値を origin.kind に - でつないで書く
perl -MJSON::PP -e '
    my ($file, $cwd) = @ARGV;
    my $j = JSON::PP->new->utf8->canonical;
    my $n = 0;
    my $c = sub { $n++; return (cwd => $cwd, sessionId => "s-old", timestamp => sprintf("2026-10-26T00:02:%02d.000Z", $n)) };
    my $u = sub { my ($origin, $content, %o) = @_; return {$c->(), type => "user", origin => $origin, %o, message => {role => "user", content => $content}} };
    my @l = (
        $u->({kind => "human"}, "SECRET-OLD-USER-TEXT"),
        $u->({kind => "task-notification"}, "<task-notification>\n<task-id>b87654321</task-id>\nSECRET-OLD-NOTICE-TEXT</task-notification>"),
        $u->({kind => "task-notification"}, "[resume-after-usage-limit] SECRET-OLD-RESUME-TEXT"),
        $u->({kind => "coordinator", body => "SECRET-OLD-BODY", from => "SECRET-OLD-FROM"}, "SECRET-OLD-COORDINATOR-TEXT"),
        $u->({kind => "human"}, "SECRET-OLD-PEER-TEXT", turnOrigin => "peer"),
        $u->({kind => {nested => "human"}}, "SECRET-OLD-NESTED-TEXT"),
        $u->({kind => "task-notification"}, "<task-notification>\n<task-id>not an id!</task-id>\nSECRET-OLD-BADID-TEXT</task-notification>"),
        {$c->(), type => "assistant", message => {id => "msg_o1", model => "claude-opus-5-5", role => "assistant", stop_reason => "tool_use", usage => {input_tokens => 1, output_tokens => 1},
            content => [{type => "tool_use", id => "toolu_o", name => "Bash", input => {command => "ls # SECRET-COMMAND"}}]}},
        {$c->(), type => "user", permissionDecision => {decision => "allow", source => "auto_user"},
            message => {role => "user", content => [{type => "tool_result", tool_use_id => "toolu_o", content => "SECRET-FILE-CONTENT"}]}},
    );
    open my $f, ">", $file or die "$file: $!";
    print $f $j->encode($_), "\n" for @l;
' "$D/s-old.jsonl" "$REPO"
run_all
O="$EX/s-old.jsonl"
check "turnOrigin の無い古い版の行は、origin.kind の値を - を _ に替えて turnOrigin の値として読み、turnOrigin があればそちらを読む" \
    "$(kall "$O" turn from)|$(kall "$O" turn raw)|$(kall "$O" turn job)" \
    "owner,notice,limit,unknown,peer,notice|undef,undef,undef,coordinator,undef,undef|null,b87654321,null,null,null,null"
check "知らせの元の仕事の識別子が英字と数字と _ と - だけの形でなければ、turn.job が null になる" "$(kall "$O" turn job | cut -d, -f6)/$(grep -c 'not an id' "$O")" "null/0"
check "古い版の行の origin の欄と会話の文が、抜き出した記録に残らない" \
    "$(grep -c -e SECRET -e '"origin"' -e task-notification -e '"human"' -e '"body"' "$O")" "0"
check "permissionDecision.source が user_ で始まらない値は、user を含んでも perm が other になる" "$(kall "$O" tool perm)" "other"
# データのファイルは extract.pl と同じフォルダから読む。読めないときは何も書かずに 1 で終わる
mkdir -p "$WORK/nocfg"
cp "$EXTRACT" "$WORK/nocfg/extract.pl"
perl "$WORK/nocfg/extract.pl" --state "$WORK/nocfgstate" --all --skip-locked --repo "$REPO" 2>/dev/null
check "データのファイルが読めないときは 1 で終わり、抜き出した記録を作らない" "$?/$( [ -e "$WORK/nocfgstate/extract/s-tool.jsonl" ] && echo yes || echo no)" "1/no"

printf '== 出来事と補助役の情報\n'
# 作り物の会話の記録: 段階の印、受け持ちとまとめの出来事、別に起こしたセッションの出来事
perl -MJSON::PP -e '
    my ($file, $cwd) = @ARGV;
    my $j = JSON::PP->new->utf8->canonical;
    my $n = 0;
    my $c = sub { $n++; return (cwd => $cwd, sessionId => "s-ev", timestamp => sprintf("2026-10-26T00:03:%02d.000Z", $n)) };
    my $u = sub { return {$c->(), type => "user", message => {role => "user", content => $_[0]}} };
    my $call = sub { my ($id, $name, $input) = @_; return {$c->(), type => "assistant",
        message => {id => "msg_$id", model => "claude-opus-5-5", role => "assistant", stop_reason => "tool_use", usage => {input_tokens => 1, output_tokens => 1},
            content => [{type => "tool_use", id => $id, name => $name, input => $input}]}} };
    my $res = sub { my ($id, $content, $err) = @_; return {$c->(), type => "user",
        message => {role => "user", content => [{type => "tool_result", tool_use_id => $id, content => $content, ($err ? (is_error => JSON::PP::true) : ())}]}} };
    my $bash = sub { my ($id, $cmd, $err) = @_; return ($call->($id, "Bash", {command => $cmd}), $res->($id, "SECRET-OUTPUT", $err)) };
    my $closed = " に統合した。"; utf8::decode($closed);
    my @l = (
        $u->("<command-message>start</command-message>\n<command-name>/start</command-name>\n<command-args>#42 SECRET-ARGS</command-args>"),
        $u->("<command-message>model</command-message>\n<command-name>/model</command-name>\n<command-args>opus</command-args>"),
        $u->([{type => "text", text => "<command-name>/kiro-spec-design</command-name>\n            <command-message>kiro-spec-design</command-message>\n            <command-args>feat-x SECRET-ARGS</command-args>"}]),
        $u->("SECRET-USER-TEXT <command-name>/ship</command-name>"),
        $call->("toolu_s1", "Skill", {skill => "spec-review", args => "feat-x design changed SECRET-ARGS"}),
        $res->("toolu_s1", "Launching skill: spec-review"),
        $call->("toolu_s2", "Skill", {skill => "verify-backend"}),
        $res->("toolu_s2", "Launching skill: verify-backend"),
        $call->("toolu_s3", "Skill", {skill => "verify-"}),
        $res->("toolu_s3", "Launching skill: verify-"),
        $call->("toolu_s4", "Skill", {skill => "simplify", args => "#77"}),
        $res->("toolu_s4", "Launching skill: simplify"),
        $bash->("toolu_b1", "bash .claude/scripts/parallel/session.sh claim 42 --branch feat/x --session SECRET-SESSION"),
        $bash->("toolu_b2", "bash .claude/scripts/parallel/session.sh check-start 43", 1),
        $bash->("toolu_b3", "bash .claude/scripts/parallel/session.sh takeover #44 --branch=feat/y"),
        $bash->("toolu_b4", "gh issue close 7 --reason \"not planned\" --comment \"#9$closed\""),
        $bash->("toolu_b5", "gh issue close 8 --reason \"not planned\" --comment \"#9$closed\"", 1),
        $bash->("toolu_b6", "gh issue close 10 --reason completed --comment \"#9$closed\""),
        $call->("toolu_p1", "mcp__ccd_session__start_session", {title => "SECRET-TITLE", prompt => "SECRET-PROMPT"}),
        $res->("toolu_p1", [{type => "text", text => "Started session \"SECRET-TITLE\" (session_id: local_f6786648-d7d9-44d1-841b-cf76b75c4a8f, name: x). SECRET-RESULT"}]),
        $call->("toolu_p2", "mcp__ccd_session__start_session", {title => "SECRET-TITLE"}),
        $res->("toolu_p2", "local_00000000-0000-4000-8000-000000000000 SECRET-RESULT", 1),
    );
    open my $f, ">", $file or die "$file: $!";
    print $f $j->encode($_), "\n" for @l;
' "$D/s-ev.jsonl" "$REPO"
# 作り物の補助役の記録: mkagent <ファイル> <報告の返し方> <meta.json の中身か none>
# 返し方は text(最後の assistant の行の文)か handback(SubagentHandback)か handback-then-text(報告のあとに文が続く)
mkagent() {
    mkdir -p "$(dirname "$1")"
    [ "$3" = none ] || printf '%s\n' "$3" >"${1%.jsonl}.meta.json"
    perl -MJSON::PP -e '
        my ($file, $cwd, $how) = @ARGV;
        my $j = JSON::PP->new->utf8->canonical;
        my $n = 0;
        my $c = sub { $n++; return (cwd => $cwd, sessionId => "s-ev", isSidechain => JSON::PP::true, timestamp => sprintf("2026-10-26T00:04:%02d.000Z", $n)) };
        my $say = sub { my ($id, @b) = @_; return {$c->(), type => "assistant", message => {id => $id, model => "claude-opus-5-5", role => "assistant",
            stop_reason => "end_turn", usage => {input_tokens => 1, output_tokens => 1}, content => [@b]}} };
        my $report = "SECRET-REPORT-TEXT\n## Review Verdict\n- VERDICT: REJECTED\n- NEXT_ACTION: RETRY_TASK\n";
        my @l = (
            {$c->(), type => "user", message => {role => "user", content => "- FEATURE: feat-x\n- STAGE: design\n- CYCLE: 1\n- ROUND: 2\n- REVIEW_FILE: SECRET-FILE\nSECRET-PROMPT"}},
            $say->("msg_a1", {type => "text", text => "SECRET-DRAFT\n- VERDICT: APPROVED\n"}),
        );
        if ($how eq "text") {
            push @l, $say->("msg_a2", {type => "text", text => $report});
        } else {
            push @l, $say->("msg_a2", {type => "tool_use", id => "toolu_h1", name => "SubagentHandback", input => {message => $how eq "handback" ? $report : "- VERDICT: APPROVED\n"}}),
                {$c->(), type => "user", message => {role => "user", content => [{type => "tool_result", tool_use_id => "toolu_h1", content => "SECRET-RESULT"}]}};
            push @l, $say->("msg_a3", {type => "text", text => "SECRET-AFTER-TEXT"}) if $how eq "handback-then-text";
        }
        open my $f, ">", $file or die "$file: $!";
        print $f $j->encode($_), "\n" for @l;
    ' "$1" "$REPO" "$2"
}
AG="$D/s-ev/subagents"
mkagent "$AG/agent-atext1.jsonl" text '{"agentType":"spec-reviewer","description":"SECRET-DESC","model":"opus","toolUseId":"toolu_x"}'
mkagent "$AG/agent-ahand1.jsonl" handback '{"agentType":"general-purpose","description":"SECRET-DESC"}'
mkagent "$AG/agent-alate1.jsonl" handback-then-text '{"agentType":"SECRET TYPE","model":"SECRET MODEL"}'
mkagent "$AG/agent-anometa.jsonl" text none
# このリポジトリでない会話の補助役の記録は読まない
mkagent "$PROJ/proj-b/s-other/subagents/agent-aother.jsonl" text none
run_all
check "補助役の記録を読んでも 0 で終わる" "$?" "0"
E="$EX/s-ev.jsonl"
check "stage_marks に載ったスキルの名前だけが段階の印になる" "$(kall "$E" stage name)" "start,kiro-spec-design,spec-review,verify-backend"
check "段階の印の引数からは Issue の番号と spec-review の段階の名前だけを取り出す" \
    "$(kall "$E" stage issue)|$(kall "$E" stage spec_stage)" "42,null,null,null|null,null,design,null"
check "session.sh claim 42 --branch feat/x と /start #42 と gh issue close 7 --reason \"not planned\" --comment \"#9 に統合した。\" から、受け持ちとまとめの出来事が抜き出される" \
    "$(kall "$E" recv how)|$(kall "$E" recv issue)|$(kall "$E" recv branch)|$(kall "$E" merge from)|$(kall "$E" merge to)" \
    "claim,takeover|42,44|feat/x,feat/y|7|9"
check "失敗した結果の呼び出しからは出来事が抜き出されない" "$(kcount "$E" recv)/$(kcount "$E" merge)/$(kcount "$E" spawn)" "2/1/1"
check "start_session の結果から local_<uuid> が抜き出される" "$(kall "$E" spawn child)" "local_f6786648-d7d9-44d1-841b-cf76b75c4a8f"
check "出来事の行の時刻は呼び出しの時刻" "$(kall "$E" recv ts | cut -d, -f1)" "$(kall "$E" tool ts | cut -d, -f5)"
check "本体の会話の meta の行は補助役の欄を持たない" "$(kall "$E" meta agent_id)|$(kall "$E" meta agent_type)|$(kall "$E" meta stage)" "null|null|null"
AT="$EX/s-ev.agent-atext1.jsonl"
AH="$EX/s-ev.agent-ahand1.jsonl"
check "補助役の記録の鍵は、本体の会話の記録の鍵と補助役の記録の名前" "$(kall "$AT" meta session)|$(kall "$AT" meta agent_id)" "s-ev.agent-atext1|atext1"
check "補助役の meta の行に agentType とモデルが入る" "$(kall "$AT" meta agent_type)|$(kall "$AT" meta model)|$(kall "$AH" meta agent_type)|$(kall "$AH" meta model)" \
    "spec-reviewer|opus|general-purpose|null"
check "確認役の - VERDICT: REJECTED と NEXT_ACTION: の行と、審査役の STAGE: design CYCLE: 1 ROUND: 2 が、最後の assistant の行の文で返した記録と SubagentHandback で返した記録の両方から抜き出される" \
    "$(kall "$AT" verdict value)|$(kall "$AT" verdict next_action)|$(kall "$AT" meta stage)|$(kall "$AT" meta cycle)|$(kall "$AT" meta round)/$(kall "$AH" verdict value)|$(kall "$AH" verdict next_action)|$(kall "$AH" meta stage)|$(kall "$AH" meta cycle)|$(kall "$AH" meta round)" \
    "REJECTED|true|design|1|2/REJECTED|true|design|1|2"
check "報告のあとに判定の行の無い文が続けば、判定の行を書かない" "$(kcount "$EX/s-ev.agent-alate1.jsonl" verdict)" "0"
check "名前の形でない agentType とモデルは null になる" "$(kall "$EX/s-ev.agent-alate1.jsonl" meta agent_type)|$(kall "$EX/s-ev.agent-alate1.jsonl" meta model)" "null|null"
check "meta.json の無い補助役の記録も読み、agentType とモデルを null にする" \
    "$(kall "$EX/s-ev.agent-anometa.jsonl" meta agent_type)|$(kall "$EX/s-ev.agent-anometa.jsonl" verdict value)" "null|REJECTED"
check "このリポジトリでない会話の補助役の記録を読まない" "$(find "$EX" -name '*aother*' | wc -l | tr -d ' ')" "0"
check "会話の文とコマンドと依頼文と報告の文が、抜き出した記録に残らない" "$(cat "$E" "$EX"/s-ev.agent-*.jsonl | grep -c -e SECRET -e Launching -e session_id)" "0"
# 補助役が動いている間に読むと、途中の文を報告として読む。集計は最後の verdict の行を使う
# splitread <ファイル> <1回目に読む行の数>: 先頭の行だけを読ませてから、全部を読ませる
splitread() {
    cp "$1" "$WORK/split.full"
    head -n "$2" "$WORK/split.full" >"$1"
    run_all
    cp "$WORK/split.full" "$1"
    run_all
}
mkagent "$AG/agent-asplit.jsonl" text none
splitread "$AG/agent-asplit.jsonl" 2
check "途中の文の判定のあとに報告を読むと、報告の判定の行を最後に書く" \
    "$(kall "$EX/s-ev.agent-asplit.jsonl" verdict value)|$(kall "$EX/s-ev.agent-asplit.jsonl" verdict ts)" \
    "APPROVED,REJECTED|$(kall "$EX/s-ev.agent-asplit.jsonl" msg ts)"
mkagent "$AG/agent-alsplit.jsonl" handback-then-text none
splitread "$AG/agent-alsplit.jsonl" 4
check "途中の判定のあとに判定の行の無い報告を読むと、value が null の行で前の判定を打ち消す" \
    "$(kall "$EX/s-ev.agent-alsplit.jsonl" verdict value)|$(kall "$EX/s-ev.agent-alsplit.jsonl" verdict next_action)" "APPROVED,null|false,false"
run_all
check "続きの無い記録をもう一度読んでも、判定の行を書き足さない" "$(kcount "$EX/s-ev.agent-alsplit.jsonl" verdict)" "2"
# データのファイルに stage_marks が無いときも、データのファイルを読めないときと同じに扱う
mkdir -p "$WORK/nomarks"
cp "$EXTRACT" "$WORK/nomarks/extract.pl"
perl -MJSON::PP -e 'local $/; my $d = decode_json(<STDIN>); delete $d->{stage_marks}; print JSON::PP->new->utf8->canonical->encode($d)' \
    <"$(dirname "$EXTRACT")/usage-config.json" >"$WORK/nomarks/usage-config.json"
perl "$WORK/nomarks/extract.pl" --state "$WORK/nomarksstate" --all --skip-locked --repo "$REPO" 2>/dev/null
check "データのファイルに stage_marks が無いときは 1 で終わり、抜き出した記録を作らない" "$?/$( [ -e "$WORK/nomarksstate/extract/s-ev.jsonl" ] && echo yes || echo no)" "1/no"

printf '== デスクトップアプリの手元の記録\n'
# desktop.jsonl の行を local>session の形にしてつなぐ。ファイルが無ければ nofile
dpairs() {
    [ -f "$1" ] || { printf 'nofile'; return; }
    perl -MJSON::PP -ne 'my $d = decode_json($_); push @p, "$d->{local}>$d->{session}"; END { print join ",", @p }' "$1"
}
# 作り物の手元の記録を書く: mklocal <ファイル> <sessionId> <cliSessionId>
mklocal() {
    mkdir -p "$(dirname "$1")"
    perl -MJSON::PP -e 'my ($f, $l, $c) = @ARGV; open my $h, ">", $f or die; print $h JSON::PP->new->canonical->encode({sessionId => $l, cliSessionId => $c, title => "SECRET TITLE", cwd => "x"})' "$1" "$2" "$3"
}
U1=11111111-1111-4111-8111-111111111111
U2=22222222-2222-4222-8222-222222222222
U3=33333333-3333-4333-8333-333333333333
LA=local_aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
LB=local_bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
LC=local_cccccccc-cccc-4ccc-8ccc-cccccccccccc
DHOME="$WORK/dhome"
mkrec "$DHOME/.claude/projects/p/$U1.jsonl" "$REPO" 0
mkrec "$DHOME/.claude/projects/p/$U2.jsonl" "$WORK/other" 0
mkrec "$DHOME/.claude/projects/p/$U3.jsonl" "$REPO" 0
DS="$DHOME/AppData/Local/Claude-Data/claude_x/claude-code-sessions"
mklocal "$DS/g1/g2/$LA.json" "$LA" "$U1"
mklocal "$DS/g1/g2/waiting-input/$LB.json" "$LB" "$U3"
mklocal "$DS/g1/g2/$LC.json" "$LC" "$U2"
mklocal "$DS/g1/g2/local_dddddddd-dddd-4ddd-8ddd-dddddddddddd.json" "not-a-local-id" "$U1"
printf '{broken' >"$DS/g1/g2/local_eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee.json"
drun() { HOME="${3:-$DHOME}" USERPROFILE="${3:-$DHOME}" LOCALAPPDATA="$1" perl "$EXTRACT" --state "$2" --all --skip-locked --repo "$REPO"; }
drun "$DHOME/AppData/Local" "$WORK/dstate"
check "デスクトップアプリの手元の記録があっても 0 で終わる" "$?" "0"
check "デスクトップアプリの記録の cliSessionId から desktop.jsonl に local と session の対応が書かれる" \
    "$(dpairs "$WORK/dstate/extract/desktop.jsonl")" "$LA>$U1,$LB>$U3"
check "desktop.jsonl に手元の記録の文を書かない" "$(grep -c SECRET "$WORK/dstate/extract/desktop.jsonl")" "0"
rm "$DS/g1/g2/waiting-input/$LB.json"
drun "$DHOME/AppData/Local" "$WORK/dstate"
check "読むたびに desktop.jsonl を書き直す" "$(dpairs "$WORK/dstate/extract/desktop.jsonl")" "$LA>$U1"
rm "$DHOME/.claude/projects/p/$U1.jsonl"
drun "$DHOME/AppData/Local" "$WORK/dstate"
check "会話の記録のファイルが消えた鍵でも、手元の記録に残る対応を desktop.jsonl に書く" "$(dpairs "$WORK/dstate/extract/desktop.jsonl")" "$LA>$U1"
run_all
check "デスクトップアプリの手元の記録の置き場所が無い PC で、desktop.jsonl を作らずに 0 で終わる" \
    "$?/$(dpairs "$EX/desktop.jsonl")" "0/nofile"
mkdir -p "$WORK/emptylocal/Claude-Data/claude_y"
mkrec "$WORK/ehome/.claude/projects/p/$U1.jsonl" "$REPO" 0
drun "$WORK/emptylocal" "$WORK/dstate2" "$WORK/ehome"
check "Claude-Data に claude-code-sessions が無いときも、desktop.jsonl を作らずに 0 で終わる" \
    "$?/$(dpairs "$WORK/dstate2/extract/desktop.jsonl")/$(kcount "$WORK/dstate2/extract/$U1.jsonl" meta)" "0/nofile/1"
# Windows の Git Bash では、LOCALAPPDATA が無くても USERPROFILE の下の AppData/Local を見る
if [ "$IS_WIN" = 1 ]; then
    mkrec "$DHOME/.claude/projects/p/$U1.jsonl" "$REPO" 0
    HOME="$DHOME" USERPROFILE="$DHOME" perl -e 'delete $ENV{LOCALAPPDATA}; exec @ARGV' \
        perl "$EXTRACT" --state "$WORK/dstate3" --all --skip-locked --repo "$REPO"
    check "Windows では LOCALAPPDATA が無くても USERPROFILE の下の手元の記録を読む" "$(dpairs "$WORK/dstate3/extract/desktop.jsonl")" "$LA>$U1"
fi

printf '== 錠と、知らない値の行の書き直し\n'
LHOME="$WORK/lhome"
LP="$LHOME/.claude/projects/p"
LSTATE="$WORK/lstate"
LLOCK="$LSTATE/locks/extract-lk1"
# lk1 は読むのに時間のかかる長い記録、lk2 と lk3 は短い記録
mkrec "$LP/lk1.jsonl" "$REPO" 0
i=0
while [ "$i" -lt 80 ]; do
    addline "$LP/lk1.jsonl" "$(printf '{"type":"user","sessionId":"lk1","timestamp":"2026-10-26T01:%02d:%02d.000Z","turnOrigin":"human","message":{"role":"user","content":"x"}}' $((i / 60)) $((i % 60)))"
    i=$((i + 1))
done
mkrec "$LP/lk2.jsonl" "$REPO" 0
mkrec "$LP/lk3.jsonl" "$REPO" 0
# テストのための上書きは、呼び出しごとに環境変数で渡す(待つ上限・古いとみなす時間・時刻を直す間隔)
lrun() { HOME="$LHOME" USERPROFILE="$LHOME" LOCALAPPDATA="$WORK/nolocal" perl "$EXTRACT" --state "$LSTATE" --all "$1" --repo "$REPO"; }
# 1行読むたびに少し待つ extract.pl(読んでいる間の錠の扱いを確かめるため)
slowrun() {
    HOME="$LHOME" USERPROFILE="$LHOME" LOCALAPPDATA="$WORK/nolocal" perl -e '
        BEGIN { no warnings "once"; *CORE::GLOBAL::readline = sub { select(undef, undef, undef, 0.1); CORE::readline($_[0]) } }
        $0 = shift; do $0; die $@ if $@; exit 1' "$EXTRACT" --state "$LSTATE" --all --skip-locked --repo "$REPO"
}
exists() { if [ -e "$1" ]; then printf yes; else printf no; fi; }
mkdir -p "$LLOCK"
lrun --skip-locked
check "錠を持つ呼び出しがあるとき、--skip-locked はその記録の鍵を飛ばし、ほかの鍵は読む" \
    "$?/$(exists "$LSTATE/extract/lk1.pos")/$(exists "$LSTATE/extract/lk2.pos")" "0/no/yes"
KP_USAGE_TEST_LOCK_WAIT=30 lrun --wait &
wpid=$!
sleep 2
check "--wait は錠が外れるまで読まずに待つ" "$(exists "$LSTATE/extract/lk1.pos")" "no"
rmdir "$LLOCK"
wait "$wpid"
check "--wait は錠が外れてから最後まで読む" \
    "$?/$(jfile "$LSTATE/extract/lk1.pos" offset)/$(fsize "$LP/lk1.jsonl")/$(exists "$LLOCK")" \
    "0/$(fsize "$LP/lk1.jsonl")/$(fsize "$LP/lk1.jsonl")/no"
addline "$LP/lk3.jsonl" '{"type":"user","sessionId":"lk3","timestamp":"2026-10-26T00:02:00.000Z","turnOrigin":"human","message":{"role":"user","content":"x"}}'
mkdir -p "$LSTATE/locks/extract-lk3"
KP_USAGE_TEST_LOCK_WAIT=1 lrun --wait 2>/dev/null
check "--wait は上限を超えると 1 で終わり、その鍵を読まない" "$?/$(kcount "$LSTATE/extract/lk3.jsonl" turn)" "1/0"
touch -t 202001010000 "$LSTATE/locks/extract-lk3"
lrun --skip-locked
check "古いとみなす時間より古い錠は取り直して読み、読み終えたら錠を外す" \
    "$?/$(kcount "$LSTATE/extract/lk3.jsonl" turn)/$(exists "$LSTATE/locks/extract-lk3")" "0/1/no"
# 読み直させるために lk1 の抜き出した記録を消し、遅い呼び出しが錠を持って読んでいる間に、ほかの呼び出しを動かす
rm -f "$LSTATE/extract/lk1.pos" "$LSTATE/extract/lk1.jsonl"
KP_USAGE_TEST_LOCK_TOUCH=1 KP_USAGE_TEST_LOCK_STALE=3 slowrun &
spid=$!
i=0
while [ ! -d "$LLOCK" ] && [ "$i" -lt 100 ]; do
    sleep 0.1
    i=$((i + 1))
done
sleep 4
KP_USAGE_TEST_LOCK_STALE=3 lrun --skip-locked
check "読んでいる間に錠の時刻が直り、古いとみなす時間を過ぎてもほかの呼び出しが錠を取り直さない" \
    "$?/$(exists "$LLOCK")/$(exists "$LSTATE/extract/lk1.pos")" "0/yes/no"
wait "$spid"
check "錠を持って読んでいた呼び出しは最後まで読む" \
    "$?/$(jfile "$LSTATE/extract/lk1.pos" offset)/$(kcount "$LSTATE/extract/lk1.jsonl" turn)/$(exists "$LLOCK")" \
    "0/$(fsize "$LP/lk1.jsonl")/80/no"
# 古い extract.pl が書いた unknown の行を手で作る。human は今の値の一覧にあり、brand_new は無い
UH='{"from":"unknown","job":null,"k":"turn","raw":"human","ts":1792972980}'
UN='{"from":"unknown","job":null,"k":"turn","raw":"brand_new","ts":1792973040}'
addline "$LSTATE/extract/lk2.jsonl" "$UH"
addline "$LSTATE/extract/lk2.jsonl" "$UN"
addline "$LSTATE/extract/lk3.jsonl" "$UH"
# lk3 には、UH を書き直した行と同じ行を、UH より後ろにも置く
addline "$LSTATE/extract/lk3.jsonl" '{"from":"owner","job":null,"k":"turn","ts":1792972980}'
rm "$LP/lk3.jsonl"
mkdir -p "$LSTATE/locks/extract-lk2"
lrun --skip-locked
check "錠を取れない記録の鍵では unknown の行を書き直さない" "$(kfield "$LSTATE/extract/lk2.jsonl" turn 1 from)" "unknown"
rmdir "$LSTATE/locks/extract-lk2"
lrun --skip-locked
check "--all で呼ぶと、raw の値が値の一覧にある unknown の行が値の一覧のとおりに書き直される" \
    "$(kfield "$LSTATE/extract/lk2.jsonl" turn 1 from)/$(kfield "$LSTATE/extract/lk2.jsonl" turn 1 raw)/$(kfield "$LSTATE/extract/lk2.jsonl" turn 1 ts)" \
    "owner/undef/1792972980"
check "raw の値が値の一覧に無い unknown の行は書き直さない" \
    "$(kfield "$LSTATE/extract/lk2.jsonl" turn 2 from)/$(kfield "$LSTATE/extract/lk2.jsonl" turn 2 raw)" "unknown/brand_new"
check "元の会話の記録のファイルが無い記録の鍵でも、unknown の行が書き直される" \
    "$(kfield "$LSTATE/extract/lk3.jsonl" turn 2 from)/$(kfield "$LSTATE/extract/lk3.jsonl" turn 2 raw)" "owner/undef"
check "書き直した行と同じ行がファイルの後ろにあるときは、同じ行を2つ残さない" "$(kcount "$LSTATE/extract/lk3.jsonl" turn)" "2"

printf '== 終了コード\n'
printf 'x\n' >"$WORK/afile"
perl "$EXTRACT" --state "$WORK/afile/state" --all --skip-locked --repo "$REPO" 2>/dev/null
check "記録の置き場所に書けないときは 1 で終わる" "$?" "1"
perl "$EXTRACT" --state "$STATE" --all --skip-locked 2>/dev/null
check "--repo が無いときは 64 で終わる" "$?" "64"
perl "$EXTRACT" --state "$STATE" --all --skip-locked --wait --repo "$REPO" 2>/dev/null
check "--skip-locked と --wait を両方渡すと 64 で終わる" "$?" "64"
perl "$EXTRACT" --state "$STATE" --all --repo "$REPO" 2>/dev/null
check "--skip-locked も --wait も無いときは 64 で終わる" "$?" "64"

printf '\n%d ok, %d NG\n' "$pass" "$failn"
[ "$failn" -eq 0 ]
