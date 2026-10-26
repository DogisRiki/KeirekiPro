#!/bin/bash
# =====================================================================
# usage.sh(集計の入口のコマンド)のテスト
#
# 実行: bash .claude/scripts/usage/tests/test-usage.sh
# 一時フォルダに git のリポジトリを作り、origin/main にデータのファイル(usage-config.json)を足したコミットを置く。
# 偽の gh(fixtures/fake-gh.sh)を一時フォルダに gh の名前で写し、その一時フォルダを PATH の先頭に置く。
# 偽の gh は、一時フォルダの db.json を GitHub の代わりにする。本物の GitHub は読まず、書かない。
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
# props(<番号>, <行>...) は直す案を持つ集計のコメントの本文である
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
        my $db = { '"$1"' };
        open my $fh, ">", "$ENV{FAKE_GH_DIR}/db.json" or die $!;
        print $fh JSON::PP->new->canonical->encode($db);
    ' || ng "偽の GitHub を用意できない"
}
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

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
