#!/usr/bin/env perl
# =====================================================================
# github.pl: GitHub に集計のコメントと、蓄積の一覧と、まだ答えていない直す案の索引を書く部品
#
# 呼び出し方:
#   perl github.pl reported <N>
#     Issue N に集計のコメントがあれば、そのコメントの URL を出して 0、無ければ 3 で終わる
#
# gh は、開発者の PC の gh のトークンで、いまの作業フォルダのリポジトリ({owner}/{repo})を読み書きする。
# 印で見つけるコメントと、題名で見つける一覧の Issue は、リポジトリとの関係の欄(author_association)が
# OWNER か COLLABORATOR のものに限る(trusted)。公開のリポジトリでは誰でもコメントと Issue を書けるので、
# 印や題名だけでは、この部品が書いたものと見分けられないためである。
#
# 一覧の Issue は、題名が「AIの作業の集計の一覧」で、書き手の確認を通り、ロックしてある Issue のうち、
# 最小の番号の Issue である。見つけた番号は、手元の記録の置き場所の state.json の list_issue に置いて使う。
# 一覧の Issue を作る・閉じる・ロックするのは、書き込む呼び出しだけで、書き込む呼び出しは、最初に
# permissions.push を確かめる。手元の記録の置き場所は、<git の共通ディレクトリ>/keirekipro-usage/ である。
#
# 終了コード: 0 できた / 1 gh の呼び出しに失敗した / 3 集計のコメントが無い / 64 引数が違う
# 失敗したときは、標準エラーに日本語の1文で理由を残す。
# =====================================================================
use strict;
use warnings;
use JSON::PP ();
use File::Temp ();
use Encode ();

# 集計のコメントの1行目の印。あとに issue=<N> と空白が続く
use constant REPORT_MARK => '<!-- keirekipro-usage-report:v1';

# 一覧の Issue の題名と、作るときの本文(行の無い一覧)
use constant LIST_TITLE => 'AIの作業の集計の一覧';
use constant LIST_INTRO => <<'END';
## AIの作業の集計の一覧

この一覧は、Issue ごとの AI の作業の集計を、終了日の古い順に1行ずつ並べたものである。Issue の列の番号から、その Issue の集計のコメントを開ける。「AIの作業時間」は、AI の会話のどれかが動いていた時間で、所有者の返事を待っていた時間と、使う量の上限で止まっていた時間を含まない。「トークン数」は、入力、キャッシュの書き込み、キャッシュの読み込み、出力の合計である。「使用料」は、トークン数を公表価格で換算した米ドルの額である。「実装中に spec へ戻った回数」は、実装の途中で要件、設計、タスクに戻って直した回数の合計である。300行を超えた行は、この Issue のコメントに続く。

| Issue | spec | 終了日 | AIの作業時間 | トークン数 | 使用料 | 実装中に spec へ戻った回数 |
|---|---|---|---|---|---|---|
END

# 書き手として認めるリポジトリとの関係の欄の値
my %TRUSTED = map { $_ => 1 } qw(OWNER COLLABORATOR);

my %COMMANDS = (
    reported => \&cmd_reported,
);

my $JSON = JSON::PP->new->utf8->canonical;

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
    print STDERR "github.pl: $why\n";
    return 1;
}

sub usage {
    print STDERR "usage: perl github.pl reported <N>\n";
    return 64;
}

# 書き手が所有者か共同作業者のものかを、Issue かコメントの応答の関係の欄で確かめる
sub trusted {
    my ($obj) = @_;
    my $assoc = ref $obj eq 'HASH' ? $obj->{author_association} : undef;
    return defined $assoc && !ref $assoc && $TRUSTED{$assoc} ? 1 : 0;
}

# gh を呼び、標準出力をそのまま返す。失敗したら、gh の標準エラーの最後の行を添えて、日本語の1文で die する
sub gh {
    my (@args) = @_;
    my @what = grep { !/\A-/ } @args;
    splice @what, 3 if @what > 3;
    return command("gh @what", 'gh', @args);
}

# コマンドを呼び、標準出力をそのまま返す。失敗したら、「<$what> に失敗した」に
# コマンドの標準エラーの最後の行を添えて die する。コマンドの標準エラーは、そのままは出さない
sub command {
    my ($what, @cmd) = @_;
    my $errf = File::Temp->new;
    open(my $saved, '>&', \*STDERR) or die "標準エラーを控えられなかった($!)\n";
    open(STDERR, '>', $errf->filename) or die "$cmd[0] の標準エラーの置き場所を開けなかった($!)\n";
    my $ph;
    my $started = open($ph, '-|', @cmd);
    my $why = $!;
    my $out;
    if ($started) {
        binmode $ph;
        local $/;
        $out = <$ph>;
        close $ph;
    }
    my $rc = $?;
    open(STDERR, '>&', $saved) or die "標準エラーを戻せなかった($!)\n";
    die "$cmd[0] を起動できなかった($why)\n" unless $started;
    if ($rc) {
        my $last = '';
        if (open my $ef, '<', $errf->filename) {
            while (my $l = <$ef>) { $last = $l if $l =~ /\S/ }
            close $ef;
        }
        $last =~ s/\s+/ /g;
        $last =~ s/\A | \z//g;
        die "$what に失敗した" . (length $last ? "($last)" : '') . "\n";
    }
    return $out // '';
}

# gh api --paginate の出力(ページごとの JSON の配列が区切らずに続く)を、項目の並び1つにする
sub gh_api_list {
    my ($path) = @_;
    my $out = gh('api', '--paginate', $path);
    my $json = JSON::PP->new->utf8;
    my @pages = eval { $json->incr_parse($out) };
    die "gh api $path の出力を JSON として読めなかった\n" if $@;
    my $rest = $json->incr_text;
    die "gh api $path の出力を JSON として読めなかった\n" if defined $rest && $rest =~ /\S/;
    my @items;
    for my $p (@pages) {
        die "gh api $path の出力が配列でなかった\n" unless ref $p eq 'ARRAY';
        push @items, @$p;
    }
    return \@items;
}

# Issue N のコメントのうち、書き手の確認を通るものだけを返す
sub trusted_comments {
    my ($n) = @_;
    return [ grep { trusted($_) } @{ gh_api_list("repos/{owner}/{repo}/issues/$n/comments") } ];
}

# gh api の1つの JSON の応答を読む
sub gh_api_one {
    my ($path) = @_;
    my $out = gh('api', $path);
    my $r = eval { $JSON->decode($out) };
    die "gh api $path の出力を JSON として読めなかった\n" unless defined $r;
    return $r;
}

sub issue_number {
    my ($s) = @_;
    return defined $s && !ref $s && $s =~ /\A[1-9][0-9]{0,9}\z/ ? $s : undef;
}

sub is_true {
    my ($v) = @_;
    return JSON::PP::is_bool($v) && $v ? 1 : 0;
}

# 書き込む呼び出しが最初に呼ぶ。gh のアカウントがリポジトリに書き込めなければ die する
sub require_push {
    my $r = gh_api_one('repos/{owner}/{repo}');
    my $perm = ref $r eq 'HASH' && ref $r->{permissions} eq 'HASH' ? $r->{permissions}{push} : undef;
    die "gh のアカウントがリポジトリに書き込む権限(permissions.push)を持たないので、書かなかった\n" unless is_true($perm);
    return 1;
}

# ---- 手元の記録 ----------------------------------------------------------

my $STATE_DIR;

# 手元の記録の置き場所 <git の共通ディレクトリ>/keirekipro-usage を返す。無ければ作る
sub state_dir {
    return $STATE_DIR if defined $STATE_DIR;
    my $common = command('git の共通ディレクトリを求めること', 'git', 'rev-parse', '--path-format=absolute', '--git-common-dir');
    $common =~ s/\r?\n\z//;
    die "git の共通ディレクトリを求められなかった\n" unless $common =~ /\S/ && $common !~ /\n/;
    my $d = "$common/keirekipro-usage";
    for my $x ($d, "$d/issues") {
        next if -d $x;
        mkdir $x or -d $x or die "$x を作れなかった($!)\n";
    }
    return $STATE_DIR = $d;
}

# JSON のファイルを読む。無いときと、オブジェクトとして読めないときは、空のオブジェクトを返す
sub read_json_file {
    my ($f) = @_;
    open(my $fh, '<:raw', $f) or return {};
    local $/;
    my $s = <$fh>;
    close $fh;
    my $d = eval { $JSON->decode($s // '') };
    return ref $d eq 'HASH' ? $d : {};
}

# JSON のファイルを読み直し、$edit で欄を替え、一時ファイルに書いてから名前を替えて置き換える。
# 読み直してから替えるので、ほかの部品が書いたほかの欄は残る
sub update_json_file {
    my ($f, $edit) = @_;
    my $d = read_json_file($f);
    $edit->($d);
    my $tmp = "$f.tmp.$$";
    open(my $fh, '>:raw', $tmp) or die "$tmp に書けなかった($!)\n";
    my $ok = print $fh $JSON->encode($d), "\n";
    $ok = close($fh) && $ok;
    if (!$ok || !rename($tmp, $f)) {
        my $why = $!;
        unlink $tmp;
        die "$f に書けなかった($why)\n";
    }
    return 1;
}

sub saved_list_issue {
    return issue_number(read_json_file(state_dir() . '/state.json')->{list_issue});
}

sub save_list_issue {
    my ($n) = @_;
    update_json_file(state_dir() . '/state.json', sub { $_[0]{list_issue} = $n + 0 });
}

# issues/<N>.json に、一覧か案の索引に書けなかった印(list_pending か proposals_pending)を書く
sub mark_pending {
    my ($n, $key) = @_;
    update_json_file(state_dir() . "/issues/$n.json", sub { $_[0]{$key} = JSON::PP::true });
}

# ---- 一覧の Issue --------------------------------------------------------

sub is_list_issue {
    my ($i) = @_;
    return 0 unless ref $i eq 'HASH' && !exists $i->{pull_request} && trusted($i) && defined issue_number($i->{number});
    my $t = $i->{title};
    return defined $t && !ref $t && Encode::encode('UTF-8', $t) eq LIST_TITLE ? 1 : 0;
}

# state.json の list_issue が、書き手の確認を通り、ロックしてある Issue を指していれば、その番号を返す
sub checked_saved_list_issue {
    my $n = saved_list_issue();
    return undef unless defined $n;
    my $i = eval { gh_api_one("repos/{owner}/{repo}/issues/$n") };
    return ref $i eq 'HASH' && !exists $i->{pull_request} && trusted($i) && is_true($i->{locked}) ? $n : undef;
}

# すべての Issue から一覧の Issue を探し、ロックしてあるものとしていないものの、最小の番号の Issue を返す
sub scan_list_issues {
    my ($locked, $unlocked);
    for my $i (@{ gh_api_list('repos/{owner}/{repo}/issues?state=all&per_page=100') }) {
        next unless is_list_issue($i);
        if (is_true($i->{locked})) {
            $locked = $i if !$locked || $i->{number} < $locked->{number};
        } else {
            $unlocked = $i if !$unlocked || $i->{number} < $unlocked->{number};
        }
    }
    return ($locked, $unlocked);
}

# 読むだけの呼び出しが使う。ロックしてある一覧の Issue の番号か、無ければ undef を返す。
# 一覧の Issue を作らない。閉じることも、ロックすることもしない
sub list_issue_for_read {
    my $n = checked_saved_list_issue();
    return $n if defined $n;
    my ($locked) = scan_list_issues();
    return undef unless $locked;
    save_list_issue($locked->{number});
    return $locked->{number};
}

# 書き込む呼び出しが使う。一覧の Issue の番号を返す。無ければ作り、閉じ、ロックする。
# ロックしていない一覧の Issue があれば、新しく作らずに、閉じていなければ閉じ、ロックだけをやり直す
sub list_issue_for_write {
    my $n = checked_saved_list_issue();
    return $n if defined $n;
    my ($locked, $unlocked) = scan_list_issues();
    if ($locked) {
        $n = $locked->{number};
    } else {
        my $open = 1;
        if ($unlocked) {
            $n = $unlocked->{number};
            $open = 0 if ($unlocked->{state} // '') eq 'closed';
        } else {
            $n = create_list_issue();
        }
        gh('issue', 'close', $n, '--reason', 'not planned') if $open;
        gh('issue', 'lock', $n);
    }
    save_list_issue($n);
    return $n;
}

sub create_list_issue {
    my $body = File::Temp->new;
    binmode $body;
    print $body LIST_INTRO;
    close $body or die "一覧の Issue の本文を一時ファイルに書けなかった($!)\n";
    my $out = gh('issue', 'create', '--title', LIST_TITLE, '--body-file', $body->filename);
    my ($n) = $out =~ m{/issues/([1-9][0-9]*)\s*\z};
    die "作った一覧の Issue の番号を gh の出力から読めなかった\n" unless defined $n;
    return $n;
}

# 一覧に行を足す呼び出しが使う。一覧の Issue を用意できなければ、Issue N に list_pending を残して die する
sub list_issue_for_rows {
    my ($n) = @_;
    my $list = eval { list_issue_for_write() };
    return $list if defined $list;
    my $why = $@;
    mark_pending($n, 'list_pending');
    die $why;
}

sub cmd_reported {
    my (@args) = @_;
    my $n = @args == 1 ? issue_number($args[0]) : undef;
    return usage() unless defined $n;
    my $head = REPORT_MARK . " issue=$n ";
    for my $c (@{ trusted_comments($n) }) {
        my $body = $c->{body};
        next unless defined $body && !ref $body && index($body, $head) == 0;
        my $url = $c->{html_url};
        die "集計のコメントの URL が応答に無かった\n" unless defined $url && !ref $url;
        print "$url\n";
        return 0;
    }
    return 3;
}
