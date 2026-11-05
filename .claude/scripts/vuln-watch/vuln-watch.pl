#!/usr/bin/env perl
# =====================================================================
# 直近7日に出た脆弱性を集め、このリポジトリの部品と突き合わせる入口のスクリプト
#
# 呼び出し方: perl .claude/scripts/vuln-watch/vuln-watch.pl collect
#   collect は、作業フォルダの最上位の .claude/.state/vuln-watch/ の下に実行のフォルダを作り、
#   feeds.pl と inventory.pl と ranges.pl の結果から、項目ごとの判定の案と、主の Claude が読む材料を書く。
#   標準出力に、実行の ID と、材料と項目のファイルと判断の JSON の場所と、項目の数を持つ JSON の1行を出す。
#   出どころと GitHub と記事のページへの要求が失敗しても 0 で終わり、失敗を材料の failed と github に残す。
#   作業フォルダが git のリポジトリでないときと、実行のフォルダを作れないときは、標準エラーに理由を1行出して 2 で終わる。
# 今の時刻は、テストのときだけ、環境変数 KP_VULN_WATCH_TEST_NOW の YYYY-MM-DDThh:mm:ssZ で替える。
# 前提: perl(JSON::PP・Time::Local)と、git・curl 7.66 以上・gh 2.x
# =====================================================================
use strict;
use warnings;
use utf8;
use JSON::PP ();
use File::Spec ();
use File::Basename qw(dirname);
use File::Path qw(remove_tree);
use Time::Local qw(timegm);
use POSIX qw(strftime);

my $VW_DIR = dirname(File::Spec->rel2abs(__FILE__));
my $VW_STATE = '.claude/.state/vuln-watch'; # 受け渡しの場所(作業フォルダの最上位からの場所)
my $VW_KEEP = 24 * 3600;                    # 古い実行のフォルダを消すまでの秒数
my $VW_WINDOW = 7 * 24 * 3600;              # 直近7日
my $VW_BUDGET = 150;                        # 外部への要求の全体を打ち切る秒数
my $VW_NAME_MIN = 4;                        # 名前の手がかりに使う部品の鍵の名前の、最も短い文字数
my $VW_NAME_HITS_MAX = 10;                  # 名前の手がかりに入れる部品の鍵の数
my $VW_RUN_ID = qr/\A(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z-\d+\z/;

my $VW_JSON = JSON::PP->new->utf8->canonical->pretty->indent_length(1);

exit main(@ARGV);

sub main {
    my ($command) = @_;
    return collect() if defined $command && $command eq 'collect' && @_ == 1;
    print STDERR "vuln-watch.pl: 使い方: perl vuln-watch.pl collect\n";
    return 2;
}

# ---------------------------------------------------------------------
# collect
# ---------------------------------------------------------------------
sub collect {
    my $now = _vw_now();
    my $root = _vw_toplevel() // _vw_fail('作業フォルダが git のリポジトリでない');
    my $state = "$root/$VW_STATE";
    _vw_mkpath($state) or _vw_fail("受け渡しの場所を作れない: $state");
    _vw_remove_old($state, $now);
    my $run = strftime('%Y%m%dT%H%M%SZ', gmtime $now) . "-$$";
    my $run_dir = "$state/$run";
    mkdir $run_dir or _vw_fail("実行のフォルダを作れない: $run_dir");
    my $work = "$run_dir/work";
    mkdir $work or _vw_fail("実行のフォルダの中に作業の場所を作れない: $work");

    require "$VW_DIR/feeds.pl";
    require "$VW_DIR/inventory.pl";
    require "$VW_DIR/ranges.pl";
    my $deadline = time + $VW_BUDGET;

    my $feeds = feeds_collect($now, $work);
    my @items = @{ $feeds->{items} };
    my $inventory = inventory_read($root);
    my $aliases = _vw_read_json("$VW_DIR/aliases.json");
    my $kev_names = _vw_kev_names($feeds->{kev});
    my ($cves, $priority) = _vw_lookup_order(\@items);
    my ($lookup, $advisories_ok) = ranges_lookup($cves, $priority, $inventory, $aliases, $kev_names, $work, $deadline);
    my $matches = ranges_match($lookup, $inventory, $aliases, $kev_names);
    my ($refs, $refs_ok) = ranges_refs({ map { $_->{key} => { cves => $_->{cves} } } @items }, $matches);

    my $components = $inventory->{components} // {};
    my $kev_info = _vw_kev_info($feeds->{kev});
    my $names = _vw_component_names($components);
    my @entries = map { _vw_entry($_, $lookup, $matches, $refs, $kev_info, $names) } @items;
    my $entries_file = "$run_dir/entries-1.json";
    my $material_file = "$run_dir/material.json";
    my %counts = (npm => 0, maven => 0);
    for my $key (keys %$components) {
        $counts{$1}++ if $key =~ /\A(npm|maven):/;
    }
    my $material = {
        version      => 1,
        run          => $run,
        collected_at => _vw_iso($now),
        window_from  => _vw_iso($now - $VW_WINDOW),
        failed       => $feeds->{failed},
        github       => {
            advisories_ok => _vw_bool($advisories_ok),
            sbom_ok       => _vw_bool($inventory->{sbom_ok}),
            refs_ok       => _vw_bool($refs_ok),
        },
        inventory => {
            ref     => $inventory->{ref},
            commit  => $inventory->{commit},
            fetched => _vw_bool($inventory->{fetched}),
            keys    => [ sort keys %$components ],
            counts  => \%counts,
        },
        parts => [ _vw_text($entries_file) ],
    };
    _vw_write_json($entries_file, { entries => \@entries }) or _vw_fail("材料を書けない: $entries_file");
    _vw_write_json($material_file, $material) or _vw_fail("材料を書けない: $material_file");
    remove_tree($work);
    print JSON::PP->new->utf8->canonical->encode({
        run      => $run,
        material => _vw_text($material_file),
        parts    => [ _vw_text($entries_file) ],
        result   => _vw_text("$run_dir/result.json"),
        entries  => scalar @entries,
    }), "\n";
    return 0;
}

# 項目の1つを、材料の項目にする
sub _vw_entry {
    my ($item, $lookup, $matches, $refs, $kev_info, $names) = @_;
    my @cves = @{ $item->{cves} };
    my (%descriptions, @products, @matches, %seen, @kev_dates);
    my $feeds_descriptions = $item->{descriptions} // {};
    for my $cve (@cves) {
        my $l = $lookup->{$cve} // {};
        my $text = $l->{descriptions}{en} // $feeds_descriptions->{$cve};
        $descriptions{$cve} = $text if defined $text;
        push @products, _vw_products($l);
        push @kev_dates, $kev_info->{$cve}{date} if $kev_info->{$cve} && defined $kev_info->{$cve}{date};
        for my $m (@{ $matches->{$cve}{matches} // [] }) {
            push @matches, $m unless $seen{ JSON::PP->new->canonical->encode($m) }++;
        }
    }
    my $item_refs = $refs->{ $item->{key} } // [];
    return {
        key          => $item->{key},
        cves         => \@cves,
        sources      => $item->{sources},
        article_ok   => _vw_bool($item->{article_ok}),
        # 番号のどれかが KEV に載っていれば、最も早く載った日を入れる
        kev          => @kev_dates ? (sort @kev_dates)[0] : undef,
        descriptions => \%descriptions,
        article_text => $item->{article_text},
        products     => \@products,
        origins      => [ _vw_origins($item, $lookup, $kev_info) ],
        name_hits    => [ _vw_name_hits($item, \%descriptions, $names) ],
        matches      => \@matches,
        refs         => $item_refs,
        suggested    => _vw_suggest($item, \@matches, $item_refs),
    };
}

# 判定の案を決める。引けなかった番号は、鍵 * で in_range が null の部品として matches に入っている
sub _vw_suggest {
    my ($item, $matches, $refs) = @_;
    my @in = map { $_->{in_range} } @$matches;
    return 'affected' if grep { defined && $_ } @in;
    return 'affected' if grep { ($_->{kind} // '') eq 'issue' } @$refs;
    return 'undeterminable' if grep { !defined } @in;
    # 記事のページを取れなかった項目は、題名で省かれた番号の部品を見落とすおそれがあるので、決められないとする
    return 'undeterminable' unless $item->{article_ok};
    return @in ? 'not_affected' : 'unrelated';
}

# CVE の番号の1つについて、CVE の記録と GitHub の勧告と NVD の製品の名前と範囲を並べる
sub _vw_products {
    my ($l) = @_;
    my @products;
    for my $p (@{ $l->{products} // [] }) {
        push @products, {
            from => $p->{from}, vendor => $p->{vendor}, product => $p->{product},
            package => $p->{packageName}, ranges => $p->{versions} // [],
        };
    }
    $_->{fixed} = _vw_fixed('cve', $_->{ranges}) for @products;
    my (%github, @github_order);
    for my $a (@{ $l->{advisories} // [] }) {
        for my $v (@{ $a->{vulnerabilities} // [] }) {
            my $name = join ':', map { $_ // '' } @$v{qw(ecosystem name)};
            push @github_order, $name unless $github{$name};
            $github{$name} //= { from => 'github', vendor => $v->{ecosystem}, product => $v->{name}, package => $v->{name}, ranges => [] };
            push @{ $github{$name}{ranges} }, { map { $_ => $v->{$_} } qw(vulnerable_version_range first_patched_version) };
        }
    }
    $github{$_}{fixed} = _vw_fixed('ghsa', $github{$_}{ranges}) for @github_order;
    push @products, map { $github{$_} } @github_order;
    my (%nvd, @nvd_order);
    for my $c (@{ $l->{nvd} // [] }) {
        my @f = split /:/, $c->{criteria} // '';
        my $name = join ':', map { $_ // '' } @f[3, 4];
        push @nvd_order, $name unless $nvd{$name};
        $nvd{$name} //= { from => 'nvd', vendor => $f[3], product => $f[4], package => undef, ranges => [] };
        push @{ $nvd{$name}{ranges} }, $c;
    }
    $nvd{$_}{fixed} = _vw_fixed('nvd', $nvd{$_}{ranges}) for @nvd_order;
    push @products, map { $nvd{$_} } @nvd_order;
    return @products;
}

# 製品の範囲ごとに直った版を決め、null を除いて範囲の順に ", " でつなぐ。どの範囲からも得られなければ undef を返す
sub _vw_fixed {
    my ($source, $ranges) = @_;
    my @fixed = grep { defined } map { ranges_fixed($source, $_) } @{ $ranges // [] };
    return @fixed ? join(', ', @fixed) : undef;
}

# KEV の本文から、CVE の番号ごとの、載った日(dateAdded)と notes の URL を作る。
# notes の URL のうち、CISA が連邦機関に向けて出した指令の URL は、元の発表ではないので除く(feeds.pl と同じ決まり)
sub _vw_kev_info {
    my ($kev) = @_;
    my %info;
    for my $v (ref $kev eq 'HASH' && ref $kev->{vulnerabilities} eq 'ARRAY' ? @{ $kev->{vulnerabilities} } : ()) {
        next unless ref $v eq 'HASH' && defined $v->{cveID} && !ref $v->{cveID};
        my $i = $info{ $v->{cveID} } //= { date => undef, notes => [] };
        my $date = defined $v->{dateAdded} && !ref $v->{dateAdded} ? $v->{dateAdded} : undef;
        $i->{date} = $date if defined $date && (!defined $i->{date} || $date lt $i->{date});
        my $notes = defined $v->{notes} && !ref $v->{notes} ? $v->{notes} : '';
        push @{ $i->{notes} }, grep { !m{\Ahttps?://(?:www\.)?cisa\.gov/news-events/directives/} } $notes =~ m{(https?://[^\s;]+)}g;
    }
    return \%info;
}

# 元の発表の URL を、KEV の notes の URL、JPCERT/CC と IPA の記事の URL、CVE の記録の vendor-advisory の URL の順に、
# 重複を除いて並べる。ほかの URL が無い CVE の番号には、cve.org の URL を足す。cvemon のページの URL は入れない。
# 記事は項目のどの番号も扱うので、記事の URL がある項目の番号には cve.org の URL を足さない
sub _vw_origins {
    my ($item, $lookup, $kev_info) = @_;
    my @cves = @{ $item->{cves} };
    my @articles = map { $_->{url} } grep { ($_->{source} eq 'jpcert' || $_->{source} eq 'ipa') && defined $_->{url} } @{ $item->{sources} };
    my (%has, @urls);
    for my $cve (@cves) {
        my @notes = @{ ($kev_info->{$cve} // {})->{notes} // [] };
        push @urls, @notes;
        $has{$cve} = 1 if @notes || @articles;
    }
    push @urls, @articles;
    for my $cve (@cves) {
        my @advisories = @{ ($lookup->{$cve} // {})->{vendor_advisories} // [] };
        push @urls, @advisories;
        $has{$cve} = 1 if @advisories;
    }
    push @urls, map { "https://www.cve.org/CVERecord?id=$_" } grep { !$has{$_} } @cves;
    my %seen;
    return grep { !$seen{$_}++ } @urls;
}

# 部品の鍵ごとに、名前の手がかりに使う名前を語として探す正規表現を作る。npm の部品はパッケージの名前、Maven の部品は
# artifact の名前、そのほかの部品は : よりあとの最後の / よりあとの部分を名前とする。4文字より短い名前の鍵は使わない
sub _vw_component_names {
    my ($components) = @_;
    my %names;
    for my $key (sort keys %$components) {
        my ($kind, $rest) = $key =~ /\A([^:]+):(.+)\z/ or next;
        my ($name) = $kind eq 'npm' ? ($rest)
            : $kind eq 'maven' ? ($rest =~ /([^:]+)\z/)
            : ($rest =~ m{([^/]+)\z});
        next unless defined $name && length $name >= $VW_NAME_MIN;
        $names{$key} = qr/(?<![A-Za-z0-9_])\Q$name\E(?![A-Za-z0-9_])/i;
    }
    return \%names;
}

# 部品の鍵の名前が、項目の題名と説明と記事の本文に語として出る部品の鍵を、鍵の順に10件まで返す
sub _vw_name_hits {
    my ($item, $descriptions, $names) = @_;
    my $text = join "\n", (map { $_->{title} // '' } @{ $item->{sources} }),
        (map { $descriptions->{$_} } sort keys %$descriptions), $item->{article_text} // '';
    my @hits = grep { $text =~ $names->{$_} } sort keys %$names;
    splice @hits, $VW_NAME_HITS_MAX if @hits > $VW_NAME_HITS_MAX;
    return @hits;
}

# KEV の本文から、CVE の番号ごとの [vendorProject, product] の組の一覧を作る
sub _vw_kev_names {
    my ($kev) = @_;
    my %names;
    for my $v (ref $kev eq 'HASH' && ref $kev->{vulnerabilities} eq 'ARRAY' ? @{ $kev->{vulnerabilities} } : ()) {
        next unless ref $v eq 'HASH' && defined $v->{cveID} && !ref $v->{cveID};
        push @{ $names{ $v->{cveID} } }, [ $v->{vendorProject}, $v->{product} ];
    }
    return \%names;
}

# CVE の番号を引く順を決める。KEV と cvemon の出どころの番号を先に引く値を %priority に入れ、
# そのほかの番号を、持つ CVE の番号の少ない項目の番号から順に並べる
sub _vw_lookup_order {
    my ($items) = @_;
    my %priority;
    for my $item (@$items) {
        for my $s (@{ $item->{sources} }) {
            next unless ($s->{source} eq 'kev' || $s->{source} eq 'cvemon') && defined $s->{id};
            $priority{ $s->{id} } = 0;
        }
    }
    my @order = sort { @{ $items->[$a]{cves} } <=> @{ $items->[$b]{cves} } || $a <=> $b } 0 .. $#$items;
    my %seen;
    my @cves = grep { !$seen{$_}++ } map { @{ $items->[$_]{cves} } } @order;
    return (\@cves, \%priority);
}

# ---------------------------------------------------------------------
# 共通の処理
# ---------------------------------------------------------------------

# 受け渡しの場所の下の、実行の ID の形の名前を持つフォルダのうち、作られてから1日より古いものを消す
sub _vw_remove_old {
    my ($state, $now) = @_;
    opendir my $d, $state or return;
    my @names = readdir $d;
    closedir $d;
    for my $name (@names) {
        next unless $name =~ $VW_RUN_ID && -d "$state/$name";
        my $made = eval { timegm($6, $5, $4, $3, $2 - 1, $1) } // next;
        remove_tree("$state/$name") if $now - $made > $VW_KEEP;
    }
}

# 今のフォルダで git rev-parse --show-toplevel を動かし、作業フォルダの最上位を返す。git のリポジトリでなければ undef を返す
sub _vw_toplevel {
    open my $saved, '>&', \*STDERR or return undef;
    open STDERR, '>', File::Spec->devnull;
    my $ok = open my $h, '-|', 'git', 'rev-parse', '--show-toplevel';
    my $out = $ok ? do { local $/; <$h> } : undef;
    my $closed = $ok ? close $h : 0;
    open STDERR, '>&', $saved;
    return undef unless $closed && defined $out;
    $out =~ s/\s+\z//;
    return length $out ? $out : undef;
}

sub _vw_now {
    my $t = $ENV{KP_VULN_WATCH_TEST_NOW};
    if (defined $t && $t =~ /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z\z/) {
        return timegm($6, $5, $4, $3, $2 - 1, $1);
    }
    return int time;
}

# ファイルの場所のバイトの列を、JSON に書く文字の列にする。git は場所を UTF-8 で返す
sub _vw_text {
    my ($path) = @_;
    utf8::decode($path);
    return $path;
}

sub _vw_iso { strftime('%Y-%m-%dT%H:%M:%SZ', gmtime $_[0]) }

sub _vw_bool { $_[0] ? JSON::PP::true : JSON::PP::false }

sub _vw_mkpath {
    my ($path) = @_;
    return 1 if -d $path;
    my $parent = dirname($path);
    return 0 if $parent eq $path;
    return 0 unless _vw_mkpath($parent);
    return mkdir($path) || -d $path;
}

sub _vw_read_json {
    my ($file) = @_;
    open my $h, '<:raw', $file or return {};
    my $text = do { local $/; <$h> };
    close $h;
    my $value = eval { JSON::PP->new->utf8->decode($text) };
    return ref $value eq 'HASH' ? $value : {};
}

sub _vw_write_json {
    my ($file, $value) = @_;
    open my $h, '>:raw', $file or return 0;
    my $written = print {$h} $VW_JSON->encode($value);
    return close($h) && $written;
}

sub _vw_fail {
    my ($message) = @_;
    binmode STDERR, ':encoding(UTF-8)';
    print STDERR "vuln-watch.pl: $message\n";
    exit 2;
}
