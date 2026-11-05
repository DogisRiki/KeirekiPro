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

# フォルダの中のファイルとフォルダの名前を、. で始まる名前も含めて、名前の順に1行ずつ出す。フォルダが無いときは何も出さない
names() {
    [ -d "$1" ] || return 0
    (shopt -s nullglob dotglob; cd "$1" && for f in *; do printf '%s\n' "$f"; done) | LC_ALL=C sort
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
    put https://www.ipa.go.jp/security/security-alert/2026/1103-valkey.html 200 "$VFIX/article-ipa-1103-valkey.html"
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
# collect が出した項目のファイルを、material.json の parts の順にすべて読む。項目の鍵ごとの項目を %e に置いて式を評価する
ent() {
    local part all='' sep=''
    while IFS= read -r part; do
        all="$all$sep$(cat "$part")"
        sep=','
    done <<EOF
$(mat 'join "\n", @{ $d->{parts} }')
EOF
    printf '[%s]' "$all" | pj 'my %e = map { $_->{key} => $_ } map { @{ $_->{entries} } } @$d; '"$1"
}
# collect が作った実行のフォルダの場所を出す
run_dir() {
    local m
    m=$(out '$d->{material}')
    printf '%s' "${m%/material.json}"
}
# 実行のフォルダに判断の JSON を書く。式を渡したときは、式で判断を変えてから書く: result [<perl の式>]
result() { perl "$VFIX/make-result.pl" "$(run_dir)" "$@" || exit 2; }
# $VW_IN(無ければリポジトリのフォルダ)で show と clean を呼ぶ。
# 標準出力を $CASE/<サブコマンド>.out に、標準エラーを $CASE/<サブコマンド>.err に、終了コードを $CASE/<サブコマンド>.rc に書く
vw() {
    local cmd=$1
    shift
    (cd "${VW_IN:-$CASE/repo}" && perl "$VW" "$cmd" "$@" >"$CASE/$cmd.out" 2>"$CASE/$cmd.err"; echo $? >"$CASE/$cmd.rc")
}
# show.md があれば yes、無ければ no を出す
has_show() { if [ -e "$(run_dir)/show.md" ]; then echo yes; else echo no; fi; }
# show.md に「脆弱性の名前 <鍵>」が書かれていない項目の鍵を、鍵の順に出す
missing_names() {
    ent 'my $f = "'"$(run_dir)"'/show.md"; open my $h, "<:encoding(UTF-8)", $f or die "show.md が無い\n"; my $t = do { local $/; <$h> }; join " ", grep { index($t, "脆弱性の名前 $_") < 0 } sort keys %e'
}
# 判断の JSON を式で変えて show を呼び、2 で終わり、show.md を書かず、標準エラーが期待どおりかを確かめる: rejects <名前> <式> <標準エラー>
rejects() {
    result "$2"
    vw show --run "$(out '$d->{run}')"
    check "$1(終了コード)" "$(cat "$CASE/show.rc")" "2"
    check "$1(show.md を書かない)" "$(has_show)" "no"
    check "$1(標準エラー)" "$(cat "$CASE/show.err")" "$3"
}

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
        "CVE-2026-2001:pr731 CVE-2026-2002: CVE-2026-2003: CVE-2026-2010: CVE-2026-2011: CVE-2026-2020: CVE-2026-2030:issue801 CVE-2026-2040: CVE-2026-2041: CVE-2026-2060:"
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
    check "$name(項目の数)" "$(out '$d->{entries}')" "10"
    check "$name(材料の parts が、出した場所と同じ)" "$(mat 'join " ", @{ $d->{parts} }')" "$(out '$d->{parts}[0]')"
    check "$name(作業の場所を残さない)" "$(names "$CASE/repo/.claude/.state/vuln-watch/$(out '$d->{run}')" | tr '\n' ' ')" "entries-1.json material.json "
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
    # npm:next に範囲を当てたのは GitHub の勧告なので、GitHub の勧告の製品が先に並ぶ
    check "$name(製品)" \
        "$(ent 'join " ", map { "$_->{from}:$_->{vendor}:$_->{product}:" . scalar @{ $_->{ranges} } } @{ $e{"CVE-2026-2001"}{products} }')" \
        "github:npm:next:1 cna:vercel:next.js:1"
    check "$name(GitHub の勧告の範囲)" "$(ent 'my $r = $e{"CVE-2026-2001"}{products}[0]{ranges}[0]; "$r->{vulnerable_version_range}/$r->{first_patched_version}"')" \
        ">= 15.0.0, < 15.5.3/15.5.3"
}
addcase products

# ---------------------------------------------------------------------
# 要件4の受入基準3・要件3の受入基準3・要件2の受入基準1と3: 悪用と、製品の直った版と、元の発表のリンクと、名前の手がかり
# ---------------------------------------------------------------------
case_kev() {
    newcase
    collect
    local name="20日前に KEV に載った CVE の番号を持つ JPCERT/CC の直近7日の項目の kev に、その dateAdded が入る。KEV のどこにも無い番号だけを持つ項目の kev が null になる"
    check "$name(20日前に KEV に載った番号の項目)" "$(ent '$e{"CVE-2026-2010"}{kev}')" "2026-10-15"
    check "$name(KEV の項目)" "$(ent '$e{"CVE-2026-2003"}{kev}')" "2026-11-03"
    check "$name(KEV のどこにも無い番号の項目)" "$(ent 'join " ", map { exists $e{$_}{kev} ? $e{$_}{kev} // "null" : "<none>" } qw(CVE-2026-2020 CVE-2026-2040 CVE-2026-2060)')" "null null null"
}
addcase kev

case_origins() {
    newcase
    collect
    local name="products に、リポジトリの部品に当たらない製品の範囲と直った版が入る。origins に、KEV の notes の URL、記事の URL、vendor-advisory の URL の順に URL が並び、cvemon のページの URL が入らない。ほかの URL がある番号には cve.org の URL が入らない"
    check "$name(部品に当たらない製品)" \
        "$(ent 'join " ", map { "$_->{from}:$_->{vendor}:$_->{product}:" . scalar(@{ $_->{ranges} }) . ":" . ($_->{fixed} // "null") } @{ $e{"CVE-2026-2003"}{products} }')" \
        "cna:microsoft:windows_11:2:10.0.22631.4567, 10.0.26100.1234 cna:microsoft:windows_server_2019:1:null"
    check "$name(部品に当たらない製品の項目は、部品を持たない)" "$(ent 'scalar @{ $e{"CVE-2026-2003"}{matches} }')" "0"
    check "$name(GitHub の勧告の製品の直った版)" "$(ent 'join " ", map { "$_->{from}=" . ($_->{fixed} // "null") } @{ $e{"CVE-2026-2001"}{products} }')" \
        "github=15.5.3 cna=15.5.3"
    check "$name(部品に当たる製品の、CVE の記録と GitHub の勧告の直った版)" "$(ent 'join " ", map { "$_->{from}=" . ($_->{fixed} // "null") } @{ $e{"CVE-2026-2040"}{products} }')" \
        "github=19.0.0 cna=19.0.0"
    check "$name(並ぶ順)" "$(ent 'join " ", @{ $e{"CVE-2026-2010"}{origins} }')" \
        "https://oracle.example/security-alerts/cpuoct2026.html https://www.jpcert.or.jp/at/2026/at260101.html https://oracle.example/security-alerts/alert-cve-2026-2010.html"
    check "$name(重複と CISA の指令の URL を除く)" "$(ent 'join " ", @{ $e{"CVE-2026-2003"}{origins} }')" \
        "https://msrc.example/update-guide/vulnerability/CVE-2026-2003"
    check "$name(cvemon のページの URL が無い)" "$(ent 'join " ", grep { /cvemon/ } map { @{ $_->{origins} } } values %e')" ""
    check "$name(記事の URL だけを持つ項目に cve.org の URL が無い)" "$(ent 'join " ", @{ $e{"CVE-2026-2020"}{origins} }')" \
        "https://www.ipa.go.jp/security/security-alert/2026/1101-cms.html"

    name="cvemon だけに載り、vendor-advisory の URL を持たない番号の項目の origins に、その番号の cve.org の URL が入る"
    check "$name" "$(ent 'join " ", map { @{ $e{$_}{origins} } } qw(CVE-2026-2040 CVE-2026-2041)')" \
        "https://www.cve.org/CVERecord?id=CVE-2026-2040 https://www.cve.org/CVERecord?id=CVE-2026-2041"
}
addcase origins

case_name_hits() {
    newcase
    collect
    local name="題名に Valkey を含み、表に名前の無い製品の項目の name_hits に image:valkey/valkey が入る。4文字より短い名前の部品の鍵は name_hits に入らない"
    # 見本の frontend/pnpm-lock.yaml の npm の部品は next と react と ws の3件で、package.json の pnpm を合わせて4件になる
    check "$name(部品の一覧に、Valkey のイメージと、名前の短い部品を含む npm の部品がある)" \
        "$(mat 'join " ", (grep { $_ eq "image:valkey/valkey" } @{ $d->{inventory}{keys} }), $d->{inventory}{counts}{npm}')" \
        "image:valkey/valkey 4"
    # 見本の Valkey の名前は題名にだけ出て、React と Nextcloud と ws は記事の本文にだけ出る。Nextcloud の Next は語の一部なので合わない
    check "$name(名前の手がかり)" "$(ent 'join " ", @{ $e{"CVE-2026-2060"}{name_hits} }')" "image:valkey/valkey npm:react"
    check "$name(CVE の記録の説明にだけ出る名前)" "$(ent 'join " ", @{ $e{"CVE-2026-2040"}{name_hits} }')" "npm:react"
    check "$name(表に名前が無いので、部品は合わない)" "$(ent 'scalar(@{ $e{"CVE-2026-2060"}{matches} }) . " " . $e{"CVE-2026-2060"}{suggested}')" "0 unrelated"
    check "$name(題名の Next.js の Next が語として合う)" "$(ent 'join " ", @{ $e{"CVE-2026-2001"}{name_hits} }')" "npm:next"
    check "$name(名前が出ない項目)" "$(ent 'scalar @{ $e{"CVE-2026-2020"}{name_hits} }')" "0"
}
addcase name_hits

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
    check "$name(実行のフォルダ)" "$(names "$CASE/repo/.claude/.state/vuln-watch" | wc -l | tr -d ' ')" "0"
}
addcase fatal

# ---------------------------------------------------------------------
# 要件2の受入基準2・要件3の受入基準3・要件4の受入基準1と3: 材料の量を抑え、項目のファイルを分けて書く
# ---------------------------------------------------------------------
case_large() {
    newcase
    # 大きな見本(fixtures/test-vuln-watch/make-large.pl の頭に書いたもの)を置き、リポジトリの部品の見本を足して push する
    perl "$VFIX/make-large.pl" "$VFIX" "$CASE" || exit 2
    g "$CASE/repo" add -A
    g "$CASE/repo" commit -q -m large
    g "$CASE/repo" push -q origin main
    g "$CASE/repo" fetch -q origin
    collect
    check "collect の終了コード(大きな見本)" "$(cat "$CASE/rc")" "0"

    local name="大きな見本で collect を呼ぶと、CVE の番号を300件持つ記事があっても、KEV の項目の番号と、CVE の番号を1件だけ持つ IPA の項目の番号の looked_up が真になる"
    # 確かめられなかった番号には、鍵 * の1件が matches に入る。* の無い項目は、どの番号も確かめられた
    check "$name(KEV の項目と IPA の項目)" \
        "$(ent 'join " ", map { my $k = $_; "$k=" . ((grep { $_->{key} eq "*" } @{ $e{$k}{matches} }) ? "not_looked_up" : "looked_up") } qw(CVE-2026-2001 CVE-2026-2002 CVE-2026-2003 CVE-2026-2010 CVE-2026-2020)')" \
        "CVE-2026-2001=looked_up CVE-2026-2002=looked_up CVE-2026-2003=looked_up CVE-2026-2010=looked_up CVE-2026-2020=looked_up"
    check "$name(300件の番号の項目は、確かめられなかった番号を持つ)" \
        "$(ent 'scalar(@{ $e{"CVE-2026-5000"}{cves} }) . ":" . join(",", map { $_->{reason} } grep { $_->{key} eq "*" } @{ $e{"CVE-2026-5000"}{matches} })')" \
        "300:not_looked_up"

    name="大きな見本で collect を呼ぶと、material.json とどの entries-<番号>.json も40,000バイト以下になり、項目のファイルが2つ以上に分かれる。どの項目も products が10件以下で origins が5件以下になり、inventory.keys に npm:pnpm と npm:@openai/codex のほかの npm: と maven: の鍵が入らない"
    check "$name(40,000バイトを超えるファイル)" "$(out 'join " ", grep { -s $_ > 40000 } $d->{material}, @{ $d->{parts} }')" ""
    check "$name(項目のファイルの数が2つ以上)" "$(out 'scalar(@{ $d->{parts} }) >= 2 ? "yes" : scalar @{ $d->{parts} }')" "yes"
    check "$name(products が10件を超えるか origins が5件を超える項目)" \
        "$(ent 'join " ", grep { @{ $e{$_}{products} } > 10 || @{ $e{$_}{origins} } > 5 } sort keys %e')" ""
    # 300件の番号の項目の製品は、vendor-<0から49>:prod-<同じ数> の50種類と vercel:next.js の51種類。
    # 部品の npm:next に範囲を当てた vercel:next.js が先頭に来て、そのあとに番号の大きい順(項目の番号の並び)で9件が続く
    check "$name(300件の番号の項目の製品と、入れなかった製品の数)" \
        "$(ent 'my $x = $e{"CVE-2026-5000"}; join(" ", map { "$_->{vendor}:$_->{product}" } @{ $x->{products} }) . " omitted=$x->{products_omitted}"')" \
        "vercel:next.js vendor-49:prod-49 vendor-48:prod-48 vendor-47:prod-47 vendor-46:prod-46 vendor-45:prod-45 vendor-44:prod-44 vendor-43:prod-43 vendor-42:prod-42 vendor-41:prod-41 omitted=41"
    check "$name(300件の番号の項目の元の発表の URL は5件で、全体の数は5件より多い)" \
        "$(ent 'my $x = $e{"CVE-2026-5000"}; scalar(@{ $x->{origins} }) . ":" . ($x->{origins_total} > 5 ? "more" : $x->{origins_total})')" \
        "5:more"
    # 300件の番号の項目の説明は、先頭の3件の番号(番号の大きい順)と、部品の名前が合った CVE-2026-5200 だけになる
    check "$name(300件の番号の項目の説明)" "$(ent 'join " ", sort keys %{ $e{"CVE-2026-5000"}{descriptions} }')" \
        "CVE-2026-5200 CVE-2026-5297 CVE-2026-5298 CVE-2026-5299"

    name="大きな見本で collect を呼ぶと、CVE の番号が多く説明を絞った項目でも、絞る前のすべての番号の説明から name_hits を作る"
    # CVE-2026-5100 の説明は材料に入らないが、その説明にある Valkey の名前が name_hits に入る
    check "$name" "$(ent 'my $x = $e{"CVE-2026-5000"}; (exists $x->{descriptions}{"CVE-2026-5100"} ? "kept" : "dropped") . " " . join(" ", grep { $_ eq "image:valkey/valkey" } @{ $x->{name_hits} })')" \
        "dropped image:valkey/valkey"

    name="大きな見本で collect を呼ぶと、material.json とどの entries-<番号>.json も40,000バイト以下になり、項目のファイルが2つ以上に分かれる。どの項目も products が10件以下で origins が5件以下になり、inventory.keys に npm:pnpm と npm:@openai/codex のほかの npm: と maven: の鍵が入らない"
    check "$name(部品の一覧の npm: と maven: の鍵)" "$(mat 'join " ", grep { /\A(?:npm|maven):/ } @{ $d->{inventory}{keys} }')" \
        "npm:@openai/codex npm:pnpm"
    # npm の部品は、見本の3件と足した700件と、npm:pnpm と npm:@openai/codex の705件。Maven の部品は足した500件
    check "$name(部品の数)" "$(mat 'my $c = $d->{inventory}{counts}; "npm=$c->{npm} maven=$c->{maven}"')" "npm=705 maven=500"

    name="大きな見本で、show が分かれたすべての項目のファイルを読んで表示の文を組み立てる"
    result
    vw show --run "$(out '$d->{run}')"
    check "$name(終了コード)" "$(cat "$CASE/show.rc")" "0"
    # どの項目のファイルの項目も、名前が show.md に書かれる
    check "$name(名前の無い項目)" "$(missing_names)" ""
    check "$name(最後の項目のファイルの項目)" \
        "$(pj 'scalar @{ $d->{entries} } > 0 ? "has_entries" : "empty"' <"$(out '$d->{parts}[-1]')")" "has_entries"
}
addcase large

case_git_ranges() {
    newcase
    # この場合だけ、KEV に載った CVE-2026-2003 の記録を、git の範囲を10件と unaffected の範囲を7件持つ linux:linux_kernel と、
    # 部品の npm:next に当たらない範囲と当たる範囲の2件の vercel:next.js と、KEV に載った Microsoft の製品と、
    # そのほかの製品を持つ記録に替える。KEV の vendorProject は Microsoft で、記録の vendor も Microsoft と大文字で始める
    put "${CVE_URL}CVE-2026-2003" 200 "$VFIX/cve-git-ranges.json"
    # KEV に載った Oracle の CVE-2026-2010 は、記録に製品が無く、image:eclipse-temurin に範囲を当てられないので NVD を引く。
    # NVD の応答は、部品に当たらない oracle:graalvm と、部品に当たる oracle:java_se の順に範囲を持つ
    put "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-2010" 200 "$VFIX/nvd-CVE-2026-2010.json"
    collect
    local name="git の範囲を10件と unaffected の範囲を7件持つ製品の見本で collect を呼ぶと、材料のその製品の範囲が、git でない範囲から先に残った5件になり、製品の fixed に7件の unaffected の範囲から得た直った版がすべて入る"
    check "$name(範囲)" \
        "$(ent 'my ($p) = grep { $_->{product} eq "linux_kernel" } @{ $e{"CVE-2026-2003"}{products} }; join " ", map { "$_->{version}/$_->{versionType}" } @{ $p->{ranges} }')" \
        "5.10.230/semver 5.15.170/semver 6.1.120/semver 6.6.60/semver 6.11.7/semver"
    check "$name(直った版)" \
        "$(ent 'my ($p) = grep { $_->{product} eq "linux_kernel" } @{ $e{"CVE-2026-2003"}{products} }; $p->{fixed} // "null"')" \
        "5.10.230, 5.15.170, 6.1.120, 6.6.60, 6.11.7, 6.12.1, 6.13"

    name="材料の製品は、部品に範囲を当てた製品、KEV に載った製品、そのほかの製品の順に並び、同じ順位の中では元の順に並ぶ。<vendor>:<product> が重なる製品は、先に並んだ製品だけが残る"
    check "$name(CVE の記録の製品)" "$(ent 'join " ", map { "$_->{vendor}:$_->{product}" } @{ $e{"CVE-2026-2003"}{products} }')" \
        "vercel:next.js Microsoft:windows_11 acme:tool linux:linux_kernel"
    check "$name(重なる製品は、部品に範囲を当てた製品が残る)" "$(ent 'join " ", map { $_->{version} } @{ $e{"CVE-2026-2003"}{products}[0]{ranges} }')" \
        "15.0.0"
    check "$name(NVD の製品)" "$(ent 'join " ", map { "$_->{from}:$_->{vendor}:$_->{product}" } @{ $e{"CVE-2026-2010"}{products} }')" \
        "nvd:oracle:java_se nvd:oracle:graalvm"
}
addcase git_ranges

# ---------------------------------------------------------------------
# 要件2の受入基準3・要件4の受入基準1と3: show が判断の JSON を確かめ、表示の文を書く
# ---------------------------------------------------------------------
case_show() {
    newcase
    collect
    local run dir name
    run=$(out '$d->{run}')
    dir=$(run_dir)
    result
    vw show --run "$run"
    name="show が、材料のすべての項目を確かめに通る判断の JSON で、表示の文を show.md に書き、その場所を標準出力に出す"
    check "$name(終了コード)" "$(cat "$CASE/show.rc")" "0"
    check "$name(標準エラーに何も出さない)" "$(cat "$CASE/show.err")" ""
    check "$name(標準出力)" "$(cat "$CASE/show.out")" "{\"show\":\"$dir/show.md\"}"
    check "$name(見出し)" "$(head -n 1 "$dir/show.md")" "## 直近7日に出た脆弱性(2026-10-28から2026-11-04まで)"
    check "$name(組の見出し)" "$(grep '^### ' "$dir/show.md" | tr '\n' ' ')" \
        "### このリポジトリの部品に影響がある脆弱性と、影響があるかを決められない脆弱性 ### そのほかの脆弱性 "
    check "$name(名前の無い項目)" "$(missing_names)" ""

    result '$j{"CVE-2026-2040"}{verdict} = "undeterminable"; $j{"CVE-2026-2040"}{reason} = "理由"; $j{"CVE-2026-2040"}{check} = "手順"; $j{"CVE-2026-2020"}{verdict} = "undeterminable"; $j{"CVE-2026-2020"}{reason} = "理由"; $j{"CVE-2026-2020"}{check} = "手順"'
    vw show --run "$run"
    check "show が、判定の案が not_affected の項目と unrelated の項目を undeterminable にした判断の JSON を受け入れる" "$(cat "$CASE/show.rc")" "0"

    name="show が、affected を not_affected にした判断の JSON と、undeterminable に reason の無い判断の JSON と、kev がある項目の exploited を偽にした判断の JSON と、項目の足りない判断の JSON を、2 で終わって退け、show.md を書かない"
    rejects "$name(affected を not_affected にした)" '$j{"CVE-2026-2001"}{verdict} = "not_affected"; $j{"CVE-2026-2001"}{action} = undef' \
        "vuln-watch.pl: 判断の JSON が合わない: CVE-2026-2001 の verdict: 判定の案が affected の項目では affected にする"
    rejects "$name(undeterminable に reason が無い)" '$j{"CVE-2026-2002"}{reason} = undef' \
        "vuln-watch.pl: 判断の JSON が合わない: CVE-2026-2002 の reason: undeterminable の項目では空でない文字列にする"
    rejects "$name(kev がある項目の exploited が偽)" '$j{"CVE-2026-2003"}{exploited} = JSON::PP::false' \
        "vuln-watch.pl: 判断の JSON が合わない: CVE-2026-2003 の exploited: CISA の一覧に載った脆弱性では真にする"
    rejects "$name(項目が足りない)" '$r->{entries} = [ grep { $_->{key} ne "CVE-2026-2020" } @{ $r->{entries} } ]' \
        "vuln-watch.pl: 判断の JSON が合わない: CVE-2026-2020 の key: 判断の JSON に無い"

    name="show が、affected の項目の action が null の判断の JSON と、pc の要素の check が空の判断の JSON と、damage が空の判断の JSON と、材料に無い key を持つ判断の JSON と、suggested が unrelated の項目の verdict を affected にした判断の JSON を、2 で終わって退け、標準エラーに key と欄を出す"
    rejects "$name(affected の action が null)" '$j{"CVE-2026-2001"}{action} = undef' \
        "vuln-watch.pl: 判断の JSON が合わない: CVE-2026-2001 の action: affected の項目では空でない文字列にする"
    rejects "$name(pc の要素の check が空)" '$j{"CVE-2026-2020"}{pc} = [ { software => "Windows 11", versions => "24H2", fixed => "26100.4000", check => "" } ]' \
        "vuln-watch.pl: 判断の JSON が合わない: CVE-2026-2020 の pc の1件目の check: 空でない文字列にする"
    rejects "$name(damage が空)" '$j{"CVE-2026-2040"}{damage} = ""' \
        "vuln-watch.pl: 判断の JSON が合わない: CVE-2026-2040 の damage: 空でない文字列にする"
    rejects "$name(材料に無い key)" 'push @{ $r->{entries} }, { %{ $j{"CVE-2026-2020"} }, key => "CVE-2099-0001" }' \
        "vuln-watch.pl: 判断の JSON が合わない: CVE-2099-0001 の key: 材料に無い"
    rejects "$name(unrelated を affected にした)" '$j{"CVE-2026-2020"}{verdict} = "affected"; $j{"CVE-2026-2020"}{action} = "上げる"' \
        "vuln-watch.pl: 判断の JSON が合わない: CVE-2026-2020 の verdict: 判定の案が unrelated の項目では unrelated か undeterminable にする"
    rejects "$name(欄が無い)" 'delete $j{"CVE-2026-2040"}{exploited_note}' \
        "vuln-watch.pl: 判断の JSON が合わない: CVE-2026-2040 の exploited_note: 欄が無い"
    rejects "$name(合わない項目が2つ)" '$j{"CVE-2026-2001"}{name} = ""; $j{"CVE-2026-2002"}{check} = undef' \
        "vuln-watch.pl: 判断の JSON が合わない: CVE-2026-2001 の name: 空でない文字列にする
vuln-watch.pl: 判断の JSON が合わない: CVE-2026-2002 の check: undeterminable の項目では空でない文字列にする"

    name="判断の JSON が無いか JSON として読めないとき、show は標準エラーに理由を1行出して 2 で終わる"
    rm -f "$dir/result.json"
    vw show --run "$run"
    check "$name(無い)" "$(cat "$CASE/show.rc"):$(cat "$CASE/show.err")" "2:vuln-watch.pl: 判断の JSON が無いか、JSON として読めない: $dir/result.json"
    printf '{"version":1,' >"$dir/result.json"
    vw show --run "$run"
    check "$name(読めない)" "$(cat "$CASE/show.rc"):$(cat "$CASE/show.err")" "2:vuln-watch.pl: 判断の JSON が無いか、JSON として読めない: $dir/result.json"

    name="実行のフォルダか material.json か parts のファイルが無いとき、show は標準エラーに理由を1行出して 3 で終わる"
    result
    vw show --run 20261104T000000Z-1
    check "$name(実行のフォルダ)" "$(cat "$CASE/show.rc"):$(cat "$CASE/show.err")" \
        "3:vuln-watch.pl: 実行のフォルダが無い: $CASE/repo/.claude/.state/vuln-watch/20261104T000000Z-1"
    mv "$dir/entries-1.json" "$dir/entries-1.json.bak"
    vw show --run "$run"
    check "$name(parts のファイル)" "$(cat "$CASE/show.rc"):$(cat "$CASE/show.err"):$(has_show)" \
        "3:vuln-watch.pl: 項目のファイルが無いか、JSON として読めない: $dir/entries-1.json:no"
    mv "$dir/entries-1.json.bak" "$dir/entries-1.json"
    mv "$dir/material.json" "$dir/material.json.bak"
    vw show --run "$run"
    check "$name(material.json)" "$(cat "$CASE/show.rc"):$(cat "$CASE/show.err")" \
        "3:vuln-watch.pl: 材料が無いか、JSON として読めない: $dir/material.json"
    mv "$dir/material.json.bak" "$dir/material.json"

    name="show と clean は、--run に実行の ID の形でない値を渡されると、標準エラーに理由を出して 2 で終わる。--run が無いときは使い方を出して 2 で終わる"
    vw show --run ../vuln-watch
    check "$name(show)" "$(cat "$CASE/show.rc"):$(cat "$CASE/show.err")" "2:vuln-watch.pl: 実行の ID の形でない: ../vuln-watch"
    vw show
    check "$name(show の --run が無い)" "$(cat "$CASE/show.rc"):$(grep -c "^vuln-watch.pl: 使い方: " "$CASE/show.err")" "2:1"
    vw clean
    check "$name(clean の --run が無い)" "$(cat "$CASE/clean.rc"):$(grep -c "^vuln-watch.pl: 使い方: " "$CASE/clean.err")" "2:1"
}
addcase show

# ---------------------------------------------------------------------
# 要件6の受入基準2: 集めた情報と示した脆弱性を記録に残さない
# ---------------------------------------------------------------------
case_clean() {
    newcase
    mkdir -p "$CASE/tmp"
    local state="$CASE/repo/.claude/.state/vuln-watch" run name
    (cd "$CASE/repo" && TMPDIR="$CASE/tmp" TMP="$CASE/tmp" TEMP="$CASE/tmp" perl "$VW" collect >"$CASE/out.json" 2>"$CASE/err.txt")
    run=$(out '$d->{run}')
    result
    TMPDIR="$CASE/tmp" TMP="$CASE/tmp" TEMP="$CASE/tmp" vw show --run "$run"
    TMPDIR="$CASE/tmp" TMP="$CASE/tmp" TEMP="$CASE/tmp" vw clean --run "$run"
    name="collect と show と clean のあと、受け渡しの場所に実行のフォルダが残らず、HOME の一時フォルダにも、.claude/.state/ のほかの場所にも、ファイルが書かれない"
    check "$name(show と clean の終了コード)" "$(cat "$CASE/show.rc") $(cat "$CASE/clean.rc")" "0 0"
    check "$name(clean は何も出さない)" "$(cat "$CASE/clean.out")$(cat "$CASE/clean.err")" ""
    check "$name(受け渡しの場所)" "$(names "$state" | tr '\n' ' ')" ""
    check "$name(HOME の一時フォルダ)" "$(find "$CASE/home" -mindepth 1 | tr '\n' ' ')" ""
    check "$name(一時ファイルの場所)" "$(find "$CASE/tmp" -mindepth 1 | tr '\n' ' ')" ""
    check "$name(リポジトリ)" "$(git -C "$CASE/repo" status --porcelain --untracked-files=all --ignored)" ""
    vw clean --run "$run"
    check "clean は、実行のフォルダが無いときも 0 で終わる" "$(cat "$CASE/clean.rc")" "0"

    newcase
    state="$CASE/repo/.claude/.state/vuln-watch"
    mkdir -p "$state/keep-me"
    (cd "$CASE/repo/frontend" && env -u CLAUDE_PROJECT_DIR perl "$VW" collect >"$CASE/out.json" 2>"$CASE/err.txt"; echo $? >"$CASE/rc")
    run=$(out '$d->{run}')
    name="CLAUDE_PROJECT_DIR を消して、リポジトリの下のフォルダで collect と show と clean を呼ぶと、受け渡しの場所が見つかる。clean は、実行の ID の形でない値を退け、何も消さない"
    check "$name(collect)" "$(cat "$CASE/rc"):$(out '$d->{material}')" "0:$state/$run/material.json"
    result
    export VW_IN="$CASE/repo/frontend"
    (unset CLAUDE_PROJECT_DIR; vw show --run "$run")
    check "$name(show)" "$(cat "$CASE/show.rc"):$(cat "$CASE/show.out")" "0:{\"show\":\"$state/$run/show.md\"}"
    local bad
    for bad in keep-me ../vuln-watch "$run/.." 20261104T120000Z; do
        (unset CLAUDE_PROJECT_DIR; vw clean --run "$bad")
        check "$name(clean --run $bad)" "$(cat "$CASE/clean.rc"):$(cat "$CASE/clean.err")" "2:vuln-watch.pl: 実行の ID の形でない: $bad"
    done
    check "$name(実行の ID の形でない値では何も消さない)" "$(names "$state" | tr '\n' ' ')" "$(printf '%s\n' "$run" keep-me | LC_ALL=C sort | tr '\n' ' ')"
    (unset CLAUDE_PROJECT_DIR; vw clean --run "$run")
    check "$name(clean)" "$(cat "$CASE/clean.rc"):$(names "$state" | tr '\n' ' ')" "0:keep-me "
    unset VW_IN
}
addcase clean

# ---------------------------------------------------------------------
# 要件5の受入基準1・要件6の受入基準1: スキルの設定と、決まりの置き場所
# ---------------------------------------------------------------------
case_skill() {
    local skill="$HERE/../../../skills/vuln-watch/SKILL.md" name want line_rules line_steps
    name="SKILL.md のフロントマターが disable-model-invocation: true と、部品の節の allowed-tools を持つ。本文で、決まりの見出しが手順の見出しより前にあり、公開の場所に書かない決まりの文を持つ"
    want='---
name: vuln-watch
description: 直近7日に出た脆弱性を4つの出どころから集め、このリポジトリの部品と開発者の PC のソフトへの影響を示す手順。開発者が /vuln-watch と打ったときだけ動く。
disable-model-invocation: true
allowed-tools: Read, Write, Bash(perl .claude/scripts/vuln-watch/vuln-watch.pl *)
---'
    check "$name(フロントマター)" "$(head -n 6 "$skill" 2>/dev/null | tr -d '\r')" "$want"
    line_rules=$(grep -n -x '## 決まり' "$skill" 2>/dev/null | head -n 1 | cut -d: -f1)
    line_steps=$(grep -n -x '## 手順' "$skill" 2>/dev/null | head -n 1 | cut -d: -f1)
    check "$name(決まりの見出しが手順の見出しより前にある)" \
        "$([ -n "$line_rules" ] && [ -n "$line_steps" ] && [ "$line_rules" -lt "$line_steps" ] && echo yes || echo no)" "yes"
    check "$name(公開の場所に書かない決まり)" \
        "$(head -n "${line_steps:-0}" "$skill" 2>/dev/null | grep -c -x -F -e '- 主の Claude は、この会話の終わりまで、開発者の PC のソフトが脆弱性の影響を受けることと、PC のソフトの名前と版を、Issue の本文、PR の本文、PR のコメント、コミットのメッセージに書かない。開発者が会話で、自分の PC が影響を受けると答えたときも書かない。このリポジトリの部品に影響がある脆弱性は、それを直す PR と、コンテナの脆弱性の Issue に書いてよい')" "1"
}
addcase skill

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
