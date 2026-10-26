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
# 終了コード: 0 できた / 1 gh の呼び出しに失敗した / 3 集計のコメントが無い / 64 引数が違う
# 失敗したときは、標準エラーに日本語の1文で理由を残す。
# =====================================================================
use strict;
use warnings;
use JSON::PP ();
use File::Temp ();

# 集計のコメントの1行目の印。あとに issue=<N> と空白が続く
use constant REPORT_MARK => '<!-- keirekipro-usage-report:v1';

# 書き手として認めるリポジトリとの関係の欄の値
my %TRUSTED = map { $_ => 1 } qw(OWNER COLLABORATOR);

my %COMMANDS = (
    reported => \&cmd_reported,
);

exit main(@ARGV);

sub main {
    my ($cmd, @args) = @_;
    my $run = defined $cmd ? $COMMANDS{$cmd} : undef;
    return usage() unless $run;
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
    my $errf = File::Temp->new;
    open(my $saved, '>&', \*STDERR) or die "標準エラーを控えられなかった($!)\n";
    open(STDERR, '>', $errf->filename) or die "gh の標準エラーの置き場所を開けなかった($!)\n";
    my $ph;
    my $started = open($ph, '-|', 'gh', @args);
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
    die "gh を起動できなかった($why)\n" unless $started;
    if ($rc) {
        my $last = '';
        if (open my $ef, '<', $errf->filename) {
            while (my $l = <$ef>) { $last = $l if $l =~ /\S/ }
            close $ef;
        }
        $last =~ s/\s+/ /g;
        $last =~ s/\A | \z//g;
        my @what = grep { !/\A-/ } @args;
        splice @what, 3 if @what > 3;
        die "gh @what に失敗した" . (length $last ? "($last)" : '') . "\n";
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

sub issue_number {
    my ($s) = @_;
    return defined $s && $s =~ /\A[1-9][0-9]{0,9}\z/ ? $s : undef;
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
