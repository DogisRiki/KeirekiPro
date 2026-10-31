#!/usr/bin/perl
# =====================================================================
# 点検の状態のファイルを読み書きするスクリプト。memory-inspect.sh から呼ばれる
#
# 使い方: perl .claude/scripts/memory/memory-inspect.pl <サブコマンド> [引数]
#   paths [<フォルダ>]
#     フォルダ(省略したときはこのスクリプトのフォルダ)を含むリポジトリの、本体の作業フォルダと、
#     点検の状態の場所と、メモリのディレクトリを、この順に1行ずつ出す。どれも作らない
#   tools <claude の場所> <gh の場所> <bash の場所> <PATH>
#     {"bin":{"bash":..,"claude":..,"gh":..},"path":..} の1行を出す。見つからないコマンドの場所は空の文字列で受ける
#   lock take <run|memory> <回の ID> <プロセスの番号>
#     点検のロック locks/run/ か、メモリのロック locks/memory を取る。取れたら taken を出して 0 を返す。
#     ほかの回が取っていて古くなければ、held <取っている回の ID> を出して 3 を返す。古いロックは外してから取り直す
#   lock release <run|memory> <回の ID>
#     その回が取っているロックを外す。ほかの回のロックと、取られていないロックには何もしない
#   lock state <run|memory>
#     ロックの今の様子を、free か held <回の ID> か stale <回の ID> の1行で出す
# 終了コード: 成功は 0、使い方の誤りは 2、失敗は 1(標準エラーに理由を日本語の1文で出す)
# 前提: perl(JSON::PP)・git。Windows では、git に渡す場所を C:/... の形で受ける
# =====================================================================
use strict;
use warnings;
use Encode qw(decode);
use Errno qw(EEXIST EPERM);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use POSIX qw(strftime);
use JSON::PP;
use Time::Local qw(timegm);

my %COMMANDS = (
    paths => \&cmd_paths,
    tools => \&cmd_tools,
    lock  => \&cmd_lock,
);

my $JSON = JSON::PP->new->utf8->canonical;

# ロックの種類と、点検の状態の場所の locks/ の下の名前
my %LOCKS = (run => q{run}, memory => q{memory});

# テストが do で読み込んだときは、呼び出しを動かさない
exit main(@ARGV) unless caller;

sub main {
    my ($cmd, @args) = @_;
    my $run = defined $cmd ? $COMMANDS{$cmd} : undef;
    return usage() unless $run;
    return guarded($run, @args);
}

# 呼び出しを動かし、die したら標準エラーに理由を1行で残して 1 を返す
sub guarded {
    my ($run, @args) = @_;
    my $rc = eval { $run->(@args) };
    return $rc if defined $rc;
    (my $why = $@ // '') =~ s/\s+/ /g;
    $why =~ s/ \z//;
    print STDERR "memory-inspect.pl: $why\n";
    return 1;
}

sub usage {
    print STDERR "使い方: perl memory-inspect.pl paths [<フォルダ>] | tools <claude の場所> <gh の場所> <bash の場所> <PATH> | lock take|release|state <run|memory> [<回の ID> [<プロセスの番号>]]\n";
    return 2;
}

# ---- 場所 ----------------------------------------------------------------

# フォルダを含むリポジトリの git の共通ディレクトリを返す。worktree の中のフォルダからも、本体と同じ場所を返す
sub git_common_dir {
    my ($dir) = @_;
    open(my $saved, '>&', \*STDERR) or die "標準エラーを控えられなかった($!)\n";
    open(STDERR, '>', File::Spec->devnull) or die "標準エラーを閉じられなかった($!)\n";
    my $ok = open(my $g, '-|', 'git', '-C', $dir, 'rev-parse', '--path-format=absolute', '--git-common-dir');
    my $out = $ok ? do { local $/; <$g> } : undef;
    my $closed = $ok ? close($g) : 0;
    open(STDERR, '>&', $saved) or die "標準エラーを戻せなかった($!)\n";
    die "$dir を含む git のリポジトリの共通ディレクトリを求められなかった\n" unless $closed && defined $out;
    $out =~ s/\r?\n\z//;
    die "$dir を含む git のリポジトリの共通ディレクトリを求められなかった\n" unless $out =~ /\S/ && $out !~ /\n/;
    return $out;
}

# 本体の作業フォルダを、git の共通ディレクトリの親のフォルダとして返す
sub main_worktree {
    my ($dir) = @_;
    return dirname(git_common_dir($dir));
}

# 点検の状態の場所 <git の共通ディレクトリ>/keirekipro-memory-inspection を返す。作らない
sub state_dir {
    my ($dir) = @_;
    return git_common_dir($dir) . '/keirekipro-memory-inspection';
}

# このリポジトリのメモリのディレクトリ ~/.claude/projects/<名前>/memory を返す。<名前> は、本体の作業フォルダの場所の
# 英数字でない文字を1文字ずつ - に替えたものである。Claude Code がプロジェクトのディレクトリの名前を作る決まりである
sub memory_dir {
    my ($main) = @_;
    my $home = $ENV{HOME};
    die "HOME が無いので、メモリのディレクトリを求められなかった\n" unless defined $home && $home ne '';
    (my $name = decode('UTF-8', $main)) =~ s/[^A-Za-z0-9]/-/g;
    $home =~ s{/+\z}{};
    return "$home/.claude/projects/$name/memory";
}

# ---- 時刻 ----------------------------------------------------------------

# ISO 8601 の時刻を、1970年からの秒に直す。時刻の帯(Z か +09:00 の形)の無い時刻は読まない。読めなければ undef を返す
sub epoch {
    my ($t) = @_;
    return undef unless defined $t && !ref $t;
    my ($y, $mo, $d, $h, $mi, $se, $frac, $zone, $sign, $zh, $zm)
        = $t =~ /\A(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(\.\d+)?(Z|([+-])(\d\d):?(\d\d))\z/ or return undef;
    my $s = eval { timegm($se, $mi, $h, $d, $mo - 1, $y) };
    return undef unless defined $s;
    $s += $frac if defined $frac;
    $s -= ($sign eq '+' ? 1 : -1) * ($zh * 3600 + $zm * 60) if defined $sign;
    return $s;
}

# 今の時刻を、1970年からの秒で返す。テストは KP_MEMORY_INSPECTION_NOW で今の時刻を与える
sub now {
    my $t = $ENV{KP_MEMORY_INSPECTION_NOW};
    return time() unless defined $t && $t ne '';
    my $s = epoch($t);
    die "KP_MEMORY_INSPECTION_NOW の時刻 $t を読めなかった\n" unless defined $s;
    return int $s;
}

sub iso_utc { return strftime('%Y-%m-%dT%H:%M:%SZ', gmtime $_[0]); }

# design の待つ時間と上限を秒で返す。テストは環境変数で短くする: limit_sec <環境変数の名前> <design の秒>
sub limit_sec {
    my ($name, $sec) = @_;
    my $v = $ENV{$name};
    return defined $v && $v =~ /\A\d+\z/ ? $v : $sec;
}

# ---- ロック --------------------------------------------------------------
# 点検のロック locks/run/ とメモリのロック locks/memory は、mkdir で取り、取った回が中にファイル owner を置く。
# owner は {"pid":<プロセスの番号>,"run":<回の ID>,"taken_at":<取った時刻>} である。古いロックの見分けは、
# run と run-now と後始末の部品のどれも lock_status を使う


# ロックのディレクトリの場所を返す: lock_dir <点検の状態の場所> <run|memory>
sub lock_dir {
    my ($state, $kind) = @_;
    die "知らないロック $kind を受けた\n" unless defined $kind && $LOCKS{$kind};
    return "$state/locks/$LOCKS{$kind}";
}

# owner を読む。無いか読めなければ undef を返す
sub lock_owner {
    my ($dir) = @_;
    open(my $fh, '<:raw', "$dir/owner") or return undef;
    my $text = do { local $/; <$fh> };
    close $fh;
    my $o = eval { $JSON->decode($text) };
    return ref $o eq 'HASH' && defined $o->{run} && !ref $o->{run} ? $o : undef;
}

# プロセスがあるかを返す。Windows(Git Bash の /proc/<番号>/winpid がある)では、番号を Windows のプロセスの番号として
# tasklist.exe で見分ける。点検は別の Git Bash から起動されることがあるためである。見分けられないときは、あるとみなす
sub pid_alive {
    my ($pid) = @_;
    return 0 unless defined $pid && $pid =~ /\A[1-9]\d*\z/;
    if (-r "/proc/$$/winpid") {
        # Git Bash の引数の書き換えで /FI が場所に替わらないようにする
        local $ENV{MSYS2_ARG_CONV_EXCL} = '*';
        open(my $saved, '>&', \*STDERR) or return 1;
        open(STDERR, '>', File::Spec->devnull) or return 1;
        my $ok = open(my $t, '-|', 'tasklist.exe', '/FI', "PID eq $pid", '/NH', '/FO', 'CSV');
        my $out = $ok ? do { local $/; <$t> } : undef;
        close $t if $ok;
        open(STDERR, '>&', $saved) or return 1;
        return 1 unless defined $out;
        return index($out, qq{"$pid"}) >= 0 ? 1 : 0;
    }
    return 1 if kill 0, $pid;
    return $! == EPERM ? 1 : 0;
}

# ロックの今の様子を返す: (free|held|stale, owner か undef)。
# owner のプロセスが無いか、取った時刻から90分を過ぎたロックは古い。owner が無いか読めないロックは、
# ディレクトリの更新の時刻から1分以内ならほかの回が取ったばかりのロックとみなし、1分を過ぎていれば古いとみなす
sub lock_status {
    my ($dir) = @_;
    return ('free', undef) unless -d $dir;
    my $now = now();
    my $o = lock_owner($dir);
    unless ($o) {
        my $mtime = (stat $dir)[9];
        return ('free', undef) unless defined $mtime;
        return ($now - $mtime > limit_sec('KP_MEMORY_INSPECTION_OWNERLESS_SEC', 60) ? 'stale' : 'held', undef);
    }
    my $at = epoch($o->{taken_at});
    return ('stale', $o) unless defined $at && $now - $at <= limit_sec('KP_MEMORY_INSPECTION_STALE_SEC', 90 * 60);
    return ('stale', $o) unless pid_alive($o->{pid});
    return ('held', $o);
}

# 古いロックを外す。外す直前に owner を読み直し、見分けたときと同じときだけ外す。
# ほかの回が先に外して取り直したロックを外さないためである
sub lock_remove_stale {
    my ($dir, $seen) = @_;
    my $now_owner = lock_owner($dir);
    my $same = defined $seen ? defined $now_owner && $JSON->encode($now_owner) eq $JSON->encode($seen) : !defined $now_owner;
    return unless $same;
    unlink "$dir/owner";
    rmdir $dir;
}

# ロックを取る。取れたら (1)、ほかの回が取っていれば (0, owner か undef) を返す: lock_take <ディレクトリ> <回の ID> <プロセスの番号>
sub lock_take {
    my ($dir, $run, $pid) = @_;
    make_path(dirname($dir));
    for my $try (1 .. 2) {
        if (mkdir $dir) {
            my $tmp = "$dir/owner.$$.tmp";
            open(my $fh, '>:raw', $tmp) or die "ロックの owner を書けなかった($!)\n";
            print {$fh} $JSON->encode({ pid => 0 + $pid, run => $run, taken_at => iso_utc(now()) }), "\n";
            close $fh or die "ロックの owner を書けなかった($!)\n";
            rename $tmp, "$dir/owner" or die "ロックの owner を書けなかった($!)\n";
            return (1);
        }
        die "ロック $dir を取れなかった($!)\n" unless $! == EEXIST;
        my ($state, $o) = lock_status($dir);
        return (0, $o) unless $state eq 'stale' && $try == 1;
        lock_remove_stale($dir, $o);
    }
    return (0, lock_owner($dir));
}

# その回が取っているロックを外す: lock_release <ディレクトリ> <回の ID>
sub lock_release {
    my ($dir, $run) = @_;
    my $o = lock_owner($dir);
    return unless $o && $o->{run} eq $run;
    unlink "$dir/owner";
    rmdir $dir;
}

# ---- サブコマンド ----------------------------------------------------------

sub cmd_paths {
    my @args = @_;
    return usage() if @args > 1;
    my $dir = @args ? $args[0] : dirname(__FILE__);
    my $main = main_worktree($dir);
    print "$main\n", state_dir($dir), "\n", memory_dir($main), "\n";
    return 0;
}

sub cmd_tools {
    my @args = @_;
    return usage() unless @args == 4;
    my ($claude, $gh, $bash, $path) = map { decode('UTF-8', $_) } @args;
    print $JSON->encode({ bin => { claude => $claude, gh => $gh, bash => $bash }, path => $path }), "\n";
    return 0;
}

sub cmd_lock {
    my ($op, $kind, @args) = @_;
    return usage() unless defined $op && defined $kind && $LOCKS{$kind};
    my %need = (take => 2, release => 1, state => 0);
    return usage() unless defined $need{$op} && @args == $need{$op};
    my ($run, $pid) = @args;
    return usage() if defined $run && $run !~ /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/;
    return usage() if defined $pid && $pid !~ /\A[1-9]\d*\z/;
    my $dir = lock_dir(state_dir(dirname(__FILE__)), $kind);
    if ($op eq 'state') {
        my ($state, $o) = lock_status($dir);
        print $state eq 'free' ? "free\n" : "$state " . ($o ? $o->{run} : '') . "\n";
        return 0;
    }
    if ($op eq 'release') {
        lock_release($dir, $run);
        return 0;
    }
    my ($taken, $o) = lock_take($dir, $run, $pid);
    if ($taken) {
        print "taken\n";
        return 0;
    }
    print 'held ', ($o ? $o->{run} : ''), "\n";
    return 3;
}
