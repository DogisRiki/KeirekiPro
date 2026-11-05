# 版の範囲を読み、部品と突き合わせるモジュール
#
# 呼び出し方:
#   ranges_version_cmp($a, $b) は、版 $a が $b より小さければ -1、同じなら 0、大きければ 1 を返す。
#     どちらかの版の形を比べられなければ undef を返す
#   ranges_in_range($source, $range, $version, $partial) は、($in, $reason) を返す。
#     $in は、部品の版が範囲に入れば 1、入らなければ 0、決められなければ undef とする。
#     $reason は、$in が undef のときの理由で、no_range・no_version・partial_version・uncomparable のどれかとする
#     $source と $range は次のどれかとする
#       cve:  CVE の記録の affected[] の製品。versions[] の version・lessThan・lessThanOrEqual・status・versionType・changes と、
#             defaultStatus を読む
#       ghsa: GitHub の勧告の vulnerabilities[] の要素。vulnerable_version_range の式を読む
#       nvd:  NVD の cpeMatch[] の要素。versionStart*・versionEnd* と、criteria の版の欄を読む
#     $partial が真のときは、$version を一部だけの版(21 なら 21 以上 22 未満の幅)として比べる
#
# 版の比べ方: 先頭の v を除き、. と - と + で区切った数の並びとして比べる。足りない桁は 0 とする。
# 英字だけの部分(.Final や -jre)は末尾にあるときだけ除き、途中にあるとき(1.0.0-rc.1)や、
# 数と英字が混ざった部分(1.0.2k)があるときは、比べられないとする
use strict;
use warnings;
use utf8;

# 範囲の下の境が、境が無いことを示す値
my %RANGES_NO_LOWER = map { $_ => 1 } ('*', 'unspecified', 'n/a', '-');

sub ranges_version_cmp {
    my ($x, $y) = @_;
    my ($p, $wp) = _ranges_parse($x);
    my ($q, $wq) = _ranges_parse($y);
    return undef unless $p && $q && !$wp && !$wq && @$p && @$q;
    return _ranges_cmp($p, $q);
}

sub ranges_in_range {
    my ($source, $range, $version, $partial) = @_;
    return (undef, 'no_range') unless ref $range eq 'HASH';
    my $eval = $source eq 'cve' ? \&_ranges_eval_cve : $source eq 'ghsa' ? \&_ranges_eval_ghsa : $source eq 'nvd' ? \&_ranges_eval_nvd : undef;
    return (undef, 'no_range') unless $eval;
    my $prepared = $eval->($range);
    return (undef, $prepared->{reason}) if $prepared->{reason};
    return (undef, 'no_version') unless defined $version && length $version;
    my $w = _ranges_width($version, $partial);
    return (undef, 'uncomparable') unless $w;
    return $prepared->{decide}->($w);
}

# 版を数の並びに直す。比べられない形なら空の一覧を返す。
# 2つ目の値は、末尾が * だったか(1.* は、1 で始まるどの版よりも大きい版を指す)を示す
sub _ranges_parse {
    my ($s) = @_;
    return () unless defined $s && !ref $s;
    $s =~ s/\A\s+//;
    $s =~ s/\s+\z//;
    $s =~ s/\A[vV](?=\d)//;
    my @parts = split /[.\-+]/, $s, -1;
    my $wild = 0;
    if (@parts && $parts[-1] eq '*') {
        pop @parts;
        $wild = 1;
    } else {
        pop @parts while @parts > 1 && $parts[-1] =~ /\A[A-Za-z]+\z/;
    }
    for (@parts) {
        return () unless /\A\d+\z/;
    }
    return () unless @parts || $wild;
    return (\@parts, $wild);
}

sub _ranges_ncmp {
    my ($x, $y) = @_;
    $x =~ s/\A0+(?=\d)//;
    $y =~ s/\A0+(?=\d)//;
    return length($x) <=> length($y) || $x cmp $y;
}

sub _ranges_cmp {
    my ($p, $q) = @_;
    my $n = @$p > @$q ? scalar @$p : scalar @$q;
    for my $i (0 .. $n - 1) {
        my $c = _ranges_ncmp($p->[$i] // 0, $q->[$i] // 0);
        return $c if $c;
    }
    return 0;
}

# 末尾の桁に 1 を足した並びを返す(21 は 22、6.1 は 6.2)
sub _ranges_next {
    my ($n) = @_;
    my @next = @$n;
    $next[-1] = $next[-1] + 1;
    return \@next;
}

# 部品の版を、比べる幅 {lo, hi, hi_inc} に直す。一部だけの版は、末尾の桁に 1 を足した版の手前までの幅にする
sub _ranges_width {
    my ($version, $partial) = @_;
    my ($n, $wild) = _ranges_parse($version);
    return undef unless $n && !$wild && @$n;
    return { lo => $n, hi => _ranges_next($n), hi_inc => 0 } if $partial;
    return { lo => $n, hi => $n, hi_inc => 1 };
}

# 範囲の上の境を読む。境が無ければ (undef) を、読めなければ空の一覧を返す
sub _ranges_upper {
    my ($s, $inc) = @_;
    my ($n, $wild) = _ranges_parse($s);
    return () unless $n;
    if ($wild) {
        return ({ hi => undef }) unless @$n;
        return ({ hi => _ranges_next($n), hi_inc => 0 });
    }
    return ({ hi => $n, hi_inc => $inc ? 1 : 0 });
}

# 範囲の下の境を読む
sub _ranges_lower {
    my ($s) = @_;
    return ({ lo => undef }) if defined $s && !ref $s && $RANGES_NO_LOWER{ lc $s };
    my ($n, $wild) = _ranges_parse($s);
    return () unless $n;
    return ({ lo => undef }) unless @$n;
    return ({ lo => $n, lo_inc => 1 });
}

# >= 14.0.0, < 14.2.25 の形の式を、範囲 {lo, lo_inc, hi, hi_inc} に読む。読めなければ undef を返す
sub _ranges_expr {
    my ($s) = @_;
    my %i = (lo => undef, hi => undef);
    for my $term (split /,/, $s, -1) {
        return undef unless $term =~ /\A\s*(<=|>=|<|>|=)\s*(\S+)\s*\z/;
        my ($op, $v) = ($1, $2);
        my ($n, $wild) = _ranges_parse($v);
        return undef unless $n && !$wild && @$n;
        if ($op eq '=') {
            @i{qw(lo lo_inc hi hi_inc)} = ($n, 1, $n, 1);
        } elsif ($op eq '>' || $op eq '>=') {
            @i{qw(lo lo_inc)} = ($n, $op eq '>=' ? 1 : 0);
        } else {
            @i{qw(hi hi_inc)} = ($n, $op eq '<=' ? 1 : 0);
        }
    }
    return \%i;
}

# 幅 $w と範囲 $i の関係を返す。幅の全体が範囲に入れば in、全体が外れれば out、またがれば part
sub _ranges_rel {
    my ($w, $i) = @_;
    if (defined $i->{hi}) {
        my $c = _ranges_cmp($i->{hi}, $w->{lo});
        return 'out' if $c < 0 || ($c == 0 && !$i->{hi_inc});
    }
    if (defined $i->{lo}) {
        my $c = _ranges_cmp($i->{lo}, $w->{hi});
        return 'out' if $c > 0 || ($c == 0 && (!$i->{lo_inc} || !$w->{hi_inc}));
    }
    my $lo_ok = 1;
    if (defined $i->{lo}) {
        my $c = _ranges_cmp($i->{lo}, $w->{lo});
        $lo_ok = $c < 0 || ($c == 0 && $i->{lo_inc});
    }
    my $hi_ok = 1;
    if (defined $i->{hi}) {
        my $c = _ranges_cmp($w->{hi}, $i->{hi});
        $hi_ok = $c < 0 || ($c == 0 && ($i->{hi_inc} || !$w->{hi_inc}));
    }
    return $lo_ok && $hi_ok ? 'in' : 'part';
}

# status を、範囲に入るかの値に直す。affected は 1、unaffected は 0、そのほか(unknown)は範囲が無いとする
sub _ranges_status {
    my ($status) = @_;
    $status //= 'unknown';
    return (1) if $status eq 'affected';
    return (0) if $status eq 'unaffected';
    return (undef, 'no_range');
}

# 区切った範囲の一覧 [[範囲, status], ...] のうち、幅が入る1つの status を返す。
# どれにも当たらなければ空の一覧を、2つ以上にまたがれば partial_version を返す
sub _ranges_pick {
    my ($w, $segs) = @_;
    my @hit;
    for my $seg (@$segs) {
        my $rel = _ranges_rel($w, $seg->[0]);
        next if $rel eq 'out';
        return (undef, 'partial_version') if $rel eq 'part';
        push @hit, $seg;
    }
    return () unless @hit;
    return (undef, 'partial_version') if @hit > 1;
    return _ranges_status($hit[0][1]);
}

# CVE の記録の versions[] の1つの要素を、区切った範囲の一覧に直す。比べられなければ undef を返す
sub _ranges_cve_segments {
    my ($e) = @_;
    return undef unless ref $e eq 'HASH';
    return undef if lc($e->{versionType} // '') eq 'git';
    my $status = $e->{status};
    my $has_lt = defined $e->{lessThan};
    my $has_le = defined $e->{lessThanOrEqual};
    if (!$has_lt && !$has_le) {
        my $v = $e->{version};
        return undef unless defined $v && !ref $v;
        if ($v =~ /\A\s*[<>=]/) {
            my $i = _ranges_expr($v);
            return $i ? [[$i, $status]] : undef;
        }
        my ($n, $wild) = _ranges_parse($v);
        return undef unless $n;
        return [[{ lo => undef, hi => undef }, $status]] unless @$n;
        return [[{ lo => $n, lo_inc => 1, hi => _ranges_next($n), hi_inc => 0 }, $status]] if $wild;
        return [[{ lo => $n, lo_inc => 1, hi => $n, hi_inc => 1 }, $status]];
    }
    my ($lo) = _ranges_lower($e->{version});
    my ($hi) = $has_lt ? _ranges_upper($e->{lessThan}, 0) : _ranges_upper($e->{lessThanOrEqual}, 1);
    return undef unless $lo && $hi;
    my @changes;
    for my $c (@{ ref $e->{changes} eq 'ARRAY' ? $e->{changes} : [] }) {
        return undef unless ref $c eq 'HASH';
        my ($n, $wild) = _ranges_parse($c->{at});
        return undef unless $n && !$wild && @$n;
        push @changes, [$n, $c->{status}];
    }
    @changes = sort { _ranges_cmp($a->[0], $b->[0]) } @changes;
    my @segs;
    my ($from, $from_inc, $st) = ($lo->{lo}, $lo->{lo_inc}, $status);
    for my $c (@changes) {
        push @segs, [{ lo => $from, lo_inc => $from_inc, hi => $c->[0], hi_inc => 0 }, $st];
        ($from, $from_inc, $st) = ($c->[0], 1, $c->[1]);
    }
    push @segs, [{ lo => $from, lo_inc => $from_inc, hi => $hi->{hi}, hi_inc => $hi->{hi_inc} }, $st];
    return \@segs;
}

# CVE の記録の製品。versions[] を前から順に見て、最初に版が当たった要素の status を使う。
# どの要素にも当たらなければ defaultStatus を使い、defaultStatus が無ければ範囲に入らないとする
sub _ranges_eval_cve {
    my ($p) = @_;
    my $versions = ref $p->{versions} eq 'ARRAY' ? $p->{versions} : [];
    my $default = $p->{defaultStatus};
    return { reason => 'no_range' } unless @$versions || defined $default;
    return {
        decide => sub {
            my ($w) = @_;
            for my $e (@$versions) {
                my $segs = _ranges_cve_segments($e);
                return (undef, 'uncomparable') unless $segs;
                my @r = _ranges_pick($w, $segs);
                return @r if @r;
            }
            return defined $default ? _ranges_status($default) : (0);
        },
    };
}

# GitHub の勧告の vulnerabilities[] の要素
sub _ranges_eval_ghsa {
    my ($v) = @_;
    my $expr = $v->{vulnerable_version_range};
    return { reason => 'no_range' } unless defined $expr && !ref $expr && $expr =~ /\S/;
    my $i = _ranges_expr($expr);
    return { reason => 'uncomparable' } unless $i;
    return { decide => sub { my @r = _ranges_pick($_[0], [[$i, 'affected']]); @r ? @r : (0) } };
}

# NVD の cpeMatch[] の要素。versionStart* と versionEnd* が無ければ、criteria の版の欄を読む
sub _ranges_eval_nvd {
    my ($m) = @_;
    my %i = (lo => undef, hi => undef);
    my $bounded = 0;
    for my $k (qw(versionStartIncluding versionStartExcluding versionEndIncluding versionEndExcluding)) {
        next unless defined $m->{$k};
        $bounded = 1;
        my ($n, $wild) = _ranges_parse($m->{$k});
        return { reason => 'uncomparable' } unless $n && !$wild && @$n;
        if ($k =~ /\AversionStart/) {
            @i{qw(lo lo_inc)} = ($n, $k eq 'versionStartIncluding' ? 1 : 0);
        } else {
            @i{qw(hi hi_inc)} = ($n, $k eq 'versionEndIncluding' ? 1 : 0);
        }
    }
    if (!$bounded) {
        my $criteria = $m->{criteria};
        return { reason => 'no_range' } unless defined $criteria && !ref $criteria;
        my $ver = (split /:/, $criteria)[5];
        return { reason => 'no_range' } unless defined $ver;
        if ($ver ne '*') {
            my ($n, $wild) = _ranges_parse($ver);
            return { reason => 'uncomparable' } unless $n && !$wild && @$n;
            @i{qw(lo lo_inc hi hi_inc)} = ($n, 1, $n, 1);
        }
    }
    return { decide => sub { my @r = _ranges_pick($_[0], [[\%i, 'affected']]); @r ? @r : (0) } };
}

1;
