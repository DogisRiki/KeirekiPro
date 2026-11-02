#!/bin/bash
# =====================================================================
# メモリを読み、確かめてから消すスクリプト(memory-files.pl)のテスト
#
# 実行: bash .claude/scripts/memory/tests/test-memory-files.sh
# テストの場合ごとに、一時のディレクトリ(newcase)に、偽の git のリポジトリと、偽のホームと、偽のメモリのディレクトリを作る。
# HOME を偽のホームに替え、CLAUDE_CONFIG_DIR を外し、所有者の本物のメモリと会話の記録に触れない。
# 前提: bash 3.2 以上・perl(JSON::PP・Digest::SHA)・git。macOS で動く書き方だけを使う
#
# 場合を選んで流す: KP_TEST_CASE='show_basic list_order' bash .claude/scripts/memory/tests/test-memory-files.sh
# 空白で区切った名前の場合だけを流す。どの場合にも合わない名前があれば、何も流さずに終了コード 2 で終わる
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PL="$(cd "$HERE/.." && pwd)/memory-files.pl"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# git が返すパス(Windows では C:/...、ほかではシンボリックリンクを解いた形)と同じ形で作る。
# macOS の mktemp が返す /var/folders/... の /var は、/private/var へのシンボリックリンクである
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd -P; })

# 本物の会話の記録の置き場所を使わないように、Claude Code の設定の場所を外す
unset CLAUDE_CONFIG_DIR

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }

# 場所の英数字でない文字を1文字ずつ - に替えた名前を出す。Claude Code がプロジェクトのディレクトリの名前を作る決まりである
encname() { printf '%s' "$1" | perl -CS -pe 's/[^A-Za-z0-9]/-/g'; }

# 標準入力の JSON を $d に読み、perl の式を評価した値を出す: pj '<式>'
pj() {
    perl -MJSON::PP -e '
        my $d = JSON::PP->new->utf8->decode(do { local $/; <STDIN> });
        binmode STDOUT, ":encoding(UTF-8)";
        my $v = eval $ARGV[0];
        die $@ if $@;
        print defined $v ? $v : "<undef>";
    ' "$1"
}

# ファイルのバイトの列の SHA-256 を出す
sha() { perl -MDigest::SHA=sha256_hex -e 'open my $f, "<:raw", $ARGV[0] or die; local $/; print sha256_hex(<$f>)' "$1"; }

# 場合ごとの一時のディレクトリを作り、偽の git のリポジトリ REPO と、偽のホーム、偽のメモリのディレクトリ MEMDIR を用意する。
# MEMDIR は作らない。作業フォルダは REPO に移る
CASE_NO=0
newcase() {
    CASE_NO=$((CASE_NO + 1))
    CASE="$WORK/c$CASE_NO"
    REPO="$CASE/repo"
    mkdir -p "$REPO" "$CASE/home"
    git init -q "$REPO"
    git -c user.name=test -c user.email=test@example.com -C "$REPO" commit -q --allow-empty -m init
    export HOME="$CASE/home"
    MEMDIR="$HOME/.claude/projects/$(encname "$REPO")/memory"
    cd "$REPO" || exit 1
}

# メモリのディレクトリにファイルを書く: memfile <名前> <中身>
memfile() { mkdir -p "$MEMDIR" && printf '%s' "$2" >"$MEMDIR/$1"; }

CASES=''
addcase() { CASES="$CASES $1"; }

# ---------------------------------------------------------------------
# list
# ---------------------------------------------------------------------

case_list_order() {
    memfile b.md 'b'
    memfile a.md 'a'
    memfile z.md 'z'
    memfile y.md 'y'
    memfile c.md 'c'
    memfile .hidden.md 'h'
    memfile note.txt 'n'
    memfile MEMORY.md '# MEMORY

- [B](b.md) — 説明
- [A](./a.md#節) — 説明
- [B の2つ目](b.md) — もう1行
- [外](https://example.com/x.md)
'
    touch -t 202610200900 "$MEMDIR/a.md"
    out=$(perl "$PL" list)
    check "list は目次の行の順に並べ、行の無いメモリファイルを名前の順にあとに並べる" \
        "$?|$(printf '%s' "$out" | pj 'join ",", map { $_->{name} } @{$d->{files}}')" "0|b.md,a.md,c.md,y.md,z.md"
    check "list はメモリファイルごとに、そのファイルへのリンクを持つ目次の行の番号と文を出す" \
        "$(printf '%s' "$out" | pj 'join ";", map { my $f = $_; join ",", $f->{name}, map { "$_->{no}:$_->{text}" } @{$f->{index_lines}} } @{$d->{files}}[0,1,2]')" \
        "b.md,3:- [B](b.md) — 説明,5:- [B の2つ目](b.md) — もう1行;a.md,4:- [A](./a.md#節) — 説明;c.md"
    check "list はメモリのディレクトリと、目次があることと、更新した日付を出す" \
        "$(printf '%s' "$out" | pj 'join "|", $d->{memory_dir}, $d->{index_exists} ? 1 : 0, $d->{files}[1]{modified_on}, scalar @{$d->{dangling}}')" \
        "$MEMDIR|1|2026-10-20|0"
}
addcase list_order

case_list_dangling() {
    memfile a.md 'a'
    printf '%s\r\n' '# MEMORY' '- [A](a.md)' '- [消えた](gone.md) — 説明' '- [どちらか](gone2.md) と [A](a.md)' '- リンクの無い行' >"$MEMDIR/MEMORY.md"
    out=$(perl "$PL" list)
    check "list は指すファイルの無い目次の行を dangling に出す" \
        "$?|$(printf '%s' "$out" | pj 'join ";", map { "$_->{no}:$_->{text}:" . join ",", @{$_->{files}} } @{$d->{dangling}}')" \
        "0|3:- [消えた](gone.md) — 説明:gone.md"
}
addcase list_dangling

case_list_no_dir() {
    out=$(perl "$PL" list)
    check "list はメモリのディレクトリが無いとき、files と dangling を空にして 0 で終わる" \
        "$?|$(printf '%s' "$out" | pj 'join "|", scalar @{$d->{files}}, scalar @{$d->{dangling}}, $d->{index_exists} ? 1 : 0')" "0|0|0|0"
}
addcase list_no_dir

case_worktree() {
    memfile a.md 'a'
    git -C "$REPO" worktree add -q "$CASE/wt" 2>/dev/null
    mkdir -p "$CASE/wt/sub"
    cd "$CASE/wt/sub" || exit 1
    out=$(perl "$PL" list)
    check "worktree の中で打っても、本体の作業フォルダの場所から求めたメモリのディレクトリを読む" \
        "$?|$(printf '%s' "$out" | pj '$d->{memory_dir} . "|" . join ",", map { $_->{name} } @{$d->{files}}')" "0|$MEMDIR|a.md"
}
addcase worktree

# ---------------------------------------------------------------------
# show
# ---------------------------------------------------------------------

case_show_basic() {
    memfile 'あ.md' "$(printf '一行目\r\n二行目')"
    memfile b.md 'b'
    mkdir -p "$CASE/home/.claude/projects"
    printf 'outside' >"$CASE/home/.claude/projects/x.md"
    out=$(perl "$PL" show 'あ.md' gone.md ../x.md MEMORY.md)
    check "show は全文と SHA-256 を出し、無い名前を missing、決まりに合わない名前を invalid にする" \
        "$?|$(printf '%s' "$out" | pj 'join ";", map { join ",", map { defined $_ ? $_ : "-" } @$_{qw(name sha256 content result)}, exists $_->{decode_error} ? ($_->{decode_error} ? 1 : 0) : "-" } @{$d->{files}}')" \
        "0|あ.md,$(sha "$MEMDIR/あ.md"),$(printf '一行目\r\n二行目'),-,0;gone.md,-,-,missing,-;../x.md,-,-,invalid,-;MEMORY.md,-,-,invalid,-"
}
addcase show_basic

case_show_decode() {
    mkdir -p "$MEMDIR"
    printf 'ok\377\376' >"$MEMDIR/bad.md"
    out=$(perl "$PL" show bad.md)
    check "show は UTF-8 として読めないファイルの content を空にし、decode_error を真にする" \
        "$?|$(printf '%s' "$out" | pj 'my $f = $d->{files}[0]; join ",", $f->{name}, $f->{sha256}, "[$f->{content}]", $f->{decode_error} ? 1 : 0')" \
        "0|bad.md,$(sha "$MEMDIR/bad.md"),[],1"
}
addcase show_decode

case_show_too_many() {
    memfile a.md 'a'
    out=$(perl "$PL" show a.md a.md a.md a.md a.md 2>/dev/null)
    rc=$?
    four=$(perl "$PL" show a.md a.md a.md a.md | pj 'scalar @{$d->{files}}')
    check "show は名前を5つ以上渡すと 2 で終わり、何も出さない" "$rc|[$out]|$four" "2|[]|4"
}
addcase show_too_many

# ---------------------------------------------------------------------
# 選んだ場合を流す
# ---------------------------------------------------------------------

selected=$CASES
if [ -n "${KP_TEST_CASE:-}" ]; then
    for want in $KP_TEST_CASE; do
        case " $CASES " in
        *" $want "*) ;;
        *)
            echo "どの場合にも合わない名前: $want" >&2
            exit 2
            ;;
        esac
    done
    selected=$KP_TEST_CASE
fi
for name in $selected; do
    newcase
    "case_$name"
done

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
