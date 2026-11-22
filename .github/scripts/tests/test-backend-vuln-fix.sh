#!/usr/bin/env bash
# =====================================================================
# backend-vuln-fix.sh の自動テスト
#
# run が使う判断の部品(警告の絞り込みとまとめ方、依存の木の読み方、脆弱な版の見つけ方、
# 72時間の判断、libs.versions.toml の書き換え)を、サブコマンドで1つずつ呼んで確かめる。
# PR を作る run は、gh・git・curl・gradlew を偽物に替えて流し、PR を作れなかった組を
# vuln-fix の結果のファイル(VULN_FIX_UNRESOLVED)に書くことと、Claude の変更のブランチが
# ある組で PR を作らないことを確かめる。
#
# Go の仕事の go_run は、本物の git(手元の bare のリポジトリを origin にする)と、
# make・go・gh・docker の代わりのスクリプトで、PR を作るまでを流して確かめる。
# 外から呼ぶ tree vulncheck go_bump digest も、同じ代わりのスクリプトで呼んで確かめる。
#
# 場合の名前を KP_TEST_CASE に入れると、その場合だけを流す(例: KP_TEST_CASE=go_stdlib_pr)。
# 名前は plan resolved decide pin run_unresolved run_claude usage go_plan go_module_pr go_stdlib_pr
# go_not_called go_unfixed go_unresolved go_claude callable。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/backend-vuln-fix.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
RAN=0

ok() { echo "  ok: $1"; }
ng() { echo "  NG: $1" >&2; FAILED=1; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1(期待: [$3] 実際: [$2])"; fi; }
want() { if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then RAN=$((RAN + 1)); return 0; fi; return 1; }

# --- plan ---------------------------------------------------------------
if want plan; then
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
fi

# --- resolved / vulnerable ----------------------------------------------
if want resolved; then
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
fi

# --- decide -------------------------------------------------------------
if want decide; then
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
fi

# --- pin ----------------------------------------------------------------
if want pin; then
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
fi

# --- run(Java 版の PR を作る処理)-----------------------------------------
# gh・git・curl と backend/gradlew を偽物に替え、環境変数で成功と失敗を選んで run を流す。
# 偽の gradlew は、libs.versions.toml に vuln-fix- の行があれば直した版の依存の木を出す
RUN_BIN=$WORK/run-bin
mkdir -p "$RUN_BIN"
cat >"$RUN_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE_LOG"
case "$1 $2" in
    "api "*) cat "$FAKE_ALERTS" ;;
    "pr list") ;;
    "auth setup-git") ;;
    "pr create") [ -z "${FAKE_PR_FAIL:-}" ] || exit 1 ;;
    *) exit 99 ;;
esac
EOF
cat >"$RUN_BIN/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"$FAKE_LOG"
case "$1" in
    ls-remote) for b in ${FAKE_REMOTE_BRANCHES:-}; do [ "$b" != "$5" ] || exit 0; done; exit 2 ;;
    diff) exit "${FAKE_DIFF_QUIET:-1}" ;;
    push) [ -z "${FAKE_PUSH_FAIL:-}" ] || exit 1 ;;
    config | switch | add | commit) ;;
    *) exit 99 ;;
esac
EOF
cat >"$RUN_BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"$FAKE_LOG"
[ -z "${FAKE_CURL_FAIL:-}" ] || exit 22
printf 'HTTP/2 200\r\nLast-Modified: Wed, 01 Jan 2020 00:00:00 GMT\r\n\r\n'
EOF
chmod +x "$RUN_BIN/gh" "$RUN_BIN/git" "$RUN_BIN/curl"
cat >"$WORK/run-gradlew" <<'EOF'
#!/usr/bin/env bash
echo "gradlew $*" >>"$FAKE_LOG"
pinned=0
! grep -q '^vuln-fix-com-example-lib = "1.0.1"$' gradle/libs.versions.toml || pinned=1
if [ "${FAKE_TREE_FAIL:-}" = base ] || { [ "${FAKE_TREE_FAIL:-}" = after ] && [ "$pinned" = 1 ]; }; then
    echo '+--- com.example:lib:1.0.0 FAILED'; exit 0; fi
echo 'productionRuntimeClasspath'
if [ "$pinned" = 1 ] && [ -z "${FAKE_KEEP_VULN:-}" ]; then echo '+--- com.example:lib:1.0.0 -> 1.0.1'
else echo '+--- com.example:lib:1.0.0'; fi
echo '\--- com.example:other:2.0.0'
EOF
run_alert() { # number name range patched
    printf '{"number":%s,"state":"open","html_url":"https://example.test/%s",
      "dependency":{"package":{"ecosystem":"maven","name":"%s"},"relationship":"transitive","scope":"runtime","manifest_path":"backend/build.gradle"},
      "security_advisory":{"severity":"medium"},
      "security_vulnerability":{"vulnerable_version_range":"%s","first_patched_version":{"identifier":"%s"}}}' "$1" "$1" "$2" "$3" "$4"
}
{ printf '[['; run_alert 1 com.example:lib '< 1.0.1' 1.0.1; printf ']]'; } >"$WORK/run-alerts.json"
{ printf '[['; run_alert 1 com.example:lib '< 1.0.1' 1.0.1; printf ','; run_alert 2 com.example:other '< 2.0.1' 2.0.1; printf ']]'; } >"$WORK/run-alerts2.json"
cat >"$WORK/run-catalog.toml" <<'EOF'
[versions]
# backend-vuln-fix.yaml は、この下に vuln-fix- の行を足す

[libraries]
# backend-vuln-fix.yaml は、この下に vuln-fix- の行を足す
EOF

# run_case <場合の名前> [<環境変数>=<値> ...]。終わり方を RC に、場合のフォルダを RD に入れる
run_case() {
    RD="$WORK/run-$1"; shift
    rm -rf "$RD"; mkdir -p "$RD/backend/gradle"
    cp "$WORK/run-catalog.toml" "$RD/backend/gradle/libs.versions.toml"
    cp "$WORK/run-gradlew" "$RD/backend/gradlew" && chmod +x "$RD/backend/gradlew"
    printf 'stale\n' >"$RD/unresolved.jsonl"
    (cd "$RD" && env PATH="$RUN_BIN:$PATH" GITHUB_REPOSITORY=owner/repo GH_TOKEN=dummy \
        FAKE_LOG="$RD/calls.log" FAKE_ALERTS="$WORK/run-alerts.json" \
        VULN_FIX_UNRESOLVED="$RD/unresolved.jsonl" "$@" bash "$SCRIPT" run >"$RD/out.txt" 2>&1)
    RC=$?
    touch "$RD/calls.log"
}
# expect_unresolved <場合の名前> <種類> <組の JSON> <止まった理由>。1行だけが書かれ、種類・組・理由が合うかを確かめる
expect_unresolved() {
    expect_eq "$1: 1 で終わる" "$RC" 1
    expect_eq "$1: 結果のファイルに1行だけが書かれる" "$(wc -l <"$RD/unresolved.jsonl" | tr -d ' ')" 1
    expect_eq "$1: 種類" "$(jq -r .kind "$RD/unresolved.jsonl" 2>/dev/null)" "$2"
    expect_eq "$1: 組は計画の組と同じ" "$(jq -cS .group "$RD/unresolved.jsonl" 2>/dev/null)" "$3"
    expect_eq "$1: 理由" "$(jq -r .reason "$RD/unresolved.jsonl" 2>/dev/null)" "$4"
}

if want run_unresolved; then
echo "run: PR を作れなかった組を結果のファイルに書く"
run_group=$(bash "$SCRIPT" plan "$WORK/run-alerts.json" "$WORK/run-catalog.toml" | jq -cS '.[0]')
run_case curl FAKE_CURL_FAIL=1
expect_unresolved "公開日時を読めない" maven "$run_group" "公開日時を読めなかった"
run_case keep FAKE_KEEP_VULN=1
expect_unresolved "上げても脆弱な版が残る" maven "$run_group" "警告が消える版に上げられなかった"
run_case after FAKE_TREE_FAIL=after
expect_unresolved "上げたあとの依存を解決できない" maven "$run_group" "警告が消える版に上げられなかった"
run_case push FAKE_PUSH_FAIL=1
expect_unresolved "push が失敗する" maven "$run_group" "ブランチを push できなかった"
run_case pr FAKE_PR_FAIL=1
expect_unresolved "PR を作れない" maven "$run_group" "PR を作れなかった"

run_case base FAKE_TREE_FAIL=base FAKE_ALERTS="$WORK/run-alerts2.json"
expect_eq "main の依存を解決できない: 1 で終わる" "$RC" 1
expect_eq "main の依存を解決できない: 計画したすべての組を書く" "$(jq -sc '[.[].group.name]' "$RD/unresolved.jsonl" 2>/dev/null)" '["com.example:lib","com.example:other"]'
expect_eq "main の依存を解決できない: 種類と理由" "$(jq -sc '[.[] | [.kind, .reason]] | unique' "$RD/unresolved.jsonl" 2>/dev/null)" '[["maven","main の依存を解決できなかった"]]'
expect_eq "main の依存を解決できない: 組は計画の組と同じ" "$(jq -cS -s '[.[].group]' "$RD/unresolved.jsonl" 2>/dev/null)" \
    "$(bash "$SCRIPT" plan "$WORK/run-alerts2.json" "$WORK/run-catalog.toml" | jq -cS '.')"

run_case ok
expect_eq "PR を作れた: 0 で終わる" "$RC" 0
expect_eq "PR を作れた: PR を1つ作る" "$(grep -c '^gh pr create' "$RD/calls.log")" 1
if [ -f "$RD/unresolved.jsonl" ] && [ ! -s "$RD/unresolved.jsonl" ]; then ok "PR を作れた: 結果のファイルは空で残る(前の中身を消す)"
else ng "PR を作れた: 結果のファイルが空でない: [$(cat "$RD/unresolved.jsonl" 2>/dev/null)]"; fi

run_case noenv FAKE_CURL_FAIL=1 VULN_FIX_UNRESOLVED=
expect_eq "VULN_FIX_UNRESOLVED が無い: 1 で終わる(書かずに今と同じに動く)" "$RC" 1
expect_eq "VULN_FIX_UNRESOLVED が無い: ファイルを書き換えない" "$(cat "$RD/unresolved.jsonl")" stale
fi

if want run_claude; then
echo "run: Claude の変更のブランチがある組で PR を作らない"
run_case claude FAKE_REMOTE_BRANCHES=fix/claude-auto-fix-backend-vuln-fix-com-example-lib-1-0-1
expect_eq "Claude の変更のブランチがある: 0 で終わる" "$RC" 0
expect_eq "Claude の変更のブランチがある: PR を作らない" "$(grep -c '^gh pr create' "$RD/calls.log")" 0
expect_eq "Claude の変更のブランチがある: 版の一覧を書き換えない" "$(grep -c '^vuln-fix-' "$RD/backend/gradle/libs.versions.toml")" 0
expect_eq "Claude の変更のブランチがある: 結果のファイルに書かない" "$(wc -c <"$RD/unresolved.jsonl" | tr -d ' ')" 0
run_case chore FAKE_REMOTE_BRANCHES=chore/backend-vuln-fix-com-example-lib-1-0-1
expect_eq "同じ組の vuln-fix のブランチがある: PR を作らない" "$RC:$(grep -c '^gh pr create' "$RD/calls.log")" 0:0
fi

# --- 使い方 -------------------------------------------------------------
if want usage; then
echo "使い方"
bash "$SCRIPT" unknown >/dev/null 2>&1
expect_eq "知らないサブコマンドは 2 で終わる" "$?" 2
fi

# --- Go の仕事 -----------------------------------------------------------
# govulncheck の JSON の finding を1つ出す。本物と同じく、複数行に整形した JSON を並べる。
# 呼ばれる箇所のある finding は trace[0] に function が入る。部品と package だけの finding は、呼ばれる箇所が無い
finding() { # osv module version fixed(none は直した版が無い) [package] [function]
    local fix='' pkg='' fn=''
    [ "$4" = none ] || fix="\"fixed_version\": \"$4\","
    [ -z "${5:-}" ] || pkg=",
        \"package\": \"$5\""
    [ -z "${6:-}" ] || fn=",
        \"function\": \"$6\""
    printf '{\n  "finding": {\n    "osv": "%s",\n    %s\n    "trace": [\n      {\n        "module": "%s",\n        "version": "%s"%s%s\n      }\n    ]\n  }\n}\n' \
        "$1" "$fix" "$2" "$3" "$pkg" "$fn"
}
config() { printf '{\n  "config": {\n    "scanner_name": "govulncheck",\n    "go_version": "go1.27.3",\n    "scan_level": "symbol"\n  }\n}\n'; }

if want go_plan; then
echo "go_plan: govulncheck の結果のまとめ方"
{
    config
    finding GO-2026-0001 stdlib v1.27.3 v1.27.4 net/http Serve
    finding GO-2026-0002 stdlib v1.27.3 v1.27.10 crypto/tls Conn.Read
    finding GO-2026-0002 stdlib v1.27.3 v1.27.10 crypto/tls
    finding GO-2026-0003 stdlib v1.27.3 v1.28.1
    finding GO-2026-0010 golang.org/x/net v0.37.0 v0.38.0 golang.org/x/net/http2 Server.ServeConn
    finding GO-2026-0011 golang.org/x/net v0.37.0 v0.39.0 golang.org/x/net/html Parse
    finding GO-2026-0012 golang.org/x/net v0.37.0 v0.45.0 golang.org/x/net/idna
    finding GO-2026-0020 gopkg.in/yaml.v3 v3.0.0 v3.0.1
    finding GO-2026-0030 golang.org/x/crypto v0.40.0 none golang.org/x/crypto/ssh Dial
} >"$WORK/govuln.json"
if ! out=$(bash "$SCRIPT" go_plan "$WORK/govuln.json"); then ng "go_plan が失敗した"; out='{}'; fi
expect_eq "標準ライブラリは、呼ばれる箇所のある脆弱性の直した版のうち、いちばん新しい版にする(1.27.10 は 1.27.4 より新しい)" \
    "$(jq -c '.stdlib' <<<"$out")" '{"version":"1.27.10","osv":["GO-2026-0001","GO-2026-0002"]}'
expect_eq "部品は部品ごとにまとめ、呼ばれる箇所の無い脆弱性(package だけ・部品だけ)は数えない" \
    "$(jq -c '.modules' <<<"$out")" '[{"module":"golang.org/x/net","version":"v0.39.0","osv":["GO-2026-0010","GO-2026-0011"]}]'
expect_eq "直した版の無い脆弱性は nofix に出す" "$(jq -c '.nofix' <<<"$out")" '["GO-2026-0030"]'
{ config; finding GO-2026-0003 stdlib v1.27.3 v1.28.1 net/http; finding GO-2026-0020 gopkg.in/yaml.v3 v3.0.0 v3.0.1; } >"$WORK/govuln-none.json"
expect_eq "呼ばれる箇所のある脆弱性が無ければ、直すものは無い" "$(bash "$SCRIPT" go_plan "$WORK/govuln-none.json" | jq -c '[.stdlib, .modules, .nofix]')" '[null,[],[]]'
fi

# go_run を、本物の git(手元の bare のリポジトリを origin にする)と、make・go・gh・docker の代わりのスクリプトで流す。
# 代わりの go は、作業フォルダの go.mod の版に合わせて、$GO_FIX の下の結果を出す(直せば消える)。
# 代わりのスクリプトは、呼ばれた引数を $GO_LOG に書く
GO_FILES="docker/backend-go/Dockerfile docker/backend-go/Dockerfile.prod backend/compat/fakeaws/Dockerfile backend/compat/fakeoidc/Dockerfile"
DIGEST_OLD="sha256:$(printf 'a%.0s' $(seq 64))"
DIGEST_NEW="sha256:$(printf 'b%.0s' $(seq 64))"
go_setup() { # 作業の名前
    local d=$WORK/$1 f
    GO_REPO=$d/repo GO_ORIGIN=$d/origin.git GO_LOG=$d/log GO_FIX=$d/fix GO_STUB=$d/bin GO_UNRESOLVED=$d/unresolved.jsonl
    mkdir -p "$GO_REPO/backend" "$GO_FIX" "$GO_STUB" && : >"$GO_LOG"
    git init -q --bare "$GO_ORIGIN"
    printf 'module example.test/backend\n\ngo 1.27.0\n\ntoolchain go1.27.3\n\nrequire golang.org/x/net v0.37.0\n' >"$GO_REPO/backend/go.mod"
    printf 'golang.org/x/net v0.37.0 h1:old\n' >"$GO_REPO/backend/go.sum"
    for f in $GO_FILES; do
        mkdir -p "$GO_REPO/$(dirname "$f")"
        printf 'FROM golang:1.27.3-trixie@%s AS builder\nRUN go build\nFROM gcr.io/distroless/static-debian13:nonroot@%s\n' "$DIGEST_OLD" "$DIGEST_OLD" >"$GO_REPO/$f"
    done
    printf 'FROM docker:29-cli@%s AS docker-cli\nFROM golang:1.27.3-trixie@%s\n' "$DIGEST_OLD" "$DIGEST_OLD" >"$GO_REPO/docker/backend-go/Dockerfile"
    (cd "$GO_REPO" && git init -q && git checkout -q -b main && git add -A &&
        git -c user.name=t -c user.email=t@example.test commit -q -m init &&
        git remote add origin "$GO_ORIGIN" && git push -q origin main && git fetch -q origin) || ng "作業のリポジトリを作れなかった"
    config >"$GO_FIX/always.json"
    finding GO-2026-0020 gopkg.in/yaml.v3 v3.0.0 v3.0.1 gopkg.in/yaml.v3 >>"$GO_FIX/always.json"
    : >"$GO_FIX/stdlib.json"
    : >"$GO_FIX/net.json"
    cat >"$GO_STUB/make" <<'EOF'
#!/usr/bin/env bash
echo "make $*" >>"$GO_LOG"
exit "${STUB_MAKE_RC:-2}"
EOF
    cat >"$GO_STUB/go" <<'EOF'
#!/usr/bin/env bash
echo "go $* (GOTOOLCHAIN=${GOTOOLCHAIN:-})" >>"$GO_LOG"
case "$1" in
    tool)
        cat "$GO_FIX/always.json"
        if grep -qx 'toolchain go1.27.3' go.mod; then cat "$GO_FIX/stdlib.json"; fi
        if grep -q 'golang.org/x/net v0.37.0' go.mod; then cat "$GO_FIX/net.json"; fi ;;
    get) [ -z "${STUB_GET_FAIL:-}" ] || exit 1; [ -n "${STUB_GET_NOOP:-}${STUB_KEEP_VULN:-}" ] || sed -i "s#golang.org/x/net v0.37.0#golang.org/x/net ${2#*@}#" go.mod ;;
    mod) [ -n "${STUB_GET_NOOP:-}" ] || echo "golang.org/x/net ${STUB_TIDY:-new} h1:new" >go.sum ;;
esac
EOF
    cat >"$GO_STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$GO_LOG"
if [ "$1 $2" = "pr list" ]; then printf '%s\n' "${STUB_OPEN_TITLES:-}"; fi
if [ "$1 $2" = "pr create" ] && [ -n "${STUB_PR_FAIL:-}" ]; then exit 1; fi
EOF
    cat >"$GO_STUB/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >>"$GO_LOG"
[ -z "${STUB_DOCKER_FAIL:-}" ] || exit 1
printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","digest":"%s","size":1}\n' "$DIGEST_NEW"
EOF
    chmod +x "$GO_STUB"/*
}
go_run() { # go_run を流し、出力を $GO_OUT、終了コードを $GO_RC に入れる
    GO_OUT=$(cd "$GO_REPO" && env PATH="$GO_STUB:$PATH" GO_LOG="$GO_LOG" GO_FIX="$GO_FIX" DIGEST_NEW="$DIGEST_NEW" \
        VULN_FIX_UNRESOLVED="$GO_UNRESOLVED" bash "$SCRIPT" go_run 2>&1)
    GO_RC=$?
}
branches() { git --git-dir="$GO_ORIGIN" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' '; }
changed() { git --git-dir="$GO_ORIGIN" diff --name-only main "$1" | tr '\n' ' '; }
shown() { git --git-dir="$GO_ORIGIN" show "$1:$2"; }
prs() { grep -c '^gh pr create' "$GO_LOG"; }

if want go_module_pr; then
echo "go_run: Go の部品の脆弱性で go get の PR を作る"
go_setup go-module
finding GO-2026-0010 golang.org/x/net v0.37.0 v0.38.0 golang.org/x/net/http2 Server.ServeConn >"$GO_FIX/net.json"
go_run
expect_eq "PR を作って 0 で終わる" "$GO_RC" 0
expect_eq "部品と直した版の名前のブランチを送る(標準ライブラリのブランチは作らない)" "$(branches)" 'chore/backend-vuln-fix-go-golang-org-x-net-v0-38-0 main '
expect_eq "go get と go mod tidy で直す" "$(grep -c -e '^go get golang.org/x/net@v0.38.0 ' -e '^go mod tidy ' "$GO_LOG")" 2
expect_eq "変えるのは go.mod と go.sum だけ" "$(changed chore/backend-vuln-fix-go-golang-org-x-net-v0-38-0)" 'backend/go.mod backend/go.sum '
expect_eq "go.mod の部品の版が上がる" "$(shown chore/backend-vuln-fix-go-golang-org-x-net-v0-38-0 backend/go.mod | grep -c 'golang.org/x/net v0.38.0')" 1
expect_eq "PR を1つ作る" "$(prs)" 1
expect_eq "PR の題に部品と直した版を書く" "$(grep -cF -- '--title chore: backend の Go の部品 golang.org/x/net を v0.38.0 以上に上げる' "$GO_LOG")" 1
expect_eq "PR の本文に消える脆弱性を書く" "$(grep -cF 'https://pkg.go.dev/vuln/GO-2026-0010' "$GO_LOG")" 1
expect_eq "直したあとに、toolchain の行の Go で調べ直す" "$(grep -c '^go tool govulncheck -format json ./... (GOTOOLCHAIN=auto)$' "$GO_LOG")" 2
git -C "$GO_REPO" switch -q -f main # 本物の仕事は、毎回 main を取り出し直してから動く
go_run
expect_eq "ブランチがあれば、もう1度は作らない" "$GO_RC:$(prs)" 0:1
go_setup go-module-dependabot
finding GO-2026-0010 golang.org/x/net v0.37.0 v0.38.0 golang.org/x/net/http2 Server.ServeConn >"$GO_FIX/net.json"
STUB_OPEN_TITLES='chore(deps): bump golang.org/x/net from 0.37.0 to 0.38.0 in /backend' go_run
expect_eq "Dependabot の PR があれば作らない" "$GO_RC:$(prs):$(branches)" '0:0:main '
fi

if want go_stdlib_pr; then
echo "go_run: 標準ライブラリの脆弱性で toolchain と4つの Dockerfile を上げる"
go_setup go-stdlib
{
    finding GO-2026-0001 stdlib v1.27.3 v1.27.4 net/http Serve
    finding GO-2026-0002 stdlib v1.27.3 v1.27.4 crypto/tls Conn.Read
} >"$GO_FIX/stdlib.json"
go_run
stdlib_branch=chore/backend-vuln-fix-go-stdlib-1-27-4
expect_eq "PR を作って 0 で終わる" "$GO_RC" 0
expect_eq "Go の版の名前のブランチを送る" "$(branches)" "$stdlib_branch main "
expect_eq "go.mod と4つの Dockerfile を1つのブランチで変える" "$(changed "$stdlib_branch")" \
    'backend/compat/fakeaws/Dockerfile backend/compat/fakeoidc/Dockerfile backend/go.mod docker/backend-go/Dockerfile docker/backend-go/Dockerfile.prod '
expect_eq "go.mod の toolchain を上げる" "$(shown "$stdlib_branch" backend/go.mod | grep '^toolchain')" 'toolchain go1.27.4'
for f in $GO_FILES; do
    expect_eq "$f の golang のイメージを、新しい版とその digest にする" "$(shown "$stdlib_branch" "$f" | grep -c "^FROM golang:1.27.4-trixie@${DIGEST_NEW}\( AS builder\)\?$")" 1
    expect_eq "$f の golang でないイメージは変えない" "$(shown "$stdlib_branch" "$f" | grep -c "^FROM .*@${DIGEST_OLD}")" 1
done
expect_eq "digest は新しい版のイメージから1度だけ読む" "$(grep '^docker ' "$GO_LOG")" "docker buildx imagetools inspect golang:1.27.4-trixie --format {{json .Manifest}}"
expect_eq "PR を1つ作り、題に Go の版を書く" "$(prs):$(grep -cF -- '--title chore: backend の Go を 1.27.4 に上げる' "$GO_LOG")" 1:1
expect_eq "PR の本文に消える脆弱性を書く" "$(grep -cF -e 'https://pkg.go.dev/vuln/GO-2026-0001' -e 'https://pkg.go.dev/vuln/GO-2026-0002' "$GO_LOG")" 2
expect_eq "部品の go get は動かさない" "$(grep -c '^go get' "$GO_LOG")" 0
fi

if want go_not_called; then
echo "go_run: 呼ばれる箇所の無い脆弱性では PR を作らない"
go_setup go-not-called
STUB_MAKE_RC=0 go_run
expect_eq "make vuln が成功すれば、0 で終わる" "$GO_RC" 0
expect_eq "make vuln を動かす" "$(grep -c '^make vuln$' "$GO_LOG")" 1
expect_eq "make vuln が成功すれば、JSON の検査も PR も作らない" "$(grep -c -e '^go ' -e '^gh ' "$GO_LOG"):$(branches)" '0:main '
go_setup go-not-called-json
go_run
expect_eq "make vuln が失敗したのに直すものが無ければ、失敗で終える" "$GO_RC" 1
expect_eq "そのときも PR とブランチを作らない" "$(prs):$(branches)" '0:main '
fi

if want go_unfixed; then
echo "go_run: 直せなかったとき"
go_setup go-unfixed
finding GO-2026-0010 golang.org/x/net v0.37.0 v0.38.0 golang.org/x/net/http2 Server.ServeConn >"$GO_FIX/net.json"
finding GO-2026-0001 stdlib v1.27.3 v1.27.4 net/http Serve >"$GO_FIX/stdlib.json"
STUB_GET_NOOP=1 go_run
expect_eq "部品を直せなければ失敗で終える" "$GO_RC" 1
expect_eq "直せなかった部品の PR は作らず、ほかの組(標準ライブラリ)の PR は作る" "$(prs):$(branches)" '1:chore/backend-vuln-fix-go-stdlib-1-27-4 main '
go_setup go-still-vulnerable
finding GO-2026-0010 golang.org/x/net v0.37.0 v0.38.0 golang.org/x/net/http2 Server.ServeConn >"$GO_FIX/net.json"
STUB_KEEP_VULN=1 go_run # go.sum だけが変わり、部品の版は上がらない
expect_eq "差分はできても、調べ直して脆弱性が残っていれば、PR を作らずに失敗で終える" "$GO_RC:$(prs):$(branches)" '1:0:main '
go_setup go-nofix
{ finding GO-2026-0030 golang.org/x/crypto v0.40.0 none golang.org/x/crypto/ssh Dial; } >"$GO_FIX/net.json"
go_run
expect_eq "直した版の無い脆弱性だけなら、警告を出して 0 で終える" "$GO_RC:$(prs):$(grep -c 'GO-2026-0030' <<<"$GO_OUT")" 0:0:1
fi

unresolved_lines() { if [ -f "$GO_UNRESOLVED" ]; then wc -l <"$GO_UNRESOLVED" | tr -d ' '; else echo none; fi; }
unresolved_of() { jq -r "$1" "$GO_UNRESOLVED" 2>/dev/null; }

if want go_unresolved; then
echo "go_run: PR を作れなかった組を結果のファイルに書く"
std_group='{"osv":["GO-2026-0001","GO-2026-0002"],"version":"1.27.4"}'
mod_group='{"module":"golang.org/x/net","osv":["GO-2026-0010"],"version":"v0.38.0"}'
std_findings() {
    finding GO-2026-0001 stdlib v1.27.3 v1.27.4 net/http Serve
    finding GO-2026-0002 stdlib v1.27.3 v1.27.4 crypto/tls Conn.Read
}
go_setup go-unresolved-bump
std_findings >"$GO_FIX/stdlib.json"
STUB_DOCKER_FAIL=1 go_run
expect_eq "Go の版を上げられない: 1 で終わり、1行だけ書く" "$GO_RC:$(unresolved_lines)" 1:1
expect_eq "Go の版を上げられない: 種類と理由" "$(unresolved_of '[.kind, .reason] | join(":")')" "go-stdlib:Go の版を上げられなかった"
expect_eq "Go の標準ライブラリの組を1行にまとめる(組は go_plan の stdlib)" "$(jq -cS .group "$GO_UNRESOLVED" 2>/dev/null)" "$std_group"
go_setup go-unresolved-std-ship
std_findings >"$GO_FIX/stdlib.json"
STUB_PR_FAIL=1 go_run
expect_eq "Go を上げた変更を PR にできない: 1 で終わり、1行だけ書く" "$GO_RC:$(unresolved_lines)" 1:1
expect_eq "Go を上げた変更を PR にできない: 種類と理由" "$(unresolved_of '[.kind, .reason] | join(":")')" "go-stdlib:Go を上げた変更を PR にできなかった"
expect_eq "Go を上げた変更を PR にできない: 組" "$(jq -cS .group "$GO_UNRESOLVED" 2>/dev/null)" "$std_group"
go_setup go-unresolved-get
finding GO-2026-0010 golang.org/x/net v0.37.0 v0.38.0 golang.org/x/net/http2 Server.ServeConn >"$GO_FIX/net.json"
STUB_GET_FAIL=1 go_run
expect_eq "go get が失敗する: 1 で終わり、1行だけ書く" "$GO_RC:$(unresolved_lines)" 1:1
expect_eq "go get が失敗する: 種類と理由" "$(unresolved_of '[.kind, .reason] | join(":")')" "go-module:go get か go mod tidy が失敗した"
expect_eq "go get が失敗する: 組は go_plan の modules の組" "$(jq -cS .group "$GO_UNRESOLVED" 2>/dev/null)" "$mod_group"
go_setup go-unresolved-mod-ship
finding GO-2026-0010 golang.org/x/net v0.37.0 v0.38.0 golang.org/x/net/http2 Server.ServeConn >"$GO_FIX/net.json"
STUB_GET_NOOP=1 go_run
expect_eq "部品を上げた変更を PR にできない: 1 で終わり、1行だけ書く" "$GO_RC:$(unresolved_lines)" 1:1
expect_eq "部品を上げた変更を PR にできない: 種類と理由" "$(unresolved_of '[.kind, .reason] | join(":")')" "go-module:部品を上げた変更を PR にできなかった"
expect_eq "部品を上げた変更を PR にできない: 組" "$(jq -cS .group "$GO_UNRESOLVED" 2>/dev/null)" "$mod_group"
go_setup go-unresolved-ok
finding GO-2026-0010 golang.org/x/net v0.37.0 v0.38.0 golang.org/x/net/http2 Server.ServeConn >"$GO_FIX/net.json"
std_findings >"$GO_FIX/stdlib.json"
printf 'stale\n' >"$GO_UNRESOLVED"
go_run
expect_eq "PR を作れた: 0 で終わり、結果のファイルを空にする" "$GO_RC:$(prs):$(unresolved_lines)" 0:2:0
go_setup go-unresolved-noread
go_run # make vuln が失敗したのに、呼ばれる箇所のある脆弱性を読めない(組を読む前に止まる)
expect_eq "組を読む前に止まれば、1 で終わり、書かない" "$GO_RC:$(unresolved_lines)" 1:0
fi

if want go_claude; then
echo "go_run: Claude の変更のブランチがある組で PR を作らない"
go_setup go-claude
finding GO-2026-0010 golang.org/x/net v0.37.0 v0.38.0 golang.org/x/net/http2 Server.ServeConn >"$GO_FIX/net.json"
finding GO-2026-0001 stdlib v1.27.3 v1.27.4 net/http Serve >"$GO_FIX/stdlib.json"
git --git-dir="$GO_ORIGIN" branch fix/claude-auto-fix-backend-vuln-fix-go-stdlib-1-27-4 main
git --git-dir="$GO_ORIGIN" branch fix/claude-auto-fix-backend-vuln-fix-go-golang-org-x-net-v0-38-0 main
go_run
expect_eq "Claude の変更のブランチがある: 0 で終わる" "$GO_RC" 0
expect_eq "Claude の変更のブランチがある: PR もブランチも作らない" "$(prs):$(branches)" \
    '0:fix/claude-auto-fix-backend-vuln-fix-go-golang-org-x-net-v0-38-0 fix/claude-auto-fix-backend-vuln-fix-go-stdlib-1-27-4 main '
expect_eq "Claude の変更のブランチがある: go get も digest の読み取りもしない" "$(grep -c -e '^go get' -e '^docker ' "$GO_LOG")" 0
expect_eq "Claude の変更のブランチがある: 結果のファイルに書かない" "$(unresolved_lines)" 0
fi

if want callable; then
echo "tree vulncheck go_bump digest を引数で呼べる"
go_setup callable
out=$(cd "$GO_REPO" && env PATH="$GO_STUB:$PATH" GO_LOG="$GO_LOG" DIGEST_NEW="$DIGEST_NEW" bash "$SCRIPT" digest golang:1.27.4-trixie)
expect_eq "digest: イメージの digest を出す" "$?:$out" "0:$DIGEST_NEW"
(cd "$GO_REPO" && env PATH="$GO_STUB:$PATH" GO_LOG="$GO_LOG" DIGEST_NEW="$DIGEST_NEW" bash "$SCRIPT" go_bump 1.27.4)
expect_eq "go_bump: 0 で終わり、toolchain の行を上げる" "$?:$(grep '^toolchain' "$GO_REPO/backend/go.mod")" "0:toolchain go1.27.4"
expect_eq "go_bump: Dockerfile の golang のイメージを上げる" "$(grep -c "^FROM golang:1.27.4-trixie@${DIGEST_NEW}" "$GO_REPO/docker/backend-go/Dockerfile.prod")" 1
finding GO-2026-0010 golang.org/x/net v0.37.0 v0.38.0 golang.org/x/net/http2 Server.ServeConn >"$GO_FIX/net.json"
(cd "$GO_REPO" && env PATH="$GO_STUB:$PATH" GO_LOG="$GO_LOG" GO_FIX="$GO_FIX" bash "$SCRIPT" vulncheck "$WORK/callable-vuln.json")
expect_eq "vulncheck: 0 で終わり、govulncheck の JSON を書く" "$?:$(bash "$SCRIPT" go_plan "$WORK/callable-vuln.json" | jq -r '.modules[0].module')" "0:golang.org/x/net"
mkdir -p "$WORK/callable-tree/backend/gradle"
cp "$WORK/run-catalog.toml" "$WORK/callable-tree/backend/gradle/libs.versions.toml"
cp "$WORK/run-gradlew" "$WORK/callable-tree/backend/gradlew" && chmod +x "$WORK/callable-tree/backend/gradlew"
(cd "$WORK/callable-tree" && FAKE_LOG="$WORK/callable-tree/log" bash "$SCRIPT" tree "$WORK/callable-tree.txt")
expect_eq "tree: 0 で終わり、依存の木を書く" "$?:$(bash "$SCRIPT" resolved "$WORK/callable-tree.txt" | tr '\n' '|')" "0:com.example:lib 1.0.0|com.example:other 2.0.0|"
(cd "$WORK/callable-tree" && FAKE_LOG="$WORK/callable-tree/log" FAKE_TREE_FAIL=base bash "$SCRIPT" tree "$WORK/callable-tree.txt")
expect_eq "tree: 解決に失敗した部品があれば 0 以外で終わる" "$?" 1
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: 場合 ${CASE} がありません" >&2
    exit 1
fi

if [ "$FAILED" -ne 0 ]; then
    echo "test-backend-vuln-fix: 失敗があります" >&2
    exit 1
fi
echo "test-backend-vuln-fix: すべて成功"
