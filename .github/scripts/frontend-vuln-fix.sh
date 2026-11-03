#!/usr/bin/env bash
# =====================================================================
# Dependabot が PR を作らない frontend の間接依存の警告について、警告が消える版に
# 上げる PR を、部品と最初の修正版の組ごとに作る(frontend-vuln-fix.yaml から呼ばれる)
#   1. pnpm update <名前> で lockfile だけを直す(使っている側の範囲の中で上げる)
#   2. 脆弱な版が残れば overrides に版の指定を足す(dependency-gate が所有者の承認を求める)
#   3. それでも残れば PR を作らず、失敗で終える
#   4. ci.yaml の frontend-test と同じ検査を流し、通らなければ PR を作らず、消せなかった警告を
#      実行の記録に出して失敗で終える(overrides が、ほかの部品が使う古い版まで置き換えることがある)
# 同じ組のブランチが origin にあれば作らない。修正版が公開から72時間経っていないときは、
# 本番で動く部品の high か critical の警告なら minimumReleaseAgeExclude に足して進み、
# それ以外は経ってからの実行に回す(pnpm-workspace.yaml の minimumReleaseAge の決まり)。
# 使い方: frontend-vuln-fix.sh run(GH_TOKEN と GITHUB_REPOSITORY が要る)。ほかはテストが呼ぶ
# =====================================================================
set -euo pipefail

FRONTEND=frontend
# ci.yaml の frontend-test が流す pnpm のコマンドを、同じ順に並べる(そろっていることはテストが確かめる)
FRONTEND_TEST=("install --frozen-lockfile" "run format" "run lint" "test" "run coverage" "run build")

plan() {
    jq '[ .[] | if type == "array" then .[] else . end
          | select(.state == "open" and .dependency.package.ecosystem == "npm"
              and ((.dependency.manifest_path // "") | startswith("frontend/"))
              and .dependency.relationship != "direct"
              and .security_vulnerability.first_patched_version.identifier != null) ]
        | group_by([.dependency.package.name, .security_vulnerability.first_patched_version.identifier])
        | map({ name: .[0].dependency.package.name,
                version: .[0].security_vulnerability.first_patched_version.identifier,
                ranges: (map(.security_vulnerability.vulnerable_version_range) | unique),
                urgent: any(.[]; .dependency.scope == "runtime"
                    and ((.security_advisory.severity // "") | ascii_downcase | IN("high", "critical"))),
                alerts: map({ html_url, severity: .security_advisory.severity, scope: .dependency.scope }) })' "$1"
}

# 警告の範囲(">= 6.7.0, <= 6.16.0" の形)に版 $1 が入るか。版の大小は sort -V で比べる
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

# lockfile の packages: より後ろの <名前>@<版> のうち、範囲に入る版を出す。1つでもあれば 0
vulnerable() {
    local v found=1
    while IFS= read -r v; do
        if in_range "$v" "$3"; then echo "$v"; found=0; fi
    done < <(awk -v n="$2" -v q="'" 'f && (index($0, "  " n "@") == 1 || index($0, "  " q n "@") == 1) {
                 s = substr($0, index($0, n "@") + length(n) + 1); sub(/[(:'"'"'].*/, "", s); print s }
             /^packages:/ { f = 1 }' "$1" | sort -u)
    return "$found"
}

# 公開からの経過で、進める(go)・例外に足して進める(exclude)・待つ(wait)を決める
decide() {
    local t="${1%%.*}"; t="${t%Z}"
    if [ $(( ($2 - $(date -u -d "${t/T/ }" +%s)) / 60 )) -ge 4320 ]; then echo go
    elif [ "$3" = true ]; then echo exclude
    else echo wait; fi
}

# 修正版のメジャーのキー(qs@6 など)があれば値を置き換え、無ければ警告の範囲のキーを足す
override() {
    local range tmp; tmp=$(mktemp)
    range=$(sed -E 's/, */ /g; s/([<>=]+) +/\1/g' <<<"$4")
    awk -v k="$2@${3%%.*}" -v add="  \"$2@${range}\": \"^$3\"" -v val=" \"^$3\"" '
        { key = $0; sub(/:.*/, "", key); gsub(/^ +|["'"'"']/, "", key) }
        NR == FNR { if (/^overrides:/) inov = 1; else if (/^[^ #]/) inov = 0
                    if (inov && /^  [^ #]/ && key == k) has = 1; next }
        /^overrides:/ { inov = 1; print; if (!has) print add; done = 1; next }
        /^[^ #]/ { inov = 0 }
        inov && /^  [^ #]/ && key == k { print substr($0, 1, index($0, ":")) val; next }
        { print }
        END { if (!done) { print "overrides:"; print add } }' "$1" "$1" >"$tmp" && cat "$tmp" >"$1"
}

# minimumReleaseAgeExclude のキーの下に足す。キーが無ければ minimumReleaseAge の下に作る
exclude() {
    local tmp has; has=$(grep -c '^minimumReleaseAgeExclude:' "$1" || true)
    tmp=$(mktemp)
    awk -v item="  - '$2'" -v has="$has" '{ print }
        /^minimumReleaseAgeExclude:/ || (/^minimumReleaseAge:/ && !has) {
            if (!has) print "minimumReleaseAgeExclude:"; print item; done = 1 }
        END { if (!done) { print "minimumReleaseAgeExclude:"; print item } }' "$1" >"$tmp" && cat "$tmp" >"$1"
}

still_vulnerable() {
    local range
    while IFS= read -r range; do
        vulnerable "$FRONTEND/pnpm-lock.yaml" "$1" "$range" >/dev/null && return 0
    done < <(jq -r '.ranges[]' <<<"$2")
    return 1
}

# frontend-test と同じ検査を流す。1つでも失敗すればそこで止め、0 以外で終わる。
# 部品のスクリプトに bot の PAT を渡さないよう、GH_TOKEN を外して呼ぶ
frontend_test() {
    local c args
    for c in "${FRONTEND_TEST[@]}"; do
        read -ra args <<<"$c"
        echo "::group::pnpm ${c}"
        if ! env -u GH_TOKEN pnpm --dir "$FRONTEND" "${args[@]}" </dev/null; then echo "::endgroup::"; return 1; fi
        echo "::endgroup::"
    done
}

# shellcheck disable=SC2016 # 本文の ` は Markdown の印であり、シェルの展開ではない
pr_body() {
    printf '## 概要\nDependabot が PR を作らない frontend の間接依存 `%s` を、警告が消える `%s` 以上に上げる。\n' "$2" "$3"
    printf 'この PR は、定期実行のワークフロー frontend-vuln-fix が自動で作った。\n\n## 変えたこと\n'
    git diff --name-only HEAD~1 | sed 's/^/- `/; s/$/`/'
    git diff --quiet HEAD~1 -- "$FRONTEND/pnpm-workspace.yaml" || printf -- '- `pnpm-workspace.yaml` を変えたので、マージの前に所有者の承認が要る\n'
    [ "$4" != exclude ] || printf -- '- 修正版が公開から72時間経っていないので `minimumReleaseAgeExclude` に足した(本番で動く部品の high か critical の警告)\n'
    printf '\n## 消える警告\n'
    jq -r '.alerts[] | "- \(.html_url)(深刻度 \(.severity)、\(.scope // "scope 不明"))"' <<<"$1"
    printf '\nRefs: N/A\n'
}

run() {
    local alerts group name ver branch published how range title failed=0
    alerts=$(mktemp)
    gh api --paginate --slurp "repos/${GITHUB_REPOSITORY}/dependabot/alerts?state=open&ecosystem=npm&per_page=100" >"$alerts"
    gh auth setup-git
    git config user.name "keirekipro-vuln-fix-bot" && git config user.email "vuln-fix-bot@users.noreply.github.com"
    while IFS= read -r group <&3; do
        name=$(jq -r .name <<<"$group"); ver=$(jq -r .version <<<"$group")
        branch="chore/frontend-vuln-fix-$(printf '%s-%s' "$name" "$ver" | tr -c 'a-z0-9' '-' | sed -E 's/-+/-/g; s/^-//')"
        title="chore: frontend の ${name} を ${ver} 以上に上げる"
        git switch -q -f --detach origin/main
        if git ls-remote --exit-code --heads origin "$branch" >/dev/null || ! still_vulnerable "$name" "$group"; then
            echo "::notice::${name} ${ver}: ブランチ ${branch} があるか、main に脆弱な版が無いので作りません。"; continue; fi
        published=$(curl -fsS "https://registry.npmjs.org/${name/\//%2F}" | jq -r --arg v "$ver" '.time[$v] // ""') || published=""
        if [ -z "$published" ]; then echo "::error::${name} ${ver} の公開日時を読めませんでした。"; failed=1; continue; fi
        how=$(decide "$published" "$(date +%s)" "$(jq -r .urgent <<<"$group")")
        if [ "$how" = wait ]; then echo "::notice::${name} ${ver} は公開から72時間経ってから作ります。"; continue; fi
        [ "$how" != exclude ] || exclude "$FRONTEND/pnpm-workspace.yaml" "${name}@${ver}"
        env -u GH_TOKEN pnpm --dir "$FRONTEND" update "$name" --lockfile-only </dev/null || { failed=1; continue; }
        if still_vulnerable "$name" "$group"; then
            while IFS= read -r range; do override "$FRONTEND/pnpm-workspace.yaml" "$name" "$ver" "$range"
            done < <(jq -r '.ranges[]' <<<"$group")
            env -u GH_TOKEN pnpm --dir "$FRONTEND" install --lockfile-only --no-frozen-lockfile </dev/null || { failed=1; continue; }
        fi
        if still_vulnerable "$name" "$group" || git diff --quiet; then
            echo "::error::${name} を ${ver} 以上に上げられませんでした。手で直してください。"; failed=1; continue; fi
        if ! frontend_test; then
            echo "::error::${name} を ${ver} 以上に上げると frontend-test の検査が通らないので、PR を作りません。手で直してください。消せなかった警告: $(jq -r '[.alerts[].html_url] | join(" ")' <<<"$group")"
            failed=1; continue; fi
        git switch -q -c "$branch"
        git add "$FRONTEND/pnpm-lock.yaml" "$FRONTEND/pnpm-workspace.yaml"
        git commit -q -m "$title" -m "Changes:
- frontend の間接依存 ${name} を、脆弱性の警告が消える ${ver} 以上に上げる
Reason:
- Dependabot が PR を作らない間接依存の警告を消すため(frontend-vuln-fix が自動で作った)
BREAKING CHANGE: N/A
Related: N/A
Refs: N/A"
        git push -q -u origin "$branch" </dev/null || { failed=1; continue; }
        gh pr create --base main --head "$branch" --title "$title" \
            --body "$(pr_body "$group" "$name" "$ver" "$how")" </dev/null || failed=1
    done 3< <(plan "$alerts" | jq -c '.[]')
    return "$failed"
}

case "${1:-}" in
    run | plan | vulnerable | decide | override | exclude | frontend_test) "$@" ;;
    *) echo "使い方: frontend-vuln-fix.sh run | plan | vulnerable | decide | override | exclude | frontend_test" >&2; exit 2 ;;
esac
