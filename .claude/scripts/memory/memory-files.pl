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
#   prune-index
#     目次を読み直し、リンクの指すファイルがどれもメモリのディレクトリに無い行を消し、{"removed":[<消した行>]} の1行を出す。
#     リンクの無い行は残す
#   delete <名前>=<sha256>...
#     名前ごとに、今の中身の SHA-256 が渡した値と同じときだけ、メモリファイルと、そのファイルへのリンクを持つ目次の行を消し、
#     {"results":[{"name":..,"result":..,"removed_index_lines":[..]}]} の1行を出す。result は deleted・changed・missing・invalid・error のどれかである
#   origins <名前>...
#     名前ごとに、会話の記録の中の、メモリファイルへの最も早い書き込みを探し、{"origins":[..]} の1行を出す。名前は4つまで。
#     最も早い書き込みが Write で、その結果が update でなければ、found を真にし、その会話の、書き込みまでの開発者の文を utterances に
#     並べる。utterances は JSON にして6,000バイトまでにし、古い文から外して truncated を真にする。
#     最も早い書き込みが Edit か MultiEdit か、結果が update の Write なら reason が first-write-not-kept、書き込みが無ければ no-write、
#     決まりに合わない名前なら invalid になる
# 会話の記録: projects/ のうち、名前が本体の作業フォルダの名前と同じか、その名前に - を付けたもので始まるディレクトリの直下の *.jsonl。
# projects/ は、CLAUDE_CONFIG_DIR が空でなければその下、空なら $HOME/.claude の下にある。cwd が本体の作業フォルダかその下の行だけを使う
# 目次を書き換えるときは、消す直前に読み直し、同じディレクトリの一時のファイルに書いてから名前を替えて置き換える。
# 改行の形(\n か \r\n)と、消さない行のバイトの列は変えない
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
use Time::Local qw(timegm);

my $JSON  = JSON::PP->new->utf8->canonical;
my $INDEX = 'MEMORY.md';
# show と origins に1回で渡せる名前の数。1回の出力を、Bash の道具がそのまま返すおよそ30,000文字に収めるためである
my $MAX_NAMES = 4;
# origins が名前1つあたりに出す開発者の文の、JSON にしたときのバイトの数の上限
my $MAX_UTTERANCE_BYTES = 6000;

my %COMMANDS = (
    list => \&cmd_list,
    show => \&cmd_show,
    'prune-index' => \&cmd_prune_index,
    delete => \&cmd_delete,
    origins => \&cmd_origins,
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
    print STDERR "使い方: perl memory-files.pl list | show <名前>...(4つまで) | prune-index | delete <名前>=<sha256>... | origins <名前>...(4つまで)\n";
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

# 目次を読み直し、$drop が真を返す行を消して置き換える。消した行の文を並べて返す。$drop は、行の終わりの改行を除いた行の文を受ける。
# 目次が無いときと、消す行が無いときは、目次を書き換えない
sub rewrite_index {
    my ($memdir, $drop) = @_;
    my $path  = "$memdir/$INDEX";
    my $bytes = -d $memdir ? read_bytes($path) : undef;
    return () unless defined $bytes;
    my ($kept, @removed) = ('');
    # 行の終わりの改行を付けたまま分けるので、残す行のバイトの列と改行の形は変わらない
    for my $raw (split /(?<=\n)/, $bytes) {
        (my $text = $raw) =~ s/\r?\n\z//;
        if ($drop->($text)) { push @removed, $text; } else { $kept .= $raw; }
    }
    return () unless @removed;
    # 一時のファイルの名前は .md で終わらないので、途中で止まってもメモリファイルに数えられない
    my $tmp = "$path.$$.tmp";
    # 失敗した理由は、失敗した処理の直後に控える。あとの処理が $! を上書きするためである
    my $why;
    if (open(my $fh, '>:raw', $tmp)) {
        $why = "$!" unless print {$fh} $kept;
        $why //= "$!" unless close $fh;
    } else {
        $why = "$!";
    }
    # 書き終えられなかった一時のファイルで目次を置き換えないように、書き終えたときだけ名前を替える
    $why = "$!" if !defined $why && !rename $tmp, $path;
    if (defined $why) {
        unlink $tmp;
        die "目次 $path を書き換えられなかった($why)\n";
    }
    return @removed;
}

sub cmd_prune_index {
    return usage() if @_;
    my $memdir  = memory_dir();
    my @removed = rewrite_index($memdir, sub {
        my @links = index_links($_[0]);
        return @links && !grep { -e "$memdir/$_" } @links;
    });
    return emit({ removed => [ map { text_of($_) } @removed ] });
}

# 1つのメモリファイルを消せなかった結果を書き、同じ理由を標準エラーに1文で出す。理由はバイトの列で受ける
sub fail_one {
    my ($result, $why) = @_;
    ($result->{result}, $result->{error}) = ('error', text_of($why));
    print STDERR "memory-files.pl: $why\n";
}

sub cmd_delete {
    my @args = @_;
    return usage() unless @args;
    my @pairs;
    for my $arg (@args) {
        my ($name, $sha) = $arg =~ /\A(.*)=([0-9a-fA-F]{64})\z/s or return usage();
        push @pairs, [ $name, lc $sha ];
    }
    my $memdir = memory_dir();
    my ($failed, @results) = (0);
    for my $pair (@pairs) {
        my ($name, $sha) = @$pair;
        my $result = { name => text_of($name) };
        push @results, $result;
        if (!valid_name($name)) {
            $result->{result} = 'invalid';
            next;
        }
        my $path  = "$memdir/$name";
        my $bytes = eval { -f $path ? read_bytes($path) : undef };
        if ($@) {
            fail_one($result, $@ =~ s/\s+\z//r);
            $failed = 1;
            next;
        }
        if (!defined $bytes) {
            $result->{result} = 'missing';
            next;
        }
        if (sha256_hex($bytes) ne $sha) {
            $result->{result} = 'changed';
            next;
        }
        if (!unlink $path) {
            fail_one($result, "$path を消せなかった($!)");
            $failed = 1;
            next;
        }
        $result->{result} = 'deleted';
        my @removed = eval { rewrite_index($memdir, sub { grep { $_ eq $name } index_links($_[0]) }) };
        if ($@) {
            # メモリファイルは消えたが、目次の行が残った。行は list の dangling に出る
            print STDERR "memory-files.pl: $@";
            $failed = 1;
        }
        $result->{removed_index_lines} = [ map { text_of($_) } @removed ];
    }
    emit({ results => \@results });
    return $failed ? 1 : 0;
}

# ---- 会話の記録 ------------------------------------------------------------

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

# このリポジトリの会話の記録のファイルを返す。projects/ のうち、名前が本体の作業フォルダの名前と同じか、その名前に - を付けたもので
# 始まるディレクトリの直下の *.jsonl である。場所に空白や記号があっても読めるように、glob を使わない
sub transcript_files {
    my ($main) = @_;
    my $base = defined $ENV{CLAUDE_CONFIG_DIR} && $ENV{CLAUDE_CONFIG_DIR} ne '' ? $ENV{CLAUDE_CONFIG_DIR} : do {
        die "HOME が無いので、会話の記録の場所を求められなかった\n" unless defined $ENV{HOME} && $ENV{HOME} ne '';
        "$ENV{HOME}/.claude";
    };
    $base =~ s{[/\\]+\z}{};
    my $root = "$base/projects";
    my $name = project_name($main);
    opendir(my $dh, $root) or return ();
    my @dirs = sort grep { ($_ eq $name || index($_, "$name-") == 0) && -d "$root/$_" } readdir $dh;
    closedir $dh;
    my @files;
    for my $dir (map { "$root/$_" } @dirs) {
        opendir(my $d, $dir) or die "$dir を読めなかった($!)\n";
        push @files, map { "$dir/$_" } sort grep { /\.jsonl\z/ && -f "$dir/$_" } readdir $d;
        closedir $d;
    }
    return @files;
}

# 記録のファイルを1行ずつ読み、$keep が真を返す行だけを JSON として読み、cwd が本体の作業フォルダかその下の行を $each に渡す。
# $keep は、JSON として読む前の行のバイトの列を受ける。JSON として読む行を減らし、大きな記録を速く読むためである。JSON として読めない行は飛ばす
sub each_line {
    my ($file, $top, $keep, $each) = @_;
    open(my $fh, '<:raw', $file) or die "$file を読めなかった($!)\n";
    while (my $line = <$fh>) {
        next unless $keep->($line);
        my $j = eval { $JSON->decode($line) };
        next unless ref $j eq 'HASH' && defined $j->{cwd} && !ref $j->{cwd};
        next unless under(norm(encode('UTF-8', $j->{cwd})), $top);
        $each->($j);
    }
    close $fh;
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

# 記録のファイルから、開発者が打った文を、{at, text} の一覧で古い順に返す
sub developer_texts {
    my ($file, $top) = @_;
    my @said;
    # 開発者が打った文の行は、行の中に "type":"user" を持つ。道具の結果の行は、中身が "type":"tool_result" の部分を持つ配列で、
    # "type":"text" の部分を持たなければ developer_text が文を返さない。大きな記録を速く読むために、どちらの行も JSON として読まない
    each_line($file, $top, sub {
        my ($line) = @_;
        return index($line, '"type":"user"') >= 0 && (index($line, '"type":"tool_result"') < 0 || index($line, '"type":"text"') >= 0);
    }, sub {
        my ($j) = @_;
        my $text = developer_text($j);
        push @said, { at => $j->{timestamp}, text => $text } if defined $text && defined $j->{timestamp} && !ref $j->{timestamp};
    });
    return @said;
}

# 開発者の文の一覧を、JSON にしたときに $MAX_UTTERANCE_BYTES までに収める。書き込みに近い文を残し、古い文から外す。
# 書き込みに最も近い文だけでも収まらないときは、その文の終わりを切って収める。収めた一覧と、外したか切ったかを返す
sub fit {
    my ($said) = @_;
    my ($size, @kept) = (2);   # 2 は、配列を囲む [ と ] のバイトの数である
    for my $u (reverse @$said) {
        my $len = length($JSON->encode($u)) + (@kept ? 1 : 0);   # 1 は、文と文の間の , のバイトの数である
        last if $size + $len > $MAX_UTTERANCE_BYTES;
        $size += $len;
        unshift @kept, $u;
    }
    if (!@kept && @$said) {
        my $u = $said->[-1];
        my ($lo, $hi) = (0, length $u->{text});
        while ($lo < $hi) {
            my $mid = int(($lo + $hi + 1) / 2);
            if (length($JSON->encode([{ %$u, text => substr($u->{text}, 0, $mid) }])) <= $MAX_UTTERANCE_BYTES) { $lo = $mid; } else { $hi = $mid - 1; }
        }
        @kept = ({ %$u, text => substr($u->{text}, 0, $lo) }) if $lo > 0;
    }
    return (\@kept, @kept < @$said || (@kept && $kept[-1]{text} ne $said->[-1]{text}) ? 1 : 0);
}

# 記録の時刻(UTC の ISO 8601 の形)を、この PC の時刻の日付にする。読めない形なら、先頭の10文字を返す
sub local_date {
    my ($at) = @_;
    my @t = $at =~ /\A(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)/ or return substr($at, 0, 10);
    my $epoch = eval { timegm($t[5], $t[4], $t[3], $t[2], $t[1] - 1, $t[0]) };
    return defined $epoch ? strftime('%Y-%m-%d', localtime $epoch) : substr($at, 0, 10);
}

sub cmd_origins {
    my @names = @_;
    return usage() if !@names || @names > $MAX_NAMES;
    my $main   = main_worktree();
    my $top    = norm($main);
    my $memdir = memory_dir();
    # 決まりに合わない名前は探さない。メモリのディレクトリの外の場所への書き込みを、メモリファイルへの書き込みとして見つけないためである
    my @valid  = grep { valid_name($_) } @names;
    my %want   = map { (norm("$memdir/$_") => $_) } @valid;
    # %first は名前ごとの最も早い書き込み、%type_of は道具の呼び出しの ID ごとの結果の toolUseResult.type である
    my (%first, %type_of);
    for my $file (@valid ? transcript_files($main) : ()) {
        # 書き込みの行と、その結果の行は、どちらも行の中にメモリファイルの名前を持つ
        each_line($file, $top, sub { my ($line) = @_; grep { index($line, $_) >= 0 } @valid }, sub {
            my ($j) = @_;
            my $content = ref $j->{message} eq 'HASH' ? $j->{message}{content} : undef;
            return unless ref $content eq 'ARRAY';
            if (ref $j->{toolUseResult} eq 'HASH') {
                for my $c (grep { ref $_ eq 'HASH' && ($_->{type} // '') eq 'tool_result' } @$content) {
                    $type_of{ $c->{tool_use_id} } = $j->{toolUseResult}{type} // '' if defined $c->{tool_use_id} && !ref $c->{tool_use_id};
                }
            }
            my $at = $j->{timestamp};
            return unless defined $at && !ref $at;
            for my $c (@$content) {
                next unless ref $c eq 'HASH' && ($c->{type} // '') eq 'tool_use';
                next unless ($c->{name} // '') =~ /\A(?:Write|Edit|MultiEdit)\z/;
                my $path = ref $c->{input} eq 'HASH' ? $c->{input}{file_path} : undef;
                next unless defined $path && !ref $path;
                my $name = $want{ norm(encode('UTF-8', $path)) };
                # 時刻は、どの記録も同じ ISO 8601 の形なので、文字の列のまま比べる
                next if !defined $name || ($first{$name} && $first{$name}{at} le $at);
                my ($sid) = $file =~ m{([^/]+)\.jsonl\z};
                $first{$name} = {
                    at      => $at,
                    tool    => $c->{name},
                    id      => defined $c->{id} && !ref $c->{id} ? $c->{id} : undef,
                    file    => $file,
                    session => defined $j->{sessionId} && !ref $j->{sessionId} ? $j->{sessionId} : decode('UTF-8', $sid),
                };
            }
        });
    }
    my (%said, @origins);
    for my $name (@names) {
        my $w = $first{$name};
        my $reason = !valid_name($name) ? 'invalid'
            : !$w ? 'no-write'
            : $w->{tool} ne 'Write' || (defined $w->{id} && ($type_of{ $w->{id} } // '') eq 'update') ? 'first-write-not-kept'
            : undef;
        if (defined $reason) {
            push @origins, { name => text_of($name), found => JSON::PP::false, reason => $reason };
            next;
        }
        # 選んだ記録は、開発者の文を読むためにもう一度読む。同じ記録は1回だけ読む
        $said{ $w->{file} } //= [ developer_texts($w->{file}, $top) ];
        my ($utterances, $truncated) = fit([ grep { $_->{at} le $w->{at} } @{ $said{ $w->{file} } } ]);
        push @origins, {
            name       => text_of($name),
            found      => JSON::PP::true,
            session    => $w->{session},
            written_on => local_date($w->{at}),
            utterances => $utterances,
            truncated  => $truncated ? JSON::PP::true : JSON::PP::false,
        };
    }
    return emit({ origins => \@origins });
}

1;
