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
export HOME USERPROFILE
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
    perl -MJSON::PP -ne 'BEGIN { ($want, $nth, $field) = splice @ARGV, 0, 3; $i = 0 } my $d = eval { decode_json($_) } or next; next unless ($d->{k} // "") eq $want; next unless ++$i == $nth; my $v = $d->{$field}; print !defined $v ? "undef" : JSON::PP::is_bool($v) ? ($v ? "true" : "false") : $v; END { print "noline" if $i < $nth }' "$2" "$3" "$4" <"$1"
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
# 補助役の記録の置き場所は、本体の会話として読まない(補助役はタスク2.4で読む)
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
check "補助役の記録を本体の会話として読まない" "$( [ -e "$EX/agent-a1.pos" ] && echo yes || echo no)" "no"
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
if [ "$(perl -e 'print $^O')" = msys ]; then
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
