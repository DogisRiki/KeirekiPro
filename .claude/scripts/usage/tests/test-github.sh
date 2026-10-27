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

# 一覧を読み直す前に待つ秒数を 0 にする(既定の10秒は「一覧を読み直す前に待つ」で確かめる)
KP_USAGE_TEST_LIST_REREAD=0
export KP_USAGE_TEST_LIST_REREAD
# list-add に渡す行の JSON のファイル
ROWS="$TMP_ROOT/rows.json"
export ROWS

# mkdb・dbq・drive の perl が読み込む、テストの関数。本文の文字は UTF-8 のバイトのまま扱う。
# intro() は一覧の本文の見出しと説明と表の頭、R(<番号>, <終了日>[, <spec>]) は決まった値の一覧の行、
# Rs(<始め>, <終わり>, <終了日>) はその範囲の番号の R の行、body_with(<行>...) は行を持つ一覧の本文、
# page(<k>, <行>...) は k ページ目のコメントの本文、cm(<id>, <本文>[, <関係の欄>]) はコメントである。
# report_body(<番号>, <数字の行の JSON>...) は集計のコメントの本文、D_OLD と D_NEW は数字の行の JSON、
# L501(<コメントの id>) は D_NEW から作った一覧の行、worst_rows() は値の桁が最も多い300行の JSON である。
# not_row() は URL が一覧の行の形でない行、worst_last(<行>) は worst_rows() の最後の行かどうかを返す。
# dbq だけで使うもの: read_after_add() は「一覧を読む」の一覧に行を足したあとの本文とコメントを、見込みと比べる
# drive だけで使うもの: add_file() は $ROWS で list-add を呼ぶ。rr(<JSON>, <番号>) は集計の JSON から作った行を出す。
# clobber(<回数>, <行>...) は、いまの一覧の本文に行を足した写しを控え、書いたあとの読み直しの前の待ちを、
# 最初の <回数> 回だけ、控えを書き戻すものに替える。ほかの人が同時に一覧を書き、こちらの行を消した形になる
export KP_TEST_H="$TMP_ROOT/h.pl"
cat >"$KP_TEST_H" <<'__H__'
require JSON::PP;
my $URLB = "https://github.com/owner/repo/issues";
sub head { return "| Issue | spec | 終了日 | AIの作業時間 | トークン数 | 使用料 | 実装中に spec へ戻った回数 |\n|---|---|---|---|---|---|---|\n" }
sub intro {
    return "## AIの作業の集計の一覧\n\nこの一覧は、Issue ごとの AI の作業の集計を、終了日の古い順に1行ずつ並べたものである。Issue の列の番号から、その Issue の集計のコメントを開ける。「AIの作業時間」は、AI の会話のどれかが動いていた時間で、所有者の返事を待っていた時間と、使う量の上限で止まっていた時間を含まない。「トークン数」は、入力、キャッシュの書き込み、キャッシュの読み込み、出力の合計である。「使用料」は、トークン数を公表価格で換算した米ドルの額である。「実装中に spec へ戻った回数」は、実装の途中で要件、設計、タスクに戻って直した回数の合計である。300行を超えた行は、この Issue のコメントに続く。\n\n" . head();
}
sub R { my ($n, $date, $spec) = @_; return "| [#$n]($URLB/$n#issuecomment-" . (5000 + $n) . ") | " . ($spec // "無し") . " | $date | 1時間20分 | 3,456,789 | \$8.90 | 0 |" }
sub Rs { my ($from, $to, $date) = @_; return map { R($_, $date) } $from .. $to }
sub body_with { return intro() . join("", map { "$_\n" } @_) }
sub page { my ($k, @l) = @_; return "<!-- keirekipro-usage-list:v1 page=$k -->\n\n### 一覧の続き(${k}ページ目)\n\n" . head() . join("", map { "$_\n" } @l) }
sub cm { my ($id, $body, $a) = @_; return { id => $id, body => $body, author_association => $a // "OWNER", created_at => "2026-10-26T00:00:00Z" } }
sub report_body {
    my ($n, @data) = @_;
    return "<!-- keirekipro-usage-report:v1 issue=$n -->\n\n## AIの作業の集計\n\n本文\n"
        . join("本文の途中\n", map { "<!-- keirekipro-usage-data:v1 $_ -->\n" } @data);
}
sub D_OLD { return '{"v":1,"issue":501,"spec":false,"end_date":"2026-01-01","totals":{"work_sec":60,"tokens":1,"usd":1,"usd_unknown_models":[]},"rework":{"impl_spec_back":{"requirements":0,"design":0,"tasks":0}}}' }
sub D_NEW { return '{"v":1,"issue":501,"prs":[612,618],"spec":true,"end_date":"2026-11-02","totals":{"work_sec":50700,"wait_sec":0,"tokens":123456789,"usd":312.45,"usd_unknown_models":["claude-x"]},"rework":{"impl_spec_back":{"requirements":1,"design":0,"tasks":0}}}' }
sub L501 { my ($id) = @_; return "| [#501]($URLB/501#issuecomment-$id) | あり | 2026-11-02 | 14時間5分 | 123,456,789 | \$312.45(価格が分からないモデルを除く) | 1 |" }
sub worst_rows {
    return JSON::PP->new->canonical->encode([ map { { issue => $_, url => "https://github.com/DogisRiki/KeirekiPro/issues/$_#issuecomment-99999999999",
        spec => JSON::PP::true, end_date => "2026-11-02", work_sec => 3599940, tokens => 999999999999, usd => 99999.99,
        usd_partial => JSON::PP::true, impl_spec_back => undef } } 99000 .. 99299 ]);
}
sub add_file { return cmd_list_add($ENV{ROWS}) }
sub rr { my ($json, $n) = @_; print format_row(row_from_report(JSON::PP->new->decode($json), "$URLB/$n#issuecomment-9", $n)), "\n"; return 0 }
sub clobber {
    my ($k, @extra) = @_;
    my $f = "$ENV{FAKE_GH_DIR}/db.json";
    my $j = JSON::PP->new->canonical;
    open my $fh, "<", $f or die $!;
    my $db = $j->decode(do { local $/; <$fh> });
    close $fh;
    for my $i (@{ $db->{issues} }) { $i->{body} .= join "", map { "$_\n" } @extra if $i->{title} eq "AIの作業の集計の一覧" }
    my $snap = $j->encode($db);
    my $n = 0;
    no warnings "redefine";
    *main::list_reread_wait = sub { return if $n++ >= $k; open my $o, ">", $f or die $!; print $o $snap; close $o };
    return 1;
}
sub not_row { return "| [#9](https://example.com/x/issues/9#issuecomment-1) | 無し | 2026-10-01 | 1分 | 1 | \$1.00 | 0 |" }
sub worst_last {
    return $_[0] eq "| [#99299](https://github.com/DogisRiki/KeirekiPro/issues/99299#issuecomment-99999999999) | あり | 2026-11-02 | 999時間59分 | 999,999,999,999 | \$99,999.99(価格が分からないモデルを除く) | 数えられない |";
}
sub read_after_add {
    my %c = map { $_->{id} => $_->{body} } @{ I(1)->{comments} };
    my @want = (
        [ I(1)->{body}, body_with(R(480, "2026-09-30"), R(700, "2026-10-15"), R(501, "2026-11-02", "あり"), R(812, "2027-05-10"), R(813, "2027-05-12")) ],
        [ $c{1001}, page(2) ], [ $c{1002}, page(3, R(900, "2027-06-01")) ], [ $c{1003}, page(2, R(901, "2027-06-02")) ],
        [ $c{1004}, page(2) ], [ $c{1005}, "ふつうのコメント\n" . R(902, "2027-06-03") ], [ $c{1006}, page(1, R(903, "2027-06-04")) ],
    );
    return join " ", map { $_->[0] eq $_->[1] ? "same" : "diff" } @want;
}
# many(<番号>, <件数>) はその Issue の連番の案の ID、worst_ids() は桁の最も多い1,000件の案の ID である。
# idx_body(<k>, <ID>...) は案の索引のコメントの本文、rep_props(<番号>, <行>...) は直す案を持つ集計のコメントの本文である。
# dbq だけで使うもの: idx_desc(<番号>) は Issue の索引のコメントごとの「ページ:件数」、idx_ids(<番号>) は索引の案の ID である
sub many { my ($n, $k) = @_; return map { "$n-$_" } 1 .. $k }
sub worst_ids { return map { "9999999999-" . (998999 + $_) } 1 .. 1000 }
sub idx_body { my ($k, @ids) = @_; return "<!-- keirekipro-usage-proposals:v1 page=$k " . JSON::PP->new->canonical->encode([ map { { id => $_, issue => (split /-/)[0] + 0 } } @ids ]) . " -->\n説明\n" }
sub rep_props { my ($n, @l) = @_; return "<!-- keirekipro-usage-report:v1 issue=$n -->\n\n## AIの作業の集計\n\n### 所見\n\n- 箇条\n\n### 直す案\n\n" . join("", map { "$_\n" } @l) }
sub idx_parse { my ($b) = @_; my ($k, $j) = $b =~ /\A<!-- keirekipro-usage-proposals:v1 page=([0-9]+) (\[[^\n]*\]) -->/ or return; return [ $k, JSON::PP->new->decode($j) ] }
sub idx_desc { return join " ", map { "$_->[0]:" . scalar @{ $_->[1] } } grep { defined } map { idx_parse($_->{body}) } @{ I(shift)->{comments} } }
sub idx_ids { return join " ", map { $_->{id} } map { @{ $_->[1] } } grep { defined } map { idx_parse($_->{body}) } @{ I(shift)->{comments} } }
1;
__H__

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
    (cd "$REPO" && perl -e 'do $ARGV[0]; die $@ if $@; do $ENV{KP_TEST_H} or die "h.pl: $@ $!"; exit guarded(sub { '"$1"' })' "$GITHUB") >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"
    RC=$?
    OUT=$(cat "$TMP_ROOT/out")
    ERR=$(cat "$TMP_ROOT/err")
}
# 偽の GitHub の db.json を書く: mkdb <perl のハッシュの中身>。iss(<番号>, <欄> => <値>, ...) は、
# 既定で、OWNER が作り、閉じてロックした、題名が一覧の題名の Issue を作る。F は偽、LT は一覧の題名である。
# fill(<始め>, <終わり>) は、その範囲の番号の、ロックしていない開いたふつうの Issue を作る
mkdb() {
    perl -MJSON::PP -e '
        do $ENV{KP_TEST_H} or die "h.pl: $@ $!";
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
    perl -MJSON::PP -MEncode -e '
        do $ENV{KP_TEST_H} or die "h.pl: $@ $!";
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
calls() { if [ -f "$FAKE_GH_DIR/calls.log" ]; then sed -e 's/--body-file [^ ]*/--body-file F/' -e 's/body=@[^ ]*/body=@F/' "$FAKE_GH_DIR/calls.log" | tr '\n' '|'; fi; }
# 偽の gh の呼び出しのうち、GitHub に書いたものだけを | でつなぐ
writes() { calls | tr '|' '\n' | grep -E '^(issue (edit|comment|create|close|lock)|api -X)' | tr '\n' '|'; }
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
for a in "" "reported" "reported abc" "reported 0" "reported 1 2" "nosuch 1" "list-read x" "list-add" "list-add a b" "list-ensure" "list-ensure abc" "list-ensure 1 2"; do
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

echo "== 一覧の行の書き方"
# 一覧の行の JSON(list-read の出力と同じ形)を $ROWS に書く: row_json <番号> <終了日>。値は R(<番号>, <終了日>) と同じ
row_json() {
    printf '[{"issue":%s,"url":"%s/%s#issuecomment-%s","spec":false,"end_date":"%s","work_sec":4800,"tokens":3456789,"usd":8.9,"impl_spec_back":0}]\n' \
        "$1" "$URL" "$1" "$(($1 + 5000))" "$2" >"$ROWS"
}
# R(<番号>, <終了日>[, <spec>]) の行を list-read が戻した JSON: J <番号> <終了日> [true]
J() {
    printf '{"end_date":"%s","impl_spec_back":0,"issue":%s,"spec":%s,"tokens":3456789,"url":"%s/%s#issuecomment-%s","usd":8.9,"usd_partial":false,"work_sec":4800}' \
        "$2" "$1" "${3:-false}" "$URL" "$1" "$(($1 + 5000))"
}
newgh format
mkdb 'issues => [ iss(1, body => intro()) ]'
rm -rf "$STATE"
cat >"$ROWS" <<'__ROWS__'
[{"issue":493,"url":"https://github.com/owner/repo/issues/493#issuecomment-1234567894","spec":false,"end_date":"2026-10-01","work_sec":3599,"tokens":1000000,"usd":0.005,"impl_spec_back":0},
 {"issue":501,"url":"https://github.com/owner/repo/issues/501#issuecomment-1234567891","spec":true,"end_date":"2026-11-02","work_sec":50700,"tokens":123456789,"usd":312.45,"usd_partial":true,"impl_spec_back":1},
 {"issue":490,"url":"https://github.com/owner/repo/issues/490#issuecomment-1234567892","spec":false,"end_date":"2026-10-01","work_sec":2670,"tokens":0,"usd":1234.5,"impl_spec_back":null},
 {"issue":480,"url":"https://github.com/owner/repo/issues/480#issuecomment-1234567890","spec":false,"end_date":"2026-09-30","work_sec":4800,"tokens":3456789,"usd":8.9,"impl_spec_back":0},
 {"issue":492,"url":"https://github.com/owner/repo/issues/492#issuecomment-1234567895","spec":false,"end_date":"2026-10-01","work_sec":null,"tokens":999,"usd":1.005,"impl_spec_back":0},
 {"issue":491,"url":"https://github.com/owner/repo/issues/491#issuecomment-1234567893","spec":true,"end_date":"2026-10-01","work_sec":29,"tokens":null,"usd":0,"impl_spec_back":2}]
__ROWS__
cat >"$TMP_ROOT/want" <<'__WANT__'
| [#480](https://github.com/owner/repo/issues/480#issuecomment-1234567890) | 無し | 2026-09-30 | 1時間20分 | 3,456,789 | $8.90 | 0 |
| [#490](https://github.com/owner/repo/issues/490#issuecomment-1234567892) | 無し | 2026-10-01 | 45分 | 0 | $1,234.50 | 数えられない |
| [#491](https://github.com/owner/repo/issues/491#issuecomment-1234567893) | あり | 2026-10-01 | 0分 | 数えられない | $0.00 | 2 |
| [#492](https://github.com/owner/repo/issues/492#issuecomment-1234567895) | 無し | 2026-10-01 | 数えられない | 999 | $1.01 | 0 |
| [#493](https://github.com/owner/repo/issues/493#issuecomment-1234567894) | 無し | 2026-10-01 | 1時間0分 | 1,000,000 | $0.01 | 0 |
| [#501](https://github.com/owner/repo/issues/501#issuecomment-1234567891) | あり | 2026-11-02 | 14時間5分 | 123,456,789 | $312.45(価格が分からないモデルを除く) | 1 |
__WANT__
cat >"$TMP_ROOT/want.json" <<'__J__'
[{"end_date":"2026-09-30","impl_spec_back":0,"issue":480,"spec":false,"tokens":3456789,"url":"https://github.com/owner/repo/issues/480#issuecomment-1234567890","usd":8.9,"usd_partial":false,"work_sec":4800},{"end_date":"2026-10-01","impl_spec_back":null,"issue":490,"spec":false,"tokens":0,"url":"https://github.com/owner/repo/issues/490#issuecomment-1234567892","usd":1234.5,"usd_partial":false,"work_sec":2700},{"end_date":"2026-10-01","impl_spec_back":2,"issue":491,"spec":true,"tokens":null,"url":"https://github.com/owner/repo/issues/491#issuecomment-1234567893","usd":0,"usd_partial":false,"work_sec":0},{"end_date":"2026-10-01","impl_spec_back":0,"issue":492,"spec":false,"tokens":999,"url":"https://github.com/owner/repo/issues/492#issuecomment-1234567895","usd":1.01,"usd_partial":false,"work_sec":null},{"end_date":"2026-10-01","impl_spec_back":0,"issue":493,"spec":false,"tokens":1000000,"url":"https://github.com/owner/repo/issues/493#issuecomment-1234567894","usd":0.01,"usd_partial":false,"work_sec":3600},{"end_date":"2026-11-02","impl_spec_back":1,"issue":501,"spec":true,"tokens":123456789,"url":"https://github.com/owner/repo/issues/501#issuecomment-1234567891","usd":312.45,"usd_partial":true,"work_sec":50700}]
__J__
run list-add "$ROWS"
check "list-add が、行を足して 0 で終わる" "$RC/$OUT/$ERR" "0//"
check "一覧の本文が、見本の形で、終了日の古い順に、終了日が同じなら Issue の番号の順に、数の書き方の決まりで行を並べる" "$(dbq 'I(1)->{body}')" "$(dbq 'intro()'; cat "$TMP_ROOT/want")"
check "list-add は、本文を1回書き直し、ページのコメントを書かない" "$(writes)" "issue edit 1 --body-file F|"
check "D_NEW の集計の値の行が、L501 の形である" "$(dbq '[lines(1)]->[-1] eq L501(1234567891) ? "same" : "diff"')" "same"
run list-read
check "list-read が、一覧の行を数に戻し、数えられない値を null にして、JSON の配列の1行で出す" "$RC/$(nlines "$OUT")/$OUT" "0/1/$(cat "$TMP_ROOT/want.json")"
printf '%s\n' "$OUT" >"$ROWS"
rm -f "$FAKE_GH_DIR/calls.log"
run list-add "$ROWS"
check "list-read の出力を list-add に渡すと、同じ行を置き換えるだけで、一覧に何も書かない" "$RC/$(writes)/$(dbq 'scalar(grep { /\A\| \[#/ } lines(1))')" "0//6"
drive 'rr(q{{"issue":7,"spec":false,"end_date":"2026-10-01","totals":{"work_sec":0,"tokens":0,"usd":0,"usd_unknown_models":[]},"rework":{"impl_spec_back":{"requirements":null,"design":0,"tasks":0}}}}, 7)'
check "集計の JSON の impl_spec_back の3つのどれかが null のときは、回数を「数えられない」と書く" "$RC/$OUT" "0/| [#7]($URL/7#issuecomment-9) | 無し | 2026-10-01 | 0分 | 0 | \$0.00 | 数えられない |"
drive 'rr(q{{"issue":8,"spec":false,"end_date":"2026-10-01","totals":{"work_sec":0,"tokens":0,"usd":0,"usd_unknown_models":[]},"rework":{"impl_spec_back":{"requirements":0,"design":0,"tasks":0}}}}, 7)'
check "集計の JSON の issue が行の Issue と違えば、行を作らない" "$RC/$OUT/$(nlines "$ERR")" "1//1"

echo "== list-add に渡す行が正しくないとき"
newgh badrows
mkdb 'issues => [ iss(1, body => intro()) ]'
cat >"$TMP_ROOT/bad" <<'__BAD__'
{}
[]
[{"issue":5,"url":"https://github.com/owner/repo/issues/6#issuecomment-1","spec":false,"end_date":"2026-10-01","work_sec":0,"tokens":0,"usd":0,"impl_spec_back":0}]
[{"issue":5,"url":"https://github.com/owner/repo/issues/5#issuecomment-1","spec":false,"end_date":"2026-10-01","work_sec":0,"tokens":1.5,"usd":0,"impl_spec_back":0}]
[{"issue":5,"url":"https://github.com/owner/repo/issues/5#issuecomment-1","spec":"no","end_date":"2026-10-01","work_sec":0,"tokens":1,"usd":0,"impl_spec_back":0}]
[{"issue":5,"url":"https://github.com/owner/repo/issues/5#issuecomment-1","spec":false,"end_date":"2026-10-01","work_sec":-1,"tokens":1,"usd":0,"impl_spec_back":0}]
[{"issue":5,"url":"https://github.com/owner/repo/issues/5#issuecomment-1","spec":false,"end_date":"2026/10/01","work_sec":0,"tokens":1,"usd":0,"impl_spec_back":0}]
__BAD__
while IFS= read -r bad; do
    printf '%s\n' "$bad" >"$ROWS"
    rm -f "$FAKE_GH_DIR/calls.log"
    run list-add "$ROWS"
    check "行の JSON が正しくないとき($(printf '%s' "$bad" | cut -c1-30)…)は、gh を呼ばずに 1 で終わる" "$RC/$(ncalls)/$(nlines "$ERR")" "1/0/1"
done <"$TMP_ROOT/bad"
run list-add "$TMP_ROOT/nosuch.json"
check "行の JSON のファイルが無いときは、1 で終わる" "$RC/$(nlines "$ERR")" "1/1"

echo "== 一覧のページ"
newgh pages
mkdb 'issues => [ iss(1, body => body_with(Rs(1001, 1300, "2026-10-01"))) ]'
rm -rf "$STATE"
mkdir -p "$STATE"
printf '%s\n' '{"list_issue":1}' >"$STATE/state.json"
row_json 1301 2026-10-02
run list-add "$ROWS"
check "一覧が301行になると、本文を書き直さずに2ページ目のコメントを書き、読み直して確かめる" "$RC/$(calls)" "0/api repos/{owner}/{repo}|api repos/{owner}/{repo}/issues/1|api repos/{owner}/{repo}/issues/1|api --paginate repos/{owner}/{repo}/issues/1/comments|issue comment 1 --body-file F|api repos/{owner}/{repo}/issues/1|api --paginate repos/{owner}/{repo}/issues/1/comments|"
check "2ページ目のコメントが、見本の形で301行目を持ち、本文が300行のまま" "$(dbq 'join " ", scalar @{ I(1)->{comments} }, I(1)->{comments}[0]{body} eq page(2, R(1301, "2026-10-02")) ? "same" : "diff", I(1)->{body} eq body_with(Rs(1001, 1300, "2026-10-01")) ? "same" : "diff"')" "1 same same"
row_json 999 2026-09-01
rm -f "$FAKE_GH_DIR/calls.log"
run list-add "$ROWS"
check "終了日が古い行を足すと、本文と2ページ目のコメントを書き直す" "$RC/$(writes)" "0/issue edit 1 --body-file F|api -X PATCH repos/{owner}/{repo}/issues/comments/1000 -F body=@F|"
check "終了日が古い行を足すと、ページの境目の行がずれて並ぶ" "$(dbq 'join " ", scalar @{ I(1)->{comments} }, I(1)->{body} eq body_with(R(999, "2026-09-01"), Rs(1001, 1299, "2026-10-01")) ? "same" : "diff", I(1)->{comments}[0]{body} eq page(2, R(1300, "2026-10-01"), R(1301, "2026-10-02")) ? "same" : "diff"')" "1 same same"

printf '[{"issue":1001,"url":"%s/1001#issuecomment-6001","spec":false,"end_date":"2026-10-01","work_sec":60,"tokens":3456789,"usd":8.9,"impl_spec_back":0}]\n' "$URL" >"$ROWS"
rm -f "$FAKE_GH_DIR/calls.log"
run list-add "$ROWS"
check "1ページ目の行だけが変わるときは、本文だけを書き直し、変わらない2ページ目のコメントを書き直さない" "$RC/$(writes)/$(dbq 'I(1)->{comments}[0]{body} eq page(2, R(1300, "2026-10-01"), R(1301, "2026-10-02")) ? "same" : "diff"')" "0/issue edit 1 --body-file F|/same"

newgh worst
mkdb 'issues => [ iss(1, body => intro()) ]'
rm -rf "$STATE"
dbq 'worst_rows()' >"$ROWS"
run list-add "$ROWS"
check "値の桁が最も多い300行を足すと、すべての行が本文に入り、ページのコメントを書かない" "$RC/$(dbq 'scalar(grep { /\A\| \[#99[0-9]{3}\]/ } lines(1)) . " " . scalar @{ I(1)->{comments} } . " " . (worst_last((lines(1))[-1]) ? "worst" : "diff")')" "0/300 0 worst"
blen=$(dbq 'length(Encode::decode("UTF-8", I(1)->{body}))')
if [ "$blen" -lt 65536 ]; then ok "300行の一覧の本文が65,536文字に届かない($blen 文字)"; else ng "300行の一覧の本文が65,536文字に届かない($blen 文字)"; fi

echo "== 一覧を読む"
newgh read
mkdb 'issues => [ iss(1, body => body_with(R(501, "2026-11-02", "あり"), R(480, "2026-09-30"), not_row()), comments => [ cm(1001, page(2, R(812, "2027-05-10"))), cm(1002, page(3, R(900, "2027-06-01")), "NONE"), cm(1003, page(2, R(901, "2027-06-02")), "CONTRIBUTOR"), cm(1004, page(2, R(812, "2027-05-11"), R(813, "2027-05-12")), "COLLABORATOR"), cm(1005, "ふつうのコメント\n" . R(902, "2027-06-03")), cm(1006, page(1, R(903, "2027-06-04"))) ]) ]'
rm -rf "$STATE"
run list-read
check "list-read が、本文と、関係の欄が OWNER か COLLABORATOR の2ページ目からのコメントの行を並べて出す。同じ Issue の行は先の行を使う" "$RC/$OUT" "0/[$(J 480 2026-09-30),$(J 501 2026-11-02 true),$(J 812 2027-05-10),$(J 813 2027-05-12)]"
check "list-read は、一覧の本文とコメントを読むだけで、書かない" "$(calls)" "$SCAN|api repos/{owner}/{repo}/issues/1|api --paginate repos/{owner}/{repo}/issues/1/comments|"
row_json 700 2026-10-15
rm -f "$FAKE_GH_DIR/calls.log"
run list-add "$ROWS"
check "行が1ページに収まると、本文に行を集め、ページのコメントを行の無いページにする" "$RC/$(writes)" "0/issue edit 1 --body-file F|api -X PATCH repos/{owner}/{repo}/issues/comments/1001 -F body=@F|api -X PATCH repos/{owner}/{repo}/issues/comments/1004 -F body=@F|"
check "関係の欄が OWNER でも COLLABORATOR でもないページのコメントと、1ページ目の印のコメントの行を一覧に入れず、そのコメントを編集しない" "$(dbq 'read_after_add()')" "same same same same same same same"

newgh stale-page
mkdb 'issues => [ iss(1, body => body_with(R(480, "2026-09-30")), comments => [ cm(1001, page(3, R(812, "2027-05-10"))) ]) ]'
rm -rf "$STATE"
row_json 700 2026-10-15
run list-add "$ROWS"
check "2ページ目が無く、行が1ページに収まるときは、3ページ目のコメントを行の無いページにし、ページのコメントを新しく書かない" "$RC/$(writes)/$(dbq 'scalar(@{ I(1)->{comments} }) == 1 && I(1)->{comments}[0]{body} eq page(3) && I(1)->{body} eq body_with(R(480, "2026-09-30"), R(700, "2026-10-15"), R(812, "2027-05-10")) ? "same" : "diff"')" "0/issue edit 1 --body-file F|api -X PATCH repos/{owner}/{repo}/issues/comments/1001 -F body=@F|/same"

newgh read-none
mkdb 'issues => [ iss(1, locked => F, state => "open") ]'
rm -rf "$STATE"
run list-read
check "一覧の Issue が無いとき、list-read は [] を出し、一覧の Issue を作らない" "$RC/$OUT/$(calls)/$(dbq 'st(1)')/$(statejson state.json)" "0/[]/$SCAN|/open/not_planned/unlocked/none"

echo "== 一覧を読み直す前に待つ"
drive 'print list_reread_secs(), "\n"; 0'
check "テストでは、読み直す前に待つ秒数を環境変数で 0 にする" "$OUT" "0"
OUT=$(unset KP_USAGE_TEST_LIST_REREAD; drive 'print list_reread_secs(), "\n"; 0'; printf '%s' "$OUT")
check "環境変数が無いときは、書いたあと10秒待ってから一覧を読み直す" "$OUT" "10"
OUT=$(KP_USAGE_TEST_LIST_REREAD=abc; export KP_USAGE_TEST_LIST_REREAD; drive 'print list_reread_secs(), "\n"; 0'; printf '%s' "$OUT")
check "環境変数が数でないときも、10秒待つ" "$OUT" "10"

echo "== 同時に行を足したとき"
newgh race
mkdb 'issues => [ iss(1, body => body_with(R(480, "2026-09-30"))) ]'
rm -rf "$STATE"
mkdir -p "$STATE/issues"
printf '%s\n' '{"list_issue":1}' >"$STATE/state.json"
printf '%s\n' '{"list_pending":true,"reported_at":"2026-10-26T00:00:00Z"}' >"$STATE/issues/501.json"
row_json 501 2026-11-02
drive 'clobber(1, R(700, "2026-10-15")); add_file()'
check "書いたあとの読み直しで足した行が無いときは、読み直した一覧に行を足し直し、0 で終わる" "$RC/$ERR/$(writes)" "0//issue edit 1 --body-file F|issue edit 1 --body-file F|"
check "足し直した一覧が、ほかの人が足した行とこちらの行を、重ならずに持つ" "$(dbq 'I(1)->{body} eq body_with(R(480, "2026-09-30"), R(700, "2026-10-15"), R(501, "2026-11-02")) ? "same" : I(1)->{body}')" "same"
check "行を足せたら list_pending を消し、ほかの欄は残る" "$(statejson issues/501.json)" '{"reported_at":"2026-10-26T00:00:00Z"}'
newgh race3
mkdb 'issues => [ iss(1, body => body_with(R(480, "2026-09-30"))) ]'
rm -f "$STATE/issues/501.json"
printf '%s\n' '{"list_issue":1}' >"$STATE/state.json"
drive 'clobber(3, R(700, "2026-10-15")); add_file()'
check "3回書き直しても足した行が無ければ、1 で終わり、標準エラーに理由を1行で残す" "$RC/$OUT/$ERR/$(writes)" "1//github.pl: 3回書き直しても、一覧に足した行が残らなかった/issue edit 1 --body-file F|issue edit 1 --body-file F|issue edit 1 --body-file F|"
check "3回書き直しても足した行が無ければ、list_pending を残す" "$(statejson issues/501.json)" '{"list_pending":true}'
newgh editfail
mkdb 'issues => [ iss(1, body => intro()) ]'
rm -rf "$STATE"
printf '%s\n' '^issue edit' >"$FAKE_GH_DIR/fail"
printf '[%s,%s]\n' "$(J 480 2026-09-30)" "$(J 501 2026-11-02 true)" >"$ROWS"
run list-add "$ROWS"
check "一覧を書けなかったときは、1 で終わり、足す行の Issue ごとに list_pending を残す" "$RC/$(nlines "$ERR")/$(statejson issues/480.json)/$(statejson issues/501.json)" '1/1/{"list_pending":true}/{"list_pending":true}'

echo "== list-ensure"
newgh ensure
# 「list-ensure」の偽の GitHub の、一覧の Issue 1 のほかの Issue
ENSURE='iss(501, title => "ふつうの Issue", locked => F, comments => [ cm(2001, report_body(501, D_NEW()), "NONE"), cm(2002, report_body(501, D_NEW(), D_OLD()), "CONTRIBUTOR"), cm(2003, "ふつうのコメント"), cm(2004, report_body(501, D_OLD(), D_NEW())) ]), iss(502, title => "ふつうの Issue", locked => F)'
mkdb "issues => [ iss(1, body => intro()), $ENSURE ]"
rm -rf "$STATE"
mkdir -p "$STATE/issues"
printf '%s\n' '{"list_issue":1}' >"$STATE/state.json"
printf '%s\n' '{"list_pending":true}' >"$STATE/issues/501.json"
run list-ensure 501
check "list-ensure が、書き手の確認を通る集計のコメントの最後の数字の行の JSON から行を作って足し、0 で終わる" "$RC/$OUT/$ERR/$(dbq 'I(1)->{body} eq intro() . L501(2004) . "\n" ? "same" : I(1)->{body}')" "0///same"
check "list-ensure が行を足せたら list_pending を消す" "$(statejson issues/501.json)" "{}"
mkdb "issues => [ iss(1, body => body_with(R(501, \"2026-11-02\", \"あり\"))), $ENSURE ]"
printf '%s\n' '{"list_pending":true}' >"$STATE/issues/501.json"
rm -f "$FAKE_GH_DIR/calls.log"
run list-ensure 501
check "一覧に Issue の行があれば、行の値が集計のコメントと違っても、list-ensure は書かずに 0 で終わり、list_pending を消す" "$RC/$(writes)/$(statejson issues/501.json)/$(dbq 'I(1)->{body} eq body_with(R(501, "2026-11-02", "あり")) ? "same" : "diff"')" "0//{}/same"
run list-ensure 502
check "集計のコメントが無ければ、list-ensure は 1 で終わり、list_pending を残す" "$RC/$ERR/$(statejson issues/502.json)" '1/github.pl: Issue 502 に集計のコメントが無いので、一覧の行を作れなかった/{"list_pending":true}'

echo "== 書き込む権限が無いとき"
newgh nopush-cli
mkdb 'repo => { owner => "owner", name => "repo", push => F }, issues => [ iss(1, body => intro()), iss(501, title => "ふつうの Issue", locked => F, comments => [ cm(2004, report_body(501, D_NEW())) ]) ]'
rm -rf "$STATE"
row_json 501 2026-11-02
run list-add "$ROWS"
check "permissions.push が偽のときは、list-add は書かずに 1 で終わり、手元に何も残さない" "$RC/$(calls)/$(nlines "$ERR")/$(statejson issues/501.json)" "1/api repos/{owner}/{repo}|/1/none"
rm -f "$FAKE_GH_DIR/calls.log"
run list-ensure 501
check "permissions.push が偽のときは、list-ensure は書かずに 1 で終わり、手元に何も残さない" "$RC/$(calls)/$(nlines "$ERR")/$(statejson issues/501.json)/$(dbq 'I(1)->{body} eq intro() ? "same" : "diff"')" "1/api repos/{owner}/{repo}|/1/none/same"

echo "== 関係の欄が COLLABORATOR のアカウント"
newgh collaborator-rows
mkdb 'viewer_association => "COLLABORATOR", issues => [ iss(1, body => body_with(Rs(1001, 1300, "2026-10-01"))) ]'
rm -rf "$STATE"
row_json 1301 2026-10-02
run list-add "$ROWS"
check "COLLABORATOR のアカウントが、OWNER の一覧に行を足し、一覧の Issue が1つのまま、2ページ目のコメントを書く" "$RC/$(dbq 'nlist . " " . scalar @{ I(1)->{comments} } . " " . I(1)->{comments}[0]{author_association}')" "0/1 1 COLLABORATOR"
run list-read
check "COLLABORATOR のアカウントが書いた2ページ目の行を、list-read が読む" "$RC/$(printf '%s' "$OUT" | grep -o '"issue":1301')" '0/"issue":1301'

echo "== 集計のコメントと案の索引"
DRAFT="$TMP_ROOT/draft"
FIND="$TMP_ROOT/findings.md"
mkdir -p "$DRAFT"
# report.json は、github.pl が数字の行に書く形(キーの順、空白無し、最後の改行無し)で書く
perl -MJSON::PP -e '
    my ($t, $f) = (JSON::PP::true, JSON::PP::false);
    my @st = ("着手の判断", "要件", "要件の審査", "設計", "設計の審査", "タスク", "タスクの審査", "実装", "実装中の spec の直し", "出荷とレビュー対応", "その他", "合計");
    my $m = sub { { model => $_[0], role => $_[1], in => 100456, cw => 2856789, cr => 61123456, out => 376789, usd => 155.2 } };
    my $tri = sub { { requirements => $_[0], design => $_[1], tasks => $_[2] } };
    my $d = { v => 1, issue => 501, prs => [ 612, 618 ], spec => $t, start_date => "2026-10-20", end_date => "2026-11-02",
        totals => { work_sec => 50700, wait_sec => 7800, concurrent_sec => 23280, tokens => 123456789, usd => 312.45,
            usd_unknown_models => [], limit_count => 1, limit_sec => 9000 },
        stages => [ map { { name => $_, work_sec => 720, wait_sec => 0, concurrent_sec => 180, tokens => 1234567, usd => 3.1 } } @st ],
        models => [ $m->("claude-opus-5-5", "本体の会話"), $m->("claude-opus-5-5", "spec の審査役"), $m->("claude-opus-5-5", "タスクごとの確認役"),
            $m->("claude-haiku-5-5", "Explore") ],
        rework => { spec_review_rounds => $tri->(3, 5, 2), owner_fix => $tri->(0, 1, 0), spec_back => [ { from => "design", to => "requirements" } ],
            impl_spec_back => $tri->(0, 1, 0), task_rejected => 2, codex_rounds => 3, ci_fix => 1, same_failure => 0, split => $f,
            switch_to_spec => 0, size_check_stops => 0, decided_method_stops => 0 },
        uncountable => [], partial_records => $f, unknown_turns => 3,
        prices => { source => "https://platform.claude.com/docs/en/about-claude/pricing", checked_on => "2026-10-24" } };
    print JSON::PP->new->canonical->encode($d);
' >"$DRAFT/report.json" || ng "report.json を用意できない"
# report.md は design の「集計のコメント」の見本の形である
cat >"$DRAFT/report.md" <<'__MD__'
## AIの作業の集計

| 開始日 | 終了日 | spec | PR |
|---|---|---|---|
| 2026-10-20 | 2026-11-02 | あり | #612、#618 |

### 全体の合計

| 項目 | 値 |
|---|---|
| AIの作業時間 | 14時間5分 |
| トークン数 | 123,456,789 |
| 使用料 | $312.45 |
| 使う量の上限で止まった回数 | 1 |
| 使う量の上限で止まっていた時間 | 2時間30分 |

### 段階ごと

| 段階 | AIの作業時間 | そのうち待ち時間 | 審査役などが同時に動いた時間 | トークン数 | 使用料 |
|---|---|---|---|---|---|
| 着手の判断 | 12分 | 0分 | 3分 | 1,234,567 | $3.10 |
| 要件 | 1時間2分 | 0分 | 10分 | 8,765,432 | $20.12 |
| 要件の審査 | 1時間40分 | 0分 | 1時間20分 | 15,432,109 | $38.40 |
| 設計 | 2時間5分 | 0分 | 15分 | 16,543,210 | $41.25 |
| 設計の審査 | 3時間10分 | 0分 | 2時間40分 | 30,123,456 | $76.80 |
| タスク | 40分 | 0分 | 5分 | 5,432,100 | $13.55 |
| タスクの審査 | 50分 | 0分 | 40分 | 6,123,456 | $15.30 |
| 実装 | 2時間30分 | 50分 | 1時間10分 | 25,678,901 | $66.20 |
| 実装中の spec の直し | 20分 | 0分 | 5分 | 3,456,789 | $8.63 |
| 出荷とレビュー対応 | 1時間20分 | 1時間10分 | 0分 | 9,876,543 | $24.70 |
| その他 | 16分 | 10分 | 0分 | 790,226 | $4.40 |
| 合計 | 14時間5分 | 2時間10分 | 6時間28分 | 123,456,789 | $312.45 |

### モデルごと

| モデル | 役割 | 入力 | キャッシュの書き込み | キャッシュの読み込み | 出力 | 使用料 |
|---|---|---|---|---|---|---|
| claude-opus-5-5 | 本体の会話 | 100,456 | 2,856,789 | 61,123,456 | 376,789 | $155.20 |
| claude-opus-5-5 | spec の審査役 | 30,123 | 1,234,567 | 30,456,789 | 123,456 | $95.15 |
| claude-opus-5-5 | タスクごとの確認役 | 20,000 | 600,000 | 9,000,000 | 80,000 | $25.00 |
| claude-opus-5-5 | 書き方の点検役 | 10,234 | 456,789 | 8,765,432 | 45,678 | $20.60 |
| claude-haiku-5-5 | Explore | 5,678 | 345,678 | 7,801,419 | 23,456 | $16.50 |

### 往復と手戻り

| 項目 | 回数 |
|---|---|
| spec の審査役との往復 | 要件 3、設計 5、タスク 2 |
| 承認の前に、所有者が spec の直しを求めた | 要件 0、設計 1、タスク 0 |
| spec を作る途中で、前の段階に戻って直した | 1(設計から要件へ 1) |
| 実装の途中で、spec に戻って直した | 要件 0、設計 1、タスク 0 |
| 実装したコードに、タスクごとの確認役が問題を見つけ、コードを直した | 2 |
| PR の Codex レビューとの往復 | 3 |
| PR を出したあと、CI の自動チェックが失敗し、コードを直した | 1 |
| 同じ失敗を3回続けて直せず、AI が作業を止めて所有者に報告した | 0 |
| 実装の途中で、Issue を分けた | 無し |
| spec 無しで始め、実装の途中で spec に切り替えた | 0 |
| 200行の検査で PR が止まった | 0 |
| 自動レビューが、Issue の決めた方式から外れたとして PR を止めた | 0 |

### 価格

使用料は、https://platform.claude.com/docs/en/about-claude/pricing の公表価格で換算した。価格を確かめた日は 2026-10-24 である。

### 注記

- 会話が再開したきっかけのうち、仕組みが種類を見分けられなかったものが 3回あった。仕組みは、見分けられなかったきっかけの前の時間を、外の仕組みを待っていた時間として、作業時間と待ち時間に数えた。そのため、作業時間と待ち時間は、実際より長いことがある。
__MD__
cat >"$FIND" <<'__FIND__'
- AIの作業時間は 14時間5分で、過去 12件の中央値 5時間40分の 2.5倍だった。設計の審査の段階が 3時間10分だった。
- 実装中に spec へ戻った回数は 1 で、過去 10件の中央値は 0 だった。

### 直す案

- [501-1] 設計の審査の往復を減らすため、審査役に渡す差分を短くする。
- [501-2] extract.pl の、会話の再開のきっかけの値の一覧に、値 `example_value` を足す。
__FIND__
ROW501="| [#501]($URL/501#issuecomment-1000) | あり | 2026-11-02 | 14時間5分 | 123,456,789 | \$312.45 | 1 |"
IDX_NOTE="このコメントは、所有者がまだ起票するかを答えていない直す案の番号を、AI が覚えておくためのものである。案の文は、番号の頭の Issue の集計のコメントの所見にある。"
PUBDB='issues => [ iss(1, body => intro()), iss(501, title => "ふつうの Issue", locked => F, state => "open") ]'
# publish の出力の見込み: pubout <書けなかった書き込みの JSON の中身>
pubout() { printf '{"failed":[%s],"proposals":["501-1","501-2"],"url":"%s/501#issuecomment-1000"}' "$1" "$URL"; }

newgh publish
mkdb "$PUBDB"
rm -rf "$STATE"
run publish 501 --draft "$DRAFT" --findings "$FIND"
check "publish が 0 で終わり、集計のコメントの URL と案の ID と、空の書けなかった書き込みを出す" "$RC/$OUT/$ERR" "0/$(pubout '')/"
check "publish は、集計のコメント、案の索引、一覧の順に書く" "$(writes)" "issue comment 501 --body-file F|issue comment 1 --body-file F|issue edit 1 --body-file F|"
check "publish は、gh に渡す本文の一時ファイルを、手元の記録の置き場所に作る" \
    "$(grep -o -- '--body-file [^ ]*' "$FAKE_GH_DIR/calls.log" | grep -v -c -- "--body-file $STATE/")" "0"
check "集計のコメントが、1行目の印、report.md、### 所見 と所見のファイル、最後の数字の行の順に組み立てられる" \
    "$(dbq 'I(501)->{comments}[0]{body}')" \
    "$(printf '<!-- keirekipro-usage-report:v1 issue=501 -->\n\n%s\n\n### 所見\n\n%s\n\n<!-- keirekipro-usage-data:v1 %s -->' "$(cat "$DRAFT/report.md")" "$(cat "$FIND")" "$(cat "$DRAFT/report.json")")"
check "案の索引のコメントが、一覧の Issue の見本の形で書かれる" "$(dbq 'I(1)->{comments}[0]{body}')" \
    "$(printf '<!-- keirekipro-usage-proposals:v1 page=1 [{"id":"501-1","issue":501},{"id":"501-2","issue":501}] -->\n%s' "$IDX_NOTE")"
check "publish が一覧に足した行が、集計の値から作った行である" "$(dbq '"" . (lines(1))[-1]')" "$ROW501"
check "案の索引が一覧の本文に入らない" "$(dbq 'index(I(1)->{body}, "keirekipro-usage-proposals") < 0 ? "none" : "found"')" "none"
check "案の索引に書けたら proposals_pending を消す" "$(statejson issues/501.json)" "{}"
perl -MJSON::PP -e '
    do $ENV{KP_TEST_H} or die "h.pl: $@ $!";
    my $f = "$ENV{FAKE_GH_DIR}/db.json";
    open my $i, "<", $f or die $!;
    my $db = JSON::PP->new->decode(do { local $/; <$i> });
    close $i;
    $_->{body} = intro() for grep { $_->{number} == 1 } @{ $db->{issues} };
    open my $o, ">", $f or die $!;
    print $o JSON::PP->new->canonical->encode($db);
' || ng "一覧の本文を戻せない"
printf '%s\n' '{"list_pending":true}' >"$STATE/issues/501.json"
run list-ensure 501
check "list-ensure が、publish の書いた集計のコメントの最後の数字の行の JSON から作った行が、publish が一覧に足した行と同じになる" "$RC/$(dbq '"" . (lines(1))[-1]')" "0/$ROW501"

echo "== 集計のコメントの形に無い値"
mkdir -p "$TMP_ROOT/bad-json" "$TMP_ROOT/bad-md"
sed 's/^{/{"branch":"feat\/x",/' "$DRAFT/report.json" >"$TMP_ROOT/bad-json/report.json"
cp "$DRAFT/report.md" "$TMP_ROOT/bad-json/report.md"
cp "$DRAFT/report.json" "$TMP_ROOT/bad-md/report.json"
perl -pe 's/^(### 価格)$/余計な段落\n\n$1/' "$DRAFT/report.md" >"$TMP_ROOT/bad-md/report.md"
{ cat "$FIND"; printf '%s\n' '- <!-- 隠した行 -->'; } >"$TMP_ROOT/bad-findings.md"
newgh publish-bad
mkdb "$PUBDB"
rm -rf "$STATE"
run publish 501 --draft "$TMP_ROOT/bad-json" --findings "$FIND"
check "report.json に形に無い欄があると、publish は書かずに 1 で終わり、手元に何も残さない" "$RC/$(calls)/$(nlines "$ERR")/$(statejson issues/501.json)" "1//1/none"
run publish 501 --draft "$TMP_ROOT/bad-md" --findings "$FIND"
check "report.md に形に無い段落があると、publish は書かずに 1 で終わる" "$RC/$(calls)/$(nlines "$ERR")/$(statejson issues/501.json)" "1//1/none"
run publish 501 --draft "$DRAFT" --findings "$TMP_ROOT/bad-findings.md"
check "所見に HTML のコメントの印があると、publish は書かずに 1 で終わる" "$RC/$(calls)/$(nlines "$ERR")/$(statejson issues/501.json)" "1//1/none"

echo "== report.pl が決める役割とモデルの名前"
# report.pl は、agent_type の無い補助役を「補助役」に、モデルの分からない応答を「不明」にし、
# 表に無い agent_type(プラグインの補助役の「plugin:helper」など)をそのまま役割の名前にする
mkdir -p "$TMP_ROOT/names"
perl -MJSON::PP -e '
    my $j = JSON::PP->new->canonical;
    my $d = $j->decode(do { local $/; <STDIN> });
    my $m = $d->{models}[-1];
    $d->{models}[-1] = { %$m, role => "補助役" };
    push @{ $d->{models} }, { %$m, role => "plugin:helper" }, { %$m, model => "不明", usd => 0 };
    $d->{totals}{usd_unknown_models} = ["us.anthropic.claude-x-v1:0", "不明"];
    print $j->encode($d);
' <"$DRAFT/report.json" >"$TMP_ROOT/names/report.json" || ng "役割とモデルの名前の report.json を用意できない"
# report.md は、report.pl が価格の分からないモデルがあるときに書くとおり、使用料に「(価格が分からないモデルを除く)」を付け、注記に1行を足す
perl -pe 's/^\| claude-haiku-5-5 \| Explore \|(.*)$/| claude-haiku-5-5 | 補助役 |$1\n| claude-haiku-5-5 | plugin:helper |$1\n| 不明 | 本体の会話 | 1 | 1 | 1 | 1 | 価格が分からない |/;
    s/^(\| (?:使用料|合計) \|.*\$312\.45)( \|)$/$1(価格が分からないモデルを除く)$2/;
    s/^(### 注記)$/$1\n\n- 不明、us.anthropic.claude-x-v1:0の公表価格が分からないため、仕組みは、このモデルの使用料を数えていない。全体の合計と段階ごとの表の使用料は、このモデルの分を除いた額である。/' \
    "$DRAFT/report.md" | perl -0pe 's/(この.*額である。)\n\n(- )/$1\n$2/' >"$TMP_ROOT/names/report.md"
check "名前の見本の report.md に、価格の分からないモデルの注記が1行と、モデルを除いた使用料が2つある" \
    "$(grep -c '^- 不明、us\.anthropic\.claude-x-v1:0の公表価格' "$TMP_ROOT/names/report.md")/$(grep -c '[$]312[.]45(価格が分からないモデルを除く) |' "$TMP_ROOT/names/report.md")/$(grep -c '^$' "$TMP_ROOT/names/report.md")" \
    "1/2/$(grep -c '^$' "$DRAFT/report.md")"
newgh publish-names
mkdb "$PUBDB"
rm -rf "$STATE"
run publish 501 --draft "$TMP_ROOT/names" --findings "$FIND"
check "役割が 補助役 と plugin:helper で、モデルが 不明 の集計を、publish が書いて 0 で終わる" "$RC/$ERR/$(dbq 'scalar @{ I(501)->{comments} }')" "0//1"

echo "== 数えられない項目がある集計"
# report.pl は、数えられない行の値を null にし、uncountable に往復と手戻りの行の名前(rework の欄の名前)を入れる
for d in uncount uncount-bad; do mkdir -p "$TMP_ROOT/$d"; cp "$DRAFT/report.md" "$TMP_ROOT/$d/report.md"; done
for v in 'same_failure owner_fix' 'branch'; do
    if [ "$v" = branch ]; then d=uncount-bad; else d=uncount; fi
    perl -MJSON::PP -e '
        my $j = JSON::PP->new->canonical;
        my $d = $j->decode(do { local $/; <STDIN> });
        my @k = split / /, $ARGV[0];
        $d->{uncountable} = \@k;
        exists $d->{rework}{$_} and $d->{rework}{$_} = undef for @k;
        print $j->encode($d);
    ' "$v" <"$DRAFT/report.json" >"$TMP_ROOT/$d/report.json" || ng "数えられない項目の report.json を用意できない"
done
newgh publish-uncount
mkdb "$PUBDB"
rm -rf "$STATE"
run publish 501 --draft "$TMP_ROOT/uncount-bad" --findings "$FIND"
bad="$RC/$(calls)/$(nlines "$ERR")"
run publish 501 --draft "$TMP_ROOT/uncount" --findings "$FIND"
check "数えられない項目に往復と手戻りの行の名前がある集計を、publish が書いて 0 で終わる。行の名前でない値があると、書かずに 1 で終わる" \
    "$bad|$RC/$ERR/$(dbq 'scalar @{ I(501)->{comments} }')" "1//1|0//1"

echo "== 集計のコメントを書くときの失敗"
newgh publish-nopush
mkdb "repo => { owner => \"owner\", name => \"repo\", push => F }, $PUBDB"
rm -rf "$STATE"
run publish 501 --draft "$DRAFT" --findings "$FIND"
check "permissions.push が偽のときは、publish は書かずに 1 で終わり、手元に何も残さない" "$RC/$(writes)/$(nlines "$ERR")/$(statejson issues/501.json)" "1//1/none"
newgh publish-comment-fail
mkdb "$PUBDB"
rm -rf "$STATE"
printf '%s\n' '^issue comment 501 ' >"$FAKE_GH_DIR/fail"
run publish 501 --draft "$DRAFT" --findings "$FIND"
check "publish は、集計のコメントを書く前に proposals_pending を書く" "$RC/$(statejson issues/501.json)" '1/{"proposals_pending":["501-1","501-2"]}'
rm -f "$FAKE_GH_DIR/fail"
grep -v -e '^### 直す案$' -e '^- \[501-' "$FIND" >"$TMP_ROOT/no-proposals.md"
run publish 501 --draft "$DRAFT" --findings "$TMP_ROOT/no-proposals.md"
check "案の無い所見で書き直すと、前に書けなかった集計の proposals_pending を消し、案の索引を書かない" "$RC/$(statejson issues/501.json)/$(dbq 'idx_ids(1)')" "0/{}/"
newgh publish-index-fail
mkdb "$PUBDB"
rm -rf "$STATE"
printf '%s\n' '^issue comment 1 ' >"$FAKE_GH_DIR/fail"
run publish 501 --draft "$DRAFT" --findings "$FIND"
check "案の索引に書けなくても、publish は 0 で終わり、proposals を書けなかった書き込みとして出し、一覧に行を足す" "$RC/$OUT/$(dbq '"" . (lines(1))[-1]')" "0/$(pubout '"proposals"')/$ROW501"
check "案の索引に書けなかったときは、proposals_pending を残す" "$(statejson issues/501.json)" '{"proposals_pending":["501-1","501-2"]}'
rm -f "$FAKE_GH_DIR/fail"
run proposals-ensure 501
check "proposals-ensure が、proposals_pending の案を案の索引に足し、proposals_pending を消す" "$RC/$(dbq 'idx_ids(1)')/$(statejson issues/501.json)" "0/501-1 501-2/{}"
newgh publish-list-fail
mkdb "$PUBDB"
rm -rf "$STATE"
printf '%s\n' '^issue edit 1 ' >"$FAKE_GH_DIR/fail"
run publish 501 --draft "$DRAFT" --findings "$FIND"
check "一覧に書けなくても、publish は 0 で終わり、list を書けなかった書き込みとして出し、list_pending を残す" "$RC/$OUT/$(statejson issues/501.json)" "0/$(pubout '"list"')/{\"list_pending\":true}"

echo "== 案の索引のページ"
newgh index-pages
mkdb 'issues => [ iss(1, body => intro()) ]'
rm -rf "$STATE"
drive 'write_proposals(1, [ many(7, 1001) ], []); 0'
check "1,001件の案は、1,000件と1件の2つの索引のコメントに分かれ、一覧の本文は変わらない" "$RC/$(dbq 'idx_desc(1)')/$(dbq 'I(1)->{body} eq intro() ? "same" : "diff"')" "0/1:1000 2:1/same"
drive 'print length(Encode::decode("UTF-8", proposals_text(1, worst_ids()))) < 65536 ? "under" : "over"; 0'
check "ID の桁が最も多い1,000件の索引のコメントが、65,536文字に届かない" "$RC/$OUT" "0/under"
run proposal-remove 7-1001
check "案が無くなったページの索引のコメントを、JSON を [] にして残す" "$RC/$(dbq 'idx_desc(1)')" "0/1:1000 2:0"
newgh index-reread
mkdb 'issues => [ iss(1, body => intro()) ]'
rm -rf "$STATE"
drive 'clobber(1); write_proposals(1, ["7-1"], []); 0'
check "書いたあとに読み直して案が無ければ、索引のコメントを書き直す" "$RC/$(writes)/$(dbq 'idx_ids(1)')" "0/issue comment 1 --body-file F|issue comment 1 --body-file F|/7-1"

echo "== 案を外す"
newgh proposal-remove
mkdb 'issues => [ iss(1, body => intro(), comments => [ cm(2001, idx_body(1, "7-1")) ]) ]'
rm -rf "$STATE"
mkdir -p "$STATE/issues"
printf '%s\n' '{"proposals_pending":["7-1","7-2"]}' >"$STATE/issues/7.json"
run proposal-remove 7-1
check "proposal-remove が、案を proposals_pending と案の索引から外す" "$RC/$(statejson issues/7.json)/$(dbq 'idx_ids(1)')" '0/{"proposals_pending":["7-2"]}/'
run proposals-ensure 7
check "proposal-remove で外した案は、proposals-ensure で索引に戻らない" "$RC/$(dbq 'idx_ids(1)')/$(statejson issues/7.json)" "0/7-2/{}"

echo "== 答えていない案を読む"
newgh proposals-open
mkdb 'issues => [ iss(1, body => intro(), comments => [ cm(2001, idx_body(1, "501-1")), cm(2002, idx_body(1, "502-1"), "NONE") ]),
    iss(501, title => "t", locked => F, comments => [ cm(3001, rep_props(501, "- [501-1] 案の文その1")) ]),
    iss(502, title => "t", locked => F, comments => [ cm(3002, rep_props(502, "- [502-1] 案の文その2")) ]) ]'
rm -rf "$STATE"
run proposals-open
check "proposals-open が、案の ID と Issue の番号と案の文を出し、関係の欄の違う索引のコメントの案を出さない" "$RC/$OUT" '0/[{"id":"501-1","issue":501,"text":"案の文その1"}]'

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
