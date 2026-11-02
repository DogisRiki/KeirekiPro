#!/usr/bin/perl
# =====================================================================
# このリポジトリのメモリを読み、確かめてから消すスクリプト。点検のスキル(memory-inspect-now)から呼ばれる。
# 消すかどうかは判断しない。メモリのディレクトリの外のファイルと会話の記録を書き換えず、新しいメモリファイルを作らない
#
# 使い方: perl .claude/scripts/memory/memory-files.pl <サブコマンド> [引数]
#   list
#     目次とメモリファイルを読み、{"memory_dir":..,"index_exists":..,"files":[..],"dangling":[..]} の1行を出す。
#     files は目次の行に初めて出た順で、目次に行の無いメモリファイルは名前の順にそのあとに並べる。中身は出さない。
#     dangling は、リンクの指すメモリファイルがどれもメモリのディレクトリに無い目次の行である
#   show <名前>...
#     名前ごとに、中身と SHA-256 を {"files":[{"name":..,"sha256":..,"content":..,"decode_error":..}]} の1行で出す。
#     無い名前は result が missing、決まりに合わない名前は result が invalid になる。名前は4つまで
# メモリのディレクトリ: 今の作業フォルダを含むリポジトリの git の共通ディレクトリの親を本体の作業フォルダとし、
# その場所の英数字でない文字を1文字ずつ - に替えた名前の $HOME/.claude/projects/<名前>/memory である
# メモリファイルの名前: / と \ を含まず、. で始まらず、.md で終わり、MEMORY.md でない名前
# 終了コード: 成功は 0、使い方の誤りは 2、読み書きの失敗は 1(標準エラーに理由を日本語の1文で出す)
# 前提: perl(JSON::PP・Digest::SHA)・git
# =====================================================================
package MemoryFiles;

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use Encode qw(decode encode);
use File::Basename qw(dirname);
use File::Spec;
use JSON::PP;
use POSIX qw(strftime);

my $JSON  = JSON::PP->new->utf8->canonical;
my $INDEX = 'MEMORY.md';
# show と origins に1回で渡せる名前の数。1回の出力を、Bash の道具がそのまま返すおよそ30,000文字に収めるためである
my $MAX_NAMES = 4;

my %COMMANDS = (
    list => \&cmd_list,
    show => \&cmd_show,
);

# old-inspection-cleanup.pl が require で読み込んだときは、サブコマンドを動かさない
exit main(@ARGV) unless caller;

sub main {
    my ($cmd, @args) = @_;
    my $run = defined $cmd ? $COMMANDS{$cmd} : undef;
    return usage() unless $run;
    my $rc = eval { $run->(@args) };
    return $rc if defined $rc;
    (my $why = $@ // '') =~ s/\s+/ /g;
    $why =~ s/ \z//;
    print STDERR "memory-files.pl: $why\n";
    return 1;
}

sub usage {
    print STDERR "使い方: perl memory-files.pl list | show <名前>...(4つまで)\n";
    return 2;
}

# 結果を JSON の1行で標準出力に出し、0 を返す
sub emit {
    my ($data) = @_;
    binmode STDOUT;
    print $JSON->encode($data), "\n";
    return 0;
}

# ---- 場所 ----------------------------------------------------------------

# 今の作業フォルダを含むリポジトリの git の共通ディレクトリを返す。worktree の中からも、本体と同じ場所を返す
sub git_common_dir {
    open(my $saved, '>&', \*STDERR) or die "標準エラーを控えられなかった($!)\n";
    open(STDERR, '>', File::Spec->devnull) or die "標準エラーを閉じられなかった($!)\n";
    my $ok = open(my $g, '-|', 'git', 'rev-parse', '--path-format=absolute', '--git-common-dir');
    my $out = $ok ? do { local $/; <$g> } : undef;
    my $closed = $ok ? close($g) : 0;
    open(STDERR, '>&', $saved) or die "標準エラーを戻せなかった($!)\n";
    die "今の作業フォルダを含む git のリポジトリの共通ディレクトリを求められなかった\n" unless $closed && defined $out;
    $out =~ s/\r?\n\z//;
    die "今の作業フォルダを含む git のリポジトリの共通ディレクトリを求められなかった\n" unless $out =~ /\S/ && $out !~ /\n/;
    return $out;
}

# 本体の作業フォルダを、git の共通ディレクトリの親のフォルダとして返す
sub main_worktree { return dirname(git_common_dir()); }

# 本体の作業フォルダの場所の英数字でない文字を1文字ずつ - に替えた名前を返す。Claude Code がプロジェクトのディレクトリの名前を作る決まりである
sub project_name {
    my ($main) = @_;
    (my $name = decode('UTF-8', $main)) =~ s/[^A-Za-z0-9]/-/g;
    # 名前は英数字と - だけになるので、バイトの列に戻す。ファイルの名前のバイトの列とつないでも、名前が化けないためである
    utf8::downgrade($name);
    return $name;
}

# このリポジトリのメモリのディレクトリ $HOME/.claude/projects/<名前>/memory を返す。作らない
sub memory_dir {
    my $home = $ENV{HOME};
    die "HOME が無いので、メモリのディレクトリを求められなかった\n" unless defined $home && $home ne '';
    $home =~ s{/+\z}{};
    return "$home/.claude/projects/" . project_name(main_worktree()) . '/memory';
}

# ---- メモリ --------------------------------------------------------------

# 名前がメモリファイルの名前の決まりに合うかを返す。名前はバイトの列で受ける
sub valid_name {
    my ($name) = @_;
    return defined $name && $name =~ m{\A[^/\\.][^/\\]*\.md\z} && $name ne $INDEX ? 1 : 0;
}

# バイトの列を、表示のための文字の列に直す。UTF-8 として読めないバイトは置き換えの文字にする
sub text_of { return decode('UTF-8', $_[0]); }

# ファイルの中身をバイトの列で返す。無ければ undef を返し、読めなければ die する
sub read_bytes {
    my ($path) = @_;
    return undef unless -e $path;
    open(my $fh, '<:raw', $path) or die "$path を読めなかった($!)\n";
    my $bytes = do { local $/; <$fh> };
    close $fh;
    return defined $bytes ? $bytes : '';
}

# メモリのディレクトリの最上位の、名前の決まりに合うメモリファイルの名前を、バイトの列で並べて返す。ディレクトリが無ければ空を返す
sub memory_files {
    my ($memdir) = @_;
    return () unless -d $memdir;
    opendir(my $dh, $memdir) or die "メモリのディレクトリ $memdir を読めなかった($!)\n";
    my @names = sort grep { valid_name($_) && -f "$memdir/$_" } readdir $dh;
    closedir $dh;
    return @names;
}

# 目次の中身を行に分け、[行の番号, 行の文] の組を並べて返す。行の文は、行の終わりの改行と、その前の \r を除いたものである
sub index_lines {
    my ($text) = @_;
    my @lines = split /\n/, $text, -1;
    pop @lines if @lines && $lines[-1] eq '';
    my $no = 0;
    return map { (my $t = $_) =~ s/\r\z//; [ ++$no, $t ] } @lines;
}

# 目次の行のリンクが指すメモリファイルの名前を、重ねずに返す。# から後ろと先頭の ./ を外し、.md で終わり :// を含まない名前だけを返す
sub index_links {
    my ($line) = @_;
    my (%seen, @names);
    while ($line =~ /\]\(\s*<?([^)<>\s]+?)>?\s*\)/g) {
        (my $name = $1) =~ s/#.*\z//;
        $name =~ s{\A\./}{};
        next if $name !~ /\.md\z/ || $name =~ m{://};
        push @names, $name unless $seen{$name}++;
    }
    return @names;
}

# ---- サブコマンド ----------------------------------------------------------

sub cmd_list {
    return usage() if @_;
    my $memdir = memory_dir();
    my @names  = memory_files($memdir);
    my $index  = -d $memdir ? read_bytes("$memdir/$INDEX") : undef;
    my (%lines_of, @order, @dangling);
    for my $line (defined $index ? index_lines($index) : ()) {
        my ($no, $text) = @$line;
        my @links = index_links($text);
        next unless @links;
        my $entry = { no => $no, text => text_of($text) };
        for my $name (@links) {
            next unless valid_name($name) && -f "$memdir/$name";
            push @order, $name unless $lines_of{$name};
            push @{ $lines_of{$name} }, $entry;
        }
        push @dangling, { %$entry, files => [ map { text_of($_) } @links ] } unless grep { -e "$memdir/$_" } @links;
    }
    my %listed = map { $_ => 1 } @order;
    my @files;
    for my $name (@order, grep { !$listed{$_} } @names) {
        my $mtime = (stat "$memdir/$name")[9];
        die "$memdir/$name の更新した日付を読めなかった($!)\n" unless defined $mtime;
        push @files, {
            name        => text_of($name),
            modified_on => strftime('%Y-%m-%d', localtime $mtime),
            index_lines => $lines_of{$name} || [],
        };
    }
    return emit({
        memory_dir   => text_of($memdir),
        index_exists => defined $index ? JSON::PP::true : JSON::PP::false,
        files        => \@files,
        dangling     => \@dangling,
    });
}

sub cmd_show {
    my @names = @_;
    return usage() if !@names || @names > $MAX_NAMES;
    my $memdir = memory_dir();
    my @files;
    for my $name (@names) {
        if (!valid_name($name)) {
            push @files, { name => text_of($name), result => 'invalid' };
            next;
        }
        my $path  = "$memdir/$name";
        my $bytes = -f $path ? read_bytes($path) : undef;
        if (!defined $bytes) {
            push @files, { name => text_of($name), result => 'missing' };
            next;
        }
        my $content = eval { decode('UTF-8', $bytes, Encode::FB_CROAK | Encode::LEAVE_SRC) };
        push @files, {
            name         => text_of($name),
            sha256       => sha256_hex($bytes),
            content      => defined $content ? $content : '',
            decode_error => defined $content ? JSON::PP::false : JSON::PP::true,
        };
    }
    return emit({ files => \@files });
}

1;
