#!/usr/bin/env bash
# =====================================================================
# テストに使う偽の curl
#
# テストは、このファイルを一時フォルダに curl の名前で写し、その一時フォルダを
# PATH の先頭に置く。偽の curl は、ネットワークに出ず、$KP_FAKE_CURL_DIR のフォルダの
# 見本を応答の代わりにする。前提: bash・perl。
#
# 見本: URL の英数字でない文字を1文字ずつ _ に替えた名前に、.status と .body を付けた
# 2つのファイル。.status には HTTP の状態(200 など)を書く。.status が 000 のときは、
# つながらなかったものとして、本文を書かず、終了コードを 7 にする。
# 見本の無い URL には、状態 404 と空の本文を返す。
#
# 読むオプション
# - --parallel: 遅らせていない URL を先に終え、遅らせた URL を遅らせた秒数の短い順に終える
# - --next: URL ごとのオプション(-o -w -H)の区切り
# - -o <ファイル>: URL の本文を書くファイル。無いときは本文を標準出力に出す
# - -w <書式>: URL が終わるたびに標準出力に出す行。%{url_effective} %{http_code}
#   %{response_code} %{exitcode} と \n \t を置き換える
# - -H <ヘッダー> / -H @<ファイル>: 受け取って記録する
# - -K <ファイル>: 設定ファイルを読み、1行を1つのオプションとして、その場所に引数を足す。
#   行は「--<名前> <値>」「-<1文字> <値>」「<名前> = <値>」の形とし、値は " で囲めば
#   \\ \" \t \n \r \v を読む。url の行の値は URL とし、--output --write-out --header --user-agent は
#   -o -w -H -A と同じに読む。# で始まる行と空の行は読まない
# 受け付けて値を使わないオプション: --parallel-max --max-time --compressed -A -s
# そのほかのオプションは、標準エラーに1行を出して 2 で終わる。テストが、偽の curl の
# 答えない呼び出しに気づかないまま通ることを防ぐためである。
#
# 環境変数
# - KP_FAKE_CURL_LOG: 呼び出しごとに、受け取った引数と、-H @<ファイル> の中身を書き足すファイル。
#   1回の呼び出しは「CALL」の行で始まり、引数を1つにつき1行「ARG <引数>」で、
#   -K の設定ファイルから読んだ引数は「KARG <引数>」で、
#   -H @<ファイル> の中身を1行につき1行「HFILE <ファイル> <行>」で書く
# - KP_FAKE_CURL_DELAY: 空白で区切った「<URL>=<秒>」。その URL の応答を、その秒数だけ遅らせる
#
# 偽の curl は、URL が終わるたびに -o のファイルを書き、-w の行を出してすぐに流す。
# 呼び出しの途中で止められても、それまでに書いたファイルと行は残る。
# =====================================================================
: <<'__PERL__'
#!perl
use strict;
use warnings;
use Time::HiRes qw(sleep);

$| = 1;

sub unsupported {
    print STDERR "fake-curl: unsupported: $_[0]\n";
    exit 2;
}

my $dir = $ENV{KP_FAKE_CURL_DIR};
unsupported('KP_FAKE_CURL_DIR is not set') unless defined $dir && length $dir;

# 設定ファイルの1行の値を読む。" で囲んだ値は、決まった文字の前の \ を読む
sub config_value {
    my ($v) = @_;
    return $v unless $v =~ /\A"(.*)"\s*\z/s;
    my $q = $1;
    my %esc = ('\\' => '\\', '"' => '"', t => "\t", n => "\n", r => "\r", v => "\x0b");
    $q =~ s/\\(.)/exists $esc{$1} ? $esc{$1} : $1/ge;
    return $q;
}

# -K の設定ファイルを読み、引数の一覧に直す
sub read_config {
    my ($file) = @_;
    open my $h, '<', $file or unsupported("-K $file: $!");
    my %long = ('--output' => '-o', '--write-out' => '-w', '--header' => '-H', '--user-agent' => '-A');
    my @out;
    while (my $line = <$h>) {
        $line =~ s/\r?\n\z//;
        $line =~ s/\A\s+//;
        next if $line eq '' || $line =~ /\A#/;
        my ($opt, $rest) = $line =~ /\A([^\s=:]+)\s*(.*)\z/s or unsupported("-K line: $line");
        if ($opt !~ /\A-/) {
            $rest =~ s/\A[=:]\s*//;
            $opt = "--$opt";
        }
        $opt = $long{$opt} // $opt;
        if ($opt eq '--url') {
            push @out, ['url', config_value($rest)];
        } elsif ($rest eq '') {
            push @out, ['opt', $opt];
        } else {
            push @out, ['opt', $opt], ['opt', config_value($rest)];
        }
    }
    close $h;
    return @out;
}

# -K の設定ファイルを、その場所の引数に開く。$from_config には、設定ファイルから読んだ引数の場所を残す
my (@args, %from_config);
{
    my @raw = @ARGV;
    while (@raw) {
        my $arg = shift @raw;
        if ($arg eq '-K' || $arg eq '--config') {
            unsupported('-K needs a value') unless @raw;
            for my $t (read_config(shift @raw)) {
                # url の行の値は、- で始まってもオプションとして読まない
                $from_config{ scalar @args } = $t->[0];
                push @args, $t->[1];
            }
            next;
        }
        push @args, $arg;
    }
}

# 呼び出しを記録する。-H @<ファイル> の中身は、呼び出しのあとにファイルが消されても残るよう、最初に読む
if (defined $ENV{KP_FAKE_CURL_LOG} && length $ENV{KP_FAKE_CURL_LOG}) {
    open my $log, '>>', $ENV{KP_FAKE_CURL_LOG} or die "fake-curl: cannot open log: $!";
    print $log "CALL\n";
    print $log ($from_config{$_} ? "KARG" : "ARG") . " $args[$_]\n" for 0 .. $#args;
    for my $i (0 .. $#args - 1) {
        next unless $args[$i] eq '-H' && $args[$i + 1] =~ /\A@(.+)\z/s;
        my $file = $1;
        if (open my $h, '<', $file) {
            while (my $line = <$h>) {
                chomp $line;
                $line =~ s/\r\z//;
                print $log "HFILE $file $line\n";
            }
            close $h;
        } else {
            print $log "HFILE $file <unreadable>\n";
        }
    }
    close $log;
}

my %delay;
for my $pair (split ' ', $ENV{KP_FAKE_CURL_DELAY} // '') {
    my ($url, $sec) = $pair =~ /\A(.+)=(\d+(?:\.\d+)?)\z/ or unsupported("KP_FAKE_CURL_DELAY: $pair");
    $delay{$url} = $sec;
}

# 引数を、--next で区切った組に分ける。組ごとに、URL と -o と -w と -H を持つ
my $parallel = 0;
my @groups = ({ urls => [], outs => [], write => undef });
my %with_value = map { $_ => 1 } qw(-o -w -H -A --parallel-max --max-time);
my $pos = 0;
while (@args) {
    my $is_url = ($from_config{$pos} // '') eq 'url';
    my $arg = shift @args;
    $pos++;
    if ($is_url) {
        push @{ $groups[-1]{urls} }, $arg;
        next;
    }
    if ($arg eq '--next') {
        push @groups, { urls => [], outs => [], write => undef };
        next;
    }
    if ($arg eq '--parallel') { $parallel = 1; next }
    if ($arg eq '--compressed' || $arg eq '-s') { next }
    if ($with_value{$arg}) {
        unsupported("$arg needs a value") unless @args;
        my $v = shift @args;
        $pos++;
        if    ($arg eq '-o') { push @{ $groups[-1]{outs} }, $v }
        elsif ($arg eq '-w') { $groups[-1]{write} = $v }
        next;
    }
    unsupported("option $arg") if $arg =~ /\A-/;
    push @{ $groups[-1]{urls} }, $arg;
}

# 終える順に並べた要求の一覧を作る
my @reqs;
for my $g (@groups) {
    my @urls = @{ $g->{urls} };
    for my $i (0 .. $#urls) {
        push @reqs, { url => $urls[$i], out => $g->{outs}[$i], write => $g->{write}, seq => scalar @reqs };
    }
}
unsupported('no URL') unless @reqs;

sub sample_name {
    my ($url) = @_;
    (my $name = $url) =~ s/[^A-Za-z0-9]/_/g;
    return "$dir/$name";
}

sub expand_write {
    my ($fmt, $url, $code, $exit) = @_;
    my %v = (url_effective => $url, http_code => $code, response_code => $code, exitcode => $exit);
    $fmt =~ s/\\n/\n/g;
    $fmt =~ s/\\t/\t/g;
    $fmt =~ s/%\{(\w+)\}/exists $v{$1} ? $v{$1} : unsupported("-w %{$1}")/ge;
    return $fmt;
}

my $last_exit = 0;

sub finish {
    my ($r) = @_;
    my $base = sample_name($r->{url});
    my ($code, $body) = ('404', '');
    if (-e "$base.status") {
        open my $s, '<', "$base.status" or die "fake-curl: $base.status: $!";
        $code = do { local $/; <$s> };
        close $s;
        $code =~ s/\s+//g;
        if (-e "$base.body") {
            open my $b, '<:raw', "$base.body" or die "fake-curl: $base.body: $!";
            $body = do { local $/; <$b> };
            close $b;
        }
    }
    my $exit = 0;
    if ($code eq '000') {
        $exit = 7;
        $body = '';
    }
    if ($exit == 0) {
        if (defined $r->{out}) {
            open my $o, '>:raw', $r->{out} or die "fake-curl: cannot write $r->{out}: $!";
            print $o $body;
            close $o;
        } else {
            binmode STDOUT, ':raw';
            print $body;
        }
    }
    print expand_write($r->{write}, $r->{url}, $code, $exit) if defined $r->{write};
    $last_exit = $exit if $exit;
}

if ($parallel) {
    my @order = sort { ($delay{ $a->{url} } // 0) <=> ($delay{ $b->{url} } // 0) || $a->{seq} <=> $b->{seq} } @reqs;
    my $waited = 0;
    for my $r (@order) {
        my $d = $delay{ $r->{url} } // 0;
        if ($d > $waited) {
            sleep($d - $waited);
            $waited = $d;
        }
        finish($r);
    }
} else {
    for my $r (@reqs) {
        my $d = $delay{ $r->{url} } // 0;
        sleep($d) if $d > 0;
        finish($r);
    }
}
exit $last_exit;
__END__
__PERL__
exec perl -x "$0" "$@"
