#!/bin/bash
# =====================================================================
# github.pl(GitHub に集計と一覧と案の索引を書く部品)のテスト
#
# 実行: bash .claude/scripts/usage/tests/test-github.sh
# 偽の gh(fixtures/fake-gh.sh)を一時フォルダに gh の名前で写し、その一時フォルダを PATH の先頭に置く。
# 偽の gh は、一時フォルダの db.json を GitHub の代わりにする。本物の GitHub は読まず、書かない。
# 前提: bash・perl(JSON::PP)。
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GITHUB="$(cd "$HERE/.." && pwd)/github.pl"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/bin"
cp "$HERE/fixtures/fake-gh.sh" "$TMP_ROOT/bin/gh"
chmod +x "$TMP_ROOT/bin/gh"
PATH="$TMP_ROOT/bin:$PATH"
export PATH

# github.pl は、手元の記録を <git の共通ディレクトリ>/keirekipro-usage に置くので、一時の git のリポジトリの中で動かす。
# git が返すパス(Windows では C:/...)と同じ形で作る
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })
REPO="$WORK/repo"
git init -q "$REPO"
STATE="$REPO/.git/keirekipro-usage"

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }

# テストごとの偽の GitHub のフォルダを作り、FAKE_GH_DIR にする: newgh <名前>
newgh() {
    FAKE_GH_DIR="$TMP_ROOT/gh-$1"
    mkdir -p "$FAKE_GH_DIR"
    export FAKE_GH_DIR
}
# github.pl を呼び、標準出力を $OUT、標準エラーを $ERR、終了コードを $RC に置く
run() {
    (cd "$REPO" && perl "$GITHUB" "$@") >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"
    RC=$?
    OUT=$(cat "$TMP_ROOT/out")
    ERR=$(cat "$TMP_ROOT/err")
}
# github.pl を読み込み、github.pl の中の関数を呼ぶ perl の文を、呼び出しと同じ失敗の扱い(guarded)で動かす。
# 一覧の Issue を用意する部分は、一覧に行を足す呼び出し(タスク3.3・3.4)の中から呼ばれるので、ここで直に確かめる
drive() {
    (cd "$REPO" && perl -e 'do $ARGV[0]; die $@ if $@; exit guarded(sub { '"$1"' })' "$GITHUB") >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"
    RC=$?
    OUT=$(cat "$TMP_ROOT/out")
    ERR=$(cat "$TMP_ROOT/err")
}
# 偽の GitHub の db.json を書く: mkdb <perl のハッシュの中身>。iss(<番号>, <欄> => <値>, ...) は、
# 既定で、OWNER が作り、閉じてロックした、題名が一覧の題名の Issue を作る。F は偽、LT は一覧の題名である。
# fill(<始め>, <終わり>) は、その範囲の番号の、ロックしていない開いたふつうの Issue を作る
mkdb() {
    perl -MJSON::PP -e '
        my $T = "AIの作業の集計の一覧";
        my ($t, $f) = (JSON::PP::true, JSON::PP::false);
        sub F () { return $f }
        sub LT () { return $T }
        sub iss { my ($n, %o) = @_; return { number => $n, title => $T, body => "", state => "closed",
            state_reason => "not_planned", locked => $t, author_association => "OWNER", comments => [], %o } }
        sub fill { my ($from, $to) = @_; return map { iss($_, title => "ふつうの Issue $_", locked => $f, state => "open") } $from .. $to }
        my $db = { '"$1"' };
        open my $fh, ">", "$ENV{FAKE_GH_DIR}/db.json" or die $!;
        print $fh JSON::PP->new->canonical->encode($db);
    ' || ng "偽の GitHub を用意できない"
}
# 偽の GitHub の db.json から値を読む: dbq <perl の式>。I(<番号>) は Issue、st(<番号>) は Issue の状態、
# nlist は題名が一覧の題名の Issue の数、lines(<番号>) は Issue の本文の行である
dbq() {
    perl -MJSON::PP -e '
        open my $fh, "<", "$ENV{FAKE_GH_DIR}/db.json" or die $!;
        local $/;
        my $db = JSON::PP->new->decode(<$fh>);
        my $T = "AIの作業の集計の一覧";
        sub I { my $n = shift; return (grep { $_->{number} == $n } @{ $db->{issues} })[0] }
        sub st { my $i = I(shift); return join "/", $i->{state}, $i->{state_reason} // "", $i->{locked} ? "locked" : "unlocked" }
        sub lines { return split /\n/, I(shift)->{body} }
        sub nlist { return scalar grep { $_->{title} eq $T } @{ $db->{issues} } }
        print '"$1"';
    '
}
# 偽の gh が呼ばれた引数を | でつなぐ。一時ファイルの名前は F にそろえる
calls() { if [ -f "$FAKE_GH_DIR/calls.log" ]; then sed 's/--body-file [^ ]*/--body-file F/' "$FAKE_GH_DIR/calls.log" | tr '\n' '|'; fi; }
statejson() { if [ -f "$STATE/$1" ]; then cat "$STATE/$1"; else printf 'none'; fi; }
# 偽の gh が呼ばれた回数
ncalls() { if [ -f "$FAKE_GH_DIR/calls.log" ]; then wc -l <"$FAKE_GH_DIR/calls.log" | tr -d ' '; else printf 0; fi; }
# 標準エラーの行の数
nlines() { if [ -n "$1" ]; then printf '%s\n' "$1" | wc -l | tr -d ' '; else printf 0; fi; }

URL="https://github.com/owner/repo/issues"

echo "== 部品の形"
perl -c "$GITHUB" >/dev/null 2>&1
check "perl -c が通る" "$?" "0"

echo "== 出し済みかの確認と書き手の確認"
newgh reported
# Issue 1: 関係の欄の違う集計のコメントが先にあり、OWNER の集計のコメントが後にある
# Issue 2: 関係の欄が OWNER でも COLLABORATOR でもない集計のコメントだけがある
# Issue 3: COLLABORATOR の集計のコメントがある
# Issue 4: OWNER のコメントだが、印の Issue の番号が違うか、印が1行目に無い
# Issue 5: 35件のコメントの、2ページ目(31件目より後)に OWNER の集計のコメントがある
perl -MJSON::PP -e '
    my $m = sub { "<!-- keirekipro-usage-report:v1 issue=$_[0] -->\n\n## AIの作業の集計" };
    my $id = 100;
    my $c = sub { { id => $id++, body => $_[0], author_association => $_[1], created_at => "2026-10-26T00:00:00Z" } };
    my @i5 = map { $c->("ふつうのコメント $_", "OWNER") } 1 .. 31;
    push @i5, $c->($m->(5), "OWNER"), map { $c->("あとのコメント $_", "NONE") } 1 .. 3;
    my $issue = sub { { number => $_[0], title => "t$_[0]", body => "", state => "closed", locked => JSON::PP::false,
        author_association => "OWNER", comments => $_[1] } };
    my $db = { issues => [
        $issue->(1, [ $c->($m->(1), "NONE"), $c->($m->(1), "CONTRIBUTOR"), $c->("ふつうのコメント", "OWNER"), $c->($m->(1), "OWNER") ]),
        $issue->(2, [ $c->($m->(2), "NONE"), $c->($m->(2), "FIRST_TIME_CONTRIBUTOR"), $c->($m->(2), "CONTRIBUTOR"), $c->($m->(2), "MEMBER") ]),
        $issue->(3, [ $c->($m->(3), "COLLABORATOR") ]),
        $issue->(4, [ $c->($m->(40), "OWNER"), $c->("前の行\n" . $m->(4), "OWNER"), $c->(" " . $m->(4), "OWNER") ]),
        $issue->(5, \@i5),
    ] };
    open my $f, ">", "$ENV{FAKE_GH_DIR}/db.json" or die $!;
    print $f JSON::PP->new->utf8->canonical->encode($db);
' || ng "偽の GitHub を用意できない"

run reported 1
check "reported が、関係の欄が OWNER の集計のコメントを出し済みとし、そのコメントの URL を出す" "$RC/$OUT" "0/$URL/1#issuecomment-138"
run reported 2
check "reported が、関係の欄の違う集計のコメントを出し済みとしない" "$RC/$OUT/$ERR" "3//"
run reported 3
check "reported が、関係の欄が COLLABORATOR の集計のコメントを出し済みとする" "$RC/$OUT" "0/$URL/3#issuecomment-143"
run reported 4
check "reported が、ほかの Issue の番号の印と、1行目に無い印を、集計のコメントとしない" "$RC/$OUT" "3/"
: >"$FAKE_GH_DIR/calls.log"
run reported 5
check "reported が、コメントの2ページ目にある集計のコメントを見つける" "$RC/$OUT" "0/$URL/5#issuecomment-131"
check "reported は、gh をコメントの一覧を読む1回だけ呼ぶ" "$(ncalls)/$(cat "$FAKE_GH_DIR/calls.log")" "1/api --paginate repos/{owner}/{repo}/issues/5/comments"

echo "== 失敗したとき"
printf '%s\n' 'issues/1/comments' >"$FAKE_GH_DIR/fail"
run reported 1
check "gh の呼び出しに失敗したら、何も出さずに 1 で終わり、標準エラーに理由を1行で残す" "$RC/$OUT/$(nlines "$ERR")" "1//1"
check "標準エラーの理由の行が、失敗した gh の呼び出しと gh の理由を持つ" "$ERR" "github.pl: gh api repos/{owner}/{repo}/issues/1/comments に失敗した(fake-gh: forced failure (issues/1/comments))"
rm -f "$FAKE_GH_DIR/fail"
run reported 99
check "無い Issue の番号では、何も出さずに 1 で終わる" "$RC/$OUT/$(nlines "$ERR")" "1//1"

newgh broken
printf '%s\n' '{"issues":[{"number":1,"title":"t","body":"","state":"open","locked":false,"author_association":"OWNER","comments":[{"id":1,"body":["<!-- keirekipro-usage-report:v1 issue=1 -->"],"author_association":"OWNER"},{"id":2,"body":"<!-- keirekipro-usage-report:v1 issue=1 -->","author_association":["OWNER"]}]}]}' >"$FAKE_GH_DIR/db.json"
run reported 1
check "本文や関係の欄が文字でないコメントを、集計のコメントとしない" "$RC/$OUT" "3/"

echo "== 引数が違うとき"
newgh usage
for a in "" "reported" "reported abc" "reported 0" "reported 1 2" "nosuch 1"; do
    # 空白で分けた引数として渡す。bash 3.2 の set -u は空の配列の展開を止めるので、+ の形で展開する
    read -r -a argv <<<"$a"
    rm -f "$FAKE_GH_DIR/calls.log"
    run ${argv[@]+"${argv[@]}"}
    check "引数 [$a] では、gh を呼ばずに 64 で終わる" "$RC/$(ncalls)" "64/0"
done

echo "== 書き込む権限の確認"
SCAN="api --paginate repos/{owner}/{repo}/issues?state=all&per_page=100"
newgh nopush
mkdb 'repo => { owner => "owner", name => "repo", push => F }, issues => []'
rm -rf "$STATE"
drive 'require_push(); list_issue_for_rows(9); 0'
check "permissions.push が偽のときは、書かずに 1 で終わり、一覧の Issue を作らない" "$RC/$OUT/$(calls)/$(dbq nlist)" "1//api repos/{owner}/{repo}|/0"
check "permissions.push が偽のときの標準エラーが、理由の1行である" "$(nlines "$ERR")/${ERR%%(*}" "1/github.pl: gh のアカウントがリポジトリに書き込む権限"
newgh push
mkdb 'issues => []'
drive 'require_push(); print "ok\n"; 0'
check "permissions.push が真のときは、書き込む呼び出しが先に進む" "$RC/$OUT" "0/ok"

echo "== 一覧の Issue を見つけ、作り、ロックする"
newgh create
mkdb 'issues => [ iss(1, title => "ふつうの Issue", locked => F, state => "open") ]'
rm -rf "$STATE"
drive 'print list_issue_for_write(), "\n"; 0'
check "一覧の Issue が無いときは、書き込む呼び出しが一覧の Issue を作り、閉じ、ロックする" "$RC/$OUT/$(calls)" "0/2/$SCAN|issue create --title AIの作業の集計の一覧 --body-file F|issue close 2 --reason not planned|issue lock 2|"
check "作った一覧の Issue は、理由が not planned で閉じてあり、ロックしてある" "$(dbq 'st(2)')" "closed/not_planned/locked"
check "作った一覧の Issue の本文は、見出しと説明と行の無い表である" "$(dbq 'join "|", scalar(@{[lines(2)]}), (lines(2))[0, 4]')" "6|## AIの作業の集計の一覧|| Issue | spec | 終了日 | AIの作業時間 | トークン数 | 使用料 | 実装中に spec へ戻った回数 |"
check "見つけた一覧の Issue の番号を state.json の list_issue に置く" "$(statejson state.json)" '{"list_issue":2}'
rm -f "$FAKE_GH_DIR/calls.log"
drive 'print list_issue_for_write(), "\n"; 0'
check "state.json の list_issue があれば、その Issue の関係の欄とロックだけを確かめて使う" "$RC/$OUT/$(calls)/$(dbq nlist)" "0/2/api repos/{owner}/{repo}/issues/2|/1"

newgh untrusted
mkdb 'issues => [ iss(1, author_association => "NONE"), iss(2, author_association => "CONTRIBUTOR", locked => F, state => "open"), iss(3, author_association => "MEMBER") ]'
rm -rf "$STATE"
drive 'print list_issue_for_write(), "\n"; 0'
check "関係の欄の違う一覧の Issue しか無いときは、一覧の Issue を作り、閉じ、ロックする" "$RC/$OUT/$(calls)" "0/4/$SCAN|issue create --title AIの作業の集計の一覧 --body-file F|issue close 4 --reason not planned|issue lock 4|"
check "関係の欄が OWNER でも COLLABORATOR でもない、一覧の題名の Issue を読まず、編集しない" "$(dbq 'join " ", st(1), st(2), st(3), length(I(1)->{body}) + length(I(2)->{body}) + length(I(3)->{body})')" "closed/not_planned/locked open/not_planned/unlocked closed/not_planned/locked 0"

newgh saved
mkdb 'issues => [ iss(1, author_association => "NONE"), iss(2), iss(3, locked => F), iss(5) ]'
rm -rf "$STATE"
mkdir -p "$STATE"
printf '%s\n' '{"list_issue":1,"owner":true}' >"$STATE/state.json"
drive 'print list_issue_for_write(), "\n"; 0'
check "state.json の list_issue が関係の欄の違う Issue を指すときは、一覧の Issue を探し直す" "$RC/$OUT/$(calls)" "0/2/api repos/{owner}/{repo}/issues/1|$SCAN|"
check "state.json に owner があるときに list_issue を書くと、list_issue が書かれ、owner が残る" "$(statejson state.json)" '{"list_issue":2,"owner":true}'
printf '%s\n' '{"list_issue":3}' >"$STATE/state.json"
rm -f "$FAKE_GH_DIR/calls.log"
drive 'print list_issue_for_write(), "\n"; 0'
check "state.json の list_issue がロックしていない Issue を指すときは、ロックしてある一覧の Issue を探し直す" "$RC/$OUT/$(calls)/$(dbq 'st(3)')" "0/2/api repos/{owner}/{repo}/issues/3|$SCAN|/closed/not_planned/unlocked"

newgh unlocked
mkdb 'issues => [ iss(1, title => "ふつうの Issue"), iss(2, locked => F, state => "open", state_reason => undef, author_association => "COLLABORATOR"), iss(4, locked => F, state => "open") ]'
rm -rf "$STATE"
drive 'print list_issue_for_write(), "\n"; 0'
check "ロックしていない一覧の Issue しか無いときは、ロックしてから使い、新しい Issue を作らない(開いていれば先に閉じる)" "$RC/$OUT/$(calls)/$(dbq 'nlist . " " . st(2) . " " . st(4)')" "0/2/$SCAN|issue close 2 --reason not planned|issue lock 2|/2 closed/not_planned/locked open/not_planned/unlocked"
newgh unlocked-closed
mkdb 'issues => [ iss(3, locked => F) ]'
rm -rf "$STATE"
drive 'print list_issue_for_write(), "\n"; 0'
check "ロックしていない一覧の Issue が閉じてあるときは、ロックだけをやり直す" "$RC/$OUT/$(calls)/$(dbq 'st(3)')" "0/3/$SCAN|issue lock 3|/closed/not_planned/locked"

newgh smallest
mkdb 'issues => [ fill(10, 160), iss(7), iss(5), iss(4, title => "AIの作業の集計の一覧(古い)"), iss(6, author_association => "COLLABORATOR") ], prs => [ { number => 3, title => LT, state => "OPEN", author_association => "OWNER" } ]'
rm -rf "$STATE"
drive 'print list_issue_for_write(), "\n"; 0'
check "一覧の Issue が2ページ目にあり、いくつもあるときは、題名が完全に一致する最小の番号の Issue を使う" "$RC/$OUT/$(calls)" "0/5/$SCAN|"
newgh pr
mkdb 'issues => [ iss(2, title => "AIの作業の集計の一覧(古い)") ], prs => [ { number => 1, title => LT, state => "OPEN", author_association => "OWNER" } ]'
rm -rf "$STATE"
drive 'print list_issue_for_write(), "\n"; 0'
check "題名が一覧の題名の PR を、一覧の Issue としない" "$RC/$OUT/$(calls)" "0/3/$SCAN|issue create --title AIの作業の集計の一覧 --body-file F|issue close 3 --reason not planned|issue lock 3|"

newgh collaborator
mkdb 'viewer_association => "COLLABORATOR", issues => [ iss(1) ]'
rm -rf "$STATE"
drive 'print list_issue_for_write(), "\n"; 0'
check "関係の欄が OWNER のアカウントで作った一覧の Issue を、COLLABORATOR のアカウントの書き込む呼び出しが使い、一覧の Issue が1つのまま" "$RC/$OUT/$(calls)/$(dbq nlist)" "0/1/$SCAN|/1"

echo "== 一覧の Issue を用意できないとき"
newgh lockfail
mkdb 'issues => []'
rm -rf "$STATE"
mkdir -p "$STATE/issues"
printf '%s\n' '{"reported_at":"2026-10-26T00:00:00Z"}' >"$STATE/issues/9.json"
printf '%s\n' '^issue lock' >"$FAKE_GH_DIR/fail"
drive 'list_issue_for_rows(9); 0'
check "ロックに失敗したときは、1 で終わり、標準エラーに理由を1行で残す" "$RC/$OUT/$ERR" "1//github.pl: gh issue lock 1 に失敗した(fake-gh: forced failure (^issue lock))"
check "ロックに失敗したときは list_pending が残り、issues/<N>.json のほかの欄も残る" "$(statejson issues/9.json)" '{"list_pending":true,"reported_at":"2026-10-26T00:00:00Z"}'
check "ロックに失敗した一覧の Issue の番号を、state.json に置かない" "$(statejson state.json)" "none"
rm -f "$FAKE_GH_DIR/fail" "$FAKE_GH_DIR/calls.log"
drive 'print list_issue_for_rows(9), "\n"; 0'
check "ロックに失敗した一覧の Issue を、次の呼び出しが新しく作らずにロックし直して使う" "$RC/$OUT/$(calls)/$(dbq 'nlist . " " . st(1)')" "0/1/$SCAN|issue lock 1|/1 closed/not_planned/locked"
newgh closefail
mkdb 'issues => []'
rm -rf "$STATE"
printf '%s\n' '^issue close' >"$FAKE_GH_DIR/fail"
drive 'list_issue_for_rows(8); 0'
check "閉じるのに失敗したときも list_pending が残る" "$RC/$(statejson issues/8.json)" '1/{"list_pending":true}'
rm -f "$FAKE_GH_DIR/fail" "$FAKE_GH_DIR/calls.log"
drive 'print list_issue_for_rows(8), "\n"; 0'
check "閉じるのに失敗した一覧の Issue を、次の呼び出しが閉じてロックして使う" "$RC/$OUT/$(calls)/$(dbq 'nlist . " " . st(1)')" "0/1/$SCAN|issue close 1 --reason not planned|issue lock 1|/1 closed/not_planned/locked"

echo "== 読むだけの呼び出し"
newgh readonly
mkdb 'issues => [ iss(1, locked => F, state => "open"), iss(2, author_association => "NONE"), iss(3, title => "ふつうの Issue") ]'
rm -rf "$STATE"
drive 'print list_issue_for_read() // "none", "\n"; 0'
check "ロックしてある一覧の Issue が無いとき、読むだけの呼び出しは一覧が無いものとし、Issue の作成とクローズとロックを頼まない" "$RC/$OUT/$(calls)/$(dbq 'st(1)')/$(statejson state.json)" "0/none/$SCAN|/open/not_planned/unlocked/none"
rm -f "$FAKE_GH_DIR/calls.log"
run reported 1
check "一覧の Issue が無いとき、reported は、一覧の Issue を探さず、作らない" "$RC/$(calls)" "3/api --paginate repos/{owner}/{repo}/issues/1/comments|"
newgh readonly-found
mkdb 'issues => [ iss(2, author_association => "NONE"), iss(4, author_association => "COLLABORATOR") ]'
rm -rf "$STATE"
drive 'print list_issue_for_read(), "\n"; 0'
check "読むだけの呼び出しは、ロックしてある一覧の Issue を見つけ、state.json の list_issue に置く" "$RC/$OUT/$(calls)/$(statejson state.json)" "0/4/$SCAN|/{\"list_issue\":4}"
rm -f "$FAKE_GH_DIR/calls.log"
drive 'print list_issue_for_read(), "\n"; 0'
check "読むだけの呼び出しは、state.json の list_issue の Issue を確かめて使う" "$RC/$OUT/$(calls)" "0/4/api repos/{owner}/{repo}/issues/4|"

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
