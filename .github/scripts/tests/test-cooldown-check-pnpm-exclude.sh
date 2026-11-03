#!/usr/bin/env bash
# =====================================================================
# cooldown-check-pnpm-exclude.sh の自動テスト(dependency-review CI から実行)
#
# pnpm-workspace.yaml の minimumReleaseAgeExclude の書き方ごとに、版を指す要素を
# 見分けられるかと、読めない書き方で終了コード 2 になるかを検証する。
# real_workspace の場合は、リポジトリの frontend/pnpm-workspace.yaml をそのまま読む。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/cooldown-check-pnpm-exclude.sh"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"

# 使い方: run <pnpm-workspace.yaml> <入力の JSON>。出力を $WORK/out.json に、終了コードを $RC に入れる
run() {
    printf '%s' "$2" >"$WORK/in.json"
    bash "$SCRIPT" "$1" "$WORK/in.json" >"$WORK/out.json" 2>"$WORK/err.log"
    RC=$?
}

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1 ($2)"
    FAILED=1
}

# 使い方: expect <説明> <jq の式>。終了コードが 0 で、出力にその式を当てると true になる
expect() {
    if [ "$RC" -eq 0 ] && jq -e "$2" "$WORK/out.json" >/dev/null 2>&1; then
        pass "$1"
    else
        fail "$1" "終了コード ${RC} / 出力: $(head -c 500 "$WORK/out.json") / 標準エラー: $(head -c 300 "$WORK/err.log")"
    fi
}

expect_rc() {
    if [ "$RC" -eq "$2" ]; then pass "$1"; else fail "$1" "expected exit $2, got $RC"; fi
}

RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        return 0
    fi
    return 1
}

# 使い方: present_of <名前> <版>。出力の中のその版の present を出す jq の式
present_of() { printf '[.[] | select(.name == "%s" and .version == "%s") | .present] == [%s]' "$1" "$2" "$3"; }

# --- 場合 ------------------------------------------------------------------------

if want exact; then
    cat >"$WORK/ws.yaml" <<'YAML'
packages:
  - .
minimumReleaseAge: 4320
minimumReleaseAgeExclude:
  - axios@1.12.0
YAML
    run "$WORK/ws.yaml" '[{"name":"axios","version":"1.12.0"},{"name":"axios","version":"1.12.1"}]'
    expect "name@1.2.3 の要素は present になる" "$(present_of axios 1.12.0 true)"
    expect "name@1.2.3 の要素は present になる(ほかの版は present にならない)" "$(present_of axios 1.12.1 false)"
fi

if want or_versions; then
    cat >"$WORK/ws.yaml" <<'YAML'
minimumReleaseAgeExclude:
  - axios@1.12.0 || 1.12.1
  - vite@7.1.0||7.1.1
YAML
    run "$WORK/ws.yaml" '[{"name":"axios","version":"1.12.0"},{"name":"axios","version":"1.12.1"},
        {"name":"axios","version":"1.12.2"},{"name":"vite","version":"7.1.1"}]'
    expect "name@1.2.3 || 1.2.4 の要素は present になる(1つ目の版)" "$(present_of axios 1.12.0 true)"
    expect "name@1.2.3 || 1.2.4 の要素は present になる(2つ目の版)" "$(present_of axios 1.12.1 true)"
    expect "name@1.2.3 || 1.2.4 の要素は present になる(並べていない版は present にならない)" "$(present_of axios 1.12.2 false)"
    expect "name@1.2.3 || 1.2.4 の要素は present になる(|| の前後に空白が無くても読む)" "$(present_of vite 7.1.1 true)"
fi

if want name_only; then
    cat >"$WORK/ws.yaml" <<'YAML'
minimumReleaseAgeExclude:
  - axios
  - '@types/*'
  - 'vite*'
YAML
    run "$WORK/ws.yaml" '[{"name":"axios","version":"1.12.0"},{"name":"@types/node","version":"24.0.0"},
        {"name":"vite","version":"7.1.0"}]'
    expect "名前だけの要素とパターンの要素は present にならない(名前だけ)" "$(present_of axios 1.12.0 false)"
    expect "名前だけの要素とパターンの要素は present にならない(スコープのパターン)" "$(present_of @types/node 24.0.0 false)"
    expect "名前だけの要素とパターンの要素は present にならない(名前のパターン)" "$(present_of vite 7.1.0 false)"
fi

if want inline_list; then
    printf 'minimumReleaseAgeExclude: [axios@1.12.0]\n' >"$WORK/ws.yaml"
    run "$WORK/ws.yaml" '[{"name":"axios","version":"1.12.0"}]'
    expect_rc "[...] の中に並べて書かれていたら終了コード 2 になる" 2
    printf 'minimumReleaseAgeExclude: []\n' >"$WORK/ws.yaml"
    run "$WORK/ws.yaml" '[{"name":"axios","version":"1.12.0"}]'
    expect_rc "[...] の中に並べて書かれていたら終了コード 2 になる(空の [])" 2
    printf 'minimumReleaseAgeExclude: axios@1.12.0\n' >"$WORK/ws.yaml"
    run "$WORK/ws.yaml" '[{"name":"axios","version":"1.12.0"}]'
    expect_rc "キーと同じ行に値が書かれていたら終了コード 2 になる" 2
fi

if want missing_file; then
    run "$WORK/nosuch.yaml" '[{"name":"axios","version":"1.12.0"}]'
    expect_rc "ファイルが無ければ終了コード 2 になる" 2
    mkdir -p "$WORK/dir.yaml"
    run "$WORK/dir.yaml" '[{"name":"axios","version":"1.12.0"}]'
    expect_rc "ファイルが無ければ終了コード 2 になる(ファイルではなくフォルダのとき)" 2
fi

if want quoted_scoped; then
    cat >"$WORK/ws.yaml" <<'YAML'
minimumReleaseAgeExclude:
  # 2026-11-02 まで
  - '@tanstack/react-query@5.90.0'   # 要素の後ろのコメント

  - "follow-redirects@1.16.0"
  - plain@2.0.0 # 囲んでいない要素の後ろのコメント
YAML
    run "$WORK/ws.yaml" '[{"name":"@tanstack/react-query","version":"5.90.0"},
        {"name":"follow-redirects","version":"1.16.0"},{"name":"plain","version":"2.0.0"}]'
    expect "スコープ付きの名前と、' か \" で囲んだ要素を読む(' で囲んだスコープ付きの名前)" \
        "$(present_of @tanstack/react-query 5.90.0 true)"
    expect "スコープ付きの名前と、' か \" で囲んだ要素を読む(\" で囲んだ要素)" "$(present_of follow-redirects 1.16.0 true)"
    expect "スコープ付きの名前と、' か \" で囲んだ要素を読む(コメントと空の行を飛ばす)" "$(present_of plain 2.0.0 true)"
fi

if want line; then
    cat >"$WORK/ws.yaml" <<'YAML'
minimumReleaseAgeExclude:
  - axios@1.12.0
YAML
    run "$WORK/ws.yaml" '[{"name":"@tanstack/react-query","version":"5.90.0"},{"name":"axios","version":"1.12.0"}]'
    expect "line に足すべき1行が入る" \
        ".[0] == {name: \"@tanstack/react-query\", version: \"5.90.0\", present: false, line: \"  - '@tanstack/react-query@5.90.0'\"}"
    expect "line に足すべき1行が入る(入力と同じ順で、present の版にも入る)" \
        ".[1] == {name: \"axios\", version: \"1.12.0\", present: true, line: \"  - 'axios@1.12.0'\"} and length == 2"
fi

if want next_key; then
    cat >"$WORK/ws.yaml" <<'YAML'
minimumReleaseAgeExclude:
  - axios@1.12.0
onlyBuiltDependencies:
  - esbuild@0.25.0
YAML
    run "$WORK/ws.yaml" '[{"name":"axios","version":"1.12.0"},{"name":"esbuild","version":"0.25.0"}]'
    expect "次のキーの行までを読む(除外の欄の要素)" "$(present_of axios 1.12.0 true)"
    expect "次のキーの行までを読む(ほかのキーの要素は数えない)" "$(present_of esbuild 0.25.0 false)"
fi

if want no_key; then
    printf 'packages:\n  - .\nminimumReleaseAge: 4320\n' >"$WORK/ws.yaml"
    run "$WORK/ws.yaml" '[{"name":"axios","version":"1.12.0"}]'
    expect "除外の欄が無ければ、どの版も present にならない" "$(present_of axios 1.12.0 false)"
fi

if want real_workspace; then
    run "$ROOT/frontend/pnpm-workspace.yaml" '[{"name":"axios","version":"0.0.0-test"}]'
    expect "リポジトリの pnpm-workspace.yaml を読める" "length == 1 and (.[0].present | type) == \"boolean\""
fi

if want bad_input; then
    printf 'minimumReleaseAgeExclude:\n  - axios@1.12.0\n' >"$WORK/ws.yaml"
    run "$WORK/ws.yaml" '{"name":"axios"}'
    expect_rc "入力が配列でなければ終了コード 2 になる" 2
    run "$WORK/ws.yaml" '[{"name":"axios"}]'
    expect_rc "入力の要素に版が無ければ終了コード 2 になる" 2
    bash "$SCRIPT" "$WORK/ws.yaml" >/dev/null 2>"$WORK/err.log"
    RC=$?
    expect_rc "引数が2つでなければ終了コード 2 になる" 2
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    FAILED=1
fi

exit "$FAILED"
