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
# pr(<番号>, <状態>, <本文>, <ブランチ>, <マージの時刻>, <マージのコミット>) は main に向けた PR である
mkdb() {
    perl -MJSON::PP -e '
        sub pr { my ($n, $st, $body, $br, $at, $sha) = @_;
            return { number => $n, state => $st, body => $body, headRefName => $br, baseRefName => "main",
                mergedAt => $at, mergeCommit => defined $sha ? { oid => $sha } : undef } }
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
mark '{"ts":1759363200,"session":"s1","kind":"switch-to-spec","stage":null,"issue":504,"branch":"b504"}' \
    '{"ts":1759363200,"session":"s1","kind":"spec-fix","stage":"design","issue":502,"branch":"b502"}'
got=""
for n in 501 502 503 504 505; do
    run "$n"
    got="$got $n:$RC:$(rj 'J(R("spec"))')"
done
check "終了の時刻の main に Issue の番号を持つ spec.json が無い Issue を spec 無しとし、switch-to-spec の印がある Issue を spec ありとする" \
    "$got" " 501:0:true 502:0:false 503:0:true 504:0:true 505:0:false"

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
