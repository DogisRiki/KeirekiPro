#!/bin/bash
# =====================================================================
# usage.sh(集計の入口のコマンド)のテスト
#
# 実行: bash .claude/scripts/usage/tests/test-usage.sh
# 一時フォルダに git のリポジトリを作り、origin/main にデータのファイル(usage-config.json)を足したコミットを置く。
# 偽の gh(fixtures/fake-gh.sh)を一時フォルダに gh の名前で写し、その一時フォルダを PATH の先頭に置く。
# 偽の gh は、一時フォルダの db.json を GitHub の代わりにする。本物の GitHub は読まず、書かない。
# 最後の節は、作業フォルダの最上位の .claude/hooks/usage-hook.sh と .claude/settings.json と、
# 集計の時点と印を書いた手順の文書(スキルと CLAUDE.md)を読む。
# 前提: bash・perl(JSON::PP)・git。
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
USAGE="$(cd "$HERE/.." && pwd)/usage.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/bin"
cp "$HERE/fixtures/fake-gh.sh" "$TMP_ROOT/bin/gh"
chmod +x "$TMP_ROOT/bin/gh"
PATH="$TMP_ROOT/bin:$PATH"
export PATH

# git が返すパス(Windows では C:/...)と同じ形で作る
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })
SCRIPTS="$(cd "$HERE/.." && pwd)"

# draft が呼ぶ extract.pl が本物の会話の記録を読まないように、会話の記録の置き場所の候補
# (HOME と、Windows の USERPROFILE と LOCALAPPDATA)を一時フォルダに替える
HOME="$WORK/home"
USERPROFILE="$HOME"
LOCALAPPDATA="$WORK/nolocal"
export HOME USERPROFILE LOCALAPPDATA

# 仕組みが main に入った時刻(データのファイルを足したコミットの時刻)。協定世界時では 2026-10-24T03:00:00Z である
SYS="2026-10-24T12:00:00+09:00"

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }

gitq() { git -c user.name=test -c user.email=test@example.com -C "$REPO" "$@"; }
# 一時の git のリポジトリを作り、REPO と STATE にする: newrepo <名前> [config]
# config を付けると、origin/main に、時刻 $SYS にデータのファイルを足したコミットを置く。
# どちらでも、作業のブランチは feat/usage-test である
newrepo() {
    REPO="$WORK/$1"
    STATE="$REPO/.git/keirekipro-usage"
    git init -q "$REPO"
    gitq symbolic-ref HEAD refs/heads/main
    printf 'a\n' >"$REPO/README"
    gitq add README
    GIT_COMMITTER_DATE="2026-10-01T00:00:00+09:00" gitq commit -q -m base
    if [ "${2:-}" = config ]; then
        mkdir -p "$REPO/.claude/scripts/usage"
        printf '{}\n' >"$REPO/.claude/scripts/usage/usage-config.json"
        gitq add .claude/scripts/usage/usage-config.json
        GIT_COMMITTER_DATE="$SYS" gitq commit -q -m config
    fi
    gitq update-ref refs/remotes/origin/main HEAD
    gitq checkout -q -b feat/usage-test
}
# テストごとの偽の GitHub のフォルダを作り、FAKE_GH_DIR にする: newgh <名前>
newgh() {
    FAKE_GH_DIR="$TMP_ROOT/gh-$1"
    mkdir -p "$FAKE_GH_DIR"
    export FAKE_GH_DIR
}
# 偽の GitHub の db.json を書く: mkdb <perl のハッシュの中身>。
# cl(<番号>, <閉じた時刻>) は閉じた Issue、op(<番号>) は開いた Issue である。どちらも、<欄> => <値> を続けて欄を替えられる。
# list(<コメント>...) は一覧の Issue(番号 1)、cm(<id>, <本文>) はコメント、idx(<ID>...) は案の索引のコメントの本文、
# props(<番号>, <行>...) は直す案を持つ集計のコメントの本文、rep(<番号>) は数字の行を1つ持つ集計のコメントの本文である。
# pr(<番号>, <state>, <本文>, <mergedAt>, <mergeCommit の oid>) は main に向けた PR である
mkdb() {
    perl -MJSON::PP -e '
        my ($t, $f) = (JSON::PP::true, JSON::PP::false);
        sub iss { my ($n, %o) = @_; return { number => $n, title => "t$n", body => "", state => "closed", state_reason => "completed",
            locked => $f, author_association => "OWNER", comments => [], %o } }
        sub cl { my ($n, $at, %o) = @_; return iss($n, closed_at => $at, %o) }
        sub op { my ($n, %o) = @_; return iss($n, state => "open", state_reason => undef, closed_at => undef, %o) }
        sub list { return iss(1, title => "AIの作業の集計の一覧", state_reason => "not_planned", closed_at => "2026-10-25T00:00:00Z",
            locked => $t, comments => [@_]) }
        sub cm { my ($id, $body) = @_; return { id => $id, body => $body, author_association => "OWNER", created_at => "2026-10-26T00:00:00Z" } }
        sub idx { return "<!-- keirekipro-usage-proposals:v1 page=1 " . JSON::PP->new->canonical->encode([ map { { id => $_, issue => (split /-/)[0] + 0 } } @_ ]) . " -->\n説明\n" }
        sub props { my ($n, @l) = @_; return "<!-- keirekipro-usage-report:v1 issue=$n -->\n\n## AIの作業の集計\n\n### 所見\n\n- 箇条\n\n### 直す案\n\n" . join("", map { "$_\n" } @l) }
        sub rep { my ($n) = @_; return "<!-- keirekipro-usage-report:v1 issue=$n -->\n\n## AIの作業の集計\n\n本文\n<!-- keirekipro-usage-data:v1 "
            . q({"v":1,"issue":) . $n . q(,"prs":[305],"spec":false,"end_date":"2026-10-25","totals":{"work_sec":600,"wait_sec":0,"tokens":12,"usd":0.5,"usd_unknown_models":[]},"rework":{"impl_spec_back":{"requirements":0,"design":0,"tasks":0}}})
            . " -->\n" }
        sub pr { my ($n, $st, $body, $at, $mc) = @_; return { number => $n, state => $st, baseRefName => "main", headRefName => "feat/pr$n",
            body => $body, mergedAt => $at, mergeCommit => defined $mc ? { oid => $mc } : undef } }
        my $db = { '"$1"' };
        open my $fh, ">", "$ENV{FAKE_GH_DIR}/db.json" or die $!;
        print $fh JSON::PP->new->canonical->encode($db);
    ' || ng "偽の GitHub を用意できない"
}
# 集計の対象かを確かめる一時の git のリポジトリを作り、REPO と STATE にする: draftrepo <名前> [noconfig]
# main に、base と、仕組みが入る前の PR のマージ(PRE)と、時刻 $SYS にデータのファイルを足したコミット(SYSC)と、
# 仕組みが入ったあとの PR のマージ(POST)を置く。noconfig を付けると、base だけを置く。
# origin はこのリポジトリ自身で、origin/main は無い。draft の git fetch origin main が origin/main を作る
draftrepo() {
    REPO="$WORK/$1"
    STATE="$REPO/.git/keirekipro-usage"
    git init -q "$REPO"
    gitq symbolic-ref HEAD refs/heads/main
    printf 'a\n' >"$REPO/README"
    gitq add README
    GIT_COMMITTER_DATE="2026-10-01T00:00:00+09:00" gitq commit -q -m base
    if [ "${2:-}" != noconfig ]; then
        printf 'p\n' >"$REPO/pre"
        gitq add pre
        GIT_COMMITTER_DATE="2026-10-20T00:00:00+09:00" gitq commit -q -m pre
        PRE=$(gitq rev-parse HEAD)
        mkdir -p "$REPO/.claude/scripts/usage"
        printf '{}\n' >"$REPO/.claude/scripts/usage/usage-config.json"
        gitq add .claude/scripts/usage/usage-config.json
        GIT_COMMITTER_DATE="$SYS" gitq commit -q -m config
        SYSC=$(gitq rev-parse HEAD)
        printf 'q\n' >"$REPO/post"
        gitq add post
        GIT_COMMITTER_DATE="2026-10-25T00:00:00+09:00" gitq commit -q -m post
        POST=$(gitq rev-parse HEAD)
    fi
    gitq remote add origin "$REPO"
    gitq checkout -q -b feat/usage-test
}
# 作業フォルダ $REPO で、Issue 203 のブランチ feat/pr305 で動いた会話の記録を置く: mktrans <会話の ID> <assistant の行の数> [<cwd> [<ブランチ>]]
# cwd とブランチを付けると、その作業フォルダとブランチで動いた会話の記録にする
# 2026-10-24T10:00Z(仕組みが入ったあとで、PR 305 のマージより前)に、所有者の行と assistant の行を続け、
# 最後に、見分けられない再開の値 mystery-x の user の行と、assistant の行を1つ置く。assistant の行は、1行で 3 トークンを使う
mktrans() {
    perl -MJSON::PP -e '
        my ($file, $cwd, $sid, $n, $br) = @ARGV;
        my $j = JSON::PP->new->utf8->canonical;
        my $k = 0;
        my $ts = sub { my $s = $k++; return sprintf("2026-10-24T10:%02d:%02d.000Z", int($s / 60), $s % 60) };
        my %c = (cwd => $cwd, sessionId => $sid, gitBranch => $br);
        my $user = sub { return { %c, type => "user", turnOrigin => $_[0], timestamp => $ts->(), message => { role => "user", content => "hi" } } };
        my $ai = sub { return { %c, type => "assistant", timestamp => $ts->(),
            message => { id => "m$_[0]", model => "claude-opus-5-5", content => [], usage => { input_tokens => 1, output_tokens => 2 } } } };
        open my $f, ">", $file or die "$file: $!";
        print $f $j->encode($_), "\n" for $user->("human"), (map { $ai->($_) } 1 .. $n), $user->("mystery-x"), $ai->($n + 1);
        close $f or die $!;
    ' "$(mkdir -p "$HOME/.claude/projects/p-$1" && printf '%s' "$HOME/.claude/projects/p-$1")/$1.jsonl" "${3:-$REPO}" "$1" "$2" "${4:-feat/pr305}" ||
        ng "会話の記録を用意できない"
}
# 下書きの report.json の totals の tokens
drafttokens() { perl -MJSON::PP -e 'open my $f, "<", $ARGV[0] or exit 1; local $/; print JSON::PP->new->decode(<$f>)->{totals}{tokens} // "null"' "$STATE/drafts/203/report.json" 2>/dev/null || printf none; }
# git の呼び出しを $TMP_ROOT/git-calls.log に書いてから本物の git を動かす偽の git を、$TMP_ROOT/gitlog-bin に置く
REALGIT=$(command -v git)
mkdir -p "$TMP_ROOT/gitlog-bin"
cat >"$TMP_ROOT/gitlog-bin/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMP_ROOT/git-calls.log"
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP_ROOT/gitlog-bin/git"
# 偽の git を PATH の先頭に置いて usage.sh を呼ぶ: gitlogrun <引数>...
gitlogrun() {
    local saved=$PATH
    : >"$TMP_ROOT/git-calls.log"
    PATH="$TMP_ROOT/gitlog-bin:$PATH"
    run "$@"
    PATH=$saved
}
# 偽の git が merge-base の呼び出しを書いた回数(git -C <場所> merge-base の形も数える)
mergebases() { grep -cE '(^| )merge-base( |$)' "$TMP_ROOT/git-calls.log" | tr -d ' '; }
# 手元の抜き出した記録に行を足す: xrow <記録の鍵> <行の JSON>
xrow() {
    mkdir -p "$STATE/extract"
    printf '%s\n' "$2" >>"$STATE/extract/$1.jsonl"
}
# 手元の抜き出した記録に、Issue N の受け持ちの出来事を足す: recv <N>
recv() { xrow s1 "{\"branch\":\"feat/x\",\"how\":\"claim\",\"issue\":$1,\"k\":\"recv\",\"ts\":1761300000}"; }
# 手元の issues/<N>.json を書く: issuejson <N> <JSON>
issuejson() {
    mkdir -p "$STATE/issues"
    printf '%s\n' "$2" >"$STATE/issues/$1.json"
}
statejson() { if [ -f "$STATE/$1" ]; then cat "$STATE/$1"; else printf 'none'; fi; }
# usage.sh を作業フォルダ $REPO(runin では <フォルダ>)で呼び、標準出力を $OUT、標準エラーを $ERR、終了コードを $RC に置く
runin() {
    local d=$1
    shift
    (cd "$d" && bash "$USAGE" "$@") >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"
    RC=$?
    OUT=$(cat "$TMP_ROOT/out")
    ERR=$(cat "$TMP_ROOT/err")
}
run() { runin "$REPO" "$@"; }
# 偽の gh が呼ばれた引数を | でつなぐ
calls() { if [ -f "$FAKE_GH_DIR/calls.log" ]; then tr '\n' '|' <"$FAKE_GH_DIR/calls.log"; fi; }
# 標準エラーの行の数
nlines() { if [ -n "$1" ]; then printf '%s\n' "$1" | wc -l | tr -d ' '; else printf 0; fi; }
# 標準エラーが usage.sh の日本語の1行かどうか
errline() { if [ "$(nlines "$ERR")" = 1 ] && printf '%s' "$ERR" | grep -q '^usage\.sh: .*。$'; then printf 'one'; else printf 'bad:%s' "$ERR"; fi; }
# marks.jsonl の行の数と、最後の行の会話・種類・段階・Issue・ブランチ・時刻(いまの UNIX 秒の整数なら now)
lastmark() {
    perl -MJSON::PP -e '
        my @l = <STDIN>;
        my $m = JSON::PP->new->decode($l[-1]);
        my $ts = $l[-1] =~ /"ts":([0-9]+)[,}]/ ? $1 : undef;
        my $issue = $l[-1] =~ /"issue":(null|[0-9]+)[,}]/ ? $1 : "not-a-number";
        print scalar(@l), "/", join("/", map { defined $m->{$_} ? $m->{$_} : "null" } qw(session kind stage)), "/$issue/",
            (defined $m->{branch} ? $m->{branch} : "null"), "/", (defined $ts && abs($ts - time) < 600 ? "now" : "ts=" . ($m->{ts} // "null"));
    ' <"$STATE/marks.jsonl"
}

echo "== 部品の形"
bash -n "$USAGE"
check "bash -n が通る" "$?" "0"

echo "== 往復と手戻りの印"
newrepo mark config
newgh mark
run mark spec-fix --stage design --issue 12 --session S1
check "mark が marks.jsonl に、時刻と会話と種類と段階と Issue とブランチの1行を足し、ほかの種類を受けない(種類と段階と Issue)" \
    "$RC/$OUT/$(lastmark)" "0//1/S1/spec-fix/design/12/feat/usage-test/now"
run mark same-failure
check "mark が marks.jsonl に、時刻と会話と種類と段階と Issue とブランチの1行を足し、ほかの種類を受けない(段階と Issue と会話の無い印)" \
    "$RC/$(lastmark)" "0/2/null/same-failure/null/null/feat/usage-test/now"
run mark review-done --issue 12
check "mark が marks.jsonl に、時刻と会話と種類と段階と Issue とブランチの1行を足し、ほかの種類を受けない(ほかの種類)" \
    "$RC/$(errline)/$(lastmark)" "1/one/2/null/same-failure/null/null/feat/usage-test/now"
run mark spec-fix --issue abc
check "mark が、Issue の番号でない --issue を受けない" "$RC/$(errline)/$(lastmark)" "1/one/2/null/same-failure/null/null/feat/usage-test/now"
run mark spec-fix --issue 12345678901
check "mark が、11桁の --issue を受けない" "$RC/$(errline)/$(lastmark)" "1/one/2/null/same-failure/null/null/feat/usage-test/now"
gitq worktree add -q "$WORK/mark-wt" -b feat/wt
runin "$WORK/mark-wt" mark switch-to-spec --issue 7 --session S2
check "worktree の作業フォルダから呼んだ mark が、git の共通ディレクトリの下の記録の置き場所に、その worktree のブランチで書く" \
    "$RC/$(lastmark)/$([ -e "$WORK/mark-wt/.git/keirekipro-usage" ] && printf wt || printf none)" "0/3/S2/switch-to-spec/null/7/feat/wt/now/none"
check "mark が gh を呼ばない" "$(calls)" ""

echo "== まだ出していない Issue"
newrepo pend config
newgh pend
# 101: 仕組みが入ったあとに閉じた、受け持ちの出来事がある Issue
# 102: 仕組みが入った時刻ちょうどに閉じた、受け持ちの出来事がある Issue
# 103: 仕組みが入った日の、仕組みが入る前に閉じた、受け持ちの出来事がある Issue
# 104: 仕組みが入ったあとに閉じた、受け持ちの出来事が無く、start でない段階の印とブランチの行だけがある Issue
# 105: 開いている、受け持ちの出来事がある Issue
# 106: 集計しない印の closed_at が、いまの closedAt と同じ Issue
# 107: 出し済みで list_pending がある Issue(受け持ちの出来事は無い)
# 108: 出し済みで proposals_pending がある Issue
# 109: 出し済みで、list_pending も proposals_pending も無い Issue
# 110: 仕組みが入る前の日に閉じた、出し済みで list_pending がある Issue(さかのぼりの集計で出した Issue)
# 111: 集計しない印の system-pr があり、出し済みで list_pending がある Issue(さかのぼりの集計で出した #501)
# 112: 仕組みが入ったあとに閉じた、受け持ちの出来事が Issue の番号のある start の段階の印だけの Issue
pendb() {
    mkdb "issues => [ cl(101, '2026-10-25T01:00:00Z'), cl(102, '2026-10-24T03:00:00Z'), cl(103, '2026-10-24T02:59:59Z'),
        cl(104, '2026-10-25T01:00:00Z'), op(105), cl(106, '$1'), cl(107, '2026-10-25T02:00:00Z'), cl(108, '2026-10-25T03:00:00Z'),
        cl(109, '2026-10-25T04:00:00Z'), cl(110, '2026-10-23T20:00:00Z'), cl(111, '2026-10-25T05:00:00Z'),
        cl(112, '2026-10-25T08:00:00Z') ]"
}
pendb "2026-10-25T06:00:00Z"
for n in 101 102 103 105 106 109 111; do recv "$n"; done
xrow s2 '{"issue":104,"k":"stage","name":"ship","spec_stage":null,"ts":1761300000}'
xrow s2 '{"k":"branch","name":"feat/104","ts":1761300001}'
xrow s3 '{"issue":112,"k":"stage","name":"start","spec_stage":null,"ts":1761300002}'
issuejson 106 '{"closed_at":"2026-10-25T06:00:00Z","skip":"no-merged-pr"}'
issuejson 107 '{"list_pending":true,"report_url":"https://github.com/owner/repo/issues/107#issuecomment-1","reported_at":"2026-10-25T02:10:00Z"}'
issuejson 108 '{"proposals_pending":["108-1"],"report_url":"https://github.com/owner/repo/issues/108#issuecomment-2","reported_at":"2026-10-25T03:10:00Z"}'
issuejson 109 '{"report_url":"https://github.com/owner/repo/issues/109#issuecomment-3","reported_at":"2026-10-25T04:10:00Z"}'
issuejson 110 '{"list_pending":true,"report_url":"https://github.com/owner/repo/issues/110#issuecomment-4","reported_at":"2026-10-26T00:00:00Z","skip":"before-system","closed_at":"2026-10-23T20:00:00Z"}'
issuejson 111 '{"closed_at":"2026-10-25T05:00:00Z","list_pending":true,"report_url":"https://github.com/owner/repo/issues/111#issuecomment-5","reported_at":"2026-10-26T00:00:00Z","skip":"system-pr"}'
run pending --session S1
check "pending が、仕組みが入ったあとに閉じた Issue のうち出していないものを出し、gh issue list を1回だけ呼ぶ" \
    "$RC/$OUT/$(calls)" '0/{"issues":[101,102,107,108,112]}/issue list --state closed --search closed:>=2026-10-23 --limit 200 --json number,closedAt|'
check "データのファイルを足したコミットと同じ日の、そのコミットより前の時刻に閉じた Issue を、pending が出さない" \
    "$(printf '%s' "$OUT" | grep -c '103')" "0"
check "出し済みで list_pending か proposals_pending がある Issue を pending が出す" \
    "$(printf '%s' "$OUT" | grep -o '107,108')" "107,108"
check "データのファイルを足したコミットより前に閉じた Issue と、集計しない印の system-pr がある Issue に list_pending があっても、pending が出さない" \
    "$(printf '%s' "$OUT" | grep -c '11[01]')" "0"
check "手で作った抜き出した記録に受け持ちの出来事が無い Issue を、pending が出さない" \
    "$(printf '%s' "$OUT" | grep -c '104')" "0"
check "受け持ちの出来事が、Issue の番号のある start の段階の印だけの Issue を、pending が出す" \
    "$(printf '%s' "$OUT" | grep -o '112')" "112"
newgh pend-reclosed
pendb "2026-10-25T07:00:00Z"
run pending
check "集計しない印の closed_at がいまの closedAt と同じ Issue を pending が出さず、closedAt が変わるとまた出す" \
    "$RC/$OUT/$(statejson issues/106.json)" '0/{"issues":[101,102,106,107,108,112]}/{"closed_at":"2026-10-25T06:00:00Z","skip":"no-merged-pr"}'
newgh pend-fail
pendb "2026-10-25T07:00:00Z"
printf '%s\n' '^issue list' >"$FAKE_GH_DIR/fail"
run pending
check "gh issue list が失敗すると、pending が標準出力に何も出さずに 1 で終わり、理由を1行で出す" "$RC/$OUT/$(errline)" "1//one"

newrepo noconf
newgh noconf
recv 101
mkdb "issues => [ cl(101, '2026-10-25T01:00:00Z') ]"
run pending
check "origin/main にデータのファイルを足したコミットが無いとき、pending が番号の無い JSON の1行を出して 0 で終わり、偽の gh を呼ばない" \
    "$RC/$OUT/$(calls)" '0/{"issues":[]}/'
gitq update-ref -d refs/remotes/origin/main
run pending
check "origin/main が無いときも、pending が番号の無い JSON の1行を出して 0 で終わり、偽の gh を呼ばない" \
    "$RC/$OUT/$(calls)" '0/{"issues":[]}/'

newrepo "pend sp" config
newgh pend-sp
recv 101
mkdb "issues => [ cl(101, '2026-10-25T01:00:00Z') ]"
run pending
check "記録の置き場所のパスに空白があっても、pending が、受け持ちの出来事がある Issue を出す" "$RC/$OUT" '0/{"issues":[101]}'

echo "== 集計の対象か"
draftrepo dr
newgh dr
mktrans dr-a 1
# 201: Refs: の PR の mergeCommit がデータのファイルを足したコミット(SYSC)で、閉じる PR はそのあとにマージされた Issue
# 202: 閉じる PR が SYSC より前にマージされた Issue
# 203: 閉じる PR が2つあり、遅くマージされたほうが SYSC よりあとにマージされた Issue。Closes #2031 の PR は 203 の PR でない
# 204: Refs: の PR だけがマージされ、Closes の PR はマージせずに閉じた、閉じた Issue
# 205: 開いていて、PR の無い Issue
# 206: まとめて閉じた、PR の無い Issue。207: 分けた元の、PR の無い Issue
# 208: 閉じる PR の mergeCommit が手元に無い Issue
drdb() {
    mkdb "issues => [ cl(201, '2026-10-25T01:00:00Z'), cl(202, '2026-10-25T02:00:00Z'), cl(203, '2026-10-25T03:00:00Z'),
        cl(204, '2026-10-25T04:00:00Z'), op(205), cl(206, '$1', state_reason => 'not_planned'),
        cl(207, '2026-10-25T07:00:00Z', state_reason => 'not_planned'), cl(208, '2026-10-25T08:00:00Z') ],
      prs => [ pr(301, 'MERGED', 'Refs: #201', '2026-10-24T03:00:00Z', '$SYSC'), pr(302, 'MERGED', 'Closes #201', '2026-10-25T00:30:00Z', '$POST'),
        pr(303, 'MERGED', 'Closes #202', '2026-10-19T15:00:00Z', '$PRE'),
        pr(304, 'MERGED', 'Closes #203', '2026-10-19T15:00:00Z', '$PRE'), pr(305, 'MERGED', 'Closes #203', '2026-10-24T15:00:00Z', '$POST'),
        pr(306, 'MERGED', 'Closes #2031', '2026-10-26T00:00:00Z', '$PRE'),
        pr(307, 'MERGED', 'Refs: #204', '2026-10-24T15:00:00Z', '$POST'), pr(308, 'CLOSED', 'Closes #204', undef, undef),
        pr(309, 'MERGED', 'Closes #208', '2026-10-25T08:00:00Z', '0123456789abcdef0123456789abcdef01234567') ]"
}
drdb "2026-10-25T06:00:00Z"
for n in 201 206 207; do recv "$n"; done
run draft 202 --session S1
check "閉じる PR がデータのファイルを足したコミットより前にマージされた Issue に、draft が before-system の印を書いて 2 で終わり、集計のコメントを探してから、PR と Issue を report.pl と同じ gh のコマンドで読む" \
    "$RC/$(statejson issues/202.json)/$(calls)" \
    '2/{"closed_at":"2026-10-25T02:00:00Z","skip":"before-system"}/api --paginate repos/{owner}/{repo}/issues/202/comments|pr list --state all --base main --limit 1000 --json number,state,body,headRefName,mergedAt,mergeCommit|issue view 202 --json state,closedAt|'
run draft 203
check "閉じる PR がデータのファイルを足したコミットより後にマージされた Issue には、draft が集計しない印を書かない" \
    "$RC/$(statejson issues/203.json)" "0/none"
run draft 201
check "Refs: の PR の mergeCommit がデータのファイルを足したコミットと同じ Issue に、draft が system-pr の印を書いて 2 で終わる" \
    "$RC/$(statejson issues/201.json)" '2/{"closed_at":"2026-10-25T01:00:00Z","skip":"system-pr"}'
gitlogrun draft 204
check "Refs: の PR だけがあって閉じる PR の無い閉じた Issue で、draft が git merge-base を呼ばずに no-merged-pr の印を書く" \
    "$RC/$(statejson issues/204.json)/$(mergebases)" '2/{"closed_at":"2026-10-25T04:00:00Z","skip":"no-merged-pr"}/0'
gitlogrun draft 202
check "閉じる PR のある Issue では、draft が git merge-base を呼ぶ(偽の git が呼び出しを数えられる)" "$RC/$(mergebases)" "2/1"
run draft 205
check "開いていてマージ済みの Closes の PR が無い Issue で、draft が何も書かずに 2 で終わる" "$RC/$(statejson issues/205.json)" "2/none"
run draft 206
r206="$RC/$(statejson issues/206.json)"
run draft 207
check "まとめて閉じた Issue と分けた元の Issue で、draft が集計しない印を書いて 2 で終わる" "$r206/$RC/$(statejson issues/207.json)" \
    '2/{"closed_at":"2026-10-25T06:00:00Z","skip":"no-merged-pr"}/2/{"closed_at":"2026-10-25T07:00:00Z","skip":"no-merged-pr"}'
run pending
check "draft が集計しない印を書いた Issue を、次の pending が出さない" "$RC/$OUT" '0/{"issues":[]}'
drdb "2026-10-25T09:00:00Z"
run pending
check "まとめて閉じた Issue を開き直して閉じ直すと、また pending に出る" "$RC/$OUT" '0/{"issues":[206]}'
run draft 208
check "閉じる PR の mergeCommit が手元に無く、git merge-base --is-ancestor が 0 と 1 のほかの値で終わると、draft が 1 で終わる" \
    "$RC/$(errline)/$(statejson issues/208.json)" "1/one/none"
run draft 0
check "draft が、Issue の番号でない引数を受けない" "$RC/$(errline)" "1/one"
run draft 202 203
check "draft が、2つ目の Issue の番号を受けない" "$RC/$(errline)" "1/one"
check "draft が、終わるたびに Issue の錠を外す" "$([ -e "$STATE/locks/issue-202" ] || [ -e "$STATE/locks/issue-208" ] && printf left || printf none)" "none"

newgh dr-lock
drdb "2026-10-25T06:00:00Z"
mkdir -p "$STATE/locks/issue-203"
perl -e 'my $t = time - 700; utime $t, $t, $ARGV[0] or exit 1' "$STATE/locks/issue-203"
run draft 203
check "テストのための上書きが無いとき、draft が、700秒前の Issue の錠を、持ち主が止まった錠とみなして取り直す" \
    "$RC/$([ -e "$STATE/locks/issue-203" ] && printf left || printf none)" "0/none"
mkdir "$STATE/locks/issue-203"
: >"$FAKE_GH_DIR/calls.log"
(cd "$REPO" && exec bash "$USAGE" draft 203) >"$TMP_ROOT/bg-out" 2>"$TMP_ROOT/bg-err" &
bg=$!
sleep 2
held="$(calls)"
rmdir "$STATE/locks/issue-203"
wait "$bg"
bgrc=$?
check "テストのための上書きが無いとき、draft が、ほかの呼び出しが持つ新しい Issue の錠が外れるまで gh を呼ばずに待ち、外れたら続ける" \
    "$held/$bgrc/$(calls | grep -c 'issue view 203' | tr -d ' ')" "/0/1"
mkdir "$STATE/locks/issue-203"
: >"$FAKE_GH_DIR/calls.log"
KP_USAGE_TEST_ISSUE_LOCK_STALE=1
export KP_USAGE_TEST_ISSUE_LOCK_STALE
run draft 203
unset KP_USAGE_TEST_ISSUE_LOCK_STALE
check "テストのための上書きで錠の古さの上限を短くすると、draft が、外れない Issue の錠を取り直して続ける" \
    "$RC/$([ -e "$STATE/locks/issue-203" ] && printf left || printf none)" "0/none"

newgh dr-ghfail
drdb "2026-10-25T06:00:00Z"
printf '%s\n' '^pr list' >"$FAKE_GH_DIR/fail"
run draft 202
check "gh pr list が失敗すると、draft が 1 で終わり、理由を1行で出す" "$RC/$(errline)" "1/one"

newgh dr-fetch
drdb "2026-10-25T06:00:00Z"
gitq remote set-url origin "$WORK/no-such-repo"
run draft 202
check "git fetch が失敗すると draft が 1 で終わる" "$RC/$(errline)/$(calls)" "1/one/"

draftrepo dr-noconf noconfig
newgh dr-noconf
mkdb "issues => [ cl(202, '2026-10-25T02:00:00Z') ]"
run draft 202
check "origin/main にデータのファイルを足したコミットが無いとき、draft が issues/<N>.json に書かず、偽の gh を呼ばずに 2 で終わる" \
    "$RC/$(statejson issues/202.json)/$(calls)" "2/none/"

echo "== 集計の下書き"
# Issue 203 と、それを閉じる、仕組みが入ったあとにマージされた PR 305 だけの偽の GitHub
dwdb() { mkdb "issues => [ cl(203, '2026-10-25T03:00:00Z'${1-}) ], prs => [ pr(305, 'MERGED', 'Closes #203', '2026-10-24T15:00:00Z', '$POST') ]"; }
draftrepo dw
newgh dw
dwdb
mktrans dw-a 3
run draft 203
r1=$RC
c1=$(cat "$STATE/drafts/203/created_at" 2>/dev/null)
sleep 1
run draft 203
c2=$(cat "$STATE/drafts/203/created_at" 2>/dev/null)
check "draft を2回呼ぶと、drafts/<N>/ の created_at が2回目の時刻になる" \
    "$r1/$RC/$(perl -e 'my ($a1, $a2) = @ARGV; print $a2 =~ /\A[0-9]+\z/ && $a2 > $a1 && abs(time - $a2) <= 5 ? "later" : "c1=$a1 c2=$a2"' "${c1:-0}" "${c2:-x}")/$(ls "$STATE/drafts")" \
    "0/0/later/203"
check "draft が、下書きの場所を出し、会話の記録を抜き出して集計を作る" \
    "$(printf '%s' "$OUT" | perl -MJSON::PP -e 'local $/; print JSON::PP->new->decode(<STDIN>)->{draft}')/$(drafttokens)" "$STATE/drafts/203/12"
check "unknown.json があるとき、draft が値と回数を標準出力に出す" \
    "$(printf '%s' "$OUT" | perl -MJSON::PP -e 'local $/; print JSON::PP->new->canonical->encode(JSON::PP->new->decode(<STDIN>)->{unknown})')/$(cat "$STATE/drafts/203/unknown.json")" \
    '{"mystery-x":1}/{"mystery-x":1}'
printf '%s\n' '[{"issue":150,"url":"https://github.com/owner/repo/issues/150#issuecomment-5150","spec":false,"end_date":"2026-10-01","work_sec":600,"tokens":24,"usd":1,"usd_partial":false,"impl_spec_back":0}]' >"$TMP_ROOT/rows.json"
(cd "$REPO" && perl "$SCRIPTS/github.pl" list-add "$TMP_ROOT/rows.json") || ng "一覧に過去の行を足せない"
run draft 203
check "draft が、一覧の過去の行と比べた compare.json の要約を出す" \
    "$RC/$(printf '%s' "$OUT" | perl -MJSON::PP -e 'local $/; my $c = JSON::PP->new->decode(<STDIN>)->{compare}; my $t = $c->{values}[1];
        print join("/", $c->{past_rows}, scalar @{ $c->{values} }, map { $t->{$_} // "null" } qw(value_text median_text ratio rows))')" \
    "0/1/4/12/24/0.5/1"
check "draft が、作業のブランチの名前と会話の文を下書きの要約に出さない" "$(printf '%s' "$OUT" | grep -cE 'feat/pr305|"hi"' | tr -d ' ')" "0"

draftrepo dw-rep
newgh dw-rep
dwdb ", comments => [ cm(4001, rep(203)) ]"
run draft 203
check "集計のコメントがあって一覧に行が無い Issue で、draft が一覧に行を足して 2 で終わる" \
    "$RC/$(perl -MJSON::PP -e 'open my $f, "<", "$ENV{FAKE_GH_DIR}/db.json" or exit 1; local $/; my $db = JSON::PP->new->decode(<$f>);
        my @l = grep { $_->{number} != 203 } @{ $db->{issues} };
        print scalar(@l), "/", scalar(() = $l[0]{body} =~ m{^\| \[#203\]\(https://github\.com/owner/repo/issues/203#issuecomment-4001\) \|}mg)')" "2/1/1"
check "出し済みの Issue で、draft が issues/<N>.json に出した時刻と集計のコメントの URL を書き、PR を読まず、下書きを作らない" \
    "$(perl -MJSON::PP -e 'open my $f, "<", $ARGV[0] or exit 1; local $/; my $d = JSON::PP->new->decode(<$f>);
        print join(",", sort keys %$d), "/", $d->{report_url}, "/", $d->{reported_at} =~ /\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/ ? "time" : "bad"' "$STATE/issues/203.json")/$(calls | grep -c 'pr list' | tr -d ' ')/$([ -e "$STATE/drafts/203" ] && printf made || printf none)" \
    "report_url,reported_at/https://github.com/owner/repo/issues/203#issuecomment-4001/time/0/none"
run draft 203
check "出し済みの Issue で draft を呼び直すと、一覧の行を重ねず、出した時刻を書き直さずに 2 で終わる" \
    "$RC/$(perl -MJSON::PP -e 'open my $f, "<", "$ENV{FAKE_GH_DIR}/db.json" or exit 1; local $/; my $db = JSON::PP->new->decode(<$f>);
        my @l = grep { $_->{number} != 203 } @{ $db->{issues} }; print scalar(() = $l[0]{body} =~ m{^\| \[#203\]}mg)')" "2/1"

draftrepo dw-conc
newgh dw-conc
dwdb
mktrans dw-conc-a 60
# 1行読むたびに少し待つ extract.pl を裏で動かし、記録の鍵の錠を持って読んでいる間に draft を呼ぶ
mkdir -p "$STATE"
perl -e 'BEGIN { no warnings "once"; *CORE::GLOBAL::readline = sub { select(undef, undef, undef, 0.1); CORE::readline($_[0]) } }
    $0 = shift; do $0; die $@ if $@; exit 1' "$SCRIPTS/extract.pl" --state "$STATE" --all --skip-locked --repo "$REPO" &
slow=$!
i=0
while [ ! -d "$STATE/locks/extract-dw-conc-a" ] && [ "$i" -lt 100 ]; do
    sleep 0.1
    i=$((i + 1))
done
held=$([ -d "$STATE/locks/extract-dw-conc-a" ] && printf held || printf free)
run draft 203
during="$RC/$(drafttokens)"
wait "$slow"
run draft 203
check "裏の extract.pl --all --skip-locked が記録を読んでいる間に draft を呼んでも、集計の数が、裏の読み込みが終わってから呼んだときと同じになる" \
    "$held/$during/$RC/$(drafttokens)" "held/0/183/0/183"

draftrepo dw-xfail
newgh dw-xfail
dwdb
mktrans dw-xfail-a 1
# 記録の鍵の錠を持ったままにし、テストのための上書きで錠を待つ上限を1秒にする
mkdir -p "$STATE/locks/extract-dw-xfail-a"
KP_USAGE_TEST_LOCK_WAIT=1
export KP_USAGE_TEST_LOCK_WAIT
run draft 203
unset KP_USAGE_TEST_LOCK_WAIT
check "extract.pl が 1 で終わると、draft が report.pl を呼ばずに、下書きを作らずに 1 で終わる" \
    "$RC/$(errline)/$([ -e "$STATE/drafts/203" ] && printf made || printf none)/$(calls | grep -c 'pr list' | tr -d ' ')" "1/one/none/1"

echo "== 集計を出す"
# 一覧の書き込みのあと、読み直す前の10秒の待ちを外す
KP_USAGE_TEST_LIST_REREAD=0
export KP_USAGE_TEST_LIST_REREAD
# Issue 203 と、それを閉じる、仕組みが入ったあとにマージされた PR 305 と、一覧の Issue(番号 1)の偽の GitHub: pubdb [Issue 203 の欄]
pubdb() { mkdb "issues => [ list(), cl(203, '2026-10-25T03:00:00Z'${1-}) ], prs => [ pr(305, 'MERGED', 'Closes #203', '2026-10-24T15:00:00Z', '$POST') ]"; }
# 目立つ点の箇条1つと、直す案1つの所見のファイル
FINDINGS="$TMP_ROOT/findings.md"
printf '%s\n' '- 目立つ点の箇条' '' '### 直す案' '' '- [203-1] 案の文その1' >"$FINDINGS"
# 偽の GitHub の Issue N のコメントのうち、集計のコメントの数: reports <N>
reports() {
    perl -MJSON::PP -e 'open my $f, "<", "$ENV{FAKE_GH_DIR}/db.json" or exit 1; local $/; my $db = JSON::PP->new->decode(<$f>);
        my ($i) = grep { $_->{number} == $ARGV[0] } @{ $db->{issues} };
        print scalar grep { $_->{body} =~ /\A<!-- keirekipro-usage-report:v1 issue=$ARGV[0] -->/ } @{ $i->{comments} }' "$1"
}
# 偽の GitHub の一覧の Issue(番号 1)の本文にある、Issue N の行の数: listrows <N>
listrows() {
    perl -MJSON::PP -e 'open my $f, "<", "$ENV{FAKE_GH_DIR}/db.json" or exit 1; local $/; my $db = JSON::PP->new->decode(<$f>);
        my ($l) = grep { $_->{number} == 1 } @{ $db->{issues} };
        print scalar(() = $l->{body} =~ /^\| \[#$ARGV[0]\]\(/mg)' "$1"
}
# 偽の GitHub の案の索引にある案の ID を , でつなぐ
indexids() {
    perl -MJSON::PP -e 'open my $f, "<", "$ENV{FAKE_GH_DIR}/db.json" or exit 1; local $/; my $J = JSON::PP->new; my $db = $J->decode(<$f>);
        my ($l) = grep { $_->{number} == 1 } @{ $db->{issues} };
        my @ids = map { $_->{body} =~ /\A<!-- keirekipro-usage-proposals:v1 page=[0-9]+ (\[[^\n]*\]) -->/ ? map { $_->{id} } @{ $J->decode($1) } : () } @{ $l->{comments} };
        print join(",", sort @ids)'
}
# publish の出力の、url が Issue N の集計のコメントの URL か(url)と、proposals と、owner と、failed(並べ替えて , でつなぐ): pubout <N>
pubout() {
    printf '%s' "$OUT" | perl -MJSON::PP -e 'local $/; my $o = eval { JSON::PP->new->decode(<STDIN>) }; if (ref $o ne "HASH") { print "bad"; exit }
        print join("/", (($o->{url} // "") =~ m{\Ahttps://github\.com/owner/repo/issues/$ARGV[0]#issuecomment-[0-9]+\z} ? "url" : "nourl"),
            join(",", @{ $o->{proposals} || [] }), $o->{owner} // "null", join(",", sort @{ $o->{failed} || [] }))' "$1"
}
# 一覧の書き込みを失敗させる偽の gh の決まり(一覧の Issue の本文の書き直し)と、案の索引の書き込みを失敗させる決まり(一覧の Issue への新しいコメント)
FAIL_LIST='^issue edit 1 '
FAIL_INDEX='^issue comment 1 '

draftrepo pub
newgh pub
pubdb
mktrans pub-a 400
run draft 203
dr=$RC
run publish 203 --findings "$FINDINGS" --session S1
check "state.json に owner が無いと、publish が、集計のコメントの URL と案の ID と、owner に unknown を出し、両方に書けたときは書けなかった書き込みを空にして出す" \
    "$dr/$RC/$(pubout 203)" "0/0/url/203-1/unknown/"
url=$(printf '%s' "$OUT" | perl -MJSON::PP -e 'local $/; print JSON::PP->new->decode(<STDIN>)->{url} // ""' 2>/dev/null)
check "publish が、issues/<N>.json に reported_at と、その7日後の list_checked_until を書く" \
    "$(perl -MJSON::PP -MTime::Local=timegm -e 'open my $f, "<", $ARGV[0] or exit 1; local $/; my $d = JSON::PP->new->decode(<$f>);
        my @t = map { /\A([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z\z/ ? timegm($6, $5, $4, $3, $2 - 1, $1) : undef } map { $d->{$_} // "" } qw(reported_at list_checked_until);
        print join("/", (grep { !defined } @t) ? "bad" : ($t[1] - $t[0] == 7 * 86400 ? "7d" : "bad"), defined $t[0] && abs(time - $t[0]) <= 120 ? "now" : "old", $d->{report_url} // "null")' "$STATE/issues/203.json")" \
    "7d/now/$url"
check "publish が、Issue に集計のコメントを1つ書き、案を案の索引に足す" "$(reports 203)/$(indexids)" "1/203-1"
check "publish が一覧に1行を足し、その行の値が、同じ Issue の report.md の値と同じ形で書かれる" \
    "$(listrows 203)/$(perl -MJSON::PP -e 'open my $f, "<", "$ENV{FAKE_GH_DIR}/db.json" or exit 1; local $/; my $db = JSON::PP->new->decode(<$f>);
        my ($l) = grep { $_->{number} == 1 } @{ $db->{issues} };
        my ($row) = grep { /\A\| \[#203\]\(/ } split /\n/, $l->{body};
        my @c = map { s/\A\s+|\s+\z//gr } split /\|/, $row // "";
        open my $m, "<", $ARGV[0] or exit 1; my $md = <$m>;
        my %v = map { /\A\| (.+?) \| (.+?) \|\z/ ? ($1 => $2) : () } split /\n/, $md;
        my ($end, $spec) = $md =~ /^\| [0-9]{4}-[0-9]{2}-[0-9]{2} \| ([0-9]{4}-[0-9]{2}-[0-9]{2}) \| (\S+) \| #/m;
        my @want = ($spec, $end, map { $v{$_} } "AIの作業時間", "トークン数", "使用料");
        my $same = !grep { !defined $want[$_] || !defined $c[$_ + 2] || $want[$_] ne $c[$_ + 2] } 0 .. $#want;
        print $same ? "same/$c[5]" : "row=[" . join("|", map { $_ // "" } @c) . "] md=[" . join("|", map { $_ // "" } @want) . "]"' "$STATE/drafts/203/report.md")" \
    "1/same/1,203"
run publish 203 --findings "$FINDINGS"
check "出し済みの Issue で publish を呼ぶと、集計のコメントと一覧の行を重ねずに 2 で終わる" "$RC/$(reports 203)/$(listrows 203)" "2/1/1"

draftrepo pub-old
newgh pub-old
pubdb
mktrans pub-old-a 1
run publish 203 --findings "$FINDINGS"
check "下書きが無いと、publish が GitHub に書かずに 1 で終わり、理由を1行で出す" "$RC/$(errline)/$(calls | grep -c 'issue comment' | tr -d ' ')" "1/one/0"
run draft 203
KP_USAGE_TEST_DRAFT_MAX_AGE=1
export KP_USAGE_TEST_DRAFT_MAX_AGE
sleep 2
run publish 203 --findings "$FINDINGS"
unset KP_USAGE_TEST_DRAFT_MAX_AGE
check "下書きを作ってから上限の時間を過ぎると、publish が GitHub に書かずに、draft からやり直すよう返す" \
    "$RC/$(errline)/$(printf '%s' "$ERR" | grep -c 'draft' | tr -d ' ')/$(calls | grep -c 'issue comment' | tr -d ' ')/$(statejson issues/203.json)" "1/one/1/0/none"
perl -e 'print time - 3660, "\n"' >"$STATE/drafts/203/created_at"
run publish 203 --findings "$FINDINGS"
old="$RC/$(reports 203)"
perl -e 'print time - 3540, "\n"' >"$STATE/drafts/203/created_at"
run publish 203 --findings "$FINDINGS"
check "テストのための上書きが無いと、publish が、作ってから61分の下書きを出さず、59分の下書きを出す" "$old/$RC/$(reports 203)" "1/0/0/1"

draftrepo pub-priv
newgh pub-priv
pubdb
mktrans pub-priv-a 1
run draft 203
gitq config user.email owner-secret@example.com
for p in 'C:/Users/someone/a.txt' 'C:\Users\someone\a.txt' '/Users/someone/a.txt' '/home/someone/a.txt' "$HOME/a.txt" "$(id -un)" owner-secret@example.com; do
    printf -- '- 見た場所は %s である\n' "$p" >"$TMP_ROOT/findings-priv.md"
    : >"$FAKE_GH_DIR/calls.log"
    run publish 203 --findings "$TMP_ROOT/findings-priv.md"
    check "所見に $p を含むと、publish が書かずに 1 で終わる" "$RC/$(errline)/$(calls)/$(reports 203)" "1/one//0"
done

draftrepo pub-cfail
newgh pub-cfail
pubdb
mktrans pub-cfail-a 1
run draft 203
recv 203
printf '%s\n' '^issue comment 203 ' >"$FAKE_GH_DIR/fail"
run publish 203 --findings "$FINDINGS"
pub="$RC/$(errline)"
run pending
check "集計のコメントの書き込みが失敗すると publish が 1 で終わり、pending がその Issue を出し続ける" "$pub/$RC/$OUT/$(reports 203)" '1/one/0/{"issues":[203]}/0'

draftrepo pub-ifail
newgh pub-ifail
pubdb
mktrans pub-ifail-a 1
run owner yes
run draft 203
printf '%s\n' "$FAIL_INDEX" >"$FAKE_GH_DIR/fail"
run publish 203 --findings "$FINDINGS"
check "案の索引の書き込みが失敗すると、publish が 0 で終わって案の ID と owner を出し、書けなかった書き込みに proposals を出す" \
    "$RC/$(pubout 203)/$(reports 203)/$(listrows 203)/$(indexids)" "0/url/203-1/yes/proposals/1/1/"
rm -f "$FAKE_GH_DIR/fail"
run draft 203
check "案の索引に書けなかったあと、次の draft が案を索引に足して 2 で終わる" "$RC/$(indexids)/$(statejson issues/203.json | grep -c proposals_pending | tr -d ' ')" "2/203-1/0"
run proposal 203-1 declined
run draft 203
check "proposal で答えた案を、次の draft が案の索引に戻さない" "$RC/$(indexids)/$(listrows 203)" "2//1"

draftrepo pub-lfail
newgh pub-lfail
pubdb
mktrans pub-lfail-a 1
run owner no
run draft 203
printf '%s\n' "$FAIL_LIST" >"$FAKE_GH_DIR/fail"
run publish 203 --findings "$FINDINGS"
pub="$RC/$(pubout 203)/$(reports 203)/$(listrows 203)/$(indexids)"
run pending
check "一覧の書き込みが失敗すると、publish が 0 で終わり、書けなかった書き込みに list を出し、pending がその Issue を出す" \
    "$pub/$OUT" '0/url/203-1/no/list/1/0/203-1/{"issues":[203]}'
rm -f "$FAKE_GH_DIR/fail"
run draft 203
check "一覧に書けなかったあと、次の draft が行を一覧に足して 2 で終わる" "$RC/$(listrows 203)/$(statejson issues/203.json | grep -c list_pending | tr -d ' ')" "2/1/0"

draftrepo pub-bfail
newgh pub-bfail
pubdb
mktrans pub-bfail-a 1
run draft 203
printf '%s\n' "$FAIL_LIST" "$FAIL_INDEX" >"$FAKE_GH_DIR/fail"
run publish 203 --findings "$FINDINGS"
check "一覧と案の索引の両方に書けないと、publish が 0 で終わり、書けなかった書き込みに両方を出す" "$RC/$(pubout 203)/$(reports 203)" "0/url/203-1/unknown/list,proposals/1"

draftrepo pub-none
newgh pub-none
pubdb ", author_association => 'NONE'"
mktrans pub-none-a 1
run draft 203
dr=$RC
run publish 203 --findings "$FINDINGS"
check "関係の欄が NONE のアカウントが起票した Issue で、draft と publish が集計のコメントを書き、一覧に行を足す" "$dr/$RC/$(reports 203)/$(listrows 203)" "0/0/1/1"

draftrepo pub-conc
newgh pub-conc
pubdb
mktrans pub-conc-a 30
# draft のあとに publish を呼ぶ組を、裏で2つ同時に動かす
pubpair() { (cd "$REPO" && bash "$USAGE" draft 203 >/dev/null 2>&1 && bash "$USAGE" publish 203 --findings "$FINDINGS" >/dev/null 2>&1); }
pubpair &
p1=$!
pubpair &
p2=$!
wait "$p1"
wait "$p2"
check "draft と publish の組を2つ同時に動かしても、集計のコメントは1つだけ書かれる" "$(reports 203)/$(listrows 203)" "1/1"

echo "== 会話の始めに知らせる文"
# 7日の間を過ぎた時刻と、まだ過ぎない時刻
PAST="2026-01-01T00:00:00Z"
FUTURE="2099-01-01T00:00:00Z"
# 知らせる文の行の、Issue の番号(issue)と、出し直す書き込み(write)と、所有者の行(owner)と、案(案の ID)と、
# 所有者かどうか(undecided)を , でつなぐ
ctxlines() {
    printf '%s\n' "$OUT" | perl -ne '
        chomp; next unless length;
        if (/\A\[usage\] Issue #([0-9]+) を閉じる PR がマージされ、/) { push @o, "issue$1" }
        elsif (/\A\[usage\] Issue #([0-9]+) の集計は GitHub に出したが、/) { push @o, "write$1" }
        elsif ($_ eq "[usage] 会話の相手: 所有者") { push @o, "owner" }
        elsif (/\A\[usage\] まだ答えていない直す案がある: (.*?)。/) { push @o, map { /\A([0-9]+-[0-9]+)（Issue #[0-9]+）\z/ ? $1 : "bad" } split /、/, $1 }
        elsif (/\A\[usage\] この PC で Claude と話す人が所有者かどうかが、まだ決まっていない/) { push @o, "undecided" }
        else { push @o, "unknown-line" }
        END { print join(",", @o) }'
}
# 一覧に Issue N の行を足す: ctxrow <N>
ctxrow() {
    printf '[{"end_date":"2026-10-25","impl_spec_back":0,"issue":%s,"spec":false,"tokens":12,"url":"https://github.com/owner/repo/issues/%s#issuecomment-9","usd":0.5,"usd_partial":false,"work_sec":600}]\n' "$1" "$1" >"$TMP_ROOT/row.json"
    (cd "$REPO" && perl "$SCRIPTS/github.pl" list-add "$TMP_ROOT/row.json") >/dev/null 2>&1 || ng "一覧に行を足せない"
}
newrepo ctx config
newgh ctx
# 101: 出していない、閉じた Issue / 105: 開いた Issue / 107: 出し済みで list_pending がある Issue
# 120: 出してから7日の間で、一覧に行が無い Issue / 121: 出してから7日の間で、一覧に行がある Issue
# 122: 出してから7日を過ぎ、一覧に行が無い Issue / 123: 出してから7日の間で、一覧に行が無く、集計しない印がある Issue
mkdb "issues => [ list(), cl(101, '2026-10-25T01:00:00Z'), op(105), cl(107, '2026-10-25T02:00:00Z'), cl(120, '2026-10-25T03:00:00Z'),
    cl(121, '2026-10-25T04:00:00Z'), cl(122, '2026-10-25T05:00:00Z'), cl(123, '2026-10-25T06:00:00Z') ]"
for n in 101 105; do recv "$n"; done
ctxrow 121
issuejson 107 '{"list_pending":true,"report_url":"https://github.com/owner/repo/issues/107#issuecomment-1","reported_at":"2026-10-25T02:10:00Z"}'
for n in 120 121 123; do
    issuejson "$n" "{\"list_checked_until\":\"$FUTURE\",\"report_url\":\"https://github.com/owner/repo/issues/$n#issuecomment-2\",\"reported_at\":\"2026-10-25T03:10:00Z\"}"
done
issuejson 122 "{\"list_checked_until\":\"$PAST\",\"report_url\":\"https://github.com/owner/repo/issues/122#issuecomment-3\",\"reported_at\":\"2026-10-25T05:10:00Z\"}"
issuejson 123 "{\"closed_at\":\"2026-10-25T06:00:00Z\",\"list_checked_until\":\"$FUTURE\",\"reported_at\":\"2026-10-25T06:10:00Z\",\"skip\":\"system-pr\"}"
: >"$FAKE_GH_DIR/calls.log"
run session-context --session S1
check "session-context が、閉じた Issue だけを知らせ、gh が失敗したら何も知らせずに 0 で終わる(閉じた Issue だけを知らせる)" \
    "$RC/$(ctxlines)/$ERR" "0/issue101,write107,write120/"
check "出してから7日の間の Issue の行が一覧に無いと、list_pending を書き直してその Issue を知らせる" \
    "$(statejson issues/120.json | grep -c '"list_pending":true')/$(statejson issues/121.json | grep -c list_pending)/$(statejson issues/122.json | grep -c list_pending)/$(statejson issues/123.json | grep -c list_pending)" "1/0/0/0"
# gh の呼び出しが、閉じた Issue の一覧を読む呼び出しと、本文や欄を付けない gh api の読み取りだけか
check "session-context が gh で GitHub に書かない" \
    "$([ -n "$(calls)" ] && printf called)/$(calls | tr '|' '\n' | grep -v '^$' | grep -vcE '^(issue list |api )')/$(calls | tr '|' '\n' | grep -cE '^api .*(^| )(-X|--method|-f|-F|--field|--raw-field|--input)( |=|$)')" "called/0/0"
check "知らせる文が、usage-report のスキルの手順を指し、所有者に打たせるコマンドを含まない" \
    "$(nlines "$OUT")/$(printf '%s\n' "$OUT" | grep -v "usage-report のスキルの『" | grep -vc '^\[usage\] 会話の相手: 所有者$')/$(printf '%s\n' "$OUT" | grep -cE 'usage\.sh|`|/[a-z]|gh |打')" "3/0/0"
run session-context
check "session-context が、出し直した list_pending の Issue を、次の会話でも知らせる" "$RC/$(ctxlines)" "0/issue101,write107,write120"
for re in '^issue list' '^api '; do
    printf '%s\n' "$re" >"$FAKE_GH_DIR/fail"
    run session-context
    check "session-context が、閉じた Issue だけを知らせ、gh が失敗したら何も知らせずに 0 で終わる(失敗させた gh の呼び出し: $re)" "$RC/$OUT/$ERR" "0//"
done
rm -f "$FAKE_GH_DIR/fail"
# gh が10秒を超える場合。テストだけ、待つ上限を KP_USAGE_TEST_CONTEXT_TIMEOUT で2秒にする。
# 遅い gh は、動き出したことを slow-started に残してから待つ。gh が動き出せずに失敗した場合と見分けるためである
mkdir -p "$TMP_ROOT/slowbin"
printf '#!/usr/bin/env bash\n: >"%s/slow-started"\nsleep 30\nexec "%s/bin/gh" "$@"\n' "$TMP_ROOT" "$TMP_ROOT" >"$TMP_ROOT/slowbin/gh"
chmod +x "$TMP_ROOT/slowbin/gh"
t0=$(date +%s)
PATH="$TMP_ROOT/slowbin:$PATH" KP_USAGE_TEST_CONTEXT_TIMEOUT=2 run session-context
t1=$(date +%s)
check "gh が待つ上限を超えると、session-context が何も出さずに 0 で終わる" \
    "$RC/$OUT/$ERR/$([ -e "$TMP_ROOT/slow-started" ] && printf started)/$([ $((t1 - t0)) -lt 15 ] && printf fast || printf slow)" "0///started/fast"

newrepo ctx-noconf
newgh ctx-noconf
recv 101
mkdb "issues => [ cl(101, '2026-10-25T01:00:00Z') ]"
run session-context
check "origin/main にデータのファイルを足したコミットが無いとき、session-context が何も出さずに 0 で終わり、偽の gh を呼ばない" \
    "$RC/$OUT/$ERR/$(calls)" "0///"

newrepo ctx-owner config
newgh ctx-owner
# 案の索引に、関係の欄が OWNER のコメントの案 501-1 と、NONE のコメントの案 502-1 がある
mkdb 'issues => [ list(cm(2001, idx("501-1")), { %{ cm(2002, idx("502-1")) }, author_association => "NONE" }),
    cl(501, "2026-10-20T01:00:00Z", comments => [ cm(3001, props(501, "- [501-1] 案の文その1")) ]),
    cl(502, "2026-10-20T02:00:00Z", comments => [ cm(3002, props(502, "- [502-1] 案の文その2")) ]) ]'
run session-context
check "owner が無く案があると、所有者かどうかがまだ決まっていないと知らせ、owner が偽の PC では案を知らせない(owner が無い)" "$RC/$(ctxlines)" "0/undecided"
check "所有者かどうかがまだ決まっていないと知らせる行が、usage-report のスキルの手順を指し、所有者に打たせるコマンドを含まない" \
    "$(printf '%s\n' "$OUT" | grep -c "usage-report のスキルの『所有者かを尋ねるとき』")/$(printf '%s\n' "$OUT" | grep -cE 'usage\.sh|`|/[a-z]|gh |打')" "1/0"
run owner yes
run session-context
check "関係の欄の違う案の索引のコメントの案を知らせない" "$RC/$(ctxlines)" "0/owner,501-1"
check "owner が真の PC で、案の行が、usage-report のスキルの手順を指す" \
    "$(printf '%s\n' "$OUT" | grep '^\[usage\] まだ答えていない直す案がある: ' | grep -c "usage-report のスキルの『案を尋ねるとき』")" "1"
run owner no
: >"$FAKE_GH_DIR/calls.log"
run session-context
check "owner が無く案があると、所有者かどうかがまだ決まっていないと知らせ、owner が偽の PC では案を知らせない(owner が偽)" "$RC/$OUT/$(calls | tr '|' '\n' | grep -c '^api ')" "0//0"

newrepo ctx-noprop config
newgh ctx-noprop
mkdb 'issues => [ list(cm(2002, idx())) ]'
run session-context
check "owner が無く、まだ答えていない案が無いと、session-context が所有者の行を出さない" "$RC/$OUT" "0/"

echo "== さかのぼりの集計の対象"
# 終了日は所有者の PC の時間帯の日付なので、日本の時間帯で確かめる。協定世界時と日付が違う時刻を使う
SAVED_TZ=${TZ-unset}
TZ=JST-9
export TZ
draftrepo bf
newgh bf
# 401: 受け持ちの出来事がある。閉じる PR は日本の時間帯の 10-20 01:00 にマージされた
# 402: ブランチ feat/pr412 の会話の記録がある。閉じる PR 412 は 10-20 00:30 にマージされた(401 より先)
# 403: start でない段階の印がある。閉じる PR は日本の時間帯の 10-19 00:30(協定世界時では 10-18)にマージされた
# 404: 受け持ちの出来事がある。閉じる PR は日本の時間帯の 10-18 23:00 にマージされた
# 405: 仕組みを main に入れた Issue。PR 415 が Refs: を書き、閉じる PR 416 は仕組みが入ったあとにマージされた
# 406: 受け持ちの出来事がある。閉じる PR は仕組みが入ったあとにマージされた
# 407: 手元の記録が無い。閉じる PR は仕組みが入る前にマージされた
# 408: 受け持ちの出来事がある。Refs: の PR だけがあり、閉じる PR が無い
# 409: 受け持ちの出来事がある。出し済みで、一覧と案の索引への書き込みが残っていない
# 410: 受け持ちの出来事がある。出し済みで、一覧への書き込みが残っている。閉じる PR は 10-21 にマージされた
# 412: 仕組みを main に入れた Issue。PR 423 が Refs: だけを書き、閉じる PR がまだ無い
mkdb "issues => [],
  prs => [ pr(411, 'MERGED', 'Closes #401', '2026-10-19T16:00:00Z', '$PRE'), pr(412, 'MERGED', \"text\nCloses #402\", '2026-10-19T15:30:00Z', '$PRE'),
    pr(413, 'MERGED', 'Closes #403', '2026-10-18T15:30:00Z', '$PRE'), pr(414, 'MERGED', 'Closes #404', '2026-10-18T14:00:00Z', '$PRE'),
    pr(415, 'MERGED', 'Refs: #405', '2026-10-24T03:00:00Z', '$SYSC'), pr(416, 'MERGED', 'Closes #405', '2026-10-25T00:00:00Z', '$POST'),
    pr(417, 'MERGED', 'Closes #406', '2026-10-24T15:00:00Z', '$POST'), pr(418, 'MERGED', 'Closes #407', '2026-10-19T00:00:00Z', '$PRE'),
    pr(419, 'MERGED', 'Refs: #408', '2026-10-19T00:00:00Z', '$PRE'), pr(420, 'MERGED', 'Closes #409', '2026-10-19T00:00:00Z', '$PRE'),
    pr(421, 'MERGED', 'Closes #410', '2026-10-21T00:00:00Z', '$PRE'), pr(423, 'MERGED', 'Refs: #412', '2026-10-24T03:00:00Z', '$SYSC') ]"
for n in 401 404 406 408 409 410; do recv "$n"; done
xrow s2 '{"issue":403,"k":"stage","name":"ship","spec_stage":null,"ts":1761300000}'
mktrans bf-a 1 "$REPO" feat/pr412
issuejson 409 '{"report_url":"https://github.com/owner/repo/issues/409#issuecomment-1","reported_at":"2026-10-25T00:00:00Z"}'
issuejson 410 '{"list_pending":true,"report_url":"https://github.com/owner/repo/issues/410#issuecomment-2","reported_at":"2026-10-25T00:00:00Z"}'
run backfill-list
check "backfill-list が、仕組みが入る前にマージされた PR が閉じた、手元の記録に受け持ちかブランチの行がある Issue と、仕組みを入れた Issue を、終了日の古い順に、同じ日なら番号の小さい順に出し、PR の一覧を1回だけ読む" \
    "$RC/$OUT/$(calls)" '0/{"issues":[404,403,401,402,410,405],"waiting":[412]}/pr list --state all --base main --limit 1000 --json number,state,body,headRefName,mergedAt,mergeCommit|'
check "そのコミットの PR が本文に Refs: だけを書き、その Issue を閉じる PR がまだ無いとき、backfill-list がその番号を issues に入れず、waiting に入れる" \
    "$(printf '%s' "$OUT" | grep -o '"waiting":\[412\]')/$(printf '%s' "$OUT" | grep -o '"issues":\[[^]]*\]' | grep -c 412)" '"waiting":[412]/0'

draftrepo bf-noconf noconfig
newgh bf-noconf
recv 401
mkdb "issues => [], prs => [ pr(411, 'MERGED', 'Closes #401', '2026-10-19T16:00:00Z', undef) ]"
run backfill-list
check "origin/main にデータのファイルを足したコミットが無いとき、backfill-list が偽の gh を呼ばずに 2 で終わる" "$RC/$OUT/$(calls)" "2//"

draftrepo bf-wt
newgh bf-wt
mkdb "issues => [], prs => [ pr(431, 'MERGED', 'Closes #430', '2026-10-19T16:00:00Z', '$PRE') ]"
mktrans bf-wt-a 1 "$REPO/.claude/worktrees/gone" feat/pr431
gitq worktree add -q "$WORK/bf-wt-here" -b feat/here
runin "$WORK/bf-wt-here" backfill-list
check "worktree の作業フォルダから backfill-list を呼んでも、git worktree list に無い、本体の作業フォルダの下の .claude/worktrees/<名前> を cwd に持つ記録の Issue が候補に入る" \
    "$RC/$OUT" '0/{"issues":[430],"waiting":[]}'

draftrepo bf-fail
newgh bf-fail
recv 401
mkdb "issues => [], prs => [ pr(411, 'MERGED', 'Closes #401', '2026-10-19T16:00:00Z', '$PRE') ]"
printf '%s\n' '^pr list' >"$FAKE_GH_DIR/fail"
run backfill-list
check "偽の gh が失敗すると、backfill-list が 1 で終わり、標準出力に何も出さない" "$RC/$OUT/$(errline)" "1//one"
rm -f "$FAKE_GH_DIR/fail"
mkdb "issues => [], prs => [ pr(411, 'MERGED', 'Closes #401', '2026-10-19T16:00:00Z', '0123456789abcdef0123456789abcdef01234567') ]"
run backfill-list
check "閉じる PR のコミットが手元に無く、祖先かを確かめられないとき、backfill-list が 1 で終わり、標準出力に何も出さない" "$RC/$OUT/$(errline)" "1//one"
if [ "$SAVED_TZ" = unset ]; then unset TZ; else TZ=$SAVED_TZ; fi

echo "== さかのぼりの集計の下書き"
# 下書きの report.json の backfill: bfflag <N>
bfflag() { perl -MJSON::PP -e 'open my $f, "<", $ARGV[0] or do { print "none"; exit }; local $/; my $d = JSON::PP->new->decode(<$f>); print $d->{backfill} ? "true" : "false"' "$STATE/drafts/$1/report.json"; }
# 目立つ点の箇条だけの所見のファイル
FINDINGS_PLAIN="$TMP_ROOT/findings-plain.md"
printf '%s\n' '- 目立つ点の箇条' >"$FINDINGS_PLAIN"
draftrepo bfd
newgh bfd
# 501: 仕組みが入る前に閉じた、印の無い Issue。閉じる PR 511 は仕組みが入る前のコミットである
# 502: 仕組みが入る前に閉じた、before-system の印がすでにある Issue
# 503: 仕組みを main に入れた Issue。PR 513 が Refs: を書き、閉じる PR 514 は仕組みが入ったあとにマージされた
# 504: 閉じる PR 515 が仕組みが入ったあとにマージされた Issue
# 505: 仕組みを main に入れた Issue。PR 516 が Refs: だけを書き、閉じる PR がまだ無い
# 506: 仕組みが入る前に閉じた、印の無い Issue(--backfill を付けない draft で確かめる)
# 507: 仕組みが入ったあとに閉じた、受け持ちの出来事がある、まだ出していない Issue
mkdb "issues => [ list(), cl(501, '2026-10-23T20:00:00Z'), cl(502, '2026-10-23T21:00:00Z'), cl(503, '2026-10-25T01:00:00Z'),
    cl(504, '2026-10-25T02:00:00Z'), cl(505, '2026-10-25T03:00:00Z'), cl(506, '2026-10-23T22:00:00Z'), cl(507, '2026-10-25T04:00:00Z') ],
  prs => [ pr(511, 'MERGED', 'Closes #501', '2026-10-24T15:00:00Z', '$PRE'), pr(512, 'MERGED', 'Closes #502', '2026-10-24T15:00:00Z', '$PRE'),
    pr(513, 'MERGED', 'Refs: #503', '2026-10-24T03:00:00Z', '$SYSC'), pr(514, 'MERGED', 'Closes #503', '2026-10-24T15:00:00Z', '$POST'),
    pr(515, 'MERGED', 'Closes #504', '2026-10-24T15:00:00Z', '$POST'), pr(516, 'MERGED', 'Refs: #505', '2026-10-24T03:00:00Z', '$SYSC'),
    pr(517, 'MERGED', 'Closes #506', '2026-10-24T15:00:00Z', '$PRE') ]"
mktrans bfd-a 1 "$REPO" feat/pr511
mktrans bfd-b 1 "$REPO" feat/pr512
mktrans bfd-c 1 "$REPO" feat/pr514
mktrans bfd-d 1 "$REPO" feat/pr515
mktrans bfd-e 1 "$REPO" feat/pr517
issuejson 502 '{"closed_at":"2026-10-23T21:00:00Z","skip":"before-system"}'
run draft 502 --backfill
d502="$RC/$(bfflag 502)/$(statejson issues/502.json)"
run draft 501 --backfill
d501="$RC/$(bfflag 501)/$(statejson issues/501.json)"
run draft 503 --backfill
d503="$RC/$(bfflag 503)/$(statejson issues/503.json)"
run draft 504 --backfill
d504="$RC/$(bfflag 504)/$(statejson issues/504.json)"
run draft 506
d506="$RC/$(bfflag 506)/$(statejson issues/506.json)"
check "draft <N> --backfill が、before-system の印がある Issue と、印を書いた仕組みが入る前の Issue と、system-pr の印を書いた仕組みを入れた Issue で backfill が真の下書きを作り、閉じる PR が仕組みのあとの Issue では書かずに 2 で終わる。--backfill の無い draft は before-system の印を書いて 2 で終わる" \
    "$d502|$d501|$d503|$d504|$d506" \
    '0/true/{"closed_at":"2026-10-23T21:00:00Z","skip":"before-system"}|0/true/{"closed_at":"2026-10-23T20:00:00Z","skip":"before-system"}|0/true/{"closed_at":"2026-10-25T01:00:00Z","skip":"system-pr"}|2/none/none|2/none/{"closed_at":"2026-10-23T22:00:00Z","skip":"before-system"}'
run draft 505 --backfill
check "そのコミットの PR が本文に Refs: だけを書き、その Issue を閉じる PR がまだ無いとき、draft <N> --backfill が system-pr の印を書いて 2 で終わる" \
    "$RC/$(bfflag 505)/$(statejson issues/505.json)" '2/none/{"closed_at":"2026-10-25T03:00:00Z","skip":"system-pr"}'
run draft 501 --frobnicate
check "draft が、--backfill のほかの2つ目の引数を受けない" "$RC/$(errline)" "1/one"

run owner no
printf '%s\n' '^issue comment 501 ' '^issue comment 503 ' >"$FAKE_GH_DIR/fail"
run publish 501 --findings "$FINDINGS_PLAIN"
p501=$RC
run publish 503 --findings "$FINDINGS_PLAIN"
p503=$RC
for n in 501 503 507; do recv "$n"; done
run pending
pend="$RC/$OUT"
run session-context
check "draft <N> --backfill のあとに publish が失敗した、仕組みが入る前に閉じた Issue と仕組みを入れた Issue を、次の pending が出さず、session-context もその Issue の文を作らない" \
    "$p501/$p503/$pend/$RC/$(ctxlines)" '1/1/0/{"issues":[507]}/0/issue507'
printf '%s\n' "$FAIL_LIST" >"$FAKE_GH_DIR/fail"
run publish 502 --findings "$FINDINGS_PLAIN"
pub="$RC/$(pubout 502)/$(reports 502)/$(listrows 502)"
run pending
check "draft <N> --backfill のあとに集計のコメントを書き、一覧の書き込みが失敗した Issue で、publish が 0 で終わって書けなかった書き込みに list を出し、次の pending はその Issue を出さない" \
    "$pub/$RC/$OUT" '0/url//no/list/1/0/0/{"issues":[507]}'
rm -f "$FAKE_GH_DIR/fail"
run backfill-list
bl="$RC/$OUT"
run draft 502 --backfill
check "一覧に書けなかったあと、backfill-list がその Issue を出し、draft <N> --backfill が一覧にその行を足して 2 で終わる" \
    "$bl/$RC/$(listrows 502)" '0/{"issues":[501,502,503,506],"waiting":[505]}/2/1'

echo "== 案と所有者"
newrepo prop config
newgh prop
mkdb 'issues => [ list(cm(2001, idx("501-1"))), cl(501, "2026-10-25T01:00:00Z", comments => [ cm(3001, props(501, "- [501-1] 案の文その1")) ]) ]'
run owner yes --session S1
check "owner が無い PC で owner yes を呼ぶと、state.json に owner が真で書かれる" "$RC/$(statejson state.json)" '0/{"owner":true}'
run proposals --session S1
check "owner が無い PC で owner yes を呼んだあと、proposals が、まだ答えていない案の ID と Issue の番号と案の文を出す" \
    "$RC/$OUT" '0/[{"id":"501-1","issue":501,"text":"案の文その1"}]'
issuejson 501 '{"proposals_pending":["501-1","501-2"]}'
: >"$FAKE_GH_DIR/calls.log"
run proposal 501-1 maybe
check "proposal が、filed と declined のほかの答えを受けず、gh を呼ばない" "$RC/$(errline)/$(calls)" "1/one/"
for id in 1a-1 1-1x 12345678901-1 501-01 501-1234567; do
    run proposal "$id" declined
    check "proposal が、形の違う案の ID $id を受けず、1 で終わり、理由を1行で出し、gh を呼ばない" "$RC/$(errline)/$(calls)" "1/one/"
done
run proposal 501-1 declined --session S1
check "proposal <ID> declined が、案を issues/<N>.json の proposals_pending から外す" "$RC/$(statejson issues/501.json)" '0/{"proposals_pending":["501-2"]}'
run proposals
check "proposal <ID> declined で答えた案を proposals が出さない" "$RC/$OUT" '0/[]'
run proposal 501-2 filed
check "proposal <ID> filed が、最後の案を外すと proposals_pending を消す" "$RC/$(statejson issues/501.json)" '0/{}'

newrepo owner config
newgh owner
mkdir -p "$STATE"
printf '%s\n' '{"list_issue":1}' >"$STATE/state.json"
run owner no
check "state.json に list_issue があるときに owner no を呼ぶと、owner が偽で書かれ、list_issue が残る" "$RC/$(statejson state.json)" '0/{"list_issue":1,"owner":false}'
run owner yes
check "state.json に list_issue があるときに owner yes を呼ぶと、owner が書かれ、list_issue が残る" "$RC/$(statejson state.json)" '0/{"list_issue":1,"owner":true}'
run owner maybe
check "owner が、yes と no のほかの答えを受けず、state.json を変えない" "$RC/$(errline)/$(statejson state.json)" '1/one/{"list_issue":1,"owner":true}'
printf '%s\n' '{"list_issue":1,' >"$STATE/state.json"
run owner yes
check "state.json が JSON のオブジェクトとして読めないとき、owner が 1 で終わり、理由を1行で出し、state.json を変えない" \
    "$RC/$(errline)/$(statejson state.json)" '1/one/{"list_issue":1,'
check "owner が state.json の一時ファイルを残さない" "$(find "$STATE" -name 'state.json.*' | wc -l | tr -d ' ')" "0"
check "owner が gh を呼ばない" "$(calls)" ""

echo "== 呼び出しの形"
run
check "サブコマンドが無いと、1 で終わり、理由を1行で出す" "$RC/$(errline)" "1/one"
run frobnicate
check "知らないサブコマンドを受けると、1 で終わり、理由を1行で出す" "$RC/$(errline)" "1/one"
run pending --session
check "--session に会話の ID が無いと、1 で終わり、理由を1行で出す" "$RC/$(errline)" "1/one"
runin "$WORK" pending
check "git のリポジトリの外で呼ぶと、1 で終わり、理由を1行で出す" "$RC/$(errline)" "1/one"

echo "== フックと設定と手順の文書"
# 作業フォルダの最上位(このテストは .claude/scripts/usage/tests/ にある)
ROOT="$(cd "$HERE/../../../.." && pwd)"
HOOK="$ROOT/.claude/hooks/usage-hook.sh"
# 偽の extract.pl を置いた作業フォルダ。受けた引数と標準入力をそのまま出し、3 で終わる
FAKEP="$WORK/fakeproj"
mkdir -p "$FAKEP/.claude/scripts/usage"
cat >"$FAKEP/.claude/scripts/usage/extract.pl" <<'EOF'
binmode STDIN; binmode STDOUT;
print "args=@ARGV\n";
local $/;
print scalar(<STDIN>) // '';
exit 3;
EOF
mkdir -p "$WORK/hookcwd"
out=$(printf 'line1\n{"a":1}' | (cd "$WORK/hookcwd" && CLAUDE_PROJECT_DIR="$FAKEP" bash "$HOOK"))
check "usage-hook.sh が入力をそのまま extract.pl hook に渡して出力を返し、extract.pl が失敗しても 0 で終わる" \
    "$?|$out" "0|args=hook
line1
{\"a\":1}"
newrepo hookrepo
out=$(printf '{"session_id":"hk1","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"toolu_H1","duration_ms":34}' "$REPO" |
    (cd "$ROOT/.claude" && CLAUDE_PROJECT_DIR="$ROOT" bash "$HOOK"))
RC=$?
check "usage-hook.sh を作業フォルダの最上位でないディレクトリから、CLAUDE_PROJECT_DIR に最上位を入れて動かすと、extract.pl が動いて durations/ に行が足される" \
    "$RC|$out|$(cat "$STATE/durations/hk1.tsv" 2>/dev/null)" "0||toolu_H1	34"

# settings.json の、usage-hook.sh を呼ぶフックを「時点/matcher/async か timeout」で並べ、許可の有無と、
# usage-hook.sh を呼ぶのに決まったコマンドの形でないフックの数を添える
hookregs() {
    perl -MJSON::PP -e '
        local $/;
        open my $f, "<", $ARGV[0] or do { print "none"; exit };
        my $d = JSON::PP->new->decode(<$f>);
        my $c = q{bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/usage-hook.sh"};
        my (@got, $bad);
        for my $ev (sort keys %{ $d->{hooks} }) {
            for my $g (@{ $d->{hooks}{$ev} }) {
                for my $h (@{ $g->{hooks} }) {
                    next unless ($h->{command} // "") =~ /usage-hook/;
                    $bad++ if $h->{command} ne $c;
                    my $how = JSON::PP::is_bool($h->{async}) && $h->{async} ? "async"
                        : defined $h->{timeout} ? "timeout$h->{timeout}" : "none";
                    push @got, "$ev/" . ($g->{matcher} // "-") . "/$how";
                }
            }
        }
        my $allow = grep { $_ eq q{Bash(bash .claude/scripts/usage/usage.sh *)} } @{ $d->{permissions}{allow} };
        print join(" ", @got), " allow=$allow bad=", $bad // 0;
    ' "$1"
}
check "settings.json に、Stop・SubagentStop・SessionEnd・PostToolUse(matcher *)の async の登録と、SessionStart の timeout 10 の登録と、Bash(bash .claude/scripts/usage/usage.sh *) の許可がある" \
    "$(hookregs "$ROOT/.claude/settings.json")" \
    "PostToolUse/*/async SessionEnd/-/async SessionStart/-/timeout10 Stop/-/async SubagentStop/-/async allow=1 bad=0"
# usage-hook.sh を書いた行の数も数え、フックのコマンドのほかに usage-hook.sh を呼ぶ書き方が無いことを確かめる
check "settings.json の完成版の、足したフックのコマンドが、どれも bash \"\${CLAUDE_PROJECT_DIR}/.claude/hooks/usage-hook.sh\" である" \
    "$(hookregs "$ROOT/.claude/settings.json" | sed 's/.* bad=//')/$(grep -c 'usage-hook' "$ROOT/.claude/settings.json")" "0/5"

# 文書 $1 に、拡張正規表現 $2 に合う行があれば yes を出す
hasline() { if grep -qE -- "$2" "$1"; then printf yes; else printf no; fi; }
# 文書 $1 の、$2 に合う行から続く $3 行のどこかに、$4 に合う行があれば yes を出す
hasnear() { if grep -E -A"$3" -- "$2" "$1" | grep -qE -- "$4"; then printf yes; else printf no; fi; }
SK="$ROOT/.claude/skills"
UR="$SK/usage-report/SKILL.md"
check "usage-report の SKILL.md に、5つの時点の見出しと、usage.sh の draft・publish・proposals・proposal・owner・backfill-list と draft --backfill を呼ぶ行と、所見の決まりの見出しがある" \
    "$(hasline "$UR" '^### マージを見届けたとき$')$(hasline "$UR" '^### 次の会話で出すとき$')$(hasline "$UR" '^### 案を尋ねるとき$')$(hasline "$UR" '^### 所有者かを尋ねるとき$')$(hasline "$UR" '^### さかのぼりの集計を頼まれたとき$') $(hasline "$UR" 'usage\.sh draft <N>')$(hasline "$UR" 'usage\.sh publish <N>')$(hasline "$UR" 'usage\.sh proposals')$(hasline "$UR" 'usage\.sh proposal <')$(hasline "$UR" 'usage\.sh owner (yes|no)')$(hasline "$UR" 'usage\.sh backfill-list')$(hasline "$UR" 'usage\.sh draft <N> --backfill') $(hasline "$UR" '^## 所見の決まり$')" \
    "yesyesyesyesyes yesyesyesyesyesyesyes yes"
check "ship の SKILL.md の MERGED の行が usage-report の手順を指し、同じ失敗の3回目の箇所が mark same-failure を呼ぶ" \
    "$(hasline "$SK/ship/SKILL.md" 'MERGED.*usage-report のスキル.*マージを見届けたとき')$(hasnear "$SK/ship/SKILL.md" '同じ失敗が3回続いたとき' 2 'usage\.sh mark same-failure')" "yesyes"
check "spec-review の SKILL.md が changed のときに mark spec-fix を呼ぶ" \
    "$(hasline "$SK/spec-review/SKILL.md" 'changed.*usage\.sh mark spec-fix --stage')" "yes"
check "start の SKILL.md の spec に切り替えるときの箇所が mark switch-to-spec を呼ぶ" \
    "$(hasnear "$SK/start/SKILL.md" 'spec に切り替えるとき' 2 'usage\.sh mark switch-to-spec --issue')" "yes"
check "CLAUDE.md に mark same-failure の行と usage-report の行がある" \
    "$(hasline "$ROOT/CLAUDE.md" '同一の失敗が3回.*usage\.sh mark same-failure')$(hasline "$ROOT/CLAUDE.md" 'usage-report.*スキルに従う')" "yesyes"

# Claude Code が決めている欄の名前と値。読むのは extract.pl だけにする
CCNAMES="stop_reason turnOrigin hook_event_name cliSessionId AskUserQuestion transcript_path agent_transcript_path
permissionDecision toolUseResult tool_use_id duration_ms cache_read_input_tokens cache_creation_input_tokens
input_tokens output_tokens quotaLimits SubagentHandback task_notification gitBranch end_turn run_in_background
mcp__ccd_session__start_session prNumber resetsAt retryInMs agentType server_tool_use web_search_requests tool_result"
hits=""
for f in "$SCRIPTS/report.pl" "$SCRIPTS/github.pl" "$SCRIPTS/usage.sh" "$SCRIPTS/usage-config.json" "$HOOK"; do
    if [ ! -f "$f" ]; then
        hits="$hits ${f##*/}:missing"
        continue
    fi
    for w in $CCNAMES; do
        if grep -qF -- "$w" "$f"; then hits="$hits ${f##*/}:$w"; fi
    done
done
check "report.pl、github.pl、usage.sh、usage-config.json、usage-hook.sh に、stop_reason・turnOrigin・hook_event_name・cliSessionId・AskUserQuestion などの欄の名前と値が文字列として現れない" "$hits" ""

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
