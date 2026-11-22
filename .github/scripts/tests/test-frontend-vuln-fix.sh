#!/usr/bin/env bash
# =====================================================================
# frontend-vuln-fix.sh の自動テスト
#
# run が使う判断の部品(警告の絞り込みとまとめ方、脆弱な版の見つけ方、72時間の判断、
# pnpm-workspace.yaml の書き換え、frontend-test と同じ検査)を、サブコマンドで1つずつ呼んで確かめる。
# PR を作る run は、gh・git・curl・pnpm を偽物に替えて流し、PR を作れなかった組を
# vuln-fix の結果のファイル(VULN_FIX_UNRESOLVED)に書くことと、Claude の変更のブランチが
# ある組で PR を作らないことを確かめる。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/frontend-vuln-fix.sh"
CI_YAML="$(cd "$(dirname "$0")/../.." && pwd)/workflows/ci.yaml"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

ok() { echo "  ok: $1"; }
ng() { echo "  NG: $1" >&2; FAILED=1; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1(期待: [$3] 実際: [$2])"; fi; }

# --- plan ---------------------------------------------------------------
echo "plan: 警告の絞り込みとまとめ方"
alert() { # number name relationship scope severity manifest range patched state ecosystem
    local fp='null'
    [ "$8" = none ] || fp="{\"identifier\":\"$8\"}"
    printf '{"number":%s,"state":"%s","html_url":"https://example.test/%s",
      "dependency":{"package":{"ecosystem":"%s","name":"%s"},"relationship":"%s","scope":%s,"manifest_path":"%s"},
      "security_advisory":{"severity":"%s"},
      "security_vulnerability":{"vulnerable_version_range":"%s","first_patched_version":%s}}' \
        "$1" "${9:-open}" "$1" "${10:-npm}" "$2" "$3" "$4" "$6" "$5" "$7" "$fp"
}
{
    printf '[['
    alert 1 qs transitive '"development"' medium frontend/pnpm-lock.yaml '>= 6.7.0, <= 6.16.0' 6.16.1; printf ','
    alert 2 qs transitive '"development"' low frontend/pnpm-lock.yaml '>= 6.7.0, <= 6.16.0' 6.16.1; printf ','
    alert 3 qs transitive '"development"' high frontend/pnpm-lock.yaml '< 6.16.1' 6.16.1; printf ','
    alert 4 direct-dep direct '"runtime"' high frontend/pnpm-lock.yaml '< 2.0.0' 2.0.0; printf ','
    alert 5 closed-one transitive '"runtime"' high frontend/pnpm-lock.yaml '< 2.0.0' 2.0.0 dismissed; printf ','
    alert 6 back-end transitive '"runtime"' high backend/build.gradle '< 2.0.0' 2.0.0 open maven; printf '],['
    alert 7 no-fix transitive '"runtime"' critical frontend/pnpm-lock.yaml '< 9.9.9' none; printf ','
    alert 8 '@scope/run' transitive '"runtime"' HIGH frontend/pnpm-lock.yaml '< 1.2.3' 1.2.3; printf ','
    alert 9 dev-crit transitive '"development"' critical frontend/pnpm-lock.yaml '< 3.0.0' 3.0.0; printf ','
    alert 10 run-med transitive '"runtime"' medium frontend/pnpm-lock.yaml '< 4.0.0' 4.0.0; printf ','
    alert 11 no-scope transitive null high frontend/pnpm-lock.yaml '< 5.0.0' 5.0.0
    printf ']]'
} >"$WORK/alerts.json"
if ! out=$(bash "$SCRIPT" plan "$WORK/alerts.json"); then ng "plan が失敗した"; out='[]'; fi
expect_eq "対象の組だけが残る(直接依存・閉じた警告・backend・修正版の無い警告は除く)" \
    "$(jq -c '[.[].name]' <<<"$out")" '["@scope/run","dev-crit","no-scope","qs","run-med"]'
expect_eq "同じ部品と修正版の警告は1つの組にまとまる" "$(jq -c '[.[] | select(.name == "qs") | .alerts | length]' <<<"$out")" '[3]'
expect_eq "組の範囲は重ねずに並ぶ" "$(jq -c '.[] | select(.name == "qs") | .ranges' <<<"$out")" '["< 6.16.1",">= 6.7.0, <= 6.16.0"]'
expect_eq "本番で動く high は urgent(深刻度の大文字小文字を問わない)" "$(jq '.[] | select(.name == "@scope/run") | .urgent' <<<"$out")" true
expect_eq "開発用の critical は urgent でない" "$(jq '.[] | select(.name == "dev-crit") | .urgent' <<<"$out")" false
expect_eq "本番で動く medium は urgent でない" "$(jq '.[] | select(.name == "run-med") | .urgent' <<<"$out")" false
expect_eq "scope の無い high は urgent でない" "$(jq '.[] | select(.name == "no-scope") | .urgent' <<<"$out")" false
expect_eq "開発用の high が混ざっても本番で動く警告が無ければ urgent でない" "$(jq '.[] | select(.name == "qs") | .urgent' <<<"$out")" false

# --- vulnerable ---------------------------------------------------------
echo "vulnerable: lockfile の脆弱な版"
cat >"$WORK/pnpm-lock.yaml" <<'EOF'
lockfileVersion: '9.0'

overrides:
  qs@6: ^6.15.2
  minimatch@3: ^3.0.0

importers:

  .:
    devDependencies:
      qs:
        specifier: ^6.0.0
        version: 6.15.3

packages:

  '@scope/run@1.2.2':
    resolution: {integrity: sha512-x}

  minimatch@10.2.5:
    resolution: {integrity: sha512-x}

  minimatch@3.1.5:
    resolution: {integrity: sha512-x}

  minimatch-extra@1.0.0:
    resolution: {integrity: sha512-x}

  qs@6.15.3:
    resolution: {integrity: sha512-x}

snapshots:

  '@scope/run@1.2.2(react@18.0.0)':
    dependencies:
      qs: 6.15.3

  minimatch@11.0.3:
    dependencies:
      brace-expansion: 5.0.0
EOF
vuln() { bash "$SCRIPT" vulnerable "$WORK/pnpm-lock.yaml" "$1" "$2" | tr '\n' ' '; }
expect_eq "範囲の中の版を出す(上限と下限)" "$(vuln qs '>= 6.7.0, <= 6.16.0')" '6.15.3 '
expect_eq "上限ちょうどは範囲に入る" "$(vuln qs '>= 6.7.0, <= 6.15.3')" '6.15.3 '
expect_eq "未満の範囲で古い版を全部出す" "$(vuln minimatch '< 11.0.1')" '10.2.5 3.1.5 '
expect_eq "修正版より新しい版は出さない" "$(vuln minimatch '< 10.2.5')" '3.1.5 '
expect_eq "名前が前方一致するだけの部品は数えない" "$(vuln minimatch-extra '< 2.0.0')" '1.0.0 '
expect_eq "引用符の付いた scope 付きの名前と、peer の付いた行を読む" "$(vuln '@scope/run' '< 1.2.3')" '1.2.2 '
expect_eq "等号の範囲" "$(vuln qs '= 6.15.3')" '6.15.3 '
expect_eq "下限より古い版は出さない" "$(vuln qs '> 6.15.3')" ''
if bash "$SCRIPT" vulnerable "$WORK/pnpm-lock.yaml" qs '>= 6.16.1' >/dev/null; then
    ng "脆弱な版が無いのに 0 で終わった"
else ok "脆弱な版が無ければ 0 以外で終わる"; fi
if bash "$SCRIPT" vulnerable "$WORK/pnpm-lock.yaml" qs '< 7' >/dev/null; then
    ok "overrides の節の qs@6 は版として読まない(packages の 6.15.3 だけで 0)"
else ng "packages の版を読めていない"; fi
expect_eq "overrides の節の minimatch@3 は版として読まない" "$(vuln minimatch '< 4')" '3.1.5 '

# --- decide -------------------------------------------------------------
echo "decide: 公開から72時間の判断"
now=$(date +%s)
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.123Z; }
expect_eq "72時間を過ぎていれば進める" "$(bash "$SCRIPT" decide "$(iso $((now - 72 * 3600 - 60)))" "$now" false)" go
expect_eq "ちょうど72時間なら進める" "$(bash "$SCRIPT" decide "$(iso $((now - 72 * 3600)))" "$now" false)" go
expect_eq "72時間前で急がない警告なら待つ" "$(bash "$SCRIPT" decide "$(iso $((now - 71 * 3600)))" "$now" false)" wait
expect_eq "72時間前で本番の high か critical なら例外に足す" "$(bash "$SCRIPT" decide "$(iso $((now - 3600)))" "$now" true)" exclude
expect_eq "小数の秒が無い形も読む" "$(bash "$SCRIPT" decide "$(date -u -d "@$((now - 100 * 3600))" +%Y-%m-%dT%H:%M:%SZ)" "$now" true)" go

# --- override -----------------------------------------------------------
echo "override: overrides の書き換え"
cat >"$WORK/base.yaml" <<'EOF'
packages:
  - .

minimumReleaseAge: 4320

overrides:
  follow-redirects: ">=1.16.0"
  # コメント qs@6
  qs@6: "^6.15.2"
  '@scope/run@1': "^1.0.0"

allowBuilds:
  esbuild: false
EOF
cp "$WORK/base.yaml" "$WORK/w.yaml"
bash "$SCRIPT" override "$WORK/w.yaml" qs 6.16.1 '>= 6.7.0, <= 6.16.0'
sed 's/^  qs@6: "^6.15.2"$/  qs@6: "^6.16.1"/' "$WORK/base.yaml" >"$WORK/expected.yaml"
if cmp -s "$WORK/expected.yaml" "$WORK/w.yaml" && ! cmp -s "$WORK/base.yaml" "$WORK/w.yaml"; then
    ok "メジャーのキーがあれば値だけを置き換える"
else ng "メジャーのキーの置き換えが期待と違う: $(tr '\n' '|' <"$WORK/w.yaml")"; fi
cp "$WORK/base.yaml" "$WORK/w.yaml"
bash "$SCRIPT" override "$WORK/w.yaml" '@scope/run' 1.2.3 '< 1.2.3'
expect_eq "引用符の付いたキーも置き換える" "$(grep -c "^  '@scope/run@1': \"^1.2.3\"$" "$WORK/w.yaml")" 1
cp "$WORK/base.yaml" "$WORK/w.yaml"
bash "$SCRIPT" override "$WORK/w.yaml" minimatch 11.0.1 '< 11.0.1'
expect_eq "キーが無ければ overrides の先頭に範囲のキーを足す" "$(sed -n '/^overrides:/{n;p;}' "$WORK/w.yaml")" '  "minimatch@<11.0.1": "^11.0.1"'
if grep -vxF '  "minimatch@<11.0.1": "^11.0.1"' "$WORK/w.yaml" | cmp -s - "$WORK/base.yaml"; then
    ok "足すほかは変えない"
else ng "足した行のほかも変わった: $(tr '\n' '|' <"$WORK/w.yaml")"; fi
cp "$WORK/base.yaml" "$WORK/w.yaml"
bash "$SCRIPT" override "$WORK/w.yaml" qs 7.0.1 '>= 6.7.0, < 7.0.1'
expect_eq "メジャーが違えば別のキーとして足し、範囲を pnpm の形にする" "$(sed -n '/^overrides:/{n;p;}' "$WORK/w.yaml")" '  "qs@>=6.7.0 <7.0.1": "^7.0.1"'
expect_eq "コメントの中の名前は置き換えない" "$(grep -c '^  # コメント qs@6$' "$WORK/w.yaml")" 1
printf 'packages:\n  - .\n' >"$WORK/w.yaml"
bash "$SCRIPT" override "$WORK/w.yaml" qs 6.16.1 '< 6.16.1'
expect_eq "overrides の節が無ければ最後に作る" "$(tail -n 2 "$WORK/w.yaml" | tr '\n' '|')" 'overrides:|  "qs@<6.16.1": "^6.16.1"|'
printf 'overrides:\n  qs@6: "^6.15.2"\nallowBuilds:\n  qs@6: false\n' >"$WORK/w.yaml"
bash "$SCRIPT" override "$WORK/w.yaml" qs 6.16.1 '< 6.16.1'
expect_eq "ほかの節の同じ名前のキーは変えない" "$(tr '\n' '|' <"$WORK/w.yaml")" 'overrides:|  qs@6: "^6.16.1"|allowBuilds:|  qs@6: false|'

# --- exclude ------------------------------------------------------------
echo "exclude: minimumReleaseAgeExclude への追加"
cp "$WORK/base.yaml" "$WORK/w.yaml"
bash "$SCRIPT" exclude "$WORK/w.yaml" '@scope/run@1.2.3'
expect_eq "キーが無ければ minimumReleaseAge の下に作る" "$(sed -n '/^minimumReleaseAge:/{n;p;n;p;}' "$WORK/w.yaml" | tr '\n' '|')" \
    "minimumReleaseAgeExclude:|  - '@scope/run@1.2.3'|"
bash "$SCRIPT" exclude "$WORK/w.yaml" 'qs@6.16.1'
expect_eq "キーがあればその下に足し、前の要素を残す" "$(sed -n '/^minimumReleaseAgeExclude:/{n;p;n;p;}' "$WORK/w.yaml" | tr '\n' '|')" \
    "  - 'qs@6.16.1'|  - '@scope/run@1.2.3'|"
expect_eq "キーは1つのまま" "$(grep -c '^minimumReleaseAgeExclude:' "$WORK/w.yaml")" 1
printf 'packages:\n  - .\n' >"$WORK/w.yaml"
bash "$SCRIPT" exclude "$WORK/w.yaml" 'qs@6.16.1'
expect_eq "どちらのキーも無ければ最後に作る" "$(tail -n 2 "$WORK/w.yaml" | tr '\n' '|')" "minimumReleaseAgeExclude:|  - 'qs@6.16.1'|"

# --- frontend_test ------------------------------------------------------
echo "frontend_test: frontend-test と同じ検査"
# pnpm の代わりに、受け取った引数を記録し、PNPM_FAIL と同じ引数のときだけ失敗する偽物を置く
mkdir -p "$WORK/bin"
cat >"$WORK/bin/pnpm" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$PNPM_LOG"
[ -z "${GH_TOKEN+x}" ] || echo "GH_TOKEN が渡った" >>"$PNPM_LOG"
[ "$*" != "${PNPM_FAIL:-}" ]
EOF
chmod +x "$WORK/bin/pnpm"
fake_test() { # 失敗させる引数
    : >"$WORK/pnpm.log"
    PATH="$WORK/bin:$PATH" PNPM_LOG="$WORK/pnpm.log" PNPM_FAIL="$1" GH_TOKEN=secret \
        bash "$SCRIPT" frontend_test >/dev/null
}
ci_cmds=$(awk '/^  frontend-test:/ { f = 1; next } f && /^  [^ #]/ { f = 0 }
               f && /run: pnpm / { sub(/.*run: pnpm /, ""); print "--dir frontend " $0 }' "$CI_YAML")
if [ "$(wc -l <<<"$ci_cmds")" -ge 5 ]; then ok "ci.yaml の frontend-test から pnpm のコマンドを読めた"
else ng "ci.yaml の frontend-test から pnpm のコマンドを読めない: [$ci_cmds]"; fi
if fake_test ''; then ok "すべて通れば 0 で終わる"; else ng "すべて通ったのに 0 以外で終わった"; fi
expect_eq "ci.yaml の frontend-test と同じコマンドを同じ順に流す" "$(cat "$WORK/pnpm.log")" "$ci_cmds"
if fake_test '--dir frontend run lint'; then ng "ESLint が失敗したのに 0 で終わった"
else ok "ESLint が失敗すれば 0 以外で終わる"; fi
expect_eq "失敗したところで止め、後ろの検査を流さない" "$(tail -n 1 "$WORK/pnpm.log")" '--dir frontend run lint'
if fake_test '--dir frontend run build'; then ng "組み立てが失敗したのに 0 で終わった"
else ok "最後の組み立てが失敗しても 0 以外で終わる"; fi
expect_eq "部品のスクリプトに GH_TOKEN を渡さない" "$(grep -c 'GH_TOKEN' "$WORK/pnpm.log")" 0

# --- run(PR を作る処理)-------------------------------------------------
# gh・git・curl・pnpm を偽物に替え、環境変数で成功と失敗を選んで run を流す
echo "run: PR を作れなかった組の書き残しと、Claude の変更のブランチ"
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE_LOG"
case "$1 $2" in
    "api "*) cat "$FAKE_ALERTS" ;;
    "auth setup-git") ;;
    "pr create") [ -z "${FAKE_PR_FAIL:-}" ] || exit 1 ;;
    *) exit 99 ;;
esac
EOF
cat >"$WORK/bin/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"$FAKE_LOG"
case "$1" in
    ls-remote) for b in ${FAKE_REMOTE_BRANCHES:-}; do [ "$b" != "$5" ] || exit 0; done; exit 2 ;;
    diff) case " $* " in
              *" --name-only "*) echo frontend/pnpm-lock.yaml ;;
              *" HEAD~1 "*) exit 0 ;;
              *) exit "${FAKE_DIFF_QUIET:-1}" ;;
          esac ;;
    push) [ -z "${FAKE_PUSH_FAIL:-}" ] || exit 1 ;;
    config | switch | add | commit) ;;
    *) exit 99 ;;
esac
EOF
cat >"$WORK/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"$FAKE_LOG"
[ -z "${FAKE_CURL_FAIL:-}" ] || exit 22
printf '{"time":{"6.16.1":"2020-01-01T00:00:00.000Z"}}\n'
EOF
cat >"$WORK/bin/pnpm" <<'EOF'
#!/usr/bin/env bash
echo "pnpm $*" >>"$FAKE_LOG"
case "$3 $4" in
    "update "*) [ -z "${FAKE_UPDATE_FAIL:-}" ] || exit 1
                [ -z "${FAKE_UPDATE_FIX:-}" ] || cp "$FAKE_LOCK_FIXED" frontend/pnpm-lock.yaml ;;
    "install --lockfile-only") [ -z "${FAKE_INSTALL_FAIL:-}" ] || exit 1 ;;
    *) [ -z "${FAKE_TEST_FAIL:-}" ] || exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/gh" "$WORK/bin/git" "$WORK/bin/curl" "$WORK/bin/pnpm"
{ printf '[['; alert 1 qs transitive '"development"' medium frontend/pnpm-lock.yaml '< 6.16.1' 6.16.1; printf ']]'; } >"$WORK/run-alerts.json"
printf "lockfileVersion: '9.0'\n\npackages:\n\n  qs@6.14.0:\n    resolution: {integrity: sha512-a}\n" >"$WORK/lock-old.yaml"
printf "lockfileVersion: '9.0'\n\npackages:\n\n  qs@6.16.1:\n    resolution: {integrity: sha512-b}\n" >"$WORK/lock-fixed.yaml"
run_group=$(bash "$SCRIPT" plan "$WORK/run-alerts.json" | jq -cS '.[0]')

# run_case <場合の名前> [<環境変数>=<値> ...]。終わり方を RC に、場合のフォルダを RD に入れる
run_case() {
    RD="$WORK/run-$1"; shift
    rm -rf "$RD"; mkdir -p "$RD/frontend"
    cp "$WORK/lock-old.yaml" "$RD/frontend/pnpm-lock.yaml"
    printf 'minimumReleaseAge: 4320\n' >"$RD/frontend/pnpm-workspace.yaml"
    printf 'stale\n' >"$RD/unresolved.jsonl"
    (cd "$RD" && env PATH="$WORK/bin:$PATH" GITHUB_REPOSITORY=owner/repo GH_TOKEN=dummy \
        FAKE_LOG="$RD/calls.log" FAKE_ALERTS="$WORK/run-alerts.json" FAKE_LOCK_FIXED="$WORK/lock-fixed.yaml" \
        VULN_FIX_UNRESOLVED="$RD/unresolved.jsonl" "$@" bash "$SCRIPT" run >"$RD/out.txt" 2>&1)
    RC=$?
    touch "$RD/calls.log"
}

# expect_unresolved <場合の名前> <止まった理由>。1行だけが足され、種類・組・理由が合うかを確かめる
expect_unresolved() {
    expect_eq "$1: 1 で終わる" "$RC" 1
    expect_eq "$1: 結果のファイルに1行だけが足される" "$(wc -l <"$RD/unresolved.jsonl" | tr -d ' ')" 1
    expect_eq "$1: 種類は npm" "$(jq -r .kind "$RD/unresolved.jsonl" 2>/dev/null)" npm
    expect_eq "$1: 組は plan の出す組と同じ" "$(jq -cS .group "$RD/unresolved.jsonl" 2>/dev/null)" "$run_group"
    expect_eq "$1: 理由" "$(jq -r .reason "$RD/unresolved.jsonl" 2>/dev/null)" "$2"
    expect_eq "$1: PR を作らない" "$(grep -c '^gh pr create' "$RD/calls.log")" 0
}

run_case curl FAKE_CURL_FAIL=1
expect_unresolved "公開日時を読めない" "公開日時を読めなかった"
run_case update FAKE_UPDATE_FAIL=1
expect_unresolved "pnpm update が失敗する" "pnpm update が失敗した"
run_case install FAKE_INSTALL_FAIL=1
expect_unresolved "pnpm install が失敗する" "pnpm install が失敗した"
run_case still
expect_unresolved "上げても脆弱な版が残る" "警告が消える版に上げられなかった"
run_case nodiff FAKE_UPDATE_FIX=1 FAKE_DIFF_QUIET=0
expect_unresolved "lockfile が変わらない" "警告が消える版に上げられなかった"
run_case test FAKE_UPDATE_FIX=1 FAKE_TEST_FAIL=1
expect_unresolved "frontend-test の検査が通らない" "frontend-test の検査が通らなかった"
run_case push FAKE_UPDATE_FIX=1 FAKE_PUSH_FAIL=1
expect_unresolved "push が失敗する" "ブランチを push できなかった"
run_case pr FAKE_UPDATE_FIX=1 FAKE_PR_FAIL=1
expect_eq "PR を作れない: 1 で終わる" "$RC" 1
expect_eq "PR を作れない: 結果のファイルに1行だけが足される" "$(wc -l <"$RD/unresolved.jsonl" | tr -d ' ')" 1
expect_eq "PR を作れない: 組は plan の出す組と同じ" "$(jq -cS .group "$RD/unresolved.jsonl" 2>/dev/null)" "$run_group"
expect_eq "PR を作れない: 理由" "$(jq -r .reason "$RD/unresolved.jsonl" 2>/dev/null)" "PR を作れなかった"

run_case ok FAKE_UPDATE_FIX=1
expect_eq "PR を作れた: 0 で終わる" "$RC" 0
expect_eq "PR を作れた: PR を1つ作る" "$(grep -c '^gh pr create' "$RD/calls.log")" 1
if [ -f "$RD/unresolved.jsonl" ] && [ ! -s "$RD/unresolved.jsonl" ]; then ok "PR を作れた: 結果のファイルは空で残る(前の中身を消す)"
else ng "PR を作れた: 結果のファイルが空でない: [$(cat "$RD/unresolved.jsonl" 2>/dev/null)]"; fi

run_case claude FAKE_UPDATE_FIX=1 FAKE_REMOTE_BRANCHES=fix/claude-auto-fix-frontend-vuln-fix-qs-6-16-1
expect_eq "Claude の変更のブランチがある: 0 で終わる" "$RC" 0
expect_eq "Claude の変更のブランチがある: PR を作らない" "$(grep -c '^gh pr create' "$RD/calls.log")" 0
expect_eq "Claude の変更のブランチがある: lockfile を直さない" "$(grep -c '^pnpm ' "$RD/calls.log")" 0
expect_eq "Claude の変更のブランチがある: 結果のファイルに書かない" "$(wc -c <"$RD/unresolved.jsonl" | tr -d ' ')" 0

run_case chore FAKE_UPDATE_FIX=1 FAKE_REMOTE_BRANCHES=chore/frontend-vuln-fix-qs-6-16-1
expect_eq "同じ組の vuln-fix のブランチがある: PR を作らない" "$(grep -c '^gh pr create' "$RD/calls.log")" 0

run_case noenv FAKE_UPDATE_FIX=1 FAKE_CURL_FAIL=1 VULN_FIX_UNRESOLVED=
expect_eq "VULN_FIX_UNRESOLVED が無い: 1 で終わる(書かずに今と同じに動く)" "$RC" 1
expect_eq "VULN_FIX_UNRESOLVED が無い: ファイルを書き換えない" "$(cat "$RD/unresolved.jsonl")" stale

# --- 使い方 -------------------------------------------------------------
echo "使い方"
bash "$SCRIPT" unknown >/dev/null 2>&1
expect_eq "知らないサブコマンドは 2 で終わる" "$?" 2

if [ "$FAILED" -ne 0 ]; then
    echo "test-frontend-vuln-fix: 失敗があります" >&2
    exit 1
fi
echo "test-frontend-vuln-fix: すべて成功"
