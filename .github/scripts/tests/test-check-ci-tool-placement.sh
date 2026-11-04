#!/usr/bin/env bash
# =====================================================================
# check-ci-tool-placement.sh の自動テスト(guardrails CI の escape-hatch から実行)
#
# 一時のフォルダに、ワークフローとデータのファイル(ci-tool-versions.json)と
# 棚卸しの対象の一覧(inventory-targets.json)を置いて検査を流し、終了コードと
# ::error の行を確かめる。本物のワークフローとデータのファイルと棚卸しの対象の
# 一覧の並びで検査が通ることも確かめる。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-ci-tool-placement.sh"
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
N=0

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1 ($2)"
    FAILED=1
}

RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        return 0
    fi
    return 1
}

W=.github/workflows
DATA=.github/ci-tool-versions.json
INV=.github/audit/inventory-targets.json

# 使い方: base。問題の無い並びの根のフォルダを作り、$ROOT に入れる。
# a.yaml の版の行は、3行目が TRIVY_VERSION、9行目が node-version、12行目が java-version。
# b.yaml の版の行は、6行目が node-version。
base() {
    N=$((N + 1))
    ROOT="$WORK/root$N"
    mkdir -p "$ROOT/$W" "$ROOT/.github/audit"
    cat >"$ROOT/$W/a.yaml" <<'YAML'
name: a
env:
  TRIVY_VERSION: 0.60.0
jobs:
  a:
    steps:
      - uses: actions/setup-node@0123456789abcdef0123456789abcdef01234567 # v4.0.0
        with:
          node-version: '24.1.0'
      - uses: actions/setup-java@0123456789abcdef0123456789abcdef01234567 # v4.0.0
        with:
          java-version: '21'
YAML
    cat >"$ROOT/$W/b.yaml" <<'YAML'
name: b
jobs:
  b:
    steps:
      - uses: actions/setup-node@0123456789abcdef0123456789abcdef01234567 # v4.0.0
        node-version: '24.1.0'
YAML
    cat >"$ROOT/$DATA" <<'JSON'
{
  "schema": 1,
  "tools": {
    "node": {
      "name": "Node.js", "inventory_name": "Node.js",
      "keys": ["node-version", "NODE_VERSION", "node"],
      "ci": [
        { "file": ".github/workflows/a.yaml", "key": "node-version" },
        { "file": ".github/workflows/b.yaml", "key": "node-version" }
      ],
      "dev": { "file": "docker/frontend/Dockerfile", "image": "node", "hub_repository": "library/node", "tag_suffix": "-bookworm-slim" }
    },
    "trivy": {
      "name": "Trivy", "inventory_name": "Trivy",
      "keys": ["trivy-version", "TRIVY_VERSION", "aquasec/trivy"],
      "ci": [
        { "file": ".github/workflows/a.yaml", "key": "TRIVY_VERSION" }
      ]
    }
  },
  "excluded": [
    { "file": ".github/workflows/a.yaml", "key": "java-version", "reason": "Java はメジャー版だけを書くため" }
  ]
}
JSON
    cat >"$ROOT/$INV" <<'JSON'
{
  "targets": [
    {
      "name": "Node.js",
      "declarations": [
        { "files": ["docker/frontend/Dockerfile"], "pattern": "x" },
        { "files": [".github/workflows/a.yaml", ".github/workflows/b.yaml"], "pattern": "y" }
      ]
    },
    {
      "name": "Trivy",
      "declarations": [
        { "files": [".github/workflows/a.yaml"], "pattern": "z" }
      ]
    }
  ]
}
JSON
}

# 使い方: edit <根からのパス> <前の文字> <後の文字>。ファイルの中の最初の <前の文字> を
# <後の文字> に替える。正規表現ではなく、そのままの文字で比べる。<前の文字> が無ければ失敗にする
edit() {
    local c
    c=$(cat "$ROOT/$1")
    if [[ "$c" != *"$2"* ]]; then
        fail "テストの準備" "$1 に「$2」がありません"
        return 1
    fi
    printf '%s\n' "${c/"$2"/"$3"}" >"$ROOT/$1"
}

# 使い方: check。検査の標準出力を $WORK/out.txt に、終了コードを $RC に入れる
check() {
    bash "$SCRIPT" "$ROOT" >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
}

# 使い方: lineof <根からのパス> <文字>。文字を含む最初の行の番号を出す
lineof() {
    grep -nF -- "$2" "$ROOT/$1" | head -n 1 | cut -d: -f1
}

show() {
    echo "終了コード ${RC} / 出力: $(head -c 1200 "$WORK/out.txt") / 標準エラー: $(head -c 300 "$WORK/err.txt")"
}

# 使い方: expect_errors <説明> <終了コード> [<::error の行>...]。
# 終了コードが同じで、::error の行が期待の行と同じ並びで一致すれば通る
expect_errors() {
    local desc="$1" rc="$2"
    shift 2
    if [ "$#" -eq 0 ]; then
        : >"$WORK/want.txt"
    else
        printf '%s\n' "$@" >"$WORK/want.txt"
    fi
    grep '^::error' "$WORK/out.txt" >"$WORK/got.txt"
    if [ "$RC" -eq "$rc" ] && cmp -s "$WORK/want.txt" "$WORK/got.txt"; then
        pass "$desc"
    else
        fail "$desc" "$(show) / 期待: $(head -c 1200 "$WORK/want.txt")"
    fi
}

# 使い方: expect_rc <説明> <終了コード> <出力に含む文字>
expect_rc() {
    if [ "$RC" -eq "$2" ] && grep -qF -- "$3" "$WORK/out.txt"; then
        pass "$1"
    else
        fail "$1" "$(show) / 期待: 終了コード $2 と「$3」"
    fi
}

if want ok; then
    base
    check
    expect_errors "問題の無い並びで 0 で終わる" 0
    expect_rc "問題の無い並びで、見つけた版の行の数を出す" 0 "問題はありません(版の行 4 件)"
fi

if want not_listed; then
    base
    printf '      - run: docker run --rm hadolint/hadolint:2.12.0 Dockerfile\n' >>"$ROOT/$W/a.yaml"
    check
    expect_errors "どの一覧にも無い版で、ファイルと行と足す先を出して失敗する" 1 \
        '::error file=.github/workflows/a.yaml,line=13::道具の版 hadolint/hadolint 2.12.0 が、.github/ci-tool-versions.json の tools(自動で上がる対象)にも excluded(対象外の一覧)にもありません。どちらかに {"file": ".github/workflows/a.yaml", "key": "hadolint/hadolint"} を足してください。excluded に足すときは reason に自動で上げない理由を書いてください'
    expect_rc "失敗した件数を出す" 1 "版の書き場所の検査: 1 件の問題があります。"
fi

if want tool_key_elsewhere; then
    base
    cat >"$ROOT/$W/c.yaml" <<'YAML'
name: c
jobs:
  c:
    steps:
      - uses: actions/setup-node@0123456789abcdef0123456789abcdef01234567 # v4.0.0
        node-version: '24.1.0'
YAML
    check
    expect_errors "4つの道具の名前の行が ci に無いファイルにあると、足す先を出して失敗する" 1 \
        '::error file=.github/workflows/c.yaml,line=6::Node.js の版 24.1.0(node-version)が、自動で上がる対象に入っていない場所にあります。.github/ci-tool-versions.json の tools.node.ci に {"file": ".github/workflows/c.yaml", "key": "node-version"} を足してください'
fi

if want excluded_tool_key; then
    base
    edit "$DATA" $',\n        { "file": ".github/workflows/b.yaml", "key": "node-version" }' ''
    edit "$DATA" '"reason": "Java はメジャー版だけを書くため" }' \
        $'"reason": "Java はメジャー版だけを書くため" },\n    { "file": ".github/workflows/b.yaml", "key": "node-version", "reason": "試すため" }'
    check
    l=$(lineof "$DATA" '"file": ".github/workflows/b.yaml", "key": "node-version", "reason"')
    expect_errors "excluded の組の名前が4つの道具の keys に入っていると失敗する" 1 \
        "::error file=.github/ci-tool-versions.json,line=${l}::excluded の組 {\"file\": \".github/workflows/b.yaml\", \"key\": \"node-version\"} の名前は、Node.js の keys に入っています。Node.js の版は対象外にできません。tools.node.ci に移してください"
fi

if want version_mismatch; then
    base
    edit "$W/b.yaml" "node-version: '24.1.0'" "node-version: '24.2.0'"
    check
    where='版ごとの場所: 24.1.0(.github/workflows/a.yaml:9) / 24.2.0(.github/workflows/b.yaml:6)'
    expect_errors "場所によって版が違うと、版ごとの場所を並べて失敗する" 1 \
        "::error file=.github/workflows/a.yaml,line=9::Node.js の CI の版が、場所によって違います。${where}" \
        "::error file=.github/workflows/b.yaml,line=6::Node.js の CI の版が、場所によって違います。${where}"
fi

if want version_v_prefix; then
    base
    edit "$W/b.yaml" "node-version: '24.1.0'" "node-version: 'v24.1.0'"
    check
    expect_errors "先頭の v だけが違う版は、同じ版と読む" 0
fi

if want no_reason; then
    base
    edit "$DATA" ', "reason": "Java はメジャー版だけを書くため"' ''
    check
    l=$(lineof "$DATA" '"key": "java-version"')
    expect_errors "reason の無い excluded で失敗する" 1 \
        "::error file=.github/ci-tool-versions.json,line=${l}::excluded の組 {\"file\": \".github/workflows/a.yaml\", \"key\": \"java-version\"} に、自動で上げない理由の reason がありません"
fi

if want empty_reason; then
    base
    edit "$DATA" '"reason": "Java はメジャー版だけを書くため"' $'"reason": " \\t "'
    check
    l=$(lineof "$DATA" '"key": "java-version"')
    expect_errors "reason が空の excluded で失敗する" 1 \
        "::error file=.github/ci-tool-versions.json,line=${l}::excluded の組 {\"file\": \".github/workflows/a.yaml\", \"key\": \"java-version\"} に、自動で上げない理由の reason がありません"
fi

if want no_inventory_target; then
    base
    edit "$INV" $',\n    {\n      "name": "Trivy",\n      "declarations": [\n        { "files": [".github/workflows/a.yaml"], "pattern": "z" }\n      ]\n    }' ''
    check
    l=$(lineof "$DATA" '"inventory_name": "Trivy"')
    expect_errors "棚卸しの対象が無いと失敗する" 1 \
        "::error file=.github/ci-tool-versions.json,line=${l}::.github/audit/inventory-targets.json に、Trivy の棚卸しの対象 Trivy がありません。targets に足してください"
fi

if want inventory_missing_file; then
    base
    edit "$INV" $'{ "files": ["docker/frontend/Dockerfile"], "pattern": "x" },\n        ' ''
    edit "$INV" ', ".github/workflows/b.yaml"' ''
    check
    l=$(lineof "$INV" '"name": "Node.js"')
    expect_errors "棚卸しの宣言が書き場所のファイルを全部は含まないと失敗する" 1 \
        "::error file=.github/audit/inventory-targets.json,line=${l}::棚卸しの対象 Node.js の宣言のファイルに、.github/workflows/b.yaml、docker/frontend/Dockerfile がありません。declarations の files に足してください"
fi

if want pair_line_missing; then
    base
    edit "$DATA" '{ "file": ".github/workflows/b.yaml", "key": "node-version" }' \
        $'{ "file": ".github/workflows/b.yaml", "key": "node-version" },\n        { "file": ".github/workflows/a.yaml", "key": "NODE_VERSION" }'
    edit "$DATA" '"reason": "Java はメジャー版だけを書くため" }' \
        $'"reason": "Java はメジャー版だけを書くため" },\n    { "file": ".github/workflows/b.yaml", "key": "java-version", "reason": "試すため" }'
    check
    l1=$(lineof "$DATA" '"key": "NODE_VERSION" }')
    l2=$(lineof "$DATA" '"file": ".github/workflows/b.yaml", "key": "java-version"')
    expect_errors "書き場所の組が指す行がファイルに無いと失敗する" 1 \
        "::error file=.github/ci-tool-versions.json,line=${l1}::組 {\"file\": \".github/workflows/a.yaml\", \"key\": \"NODE_VERSION\"} が指す版の行が .github/workflows/a.yaml にありません。組を消すか、ファイルと名前を直してください" \
        "::error file=.github/ci-tool-versions.json,line=${l2}::組 {\"file\": \".github/workflows/b.yaml\", \"key\": \"java-version\"} が指す版の行が .github/workflows/b.yaml にありません。組を消すか、ファイルと名前を直してください"
fi

if want all_problems; then
    base
    printf '      - run: docker run --rm hadolint/hadolint:2.12.0 Dockerfile\n' >>"$ROOT/$W/a.yaml"
    edit "$DATA" ', "reason": "Java はメジャー版だけを書くため"' ''
    check
    expect_rc "問題が2つあれば、全部を調べてから 2 件と出して失敗する" 1 "版の書き場所の検査: 2 件の問題があります。"
fi

if want unreadable; then
    base
    rm "$ROOT/$DATA"
    check
    expect_rc "データのファイルか棚卸しの対象の一覧を読めないと終了コード 2 になる(データのファイルが無い)" 2 "::error::データのファイル .github/ci-tool-versions.json を読めませんでした"
    base
    printf '{ "tools": ' >"$ROOT/$DATA"
    check
    expect_rc "データのファイルか棚卸しの対象の一覧を読めないと終了コード 2 になる(データのファイルが JSON として読めない)" 2 "::error::データのファイル .github/ci-tool-versions.json を読めませんでした"
    base
    rm "$ROOT/$INV"
    check
    expect_rc "データのファイルか棚卸しの対象の一覧を読めないと終了コード 2 になる(棚卸しの対象の一覧が無い)" 2 "::error::棚卸しの対象の一覧 .github/audit/inventory-targets.json が無いか、JSON として読めません"
    base
    printf '{ "targets": [' >"$ROOT/$INV"
    check
    expect_rc "データのファイルか棚卸しの対象の一覧を読めないと終了コード 2 になる(棚卸しの対象の一覧が JSON として読めない)" 2 "::error::棚卸しの対象の一覧 .github/audit/inventory-targets.json が無いか、JSON として読めません"
    base
    edit "$DATA" '"excluded": [' '"excluded": [ 1,'
    check
    expect_rc "データのファイルの形が違うと終了コード 2 になる" 2 "::error::.github/ci-tool-versions.json か .github/audit/inventory-targets.json の形が違うため、検査できませんでした"
    N=$((N + 1))
    ROOT="$WORK/none$N"
    check
    expect_rc "根のフォルダが無いと終了コード 2 になる" 2 "::error::版の行を読めませんでした"
fi

if want main_snapshot; then
    N=$((N + 1))
    ROOT="$WORK/root$N"
    mkdir -p "$ROOT/.github/audit"
    cp -r "$REPO/.github/workflows" "$ROOT/.github/"
    [ -d "$REPO/.github/actions" ] && cp -r "$REPO/.github/actions" "$ROOT/.github/"
    cp "$REPO/$DATA" "$ROOT/$DATA"
    cp "$REPO/$INV" "$ROOT/$INV"
    check
    expect_errors "この spec が main に入った時点と同じ並びのワークフローとデータのファイルで通る" 0
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: 場合 ${CASE} がありません"
    exit 1
fi

exit "$FAILED"
