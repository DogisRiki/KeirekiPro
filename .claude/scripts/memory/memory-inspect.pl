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
#   prepare <回の ID> <scheduled|now>
#     メモリを読み、記録 runs/<回の ID>/record.json を状態 running で書き、比べる材料の JSON を標準出力に1行で出す。
#     メモリを書き換えない。メモリのディレクトリが無いときは、点検したメモリファイルを0とする。
#     比べる元 snapshot.json があれば、書き換わったファイルを会話の記録と照らし、記録に無い書き換えを汚染の種類11として記録に書く
#     材料には、まだメモリに残る戻された直しと、決まりの見直しの案を書いてよい種類と、断られた移す先の案と、案をまだ作っていない見落としも入れる
#   content
#     目次とメモリファイルを1つずつ <<<MEMORY-FILE name="<ファイル名>">>> と <<<END-MEMORY-FILE>>> で囲み、
#     行ごとに「<行番号>| <行>」の形で標準出力に出す。前の点検のあとに足された行は、行番号の前に + を付ける。ファイルに書かない
#   lookup <回の ID> <最初の番号>
#     点検の中の Claude が返した調べてほしいことの JSON の配列を標準入力で受け、その回の記録の origin_main のコミットと
#     GitHub と会話の記録で調べ、結果を1件ずつ <<<LOOKUP-RESULT id="<番号>">>> と <<<END-LOOKUP-RESULT>>> で囲んで標準出力に出す。
#     番号は最初の番号から振る。結果の行の頭には | を付ける。コマンドはシェルを通さずに動かし、作業フォルダと git の参照を書き換えない
#   apply <回の ID>
#     点検の中の Claude が返した直し方の JSON(plan-schema.json の形)を標準入力で受け、prepare が記録に書いた汚染に続けて、
#     汚染に F、直しに C、移す先の案に R、決まりの見直しの案に K、点検のやり方の見直しの案に M の番号を振る。
#     直しを1つずつ確かめ、行わない直しは状態を skipped にして理由を記録に書く。読んだあとに書き換わったファイルを skipped_files に書く
# 終了コード: 成功は 0、使い方の誤りは 2、失敗は 1(標準エラーに理由を日本語の1文で出す)
# 前提: perl(JSON::PP)・git。Windows では、git に渡す場所を C:/... の形で受ける
# =====================================================================
use strict;
use warnings;
use Encode qw(decode encode);
use Digest::SHA qw(sha256_hex);
use Errno qw(EEXIST EPERM);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use POSIX qw(strftime);
use JSON::PP;
use Time::Local qw(timegm);

my %COMMANDS = (
    paths   => \&cmd_paths,
    tools   => \&cmd_tools,
    lock    => \&cmd_lock,
    prepare => \&cmd_prepare,
    content => \&cmd_content,
    lookup  => \&cmd_lookup,
    apply   => \&cmd_apply,
);

my $JSON = JSON::PP->new->utf8->canonical;

# ロックの種類と、点検の状態の場所の locks/ の下の名前
my %LOCKS = (run => q{run}, memory => q{memory});

# 目次のファイルの名前と、目次の行の数と大きさの上限。Claude Code が会話の始めに読む上限の200行と25KBの8割である
my $INDEX = q{MEMORY.md};
my %INDEX_LIMIT = (lines => 160, bytes => 20480);

# 会話を通らない書き換え(汚染の種類11)を直さない理由
my $REWRITE_REASON = q{書き換えられたことだけでは直さない。中身はほかの種類について点検した};

# 事実の調べの上限。1回の呼び出しの件数と、1件の結果のバイトの数と、結果の合計のバイトの数である
my %LOOKUP_LIMIT = (count => 40, item => 20480, total => 204800);
my $OVER_LIMIT = q{上限を超えたので調べなかった};

# 直し方の確認で、直しを行わなかった理由
my %SKIP = (
    not_fix       => q{汚染の扱いが fix でない},
    kind          => q{置き場所の誤りと、会話を通らない書き換えは、点検の中で直さない},
    shape         => q{直し方の形が違う},
    name          => q{対象がメモリのディレクトリの最上位の .md でない},
    index_delete  => q{目次は消さない},
    missing       => q{対象のファイルが無い},
    rewritten     => q{点検の間に書き換えられたので、次の点検で点検する},
    excerpt       => q{汚染の記述がメモリファイルにそのまま無い},
    old_count     => q{old がメモリファイルにちょうど1回現れない},
    whole         => q{old が本文の全体に当たる。ファイルの全体を消すときは delete を使う},
    reverted      => q{戻された直しの文に重なる},
    reverted_file => q{戻されてから中身が変わっていないメモリファイルは消さない},
);
# 案の汚染の番号が、直し方の汚染の数を超えたときに、記録の notes に書く文
my %NOTE_OUT_OF_RANGE = (
    relocation => q{移す先の案の汚染の番号 %s が直し方の汚染の数を超えたので、案を載せなかった},
    inspection => q{点検のやり方の見直しの案の汚染の番号 %s が直し方の汚染の数を超えたので、案を載せなかった},
);

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
    print STDERR "使い方: perl memory-inspect.pl paths [<フォルダ>] | tools <claude の場所> <gh の場所> <bash の場所> <PATH> | lock take|release|state <run|memory> [<回の ID> [<プロセスの番号>]] | prepare <回の ID> <scheduled|now> | content | lookup <回の ID> <最初の番号> | apply <回の ID>\n";
    return 2;
}

# ---- 場所 ----------------------------------------------------------------

# git をシェルを通さずに動かし、標準出力の1行を返す。失敗したときと、出力が1行でないときは undef を返す: git_line <フォルダ> <引数>...
sub git_line {
    my ($dir, @args) = @_;
    open(my $saved, '>&', \*STDERR) or die "標準エラーを控えられなかった($!)\n";
    open(STDERR, '>', File::Spec->devnull) or die "標準エラーを閉じられなかった($!)\n";
    my $ok = open(my $g, '-|', 'git', '-C', $dir, @args);
    my $out = $ok ? do { local $/; <$g> } : undef;
    my $closed = $ok ? close($g) : 0;
    open(STDERR, '>&', $saved) or die "標準エラーを戻せなかった($!)\n";
    return undef unless $closed && defined $out;
    $out =~ s/\r?\n\z//;
    return $out =~ /\S/ && $out !~ /\n/ ? $out : undef;
}

# フォルダを含むリポジトリの git の共通ディレクトリを返す。worktree の中のフォルダからも、本体と同じ場所を返す
sub git_common_dir {
    my ($dir) = @_;
    my $out = git_line($dir, 'rev-parse', '--path-format=absolute', '--git-common-dir');
    die "$dir を含む git のリポジトリの共通ディレクトリを求められなかった\n" unless defined $out;
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
    # 名前は英数字と - だけになるので、バイトの列に戻す。ファイルの名前のバイトの列とつないでも、名前が化けないためである
    (my $name = decode(q{UTF-8}, $main)) =~ s/[^A-Za-z0-9]/-/g;
    utf8::downgrade($name);
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

# ---- ファイル ------------------------------------------------------------

# ファイルの中身をバイトの列で返す。無いか読めなければ undef を返す
sub read_bytes {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or return undef;
    my $text = do { local $/; <$fh> };
    close $fh;
    return defined $text ? $text : '';
}

# JSON のファイルを読む。無ければ undef を返し、読めなければ die する
sub read_json {
    my ($path) = @_;
    my $text = read_bytes($path);
    return undef unless defined $text;
    my $data = eval { $JSON->decode($text) };
    die "$path を JSON として読めなかった\n" unless defined $data;
    return $data;
}

# JSON のファイルを、一時のファイルに書いてから名前を替えて書く。読む側が書きかけのファイルを読まないためである
sub write_json {
    my ($path, $data) = @_;
    my $tmp = "$path.$$.tmp";
    open(my $fh, '>:raw', $tmp) or die "$path を書けなかった($!)\n";
    print {$fh} $JSON->encode($data), "\n";
    close $fh or die "$path を書けなかった($!)\n";
    rename $tmp, $path or die "$path を書けなかった($!)\n";
}

# ---- メモリ --------------------------------------------------------------

# メモリのディレクトリの最上位の *.md の名前を、バイトの列で並べて返す。ディレクトリが無ければ空を返す
sub memory_files {
    my ($memdir) = @_;
    return () unless -d $memdir;
    opendir(my $dh, $memdir) or die "メモリのディレクトリ $memdir を読めなかった($!)\n";
    my @names = sort grep { /\.md\z/ && -f "$memdir/$_" } readdir $dh;
    closedir $dh;
    return @names;
}

# 目次の中身から、frontmatter と HTML の注記を除いた本文を返す。行の全体が注記の行は、行ごと除く
sub index_body {
    my ($text) = @_;
    $text =~ s/\A---[ \t]*\r?\n.*?^---[ \t]*\r?(?:\n|\z)//ms;
    $text =~ s/^[ \t]*<!--(?:(?!-->).)*-->[ \t]*\r?(?:\n|\z)//gms;
    $text =~ s/<!--.*?-->//gs;
    return $text;
}

# 本文の行の数を返す。最後の行が改行で終わらなくても1行と数える
sub line_count {
    my ($text) = @_;
    my $n = () = $text =~ /\n/g;
    $n++ if length $text && $text !~ /\n\z/;
    return $n;
}

# 目次の本文のリンクが指すメモリファイルの名前を、重ねずに返す
sub index_links {
    my ($body) = @_;
    my (%seen, @names);
    while ($body =~ /\]\(\s*<?([^)<>\s]+?)>?\s*\)/g) {
        (my $name = $1) =~ s/#.*\z//;
        $name =~ s{\A\./}{};
        next if $name !~ /\.md\z/ || $name =~ m{://};
        push @names, $name unless $seen{$name}++;
    }
    return @names;
}

# ファイルの中身を行に分ける。行の終わりの改行と、その前の \r を除く
sub split_lines {
    my ($text) = @_;
    my @lines = split /\n/, $text, -1;
    pop @lines if @lines && $lines[-1] eq '';
    s/\r\z// for @lines;
    return @lines;
}

# 比べる元 snapshot.json に書く、1つのファイルの中身のハッシュと、空でない行ごとのハッシュを返す。
# 比べる元を書く部品は、この形で書く
sub snapshot_entry {
    my ($text) = @_;
    return { sha256 => sha256_hex($text), lines => [ map { sha256_hex($_) } grep { /\S/ } split_lines($text) ] };
}

# 比べる元を読む。無ければ undef を返す。files の名前は、メモリのディレクトリを読んだ名前と比べられるようにバイトの列にする
sub read_snapshot {
    my ($state) = @_;
    my $snap = read_json("$state/snapshot.json");
    return undef unless defined $snap;
    die "比べる元 snapshot.json の形が違う\n"
        unless ref $snap eq 'HASH' && ref $snap->{files} eq 'HASH' && defined $snap->{taken_at} && !ref $snap->{taken_at};
    my %files = map { (encode('UTF-8', $_) => $snap->{files}{$_}) } keys %{ $snap->{files} };
    return { %$snap, files => \%files };
}

# 前の点検のあとに足された行の番号(1から数える)を、番号 => 1 の表で返す。空の行は足された行にしない。
# 比べる元の同じファイルにある同じ行は、ある数だけ、足されていない行とみなす。比べる元に無いファイルは、空でない行をすべて足された行とする
sub added_line_numbers {
    my ($text, $old) = @_;
    my %left;
    $left{$_}++ for ref $old eq 'HASH' && ref $old->{lines} eq 'ARRAY' ? @{ $old->{lines} } : ();
    my %added;
    my $n = 0;
    for my $line (split_lines($text)) {
        $n++;
        next unless $line =~ /\S/;
        my $h = sha256_hex($line);
        if ($left{$h}) {
            $left{$h}--;
            next;
        }
        $added{$n} = 1;
    }
    return \%added;
}

# 書き換わったファイルごとに、時刻のあとの会話の記録に書き込みの呼び出しがあったかを、名前(バイトの列)=> 真偽の表で返す
sub conversation_writes {
    my ($here, $since, $memdir, @names) = @_;
    my @cmd = ($^X, "$here/transcript-scan.pl", 'writes', '--since', $since, '--memory-dir', $memdir, @names);
    open(my $fh, '-|', @cmd) or die "会話の記録を読む部品を動かせなかった($!)\n";
    my $out = do { local $/; <$fh> };
    close $fh or die "会話の記録を読む部品が失敗した\n";
    my $found = eval { $JSON->decode($out // '') };
    die "会話の記録を読む部品の結果を読めなかった\n" unless ref $found eq 'HASH';
    return { map { (encode('UTF-8', $_) => ($found->{$_} ? 1 : 0)) } keys %$found };
}

# 記録の中のメモリファイルの名前を、メモリのディレクトリの最上位の *.md を指すときだけ、バイトの列で返す
sub memory_name {
    my ($name) = @_;
    return undef unless defined $name && !ref $name;
    my $bytes = encode('UTF-8', $name);
    return $bytes =~ m{\A[^/\\.][^/\\]*\.md\z} ? $bytes : undef;
}

# 空白の続きを1つの空白にそろえる。fingerprint を求めるときの、記述の文のそろえ方である
sub squash_space {
    my ($text) = @_;
    (my $s = $text) =~ s/\s+/ /g;
    $s =~ s/\A | \z//g;
    return $s;
}

# 状態の場所の JSON を読む。無ければ空の値を返し、形が違えば die する
sub read_state_json {
    my ($path, $type) = @_;
    my $data = read_json($path);
    return $type eq 'ARRAY' ? [] : {} unless defined $data;
    die "$path の形が違う\n" unless ref $data eq $type;
    return $data;
}

# ---- 繰り返しの数え方 ------------------------------------------------------
# 決まりの見直しの案を載せる種類を、prepare と適用の部品が同じ決まりで求めるための関数である

# 記録のある回を、[記録, 始めた時刻の秒] の組で並べる。except の回は除く
sub run_records {
    my ($state, $except) = @_;
    opendir(my $dh, "$state/runs") or return ();
    my @ids = sort grep { !/\A\./ && !(defined $except && $_ eq $except) } readdir $dh;
    closedir $dh;
    my @records;
    for my $id (@ids) {
        my $rec = read_json("$state/runs/$id/record.json");
        next unless defined $rec;
        die "回 $id の記録の形が違う\n" unless ref $rec eq 'HASH';
        my $t = epoch($rec->{started_at});
        die "回 $id の記録の started_at を読めなかった\n" unless defined $t;
        push @records, [ $rec, $t ];
    }
    return @records;
}

# 完了した回のうち、新しい順に n 回分の記録を返す。その場で動かした回も数え、中断した回と動いている回は数えない
sub recent_completed_records {
    my ($state, $n, $except) = @_;
    my @done = sort { $b->[1] <=> $a->[1] || ($b->[0]{run_id} // '') cmp ($a->[0]{run_id} // '') }
        grep { ($_->[0]{status} // '') eq 'completed' } run_records($state, $except);
    splice(@done, $n) if @done > $n;
    return map { $_->[0] } @done;
}

# 種類ごとに、新しく見つかった汚染が1つ以上あった回の数を、種類 => 数の表で返す。
# answers.json で断られた種類は数えず、Issue を起票した種類は、起票した時刻よりあとに始めた回だけを数える
sub kind_repeats {
    my ($answers, @records) = @_;
    my $rule = ref $answers eq 'HASH' && ref $answers->{rule} eq 'HASH' ? $answers->{rule} : {};
    my %count;
    for my $rec (@records) {
        my $t = epoch($rec->{started_at});
        my %kinds = map { ($_->{kind} => 1) }
            grep { ref $_ eq 'HASH' && $_->{new} && defined $_->{kind} } @{ ref $rec->{findings} eq 'ARRAY' ? $rec->{findings} : [] };
        for my $kind (keys %kinds) {
            my $answer = $rule->{$kind};
            if (ref $answer eq 'HASH') {
                next if defined $answer->{declined_at};
                if (defined $answer->{filed_at}) {
                    my $filed = epoch($answer->{filed_at});
                    die "answers.json の種類 $kind の filed_at を読めなかった\n" unless defined $filed;
                    next unless defined $t && $t > $filed;
                }
            }
            $count{$kind}++;
        }
    }
    return \%count;
}

# ---- 事実の調べ ------------------------------------------------------------

# コマンドをシェルを通さずに、フォルダで動かし、標準出力と標準エラーを合わせて読む。読むのは頭の上限のバイトの数と4バイトまでで、
# 残りは読み捨てる。(出力, 終了の状態 $?) を返す: run_capture <フォルダ> <上限> <コマンド> <引数>...
sub run_capture {
    my ($dir, $cap, @cmd) = @_;
    pipe(my $r, my $w) or die "調べるコマンドの出力を受ける管を作れなかった($!)\n";
    my $pid = fork;
    die "調べるコマンドを動かせなかった($!)\n" unless defined $pid;
    if (!$pid) {
        close $r;
        open(STDIN, '<', File::Spec->devnull) or POSIX::_exit(127);
        open(STDOUT, '>&', $w) or POSIX::_exit(127);
        open(STDERR, '>&', $w) or POSIX::_exit(127);
        chdir $dir or do { print STDERR "フォルダ $dir に移れなかった($!)\n"; POSIX::_exit(127) };
        { no warnings 'exec'; exec { $cmd[0] } @cmd; }
        print STDERR "コマンド $cmd[0] を動かせなかった($!)\n";
        POSIX::_exit(127);
    }
    close $w;
    binmode $r;
    my $out = '';
    my $buf;
    while (read($r, $buf, 65536)) {
        $out .= $buf if length $out <= $cap + 4;
    }
    close $r;
    waitpid $pid, 0;
    return (substr($out, 0, $cap + 4), $?);
}

# バイトの列を上限のバイトの数で切る。UTF-8 の1文字の途中で切れたときは、その文字を落とす。(切った列, 切ったか) を返す
sub cut_bytes {
    my ($s, $n) = @_;
    return ($s, 0) if length $s <= $n;
    $s = substr($s, 0, $n);
    for my $k (1 .. 3) {
        last if $k > length $s;
        my $c = ord substr($s, -$k, 1);
        next if ($c & 0xC0) == 0x80;
        my $need = $c >= 0xF0 ? 4 : $c >= 0xE0 ? 3 : $c >= 0xC0 ? 2 : 1;
        substr($s, -$k) = '' if $k < $need;
        last;
    }
    return ($s, 1);
}

# 調べてほしいことの引数を確かめる。断るときは理由を返し、受けるときは undef を返す: lookup_refusal <種類> <引数のバイトの列>
sub lookup_refusal {
    my ($type, $arg) = @_;
    return q{引数が空} if $arg eq '';
    return q{引数に改行か NUL がある} if $arg =~ /[\r\n\0]/;
    if ($type =~ /\A(?:file|ls|log|home_path)\z/) {
        return q{パスが - で始まる} if $arg =~ /\A-/;
    }
    if ($type =~ /\A(?:issue|pr)\z/) {
        return q{番号が数字でない} unless $arg =~ /\A[0-9]{1,10}\z/;
    }
    if ($type eq 'utterances') {
        return q{会話の ID の形が合わない} unless $arg =~ /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/;
    }
    if ($type eq 'command') {
        return q{コマンドの名前の形が合わない} unless $arg =~ /\A[A-Za-z0-9_.+][A-Za-z0-9_.+-]*\z/;
    }
    if ($type eq 'home_path') {
        return q{ホームの外を指すパス} if $arg =~ m{\A[/\\]} || $arg =~ /\A[A-Za-z]:/ || grep { $_ eq '..' } split m{[/\\]}, $arg;
    }
    return undef;
}

# 1件の調べてほしいことを調べ、(結果の行, 出力, 切ったか) を返す。出力は上限のバイトの数で切る:
# lookup_one <本体の作業フォルダ> <コミット> <種類> <引数のバイトの列> <上限>
sub lookup_one {
    my ($main, $commit, $type, $arg, $cap) = @_;
    if ($type eq 'home_path') {
        (my $home = $ENV{HOME} // '') =~ s{/+\z}{};
        die "HOME が無いので、ホームの下のパスを調べられなかった\n" if $home eq '';
        my $p = "$home/$arg";
        my $what = -d $p ? q{ディレクトリ} : -f $p ? q{ファイル} : -e $p ? q{ほかの種類} : q{無い};
        return (q{成功した}, "$what\n", 0);
    }
    my @git = ('git', '-c', 'core.quotePath=false', '-c', 'color.ui=never');
    (my $dir = $arg) =~ s{/+\z}{};
    my %cmd = (
        file       => [@git, 'show', "$commit:$arg"],
        ls         => [@git, 'ls-tree', '--name-only', $commit, ($dir eq '' || $dir eq '.' ? () : ('--', "$dir/"))],
        log        => [@git, 'log', '--oneline', '-n', '30', $commit, '--', $arg],
        grep       => [@git, 'grep', '-n', '-F', '-e', $arg, $commit],
        issue      => ['gh', 'issue', 'view', $arg, '--json', 'number,title,state,stateReason,closedAt,body'],
        pr         => ['gh', 'pr', 'view', $arg, '--json', 'number,title,state,mergedAt,body'],
        search     => ['gh', 'issue', 'list', '--state', 'all', "--search=$arg", '--limit', '20', '--json', 'number,title,state'],
        utterances => [$^X, dirname(__FILE__) . '/transcript-scan.pl', 'utterances', $arg],
        command    => ['sh', '-c', 'command -v "$1"', 'sh', $arg],
    );
    my ($out, $status) = run_capture($main, $cap, @{ $cmd{$type} });
    if ($type eq 'command') {
        (my $where = $out) =~ s/\r?\n\z//;
        $out = $status == 0 && $where ne '' && $where !~ /\n/ ? q{ある: } . "$where\n" : q{無い} . "\n";
        $status = 0;
    }
    my $result = $status == 0 ? q{成功した}
        : $status & 127 ? sprintf(q{失敗した(シグナル %d)}, $status & 127)
        : sprintf(q{失敗した(終了コード %d)}, $status >> 8);
    my ($cut, $over) = cut_bytes($out, $cap);
    return ($result, $cut, $over);
}

# ---- 直し方の確認 ----------------------------------------------------------

# 配列ならその配列を、配列でなければ空の配列を返す
sub list_of { return ref $_[0] eq 'ARRAY' ? $_[0] : []; }

# 文の中に、別の文が現れる数を、重なる現れ方も数えて返す。空の文は0回とする
sub count_in {
    my ($text, $part) = @_;
    return 0 unless length $part;
    my ($n, $at) = (0, 0);
    while ((my $i = index($text, $part, $at)) >= 0) {
        $n++;
        $at = $i + 1;
    }
    return $n;
}

# メモリファイルの frontmatter のあとの本文を、前後の空白を除いて返す
sub memory_body {
    my ($text) = @_;
    (my $body = $text) =~ s/\A---[ \t]*\r?\n.*?^---[ \t]*\r?(?:\n|\z)//ms;
    $body =~ s/\A\s+|\s+\z//g;
    return $body;
}

# 直し方の確認に使う、メモリのディレクトリの今の様子を返す。名前はどれもバイトの列である。
#   read      prepare が読んだときのハッシュ
#   text      今の中身
#   reverted  戻された直しのうち、戻した文がまだ残っているもの(texts)と、作り直したファイルが変わっていないこと(unchanged)
sub memory_state {
    my ($memdir, $read, $state) = @_;
    my %read = ref $read eq 'HASH' ? map { (encode('UTF-8', $_) => $read->{$_}) } keys %$read : ();
    my %text;
    for my $name (memory_files($memdir)) {
        my $t = read_bytes("$memdir/$name");
        $text{$name} = $t if defined $t;
    }
    my %reverted;
    for my $r (@{ read_state_json("$state/reverted.json", 'ARRAY') }) {
        next unless ref $r eq 'HASH';
        my $name = memory_name($r->{file});
        next unless defined $name && defined $text{$name};
        my $restored = defined $r->{restored_text} && !ref $r->{restored_text} ? encode('UTF-8', $r->{restored_text}) : '';
        push @{ $reverted{$name}{texts} }, $restored if length $restored && index($text{$name}, $restored) >= 0;
        $reverted{$name}{unchanged} = 1
            if defined $r->{restored_sha256} && !ref $r->{restored_sha256} && $r->{restored_sha256} eq sha256_hex($text{$name});
    }
    return { read => \%read, text => \%text, reverted => \%reverted };
}

# prepare が読んだあとに、書き換えられたか、消されたか、作られたメモリファイルの名前を、バイトの列で並べて返す
sub rewritten_files {
    my ($mem) = @_;
    my %names = map { $_ => 1 } keys %{ $mem->{read} }, keys %{ $mem->{text} };
    return grep {
        my ($read, $text) = ($mem->{read}{$_}, $mem->{text}{$_});
        !(defined $read && defined $text && sha256_hex($text) eq $read);
    } sort keys %names;
}

# 1つの直しを確かめる。行わない直しなら、%SKIP の理由の名前を返す。行ってよい直しなら undef を返す
# $f は直し方の汚染、$c はその汚染の直し、$mem は memory_state の様子である
sub change_refusal {
    my ($f, $c, $mem) = @_;
    my $str = sub { my ($h, $k) = @_; return ref $h eq 'HASH' && defined $h->{$k} && !ref $h->{$k}; };
    return 'not_fix' unless $str->($f, 'status') && $f->{status} eq 'fix';
    return 'kind' if $str->($f, 'kind') && $f->{kind} =~ /\A(?:10|11)\z/;
    my $op = $str->($c, 'op') ? $c->{op} : '';
    return 'shape' unless ($op eq 'edit' && $str->($c, 'file') && $str->($c, 'old') && $str->($c, 'new'))
        || ($op eq 'append_index_line' && $str->($c, 'line'))
        || ($op eq 'delete' && $str->($c, 'file'));

    my $name = $op eq 'append_index_line' ? $INDEX : memory_name($c->{file});
    return 'name' unless defined $name;
    return 'index_delete' if $op eq 'delete' && $name eq $INDEX;
    my ($read, $text) = ($mem->{read}{$name}, $mem->{text}{$name});
    return 'missing' unless defined $read || defined $text;
    return 'rewritten' unless defined $read && defined $text && sha256_hex($text) eq $read;

    my $fname = memory_name($f->{file});
    my $ftext = defined $fname ? $mem->{text}{$fname} : undef;
    my $excerpt = $str->($f, 'excerpt') ? encode('UTF-8', $f->{excerpt}) : '';
    return 'excerpt' unless length $excerpt && defined $ftext && index($ftext, $excerpt) >= 0;

    my $rev = $mem->{reverted}{$name} || {};
    my @restored = @{ $rev->{texts} || [] };
    if ($op eq 'delete') {
        return 'reverted_file' if $rev->{unchanged};
        return 'reverted' if @restored;
        return undef;
    }
    return undef unless $op eq 'edit';
    my $old = encode('UTF-8', $c->{old});
    return 'old_count' unless count_in($text, $old) == 1;
    my $body = memory_body($text);
    return 'whole' if length $body && index($old, $body) >= 0;
    return 'reverted' if grep { index($old, $_) >= 0 || index($_, $old) >= 0 } @restored;
    return undef;
}

# 記録に書く直しを返す。行わない直しは状態を skipped にし、理由を skip_reason に書く。
# 確認に通った直しは、メモリに書くまで状態を not_applied にする
sub change_entry {
    my ($id, $finding, $c, $why) = @_;
    my $h = ref $c eq 'HASH' ? $c : {};
    my $str = sub { my $v = $h->{ $_[0] }; return defined $v && !ref $v ? $v : ''; };
    my $op = $str->('op');
    return {
        id                  => $id,
        finding             => $finding,
        op                  => $op,
        file                => $op eq 'append_index_line' ? $INDEX : $str->('file'),
        before              => $op eq 'edit' ? $str->('old') : '',
        after               => $op eq 'edit' ? $str->('new') : $op eq 'append_index_line' ? $str->('line') : '',
        removed_index_lines => [],
        anchor              => undef,
        anchor_side         => undef,
        state               => defined $why ? 'skipped' : 'not_applied',
        skip_reason         => defined $why ? decode('UTF-8', $SKIP{$why}) : undef,
    };
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

# 比べる材料を作る: prepare <回の ID> <scheduled|now>
# メモリを読み、記録 runs/<回の ID>/record.json を状態 running で書き、比べる材料の JSON を標準出力に1行で出す。
# メモリを書き換えず、メモリの中身をファイルに写さない
sub cmd_prepare {
    my @args = @_;
    return usage() unless @args == 2;
    my ($run, $trigger) = @args;
    return usage() unless $run =~ /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/ && $trigger =~ /\A(?:scheduled|now)\z/;
    my $here = dirname(__FILE__);
    my $main = main_worktree($here);
    my $state = state_dir($here);
    my $memdir = memory_dir($main);
    my $rundir = "$state/runs/$run";
    die "回 $run の記録がもうある\n" if -e "$rundir/record.json";

    my $origin = git_line($main, 'rev-parse', '--verify', '--quiet', 'origin/main^{commit}');
    die "本体の作業フォルダの origin/main のコミットを読めなかった\n" unless defined $origin;
    my $read_at = iso_utc(now());

    my %hashes;
    my %index = (lines => 0, bytes => 0);
    my @links;
    for my $name (memory_files($memdir)) {
        my $text = read_bytes("$memdir/$name");
        die "メモリファイル $name を読めなかった\n" unless defined $text;
        $hashes{$name} = sha256_hex($text);
        next unless $name eq $INDEX;
        my $body = index_body($text);
        %index = (lines => line_count($body), bytes => length $body);
        @links = index_links($body);
    }
    my %linked = map { $_ => 1 } @links;
    my @index_without_file = grep { !-f "$memdir/$_" } @links;
    my @file_without_index = grep { $_ ne $INDEX && !$linked{$_} } sort keys %hashes;

    # 比べる元が無い初回は、会話を通らない書き換えを探さない
    my $snap = read_snapshot($state);
    my (@outside, @inside, @findings);
    if ($snap) {
        my @changed = grep {
            my $old = $snap->{files}{$_};
            !(ref $old eq 'HASH' && defined $old->{sha256} && $old->{sha256} eq $hashes{$_});
        } sort keys %hashes;
        my $written = @changed ? conversation_writes($here, $snap->{taken_at}, $memdir, @changed) : {};
        for my $name (@changed) {
            if ($written->{$name}) {
                push @inside, $name;
                next;
            }
            push @outside, $name;
            push @findings, {
                id      => 'F' . (@findings + 1),
                kind    => 11,
                file    => decode('UTF-8', $name),
                excerpt => '',
                status  => 'keep',
                reason  => decode('UTF-8', $REWRITE_REASON),
                changes => [],
            };
        }
    }

    # 戻された直しのうち、戻した文がまだメモリにそのまま残っているもの。消したファイルを戻した直しは、作り直したファイルのハッシュでも見る
    my (@reverted, %reverted_seen);
    for my $r (@{ read_state_json("$state/reverted.json", 'ARRAY') }) {
        next unless ref $r eq 'HASH';
        my $name = memory_name($r->{file});
        next unless defined $name && defined $hashes{$name};
        my $restored = defined $r->{restored_text} && !ref $r->{restored_text} ? $r->{restored_text} : '';
        my $text = read_bytes("$memdir/$name");
        next unless defined $text;
        my $kept = (length $restored && index($text, encode('UTF-8', $restored)) >= 0)
            || (defined $r->{restored_sha256} && !ref $r->{restored_sha256} && $r->{restored_sha256} eq $hashes{$name});
        push @reverted, { file => $r->{file}, text => $restored } if $kept && !$reverted_seen{"$name\0$restored"}++;
    }

    # 決まりの見直しの案を書いてよい種類。前の3回で2回以上の種類と、前の3回で1回の種類を渡す
    my $answers = read_state_json("$state/answers.json", 'HASH');
    my $repeats = kind_repeats($answers, recent_completed_records($state, 3, $run));
    my @rule_kinds = sort { $a <=> $b } map { 0 + $_ } grep { $repeats->{$_} >= 1 } keys %$repeats;

    # 断られた移す先の案。記録の汚染から記述を引き、その記述がまだ同じファイルにあるものだけを並べる
    my %declined = map { ($_->{fingerprint} => 1) }
        grep { ref $_ eq 'HASH' && defined $_->{fingerprint} && ($_->{answer} // '') eq 'declined' }
        @{ ref $answers->{relocation} eq 'ARRAY' ? $answers->{relocation} : [] };
    my (@declined_relocations, %declined_seen);
    if (%declined) {
        for my $pair (run_records($state, $run)) {
            for my $f (@{ ref $pair->[0]{findings} eq 'ARRAY' ? $pair->[0]{findings} : [] }) {
                next unless ref $f eq 'HASH' && defined $f->{fingerprint} && $declined{ $f->{fingerprint} };
                next if $declined_seen{ $f->{fingerprint} }++;
                my $name = memory_name($f->{file});
                next unless defined $name && defined $hashes{$name} && defined $f->{excerpt} && !ref $f->{excerpt};
                my $excerpt = squash_space($f->{excerpt});
                my $text = read_bytes("$memdir/$name");
                next unless length $excerpt && defined $text
                    && index(squash_space(decode('UTF-8', $text)), $excerpt) >= 0;
                push @declined_relocations, { file => $f->{file}, excerpt => $f->{excerpt} };
            }
        }
    }

    # 開発者が会話で指摘した見落としのうち、まだ点検のやり方の見直しの案を作っていないもの
    my @missed = map { +{ id => $_->{id}, kind => $_->{kind}, file => $_->{file}, summary => $_->{summary} } }
        grep { ref $_ eq 'HASH' && !(defined $_->{proposed_in} && $_->{proposed_in} ne '') }
        @{ read_state_json("$state/missed.json", 'ARRAY') };

    make_path($rundir);
    write_json("$rundir/record.json", {
        run_id               => $run,
        trigger              => $trigger,
        status               => 'running',
        started_at           => $read_at,
        finished_at          => undef,
        interrupt_reason     => undef,
        first_run            => $snap ? JSON::PP::false : JSON::PP::true,
        origin_main          => $origin,
        # 目次はメモリファイルに数えない(要件の用語の定義)
        files_inspected      => scalar(grep { $_ ne $INDEX } keys %hashes),
        index                => { %index },
        read_hashes          => { map { decode('UTF-8', $_) => $hashes{$_} } keys %hashes },
        findings             => \@findings,
        changes              => [],
        skipped_files        => [],
        relocation_proposals => [],
        rule_proposals       => [],
        inspection_proposals => [],
        notes                => [],
        reverts              => [],
    });
    print $JSON->encode({
        now                => $read_at,
        first_run          => $snap ? JSON::PP::false : JSON::PP::true,
        origin_main        => $origin,
        index              => { %index, limit_lines => $INDEX_LIMIT{lines}, limit_bytes => $INDEX_LIMIT{bytes} },
        index_without_file => [ map { decode('UTF-8', $_) } @index_without_file ],
        file_without_index => [ map { decode('UTF-8', $_) } @file_without_index ],
        rewritten_outside_conversation => [ map { decode('UTF-8', $_) } @outside ],
        rewritten_in_conversation      => [ map { decode('UTF-8', $_) } @inside ],
        reverted                       => \@reverted,
        rule_proposal_kinds            => \@rule_kinds,
        declined_relocations           => \@declined_relocations,
        missed                         => \@missed,
    }), "\n";
    return 0;
}

# メモリの中身を出す: content
# 目次を先に、ほかのメモリファイルを名前の順に、1つずつ囲んで出す。行の頭に行番号を付けるのは、
# メモリの文が囲みの終わりの印を書いても、囲みの終わりと見分けられるようにするためである。ファイルに書かない
sub cmd_content {
    my @args = @_;
    return usage() if @args;
    my $here = dirname(__FILE__);
    my $memdir = memory_dir(main_worktree($here));
    my $snap = read_snapshot(state_dir($here));
    my @names = memory_files($memdir);
    @names = ((grep { $_ eq $INDEX } @names), (grep { $_ ne $INDEX } @names));
    my $out = '';
    for my $name (@names) {
        my $text = read_bytes("$memdir/$name");
        die "メモリファイル $name を読めなかった\n" unless defined $text;
        my $added = $snap ? added_line_numbers($text, $snap->{files}{$name}) : {};
        $out .= qq{<<<MEMORY-FILE name="$name">>>\n};
        my $n = 0;
        for my $line (split_lines($text)) {
            $n++;
            $out .= ($added->{$n} ? '+' : '') . "$n|" . (length($line) ? " $line" : '') . "\n";
        }
        $out .= "<<<END-MEMORY-FILE>>>\n";
    }
    binmode STDOUT, ':raw';
    print $out;
    return 0;
}

sub cmd_lookup {
    my @args = @_;
    return usage() unless @args == 2;
    my ($run, $first) = @args;
    return usage() unless $run =~ /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/ && $first =~ /\A[1-9][0-9]{0,8}\z/;
    my $here = dirname(__FILE__);
    my $main = main_worktree($here);
    my $path = state_dir($here) . "/runs/$run/record.json";
    my $record = read_json($path);
    die "回 $run の記録が無い\n" unless ref $record eq 'HASH';
    my $commit = $record->{origin_main};
    die "$path に origin_main のコミットが無い\n" unless defined $commit && !ref $commit && $commit =~ /\A[0-9a-f]{40,64}\z/;

    binmode STDIN, ':raw';
    my $text = do { local $/; <STDIN> };
    my $asks = eval { $JSON->decode($text // '') };
    die "標準入力が調べてほしいことの JSON の配列でない\n" unless ref $asks eq 'ARRAY';

    my $show = JSON::PP->new->utf8->allow_nonref->canonical;
    my $total = 0;
    my $out = '';
    for my $i (0 .. $#$asks) {
        my $ask = $asks->[$i];
        my ($type, $arg) = ref $ask eq 'HASH' ? ($ask->{type}, $ask->{arg}) : ();
        my $head = q{種類: } . $show->encode($type) . "\n" . q{引数: } . $show->encode($arg) . "\n";
        my ($result, $body, $over) = ('', '', 0);
        my $git = defined $type && !ref $type && $type =~ /\A(?:file|ls|log|grep)\z/;
        if ($i >= $LOOKUP_LIMIT{count} || $total >= $LOOKUP_LIMIT{total}) {
            $result = $OVER_LIMIT;
        } elsif (!defined $type || ref $type || $type !~ /\A(?:file|ls|log|grep|issue|pr|search|utterances|command|home_path)\z/) {
            $result = q{断った: 種類が表の10の種類でない};
        } elsif (!defined $arg || ref $arg) {
            $result = q{断った: 引数が文字列でない};
        } else {
            my $bytes = encode('UTF-8', "$arg");
            my $why = lookup_refusal($type, $bytes);
            if (defined $why) {
                $result = q{断った: } . $why;
            } else {
                my $cap = $LOOKUP_LIMIT{total} - $total;
                $cap = $LOOKUP_LIMIT{item} if $cap > $LOOKUP_LIMIT{item};
                ($result, $body, $over) = lookup_one($main, $commit, $type, $bytes, $cap);
                $total += length $body;
                $head .= q{コミット: } . "$commit\n" if $git;
            }
        }
        $out .= sprintf(qq{<<<LOOKUP-RESULT id="%d">>>\n}, $first + $i) . $head . q{結果: } . "$result\n";
        $out .= "| $_\n" for split_lines($body);
        $out .= q{続き: } . "$OVER_LIMIT\n" if $over;
        $out .= "<<<END-LOOKUP-RESULT>>>\n";
    }
    binmode STDOUT, ':raw';
    print $out;
    return 0;
}

# 直し方を確かめて適用する: apply <回の ID>
# 標準入力の直し方の JSON(plan-schema.json の形)を読み、prepare が記録に書いた汚染に続けて、直し方の汚染に番号を振る。
# 直しを1つずつ確かめ、行わない直しには理由を記録に書く。読んだあとに書き換わったファイルを記録の skipped_files に書く
sub cmd_apply {
    my @args = @_;
    return usage() unless @args == 1;
    my ($run) = @args;
    return usage() unless $run =~ /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/;
    my $here = dirname(__FILE__);
    my $main = main_worktree($here);
    my $state = state_dir($here);
    my $memdir = memory_dir($main);
    my $path = "$state/runs/$run/record.json";
    my $record = read_json($path);
    die "回 $run の記録が無い\n" unless ref $record eq 'HASH';
    die "回 $run の記録の状態が running でない\n" unless ($record->{status} // '') eq 'running';

    binmode STDIN, ':raw';
    my $text = do { local $/; <STDIN> };
    my $input = eval { $JSON->decode($text // '') };
    die "標準入力が、plan を持つ直し方の JSON でない\n" unless ref $input eq 'HASH' && ref $input->{plan} eq 'HASH';
    my $plan = $input->{plan};

    my $mem = memory_state($memdir, $record->{read_hashes}, $state);
    my @findings = grep { ref $_ eq 'HASH' } @{ list_of($record->{findings}) };
    my $base = @findings;
    my $planned = @{ list_of($plan->{findings}) };
    my @changes;
    for my $f (@{ list_of($plan->{findings}) }) {
        my $pf = ref $f eq 'HASH' ? $f : {};
        my $id = 'F' . (@findings + 1);
        my @ids;
        for my $c (@{ list_of($pf->{changes}) }) {
            my $cid = 'C' . (@changes + 1);
            push @changes, change_entry($cid, $id, $c, change_refusal($pf, $c, $mem));
            push @ids, $cid;
        }
        push @findings, { id => $id, (map { ($_ => $pf->{$_}) } qw(kind file excerpt status reason)), changes => \@ids };
    }

    # 案の汚染の番号は、直し方の findings の1から数えた順番である
    my $finding_id = sub {
        my ($n) = @_;
        return defined $n && !ref $n && $n =~ /\A[1-9][0-9]{0,8}\z/ && $n <= $planned ? 'F' . ($base + $n) : undef;
    };
    my @notes = @{ list_of($record->{notes}) };
    my (@relocations, @rules, @inspections);
    for my $p (grep { ref $_ eq 'HASH' } @{ list_of($plan->{relocation_proposals}) }) {
        my $fid = $finding_id->($p->{finding});
        unless (defined $fid) {
            push @notes, decode('UTF-8', sprintf($NOTE_OUT_OF_RANGE{relocation}, encode('UTF-8', $p->{finding} // '')));
            next;
        }
        push @relocations, { id => 'R' . (@relocations + 1), finding => $fid, target => $p->{target}, text => $p->{text} };
    }
    for my $p (grep { ref $_ eq 'HASH' } @{ list_of($plan->{rule_proposals}) }) {
        push @rules, { id => 'K' . (@rules + 1), kind => $p->{kind}, target => $p->{target}, text => $p->{text} };
    }
    for my $p (grep { ref $_ eq 'HASH' } @{ list_of($plan->{inspection_proposals}) }) {
        my $trigger = defined $p->{trigger} && !ref $p->{trigger} ? $p->{trigger} : '';
        if ($trigger =~ /\Afinding:(.*)\z/s) {
            my $fid = $finding_id->($1);
            unless (defined $fid) {
                push @notes, decode('UTF-8', sprintf($NOTE_OUT_OF_RANGE{inspection}, encode('UTF-8', $1)));
                next;
            }
            $trigger = "finding:$fid";
        }
        push @inspections, { id => 'M' . (@inspections + 1), trigger => $trigger, text => $p->{text} };
    }

    my $rewritten = decode('UTF-8', $SKIP{rewritten});
    write_json($path, {
        %$record,
        findings             => \@findings,
        changes              => \@changes,
        skipped_files        => [ map { +{ file => decode('UTF-8', $_), reason => $rewritten } } rewritten_files($mem) ],
        relocation_proposals => \@relocations,
        rule_proposals       => \@rules,
        inspection_proposals => \@inspections,
        notes                => \@notes,
    });
    return 0;
}
