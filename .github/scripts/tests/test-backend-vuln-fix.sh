#!/usr/bin/env bash
# =====================================================================
# backend-vuln-fix.sh の自動テスト
#
# PR を作る run は gh・git・Gradle・Maven Central につながるので、ここでは流さない。
# run が使う判断の部品(警告の絞り込みとまとめ方、依存の木の読み方、脆弱な版の見つけ方、
# 72時間の判断、libs.versions.toml の書き換え)を、サブコマンドで1つずつ呼んで確かめる。
#
# Go の仕事の go_run は、本物の git(手元の bare のリポジトリを origin にする)と、
# make・go・gh・docker の代わりのスクリプトで、PR を作るまでを流して確かめる。
#
# 場合の名前を KP_TEST_CASE に入れると、その場合だけを流す(例: KP_TEST_CASE=go_stdlib_pr)。
# 名前は plan resolved decide pin usage go_plan go_module_pr go_stdlib_pr go_not_called go_unfixed。
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
    GO_REPO=$d/repo GO_ORIGIN=$d/origin.git GO_LOG=$d/log GO_FIX=$d/fix GO_STUB=$d/bin
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
    get) [ -n "${STUB_GET_NOOP:-}${STUB_KEEP_VULN:-}" ] || sed -i "s#golang.org/x/net v0.37.0#golang.org/x/net ${2#*@}#" go.mod ;;
    mod) [ -n "${STUB_GET_NOOP:-}" ] || echo "golang.org/x/net ${STUB_TIDY:-new} h1:new" >go.sum ;;
esac
EOF
    cat >"$GO_STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$GO_LOG"
if [ "$1 $2" = "pr list" ]; then printf '%s\n' "${STUB_OPEN_TITLES:-}"; fi
EOF
    cat >"$GO_STUB/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >>"$GO_LOG"
printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","digest":"%s","size":1}\n' "$DIGEST_NEW"
EOF
    chmod +x "$GO_STUB"/*
}
go_run() { # go_run を流し、出力を $GO_OUT、終了コードを $GO_RC に入れる
    GO_OUT=$(cd "$GO_REPO" && env PATH="$GO_STUB:$PATH" GO_LOG="$GO_LOG" GO_FIX="$GO_FIX" DIGEST_NEW="$DIGEST_NEW" \
        bash "$SCRIPT" go_run 2>&1)
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

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: 場合 ${CASE} がありません" >&2
    exit 1
fi

if [ "$FAILED" -ne 0 ]; then
    echo "test-backend-vuln-fix: 失敗があります" >&2
    exit 1
fi
echo "test-backend-vuln-fix: すべて成功"
