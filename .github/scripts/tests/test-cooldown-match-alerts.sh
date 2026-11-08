#!/usr/bin/env bash
# =====================================================================
# cooldown-match-alerts.sh の自動テスト(dependency-review CI から実行)
#
# gh をスタブし、版ごとの判定(eligible と理由の種類)と終了コードを検証する。
# スタブが返す警告は、Dependabot の警告の API の実際の答え(2026-11-02 に
# このリポジトリの警告 #214 を1件取得)の欄の並びをもとにしてある。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/cooldown-match-alerts.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"

mkdir -p "$WORK/bin" "$WORK/alerts"

# --- gh のスタブ ---------------------------------------------------------------
# 問い合わせの package= の値(URL の符号のまま)を名前にしたファイルを、
# --paginate --slurp の形(ページの配列)で返す。ファイル名の末尾が .fail のものが
# あれば失敗を返す。ファイルが無い部品は、警告が0件のページを返す。
# 呼ばれたときの引数は $STUB_CALLS に記録する。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in repos/*) url="$a" ;; esac; done
echo "$*" >>"${STUB_CALLS:?}"
pkg=$(printf '%s' "$url" | sed -n 's/.*[?&]package=\([^&]*\).*/\1/p')
if [ -e "${STUB_ALERTS:?}/${pkg}.fail" ]; then
    echo "gh: HTTP 403: Resource not accessible by integration" >&2
    exit 1
fi
if [ -f "${STUB_ALERTS}/${pkg}.json" ]; then
    printf '[%s]\n' "$(cat "${STUB_ALERTS}/${pkg}.json")"
else
    echo '[[]]'
fi
STUB
chmod +x "$WORK/bin/gh"

# 使い方: alert <番号> <ecosystem> <名前> <深刻度> <scope(null は JSON の null)> <最初の修正版>
alert() {
    local scope_json=null
    [ "$5" = null ] || scope_json=$(jq -n --arg s "$5" '$s')
    jq -n --argjson num "$1" --arg eco "$2" --arg name "$3" --arg sev "$4" \
        --argjson scope "$scope_json" --arg fp "$6" '{
        number: $num, state: "open",
        dependency: {package: {ecosystem: $eco, name: $name},
            manifest_path: "frontend/pnpm-lock.yaml", version_requirement: "1.0.0",
            scope: $scope, relationship: "transitive"},
        security_advisory: {ghsa_id: ("GHSA-test-" + ($num|tostring)), cve_id: null,
            summary: "test advisory", severity: $sev},
        security_vulnerability: {package: {ecosystem: $eco, name: $name}, severity: $sev,
            vulnerable_version_range: ("< " + $fp), first_patched_version: {identifier: $fp}},
        html_url: ("https://github.com/owner/repo/security/dependabot/" + ($num|tostring)),
        url: ("https://api.github.com/repos/owner/repo/dependabot/alerts/" + ($num|tostring))
    }'
}

# 使い方: page <URL の符号にした名前> <警告の JSON>...  ページのファイルを作る
page() {
    local f="$WORK/alerts/$1.json"
    shift
    printf '%s\n' "$@" | jq -s . >"$f"
}

reset() {
    rm -f "$WORK/alerts/"*
    : >"$WORK/calls.log"
}

# 使い方: run <入力の JSON>。結果を $WORK/out.json に、終了コードを $RC に入れる
run() {
    printf '%s' "$1" >"$WORK/input.json"
    PATH="$WORK/bin:$PATH" STUB_ALERTS="$WORK/alerts" STUB_CALLS="$WORK/calls.log" \
        GITHUB_REPOSITORY="owner/repo" GH_TOKEN="dummy" \
        bash "$SCRIPT" "$WORK/input.json" >"$WORK/out.json" 2>"$WORK/err.log"
    RC=$?
}

# 使い方: expect <説明> <jq の式(真を期待)>
expect() {
    if jq -e "$2" "$WORK/out.json" >/dev/null 2>&1; then
        echo "PASS: $1"
    else
        echo "FAIL: $1 (式: $2 / 出力: $(cat "$WORK/out.json"))"
        FAILED=1
    fi
}

expect_rc() {
    if [ "$RC" -eq "$2" ]; then
        echo "PASS: $1"
    else
        echo "FAIL: $1 (expected exit $2, got $RC)"
        FAILED=1
    fi
}

RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        return 0
    fi
    return 1
}

# --- 場合 ------------------------------------------------------------------------

if want high_eligible; then
    reset
    # 別の部品の警告と別の ecosystem の警告がページに混ざっても、照合で外れる
    page axios "$(alert 210 npm axios high runtime 1.2.3)" \
        "$(alert 211 npm axios-mock high runtime 1.2.3)" \
        "$(alert 212 maven axios high runtime 1.2.3)"
    run '[{"ecosystem":"npm","name":"axios","version":"1.2.3"}]'
    expect_rc "high の警告の最初の修正版は eligible になる(終了コード)" 0
    expect "high の警告の最初の修正版は eligible になる" \
        '.[0].eligible == true and .[0].reason == "eligible"
         and .[0].alerts == [{"number":210,"ghsa_id":"GHSA-test-210","severity":"high",
             "html_url":"https://github.com/owner/repo/security/dependabot/210"}]
         and .[0].first_patched == []
         and .[0].ecosystem == "npm" and .[0].name == "axios" and .[0].version == "1.2.3"'
    if grep -q 'state=open' "$WORK/calls.log" && grep -q 'ecosystem=npm' "$WORK/calls.log" \
        && grep -q 'package=axios' "$WORK/calls.log" && grep -q -- '--paginate' "$WORK/calls.log" \
        && grep -q -- '--slurp' "$WORK/calls.log"; then
        echo "PASS: high の警告の最初の修正版は eligible になる(問い合わせの形)"
    else
        echo "FAIL: high の警告の最初の修正版は eligible になる(問い合わせの形: $(cat "$WORK/calls.log"))"
        FAILED=1
    fi
fi

if want two_alerts; then
    reset
    page "org.example%3Alib" \
        "$(alert 301 maven org.example:lib high runtime 2.0.1)" \
        "$(alert 302 maven org.example:lib critical runtime 2.0.1)"
    run '[{"ecosystem":"maven","name":"org.example:lib","version":"2.0.1"}]'
    expect "high と critical の警告が2つあれば、満たす警告がすべて返る" \
        '.[0].eligible == true and .[0].reason == "eligible"
         and ([.[0].alerts[].number] | sort) == [301,302]
         and ([.[0].alerts[].severity] | sort) == ["critical","high"]'
    # 最初の修正版が違う2つの警告。どちらの最初の修正版も入る
    reset
    page "org.example%3Alib" \
        "$(alert 303 maven org.example:lib high runtime 2.0.1)" \
        "$(alert 304 maven org.example:lib critical runtime 2.1.0)"
    run '[{"ecosystem":"maven","name":"org.example:lib","version":"2.0.1"},{"ecosystem":"maven","name":"org.example:lib","version":"2.1.0"}]'
    expect "high と critical の警告が2つあれば、どちらの最初の修正版も eligible になる" \
        'all(.[]; .eligible == true and .reason == "eligible")
         and [.[0].alerts[].number] == [303] and [.[1].alerts[].number] == [304]'
    # 条件を満たす警告と満たさない警告が並ぶ部品。満たす警告だけが返る
    reset
    page axios \
        "$(alert 305 npm axios medium runtime 1.2.3)" \
        "$(alert 306 npm axios high runtime 1.2.3)" \
        "$(alert 307 npm axios high runtime 1.2.0)"
    run '[{"ecosystem":"npm","name":"axios","version":"1.2.3"}]'
    expect "high と critical の警告が2つあれば、満たす警告がすべて返る(満たさない警告は返らない)" \
        '.[0].eligible == true and .[0].reason == "eligible"
         and [.[0].alerts[].number] == [306] and .[0].first_patched == []'
fi

if want low_severity; then
    reset
    page axios "$(alert 220 npm axios medium runtime 1.2.3)"
    run '[{"ecosystem":"npm","name":"axios","version":"1.2.3"}]'
    expect "medium の警告だけなら low-severity になる" \
        '.[0].eligible == false and .[0].reason == "low-severity" and .[0].alerts == []'
fi

if want development; then
    reset
    page axios "$(alert 230 npm axios high development 1.2.3)"
    run '[{"ecosystem":"npm","name":"axios","version":"1.2.3"}]'
    expect "scope が development なら development になる" \
        '.[0].eligible == false and .[0].reason == "development"'
fi

if want no_scope; then
    reset
    page axios "$(alert 240 npm axios critical null 1.2.3)"
    run '[{"ecosystem":"npm","name":"axios","version":"1.2.3"}]'
    expect "scope が null なら no-scope になる" \
        '.[0].eligible == false and .[0].reason == "no-scope"'
fi

if want not_first_patched; then
    reset
    page axios "$(alert 250 npm axios high runtime 1.2.3)"
    run '[{"ecosystem":"npm","name":"axios","version":"1.2.4"}]'
    expect "最初の修正版より新しい版は not-first-patched になり、最初の修正版が返る" \
        '.[0].eligible == false and .[0].reason == "not-first-patched"
         and .[0].first_patched == ["1.2.3"] and .[0].alerts == []'
fi

if want alerts_unreadable; then
    reset
    : >"$WORK/alerts/axios.fail"
    page lodash "$(alert 260 npm lodash high runtime 4.17.22)"
    run '[{"ecosystem":"npm","name":"axios","version":"1.2.3"},{"ecosystem":"npm","name":"lodash","version":"4.17.22"}]'
    expect_rc "警告の API が失敗したら alerts-unreadable になる(終了コード)" 0
    expect "警告の API が失敗したら alerts-unreadable になる" \
        'length == 2 and .[0].name == "axios" and .[0].eligible == false
         and .[0].reason == "alerts-unreadable" and .[0].alerts == []
         and .[1].name == "lodash" and .[1].eligible == true'
fi

if want closest_reason; then
    reset
    page axios \
        "$(alert 271 npm axios medium runtime 1.2.3)" \
        "$(alert 272 npm axios high development 1.2.3)" \
        "$(alert 273 npm axios high runtime 1.2.2)" \
        "$(alert 277 npm axios critical null 1.2.3)"
    page lodash \
        "$(alert 274 npm lodash low runtime 4.17.22)" \
        "$(alert 275 npm lodash critical null 4.17.22)"
    page "%40scope%2Fpkg" "$(alert 276 npm @scope/pkg medium development 3.0.0)"
    run '[{"ecosystem":"npm","name":"axios","version":"1.2.3"},{"ecosystem":"npm","name":"lodash","version":"4.17.22"},{"ecosystem":"npm","name":"@scope/pkg","version":"3.0.0"},{"ecosystem":"npm","name":"left-pad","version":"1.0.0"}]'
    expect "条件を満たさない警告がいくつかあれば、最初の修正版の一致に最も近い理由を返す" \
        '.[0].reason == "not-first-patched" and .[0].first_patched == ["1.2.2"]
         and .[1].reason == "no-scope" and .[2].reason == "low-severity"
         and .[3].reason == "no-alert" and all(.[]; .eligible == false)'
fi

if want not_array; then
    reset
    run '{"ecosystem":"npm","name":"axios","version":"1.2.3"}'
    expect_rc "入力が JSON の配列でなければ終了コード 2 になる" 2
    run 'not json'
    expect_rc "入力が JSON でなければ終了コード 2 になる" 2
fi

if want broken_page; then
    reset
    echo '["not-an-object"]' >"$WORK/alerts/axios.json"
    run '[{"ecosystem":"npm","name":"axios","version":"1.2.3"}]'
    expect_rc "警告の答えの要素がオブジェクトでなければ alerts-unreadable になる(終了コード)" 0
    expect "警告の答えの要素がオブジェクトでなければ alerts-unreadable になる" \
        '.[0].reason == "alerts-unreadable" and .[0].eligible == false'
fi

if want gomod_eligible; then
    reset
    # 警告の API は Go のモジュールのエコシステムを go と呼ぶ。名前の大文字と小文字と、
    # 最初の修正版の先頭の v の有無が、差分比較の API と違っても照らす。
    # gomod と書いた警告と npm の警告は、エコシステムが違うので外れる
    page 'github.com%2FExample%2FTool' "$(alert 260 go github.com/example/tool high runtime v1.2.0)" \
        "$(alert 261 gomod github.com/Example/Tool high runtime 1.2.0)" \
        "$(alert 262 npm github.com/Example/Tool high runtime 1.2.0)"
    run '[{"ecosystem":"gomod","name":"github.com/Example/Tool","version":"1.2.0"}]'
    expect_rc "gomod の部品は go のエコシステムの警告に照らす(終了コード)" 0
    expect "gomod の部品は go のエコシステムの警告に照らす" \
        '.[0].eligible == true and .[0].reason == "eligible" and [.[0].alerts[].number] == [260]
         and .[0].ecosystem == "gomod" and .[0].name == "github.com/Example/Tool" and .[0].version == "1.2.0"'
    if grep -qF 'ecosystem=go&package=github.com%2FExample%2FTool' "$WORK/calls.log"; then
        echo "PASS: gomod の部品は go のエコシステムの警告に照らす(問い合わせの形)"
    else
        echo "FAIL: gomod の部品は go のエコシステムの警告に照らす(問い合わせの形: $(cat "$WORK/calls.log"))"
        FAILED=1
    fi
fi

if want gomod_not_first_patched; then
    reset
    page 'github.com%2FExample%2FTool' "$(alert 263 go github.com/Example/Tool high runtime 1.2.0)"
    run '[{"ecosystem":"gomod","name":"github.com/Example/Tool","version":"1.2.1"}]'
    expect "gomod の部品が最初の修正版より新しければ not-first-patched になる" \
        '.[0].eligible == false and .[0].reason == "not-first-patched" and .[0].first_patched == ["1.2.0"]'
fi

if want npm_case; then
    reset
    # 大文字と小文字を区別せずに照らすのは gomod の部品だけである
    page axios "$(alert 264 npm Axios high runtime 1.2.3)"
    run '[{"ecosystem":"npm","name":"axios","version":"1.2.3"}]'
    expect "npm の部品は、名前の大文字と小文字が違う警告に照らさない" \
        '.[0].eligible == false and .[0].reason == "no-alert"'
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    FAILED=1
fi

exit "$FAILED"
