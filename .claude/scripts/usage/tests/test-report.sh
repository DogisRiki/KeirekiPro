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
# iss(<番号>, <親の番号>) は Issue である
mkdb() {
    perl -MJSON::PP -e '
        sub pr { my ($n, $st, $body, $br, $at, $sha) = @_;
            return { number => $n, state => $st, body => $body, headRefName => $br, baseRefName => "main",
                mergedAt => $at, mergeCommit => defined $sha ? { oid => $sha } : undef } }
        sub iss { my ($n, $parent) = @_; return { number => $n, parent => defined $parent ? { number => $parent } : undef } }
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
# report.json の値を読む: rj <perl の式>。R(<欄>, ...) は report.json の欄の値(欄を順にたどる)、J(<値>) は値の JSON である
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
