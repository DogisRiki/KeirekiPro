#!/bin/bash
# shellcheck disable=SC2016 # $d や $e や $_ などは pj に渡す perl の式の変数で、シェルの変数ではない
# =====================================================================
# 入口のスクリプト(vuln-watch.pl)の結合テスト
#
# 実行: bash .claude/scripts/vuln-watch/tests/test-vuln-watch.sh
# テストの場合ごとに、一時フォルダに、偽の curl と偽の gh を置いて PATH の先頭にし、origin にする裸のリポジトリと、
# それを origin に持つ git のリポジトリを作り、部品の見本(fixtures/test-vuln-watch/repo/)を main に置く。
# HOME を空の一時フォルダに替え、git のシステムの設定を読ませない。今の時刻は KP_VULN_WATCH_TEST_NOW で決める。
# 本物のネットワークと GitHub には出ない。
# 前提: bash・perl(JSON::PP)・git
#
# 場合を選んで流す: KP_TEST_CASE='verdicts failures' bash .claude/scripts/vuln-watch/tests/test-vuln-watch.sh
# 空白で区切った名前の場合だけを流す。どの場合にも合わない名前があれば、何も流さずに終了コード 2 で終わる
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
VW="$(cd "$HERE/.." && pwd)/vuln-watch.pl"
FIX="$HERE/fixtures"
VFIX="$FIX/test-vuln-watch"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd -P; })

export KP_VULN_WATCH_TEST_NOW=2026-11-04T12:00:00Z
# NVD への要求の間に待つ秒数を 0 にする。見本に NVD の応答は無く、待つとテストが遅くなるだけである
export KP_VULN_WATCH_NVD_WAIT=0
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

KEV_URL=https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json
JPCERT_URL=https://www.jpcert.or.jp/rss/jpcert.rdf
IPA_URL=https://www.ipa.go.jp/security/alert-rss.rdf
CVEMON_URL=https://cvemon.intruder.io/rss/cvetrends/latest
CVE_URL=https://cveawg.mitre.org/api/cve/
GHSA_URL='https://api.github.com/advisories?cve_id='

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }

# 標準入力の JSON を $d に読み、perl の式を評価した値を出す: pj '<式>'
pj() {
    perl -MJSON::PP -e '
        my $d = JSON::PP->new->utf8->decode(do { local $/; <STDIN> });
        binmode STDOUT, ":encoding(UTF-8)";
        # 式の中の日本語を文字として読むため、式を UTF-8 として解く
        my $src = $ARGV[0];
        utf8::decode($src);
        my $v = eval $src;
        die $@ if $@;
        print defined $v ? $v : "<undef>";
    ' "$1"
}

# URL の英数字でない文字を _ に替えた、偽の curl の見本の名前を出す
sample() { printf '%s/%s' "$KP_FAKE_CURL_DIR" "$(printf '%s' "$1" | perl -pe 's/[^A-Za-z0-9]/_/g')"; }

# 偽の curl の見本を置く: put <URL> <状態> <本文のファイル>
put() {
    printf '%s' "$2" >"$(sample "$1").status"
    cp "$3" "$(sample "$1").body"
}

# git を静かに動かす: g <リポジトリ> <引数...>
g() { git -C "$@" >/dev/null 2>&1 || { echo "git の準備に失敗した: $*" >&2; exit 2; }; }

# 場合ごとの一時フォルダを作り、偽の curl と偽の gh と見本を置き、origin にする裸のリポジトリと、それを origin に持つリポジトリを作る
ORIG_PATH=$PATH
CASE_NO=0
newcase() {
    CASE_NO=$((CASE_NO + 1))
    CASE="$WORK/c$CASE_NO"
    mkdir -p "$CASE/bin" "$CASE/curl" "$CASE/gh" "$CASE/home"
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
    put "$KEV_URL" 200 "$VFIX/kev.json"
    put "$JPCERT_URL" 200 "$VFIX/jpcert.rdf"
    put "$IPA_URL" 200 "$VFIX/ipa.rdf"
    put "$CVEMON_URL" 200 "$VFIX/cvemon.xml"
    # 記事のページ。at260102 は状態 503 で返し、記事のページを取れなかった項目にする
    put https://www.jpcert.or.jp/at/2026/at260101.html 200 "$VFIX/article-jpcert-at260101.html"
    put https://www.jpcert.or.jp/at/2026/at260102.html 503 "$VFIX/article-jpcert-at260102.html"
    put https://www.ipa.go.jp/security/security-alert/2026/1101-cms.html 200 "$VFIX/article-ipa-1101-cms.html"
    put https://www.ipa.go.jp/security/security-alert/2026/1102-glibc.html 200 "$VFIX/article-ipa-1102-glibc.html"
    local f cve
    for f in "$VFIX/records/"cve-*.json; do
        cve=${f##*/cve-}
        put "$CVE_URL${cve%.json}" 200 "$f"
    done
    for f in "$VFIX/records/"ghsa-*.json; do
        cve=${f##*/ghsa-}
        put "$GHSA_URL${cve%.json}" 200 "$f"
    done
    printf 'gho_testtoken\n' >"$CASE/gh/auth-token.out"
    cp "$VFIX/sbom.json" "$VFIX/pr-list.json" "$VFIX/issue-list.json" "$CASE/gh/"
    git init -q --bare -b main "$CASE/origin.git" || exit 2
    git init -q -b main "$CASE/repo" || exit 2
    mkdir -p "$CASE/repo/frontend" "$CASE/repo/docker/app"
    cp "$VFIX/repo/pnpm-lock.yaml" "$VFIX/repo/package.json" "$CASE/repo/frontend/"
    cp "$VFIX/repo/compose.yaml" "$CASE/repo/"
    # 見本の Dockerfile は、Dockerfile で始まらない名前で置き、写すときに Dockerfile の名前に戻す。
    # このリポジトリの main を読むときに、見本の FROM が本物のイメージとして読まれないようにするためである
    cp "$VFIX/repo/app.dockerfile" "$CASE/repo/docker/app/Dockerfile"
    g "$CASE/repo" add -A
    g "$CASE/repo" commit -q -m fixture
    g "$CASE/repo" remote add origin "$CASE/origin.git"
    g "$CASE/repo" push -q origin main
    g "$CASE/repo" fetch -q origin
}

# リポジトリのフォルダで collect を呼ぶ。標準出力を $CASE/out.json に、標準エラーを $CASE/err.txt に、終了コードを $CASE/rc に書く
collect() {
    (cd "$CASE/repo" && perl "$VW" collect >"$CASE/out.json" 2>"$CASE/err.txt"; echo $? >"$CASE/rc")
}

out() { pj "$1" <"$CASE/out.json"; }
# collect が出した材料の material.json を読む
mat() { pj "$1" <"$(out '$d->{material}')"; }
# collect が出した項目のファイルを読む。項目の鍵ごとの項目を %e に置いて式を評価する
ent() {
    local part
    part=$(out '$d->{parts}[0]')
    pj 'my %e = map { $_->{key} => $_ } @{ $d->{entries} }; '"$1" <"$part"
}
# 鍵ごとの「鍵=判定の案」を、鍵の順に並べる式
SUGGESTED='join " ", map { "$_=$e{$_}{suggested}" } sort keys %e'

CASES=''
addcase() { CASES="$CASES $1"; }

# ---------------------------------------------------------------------
# 要件2の受入基準2・3・4: 判定の案と、扱っている PR と Issue
# ---------------------------------------------------------------------
case_verdicts() {
    newcase
    collect
    local name="部品の版が範囲に入る項目が affected、範囲が無い項目が undeterminable、コンテナの脆弱性の Issue がある項目が affected、名前の合わない項目が unrelated、article_ok が偽の項目が undeterminable で入り、扱っている PR と Issue の番号が入る"
    check "$name(collect が 0 で終わる)" "$(cat "$CASE/rc")" "0"
    check "$name(標準エラーに何も出さない)" "$(cat "$CASE/err.txt")" ""
    check "$name(判定の案)" "$(ent 'my @k = qw(CVE-2026-2001 CVE-2026-2002 CVE-2026-2030 CVE-2026-2020 CVE-2026-2011); join " ", map { "$_=$e{$_}{suggested}" } @k')" \
        "CVE-2026-2001=affected CVE-2026-2002=undeterminable CVE-2026-2030=affected CVE-2026-2020=unrelated CVE-2026-2011=undeterminable"
    check "$name(範囲に入る部品)" "$(ent 'join " ", map { "$_->{key}=" . ($_->{in_range} ? "true" : "false") . "/$_->{range_source}" } @{ $e{"CVE-2026-2001"}{matches} }')" \
        "npm:next=true/github"
    check "$name(範囲が無い部品)" "$(ent 'join " ", map { "$_->{key}=" . ($_->{reason} // "") } @{ $e{"CVE-2026-2002"}{matches} }')" \
        "image:postgres=no_range"
    check "$name(名前の合わない項目と、コンテナの脆弱性の Issue だけがある項目は、部品を持たない)" \
        "$(ent 'join " ", map { scalar @{ $e{$_}{matches} } } qw(CVE-2026-2020 CVE-2026-2030 CVE-2026-2011)')" "0 0 0"
    check "$name(記事のページを取れなかった項目)" "$(ent '$e{"CVE-2026-2011"}{article_ok} ? "true" : "false"')" "false"
    check "$name(扱っている PR と Issue の番号)" \
        "$(ent 'join " ", map { my $k = $_; "$k:" . join(",", map { "$_->{kind}$_->{number}" } @{ $e{$k}{refs} }) } sort keys %e')" \
        "CVE-2026-2001:pr731 CVE-2026-2002: CVE-2026-2010: CVE-2026-2011: CVE-2026-2020: CVE-2026-2030:issue801 CVE-2026-2040: CVE-2026-2041:"
    check "$name(材料の github)" "$(mat 'join " ", map { "$_=" . ($d->{github}{$_} ? "true" : "false") } sort keys %{ $d->{github} }')" \
        "advisories_ok=true refs_ok=true sbom_ok=true"

    name="collect が標準出力に、run と material と parts と result と entries を持つ JSON の1行を出す"
    check "$name(行の数)" "$(wc -l <"$CASE/out.json" | tr -d ' ')" "1"
    check "$name(欄)" "$(out 'join " ", sort keys %$d')" "entries material parts result run"
    check "$name(実行の ID の形)" "$(out '$d->{run} =~ /\A20261104T120000Z-\d+\z/ ? "ok" : $d->{run}')" "ok"
    local dir
    dir="$CASE/repo/.claude/.state/vuln-watch/$(out '$d->{run}')"
    check "$name(場所)" "$(out 'join " ", $d->{material}, @{ $d->{parts} }, $d->{result}')" \
        "$dir/material.json $dir/entries-1.json $dir/result.json"
    check "$name(項目の数)" "$(out '$d->{entries}')" "8"
    check "$name(材料の parts が、出した場所と同じ)" "$(mat 'join " ", @{ $d->{parts} }')" "$(out '$d->{parts}[0]')"
    check "$name(作業の場所を残さない)" "$(ls "$CASE/repo/.claude/.state/vuln-watch/$(out '$d->{run}')" | tr '\n' ' ')" "entries-1.json material.json "
}
addcase verdicts

case_not_affected() {
    newcase
    collect
    local name="すべての in_range が偽の部品だけを持つ項目が not_affected で入り、in_range が偽の部品と null の部品を持つ項目が undeterminable で入る"
    check "$name(判定の案)" "$(ent 'join " ", map { "$_=$e{$_}{suggested}" } qw(CVE-2026-2040 CVE-2026-2041)')" \
        "CVE-2026-2040=not_affected CVE-2026-2041=undeterminable"
    check "$name(部品)" \
        "$(ent 'join " ", map { my $k = $_; map { "$k:$_->{key}=" . (defined $_->{in_range} ? ($_->{in_range} ? "true" : "false") : "null") } @{ $e{$k}{matches} } } qw(CVE-2026-2040 CVE-2026-2041)')" \
        "CVE-2026-2040:npm:react=false CVE-2026-2041:npm:react=false CVE-2026-2041:image:debian=null"
}
addcase not_affected

case_kev_names() {
    newcase
    collect
    local name="20日前に KEV に載った CVE の番号を持つ JPCERT/CC の直近7日の項目で、KEV の本文の vendorProject の Oracle と product の Java SE が %kev_names に入り、image:eclipse-temurin が matches に入る"
    check "$name(KEV の項目にならない)" "$(ent 'join " ", map { $_->{source} } @{ $e{"CVE-2026-2010"}{sources} }')" "jpcert"
    check "$name(部品)" "$(ent 'join " ", map { $_->{key} } @{ $e{"CVE-2026-2010"}{matches} }')" "image:eclipse-temurin"
    check "$name(判定の案)" "$(ent '$e{"CVE-2026-2010"}{suggested}')" "undeterminable"
}
addcase kev_names

case_products() {
    newcase
    collect
    local name="材料の項目が、feeds.pl の descriptions と article_text と、製品の名前と範囲を持つ products を持つ"
    check "$name(CVE の記録の説明)" "$(ent '$e{"CVE-2026-2001"}{descriptions}{"CVE-2026-2001"}')" "Next.js before 15.5.3 allows authorization bypass."
    check "$name(記事の本文)" "$(ent '$e{"CVE-2026-2010"}{article_text} =~ /Oracle Java SE の脆弱性/ ? "ok" : $e{"CVE-2026-2010"}{article_text} // "<undef>"')" "ok"
    check "$name(製品)" \
        "$(ent 'join " ", map { "$_->{from}:$_->{vendor}:$_->{product}:" . scalar @{ $_->{ranges} } } @{ $e{"CVE-2026-2001"}{products} }')" \
        "cna:vercel:next.js:1 github:npm:next:1"
    check "$name(GitHub の勧告の範囲)" "$(ent 'my $r = $e{"CVE-2026-2001"}{products}[1]{ranges}[0]; "$r->{vulnerable_version_range}/$r->{first_patched_version}"')" \
        ">= 15.0.0, < 15.5.3/15.5.3"
}
addcase products

case_two_cves() {
    newcase
    # この場合だけ、IPA の一覧に、CVE の番号を2つ持つ React の項目を足す。2つの番号は、どちらも npm:react の同じ範囲を持つ
    local f="$CASE/ipa.rdf" n
    perl -pe 's{ </rdf:RDF>}{}; s{^</rdf:RDF>}{ <item rdf:about="https://www.ipa.go.jp/security/security-alert/2026/1103-react.html">\n  <title>React の脆弱性対策について(CVE-2026-2050、CVE-2026-2051)</title>\n  <link>https://www.ipa.go.jp/security/security-alert/2026/1103-react.html</link>\n  <dc:date>2026-11-03T00:00:00+09:00</dc:date>\n </item>\n</rdf:RDF>}' "$VFIX/ipa.rdf" >"$f"
    put "$IPA_URL" 200 "$f"
    printf '<html><body><p>React の脆弱性(CVE-2026-2050、CVE-2026-2051)</p></body></html>\n' >"$CASE/article-1103.html"
    put https://www.ipa.go.jp/security/security-alert/2026/1103-react.html 200 "$CASE/article-1103.html"
    for n in 2050 2051; do
        perl -pe "s/CVE-2026-2040/CVE-2026-$n/g; s/GHSA-aaaa-2040-reac/GHSA-aaaa-$n-reac/g" "$VFIX/records/cve-CVE-2026-2040.json" >"$CASE/cve-$n.json"
        perl -pe "s/CVE-2026-2040/CVE-2026-$n/g; s/GHSA-aaaa-2040-reac/GHSA-aaaa-$n-reac/g" "$VFIX/records/ghsa-CVE-2026-2040.json" >"$CASE/ghsa-$n.json"
        put "${CVE_URL}CVE-2026-$n" 200 "$CASE/cve-$n.json"
        put "$GHSA_URL""CVE-2026-$n" 200 "$CASE/ghsa-$n.json"
    done
    collect
    local name="CVE の番号を2つ持つ項目で、2つの番号が同じ部品の同じ範囲に合うとき、matches に部品が1つだけ入る"
    check "$name(項目の番号)" "$(ent 'my ($k) = grep { grep { $_ eq "CVE-2026-2050" } @{ $e{$_}{cves} } } keys %e; join " ", sort @{ $e{$k}{cves} }')" \
        "CVE-2026-2050 CVE-2026-2051"
    check "$name(部品)" "$(ent 'my ($k) = grep { grep { $_ eq "CVE-2026-2050" } @{ $e{$_}{cves} } } keys %e; join " ", map { $_->{key} } @{ $e{$k}{matches} }')" \
        "npm:react"
    check "$name(判定の案)" "$(ent 'my ($k) = grep { grep { $_ eq "CVE-2026-2050" } @{ $e{$_}{cves} } } keys %e; $e{$k}{suggested}')" "not_affected"
}
addcase two_cves

# ---------------------------------------------------------------------
# 要件6の受入基準2: スキルを打つたびに集め直し、前の実行の材料を使わない
# ---------------------------------------------------------------------
case_old_runs() {
    newcase
    local state="$CASE/repo/.claude/.state/vuln-watch"
    mkdir -p "$state/20261102T115959Z-1111" "$state/20261104T110000Z-2222" "$state/keep-me"
    printf '{"entries":[{"key":"CVE-2099-9999"}]}\n' >"$state/20261104T110000Z-2222/entries-1.json"
    collect
    local first
    first=$(out '$d->{parts}[0]')
    local name="2日前に作った実行のフォルダだけが消え、1時間前のフォルダの偽の材料が新しい材料に入らない"
    check "$name(残るフォルダ)" "$(cd "$state" && find . -maxdepth 1 -mindepth 1 -type d ! -name "$(out '$d->{run}')" | sort | tr '\n' ' ')" \
        "./20261104T110000Z-2222 ./keep-me "
    check "$name(偽の材料が入らない)" "$(ent 'exists $e{"CVE-2099-9999"} ? "found" : "none"')" "none"
    collect
    name="同じ見本で collect を2回呼ぶと、2回の材料の entries が同じになる"
    check "$name(実行の ID が違う)" "$(out '$d->{parts}[0]')" "$(out '$d->{parts}[0]' | grep -v -x -F "$first")"
    check "$name" "$(pj 'JSON::PP->new->canonical->encode($d->{entries})' <"$first")" \
        "$(pj 'JSON::PP->new->canonical->encode($d->{entries})' <"$(out '$d->{parts}[0]')")"
}
addcase old_runs

# ---------------------------------------------------------------------
# 要件1の受入基準4: 取れなかった出どころの名前を示すための材料
# ---------------------------------------------------------------------
case_failures() {
    newcase
    printf '503' >"$(sample "$JPCERT_URL").status"
    export KP_FAKE_GH_FAIL='sbom pr-list'
    collect
    local name="JPCERT/CC の応答を 503 にし、偽の gh の sbom と pr-list を失敗させると、材料の failed に JPCERT/CC が入り、github の sbom_ok と refs_ok が偽になる"
    check "$name(collect が 0 で終わる)" "$(cat "$CASE/rc")" "0"
    check "$name(failed)" "$(mat 'join " ", map { "$_->{source}/$_->{name}" } @{ $d->{failed} }')" "jpcert/JPCERT/CC の注意喚起"
    check "$name(github)" "$(mat 'join " ", map { "$_=" . ($d->{github}{$_} ? "true" : "false") } sort keys %{ $d->{github} }')" \
        "advisories_ok=true refs_ok=false sbom_ok=false"

    newcase
    export KP_FAKE_GH_FAIL=auth-token
    collect
    name="gh の auth-token を失敗させると github の advisories_ok が偽になる"
    check "$name" "$(mat '$d->{github}{advisories_ok} ? "true" : "false"')" "false"
    check "$name(CVE の番号を持つ項目は、どれも決められない)" "$(ent 'join " ", sort { $a cmp $b } map { $_->{suggested} } grep { $_->{suggested} ne "undeterminable" } values %e')" "affected"

    newcase
    g "$CASE/repo" remote set-url origin "$CASE/no-such-origin.git"
    collect
    name="git fetch を失敗させると inventory.fetched が偽になる"
    check "$name(collect が 0 で終わる)" "$(cat "$CASE/rc")" "0"
    check "$name" "$(mat '$d->{inventory}{fetched} ? "true" : "false"')" "false"
}
addcase failures

case_fatal() {
    newcase
    mkdir -p "$CASE/not-repo"
    (cd "$CASE/not-repo" && GIT_CEILING_DIRECTORIES="$CASE" perl "$VW" collect >"$CASE/out.json" 2>"$CASE/err.txt"; echo $? >"$CASE/rc")
    local name="作業フォルダが git のリポジトリでないとき、collect が標準エラーに理由を1行出して 2 で終わる"
    check "$name(終了コード)" "$(cat "$CASE/rc")" "2"
    check "$name(標準エラー)" "$(cat "$CASE/err.txt")" "vuln-watch.pl: 作業フォルダが git のリポジトリでない"
    check "$name(標準出力に何も出さない)" "$(cat "$CASE/out.json")" ""

    (cd "$CASE/repo" && perl "$VW" collect extra >"$CASE/out.json" 2>"$CASE/err.txt"; echo $? >"$CASE/rc")
    name="collect に引数を付けると、使い方を出して 2 で終わり、実行のフォルダを作らない"
    check "$name(終了コード)" "$(cat "$CASE/rc")" "2"
    check "$name(実行のフォルダ)" "$(ls "$CASE/repo/.claude/.state/vuln-watch" 2>/dev/null | wc -l | tr -d ' ')" "0"
}
addcase fatal

# ---------------------------------------------------------------------
# 流す
# ---------------------------------------------------------------------
run_cases="$CASES"
if [ -n "${KP_TEST_CASE:-}" ]; then
    for want in $KP_TEST_CASE; do
        case " $CASES " in
            *" $want "*) ;;
            *) echo "当たる場合が無い: $want(場合: $CASES)" >&2; exit 2 ;;
        esac
    done
    run_cases="$KP_TEST_CASE"
fi
for c in $run_cases; do
    "case_$c"
done

echo
echo "$pass ok, $failn NG"
[ "$failn" -eq 0 ]
