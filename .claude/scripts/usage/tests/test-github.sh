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
    perl "$GITHUB" "$@" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"
    RC=$?
    OUT=$(cat "$TMP_ROOT/out")
    ERR=$(cat "$TMP_ROOT/err")
}
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

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
