#!/bin/bash
# shellcheck disable=SC2016 # $r や $p などは rr に渡す perl の式の変数で、シェルの変数ではない
# =====================================================================
# 版の範囲を読み、部品と突き合わせるモジュール(ranges.pl)のテスト
#
# 実行: bash .claude/scripts/vuln-watch/tests/test-ranges.sh
# 前提: bash・perl(JSON::PP)
#
# 場合を選んで流す: KP_TEST_CASE='compare forms' bash .claude/scripts/vuln-watch/tests/test-ranges.sh
# 空白で区切った名前の場合だけを流す。どの場合にも合わない名前があれば、何も流さずに終了コード 2 で終わる
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
RANGES="$(cd "$HERE/.." && pwd)/ranges.pl"

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }

# ranges.pl を読み込み、perl の式を評価した値を出す: rr <perl の式> [<式の中で $ARGV[2] から読む値>...]
# 式の中では次の2つを使う。範囲は JSON の文字列で書く
#   C(<版>, <版>): ranges_version_cmp の値。比べられなければ undef と出す
#   IN(<出どころ>, <範囲の JSON>, <版>, <一部だけの版か>): ranges_in_range の値を true・false・null:<理由> で出す
rr() {
    perl -MJSON::PP -e '
        require $ARGV[0];
        sub C { my $c = ranges_version_cmp(@_); defined $c ? $c : "undef" }
        sub IN {
            my ($source, $json, $version, $partial) = @_;
            my ($in, $why) = ranges_in_range($source, JSON::PP->new->decode($json), $version, $partial);
            defined $in ? ($in ? "true" : "false") : "null:" . (defined $why ? $why : "");
        }
        my $v = eval $ARGV[1];
        die $@ if $@;
        print defined $v ? $v : "<undef>";
    ' "$RANGES" "$@" 2>&1
}

# ---------------------------------------------------------------------
# 場合
# ---------------------------------------------------------------------

case_compare() {
    check "17.11 と 17.9、2.21.7 と 2.21.10、v0.65.0、9.1.5.Final が正しく比べられる" \
        "$(rr 'join " ", C("17.11", "17.9"), C("2.21.7", "2.21.10"), C("v0.65.0", "0.65.0"), C("v0.65.0", "0.64.9"),
            C("9.1.5.Final", "9.1.5"), C("9.1.5.Final", "9.1.10"), C("33.3.1-jre", "33.3.1"), C("2.21", "2.21.0"), C("1.10.0", "1.9.9")')" \
        "1 -1 0 1 0 -1 0 0 1"
    check "17.11 と 17.9、2.21.7 と 2.21.10、v0.65.0、9.1.5.Final が正しく比べられる(範囲の判定で使う場合)" \
        "$(rr 'join " ", IN("ghsa", q({"vulnerable_version_range":">= 17.10, < 17.12"}), "17.11", 0),
            IN("ghsa", q({"vulnerable_version_range":"< 17.10"}), "17.9", 0),
            IN("ghsa", q({"vulnerable_version_range":"< 17.10"}), "17.11", 0),
            IN("ghsa", q({"vulnerable_version_range":"< 2.21.10"}), "2.21.7", 0),
            IN("ghsa", q({"vulnerable_version_range":"< 0.65.1"}), "v0.65.0", 0),
            IN("ghsa", q({"vulnerable_version_range":"< 9.1.5"}), "9.1.5.Final", 0)')" \
        "true true false true true false"
}

case_forms() {
    local cna='{"versions":[{"version":"9.0.0","lessThan":"9.0.30","status":"affected","versionType":"semver"},{"version":"10.1.0","lessThanOrEqual":"10.1.15","status":"affected","versionType":"maven"}]}'
    check "CVE の記録の lessThan と lessThanOrEqual と status: unaffected、version の式、GitHub の勧告の式、NVD の versionEndExcluding が読まれる(CVE の記録の lessThan と lessThanOrEqual)" \
        "$(rr 'my $r = $ARGV[2]; join " ", map { IN("cve", $r, $_, 0) } qw(9.0.29 9.0.30 8.5.99 10.1.0 10.1.15 10.1.16)' "$cna")" \
        "true false false true true false"
    # Linux の CNA の書き方。作り込まれる前の版と、版の系列ごとの直った版を unaffected で書く。最初に当たった範囲の status を使い、どれにも当たらなければ defaultStatus を使う
    local linux='{"defaultStatus":"affected","versions":[{"version":"3.12","status":"affected"},{"version":"0","lessThan":"3.12","status":"unaffected","versionType":"semver"},{"version":"6.1.117","lessThanOrEqual":"6.1.*","status":"unaffected","versionType":"semver"},{"version":"6.6.61","lessThanOrEqual":"6.6.*","status":"unaffected","versionType":"semver"},{"version":"6.12","lessThanOrEqual":"*","status":"unaffected","versionType":"original_commit_for_fix"}]}'
    check "CVE の記録の lessThan と lessThanOrEqual と status: unaffected、version の式、GitHub の勧告の式、NVD の versionEndExcluding が読まれる(CVE の記録の status: unaffected)" \
        "$(rr 'my $r = $ARGV[2]; join " ", map { IN("cve", $r, $_, 0) } qw(3.10 3.12 6.1.100 6.1.117 6.1.200 6.2.0 6.6.70 6.12.1)' "$linux")" \
        "false true true false false true false false"
    # defaultStatus が無いときは、書かれた範囲の外の版を、範囲に入らないとする。unknown と書かれた範囲は、範囲が無いとする
    check "CVE の記録の lessThan と lessThanOrEqual と status: unaffected、version の式、GitHub の勧告の式、NVD の versionEndExcluding が読まれる(defaultStatus と unknown)" \
        "$(rr 'join " ", IN("cve", q({"versions":[{"version":"1.0.0","lessThan":"1.5.0","status":"affected","versionType":"semver"}]}), "2.0.0", 0),
            IN("cve", q({"defaultStatus":"unknown","versions":[{"version":"1.0.0","lessThan":"1.5.0","status":"affected","versionType":"semver"}]}), "2.0.0", 0),
            IN("cve", q({"versions":[{"version":"1.0.0","lessThan":"1.5.0","status":"unknown","versionType":"semver"}]}), "1.2.0", 0),
            IN("cve", q({"versions":[{"version":"1.0.0","lessThan":"1.*","status":"affected","versionType":"semver"}]}), "1.99.0", 0),
            IN("cve", q({"versions":[{"version":"1.0.0","lessThan":"1.*","status":"affected","versionType":"semver"}]}), "2.0.0", 0),
            IN("cve", q({"versions":[{"version":"unspecified","lessThan":"2.3","status":"affected","versionType":"custom"}]}), "1.0", 0),
            IN("cve", q({"versions":[{"version":"2.0.0","status":"affected"}]}), "2.0.0", 0),
            IN("cve", q({"versions":[{"version":"2.0.0","status":"affected"}]}), "2.0.1", 0),
            IN("cve", q({"versions":[{"version":"1.0.0","lessThan":"2.0.0","status":"affected","versionType":"semver","changes":[{"at":"1.4.2","status":"unaffected"}]}]}), "1.4.1", 0),
            IN("cve", q({"versions":[{"version":"1.0.0","lessThan":"2.0.0","status":"affected","versionType":"semver","changes":[{"at":"1.4.2","status":"unaffected"}]}]}), "1.4.2", 0)')" \
        "false null:no_range null:no_range true false true true false true false"
    local expr='{"versions":[{"version":">= 14.0.0, < 14.2.25","status":"affected"},{"version":"< 13.5.8","status":"affected"}]}'
    check "CVE の記録の lessThan と lessThanOrEqual と status: unaffected、version の式、GitHub の勧告の式、NVD の versionEndExcluding が読まれる(version の式)" \
        "$(rr 'my $r = $ARGV[2]; join " ", map { IN("cve", $r, $_, 0) } qw(14.0.0 14.2.24 14.2.25 13.5.7 13.5.8)' "$expr")" \
        "true true false true false"
    check "CVE の記録の lessThan と lessThanOrEqual と status: unaffected、version の式、GitHub の勧告の式、NVD の versionEndExcluding が読まれる(GitHub の勧告の式)" \
        "$(rr 'join " ", IN("ghsa", q({"vulnerable_version_range":"= 1.2.3"}), "1.2.3", 0), IN("ghsa", q({"vulnerable_version_range":"= 1.2.3"}), "1.2.4", 0),
            IN("ghsa", q({"vulnerable_version_range":"<= 1.2.3"}), "1.2.3", 0), IN("ghsa", q({"vulnerable_version_range":"> 1.2.3"}), "1.2.3", 0),
            IN("ghsa", q({"vulnerable_version_range":">= 4.0.0, < 4.17.21"}), "4.17.20", 0), IN("ghsa", q({"vulnerable_version_range":">= 4.0.0, < 4.17.21"}), "3.9.9", 0),
            IN("ghsa", q({"vulnerable_version_range":"> 2.0, <= 2.5"}), "2.5", 0), IN("ghsa", q({"vulnerable_version_range":"> 2.0, <= 2.5"}), "2.0", 0),
            IN("ghsa", q({"vulnerable_version_range":""}), "1.0", 0), IN("ghsa", q({"vulnerable_version_range":"~> 1.2"}), "1.2", 0)')" \
        "true false true false true false true false null:no_range null:uncomparable"
    check "CVE の記録の lessThan と lessThanOrEqual と status: unaffected、version の式、GitHub の勧告の式、NVD の versionEndExcluding が読まれる(NVD)" \
        "$(rr 'join " ", IN("nvd", q({"criteria":"cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*","versionStartIncluding":"9.0.0","versionEndExcluding":"9.0.30"}), "9.0.29", 0),
            IN("nvd", q({"criteria":"cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*","versionStartIncluding":"9.0.0","versionEndExcluding":"9.0.30"}), "9.0.30", 0),
            IN("nvd", q({"criteria":"cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*","versionStartExcluding":"9.0.0","versionEndIncluding":"9.0.30"}), "9.0.0", 0),
            IN("nvd", q({"criteria":"cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*","versionStartExcluding":"9.0.0","versionEndIncluding":"9.0.30"}), "9.0.30", 0),
            IN("nvd", q({"criteria":"cpe:2.3:a:apache:tomcat:9.0.5:*:*:*:*:*:*:*"}), "9.0.5", 0),
            IN("nvd", q({"criteria":"cpe:2.3:a:apache:tomcat:9.0.5:*:*:*:*:*:*:*"}), "9.0.6", 0),
            IN("nvd", q({"criteria":"cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*"}), "1.0", 0),
            IN("nvd", q({}), "1.0", 0)')" \
        "true false false true true false true null:no_range"
    check "版が分からない部品と、範囲を持たない CVE の記録の製品は、null になる" \
        "$(rr 'join " ", IN("cve", q({"versions":[{"version":"1.0.0","lessThan":"1.5.0","status":"affected","versionType":"semver"}]}), undef, 0),
            IN("cve", q({"versions":[]}), "1.0.0", 0), IN("cve", q({"vendor":"x"}), "1.0.0", 0), IN("nosuch", q({}), "1.0.0", 0)')" \
        "null:no_version null:no_range null:no_range null:no_range"
}

case_uncomparable() {
    check "1.0.0-rc.1 の途中の文字と、versionType が git の範囲が uncomparable になる(版の比較)" \
        "$(rr 'join " ", C("1.0.0-rc.1", "1.0.0"), C("1.0.0", "1.0.0-rc.1"), C("1.0.2k", "1.0.2"), C("", "1.0"), C("rc", "1.0")')" \
        "undef undef undef undef undef"
    check "1.0.0-rc.1 の途中の文字と、versionType が git の範囲が uncomparable になる(範囲の判定)" \
        "$(rr 'join " ", IN("ghsa", q({"vulnerable_version_range":"< 2.0.0"}), "1.0.0-rc.1", 0),
            IN("ghsa", q({"vulnerable_version_range":"< 2.0.0-rc.1"}), "1.0.0", 0),
            IN("cve", q({"versions":[{"version":"1.0.0","lessThan":"1.1.0-rc.1","status":"affected","versionType":"semver"}]}), "1.0.5", 0),
            IN("cve", q({"versions":[{"version":"1da177e4c3f4","lessThan":"8c4ebe8e4c22","status":"affected","versionType":"git"}]}), "6.1.0", 0),
            IN("cve", q({"versions":[{"version":"3.12","lessThan":"3.13","status":"affected","versionType":"git"}]}), "3.12.5", 0),
            IN("nvd", q({"criteria":"cpe:2.3:a:x:y:*:*:*:*:*:*:*:*","versionEndExcluding":"2.0.0-rc.1"}), "1.0.0", 0)')" \
        "null:uncomparable null:uncomparable null:uncomparable null:uncomparable null:uncomparable null:uncomparable"
    # 部品の版の形を比べられない範囲より前の範囲に版が当たれば、その範囲で決める
    check "比べられない範囲より前の範囲に当たった版は、その範囲で決まる" \
        "$(rr 'IN("cve", q({"versions":[{"version":"1.0.0","lessThan":"1.5.0","status":"affected","versionType":"semver"},{"version":"abc","lessThan":"def","status":"affected","versionType":"git"}]}), "1.2.0", 0)')" \
        "true"
}

case_partial() {
    check "一部だけの版 21 が、範囲 >= 21.0.0, < 21.0.5 で partial_version に、範囲 < 17.0.0 で偽になる" \
        "$(rr 'join " ", IN("ghsa", q({"vulnerable_version_range":">= 21.0.0, < 21.0.5"}), "21", 1),
            IN("ghsa", q({"vulnerable_version_range":"< 17.0.0"}), "21", 1)')" \
        "null:partial_version false"
    check "一部だけの版 21 が、範囲 >= 21.0.0, < 21.0.5 で partial_version に、範囲 < 17.0.0 で偽になる(幅の全体が入る範囲と、境の版)" \
        "$(rr 'join " ", IN("ghsa", q({"vulnerable_version_range":">= 21.0.0, < 22.0.0"}), "21", 1),
            IN("ghsa", q({"vulnerable_version_range":"< 21.0.0"}), "21", 1),
            IN("ghsa", q({"vulnerable_version_range":"<= 21.0.0"}), "21", 1),
            IN("ghsa", q({"vulnerable_version_range":">= 22.0.0"}), "21", 1),
            IN("ghsa", q({"vulnerable_version_range":"< 21.0.5"}), "21", 0),
            IN("nvd", q({"criteria":"cpe:2.3:o:oracle:java_se:*:*:*:*:*:*:*:*","versionStartIncluding":"17.0","versionEndIncluding":"21.0.8"}), "21", 1),
            IN("nvd", q({"criteria":"cpe:2.3:o:oracle:java_se:21.0.3:*:*:*:*:*:*:*"}), "21", 1)')" \
        "true false null:partial_version false true null:partial_version null:partial_version"
    local cna='{"versions":[{"version":"16.0","lessThan":"16.4","status":"affected","versionType":"custom"},{"version":"17.0","lessThan":"17.2","status":"affected","versionType":"custom"}]}'
    check "一部だけの版 21 が、範囲 >= 21.0.0, < 21.0.5 で partial_version に、範囲 < 17.0.0 で偽になる(CVE の記録の範囲)" \
        "$(rr 'my $r = $ARGV[2]; join " ", map { IN("cve", $r, $_, 1) } qw(15 16 17 18)' "$cna")" \
        "false null:partial_version null:partial_version false"
    check "一部だけの版 21 が、範囲 >= 21.0.0, < 21.0.5 で partial_version に、範囲 < 17.0.0 で偽になる(版の系列の全体が入る CVE の記録の範囲)" \
        "$(rr 'join " ", IN("cve", q({"versions":[{"version":"16","lessThanOrEqual":"16.*","status":"affected","versionType":"custom"}]}), "16", 1),
            IN("cve", q({"defaultStatus":"affected","versions":[{"version":"16.4","lessThanOrEqual":"16.*","status":"unaffected","versionType":"custom"}]}), "16", 1),
            IN("cve", q({"defaultStatus":"affected","versions":[{"version":"16.4","lessThanOrEqual":"16.*","status":"unaffected","versionType":"custom"}]}), "17", 1)')" \
        "true null:partial_version true"
}

CASES='compare forms uncomparable partial'

# ---------------------------------------------------------------------
# 選んだ場合を流す
# ---------------------------------------------------------------------

selected=$CASES
if [ -n "${KP_TEST_CASE:-}" ]; then
    for want in $KP_TEST_CASE; do
        case " $CASES " in
        *" $want "*) ;;
        *)
            echo "どの場合にも合わない名前: $want" >&2
            exit 2
            ;;
        esac
    done
    selected=$KP_TEST_CASE
fi
for name in $selected; do
    "case_$name"
done

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
