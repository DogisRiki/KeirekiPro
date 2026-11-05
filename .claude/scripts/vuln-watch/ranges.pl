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
#   ranges_lookup(\@cves, \%priority, \%inventory, \%aliases, \%kev_names, $work_dir, $deadline) は、
#     (\%lookup, $advisories_ok) を返す。%lookup は CVE の番号ごとに
#     {products, advisories, vendor_advisories, descriptions, looked_up} を持つ。
#     products は CVE の記録の CNA と CISA-ADP の affected[] の製品で、
#       {from(cna か adp), vendor, product, packageName, collectionURL, defaultStatus, versions} を持つ。
#     advisories は GitHub の勧告で、{ghsa_id, repository_advisory_url, vulnerabilities} を持ち、
#       vulnerabilities は {ecosystem, name, vulnerable_version_range, first_patched_version} を持つ。
#     vendor_advisories は CNA の references[] のうち vendor-advisory の付いた URL を3件まで、
#       descriptions は英語の説明 {en} を600文字まで持つ。
#     looked_up は、CVE の記録と GitHub の勧告の両方を得られたときだけ真とする。
#     $advisories_ok は、GitHub の勧告をすべての番号について得られたときだけ真とする。
#     %priority は CVE の番号ごとの、先に引く順の値で、値の小さい番号から引く。値の無い番号は最後に引く。
#     同じ値の番号は @cves の順に引く。引くのは300件の番号までとする。
#     curl の出力と設定ファイルは $work_dir のフォルダに書く。$deadline の時刻を過ぎたら curl を止める。
#     %inventory と %aliases と %kev_names は、NVD を引く番号を決めるために受け取る
#
# 版の比べ方: 先頭の v を除き、. と - と + で区切った数の並びとして比べる。足りない桁は 0 とする。
# 英字で始まる部分(.Final や -jre や -M1 や .x)は末尾にあるときだけ除く。途中にあるとき(1.0.0-rc.1)や、
# 数で始まり英字が混ざった部分(1.0.2k)があるときは、比べられないとする
use strict;
use warnings;
use utf8;
use JSON::PP ();
use File::Spec ();
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use POSIX qw(WNOHANG);
use Time::HiRes qw(time);

# 範囲の下の境が、境が無いことを示す値
my %RANGES_NO_LOWER = map { $_ => 1 } ('*', 'unspecified', 'n/a', '-');

# CVE の記録と GitHub の勧告を引く数と、引き方
my $RANGES_LOOKUP_LIMIT = 300;
my $RANGES_CVE_URL = 'https://cveawg.mitre.org/api/cve/';
my $RANGES_GHSA_URL = 'https://api.github.com/advisories?cve_id=';
my $RANGES_CURL_PARALLEL = 8;
my $RANGES_CURL_MAX_TIME = 15;
my $RANGES_GH_TIMEOUT = 10;
my $RANGES_AUTH_FILE = 'ranges-auth.txt';
my $RANGES_DESCRIPTION_MAX = 600;
my $RANGES_VENDOR_ADVISORY_MAX = 3;

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
        pop @parts while @parts > 1 && $parts[-1] =~ /\A[A-Za-z]/;
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


# ---------------------------------------------------------------------
# CVE の記録と GitHub の勧告を引く
# ---------------------------------------------------------------------

sub ranges_lookup {
    my ($cves, $priority, $inventory, $aliases, $kev_names, $work_dir, $deadline) = @_;
    $priority = {} unless ref $priority eq 'HASH';
    my (%lookup, %seen, %index, @uniq);
    for my $cve (ref $cves eq 'ARRAY' ? @$cves : ()) {
        next unless defined $cve && !ref $cve && $cve =~ /\ACVE-\d{4}-\d{4,}\z/ && !$seen{$cve}++;
        $index{$cve} = scalar @uniq;
        push @uniq, $cve;
        $lookup{$cve} = { products => [], advisories => [], vendor_advisories => [], descriptions => {}, looked_up => JSON::PP::false };
    }
    # KEV と cvemon の項目の番号(先に引く順の値が小さい番号)を先に引く。同じ値の番号は渡された順に引く
    my $rank = sub { my $p = $priority->{ $_[0] }; defined $p && !ref $p && $p =~ /\A\d+(?:\.\d+)?\z/ ? $p : 9**9 };
    my @order = sort { $rank->($a) <=> $rank->($b) || $index{$a} <=> $index{$b} } @uniq;
    my @pick = @order > $RANGES_LOOKUP_LIMIT ? @order[0 .. $RANGES_LOOKUP_LIMIT - 1] : @order;
    my $advisories_ok = @order <= $RANGES_LOOKUP_LIMIT;
    return (\%lookup, JSON::PP::true) unless @uniq;
    return (\%lookup, JSON::PP::false) if time >= $deadline || !defined $work_dir || !-d $work_dir;

    # GitHub のトークンを、持ち主だけが読めるファイルに書く。トークンを curl の引数に書かない
    my $header;
    my $token = _ranges_gh_token(_ranges_min($RANGES_GH_TIMEOUT, $deadline - time));
    if (defined $token) {
        $header = $RANGES_AUTH_FILE;
        unlink "$work_dir/$header";
        if (sysopen my $h, "$work_dir/$header", O_WRONLY | O_CREAT | O_EXCL, 0600) {
            my $written = print {$h} "Authorization: Bearer $token\n";
            undef $header unless close($h) && $written;
        } else {
            undef $header;
        }
    }
    $advisories_ok = 0 unless defined $header;

    my (@reqs, %file);
    my $n = 0;
    for my $cve (@pick) {
        $n++;
        push @reqs, { url => "$RANGES_CVE_URL$cve", out => "ranges-cve-$n.json" };
        $file{$cve}{cve} = $reqs[-1];
        next unless defined $header;
        push @reqs, { url => "$RANGES_GHSA_URL$cve", out => "ranges-ghsa-$n.json", github => 1 };
        $file{$cve}{ghsa} = $reqs[-1];
    }
    my $res = _ranges_curl($work_dir, \@reqs, $header, $deadline);
    unlink "$work_dir/$header" if defined $header;

    for my $cve (@pick) {
        my $record = _ranges_response($work_dir, $res, $file{$cve}{cve}, 'HASH');
        $record = undef unless $record && ref $record->{containers} eq 'HASH';
        my $ghsa = _ranges_response($work_dir, $res, $file{$cve}{ghsa}, 'ARRAY');
        _ranges_read_record($lookup{$cve}, $record) if $record;
        $lookup{$cve}{advisories} = _ranges_read_advisories($ghsa) if $ghsa;
        $advisories_ok = 0 unless $ghsa;
        $lookup{$cve}{looked_up} = $record && $ghsa ? JSON::PP::true : JSON::PP::false;
    }
    return (\%lookup, $advisories_ok ? JSON::PP::true : JSON::PP::false);
}

sub _ranges_min { $_[0] < $_[1] ? $_[0] : $_[1] }

# 文字列の値だけを返す
sub _ranges_str { defined $_[0] && !ref $_[0] ? $_[0] : undef }

# CVE の記録の製品と説明と元の発表の URL を読む
sub _ranges_read_record {
    my ($entry, $record) = @_;
    my $c = $record->{containers};
    my @from = (['cna', $c->{cna}]);
    for my $adp (ref $c->{adp} eq 'ARRAY' ? @{ $c->{adp} } : ()) {
        next unless ref $adp eq 'HASH' && ref $adp->{providerMetadata} eq 'HASH';
        push @from, ['adp', $adp] if (_ranges_str($adp->{providerMetadata}{shortName}) // '') eq 'CISA-ADP';
    }
    for my $f (@from) {
        my ($name, $container) = @$f;
        next unless ref $container eq 'HASH' && ref $container->{affected} eq 'ARRAY';
        for my $aff (@{ $container->{affected} }) {
            next unless ref $aff eq 'HASH';
            my %p = (from => $name, versions => []);
            for my $k (qw(vendor product packageName collectionURL defaultStatus)) {
                my $v = _ranges_str($aff->{$k});
                $p{$k} = $v if defined $v;
            }
            for my $v (ref $aff->{versions} eq 'ARRAY' ? @{ $aff->{versions} } : ()) {
                next unless ref $v eq 'HASH';
                my %r;
                for my $k (qw(version lessThan lessThanOrEqual status versionType)) {
                    my $s = _ranges_str($v->{$k});
                    $r{$k} = $s if defined $s;
                }
                if (ref $v->{changes} eq 'ARRAY') {
                    $r{changes} = [ map { { at => $_->{at}, status => $_->{status} } }
                            grep { ref $_ eq 'HASH' && defined _ranges_str($_->{at}) && defined _ranges_str($_->{status}) } @{ $v->{changes} } ];
                }
                push @{ $p{versions} }, \%r;
            }
            push @{ $entry->{products} }, \%p;
        }
    }
    my $cna = ref $c->{cna} eq 'HASH' ? $c->{cna} : {};
    for my $d (ref $cna->{descriptions} eq 'ARRAY' ? @{ $cna->{descriptions} } : ()) {
        next unless ref $d eq 'HASH' && (_ranges_str($d->{lang}) // '') =~ /\Aen\b/i;
        my $text = _ranges_str($d->{value});
        next unless defined $text;
        $entry->{descriptions}{en} = length $text > $RANGES_DESCRIPTION_MAX ? substr($text, 0, $RANGES_DESCRIPTION_MAX) : $text;
        last;
    }
    my %seen;
    for my $r (ref $cna->{references} eq 'ARRAY' ? @{ $cna->{references} } : ()) {
        last if @{ $entry->{vendor_advisories} } >= $RANGES_VENDOR_ADVISORY_MAX;
        next unless ref $r eq 'HASH' && ref $r->{tags} eq 'ARRAY' && grep { defined $_ && !ref $_ && $_ eq 'vendor-advisory' } @{ $r->{tags} };
        my $url = _ranges_str($r->{url});
        next unless defined $url && $url =~ m{\Ahttps?://\S+\z} && !$seen{$url}++;
        push @{ $entry->{vendor_advisories} }, $url;
    }
}

# GitHub の勧告の一覧を読む
sub _ranges_read_advisories {
    my ($list) = @_;
    my @out;
    for my $item (@$list) {
        next unless ref $item eq 'HASH';
        my %adv = (ghsa_id => _ranges_str($item->{ghsa_id}), repository_advisory_url => _ranges_str($item->{repository_advisory_url}), vulnerabilities => []);
        for my $v (ref $item->{vulnerabilities} eq 'ARRAY' ? @{ $item->{vulnerabilities} } : ()) {
            next unless ref $v eq 'HASH';
            my $package = ref $v->{package} eq 'HASH' ? $v->{package} : {};
            # first_patched_version は、文字列か、identifier を持つ形で返る
            my $fixed = $v->{first_patched_version};
            $fixed = $fixed->{identifier} if ref $fixed eq 'HASH';
            push @{ $adv{vulnerabilities} }, {
                ecosystem => _ranges_str($package->{ecosystem}),
                name => _ranges_str($package->{name}),
                vulnerable_version_range => _ranges_str($v->{vulnerable_version_range}),
                first_patched_version => _ranges_str($fixed),
            };
        }
        push @out, \%adv;
    }
    return \@out;
}

# 要求の応答を読む。状態が 200 で、JSON の形が $type のときだけ値を返す
sub _ranges_response {
    my ($work_dir, $res, $req, $type) = @_;
    return undef unless $req && $res->{ $req->{url} } && $res->{ $req->{url} }{code} eq '200';
    open my $h, '<:raw', "$work_dir/$req->{out}" or return undef;
    my $raw = do { local $/; <$h> };
    close $h;
    my $json = eval { JSON::PP->new->utf8->decode($raw) };
    return ref $json eq $type ? $json : undef;
}

# gh auth token でトークンを得る。得られなければ undef を返す
sub _ranges_gh_token {
    my ($seconds) = @_;
    return undef unless $seconds > 0;
    my $out;
    my $rc = _ranges_run_limited($seconds, \$out, 'gh', 'auth', 'token');
    return undef unless $rc == 0 && defined $out;
    $out =~ s/\A\s+//;
    $out =~ s/\s+\z//;
    # ヘッダーの1行を壊す文字を持つ値は使わない
    return $out =~ /\A[\x21-\x7e]+\z/ ? $out : undef;
}

# コマンドを動かし、決めた秒数で打ち切る。標準出力を $$out に入れ、終了コードを返す。
# シグナルで終わったときと、打ち切ったときと、動かせなかったときは -1 を返す。
# 標準入力と標準エラーは捨て、gh が認証を尋ねて止まらないようにする
sub _ranges_run_limited {
    my ($seconds, $out, @cmd) = @_;
    pipe(my $r, my $w) or return -1;
    my $pid = fork;
    if (!defined $pid) {
        close $r;
        close $w;
        return -1;
    }
    if (!$pid) {
        my $null = File::Spec->devnull;
        close $r;
        open STDIN, '<', $null;
        open STDOUT, '>&', $w;
        open STDERR, '>', $null;
        $ENV{GH_PROMPT_DISABLED} = '1';
        exec(@cmd) or POSIX::_exit(127);
    }
    close $w;
    my $buf = '';
    my $until = time + $seconds;
    while (time < $until) {
        if ($r) {
            # 子が標準出力を閉じるまで読む。パイプが詰まって子が止まらないよう、終わりを待つ前に読み切る
            my $rin = '';
            vec($rin, fileno($r), 1) = 1;
            next unless select(my $rout = $rin, undef, undef, 0.1) > 0;
            my $n = sysread($r, $buf, 65536, length $buf);
            next if !defined $n && $! == POSIX::EINTR();
            if (!$n) {
                close $r;
                undef $r;
            }
            next;
        }
        if (waitpid($pid, WNOHANG) == $pid) {
            $$out = $buf;
            return $? == 0 ? 0 : (($? >> 8) || -1);
        }
        select(undef, undef, undef, 0.1);
    }
    close $r if $r;
    kill 'TERM', $pid;
    for (1 .. 20) {
        return -1 if waitpid($pid, WNOHANG) == $pid;
        select(undef, undef, undef, 0.1);
    }
    kill 'KILL', $pid;
    waitpid($pid, 0);
    return -1;
}

# curl を1回動かし、要求を並列に取る。$reqs は [{url, out, github}]。
# 引数は設定ファイルで渡す(URL が数百あると、Windows のコマンドの行の長さの上限を超えるため)。
# github が真の要求にだけ、$header のファイルを -H @<ファイル> で付ける。
# $deadline の時刻を過ぎたら curl を止め、それまでに出た -w の行を読む。{<URL> => {code}} を返す
sub _ranges_curl {
    my ($work_dir, $reqs, $header, $deadline) = @_;
    my %res;
    return \%res unless @$reqs;
    my $q = sub { (my $s = $_[0]) =~ s/([\\"])/\\$1/g; "\"$s\"" };
    my @lines;
    for my $i (0 .. $#$reqs) {
        my $req = $reqs->[$i];
        unlink "$work_dir/$req->{out}";
        push @lines, '--next' if $i > 0;
        push @lines, "--max-time $RANGES_CURL_MAX_TIME", '-s', '--compressed', '-A KeirekiPro-vuln-watch';
        if ($req->{github}) {
            push @lines, '-H ' . $q->("\@$header"), '-H ' . $q->('Accept: application/vnd.github+json'),
                '-H ' . $q->('X-GitHub-Api-Version: 2022-11-28');
        }
        push @lines, '-o ' . $q->($req->{out}), '-w "%{url_effective} %{http_code}\n"', 'url = ' . $q->($req->{url});
    }
    my $config = 'ranges-curl.cfg';
    my $out = 'ranges-curl.out';
    unlink "$work_dir/$out";
    open my $c, '>', "$work_dir/$config" or return \%res;
    print {$c} map { "$_\n" } @lines;
    close $c or return \%res;
    my $pid = fork;
    return \%res unless defined $pid;
    if ($pid == 0) {
        chdir $work_dir or POSIX::_exit(126);
        open STDIN, '<', File::Spec->devnull;
        open STDOUT, '>', $out or POSIX::_exit(126);
        open STDERR, '>', 'ranges-curl.err';
        exec('curl', '-s', '--parallel', '--parallel-max', $RANGES_CURL_PARALLEL, '-K', $config) or POSIX::_exit(127);
    }
    my $reaped = 0;
    while (!$reaped && time < $deadline) {
        $reaped = waitpid($pid, WNOHANG) == $pid;
        select(undef, undef, undef, 0.1) unless $reaped;
    }
    if (!$reaped) {
        kill 'TERM', $pid;
        for (1 .. 20) {
            $reaped = waitpid($pid, WNOHANG) == $pid;
            last if $reaped;
            select(undef, undef, undef, 0.1);
        }
    }
    if (!$reaped) {
        kill 'KILL', $pid;
        waitpid($pid, 0);
    }
    if (open my $f, '<', "$work_dir/$out") {
        while (my $line = <$f>) {
            $line =~ s/\r?\n\z//;
            my ($url, $code) = $line =~ /\A(\S+) (\d{3})\z/ or next;
            $res{$url} = { code => $code };
        }
        close $f;
    }
    return \%res;
}

1;
