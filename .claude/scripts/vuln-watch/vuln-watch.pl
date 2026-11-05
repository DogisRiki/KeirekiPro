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
# 呼び出し方: perl .claude/scripts/vuln-watch/vuln-watch.pl show --run <実行の ID>
#   show は、実行のフォルダの材料と、主の Claude が書いた判断の JSON(result.json)を読み、判断を確かめてから、
#   render.pl で組み立てた表示の文を実行のフォルダの show.md に書き、標準出力に {"show":"<show.md の場所>"} の1行を出す。
#   判断が材料と合わないときは、合わない項目の key と欄を標準エラーに1行ずつ出して 2 で終わり、show.md を書かない。
#   判断の JSON が無いか JSON として読めないときも 2 で終わる。実行のフォルダか材料か項目のファイルが無いときは 3 で終わる。
# 呼び出し方: perl .claude/scripts/vuln-watch/vuln-watch.pl clean --run <実行の ID>
#   clean は、実行のフォルダを中のファイルごと消す。実行のフォルダが無いときも 0 で終わる。
# show と clean は、<実行の ID> が実行の ID の形でないときは、標準エラーに理由を出して 2 で終わり、何も読み書きしない。
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
use Scalar::Util qw(refaddr);
use Time::Local qw(timegm);
use POSIX qw(strftime);

my $VW_DIR = dirname(File::Spec->rel2abs(__FILE__));
my $VW_STATE = '.claude/.state/vuln-watch'; # 受け渡しの場所(作業フォルダの最上位からの場所)
my $VW_KEEP = 24 * 3600;                    # 古い実行のフォルダを消すまでの秒数
my $VW_WINDOW = 7 * 24 * 3600;              # 直近7日
my $VW_BUDGET = 150;                        # 外部への要求の全体を打ち切る秒数
my $VW_NAME_MIN = 4;                        # 名前の手がかりに使う部品の鍵の名前の、最も短い文字数
my $VW_NAME_HITS_MAX = 10;                  # 名前の手がかりに入れる部品の鍵の数
my $VW_PRODUCTS_MAX = 10;                   # 1つの項目に入れる製品の数
my $VW_RANGES_MAX = 5;                      # 製品ごとに入れる範囲の数
my $VW_ORIGINS_MAX = 5;                     # 1つの項目に入れる元の発表の URL の数
my $VW_DESCRIPTIONS_FROM = 6;               # 説明を絞る、項目の CVE の番号の数
my $VW_DESCRIPTIONS_FIRST = 3;              # 説明を絞るときに残す、先頭の番号の数
my $VW_PART_BYTES = 40_000;                 # 項目のファイルの1つの大きさの上限
my %VW_KEEP_KEYS = map { $_ => 1 } ('npm:pnpm', 'npm:@openai/codex'); # 材料の部品の一覧に残す npm の鍵
my $VW_RUN_ID = qr/\A(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z-\d+\z/;

my $VW_JSON = JSON::PP->new->utf8->canonical->pretty->indent_length(1);

exit main(@ARGV);

sub main {
    my ($command, @args) = @_;
    $command //= '';
    return collect() if $command eq 'collect' && !@args;
    if (@args == 2 && $args[0] eq '--run') {
        return show($args[1]) if $command eq 'show';
        return clean($args[1]) if $command eq 'clean';
    }
    binmode STDERR, ':encoding(UTF-8)';
    print STDERR "vuln-watch.pl: 使い方: perl vuln-watch.pl collect | show --run <実行の ID> | clean --run <実行の ID>\n";
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
    my ($refs, $refs_ok) = ranges_refs({ map { $_->{key} => { cves => $_->{cves} } } @items }, $matches, $deadline);

    my $components = $inventory->{components} // {};
    my $kev_info = _vw_kev_info($feeds->{kev});
    my $names = _vw_component_names($components);
    my @entries = map { _vw_entry($_, $lookup, $matches, $refs, $kev_info, $names, $kev_names) } @items;
    my @parts = _vw_parts(\@entries);
    my @part_files = map { "$run_dir/entries-$_.json" } 1 .. @parts;
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
            # npm と Maven の部品は千件を超えるので、npm:pnpm と npm:@openai/codex のほかは数だけを入れる
            keys    => [ grep { !/\A(?:npm|maven):/ || $VW_KEEP_KEYS{$_} } sort keys %$components ],
            counts  => \%counts,
        },
        parts => [ map { _vw_text($_) } @part_files ],
    };
    for my $n (0 .. $#parts) {
        _vw_write_json($part_files[$n], { entries => $parts[$n] }) or _vw_fail("材料を書けない: $part_files[$n]");
    }
    _vw_write_json($material_file, $material) or _vw_fail("材料を書けない: $material_file");
    remove_tree($work);
    print JSON::PP->new->utf8->canonical->encode({
        run      => $run,
        material => _vw_text($material_file),
        parts    => [ map { _vw_text($_) } @part_files ],
        result   => _vw_text("$run_dir/result.json"),
        entries  => scalar @entries,
    }), "\n";
    return 0;
}

# ---------------------------------------------------------------------
# show
# ---------------------------------------------------------------------
sub show {
    my ($run) = @_;
    my $run_dir = _vw_run_dir($run);
    -d $run_dir or _vw_fail('実行のフォルダが無い: ' . _vw_text($run_dir), 3);
    my $material_file = "$run_dir/material.json";
    my $material = _vw_load($material_file);
    _vw_fail('材料が無いか、JSON として読めない: ' . _vw_text($material_file), 3)
        unless $material && ref $material->{parts} eq 'ARRAY';
    my @entries;
    for my $part (@{ $material->{parts} }) {
        # 項目のファイルは、collect が書いた場所でなく、実行のフォルダの中の同じ名前のファイルを読む
        my ($base) = (defined $part && !ref $part && $part =~ m{([^/\\]+)\z}) ? ($1) : ();
        my $file = (defined $base && $base =~ /\Aentries-\d+\.json\z/) ? "$run_dir/$base" : undef;
        my $loaded = defined $file ? _vw_load($file) : undef;
        _vw_fail('項目のファイルが無いか、JSON として読めない: ' . (defined $file ? _vw_text($file) : $part // ''), 3)
            unless $loaded && ref $loaded->{entries} eq 'ARRAY';
        push @entries, @{ $loaded->{entries} };
    }
    # 前に書いた show.md を消してから確かめる。判断を退けたときに、前の判断の表示の文が残らないようにするためである
    my $show_file = "$run_dir/show.md";
    unlink $show_file;
    my $result_file = "$run_dir/result.json";
    my $result = _vw_load($result_file) // _vw_fail('判断の JSON が無いか、JSON として読めない: ' . _vw_text($result_file));
    my @problems = _vw_check_result($result, \@entries);
    if (@problems) {
        binmode STDERR, ':encoding(UTF-8)';
        print STDERR "vuln-watch.pl: 判断の JSON が合わない: $_\n" for @problems;
        return 2;
    }
    require "$VW_DIR/render.pl";
    my $text = render_text($material, \@entries, $result);
    my $h;
    my $written = open($h, '>:encoding(UTF-8)', $show_file) && print({$h} $text);
    ($written && close $h) or _vw_fail('表示の文を書けない: ' . _vw_text($show_file), 3);
    print JSON::PP->new->utf8->canonical->encode({ show => _vw_text($show_file) }), "\n";
    return 0;
}

# 判断の JSON が材料と合うかを確かめ、合わない項目ごとに「<key> の <欄>: <直し方>」を返す
sub _vw_check_result {
    my ($result, $entries) = @_;
    return ('version: 1 にする') unless defined $result->{version} && !ref $result->{version} && $result->{version} eq '1';
    return ('entries: 項目の一覧にする') unless ref $result->{entries} eq 'ARRAY';
    my %material = map { $_->{key} => $_ } @$entries;
    my (%seen, @problems);
    for my $i (0 .. $#{ $result->{entries} }) {
        my $j = $result->{entries}[$i];
        unless (ref $j eq 'HASH' && _vw_str($j->{key})) {
            push @problems, sprintf('%d件目の項目の key: 空でない文字列にする', $i + 1);
            next;
        }
        my $key = $j->{key};
        if ($seen{$key}++) {
            push @problems, "$key の key: 判断の JSON に2回ある";
            next;
        }
        my $e = $material{$key};
        unless ($e) {
            push @problems, "$key の key: 材料に無い";
            next;
        }
        push @problems, map { "$key の $_" } _vw_check_judgement($j, $e);
    }
    push @problems, map { "$_->{key} の key: 判断の JSON に無い" } grep { !$seen{ $_->{key} } } @$entries;
    return @problems;
}

# 判断の項目の1つを確かめ、合わない欄ごとに「<欄>: <直し方>」を返す
sub _vw_check_judgement {
    my ($j, $e) = @_;
    my @missing = grep { !exists $j->{$_} } qw(name damage exploited exploited_note software verdict action reason check pc);
    return map { "$_: 欄が無い" } @missing if @missing;
    my @p;
    for my $f (qw(name damage software)) {
        push @p, "$f: 空でない文字列にする" unless _vw_str($j->{$f});
    }
    if (!JSON::PP::is_bool($j->{exploited})) {
        push @p, 'exploited: 真か偽にする';
    } elsif (defined $e->{kev} && !$j->{exploited}) {
        push @p, 'exploited: CISA の一覧に載った脆弱性では真にする';
    }
    push @p, 'exploited_note: 文字列か null にする' if ref $j->{exploited_note};
    my $v = (defined $j->{verdict} && !ref $j->{verdict}) ? $j->{verdict} : '';
    my $s = $e->{suggested} // '';
    if ($v !~ /\A(?:affected|undeterminable|not_affected|unrelated)\z/) {
        push @p, 'verdict: affected か undeterminable か not_affected か unrelated にする';
    } elsif (($s eq 'affected' || $s eq 'undeterminable') && $v ne $s) {
        push @p, "verdict: 判定の案が $s の項目では $s にする";
    } elsif (($s eq 'not_affected' || $s eq 'unrelated') && $v ne $s && $v ne 'undeterminable') {
        push @p, "verdict: 判定の案が $s の項目では $s か undeterminable にする";
    }
    for my $need ([ action => 'affected' ], [ reason => 'undeterminable' ], [ check => 'undeterminable' ]) {
        my ($f, $when) = @$need;
        if ($v eq $when) {
            push @p, "$f: $when の項目では空でない文字列にする" unless _vw_str($j->{$f});
        } elsif (defined $j->{$f}) {
            push @p, "$f: $when でない項目では null にする";
        }
    }
    if (ref $j->{pc} ne 'ARRAY') {
        push @p, 'pc: 一覧にする';
    } else {
        for my $n (0 .. $#{ $j->{pc} }) {
            my $pc = $j->{pc}[$n];
            for my $f (qw(software versions fixed check)) {
                push @p, sprintf('pc の%d件目の %s: 空でない文字列にする', $n + 1, $f) unless ref $pc eq 'HASH' && _vw_str($pc->{$f});
            }
        }
    }
    return @p;
}

# 空白でない文字を持つ文字列なら真
sub _vw_str { defined $_[0] && !ref $_[0] && $_[0] =~ /\S/ }

# ---------------------------------------------------------------------
# clean
# ---------------------------------------------------------------------
sub clean {
    my ($run) = @_;
    my $run_dir = _vw_run_dir($run);
    remove_tree($run_dir) if -e $run_dir;
    _vw_fail('実行のフォルダを消せない: ' . _vw_text($run_dir), 3) if -e $run_dir;
    return 0;
}

# 項目の1つを、材料の項目にする
sub _vw_entry {
    my ($item, $lookup, $matches, $refs, $kev_info, $names, $kev_names) = @_;
    my @cves = @{ $item->{cves} };
    my (%descriptions, @products, @matches, %seen, @kev_dates);
    my $feeds_descriptions = $item->{descriptions} // {};
    for my $cve (@cves) {
        my $l = $lookup->{$cve} // {};
        my $text = $l->{descriptions}{en} // $feeds_descriptions->{$cve};
        $descriptions{$cve} = $text if defined $text;
        push @products, _vw_products($l, _vw_used_ranges($matches->{$cve}), _vw_kev_vendors($kev_names->{$cve}));
        push @kev_dates, $kev_info->{$cve}{date} if $kev_info->{$cve} && defined $kev_info->{$cve}{date};
        for my $m (@{ $matches->{$cve}{matches} // [] }) {
            push @matches, $m unless $seen{ JSON::PP->new->canonical->encode($m) }++;
        }
    }
    # 名前の手がかりは、説明を絞る前の、すべての番号の説明から作る
    my @name_hits = _vw_name_hits($item, \%descriptions, $names);
    # CVE の番号の多い項目では、部品の名前が合った番号と、先頭の番号の説明だけを入れる
    if (@cves >= $VW_DESCRIPTIONS_FROM) {
        my %keep = map { $_ => 1 } @cves[0 .. $VW_DESCRIPTIONS_FIRST - 1];
        $keep{$_} = 1 for grep { grep { $_->{key} ne '*' } @{ $matches->{$_}{matches} // [] } } @cves;
        delete @descriptions{ grep { !$keep{$_} } keys %descriptions };
    }
    my ($kept_products, $omitted) = _vw_limit_products(\@products);
    my @origins = _vw_origins($item, $lookup, $kev_info);
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
        products     => $kept_products,
        products_omitted => $omitted,
        origins      => [ @origins > $VW_ORIGINS_MAX ? @origins[0 .. $VW_ORIGINS_MAX - 1] : @origins ],
        origins_total => scalar @origins,
        name_hits    => \@name_hits,
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
# 製品の一覧を作る。製品ごとに、部品に当てた範囲を持つか(_matched)と、KEV に載った製品か(_kev)の目印を、
# 並べ替えのためだけに付ける。目印は _vw_limit_products が外す
sub _vw_products {
    my ($l, $used, $kev_vendors) = @_;
    my @products;
    for my $p (@{ $l->{products} // [] }) {
        push @products, {
            from => $p->{from}, vendor => $p->{vendor}, product => $p->{product},
            package => $p->{packageName}, ranges => [ @{ $p->{versions} // [] } ],
            _matched => $used->{ refaddr $p } ? 1 : 0,
        };
    }
    $_->{fixed} = _vw_fixed('cve', $_->{ranges}) for @products;
    my (%github, @github_order);
    for my $a (@{ $l->{advisories} // [] }) {
        for my $v (@{ $a->{vulnerabilities} // [] }) {
            my $name = join ':', map { $_ // '' } @$v{qw(ecosystem name)};
            push @github_order, $name unless $github{$name};
            $github{$name} //= { from => 'github', vendor => $v->{ecosystem}, product => $v->{name}, package => $v->{name}, ranges => [], _matched => 0 };
            push @{ $github{$name}{ranges} }, { map { $_ => $v->{$_} } qw(vulnerable_version_range first_patched_version) };
            $github{$name}{_matched} = 1 if $used->{ refaddr $v };
        }
    }
    $github{$_}{fixed} = _vw_fixed('ghsa', $github{$_}{ranges}) for @github_order;
    push @products, map { $github{$_} } @github_order;
    my (%nvd, @nvd_order);
    for my $c (@{ $l->{nvd} // [] }) {
        my @f = split /:/, $c->{criteria} // '';
        my $name = join ':', map { $_ // '' } @f[3, 4];
        push @nvd_order, $name unless $nvd{$name};
        $nvd{$name} //= { from => 'nvd', vendor => $f[3], product => $f[4], package => undef, ranges => [], _matched => 0 };
        push @{ $nvd{$name}{ranges} }, $c;
        $nvd{$name}{_matched} = 1 if ref $c && $used->{ refaddr $c };
    }
    $nvd{$_}{fixed} = _vw_fixed('nvd', $nvd{$_}{ranges}) for @nvd_order;
    push @products, map { $nvd{$_} } @nvd_order;
    $_->{_kev} = $kev_vendors->{ _vw_norm($_->{vendor}) } ? 1 : 0 for @products;
    return @products;
}

# ranges_match が CVE の番号ごとに返した、部品の鍵ごとに当てた範囲の一覧から、当てた範囲の元の要素
# (CVE の記録の製品、GitHub の勧告の vulnerabilities の要素、NVD の cpeMatch)の場所の一覧を作る
sub _vw_used_ranges {
    my ($m) = @_;
    my %used;
    for my $level (values %{ ref $m eq 'HASH' && ref $m->{ranges} eq 'HASH' ? $m->{ranges} : {} }) {
        for my $cand (ref $level eq 'ARRAY' ? @$level : ()) {
            $used{ refaddr $cand->[2] } = 1 if ref $cand eq 'ARRAY' && ref $cand->[2];
        }
    }
    return \%used;
}

# KEV の、CVE の番号の [vendorProject, product] の組の一覧から、vendorProject の名前の一覧を作る
sub _vw_kev_vendors {
    my ($pairs) = @_;
    my %vendors;
    for my $k (ref $pairs eq 'ARRAY' ? @$pairs : ()) {
        my $vendor = ref $k eq 'ARRAY' ? $k->[0] : ref $k eq 'HASH' ? $k->{vendor} : undef;
        my $n = _vw_norm($vendor);
        $vendors{$n} = 1 if length $n;
    }
    return \%vendors;
}

# 名前を、大文字と小文字を区別せず、空白を _ にした形に直す
sub _vw_norm {
    my ($s) = @_;
    return '' unless defined $s && !ref $s;
    $s =~ s/\A\s+|\s+\z//g;
    $s =~ s/\s+/_/g;
    return lc $s;
}

# 製品を、部品に当てた範囲を持つ製品、KEV に載った製品、そのほかの製品の順に並べ(同じ順位の中では元の順)、
# <vendor>:<product> の重複を除いて10件まで残す。重複は並べたあとの先の製品を残すので、部品に範囲を当てた製品が残る。
# 製品ごとの範囲は、versionType が git の範囲を後に回してから先頭の5件を残す。
# fixed は、_vw_products が絞る前の範囲の全部から決めてある。残した製品の一覧と、入れなかった製品の数を返す
sub _vw_limit_products {
    my ($products) = @_;
    my $rank = sub { $_[0]{_matched} ? 0 : $_[0]{_kev} ? 1 : 2 };
    my @order = map { $products->[$_] } sort { $rank->($products->[$a]) <=> $rank->($products->[$b]) || $a <=> $b } 0 .. $#$products;
    my (%seen, @uniq);
    for my $p (@order) {
        push @uniq, $p unless $seen{ join ':', map { $_ // '' } @$p{qw(vendor product)} }++;
    }
    my @kept = @uniq > $VW_PRODUCTS_MAX ? @uniq[0 .. $VW_PRODUCTS_MAX - 1] : @uniq;
    my $git = sub { ref $_[0] eq 'HASH' && lc($_[0]{versionType} // '') eq 'git' ? 1 : 0 };
    my @out;
    for my $p (@kept) {
        my @ranges = @{ $p->{ranges} };
        my @sorted = map { $ranges[$_] } sort { $git->($ranges[$a]) <=> $git->($ranges[$b]) || $a <=> $b } 0 .. $#ranges;
        splice @sorted, $VW_RANGES_MAX if @sorted > $VW_RANGES_MAX;
        push @out, { (map { $_ => $p->{$_} } qw(from vendor product package fixed)), ranges => \@sorted };
    }
    return (\@out, @uniq - @kept);
}

# 項目を前から順に、1つのファイルが40,000バイトを超える前に次のファイルに移るように分ける。
# 項目が無いときも、空の一覧の1つのファイルにする。1つの項目だけで上限を超えるときは、その項目だけを1つのファイルにする
sub _vw_parts {
    my ($entries) = @_;
    my @parts = ([]);
    for my $e (@$entries) {
        my $cur = $parts[-1];
        if (@$cur && length($VW_JSON->encode({ entries => [ @$cur, $e ] })) > $VW_PART_BYTES) {
            push @parts, [$e];
        } else {
            push @$cur, $e;
        }
    }
    return @parts;
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

# 実行の ID を確かめ、実行のフォルダの場所を返す。実行の ID の形でないときと、git のリポジトリでないときは 2 で終わる
sub _vw_run_dir {
    my ($run) = @_;
    _vw_fail('実行の ID の形でない: ' . _vw_text($run)) unless $run =~ $VW_RUN_ID;
    my $root = _vw_toplevel() // _vw_fail('作業フォルダが git のリポジトリでない');
    return "$root/$VW_STATE/$run";
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

sub _vw_read_json { _vw_load($_[0]) // {} }

# JSON のファイルを読み、オブジェクトを返す。無いか、JSON のオブジェクトとして読めないときは undef を返す
sub _vw_load {
    my ($file) = @_;
    open my $h, '<:raw', $file or return undef;
    my $text = do { local $/; <$h> };
    close $h;
    my $value = eval { JSON::PP->new->utf8->decode($text) };
    return ref $value eq 'HASH' ? $value : undef;
}

sub _vw_write_json {
    my ($file, $value) = @_;
    open my $h, '>:raw', $file or return 0;
    my $written = print {$h} $VW_JSON->encode($value);
    return close($h) && $written;
}

# 標準エラーに理由を1行出して終わる。終了コードは、渡さないときは 2 とする
sub _vw_fail {
    my ($message, $code) = @_;
    binmode STDERR, ':encoding(UTF-8)';
    print STDERR "vuln-watch.pl: $message\n";
    exit($code // 2);
}
