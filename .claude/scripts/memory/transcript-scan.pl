#!/usr/bin/perl
# =====================================================================
# このリポジトリの会話の記録を読むスクリプト。記録を書き換えない
#
# 使い方: perl .claude/scripts/memory/transcript-scan.pl <サブコマンド> [引数]
#   writes --since <時刻> --memory-dir <場所> <ファイル名>...
#     時刻よりあとの記録から、名前が Write・Edit・MultiEdit で file_path がメモリのディレクトリの中のファイルを指す
#     道具の呼び出しを探し、{"<ファイル名>":true|false,...} の1行を出す。時刻は ISO 8601 の形で受ける
#   utterances <会話の ID>
#     その会話の記録から、開発者が打った文だけを時刻と一緒に {"found":true,"truncated":..,"utterances":[{"at":..,"text":..}]}
#     の1行で出す。出す JSON は20KBまでで切る。記録が無いか読めないときは {"found":false} を出す
# 選ぶ記録: <CLAUDE_CONFIG_DIR か ~/.claude>/projects/ の下の、名前が本体の作業フォルダの場所を符号にした名前と同じか、
# その名前に - を続けた名前で始まるディレクトリの *.jsonl と */subagents/*.jsonl のうち、cwd の欄が本体の作業フォルダか
# その下の場所の行だけを使う。符号にした名前とは、場所の英数字でない文字を1文字ずつ - に替えた名前である。
# 本体の作業フォルダは、このスクリプトの場所から、memory-inspect.pl と同じ求め方で求める
# 終了コード: 成功は 0、使い方の誤りは 2、失敗は 1(標準エラーに理由を日本語の1文で出す)
# 前提: perl(JSON::PP)・git
# =====================================================================
package TranscriptScan;

use strict;
use warnings;
use Encode qw(decode encode);
use File::Basename qw(dirname);
use JSON::PP;

my $LIMIT = 20 * 1024;
my $JSON  = JSON::PP->new->utf8->canonical;

# 本体の作業フォルダの求め方を memory-inspect.pl から使う。読み込んでも memory-inspect.pl は動かない。
# require は / や ./ で始まらない場所(Windows の C:/... の形や、相対の場所)を @INC から探すので、このフォルダを @INC の先頭に置く。
# 読み込んだファイルは呼んだ側のパッケージに入るので、memory-inspect.pl の関数を main に置くように、main から読み込む
BEGIN { unshift @INC, dirname(__FILE__); }
{
    package main;
    require 'memory-inspect.pl';
}

my %COMMANDS = (
    writes     => \&cmd_writes,
    utterances => \&cmd_utterances,
);

# テストが do で読み込んだときは、呼び出しを動かさない
exit run(@ARGV) unless caller;

sub run {
    my ($cmd, @args) = @_;
    my $sub = defined $cmd ? $COMMANDS{$cmd} : undef;
    return usage() unless $sub;
    my $rc = eval { $sub->(@args) };
    return $rc if defined $rc;
    (my $why = $@ // '') =~ s/\s+/ /g;
    $why =~ s/ \z//;
    print STDERR "transcript-scan.pl: $why\n";
    return 1;
}

sub usage {
    print STDERR "使い方: perl transcript-scan.pl writes --since <時刻> --memory-dir <場所> <ファイル名>... | utterances <会話の ID>\n";
    return 2;
}

# ---- 場所 ----------------------------------------------------------------

# 場所の形をそろえる。C:\ と C:/ と /c/ の形を c:/ の形にし、区切りを / にそろえ、大文字と小文字をそろえる
sub norm {
    my ($p) = @_;
    $p =~ s{\\}{/}g;
    $p =~ s{\A/([A-Za-z])(?=/|\z)}{$1:};
    $p =~ s{/+}{/}g;
    $p =~ s{(?<=.)/\z}{};
    return lc $p;
}

# 場所 $p が、場所 $top か、その下の場所かを返す。どちらも norm でそろえた形で受ける
sub under {
    my ($p, $top) = @_;
    return $p eq $top || index($p, "$top/") == 0;
}

# このリポジトリの記録のディレクトリを返す
sub project_dirs {
    my ($main) = @_;
    my $base = defined $ENV{CLAUDE_CONFIG_DIR} && $ENV{CLAUDE_CONFIG_DIR} ne '' ? $ENV{CLAUDE_CONFIG_DIR} : do {
        die "HOME が無いので、会話の記録の場所を求められなかった\n" unless defined $ENV{HOME} && $ENV{HOME} ne '';
        "$ENV{HOME}/.claude";
    };
    $base =~ s{/+\z}{};
    my $root = "$base/projects";
    (my $name = decode('UTF-8', $main)) =~ s/[^A-Za-z0-9]/-/g;
    opendir(my $dh, $root) or return ();
    my @dirs = sort grep { ($_ eq $name || index($_, "$name-") == 0) && -d "$root/$_" } readdir $dh;
    closedir $dh;
    return map { "$root/$_" } @dirs;
}

# このリポジトリの記録のファイルを返す
sub transcript_files {
    my ($main) = @_;
    my @files;
    for my $dir (project_dirs($main)) {
        push @files, jsonl_in($dir);
        opendir(my $dh, $dir) or next;
        my @subs = sort grep { !/\A\.\.?\z/ && -d "$dir/$_/subagents" } readdir $dh;
        closedir $dh;
        push @files, jsonl_in("$dir/$_/subagents") for @subs;
    }
    return @files;
}

# ディレクトリの直下の *.jsonl のファイルを返す。場所に空白や記号があっても読めるように、glob を使わない
sub jsonl_in {
    my ($dir) = @_;
    opendir(my $dh, $dir) or return ();
    my @names = sort grep { /\.jsonl\z/ && -f "$dir/$_" } readdir $dh;
    closedir $dh;
    return map { "$dir/$_" } @names;
}

# 記録のファイルを1行ずつ読み、cwd が本体の作業フォルダの下の行を $each に渡す。読めない行は飛ばす
sub each_line {
    my ($file, $top, $each) = @_;
    open(my $fh, '<:raw', $file) or return;
    while (my $line = <$fh>) {
        my $j = eval { $JSON->decode($line) };
        next unless ref $j eq 'HASH' && defined $j->{cwd} && !ref $j->{cwd};
        next unless under(norm(encode('UTF-8', $j->{cwd})), $top);
        $each->($j);
    }
    close $fh;
}

# ---- サブコマンド ----------------------------------------------------------

sub cmd_writes {
    my @args = @_;
    my ($since, $memdir, @names);
    while (@args) {
        my $a = shift @args;
        if ($a eq '--since' && @args) { $since = shift @args; }
        elsif ($a eq '--memory-dir' && @args) { $memdir = shift @args; }
        else { push @names, $a; }
    }
    return usage() unless defined $since && defined $memdir && @names;
    my $from = main::epoch($since);
    die "時刻 $since を読めなかった\n" unless defined $from;
    my $main = main::main_worktree(dirname(__FILE__));
    my $top  = norm($main);
    my %want = map { (norm("$memdir/$_") => $_) } @names;
    my %found = map { ($_ => JSON::PP::false) } @names;
    for my $file (transcript_files($main)) {
        my $mtime = (stat $file)[9];
        next unless defined $mtime && $mtime >= int($from);
        each_line($file, $top, sub {
            my ($j) = @_;
            my $at = main::epoch($j->{timestamp});
            return if defined $at && $at <= $from;
            my $content = ref $j->{message} eq 'HASH' ? $j->{message}{content} : undef;
            return unless ref $content eq 'ARRAY';
            for my $c (@$content) {
                next unless ref $c eq 'HASH' && ($c->{type} // '') eq 'tool_use';
                next unless ($c->{name} // '') =~ /\A(?:Write|Edit|MultiEdit)\z/;
                my $path = ref $c->{input} eq 'HASH' ? $c->{input}{file_path} : undef;
                next unless defined $path && !ref $path;
                my $name = $want{ norm(encode('UTF-8', $path)) };
                $found{$name} = JSON::PP::true if defined $name;
            }
        });
    }
    print $JSON->encode({ map { (decode('UTF-8', $_) => $found{$_}) } keys %found }), "\n";
    return 0;
}

# 開発者が打った文の行かを返す。中身が配列の行(画像と一緒に打った文)は、type が text の部分の文を
# 改行でつなぐ。text の部分が無い行(道具の結果の行)と、isMeta の行と、会話の要約の行と、
# 開発者でない出どころ(origin.kind が human でない)の行と、会話に差し込まれた知らせの行を除く
sub developer_text {
    my ($j) = @_;
    return undef unless ($j->{type} // '') eq 'user';
    my $text = ref $j->{message} eq 'HASH' ? $j->{message}{content} : undef;
    if (ref $text eq 'ARRAY') {
        my @parts = map { $_->{text} } grep { ref $_ eq 'HASH' && ($_->{type} // '') eq 'text' && defined $_->{text} && !ref $_->{text} } @$text;
        $text = @parts ? join("\n", @parts) : undef;
    }
    return undef unless defined $text && !ref $text;
    return undef if $j->{isMeta} || $j->{isCompactSummary} || $j->{isVisibleInTranscriptOnly};
    return undef if ref $j->{origin} eq 'HASH' && ($j->{origin}{kind} // '') ne 'human';
    return undef if $text =~ /\A\s*<(?:task-notification|system-reminder|local-command-stdout|local-command-caveat|agent-message)\b/;
    return $text;
}

sub cmd_utterances {
    my @args = @_;
    return usage() unless @args == 1;
    my ($id) = @args;
    die "会話の ID $id の形が正しくない\n" unless $id =~ /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/;
    my $main = main::main_worktree(dirname(__FILE__));
    my $top  = norm($main);
    my ($file) = grep { -f } map { "$_/$id.jsonl" } project_dirs($main);
    my @said;
    my $read = 0;
    if (defined $file) {
        each_line($file, $top, sub {
            my ($j) = @_;
            $read = 1;
            my $text = developer_text($j);
            push @said, { at => $j->{timestamp}, text => $text } if defined $text;
        });
    }
    unless ($read) {
        print $JSON->encode({ found => JSON::PP::false }), "\n";
        return 0;
    }
    print fit(\@said), "\n";
    return 0;
}

# 開発者の文の一覧を、JSON にしたときに20KBまでに収まるように切って、JSON の文字列を返す。
# 入りきらない最初の文は、収まる長さまで末尾を切って入れ、そのあとの文は入れない
sub fit {
    my ($said) = @_;
    my $out = { found => JSON::PP::true, truncated => JSON::PP::false, utterances => [] };
    for my $u (@$said) {
        push @{ $out->{utterances} }, $u;
        next if length($JSON->encode($out)) <= $LIMIT;
        $out->{truncated} = JSON::PP::true;
        pop @{ $out->{utterances} };
        my $full = $u->{text};
        my ($lo, $hi) = (0, length $full);
        while ($lo < $hi) {
            my $mid = int(($lo + $hi + 1) / 2);
            push @{ $out->{utterances} }, { %$u, text => substr($full, 0, $mid) };
            my $fits = length($JSON->encode($out)) <= $LIMIT;
            pop @{ $out->{utterances} };
            if ($fits) { $lo = $mid; } else { $hi = $mid - 1; }
        }
        push @{ $out->{utterances} }, { %$u, text => substr($full, 0, $lo) } if $lo > 0;
        last;
    }
    return $JSON->encode($out);
}
