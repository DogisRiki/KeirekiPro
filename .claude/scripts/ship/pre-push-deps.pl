#!/usr/bin/env perl
# =====================================================================
# push の前に、このブランチで増えた部品(名前と版の組)を書き出す(pre-push-dependency-review.sh と pre-push-dependency-cooldown.sh が呼ぶ)
#
# 使い方: perl pre-push-deps.pl <基準のフォルダ> <対象のフォルダ>
#   どちらのフォルダにも、次のファイルがあれば読む(無いファイルは部品が無いものとして読む)。
#     go.mod            backend/go.mod
#     pnpm-lock.yaml    frontend/pnpm-lock.yaml
#   対象のフォルダにあって基準のフォルダに無い組を、1行に「種類<TAB>名前<TAB>版」で標準出力に書く。
#   種類は gomod / npm。CI の dependency-review と dependency-cooldown が読む依存グラフの
#   ecosystem の書き方に合わせる。版は先頭の v を落とす(依存グラフの差分比較の API と同じ書き方)。
#
# CI との違い: CI は maven(Java 版の backend)の部品も読む。Java 版は Go 版に置き換えて消すので、ここでは読まない。
# =====================================================================
use strict;
use warnings;

my ($base_dir, $head_dir) = @ARGV;
die "使い方: perl pre-push-deps.pl <基準のフォルダ> <対象のフォルダ>\n" unless defined $head_dir;

sub slurp {
    my ($path) = @_;
    return '' unless -f $path;
    open my $fh, '<:raw', $path or die "読めません: $path: $!\n";
    local $/;
    my $s = <$fh>;
    close $fh;
    $s =~ s/\r\n/\n/g;
    return $s;
}

# go.mod の require(1行の形と括弧の形)。// indirect の部品も読む(依存グラフも読む)
sub gomod {
    my ($text) = @_;
    my %out;
    my $in_block = 0;
    for my $line (split /\n/, $text) {
        $line =~ s{//.*$}{};
        $line =~ s/^\s+|\s+$//g;
        if ($in_block) {
            if ($line eq ')') { $in_block = 0; next; }
        } elsif ($line =~ /^require\s*\($/) {
            $in_block = 1;
            next;
        } elsif ($line !~ s/^require\s+//) {
            next;
        }
        $out{"gomod\t$1\t$2"} = 1 if $line =~ /^(\S+)\s+v?(\d\S*)$/;
    }
    return \%out;
}

# pnpm-lock.yaml(lockfileVersion 9)の packages: の節の鍵「名前@版」
sub pnpm {
    my ($text) = @_;
    my %out;
    my $in = 0;
    for my $line (split /\n/, $text) {
        if ($line =~ /^packages:\s*$/) { $in = 1; next; }
        if ($line =~ /^\S/) { $in = 0; next; }
        next unless $in;
        next unless $line =~ /^  (?! )(['"]?)(.+?)\1:\s*$/;
        my $key = $2;
        $key =~ s/\(.*$//;    # 相手の部品の版の添え書き(古い形)を落とす
        next unless $key =~ /^((?:@[^\/@]+\/)?[^@\/]+)@(\d[^\s]*)$/;
        $out{"npm\t$1\t$2"} = 1;
    }
    return \%out;
}

sub all_of {
    my ($dir) = @_;
    my %all;
    for my $h (gomod(slurp("$dir/go.mod")), pnpm(slurp("$dir/pnpm-lock.yaml"))) {
        $all{$_} = 1 for keys %$h;
    }
    return \%all;
}

my $base = all_of($base_dir);
my $head = all_of($head_dir);
print "$_\n" for sort grep { !$base->{$_} } keys %$head;
