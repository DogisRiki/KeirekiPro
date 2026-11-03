#!/usr/bin/env bash
# Dependabot が PR を作らない backend の部品の警告の、部品と修正版の組ごとに、libs.versions.toml の vuln-fix- の行に版を書く PR を作る。
# [libraries] の部品とプラグイン(Dependabot が上げる)、Dependabot の PR かブランチがある組、main が脆弱でない組は作らない。
# 行を書いても脆弱な版が残れば失敗で終える。修正版が公開から72時間未満なら、本番で動く部品の high か critical だけ作る。
# 使い方: backend-vuln-fix.sh run(GH_TOKEN と GITHUB_REPOSITORY が要る)。ほかはテストが呼ぶ
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
case "${1:-}" in
    run | plan | resolved | vulnerable | decide | pin) "$@" ;;
    *) echo "使い方: backend-vuln-fix.sh run | plan | resolved | vulnerable | decide | pin" >&2; exit 2 ;;
esac
