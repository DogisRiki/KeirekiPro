#!/bin/bash
# =====================================================================
# report.pl(Issue ごとの集計を作る部品)のテスト
#
# 実行: bash .claude/scripts/usage/tests/test-report.sh
# 偽の gh(fixtures/fake-gh.sh)を一時フォルダに gh の名前で写し、その一時フォルダを PATH の先頭に置く。
# 偽の gh は、一時フォルダの db.json を GitHub の代わりにする。本物の GitHub は読まない。
# 一時フォルダに git のリポジトリを作り、origin/main に spec.json とデータのファイルを足したコミットを置く。
# 手元の記録は、extract.pl が書く形の行を、テストが手で書く。
# 前提: bash・perl(JSON::PP)・git。
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPORT="$(cd "$HERE/.." && pwd)/report.pl"
CONFIG="$(cd "$HERE/.." && pwd)/usage-config.json"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/bin"
cp "$HERE/fixtures/fake-gh.sh" "$TMP_ROOT/bin/gh"
chmod +x "$TMP_ROOT/bin/gh"
PATH="$TMP_ROOT/bin:$PATH"
export PATH

# 日付は所有者の PC の時間帯で書くので、テストは時間帯を日本の時間に決める
TZ=JST-9
export TZ

# git が返すパス(Windows では C:/...)と同じ形で作る
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })
REPO="$WORK/repo"
STATE="$WORK/state"
OUTD="$WORK/draft"

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }

# ---- git のリポジトリ -------------------------------------------------------
# テストのリポジトリを作り直す。コミットの作者と時刻は固定する
newrepo() {
    rm -rf "$REPO"
    git init -q "$REPO"
    git -C "$REPO" config user.name test
    git -C "$REPO" config user.email test@example.com
    git -C "$REPO" config commit.gpgsign false
}
# ファイルを書いてコミットし、origin/main をそのコミットにする: commit <時刻(ISO 8601)> <パス>=<中身> ...
# 中身が空のパスは消す。最後に作ったコミットの ID を $SHA に置く
commit() {
    local when=$1
    shift
    local kv p v
    for kv in "$@"; do
        p=${kv%%=*}
        v=${kv#*=}
        if [ -z "$v" ]; then
            git -C "$REPO" rm -q "$p"
        else
            mkdir -p "$(dirname "$REPO/$p")"
            printf '%s\n' "$v" >"$REPO/$p"
            git -C "$REPO" add "$p"
        fi
    done
    GIT_AUTHOR_DATE=$when GIT_COMMITTER_DATE=$when git -C "$REPO" commit -q --allow-empty -m "c $when"
    SHA=$(git -C "$REPO" rev-parse HEAD)
    git -C "$REPO" update-ref refs/remotes/origin/main "$SHA"
}
CFGPATH=.claude/scripts/usage/usage-config.json

# ---- 偽の GitHub ---------------------------------------------------------------
# テストごとの偽の GitHub のフォルダを作り、FAKE_GH_DIR にする: newgh <名前>
newgh() {
    FAKE_GH_DIR="$TMP_ROOT/gh-$1"
    rm -rf "$FAKE_GH_DIR"
    mkdir -p "$FAKE_GH_DIR"
    export FAKE_GH_DIR
}
# 偽の GitHub の db.json を書く: mkdb <perl のハッシュの中身>。
# pr(<番号>, <状態>, <本文>, <ブランチ>, <マージの時刻>, <マージのコミット>) は main に向けた PR である。
# iss(<番号>, <親の番号>) は Issue である。closes(<マージのコミット>, <番号>...) は、番号ごとの、Issue を閉じるマージ済みの PR である
# withc(<PR>, [<コミット>...], [<コメントの本文>...]) は、PR にコミットとコメントを足す。
# runs(<コミット> => [[<検査の名前>, <結論>]...], ...) は、コミットごとの検査の結果である
mkdb() {
    perl -MJSON::PP -e '
        sub pr { my ($n, $st, $body, $br, $at, $sha) = @_;
            return { number => $n, state => $st, body => $body, headRefName => $br, baseRefName => "main",
                mergedAt => $at, mergeCommit => defined $sha ? { oid => $sha } : undef } }
        sub iss { my ($n, $parent) = @_; return { number => $n, parent => defined $parent ? { number => $parent } : undef } }
        sub closes { my ($sha, @n) = @_; return map { pr($_, "MERGED", "Closes #$_\n", "f$_", "2026-10-30T00:00:00Z", $sha) } @n }
        sub withc { my ($p, $c, $b) = @_; $p->{commits} = [ map { { oid => $_ } } @$c ];
            $p->{comments} = [ map { { body => $_ } } @$b ]; return $p }
        sub runs { my %r = @_; return { map { my $s = $_;
            ($s => [ map { { name => $_->[0], status => "completed", conclusion => $_->[1] } } @{ $r{$s} } ]) } keys %r } }
        my $db = { '"$1"' };
        open my $fh, ">", "$ENV{FAKE_GH_DIR}/db.json" or die $!;
        print $fh JSON::PP->new->canonical->encode($db);
    ' || ng "偽の GitHub を用意できない"
}

# ---- 手元の記録 ---------------------------------------------------------------
newstate() {
    rm -rf "$STATE" "$OUTD"
    mkdir -p "$STATE/extract"
}
# 抜き出した記録に行を足す: rec <記録の鍵> <JSON の行>...
rec() {
    local key=$1
    shift
    printf '%s\n' "$@" >>"$STATE/extract/$key.jsonl"
}
# 印を足す: mark <JSON の行>...
mark() { printf '%s\n' "$@" >>"$STATE/marks.jsonl"; }

# ---- 呼び出し ---------------------------------------------------------------
# report.pl を Issue N について呼び、標準出力を $OUT、標準エラーを $ERR、終了コードを $RC に置く: run <N> [引数...]
run() {
    local n=$1
    shift
    (cd "$REPO" && perl "$REPORT" --state "$STATE" --config "$CONFIG" --issue "$n" --out "$OUTD" "$@") \
        >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"
    RC=$?
    OUT=$(cat "$TMP_ROOT/out")
    ERR=$(cat "$TMP_ROOT/err")
}
# report.json の値を読む: rj <perl の式>。R(<欄>, ...) は report.json の欄の値(欄を順にたどる)、J(<値>) は値の JSON である。
# S(<欄>, ...) と M(<欄>, ...) は、段階ごとの行とモデルごとの行の、欄の値の配列の配列である。SUM(<欄>) は段階ごとの行の欄の値の合計である。
# W(<欄>, ...) は、往復と手戻りの欄の値の配列である
rj() {
    if [ ! -f "$OUTD/report.json" ]; then
        printf 'none'
        return
    fi
    perl -MJSON::PP -e '
        open my $fh, "<", $ARGV[0] or die $!;
        local $/;
        my $r = JSON::PP->new->decode(<$fh>);
        sub R { my $v = $r; $v = ref $v eq "ARRAY" ? $v->[$_] : $v->{$_} for @_; return $v }
        sub J { return JSON::PP->new->canonical->allow_nonref->encode($_[0]) }
        sub rows { my ($what, @f) = @_; return [ map { my $s = $_; [ map { $s->{$_} } @f ] } @{ R($what) || [] } ] }
        sub S { return rows("stages", @_) }
        sub M { return rows("models", @_) }
        sub SUM { my $s = 0; $s += $_->{ $_[0] } for @{ R("stages") || [] }; return $s }
        sub W { my $w = R("rework") || {}; return [ map { $w->{$_} } @_ ] }
        print '"$1"';
    ' "$OUTD/report.json"
}
# report.pl を読み込み、report.pl の中の関数を呼ぶ perl の文を動かし、出したものを $OUT に置く: drive <perl の文>
drive() {
    (cd "$REPO" && perl -e 'do $ARGV[0]; die $@ if $@; '"$1" "$REPORT") >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"
    RC=$?
    OUT=$(cat "$TMP_ROOT/out")
    ERR=$(cat "$TMP_ROOT/err")
}

# Issue N に決めた行を読む: issue_ids <N>。
# 「msg の行の id を並べたもの/分けた Issue なら 1/meta の行を添えた記録の鍵を並べたもの」を出す
issue_ids() {
    (cd "$REPO" && perl -e '
        do $ARGV[0];
        die $@ if $@;
        my $c = prepare({ issue => $ARGV[1], state => $ARGV[2], config => $ARGV[3] });
        my @rows = map { @$_ } values %{ $c->{irec} };
        my @ids = sort map { $_->{id} } grep { ($_->{k} // "") eq "msg" } @rows;
        my @meta = sort grep { grep { ($_->{k} // "") eq "meta" } @{ $c->{irec}{$_} } } keys %{ $c->{irec} };
        print join(",", @ids), "/", ($c->{split} ? 1 : 0), "/", join(",", @meta);
    ' "$REPORT" "$1" "$STATE" "$CONFIG") 2>"$TMP_ROOT/err"
}

echo "== 部品の形"
perl -c "$REPORT" >/dev/null 2>&1
check "perl -c が通る" "$?" "0"

echo "== Issue の PR と終了日"
newrepo
commit 2026-10-01T00:00:00Z "$CFGPATH={}"
commit 2026-10-20T03:00:00Z a.txt=1
SHA10=$SHA
commit 2026-11-01T16:00:00Z a.txt=2
SHA11=$SHA
newgh prs
mkdb 'prs => [
    pr(10, "MERGED", "変更\n\nRefs: #501\n", "feat/a", "2026-10-20T03:00:00Z", "'"$SHA10"'"),
    pr(11, "MERGED", "Closes #501\r\n", "feat/b", "2026-11-01T16:00:00Z", "'"$SHA11"'"),
    pr(12, "CLOSED", "Closes #501\n", "feat/c", undef, undef),
    pr(13, "OPEN", "Closes #501\n", "feat/d", undef, undef),
    pr(14, "MERGED", "Closes #5010\nsee Closes #501\n", "feat/e", "2026-11-05T00:00:00Z", "'"$SHA11"'") ]'
newstate
rec s0 '{"k":"recv","ts":1790812800,"how":"claim","issue":501,"branch":"feat/b"}' '{"k":"msg","ts":1790812860,"id":"m0"}'
run 501
check "PR が2つの Issue で、終了日が Closes の PR のマージの日になる" "$RC/$(rj 'J([R("issue"), R("prs"), R("end_date")])')" '0/[501,[10,11,12],"2026-11-02"]'
check "Issue の PR を、gh pr list の1回の呼び出しで集める" "$(grep -c '^pr list' "$FAKE_GH_DIR/calls.log")/$(grep '^pr list' "$FAKE_GH_DIR/calls.log")" \
    "1/pr list --state all --base main --limit 1000 --json number,state,body,headRefName,mergedAt,mergeCommit"
mkdb 'prs => [
    pr(11, "MERGED", "Closes #501\n", "feat/b", "2026-10-20T03:00:00Z", "'"$SHA10"'"),
    pr(12, "CLOSED", "Closes #501\n", "feat/c", undef, undef) ]'
run 501
check "マージせずに閉じた PR は終了日を決めない" "$RC/$(rj 'J([R("prs"), R("end_date")])')" '0/[[11,12],"2026-10-20"]'
mkdb 'prs => [ pr(12, "CLOSED", "Closes #501\n", "feat/c", undef, undef), pr(10, "MERGED", "Refs: #501\n", "feat/a", "2026-10-20T03:00:00Z", "'"$SHA10"'") ]'
rm -rf "$OUTD"
run 501
check "Issue を閉じる PR が無いと、集計を作らずに 1 で終わる" "$RC/$(rj 1)/$(printf '%s' "$ERR" | grep -c 'Issue #501 を閉じる PR')" "1/none/1"
printf '%s\n' '^pr list' >"$FAKE_GH_DIR/fail"
run 501
check "gh の読み取りに失敗すると、集計を作らずに 1 で終わる" "$RC/$(rj 1)" "1/none"
rm -f "$FAKE_GH_DIR/fail"

echo "== spec の有無"
newrepo
commit 2026-10-01T00:00:00Z "$CFGPATH={}" \
    '.kiro/specs/feat-a/spec.json={"feature_name":"feat-a","issue":501}' \
    '.kiro/specs/feat-b/spec.json={"feature_name":"feat-b","issue":400,"additional_issues":[503]}'
END1=$SHA
commit 2026-10-05T00:00:00Z '.kiro/specs/feat-c/spec.json={"feature_name":"feat-c","issue":505}'
newgh spec
mkdb 'prs => [
    pr(21, "MERGED", "Closes #501\n", "b501", "2026-10-02T00:00:00Z", "'"$END1"'"),
    pr(22, "MERGED", "Closes #502\n", "b502", "2026-10-02T00:00:00Z", "'"$END1"'"),
    pr(23, "MERGED", "Closes #503\n", "b503", "2026-10-02T00:00:00Z", "'"$END1"'"),
    pr(24, "MERGED", "Closes #504\n", "b504", "2026-10-02T00:00:00Z", "'"$END1"'"),
    pr(25, "MERGED", "Closes #505\n", "b505", "2026-10-02T00:00:00Z", "'"$END1"'") ]'
newstate
for n in 501 502 503 504 505; do
    rec "s$n" "{\"k\":\"recv\",\"ts\":1790812800,\"how\":\"claim\",\"issue\":$n,\"branch\":\"b$n\"}" '{"k":"msg","ts":1790812860,"id":"m"}'
done
mark '{"ts":1759363200,"session":"s1","kind":"switch-to-spec","stage":null,"issue":504,"branch":"b504"}' \
    '{"ts":1759363200,"session":"s1","kind":"spec-fix","stage":"design","issue":502,"branch":"b502"}'
got=""
for n in 501 502 503 504 505; do
    run "$n"
    got="$got $n:$RC:$(rj 'J(R("spec"))')"
done
check "終了の時刻の main に Issue の番号を持つ spec.json が無い Issue を spec 無しとし、switch-to-spec の印がある Issue を spec ありとする" \
    "$got" " 501:0:true 502:0:false 503:0:true 504:0:true 505:0:false"

echo "== 受け持ちの区切りと、行の Issue"
newrepo
commit 2026-09-01T00:00:00Z "$CFGPATH={}"
newgh assign
mkdb 'prs => [
    pr(10, "MERGED", "Refs: #501\n", "feat/a", "2026-10-10T00:00:00Z", "'"$SHA"'"),
    pr(11, "MERGED", "Closes #501\n", "feat/b", "2026-11-01T16:00:00Z", "'"$SHA"'"),
    pr(30, "MERGED", "Closes #502\n", "feat/z", "2026-11-01T16:00:00Z", "'"$SHA"'"),
    pr(40, "MERGED", "Closes #601\n", "feat/o", "2026-11-01T16:00:00Z", "'"$SHA"'"),
    pr(41, "MERGED", "Closes #602\n", "feat/q", "2026-11-01T16:00:00Z", "'"$SHA"'"),
    pr(42, "MERGED", "Closes #611\n", "feat/s", "2026-11-01T16:00:00Z", "'"$SHA"'"),
    pr(50, "MERGED", "Closes #701\n", "feat/k", "2026-11-01T16:00:00Z", "'"$SHA"'"),
    pr(60, "MERGED", "Closes #800\n", "feat/w", "2026-10-21T00:00:00Z", "'"$SHA"'"),
    pr(70, "MERGED", "Closes #900\n", "feat/x", "2026-10-02T00:00:00Z", "'"$SHA"'") ],
  issues => [ iss(501), iss(502), iss(600), iss(601, 600), iss(602, 600), iss(610), iss(611), iss(700), iss(701) ]'
newstate
# s1: #501 を受け持ち、補助役を動かし、別のセッションを起こし、/request に移り、#502 を受け持つ
rec s1 '{"k":"meta","session":"s1"}' \
    '{"k":"stage","ts":1790733600,"name":"start","issue":501,"spec_stage":null}' \
    '{"k":"recv","ts":1790734000,"how":"check-start","issue":501,"branch":null}' \
    '{"k":"branch","ts":1790799800,"name":"feat/a"}' \
    '{"k":"msg","ts":1790800800,"id":"m1"}' \
    '{"k":"spawn","ts":1790801800,"child":"local_aaa"}' \
    '{"k":"recv","ts":1790802800,"how":"claim","issue":501,"branch":"feat/b"}' \
    '{"k":"msg","ts":1790803800,"id":"m2"}' \
    '{"k":"stage","ts":1790804800,"name":"request","issue":null,"spec_stage":null}' \
    '{"k":"branch","ts":1790804900,"name":"main"}' \
    '{"k":"msg","ts":1790805800,"id":"m3"}' \
    '{"k":"stage","ts":1790806800,"name":"start","issue":502,"spec_stage":null}' \
    '{"k":"recv","ts":1790806900,"how":"claim","issue":502,"branch":"feat/z"}' \
    '{"k":"msg","ts":1790807800,"id":"m4"}'
rec s1.agent-x1 '{"k":"meta","session":"s1","agent_id":"x1"}' '{"k":"msg","ts":1790801300,"id":"ma"}'
rec s2 '{"k":"branch","ts":1790802300,"name":"claude/zzz"}' '{"k":"msg","ts":1790802400,"id":"ms"}'
rec desktop '{"local":"local_aaa","session":"s2"}'
# s3: #501 のすぐあとに #502 を受け持ち、#502 の終了の時刻のあとにも動く
rec s3 '{"k":"recv","ts":1790815800,"how":"claim","issue":501,"branch":"feat/b"}' '{"k":"msg","ts":1790815900,"id":"n1"}' \
    '{"k":"recv","ts":1790816800,"how":"claim","issue":502,"branch":"feat/z"}' '{"k":"msg","ts":1790816900,"id":"n2"}' \
    '{"k":"msg","ts":1793548900,"id":"n3"}'
# s4: 受け持ちの出来事が無く、#501 の2つのブランチで動き、終了の時刻のあとにも動く
rec s4 '{"k":"branch","ts":1790813800,"name":"feat/a"}' '{"k":"msg","ts":1790813900,"id":"m5"}' \
    '{"k":"branch","ts":1790814800,"name":"feat/b"}' '{"k":"msg","ts":1790814900,"id":"m6"}' '{"k":"msg","ts":1793548900,"id":"m7"}'
# s5 s6: #600 を分けた #601 と #602。s6 は、s5 が #601 を受け持ったあとに #600 を受け持ち、#602 を受け持つ。s7: 親子でない #610 のあとに #611
rec s5 '{"k":"stage","ts":1790832800,"name":"start","issue":600,"spec_stage":null}' \
    '{"k":"recv","ts":1790832810,"how":"claim","issue":600,"branch":"feat/o"}' '{"k":"msg","ts":1790832900,"id":"p1"}' \
    '{"k":"recv","ts":1790833000,"how":"claim","issue":601,"branch":"feat/o"}' '{"k":"msg","ts":1790833100,"id":"p2"}'
rec s6 '{"k":"recv","ts":1790833150,"how":"takeover","issue":600,"branch":null}' '{"k":"msg","ts":1790833160,"id":"p0"}' \
    '{"k":"recv","ts":1790833210,"how":"claim","issue":602,"branch":"feat/q"}' '{"k":"msg","ts":1790833300,"id":"p3"}'
rec s7 '{"k":"recv","ts":1790833400,"how":"claim","issue":610,"branch":"feat/r"}' '{"k":"msg","ts":1790833500,"id":"q1"}' \
    '{"k":"recv","ts":1790833600,"how":"claim","issue":611,"branch":"feat/s"}' '{"k":"msg","ts":1790833700,"id":"q2"}'
# s8: #700 を受け持ち、#700 を #701 にまとめ、#701 を受け持つ
rec s8 '{"k":"stage","ts":1790833800,"name":"start","issue":700,"spec_stage":null}' '{"k":"msg","ts":1790833900,"id":"r1"}' \
    '{"k":"merge","ts":1790833950,"from":700,"to":701}' \
    '{"k":"recv","ts":1790834000,"how":"claim","issue":701,"branch":"feat/k"}' '{"k":"msg","ts":1790834100,"id":"r2"}'
# s9: 受け持ちの出来事が無く、ほかのブランチのあとに #800 のブランチで動く。s10: #900 のマージのあとにだけ動く
rec s9 '{"k":"branch","ts":1790899200,"name":"other"}' '{"k":"msg","ts":1790899300,"id":"w0"}' \
    '{"k":"branch","ts":1791244800,"name":"feat/w"}' '{"k":"msg","ts":1791244810,"id":"w1"}'
rec s10 '{"k":"branch","ts":1790985600,"name":"feat/x"}' '{"k":"msg","ts":1790985610,"id":"x1"}'
check "補助役の行と、別に起こしたセッションの行と、PR の2つのブランチの行が本体の Issue に入り、/request のあとと終了の時刻のあとの行は入らない" \
    "$(issue_ids 501)" "m1,m2,m5,m6,ma,ms,n1/0/s1,s1.agent-x1"
check "1つの会話が続けて受け持った2つの Issue は、区切りで分かれ、同じ行が重ならず、終了の時刻のあとの行は入らない" "$(issue_ids 502)" "m4,n2/0/s1"
: >"$FAKE_GH_DIR/calls.log"
check "分けた Issue では、親の区切りが最初に受け持った子に入る" "$(issue_ids 601)/$(grep -c '^issue view 601 --json parent$' "$FAKE_GH_DIR/calls.log")" "p1,p2/1//1"
: >"$FAKE_GH_DIR/calls.log"
check "親の区切りは、2つ目に受け持った子には入らない" "$(issue_ids 602)/$(grep -c '^issue view 602' "$FAKE_GH_DIR/calls.log")" "p3/0//0"
check "親子でない Issue のあとに受け持った Issue には、前の区切りが入らない" "$(issue_ids 611)" "q2/0/"
check "まとめた Issue では、まとめられた Issue の区切りが入る" "$(issue_ids 701)" "r1,r2/0/"
run 501
check "開始日が、初めて受け持った日(所有者の PC の時間帯の日付)になる" "$RC/$(rj 'R("start_date")')" "0/2026-09-30"
run 800
check "受け持ちの出来事が無いと、開始日が Issue のブランチで最初に動いた日になる" "$RC/$(rj 'R("start_date")')" "0/2026-10-06"
rm -rf "$OUTD"
run 900
check "手元の記録に Issue に決まる行が1つも無いと、下書きを書かずに 2 で終わる" "$RC/$(rj 1)/$(printf '%s' "$ERR" | grep -c 'Issue #900 の記録が無い')" "2/none/1"
printf '%s\n' '^issue view 601' >"$FAKE_GH_DIR/fail"
run 601
check "gh で親を読めないと、集計を作らずに 1 で終わる" "$RC" "1"
rm -f "$FAKE_GH_DIR/fail"

echo "== 作業時間"
# 時刻は T0 からの秒数で書く。会話ごとに、受け持ちの出来事で Issue を決める
T0=1790000000
newrepo
commit 2026-09-01T00:00:00Z "$CFGPATH={}"
newgh time
mkdb 'prs => [ closes("'"$SHA"'", 1001 .. 1011) ]'
newstate
mkdir -p "$STATE/durations"
# 受け持ち: rv <記録の鍵> <時刻> <Issue>
rv() { rec "$1" "{\"k\":\"recv\",\"ts\":$((T0 + $2)),\"how\":\"claim\",\"issue\":$3,\"branch\":null}"; }
# 応答: rmsg <記録の鍵> <時刻> <応答の終わりなら true>
rmsg() { rec "$1" "{\"k\":\"msg\",\"ts\":$((T0 + $2)),\"id\":\"$1-$2\",\"model\":\"claude-opus-5-5\",\"end\":$3}"; }
# 次の行を始めた者: rturn <記録の鍵> <時刻> <from> [<知らせの元の仕事>]
rturn() {
    local job=null raw=''
    [ $# -ge 4 ] && job="\"$4\""
    [ "$3" = unknown ] && raw=',"raw":"x"'
    rec "$1" "{\"k\":\"turn\",\"ts\":$((T0 + $2)),\"from\":\"$3\",\"job\":$job$raw}"
}
# 道具の呼び出しと結果: rtool <記録の鍵> <呼び出しの時刻> <結果の時刻> <識別子> <種類> <待ちの分類> <perm> [<仕事> <仕事の種類>]。
# extract.pl と同じく、道具の行を結果の行の直前に書く
rtool() {
    local job=null jk=null
    [ $# -ge 9 ] && job="\"$8\"" jk="\"$9\""
    rec "$1" "{\"k\":\"tool\",\"ts\":$((T0 + $2)),\"id\":\"$4\",\"kind\":\"$5\",\"cat\":\"$6\",\"perm\":\"$7\",\"bg\":false}" \
        "{\"k\":\"result\",\"ts\":$((T0 + $3)),\"id\":\"$4\",\"err\":false,\"job\":$job,\"job_kind\":$jk}"
}
rlim() { rec "$1" "{\"k\":\"limit\",\"ts\":$((T0 + $2)),\"resets_at\":null}"; }
rretry() { rec "$1" "{\"k\":\"retry\",\"ts\":$((T0 + $2)),\"ms\":$3}"; }
# 道具の実行時間: rdur <セッションの ID> <識別子> <ミリ秒>
rdur() { printf '%s\t%s\n' "$2" "$3" >>"$STATE/durations/$1.tsv"; }
# 「<終了コード>:」に続けて、全体の合計の作業時間、待ち時間、同時に動いた時間、上限で止まった回数、上限で止まった時間と、見分けられなかった再開の数を JSON の配列で出す
tot() {
    run "$1"
    printf '%s:' "$RC"
    rj 'J([R("totals", "work_sec"), R("totals", "wait_sec"), R("totals", "concurrent_sec"), R("totals", "limit_count"), R("totals", "limit_sec"), R("unknown_turns")])'
}
# #1001: 2つの会話が [150,200] で重なる
rv a1 0 1001; rmsg a1 100 false; rmsg a1 200 true
rv a2 150 1001; rmsg a2 250 false; rmsg a2 300 true
check "2つの会話が重なった時間が作業時間に1回だけ入り、同時に動いた時間に入る" "$(tot 1001)" "0:[300,0,50,0,0,0]"
# #1002: 所有者の返事の待ち(300秒)、ask の道具(200秒)、権限の確認(実行時間10秒を引いた50秒と、実行時間の記録が無い30秒)、
# ほかのセッションの知らせ(1000秒)を除く
rv b1 0 1002; rmsg b1 100 true; rturn b1 400 owner; rmsg b1 450 false
rtool b1 450 650 tb1 ask "" other; rmsg b1 700 false
rtool b1 700 760 tb2 shell "" user; rdur b1 tb2 10000
rtool b1 760 790 tb3 shell "" user; rmsg b1 800 true
rturn b1 1800 peer; rmsg b1 1850 true
check "応答の終わりのあと owner の行までの時間と、ask の道具の時間と、perm が user の道具の確認の時間(実行時間を引いた残り)が作業時間に入らない" \
    "$(tot 1002)" "0:[270,0,0,0,0,0]"
# #1003: 見分けられなかった再開の前の60秒と20秒が待ち
rv c1 0 1003; rmsg c1 100 true; rturn c1 160 unknown; rmsg c1 200 false; rmsg c1 210 true; rturn c1 230 unknown; rmsg c1 240 true
check "turn.from が unknown の行までの時間が待ち時間に入り、unknown_turns に回数が出る" "$(tot 1003)" "0:[240,80,0,0,0,2]"
# #1004: 上限の印から所有者の行までの1000秒
rv d1 0 1004; rmsg d1 100 false; rlim d1 150; rturn d1 1150 owner; rmsg d1 1200 true
check "上限の印のあとの時間が作業時間に入らず、上限で止まった回数と時間が全体の合計に別に出る" "$(tot 1004)" "0:[200,0,0,1,1000,0]"
# #1005: 応答の終わりから、上限が戻ったあとの再開の知らせまでの2000秒
rv e1 0 1005; rmsg e1 100 true; rturn e1 2100 limit; rmsg e1 2150 true
check "msg.end が真の応答のあとに turn.from が limit の行が来た記録で、その間の時間が作業時間と待ち時間に入らず、上限で止まった回数と時間に入る" \
    "$(tot 1005)" "0:[150,0,0,1,2000,0]"
# #1006: 上限の印のすぐあとに再開の知らせ
rv f1 0 1006; rmsg f1 100 false; rlim f1 120; rturn f1 3120 limit; rmsg f1 3200 true
check "上限の印のすぐあとに turn.from が limit の行が来ると、上限で止まった回数が1回になる" "$(tot 1006)" "0:[200,0,0,1,3000,0]"
# #1007: 裏で動かした補助役が上限の印で終わり、本体の会話は応答を終えたあとに再開の知らせを受ける
rv g1 0 1007; rtool g1 50 60 tg1 agent "" other gb1 agent; rmsg g1 100 true; rturn g1 3500 limit; rmsg g1 3550 true
rec g1.agent-gb1 '{"k":"meta","session":"g1","agent_id":"gb1"}'
rmsg g1.agent-gb1 110 false; rmsg g1.agent-gb1 400 false; rlim g1.agent-gb1 500
check "補助役の会話が上限の印で終わり、本体の会話に msg.end が真の応答と turn.from が limit の行があると、上限で止まった回数が1回になる" \
    "$(tot 1007)" "0:[530,0,0,1,3400,0]"
# #1008: 再開の知らせ、上限の印、再開の知らせの順
rv h1 0 1008; rmsg h1 100 true; rturn h1 1100 limit; rlim h1 1101; rturn h1 2101 limit; rmsg h1 2150 true
check "msg.end が真の応答、turn.from が limit の行、上限の印、turn.from が limit の行の順に並ぶと、上限で止まった回数が1回になる" \
    "$(tot 1008)" "0:[149,0,0,1,2001,0]"
# #1009: 本体の会話 [200,1200] と別に起こしたセッションの会話 [300,1400] が上限で止まる
rv i1 0 1009; rec i1 "{\"k\":\"spawn\",\"ts\":$((T0 + 10)),\"child\":\"local_i\"}"
rmsg i1 100 false; rlim i1 200; rturn i1 1200 owner; rmsg i1 1250 true
rec desktop '{"local":"local_i","session":"i2"}'
rmsg i2 20 false; rmsg i2 150 false; rlim i2 300; rturn i2 1400 owner; rmsg i2 1450 true
check "本体の会話と別に起こしたセッションの会話が同じ時間に上限で止まると、回数が1回で、重なった時間を1回だけ数える" \
    "$(tot 1009)" "0:[400,0,180,1,1200,0]"
# #1010: 品質チェックの600秒、裏で動かした Bash の知らせを待った1000秒、API の再試行の30秒が待ち
rv j1 0 1010; rmsg j1 50 false; rtool j1 50 650 tj1 shell "品質チェック" other; rmsg j1 700 false
rtool j1 700 701 tj2 shell "" other jb1 other; rmsg j1 710 true; rturn j1 1710 notice jb1
rretry j1 1720 30000; rmsg j1 1800 true
check "品質チェックの分類に当たる道具の時間と、裏で動かした Bash の知らせを待った時間と、API の再試行の時間が待ち時間に入る" \
    "$(tot 1010)" "0:[1800,1630,0,0,0,0]"
# #1011: 本体の会話が同期の補助役を [50,1050] 待ち、補助役は品質チェックを600秒待つ。補助役の知らせの前の1000秒も本体に入らない
rv k1 0 1011; rmsg k1 50 false; rtool k1 50 1050 tk1 agent "" other kb1 agent; rmsg k1 1100 true; rturn k1 2100 notice kb1; rmsg k1 2150 true
rec k1.agent-kb1 '{"k":"meta","session":"k1","agent_id":"kb1"}'
rmsg k1.agent-kb1 60 false; rtool k1.agent-kb1 100 700 tk2 shell "品質チェック" other; rmsg k1.agent-kb1 800 false; rmsg k1.agent-kb1 1000 true
check "同期の補助役を待つ本体の時間が、本体にも同時に動いた時間にも入らず、補助役の側に入る。補助役が品質チェックを待った時間は待ち時間に入る" \
    "$(tot 1011)" "0:[1090,600,0,0,0,0]"

echo "== 段階とモデルと役割ごとのトークン数と使用料"
# 時刻は T0 からの秒数で書く。#2001 だけが spec ありの Issue である
newrepo
commit 2026-09-01T00:00:00Z "$CFGPATH={}" '.kiro/specs/feat-s/spec.json={"feature_name":"feat-s","issue":2001}'
newgh tokens
mkdb 'prs => [ closes("'"$SHA"'", 2001 .. 2005) ]'
newstate
# 段階の印: rst <記録の鍵> <時刻> <名前> [<spec-review の段階>]
rst() {
    local s=null
    [ $# -ge 4 ] && s="\"$4\""
    rec "$1" "{\"k\":\"stage\",\"ts\":$((T0 + $2)),\"name\":\"$3\",\"issue\":null,\"spec_stage\":$s}"
}
# 入力が1トークンの応答: rm1 <記録の鍵> <時刻> <応答の終わりなら true>
rm1() {
    rec "$1" "{\"k\":\"msg\",\"ts\":$((T0 + $2)),\"id\":\"$1-$2\",\"model\":\"claude-opus-5-5\",\"in\":1,\"cw5\":0,\"cw1h\":0,\"cr\":0,\"out\":0,\"ws\":0,\"fast\":false,\"us\":false,\"end\":$3}"
}
# トークン数を持つ応答: rtk <記録の鍵> <時刻> <message.id> <モデルか null> <入力> <5分の書き込み> <1時間の書き込み> <読み込み> <出力> [<fast> <us> <Web 検索の回数>]
rtk() {
    local m="\"$4\"" f=false u=false w=0
    [ "$4" = null ] && m=null
    [ $# -ge 10 ] && f=${10}
    [ $# -ge 11 ] && u=${11}
    [ $# -ge 12 ] && w=${12}
    rec "$1" "{\"k\":\"msg\",\"ts\":$((T0 + $2)),\"id\":\"$3\",\"model\":$m,\"in\":$5,\"cw5\":$6,\"cw1h\":$7,\"cr\":$8,\"out\":$9,\"ws\":$w,\"fast\":$f,\"us\":$u,\"end\":false}"
}
# 「<終了コード>:」に続けて、段階ごとの行の名前と作業時間と同時に動いた時間とトークン数と、全体の合計の同じ3つの値を JSON の配列で出す
stg() {
    run "$1"
    printf '%s:' "$RC"
    rj 'J([S("name", "work_sec", "concurrent_sec", "tokens"), R("totals", "work_sec"), R("totals", "concurrent_sec"), R("totals", "tokens")])'
}
# #2001: 着手の判断・要件のあとに書き方の点検役(STAGE は requirements)を同期で待ち、要件の審査のあとに spec の審査役(STAGE は tasks)を
# 同期で待ち、実装のあとに設計を直す。spec ありの Issue の claim は段階を変えない。印の無い会話 t2 は、本体の会話と [860,900] で重なる
rec t1 "{\"k\":\"stage\",\"ts\":$T0,\"name\":\"start\",\"issue\":2001,\"spec_stage\":null}"
rm1 t1 100 false; rst t1 150 kiro-spec-requirements; rv t1 160 2001; rm1 t1 200 false
rtool t1 200 400 tt1 agent "" other
rst t1 450 spec-review requirements; rm1 t1 500 false
rtool t1 500 700 tt2 agent "" other
rst t1 750 kiro-impl; rm1 t1 800 false; rst t1 850 kiro-spec-design; rm1 t1 900 true
rec t1.agent-c1 '{"k":"meta","session":"t1","agent_id":"c1","agent_type":"spec-style-checker","stage":"requirements"}'
rm1 t1.agent-c1 210 false; rm1 t1.agent-c1 390 true
rec t1.agent-r1 '{"k":"meta","session":"t1","agent_id":"r1","agent_type":"spec-reviewer","stage":"tasks"}'
rm1 t1.agent-r1 510 false; rm1 t1.agent-r1 690 true
rec t2 "{\"k\":\"branch\",\"ts\":$((T0 + 860)),\"name\":\"f2001\"}"
rm1 t2 950 false; rm1 t2 1300 true
run 2001
check "段階ごとの表の合計が全体の合計と一致し、印の無い時間が その他 に入る" \
    "$RC:$(rj 'J([SUM("work_sec"), R("totals", "work_sec"), SUM("wait_sec"), R("totals", "wait_sec"), SUM("concurrent_sec"), R("totals", "concurrent_sec"), SUM("tokens"), R("totals", "tokens"), R("stages", 10, "name"), R("stages", 10, "work_sec")])')" \
    '0:[1260,1260,0,0,40,40,11,11,"その他",400]'
# #2002: spec 無しの Issue。着手の判断のあとに claim する
rec t3 "{\"k\":\"stage\",\"ts\":$T0,\"name\":\"start\",\"issue\":2002,\"spec_stage\":null}"
rm1 t3 100 false; rv t3 150 2002; rm1 t3 200 true
check "spec-review の引数と、審査役と点検役の STAGE と、kiro-impl のあとの spec の直しが、それぞれの段階に入り、spec 無しの Issue では claim のあとが 実装 に入る" \
    "$(stg 2001) $(stg 2002)" \
    '0:[[["着手の判断",150,0,1],["要件",100,0,1],["要件の審査",280,0,3],["設計",0,0,0],["設計の審査",0,0,0],["タスク",0,0,0],["タスクの審査",180,0,2],["実装",100,0,1],["実装中の spec の直し",50,40,1],["出荷とレビュー対応",0,0,0],["その他",400,0,2]],1260,40,11] 0:[[["着手の判断",150,0,1],["実装",50,0,1],["出荷とレビュー対応",0,0,0],["その他",0,0,0]],200,0,2]'
# #2003: 1時間の書き込みと Web 検索、fast、us、Haiku 5.5 の10万トークンちょうどの応答と超える応答、価格の無いモデル、日付の付いたモデルの ID
rv t4 0 2003
rtk t4 10 a claude-opus-5-5 1000000 0 1000000 0 0 false false 2
rtk t4 20 b claude-opus-5-5 1000000 1000000 0 0 0 true false 0
rtk t4 30 c claude-opus-5-5 1000000 0 0 1000000 0 false true 0
rtk t4 40 d claude-haiku-5-5 100000 0 0 0 0
rtk t4 50 e claude-haiku-5-5 50000 0 0 60000 0
rtk t4 60 f claude-fable-5-2 1000 0 0 0 0
rtk t4 70 g claude-opus-4-20250514 0 0 0 0 1000000
run 2003
check "価格がデータのファイルに無いモデルの使用料が 価格が分からない になり、Haiku 5.5 の10万トークンを超える応答と fast と us の価格が当たる" \
    "$RC:$(rj 'J([M("model", "role", "in", "cw", "cr", "out", "usd"), R("totals", "tokens"), R("totals", "usd"), R("totals", "usd_unknown_models")])')" \
    '0:[[["claude-opus-4-20250514","本体の会話",0,0,0,1000000,75],["claude-opus-5-5","本体の会話",3000000,2000000,1000000,0,34.64],["claude-haiku-5-5","本体の会話",150000,0,60000,0,0.038],["claude-fable-5-2","本体の会話",1000,0,0,0,null]],7211000,109.678,["claude-fable-5-2"]]'
# #2004: 2つの会話が同じ message.id の応答を持つ
rv t5 0 2004; rtk t5 10 dup claude-opus-5-5 100 0 0 0 0
rv t6 0 2004; rtk t6 10 dup claude-opus-5-5 100 0 0 0 0; rtk t6 20 u claude-opus-5-5 1 0 0 0 0
run 2004
check "2つの会話に同じ message.id があっても1回だけ数える" "$RC:$(rj 'J([R("totals", "tokens"), M("model", "role", "in")])')" '0:[101,[["claude-opus-5-5","本体の会話",101]]]'
# #2005: 本体の会話の2つのモデル、判定を返した確認役、判定を打ち消して NEXT_ACTION を返した補助役、
# モデルを meta の行にだけ持つ Explore、spec の審査役、別に起こしたセッション
rv t7 0 2005; rec t7 "{\"k\":\"spawn\",\"ts\":$((T0 + 5)),\"child\":\"local_t8\"}"
rec desktop '{"local":"local_t8","session":"t8"}'
rtk t7 10 m7a claude-sonnet-5-5 64 0 0 0 0; rtk t7 20 m7b claude-opus-5-5 1 0 0 0 0
rec t7.agent-v1 '{"k":"meta","session":"t7","agent_id":"v1","agent_type":"general-purpose"}' \
    "{\"k\":\"verdict\",\"ts\":$((T0 + 35)),\"value\":\"APPROVED\",\"next_action\":false}"
rtk t7.agent-v1 30 v1m claude-opus-5-5 2 0 0 0 0
rec t7.agent-v2 '{"k":"meta","session":"t7","agent_id":"v2","agent_type":"general-purpose"}' \
    "{\"k\":\"verdict\",\"ts\":$((T0 + 40)),\"value\":\"REJECTED\",\"next_action\":false}" \
    "{\"k\":\"verdict\",\"ts\":$((T0 + 45)),\"value\":null,\"next_action\":true}"
rtk t7.agent-v2 42 v2m claude-opus-5-5 4 0 0 0 0
rec t7.agent-v3 '{"k":"meta","session":"t7","agent_id":"v3","agent_type":"Explore","model":"claude-haiku-5-5"}'
rtk t7.agent-v3 50 v3m null 8 0 0 0 0
rec t7.agent-v4 '{"k":"meta","session":"t7","agent_id":"v4","agent_type":"spec-reviewer"}'
rtk t7.agent-v4 60 v4m claude-sonnet-5-5 16 0 0 0 0
rtk t8 70 t8m claude-opus-5-5 16 0 0 0 0
run 2005
check "本体の会話と、agent_type と verdict から決めた役割と、別に起こしたセッションが、モデルと役割の組ごとに分かれる" \
    "$RC:$(rj 'J(M("model", "role", "in"))')" \
    '0:[["claude-sonnet-5-5","本体の会話",64],["claude-opus-5-5","別に起こしたセッション",16],["claude-sonnet-5-5","spec の審査役",16],["claude-opus-5-5","原因を調べる補助役",4],["claude-opus-5-5","タスクごとの確認役",2],["claude-opus-5-5","本体の会話",1],["claude-haiku-5-5","Explore",8]]'

echo "== 印と spec の記録と補助役の報告から数える往復と手戻り"
# 時刻は T0 からの秒数で書く。#2010 は spec ありの Issue で、#2013 は spec 無しの Issue、#2015 は #2014 を分けた Issue である
# T0 からの秒数の時刻を ISO 8601 で出す: iso <秒数>
iso() { perl -MPOSIX -e 'print POSIX::strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($ARGV[0]))' $((T0 + $1)); }
# 承認の記録の要素: ah <段階> <承認した時刻> <取り消した時刻> <取り消した理由>
ah() { printf '{"stage":"%s","approved_by":"o","approved_at":"%s","issues":[2010],"revoked_at":"%s","revoked_for":"%s"}' "$1" "$(iso "$2")" "$(iso "$3")" "$4"; }
# 取り消しの記録: design だけを戻す(100)、requirements と design を戻す(200)、実装中に design と tasks を戻す(300)、
# Issue #2012 のための更新で3つの段階を戻す(400)、開始より前に戻す(-1000)
HIST="$(ah design 90 100 "D1 による design への差し戻し"),$(ah requirements 20 200 "R1"),$(ah design 180 200 "R1"),\
$(ah design 280 300 "T1"),$(ah tasks 290 300 "T1"),$(ah requirements 350 400 "Issue #2012 のための更新"),\
$(ah design 360 400 "Issue #2012 のための更新"),$(ah tasks 370 400 "Issue #2012 のための更新"),$(ah requirements -2000 -1000 "X")"
APPR="{\"requirements\":{\"approved\":true,\"approved_at\":\"$(iso 500)\"},\"design\":{\"approved\":true,\"approved_at\":\"$(iso 600)\"},\"tasks\":{\"approved\":true,\"approved_at\":\"$(iso 700)\"}}"
newrepo
commit 2026-09-01T00:00:00Z "$CFGPATH={}" \
    ".kiro/specs/feat-r/spec.json={\"feature_name\":\"feat-r\",\"issue\":2010,\"additional_issues\":[2012],\"approvals\":$APPR,\"approval_history\":[$HIST]}"
newgh rework
mkdb 'prs => [ closes("'"$SHA"'", 2010 .. 2015) ], issues => [ iss(2010), iss(2013), iss(2014), iss(2015, 2014) ]'
newstate
# 審査役か点検役か確認役の会話: rsub <記録の鍵> <agent_type> <STAGE か null> <CYCLE か null> <ROUND か null> [<verdict の値>...]
rsub() {
    local key=$1 type=$2 st=$3 cy=$4 ro=$5 v i=0
    [ "$st" != null ] && st="\"$st\""
    shift 5
    rec "$key" "{\"k\":\"meta\",\"session\":\"x\",\"agent_id\":\"x\",\"agent_type\":\"$type\",\"stage\":$st,\"cycle\":$cy,\"round\":$ro}"
    rm1 "$key" 1000 false
    for v in "$@"; do
        i=$((i + 1))
        [ "$v" != null ] && v="\"$v\""
        rec "$key" "{\"k\":\"verdict\",\"ts\":$((T0 + 1000 + i)),\"value\":$v,\"next_action\":false}"
    done
}
# 印: rmk <種類> <時刻> <会話> <段階か null> <Issue か null>
rmk() {
    local st=$4
    [ "$st" != null ] && st="\"$st\""
    mark "{\"ts\":$((T0 + $2)),\"session\":\"$3\",\"kind\":\"$1\",\"stage\":$st,\"issue\":$5,\"branch\":null}"
}
rv u1 0 2010; rm1 u1 2000 true
rsub u1.agent-a spec-reviewer requirements 1 1
rsub u1.agent-b spec-reviewer requirements 1 2
rsub u1.agent-c spec-reviewer requirements 1 2
rsub u1.agent-d spec-reviewer design 2 1
rsub u1.agent-e spec-style-checker requirements 1 3
rsub u1.agent-f general-purpose null null null REJECTED
rsub u1.agent-g general-purpose null null null REJECTED null
rsub u1.agent-h general-purpose null null null APPROVED
rsub u1.agent-i general-purpose null null null APPROVED REJECTED
# 取り消された design(150)と tasks(450)の spec-fix は数えない。ほかの Issue の会話と、ほかの Issue の番号の印も数えない
rv u2 0 2011; rm1 u2 10 true
rmk spec-fix 150 u1 design null; rmk spec-fix 190 u1 design null; rmk spec-fix 30 u1 requirements null
rmk spec-fix 450 u1 tasks null; rmk spec-fix 200 u2 design null
rmk same-failure 800 u1 null null; rmk same-failure 900 u1 null 2010; rmk same-failure 910 u1 null 2099
rmk switch-to-spec 50 u1 null 2010
run 2010
check "approval_history の、Issue #N のための更新でない要素から、前の段階に戻った回数と実装中に戻った回数が分かれて数えられる" \
    "$RC:$(rj 'J([R("rework", "spec_back"), R("rework", "impl_spec_back")])')" \
    '0:[[{"from":"tasks","to":"design"},{"from":"tasks","to":"requirements"}],{"design":1,"requirements":0,"tasks":0}]'
check "spec-fix と same-failure と switch-to-spec の印が、それぞれの行に数えられ、承認を取り消された段階の spec-fix の印は数えない" \
    "$RC:$(rj 'J([R("rework", "owner_fix"), R("rework", "same_failure"), R("rework", "switch_to_spec")])')" \
    '0:[{"design":1,"requirements":1,"tasks":0},2,1]'
check "spec の審査役との往復が STAGE ごとの CYCLE と ROUND の組で数えられ、最後の判定が REJECTED の確認役の会話が数えられる" \
    "$RC:$(rj 'J([R("rework", "spec_review_rounds"), R("rework", "task_rejected"), R("rework", "split")])')" \
    '0:[{"design":1,"requirements":2,"tasks":0},2,false]'
# #2013: spec 無しの Issue に、審査役の会話と、spec-fix と same-failure の印がある
rv u3 0 2013; rm1 u3 2000 true
rsub u3.agent-a spec-reviewer requirements 1 1
rmk spec-fix 100 u3 requirements 2013; rmk same-failure 120 u3 null 2013
run 2013
check "spec 無しの Issue で、spec に関わる行が無い" \
    "$RC:$(rj 'J(W("spec_review_rounds", "owner_fix", "spec_back", "impl_spec_back", "switch_to_spec", "same_failure"))')" \
    '0:[{"design":0,"requirements":0,"tasks":0},{"design":0,"requirements":0,"tasks":0},[],{"design":0,"requirements":0,"tasks":0},0,1]'
# #2015: 会話 u4 が #2014 を受け持ち、#2014 を分けた #2015 を受け持つ
rv u4 0 2014; rm1 u4 10 false; rv u4 100 2015; rm1 u4 110 true
check "分けた Issue で、分けた行が 有 になる" \
    "$(run 2015; printf '%s:' "$RC"; rj 'J(R("rework", "split"))')" '0:true'

echo "== PR と CI と Codex レビューから数える往復と手戻り"
# #2020 はマージせずに閉じた PR 30 と閉じた PR 31 を持ち、#2021 は除く検査の失敗を持ち、#2022 は Codex レビューのコメントを持つ。
# コミットの ID は、PR の番号と、PR の中の順番である
CX='## Codex Review(自動クロスレビュー)\n\n> x\n\n'
newrepo
commit 2026-09-01T00:00:00Z "$CFGPATH={}"
newgh prci
mkdb 'prs => [
    withc(pr(30, "CLOSED", "Closes #2020\n", "f30", undef, undef), [qw(a300001 a300002 a300003)],
        ["'"$CX"'| 項目 | 判定 | 根拠 |\n|---|---|---|\n| 印を残す | 沿っていない | a.pl:1 |\n"]),
    withc(pr(31, "MERGED", "Closes #2020\n", "f31", "2026-10-30T00:00:00Z", "'"$SHA"'"), [qw(a310001)], []),
    withc(pr(32, "MERGED", "Closes #2021\n", "f32", "2026-10-30T00:00:00Z", "'"$SHA"'"), [qw(a320001 a320002 a320003)], []),
    withc(pr(33, "MERGED", "Closes #2022\n", "f33", "2026-10-30T00:00:00Z", "'"$SHA"'"), [qw(a330001)],
        ["'"$CX"'| 項目 | 判定 | 根拠 |\n|---|---|---|\n| 印を残す | 沿っている | a.pl:1 |\n", "'"$CX"'VERDICT_CODE_QUALITY: PASS\n",
         "## Codex Review 打ち切り(往復上限に到達)\n", "見出しの前の文\n'"$CX"'", "沿っていない\n"]) ],
    check_runs => runs(
        a300001 => [["size-check", "success"], ["test", "failure"]],
        a300002 => [["size-check", "failure"], ["test", "success"]],
        a300003 => [["size-check", "failure"], ["test", "failure"]],
        a310001 => [["size-check", "success"]],
        a320001 => [["rerun-approval-gated-checks", "failure"], ["rerun", "failure"], ["update-pr-branches", "failure"],
            ["escape-hatch", "failure"], ["dependency-gate", "failure"], ["pre-merge-check", "failure"], ["codex-review", "failure"]],
        a320002 => [["test", "cancelled"], ["build", "success"]],
        a320003 => [["test", "failure"]],
        a330001 => [["test", "success"]])'
newstate
rv p1 0 2020; rm1 p1 10 true
rv p2 0 2021; rm1 p2 10 true
rv p3 0 2022; rm1 p3 10 true
run 2020
check "マージせずに閉じた PR の size-check の失敗が1と数えられ、閉じた PR の CI の失敗と Codex レビューも数えられる" \
    "$RC:$(rj 'J(W("size_check_stops", "ci_fix", "codex_rounds", "decided_method_stops"))')" '0:[1,1,1,1]'
run 2021
check "ci_exclude_checks の検査と取り消された検査の失敗を数えない" \
    "$RC:$(rj 'J(W("ci_fix", "size_check_stops"))')" '0:[0,0]'
run 2022
check "Codex レビューのコメントが往復の回数にだけ入り、使用料に入らない" \
    "$RC:$(rj 'J([W("codex_rounds", "decided_method_stops"), M("model", "role")])')" '0:[[2,0],[["claude-opus-5-5","本体の会話"]]]'

echo "== 数えられない行と、読めなかった記録"
# 時刻は T0 からの秒数で書く。#2030 は、仕組みが main に入る前に受け持った spec ありの Issue である
U3='J([R("uncountable"), W("owner_fix", "same_failure", "switch_to_spec"), R("partial_records")])'
U5='J([R("uncountable"), W("spec_review_rounds", "owner_fix", "task_rejected", "same_failure", "switch_to_spec"), R("partial_records")])'
UP='J([R("uncountable"), R("partial_records")])'
NULL5='[["spec_review_rounds","owner_fix","task_rejected","same_failure","switch_to_spec"],[null,null,null,null,null],true]'
LOCAL1=local_11111111-1111-1111-1111-111111111111
# 別に起こしたセッションの出来事: rspawn <記録の鍵> <時刻>
rspawn() { rec "$1" "{\"k\":\"spawn\",\"ts\":$((T0 + $2)),\"child\":\"$LOCAL1\"}"; }
newrepo
commit 2026-09-01T00:00:00Z '.kiro/specs/feat-u/spec.json={"feature_name":"feat-u","issue":2030}'
commit 2026-10-01T00:00:00Z "$CFGPATH={}"
newgh uncount
mkdb 'prs => [ closes("'"$SHA"'", 2030 .. 2039) ]'
newstate
rv q0 0 2030; rm1 q0 10 true
run 2030
check "仕組みが main に入る前に受け持った Issue で、数えられない行が 数えられない になる" \
    "$RC:$(rj "$U3")" '0:[["owner_fix","same_failure","switch_to_spec"],[null,null,null],false]'
# #2031 から #2039 は、仕組みが main に入ったあとに受け持った Issue で、#2036 だけが spec 無しの Issue である
newrepo
commit 2026-09-01T00:00:00Z "$CFGPATH={}" \
    '.kiro/specs/feat-v/spec.json={"feature_name":"feat-v","issue":2031,"additional_issues":[2032,2033,2034,2035,2037,2038,2039]}'
newgh uncount2
mkdb 'prs => [ closes("'"$SHA"'", 2030 .. 2039) ]'
newstate
mkdir -p "$STATE/durations"
rv q1 0 2031; rtool q1 5 6 t1 shell "" other; rm1 q1 10 true
run 2031
r2031="$RC:$(rj "$U3")"
newstate
mkdir -p "$STATE/durations"
rv q2 0 2032; rtool q2 5 6 t2 shell "" other; rdur q2 t2 5; rm1 q2 10 true
run 2032
check "道具を使ったのに durations に行が無い本体の会話があると、印から数える3行が 数えられない になり、すべての本体の会話に durations の行があり印が無いときは 0 になる" \
    "$r2031/$RC:$(rj "$U3")" \
    '0:[["owner_fix","same_failure","switch_to_spec"],[null,null,null],false]/0:[[],[{"design":0,"requirements":0,"tasks":0},0,0],false]'
newstate
rv q3 0 2033; rm1 q3 10 true
printf '{"offset":1,"size":1,"skipped":1,"version":1}\n' >"$STATE/extract/q3.pos"
run 2033
check ".pos の飛ばした行の数が1以上の会話があると、design が挙げる5行が null になり、uncountable に出る" "$RC:$(rj "$U5")" "0:$NULL5"
newstate
mkdir -p "$STATE/durations"
rv q4 0 2034; rtool q4 5 6 t4 agent "" other abc agent; rtool q4 7 8 t5 agent "" other def agent; rdur q4 t4 1; rm1 q4 10 true
rsub q4.agent-def general-purpose null null null APPROVED
run 2034
check "補助役の起動があるのに補助役の記録が無い会話があると、design が挙げる5行が null になり、uncountable に出る" "$RC:$(rj "$U5")" "0:$NULL5"
check "補助役の起動があるのに補助役の記録が無いとき、読めなかったことが記録される" "$RC:$(rj 'J(R("partial_records"))')" '0:true'
newstate
mkdir -p "$STATE/durations"
rv q5 0 2035; rtool q5 7 8 t6 agent "" other def agent; rdur q5 t6 1; rm1 q5 10 true
rsub q5.agent-def general-purpose null null null APPROVED
printf '{"offset":1,"size":1,"skipped":0,"version":1}\n' >"$STATE/extract/q5.pos"
run 2035
check "補助役の記録がそろい、.pos の飛ばした行の数が 0 のとき、読めなかったことが記録されない" "$RC:$(rj "$UP")" '0:[[],false]'
newstate
mkdir -p "$STATE/durations"
rv q6 0 2036; rm1 q6 10 true; rdur lost1 t9 1
run 2036
r2036="$RC:$(rj 'J([R("uncountable"), W("task_rejected", "same_failure"), R("partial_records")])')"
newstate
rv q6 0 2036; rm1 q6 10 true; rmk same-failure 5 lost2 null 2036
run 2036
check "durations にセッションの ID があり、extract にその記録が無いとき、読めなかったことが記録される" \
    "$r2036/$RC:$(rj 'J(R("partial_records"))')" '0:[["task_rejected","same_failure"],[null,null],true]/0:true'
newstate
rv q7 0 2037; rm1 q7 10 true
run 2037
check "ターミナルで動かした会話だけで desktop.jsonl が無くても、読めなかったことが記録されない" "$RC:$(rj "$UP")" '0:[[],false]'
newstate
rv q8 0 2038; rspawn q8 5; rm1 q8 10 true
run 2038
check "別に起こしたセッションの出来事があり、desktop.jsonl が無く、ブランチでも結び付けられないとき、読めなかったことが記録される" \
    "$RC:$(rj 'J(R("partial_records"))')" '0:true'
newstate
rv q9 0 2039; rspawn q9 5; rm1 q9 10 true
rec q9b "{\"k\":\"branch\",\"ts\":$((T0 + 20)),\"name\":\"f2039\"}"; rm1 q9b 30 true
run 2039
r2039="$RC:$(rj "$UP")"
newstate
rv q8 0 2038; rspawn q8 5; rm1 q8 10 true; rm1 q8c 30 true
printf '{"local":"%s","session":"q8c"}\n' "$LOCAL1" >"$STATE/extract/desktop.jsonl"
run 2038
check "別に起こしたセッションの会話がブランチか desktop.jsonl で結び付くとき、読めなかったことが記録されない" \
    "$r2039/$RC:$(rj "$UP")" '0:[[],false]/0:[[],false]'

echo "== 集計のコメントの本文"
# report.md の見出しの節の中身を出す: mdsec <見出し>
mdsec() { awk -v h="$1" '$0 == h { on = 1; next } on && /^#/ { on = 0 } on' "$OUTD/report.md"; }
# report.md の見出しの節の表の、見出しの行を除く行の1列目を「,」で区切って出す: mdcol <見出し>
mdcol() {
    mdsec "$1" | awk '/^\| / && !/^\|---/ { n++; if (n > 1) { s = substr($0, 3); sub(/ \|.*/, "", s); printf "%s%s", (n > 2 ? "," : ""), s } }'
}
PRICE_SRC=$(perl -MJSON::PP -e 'local $/; open my $f, "<", $ARGV[0] or die; print JSON::PP->new->decode(<$f>)->{prices}{source}' "$CONFIG")
PRICE_DAY=$(perl -MJSON::PP -e 'local $/; open my $f, "<", $ARGV[0] or die; print JSON::PP->new->decode(<$f>)->{prices}{checked_on}' "$CONFIG")
NOTE_PRICE='- claude-unknown-9の公表価格が分からないため、仕組みは、このモデルの使用料を数えていない。全体の合計と段階ごとの表の使用料は、このモデルの分を除いた額である。'
newrepo
commit 2026-09-01T00:00:00Z "$CFGPATH={}" '.kiro/specs/feat-w/spec.json={"feature_name":"feat-w","issue":2040}'
newgh md
mkdb 'prs => [ closes("'"$SHA"'", 2040 .. 2041) ]'
newstate
rv sess-2040-zz 0 2040
rec sess-2040-zz "{\"k\":\"branch\",\"ts\":$((T0 + 1)),\"name\":\"f2040\"}"
rtk sess-2040-zz 1800 m1 claude-opus-5-5 1000000 0 0 0 0
rtk sess-2040-zz 3900 m2 claude-unknown-9 1234 0 0 0 0
rm1 sess-2040-zz 3920 true
before=$(date +%s)
run 2040
after=$(date +%s)
EXP=$(cat <<'EOF'
## AIの作業の集計

| 開始日 | 終了日 | spec | PR |
|---|---|---|---|
| 2026-09-21 | 2026-10-30 | あり | #2040 |

### 全体の合計

| 項目 | 値 |
|---|---|
| AIの作業時間 | 1時間5分 |
| トークン数 | 1,001,235 |
| 使用料 | $4.00(価格が分からないモデルを除く) |
| 使う量の上限で止まった回数 | 0 |
| 使う量の上限で止まっていた時間 | 0分 |

### 段階ごと

| 段階 | AIの作業時間 | そのうち待ち時間 | 審査役などが同時に動いた時間 | トークン数 | 使用料 |
|---|---|---|---|---|---|
| 着手の判断 | 0分 | 0分 | 0分 | 0 | $0.00 |
| 要件 | 0分 | 0分 | 0分 | 0 | $0.00 |
| 要件の審査 | 0分 | 0分 | 0分 | 0 | $0.00 |
| 設計 | 0分 | 0分 | 0分 | 0 | $0.00 |
| 設計の審査 | 0分 | 0分 | 0分 | 0 | $0.00 |
| タスク | 0分 | 0分 | 0分 | 0 | $0.00 |
| タスクの審査 | 0分 | 0分 | 0分 | 0 | $0.00 |
| 実装 | 0分 | 0分 | 0分 | 0 | $0.00 |
| 実装中の spec の直し | 0分 | 0分 | 0分 | 0 | $0.00 |
| 出荷とレビュー対応 | 0分 | 0分 | 0分 | 0 | $0.00 |
| その他 | 1時間5分 | 0分 | 0分 | 1,001,235 | $4.00 |
| 合計 | 1時間5分 | 0分 | 0分 | 1,001,235 | $4.00(価格が分からないモデルを除く) |

### モデルごと

| モデル | 役割 | 入力 | キャッシュの書き込み | キャッシュの読み込み | 出力 | 使用料 |
|---|---|---|---|---|---|---|
| claude-opus-5-5 | 本体の会話 | 1,000,001 | 0 | 0 | 0 | $4.00 |
| claude-unknown-9 | 本体の会話 | 1,234 | 0 | 0 | 0 | 価格が分からない |

### 往復と手戻り

| 項目 | 回数 |
|---|---|
| spec の審査役との往復 | 要件 0、設計 0、タスク 0 |
| 承認の前に、所有者が spec の直しを求めた | 要件 0、設計 0、タスク 0 |
| spec を作る途中で、前の段階に戻って直した | 0 |
| 実装の途中で、spec に戻って直した | 要件 0、設計 0、タスク 0 |
| 実装したコードに、タスクごとの確認役が問題を見つけ、コードを直した | 0 |
| PR の Codex レビューとの往復 | 0 |
| PR を出したあと、CI の自動チェックが失敗し、コードを直した | 0 |
| 同じ失敗を3回続けて直せず、AI が作業を止めて所有者に報告した | 0 |
| 実装の途中で、Issue を分けた | 無し |
| spec 無しで始め、実装の途中で spec に切り替えた | 0 |
| 200行の検査で PR が止まった | 0 |
| 自動レビューが、Issue の決めた方式から外れたとして PR を止めた | 0 |

### 価格

使用料は、@SRC@ の公表価格で換算した。価格を確かめた日は @DAY@ である。

### 注記

EOF
)
EXP="${EXP//@SRC@/$PRICE_SRC}"
EXP="${EXP//@DAY@/$PRICE_DAY}"
EXP="$EXP

$NOTE_PRICE"
check "作り物の記録から作った report.md が、集計のコメントの見本と同じ見出しと表の列と行の並びを持ち、数が数の書き方の形で書かれる" \
    "$RC:$(cat "$OUTD/report.md" 2>/dev/null)" "0:$EXP"
check "report.md に、作業時間・トークン数・使用料・回数・日付・番号・段階とモデルと役割の名前のほかの値が入らない" \
    "$(grep -c -e sess-2040-zz -e f2040 "$OUTD/report.md")" "0"
created=$(cat "$OUTD/created_at" 2>/dev/null)
cr=bad
case $created in
    '' | *[!0-9]*) ;;
    *) [ "$created" -ge "$before" ] && [ "$created" -le "$after" ] && cr=ok ;;
esac
check "report.pl が、下書きのディレクトリに、作った時刻の created_at を書く" "$cr" "ok"
check "report.json に、形の版と価格の出どころが入る" "$(rj 'J([R("v"), R("prices")])')" \
    "[1,{\"checked_on\":\"$PRICE_DAY\",\"source\":\"$PRICE_SRC\"}]"
newstate
rv s41 0 2041; rm1 s41 10 true
run 2041
check "spec 無しの Issue では、段階ごとの表が5行、往復と手戻りの表が7行になる" \
    "$RC:$(mdcol '### 段階ごと')/$(mdcol '### 往復と手戻り')" \
    "0:着手の判断,実装,出荷とレビュー対応,その他,合計/実装したコードに、タスクごとの確認役が問題を見つけ、コードを直した,PR の Codex レビューとの往復,PR を出したあと、CI の自動チェックが失敗し、コードを直した,同じ失敗を3回続けて直せず、AI が作業を止めて所有者に報告した,実装の途中で、Issue を分けた,200行の検査で PR が止まった,自動レビューが、Issue の決めた方式から外れたとして PR を止めた"
r2041="$(grep -c '^### 注記' "$OUTD/report.md")"
# #2042 は、仕組みが main に入る前に受け持ち、注記の条件にすべて当たる spec ありの Issue である
newrepo
commit 2026-09-01T00:00:00Z \
    ".kiro/specs/feat-x/spec.json={\"feature_name\":\"feat-x\",\"issue\":2042,\"approval_history\":[$(ah requirements 1 5 X),$(ah design 2 6 X),$(ah requirements 3 7 X)]}"
commit 2026-10-01T00:00:00Z "$CFGPATH={}"
newgh md2
mkdb 'prs => [ closes("'"$SHA"'", 2042) ]'
newstate
rv sess-2042-zz 0 2042; rtool sess-2042-zz 5 6 t1 shell "" other; rturn sess-2042-zz 8 unknown
rtk sess-2042-zz 9 m3 claude-unknown-9 1 0 0 0 0; rm1 sess-2042-zz 10 true
printf '{"offset":1,"size":1,"skipped":1,"version":1}\n' >"$STATE/extract/sess-2042-zz.pos"
run 2042
EXP="| 項目 | 回数 |
|---|---|
| spec の審査役との往復 | 数えられない |
| 承認の前に、所有者が spec の直しを求めた | 数えられない |
| spec を作る途中で、前の段階に戻って直した | 3(設計から要件へ 2、タスクから設計へ 1) |
| 実装の途中で、spec に戻って直した | 要件 0、設計 0、タスク 0 |
| 実装したコードに、タスクごとの確認役が問題を見つけ、コードを直した | 数えられない |
| PR の Codex レビューとの往復 | 0 |
| PR を出したあと、CI の自動チェックが失敗し、コードを直した | 0 |
| 同じ失敗を3回続けて直せず、AI が作業を止めて所有者に報告した | 数えられない |
| 実装の途中で、Issue を分けた | 無し |
| spec 無しで始め、実装の途中で spec に切り替えた | 数えられない |
| 200行の検査で PR が止まった | 0 |
| 自動レビューが、Issue の決めた方式から外れたとして PR を止めた | 0 |"
check "前の段階に戻った行に戻った組ごとの回数が出て、数えられない行の全部が 数えられない になる" "$RC:$(mdsec '### 往復と手戻り' | sed '/^$/d')" "0:$EXP"
EXP="- この Issue は、仕組みが入る前に着手した。「数えられない」と書いた項目は、数えるための印を作業の途中で残す仕組みが、着手のときにまだ無かった項目である。
- 会話の記録の一部を読めなかった。Claude は、この Issue の作業の一部を、仕組みが入る前の設定で始めた会話で行った。「数えられない」と書いた項目は、その会話では、数えるための印が残らなかった項目である。
- 会話の記録の一部を読めなかった。仕組みは、この集計を、読めた分だけで数えた。そのため、作業時間とトークン数と使用料は、実際より少ないことがある。往復と手戻りの表の「数えられない」の項目は、読めなかった会話から数える項目である。
$NOTE_PRICE
- 会話が再開したきっかけのうち、仕組みが種類を見分けられなかったものが 1回あった。仕組みは、見分けられなかったきっかけの前の時間を、外の仕組みを待っていた時間として、作業時間と待ち時間に数えた。そのため、作業時間と待ち時間は、実際より長いことがある。"
check "注記は、条件に当たるものだけが注記の箇条の順に出て、どれにも当たらないときは見出しも出ない" \
    "$RC:$(mdsec '### 注記' | sed '/^$/d')/$r2041" "0:$EXP/0"
drive 'binmode STDOUT, ":encoding(UTF-8)"; print join "/", hm(0), hm(29), hm(30), hm(3569), hm(3570), hm(50700),
    commas(0), commas(999), commas(1000), commas(123456789), usd_text(0), usd_text(0.004), usd_text(1234.56), usd_text(312.449), usd_text(0.125), usd_text(1.005), usd_text(0.015), usd_text(2.675)'
check "時間とトークン数と使用料が、数の書き方の形になる" "$RC:$OUT" "0:0分/0分/1分/59分/1時間0分/14時間5分/0/999/1,000/123,456,789/\$0.00/\$0.00/\$1,234.56/\$312.45/\$0.13/\$1.01/\$0.02/\$2.68"

echo "== 過去との比べと、見分けられなかった値の一覧"
# 一覧の行(github.pl list-read の出力の形)を書く: lrow <番号> <終了日> <作業時間の秒> <トークン数> <使用料> <実装中に spec へ戻った回数>
lrow() {
    printf '{"issue":%s,"url":"https://example.com/c%s","spec":true,"end_date":"%s","work_sec":%s,"tokens":%s,"usd":%s,"impl_spec_back":%s,"usd_partial":false}' \
        "$1" "$1" "$2" "$3" "$4" "$5" "$6"
}
# compare.json の値を読む: cj <perl の式>。P は past_rows、C(<欄>) は values の行ごとの欄の値の配列、J(<値>) は値の JSON である
cj() {
    if [ ! -f "$OUTD/compare.json" ]; then
        printf 'none'
        return
    fi
    perl -MJSON::PP -e '
        open my $fh, "<", $ARGV[0] or die $!;
        local $/;
        my $c = JSON::PP->new->decode(<$fh>);
        sub P { return $c->{past_rows} }
        sub C { my ($k) = @_; return [ map { $_->{$k} } @{ $c->{values} || [] } ] }
        sub J { return JSON::PP->new->canonical->allow_nonref->encode($_[0]) }
        print '"$1"';
    ' "$OUTD/compare.json"
}
LIST="$WORK/list.json"
newrepo
commit 2026-09-01T00:00:00Z "$CFGPATH={}" '.kiro/specs/feat-c/spec.json={"feature_name":"feat-c","issue":2050}'
newgh cmp
mkdb 'prs => [ closes("'"$SHA"'", 2050) ]'
newstate
rv s50 0 2050
rtk s50 1800 m1 claude-opus-5-5 1000000 0 0 0 0
rm1 s50 2400 true
# 前に終わった行は #2047(終了日が同じで番号が小さい)と #2048 と #2049。#2048 の回数は数えられない。
# #2051(終了日が同じで番号が大きい)と #2060(終了日が新しい)は、比べる相手に入らない
printf '[%s,%s,%s,%s,%s]\n' "$(lrow 2049 2026-10-29 600 100 1.00 3)" "$(lrow 2048 2026-10-28 1800 300 3.00 null)" \
    "$(lrow 2047 2026-10-30 1200 200 2.00 1)" "$(lrow 2051 2026-10-30 99999 99999 999.00 9)" \
    "$(lrow 2060 2026-10-31 99999 99999 999.00 9)" >"$LIST"
run 2050 --list "$LIST"
c_old="$RC:$(cj 'J([P(), C("rows"), C("median"), C("median_text")])')"
check "一覧に、この Issue より終了日の新しい行と、終了日が同じで番号の大きい行があっても、その行は past_rows にも中央値にも入らない" \
    "$c_old" "0:[3,[3,3,3,2],[1200,200,2,2],[\"20分\",\"200\",\"\$2.00\",\"2\"]]"
check "compare.json の値が、集計の値と数の書き方の形の文字になり、ratio が値を中央値で割った値になる" \
    "$(cj 'J([C("name"), C("value"), C("value_text"), C("ratio")])')" \
    "[[\"AIの作業時間\",\"トークン数\",\"使用料\",\"実装中に spec へ戻った回数\"],[2400,1000001,4.000004,0],[\"40分\",\"1,000,001\",\"\$4.00\",\"0\"],[2,5000.005,2,0]]"
u_none=$(cat "$OUTD/unknown.json" 2>/dev/null)
printf '[]\n' >"$LIST"
run 2050 --list "$LIST"
c_empty="$RC:$(cj 'J([P(), C("rows"), C("median"), C("median_text"), C("ratio")])')"
run 2050
c_nolist="$RC:$(cj 'J([P(), C("ratio")])')"
printf '[%s]\n' "$(lrow 2001 2026-10-01 0 0 0 0)" >"$LIST"
run 2050 --list "$LIST"
check "compare.json で、過去の行が無いと past_rows が 0 になり、中央値が 0 の値の ratio が null になり、数えられない過去の行が中央値から除かれる" \
    "$c_empty/$c_nolist/$RC:$(cj 'J([P(), C("median"), C("ratio")])')/${c_old##*,}" \
    '0:[0,[0,0,0,0],[null,null,null,null],[null,null,null,null],[null,null,null,null]]/0:[0,[null,null,null,null]]/0:[1,[0,0,0,0],[null,null,null,null]]/"2"]]'
printf 'x\n' >"$LIST"
rm -rf "$OUTD"
run 2050 --list "$LIST"
check "一覧の行のファイルが行の JSON の配列でないと、下書きを書かずに 1 で終わる" "$RC:$(find "$OUTD" -type f 2>/dev/null | wc -l | tr -d ' ')" "1:0"
newstate
rv s50 0 2050
rec s50 "{\"k\":\"turn\",\"ts\":$((T0 + 5)),\"from\":\"unknown\",\"job\":null,\"raw\":\"qq-raw-1\"}" \
    "{\"k\":\"turn\",\"ts\":$((T0 + 6)),\"from\":\"unknown\",\"job\":null,\"raw\":\"qq-raw-1\"}" \
    "{\"k\":\"turn\",\"ts\":$((T0 + 7)),\"from\":\"unknown\",\"job\":null,\"raw\":\"qq-raw-2\"}" \
    "{\"k\":\"turn\",\"ts\":$((T0 + 8)),\"from\":\"unknown\",\"job\":null}"
rm1 s50 10 true
run 2050
check "unknown.json に raw の値ごとの回数が出て、report.json と report.md には raw の値が出ず、注記に回数と作業時間が長く数えられたことがあることが出る" \
    "$RC:$(cat "$OUTD/unknown.json" 2>/dev/null)/$u_none/$(cat "$OUTD/report.json" "$OUTD/report.md" 2>/dev/null | grep -c qq-raw)/$(rj 'R("unknown_turns")')/$(grep -c '見分けられなかったものが 4回あった。.*実際より長いことがある。' "$OUTD/report.md")" \
    '0:{"":1,"qq-raw-1":2,"qq-raw-2":1}/{}/0/4/1'

echo "== 仕組みが main に入った時刻"
newrepo
commit 2026-10-01T00:00:00Z a.txt=1
commit 2026-10-10T12:34:56+09:00 "$CFGPATH={}"
commit 2026-10-12T00:00:00Z "$CFGPATH={\"x\":1}"
drive 'print system_time()'
check "仕組みが main に入った時刻が、データのファイルを足したコミットの時刻になる" "$RC/$OUT" "0/1791603296"
newrepo
commit 2026-10-01T00:00:00Z a.txt=1
drive 'print defined system_time() ? "defined" : "undef"'
check "origin/main にデータのファイルを足したコミットが無いと、仕組みが main に入った時刻は無い" "$RC/$OUT" "0/undef"

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
