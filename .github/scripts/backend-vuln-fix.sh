#!/usr/bin/env bash
# Dependabot が PR を作らない backend の部品の警告の、部品と修正版の組ごとに、libs.versions.toml の vuln-fix- の行に版を書く PR を作る。
# [libraries] の部品とプラグイン(Dependabot が上げる)、Dependabot の PR かブランチがある組、main が脆弱でない組は作らない。
# 行を書いても脆弱な版が残れば失敗で終える。修正版が公開から72時間未満なら、本番で動く部品の high か critical だけ作る。
# go_run は、Go 版の部品と標準ライブラリの脆弱性のうち、make vuln(govulncheck)が呼ばれる箇所を見つけたものを直す PR を作る。
# 部品は go get と go mod tidy で直し、標準ライブラリは go.mod の toolchain と golang のイメージの版を1つの PR で上げる。
# 使い方: backend-vuln-fix.sh run(GH_TOKEN と GITHUB_REPOSITORY が要る)か go_run(GH_TOKEN が要る)。ほかはテストが呼ぶ
set -euo pipefail
BACKEND=backend
CATALOG=$BACKEND/gradle/libs.versions.toml
plan() {
    local skip # 版の一覧の [libraries] の部品のうち、vuln-fix- の行でないもの
    skip=$(awk '/^\[/ { lib = ($0 == "[libraries]") }
        lib && !/^vuln-fix-/ && match($0, /module = "[^"]+"/) { print substr($0, RSTART + 10, RLENGTH - 11) }' "$2" |
        jq -Rsc 'split("\n") | map(select(. != ""))')
    jq --argjson skip "$skip" '[ .[] | if type == "array" then .[] else . end
          | select(.state == "open" and .dependency.package.ecosystem == "maven"
              and ((.dependency.manifest_path // "") | startswith("backend/"))
              and (.dependency.package.name | endswith(".gradle.plugin") or IN($skip[]) | not)
              and .security_vulnerability.first_patched_version.identifier != null) ]
        | group_by([.dependency.package.name, .security_vulnerability.first_patched_version.identifier])
        | map({ name: .[0].dependency.package.name,
                version: .[0].security_vulnerability.first_patched_version.identifier,
                ranges: (map(.security_vulnerability.vulnerable_version_range) | unique),
                urgent: any(.[]; .dependency.scope == "runtime"
                    and ((.security_advisory.severity // "") | ascii_downcase | IN("high", "critical"))),
                alerts: map({ html_url, severity: .security_advisory.severity, scope: .dependency.scope }) })' "$1"
}
# 警告の範囲(">= 11.0.0, < 11.0.28" の形)に版 $1 が入るか。版の大小は sort -V で比べる
in_range() {
    local cond op bound r conds
    IFS=',' read -ra conds <<<"$2"
    for cond in "${conds[@]}"; do
        cond="${cond// /}"; op="${cond%%[0-9]*}"; bound="${cond#"$op"}"
        if [ "$1" = "$bound" ]; then r=0
        elif [ "$(printf '%s\n%s\n' "$1" "$bound" | sort -V | head -n 1)" = "$1" ]; then r=-1
        else r=1; fi
        case "$op" in
            '<') [ "$r" -lt 0 ] ;; '<=') [ "$r" -le 0 ] ;; '>') [ "$r" -gt 0 ] ;;
            '>=') [ "$r" -ge 0 ] ;; '=' | '') [ "$r" -eq 0 ] ;; *) false ;;
        esac || return 1
    done
}
# Gradle の依存の木(dependencies と buildEnvironment の出力)から、解決した「<group:name> <版>」を出す。
# 解決していない宣言((n))と、解決先の無い版の制約({strictly …})は読まない
resolved() {
    sed -nE 's/^[| +\\-]*--- //p' "$1" | sed -E 's/ \([*c]\)$//' |
        awk '/ \(n\)$|^project / { next }
             { split($0, p, " -> "); split(p[1], c, ":"); v = (2 in p) ? p[2] : c[3]
               if (c[2] != "" && v != "" && v !~ /^\{/) print c[1] ":" c[2], v }' | LC_ALL=C sort -u
}
# 依存の木の <名前> の版のうち、範囲 $3 に入る版を出す。範囲を省くと組 $4 の範囲のどれかで見る。1つでもあれば 0
vulnerable() {
    local v range found=1
    while IFS= read -r v; do
        while IFS= read -r range; do
            if in_range "$v" "$range"; then echo "$v"; found=0; break; fi
        done < <(if [ -n "$3" ]; then echo "$3"; else jq -r '.ranges[]' <<<"$4"; fi)
    done < <(resolved "$1" | awk -v n="$2" '$1 == n { print $2 }')
    return "$found"
}
# 公開からの経過で、進める(go)・待たずに進める(urgent)・待つ(wait)を決める。$1 は Last-Modified の文字列
decide() {
    local t
    t=$(awk '{ m = index("JanFebMarAprMayJunJulAugSepOctNovDec", $3)
               if (m) printf "%s-%02d-%02d %s\n", $4, (m + 2) / 3, $2, $5 }' <<<"$1")
    if [ $(( ($2 - $(date -u -d "$t" +%s)) / 60 )) -ge 4320 ]; then echo go
    elif [ "$3" = true ]; then echo urgent
    else echo wait; fi
}
slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//'; }
# 版の一覧に部品 $2 の版 $3 を書く。行があれば版を置き換え、無ければ2つの印の行の下に足す。
# 名前の区切りは数字で始められない(Gradle の決まり)ので、数字の前の - を除く
pin() {
    local id tmp; tmp=$(mktemp); id="vuln-fix-$(slug "$2" | sed -E 's/-([0-9])/\1/g')"
    awk -v id="$id" -v m="$2" -v v="$3" '
        NR == FNR { if (index($0, id " = ") == 1) has = 1; next }
        index($0, id " = \"") == 1 { print id " = \"" v "\""; next }
        { print }
        /^# backend-vuln-fix\.yaml は、この下に vuln-fix- の行を足す$/ && !has && ++n == 1 { print id " = \"" v "\"" }
        /^# backend-vuln-fix\.yaml は、この下に vuln-fix- の行を足す$/ && !has && n == 2 {
            print id " = { module = \"" m "\", version.ref = \"" id "\" }" }' "$1" "$1" >"$tmp" && cat "$tmp" >"$1"
}
# 依存の木を書き出す。ビルドには GH_TOKEN を渡さない。解決に失敗した部品があれば 0 以外
tree() {
    (cd "$BACKEND" && env -u GH_TOKEN ./gradlew -q --console=plain dependencies buildEnvironment </dev/null) >"$1" &&
        ! grep -q ' FAILED' "$1"
}
# shellcheck disable=SC2016 # 本文の ` は Markdown の印であり、シェルの展開ではない
pr_body() {
    printf '## 概要\nDependabot が PR を作らない backend の部品 `%s` を、警告が消える `%s` 以上に上げる。\n' "$2" "$3"
    printf 'この PR は、定期実行のワークフロー backend-vuln-fix が `%s` の vuln-fix- の行を書いて作った。\n' "$CATALOG"
    [ "$4" != urgent ] || printf '修正版は公開から72時間経っていない。本番で動く部品の high か critical の警告なので、待たずに作った(dependency-cooldown が所有者の承認を求める)。\n'
    printf '\n## 消える警告\n'
    jq -r '.alerts[] | "- \(.html_url)(深刻度 \(.severity)、\(.scope // "scope 不明"))"' <<<"$1"
    printf '\nRefs: N/A\n'
}
run() {
    local alerts groups base after open group name ver branch path lm how title failed=0
    alerts=$(mktemp); base=$(mktemp); after=$(mktemp)
    gh api --paginate --slurp "repos/${GITHUB_REPOSITORY}/dependabot/alerts?state=open&ecosystem=maven&per_page=100" >"$alerts"
    groups=$(plan "$alerts" "$CATALOG" | jq -c '.[]')
    if [ -z "$groups" ]; then echo "PR を作る警告はありません。"; return 0; fi
    open=$(gh pr list --author app/dependabot --state open --limit 200 --json title --jq '.[].title')
    tree "$base" || { echo "::error::main の依存を解決できませんでした。"; return 1; }
    gh auth setup-git
    git config user.name "keirekipro-vuln-fix-bot" && git config user.email "vuln-fix-bot@users.noreply.github.com"
    while IFS= read -r group <&3; do
        name=$(jq -r .name <<<"$group"); ver=$(jq -r .version <<<"$group")
        branch="chore/backend-vuln-fix-$(slug "${name}-${ver}")"; title="chore: backend の ${name} を ${ver} 以上に上げる"
        git switch -q -f --detach origin/main
        if grep -qF " ${name} " <<<"$open" || git ls-remote --exit-code --heads origin "$branch" >/dev/null ||
            ! vulnerable "$base" "$name" "" "$group" >/dev/null; then
            echo "::notice::${name} ${ver}: Dependabot の PR かブランチ ${branch} があるか、main に脆弱な版が無いので作りません。"; continue; fi
        path="$(tr '.' '/' <<<"${name%%:*}")/${name##*:}/${ver}/${name##*:}-${ver}.pom"
        lm=$(curl -fsSI -L --max-time 20 "https://repo1.maven.org/maven2/${path}" | tr -d '\r' | sed -n 's/^[Ll]ast-[Mm]odified:[[:space:]]*//p' | tail -n 1) || lm=""
        if [ -z "$lm" ]; then echo "::error::${name} ${ver} の公開日時を読めませんでした。"; failed=1; continue; fi
        how=$(decide "$lm" "$(date +%s)" "$(jq -r .urgent <<<"$group")")
        if [ "$how" = wait ]; then echo "::notice::${name} ${ver} は公開から72時間経ってから作ります。"; continue; fi
        pin "$CATALOG" "$name" "$ver"
        if ! tree "$after" || vulnerable "$after" "$name" "" "$group" >/dev/null || git diff --quiet; then
            echo "::error::${name} を ${ver} 以上に上げられませんでした。手で直してください。"; failed=1; continue; fi
        git switch -q -c "$branch" && git add "$CATALOG"
        git commit -q -m "$title" -m "Changes:
- backend の部品 ${name} を、脆弱性の警告が消える ${ver} 以上に上げる
Reason:
- Dependabot が PR を作らない部品の警告を消すため(backend-vuln-fix が自動で作った)
BREAKING CHANGE: N/A
Related: N/A
Refs: N/A"
        git push -q -u origin "$branch" </dev/null || { failed=1; continue; }
        gh pr create --base main --head "$branch" --title "$title" \
            --body "$(pr_body "$group" "$name" "$ver" "$how")" </dev/null || failed=1
    done 3<<<"$groups"
    return "$failed"
}
# --- Go の仕事(go_run)----------------------------------------------------
# golang のイメージの版を上げる Dockerfile。PR 6-1 で docker/backend/ の Dockerfile だけにする(design.md)
GO_DOCKERFILES="docker/backend-go/Dockerfile docker/backend-go/Dockerfile.prod backend/compat/fakeaws/Dockerfile backend/compat/fakeoidc/Dockerfile"
# govulncheck の JSON(整形した JSON の並び)から、呼ばれる箇所のある脆弱性(trace[0] に function のある finding)を、
# 標準ライブラリと部品ごとにまとめ、直した版のうちいちばん新しい版を選ぶ。直した版の無い脆弱性は nofix に出す
go_plan() {
    jq -s 'def vkey: ltrimstr("v") | split("+")[0] | split("-") as $p
                | ($p[0] | split(".") | map(tonumber? // 0)) + [if ($p | length) > 1 then 0 else 1 end];
        def std: .trace[0].module | IN("stdlib", "toolchain");
        [ .[] | .finding? // empty | select(.trace[0].function != null) ] as $called
        | ($called | map(select(.fixed_version != null))) as $fix
        | { stdlib: ($fix | map(select(std))
                | if length == 0 then null
                  else { version: (map(.fixed_version) | max_by(vkey) | ltrimstr("v")), osv: (map(.osv) | unique) } end),
            modules: ($fix | map(select(std | not)) | group_by(.trace[0].module)
                | map({ module: .[0].trace[0].module, version: (map(.fixed_version) | max_by(vkey)), osv: (map(.osv) | unique) })),
            nofix: ($called | map(select(.fixed_version == null) | .osv) | unique) }' "$1"
}
# govulncheck の JSON を $1 に書く。go.mod の toolchain の行の Go で調べるため、GOTOOLCHAIN=auto にする
vulncheck() { (cd "$BACKEND" && env -u GH_TOKEN GOTOOLCHAIN=auto go tool govulncheck -format json ./... </dev/null) >"$1"; }
# イメージ $1 の digest(CPU ごとのイメージをまとめた索引の digest)を出す
digest() { docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' | jq -re '.digest | select(test("^sha256:[0-9a-f]{64}$"))'; }
# go.mod の toolchain の行と、Dockerfile の golang のイメージ(golang:<版>-<種類>@sha256:<digest>)を Go $1 にする。
# digest は種類ごとに1度だけ読む。toolchain の行が無いか、上げられない Dockerfile があれば 0 以外
go_bump() {
    local kinds kind d f
    grep -q '^toolchain go' "$BACKEND/go.mod" || return 1
    sed -i -E "s/^toolchain go[^ ]+\$/toolchain go$1/" "$BACKEND/go.mod"
    # shellcheck disable=SC2086 # GO_DOCKERFILES は空白で区切った一覧
    kinds=$(sed -nE 's/^FROM golang:[0-9.]+-([a-z0-9]+)@sha256:[0-9a-f]{64}( .*)?$/\1/p' $GO_DOCKERFILES | LC_ALL=C sort -u)
    for kind in $kinds; do
        d=$(digest "golang:$1-$kind") || return 1
        for f in $GO_DOCKERFILES; do
            sed -i -E "s/^FROM golang:[0-9.]+-$kind@sha256:[0-9a-f]{64}/FROM golang:$1-$kind@$d/" "$f"
        done
    done
    for f in $GO_DOCKERFILES; do
        grep -q "^FROM golang:$1-" "$f" && ! grep -E '^FROM golang:' "$f" | grep -qvF "FROM golang:$1-" || return 1
    done
}
# shellcheck disable=SC2016 # 本文の ` は Markdown の印であり、シェルの展開ではない
go_pr_body() {
    printf '## 概要\n%s。\n' "$2"
    printf 'この PR は、定期実行のワークフロー backend-vuln-fix の Go の仕事が、`make vuln`(govulncheck)で呼ばれる箇所のある脆弱性を見つけて作った。\n'
    printf '直した版が公開から72時間たっていなければ、公開の時刻の検査がこの PR を止める。そのときは、所有者が ci-tool-fast-update の決まりで扱いを決める。\n'
    printf '\n## 消える脆弱性\n'
    jq -r '.osv[] | "- https://pkg.go.dev/vuln/\(.)"' <<<"$1"
    printf '\nRefs: N/A\n'
}
# 直したあとに調べ直し、jq の式 $1 が真なら(脆弱性が消えていれば)、ブランチ $2 に題 $3 でコミットして PR を作る。
# $4 は直し方の説明、$5 は組の JSON。直せていないか、送れなければ 0 以外
go_ship() {
    local after; after=$(mktemp)
    if git diff --quiet || ! vulncheck "$after" || ! go_plan "$after" | jq -e "$1" >/dev/null; then
        echo "::error::$3 ができませんでした。手で直してください。"; return 1; fi
    git switch -q -c "$2" && git add -u && git commit -q -m "$3" -m "Changes:
- $4
Reason:
- 呼ばれる箇所のある Go の脆弱性を消すため(backend-vuln-fix の Go の仕事が自動で作った)
BREAKING CHANGE: N/A
Related: N/A
Refs: N/A" && git push -q -u origin "$2" </dev/null &&
        gh pr create --base main --head "$2" --title "$3" --body "$(go_pr_body "$5" "$4")" </dev/null
}
# ブランチ $1 があるか、題に部品 $2 の名前を含む Dependabot の PR があれば 0
go_exists() {
    { [ -n "$2" ] && grep -qF " $2 " <<<"$open"; } || git ls-remote --exit-code --heads origin "$1" >/dev/null
}
go_run() {
    local json plan open group mod ver branch title failed=0
    json=$(mktemp)
    if (cd "$BACKEND" && env -u GH_TOKEN GOTOOLCHAIN=auto make vuln </dev/null); then
        echo "呼ばれる箇所のある Go の脆弱性はありません。"; return 0; fi
    vulncheck "$json" || { echo "::error::govulncheck の JSON を読めませんでした。"; return 1; }
    plan=$(go_plan "$json")
    jq -r '.nofix[] | "::warning::\(.) は直した版が無いので、PR を作りません。"' <<<"$plan"
    if jq -e '.stdlib == null and (.modules | length) == 0' <<<"$plan" >/dev/null; then
        jq -e '.nofix | length > 0' <<<"$plan" >/dev/null && return 0
        echo "::error::make vuln が失敗しましたが、呼ばれる箇所のある脆弱性を読めませんでした。"; return 1; fi
    open=$(gh pr list --author app/dependabot --state open --limit 200 --json title --jq '.[].title')
    gh auth setup-git
    git config user.name "keirekipro-vuln-fix-bot" && git config user.email "vuln-fix-bot@users.noreply.github.com"
    group=$(jq -c '.stdlib // empty' <<<"$plan")
    if [ -n "$group" ]; then
        ver=$(jq -r .version <<<"$group"); branch="chore/backend-vuln-fix-go-stdlib-$(slug "$ver")"
        title="chore: backend の Go を ${ver} に上げる"
        if go_exists "$branch" ""; then echo "::notice::Go ${ver}: ブランチ ${branch} があるので作りません。"
        else
            git switch -q -f --detach origin/main
            if go_bump "$ver"; then
                go_ship '.stdlib == null' "$branch" "$title" \
                    "go.mod の toolchain と4つの Dockerfile の golang のイメージを Go ${ver} に上げ、標準ライブラリの脆弱性を消す" "$group" || failed=1
            else echo "::error::Go を ${ver} に上げられませんでした。手で直してください。"; failed=1; fi
        fi
    fi
    while IFS= read -r group <&3; do
        mod=$(jq -r .module <<<"$group"); ver=$(jq -r .version <<<"$group")
        branch="chore/backend-vuln-fix-go-$(slug "${mod}-${ver}")"; title="chore: backend の Go の部品 ${mod} を ${ver} 以上に上げる"
        if go_exists "$branch" "$mod"; then
            echo "::notice::${mod} ${ver}: Dependabot の PR かブランチ ${branch} があるので作りません。"; continue; fi
        git switch -q -f --detach origin/main
        if (cd "$BACKEND" && env -u GH_TOKEN GOTOOLCHAIN=auto go get "${mod}@${ver}" </dev/null &&
            env -u GH_TOKEN GOTOOLCHAIN=auto go mod tidy </dev/null); then
            go_ship "[.modules[] | select(.module == \"${mod}\")] | length == 0" "$branch" "$title" \
                "Go の部品 ${mod} を、go get と go mod tidy で ${ver} に上げ、脆弱性を消す" "$group" || failed=1
        else echo "::error::${mod} を ${ver} に上げられませんでした。手で直してください。"; failed=1; fi
    done 3< <(jq -c '.modules[]' <<<"$plan")
    return "$failed"
}
case "${1:-}" in
    run | go_run | plan | resolved | vulnerable | decide | pin | go_plan) "$@" ;;
    *) echo "使い方: backend-vuln-fix.sh run | go_run | plan | resolved | vulnerable | decide | pin | go_plan" >&2; exit 2 ;;
esac
