#!/bin/bash
# =====================================================================
# メモリを読み、確かめてから消すスクリプト(memory-files.pl)と、前の点検を片付けるスクリプト(old-inspection-cleanup.pl)のテスト
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
# prune-index と delete
# ---------------------------------------------------------------------

case_prune_index() {
    memfile a.md 'a'
    printf '%s\r\n' '# MEMORY' '' '- [A](a.md) — 残る' '- [消えた](gone.md) — 消える' '- リンクの無い行' '- [どちらか](gone2.md) と [A](a.md)' '- [外](https://example.com/z.md)' >"$MEMDIR/MEMORY.md"
    out=$(perl "$PL" prune-index)
    check "prune-index は指すファイルの無い行だけを消し、リンクの無い行を残す" \
        "$?|$(printf '%s' "$out" | pj 'join ";", @{$d->{removed}}')|$(sha "$MEMDIR/MEMORY.md")" \
        "0|- [消えた](gone.md) — 消える|$(printf '%s\r\n' '# MEMORY' '' '- [A](a.md) — 残る' '- リンクの無い行' '- [どちらか](gone2.md) と [A](a.md)' '- [外](https://example.com/z.md)' >"$CASE/want" && sha "$CASE/want")"
}
addcase prune_index

case_delete_same() {
    memfile a.md 'a'
    memfile b.md 'b'
    printf '%s\r\n' '# MEMORY' '- [A](a.md) — 消える' '- [B](b.md) — 残る' '- [A と B](./a.md#x) と [B](b.md)' >"$MEMDIR/MEMORY.md"
    printf '%s' '- 最後の行は改行で終わらない' >>"$MEMDIR/MEMORY.md"
    out=$(perl "$PL" delete "a.md=$(sha "$MEMDIR/a.md")")
    check "delete は SHA-256 が同じなら、メモリファイルとそのファイルへのリンクを持つ目次の行を消し、ほかの目次の行と改行の形を変えない" \
        "$?|$(printf '%s' "$out" | pj 'join ";", map { join ",", $_->{name}, $_->{result}, @{$_->{removed_index_lines}} } @{$d->{results}}')|$([ -e "$MEMDIR/a.md" ] && echo exists)|$(sha "$MEMDIR/MEMORY.md")" \
        "0|a.md,deleted,- [A](a.md) — 消える,- [A と B](./a.md#x) と [B](b.md)||$({ printf '%s\r\n' '# MEMORY' '- [B](b.md) — 残る'; printf '%s' '- 最後の行は改行で終わらない'; } >"$CASE/want" && sha "$CASE/want")"
}
addcase delete_same

case_delete_changed_missing() {
    memfile a.md 'a'
    printf '%s\n' '- [A](a.md)' '- [G](gone.md)' >"$MEMDIR/MEMORY.md"
    index_before=$(sha "$MEMDIR/MEMORY.md")
    other=$(printf 'x' | perl -MDigest::SHA=sha256_hex -e 'print sha256_hex(<STDIN>)')
    out=$(perl "$PL" delete "a.md=$other" "gone.md=$other")
    check "delete は SHA-256 が違えば changed、ファイルが無ければ missing を返し、どちらも何も消さない" \
        "$?|$(printf '%s' "$out" | pj 'join ";", map { "$_->{name},$_->{result}" } @{$d->{results}}')|$(cat "$MEMDIR/a.md")|$(sha "$MEMDIR/MEMORY.md")" \
        "0|a.md,changed;gone.md,missing|a|$index_before"
}
addcase delete_changed_missing

case_delete_invalid() {
    memfile MEMORY.md "$(printf '%s\n' '- [X](../x.md)' '- [B](a/b.md)')"
    mkdir -p "$MEMDIR/a"
    printf 'b' >"$MEMDIR/a/b.md"
    printf 'x' >"$MEMDIR/../x.md"
    out=$(perl "$PL" delete "../x.md=$(sha "$MEMDIR/../x.md")" "MEMORY.md=$(sha "$MEMDIR/MEMORY.md")" "a/b.md=$(sha "$MEMDIR/a/b.md")")
    check "delete は ../x.md、MEMORY.md、a/b.md を invalid にし、メモリのディレクトリの外のファイルを消さない" \
        "$?|$(printf '%s' "$out" | pj 'join ";", map { "$_->{name},$_->{result}" } @{$d->{results}}')|$(cat "$MEMDIR/../x.md" "$MEMDIR/a/b.md")|$(grep -c . "$MEMDIR/MEMORY.md")" \
        "0|../x.md,invalid;MEMORY.md,invalid;a/b.md,invalid|xb|2"
}
addcase delete_invalid

case_show_then_delete() {
    memfile a.md '前の中身'
    printf '%s\n' '- [A](a.md)' >"$MEMDIR/MEMORY.md"
    hash=$(perl "$PL" show a.md | pj '$d->{files}[0]{sha256}')
    printf '%s' '書き換えた中身' >"$MEMDIR/a.md"
    out=$(perl "$PL" delete "a.md=$hash")
    check "show のあとにメモリファイルを書き換えると、delete は changed を返して消さない" \
        "$?|$(printf '%s' "$out" | pj '$d->{results}[0]{result}')|$(cat "$MEMDIR/a.md")|$(cat "$MEMDIR/MEMORY.md")" \
        "0|changed|書き換えた中身|- [A](a.md)"
}
addcase show_then_delete

# ---------------------------------------------------------------------
# origins
# ---------------------------------------------------------------------

# 場所 <cwd> で動いた会話の記録のディレクトリを出す: logdir <cwd>
logdir() { printf '%s/.claude/projects/%s' "$HOME" "$(encname "$1")"; }

# 会話の記録に1行足す: logline <会話の記録のファイル> <cwd> <時刻> <種類> <値>...
#   dev <文>: 開発者が打った文の行
#   meta <文>: isMeta の行
#   use <道具の呼び出しの ID> <道具の名前> <file_path>: 道具を呼んだ行
#   result <道具の呼び出しの ID> <file_path> <toolUseResult.type>: 道具の結果の行
logline() {
    mkdir -p "$(dirname "$1")"
    perl -MJSON::PP -e '
        my ($file, $cwd, $at, $kind, @v) = @ARGV;
        utf8::decode($_) for $cwd, @v;
        (my $sid = $file) =~ s{\A.*/|\.jsonl\z}{}g;
        my %l = (cwd => $cwd, timestamp => $at, sessionId => $sid);
        if ($kind eq "dev" || $kind eq "meta") {
            %l = (%l, type => "user", message => { role => "user", content => $v[0] });
            $l{isMeta} = JSON::PP::true if $kind eq "meta";
        } elsif ($kind eq "use") {
            %l = (%l, type => "assistant", message => { role => "assistant",
                content => [{ type => "tool_use", id => $v[0], name => $v[1], input => { file_path => $v[2], content => "x" } }] });
        } elsif ($kind eq "result") {
            %l = (%l, type => "user", message => { role => "user", content => [{ type => "tool_result", tool_use_id => $v[0], content => "ok" }] },
                toolUseResult => { type => $v[2], filePath => $v[1] });
        } else {
            die "logline の種類が正しくない: $kind\n";
        }
        print JSON::PP->new->utf8->canonical->encode(\%l), "\n";
    ' "$@" >>"$1"
}

case_origins_found() {
    p="$MEMDIR/a.md"
    # 名前が <本体の名前>- で始まるほかのプロジェクトの記録の、それより早い書き込みは使わない
    o="$CASE/repo-other"
    logline "$(logdir "$o")/s0.jsonl" "$o" 2026-10-20T09:00:00Z dev 'ほかのプロジェクトの文'
    logline "$(logdir "$o")/s0.jsonl" "$o" 2026-10-20T09:01:00Z use t9 Write "$p"
    # worktree の会話の記録の書き込みを見つける
    w="$REPO/.claude/worktrees/w"
    f="$(logdir "$w")/s1.jsonl"
    logline "$f" "$w" 2026-10-20T10:00:00Z dev '前の文'
    logline "$f" "$w" 2026-10-20T10:01:00Z result t0 "$REPO/x.txt" create
    logline "$f" "$w" 2026-10-20T10:02:00Z meta 'メタの文'
    logline "$f" "$o" 2026-10-20T10:02:30Z dev 'ほかのプロジェクトの別の文'
    logline "$f" "$w" 2026-10-20T10:03:00Z dev '覚えて'
    logline "$f" "$w" 2026-10-20T10:04:00Z use t1 Write "$p"
    logline "$f" "$w" 2026-10-20T10:05:00Z result t1 "$p" create
    logline "$f" "$w" 2026-10-20T10:06:00Z dev 'あとの文'
    # それよりあとの会話の書き込みは選ばない
    logline "$(logdir "$REPO")/s2.jsonl" "$REPO" 2026-10-21T10:00:00Z use t2 Edit "$p"
    out=$(perl "$PL" origins a.md)
    check "最も早い書き込みが Write なら、その会話の、書き込みまでの開発者の文だけを返す" \
        "$?|$(printf '%s' "$out" | pj 'my $o = $d->{origins}[0]; join "|", $o->{name}, $o->{found} ? 1 : 0, $o->{session}, $o->{written_on}, $o->{truncated} ? 1 : 0, map { "$_->{at}=$_->{text}" } @{ $o->{utterances} }')" \
        "0|a.md|1|s1|2026-10-20|0|2026-10-20T10:00:00Z=前の文|2026-10-20T10:03:00Z=覚えて"
}
addcase origins_found

case_origins_windows_path() {
    # Git Bash の HOME は /c/… の形で、記録の file_path は C:\… の形である
    # 一時のディレクトリは Git Bash では /tmp/… の形で返るので、C:/… の形から /c/… の形を作る
    export HOME="$(printf '%s' "$HOME" | perl -pe 's{\A([A-Za-z]):}{"/" . lc $1}e')"
    win=$(printf '%s' "$MEMDIR/a.md" | perl -pe 's{/}{\\}g; s{\A\\([A-Za-z])\\}{\U$1\E:\\}; s{\A([a-z]):}{\U$1:}')
    f="$(logdir "$REPO")/s1.jsonl"
    logline "$f" "$REPO" 2026-10-20T10:00:00Z dev '覚えて'
    logline "$f" "$REPO" 2026-10-20T10:01:00Z use t1 Write "$win"
    out=$(perl "$PL" origins a.md)
    check 'Windows の C:\…\memory\a.md の形の file_path を、a.md の書き込みとして見つける' \
        "$?|$(printf '%s' "$out" | pj 'my $o = $d->{origins}[0]; join "|", $o->{found} ? 1 : 0, map { $_->{text} } @{ $o->{utterances} }')" \
        "0|1|覚えて"
}
addcase origins_windows_path

case_origins_truncate() {
    f="$(logdir "$REPO")/s1.jsonl"
    # 1つの文は JSON にすると1,034バイトなので、6,000バイトまでに収まるのは書き込みに近い5つである
    long=$(perl -e 'print "あ" x 330')
    for i in 01 02 03 04 05 06 07 08 09 10; do
        logline "$f" "$REPO" "2026-10-20T10:00:${i}Z" dev "文$i$long"
    done
    logline "$f" "$REPO" 2026-10-20T10:01:00Z use t1 Write "$MEMDIR/c.md"
    out=$(perl "$PL" origins c.md)
    check "utterances を名前1つあたり6,000バイトまでにし、古い文から外して truncated を真にする" \
        "$?|$(printf '%s' "$out" | pj 'my $o = $d->{origins}[0]; my $u = $o->{utterances}; join "|", $o->{truncated} ? 1 : 0, scalar @$u, length(JSON::PP->new->utf8->canonical->encode($u)) <= 6000 ? "fits" : "over", substr($u->[0]{text}, 0, 3), substr($u->[-1]{text}, 0, 3)')" \
        "0|1|5|fits|文06|文10"
}
addcase origins_truncate

case_origins_too_many() {
    out=$(perl "$PL" origins a.md b.md c.md d.md e.md 2>/dev/null)
    rc=$?
    four=$(perl "$PL" origins a.md b.md c.md d.md | pj 'scalar @{$d->{origins}}')
    check "origins は名前を5つ以上渡すと 2 で終わり、何も出さない" "$rc|[$out]|$four" "2|[]|4"
}
addcase origins_too_many

case_origins_edit_nowrite() {
    f="$(logdir "$REPO")/s1.jsonl"
    logline "$f" "$REPO" 2026-10-20T10:00:00Z dev '直して'
    logline "$f" "$REPO" 2026-10-20T10:01:00Z use t1 Edit "$MEMDIR/d.md"
    logline "$(logdir "$REPO")/s2.jsonl" "$REPO" 2026-10-21T10:00:00Z use t2 Write "$MEMDIR/d.md"
    logline "$(logdir "$REPO")/s2.jsonl" "$REPO" 2026-10-21T10:01:00Z result t2 "$MEMDIR/d.md" create
    out=$(perl "$PL" origins d.md e.md)
    check "最も早い書き込みが Edit なら first-write-not-kept を、書き込みが無ければ no-write を返す" \
        "$?|$(printf '%s' "$out" | pj 'join "|", map { join ",", $_->{name}, $_->{found} ? 1 : 0, $_->{reason} } @{ $d->{origins} }')" \
        "0|d.md,0,first-write-not-kept|e.md,0,no-write"
}
addcase origins_edit_nowrite

case_origins_update() {
    f="$(logdir "$REPO")/s1.jsonl"
    logline "$f" "$REPO" 2026-10-20T10:00:00Z dev '書き直して'
    logline "$f" "$REPO" 2026-10-20T10:01:00Z use t1 Write "$MEMDIR/f.md"
    logline "$f" "$REPO" 2026-10-20T10:02:00Z result t1 "$MEMDIR/f.md" update
    out=$(perl "$PL" origins f.md)
    check "最も早い書き込みが、結果が update の Write なら first-write-not-kept を返す" \
        "$?|$(printf '%s' "$out" | pj 'my $o = $d->{origins}[0]; join ",", $o->{found} ? 1 : 0, $o->{reason}')" \
        "0|0,first-write-not-kept"
}
addcase origins_update

case_origins_invalid() {
    # メモリのディレクトリの外の場所への書き込みがあっても、決まりに合わない名前は探さない
    f="$(logdir "$REPO")/s1.jsonl"
    logline "$f" "$REPO" 2026-10-20T10:00:00Z dev '書いて'
    logline "$f" "$REPO" 2026-10-20T10:01:00Z use t1 Write "$MEMDIR/../x.md"
    logline "$f" "$REPO" 2026-10-20T10:02:00Z use t2 Write "$MEMDIR/MEMORY.md"
    out=$(perl "$PL" origins ../x.md MEMORY.md a/b.md)
    check "origins は決まりに合わない名前を探さず、reason に invalid を書く" \
        "$?|$(printf '%s' "$out" | pj 'join "|", map { join ",", $_->{name}, $_->{found} ? 1 : 0, $_->{reason} } @{ $d->{origins} }')" \
        "0|../x.md,0,invalid|MEMORY.md,0,invalid|a/b.md,0,invalid"
}
addcase origins_invalid

# ---------------------------------------------------------------------
# old-inspection-cleanup.pl
# ---------------------------------------------------------------------

# 偽の powershell.exe・launchctl・crontab を $CASE/bin に置く。受けた引数を $CASE/fake/<名前>.calls に JSON の1行ずつ書き残す。
#   powershell.exe: $CASE/fake/powershell.exe.out を出し、$CASE/fake/powershell.exe.err があれば標準エラーに出して 1 で終わる
#   launchctl:      print は $CASE/fake/launchctl.loaded があれば 0 で終わり、bootout はそのファイルを消す
#   crontab:        -l は $CASE/fake/crontab.table を出し、無ければ「no crontab」を出して 1 で終わる。- は標準入力をそのファイルに書く
osfakes() {
    local n
    mkdir -p "$CASE/bin" "$CASE/fake"
    for n in powershell.exe launchctl crontab; do
        cat >"$CASE/bin/$n" <<'FAKE'
#!/bin/bash
f="$KP_TEST_FAKE/${0##*/}"
perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode([@ARGV]), "\n"' -- "$@" >>"$f.calls"
case "${0##*/}:${1:-}" in
powershell.exe:*)
    cat "$f.out" 2>/dev/null
    if [ -f "$f.err" ]; then cat "$f.err" >&2; exit 1; fi
    ;;
launchctl:print) [ -f "$f.loaded" ] ;;
launchctl:bootout) rm -f "$f.loaded" ;;
crontab:-l)
    if [ -f "$f.table" ]; then cat "$f.table"; else echo "no crontab for test" >&2; exit 1; fi
    ;;
crontab:-) cat >"$f.table" ;;
esac
FAKE
        chmod +x "$CASE/bin/$n"
    done
    # PATH は : で区切るので、Windows の C:/… の形でなく、pwd の形の場所を入れる
    FAKEBIN=$(cd "$CASE/bin" && pwd)
    CL="$(dirname "$PL")/old-inspection-cleanup.pl"
    STATE="$REPO/.git/keirekipro-memory-inspection"
    ID8=$(git rev-parse --path-format=absolute --git-common-dir | perl -MDigest::SHA=sha256_hex -ne 'chomp; print substr(sha256_hex($_), 0, 8)')
}

# 偽のコマンドを PATH の先頭に置き、OS を替えて old-inspection-cleanup.pl を動かす: cleanup <KP_MEMORY_CLEANUP_OS の値> [引数]...
cleanup() {
    local os=$1
    shift
    PATH="$FAKEBIN:$PATH" KP_TEST_FAKE="$CASE/fake" KP_MEMORY_CLEANUP_OS=$os perl "$CL" "$@"
}

# 状態の場所に、前の点検の報告と記録の代わりのファイルを置く
oldstate() { mkdir -p "$STATE/runs/r1" && printf 'x' >"$STATE/report.md" && printf 'y' >"$STATE/runs/r1/log.jsonl"; }

# 状態の場所があれば there、無ければ gone を出す
statemark() { if [ -e "$STATE" ]; then printf there; else printf gone; fi; }

# 出力の JSON から、schedule・state・manual_command を | でつないで出す
cleanup_fields() { pj 'join "|", @$d{qw(schedule state manual_command)}'; }

case_cleanup_windows() {
    osfakes
    oldstate
    printf 'removed\r\n' >"$CASE/fake/powershell.exe.out"
    out=$(cleanup msys)
    rc=$?
    printf 'absent\r\n' >"$CASE/fake/powershell.exe.out"
    again=$(cleanup msys)
    check "3つの OS それぞれで、予定があれば外して removed を、無ければ absent を返す(Windows)" \
        "$rc|$(printf '%s' "$out" | cleanup_fields)|$(statemark)|$(printf '%s' "$again" | cleanup_fields)" \
        "0|removed|removed||gone|absent|absent|"
    check "Windows では、予定の名前を入れた命令の文を powershell.exe に -EncodedCommand で渡す" \
        "$(head -1 "$CASE/fake/powershell.exe.calls" | perl -MJSON::PP -MMIME::Base64 -MEncode=decode -ne '
            my @a = @{ JSON::PP->new->decode($_) };
            my $s = decode("UTF-16LE", decode_base64($a[3]));
            print join ",", @a[0 .. 2], $s =~ /\QUnregister-ScheduledTask -TaskName '"'"'KeirekiPro memory inspection '"$ID8"''"'"' -Confirm:$false\E/ ? "unregister" : "none"')" \
        "-NoProfile,-NonInteractive,-EncodedCommand,unregister"
}
addcase cleanup_windows

case_cleanup_macos() {
    osfakes
    uid=$(perl -e 'print $<')
    label="com.keirekipro.memory-inspection.$ID8"
    mkdir -p "$HOME/Library/LaunchAgents"
    printf 'p' >"$HOME/Library/LaunchAgents/$label.plist"
    printf 'other' >"$HOME/Library/LaunchAgents/com.example.other.plist"
    : >"$CASE/fake/launchctl.loaded"
    out=$(cleanup darwin)
    rc=$?
    first=$(perl -MJSON::PP -ne 'print join(" ", @{ JSON::PP->new->decode($_) }), ";"' "$CASE/fake/launchctl.calls")
    again=$(cleanup darwin)
    printf 'p' >"$HOME/Library/LaunchAgents/$label.plist"
    plist_only=$(cleanup darwin)
    check "3つの OS それぞれで、予定があれば外して removed を、無ければ absent を返す(macOS)" \
        "$rc|$(printf '%s' "$out" | cleanup_fields)|$(printf '%s' "$again" | cleanup_fields)|$(printf '%s' "$plist_only" | cleanup_fields)" \
        "0|removed|absent||absent|absent||removed|absent|"
    check "macOS では、launchctl bootout で予定を外し、印の付いた plist だけを消す" \
        "$first|$(ls "$HOME/Library/LaunchAgents")" \
        "print gui/$uid/$label;bootout gui/$uid/$label;|com.example.other.plist"
}
addcase cleanup_macos

case_cleanup_linux() {
    osfakes
    printf '%s\n' "0 9 * * 1 /bin/bash '/x/memory-inspect.sh' run >> '/x/run.log' 2>&1 # keirekipro-memory-inspection $ID8" \
        '# ほかの予定' '5 4 * * *  echo hi  ' '0 9 * * 1 /bin/bash /y run # keirekipro-memory-inspection deadbeef' >"$CASE/fake/crontab.table"
    out=$(cleanup linux)
    rc=$?
    table=$(cat "$CASE/fake/crontab.table")
    again=$(cleanup linux)
    writes=$(grep -c '^\["-"\]' "$CASE/fake/crontab.calls")
    rm -f "$CASE/fake/crontab.table"
    none=$(cleanup linux)
    check "3つの OS それぞれで、予定があれば外して removed を、無ければ absent を返す。Linux では印の付いた行だけを消し、ほかの行を変えない" \
        "$rc|$(printf '%s' "$out" | cleanup_fields)|$table|$(printf '%s' "$again" | cleanup_fields)|$writes|$(printf '%s' "$none" | cleanup_fields)" \
        "0|removed|absent||# ほかの予定
5 4 * * *  echo hi  
0 9 * * 1 /bin/bash /y run # keirekipro-memory-inspection deadbeef|absent|absent||1|absent|absent|"
}
addcase cleanup_linux

case_cleanup_state_only() {
    osfakes
    oldstate
    out=$(cleanup linux)
    rc=$?
    gone=$(statemark)
    again=$(cleanup linux)
    check "予定が無くても、状態の場所があれば消して state を removed にする" \
        "$rc|$(printf '%s' "$out" | pj 'join "|", @$d{qw(schedule state state_error)}, $d->{state_path}')|$gone|$(printf '%s' "$again" | cleanup_fields)" \
        "0|absent|removed||$STATE|gone|absent|absent|"
}
addcase cleanup_state_only

case_cleanup_ps_fail() {
    osfakes
    oldstate
    printf 'アクセスが拒否されました。\r\n' >"$CASE/fake/powershell.exe.err"
    out=$(cleanup MSWin32)
    check "偽の powershell.exe が失敗したとき、schedule を failed にし、manual_command に予定の名前の入ったコマンドを入れ、状態の場所は消す" \
        "$?|$(printf '%s' "$out" | cleanup_fields)|$(printf '%s' "$out" | pj 'my $e = $d->{schedule_error}; utf8::encode($e); $e =~ /アクセスが拒否されました/ ? "said" : $d->{schedule_error}')|$(statemark)" \
        "0|failed|removed|Unregister-ScheduledTask -TaskName 'KeirekiPro memory inspection $ID8' -Confirm:\$false|said|gone"
}
addcase cleanup_ps_fail

case_cleanup_errors() {
    osfakes
    args=$(cleanup linux x 2>/dev/null; printf '|%s' "$?")
    cd "$CASE/home" || exit 1
    nogit=$(GIT_CEILING_DIRECTORIES="$CASE" cleanup linux 2>"$CASE/err"; printf '|%s' "$?")
    check "old-inspection-cleanup.pl は引数を受けると 2 で、git の共通ディレクトリを求められないと 1 で終わり、何も出さない" \
        "$args|$nogit|$(grep -c '共通ディレクトリを求められなかった' "$CASE/err")" "|2||1|1"
}
addcase cleanup_errors

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
