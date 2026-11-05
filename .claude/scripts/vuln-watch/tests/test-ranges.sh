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
#   F(<出どころ>, <範囲の JSON か、読んだ範囲>): ranges_fixed の値。直った版が無ければ null と出す
rr() {
    perl -MJSON::PP -e '
        require $ARGV[0];
        sub C { my $c = ranges_version_cmp(@_); defined $c ? $c : "undef" }
        sub IN {
            my ($source, $json, $version, $partial) = @_;
            my ($in, $why) = ranges_in_range($source, JSON::PP->new->decode($json), $version, $partial);
            defined $in ? ($in ? "true" : "false") : "null:" . (defined $why ? $why : "");
        }
        sub F {
            my ($source, $range) = @_;
            my $f = ranges_fixed($source, ref $range ? $range : JSON::PP->new->decode($range));
            defined $f ? $f : "null";
        }
        my $v = eval $ARGV[1];
        die $@ if $@;
        print defined $v ? $v : "<undef>";
    ' "$RANGES" "$@" 2>&1
}

FIX="$HERE/fixtures"
ALIASES="$(cd "$HERE/.." && pwd)/aliases.json"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd -P; })
ORIG_PATH=$PATH

CVE_URL=https://cveawg.mitre.org/api/cve/
GHSA_URL='https://api.github.com/advisories?cve_id='
NVD_URL='https://services.nvd.nist.gov/rest/json/cves/2.0?cveId='
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
# 部品の一覧と KEV の名前のファイルを渡したときは、本物の aliases.json と合わせて渡す。渡さなければ、どれも空にする。
# run_lookup <空白で区切った CVE の番号> <先に引く順の JSON> [<打ち切りまでの秒数> [<部品の一覧の JSON のファイル> <KEV の名前の JSON のファイル>]]
run_lookup() {
    (cd "$CASE/work" && perl -MJSON::PP -MTime::HiRes=time -e '
        require $ARGV[0];
        my @cves = split " ", $ARGV[1];
        my $read = sub { return {} unless length $_[0]; open my $h, "<", $_[0] or die "$_[0]: $!"; local $/; JSON::PP->new->utf8->decode(<$h>) };
        my ($inventory, $aliases, $kev) = length $ARGV[5] ? map { $read->($_) } @ARGV[5 .. 7] : ({}, {}, {});
        my $t0 = time;
        my ($lookup, $ok) = ranges_lookup(\@cves, JSON::PP->new->decode($ARGV[2]), $inventory, $aliases, $kev, $ARGV[3], time + $ARGV[4]);
        print JSON::PP->new->utf8->canonical->encode({ lookup => $lookup, advisories_ok => ($ok ? JSON::PP::true : JSON::PP::false), elapsed => time - $t0 });
    ' "$RANGES" "$1" "$2" "$CASE/work" "${3:-60}" "${4:-}" "$ALIASES" "${5:-}" >"$CASE/out.json" 2>"$CASE/err.txt")
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
    export KP_FAKE_CURL_DIR="$CASE/curl" KP_FAKE_GH_DIR="$CASE/gh" KP_FAKE_CURL_LOG="$CASE/curl.log" KP_FAKE_GH_LOG="$CASE/gh.log"
    unset KP_FAKE_CURL_DELAY KP_FAKE_GH_FAIL KP_VULN_WATCH_NVD_WAIT
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
    local -a cve_list
    read -r -a cve_list <<<"$cves"
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
    ' "$KP_FAKE_CURL_DIR" "$FIX/test-ranges/cve-CVE-2025-29927.json" "$CASE/empty.json" "${cve_list[@]}"
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

# ranges_match を呼び、返した値を JSON で $CASE/out.json に書く。aliases.json のファイルを渡さなければ、本物の aliases.json を使う。
# run_match <CVE の番号ごとの引いた値の JSON のファイル> <部品の一覧の JSON のファイル> <KEV の名前の JSON のファイル> [<aliases.json のファイル>]
run_match() {
    perl -MJSON::PP -e '
        require $ARGV[0];
        my $j = JSON::PP->new->utf8;
        my $read = sub { open my $h, "<", $_[0] or die "$_[0]: $!"; local $/; $j->decode(<$h>) };
        my $aliases = $read->($ARGV[1]);
        print $j->canonical->encode(ranges_match($read->($ARGV[2]), $read->($ARGV[3]), $aliases, $read->($ARGV[4])));
    ' "$RANGES" "${4:-$ALIASES}" "$1" "$2" "$3" >"$CASE/out.json" 2>"$CASE/err.txt"
}

# CVE の番号の突き合わせの結果を、部品の鍵の順に「鍵|in_range|range_source|reason」の形で、空白で区切って出す: ms <CVE の番号>
ms() {
    KP_CVE=$1 pj 'join " ", map { join "|", $_->{key}, (defined $_->{in_range} ? ($_->{in_range} ? "true" : "false") : "null"), $_->{range_source} // "-", $_->{reason} // "-" } sort { $a->{key} cmp $b->{key} } @{ $d->{$ENV{KP_CVE}}{matches} }' <"$CASE/out.json"
}

case_aliases() {
    check "aliases.json が JSON として読め、部品「aliases.json」の表の12行の部品の鍵を持つ" \
        "$(pj 'join " ", $d->{version}, sort keys %{ $d->{aliases} }' <"$ALIASES")" \
        "1 aws:elasticache aws:rds ci:node ci:trivy image:debian image:docker image:eclipse-temurin image:ghcr.io/terraform-linters/tflint image:hashicorp/terraform image:localstack/localstack image:node image:postgres image:valkey/valkey maven:org.apache.tomcat.embed:tomcat-embed-core runtime:java tool:gradle"
    check "aliases.json が JSON として読め、部品「aliases.json」の表の12行の部品の鍵を持つ(名前は小文字で空白を持たない <vendor>:<product> の形)" \
        "$(pj 'my @bad = grep { my $l = $d->{aliases}{$_}; ref $l ne "ARRAY" || !@$l || grep { !/\A[^:\sA-Z]+:[^:\sA-Z]+\z/ } @$l } sort keys %{ $d->{aliases} }; join " ", @bad' <"$ALIASES")" \
        ""
    check "aliases.json が JSON として読め、部品「aliases.json」の表の12行の部品の鍵を持つ(同じ行の部品の鍵は同じ名前を持つ)" \
        "$(pj 'my $a = $d->{aliases}; join " ", map { join(",", @{ $a->{$_->[0]} }) eq join(",", @{ $a->{$_->[1]} }) ? 1 : 0 } (["image:eclipse-temurin", "runtime:java"], ["image:postgres", "aws:rds"], ["image:valkey/valkey", "aws:elasticache"], ["image:node", "ci:node"])' <"$ALIASES")" \
        "1 1 1 1"
}

case_match() {
    newcase
    cat >"$CASE/lookup.json" <<'EOF'
{
  "CVE-2026-1001": {"looked_up": true, "products": [], "advisories": []},
  "CVE-2024-27983": {"looked_up": true, "advisories": [], "products": [
    {"from": "cna", "vendor": "NodeJS", "product": "Node", "defaultStatus": "unaffected", "versions": [
      {"version": "20.0.0", "lessThan": "20.12.1", "status": "affected", "versionType": "semver"},
      {"version": "22.0.0", "lessThan": "22.1.0", "status": "affected", "versionType": "semver"}]}]},
  "CVE-2026-1002": {"looked_up": true, "advisories": [], "products": [
    {"from": "cna", "vendor": "Example", "product": "Other", "versions": [{"version": "0", "lessThan": "99", "status": "affected"}]}]},
  "CVE-2026-1004": {"looked_up": true, "advisories": [], "products": [
    {"from": "cna", "vendor": "Moby", "product": "Moby", "versions": [{"version": "0", "lessThan": "99", "status": "affected"}]}]}
}
EOF
    cat >"$CASE/inventory.json" <<'EOF'
{"components": {
  "image:eclipse-temurin": {"versions": ["21"], "files": ["docker/backend/Dockerfile"], "partial": true},
  "runtime:java": {"versions": ["21"], "files": ["backend/build.gradle"], "partial": true},
  "image:node": {"versions": ["20.11.0"], "files": ["docker/frontend/Dockerfile", "compose.yaml"], "partial": false},
  "ci:node": {"versions": ["21"], "files": [".github/workflows/ci.yaml"], "partial": true},
  "npm:next": {"versions": ["15.5.2"], "files": ["frontend/pnpm-lock.yaml"], "partial": false}
}}
EOF
    printf '%s' '{"CVE-2026-1001": [["Oracle", "Java SE"]]}' >"$CASE/kev.json"
    run_match "$CASE/lookup.json" "$CASE/inventory.json" "$CASE/kev.json"
    local name="KEV の Oracle の Java SE が image:eclipse-temurin と runtime:java に合い、CNA の NodeJS の Node が image:node と ci:node に合う"
    check "$name(KEV の名前)" "$(ms CVE-2026-1001)" "image:eclipse-temurin|null|-|no_range runtime:java|null|-|no_range"
    check "$name(CNA の名前と、その製品の範囲)" "$(ms CVE-2024-27983)" "ci:node|false|cna|- image:node|true|cna|-"
    check "$name(名前が表に無い製品は、CNA の製品が1つだけでも、どの部品にも合わない)" "$(ms CVE-2026-1002)" ""
    check "$name(表で引いた部品の鍵が部品の一覧に無ければ、合わない)" "$(ms CVE-2026-1004)" ""
    check "$name(部品の版と、読んだファイル)" \
        "$(pj 'my ($m) = grep { $_->{key} eq "image:node" } @{ $d->{"CVE-2024-27983"}{matches} }; join "|", join(",", @{ $m->{repo_versions} }), $m->{file}, defined $m->{fixed} ? $m->{fixed} : "null"' <"$CASE/out.json")" \
        "20.11.0|docker/frontend/Dockerfile, compose.yaml|20.12.1"
}

case_sources() {
    newcase
    cat >"$CASE/lookup.json" <<'EOF'
{
  "CVE-2025-24813": {"looked_up": true,
    "advisories": [{"ghsa_id": "GHSA-83qj-6fr2-vhqg", "repository_advisory_url": null, "vulnerabilities": [
      {"ecosystem": "maven", "name": "org.apache.tomcat.embed:tomcat-embed-core", "vulnerable_version_range": "< 11.0.3", "first_patched_version": "11.0.3"}]}],
    "products": [
      {"from": "cna", "vendor": "Apache Software Foundation", "product": "Apache Tomcat", "versions": [{"version": "11.0.0-M1", "lessThan": "11.0.6", "status": "affected", "versionType": "semver"}]},
      {"from": "cna", "vendor": "Apache Software Foundation", "product": "Apache Tomcat Connectors", "versions": [{"version": "1.0", "lessThan": "1.2.50", "status": "affected"}]}]},
  "CVE-2025-29927": {"looked_up": true,
    "advisories": [{"ghsa_id": "GHSA-f82v-jwr5-mffw", "repository_advisory_url": "https://github.com/vercel/next.js/security/advisories/GHSA-f82v-jwr5-mffw", "vulnerabilities": [
      {"ecosystem": "npm", "name": "next", "vulnerable_version_range": ">= 15.0.0, < 15.2.3", "first_patched_version": "15.2.3"}]}],
    "products": [{"from": "cna", "vendor": "vercel", "product": "next.js", "versions": [{"version": "0", "lessThan": "16.0.0", "status": "affected"}]}]},
  "CVE-2026-2001": {"looked_up": true,
    "advisories": [{"ghsa_id": "GHSA-xxxx-xxxx-xxx1", "repository_advisory_url": null, "vulnerabilities": [
      {"ecosystem": "npm", "name": "next", "vulnerable_version_range": "< 16.0.0", "first_patched_version": "16.0.0"}]}],
    "products": []},
  "CVE-2026-2006": {"looked_up": true,
    "advisories": [{"ghsa_id": "GHSA-xxxx-xxxx-xxx6", "repository_advisory_url": "https://github.com/apache/tomcat/security/advisories/GHSA-xxxx-xxxx-xxx6", "vulnerabilities": [
      {"ecosystem": "maven", "name": "org.apache.tomcat.embed:tomcat-embed-core", "vulnerable_version_range": "< 11.0.3", "first_patched_version": "11.0.3"}]}],
    "products": [
      {"from": "cna", "vendor": "Apache Software Foundation", "product": "Apache Tomcat", "versions": [{"version": "11.0.0-M1", "lessThan": "11.0.6", "status": "affected", "versionType": "semver"}]}]},
  "CVE-2026-2003": {"looked_up": true,
    "advisories": [{"ghsa_id": "GHSA-xxxx-xxxx-xxx3", "repository_advisory_url": null, "vulnerabilities": [
      {"ecosystem": "npm", "name": "next", "vulnerable_version_range": "< 15.0.0", "first_patched_version": "15.0.0"}]}],
    "products": [{"from": "cna", "vendor": "vercel", "product": "next.js", "versions": [{"version": "0", "lessThan": "16.0.0", "status": "affected"}]}]},
  "CVE-2026-2004": {"looked_up": true,
    "advisories": [{"ghsa_id": "GHSA-xxxx-xxxx-xxx4", "repository_advisory_url": "https://github.com/vercel/next.js/security/advisories/GHSA-xxxx-xxxx-xxx4", "vulnerabilities": [
      {"ecosystem": "npm", "name": "next", "vulnerable_version_range": null, "first_patched_version": null}]}],
    "products": [{"from": "cna", "vendor": "vercel", "product": "next.js", "versions": [{"version": "0", "lessThan": "16.0.0", "status": "affected"}]}]},
  "CVE-2026-2005": {"looked_up": true,
    "advisories": [{"ghsa_id": "GHSA-xxxx-xxxx-xxx5", "repository_advisory_url": "https://github.com/facebook/react/security/advisories/GHSA-xxxx-xxxx-xxx5", "vulnerabilities": [
      {"ecosystem": "npm", "name": "next", "vulnerable_version_range": ">= 13.0.0, < 13.5.9", "first_patched_version": "13.5.9"},
      {"ecosystem": "npm", "name": "next", "vulnerable_version_range": ">= 15.0.0, < 15.5.3", "first_patched_version": "15.5.3"},
      {"ecosystem": "npm", "name": "react", "vulnerable_version_range": "< 18.3.0", "first_patched_version": "18.3.0"}]}],
    "products": []},
  "CVE-2026-2002": {"looked_up": true, "advisories": [],
    "products": [
      {"from": "cna", "vendor": "example", "product": "left pad", "collectionURL": "https://www.npmjs.com", "packageName": "left-pad", "versions": [{"version": "0", "lessThan": "1.3.0", "status": "affected"}]},
      {"from": "adp", "vendor": "example", "product": "right pad", "collectionURL": "https://repo.maven.apache.org/maven2", "packageName": "org.example:right-pad", "versions": [{"version": "2.0", "lessThan": "2.1", "status": "affected"}]}]}
}
EOF
    cat >"$CASE/inventory.json" <<'EOF'
{"components": {
  "maven:org.apache.tomcat.embed:tomcat-embed-core": {"versions": ["11.0.5"], "files": ["dependency-graph/sbom"], "partial": false},
  "npm:next": {"versions": ["15.5.2"], "files": ["frontend/pnpm-lock.yaml"], "partial": false},
  "npm:left-pad": {"versions": ["1.1.0"], "files": ["frontend/pnpm-lock.yaml"], "partial": false},
  "npm:react": {"versions": ["19.0.0", "18.2.0"], "files": ["frontend/pnpm-lock.yaml"], "partial": false},
  "maven:org.example:right-pad": {"versions": ["2.1.0"], "files": ["backend/gradle/libs.versions.toml"], "partial": false}
}}
EOF
    printf '{}' >"$CASE/kev.json"
    run_match "$CASE/lookup.json" "$CASE/inventory.json" "$CASE/kev.json"
    check "Tomcat のように、名前が合った出どころと範囲を読む出どころが違うとき、aliases.json の対応で CVE の記録の製品の範囲が使われる" \
        "$(ms CVE-2025-24813)" "maven:org.apache.tomcat.embed:tomcat-embed-core|true|cna|-"
    check "Tomcat のように、名前が合った出どころと範囲を読む出どころが違うとき、aliases.json の対応で CVE の記録の製品の範囲が使われる(名前が合った勧告が範囲を持てば、勧告の範囲が先に使われる)" \
        "$(ms CVE-2026-2006)" "maven:org.apache.tomcat.embed:tomcat-embed-core|false|github|-"
    check "repository_advisory_url が空の GitHub の勧告の範囲が使われない" \
        "$(ms CVE-2026-2001)" "npm:next|null|-|no_range"
    check "repository_advisory_url が空の GitHub の勧告の範囲が使われない(空でない勧告の範囲は、CVE の記録の製品の範囲より先に使われる)" \
        "$(ms CVE-2025-29927)" "npm:next|false|github|-"
    check "名前が合った出どころと aliases.json の対応のどちらにも範囲が無ければ、CNA の製品が1つだけのときにその製品の範囲が使われる" \
        "$(ms CVE-2026-2003)" "npm:next|true|cna|-"
    check "名前が合った出どころと aliases.json の対応のどちらにも範囲が無ければ、CNA の製品が1つだけのときにその製品の範囲が使われる(範囲の式を持たない勧告は、範囲が無いとする)" \
        "$(ms CVE-2026-2004)" "npm:next|true|cna|-"
    check "1つの出どころに範囲が2つ以上あるときと、部品の版が2つ以上あるときは、1つでも入れば範囲に入る" \
        "$(ms CVE-2026-2005)" "npm:next|true|github|- npm:react|true|github|-"
    check "CVE の記録の collectionURL が npm か Maven の登録所の製品は、packageName で部品の鍵に合う" \
        "$(ms CVE-2026-2002)" "maven:org.example:right-pad|false|adp|- npm:left-pad|true|cna|-"
}

case_undecided() {
    newcase
    cat >"$CASE/lookup.json" <<'EOF'
{
  "CVE-2026-3001": {"looked_up": true, "advisories": [], "products": [
    {"from": "cna", "vendor": "PostgreSQL", "product": "PostgreSQL", "versions": []},
    {"from": "cna", "vendor": "PostgreSQL", "product": "pgAdmin", "versions": [{"version": "0", "lessThan": "9", "status": "affected"}]}]},
  "CVE-2026-3002": {"looked_up": true, "advisories": [], "products": [
    {"from": "cna", "vendor": "Debian", "product": "Debian Linux", "versions": [{"version": "0", "lessThan": "13", "status": "affected"}]}]}
}
EOF
    cat >"$CASE/inventory.json" <<'EOF'
{"components": {
  "image:postgres": {"versions": ["17.6"], "files": ["compose.yaml"], "partial": false},
  "aws:rds": {"versions": ["17.6"], "files": ["terraform/modules/rds/main.tf"], "partial": false},
  "image:debian": {"versions": [], "files": ["docker/backend/Dockerfile"], "partial": false}
}}
EOF
    printf '{}' >"$CASE/kev.json"
    run_match "$CASE/lookup.json" "$CASE/inventory.json" "$CASE/kev.json"
    local name="範囲が無い番号と、版が分からない部品が、in_range が null で、no_range と no_version になる"
    check "$name(範囲が無い番号)" "$(ms CVE-2026-3001)" "aws:rds|null|-|no_range image:postgres|null|-|no_range"
    check "$name(版が分からない部品)" "$(ms CVE-2026-3002)" "image:debian|null|cna|no_version"
}

case_notlooked() {
    newcase
    cat >"$CASE/lookup.json" <<'EOF'
{
  "CVE-2026-4001": {"looked_up": false, "advisories": [], "products": []},
  "CVE-2026-4002": {"looked_up": false, "advisories": [], "products": [
    {"from": "cna", "vendor": "NodeJS", "product": "Node", "versions": [{"version": "20.0.0", "lessThan": "20.12.1", "status": "affected"}]}]},
  "CVE-2026-4003": {"looked_up": true, "advisories": [], "products": []}
}
EOF
    printf '%s' '{"components": {"image:node": {"versions": ["20.11.0"], "files": ["compose.yaml"], "partial": false}}}' >"$CASE/inventory.json"
    printf '{}' >"$CASE/kev.json"
    run_match "$CASE/lookup.json" "$CASE/inventory.json" "$CASE/kev.json"
    local name="looked_up が偽の番号が、名前の合った部品が無くても、鍵 * と not_looked_up の1件を返す"
    check "$name" "$(ms CVE-2026-4001)" "*|null|-|not_looked_up"
    check "$name(名前の合った部品があれば、その部品と、鍵 * の1件を返す)" "$(ms CVE-2026-4002)" "*|null|-|not_looked_up image:node|true|cna|-"
    check "$name(looked_up が真で名前の合った部品が無い番号は、何も返さない)" "$(ms CVE-2026-4003)" ""
}

# CVE の番号の突き合わせの結果を、部品の鍵の順に「鍵|in_range|部品の版を , でつないだ文字列|fixed」の形で、空白で区切って出す: mf <CVE の番号>
mf() {
    KP_CVE=$1 pj 'join " ", map { join "|", $_->{key}, (defined $_->{in_range} ? ($_->{in_range} ? "true" : "false") : "null"), join(",", @{ $_->{repo_versions} }), $_->{fixed} // "null" } sort { $a->{key} cmp $b->{key} } @{ $d->{$ENV{KP_CVE}}{matches} }' <"$CASE/out.json"
}

case_fixed() {
    local name="GitHub の勧告の first_patched_version と、CVE の記録の affected の範囲の lessThan と、version に書かれた式の < の値と、CVE の記録の unaffected の範囲の version が、直った版になる。範囲に入った部品の fixed が、部品の版が入った範囲の直った版になる"
    check "$name(範囲の1つから決める)" \
        "$(rr 'join " ", map { F(@$_) } (["ghsa", q({"first_patched_version":"15.2.3"})], ["cve", q({"version":"1.0","lessThan":"1.2.3","status":"affected"})], ["cve", q({"version":">= 14.0.0, < 14.2.25","status":"affected"})], ["cve", q({"version":"6.1.117","lessThanOrEqual":"6.1.*","status":"unaffected","versionType":"semver"})])')" \
        "15.2.3 1.2.3 14.2.25 6.1.117"
    local name2="lessThanOrEqual だけを持つ affected の範囲と、lessThan を持つ unaffected の範囲と、git の範囲からは、直った版が null になる。in_range が偽か null の部品の fixed が null になる"
    check "$name2(範囲の1つから決める)" \
        "$(rr 'join " ", map { F(@$_) } (["cve", q({"version":"1.0","lessThanOrEqual":"1.2","status":"affected"})], ["cve", q({"version":"0","lessThan":"3.12","status":"unaffected","versionType":"semver"})], ["cve", q({"version":"27ce405039bfe6d3f4143415c638f56a3df77dca","lessThan":"e7ea60184e1e88a3c9e437b3265cbb6439aa7e26","status":"affected","versionType":"git"})], ["ghsa", q({"first_patched_version":null})], ["cve", q({"version":">= 1.0, <= 1.2","status":"affected"})], ["cve", q({"version":"2.0","lessThan":"2.5","status":"unaffected"})], ["cve", q({"version":"0","lessThanOrEqual":"2.*","status":"unaffected"})], ["cve", q({"version":"unspecified","lessThanOrEqual":"2.*","status":"unaffected"})], ["cve", q({"version":"1.0","lessThan":"*","status":"affected"})], ["ghsa", q({"first_patched_version":""})])')" \
        "null null null null null null null null null null"

    newcase
    put_cve CVE-2024-50302 200 "$FIX/test-ranges/cve-CVE-2024-50302.json" 200 "$CASE/empty.json"
    run_lookup CVE-2024-50302 '{}'
    check "$name(CVE-2024-50302 の CVE の記録の、範囲ごとの直った版)" \
        "$(rr 'my $d = JSON::PP->new->utf8->decode(do { open my $h, "<", $ARGV[2] or die "$ARGV[2]: $!"; local $/; <$h> }); join " / ", map { join " ", map { F("cve", $_) } @{ $_->{versions} } } @{ $d->{lookup}{"CVE-2024-50302"}{products} }' "$CASE/out.json")" \
        "null null null 3.11 3.12 / null null 4.19.324 5.4.286 5.10.230 5.15.172 6.1.117 6.6.61 6.11.8 6.12"
    perl -MJSON::PP -e 'my $j = JSON::PP->new->utf8; local $/; my $d = $j->decode(<STDIN>); print $j->encode($d->{lookup})' <"$CASE/out.json" >"$CASE/lookup.json"
    cat >"$CASE/aliases.json" <<'EOF'
{"version": 1, "aliases": {"os:linux": ["linux:linux"], "os:linux-lts": ["linux:linux"], "os:linux-new": ["linux:linux"], "os:linux-old": ["linux:linux"]}}
EOF
    cat >"$CASE/inventory.json" <<'EOF'
{"components": {
  "os:linux": {"versions": ["6.1.100"], "files": ["a"], "partial": false},
  "os:linux-lts": {"versions": ["3.12"], "files": ["a"], "partial": false},
  "os:linux-new": {"versions": ["6.12.3"], "files": ["a"], "partial": false},
  "os:linux-old": {"versions": ["2.6.0"], "files": ["a"], "partial": false}
}}
EOF
    printf '{}' >"$CASE/kev.json"
    run_match "$CASE/lookup.json" "$CASE/inventory.json" "$CASE/kev.json" "$CASE/aliases.json"
    check "$name(版の系列ごとに直った版を書いた CVE の記録では、部品の版より大きい最も小さい直った版になる)" \
        "$(mf CVE-2024-50302)" \
        "os:linux|true|6.1.100|6.1.117 os:linux-lts|true|3.12|null os:linux-new|null|6.12.3|null os:linux-old|null|2.6.0|null"

    newcase
    cat >"$CASE/lookup.json" <<'EOF'
{
  "CVE-2025-29927": {"looked_up": true, "products": [],
    "advisories": [{"ghsa_id": "GHSA-f82v-jwr5-mffw", "repository_advisory_url": "https://github.com/vercel/next.js/security/advisories/GHSA-f82v-jwr5-mffw", "vulnerabilities": [
      {"ecosystem": "npm", "name": "next", "vulnerable_version_range": ">= 13.0.0, < 13.5.9", "first_patched_version": "13.5.9"},
      {"ecosystem": "npm", "name": "next", "vulnerable_version_range": ">= 15.0.0, < 15.2.3", "first_patched_version": "15.2.3"},
      {"ecosystem": "npm", "name": "react", "vulnerable_version_range": "< 18.3.0", "first_patched_version": null}]}]},
  "CVE-2026-5001": {"looked_up": true, "advisories": [], "products": [
    {"from": "cna", "vendor": "example", "product": "left pad", "collectionURL": "https://www.npmjs.com", "packageName": "left-pad", "versions": [
      {"version": ">= 1.0.0, < 1.3.0", "status": "affected"},
      {"version": "2.0.0", "lessThanOrEqual": "2.1.0", "status": "affected"}]}]}
}
EOF
    cat >"$CASE/inventory.json" <<'EOF'
{"components": {
  "npm:next": {"versions": ["13.4.0", "15.0.0", "15.1.0", "15.5.2"], "files": ["frontend/pnpm-lock.yaml"], "partial": false},
  "npm:react": {"versions": ["18.2.0"], "files": ["frontend/pnpm-lock.yaml"], "partial": false},
  "npm:left-pad": {"versions": ["1.1.0", "2.0.5"], "files": ["frontend/pnpm-lock.yaml"], "partial": false}
}}
EOF
    printf '{}' >"$CASE/kev.json"
    run_match "$CASE/lookup.json" "$CASE/inventory.json" "$CASE/kev.json"
    check "$name(GitHub の勧告で、部品の版が入った範囲ごとの直った版)" \
        "$(mf CVE-2025-29927)" \
        "npm:next|true|13.4.0,15.0.0,15.1.0,15.5.2|13.5.9, 15.2.3 npm:react|true|18.2.0|null"
    check "$name(CVE の記録の version の式の直った版と、lessThanOrEqual だけを持つ範囲)" \
        "$(mf CVE-2026-5001)" \
        "npm:left-pad|true|1.1.0,2.0.5|1.3.0"

    newcase
    cat >"$CASE/lookup.json" <<'EOF'
{
  "CVE-2026-5002": {"looked_up": true, "products": [],
    "advisories": [{"ghsa_id": "GHSA-xxxx-xxxx-xx52", "repository_advisory_url": "https://github.com/vercel/next.js/security/advisories/GHSA-xxxx-xxxx-xx52", "vulnerabilities": [
      {"ecosystem": "npm", "name": "next", "vulnerable_version_range": ">= 15.0.0, < 15.2.3", "first_patched_version": "15.2.3"}]}]},
  "CVE-2026-5003": {"looked_up": false, "products": [],
    "advisories": [{"ghsa_id": "GHSA-xxxx-xxxx-xx53", "repository_advisory_url": "https://github.com/vercel/next.js/security/advisories/GHSA-xxxx-xxxx-xx53", "vulnerabilities": [
      {"ecosystem": "npm", "name": "next", "vulnerable_version_range": "< 16.0.0", "first_patched_version": "16.0.0"}]}]}
}
EOF
    printf '%s' '{"components": {"npm:next": {"versions": ["15.5.2"], "files": ["frontend/pnpm-lock.yaml"], "partial": false}, "image:node": {"versions": ["24"], "files": ["compose.yaml"], "partial": true}}}' >"$CASE/inventory.json"
    printf '{}' >"$CASE/kev.json"
    run_match "$CASE/lookup.json" "$CASE/inventory.json" "$CASE/kev.json"
    check "$name2(範囲に入らない部品)" "$(mf CVE-2026-5002)" "npm:next|false|15.5.2|null"
    check "$name2(looked_up が偽の番号の、範囲に入る部品と鍵 *)" "$(mf CVE-2026-5003)" "*|null||null npm:next|true|15.5.2|16.0.0"
}

# 範囲を持たない Tomcat の製品と、範囲を持つ Tomcat の製品と、名前の合わない製品の CVE の記録の見本を置く
put_nvd_records() {
    printf '%s' '{"containers": {"cna": {"affected": [{"vendor": "Apache Software Foundation", "product": "Apache Tomcat", "versions": []}]}}}' >"$CASE/norange.json"
    printf '%s' '{"containers": {"cna": {"affected": [{"vendor": "Apache Software Foundation", "product": "Apache Tomcat", "versions": [{"version": "10.1.0", "lessThan": "10.1.20", "status": "affected"}]}]}}}' >"$CASE/range.json"
    printf '%s' '{"containers": {"cna": {"affected": [{"vendor": "Example", "product": "Other", "versions": [{"version": "1.0", "lessThan": "2.0", "status": "affected"}]}]}}}' >"$CASE/other.json"
    printf '%s' '{"components": {"maven:org.apache.tomcat.embed:tomcat-embed-core": {"versions": ["10.1.30"], "files": ["backend/build.gradle"], "partial": false}, "image:debian": {"versions": ["12"], "files": ["docker/backend/Dockerfile"], "partial": true}}}' >"$CASE/inventory.json"
    printf '{}' >"$CASE/kev.json"
}

# $CASE/out.json の lookup を $CASE/lookup.json に書く
save_lookup() {
    perl -MJSON::PP -e 'my $j = JSON::PP->new->utf8; local $/; my $d = $j->decode(<STDIN>); print $j->encode($d->{lookup})' <"$CASE/out.json" >"$CASE/lookup.json"
}

case_nvd() {
    newcase
    put_nvd_records
    # 6001 から 6006 は、範囲を当てられない Tomcat の部品がある番号。6007 は範囲を当てられる番号、6008 は名前の合う部品が無い番号。
    # 6007 と 6008 を先に引く順にし、NVD の要求の対象から外れることを確かめる
    local n cves=''
    for n in 1 2 3 4 5 6 7 8; do cves="$cves CVE-2026-600$n"; done
    for n in 1 2 3 4 5 6; do put_cve "CVE-2026-600$n" 200 "$CASE/norange.json" 200 "$CASE/empty.json"; done
    put_cve CVE-2026-6007 200 "$CASE/range.json" 200 "$CASE/empty.json"
    put_cve CVE-2026-6008 200 "$CASE/other.json" 200 "$CASE/empty.json"
    put "${NVD_URL}CVE-2026-6001" 200 "$FIX/test-ranges/nvd-CVE-2025-24813.json"
    export KP_VULN_WATCH_NVD_WAIT=0
    run_lookup "$cves" '{"CVE-2026-6007": 0, "CVE-2026-6008": 1}' 60 "$CASE/inventory.json" "$CASE/kev.json"
    local name="NVD への要求が、範囲の当て方の1から3のどれでも範囲を当てられなかった部品がある番号だけで行われ、5回で止まる"
    check "$name" \
        "$(requested "$NVD_URL");$(for n in 1 2 3 4 5 6 7 8; do printf '%s,' "$(requested "${NVD_URL}CVE-2026-600$n")"; done)" \
        "5;1,1,1,1,1,0,0,0,"
    check "$name(NVD への要求ごとに curl を1回呼ぶ)" \
        "$(grep -c '^CALL' "$CASE/curl.log")" "6"

    local name3="NVD の CPE の範囲が、aliases.json で部品の鍵に引ける CPE にだけ当たる。NVD の CPE だけに名前が出る製品は、どの部品にも合わない"
    check "$name3(NVD を引いた番号の nvd に、vulnerable が真の cpeMatch だけが入る)" \
        "$(out 'join " ", map { $_->{criteria} } @{ $d->{lookup}{"CVE-2026-6001"}{nvd} }');$(out 'scalar @{ $d->{lookup}{"CVE-2026-6002"}{nvd} }')" \
        "cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:* cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:* cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:* cpe:2.3:a:apache:tomcat:10.1.0:milestone1:*:*:*:*:*:* cpe:2.3:o:debian:debian_linux:11.0:*:*:*:*:*:*:* cpe:2.3:o:netapp:bootstrap_os:-:*:*:*:*:*:*:*;0"
    save_lookup
    run_match "$CASE/lookup.json" "$CASE/inventory.json" "$CASE/kev.json"
    check "$name3(Tomcat の部品に NVD の apache:tomcat の範囲が当たり、debian:debian_linux の CPE は image:debian に合わない)" \
        "$(ms CVE-2026-6001)" "maven:org.apache.tomcat.embed:tomcat-embed-core|true|nvd|-"
    check "$name3(NVD を引けなかった番号は、範囲が無いままになる)" \
        "$(ms CVE-2026-6002)" "maven:org.apache.tomcat.embed:tomcat-embed-core|null|-|no_range"

    newcase
    cat >"$CASE/lookup.json" <<'EOF'
{
  "CVE-2026-6101": {"looked_up": true, "products": [], "advisories": [], "nvd": [
    {"criteria": "cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*", "versionEndExcluding": "11.0.0"}]},
  "CVE-2026-6102": {"looked_up": true, "advisories": [],
    "products": [{"from": "cna", "vendor": "Apache Software Foundation", "product": "Apache Tomcat", "versions": []}],
    "nvd": [
      {"criteria": "cpe:2.3:a:apache:http_server:*:*:*:*:*:*:*:*", "versionEndExcluding": "99.0"},
      {"criteria": "cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*", "versionStartIncluding": "9.0.0", "versionEndExcluding": "10.1.0"}]}
}
EOF
    printf '%s' '{"components": {"maven:org.apache.tomcat.embed:tomcat-embed-core": {"versions": ["10.1.30"], "files": ["backend/build.gradle"], "partial": false}, "image:node": {"versions": ["20.11.0"], "files": ["compose.yaml"], "partial": false}}}' >"$CASE/inventory.json"
    printf '%s' '{"CVE-2026-6102": [["Nodejs", "Node"]]}' >"$CASE/kev.json"
    run_match "$CASE/lookup.json" "$CASE/inventory.json" "$CASE/kev.json"
    check "$name3(CPE だけに名前が出る製品は、どの部品にも合わない)" "$(ms CVE-2026-6101)" ""
    check "$name3(部品の鍵に引けない apache:http_server の CPE の範囲は当たらない)" \
        "$(ms CVE-2026-6102)" "image:node|null|-|no_range maven:org.apache.tomcat.embed:tomcat-embed-core|false|nvd|-"

    local name4="NVD の versionEndExcluding が直った版になり、versionEndIncluding だけを持つ範囲からは直った版が null になる"
    check "$name4(範囲の1つから決める)" \
        "$(rr 'join " ", map { F("nvd", $_) } (q({"criteria":"cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*","versionStartIncluding":"10.1.1","versionEndExcluding":"10.1.35"}), q({"criteria":"cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*","versionStartIncluding":"1.0","versionEndIncluding":"1.2"}), q({"criteria":"cpe:2.3:a:apache:tomcat:10.1.0:milestone1:*:*:*:*:*:*"}))')" \
        "10.1.35 null null"
    newcase
    put_nvd_records
    put_cve CVE-2026-6001 200 "$CASE/norange.json" 200 "$CASE/empty.json"
    put "${NVD_URL}CVE-2026-6001" 200 "$FIX/test-ranges/nvd-CVE-2025-24813.json"
    export KP_VULN_WATCH_NVD_WAIT=0
    run_lookup CVE-2026-6001 '{}' 60 "$CASE/inventory.json" "$CASE/kev.json"
    save_lookup
    run_match "$CASE/lookup.json" "$CASE/inventory.json" "$CASE/kev.json"
    check "$name4(NVD の範囲に入った部品の fixed)" \
        "$(mf CVE-2026-6001)" "maven:org.apache.tomcat.embed:tomcat-embed-core|true|10.1.30|10.1.35"
}

case_nvdwait() {
    newcase
    local name="KP_VULN_WATCH_NVD_WAIT が無いときの待つ秒数が 6 である"
    check "$name" "$(rr 'ranges_nvd_wait()')" "6"
    check "$name(数でない値のときも 6 にする)" "$(KP_VULN_WATCH_NVD_WAIT=abc rr 'ranges_nvd_wait()')" "6"
    check "$name(テストのときは替えられる)" "$(KP_VULN_WATCH_NVD_WAIT=0 rr 'ranges_nvd_wait()')" "0"

    put_nvd_records
    local n
    for n in 1 2 3; do put_cve "CVE-2026-600$n" 200 "$CASE/norange.json" 200 "$CASE/empty.json"; done
    export KP_VULN_WATCH_NVD_WAIT=1
    run_lookup "CVE-2026-6001 CVE-2026-6002 CVE-2026-6003" '{}' 60 "$CASE/inventory.json" "$CASE/kev.json"
    check "$name(NVD への要求の間を、待つ秒数だけ空ける)" \
        "$(requested "$NVD_URL");$(out '$d->{elapsed} >= 2 ? "waited" : "not waited: $d->{elapsed}"')" "3;waited"

    newcase
    put_nvd_records
    for n in 1 2; do put_cve "CVE-2026-600$n" 200 "$CASE/norange.json" 200 "$CASE/empty.json"; done
    export KP_VULN_WATCH_NVD_WAIT=5
    run_lookup "CVE-2026-6001 CVE-2026-6002" '{}' 3 "$CASE/inventory.json" "$CASE/kev.json"
    check "$name(待つと打ち切りの時刻を過ぎるときは、次の要求をしない)" \
        "$(requested "$NVD_URL");$(out '$d->{elapsed} < 3 ? "stopped" : "not stopped: $d->{elapsed}"')" "1;stopped"

    # GitHub の勧告の応答を打ち切りの時刻より遅らせる。CVE の記録は届き、範囲を当てられない部品が残る
    newcase
    put_nvd_records
    put_cve CVE-2026-6001 200 "$CASE/norange.json" 200 "$CASE/empty.json"
    export KP_VULN_WATCH_NVD_WAIT=0 KP_FAKE_CURL_DELAY="${GHSA_URL}CVE-2026-6001=4"
    run_lookup CVE-2026-6001 '{}' 2 "$CASE/inventory.json" "$CASE/kev.json"
    check "$name(打ち切りの時刻を過ぎたあとは、NVD を引かない)" \
        "$(requested "$NVD_URL");$(out 'scalar @{ $d->{lookup}{"CVE-2026-6001"}{products} }')" "0;1"
}

# ranges_match と ranges_refs を呼び、返した値を JSON で $CASE/out.json に書く
# run_refs <CVE の番号ごとの引いた値の JSON のファイル> <部品の一覧の JSON のファイル> <項目の JSON のファイル> [期限]
# 期限は今の時刻からの秒数で、渡したときだけ ranges_refs に期限の時刻を渡す
run_refs() {
    perl -MJSON::PP -e '
        require $ARGV[0];
        my $j = JSON::PP->new->utf8;
        my $read = sub { open my $h, "<", $_[0] or die "$_[0]: $!"; local $/; $j->decode(<$h>) };
        my $matches = ranges_match($read->($ARGV[2]), $read->($ARGV[3]), $read->($ARGV[1]), {});
        my @deadline = length $ARGV[5] ? (time + $ARGV[5]) : ();
        my ($refs, $ok) = ranges_refs($read->($ARGV[4]), $matches, @deadline);
        print $j->canonical->encode({ refs => $refs, refs_ok => ($ok ? JSON::PP::true : JSON::PP::false) });
    ' "$RANGES" "$ALIASES" "$1" "$2" "$3" "${4:-}" >"$CASE/out.json" 2>"$CASE/err.txt"
}

# 項目ごとの PR と Issue の番号を、項目の鍵の順に「鍵:pr701,issue801」の形で空白で区切り、最後に「;refs_ok」を付けて出す
refs_of() {
    out 'join(" ", map { my $k = $_; "$k:" . join(",", map { "$_->{kind}$_->{number}" } @{ $d->{refs}{$k} }) } sort keys %{ $d->{refs} }) . ";" . ($d->{refs_ok} ? "true" : "false")'
}

# 引いた値と部品の一覧と項目と、偽の gh の PR と Issue の一覧の見本を置き、ranges_refs を呼ぶ
put_refs() {
    # 7001 は next の範囲 15.0.0 以上 15.5.3 未満を持つ。7002 は、repository_advisory_url の無い勧告で react の名前だけが合い、
    # react に範囲を当てられない。7004 は repository_advisory_url の無い勧告の GHSA の番号だけを持つ
    cat >"$CASE/lookup.json" <<'EOF'
{
  "CVE-2026-7001": {"looked_up": true, "products": [], "advisories": [
    {"ghsa_id": "GHSA-aaaa-bbbb-cccc", "repository_advisory_url": "https://github.com/vercel/next.js/security/advisories/GHSA-aaaa-bbbb-cccc",
     "vulnerabilities": [{"ecosystem": "npm", "name": "next", "vulnerable_version_range": ">= 15.0.0, < 15.5.3", "first_patched_version": "15.5.3"}]}]},
  "CVE-2026-7002": {"looked_up": true, "products": [], "advisories": [
    {"ghsa_id": "GHSA-rrrr-ssss-tttt", "repository_advisory_url": null,
     "vulnerabilities": [{"ecosystem": "npm", "name": "react", "vulnerable_version_range": "< 19.0.1", "first_patched_version": "19.0.1"}]}]},
  "CVE-2026-7003": {"looked_up": true, "products": [], "advisories": []},
  "CVE-2026-7004": {"looked_up": true, "products": [], "advisories": [{"ghsa_id": "GHSA-dddd-eeee-ffff", "repository_advisory_url": null, "vulnerabilities": []}]}
}
EOF
    printf '%s' '{"components": {"npm:next": {"versions": ["15.5.2"], "files": ["frontend/pnpm-lock.yaml"], "partial": false}, "npm:react": {"versions": ["19.0.0"], "files": ["frontend/pnpm-lock.yaml"], "partial": false}}}' >"$CASE/inventory.json"
    cat >"$CASE/items.json" <<'EOF'
{
  "CVE-2026-7001": {"key": "CVE-2026-7001", "cves": ["CVE-2026-7001"]},
  "CVE-2026-7002": {"key": "CVE-2026-7002", "cves": ["CVE-2026-7002"]},
  "CVE-2026-7005": {"key": "CVE-2026-7005", "cves": ["CVE-2026-7005"]},
  "JVNDB-2026-000001": {"key": "JVNDB-2026-000001", "cves": ["CVE-2026-7003", "CVE-2026-7004"]}
}
EOF
    # 701 は範囲の外の版に上げる PR、702 は範囲の中の版に上げる PR、703 は本文に CVE の番号を持つ PR、
    # 704 は番号の続きに数字のある番号を持つ PR、705 は本文の Updates の行で範囲の外の版に上げる PR、
    # 706 は題名に GHSA の番号を持つ PR、708 は、7001 では名前の合わない部品を、7002 では範囲を当てられない部品を上げる PR、
    # 709 は、範囲と比べられない版(コミットの番号の形)に上げる PR
    cat >"$CASE/gh/pr-list.json" <<'EOF'
[
  {"number": 701, "title": "chore: Bump next from 15.5.2 to 15.5.3 in /frontend", "body": "Bumps [next](https://github.com/vercel/next.js) from 15.5.2 to 15.5.3."},
  {"number": 702, "title": "Bump next from 15.4.0 to 15.5.1 in /frontend", "body": "Bumps [next](https://github.com/vercel/next.js) from 15.4.0 to 15.5.1."},
  {"number": 703, "title": "Bump org.apache.tomcat.embed:tomcat-embed-core in /backend", "body": "Fixes CVE-2026-7002."},
  {"number": 704, "title": "Bump example in /backend", "body": "Fixes CVE-2026-70010."},
  {"number": 705, "title": "Bump the npm-minor group across 1 directory with 2 updates", "body": "Updates `react` from 19.0.0 to 19.1.0\nUpdates `next` from 15.5.2 to 15.6.0\n"},
  {"number": 706, "title": "Fix GHSA-aaaa-bbbb-cccc", "body": ""},
  {"number": 708, "title": "Bump react from 19.0.0 to 19.1.0 in /frontend", "body": null},
  {"number": 709, "title": "chore: Bump next from `eee6c6e` to `266d3c2` in /frontend", "body": "Bumps next from `eee6c6e` to `266d3c2`."}
]
EOF
    cat >"$CASE/gh/issue-list.json" <<'EOF'
[
  {"number": 801, "title": "コンテナ脆弱性: CVE-2026-7003"},
  {"number": 802, "title": "コンテナ脆弱性: CVE-2026-70030"},
  {"number": 803, "title": "コンテナ脆弱性: GHSA-dddd-eeee-ffff"}
]
EOF
    run_refs "$CASE/lookup.json" "$CASE/inventory.json" "$CASE/items.json" "${KP_TEST_REFS_DEADLINE:-}"
}

case_refs() {
    newcase
    put_refs
    local name="CVE の番号を本文に持つ PR と、範囲の外の版に上げる PR と、題名の ID が合うコンテナの脆弱性の Issue が選ばれ、範囲の中の版に上げる PR が選ばれない。gh の一覧を失敗させると refs_ok が偽になる"
    check "$name" "$(refs_of)" \
        "CVE-2026-7001:pr701,pr705,pr706 CVE-2026-7002:pr703 CVE-2026-7005: JVNDB-2026-000001:issue801,issue803;true"
    check "$name(標準エラーに何も出さない)" "$(cat "$CASE/err.txt")" ""
    check "$name(PR と Issue の一覧を、決めた引数で1回ずつ呼ぶ)" "$(cat "$CASE/gh.log")" \
        "pr list --state open --author app/dependabot --json number,title,body --limit 100
issue list --state open --label container-vuln --json number,title --limit 200"
    local fail
    for fail in pr-list issue-list; do
        newcase
        export KP_FAKE_GH_FAIL=$fail
        put_refs
        check "$name($fail を失敗させると、どの項目の refs も空になる)" "$(refs_of)" \
            "CVE-2026-7001: CVE-2026-7002: CVE-2026-7005: JVNDB-2026-000001:;false"
    done
    unset KP_FAKE_GH_FAIL
    newcase
    KP_TEST_REFS_DEADLINE=60 put_refs
    check "$name(collect の期限まで時間が残っていれば、期限を渡さないときと同じ PR と Issue を選ぶ)" "$(refs_of)" \
        "CVE-2026-7001:pr701,pr705,pr706 CVE-2026-7002:pr703 CVE-2026-7005: JVNDB-2026-000001:issue801,issue803;true"
    newcase
    KP_TEST_REFS_DEADLINE=-1 put_refs
    check "$name(collect の期限を過ぎていると、gh を呼ばずに、どの項目の refs も空にして refs_ok を偽にする)" \
        "$(refs_of);$(cat "$CASE/gh.log" 2>/dev/null)" \
        "CVE-2026-7001: CVE-2026-7002: CVE-2026-7005: JVNDB-2026-000001:;false;"
}

CASES='compare forms uncomparable partial lookup token limit failures deadline aliases match sources undecided notlooked fixed nvd nvdwait refs'

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
