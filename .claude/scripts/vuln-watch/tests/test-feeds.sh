#!/bin/bash
# shellcheck disable=SC2016 # $d や $i などは pj と item_with に渡す perl の式の変数で、シェルの変数ではない
# =====================================================================
# 4つの出どころを取り、直近7日の項目に直すモジュール(feeds.pl)のテスト
#
# 実行: bash .claude/scripts/vuln-watch/tests/test-feeds.sh
# テストの場合ごとに、一時フォルダに、偽の curl と偽の gh を curl と gh の名前で写して PATH の先頭に置き、
# 出どころの見本(fixtures/test-feeds/)を偽の curl の見本の名前で置き、HOME を空の一時フォルダに替える。
# 今の時刻は KP_VULN_WATCH_TEST_NOW で 2026-11-04T12:00:00Z に決める。本物のネットワークには出ない。
# 前提: bash・perl(JSON::PP・Time::Local)
#
# 場合を選んで流す: KP_TEST_CASE='window_kev_ipa jpcert_503' bash .claude/scripts/vuln-watch/tests/test-feeds.sh
# 空白で区切った名前の場合だけを流す。どの場合にも合わない名前があれば、何も流さずに終了コード 2 で終わる
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
FEEDS="$(cd "$HERE/.." && pwd)/feeds.pl"
FIX="$HERE/fixtures"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd -P; })

export KP_VULN_WATCH_TEST_NOW=2026-11-04T12:00:00Z

KEV_URL=https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json
JPCERT_URL=https://www.jpcert.or.jp/rss/jpcert.rdf
IPA_URL=https://www.ipa.go.jp/security/alert-rss.rdf
CVEMON_URL=https://cvemon.intruder.io/rss/cvetrends/latest

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }

# URL の英数字でない文字を _ に替えた、偽の curl の見本の名前を出す
sample() { printf '%s/%s' "$KP_FAKE_CURL_DIR" "$(printf '%s' "$1" | perl -pe 's/[^A-Za-z0-9]/_/g')"; }

# 偽の curl の見本を置く: put <URL> <状態> <本文のファイル>
put() {
    printf '%s' "$2" >"$(sample "$1").status"
    cp "$3" "$(sample "$1").body"
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

# feeds_collect を呼び、返した値を JSON で $CASE/out.json に書く
run_feeds() {
    (cd "$CASE/work" && perl -MJSON::PP -MTime::Local=timegm -e '
        require $ARGV[0];
        my ($y, $mo, $d, $h, $mi, $s) = $ENV{KP_VULN_WATCH_TEST_NOW} =~ /\A(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)Z\z/ or die "bad now";
        my $now = timegm($s, $mi, $h, $d, $mo - 1, $y);
        my $r = feeds_collect($now, $ARGV[1]);
        print JSON::PP->new->utf8->canonical->encode($r);
    ' "$FEEDS" "$CASE/work" >"$CASE/out.json" 2>"$CASE/err.txt")
}

out() { pj "$1" <"$CASE/out.json"; }

# 場合ごとの一時フォルダを作り、偽の curl と偽の gh と、4つの出どころの見本を置く
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
    put "$KEV_URL" 200 "$FIX/test-feeds/kev.json"
    put "$JPCERT_URL" 200 "$FIX/test-feeds/jpcert.rdf"
    put "$IPA_URL" 200 "$FIX/test-feeds/ipa.rdf"
    put "$CVEMON_URL" 200 "$FIX/test-feeds/cvemon.xml"
    # 記事のページ。at260034 は状態 503 で返し、記事のページを取れなかった項目にする
    put https://www.jpcert.or.jp/at/2026/at260033.html 200 "$FIX/test-feeds/article-jpcert-at260033.html"
    put https://www.jpcert.or.jp/at/2026/at260034.html 503 "$FIX/test-feeds/article-jpcert-at260034.html"
    put https://www.jpcert.or.jp/at/2026/at260035.html 200 "$FIX/test-feeds/article-jpcert-at260035.html"
    put https://www.ipa.go.jp/security/security-alert/2026/alert20261022.html 200 "$FIX/test-feeds/article-ipa-alert20261022.html"
    put https://www.ipa.go.jp/security/security-alert/2026/1021-jre.html 200 "$FIX/test-feeds/article-ipa-1021-jre.html"
}
ORIG_PATH=$PATH

# 出どころ <source> の id が <id> の出どころを持つ項目を $i に置いて、続く式を評価する式を作る: item_with <source> <id> '<式>'
item_with() {
    printf 'my ($i) = grep { grep { $_->{source} eq "%s" && $_->{id} eq "%s" } @{ $_->{sources} } } @{ $d->{items} }; defined $i ? do { %s } : "<no item>"' "$1" "$2" "$3"
}
# $i の key と、出どころの一覧を「<出どころ>=<id>」の形で並べ替えて出す式
KEY_SOURCES='join " ", $i->{key}, sort map { "$_->{source}=$_->{id}" } @{ $i->{sources} }'

CASES=''
addcase() { CASES="$CASES $1"; }

# ---------------------------------------------------------------------
# 要件1の受入基準1: 4つの出どころから集め、cvemon からは話題の一覧に載った脆弱性だけを集める
# ---------------------------------------------------------------------
case_filters() {
    run_feeds
    check "JPCERT/CC の /wr/ の項目が集まらない" \
        "$(out 'scalar grep { $_->{url} =~ m{/wr/} } map { @{ $_->{sources} } } @{ $d->{items} }')" "0"
    check "cvemon の題名が CVE の番号でない項目が集まらない" \
        "$(out 'scalar grep { $_->{source} eq "cvemon" && $_->{title} !~ /\ACVE-\d{4}-\d{4,}\z/ } map { @{ $_->{sources} } } @{ $d->{items} }')" "0"
    check "4つの出どころの項目が集まる" \
        "$(out 'my %s = map { $_->{source} => 1 } map { @{ $_->{sources} } } @{ $d->{items} }; join " ", sort keys %s')" \
        "cvemon ipa jpcert kev"
    check "取れなかった出どころが無い" "$(out 'scalar @{ $d->{failed} }')" "0"
}
addcase filters

# ---------------------------------------------------------------------
# 要件1の受入基準2: 直近7日の情報を集める
# ---------------------------------------------------------------------
case_window_kev_ipa() {
    run_feeds
    check "KEV は7日前の日付の項目と6日前の項目が集まり、8日前の項目が集まらない" \
        "$(out 'join " ", sort map { $_->{id} } grep { $_->{source} eq "kev" } map { @{ $_->{sources} } } @{ $d->{items} }')" \
        "CVE-2026-111497 CVE-2026-119977 CVE-2026-120010 CVE-2026-76418"
    check "IPA は7日前の日付の項目と6日前の項目が集まり、8日前の項目が集まらない" \
        "$(out 'join " ", sort map { $_->{url} } grep { $_->{source} eq "ipa" } map { @{ $_->{sources} } } @{ $d->{items} }')" \
        "https://example.com/security/alert-20261101.html https://www.ipa.go.jp/security/security-alert/2026/1021-jre.html https://www.ipa.go.jp/security/security-alert/2026/alert20261022.html"
}
addcase window_kev_ipa

case_window_jpcert() {
    run_feeds
    check "JPCERT/CC は7日前の時刻より1分新しい項目が集まり、1分古い項目が集まらない" \
        "$(out 'join " ", sort map { $_->{id} } grep { $_->{source} eq "jpcert" } map { @{ $_->{sources} } } @{ $d->{items} }')" \
        "at260033 at260034 at260035"
}
addcase window_jpcert

# ---------------------------------------------------------------------
# 要件1の受入基準3: cvemon からはスキルを打った時点の話題の一覧を集める
# ---------------------------------------------------------------------
case_cvemon_all() {
    run_feeds
    check "cvemon は日付によらず全件が集まる" \
        "$(out 'join " ", map { "$_->{id}:$_->{rank}" } sort { $a->{rank} <=> $b->{rank} } grep { $_->{source} eq "cvemon" } map { @{ $_->{sources} } } @{ $d->{items} }')" \
        "CVE-2024-27834:1 CVE-2024-10441:3 CVE-2026-111497:4"
}
addcase cvemon_all

# ---------------------------------------------------------------------
# 要件1の受入基準4: 取れなかった出どころがあっても、ほかの出どころの情報を示す
# ---------------------------------------------------------------------
case_jpcert_503() {
    put "$JPCERT_URL" 503 "$FIX/test-feeds/jpcert.rdf"
    run_feeds
    check "JPCERT/CC の応答を 503 にすると、ほかの3つの出どころの項目が返る" \
        "$(out 'my %s = map { $_->{source} => 1 } map { @{ $_->{sources} } } @{ $d->{items} }; join " ", sort keys %s')" \
        "cvemon ipa kev"
    check "JPCERT/CC が failed に入る" \
        "$(out 'join " ", map { "$_->{source}|$_->{name}|$_->{error}" } @{ $d->{failed} }')" \
        "jpcert|JPCERT/CC の注意喚起|HTTP 503"
}
addcase jpcert_503

case_kev_timeout() {
    export KP_FAKE_CURL_DELAY="$KEV_URL=60"
    start=$(date +%s)
    run_feeds
    elapsed=$(($(date +%s) - start))
    check "KEV の応答を60秒遅らせると、feeds.pl が40秒で打ち切る" \
        "$([ "$elapsed" -ge 38 ] && [ "$elapsed" -le 50 ] && echo in-time || echo "elapsed=$elapsed")" "in-time"
    check "KEV が failed に入る" "$(out 'join " ", map { $_->{source} } @{ $d->{failed} }')" "kev"
    check "ほかの3つの出どころの項目が返る" \
        "$(out 'my %s = map { $_->{source} => 1 } map { @{ $_->{sources} } } @{ $d->{items} }; join " ", sort keys %s')" \
        "cvemon ipa jpcert"
}
addcase kev_timeout

# ---------------------------------------------------------------------
# 要件4の受入基準5: 同じ脆弱性を1回だけ示す(JPCERT/CC の更新した記事)
# ---------------------------------------------------------------------
case_jpcert_update() {
    run_feeds
    check "JPCERT/CC の同じ URL の「(更新)」の付いた項目と元の項目が、新しい項目の1つになる" \
        "$(out 'join "\n", map { "$_->{published} $_->{title}" } grep { $_->{source} eq "jpcert" && $_->{id} eq "at260033" } map { @{ $_->{sources} } } @{ $d->{items} }')" \
        "2026-10-30T15:43+09:00 注意喚起: PHPにおける複数の脆弱性（CVE-2026-109618、CVE-2026-109619）に関する注意喚起  (更新)"
}
addcase jpcert_update

# ---------------------------------------------------------------------
# 要件4の受入基準3: 悪用が確かめられているかを書くための KEV の本文
# ---------------------------------------------------------------------
case_kev_body() {
    run_feeds
    check "feeds.pl が返す kev が、20日前に KEV に載った項目も持つ" \
        "$(out 'join " ", map { "$_->{cveID}=$_->{dateAdded}" } grep { $_->{cveID} eq "CVE-2016-3427" } @{ $d->{kev}{vulnerabilities} }')" \
        "CVE-2016-3427=2026-10-15"
}
addcase kev_body

# ---------------------------------------------------------------------
# 要件4の受入基準5: 同じ脆弱性を1回だけ示す(CVE の番号を共有する項目をまとめる)
# ---------------------------------------------------------------------
case_merge_three() {
    run_feeds
    check "KEV と JPCERT/CC と cvemon に同じ CVE の番号が載ると、3つの出どころを持つ1つの項目になる" \
        "$(out "$(item_with kev CVE-2026-111497 "$KEY_SOURCES")")" \
        "CVE-2026-111497 cvemon=CVE-2026-111497 jpcert=at260034 kev=CVE-2026-111497"
    check "CVE-2026-111497 を持つ項目が1つだけある" \
        "$(out 'scalar grep { grep { $_ eq "CVE-2026-111497" } @{ $_->{cves} } } @{ $d->{items} }')" "1"
}
addcase merge_three

case_merge_chain() {
    run_feeds
    check "A と B が番号を共有し、B と C が別の番号を共有すると、3つが1つの項目になる" \
        "$(out "$(item_with jpcert at260035 "$KEY_SOURCES")")" \
        "CVE-2026-120010 ipa=https://www.ipa.go.jp/security/security-alert/2026/1021-jre.html jpcert=at260035 kev=CVE-2026-120010"
    check "まとめた項目が、3つの項目の CVE の番号を、番号の大きい順に持つ" \
        "$(out "$(item_with jpcert at260035 'join " ", @{ $i->{cves} }')")" \
        "CVE-2026-130003 CVE-2026-130002 CVE-2026-130001 CVE-2026-120010"
    check "KEV の説明が、まとめた項目に残る" \
        "$(out "$(item_with jpcert at260035 'join " ", sort keys %{ $i->{descriptions} }')")" "CVE-2026-120010"
}
addcase merge_chain

case_article_cves() {
    run_feeds
    check "記事の HTML から、題名で「等」と省かれた番号も拾われる" \
        "$(out "$(item_with jpcert at260035 'join " ", grep { /CVE-2026-13000[23]/ } @{ $i->{cves} }')")" \
        "CVE-2026-130003 CVE-2026-130002"
    check "記事のページを取れなかった項目は、題名の番号だけを持ち、article_ok が偽になる" \
        "$(out "$(item_with jpcert at260034 'join(" ", @{ $i->{cves} }) . " " . ($i->{article_ok} ? "true" : "false")')")" \
        "CVE-2026-111497 false"
    check "記事のページを取れた項目は、article_ok が真になる" \
        "$(out "$(item_with jpcert at260035 '$i->{article_ok} ? "true" : "false"')")" "true"
    check "記事の本文は、HTML のタグを外して記事ごとに2,500文字まで持つ" \
        "$(out "$(item_with jpcert at260035 'my @t = split /\n\n/, $i->{article_text}; join "|", scalar @t, length $t[0], ($t[0] =~ /<p>|<li>|<h1>|var shown|color: red/ ? "tag" : "no-tag"), substr($t[0], 0, 49), ($t[0] =~ /(\S+ & \S+)/ ? $1 : "<none>"), $t[1]')")" \
        "2|2500|no-tag|Apache Tomcatにおける複数の脆弱性（CVE-2026-130001等）に関する注意喚起|<影響> & 対策|Oracle Java の脆弱性対策について(2026年10月) Oracle Java SE には、CVE-2026-120010 と CVE-2026-130003 の脆弱性があります。"
    check "ほかのサイトの URL を持つ項目は、記事のページを取らず、題名の番号だけを持つ" \
        "$(out "$(item_with ipa https://example.com/security/alert-20261101.html 'join(" ", @{ $i->{cves} }) . " " . ($i->{article_ok} ? "true" : "false")')")" \
        "CVE-2026-140001 false"
}
addcase article_cves

# 偽の curl の記録が、ほかのサイトの URL を持たない
case_no_other_site() {
    run_feeds
    check "偽の curl の記録が、ほかのサイトの URL を持たない" \
        "$(grep '^ARG http' "$CASE/curl.log" | grep -cv '^ARG https://www\.\(cisa\.gov\|jpcert\.or\.jp\|ipa\.go\.jp\)/\|^ARG https://cvemon\.intruder\.io/')" "0"
    check "2回目の curl の呼び出しが、直近7日の JPCERT/CC と IPA の記事のページを取る" \
        "$(awk '/^CALL$/ { n++ } n == 2 && /^ARG https?:/ { print $2 }' "$CASE/curl.log" | sort | tr '\n' ' ')" \
        "https://www.ipa.go.jp/security/security-alert/2026/1021-jre.html https://www.ipa.go.jp/security/security-alert/2026/alert20261022.html https://www.jpcert.or.jp/at/2026/at260033.html https://www.jpcert.or.jp/at/2026/at260034.html https://www.jpcert.or.jp/at/2026/at260035.html "
    check "2回目の curl の呼び出しが、記事のページごとに15秒で打ち切る" \
        "$(awk '/^CALL$/ { n++ } n == 2 && prev == "ARG --max-time" { print $2 } { prev = $0 }' "$CASE/curl.log" | sort -u | tr '\n' ' ')" "15 "
}
addcase no_other_site

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
    newcase
    "case_$name"
done

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
