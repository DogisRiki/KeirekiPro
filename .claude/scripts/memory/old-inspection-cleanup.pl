#!/usr/bin/perl
# =====================================================================
# 前の点検を片付けるスクリプト。点検のスキル(memory-inspect-now)の「手順1 前の点検の片付け」から呼ばれる。
# 前の点検の予定がこの PC に残っていれば外し、前の点検の状態の場所が残っていれば消す。
# メモリと会話の記録に触れず、前の点検の予定と状態の場所のほかを変えない
#
# 使い方: perl .claude/scripts/memory/old-inspection-cleanup.pl(引数を受けない)
#   {"schedule":..,"schedule_error":..,"manual_command":..,"state":..,"state_path":..,"state_error":..} の1行を出す。
#   schedule と state は removed・absent・failed のどれかである。manual_command は、schedule が failed のときだけ、
#   開発者が予定を外すために打つコマンドを入れる
# 予定の名前に付ける印: <git の共通ディレクトリ> の場所の SHA-256 の先頭8文字。前の点検の memory-inspect.pl の id8 と同じである
#   Windows: タスク スケジューラの「KeirekiPro memory inspection <印>」を、powershell.exe の -EncodedCommand で外す
#   macOS:   launchd の「com.keirekipro.memory-inspection.<印>」を launchctl bootout で外し、~/Library/LaunchAgents の plist を消す
#   Linux:   crontab の、末尾が「# keirekipro-memory-inspection <印>」の行を除いた中身を crontab - で書き戻す
# OS は perl の $^O で見分ける。テストは環境変数 KP_MEMORY_CLEANUP_OS で替える
# 前の点検の状態の場所: <git の共通ディレクトリ>/keirekipro-memory-inspection/。予定を外せなかったときも消す
# どのコマンドもシェルを通さずに引数の並びで動かし、60秒で打ち切る。再試行しない
# 終了コード: 予定か状態の場所を片付けられなかったときも JSON を出して 0、引数を渡されたら 2、
# git の共通ディレクトリを求められなかったら 1(標準エラーに理由を日本語の1文で出す)
# 前提: perl(JSON::PP・Digest::SHA)・git
# =====================================================================
use strict;
use warnings;
use Config;
use Digest::SHA qw(sha256_hex);
use Encode qw(decode encode);
use File::Basename qw(dirname);
use File::Path qw(remove_tree);
use File::Spec;
use File::Temp qw(tempfile);
use JSON::PP;
use MIME::Base64 qw(encode_base64);
use POSIX ();

require File::Spec->catfile(dirname(File::Spec->rel2abs(__FILE__)), 'memory-files.pl');

# 予定の仕組みのコマンドを打ち切るまでの秒の数
my $TIMEOUT_SEC = 60;
my %OS_OF = (msys => 'windows', cygwin => 'windows', MSWin32 => 'windows', darwin => 'macos', linux => 'linux');

exit main(@ARGV);

sub main {
    if (@_) {
        print STDERR "使い方: perl old-inspection-cleanup.pl(引数を受けない)\n";
        return 2;
    }
    my $common = eval { MemoryFiles::git_common_dir() };
    unless (defined $common) {
        (my $why = $@ // '') =~ s/\s+\z//;
        print STDERR "old-inspection-cleanup.pl: $why\n";
        return 1;
    }
    my $id = substr(sha256_hex($common), 0, 8);
    my $os = $OS_OF{ $ENV{KP_MEMORY_CLEANUP_OS} // $^O } // '';
    my ($schedule, $schedule_error, $manual) =
          $os eq 'windows' ? windows_schedule($id)
        : $os eq 'macos'   ? macos_schedule($id)
        : $os eq 'linux'   ? linux_schedule($id)
        :                    ('absent');
    # 予定を外せなかったときも、状態の場所を消す。残った予定は、状態の場所の中の起動用のプログラムを見つけられずに終わる
    my $state_path = "$common/keirekipro-memory-inspection";
    my ($state, $state_error) = remove_state($state_path);
    binmode STDOUT;
    print JSON::PP->new->utf8->canonical->encode({
        schedule       => $schedule,
        schedule_error => $schedule_error // '',
        manual_command => $schedule eq 'failed' ? $manual : '',
        state          => $state,
        state_path     => text($state_path),
        state_error    => $state_error // '',
    }), "\n";
    return 0;
}

# バイトの列を、出力のための文字の列に直す。UTF-8 として読めないバイトは置き換えの文字にする
sub text { return decode('UTF-8', $_[0] // ''); }

# PATH からコマンドを探し、見つかれば真を返す
sub find_cmd {
    my ($name) = @_;
    return scalar grep { $_ ne '' && -f "$_/$name" && -x _ } split /\Q$Config{path_sep}\E/, $ENV{PATH} // '';
}

# コマンドを、シェルを通さずに引数の並びで動かし、(終了コード, 標準出力, 標準エラー) を返す。
# 打ち切ったときと動かせなかったときの終了コードは undef である: run_cmd <標準入力に渡す文> <コマンド> <引数>...
sub run_cmd {
    my ($input, @cmd) = @_;
    my @names;
    for my $content ($input, '', '') {
        my ($fh, $name) = tempfile(UNLINK => 1);
        binmode $fh;
        print $fh $content;
        close $fh or return (undef, '', "一時のファイルを書けなかった($!)");
        push @names, $name;
    }
    my $pid = fork;
    return (undef, '', "コマンドを動かせなかった($!)") unless defined $pid;
    if (!$pid) {
        open(STDIN, '<', $names[0]) && open(STDOUT, '>', $names[1]) && open(STDERR, '>', $names[2]) && exec { $cmd[0] } @cmd;
        POSIX::_exit(127);
    }
    my $rc;
    my $done = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm $TIMEOUT_SEC;
        waitpid $pid, 0;
        alarm 0;
        $rc = $? >> 8;
        1;
    };
    unless ($done) {
        kill 'KILL', $pid;
        waitpid $pid, 0;
    }
    my @out;
    for my $name (@names[1, 2]) {
        my $f;
        push @out, open($f, '<:raw', $name) ? do { local $/; <$f> } // '' : '';
    }
    return ($done ? $rc : undef, @out);
}

# コマンドの失敗を、schedule_error に入れる1文にする。文はバイトの列で組み立ててから文字の列に直す:
# failure <コマンドの名前> <終了コード> <標準出力> <標準エラー>
sub failure {
    my ($what, $rc, $out, $err) = @_;
    my $said = join ' ', grep { /\S/ } $err, $out;
    $said =~ s/\s+/ /g;
    $said =~ s/\A | \z//g;
    return text("$what を${TIMEOUT_SEC}秒で打ち切った。") unless defined $rc;
    return text("$what が終了コード $rc で終わった。" . ($said ne '' ? "出力: $said" : ''));
}

# Windows のタスク スケジューラから、前の点検の予定を外す。予定があれば外して removed を、無ければ absent を返す
sub windows_schedule {
    my ($id) = @_;
    my $name = "'KeirekiPro memory inspection $id'";
    my $manual = "Unregister-ScheduledTask -TaskName $name -Confirm:\$false";
    return ('failed', text('powershell.exe が見つからなかった。'), $manual) unless find_cmd('powershell.exe');
    # 前の点検の windows-task disable と同じく、命令の文を UTF-16LE の Base64 にして -EncodedCommand で渡す
    my $script = join "\n", "\$ErrorActionPreference = 'Stop'", "\$ProgressPreference = 'SilentlyContinue'", 'try {',
        "if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {",
        $manual, "'removed'", '} else {', "'absent'", '}',
        '} catch {', '[Console]::Error.WriteLine($_.Exception.Message)', 'exit 1', '}', '';
    my ($rc, $out, $err) = run_cmd('', 'powershell.exe', '-NoProfile', '-NonInteractive', '-EncodedCommand',
        encode_base64(encode('UTF-16LE', $script), ''));
    if (defined $rc && $rc == 0) {
        return ('removed') if $out =~ /^removed\r?$/m;
        return ('absent')  if $out =~ /^absent\r?$/m;
    }
    return ('failed', failure('powershell.exe', $rc, $out, $err), $manual);
}

# macOS の launchd から前の点検の予定を外し、plist を消す。どちらかがあれば外して removed を、どちらも無ければ absent を返す
sub macos_schedule {
    my ($id) = @_;
    my $label = "com.keirekipro.memory-inspection.$id";
    my $plist = defined $ENV{HOME} && $ENV{HOME} ne '' ? "$ENV{HOME}/Library/LaunchAgents/$label.plist" : undef;
    my $manual = "launchctl bootout gui/\$(id -u)/$label; rm -f ~/Library/LaunchAgents/$label.plist";
    my $service = "gui/$</$label";
    my $loaded = 0;
    if (find_cmd('launchctl')) {
        my ($rc) = run_cmd('', 'launchctl', 'print', $service);
        $loaded = defined $rc && $rc == 0;
    }
    return ('absent') unless $loaded || (defined $plist && -e $plist);
    if ($loaded) {
        my ($rc, $out, $err) = run_cmd('', 'launchctl', 'bootout', $service);
        return ('failed', failure('launchctl bootout', $rc, $out, $err), $manual) unless defined $rc && $rc == 0;
    }
    return ('failed', text("$plist を消せなかった($!)。"), $manual) if defined $plist && -e $plist && !unlink $plist;
    return ('removed');
}

# Linux の crontab から、前の点検の印の付いた行だけを消す。印の付いた行があれば消して removed を、無ければ absent を返す。
# crontab が無いときと、crontab -l が「no crontab」を出したときは、予定が無いとみなす
sub linux_schedule {
    my ($id) = @_;
    my $mark = "# keirekipro-memory-inspection $id";
    my $manual = "crontab -l | grep -v 'keirekipro-memory-inspection $id' | crontab -";
    return ('absent') unless find_cmd('crontab');
    my ($rc, $out, $err) = run_cmd('', 'crontab', '-l');
    if (!defined $rc || $rc != 0) {
        return ('absent') if defined $rc && $err =~ /no crontab/i;
        return ('failed', failure('crontab -l', $rc, $out, $err), $manual);
    }
    my @lines = split /\n/, $out;
    my @kept = grep { !/\Q$mark\E\s*\z/ } @lines;
    return ('absent') if @kept == @lines;
    ($rc, $out, $err) = run_cmd(join('', map { "$_\n" } @kept), 'crontab', '-');
    return ('failed', failure('crontab -', $rc, $out, $err), $manual) unless defined $rc && $rc == 0;
    return ('removed');
}

# 前の点検の状態の場所を消す。あれば消して removed を、無ければ absent を、消せなければ failed と理由を返す
sub remove_state {
    my ($path) = @_;
    return ('absent') unless -e $path || -l $path;
    remove_tree($path, { error => \my $errors });
    return ('removed') unless -e $path || -l $path;
    my @why = map { my ($file, $msg) = %$_; $file eq '' ? $msg : "$file: $msg" } @$errors;
    return ('failed', text(join('; ', @why) || "$path を消せなかった。"));
}
