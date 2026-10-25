#!/usr/bin/env perl
# =====================================================================
# extract.pl: Claude Code の会話の記録(JSONL)から、集計に要る数と名前だけを抜き出す部品
#
# 呼び出し方:
#   perl extract.pl --state <記録の置き場所> --all --skip-locked|--wait --repo <本体の作業フォルダ>
#     このリポジトリの全部の会話の記録の続きを読み、<記録の置き場所>/extract/ に書く
#
# Claude Code が形を決めているもの(会話の記録の欄の名前と値)を読むのは、この部品だけである。
# 抜き出した行は「この仕組みの中の値」で書き、会話の文・道具の引数・結果の中身は書かない。
#
# 終了コード: 0 読み終えた / 1 記録の置き場所に書けなかった / 64 引数が違う
# 知らない形の行と壊れた行は飛ばし、飛ばした数を extract/<記録の鍵>.pos に残して 0 で終わる。
# =====================================================================
use strict;
use warnings;
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP ();
use File::Path ();

# 抜き出し方を変えたら上げる。.pos の版の番号が違う記録の鍵は、最初から読み直す
use constant EXTRACT_VERSION => 1;

my $JSON = JSON::PP->new->utf8->canonical;

exit main(@ARGV);

sub main {
    my @args = @_;
    my %o;
    my $ok = GetOptionsFromArray(\@args,
        'state=s'     => \$o{state},
        'all'         => \$o{all},
        'skip-locked' => \$o{skip_locked},
        'wait'        => \$o{wait},
        'repo=s'      => \$o{repo},
    );
    if (!$ok || @args || !$o{all} || !defined $o{state} || !defined $o{repo}
        || ($o{skip_locked} ? 1 : 0) + ($o{wait} ? 1 : 0) != 1) {
        print STDERR "usage: perl extract.pl --state <記録の置き場所> --all --skip-locked|--wait --repo <本体の作業フォルダ>\n";
        return 64;
    }
    return run_all(\%o);
}

# このリポジトリの全部の会話の記録の続きを読む
sub run_all {
    my ($o) = @_;
    my $exdir = "$o->{state}/extract";
    if (!-d $exdir) {
        eval { File::Path::mkpath($exdir) };
        if (!-d $exdir) {
            print STDERR "extract.pl: 記録の置き場所に書けない: $exdir\n";
            return 1;
        }
    }
    my @bases = repo_bases($o->{repo});
    my %seen;
    for my $projects (project_dirs()) {
        opendir(my $pd, $projects) or next;
        my @dirs = sort grep { !/^\./ && -d "$projects/$_" } readdir $pd;
        closedir $pd;
        for my $dir (@dirs) {
            opendir(my $dd, "$projects/$dir") or next;
            my @files = sort grep { /^[A-Za-z0-9_-]+\.jsonl\z/ && -f "$projects/$dir/$_" } readdir $dd;
            closedir $dd;
            for my $file (@files) {
                (my $key = $file) =~ s/\.jsonl\z//;
                next if $seen{$key}++;
                my $path = "$projects/$dir/$file";
                # .pos がある記録の鍵は、前にこのリポジトリの会話と見分けたもの
                next unless -e "$exdir/$key.pos" || is_repo_record($path, \@bases);
                my $rc = read_record($path, $key, $exdir);
                return $rc if $rc;
            }
        }
    }
    return 0;
}

# 会話の記録の置き場所の候補。Windows では ~ が %USERPROFILE% のこともあるので、両方を見る
sub project_dirs {
    my @homes = ($ENV{HOME});
    push @homes, $ENV{USERPROFILE} if $^O =~ /^(?:MSWin32|msys|cygwin)\z/;
    my (@dirs, %dup);
    for my $h (grep { defined && length } @homes) {
        my $d = "$h/.claude/projects";
        next if $dup{norm_path($d)}++;
        push @dirs, $d if -d $d;
    }
    return @dirs;
}

# このリポジトリの作業フォルダ: 本体の作業フォルダと、git worktree list に載った作業フォルダ
# worktree は本体の下の .claude/worktrees/ に作られるので、消した worktree の会話も本体で見分ける
sub repo_bases {
    my ($repo) = @_;
    my @bases = (norm_path($repo));
    if (open(my $git, '-|', 'git', '-C', $repo, 'worktree', 'list', '--porcelain')) {
        while (my $l = <$git>) {
            $l =~ s/\r?\n\z//;
            next unless $l =~ s/^worktree //;
            utf8::decode($l);
            push @bases, norm_path($l);
        }
        close $git or print STDERR "extract.pl: git worktree list に失敗した。本体の作業フォルダだけで見分ける\n";
    }
    my %u;
    return grep { length && !$u{$_}++ } @bases;
}

# 場所をそろえて比べられる形にする
# Windows の場所(ドライブ文字か \\ で始まるもの)は、\ を / にそろえ、大文字と小文字を区別しない
sub norm_path {
    my ($p) = @_;
    if ($^O eq 'msys' || $^O eq 'cygwin') {
        $p =~ s{^/cygdrive/([A-Za-z])(?=/|\z)}{$1:};
        $p =~ s{^/([A-Za-z])(?=/|\z)}{$1:};
    }
    if ($p =~ m{^[A-Za-z]:(?:[\\/]|\z)} || $p =~ m{^\\\\}) {
        $p =~ tr{\\}{/};
        $p = lc $p;
    }
    $p =~ s{/+\z}{};
    return $p;
}

sub under_base {
    my ($p, $base) = @_;
    return $p eq $base || index($p, "$base/") == 0;
}

# cwd の欄を持つ最初の行の cwd が、このリポジトリの作業フォルダかその下にあるか
# 会話の記録の最初の数行は cwd の欄を持たないので、cwd の欄を持つ行まで読み進める
sub is_repo_record {
    my ($path, $bases) = @_;
    open(my $fh, '<:raw', $path) or return 0;
    while (my $line = <$fh>) {
        last unless $line =~ /\n\z/;
        next unless index($line, '"cwd"') >= 0;
        my $d = eval { $JSON->decode($line) };
        next unless ref $d eq 'HASH' && defined $d->{cwd} && !ref $d->{cwd};
        my $cwd = norm_path($d->{cwd});
        return scalar grep { under_base($cwd, $_) } @$bases;
    }
    return 0;
}

# 1つの記録の鍵の続きを読む。.pos は offset(読んだバイト数)size(そのときの大きさ)skipped version を持つ
sub read_record {
    my ($path, $key, $exdir) = @_;
    my $posf = "$exdir/$key.pos";
    my $exf  = "$exdir/$key.jsonl";
    my $pos  = read_pos($posf);
    my $size = -s $path;
    $size = 0 unless defined $size;
    # ファイルが小さくなったか、抜き出し方の版が違えば、抜き出した記録を消して最初から読み直す
    if (!$pos || $size < $pos->{size} || $pos->{offset} > $size
        || !defined $pos->{version} || $pos->{version} ne EXTRACT_VERSION) {
        $pos = { offset => 0, size => 0, skipped => 0 };
    }
    open(my $in, '<:raw', $path) or do {
        print STDERR "extract.pl: 会話の記録を開けない: $path\n";
        return 0;
    };
    seek($in, $pos->{offset}, 0) or return 0;
    my $out;
    if ($pos->{offset} == 0) {
        open($out, '>:raw', $exf) or return write_failed($exf);
        print $out $JSON->encode(meta_line($key)), "\n" or return write_failed($exf);
    } else {
        open($out, '>>:raw', $exf) or return write_failed($exf);
    }
    my ($offset, $skipped) = ($pos->{offset}, $pos->{skipped});
    while (my $line = <$in>) {
        # 改行の無い最後の行は書きかけなので、次の呼び出しで読む
        last unless $line =~ /\n\z/;
        $offset += length $line;
        my $d = eval { $JSON->decode($line) };
        if (ref $d ne 'HASH') {
            $skipped++;
            next;
        }
    }
    close $in;
    close $out or return write_failed($exf);
    my $now = -s $path;
    my $new = {
        offset  => $offset,
        size    => (defined $now && $now > $offset) ? $now : $offset,
        skipped => $skipped,
        version => EXTRACT_VERSION,
    };
    return write_pos($posf, $new);
}

sub meta_line {
    my ($key) = @_;
    return {
        k => 'meta', session => $key, agent_id => undef, agent_type => undef, model => undef,
        stage => undef, cycle => undef, round => undef, cwd_is_repo => JSON::PP::true,
    };
}

sub read_pos {
    my ($f) = @_;
    open(my $fh, '<:raw', $f) or return undef;
    local $/;
    my $s = <$fh>;
    close $fh;
    my $d = eval { $JSON->decode($s) };
    return undef unless ref $d eq 'HASH';
    for my $k (qw(offset size skipped)) {
        return undef unless defined $d->{$k} && $d->{$k} =~ /^\d+\z/;
    }
    return $d;
}

# .pos は、一時のファイルに書いてから置き換える(途中で止まっても壊れた .pos を残さない)
sub write_pos {
    my ($f, $d) = @_;
    my $tmp = "$f.tmp.$$";
    open(my $fh, '>:raw', $tmp) or return write_failed($tmp);
    print $fh $JSON->encode($d), "\n" or return write_failed($tmp);
    close $fh or return write_failed($tmp);
    rename($tmp, $f) or return write_failed($f);
    return 0;
}

sub write_failed {
    my ($f) = @_;
    print STDERR "extract.pl: 記録の置き場所に書けない: $f\n";
    return 1;
}
