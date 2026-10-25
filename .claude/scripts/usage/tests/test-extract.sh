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

# 作り物の会話の記録を書く: mkrec <ファイル> <cwd> <cwd の無い行の数>
# 最初に cwd の無い行を置き、cwd を持つ user の行と assistant の行を続ける
mkrec() {
    mkdir -p "$(dirname "$1")"
    perl -MJSON::PP -e '
        my ($file, $cwd, $n) = @ARGV;
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
