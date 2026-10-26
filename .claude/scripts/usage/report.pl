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
use Scalar::Util ();
use Encode ();

# 仕組みが main に入ったコミットを見分けるデータのファイルの、リポジトリの最上位からの場所
use constant CONFIG_PATH => '.claude/scripts/usage/usage-config.json';
# spec のフォルダの、リポジトリの最上位からの場所
use constant SPECS_DIR => '.kiro/specs';
# 開始と終了の時刻が無いときの、果ての時刻
use constant FAR => 9e18;
# 段階と役割の名前。データのファイルから読んだ名前と比べるので、文字の列にしておく
use constant SPEC_STAGES => [ map { Encode::decode('UTF-8', $_) }
        qw(着手の判断 要件 要件の審査 設計 設計の審査 タスク タスクの審査 実装), '実装中の spec の直し', '出荷とレビュー対応' ];
use constant NOSPEC_STAGES => [ map { Encode::decode('UTF-8', $_) } qw(着手の判断 実装 出荷とレビュー対応) ];
use constant SPEC_MAKING => { map { (Encode::decode('UTF-8', $_), 1) } qw(要件 要件の審査 設計 設計の審査 タスク タスクの審査) };
use constant OTHER_STAGE    => Encode::decode('UTF-8', 'その他');
use constant IMPL_STAGE     => Encode::decode('UTF-8', '実装');
use constant SPEC_FIX_STAGE => Encode::decode('UTF-8', '実装中の spec の直し');
use constant ROLE_MAIN      => Encode::decode('UTF-8', '本体の会話');
use constant ROLE_SPAWNED   => Encode::decode('UTF-8', '別に起こしたセッション');
use constant ROLE_SUB       => Encode::decode('UTF-8', '補助役');
use constant UNKNOWN_MODEL  => Encode::decode('UTF-8', '不明');

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

# 集計を作り、下書きを書く。Issue に決めた行が1行も無ければ、下書きを書かずに 2 で終わる
sub build {
    my ($o) = @_;
    my $ctx = prepare($o);
    my $n = $ctx->{n};
    if (!$ctx->{row_count}) {
        print STDERR "report.pl: この PC に Issue #$n の記録が無い\n";
        return 2;
    }
    my $lines = stage_lines($ctx);
    my ($totals, $by_stage) = count_times($ctx, $lines);
    my $models = count_tokens($ctx, $lines, $totals, $by_stage);
    my $report = {
        v          => 1,
        issue      => $n,
        prs        => [ map { $_->{number} } @{ $ctx->{prs} } ],
        spec       => $ctx->{spec}{has} ? JSON::PP::true : JSON::PP::false,
        start_date => local_date($ctx->{start_ts}),
        end_date   => local_date($ctx->{end_ts}),
        totals     => $totals,
        stages     => stage_rows($ctx, $by_stage),
        models     => $models,
        unknown_turns => unknown_turns($ctx),
    };
    write_file("$o->{out}/report.json", $JSON->encode($report) . "\n");
    return 0;
}

# PR と手元の記録を読み、Issue に決めた行を $ctx->{irec} に集める
sub prepare {
    my ($o) = @_;
    my $ctx = { n => $o->{issue} + 0, state => $o->{state}, cfg => read_config($o->{config}) };
    collect_prs($ctx);
    $ctx->{system_ts} = system_time();
    load_records($ctx);
    assign_rows($ctx);
    $ctx->{spec} = spec_info($ctx);
    return $ctx;
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
    # ほかの Issue のブランチと終了の時刻を決めるために、PR の一覧の全部を残す
    $ctx->{pr_list} = $list;
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

# extract/<記録の鍵>.jsonl の行を記録の鍵ごとに、marks.jsonl と extract/desktop.jsonl の行を1つの並びに読む。
# 読めない行は飛ばす
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
    $ctx->{desktop} = read_jsonl("$dir/desktop.jsonl");
    # 道具の呼び出しの識別子ごとの、道具の実行時間(ミリ秒)。同じ識別子が2行あれば後の行を使う
    my %dur;
    my $ddir = "$ctx->{state}/durations";
    if (opendir(my $dh, $ddir)) {
        for my $f (sort grep { /\.tsv\z/ } readdir $dh) {
            open(my $fh, '<:raw', "$ddir/$f") or next;
            while (my $l = <$fh>) {
                $dur{$1} = $2 + 0 if $l =~ /\A([A-Za-z0-9_-]{1,128})\t([0-9]+(?:\.[0-9]+)?)\r?\n?\z/;
            }
            close $fh;
        }
        closedir $dh;
    }
    $ctx->{durations} = \%dur;
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

# ---- 受け持ちの区切りと、行の Issue -----------------------------------------

# 1行ごとに Issue を決め、Issue N に決めた行を記録の鍵ごとに $ctx->{irec} に置く。meta の行は、
# Issue N に決めた行がある記録の鍵にだけ添える。あわせて、Issue N のブランチ($ctx->{branches})、
# 開始の時刻($ctx->{start_ts})、Issue に決めた時刻のある行の数($ctx->{row_count})、
# 分けた Issue かどうか($ctx->{split})を決める
sub assign_rows {
    my ($ctx) = @_;
    my $n = $ctx->{n};
    build_segments($ctx);
    relabel_merges($ctx);
    relabel_splits($ctx);
    issue_model($ctx);
    link_spawned($ctx);
    my (%irec, %in, $count, $first, $first_branch);
    for my $key (sort keys %{ $ctx->{rec} }) {
        my ($branch, @rows, @meta);
        for my $r (@{ $ctx->{rec}{$key} }) {
            my $k = $r->{k} // '';
            $branch = $r->{name} if $k eq 'branch' && defined $r->{name} && !ref $r->{name};
            if ($k eq 'meta') {
                push @meta, $r;
                next;
            }
            my $t = row_ts($r);
            next unless defined $t;
            my $i = issue_at($ctx, $key, $t, $branch, 0);
            next unless defined $i && $i == $n;
            push @rows, $r;
            $in{ Scalar::Util::refaddr($r) } = 1;
            $first = $t if !defined $first || $t < $first;
            $first_branch = $t if defined $branch && $ctx->{branches}{$branch} && (!defined $first_branch || $t < $first_branch);
        }
        next unless @rows;
        $irec{$key} = [ @meta, @rows ];
        $count += @rows;
    }
    $ctx->{irec} = \%irec;
    $ctx->{in_n} = \%in;
    $ctx->{row_count} = $count // 0;
    # 開始の時刻は、受け持ちの出来事のうち最も早い時刻。受け持ちの出来事が無ければ、Issue のブランチで最初に動いた行の時刻
    $ctx->{start_ts} = $ctx->{starts}{$n} // $first_branch // $first;
    return 1;
}

# 会話ごとに、受け持ちの出来事を時刻の順に並べ、次の受け持ちまでを、その Issue の区切りとする。
# /request の段階の印は、次の受け持ちまでを、どの Issue にも入れない区切り(issue が undef)にする。
# 補助役の会話は、親の会話の区切りを使うので、区切りを作らない
sub build_segments {
    my ($ctx) = @_;
    my %segs;
    for my $key (keys %{ $ctx->{rec} }) {
        next if defined parent_key($key);
        my (@ev, $i);
        for my $r (@{ $ctx->{rec}{$key} }) {
            $i++;
            my $t = row_ts($r);
            next unless defined $t;
            my $n = recv_issue($r);
            push @ev, [ $t, $i, $n, $r ] if defined $n || is_request($r);
        }
        my @s;
        for my $e (sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @ev) {
            my ($t, undef, $n, $r) = @$e;
            my $prev = @s ? $s[-1]{issue} : -1;
            if (@s && (defined $n ? defined $prev && $prev == $n : !defined $prev)) {
                push @{ $s[-1]{events} }, $r;
                next;
            }
            my $claim = ($r->{k} // '') eq 'recv' && ($r->{how} // '') eq 'claim' ? 1 : 0;
            push @s, { start => $t, issue => $n, orig => $n, events => [$r], claim => $claim };
        }
        $segs{$key} = \@s if @s;
    }
    $ctx->{segs} = \%segs;
    return 1;
}

# まとめた: 会話に M から K へのまとめの出来事があり、その会話が M を受け持ったあとに K を受け持ったとき、
# その会話の M の区切りを K の区切りにする
sub relabel_merges {
    my ($ctx) = @_;
    for my $key (keys %{ $ctx->{segs} }) {
        my %to;
        for my $r (@{ $ctx->{rec}{$key} }) {
            next unless ($r->{k} // '') eq 'merge';
            my ($m, $k) = (issue_no($r->{from}), issue_no($r->{to}));
            $to{$m} = $k if defined $m && defined $k && $m != $k;
        }
        next unless %to;
        my $s = $ctx->{segs}{$key};
        for my $i (0 .. $#$s) {
            my $m = $s->[$i]{issue};
            next unless defined $m && defined $to{$m};
            my $k = $to{$m};
            $s->[$i]{issue} = $k if grep { defined $_->{orig} && $_->{orig} == $k } @$s[ $i + 1 .. $#$s ];
        }
    }
    return 1;
}

# 分けた: Issue O の区切りのすぐあとに、O と違う Issue P の claim で始まる区切りがあり、GitHub の P の親が O で、
# P が O の子のうち最初に claim された Issue のとき、O の区切りを P の区切りにする。
# gh で親を読むのは、Issue N に関わる O の候補だけである
sub relabel_splits {
    my ($ctx) = @_;
    my $n = $ctx->{n};
    my @cand;
    for my $key (sort keys %{ $ctx->{segs} }) {
        my $s = $ctx->{segs}{$key};
        for my $i (1 .. $#$s) {
            my ($o, $p) = ($s->[ $i - 1 ]{issue}, $s->[$i]{issue});
            next unless $s->[$i]{claim} && defined $o && defined $p && $o != $p;
            push @cand, { key => $key, at => $i - 1, o => $o, p => $p, ts => $s->[$i]{start} };
        }
    }
    my %os = ($n => 1);
    $os{ $_->{o} } = 1 for grep { $_->{p} == $n } @cand;
    my %first;
    for my $c (sort { $a->{ts} <=> $b->{ts} || $a->{key} cmp $b->{key} } grep { $os{ $_->{o} } } @cand) {
        next if $first{ $c->{o} };
        my $parent = parent_of($ctx, $c->{p});
        $first{ $c->{o} } = $c if defined $parent && $parent == $c->{o};
    }
    for my $c (values %first) {
        $ctx->{segs}{ $c->{key} }[ $c->{at} ]{issue} = $c->{p};
        $ctx->{split} = 1 if $c->{p} == $n;
    }
    return 1;
}

# GitHub の Issue の親の番号。親が無ければ undef
sub parent_of {
    my ($ctx, $p) = @_;
    return $ctx->{parent}{$p} if exists $ctx->{parent}{$p};
    my $d = eval { $JSON->decode(gh('issue', 'view', $p, '--json', 'parent')) };
    die "gh issue view $p の出力を JSON として読めなかった\n" unless ref $d eq 'HASH';
    my $parent = ref $d->{parent} eq 'HASH' ? issue_no($d->{parent}{number}) : undef;
    return $ctx->{parent}{$p} = $parent;
}

# Issue ごとのブランチと、開始と終了の時刻。ブランチは、Issue の PR(本文の行頭に Closes #X か Refs: #X がある、
# マージ済みかマージせずに閉じた PR)のブランチと、Issue の区切りの受け持ちの出来事の --branch の値である
sub issue_model {
    my ($ctx) = @_;
    my (%br, %start, %end);
    for my $p (@{ $ctx->{pr_list} }) {
        next unless ref $p eq 'HASH';
        my $st = $p->{state} // '';
        next unless $st eq 'MERGED' || $st eq 'CLOSED';
        my $body = defined $p->{body} && !ref $p->{body} ? $p->{body} : '';
        my $head = defined $p->{headRefName} && !ref $p->{headRefName} ? $p->{headRefName} : '';
        my $merged = $st eq 'MERGED' ? iso_epoch($p->{mergedAt}) : undef;
        while ($body =~ /^(Closes|Refs:) #([1-9][0-9]{0,9})(?![0-9])/mg) {
            my ($how, $x) = ($1, $2 + 0);
            $br{$x}{$head} = 1 if length $head;
            $end{$x} = $merged if $how eq 'Closes' && defined $merged && (!defined $end{$x} || $merged > $end{$x});
        }
    }
    $end{ $ctx->{n} } = $ctx->{end_ts};
    for my $s (map { @$_ } values %{ $ctx->{segs} }) {
        my $x = $s->{issue};
        next unless defined $x;
        $start{$x} = $s->{start} if !defined $start{$x} || $s->{start} < $start{$x};
        for my $e (@{ $s->{events} }) {
            my $b = $e->{branch};
            $br{$x}{$b} = 1 if ($e->{k} // '') eq 'recv' && defined $b && !ref $b && length $b;
        }
    }
    my %by;
    for my $x (sort { $a <=> $b } keys %br) {
        push @{ $by{$_} }, [ $x, $start{$x} // -FAR, $end{$x} // FAR ] for sort keys %{ $br{$x} };
    }
    @$ctx{qw(by_branch starts ends)} = (\%by, \%start, \%end);
    $ctx->{branches} = $br{ $ctx->{n} } || {};
    return 1;
}

# 別に起こしたセッションの会話の記録の鍵ごとに、そのセッションを起こした親の会話の出来事
# (親の記録の鍵、時刻、そのときのブランチ)を、extract/desktop.jsonl の対応で決める。最も早い出来事を使う
sub link_spawned {
    my ($ctx) = @_;
    my %session;
    for my $d (@{ $ctx->{desktop} }) {
        my ($l, $s) = @$d{qw(local session)};
        $session{$l} = $s if defined $l && !ref $l && defined $s && !ref $s;
    }
    my %spawned;
    for my $key (sort keys %{ $ctx->{rec} }) {
        my $branch;
        for my $r (@{ $ctx->{rec}{$key} }) {
            my $k = $r->{k} // '';
            $branch = $r->{name} if $k eq 'branch' && defined $r->{name} && !ref $r->{name};
            next unless $k eq 'spawn' && defined $r->{child} && !ref $r->{child};
            my ($s, $t) = ($session{ $r->{child} }, row_ts($r));
            next unless defined $s && defined $t && $s ne $key;
            $spawned{$s} = { key => $key, ts => $t, branch => $branch } if !$spawned{$s} || $t < $spawned{$s}{ts};
        }
    }
    $ctx->{spawned} = \%spawned;
    return 1;
}

# 会話 $key の時刻 $t の行(そのときのブランチ $b)の Issue。どの Issue にも入れない行は undef。
# 次の順で決める。補助役の会話は、親の会話の区切りと、別に起こしたセッションの出来事を使う
# - /request の段階の印のあとから次の受け持ちまでの行は、Issue に入れない
# - 行のブランチが Issue のブランチで、行の時刻が開始の時刻から終了の時刻までにあるとき、その Issue。
#   2つ以上の Issue に当たれば、開始の時刻が最も遅い Issue
# - 行の会話が、その時刻にある Issue の区切りの中にあり、行の時刻が終了の時刻より前のとき、その Issue
# - 別に起こしたセッションの会話は、親の会話の、セッションを起こした出来事と同じ Issue
sub issue_at {
    my ($ctx, $key, $t, $b, $depth) = @_;
    my $host = parent_key($key) // $key;
    my $seg = seg_at($ctx, $host, $t);
    return undef if $seg && !defined $seg->{issue};
    if (defined $b) {
        my $best;
        for my $c (@{ $ctx->{by_branch}{$b} || [] }) {
            next unless $c->[1] <= $t && $t <= $c->[2];
            $best = $c if !$best || $c->[1] > $best->[1];
        }
        return $best->[0] if $best;
    }
    return $t < end_of($ctx, $seg->{issue}) ? $seg->{issue} : undef if $seg;
    my $sp = $ctx->{spawned}{$host};
    return undef unless $sp && $depth < 3;
    my $i = issue_at($ctx, $sp->{key}, $sp->{ts}, $sp->{branch}, $depth + 1);
    return defined $i && $t < end_of($ctx, $i) ? $i : undef;
}

# 会話 $key の、時刻 $t を含む区切り。無ければ undef
sub seg_at {
    my ($ctx, $key, $t) = @_;
    my $found;
    for my $s (@{ $ctx->{segs}{$key} || [] }) {
        last if $s->{start} > $t;
        $found = $s;
    }
    return $found;
}

sub end_of {
    my ($ctx, $x) = @_;
    return $ctx->{ends}{$x} // FAR;
}

# 受け持ちの出来事(Issue の番号がある start の段階の印と、recv の行)の Issue の番号。受け持ちの出来事でなければ undef
sub recv_issue {
    my ($r) = @_;
    my $k = $r->{k} // '';
    return undef unless $k eq 'recv' || ($k eq 'stage' && ($r->{name} // '') eq 'start');
    return issue_no($r->{issue});
}

sub is_request {
    my ($r) = @_;
    return ($r->{k} // '') eq 'stage' && ($r->{name} // '') eq 'request' ? 1 : 0;
}

# 補助役の会話の記録の鍵(<親の記録の鍵>.agent-<id>)の、親の記録の鍵。補助役の会話でなければ undef
sub parent_key {
    my ($key) = @_;
    return $key =~ /\A(.+?)\.agent-[A-Za-z0-9_-]+\z/ ? $1 : undef;
}

sub row_ts {
    my ($r) = @_;
    my $t = $r->{ts};
    return defined $t && !ref $t && $t =~ /\A[0-9]+(?:\.[0-9]+)?\z/ ? $t + 0 : undef;
}

sub issue_no {
    my ($v) = @_;
    return defined $v && !ref $v && $v =~ /\A[1-9][0-9]{0,9}\z/ ? $v + 0 : undef;
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

# ---- 作業時間 --------------------------------------------------------------

# Issue N の作業時間、待ち時間、同時に動いた時間、上限で止まった回数と時間(秒)を数える。
# 会話ごとの動いていた区間を重ね、1つ以上の会話が動いていた時間を作業時間、2つ以上の会話が動いていた時間を
# 同時に動いた時間、動いている会話がすべて待ちの区間にあった時間を待ち時間とする。
# 上限で止まった区間は、すべての会話の区間を重ね、重なる区間と接する区間を1つにまとめて数える。
# 段階ごとの時間は、その時刻に動いている会話のうち、本体の会話か、本体の会話が無ければ最も早く始まった会話の段階に入れる。
# 全体の時間と、段階の名前ごとの時間を返す
sub count_times {
    my ($ctx, $lines) = @_;
    my (@ev, @limits, %main, %start);
    for my $key (sort keys %{ $ctx->{irec} }) {
        $main{$key} = !defined parent_key($key) && !$ctx->{spawned}{$key} ? 1 : 0;
        ($start{$key}) = sort { $a <=> $b } grep { defined } map { row_ts($_) } @{ $ctx->{irec}{$key} };
        # 段階が変わる時刻で、区間を切る
        push @ev, map { [ $_->[0], 0, '', $key ] } grep { $_->[0] > -FAR } @{ $lines->{$key} || [] };
        my @all = timed_rows($ctx->{rec}{$key});
        # 知らせの元の仕事の種類。道具の結果の行の job と job_kind で決める
        my %jobs = map { ($_->{job}, $_->{job_kind} // '') }
            grep { ($_->{k} // '') eq 'result' && defined $_->{job} && !ref $_->{job} } @all;
        # Issue N に決めた行が続く間ごとに区間を作る。間にほかの Issue の行があれば、そこで切る
        my @run;
        for my $r (@all, undef) {
            if (defined $r && $ctx->{in_n}{ Scalar::Util::refaddr($r) }) {
                push @run, $r;
                next;
            }
            if (@run) {
                my ($spans, $lim) = run_spans($ctx, \@run, \%jobs);
                push @ev, map { [ $_->[0], 1, $_->[2], $key ], [ $_->[1], -1, $_->[2], $key ] } @$spans;
                push @limits, @$lim;
            }
            @run = ();
        }
    }
    my %tot = (work_sec => 0, wait_sec => 0, concurrent_sec => 0, limit_count => 0, limit_sec => 0);
    my %by;
    # 同じ時刻の出入りをすべて済ませてから、次の時刻までの長さを足す
    my (%on, $prev);
    for my $e (sort { $a->[0] <=> $b->[0] } @ev) {
        my ($t, $d, $label, $key) = @$e;
        if (defined $prev && $t > $prev) {
            my @act = grep { $on{$_}{think} || $on{$_}{wait} } sort keys %on;
            if (@act) {
                my $len = $t - $prev;
                my ($rep) = sort { $main{$b} <=> $main{$a} || $start{$a} <=> $start{$b} || $a cmp $b } @act;
                my $stage = stage_at($lines->{$rep}, $prev) // OTHER_STAGE;
                my $think = grep { $on{$_}{think} } @act;
                for my $h (\%tot, $by{$stage} //= {}) {
                    $h->{work_sec} += $len;
                    $h->{concurrent_sec} += $len if @act >= 2;
                    $h->{wait_sec} += $len unless $think;
                }
            }
        }
        $on{$key}{$label} += $d if $d;
        $prev = $t;
    }
    my $cur;
    for my $s (sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @limits) {
        if ($cur && $s->[0] <= $cur->[1]) {
            $cur->[1] = $s->[1] if $s->[1] > $cur->[1];
            next;
        }
        push_limit(\%tot, $cur) if $cur;
        $cur = [@$s];
    }
    push_limit(\%tot, $cur) if $cur;
    $tot{$_} = int($tot{$_} + 0.5) for keys %tot;
    return (\%tot, \%by);
}

sub push_limit {
    my ($tot, $s) = @_;
    $tot->{limit_count}++;
    $tot->{limit_sec} += $s->[1] - $s->[0];
    return 1;
}

# Issue N の、turn の from が unknown の行の数
sub unknown_turns {
    my ($ctx) = @_;
    return scalar grep { ($_->{k} // '') eq 'turn' && ($_->{from} // '') eq 'unknown' } map { @$_ } values %{ $ctx->{irec} };
}

# 時刻のある行を、時刻の順に並べる。同じ時刻の行は、記録の順のままにする
sub timed_rows {
    my ($rows) = @_;
    my $i = 0;
    my @t = map { my $t = row_ts($_); defined $t ? [ $t, $i++, $_ ] : () } @$rows;
    return map { $_->[2] } sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @t;
}

# 1つの会話の、Issue N に決めた行が続く間の行から、動いていた区間と、上限で止まった区間を作る。
# 動いていた区間は [始まり, 終わり, think か wait] の配列で、上限で止まった区間は [始まり, 終わり] の配列である。
# 隣り合う時点の間を、「処理の流れ」の図のとおりに、考える(think)、待ち(wait)、除く(skip)に分ける。
# 上限で止まった区間の中の時間は、除く
sub run_spans {
    my ($ctx, $rows, $jobs) = @_;
    my @t = map { row_ts($_) } @$rows;
    my $limits = limit_spans($rows, \@t);
    my %res;
    for my $i (0 .. $#$rows) {
        my $r = $rows->[$i];
        $res{ $r->{id} } = $t[$i] if ($r->{k} // '') eq 'result' && defined $r->{id} && !ref $r->{id};
    }
    # 応答の終わりのあとの区間を、次の行を始めた者で分けるために、行ごとに、あとで最初に来る turn か msg か tool の行を求める
    my @ender;
    my $next;
    for (my $i = $#$rows; $i >= 0; $i--) {
        $ender[$i] = $next;
        my $k = $rows->[$i]{k} // '';
        $next = $rows->[$i] if $k eq 'turn' || $k eq 'msg' || $k eq 'tool';
    }
    my (@spans, %open, $idle, $retry_until);
    for my $i (0 .. $#$rows - 1) {
        my $r = $rows->[$i];
        my $k = $r->{k} // '';
        if ($k eq 'msg') {
            $idle = $r->{end} ? 1 : 0;
            undef $retry_until;
        } elsif ($k eq 'turn') {
            $idle = 0;
            undef $retry_until;
        } elsif ($k eq 'tool' && defined $r->{id} && !ref $r->{id}) {
            $idle = 0;
            my $end = $res{ $r->{id} } // FAR;
            my $dur = $ctx->{durations}{ $r->{id} };
            # 権限の確認の分は、呼び出しから結果までの時間から、道具の実行時間を引いた残りで、呼び出しの直後に置く。
            # 実行時間の記録が無ければ、呼び出しから結果までの全部とする
            my $perm_end = ($r->{perm} // '') ne 'user' ? $t[$i] : defined $dur ? $end - $dur / 1000 : $end;
            $perm_end = $t[$i] if $perm_end < $t[$i];
            $open{ $r->{id} } = { %$r, perm_end => $perm_end };
        } elsif ($k eq 'result' && defined $r->{id} && !ref $r->{id}) {
            delete $open{ $r->{id} };
        } elsif ($k eq 'retry' && defined $r->{ms} && !ref $r->{ms} && $r->{ms} =~ /\A[0-9]+(?:\.[0-9]+)?\z/) {
            $retry_until = $t[$i] + $r->{ms} / 1000;
        }
        my ($from, $to) = ($t[$i], $t[ $i + 1 ]);
        next unless $to > $from;
        # 区間の中で分け方が変わる時刻: 権限の確認の終わり、再試行の終わり、上限で止まった区間の端
        my %cut = ($from => 1, $to => 1);
        $cut{$_} = 1 for grep { $_ > $from && $_ < $to }
            (map { $_->{perm_end} } values %open), (defined $retry_until ? $retry_until : ()), map { @$_ } @$limits;
        my @c = sort { $a <=> $b } keys %cut;
        for my $j (0 .. $#c - 1) {
            my ($p, $q) = ($c[$j], $c[ $j + 1 ]);
            my $m = ($p + $q) / 2;
            next if grep { $_->[0] <= $m && $m < $_->[1] } @$limits;
            my $label = $idle ? idle_label($ender[$i], $jobs)
                : %open ? call_label(\%open, $m)
                : defined $retry_until && $m < $retry_until ? 'wait' : 'think';
            next if $label eq 'skip';
            if (@spans && $spans[-1][1] == $p && $spans[-1][2] eq $label) {
                $spans[-1][1] = $q;
            } else {
                push @spans, [ $p, $q, $label ];
            }
        }
    }
    return (\@spans, $limits);
}

# 応答の終わりのあとの区間の分け方。次の行を始めた者が、所有者、ほかのセッションの知らせ、補助役の知らせ、
# 上限が戻ったあとの再開の知らせなら除き、それ以外なら待ちにする。あとに行が無ければ除く
sub idle_label {
    my ($r, $jobs) = @_;
    return 'skip' unless $r;
    return 'wait' unless ($r->{k} // '') eq 'turn';
    my $from = $r->{from} // '';
    return 'skip' if $from eq 'owner' || $from eq 'peer' || $from eq 'limit';
    return 'skip' if $from eq 'notice' && defined $r->{job} && !ref $r->{job} && ($jobs->{ $r->{job} } // '') eq 'agent';
    return 'wait';
}

# 道具の呼び出しの途中の分け方。所有者に尋ねる道具、同期の補助役、権限の確認の分は除く。
# 同時に呼んだ道具のうち、1つでも考える道具があれば考える、待ちの分類に当たる道具だけなら待ちにする
sub call_label {
    my ($open, $m) = @_;
    my ($think, $wait);
    for my $c (values %$open) {
        my $kind = $c->{kind} // '';
        next if $kind eq 'ask' || $kind eq 'agent' || $m < $c->{perm_end};
        if (defined $c->{cat} && !ref $c->{cat} && length $c->{cat}) {
            $wait = 1;
        } else {
            $think = 1;
        }
    }
    return $think ? 'think' : $wait ? 'wait' : 'skip';
}

# 1つの会話の上限で止まった区間を、「処理の流れ」の3つの決まりで作る
# - 上限の印の区間は、印の時刻から次の行の時刻まで。印のあとに行が無ければ作らない。
#   印の直前の行が turn の from が limit の行なら、区間の始まりをその行の時刻にする
# - turn の from が limit の行の区間は、その行の直前の時点から、その行の時刻まで
sub limit_spans {
    my ($rows, $t) = @_;
    my @s;
    for my $i (0 .. $#$rows) {
        my $k = $rows->[$i]{k} // '';
        if ($k eq 'limit') {
            my $j = $i + 1;
            $j++ while $j <= $#$rows && $t->[$j] <= $t->[$i];
            next if $j > $#$rows;
            my $p = prev_point($t, $i);
            my $start = defined $p && is_limit_turn($rows->[$p]) ? $t->[$p] : $t->[$i];
            push @s, [ $start, $t->[$j] ];
        } elsif (is_limit_turn($rows->[$i])) {
            my $p = prev_point($t, $i);
            push @s, [ $t->[$p], $t->[$i] ] if defined $p;
        }
    }
    return \@s;
}

# $i の行より前で、時刻が $i の行より早い行のうち、最も後の行の番号。無ければ undef
sub prev_point {
    my ($t, $i) = @_;
    for (my $p = $i - 1; $p >= 0; $p--) {
        return $p if $t->[$p] < $t->[$i];
    }
    return undef;
}

sub is_limit_turn {
    my ($r) = @_;
    return ($r->{k} // '') eq 'turn' && ($r->{from} // '') eq 'limit' ? 1 : 0;
}

# ---- 段階とトークン数 ------------------------------------------------------

# 会話ごとに、段階が変わる時刻と段階の名前の組 [時刻, 名前] を、時刻の順に並べる。
# 本体の会話と別に起こしたセッションは、段階の印と、spec 無しの Issue の claim で段階を変える。
# spec の審査役と書き方の点検役は、依頼文の STAGE の段階、ほかの補助役は、起動した時刻の親の会話の段階を通して使う。
# Issue に kiro-impl の段階の印が現れたあとの、spec を作る段階は、実装中の spec の直しにする
sub stage_lines {
    my ($ctx) = @_;
    my $irec = $ctx->{irec};
    my $claim_impl = !$ctx->{spec}{json} || $ctx->{spec}{switched};
    my $impl;
    for my $r (map { @$_ } values %$irec) {
        next unless ($r->{k} // '') eq 'stage' && ($r->{name} // '') eq 'kiro-impl';
        my $t = row_ts($r);
        $impl = $t if defined $t && (!defined $impl || $t < $impl);
    }
    my $fix = sub {
        my ($name, $t) = @_;
        return defined $name && SPEC_MAKING->{$name} && defined $impl && $t > $impl ? SPEC_FIX_STAGE : $name;
    };
    my %lines;
    for my $key (sort grep { !defined parent_key($_) } keys %$irec) {
        my @l;
        for my $r (timed_rows($irec->{$key})) {
            my ($k, $t) = ($r->{k} // '', row_ts($r));
            if ($k eq 'stage') {
                push @l, [ $t, $fix->(stage_of_mark($ctx, $r), $t) // OTHER_STAGE ];
            } elsif ($k eq 'recv' && $claim_impl && ($r->{how} // '') eq 'claim') {
                push @l, [ $t, IMPL_STAGE ];
            }
        }
        $lines{$key} = \@l;
    }
    my $types = $ctx->{cfg}{roles}{agent_types} || {};
    my $review = $ctx->{cfg}{stage_marks}{'spec-review'};
    for my $key (sort grep { defined parent_key($_) } keys %$irec) {
        my ($meta) = grep { ($_->{k} // '') eq 'meta' } @{ $irec->{$key} };
        my ($first) = sort { $a <=> $b } grep { defined } map { row_ts($_) } @{ $irec->{$key} };
        next unless defined $first;
        my ($type, $st) = $meta ? @$meta{qw(agent_type stage)} : ();
        my $name;
        if (defined $type && !ref $type && exists $types->{$type} && defined $st && !ref $st && ref $review eq 'HASH') {
            $name = $fix->($review->{$st}, $first);
        } else {
            $name = stage_at($lines{ parent_key($key) }, $first);
        }
        $lines{$key} = [ [ -FAR, $name // OTHER_STAGE ] ];
    }
    return \%lines;
}

# 段階の印の段階の名前。stage_marks の名前と同じ名前か、* で終わる名前の頭に当たる名前を使う。
# spec-review は、引数の段階の名前で決める。どの段階にも当たらなければ undef
sub stage_of_mark {
    my ($ctx, $r) = @_;
    my $marks = $ctx->{cfg}{stage_marks} || {};
    my $name = $r->{name} // '';
    my $v;
    if (exists $marks->{$name}) {
        $v = $marks->{$name};
    } else {
        for my $m (sort keys %$marks) {
            next unless $m =~ /\A(.+)\*\z/;
            my $head = $1;
            if (index($name, $head) == 0 && length $name > length $head) {
                $v = $marks->{$m};
                last;
            }
        }
    }
    $v = defined $r->{spec_stage} && !ref $r->{spec_stage} ? $v->{ $r->{spec_stage} } : undef if ref $v eq 'HASH';
    return defined $v && !ref $v ? $v : undef;
}

# 段階が変わる時刻の並び $l のうち、時刻 $t 以前で最も後の段階の名前。無ければ undef
sub stage_at {
    my ($l, $t) = @_;
    return undef unless $l && @$l;
    my ($lo, $hi) = (0, $#$l);
    return undef if $l->[0][0] > $t;
    while ($lo < $hi) {
        my $mid = int(($lo + $hi + 1) / 2);
        if ($l->[$mid][0] <= $t) {
            $lo = $mid;
        } else {
            $hi = $mid - 1;
        }
    }
    return $l->[$lo][1];
}

# Issue N の応答のトークン数と使用料を、すべての会話をまたいで message.id で重なりを除いてから足す。
# 全体の合計($tot)と段階ごとの合計($by)に足し、モデルと役割の組ごとの行を、使用料の大きい順に返す
sub count_tokens {
    my ($ctx, $lines, $tot, $by) = @_;
    my @msgs;
    for my $key (sort keys %{ $ctx->{irec} }) {
        push @msgs, map { [ row_ts($_), $key, $_ ] } grep { ($_->{k} // '') eq 'msg' && defined row_ts($_) } @{ $ctx->{irec}{$key} };
    }
    my (%seen, %mod, %unknown, $usd);
    $tot->{tokens} = 0;
    for my $m (sort { $a->[0] <=> $b->[0] || $a->[1] cmp $b->[1] } @msgs) {
        my ($t, $key, $r) = @$m;
        my $id = $r->{id};
        if (defined $id && !ref $id) {
            next if $seen{$id}++;
        }
        my %c = map { ($_ => num($r->{$_})) } qw(in cw5 cw1h cr out ws);
        my $model = $r->{model};
        $model = meta_of($ctx, $key)->{model} unless defined $model && !ref $model && length $model;
        $model = UNKNOWN_MODEL unless defined $model && !ref $model && length $model;
        my $u = row_usd($ctx, $model, $r, \%c);
        my $row = $mod{$model}{ role_of($ctx, $key) } //= { in => 0, cw => 0, cr => 0, out => 0, usd => 0 };
        $row->{in} += $c{in};
        $row->{cw} += $c{cw5} + $c{cw1h};
        $row->{cr} += $c{cr};
        $row->{out} += $c{out};
        if (defined $u) {
            $row->{usd} += $u;
            $usd += $u;
        } else {
            $row->{unknown} = 1;
            $unknown{$model} = 1;
        }
        my $n = $c{in} + $c{cw5} + $c{cw1h} + $c{cr} + $c{out};
        my $stage = $by->{ stage_at($lines->{$key}, $t) // OTHER_STAGE } //= {};
        $stage->{tokens} += $n;
        $stage->{usd} += $u // 0;
        $tot->{tokens} += $n;
    }
    $tot->{usd} = usd_round($usd // 0);
    $tot->{usd_unknown_models} = [ sort keys %unknown ];
    my @rows;
    for my $model (keys %mod) {
        for my $role (keys %{ $mod{$model} }) {
            my $x = $mod{$model}{$role};
            push @rows, { model => $model, role => $role, (map { ($_ => $x->{$_}) } qw(in cw cr out)),
                usd => $x->{unknown} ? undef : $x->{usd} };
        }
    }
    @rows = sort { ($b->{usd} // -1) <=> ($a->{usd} // -1) || $a->{model} cmp $b->{model} || $a->{role} cmp $b->{role} } @rows;
    $_->{usd} = usd_round($_->{usd}) for grep { defined $_->{usd} } @rows;
    return \@rows;
}

# 1つの応答の使用料(米ドル)。価格がデータのファイルに無いモデルは undef。
# fast の行は fast の価格、入力・書き込み・読み込みの合計が long_input の over_tokens を超える行は long_input の価格を使い、
# us の行は geo_us_multiplier を掛け、Web 検索の分を足す
sub row_usd {
    my ($ctx, $model, $r, $c) = @_;
    my $prices = $ctx->{cfg}{prices} || {};
    my $p = price_of($prices->{models}, $model);
    return undef unless $p;
    if ($r->{fast}) {
        $p = $p->{fast};
    } elsif (ref $p->{long_input} eq 'HASH' && is_num($p->{long_input}{over_tokens})
        && $c->{in} + $c->{cw5} + $c->{cw1h} + $c->{cr} > $p->{long_input}{over_tokens}) {
        $p = $p->{long_input};
    }
    return undef unless ref $p eq 'HASH';
    my $u = 0;
    for my $f (qw(in cw5 cw1h cr out)) {
        return undef unless is_num($p->{$f});
        $u += $c->{$f} * $p->{$f} / 1e6;
    }
    if ($r->{us}) {
        return undef unless is_num($prices->{geo_us_multiplier});
        $u *= $prices->{geo_us_multiplier};
    }
    if ($c->{ws}) {
        return undef unless is_num($prices->{web_search_per_1000});
        $u += $c->{ws} * $prices->{web_search_per_1000} / 1000;
    }
    return $u;
}

# モデルの ID の価格。ID と同じ名前か、ID の末尾の -<8桁の日付> を除いた名前の価格を使う。無ければ undef
sub price_of {
    my ($models, $id) = @_;
    return undef unless ref $models eq 'HASH';
    return $models->{$id} if ref $models->{$id} eq 'HASH';
    return $id =~ /\A(.+)-[0-9]{8}\z/ && ref $models->{$1} eq 'HASH' ? $models->{$1} : undef;
}

# 会話の役割の名前。補助役は、roles の agent_types、最後の verdict の行の VERDICT と NEXT_ACTION、
# agent_type の値の順で決める
sub role_of {
    my ($ctx, $key) = @_;
    return $ctx->{role}{$key} //= do {
        my $roles = $ctx->{cfg}{roles} || {};
        my $type = meta_of($ctx, $key)->{agent_type};
        $type = undef if ref $type;
        my ($v) = reverse grep { ($_->{k} // '') eq 'verdict' } timed_rows($ctx->{irec}{$key} || []);
        !defined parent_key($key) ? ($ctx->{spawned}{$key} ? ROLE_SPAWNED : ROLE_MAIN)
            : defined $type && defined $roles->{agent_types}{$type} ? $roles->{agent_types}{$type}
            : $v && defined $v->{value} && defined $roles->{verdict} ? $roles->{verdict}
            : $v && $v->{next_action} && defined $roles->{next_action} ? $roles->{next_action}
            : $type // ROLE_SUB;
    };
}

# 会話の meta の行。無ければ空の HASH
sub meta_of {
    my ($ctx, $key) = @_;
    my ($m) = grep { ($_->{k} // '') eq 'meta' } @{ $ctx->{irec}{$key} || [] };
    return $m || {};
}

# 段階ごとの行を、Issue の段階の並びで作る。並びに無い段階の名前の時間とトークン数は、その他に入れる
sub stage_rows {
    my ($ctx, $by) = @_;
    my @names = (@{ $ctx->{spec}{has} ? SPEC_STAGES : NOSPEC_STAGES }, OTHER_STAGE);
    my %row = map { ($_ => { work_sec => 0, wait_sec => 0, concurrent_sec => 0, tokens => 0, usd => 0 }) } @names;
    for my $name (sort keys %$by) {
        my $dst = $row{$name} || $row{ OTHER_STAGE() };
        $dst->{$_} += $by->{$name}{$_} // 0 for keys %$dst;
    }
    return [ map {
        my $x = $row{$_};
        { name => $_, (map { ($_ => int($x->{$_} + 0.5)) } qw(work_sec wait_sec concurrent_sec tokens)), usd => usd_round($x->{usd}) }
    } @names ];
}

sub usd_round {
    my ($u) = @_;
    return 0 + sprintf('%.6f', $u);
}

sub num {
    my ($v) = @_;
    return is_num($v) ? $v + 0 : 0;
}

sub is_num {
    my ($v) = @_;
    return defined $v && !ref $v && $v =~ /\A[0-9]+(?:\.[0-9]+)?\z/ ? 1 : 0;
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
