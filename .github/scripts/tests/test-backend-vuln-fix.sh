#!/usr/bin/env bash
# =====================================================================
# backend-vuln-fix.sh の自動テスト
#
# PR を作る run は gh・git・Gradle・Maven Central につながるので、ここでは流さない。
# run が使う判断の部品(警告の絞り込みとまとめ方、依存の木の読み方、脆弱な版の見つけ方、
# 72時間の判断、libs.versions.toml の書き換え)を、サブコマンドで1つずつ呼んで確かめる。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/backend-vuln-fix.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

ok() { echo "  ok: $1"; }
ng() { echo "  NG: $1" >&2; FAILED=1; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1(期待: [$3] 実際: [$2])"; fi; }

# --- plan ---------------------------------------------------------------
echo "plan: 警告の絞り込みとまとめ方"
alert() { # number name scope severity manifest range patched state ecosystem
    local fp='null'
    [ "$7" = none ] || fp="{\"identifier\":\"$7\"}"
    printf '{"number":%s,"state":"%s","html_url":"https://example.test/%s",
      "dependency":{"package":{"ecosystem":"%s","name":"%s"},"relationship":"direct","scope":%s,"manifest_path":"%s"},
      "security_advisory":{"severity":"%s"},
      "security_vulnerability":{"vulnerable_version_range":"%s","first_patched_version":%s}}' \
        "$1" "${8:-open}" "$1" "${9:-maven}" "$2" "$3" "$5" "$4" "$6" "$fp"
}
cat >"$WORK/catalog.toml" <<'EOF'
[versions]
java-jwt = "4.6.2"
vuln-fix-org-yaml-snakeyaml = "2.6"

[libraries]
java-jwt = { module = "com.auth0:java-jwt", version.ref = "java-jwt" }
vuln-fix-org-yaml-snakeyaml = { module = "org.yaml:snakeyaml", version.ref = "vuln-fix-org-yaml-snakeyaml" }

[plugins]
flyway = { id = "org.flywaydb.flyway", version.ref = "flyway" }
EOF
{
    printf '[['
    alert 1 org.apache.tomcat.embed:tomcat-embed-core '"runtime"' medium backend/settings.gradle '>= 11.0.0, < 11.0.28' 11.0.28; printf ','
    alert 2 org.apache.tomcat.embed:tomcat-embed-core '"runtime"' low backend/settings.gradle '< 11.0.28' 11.0.28; printf ','
    alert 3 com.auth0:java-jwt '"runtime"' high backend/settings.gradle '< 4.7.0' 4.7.0; printf ','
    alert 4 org.flywaydb.flyway:org.flywaydb.flyway.gradle.plugin null high backend/settings.gradle '< 14.0.0' 14.0.0; printf ','
    alert 5 closed:one '"runtime"' high backend/settings.gradle '< 2.0.0' 2.0.0 dismissed; printf '],['
    alert 6 front:end '"runtime"' high frontend/pnpm-lock.yaml '< 2.0.0' 2.0.0 open npm; printf ','
    alert 7 no:fix '"runtime"' critical backend/settings.gradle '< 9.9.9' none; printf ','
    alert 8 org.yaml:snakeyaml '"runtime"' HIGH backend/settings.gradle '< 2.7' 2.7; printf ','
    alert 9 dev:crit '"development"' critical backend/settings.gradle '< 3.0.0' 3.0.0; printf ','
    alert 10 no:scope null high backend/settings.gradle '< 5.0.0' 5.0.0
    printf ']]'
} >"$WORK/alerts.json"
if ! out=$(bash "$SCRIPT" plan "$WORK/alerts.json" "$WORK/catalog.toml"); then ng "plan が失敗した"; out='[]'; fi
expect_eq "対象の組だけが残る(版の一覧の部品・プラグイン・閉じた警告・frontend・修正版の無い警告は除く)" \
    "$(jq -c '[.[].name]' <<<"$out")" '["dev:crit","no:scope","org.apache.tomcat.embed:tomcat-embed-core","org.yaml:snakeyaml"]'
expect_eq "vuln-fix- の行の部品は除かない(行の版で足りなければ上げ直す)" "$(jq -c '[.[] | select(.name == "org.yaml:snakeyaml") | .version]' <<<"$out")" '["2.7"]'
expect_eq "同じ部品と修正版の警告は1つの組にまとまる" "$(jq -c '[.[] | select(.name | startswith("org.apache")) | .alerts | length]' <<<"$out")" '[2]'
expect_eq "組の範囲は重ねずに並ぶ" "$(jq -c '.[] | select(.name | startswith("org.apache")) | .ranges' <<<"$out")" '["< 11.0.28",">= 11.0.0, < 11.0.28"]'
expect_eq "本番で動く high は urgent(深刻度の大文字小文字を問わない)" "$(jq '.[] | select(.name == "org.yaml:snakeyaml") | .urgent' <<<"$out")" true
expect_eq "開発用の critical は urgent でない" "$(jq '.[] | select(.name == "dev:crit") | .urgent' <<<"$out")" false
expect_eq "scope の無い high は urgent でない" "$(jq '.[] | select(.name == "no:scope") | .urgent' <<<"$out")" false
expect_eq "本番で動く medium と low だけなら urgent でない" "$(jq '.[] | select(.name | startswith("org.apache")) | .urgent' <<<"$out")" false

# --- resolved / vulnerable ----------------------------------------------
echo "resolved と vulnerable: 依存の木の版"
cat >"$WORK/tree.txt" <<'EOF'

------------------------------------------------------------
Root project 'backend'
------------------------------------------------------------

productionRuntimeClasspath - Production runtime classpath of source set 'main'.
+--- org.springframework.boot:spring-boot-starter-webmvc -> 4.1.2
|    +--- org.apache.tomcat.embed:tomcat-embed-core -> 11.0.27
|    \--- org.yaml:snakeyaml:2.4 -> 2.6 (*)
+--- com.auth0:java-jwt:4.6.2
+--- project :shared
+--- io.netty:netty-codec-http2:{strictly 4.2.19.Final} -> 4.2.19.Final (c)
\--- com.google.guava:guava:{strictly 33.7.2-jre} (c)

checkstyle - The Checkstyle libraries to be used for this project.
\--- com.puppycrawl.tools:checkstyle:10.0
     +--- com.google.guava:guava:33.7.1-jre (n)
     \--- org.apache.tomcat.embed:tomcat-embed-core:10.1.0

classpath
\--- org.apache.commons:commons-lang3:3.16.0 -> 3.20.0
EOF
expect_eq "解決した版を読む(-> の先、無ければ宣言の版。(n) と解決先の無い制約は読まない)" "$(bash "$SCRIPT" resolved "$WORK/tree.txt" | tr '\n' '|')" \
    'com.auth0:java-jwt 4.6.2|com.puppycrawl.tools:checkstyle 10.0|io.netty:netty-codec-http2 4.2.19.Final|org.apache.commons:commons-lang3 3.20.0|org.apache.tomcat.embed:tomcat-embed-core 10.1.0|org.apache.tomcat.embed:tomcat-embed-core 11.0.27|org.springframework.boot:spring-boot-starter-webmvc 4.1.2|org.yaml:snakeyaml 2.6|'
vuln() { bash "$SCRIPT" vulnerable "$WORK/tree.txt" "$1" "$2" | tr '\n' ' '; }
expect_eq "範囲の中の版をすべて出す" "$(vuln org.apache.tomcat.embed:tomcat-embed-core '< 11.0.28')" '10.1.0 11.0.27 '
expect_eq "下限より古い版は出さない" "$(vuln org.apache.tomcat.embed:tomcat-embed-core '>= 11.0.0, < 11.0.28')" '11.0.27 '
expect_eq "上限ちょうどは範囲に入る" "$(vuln org.yaml:snakeyaml '<= 2.6')" '2.6 '
expect_eq "解決前の版(-> の前)は読まない" "$(vuln org.yaml:snakeyaml '< 2.5')" ''
expect_eq "Final の付いた版を比べる" "$(vuln io.netty:netty-codec-http2 '>= 4.2.0.Final, < 4.2.20.Final')" '4.2.19.Final '
expect_eq "名前が前方一致するだけの部品は数えない" "$(vuln com.auth0:java '< 9')" ''
if bash "$SCRIPT" vulnerable "$WORK/tree.txt" com.auth0:java-jwt '>= 4.7.0' >/dev/null; then
    ng "脆弱な版が無いのに 0 で終わった"
else ok "脆弱な版が無ければ 0 以外で終わる"; fi
if bash "$SCRIPT" vulnerable "$WORK/tree.txt" com.google.guava:guava '< 34' >/dev/null; then
    ng "解決していない guava を版として読んだ"
else ok "解決していない宣言と、解決先の無い制約の版は数えない"; fi
expect_eq "範囲を省くと、組の範囲のどれかに入る版を出す" \
    "$(bash "$SCRIPT" vulnerable "$WORK/tree.txt" org.apache.tomcat.embed:tomcat-embed-core '' '{"ranges":["< 10.1.5",">= 11.0.0, < 11.0.20"]}' | tr '\n' ' ')" '10.1.0 '

# --- decide -------------------------------------------------------------
echo "decide: 公開から72時間の判断"
now=$(date +%s)
lm() { # Last-Modified の形(英語の曜日と月)
    local d m
    d=$(date -u -d "@$1" '+%d %m %Y %H:%M:%S')
    m=$(echo "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec" | cut -d ' ' -f "$((10#${d:3:2}))")
    echo "Tue, ${d:0:2} ${m} ${d:6} GMT"
}
expect_eq "72時間を過ぎていれば進める" "$(bash "$SCRIPT" decide "$(lm $((now - 72 * 3600 - 60)))" "$now" false)" go
expect_eq "ちょうど72時間なら進める" "$(bash "$SCRIPT" decide "$(lm $((now - 72 * 3600)))" "$now" false)" go
expect_eq "72時間前で急がない警告なら待つ" "$(bash "$SCRIPT" decide "$(lm $((now - 71 * 3600)))" "$now" false)" wait
expect_eq "72時間前で本番の high か critical なら待たずに進める" "$(bash "$SCRIPT" decide "$(lm $((now - 3600)))" "$now" true)" urgent
expect_eq "12月の日付を読む(ちょうど72時間後)" "$(bash "$SCRIPT" decide 'Mon, 01 Dec 2025 00:00:00 GMT' "$(date -u -d '2025-12-04 00:00:00' +%s)" false)" go
expect_eq "12月の日付を読む(72時間の1秒前)" "$(bash "$SCRIPT" decide 'Mon, 01 Dec 2025 00:00:01 GMT' "$(date -u -d '2025-12-04 00:00:00' +%s)" false)" wait

# --- pin ----------------------------------------------------------------
echo "pin: libs.versions.toml の書き換え"
cat >"$WORK/base.toml" <<'EOF'
[versions]
guava = "33.7.2-jre"

# backend-vuln-fix.yaml は、この下に vuln-fix- の行を足す

[libraries]
java-jwt = { module = "com.auth0:java-jwt", version.ref = "java-jwt" }

# backend-vuln-fix.yaml は、この下に vuln-fix- の行を足す

[plugins]
EOF
cp "$WORK/base.toml" "$WORK/w.toml"
bash "$SCRIPT" pin "$WORK/w.toml" org.apache.tomcat.embed:tomcat-embed-core 11.0.28
expect_eq "版の行を [versions] の印の下に足す" "$(sed -n '5p' "$WORK/w.toml")" 'vuln-fix-org-apache-tomcat-embed-tomcat-embed-core = "11.0.28"'
expect_eq "部品の行を [libraries] の印の下に足す" "$(sed -n '11p' "$WORK/w.toml")" \
    'vuln-fix-org-apache-tomcat-embed-tomcat-embed-core = { module = "org.apache.tomcat.embed:tomcat-embed-core", version.ref = "vuln-fix-org-apache-tomcat-embed-tomcat-embed-core" }'
expect_eq "足した2行のほかは変えない" "$(grep -v '^vuln-fix-' "$WORK/w.toml" | cmp -s - "$WORK/base.toml" && echo same)" same
bash "$SCRIPT" pin "$WORK/w.toml" org.apache.tomcat.embed:tomcat-embed-core 11.0.30
expect_eq "行があれば版だけを置き換え、行を増やさない" "$(grep -c '^vuln-fix-' "$WORK/w.toml"):$(grep '^vuln-fix-[^ ]* = "' "$WORK/w.toml")" \
    '2:vuln-fix-org-apache-tomcat-embed-tomcat-embed-core = "11.0.30"'
cp "$WORK/base.toml" "$WORK/w.toml"
bash "$SCRIPT" pin "$WORK/w.toml" io.netty:netty-codec-http2 4.2.20.Final
bash "$SCRIPT" pin "$WORK/w.toml" Com.Example_X:lib-2 1.0
expect_eq "名前は小文字と - だけにし、数字で始まる区切りを作らない(Gradle の名前の決まり)" "$(grep -o '^vuln-fix-[a-z0-9-]* = "' "$WORK/w.toml" | tr '\n' '|')" \
    'vuln-fix-com-example-x-lib2 = "|vuln-fix-io-netty-netty-codec-http2 = "|'
expect_eq "後から足した行は印のすぐ下に入る" "$(sed -n '/^\[libraries\]/,$p' "$WORK/w.toml" | grep -A1 '^# backend' | sed -n 2p | cut -d ' ' -f 1)" vuln-fix-com-example-x-lib2

# --- 使い方 -------------------------------------------------------------
echo "使い方"
bash "$SCRIPT" unknown >/dev/null 2>&1
expect_eq "知らないサブコマンドは 2 で終わる" "$?" 2

if [ "$FAILED" -ne 0 ]; then
    echo "test-backend-vuln-fix: 失敗があります" >&2
    exit 1
fi
echo "test-backend-vuln-fix: すべて成功"
