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

FIX="$HERE/fixtures"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd -P; })
ORIG_PATH=$PATH

CVE_URL=https://cveawg.mitre.org/api/cve/
GHSA_URL='https://api.github.com/advisories?cve_id='
# 偽の gh が gh auth token の答えとして出す値。本物のトークンではない
FAKE_TOKEN=gho_vulnwatchFAKE0123456789abcdef

# URL の英数字でない文字を _ に替えた、偽の curl の見本の名前を出す
sample() { printf '%s/%s' "$KP_FAKE_CURL_DIR" "$(printf '%s' "$1" | perl -pe 's/[^A-Za-z0-9]/_/g')"; }

# 偽の curl の見本を置く: put <URL> <状態> <本文のファイル>
put() {
    printf '%s' "$2" >"$(sample "$1").status"
    cp "$3" "$(sample "$1").body"
}

# CVE の番号の CVE の記録と GitHub の勧告の見本を置く: put_cve <CVE の番号> <CVE の記録の状態> <本文> <勧告の状態> <本文>
put_cve() {
    put "$CVE_URL$1" "$2" "$3"
    put "$GHSA_URL$1" "$4" "$5"
}

# 標準入力の JSON を $d に読み、perl の式を評価した値を出す: pj '<式>'
pj() {
    perl -MJSON::PP -e '
        my $d = JSON::PP->new->utf8->decode(do { local $/; <STDIN> });
        binmode STDOUT, ":encoding(UTF-8)";
        my $v = eval $ARGV[0];
        die $@ if $@;
        print defined $v ? $v : "<undef>";
    ' "$1"
}

# ranges_lookup を呼び、返した値と、かかった秒数を JSON で $CASE/out.json に書く。
# run_lookup <空白で区切った CVE の番号> <先に引く順の JSON> [<打ち切りまでの秒数>]
run_lookup() {
    (cd "$CASE/work" && perl -MJSON::PP -MTime::HiRes=time -e '
        require $ARGV[0];
        my @cves = split " ", $ARGV[1];
        my $t0 = time;
        my ($lookup, $ok) = ranges_lookup(\@cves, JSON::PP->new->decode($ARGV[2]), {}, {}, {}, $ARGV[3], time + $ARGV[4]);
        print JSON::PP->new->utf8->canonical->encode({ lookup => $lookup, advisories_ok => ($ok ? JSON::PP::true : JSON::PP::false), elapsed => time - $t0 });
    ' "$RANGES" "$1" "$2" "$CASE/work" "${3:-60}" >"$CASE/out.json" 2>"$CASE/err.txt")
}

out() { pj "$1" <"$CASE/out.json"; }

# 偽の curl の記録から、要求した URL のうち、文字列を含むものの数を出す: requested <文字列>
requested() {
    if [ -f "$CASE/curl.log" ]; then
        KP_WANT=$1 perl -ne 'BEGIN { $n = 0 } $n++ if /\AKARG https:/ && index($_, $ENV{KP_WANT}) >= 0; END { print $n }' <"$CASE/curl.log"
    else
        printf 0
    fi
}

# 場合ごとの一時フォルダを作り、偽の curl と偽の gh を置く
CASE_NO=0
newcase() {
    CASE_NO=$((CASE_NO + 1))
    CASE="$WORK/c$CASE_NO"
    mkdir -p "$CASE/bin" "$CASE/curl" "$CASE/gh" "$CASE/work" "$CASE/home"
    cp "$FIX/fake-curl.sh" "$CASE/bin/curl"
    cp "$FIX/fake-gh.sh" "$CASE/bin/gh"
    chmod +x "$CASE/bin/curl" "$CASE/bin/gh"
    # PATH は : で区切るので、C:/ の形でなく、bash の形の場所を置く
    export PATH="$TMP_ROOT/c$CASE_NO/bin:$ORIG_PATH"
    if [ "$(command -v curl)" != "$TMP_ROOT/c$CASE_NO/bin/curl" ] || [ "$(command -v gh)" != "$TMP_ROOT/c$CASE_NO/bin/gh" ]; then
        echo "偽の curl と偽の gh が PATH の先頭にない: $(command -v curl) $(command -v gh)" >&2
        exit 2
    fi
    export HOME="$CASE/home"
    export KP_FAKE_CURL_DIR="$CASE/curl" KP_FAKE_GH_DIR="$CASE/gh" KP_FAKE_CURL_LOG="$CASE/curl.log"
    unset KP_FAKE_CURL_DELAY KP_FAKE_GH_FAIL
    printf '%s\n' "$FAKE_TOKEN" >"$CASE/gh/auth-token.out"
    printf '[]' >"$CASE/empty.json"
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
    # Tomcat の勧告の 11.0.0-M1 と 9.0.0.M1、Spring の CVE の記録の 5.3.x のように、英字で始まる部分が末尾にある版
    check "末尾の英字で始まる部分(-M1 .M1 .x)を除いて比べる" \
        "$(rr 'join " ", C("11.0.0-M1", "11.0.0"), C("9.0.0.M1", "9.0.0"), C("5.3.x", "5.3"), C("10.1.0-M1", "10.1.34"),
            IN("ghsa", q({"vulnerable_version_range":">= 11.0.0-M1, < 11.0.3"}), "11.0.2", 0),
            IN("cve", q({"versions":[{"version":"5.3.x","lessThan":"5.3.40","status":"affected","versionType":"custom"}]}), "5.3.39", 0)')" \
        "0 0 0 -1 true true"
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

case_lookup() {
    newcase
    put_cve CVE-2024-38816 200 "$FIX/test-ranges/cve-CVE-2024-38816.json" 200 "$FIX/test-ranges/ghsa-CVE-2024-38816.json"
    put_cve CVE-2025-29927 200 "$FIX/test-ranges/cve-CVE-2025-29927.json" 200 "$FIX/test-ranges/ghsa-CVE-2025-29927.json"
    put_cve CVE-2024-6387 200 "$FIX/test-ranges/cve-CVE-2024-6387.json" 200 "$CASE/empty.json"
    run_lookup "CVE-2024-38816 CVE-2025-29927 CVE-2024-6387 CVE-2024-38816" '{}'
    local name="CVE の記録の CNA と CISA-ADP の製品の範囲と、GitHub の勧告の範囲と、vendor-advisory の URL が読まれる"
    check "$name(CNA と CISA-ADP の製品)" \
        "$(out 'join ";", map { join "|", map { defined $_ ? $_ : "-" } @$_{qw(from vendor product packageName defaultStatus)} } @{ $d->{lookup}{"CVE-2024-38816"}{products} }')" \
        "cna|Spring|Spring|Spring Framework|affected;adp|spring_by_vmware_tanzu|spring_framework|-|unknown;adp|spring_by_vmware_tanzu|spring_framework|-|unknown;adp|spring_by_vmware_tanzu|spring_framework|-|unknown"
    check "$name(製品の範囲の欄)" \
        "$(out 'my $p = $d->{lookup}{"CVE-2024-38816"}{products}; join ";", scalar(@{ $p->[0]{versions} }), join("|", @{ $p->[0]{versions}[0] }{qw(version lessThan status versionType)}), join("|", @{ $p->[3]{versions}[0] }{qw(version lessThan status versionType)})')" \
        "3;5.3.x|5.3.40|affected|enterprise Support Only;6.1.0|6.1.13|affected|custom"
    check "$name(CISA-ADP でない書き足しの製品は読まない。collectionURL を持つ)" \
        "$(out 'join ";", map { join "|", map { defined $_ ? $_ : "-" } @$_{qw(from product packageName collectionURL)} } @{ $d->{lookup}{"CVE-2024-6387"}{products} }')" \
        "cna|-|OpenSSH|https://www.openssh.com/;cna|Red Hat Enterprise Linux 9|openssh|https://access.redhat.com/downloads/content/package-browser/"
    check "$name(version に書かれた式をそのまま持つ)" \
        "$(out 'join ";", map { $_->{version} } @{ $d->{lookup}{"CVE-2025-29927"}{products}[0]{versions} }')" \
        ">= 11.1.4, < 12.3.5;>= 14.0.0, < 14.2.25;>= 15.0.0, < 15.2.3;>= 13.0.0, < 13.5.9"
    check "$name(GitHub の勧告)" \
        "$(out 'join ";", map { my $x = $_; join "|", $x->{ghsa_id}, (defined $x->{repository_advisory_url} ? $x->{repository_advisory_url} : "null"), map { join ",", map { defined $_ ? $_ : "null" } @$_{qw(ecosystem name vulnerable_version_range first_patched_version)} } @{ $x->{vulnerabilities} } } map { @{ $d->{lookup}{$_}{advisories} } } "CVE-2025-29927", "CVE-2024-38816", "CVE-2024-6387"')" \
        "GHSA-f82v-jwr5-mffw|https://api.github.com/repos/vercel/next.js/security-advisories/GHSA-f82v-jwr5-mffw|npm,next,>= 13.0.0, < 13.5.9,13.5.9|npm,next,>= 14.0.0, < 14.2.25,14.2.25;GHSA-cx7f-g6mp-7hqm|null|maven,org.springframework:spring-webmvc,>= 6.1.0, < 6.1.13,6.1.13|maven,org.springframework:spring-webmvc,>= 6.0.0, <= 6.0.23,null"
    check "$name(vendor-advisory の URL を3件まで持つ)" \
        "$(out 'join ";", scalar(@{ $d->{lookup}{"CVE-2024-38816"}{vendor_advisories} }), @{ $d->{lookup}{"CVE-2024-6387"}{vendor_advisories} }')" \
        "0;https://access.redhat.com/errata/RHSA-2024:4312;https://access.redhat.com/errata/RHSA-2024:4340;https://access.redhat.com/errata/RHSA-2024:4389"
    check "$name(英語の説明を600文字まで持つ)" \
        "$(out 'join ";", length $d->{lookup}{"CVE-2024-38816"}{descriptions}{en}, substr($d->{lookup}{"CVE-2024-38816"}{descriptions}{en}, 0, 20), length $d->{lookup}{"CVE-2024-6387"}{descriptions}{en}')" \
        "600;Applications serving;285"
    check "$name(同じ番号は1回だけ引き、すべての番号の looked_up が真になる)" \
        "$(out 'join ";", join(",", sort keys %{ $d->{lookup} }), join(",", map { $d->{lookup}{$_}{looked_up} ? "true" : "false" } sort keys %{ $d->{lookup} }), $d->{advisories_ok} ? "true" : "false"');$(requested "$CVE_URL");$(requested "$GHSA_URL")" \
        "CVE-2024-38816,CVE-2024-6387,CVE-2025-29927;true,true,true;true;3;3"
}

case_token() {
    newcase
    put_cve CVE-2025-29927 200 "$FIX/test-ranges/cve-CVE-2025-29927.json" 200 "$FIX/test-ranges/ghsa-CVE-2025-29927.json"
    put_cve CVE-2024-6387 200 "$FIX/test-ranges/cve-CVE-2024-6387.json" 200 "$CASE/empty.json"
    run_lookup "CVE-2025-29927 CVE-2024-6387" '{}'
    local name="GitHub の勧告への要求で、トークンが curl の引数に入らず、-H で渡したファイルにだけ書かれ、呼び出しのあとにファイルが消える"
    # 組ごとに、URL と、-H @<ファイル> の数と、ほかのヘッダーを並べる
    check "$name(GitHub の勧告の組にだけ -H @<ファイル> を付ける)" \
        "$(perl -ne '
            BEGIN { @g = ({}); $prev = "" }
            chomp;
            if (/\AKARG --next\z/) { push @g, {}; $prev = $_; next }
            if (/\AKARG (https:\S+)\z/) { $g[-1]{url} = $1; $prev = $_; next }
            if ($prev eq "KARG -H" && /\AKARG (.*)\z/) { my $h = $1; if ($h =~ /\A@/) { $g[-1]{file}++ } else { push @{ $g[-1]{h} }, $h } }
            $prev = $_;
            END { print join ";", map { join "|", $_->{url}, $_->{file} || 0, @{ $_->{h} || [] } } sort { $a->{url} cmp $b->{url} } @g }
        ' <"$CASE/curl.log")" \
        "https://api.github.com/advisories?cve_id=CVE-2024-6387|1|Accept: application/vnd.github+json|X-GitHub-Api-Version: 2022-11-28;https://api.github.com/advisories?cve_id=CVE-2025-29927|1|Accept: application/vnd.github+json|X-GitHub-Api-Version: 2022-11-28;https://cveawg.mitre.org/api/cve/CVE-2024-6387|0;https://cveawg.mitre.org/api/cve/CVE-2025-29927|0"
    check "$name(curl の引数と、設定ファイルから読んだ引数にトークンが無い)" \
        "$(grep -E '^K?ARG ' "$CASE/curl.log" | grep -c -F "$FAKE_TOKEN")" "0"
    check "$name(-H で渡したファイルにトークンの1行だけが書かれる)" \
        "$(perl -ne 'print "$1\n" if /\AHFILE \S+ (.*)$/' <"$CASE/curl.log" | sort -u)" "Authorization: Bearer $FAKE_TOKEN"
    local files
    files=$(perl -ne 'print "$1\n" if /\AHFILE (\S+) /' <"$CASE/curl.log" | sort -u)
    check "$name(ファイルは \$work_dir のフォルダに1つだけ作られ、呼び出しのあとに消える)" \
        "$(printf '%s\n' "$files" | wc -l | tr -d ' ');$(cd "$CASE/work" && for f in $files; do [ -e "$f" ] && echo left; done);$(grep -rlF "$FAKE_TOKEN" "$CASE/work" | wc -l | tr -d ' ')" \
        "1;;0"
}

case_limit() {
    newcase
    # 記事の項目の番号を303件、KEV の項目の番号を2件にし、KEV の番号を最後に渡す
    local cves='' prio='' n
    for n in $(seq 1000 1302); do
        cves="$cves CVE-2026-$n"
        prio="$prio\"CVE-2026-$n\":303,"
    done
    cves="$cves CVE-2026-9001 CVE-2026-9002"
    prio="{$prio\"CVE-2026-9001\":0,\"CVE-2026-9002\":0}"
    # すべての番号に見本を置き、引いた番号はすべて looked_up が真になるようにする
    perl -e '
        my ($dir, $cve_body, $ghsa_body, @cves) = @ARGV;
        for my $c (@cves) {
            for my $u ("https://cveawg.mitre.org/api/cve/$c", "https://api.github.com/advisories?cve_id=$c") {
                (my $name = $u) =~ s/[^A-Za-z0-9]/_/g;
                open my $s, ">", "$dir/$name.status" or die; print $s "200"; close $s;
                my $from = $u =~ /cveawg/ ? $cve_body : $ghsa_body;
                open my $i, "<:raw", $from or die; open my $o, ">:raw", "$dir/$name.body" or die;
                print $o do { local $/; <$i> }; close $i; close $o;
            }
        }
    ' "$KP_FAKE_CURL_DIR" "$FIX/test-ranges/cve-CVE-2025-29927.json" "$CASE/empty.json" $cves
    run_lookup "$cves" "$prio"
    local name="CVE の番号が300件を超えるとき、引かなかった番号の looked_up が偽になる。KEV の項目の番号が、CVE の番号を多く持つ記事の番号より先に引かれる"
    check "$name(300件まで引く)" \
        "$(requested "$CVE_URL");$(requested "$GHSA_URL");$(out 'scalar keys %{ $d->{lookup} }');$(out 'scalar grep { $_->{looked_up} } values %{ $d->{lookup} }')" \
        "300;300;305;300"
    check "$name(KEV の番号を先に引き、記事の番号を渡した順に引く)" \
        "$(out 'join ",", map { $d->{lookup}{$_}{looked_up} ? "true" : "false" } qw(CVE-2026-9001 CVE-2026-9002 CVE-2026-1000 CVE-2026-1297 CVE-2026-1298 CVE-2026-1302)')" \
        "true,true,true,true,false,false"
    check "$name(引かなかった番号があれば advisories_ok が偽になる)" \
        "$(out '$d->{advisories_ok} ? "true" : "false"')" "false"
}

case_failures() {
    local name="CVE の記録は取れて GitHub の勧告への要求だけが失敗した番号と、gh が使えないときのすべての番号の looked_up が偽になる。どちらの場合も advisories_ok が偽になる"
    newcase
    printf '{"message":"Server Error"}' >"$CASE/error.json"
    put_cve CVE-2025-29927 200 "$FIX/test-ranges/cve-CVE-2025-29927.json" 200 "$FIX/test-ranges/ghsa-CVE-2025-29927.json"
    put_cve CVE-2024-38816 200 "$FIX/test-ranges/cve-CVE-2024-38816.json" 500 "$CASE/error.json"
    put_cve CVE-2024-6387 200 "$FIX/test-ranges/cve-CVE-2024-6387.json" 200 "$CASE/error.json"
    put_cve CVE-2024-21733 200 "$FIX/test-ranges/cve-CVE-2025-29927.json" 000 "$CASE/empty.json"
    run_lookup "CVE-2025-29927 CVE-2024-38816 CVE-2024-6387 CVE-2024-21733" '{}'
    check "$name(勧告が状態 500 と、配列でない本文と、つながらなかった番号)" \
        "$(out 'join ",", (map { $d->{lookup}{$_}{looked_up} ? "true" : "false" } qw(CVE-2025-29927 CVE-2024-38816 CVE-2024-6387 CVE-2024-21733)), $d->{advisories_ok} ? "true" : "false", scalar @{ $d->{lookup}{"CVE-2024-38816"}{products} }')" \
        "true,false,false,false,false,4"
    newcase
    put_cve CVE-2099-0001 404 "$FIX/test-ranges/cve-none.json" 200 "$CASE/empty.json"
    run_lookup "CVE-2099-0001" '{}'
    check "CVE の記録だけが得られなかった番号の looked_up が偽になり、勧告はすべて引けたので advisories_ok は真のまま" \
        "$(out 'join ",", $d->{lookup}{"CVE-2099-0001"}{looked_up} ? "true" : "false", $d->{advisories_ok} ? "true" : "false"')" \
        "false,true"
    newcase
    export KP_FAKE_GH_FAIL=auth-token
    put_cve CVE-2025-29927 200 "$FIX/test-ranges/cve-CVE-2025-29927.json" 200 "$FIX/test-ranges/ghsa-CVE-2025-29927.json"
    put_cve CVE-2024-6387 200 "$FIX/test-ranges/cve-CVE-2024-6387.json" 200 "$CASE/empty.json"
    run_lookup "CVE-2025-29927 CVE-2024-6387" '{}'
    check "$name(gh が使えないとき、勧告を引かず、CVE の記録は引く)" \
        "$(out 'join ",", (map { $d->{lookup}{$_}{looked_up} ? "true" : "false" } qw(CVE-2025-29927 CVE-2024-6387)), $d->{advisories_ok} ? "true" : "false", scalar @{ $d->{lookup}{"CVE-2025-29927"}{products} }');$(requested "$CVE_URL");$(requested "$GHSA_URL")" \
        "false,false,false,1;2;0"
}

case_deadline() {
    local name="ranges_lookup に今から5秒後の打ち切りの時刻を渡し、CVE の記録の応答を60秒遅らせると、ranges_lookup が打ち切りの時刻から数秒のうちに返り、残った番号の looked_up が偽になる"
    newcase
    put_cve CVE-2025-29927 200 "$FIX/test-ranges/cve-CVE-2025-29927.json" 200 "$FIX/test-ranges/ghsa-CVE-2025-29927.json"
    put_cve CVE-2024-6387 200 "$FIX/test-ranges/cve-CVE-2024-6387.json" 200 "$CASE/empty.json"
    export KP_FAKE_CURL_DELAY="${CVE_URL}CVE-2024-6387=60"
    run_lookup "CVE-2025-29927 CVE-2024-6387" '{}' 5
    check "$name" \
        "$(out 'join ",", ($d->{elapsed} >= 4.5 && $d->{elapsed} < 9 ? "in-time" : "elapsed=$d->{elapsed}"), map { $d->{lookup}{$_}{looked_up} ? "true" : "false" } qw(CVE-2025-29927 CVE-2024-6387)')" \
        "in-time,true,false"
    check "$name(打ち切ったときも、-H で渡したファイルが消える)" \
        "$(grep -rlF "$FAKE_TOKEN" "$CASE/work" | wc -l | tr -d ' ')" "0"
    newcase
    put_cve CVE-2025-29927 200 "$FIX/test-ranges/cve-CVE-2025-29927.json" 200 "$FIX/test-ranges/ghsa-CVE-2025-29927.json"
    run_lookup "CVE-2025-29927" '{}' 0
    check "打ち切りの時刻を過ぎていれば curl を呼ばず、すべての番号の looked_up と advisories_ok が偽になる" \
        "$(out 'join ",", $d->{lookup}{"CVE-2025-29927"}{looked_up} ? "true" : "false", $d->{advisories_ok} ? "true" : "false"');$([ -e "$CASE/curl.log" ] && echo called)" \
        "false,false;"
}

CASES='compare forms uncomparable partial lookup token limit failures deadline'

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
