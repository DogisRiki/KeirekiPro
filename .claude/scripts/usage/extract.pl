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
use Time::Local ();

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
    # cwd は JSON から解いた文字の列なので、引数の場所も文字の列にしてから比べる
    my $r = $repo;
    utf8::decode($r);
    my @bases = (norm_path($r));
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
        trim_partial($exf) or return write_failed($exf);
        open($out, '>>:raw', $exf) or return write_failed($exf);
    }
    my ($offset, $skipped) = ($pos->{offset}, $pos->{skipped});
    my $st = $pos->{offset} ? read_state($exf, $path, $pos->{offset}) : { ids => {}, rows => {}, branch => undef };
    while (my $line = <$in>) {
        # 改行の無い最後の行は書きかけなので、次の呼び出しで読む
        last unless $line =~ /\n\z/;
        $offset += length $line;
        my $d = eval { $JSON->decode($line) };
        if (ref $d ne 'HASH') {
            $skipped++;
            next;
        }
        my ($rows, $unknown) = extract_line($d, $st);
        $skipped++ if $unknown;
        for my $row (@$rows) {
            my $enc = $JSON->encode($row);
            next if $st->{rows}{$enc}++;
            print $out $enc, "\n" or return write_failed($exf);
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

# 書き足しの途中で止まると、抜き出した記録の最後に改行の無い書きかけの行が残る
# 続きを書き足す前に、最後の改行の直後まで切り詰める(書きかけの行は、読み直しで作り直して書く)
sub trim_partial {
    my ($exf) = @_;
    my $size = -s $exf;
    return 1 unless $size;
    open(my $fh, '+<:raw', $exf) or return 0;
    my $end = $size;
    my $keep = 0;
    while ($end > 0) {
        my $n = $end < 4096 ? $end : 4096;
        $end -= $n;
        seek($fh, $end, 0) or return 0;
        my $buf;
        return 0 unless defined read($fh, $buf, $n) && length $buf == $n;
        my $i = rindex($buf, "\n");
        if ($i >= 0) {
            $keep = $end + $i + 1;
            last;
        }
    }
    if ($keep < $size) {
        truncate($fh, $keep) or return 0;
    }
    close $fh or return 0;
    return 1;
}

# 続きを読む前に、前に抜き出した記録から、抜き出し済みの行と message.id を読み、
# 会話の記録の読んだ位置より前から、最後の gitBranch を読む
# 同じ応答は1つの message.id で2行以上に書かれ、その行が前の呼び出しと今の呼び出しにまたがることがあるため
# 書き足したあと .pos を書く前に止まると、次の呼び出しは同じ行をもう一度読む。抜き出し済みの行と同じ行は書かない
# そのときの gitBranch は、抜き出した記録の最後の branch の行ではなく、読み直す位置の直前の値でなければならない
sub read_state {
    my ($exf, $path, $offset) = @_;
    my $st = { ids => {}, rows => {}, branch => branch_before($path, $offset) };
    open(my $fh, '<:raw', $exf) or return $st;
    while (my $l = <$fh>) {
        (my $enc = $l) =~ s/\n\z//;
        $st->{rows}{$enc} = 1;
        next unless index($l, '"k":"msg"') >= 0;
        my $d = eval { $JSON->decode($l) };
        $st->{ids}{$d->{id}} = 1 if ref $d eq 'HASH' && defined $d->{id};
    }
    close $fh;
    return $st;
}

# 会話の記録の $offset より前の行のうち、gitBranch を持つ最後の行の gitBranch
# 最後の数行で見つかることが多いので、ファイルの後ろから 64KB ずつ読む
sub branch_before {
    my ($path, $offset) = @_;
    open(my $fh, '<:raw', $path) or return undef;
    my ($end, $tail) = ($offset, '');
    while ($end > 0) {
        my $n = $end < 65536 ? $end : 65536;
        $end -= $n;
        seek($fh, $end, 0) or last;
        my $buf;
        last unless defined read($fh, $buf, $n) && length $buf == $n;
        my @lines = split /\n/, $buf . $tail, -1;
        # 読んだ塊の先頭は前の行の途中のことがあるので、前の塊と合わせてから見る
        $tail = $end > 0 ? shift @lines : '';
        for my $l (reverse @lines) {
            next unless index($l, '"gitBranch"') >= 0;
            my $d = eval { $JSON->decode($l) };
            next unless ref $d eq 'HASH';
            my $br = $d->{gitBranch};
            return $br if defined $br && !ref $br && length $br;
        }
    }
    close $fh;
    return undef;
}

# 会話の記録の1行から、抜き出す行を作る。会話の文、道具の引数と結果の中身は読まない
# 返す値: 抜き出す行の配列と、知らない形の行かどうか
sub extract_line {
    my ($d, $st) = @_;
    my @rows;
    my $ts = iso_ts($d->{timestamp});
    my $br = $d->{gitBranch};
    if (defined $br && !ref $br && length $br && (!defined $st->{branch} || $st->{branch} ne $br)) {
        $st->{branch} = $br;
        push @rows, { k => 'branch', ts => $ts, name => $br };
    }
    my $type = defined $d->{type} && !ref $d->{type} ? $d->{type} : '';
    if ($type eq 'assistant') {
        my $m = $d->{message};
        return (\@rows, 1) unless ref $m eq 'HASH';
        my $model = defined $m->{model} && !ref $m->{model} ? $m->{model} : undef;
        if (defined $model && $model eq '<synthetic>') {
            # Claude Code が自分で作った行。トークン数は数えず、上限で止まった印だけを残す
            if (($d->{error} // '') eq 'rate_limit') {
                my $q = ref $d->{quotaLimits} eq 'HASH' ? $d->{quotaLimits} : {};
                push @rows, { k => 'limit', ts => $ts, resets_at => num_or_undef($q->{resetsAt}) };
            }
            return (\@rows, 0);
        }
        my $u  = $m->{usage};
        my $id = $m->{id};
        return (\@rows, 1) unless ref $u eq 'HASH' && defined $id && !ref $id && length $id;
        return (\@rows, 0) if $st->{ids}{$id}++;
        my ($cw5, $cw1h);
        if (ref $u->{cache_creation} eq 'HASH') {
            $cw5  = count($u->{cache_creation}{ephemeral_5m_input_tokens});
            $cw1h = count($u->{cache_creation}{ephemeral_1h_input_tokens});
        } else {
            # 内訳の無い記録では、書き込みの全部を既定の5分に数える
            ($cw5, $cw1h) = (count($u->{cache_creation_input_tokens}), 0);
        }
        my $stu = ref $u->{server_tool_use} eq 'HASH' ? $u->{server_tool_use} : {};
        push @rows, {
            k    => 'msg', ts => $ts, id => $id, model => $model,
            in   => count($u->{input_tokens}), cw5 => $cw5, cw1h => $cw1h,
            cr   => count($u->{cache_read_input_tokens}), out => count($u->{output_tokens}),
            ws   => count($stu->{web_search_requests}),
            fast => is_value($u->{speed}, 'fast'),
            us   => is_value($u->{inference_geo}, 'us'),
            end  => is_value($m->{stop_reason}, 'end_turn'),
        };
    } elsif ($type eq 'system' && ($d->{subtype} // '') eq 'api_error') {
        my $ms = num_or_undef($d->{retryInMs});
        push @rows, { k => 'retry', ts => $ts, ms => $ms } if defined $ms;
    }
    my $pr = $d->{prNumber};
    push @rows, { k => 'pr', ts => $ts, number => $pr + 0 } if defined $pr && !ref $pr && $pr =~ /^\d+\z/;
    return (\@rows, 0);
}

# 会話の記録の時刻(協定世界時の ISO 8601)を、UNIX 秒(小数3桁まで)にする
sub iso_ts {
    my ($s) = @_;
    return undef unless defined $s && !ref $s
        && $s =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(\.\d+)?Z\z/;
    my $t = eval { Time::Local::timegm($6, $5, $4, $3, $2 - 1, $1) };
    return undef unless defined $t;
    return sprintf('%.3f', $t + ($7 // 0)) + 0;
}

sub count {
    my ($v) = @_;
    return defined $v && !ref $v && $v =~ /^\d+\z/ ? $v + 0 : 0;
}

sub num_or_undef {
    my ($v) = @_;
    return defined $v && !ref $v && $v =~ /^\d+(?:\.\d+)?\z/ ? $v + 0 : undef;
}

sub is_value {
    my ($v, $want) = @_;
    return defined $v && !ref $v && $v eq $want ? JSON::PP::true : JSON::PP::false;
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
