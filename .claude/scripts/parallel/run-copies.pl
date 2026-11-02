#!/usr/bin/perl
# =====================================================================
# コードを壊した写しのテストを、写しごとに時間の上限を付けて同時に流すスクリプト(run-copies.pl)
#
# 使い方: perl .claude/scripts/parallel/run-copies.pl [--timeout <秒>] <一覧のファイル> <記録のフォルダ>
#   <一覧のファイル> 1行に1つの写しを「<名前><タブ><写しのフォルダ><タブ><コマンド>」で書く。
#                    空行と # で始まる行は読み飛ばす。写しは10個まで
#   <記録のフォルダ> 写しごとの出力 <名前>.log と、進み具合 progress.txt を書く。無ければ作る
#   --timeout        写しごとの時間の上限(秒)。既定300、最大540
# 写しのフォルダに移って、コマンドを bash -c で動かす。標準入力は /dev/null にする
# (Issue #465 では、標準入力を待つコマンドが止まり、約2時間待ち続けた)。
# 上限に達した写しは、写しのプロセスの組を止め、子と孫のプロセスまで止める
# (Windows の Git Bash でも、cmd /c から動かした孫のプロセスまで止まることを確かめた)。
# 写しは全部を同時に流すので、全体も上限と止めるまでの数秒で終わる。前面の Bash の10分の上限に収まる。
#
# 標準出力: 写しごとに「<名前> rc=<終了コード> <秒>s」か「<名前> 打ち切り <秒>s」を1行ずつ。
# 終了コード: 0(全部の写しが上限の前に終わった。写しの終了コードは問わない)、
#             75(上限で打ち切った写しがある)、64(呼び方の誤り)、69(記録のフォルダを用意できなかった)。
# 前提: perl(POSIX)・bash。
# =====================================================================
use strict;
use warnings;
use POSIX ();

my $MAX_COPIES  = 10;
my $MAX_TIMEOUT = 540;
my $KILL_AFTER  = 2;

sub usage {
    print STDERR "使い方: perl run-copies.pl [--timeout <秒>] <一覧のファイル> <記録のフォルダ>\n";
    print STDERR "run-copies.pl: $_[0]\n" if @_;
    exit 64;
}

my $timeout = 300;
if (@ARGV && $ARGV[0] eq '--timeout') {
    shift @ARGV;
    $timeout = shift @ARGV;
    usage("--timeout には1から${MAX_TIMEOUT}までの秒を書く")
        unless defined $timeout && $timeout =~ /\A[1-9]\d*\z/ && $timeout <= $MAX_TIMEOUT;
}
usage() unless @ARGV == 2;
my ($list, $logdir) = @ARGV;

open my $in, '<', $list or usage("一覧のファイル $list を読めなかった($!)");
my (@copies, %seen);
while (my $line = <$in>) {
    $line =~ s/\r?\n\z//;
    next if $line =~ /\A\s*(?:#|\z)/;
    my ($name, $dir, $cmd) = split /\t/, $line, 3;
    usage("$. 行目は「<名前><タブ><写しのフォルダ><タブ><コマンド>」の形でない")
        unless defined $cmd && $cmd ne '' && $name =~ /\A[A-Za-z0-9._-]+\z/;
    usage("$. 行目の名前 $name が重なっている") if $seen{$name}++;
    usage("$. 行目の写しのフォルダ $dir が無い") unless -d $dir;
    push @copies, { name => $name, dir => $dir, cmd => $cmd };
}
close $in;
usage("一覧のファイルに写しが無い") unless @copies;
usage("写しは${MAX_COPIES}個までにする(" . scalar(@copies) . "個ある)") if @copies > $MAX_COPIES;

unless (-d $logdir || mkdir $logdir) {
    print STDERR "run-copies.pl: 記録のフォルダ $logdir を作れなかった($!)\n";
    exit 69;
}
open my $progress, '>>', "$logdir/progress.txt" or do {
    print STDERR "run-copies.pl: $logdir/progress.txt に書けなかった($!)\n";
    exit 69;
};
$progress->autoflush(1);

sub clock { POSIX::strftime('%H:%M:%S', localtime) }

for my $c (@copies) {
    my $pid = fork;
    die "run-copies.pl: 写し $c->{name} を動かせなかった($!)\n" unless defined $pid;
    if (!$pid) {
        setpgrp(0, 0);
        open STDIN, '<', '/dev/null';
        open STDOUT, '>', "$logdir/$c->{name}.log";
        open STDERR, '>&', \*STDOUT;
        chdir $c->{dir} or do { print STDERR "フォルダ $c->{dir} に移れなかった($!)\n"; POSIX::_exit(127) };
        { no warnings 'exec'; exec 'bash', '-c', $c->{cmd}; }
        POSIX::_exit(127);
    }
    # 子が組を作る前に止めることがあるので、親からも組を作る
    setpgrp($pid, $pid);
    @$c{qw(pid start)} = ($pid, time);
    print $progress "$c->{name} 開始 " . clock() . " 上限 ${timeout}s\n";
}

my $timed_out = 0;
my @running = @copies;
while (@running) {
    my @left;
    for my $c (@running) {
        my $w = waitpid $c->{pid}, POSIX::WNOHANG();
        my $sec = time - $c->{start};
        if ($w == $c->{pid} || $w < 0) {
            my $st = $w < 0 ? 0 : $?;
            $c->{result} = sprintf 'rc=%d %ds', ($st & 127 ? 128 + ($st & 127) : $st >> 8), $sec;
        } elsif ($sec >= $timeout) {
            kill 'TERM', -$c->{pid};
            my $end = time + $KILL_AFTER;
            select(undef, undef, undef, 0.1) while waitpid($c->{pid}, POSIX::WNOHANG()) == 0 && time < $end;
            kill 'KILL', -$c->{pid};
            waitpid $c->{pid}, 0;
            $c->{result} = "打ち切り ${sec}s";
            $timed_out = 1;
        } else {
            push @left, $c;
            next;
        }
        print $progress "$c->{name} 終了 " . clock() . " $c->{result}\n";
    }
    @running = @left;
    select(undef, undef, undef, 0.2) if @running;
}
close $progress;

print "$_->{name} $_->{result}\n" for @copies;
exit($timed_out ? 75 : 0);
