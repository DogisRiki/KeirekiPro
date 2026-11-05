#!/usr/bin/env perl
# =====================================================================
# test-vuln-watch.sh の show の場合が使う、判断の JSON(result.json)を作る
#
# 実行: perl make-result.pl <実行のフォルダ> [<perl の式>]
# 実行のフォルダの material.json と、parts に並んだ項目のファイルを読み、どの項目も確かめに通る判断を作る。
# - verdict は材料の suggested と同じにし、name は「脆弱性の名前 <key>」、damage と software は空でない文にする
# - exploited は、材料の kev が null でない項目で真、そのほかで偽にする
# - action は affected の項目に、reason と check は undeterminable の項目に書き、そのほかでは null にする
# - pc は空の一覧にする
# 式を渡したときは、判断の JSON を $r に、鍵ごとの判断の項目を %j に、鍵ごとの材料の項目を %e に置いて式を評価し、
# 評価したあとの $r を <実行のフォルダ>/result.json に書く。式で判断を壊して、show が退けるかを確かめるためである
# 前提: perl(JSON::PP)
# =====================================================================
use strict;
use warnings;
use utf8;
use JSON::PP;

my ($run_dir, $expr) = @ARGV;
die "使い方: perl make-result.pl <実行のフォルダ> [<perl の式>]\n" unless defined $run_dir;

sub load {
    my ($file) = @_;
    open my $h, '<:raw', $file or die "読めない: $file\n";
    local $/;
    return JSON::PP->new->utf8->decode(scalar <$h>);
}

my $material = load("$run_dir/material.json");
my @entries;
for my $part (@{ $material->{parts} }) {
    my ($base) = $part =~ m{([^/\\]+)\z};
    push @entries, @{ load("$run_dir/$base")->{entries} };
}

my (%e, %j);
my $r = { version => 1, entries => [] };
for my $m (@entries) {
    my $v = $m->{suggested};
    my $j = {
        key            => $m->{key},
        name           => "脆弱性の名前 $m->{key}",
        damage         => '攻撃者が細工した要求で、任意のコードを動かせる',
        exploited      => defined $m->{kev} ? JSON::PP::true : JSON::PP::false,
        exploited_note => undef,
        software       => '見本のソフト',
        verdict        => $v,
        action         => $v eq 'affected' ? '部品を直った版に上げる' : undef,
        reason         => $v eq 'undeterminable' ? '影響する版の範囲が発表に無い' : undef,
        check          => $v eq 'undeterminable' ? '部品の版を、元の発表の版と比べる' : undef,
        pc             => [],
    };
    push @{ $r->{entries} }, $j;
    $e{ $m->{key} } = $m;
    $j{ $m->{key} } = $j;
}
if (defined $expr) {
    utf8::decode($expr);
    eval "$expr; 1" or die "式を評価できない: $@";
}

open my $out, '>:raw', "$run_dir/result.json" or die "書けない: $run_dir/result.json\n";
print {$out} JSON::PP->new->utf8->canonical->encode($r);
close $out or die "書けない: $run_dir/result.json\n";
