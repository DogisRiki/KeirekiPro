#!/usr/bin/env bash
# =====================================================================
# lib-ci-tool-versions.sh の自動テスト(guardrails CI の escape-hatch から実行)
#
# 一時のフォルダに .github/workflows/ と .github/actions/ のファイルを置き、
# civ_scan が版の行を見つけること、見つけてはいけない行を見つけないことを確かめる。
# 一時のフォルダにデータのファイル(ci-tool-versions.json)と書き場所のファイルを置き、
# 版を読む関数・書き換える関数・比べる関数を確かめる。本物のデータのファイルと
# docker/ の Dockerfile から開発環境の版を読めることも確かめる。
# ライブラリは、呼び出し側と同じく bash で source して呼ぶ。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/lib-ci-tool-versions.sh"
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

# 使い方: new_root。空の根のフォルダを作り、$ROOT に入れる
new_root() {
    N=$((N + 1))
    ROOT="$WORK/root$N"
    mkdir -p "$ROOT/.github/workflows"
}

# 使い方: scan。civ_scan の標準出力を $WORK/out.txt に、終了コードを $RC に入れる
scan() {
    bash -c '. "$1" && civ_scan "$2"' _ "$LIB" "$ROOT" >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
}

# 使い方: expect_out <説明> [<期待の行>...]。期待の行は「ファイル|行番号|名前|版」の形で書く。
# 終了コードが 0 で、標準出力が期待の行と同じ並びで一致すれば通る
expect_out() {
    local desc="$1"
    shift
    if [ "$#" -eq 0 ]; then
        : >"$WORK/want.txt"
    else
        printf '%s\n' "$@" | tr '|' '\t' >"$WORK/want.txt"
    fi
    if [ "$RC" -eq 0 ] && cmp -s "$WORK/want.txt" "$WORK/out.txt"; then
        pass "$desc"
    else
        fail "$desc" "終了コード ${RC} / 出力: $(tr '\t' '|' <"$WORK/out.txt" | head -c 600) / 期待: $(tr '\t' '|' <"$WORK/want.txt" | head -c 600) / 標準エラー: $(head -c 300 "$WORK/err.txt")"
    fi
}

W=.github/workflows/a.yaml

# --- civ_scan ----------------------------------------------------------------

if want scan_name_value; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
env:
  TOOL_VERSION: '1.2.3'
jobs:
  a:
    steps:
      - with:
          node-version: "24.1.0"
          java-version: 21
          some-Tag: v2.0
          release: 3.4.5 # コメント
          other: 1.2.3
          node-version-file: .nvmrc
          cache-version: latest
YAML
    scan
    expect_out "名前: 値 の行の版を見つける" \
        "$W|2|TOOL_VERSION|1.2.3" \
        "$W|7|node-version|24.1.0" \
        "$W|8|java-version|21" \
        "$W|9|some-Tag|v2.0" \
        "$W|10|release|3.4.5"
fi

if want scan_action_yml; then
    new_root
    mkdir -p "$ROOT/.github/actions/tool" "$ROOT/.github/actions/other"
    cat >"$ROOT/.github/actions/tool/action.yml" <<'YAML'
runs:
  using: composite
  steps:
    - shell: bash
      env:
        TOOL_VERSION: '9.8.7'
YAML
    cat >"$ROOT/.github/actions/other/action.yaml" <<'YAML'
runs:
  using: composite
  steps:
    - run: docker pull foo/bar:1.0
YAML
    printf 'TOOL_VERSION: 5.5.5\n' >"$ROOT/.github/actions/tool/notes.yml"
    scan
    expect_out "アクションの action.yml の版を見つける" \
        ".github/actions/other/action.yaml|4|foo/bar|1.0" \
        ".github/actions/tool/action.yml|6|TOOL_VERSION|9.8.7"
fi

if want scan_docker_continued; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    steps:
      - run: |
          docker run --rm \
            -w /repo \
            rhysd/actionlint:1.7.12 -color
YAML
    scan
    expect_out "\\ で続く docker run のイメージのタグを見つける" \
        "$W|7|rhysd/actionlint|1.7.12"
fi

if want scan_docker_platform; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    steps:
      - run: docker run --rm --platform linux/amd64 koalaman/shellcheck:v0.11.0 a.sh
YAML
    scan
    expect_out "--platform を付けた docker run のイメージのタグを見つける" \
        "$W|4|koalaman/shellcheck|v0.11.0"
fi

if want scan_docker_pull_create; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    steps:
      - run: docker pull alpine:3.20
      - run: docker create --name x busybox:1.36.1@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
      - run: docker pull alpine:latest
YAML
    scan
    expect_out "docker pull と docker create のイメージのタグを見つける" \
        "$W|4|alpine|3.20" \
        "$W|5|busybox|1.36.1"
fi

if want scan_image_container; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    container: node:24.1.0-bookworm
    services:
      db:
        image: "postgres:16.4"
      cache:
        image: redis
YAML
    scan
    expect_out "image: と container: の行のイメージのタグを見つける" \
        "$W|3|node|24.1.0-bookworm" \
        "$W|6|postgres|16.4"
fi

if want scan_npx; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    steps:
      - run: npx --yes @openai/codex@0.147.0 --version
      - run: npm install -g pnpm@9.1.0 corepack@latest
YAML
    scan
    expect_out "npx の パッケージ@版 を見つける" \
        "$W|4|@openai/codex|0.147.0" \
        "$W|5|pnpm|9.1.0"
fi

if want scan_apt_get; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    steps:
      - run: sudo DEBIAN_FRONTEND=noninteractive apt-get install -y jq=1.7.1-3build1 curl
      - run: apt install foo=2.0
YAML
    scan
    expect_out "apt-get install の パッケージ=版 を見つける" \
        "$W|4|jq|1.7.1-3build1" \
        "$W|5|foo|2.0"
fi

if want scan_apk_add; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    steps:
      - run: apk add --no-cache bash=5.2.26-r0 jq
YAML
    scan
    expect_out "apk add の パッケージ=版 を見つける" \
        "$W|4|bash|5.2.26-r0"
fi

if want scan_pip_eq; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    steps:
      - run: pip install yamllint==1.35.1
      - run: echo a==1.0
YAML
    scan
    expect_out "パッケージ==版 を見つける" \
        "$W|4|yamllint|1.35.1"
fi

if want scan_curl_github; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    steps:
      - run: curl -fsSL -o t.tgz "https://github.com/aquasecurity/trivy/releases/download/v0.74.0/trivy_0.74.0_Linux-64bit.tar.gz"
      - run: wget https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
      - run: echo https://github.com/x/y/releases/download/v1.0.0/a.tgz
YAML
    scan
    expect_out "curl の GitHub のリリースの URL の版を見つける" \
        "$W|4|aquasecurity/trivy|v0.74.0" \
        "$W|5|releases.hashicorp.com/terraform|1.9.0"
fi

if want scan_gh_release; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    steps:
      - run: gh release download v2.3.4 --repo cli/cli -p '*.deb'
YAML
    scan
    expect_out "gh release download の版を見つける" \
        "$W|4|cli/cli|v2.3.4"
fi

if want scan_skip_lines; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    steps:
      - uses: actions/setup-node@v4.0.0
        uses: foo/tool@1.2.3
      # node-version: '1.2.3'
          #   docker run alpine:3.1
        with:
          node-version: ${{ env.NODE }}
      - run: docker run alpine:3.20 ${{ inputs.args }}
YAML
    scan
    expect_out "uses: の行とコメントの行と \${{ を含む行を見つけない"
fi

if want scan_publish_port; then
    new_root
    cat >"$ROOT/$W" <<'YAML'
jobs:
  a:
    steps:
      - run: docker run --rm -p 8080:80 --publish=9090:90 -v "$PWD:/w" nginx:1.27.0
YAML
    scan
    expect_out "docker run -p 8080:80 と --publish=8080:80 の 8080:80 を版と読まない" \
        "$W|4|nginx|1.27.0"
fi

# --- データのファイルを読む関数 ----------------------------------------------

# 使い方: call <関数> [<引数>...]。ライブラリを読み込んで関数を呼び、標準出力を
# $WORK/out.txt に、終了コードを $RC に入れる
call() {
    bash -c '. "$1" && shift && "$@"' _ "$LIB" "$@" >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
}

# 使い方: expect_rc <説明> <終了コード>。直前の call の終了コードが一致すれば通る
expect_rc() {
    if [ "$RC" -eq "$2" ]; then
        pass "$1"
    else
        fail "$1" "終了コード ${RC} / 期待: $2 / 標準エラー: $(head -c 300 "$WORK/err.txt")"
    fi
}

# 使い方: expect_file <説明> <ファイル> [<期待の行>...]。ファイルの中身が期待の行と一致すれば通る
expect_file() {
    local desc="$1" file="$2"
    shift 2
    printf '%s\n' "$@" >"$WORK/want-file.txt"
    if cmp -s "$WORK/want-file.txt" "$file"; then
        pass "$desc"
    else
        fail "$desc" "中身: $(head -c 600 "$file") / 期待: $(head -c 600 "$WORK/want-file.txt")"
    fi
}

D1="sha256:$(printf '1%.0s' $(seq 64))"
D2="sha256:$(printf '2%.0s' $(seq 64))"
TF_FROM_TFLINT="FROM ghcr.io/terraform-linters/tflint:v0.65.0@${D1} AS tflint"

# 使い方: data_root。道具 x(ci の組2つと開発環境)、y(ci の組1つ)、tf(開発環境に
# tflint の FROM の行がある)のデータのファイルと、書き場所のファイルを置いた根を作る
data_root() {
    new_root
    mkdir -p "$ROOT/docker/x" "$ROOT/docker/tf"
    cat >"$ROOT/.github/ci-tool-versions.json" <<'JSON'
{
  "schema": 1,
  "tools": {
    "x": {
      "ci": [
        { "file": ".github/workflows/a.yaml", "key": "x-version" },
        { "file": ".github/workflows/b.yaml", "key": "X_VERSION" }
      ],
      "dev": { "file": "docker/x/Dockerfile", "image": "x", "hub_repository": "library/x", "tag_suffix": "-slim" }
    },
    "y": {
      "ci": [ { "file": ".github/workflows/b.yaml", "key": "Y_VERSION" } ]
    },
    "tf": {
      "ci": [ { "file": ".github/workflows/b.yaml", "key": "TF_VERSION" } ],
      "dev": { "file": "docker/tf/Dockerfile", "image": "hashicorp/terraform", "hub_repository": "hashicorp/terraform", "tag_suffix": "" }
    }
  },
  "excluded": []
}
JSON
    cat >"$ROOT/.github/workflows/a.yaml" <<'YAML'
jobs:
  a:
    steps:
      - with:
          x-version: '1.2.3'
          other-version: '1.2.3'
      - with:
          x-version: "1.2.3"
YAML
    cat >"$ROOT/.github/workflows/b.yaml" <<'YAML'
env:
  X_VERSION: 1.2.3
  Y_VERSION: '4.5.6'
  TF_VERSION: '1.9.0'
YAML
    printf '%s\n' "FROM x:1.2.3-slim@${D1} AS base" "RUN echo x:1.2.3-slim" >"$ROOT/docker/x/Dockerfile"
    printf '%s\n' "$TF_FROM_TFLINT" "" "FROM hashicorp/terraform:1.9.0@${D1}" >"$ROOT/docker/tf/Dockerfile"
}

if want rewrite_ci_quotes; then
    data_root
    call civ_rewrite_ci "$ROOT" y 4.6.0
    expect_rc "civ_rewrite_ci が 0 で終わる" 0
    expect_file "CI の版の書き換えが引用符を残して値だけを変える" "$ROOT/.github/workflows/b.yaml" \
        "env:" "  X_VERSION: 1.2.3" "  Y_VERSION: '4.6.0'" "  TF_VERSION: '1.9.0'"
fi

if want rewrite_ci_two_lines; then
    data_root
    call civ_tool_versions "$ROOT" x
    expect_out "civ_tool_versions が組ごとに見つけた行を出す" \
        "$W|5|1.2.3" "$W|8|1.2.3" ".github/workflows/b.yaml|2|1.2.3"
    call civ_rewrite_ci "$ROOT" x 1.10.0
    expect_rc "civ_rewrite_ci が 0 で終わる" 0
    expect_file "同じファイルの同じ名前の2つの行をどちらも書き換える" "$ROOT/$W" \
        "jobs:" "  a:" "    steps:" "      - with:" "          x-version: '1.10.0'" \
        "          other-version: '1.2.3'" "      - with:" '          x-version: "1.10.0"'
    expect_file "ほかのファイルの組の行も書き換える" "$ROOT/.github/workflows/b.yaml" \
        "env:" "  X_VERSION: 1.10.0" "  Y_VERSION: '4.5.6'" "  TF_VERSION: '1.9.0'"
fi

if want rewrite_dev_as; then
    data_root
    call civ_rewrite_dev "$ROOT" x 1.3.0 "$D2"
    expect_rc "civ_rewrite_dev が 0 で終わる" 0
    expect_file "開発環境の FROM の行を版と digest で書き換え、AS を残す" "$ROOT/docker/x/Dockerfile" \
        "FROM x:1.3.0-slim@${D2} AS base" "RUN echo x:1.2.3-slim"
    call civ_dev_from "$ROOT" x
    expect_out "civ_dev_from が書き換えた版とタグと digest を出す" "1.3.0|1.3.0-slim|${D2}"
fi

if want rewrite_dev_tflint; then
    data_root
    call civ_dev_from "$ROOT" tf
    expect_out "tflint の FROM の行を読まない" "1.9.0|1.9.0|${D1}"
    call civ_rewrite_dev "$ROOT" tf 1.10.0 "$D2"
    expect_rc "civ_rewrite_dev が 0 で終わる" 0
    expect_file "tflint の FROM の行を書き換えない" "$ROOT/docker/tf/Dockerfile" \
        "$TF_FROM_TFLINT" "" "FROM hashicorp/terraform:1.10.0@${D2}"
fi

if want dev_from_none; then
    data_root
    call civ_dev_from "$ROOT" y
    expect_out "開発環境の無い道具では何も出さない"
fi

if want gt_numeric; then
    call civ_gt 0.100.0 0.99.0
    expect_rc "0.100.0 を 0.99.0 より新しいとする" 0
    call civ_gt 0.99.0 0.100.0
    expect_rc "0.99.0 を 0.100.0 より新しいとしない" 1
    call civ_gt 1.2.3 1.2.3
    expect_rc "同じ版を新しいとしない" 1
    call civ_gt 1.2.3.1 1.2.3
    expect_rc "区切りの多い版を新しいとする" 0
fi

if want gt_strip_v; then
    call civ_gt v1.10.0 1.9.0
    expect_rc "先頭の v を外して比べる(v1.10.0 > 1.9.0)" 0
    call civ_gt 1.9.0 v1.10.0
    expect_rc "先頭の v を外して比べる(1.9.0 < v1.10.0)" 1
    call civ_major v24.11.1
    expect_out "civ_major が先頭の v を外した最初の数字を出す" "24"
    call civ_gt 1.2.x 1.2.3
    expect_rc "形の違う版を比べると 2 になる" 2
fi

if want rewrite_bad_input; then
    data_root
    cp -r "$ROOT" "$WORK/before$N"
    for v in 1.2 v1.2.3 1.2.3-rc1 ""; do
        call civ_rewrite_ci "$ROOT" x "$v"
        expect_rc "civ_rewrite_ci の形の違う版(${v})で 2 になる" 2
        call civ_rewrite_dev "$ROOT" x "$v" "$D2"
        expect_rc "civ_rewrite_dev の形の違う版(${v})で 2 になる" 2
    done
    for d in "sha256:abc" "${D2#sha256:}" "sha256:$(printf 'A%.0s' $(seq 64))" ""; do
        call civ_rewrite_dev "$ROOT" x 1.3.0 "$d"
        expect_rc "civ_rewrite_dev の形の違う digest(${d})で 2 になる" 2
    done
    if diff -r "$WORK/before$N" "$ROOT" >/dev/null; then
        pass "形の違う版か digest では、ファイルを変えない"
    else
        fail "形の違う版か digest では、ファイルを変えない" "$(diff -r "$WORK/before$N" "$ROOT" | head -c 600)"
    fi
fi

if want tool_versions_missing; then
    data_root
    printf '%s\n' "env:" "  Z_VERSION: 1.2.3" >"$ROOT/.github/workflows/b.yaml"
    cp -r "$ROOT" "$WORK/before$N"
    call civ_tool_versions "$ROOT" x
    expect_out "書き場所の組に当たる行が無ければ - を出す" \
        "$W|5|1.2.3" "$W|8|1.2.3" ".github/workflows/b.yaml|-|-"
    call civ_rewrite_ci "$ROOT" x 1.3.0
    expect_rc "当たる行の無い組があれば civ_rewrite_ci が 2 になる" 2
    if diff -r "$WORK/before$N" "$ROOT" >/dev/null; then
        pass "当たる行の無い組があれば、どのファイルも書き換えない"
    else
        fail "当たる行の無い組があれば、どのファイルも書き換えない" "$(diff -r "$WORK/before$N" "$ROOT" | head -c 600)"
    fi
fi

if want data_missing; then
    data_root
    for state in 無い 壊れた; do
        if [ "$state" = 無い ]; then
            rm -f "$ROOT/.github/ci-tool-versions.json"
        else
            printf '%s\n' '{ "tools": {' >"$ROOT/.github/ci-tool-versions.json"
        fi
        call civ_tool_versions "$ROOT" x
        expect_rc "データのファイルが${state}とき civ_tool_versions が 2 になる" 2
        call civ_dev_from "$ROOT" x
        expect_rc "データのファイルが${state}とき civ_dev_from が 2 になる" 2
        call civ_rewrite_ci "$ROOT" x 1.3.0
        expect_rc "データのファイルが${state}とき civ_rewrite_ci が 2 になる" 2
        call civ_rewrite_dev "$ROOT" x 1.3.0 "$D2"
        expect_rc "データのファイルが${state}とき civ_rewrite_dev が 2 になる" 2
    done
    data_root
    call civ_tool_versions "$ROOT" nosuch
    expect_rc "データのファイルに無い道具では 2 になる" 2
fi

# 本物のデータのファイルと docker/ の Dockerfile から、開発環境の版を読めること
if want dev_from_repo; then
    REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
    for t in node terraform; do
        call civ_dev_from "$REPO" "$t"
        IFS="$(printf '\t')" read -r ver tag digest <"$WORK/out.txt"
        case "$t" in node) suffix="-bookworm-slim" image="node" file="docker/frontend/Dockerfile" ;;
        *) suffix="" image="hashicorp/terraform" file="docker/terraform/Dockerfile" ;; esac
        if [ "$RC" -eq 0 ] && [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$tag" = "${ver}${suffix}" ] &&
            [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] && grep -q "^FROM ${image}:${tag}@${digest}" "$REPO/$file"; then
            pass "本物のデータのファイルで ${t} の開発環境の版を読む"
        else
            fail "本物のデータのファイルで ${t} の開発環境の版を読む" "終了コード ${RC} / 出力: $(tr '\t' '|' <"$WORK/out.txt") / 標準エラー: $(head -c 300 "$WORK/err.txt")"
        fi
    done
    for t in trivy codex; do
        call civ_dev_from "$REPO" "$t"
        expect_out "本物のデータのファイルで ${t} には開発環境の版が無い"
    done
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    FAILED=1
fi

exit "$FAILED"
