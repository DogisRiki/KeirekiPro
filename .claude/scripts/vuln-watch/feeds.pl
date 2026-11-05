# =====================================================================
# 4つの出どころを取り、直近7日の項目に直すモジュール
#
# vuln-watch.pl が require で読み込む。呼び出し方は feeds_collect($now, $work_dir) だけで、
# {items => [...], failed => [{source, name, error}], kev => <KEV の本文を読んだ値か undef>} を返す。
# このモジュールはファイルを書かない。ただし、curl が書くファイルだけを $work_dir に置く。
# 前提: perl(JSON::PP・Time::Local・POSIX)と curl 7.66 以上
# =====================================================================
use strict;
use warnings;
use utf8;
use JSON::PP ();
use File::Spec ();
use Time::Local qw(timegm);
use POSIX qw(WNOHANG);

# 出どころの順と、名前と URL
my @FEEDS_SOURCES = (
    { source => 'kev', name => 'CISA の実際に悪用された脆弱性の一覧', url => 'https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json', type => 'json' },
    { source => 'jpcert', name => 'JPCERT/CC の注意喚起', url => 'https://www.jpcert.or.jp/rss/jpcert.rdf', type => 'xml' },
    { source => 'ipa', name => 'IPA の重要なセキュリティ情報', url => 'https://www.ipa.go.jp/security/alert-rss.rdf', type => 'xml' },
    { source => 'cvemon', name => 'cvemon の話題の一覧', url => 'https://cvemon.intruder.io/rss/cvetrends/latest', type => 'xml' },
);

my $FEEDS_BUDGET = 40;            # 2回の curl の呼び出しを合わせて打ち切る秒数
my $FEEDS_WINDOW = 7 * 24 * 3600; # 直近7日
my $FEEDS_JST = 9 * 3600;         # IPA の日付を読む時間帯(UTC+9)

sub feeds_collect {
    my ($now, $work_dir) = @_;
    my $deadline = time + $FEEDS_BUDGET;
    my $from = $now - $FEEDS_WINDOW;
    my (@items, @failed, $kev);

    my @reqs = map { { url => $_->{url}, out => "$_->{source}.body" } } @FEEDS_SOURCES;
    my $res = _feeds_curl($work_dir, \@reqs, [ '--parallel', '--parallel-max', '4' ], [ '--max-time', '20' ], $deadline, 'feeds');

    for my $src (@FEEDS_SOURCES) {
        my $r = $res->{ $src->{url} };
        my ($body, $error) = _feeds_body($work_dir, $src, $r, $res);
        if (defined $error) {
            push @failed, { source => $src->{source}, name => $src->{name}, error => $error };
            next;
        }
        if ($src->{source} eq 'kev') {
            $kev = $body;
            push @items, _feeds_kev_items($body, $from);
        } elsif ($src->{source} eq 'jpcert') {
            push @items, _feeds_rdf_items($body, 'jpcert', $from);
        } elsif ($src->{source} eq 'ipa') {
            push @items, _feeds_rdf_items($body, 'ipa', $from);
        } else {
            push @items, _feeds_cvemon_items($body);
        }
    }
    return { items => \@items, failed => \@failed, kev => $kev };
}

# 出どころの本文を読む。読めたときは (読んだ値, undef) を、読めないときは (undef, 理由) を返す
sub _feeds_body {
    my ($work_dir, $src, $r, $res) = @_;
    unless (defined $r) {
        return (undef, "$FEEDS_BUDGET 秒で打ち切り") if $res->{_timed_out};
        return (undef, "curl が応答を返さなかった(終了コード $res->{_exit})");
    }
    return (undef, 'つながらなかった') if $r->{code} eq '000';
    return (undef, "HTTP $r->{code}") if $r->{code} ne '200';
    my $path = "$work_dir/$src->{source}.body";
    open my $f, '<:raw', $path or return (undef, '本文を読めない');
    my $raw = do { local $/; <$f> };
    close $f;
    if ($src->{type} eq 'json') {
        my $v = eval { JSON::PP->new->utf8->decode($raw) };
        return (undef, 'JSON として読めない') unless ref $v eq 'HASH' && ref $v->{vulnerabilities} eq 'ARRAY';
        return ($v, undef);
    }
    utf8::decode($raw);
    $raw =~ s/\A\x{FEFF}//;
    $raw =~ s/\A\s*(?:<\?xml[^>]*\?>\s*)?//;
    my $ok = $raw =~ /\A<rdf:RDF\b/ ? $raw =~ m{</rdf:RDF>\s*\z} : $raw =~ /\A<rss\b/ ? $raw =~ m{</rss>\s*\z} : 0;
    return (undef, 'XML として読めない') unless $ok;
    return ($raw, undef);
}

# curl を1回動かす。$reqs は [{url, out}]。$common は呼び出しの頭に、$per は URL ごとに付けるオプション。
# $deadline の時刻を過ぎたら、curl を止める。止めたあとも、それまでに出た -w の行を読む。
# {<URL> => {code}, _exit => 終了コード, _timed_out => 真偽} を返す
sub _feeds_curl {
    my ($work_dir, $reqs, $common, $per, $deadline, $tag) = @_;
    my @args = @$common;
    for my $i (0 .. $#$reqs) {
        push @args, '--next' if $i > 0;
        push @args, @$per, '--compressed', '-s', '-A', 'KeirekiPro-vuln-watch', '-o', $reqs->[$i]{out},
            '-w', '%{url_effective} %{http_code}\n', $reqs->[$i]{url};
    }
    my $out = "$tag.curl-out";
    my %res = (_exit => -1, _timed_out => 0);
    my $pid = fork;
    unless (defined $pid) {
        $res{_exit} = -1;
        return \%res;
    }
    if ($pid == 0) {
        chdir $work_dir or POSIX::_exit(126);
        open STDIN, '<', File::Spec->devnull;
        open STDOUT, '>', $out or POSIX::_exit(126);
        open STDERR, '>', "$tag.curl-err";
        exec 'curl', @args;
        POSIX::_exit(127);
    }
    my $done = 0;
    while (1) {
        my $w = waitpid($pid, WNOHANG);
        if ($w == $pid) {
            $res{_exit} = $? >> 8;
            $done = 1;
            last;
        }
        last if time >= $deadline;
        select(undef, undef, undef, 0.1);
    }
    unless ($done) {
        $res{_timed_out} = 1;
        kill 'TERM', $pid;
        for (1 .. 20) {
            last if waitpid($pid, WNOHANG) == $pid;
            select(undef, undef, undef, 0.1);
        }
        if (kill 0, $pid) {
            kill 'KILL', $pid;
            waitpid($pid, 0);
        }
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

# 日付の文字列を、時刻(UTC の秒)に直す。時刻を持たない日付と、読めない文字列には undef を返す
sub _feeds_epoch {
    my ($s) = @_;
    my ($y, $mo, $d, $h, $mi, $sec, $tz) = ($s // '') =~ /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:\d{2})\z/ or return undef;
    my $t = eval { timegm($sec // 0, $mi, $h, $d, $mo - 1, $y) };
    return undef unless defined $t;
    if ($tz ne 'Z') {
        my ($sign, $th, $tm) = $tz =~ /\A([+-])(\d{2}):(\d{2})\z/;
        my $off = $th * 3600 + $tm * 60;
        $t -= $sign eq '+' ? $off : -$off;
    }
    return $t;
}

# 時刻を、$offset 秒ずらした時間帯の日付(YYYY-MM-DD)で表す
sub _feeds_day {
    my ($t, $offset) = @_;
    my @g = gmtime($t + $offset);
    return sprintf '%04d-%02d-%02d', $g[5] + 1900, $g[4] + 1, $g[3];
}

# 日付か時刻を、$offset 秒ずらした時間帯の日付で表す。読めなければ undef
sub _feeds_local_day {
    my ($s, $offset) = @_;
    return $1 if ($s // '') =~ /\A(\d{4}-\d{2}-\d{2})\z/;
    my $t = _feeds_epoch($s);
    return defined $t ? _feeds_day($t, $offset) : undef;
}

sub _feeds_cves {
    my %seen;
    my @c = grep { !$seen{$_}++ } map { /(CVE-\d{4}-\d{4,})/g } @_;
    return sort { _feeds_cve_cmp($b, $a) } @c;
}

sub _feeds_cve_cmp {
    my ($x, $y) = @_;
    my ($xy, $xn) = $x =~ /\ACVE-(\d+)-(\d+)\z/;
    my ($yy, $yn) = $y =~ /\ACVE-(\d+)-(\d+)\z/;
    return $xy <=> $yy || $xn <=> $yn;
}

sub _feeds_item {
    my ($cves, $source, %more) = @_;
    my @cves = @$cves;
    my ($key) = sort { _feeds_cve_cmp($a, $b) } @cves;
    return {
        key          => $key // $source->{url},
        cves         => \@cves,
        sources      => [$source],
        article_ok   => $more{article_ok} ? JSON::PP::true : JSON::PP::false,
        article_text => $more{article_text},
        descriptions => $more{descriptions} // {},
    };
}

sub _feeds_kev_items {
    my ($kev, $from) = @_;
    my $from_day = _feeds_day($from, 0);
    my @items;
    for my $v (@{ $kev->{vulnerabilities} }) {
        next unless ref $v eq 'HASH';
        my $cve = $v->{cveID} // '';
        next unless $cve =~ /\ACVE-\d{4}-\d{4,}\z/;
        my $day = _feeds_local_day($v->{dateAdded}, 0);
        next unless defined $day && $day ge $from_day;
        # notes の URL のうち、CISA が連邦機関に向けて出した指令の URL は、元の発表ではないので除く
        my @notes = grep { !m{\Ahttps?://(?:www\.)?cisa\.gov/news-events/directives/} } ($v->{notes} // '') =~ m{(https?://[^\s;]+)}g;
        push @items, _feeds_item([$cve], {
            source      => 'kev',
            id          => $cve,
            title       => $v->{vulnerabilityName},
            url         => undef,
            published   => $v->{dateAdded},
            rank        => undef,
            vendor      => $v->{vendorProject},
            product     => $v->{product},
            description => $v->{shortDescription},
            notes       => \@notes,
        }, article_ok => 1, descriptions => { $cve => $v->{shortDescription} });
    }
    return @items;
}

sub _feeds_text {
    my ($s) = @_;
    return undef unless defined $s;
    $s =~ s/<!\[CDATA\[(.*?)\]\]>/$1/gs;
    $s =~ s/&lt;/</g;
    $s =~ s/&gt;/>/g;
    $s =~ s/&quot;/"/g;
    $s =~ s/&apos;/'/g;
    $s =~ s/&#x([0-9A-Fa-f]+);/chr(hex $1)/ge;
    $s =~ s/&#(\d+);/chr($1)/ge;
    $s =~ s/&amp;/&/g;
    $s =~ s/\A\s+|\s+\z//g;
    return $s;
}

sub _feeds_tag {
    my ($xml, $tag) = @_;
    return $xml =~ m{<\Q$tag\E(?:\s[^>]*)?>(.*?)</\Q$tag\E>}s ? _feeds_text($1) : undef;
}

sub _feeds_xml_items {
    my ($xml) = @_;
    return $xml =~ m{<item\b[^>]*>(.*?)</item>}gs;
}

# JPCERT/CC と IPA の RSS の項目を、直近7日の項目に直す。同じ URL の項目は、dc:date の新しい1つだけを残す
sub _feeds_rdf_items {
    my ($xml, $source, $from) = @_;
    my $from_day = _feeds_day($from, $FEEDS_JST);
    my %by_url;
    my @order;
    for my $raw (_feeds_xml_items($xml)) {
        my $link = _feeds_tag($raw, 'link') // next;
        my $title = _feeds_tag($raw, 'title') // '';
        my $date = _feeds_tag($raw, 'dc:date') // next;
        if ($source eq 'jpcert') {
            next unless $link =~ m{/at/};
            my $t = _feeds_epoch($date);
            next unless defined $t && $t > $from;
        } else {
            my $day = _feeds_local_day($date, $FEEDS_JST);
            next unless defined $day && $day ge $from_day;
        }
        my $t = _feeds_epoch($date) // 0;
        my $id = $source eq 'jpcert' ? (_feeds_tag($raw, 'dc:identifier') // $link) : $link;
        my $entry = { t => $t, link => $link, src => { source => $source, id => $id, title => $title, url => $link, published => $date, rank => undef } };
        if (my $old = $by_url{$link}) {
            $by_url{$link} = $entry if $t > $old->{t};
            next;
        }
        $by_url{$link} = $entry;
        push @order, $link;
    }
    return map { _feeds_item([ _feeds_cves($by_url{$_}{src}{title}) ], $by_url{$_}{src}, article_ok => 0) } @order;
}

# cvemon の話題の一覧を、題名が CVE の番号の項目だけの一覧に直す。日付では区切らない
sub _feeds_cvemon_items {
    my ($xml) = @_;
    my @items;
    for my $raw (_feeds_xml_items($xml)) {
        my $title = _feeds_tag($raw, 'title') // next;
        next unless $title =~ /\ACVE-\d{4}-\d{4,}\z/;
        my $rank = _feeds_tag($raw, 'intruder:rank');
        push @items, _feeds_item([$title], {
            source    => 'cvemon',
            id        => $title,
            title     => $title,
            url       => _feeds_tag($raw, 'link'),
            published => _feeds_tag($raw, 'pubDate'),
            rank      => defined $rank && $rank =~ /\A\d+\z/ ? $rank + 0 : undef,
        }, article_ok => 1);
    }
    return @items;
}

1;
