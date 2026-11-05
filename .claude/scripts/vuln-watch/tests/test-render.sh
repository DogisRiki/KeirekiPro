#!/bin/bash
# shellcheck disable=SC2016 # $d は jmod に渡す perl の式の変数で、シェルの変数ではない
# =====================================================================
# 表示の文を組み立てるモジュール(render.pl)のテスト
#
# 実行: bash .claude/scripts/vuln-watch/tests/test-render.sh
# 前提: bash・perl(JSON::PP)・awk
#
# 場合を選んで流す: KP_TEST_CASE='groups kinds' bash .claude/scripts/vuln-watch/tests/test-render.sh
# 空白で区切った名前の場合だけを流す。どの場合にも合わない名前があれば、何も流さずに終了コード 2 で終わる
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
RENDER="$(cd "$HERE/.." && pwd)/render.pl"

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }

# 材料と判断の JSON の見本。material.json は material.json の形、entries.json は entries-<番号>.json の形、
# result.json は判断の JSON の形とする
FIX="$HERE/fixtures/test-render"
M="$FIX/material.json"
E="$FIX/entries.json"
R="$FIX/result.json"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# 場合ごとの一時フォルダを作る
CASE_NO=0
newcase() {
    CASE_NO=$((CASE_NO + 1))
    CASE="$TMP_ROOT/c$CASE_NO"
    mkdir -p "$CASE"
}

# 場合の中の $(...) で、場合のフォルダの下に別のフォルダを作って使う。$(...) の中で newcase を呼ぶと、
# 場合の番号が外に戻らず、次の場合が同じフォルダを使うためである
subcase() {
    CASE="$CASE/sub"
    mkdir -p "$CASE"
}

# render_text を呼び、表示の文を $CASE/out.md に、標準エラーを $CASE/err.txt に書く:
# render [<材料の JSON> [<項目の JSON> [<判断の JSON>]]]
render() {
    perl -MJSON::PP -e '
        require $ARGV[0];
        my @d = map { open my $h, "<:raw", $_ or die "$_: $!"; local $/; JSON::PP->new->utf8->decode(<$h>) } @ARGV[1 .. 3];
        binmode STDOUT, ":encoding(UTF-8)";
        print render_text($d[0], $d[1]{entries}, $d[2]);
    ' "$RENDER" "${1:-$M}" "${2:-$E}" "${3:-$R}" >"$CASE/out.md" 2>"$CASE/err.txt"
}

# JSON のファイルを $d に読み、perl の式で直したものを書く: jmod <元のファイル> <書くファイル> '<式>'
jmod() {
    perl -MJSON::PP -e '
        open my $h, "<:raw", $ARGV[0] or die "$ARGV[0]: $!";
        my $d = JSON::PP->new->utf8->decode(do { local $/; <$h> });
        eval $ARGV[2];
        die $@ if $@;
        open my $o, ">:raw", $ARGV[1] or die "$ARGV[1]: $!";
        print $o JSON::PP->new->utf8->canonical->encode($d);
    ' "$1" "$2" "$3"
}

# 表示の文の、見出し「#### <名前の行>」から空行の前までを出す: block '<名前の行>'
block() { awk -v h="#### $1" '$0 == h { p = 1 } p && $0 == "" { exit } p { print }' "$CASE/out.md"; }

# 表示の文の、組と項目の見出しの行を出す
headings() { grep '^###' "$CASE/out.md"; }

# 表示の文の先頭の N 行を、空行を <空行> に替えて出す: top <N>
top() { head -n "$1" "$CASE/out.md" | sed 's/^$/<空行>/'; }

# 表示の文の、文字列で始まる行の数を出す: count '<文字列>'
count() { awk -v s="$1" 'index($0, s) == 1 { n++ } END { print n + 0 }' "$CASE/out.md"; }

# 見出しの名前の行
H_PG='PostgreSQL の任意のコードの実行(CVE-2026-1002)'
H_NEXT='Next.js の認可の回避(CVE-2026-1001)'
H_AXIOS='axios のサーバ側の要求の偽造(CVE-2026-1010)'
H_TOMCAT='Apache Tomcat の情報の漏えい(CVE-2026-1003、CVE-2026-1004、CVE-2026-1005、CVE-2026-1006、CVE-2026-1007、ほか 2 件)'
H_SSH='OpenSSH の任意のコードの実行(CVE-2026-1011)'
H_ESBUILD='esbuild の開発サーバの要求の読み出し(CVE-2026-1013)'
H_VITE='Vite の開発サーバのファイルの読み出し(CVE-2026-1012)'
H_WIN='Windows の権限の昇格(CVE-2026-1015)'
H_7ZIP='7-Zip の任意のコードの実行(CVE-2026-1014)'
G1='### このリポジトリの部品に影響がある脆弱性と、影響があるかを決められない脆弱性'
G2='### 開発者の PC で動くソフトの脆弱性'
G3='### そのほかの脆弱性'
TITLE='## 直近7日に出た脆弱性(2026-10-29から2026-11-05まで)'
FAILED='取れなかった出どころ: JPCERT/CC の注意喚起、cvemon の話題の一覧'

# ---------------------------------------------------------------------
# 場合
# ---------------------------------------------------------------------

# 3つの組と、組の中の並び。affected が先、exploited が先、日付の新しい順、cvemon だけの項目は最後に rank の順
case_groups() {
    local name='組への分け方と並べ方'
    newcase
    render
    check "$name(標準エラーに何も出さない)" "$(cat "$CASE/err.txt")" ""
    check "$name(3つの組に分かれ、1つ目の組で affected が先、組の中で exploited が先に並ぶ)" "$(headings)" \
        "$G1
#### $H_PG
#### $H_NEXT
#### $H_AXIOS
#### $H_TOMCAT
#### $H_SSH
#### $H_ESBUILD
#### $H_VITE
$G2
#### $H_WIN
#### $H_7ZIP
$G3"
    check "$name(部品と PC のソフトの両方に当たる項目が1つ目の組で PC で動くソフトの行を持つ)" "$(block "$H_NEXT" | grep '^- PC で動くソフト')" \
        '- PC で動くソフト: Node.js 22.0.0 から 22.11.0 まで、直った版: 22.11.1、確かめる手順: node --version を打つ'
    check "$name(項目の無い組を見出しごと書かない)" "$(
        subcase
        jmod "$E" "$CASE/e.json" '$d->{entries} = [ grep { $_->{key} eq "CVE-2026-1001" } @{ $d->{entries} } ]'
        render "$M" "$CASE/e.json"
        headings
    )" "$G1
#### $H_NEXT"
}

# 3つの種類の脆弱性に書く行
case_kinds() {
    local name='種類ごとの行'
    newcase
    render
    check "$name(affected の項目が、in_range が真の部品ごとに影響を受ける部品の行と、開発者がすることを持つ)" "$(block "$H_NEXT")" \
        "#### $H_NEXT
- 起きる被害: 認可を回避されて、管理の画面を開かれる
- 悪用: 確かめられていない
- 元の発表: https://www.jpcert.or.jp/at/2026/at260001.html、https://nextjs.example/blog/security-1001
- 影響を受ける部品: npm:next 15.5.2(frontend/pnpm-lock.yaml)、直った版: 15.5.3
- 影響を受ける部品: maven:org.example:lib 1.0, 1.1(backend/gradle/libs.versions.toml, github:dependency-graph)、直った版: 分からない
- 開発者がすること: frontend の next を 15.5.3 に上げる
- すでに扱っている PR と Issue: #731、#802
- PC で動くソフト: Node.js 22.0.0 から 22.11.0 まで、直った版: 22.11.1、確かめる手順: node --version を打つ"
    check "$name(コンテナの脆弱性の Issue だけで affected になった項目の影響を受ける部品が Issue の番号を持つ)" "$(block "$H_PG")" \
        "#### $H_PG
- 起きる被害: データベースの上で任意のコードを動かされる
- 悪用: 確かめられている(CISA の一覧に 2026-11-01 に載った)
- 元の発表: https://postgres.example/support/security/CVE-2026-1002/
- 影響を受ける部品: コンテナの脆弱性の Issue に書かれたイメージ(#801、#803)
- 開発者がすること: compose.yaml の postgres のイメージを上げる
- すでに扱っている PR と Issue: #801、#803"
    check "$name(undeterminable の項目が決められない理由と確かめる手順を持ち、CVE の番号と元の発表が先頭の5件とほか N 件になる)" "$(block "$H_TOMCAT")" \
        "#### $H_TOMCAT
- 起きる被害: 設定のファイルを読まれる
- 悪用: 確かめられていない
- 元の発表: https://www.ipa.go.jp/security/security-alert/2026/tomcat.html、https://tomcat.example/security-11.html、https://tomcat.example/security-10.html、https://tomcat.example/security-9.html、https://lists.example/thread/1003、ほか 3 件
- 影響があるかを決められない理由: 11.0 の系列の範囲が発表されていない
- 開発者が確かめる手順: Tomcat の発表で 11.0.2 が直った版より前かを読む"
    check "$name(origins が6件のときも、元の発表が先頭の5件とほか 1 件になる)" "$(
        subcase
        jmod "$E" "$CASE/e.json" 'for (@{ $d->{entries} }) { next unless $_->{key} eq "CVE-2026-1001"; $_->{origins} = [ map { "https://o.example/$_" } 1 .. 6 ]; $_->{origins_total} = 6 }'
        render "$M" "$CASE/e.json"
        block "$H_NEXT" | grep '^- 元の発表'
    )" '- 元の発表: https://o.example/1、https://o.example/2、https://o.example/3、https://o.example/4、https://o.example/5、ほか 1 件'
    check "$name(PC のソフトを2つ持つ項目が PC で動くソフトの行を2つ持ち、PR と Issue の行を持たない)" "$(block "$H_7ZIP")" \
        "#### $H_7ZIP
- 起きる被害: 細工した書庫を開くと任意のコードを動かされる
- 悪用: 確かめられていない
- 元の発表: https://www.jpcert.or.jp/at/2026/at260003.html
- PC で動くソフト: 7-Zip 25.00 より前、直った版: 25.00、確かめる手順: 7-Zip の「ヘルプ」の「バージョン情報」を開く
- PC で動くソフト: 7-Zip のコマンド 25.00 より前、直った版: 25.00、確かめる手順: 7z を引数なしで打つ"
    check "$name(影響を受ける部品と開発者がすることは affected の2件だけ、決められない理由と確かめる手順は undeterminable の5件だけが持つ)" \
        "$(count '- 影響を受ける部品:') $(count '- 開発者がすること:') $(count '- 影響があるかを決められない理由:') $(count '- 開発者が確かめる手順:')" "3 2 5 5"
}

# そのほかの脆弱性の1行
case_others() {
    local name='そのほかの脆弱性'
    newcase
    render
    check "$name(名前と CVE の番号とソフトと元の発表の先頭の URL の1行になる)" \
        "$(awk -v g="$G3" '$0 == g { p = 1; next } p && NF { print }' "$CASE/out.md")" \
        '- Oracle Java SE の情報の漏えい(CVE-2026-1017)— Oracle Java SE — https://www.ipa.go.jp/security/security-alert/2026/oracle.html
- 家庭用ルータの認証の回避(CVE-2026-1016)— 家庭用ルータ — https://www.jpcert.or.jp/at/2026/at260004.html
- ある CMS の入力の検証の漏れ(CVE-2026-1020)— ある CMS — https://www.cve.org/CVERecord?id=CVE-2026-1020'
}

# 集めた脆弱性が無いとき
case_empty() {
    local name='集めた脆弱性が無いとき'
    newcase
    printf '{"entries":[]}' >"$CASE/e.json"
    jmod "$M" "$CASE/m.json" '$d->{github}{$_} = JSON::PP::false for qw(advisories_ok sbom_ok refs_ok); $d->{inventory}{fetched} = JSON::PP::false'
    render "$CASE/m.json" "$CASE/e.json"
    check "$name(取れなかった出どころがあるときは、無いことの1行と取れなかった出どころの1行だけが出る)" "$(cat "$CASE/out.md")" \
        "直近7日に出た脆弱性は無い。(2026-10-29から2026-11-05まで)
$FAILED"
    jmod "$CASE/m.json" "$CASE/m2.json" '$d->{failed} = []'
    render "$CASE/m2.json" "$CASE/e.json"
    check "$name(取れなかった出どころも無いときは、無いことの1行だけが出る)" "$(cat "$CASE/out.md")" \
        '直近7日に出た脆弱性は無い。(2026-10-29から2026-11-05まで)'
}

# 見出しの下の行
case_header() {
    local name='見出しの下の行'
    newcase
    render
    check "$name(取れなかった出どころがあるときは、見出しの下に取れなかった出どころの1行が出る)" "$(top 3)" \
        "$TITLE
$FAILED
<空行>"
    jmod "$M" "$CASE/m.json" '$d->{failed} = []; $d->{github}{$_} = JSON::PP::false for qw(advisories_ok sbom_ok refs_ok); $d->{inventory}{fetched} = JSON::PP::false'
    render "$CASE/m.json"
    check "$name(GitHub を読めなかったものと、main を取り込めなかったことの行が出て、取れなかった出どころの行が出ない)" "$(top 4)" \
        "$TITLE
GitHub を読めなかったので、GitHub の勧告、backend の間接の依存、PR と Issue を調べていない。
main を取り込めなかったので、手元の main の写し(3e02dcc)の部品と比べた。
<空行>"
    jmod "$M" "$CASE/m.json" '$d->{failed} = []; $d->{github}{sbom_ok} = JSON::PP::false'
    render "$CASE/m.json"
    check "$name(偽のものだけを並べる)" "$(top 3)" \
        "$TITLE
GitHub を読めなかったので、backend の間接の依存を調べていない。
<空行>"
}

# すでに扱っている PR と Issue
case_refs() {
    local name='すでに扱っている PR と Issue'
    newcase
    render
    check "$name(番号を持つ1つ目の組の項目だけが行を持つ)" "$(grep '^- すでに扱っている' "$CASE/out.md")" \
        '- すでに扱っている PR と Issue: #801、#803
- すでに扱っている PR と Issue: #731、#802
- すでに扱っている PR と Issue: #740'
    jmod "$M" "$CASE/m.json" '$d->{github}{refs_ok} = JSON::PP::false'
    render "$CASE/m.json"
    check "$name(refs_ok が偽のときは、1つ目の組のどの項目も、PR と Issue を読めなかった文を持つ)" \
        "$(count '- すでに扱っている PR と Issue: PR と Issue を読めなかった') $(count '- すでに扱っている')" "7 7"
}

# 悪用の行と起きる被害の行
case_exploited() {
    local name='悪用の行'
    newcase
    render
    check "$name(kev を持つ項目と、exploited_note を持つ項目と、exploited が偽の項目が、3つの形になる)" \
        "$(block "$H_PG" | grep '^- 悪用'; block "$H_AXIOS" | grep '^- 悪用'; block "$H_SSH" | grep '^- 悪用')" \
        '- 悪用: 確かめられている(CISA の一覧に 2026-11-01 に載った)
- 悪用: 確かめられている(作り手が悪用を確かめた)
- 悪用: 確かめられていない'
    check "$name(1つ目と2つ目の組のどの項目も、起きる被害の行と悪用の行と元の発表の行を持つ)" \
        "$(count '- 起きる被害:') $(count '- 悪用:') $(count '- 元の発表:')" "9 9 9"
}

CASES='groups kinds others empty header refs exploited'

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
