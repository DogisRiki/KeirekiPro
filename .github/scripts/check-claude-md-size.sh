#!/usr/bin/env bash
# =====================================================================
# 読み込まれる文書の量の検査(guardrails CI の claude-md-size から実行)
#
# リポジトリの中で、どの会話の始めにも読み込まれる文書を集め、バイトの数の
# 合計を上限と比べる。上限の値はこのスクリプトに持たせず、環境変数で受け取る。
# PR の差分は見ない。
#
# 測る文書:
#   - ルートの CLAUDE.md(必ず測る。無ければ判定不能)
#   - あれば測る: .claude/CLAUDE.md、CLAUDE.local.md、AGENTS.md、
#     .claude/AGENTS.md、.claude/rules/ の下の .md(下のフォルダを含む)のうち、
#     先頭の前書き(--- の行で始まり次の --- の行で終わる部分)に paths: の行を
#     持たないもの
#   - 上の文書の中の、行の頭か空白のあとに置かれた @<道> が読み込む文書。
#     道は読み込みを書いた文書のフォルダから解き、4段まで辿る(5段目は辿らない)。
#     コードの囲み(``` か ~~~ で始まる行から閉じる行まで)とコードの区切り
#     (同じ数のバッククォートで囲んだ部分)の中の @ は読み込みとみなさない。
#     道は、バックスラッシュを置いた空白を含み、ほかの空白で終わる。
#     同じ文書は1回だけ数える
#   量はファイルのバイトの数をそのまま数える(HTML コメントも除かない)。
#
# 終了コード:
#   0 = 合計が上限以下
#   1 = 合計が上限を超える(文書の一覧と、Claude に向けた文を出す)
#   2 = 判定不能。上限が無いか1以上の整数でない、ルートの CLAUDE.md が無いか
#       読めない、測る文書が読めない、読み込みの先が無い・リポジトリの外を
#       指す・~ か絶対の道で書かれている。ガードしていないコマンドの想定外の
#       失敗もすべて 2 に倒す。何も測らずに 0 で終わることは無い
#
# 環境変数: CLAUDE_MD_SIZE_LIMIT(必須。上限のバイトの数)
#           GITHUB_STEP_SUMMARY(あれば同じ内容を表にして書く)
# テスト: .github/scripts/tests/test-check-claude-md-size.sh
# 使い方: check-claude-md-size.sh [リポジトリのルート](省略時は今のフォルダ)
# =====================================================================
set -Eeuo pipefail
# ガードしていないコマンドの失敗は、合否(0 / 1)ではなく判定不能(2)にする。
# -E で関数・コマンド置換の中の失敗にも適用する。
trap 'exit 2' ERR

# Summary があれば書き、無ければ捨てる
to_summary() {
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        cat >>"$GITHUB_STEP_SUMMARY"
    else
        cat >/dev/null
    fi
}

# 判定不能の報告と終了。引数の各行を ::error:: の行として出す
undecidable() {
    local line
    {
        echo "### :warning: 読み込まれる文書の量を測れませんでした(判定不能)"
        echo ""
        for line in "$@"; do
            echo "- ${line}"
        done
        echo ""
    } | to_summary
    for line in "$@"; do
        echo "::error::[読み込まれる文書の量] ${line}"
    done
    exit 2
}

if [ "$#" -gt 1 ]; then
    undecidable "引数はリポジトリのルートの1個までです(${#} 個渡されました)。"
fi
ROOT="${1:-.}"
if [ ! -d "$ROOT" ]; then
    undecidable "リポジトリのルートのフォルダが見つかりません: ${ROOT}"
fi

if [ -z "${CLAUDE_MD_SIZE_LIMIT+set}" ]; then
    undecidable "上限の環境変数 CLAUDE_MD_SIZE_LIMIT がありません。"
fi
LIMIT="$CLAUDE_MD_SIZE_LIMIT"
# 合計との比べは算術展開で行う。先頭0は8進数として扱われ、桁数が多すぎると
# 64ビットを溢れて折り返すため、先頭0なし・18桁までの1以上の整数に限る
if ! [[ "$LIMIT" =~ ^[1-9][0-9]{0,17}$ ]]; then
    undecidable "上限の環境変数 CLAUDE_MD_SIZE_LIMIT は1以上の整数(先頭0なし・18桁まで)で指定してください: '${LIMIT}'"
fi

# 文書を集める処理は perl で行う(bash と perl の標準の部品だけを使い、jq に頼らない)。
# 出力は1行に1件で、「OK<TAB><バイトの数><TAB><道>」か「ERR<TAB><理由>」。
# ERR を出したときは終了コード2で終わる。
if ! LISTING=$(
    perl - "$ROOT" <<'PERL'
use strict;
use warnings;
use Cwd qw(realpath);
use File::Find ();

my $MAX_HOPS = 4;
my $root_arg = shift @ARGV;
my $root = realpath($root_arg);

sub fail {
    print "ERR\t$_\n" for @_;
    exit 2;
}

fail("リポジトリのルートのフォルダが見つかりません: $root_arg")
    unless defined $root && -d $root;
$root =~ s{/+\z}{} unless $root eq '/';

sub rel {
    my ($abs) = @_;
    return substr($abs, length($root) + 1);
}

sub inside {
    my ($abs) = @_;
    return index($abs, "$root/") == 0;
}

sub slurp {
    my ($abs, $shown) = @_;
    open(my $fh, '<:raw', $abs) or fail("測る文書が読めません: $shown");
    local $/;
    my $text = <$fh>;
    close($fh);
    return defined $text ? $text : '';
}

# 測る文書が読める普通のファイルかを確かめ、実体の道を返す
sub readable_doc {
    my ($abs, $shown) = @_;
    fail("測る文書が読めません(普通のファイルでないか、読む権限がありません): $shown")
        unless -f $abs && -r $abs;
    my $real = realpath($abs);
    fail("測る文書が読めません: $shown") unless defined $real;
    fail("測る文書がリポジトリの外を指しています: $shown") unless inside($real);
    return $real;
}

# 前書きに paths: の行を持つか
sub has_paths_frontmatter {
    my ($text) = @_;
    return 0 unless $text =~ /\A---[ \t]*\r?\n/;
    my @lines = split /\n/, $text, -1;
    shift @lines;
    for my $line (@lines) {
        $line =~ s/\r\z//;
        return 0 if $line =~ /\A---[ \t]*\z/;
        return 1 if $line =~ /\Apaths[ \t]*:/;
    }
    # 閉じる --- の無いものは前書きとみなさない
    return 0;
}

# 段落の中のコードの区切りを、空白でない1文字に置き換えてから @<道> を拾う。
# 空白に置き換えると、区切りのすぐあとの @ が「空白のあと」に見えてしまうため
sub imports_in_paragraph {
    my ($s) = @_;
    my $o = '';
    my $i = 0;
    my $n = length $s;
    while ($i < $n) {
        my $ch = substr($s, $i, 1);
        if ($ch eq '`') {
            my ($run) = substr($s, $i) =~ /\A(`+)/;
            my $k = length $run;
            my $rest = substr($s, $i + $k);
            my $close = '(?<!`)`{' . $k . '}(?!`)';
            if ($rest =~ /$close/) {
                $o .= "\x01";
                $i += $k + $+[0];
                next;
            }
            $o .= $run;
            $i += $k;
            next;
        }
        $o .= $ch;
        $i++;
    }
    my @found;
    while ($o =~ /(?:\A|(?<=\s))\@((?:\\ |[^\s\x01])+)/g) {
        push @found, $1;
    }
    return @found;
}

# 文書の中の @<道> を、コードの囲みの外から順に拾う
sub imports_of {
    my ($text) = @_;
    my (@found, @para, $fence_re);
    my $flush = sub {
        if (@para) {
            push @found, imports_in_paragraph(join("\n", @para));
            @para = ();
        }
    };
    for my $line (split /\n/, $text, -1) {
        $line =~ s/\r\z//;
        if (defined $fence_re) {
            undef $fence_re if $line =~ $fence_re;
            next;
        }
        if ($line =~ /\A {0,3}(`{3,}|~{3,})/) {
            $flush->();
            my $c = quotemeta(substr($1, 0, 1));
            my $len = length $1;
            $fence_re = qr/\A {0,3}(?:$c){$len,}[ \t]*\z/;
            next;
        }
        if ($line =~ /\A\s*\z/) {
            $flush->();
            next;
        }
        push @para, $line;
    }
    $flush->();
    return @found;
}

# 読み込みの道を解き、実体の道を返す
sub resolve_import {
    my ($raw, $importer_real) = @_;
    my $from = rel($importer_real);
    my $p = $raw;
    $p =~ s/\\ / /g;
    fail("読み込みの先が ~ の道で書かれています: \@$raw($from の中)")
        if $p =~ /\A~/;
    fail("読み込みの先が絶対の道で書かれています: \@$raw($from の中)")
        if $p =~ m{\A[/\\]} || $p =~ /\A[A-Za-z]:/;
    my @stack = split m{/}, $from;
    pop @stack;
    for my $seg (split m{/}, $p) {
        next if $seg eq '' || $seg eq '.';
        if ($seg eq '..') {
            fail("読み込みの先がリポジトリの外を指しています: \@$raw($from の中)")
                unless @stack;
            pop @stack;
            next;
        }
        push @stack, $seg;
    }
    my $cand = join('/', $root, @stack);
    unless (-e $cand) {
        fail("読み込みの先がありません: \@$raw($from の中)",
            "文中で \@ で始まる語を読み込みにしたくないときは、その語をバッククォートで囲んでください。");
    }
    my $real = realpath($cand);
    fail("読み込みの先がリポジトリの外を指しています: \@$raw($from の中)")
        unless defined $real && inside($real);
    fail("読み込みの先が読めません(普通のファイルでないか、読む権限がありません): \@$raw($from の中)",
        "文中で \@ で始まる語を読み込みにしたくないときは、その語をバッククォートで囲んでください。")
        unless -f $real && -r $real;
    return $real;
}

# --- 会話の始めに読み込まれる文書を集める ----------------------------------
my @start;
my $claude_md = "$root/CLAUDE.md";
fail("ルートの CLAUDE.md が無いか読めません。") unless -f $claude_md && -r $claude_md;
push @start, readable_doc($claude_md, 'CLAUDE.md');

for my $name ('.claude/CLAUDE.md', 'CLAUDE.local.md', 'AGENTS.md', '.claude/AGENTS.md') {
    my $abs = "$root/$name";
    next unless -e $abs || -l $abs;
    push @start, readable_doc($abs, $name);
}

my $rules_dir = "$root/.claude/rules";
if (-d $rules_dir) {
    my @rules;
    File::Find::find({
        no_chdir => 1,
        wanted   => sub { push @rules, $File::Find::name if /\.md\z/ },
    }, $rules_dir);
    for my $abs (sort @rules) {
        my $shown = substr($abs, length($root) + 1);
        my $real = readable_doc($abs, $shown);
        next if has_paths_frontmatter(slurp($real, $shown));
        push @start, $real;
    }
}

# --- 読み込みを辿る(幅優先で、最も浅い段で1回だけ数える) -----------------
my @queue = map { [$_, 0] } @start;
my %seen;
my $count = 0;
while (my $item = shift @queue) {
    my ($real, $depth) = @$item;
    next if $seen{$real}++;
    my $shown = rel($real);
    my $text = slurp($real, $shown);
    printf "OK\t%d\t%s\n", length($text), $shown;
    $count++;
    next if $depth >= $MAX_HOPS;
    for my $raw (imports_of($text)) {
        push @queue, [resolve_import($raw, $real), $depth + 1];
    }
}
fail("測った文書がありません。") unless $count > 0;
exit 0;
PERL
); then
    reasons=()
    while IFS=$'\t' read -r tag reason; do
        if [ "$tag" = "ERR" ]; then
            reasons+=("$reason")
        fi
    done <<<"$LISTING"
    if [ "${#reasons[@]}" -eq 0 ]; then
        reasons=("文書を集める処理が想定外の理由で失敗しました。")
    fi
    undecidable "${reasons[@]}"
fi

TOTAL=0
COUNT=0
ROWS=""
LINES=""
while IFS=$'\t' read -r tag bytes path; do
    if [ "$tag" != "OK" ] || ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        undecidable "文書を集める処理の出力を読めません: ${tag} ${bytes:-} ${path:-}"
    fi
    TOTAL=$((TOTAL + bytes))
    COUNT=$((COUNT + 1))
    LINES+="${bytes} ${path}"$'\n'
    ROWS+="| ${bytes} | \`${path}\` |"$'\n'
done <<<"$LISTING"
if [ "$COUNT" -eq 0 ]; then
    undecidable "測った文書がありません。"
fi

TOTAL_LINE="合計 ${TOTAL} バイト / 上限 ${LIMIT} バイト"
printf '%s' "$LINES"
echo "$TOTAL_LINE"

ADVICE="Claude へ: どの会話の始めにも読み込まれる文書の合計が上限を超えています。
- 決まりを、要る場面で必ず読まれるスキルの本文などに移すか、短くして、合計を上限に収めてください。
- 上限の値 CLAUDE_MD_SIZE_LIMIT を上げる変更を、自分の判断で入れないでください。上げる必要があると判断したときは、理由を添えて所有者に提案してください。
- 文中で @ で始まる語を読み込みにしたくないときは、その語をバッククォートで囲んでください。"

if [ "$TOTAL" -le "$LIMIT" ]; then
    {
        echo "### :white_check_mark: 読み込まれる文書の量は上限以下です"
        echo ""
        echo "| バイト | 文書 |"
        echo "|---:|---|"
        printf '%s' "$ROWS"
        echo ""
        echo "$TOTAL_LINE"
        echo ""
    } | to_summary
    exit 0
fi

{
    echo "### :no_entry: 読み込まれる文書の量が上限を超えています"
    echo ""
    echo "| バイト | 文書 |"
    echo "|---:|---|"
    printf '%s' "$ROWS"
    echo ""
    echo "$TOTAL_LINE"
    echo ""
    echo "$ADVICE"
    echo ""
} | to_summary
echo "::error::[読み込まれる文書の量] ${TOTAL_LINE}。どの会話の始めにも読み込まれる文書の合計が上限を超えています。"
echo "$ADVICE"
exit 1
