#!/usr/bin/env perl
# =====================================================================
# test-vuln-watch.sh の case_large が使う、大きな見本を作る
#
# 実行: perl make-large.pl <見本のフォルダ> <場合のフォルダ>
# 偽の curl の見本($KP_FAKE_CURL_DIR)と偽の gh の見本($KP_FAKE_GH_DIR)と、場合のリポジトリ(<場合のフォルダ>/repo)に、
# 次のものを書く。リポジトリのファイルの commit と push は、呼んだ側が行う。
# - JPCERT/CC の一覧の先頭に、CVE-2026-5000 から CVE-2026-5299 までの300件の番号を記事に持つ項目を足す
# - IPA の一覧の末尾に、CVE-2026-4000 から CVE-2026-4029 までの番号を1件ずつ持ち、2,500文字を超える記事を持つ30件の項目を足す
# - 足した番号の CVE の記録と、空の GitHub の勧告。CVE-2026-5000 からの番号の製品は、vendor-<番号を50で割った余り> と
#   prod-<同じ余り> で、50種類がくり返す。CVE-2026-5200 だけは、リポジトリの npm:next に当たる vercel の next.js にする。
#   どの記録も、600文字を超える英語の説明と、vendor-advisory の URL を1件持つ。
#   CVE-2026-5100 の説明だけは、リポジトリの image:valkey/valkey の名前の Valkey を含む
# - frontend/pnpm-lock.yaml に700件の npm の部品を足し、依存の一覧(sbom.json)を500件の Maven の部品にする
# - .github/workflows/ci.yml に codex-version を置き、npm:@openai/codex の部品を足す
# 前提: perl(JSON::PP)
# =====================================================================
use strict;
use warnings;
use utf8;
use JSON::PP;

my ($fix, $case) = @ARGV;
die "使い方: perl make-large.pl <見本のフォルダ> <場合のフォルダ>\n" unless defined $case;
my $curl = $ENV{KP_FAKE_CURL_DIR} // die "KP_FAKE_CURL_DIR が無い\n";
my $gh = $ENV{KP_FAKE_GH_DIR} // die "KP_FAKE_GH_DIR が無い\n";
my $json = JSON::PP->new->canonical;

sub slurp {
    my ($f) = @_;
    open my $h, '<:encoding(UTF-8)', $f or die "読めない: $f\n";
    local $/;
    return scalar <$h>;
}

sub spit {
    my ($f, $text) = @_;
    open my $h, '>:encoding(UTF-8)', $f or die "書けない: $f\n";
    print {$h} $text;
    close $h or die "書けない: $f\n";
}

# 偽の curl の見本を置く。名前は URL の英数字でない文字を _ に替えたもの(test-vuln-watch.sh の sample と同じ)
sub put {
    my ($url, $status, $body) = @_;
    (my $name = $url) =~ s/[^A-Za-z0-9]/_/g;
    spit("$curl/$name.status", $status);
    spit("$curl/$name.body", $body);
}

my $article_url = 'https://www.jpcert.or.jp/at/2026/at260199.html';
my $jpcert = slurp("$fix/jpcert.rdf");
my $big = qq{  <item rdf:about="$article_url">\n}
    . qq{    <title>注意喚起: 複数の製品の脆弱性に関する注意喚起  (公開)</title>\n}
    . qq{    <link>$article_url</link>\n}
    . qq{    <dc:identifier>at260199</dc:identifier>\n}
    . qq{    <dc:date>2026-11-03T09:00+09:00</dc:date>\n}
    . qq{  </item>\n};
$jpcert =~ s{(  <item )}{$big$1} or die "JPCERT/CC の一覧に項目が無い\n";
put('https://www.jpcert.or.jp/rss/jpcert.rdf', 200, $jpcert);
put($article_url, 200, "<html><body><h1>複数の製品の脆弱性</h1><ul>\n"
    . join('', map { "<li>CVE-2026-$_</li>\n" } 5000 .. 5299) . "</ul></body></html>\n");

my $ipa = slurp("$fix/ipa.rdf");
my $ipa_items = '';
for my $n (0 .. 29) {
    my $url = sprintf 'https://www.ipa.go.jp/security/security-alert/2026/1104-p%02d.html', $n;
    my $cve = sprintf 'CVE-2026-40%02d', $n;
    $ipa_items .= qq{ <item rdf:about="$url">\n  <title>製品$n の脆弱性対策について($cve)</title>\n}
        . qq{  <link>$url</link>\n  <dc:date>2026-11-03T00:00:00+09:00</dc:date>\n </item>\n};
    put($url, 200, "<html><body><p>$cve について。" . ('この製品の脆弱性について、修正した版の情報を説明します。' x 100) . "</p></body></html>\n");
}
$ipa =~ s{</rdf:RDF>}{$ipa_items</rdf:RDF>} or die "IPA の一覧の終わりが無い\n";
put('https://www.ipa.go.jp/security/alert-rss.rdf', 200, $ipa);

sub record {
    my ($cve, $product) = @_;
    my $text = "The component $product->{product} from $product->{vendor} mishandles crafted input and allows remote code execution. " x 6;
    $text =~ s/\s+\z//;
    # CVE-2026-5100 は、先頭の3件にも、部品の範囲を当てた番号にも入らないので、材料にはこの説明が入らない。
    # ranges.pl は説明を600文字までしか持たないので、名前は説明の先頭に置く
    $text = "Deployments that cache sessions in Valkey are affected. $text" if $cve eq 'CVE-2026-5100';
    my $vendor = $product->{vendor};
    return $json->encode({
        cveMetadata => { cveId => $cve },
        containers  => { cna => {
            affected     => [$product],
            descriptions => [ { lang => 'en', value => $text } ],
            references   => [ { url => "https://$vendor.example/advisories/$cve", tags => ['vendor-advisory'] } ],
        } },
    });
}

my @records;
for my $n (5000 .. 5299) {
    my $r = $n % 50;
    my $product = $n == 5200
        ? { vendor => 'vercel', product => 'next.js', collectionURL => 'https://registry.npmjs.org', packageName => 'next',
            versions => [ { version => '15.0.0', lessThan => '15.5.3', status => 'affected', versionType => 'semver' } ] }
        : { vendor => "vendor-$r", product => "prod-$r",
            versions => [ { version => '1.0.0', lessThan => "1.0.$r", status => 'affected', versionType => 'semver' } ] };
    push @records, [ "CVE-2026-$n", $product ];
}
for my $n (0 .. 29) {
    push @records, [ sprintf('CVE-2026-40%02d', $n), { vendor => "ipa-vendor-$n", product => "ipa-prod-$n",
        versions => [ { version => '2.0.0', lessThan => "2.0.$n", status => 'affected', versionType => 'semver' } ] } ];
}
for my $rec (@records) {
    put("https://cveawg.mitre.org/api/cve/$rec->[0]", 200, record(@$rec));
    put("https://api.github.com/advisories?cve_id=$rec->[0]", 200, '[]');
}

my $lock = slurp("$fix/repo/pnpm-lock.yaml");
my $more = join '', map { sprintf "  big-pkg-%04d\@1.0.0:\n    resolution: {integrity: sha512-big%04d}\n\n", $_, $_ } 0 .. 699;
$lock =~ s{^(packages:\n\n)}{$1$more}m or die "pnpm-lock.yaml に packages: が無い\n";
spit("$case/repo/frontend/pnpm-lock.yaml", $lock);

my @packages = map {
    { name => sprintf('com.example.big:lib-%03d', $_), versionInfo => '1.0.0',
      externalRefs => [ { referenceCategory => 'PACKAGE-MANAGER', referenceType => 'purl',
                          referenceLocator => sprintf('pkg:maven/com.example.big/lib-%03d@1.0.0', $_) } ] }
} 0 .. 499;
spit("$gh/sbom.json", $json->encode({ sbom => { spdxVersion => 'SPDX-2.3', packages => \@packages } }));

mkdir "$case/repo/.github";
mkdir "$case/repo/.github/workflows";
spit("$case/repo/.github/workflows/ci.yml", "jobs:\n  review:\n    steps:\n      - with:\n          codex-version: 0.60.0\n");
