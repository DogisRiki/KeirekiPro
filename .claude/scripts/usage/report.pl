#!/usr/bin/env perl
# =====================================================================
# report.pl: 1つの Issue について、AI の作業時間とトークン数と使用料と回数を数え、集計の下書きを作る部品
#
# 呼び出し方:
#   perl report.pl --state <記録の置き場所> --config <データのファイル> --issue <N> --out <下書きのディレクトリ>
#                  [--list <一覧の行のファイル>] [--backfill]
#     手元の記録(extract/ marks.jsonl durations/)と、gh で読む PR と、git で読む main の spec.json から
#     Issue N の集計を作り、<下書きのディレクトリ> に report.json を書く。
#     --list は、github.pl list-read の出力を過去の行として受ける。--backfill は、さかのぼりの集計の印である
#
# report.pl は、gh を読み取りだけに使い、GitHub に書かない。所見を書かない。
# gh と git は、いまの作業フォルダのリポジトリを読む。
#
# 終了コード: 0 集計を作った / 2 この PC に Issue N の記録が無い / 1 失敗した(理由を標準エラーに日本語の1文で残す)
# gh の読み取りに失敗したときは、中途半端な集計を出さないように、下書きを書かずに 1 で終わる。
# =====================================================================
use strict;
use warnings;
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP ();
use File::Path ();
use File::Temp ();
use Time::Local ();
use POSIX ();

# 仕組みが main に入ったコミットを見分けるデータのファイルの、リポジトリの最上位からの場所
use constant CONFIG_PATH => '.claude/scripts/usage/usage-config.json';
# spec のフォルダの、リポジトリの最上位からの場所
use constant SPECS_DIR => '.kiro/specs';

my $JSON = JSON::PP->new->utf8->canonical;

# テストが do で読み込んだときは、呼び出しを動かさない
exit main(@ARGV) unless caller;

sub main {
    my @argv = @_;
    my %o;
    my $parsed = GetOptionsFromArray(\@argv, \%o, 'state=s', 'config=s', 'issue=s', 'out=s', 'list=s', 'backfill')
        && !@argv && defined $o{state} && defined $o{config} && defined $o{out}
        && defined $o{issue} && $o{issue} =~ /\A[1-9][0-9]{0,9}\z/;
    return usage() unless $parsed;
    my $rc = eval { build(\%o) };
    return $rc if defined $rc;
    (my $why = $@ // '') =~ s/\s+/ /g;
    $why =~ s/ \z//;
    print STDERR "report.pl: $why\n";
    return 1;
}

sub usage {
    print STDERR "report.pl: 引数が違う。使い方: perl report.pl --state <記録の置き場所> --config <データのファイル>",
        " --issue <N> --out <下書きのディレクトリ> [--list <一覧の行のファイル>] [--backfill]\n";
    return 1;
}

# 集計を作り、下書きを書く
sub build {
    my ($o) = @_;
    my $n = $o->{issue} + 0;
    my $ctx = { n => $n, state => $o->{state}, cfg => read_config($o->{config}) };
    collect_prs($ctx);
    $ctx->{system_ts} = system_time();
    load_records($ctx);
    $ctx->{branches} = issue_branches($ctx);
    $ctx->{spec} = spec_info($ctx);
    my $report = {
        v        => 1,
        issue    => $n,
        prs      => [ map { $_->{number} } @{ $ctx->{prs} } ],
        spec     => $ctx->{spec}{has} ? JSON::PP::true : JSON::PP::false,
        end_date => local_date($ctx->{end_ts}),
    };
    write_file("$o->{out}/report.json", $JSON->encode($report) . "\n");
    return 0;
}

# ---- 外のコマンド ----------------------------------------------------------

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

sub gh {
    my (@args) = @_;
    my @what = grep { !/\A-/ } @args;
    splice @what, 3 if @what > 3;
    return command("gh @what", 'gh', @args);
}

sub git {
    my ($what, @args) = @_;
    return command($what, 'git', @args);
}

# ---- データのファイル -------------------------------------------------------

sub read_config {
    my ($f) = @_;
    open(my $fh, '<:raw', $f) or die "データのファイル $f を読めなかった($!)\n";
    local $/;
    my $s = <$fh>;
    close $fh;
    my $d = eval { $JSON->decode($s // '') };
    die "データのファイル $f を JSON として読めなかった\n" unless ref $d eq 'HASH';
    return $d;
}

# ---- Issue の PR と終了日 ---------------------------------------------------

# 本文の行頭に Closes #N か Refs: #N がある、main に向けた、マージ済みかマージせずに閉じた PR を集める。
# Closes の PR のうちマージ済みで最も遅くマージされたものの時刻を、終了の時刻とする
sub collect_prs {
    my ($ctx) = @_;
    my $n = $ctx->{n};
    my $out = gh('pr', 'list', '--state', 'all', '--base', 'main', '--limit', '1000',
        '--json', 'number,state,body,headRefName,mergedAt,mergeCommit');
    my $list = eval { $JSON->decode($out) };
    die "gh pr list の出力を JSON として読めなかった\n" unless ref $list eq 'ARRAY';
    my (@prs, $last);
    for my $p (sort { $a->{number} <=> $b->{number} } grep { ref $_ eq 'HASH' && defined $_->{number} } @$list) {
        my $st = $p->{state} // '';
        next unless $st eq 'MERGED' || $st eq 'CLOSED';
        my $body = defined $p->{body} && !ref $p->{body} ? $p->{body} : '';
        my $closes = $body =~ /^Closes #$n(?![0-9])/m ? 1 : 0;
        next unless $closes || $body =~ /^Refs: #$n(?![0-9])/m;
        my $pr = { number => $p->{number} + 0, state => $st, closes => $closes, branch => $p->{headRefName} };
        if ($st eq 'MERGED') {
            $pr->{merged_ts} = iso_epoch($p->{mergedAt});
            die "PR #$pr->{number} のマージの時刻を読めなかった\n" unless defined $pr->{merged_ts};
            $pr->{merge_commit} = ref $p->{mergeCommit} eq 'HASH' ? $p->{mergeCommit}{oid} : undef;
            $last = $pr if $closes && (!$last || $pr->{merged_ts} > $last->{merged_ts});
        }
        push @prs, $pr;
    }
    die "Issue #$n を閉じる PR(本文の行頭に Closes #$n があるマージ済みの PR)が無い\n" unless $last;
    die "PR #$last->{number} のマージのコミットを読めなかった\n" unless defined $last->{merge_commit} && $last->{merge_commit} =~ /\A[0-9a-f]{7,64}\z/;
    $ctx->{prs} = \@prs;
    $ctx->{end_ts} = $last->{merged_ts};
    $ctx->{end_commit} = $last->{merge_commit};
    return 1;
}

# 仕組みが main に入った時刻(データのファイルを足した main のコミットの時刻)。そのコミットが無ければ undef
sub system_time {
    my $out = git('仕組みが main に入ったコミットを探すこと', 'log', 'origin/main', '--first-parent', '--diff-filter=A',
        '--format=%cI', '-1', '--', ':/' . CONFIG_PATH);
    $out =~ s/\s+\z//;
    return undef unless length $out;
    my $t = iso_epoch($out);
    die "仕組みが main に入ったコミットの時刻を読めなかった\n" unless defined $t;
    return $t;
}

# ---- 手元の記録 ------------------------------------------------------------

# extract/<記録の鍵>.jsonl の行を記録の鍵ごとに、marks.jsonl の行を1つの並びに読む。読めない行は飛ばす
sub load_records {
    my ($ctx) = @_;
    my $dir = "$ctx->{state}/extract";
    my %rec;
    if (opendir(my $dh, $dir)) {
        my @keys = sort map { /\A([A-Za-z0-9_.-]+)\.jsonl\z/ && $1 ne 'desktop' ? $1 : () } readdir $dh;
        closedir $dh;
        $rec{$_} = read_jsonl("$dir/$_.jsonl") for @keys;
    }
    $ctx->{rec} = \%rec;
    $ctx->{marks} = read_jsonl("$ctx->{state}/marks.jsonl");
    return 1;
}

sub read_jsonl {
    my ($f) = @_;
    my @rows;
    open(my $fh, '<:raw', $f) or return \@rows;
    while (my $l = <$fh>) {
        my $d = eval { $JSON->decode($l) };
        push @rows, $d if ref $d eq 'HASH';
    }
    close $fh;
    return \@rows;
}

# Issue のブランチ: Issue の PR のブランチと、Issue N の受け持ちの出来事の --branch の値
sub issue_branches {
    my ($ctx) = @_;
    my %b = map { $_ => 1 } grep { defined && !ref && length } map { $_->{branch} } @{ $ctx->{prs} };
    for my $rows (values %{ $ctx->{rec} }) {
        for my $r (@$rows) {
            next unless ($r->{k} // '') eq 'recv' && same_issue($r->{issue}, $ctx->{n});
            $b{ $r->{branch} } = 1 if defined $r->{branch} && !ref $r->{branch} && length $r->{branch};
        }
    }
    return \%b;
}

sub same_issue {
    my ($v, $n) = @_;
    return defined $v && !ref $v && $v =~ /\A[0-9]+\z/ && $v == $n ? 1 : 0;
}

# ---- spec の有無 -----------------------------------------------------------

# 終了の時刻の main(Issue を閉じる PR のマージのコミット)の spec.json のうち、Issue の番号を
# issue か additional_issues に持つものを探す。無ければ spec 無しの Issue である。
# ただし、spec への切り替えの印(switch-to-spec)がある Issue は spec ありとする
sub spec_info {
    my ($ctx) = @_;
    my $n = $ctx->{n};
    my $c = $ctx->{end_commit};
    my @paths = sort grep { m{\A\Q${\ SPECS_DIR}\E/[^/]+/spec\.json\z} }
        split /\n/, git("main の spec の一覧を読むこと", 'ls-tree', '-r', '--full-tree', '--name-only', $c, '--', SPECS_DIR);
    my %info = (has => 0);
    if (@paths) {
        my $out = git("main の spec.json を読むこと", 'show', map { "$c:$_" } @paths);
        my $json = JSON::PP->new->utf8;
        my @docs = eval { $json->incr_parse($out) };
        die "main の spec.json を JSON として読めなかった\n" if $@ || @docs != @paths;
        for my $i (0 .. $#paths) {
            my $d = $docs[$i];
            next unless ref $d eq 'HASH';
            my @issues = ($d->{issue}, ref $d->{additional_issues} eq 'ARRAY' ? @{ $d->{additional_issues} } : ());
            next unless grep { same_issue($_, $n) } @issues;
            ($info{feature} = $paths[$i]) =~ s{\A\Q${\ SPECS_DIR}\E/([^/]+)/spec\.json\z}{$1};
            @info{qw(has json)} = (1, $d);
            last;
        }
    }
    $info{switched} = scalar grep { ($_->{kind} // '') eq 'switch-to-spec' && mark_of_issue($ctx, $_) } @{ $ctx->{marks} };
    $info{has} = 1 if $info{switched};
    return \%info;
}

# 印が Issue N のものか。印の Issue の番号が N か、印のブランチが Issue のブランチのとき
sub mark_of_issue {
    my ($ctx, $m) = @_;
    return 1 if same_issue($m->{issue}, $ctx->{n});
    return defined $m->{branch} && !ref $m->{branch} && $ctx->{branches}{ $m->{branch} } ? 1 : 0;
}

# ---- 時刻と日付 ------------------------------------------------------------

# ISO 8601 の時刻(Z か +09:00 の形の時差を持つもの)を UNIX 秒にする。読めなければ undef
sub iso_epoch {
    my ($s) = @_;
    return undef unless defined $s && !ref $s
        && $s =~ /\A(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d+)?(Z|([+-])(\d\d):?(\d\d))\z/;
    my @f = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);
    my $t = eval { Time::Local::timegm(@f[5, 4, 3, 2], $f[1] - 1, $f[0]) };
    return undef unless defined $t;
    $t -= ($f[7] eq '+' ? 1 : -1) * ($f[8] * 3600 + $f[9] * 60) if $f[6] ne 'Z';
    return $t;
}

# UNIX 秒を、所有者の PC の時間帯の日付「年-月-日」にする
sub local_date {
    my ($t) = @_;
    return undef unless defined $t;
    return POSIX::strftime('%Y-%m-%d', localtime(int $t));
}

# ---- 書き出し --------------------------------------------------------------

# 一時ファイルに書いてから名前を替えて置き換える。ディレクトリが無ければ作る
sub write_file {
    my ($f, $content) = @_;
    (my $dir = $f) =~ s{/[^/]*\z}{};
    eval { File::Path::mkpath($dir) } unless -d $dir;
    my $tmp = "$f.tmp.$$";
    open(my $fh, '>:raw', $tmp) or die "$tmp に書けなかった($!)\n";
    my $ok = print $fh $content;
    $ok = close($fh) && $ok;
    if (!$ok || !rename($tmp, $f)) {
        my $why = $!;
        unlink $tmp;
        die "$f に書けなかった($why)\n";
    }
    return 1;
}
