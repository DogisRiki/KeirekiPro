#!/usr/bin/env bash
# =====================================================================
# テストに使う偽の gh
#
# テストは、このファイルを一時フォルダに gh の名前で写し、その一時フォルダを
# PATH の先頭に置く。偽の gh は、GitHub に出ず、$KP_FAKE_GH_DIR のフォルダの
# 見本を応答の代わりにする。前提: bash・perl。
#
# サブコマンドと見本
# - auth-token: gh auth token。auth-token.out を出す
# - sbom: gh api <...>/dependency-graph/sbom。sbom.json を出す
# - pr-list: gh pr list。pr-list.json を出す
# - issue-list: gh issue list。issue-list.json を出す
# 見本のファイルが無いときは、標準エラーに1行を出して 2 で終わる。
# --jq と --template は、見本に当てられないので、標準エラーに1行を出して 2 で終わる。
# そのほかの呼び出しも、2 で終わる。テストが、偽の gh の答えない呼び出しに
# 気づかないまま通ることを防ぐためである。
#
# 環境変数
# - KP_FAKE_GH_FAIL: 空白で区切ったサブコマンドの名前。その名前の呼び出しでは、
#   標準エラーに1行を出して 1 で終わる
# =====================================================================
: <<'__PERL__'
#!perl
use strict;
use warnings;

sub unsupported {
    print STDERR "fake-gh: unsupported: $_[0]\n";
    exit 2;
}

my $dir = $ENV{KP_FAKE_GH_DIR};
unsupported('KP_FAKE_GH_DIR is not set') unless defined $dir && length $dir;

my @args = @ARGV;
for my $arg (@args) {
    unsupported("option $arg") if $arg eq "--jq" || $arg eq "-q" || $arg eq "--template" || $arg eq "-t";
}

my $name;
if (@args >= 2 && $args[0] eq 'auth' && $args[1] eq 'token') {
    $name = 'auth-token';
} elsif (@args >= 2 && $args[0] eq 'api' && grep { m{/dependency-graph/sbom\z} } @args[1 .. $#args]) {
    $name = 'sbom';
} elsif (@args >= 2 && $args[0] eq 'pr' && $args[1] eq 'list') {
    $name = 'pr-list';
} elsif (@args >= 2 && $args[0] eq 'issue' && $args[1] eq 'list') {
    $name = 'issue-list';
} else {
    unsupported(join ' ', @args);
}

my %fail = map { $_ => 1 } split ' ', $ENV{KP_FAKE_GH_FAIL} // '';
if ($fail{$name}) {
    print STDERR "fake-gh: $name failed\n";
    exit 1;
}

my %file = ('auth-token' => 'auth-token.out', sbom => 'sbom.json', 'pr-list' => 'pr-list.json', 'issue-list' => 'issue-list.json');
my $path = "$dir/$file{$name}";
open my $f, '<:raw', $path or unsupported("no sample $file{$name}");
binmode STDOUT, ':raw';
print do { local $/; <$f> };
close $f;
exit 0;
__END__
__PERL__
exec perl -x "$0" "$@"
