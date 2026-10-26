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
# 終了コード: 0 読み終えた / 1 記録の置き場所に書けなかったか、データのファイル usage-config.json を読めなかった / 64 引数が違う
# 知らない形の行と壊れた行は飛ばし、飛ばした数を extract/<記録の鍵>.pos に残して 0 で終わる。
# =====================================================================
use strict;
use warnings;
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP ();
use File::Path ();
use Time::Local ();
use File::Basename ();
use File::Spec ();

# 抜き出し方を変えたら上げる。.pos の版の番号が違う記録の鍵は、最初から読み直す
use constant EXTRACT_VERSION => 1;

my $JSON = JSON::PP->new->utf8->canonical;

# 道具の名前と、この仕組みの中の道具の種類の対応。表に無い名前は other にする
my %TOOL_KIND = (
    Agent => 'agent', AskUserQuestion => 'ask', ExitPlanMode => 'ask',
    Bash => 'shell', PowerShell => 'shell', Monitor => 'wait',
);
# turnOrigin の値のうち、意味が分かっている値と、その行を始めた者の対応。表に無い値は unknown にする
my %TURN_FROM = (
    human => 'owner', peer => 'peer',
    task_notification => 'notice', scheduled => 'notice', sdk => 'notice',
);
# resume-after-usage-limit.sh が会話を再開させるときの知らせの印
use constant RESUME_MARK => '[resume-after-usage-limit]';
# 仕事の識別子として書き残してよい値の形(会話の文を書き残さないため、形を限る)
my $ID_RE = qr/\A[A-Za-z0-9_-]{1,64}\z/;
# まとめの出来事のコメントの、Issue の番号のあとの文(gh issue close --comment "#<K> に統合した。")
my $MERGED_COMMENT = do { my $s = ' に統合した。'; utf8::decode($s); $s };
# 別に起こしたセッションの識別子の形
my $LOCAL_RE = qr/(?<![A-Za-z0-9_])(local_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?![0-9a-f])/;

# データのファイルの wait_categories(待ちの分類)と stage_marks(段階の印の名前)。run_all が読む
my ($WAIT_CATS, $STAGE_MARKS);

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
    # 待ちの分類と段階の印の名前が分からないまま抜き出すと、分類と印の無い行が残るので、何も書かずに終わる
    ($WAIT_CATS, $STAGE_MARKS) = load_config();
    if (!$WAIT_CATS) {
        print STDERR "extract.pl: データのファイル usage-config.json の wait_categories か stage_marks を読めない\n";
        return 1;
    }
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
                # 補助役の記録は、本体の会話の記録と同じフォルダの <sessionId>/subagents/ の下にある
                my $sub = "$projects/$dir/$key/subagents";
                opendir(my $sd, $sub) or next;
                my @agents = sort grep { /^agent-[A-Za-z0-9_-]+\.jsonl\z/ && -f "$sub/$_" } readdir $sd;
                closedir $sd;
                for my $af (@agents) {
                    (my $akey = "$key.$af") =~ s/\.jsonl\z//;
                    next if $seen{$akey}++;
                    $rc = read_record("$sub/$af", $akey, $exdir);
                    return $rc if $rc;
                }
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
        print $out $JSON->encode(meta_line($key, $path)), "\n" or return write_failed($exf);
    } else {
        trim_partial($exf) or return write_failed($exf);
        open($out, '>>:raw', $exf) or return write_failed($exf);
    }
    my ($offset, $skipped) = ($pos->{offset}, $pos->{skipped});
    my $st = $pos->{offset} ? read_state($exf, $path, $pos->{offset}) : { ids => {}, rows => {}, branch => undef };
    # calls は、この呼び出しで読んだ道具の呼び出しのうち、結果をまだ読んでいないもの
    # 結果が届いたときに呼び出しが calls に無ければ、読み始めた位置より前の行から探す
    @$st{qw(calls path start)} = ({}, $path, $pos->{offset});
    # 補助役の記録では、報告の候補(最後の assistant の行の文か SubagentHandback の input.message)を覚える
    @$st{qw(sub report)} = ($key =~ /\.agent-/ ? 1 : 0, undef);
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
    # 報告は、この呼び出しで読んだ行のうち、会話の記録で後にあるほうの候補とする
    # 補助役が動いている間に読むと、途中の文を報告として読む。そのため、読むたびに、その時点の報告の判定を
    # verdict の行として書き足し、集計は最後の verdict の行を使う。前に判定を書いた記録で、
    # 今の候補に判定の行が無ければ、value が null の行を書いて前の判定を打ち消す
    # 文は、判定の行を探すためだけに読み、書かない
    if (defined $st->{report}) {
        my ($text, $rts) = @{ $st->{report} };
        my $row = verdict_row($text, $rts);
        $row ||= { k => 'verdict', ts => $rts, value => undef, next_action => JSON::PP::false }
            if grep { index($_, '"k":"verdict"') >= 0 } keys %{ $st->{rows} };
        if ($row) {
            my $enc = $JSON->encode($row);
            if (!$st->{rows}{$enc}++) {
                print $out $enc, "\n" or return write_failed($exf);
            }
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
sub branch_before {
    my ($path, $offset) = @_;
    return scan_back($path, $offset, '"gitBranch"', sub {
        my $br = $_[0]{gitBranch};
        return defined $br && !ref $br && length $br ? $br : undef;
    });
}

# 結果が届いた道具の呼び出しを、会話の記録の読み始めた位置より前の行から探す
# 呼び出しを読んだあと、結果を読む前に、前の呼び出しが読み終えたとき(道具が動いている間に読んだとき)に当たる
sub call_before {
    my ($st, $id) = @_;
    return undef unless $st->{start};
    return scan_back($st->{path}, $st->{start}, $id, sub {
        my ($d) = @_;
        return undef unless ($d->{type} // '') eq 'assistant' && ref $d->{message} eq 'HASH'
            && ref $d->{message}{content} eq 'ARRAY';
        for my $b (@{ $d->{message}{content} }) {
            next unless ref $b eq 'HASH' && ($b->{type} // '') eq 'tool_use' && ($b->{id} // '') eq $id;
            return tool_call($b, iso_ts($d->{timestamp}));
        }
        return undef;
    });
}

# 会話の記録の $offset より前の行を後ろから見て、$needle を含む行を解き、$pick が値を返した最初の値を返す
# 最後の数行で見つかることが多いので、ファイルの後ろから 64KB ずつ読む
sub scan_back {
    my ($path, $offset, $needle, $pick) = @_;
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
            next unless index($l, $needle) >= 0;
            my $d = eval { $JSON->decode($l) };
            next unless ref $d eq 'HASH';
            my $v = $pick->($d);
            return $v if defined $v;
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
        # 道具の行は、結果の行を読んだときに書く。所有者が権限の確認に答えたかは、結果の行にあるため
        if (ref $m->{content} eq 'ARRAY') {
            for my $b (@{ $m->{content} }) {
                next unless ref $b eq 'HASH';
                my $bt = $b->{type} // '';
                if ($bt eq 'text' && defined $b->{text} && !ref $b->{text}) {
                    # 補助役の報告の候補。会話の記録で後にあるほうを報告とする
                    $st->{report} = [$b->{text}, $ts] if $st->{sub};
                    next;
                }
                next unless $bt eq 'tool_use';
                my $call = tool_call($b, $ts);
                $st->{calls}{$call->{id}} = $call if $call;
                my $name = $b->{name} // '';
                my $in = ref $b->{input} eq 'HASH' ? $b->{input} : {};
                if ($name eq 'Skill') {
                    push @rows, stage_row($ts, $in->{skill}, $in->{args});
                } elsif ($name eq 'SubagentHandback' && $st->{sub} && defined $in->{message} && !ref $in->{message}) {
                    $st->{report} = [$in->{message}, $ts];
                }
            }
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
    } elsif ($type eq 'user') {
        push @rows, turn_row($d, $ts);
        # 所有者か開発者が打ったコマンド。文は、コマンドの名前と引数を探すためだけに読む
        # コマンドの行は <command-message> か <command-name> で始まる。文の途中の <command-name> は、依頼文などに書かれた例である
        my $text = message_text($d->{message});
        if ($text =~ m{\A\s*(?:<command-message>[^<]*</command-message>\s*)?<command-name>/?([^<\s]+)</command-name>}) {
            my $name = $1;
            my $args = $text =~ m{<command-args>(.*?)</command-args>}s ? $1 : '';
            push @rows, stage_row($ts, $name, $args);
        }
        push @rows, result_rows($d, $ts, $st);
    } elsif ($type eq 'system' && ($d->{subtype} // '') eq 'api_error') {
        my $ms = num_or_undef($d->{retryInMs});
        push @rows, { k => 'retry', ts => $ts, ms => $ms } if defined $ms;
    }
    my $pr = $d->{prNumber};
    push @rows, { k => 'pr', ts => $ts, number => $pr + 0 } if defined $pr && !ref $pr && $pr =~ /^\d+\z/;
    return (\@rows, 0);
}

# user の行を始めた者。turnOrigin の無い行(道具の結果と、ローカルのコマンドの行)は返さない
sub turn_row {
    my ($d, $ts) = @_;
    my $o = $d->{turnOrigin};
    # turnOrigin を持たない行(v2.1.275 までの所有者の行、今の版にもある task-notification の行、
    # 補助役の記録の coordinator の行)は、同じ値を origin.kind に - でつないで書く
    if (!defined $o && ref $d->{origin} eq 'HASH') {
        $o = $d->{origin}{kind};
        $o =~ tr/-/_/ if defined $o && !ref $o;
    }
    return () unless defined $o && !ref $o;
    my $row = { k => 'turn', ts => $ts, from => $TURN_FROM{$o}, job => undef };
    if ($o eq 'task_notification') {
        # 文は、印を含むかと、知らせの元の仕事の識別子を見るためだけに読み、書かない
        my $text = message_text($d->{message});
        if (index($text, RESUME_MARK) >= 0) {
            $row->{from} = 'limit';
        } elsif ($text =~ m{<task-id>([^<]*)</task-id>}) {
            my $job = $1;
            $row->{job} = $job if $job =~ $ID_RE;
        }
    }
    if (!defined $row->{from}) {
        # 会話の文が入らないように、英字と数字と _ と - だけの40文字以内の値だけを残す
        $row->{from} = 'unknown';
        $row->{raw} = $o =~ /\A[A-Za-z0-9_-]{1,40}\z/ ? $o : '';
    }
    return $row;
}

# 段階の印の行。stage_marks に載った名前だけを残し、引数からは Issue の番号と spec-review の段階の名前だけを取り出す
sub stage_row {
    my ($ts, $name, $args) = @_;
    return () unless defined $name && !ref $name;
    $name =~ s{\A/}{};
    return () unless length $name && is_stage_mark($name);
    $args = '' unless defined $args && !ref $args;
    my $issue = $args =~ /#(\d{1,9})(?!\d)/ ? $1 + 0 : undef;
    my $spec_stage = $name eq 'spec-review' && $args =~ /(?<![A-Za-z0-9_-])(requirements|design|tasks)(?![A-Za-z0-9_-])/ ? $1 : undef;
    return { k => 'stage', ts => $ts, name => $name, issue => $issue, spec_stage => $spec_stage };
}

# 受け持ちとまとめの出来事。結果が失敗でないときだけ、結果を読んだときに書く
# コマンドの文字列は、出来事の形を見るためだけに読み、書かない
sub shell_event {
    my ($cmd) = @_;
    return undef unless defined $cmd;
    if ($cmd =~ /session\.sh[ \t]+(check-start|claim|takeover)[ \t]+#?(\d{1,9})(?![\w-])([^\n;&|]*)/) {
        my ($how, $n, $rest) = ($1, $2, $3);
        my $branch;
        if ($rest =~ /--branch(?:[ \t]+|=)(["']?)([A-Za-z0-9._\/-]{1,200})\1(?![^ \t])/) {
            $branch = $2;
        }
        return { k => 'recv', how => $how, issue => $n + 0, branch => $branch };
    }
    if ($cmd =~ /gh[ \t]+issue[ \t]+close[ \t]+#?(\d{1,9})(?![\w-])([^\n;&|]*)/) {
        my ($m, $rest) = ($1, $2);
        return undef unless $rest =~ /--reason(?:[ \t]+|=)(["'])not planned\1/;
        return undef unless $rest =~ /--comment(?:[ \t]+|=)(["'])#(\d{1,9})\Q$MERGED_COMMENT\E\1/;
        return { k => 'merge', from => $m + 0, to => $2 + 0 };
    }
    return undef;
}

# 道具の結果の行から、道具の行と結果の行を作る
sub result_rows {
    my ($d, $ts, $st) = @_;
    my $c = ref $d->{message} eq 'HASH' ? $d->{message}{content} : undef;
    return () unless ref $c eq 'ARRAY';
    my $pd = $d->{permissionDecision};
    my $src = ref $pd eq 'HASH' ? $pd->{source} : undef;
    my $perm = defined $src && !ref $src && $src =~ /^user_/ ? 'user' : 'other';
    my ($job, $job_kind) = job_of($d->{toolUseResult});
    my @rows;
    for my $b (@$c) {
        next unless ref $b eq 'HASH' && ($b->{type} // '') eq 'tool_result';
        my $id = $b->{tool_use_id};
        next unless defined $id && !ref $id && length $id;
        my $call = delete $st->{calls}{$id};
        $call = call_before($st, $id) unless $call;
        push @rows, { k => 'tool', ts => $call->{ts}, id => $id, kind => $call->{kind}, cat => $call->{cat},
            perm => $perm, bg => $call->{bg} } if $call;
        push @rows, { k => 'result', ts => $ts, id => $id, err => $b->{is_error} ? JSON::PP::true : JSON::PP::false,
            job => $job, job_kind => $job_kind };
        next if !$call || $b->{is_error};
        push @rows, { %{ $call->{ev} }, ts => $call->{ts} } if $call->{ev};
        # 別に起こしたセッションの識別子は、結果の文から探すためだけに読み、ほかは書かない
        if ($call->{spawn}) {
            my %child;
            my $text = tool_result_text($b->{content});
            push @rows, map { { k => 'spawn', ts => $ts, child => $_ } } grep { !$child{$_}++ } $text =~ /$LOCAL_RE/g;
        }
    }
    return @rows;
}

# 道具の呼び出しの、時刻と、道具の種類と、待ちの分類の名前と、裏で動かしたかどうか
# コマンドの文字列は、待ちの分類を決めるためだけに読み、書かない
sub tool_call {
    my ($b, $ts) = @_;
    my $id = $b->{id};
    return undef unless defined $id && !ref $id && length $id;
    my $name = defined $b->{name} && !ref $b->{name} ? $b->{name} : '';
    my $in = ref $b->{input} eq 'HASH' ? $b->{input} : {};
    my $kind = $TOOL_KIND{$name} // 'other';
    my $cmd = $kind eq 'shell' && defined $in->{command} && !ref $in->{command} ? $in->{command} : undef;
    my $bg = $in->{run_in_background};
    $bg = JSON::PP::is_bool($bg) ? ($bg ? 1 : 0) : (defined $bg && !ref $bg && $bg eq 'true');
    return { ts => $ts, id => $id, kind => $kind, cat => wait_category($kind, $cmd),
        bg => $bg ? JSON::PP::true : JSON::PP::false, ev => shell_event($cmd),
        spawn => $name eq 'mcp__ccd_session__start_session' };
}

# データのファイルの wait_categories の表で、道具の種類と、コマンドの文字列を照らす。当たらなければ空
sub wait_category {
    my ($kind, $cmd) = @_;
    for my $c (@$WAIT_CATS) {
        next unless $c->{kind} eq $kind;
        next if $c->{re} && !(defined $cmd && $cmd =~ $c->{re});
        return $c->{name};
    }
    return '';
}

# 裏で動かした仕事の識別子と仕事の種類。補助役は agentId、裏で動かしたコマンドは backgroundTaskId
sub job_of {
    my ($r) = @_;
    return (undef, undef) unless ref $r eq 'HASH';
    for ([agentId => 'agent'], [backgroundTaskId => 'other']) {
        my $v = $r->{ $_->[0] };
        return ($v, $_->[1]) if defined $v && !ref $v && $v =~ $ID_RE;
    }
    return (undef, undef);
}

# user の行の文。印と識別子を探すためだけに使う
sub message_text {
    my ($m) = @_;
    return '' unless ref $m eq 'HASH';
    my $c = $m->{content};
    return $c if defined $c && !ref $c;
    return '' unless ref $c eq 'ARRAY';
    return join "\n", map { $_->{text} } grep { ref $_ eq 'HASH' && defined $_->{text} && !ref $_->{text} } @$c;
}

# 道具の結果の文。文字列か、text を持つ塊の配列で書かれる
sub tool_result_text {
    my ($c) = @_;
    return $c if defined $c && !ref $c;
    return '' unless ref $c eq 'ARRAY';
    return join "\n", map { $_->{text} } grep { ref $_ eq 'HASH' && defined $_->{text} && !ref $_->{text} } @$c;
}

# 補助役の報告から、確認役の判定の行の値と、原因を調べる補助役の NEXT_ACTION の行があるかを読む
# 判定の行も NEXT_ACTION の行も無ければ undef
sub verdict_row {
    my ($report, $ts) = @_;
    my $value = $report =~ /^[ \t]*-[ \t]*VERDICT:[ \t]*(APPROVED|REJECTED)(?![A-Za-z_])/m ? $1 : undef;
    my $next = $report =~ /^[ \t]*(?:-[ \t]*)?NEXT_ACTION:/m;
    return undef unless defined $value || $next;
    return { k => 'verdict', ts => $ts, value => $value, next_action => $next ? JSON::PP::true : JSON::PP::false };
}

# データのファイルは、この部品と同じディレクトリに置く(design の「ファイルの構成」)
# 返す値: 待ちの分類の配列と、段階の印の名前の表(名前の最後の * は、その前までが同じ名前のどれにも当たる)
sub load_config {
    my $f = File::Spec->catfile(File::Basename::dirname(File::Spec->rel2abs(__FILE__)), 'usage-config.json');
    open(my $fh, '<:raw', $f) or return;
    local $/;
    my $s = <$fh>;
    close $fh;
    my $d = eval { $JSON->decode($s) };
    return unless ref $d eq 'HASH' && ref $d->{wait_categories} eq 'ARRAY' && ref $d->{stage_marks} eq 'HASH';
    my @cats;
    for my $c (@{ $d->{wait_categories} }) {
        return unless ref $c eq 'HASH' && defined $c->{name} && defined $c->{kind};
        my $re;
        if (defined $c->{pattern}) {
            $re = eval { qr/$c->{pattern}/ } or return;
        }
        push @cats, { name => $c->{name}, kind => $c->{kind}, re => $re };
    }
    my %marks = (exact => {}, prefix => []);
    for my $k (keys %{ $d->{stage_marks} }) {
        if ($k =~ /\A(.+)\*\z/) {
            push @{ $marks{prefix} }, $1;
        } else {
            $marks{exact}{$k} = 1;
        }
    }
    return (\@cats, \%marks);
}

# 名前が stage_marks に載っているか
sub is_stage_mark {
    my ($name) = @_;
    return 1 if $STAGE_MARKS->{exact}{$name};
    return scalar grep { index($name, $_) == 0 && length $name > length $_ } @{ $STAGE_MARKS->{prefix} };
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
    my ($key, $path) = @_;
    my $meta = {
        k => 'meta', session => $key, agent_id => undef, agent_type => undef, model => undef,
        stage => undef, cycle => undef, round => undef, cwd_is_repo => JSON::PP::true,
    };
    return $meta unless $key =~ /\.agent-([A-Za-z0-9_-]+)\z/;
    # 補助役の記録: agent-<id>.meta.json の agentType とモデルと、最初の user の行である依頼文の欄の値
    $meta->{agent_id} = $1;
    (my $mf = $path) =~ s/\.jsonl\z/.meta.json/;
    if (open(my $fh, '<:raw', $mf)) {
        local $/;
        my $d = eval { $JSON->decode(scalar <$fh>) };
        close $fh;
        if (ref $d eq 'HASH') {
            $meta->{agent_type} = name_or_undef($d->{agentType});
            $meta->{model} = name_or_undef($d->{model});
        }
    }
    my $prompt = first_prompt($path);
    if ($prompt =~ /^[ \t]*(?:[-*][ \t]*)?STAGE:[ \t]*([A-Za-z_-]{1,40})[ \t]*\r?$/m) {
        $meta->{stage} = $1;
    }
    for my $f (qw(CYCLE ROUND)) {
        $meta->{ lc $f } = $1 + 0 if $prompt =~ /^[ \t]*(?:[-*][ \t]*)?$f:[ \t]*(\d{1,6})[ \t]*\r?$/m;
    }
    return $meta;
}

# 補助役の会話の記録の最初の user の行の文。依頼文の欄を探すためだけに使う
sub first_prompt {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or return '';
    while (my $line = <$fh>) {
        last unless $line =~ /\n\z/;
        next unless index($line, '"user"') >= 0;
        my $d = eval { $JSON->decode($line) };
        next unless ref $d eq 'HASH' && ($d->{type} // '') eq 'user';
        close $fh;
        return message_text($d->{message});
    }
    close $fh;
    return '';
}

# 補助役の種類とモデルの名前。会話の文が入らないように、名前の形の値だけを残す
sub name_or_undef {
    my ($v) = @_;
    return defined $v && !ref $v && $v =~ /\A[A-Za-z0-9_.:\[\]-]{1,64}\z/ ? $v : undef;
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
