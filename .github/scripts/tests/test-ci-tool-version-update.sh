#!/usr/bin/env bash
# =====================================================================
# ci-tool-version-update.sh の結合テスト(guardrails CI の escape-hatch から実行)
#
# 一時のフォルダに、bare のリモートと、今の main と同じ並びのファイルを置いた
# リポジトリを作る。bare のリモートとは、作業フォルダを持たず、push を受けるため
# だけに置く Git のリポジトリである。main を取った写しの中でスクリプトを流す。
# PATH の先頭に偽の gh と curl を置き、配布元の応答を場合ごとに返す。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/ci-tool-version-update.sh"
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

# --- 偽の gh と curl --------------------------------------------------------
# どちらも、FAKE_MAP の「取り先<TAB>HTTP の状態<TAB>応答のファイル」の行で応答を返し、
# 呼ばれた取り先を FAKE_LOG に1行ずつ書く。行の無い取り先には 404 を返す。
# gh の api 以外の呼び方は、引数と GH_TOKEN を FAKE_LOG に1行で書く。pr list は
# FAKE_DIR/prs-<道具>.json を返し(無ければ [])、pr create は題名と本文を
# FAKE_DIR/title-<道具> と FAKE_DIR/body-<道具> に書く。FAKE_PR_CREATE_FAIL があれば
# pr create は失敗する。pr edit は題名と本文を FAKE_DIR/edit-title-<番号> と
# FAKE_DIR/edit-body-<番号> に書く。

mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" != api ]; then
    printf 'gh %s GH_TOKEN=%s\n' "$(printf '%s ' "$@" | tr '\n' ' ')" "${GH_TOKEN:-}" >>"$FAKE_LOG"
    sub="${1:-} ${2:-}"
    num="${3:-}" head="" title="" body=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --head) head="$2"; shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --body) body="$2"; shift 2 ;;
        *) shift ;;
        esac
    done
    case "$sub" in
    "auth setup-git") exit 0 ;;
    "pr list")
        if [ -f "$FAKE_DIR/prs-${head##*-}.json" ]; then cat "$FAKE_DIR/prs-${head##*-}.json"; else echo '[]'; fi
        exit 0
        ;;
    "pr create")
        if [ -n "${FAKE_PR_CREATE_FAIL:-}" ]; then
            echo "pull request create failed: HTTP 422" >&2
            exit 1
        fi
        printf '%s\n' "$title" >"$FAKE_DIR/title-${head##*-}"
        printf '%s\n' "$body" >"$FAKE_DIR/body-${head##*-}"
        echo "https://github.test/owner/repo/pull/1"
        exit 0
        ;;
    "pr edit")
        printf '%s\n' "$title" >"$FAKE_DIR/edit-title-${num}"
        printf '%s\n' "$body" >"$FAKE_DIR/edit-body-${num}"
        exit 0
        ;;
    esac
    echo "偽の gh: 知らない呼び方です: $sub" >&2
    exit 9
fi
key="gh $2"
printf '%s\n' "$key" >>"$FAKE_LOG"
row=$(awk -F '\t' -v k="$key" '$1 == k { print; exit }' "$FAKE_MAP")
if [ -z "$row" ]; then
    echo '{"message":"Not Found"}'
    echo "gh: Not Found (HTTP 404)" >&2
    exit 1
fi
st=$(printf '%s\n' "$row" | cut -f2)
cat "$(printf '%s\n' "$row" | cut -f3)"
if [ "$st" -ge 400 ]; then
    echo "gh: Server Error (HTTP ${st})" >&2
    exit 1
fi
SH
cat >"$WORK/bin/curl" <<'SH'
#!/usr/bin/env bash
out="" fmt="" url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
    -o) out="$2"; shift 2 ;;
    -w) fmt="$2"; shift 2 ;;
    --max-time | --retry) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
    esac
done
key="curl $url"
printf '%s\n' "$key" >>"$FAKE_LOG"
row=$(awk -F '\t' -v k="$key" '$1 == k { print; exit }' "$FAKE_MAP")
st=404 body=/dev/null
if [ -n "$row" ]; then
    st=$(printf '%s\n' "$row" | cut -f2)
    body=$(printf '%s\n' "$row" | cut -f3)
fi
[ -n "$fmt" ] && printf '%s' "$st"
if [ "$st" -ge 400 ]; then
    echo "curl: (22) The requested URL returned error: ${st}" >&2
    exit 22
fi
if [ -n "$out" ]; then cat "$body" >"$out"; else cat "$body"; fi
SH
chmod +x "$WORK/bin/gh" "$WORK/bin/curl"

export PATH="$WORK/bin:$PATH"
export CTR_NODE_DIST_URL="https://node.test/dist"
export CTR_NPM_REGISTRY="https://npm.test"
export CTR_HASHICORP_API="https://hc.test"
export CTR_DOCKER_HUB="https://hub.test"
export FAKE_MAP FAKE_LOG FAKE_DIR
# git の設定は、この PC の設定を読まず、コミットの名前とメールを環境変数で渡す
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test

D1="sha256:c86ecead9e55a5210ac1727de38a4ca840bf03dcaf34dc9749addbf383b1920c"
D2="sha256:a5d5a5a892c98f60fcbfa81eac2a40fc19e7b3fa7719bccae10ff6111d22524a"
D3="sha256:1111111111111111111111111111111111111111111111111111111111111111"
D4="sha256:2222222222222222222222222222222222222222222222222222222222222222"
# 2026-11-04T00:00:00Z
NOW=1793750400
# 2026-11-06T01:00:00Z。2026-11-03T00:00:00Z に公開した版が通る日時のあと
LATER=1793926800
YOUNG=2026-11-03T00:00:00Z
OLD=2026-10-01T00:00:00Z
OLDER=2026-09-01T00:00:00Z

# 使い方: fx <gh|curl> <取り先> <HTTP の状態> <応答の本文>
fx() {
    local f
    f="$WORK/fx$N-$(wc -l <"$FAKE_MAP" | tr -d ' ').json"
    printf '%s\n' "$4" >"$f"
    printf '%s %s\t%s\t%s\n' "$1" "$2" "$3" "$f" >>"$FAKE_MAP"
}

# 使い方: node_list <版>...。nodejs.org の index.json の応答を足す。版は新しい順に渡す
node_list() {
    fx curl "https://node.test/dist/index.json" 200 \
        "$(printf '%s\n' "$@" | jq -R '{version: ("v" + .), date: "2026-01-01"}' | jq -s .)"
}

# 使い方: node_rel <版> <公開日時>。GitHub の Node.js の Release の応答を足す
node_rel() {
    fx gh "repos/nodejs/node/releases/tags/v$1" 200 "{\"tag_name\":\"v$1\",\"published_at\":\"$2\"}"
}

# 使い方: node_tag <版> <digest> <tag_last_pushed>。Docker Hub の node のタグの応答を足す
node_tag() {
    fx curl "https://hub.test/v2/namespaces/library/repositories/node/tags/$1-bookworm-slim" 200 \
        "{\"name\":\"$1-bookworm-slim\",\"digest\":\"$2\",\"tag_last_pushed\":\"$3\"}"
}

# 使い方: trivy_list <版>=<公開日時>...。GitHub の Trivy の Release の一覧の応答を足す。新しい順に渡す
trivy_list() {
    fx gh "repos/aquasecurity/trivy/releases?per_page=100&page=1" 200 \
        "$(printf '%s\n' "$@" | jq -R 'split("=") | {tag_name: ("v" + .[0]), published_at: .[1], draft: false, prerelease: false}' | jq -s .)"
}

# 使い方: trivy_rel <版> <公開日時>。GitHub の Trivy の Release の応答を足す
trivy_rel() {
    fx gh "repos/aquasecurity/trivy/releases/tags/v$1" 200 "{\"tag_name\":\"v$1\",\"published_at\":\"$2\"}"
}

# 使い方: tf_list <版>=<公開日時>...。HashiCorp の Terraform の版の一覧の応答を足す。新しい順に渡す
tf_list() {
    fx curl "https://hc.test/v1/releases/terraform?limit=20" 200 \
        "$(printf '%s\n' "$@" | jq -R 'split("=") | {version: .[0], timestamp_created: .[1], is_prerelease: false}' | jq -s .)"
}

# 使い方: tf_rel <版> <公開日時>。HashiCorp の Terraform の版の応答を足す
tf_rel() {
    fx curl "https://hc.test/v1/releases/terraform/$1" 200 \
        "{\"version\":\"$1\",\"timestamp_created\":\"$2\",\"is_prerelease\":false}"
}

# 使い方: tf_tag <版> <digest> <tag_last_pushed>。Docker Hub の hashicorp/terraform のタグの応答を足す
tf_tag() {
    fx curl "https://hub.test/v2/namespaces/hashicorp/repositories/terraform/tags/$1" 200 \
        "{\"name\":\"$1\",\"digest\":\"$2\",\"tag_last_pushed\":\"$3\"}"
}

# --- リポジトリの作り方 -----------------------------------------------------
# 作業のリポジトリ $G/work に今の main と同じ並びのファイルを置いてコミットし、
# bare のリモート $G/remote.git に push して、main を $G/main に取る。
# スクリプトは $G/main の中で流す。

# 使い方: new_repo <Node.js の CI の版> <Node.js の開発環境の版> <Trivy の CI の版>
#   <Terraform の CI の版> <Terraform の開発環境の版>
# Codex CLI の CI の版は 0.50.0 にする。
new_repo() {
    N=$((N + 1))
    G="$WORK/g$N"
    FAKE_MAP="$WORK/map$N.tsv"
    FAKE_LOG="$WORK/log$N.txt"
    FAKE_DIR="$G/fake"
    mkdir -p "$FAKE_DIR"
    : >"$FAKE_MAP"
    : >"$FAKE_LOG"
    mkdir -p "$G/work/.github/workflows" "$G/work/docker/frontend" "$G/work/docker/terraform"
    git init -q -b main "$G/work"
    cat >"$G/work/.github/workflows/ci.yaml" <<YAML
name: ci
jobs:
  frontend:
    steps:
      - uses: actions/setup-node@0123456789abcdef0123456789abcdef01234567 # v4.0.0
        with:
          node-version: '$1'
YAML
    cat >"$G/work/.github/workflows/codex-review.yml" <<YAML
name: codex-review
jobs:
  review:
    steps:
      - uses: actions/setup-node@0123456789abcdef0123456789abcdef01234567 # v4.0.0
        with:
          node-version: '$1'
      - uses: ./.github/actions/codex
        with:
          codex-version: '0.50.0'
YAML
    cat >"$G/work/.github/workflows/container-scan.yaml" <<YAML
name: container-scan
env:
  TRIVY_VERSION: $3
YAML
    cat >"$G/work/.github/workflows/terraform-apply.yaml" <<YAML
name: terraform-apply
env:
  TF_VERSION: $4
YAML
    printf 'FROM node:%s-bookworm-slim@%s\nRUN echo frontend\n' "$2" "$D1" >"$G/work/docker/frontend/Dockerfile"
    printf 'FROM ghcr.io/terraform-linters/tflint:v0.65.0@%s AS tflint\n\nFROM hashicorp/terraform:%s@%s\n' \
        "$D4" "$5" "$D2" >"$G/work/docker/terraform/Dockerfile"
    cat >"$G/work/.github/ci-tool-versions.json" <<'JSON'
{
  "schema": 1,
  "tools": {
    "node": {
      "name": "Node.js", "inventory_name": "Node.js", "keys": ["node-version"],
      "ci": [
        { "file": ".github/workflows/ci.yaml", "key": "node-version" },
        { "file": ".github/workflows/codex-review.yml", "key": "node-version" }
      ],
      "dev": { "file": "docker/frontend/Dockerfile", "image": "node", "hub_repository": "library/node", "tag_suffix": "-bookworm-slim" }
    },
    "trivy": {
      "name": "Trivy", "inventory_name": "Trivy", "keys": ["TRIVY_VERSION"],
      "ci": [{ "file": ".github/workflows/container-scan.yaml", "key": "TRIVY_VERSION" }]
    },
    "codex": {
      "name": "Codex CLI", "inventory_name": "Codex CLI", "keys": ["codex-version"],
      "ci": [{ "file": ".github/workflows/codex-review.yml", "key": "codex-version" }]
    },
    "terraform": {
      "name": "Terraform", "inventory_name": "Terraform", "keys": ["TF_VERSION"],
      "ci": [{ "file": ".github/workflows/terraform-apply.yaml", "key": "TF_VERSION" }],
      "dev": { "file": "docker/terraform/Dockerfile", "image": "hashicorp/terraform", "hub_repository": "hashicorp/terraform", "tag_suffix": "" }
    }
  },
  "excluded": []
}
JSON
}

# 使い方: finish。作業のリポジトリをコミットし、bare のリモートに push して main を取る
finish() {
    git -C "$G/work" add -A
    git -C "$G/work" commit -q -m main
    git init -q --bare "$G/remote.git"
    git -C "$G/work" push -q "$G/remote.git" main
    git clone -q -b main "$G/remote.git" "$G/main"
}

# 使い方: run_plan <道具> [今の時刻]。$G/main で plan を流し、$G/out と $G/err と RC に結果を入れる
run_plan() {
    (cd "$G/main" && NOW_EPOCH="${2:-$NOW}" bash "$SCRIPT" plan "$1" >"$G/out" 2>"$G/err")
    RC=$?
}

# 使い方: expect <名前> <終了コード> <標準出力の全文>
expect() {
    if [ "$RC" != "$2" ]; then
        fail "$1" "終了コードが ${RC} で、${2} ではありません。標準エラー: $(head -n 1 "$G/err")"
    elif [ "$(cat "$G/out")" != "$3" ]; then
        fail "$1" "出力が「$(cat "$G/out")」で、「$3」ではありません"
    else
        pass "$1"
    fi
}

# 使い方: expect_err <名前> <標準エラーに出るはずの文字>
expect_err() {
    if [ "$RC" != 1 ]; then
        fail "$1" "終了コードが ${RC} で、1 ではありません"
    elif [ -s "$G/out" ]; then
        fail "$1" "失敗したのに出力があります: $(cat "$G/out")"
    elif ! grep -qF "$2" "$G/err"; then
        fail "$1" "標準エラーに「$2」がありません: $(cat "$G/err")"
    else
        pass "$1"
    fi
}

T=$'\t'

# --- 上げる先の版を選ぶ -----------------------------------------------------

if want newest_old; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    trivy_list "0.62.0=$YOUNG" "0.61.1=$OLD" "0.61.0=$OLDER" "0.60.0=$OLDER"
    trivy_rel 0.61.1 "$OLD"
    run_plan trivy
    expect "72時間経った版のうち最も新しい版を選ぶ" 0 "0.61.1${T}0.60.0${T}-${T}${OLD}${T}-${T}-"
fi

if want only_young; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    trivy_list "0.61.0=$YOUNG" "0.60.0=$OLDER"
    run_plan trivy
    expect "72時間経っていない版しか無いと、書き換え先の版を出さない" 0 ""
fi

if want other_major; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    trivy_list "1.0.0=$OLD" "0.60.0=$OLDER"
    run_plan trivy
    expect "メジャー版の違う版しか無いと、書き換え先の版を出さない" 0 ""
fi

if want no_change; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    node_list 24.22.2 24.22.1
    run_plan node
    expect "上げる先の版が無く、開発環境と CI の版が同じなら、書き換え先の版を出さない" 0 ""
fi

if want young_image; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    node_list 24.24.0 24.23.0 24.22.2
    node_rel 24.24.0 "$OLD"
    node_rel 24.23.0 "$OLD"
    node_tag 24.24.0 "$D3" "$YOUNG"
    node_tag 24.23.0 "$D3" "$OLD"
    run_plan node
    expect "Node.js で、イメージのタグが72時間経っていない版を飛ばし、1つ前の版を選ぶ" 0 \
        "24.23.0${T}24.22.2${T}24.22.2${T}${OLD}${T}${D3}${T}${OLD}"
fi

# --- 開発環境と CI の版をそろえる -------------------------------------------

if want dev_newer; then
    # 開発環境の版 1.17.1 は、上げる先の版 1.16.2 より新しい
    new_repo 24.22.2 24.22.2 0.60.0 1.16.0 1.17.1
    finish
    tf_rel 1.16.0 "$OLDER"
    tf_list "1.16.2=$OLD" "1.16.0=$OLDER"
    tf_tag 1.16.2 "$D3" "$OLD"
    tf_rel 1.17.1 "$OLD"
    tf_tag 1.17.1 "$D3" "$OLD"
    run_plan terraform
    expect "開発環境の版が上げる先の版より新しいとき、CI の版を開発環境の版に上げ、開発環境の版を下げない" 0 \
        "1.17.1${T}1.16.0${T}1.17.1${T}${OLD}${T}${D3}${T}${OLD}"
fi

if want align; then
    # CI の版だけを先に 24.23.0 に上げてあり、24.23.0 より新しい版は無い
    new_repo 24.23.0 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    node_list 24.23.0 24.22.2
    node_rel 24.23.0 "$OLD"
    node_tag 24.23.0 "$D3" "$OLD"
    run_plan node
    expect "上げる先の版が無く、開発環境と CI の版が違うとき、新しいほうにそろえる" 0 \
        "24.23.0${T}24.23.0${T}24.22.2${T}${OLD}${T}${D3}${T}${OLD}"
fi

if want align_young_image; then
    # CI の版を開発環境の版にそろえる。開発環境の行は変わらないので、公開からの時間の判定は
    # CI の版だけを調べる。イメージのタグは、この場合も確かめる
    new_repo 24.22.2 24.23.0 0.60.0 1.17.1 1.17.1
    finish
    node_list 24.23.0 24.22.2
    node_rel 24.23.0 "$OLD"
    node_tag 24.23.0 "$D3" "$YOUNG"
    run_plan node
    if [ "$RC" != 0 ] || [ -s "$G/out" ]; then
        fail "そろえる先のイメージのタグが72時間経っていなければ、書き換え先の版を出さない" \
            "CI の版を開発環境の版にそろえる場合で、終了コード ${RC}、出力「$(cat "$G/out")」でした"
    else
        # 開発環境の版を CI の版にそろえる
        new_repo 24.23.0 24.22.2 0.60.0 1.17.1 1.17.1
        finish
        node_list 24.23.0 24.22.2
        node_rel 24.23.0 "$OLD"
        node_tag 24.23.0 "$D3" "$YOUNG"
        run_plan node
        expect "そろえる先のイメージのタグが72時間経っていなければ、書き換え先の版を出さない" 0 ""
    fi
fi

if want manual_ci; then
    # CI の版 24.23.0 は、72時間待たずに手で入れた版で、公開は YOUNG
    new_repo 24.23.0 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    node_list 24.23.0 24.22.2
    node_rel 24.23.0 "$YOUNG"
    node_tag 24.23.0 "$D3" "$OLD"
    run_plan node
    if [ "$RC" != 0 ] || [ -s "$G/out" ]; then
        fail "72時間待たずに手で入れた CI の版を、72時間経つまで書き換え先にしない" \
            "72時間経つ前に、終了コード ${RC}、出力「$(cat "$G/out")」でした"
    else
        run_plan node "$LATER"
        expect "72時間待たずに手で入れた CI の版を、72時間経つまで書き換え先にしない" 0 \
            "24.23.0${T}24.23.0${T}24.22.2${T}${YOUNG}${T}${D3}${T}${OLD}"
    fi
fi

# --- 更新の PR の題名と本文 -------------------------------------------------

# 使い方: run_body <plan の1行を空白で区切った引数>...。$G/main で body を流し、$G/out と $G/err と RC に結果を入れる
run_body() {
    (cd "$G/main" && NOW_EPOCH="$NOW" bash "$SCRIPT" body "$@" >"$G/out" 2>"$G/err")
    RC=$?
}

# 使い方: body_has <名前> <行>...。body が 0 で終わり、渡した行がどれも出力に1行そのままあれば通る
body_has() {
    local n="$1" l
    shift
    if [ "$RC" != 0 ]; then
        fail "$n" "終了コードが ${RC} で、0 ではありません。標準エラー: $(head -n 1 "$G/err")"
        return
    fi
    for l in "$@"; do
        if ! grep -qxF -- "$l" "$G/out"; then
            fail "$n" "出力に「${l}」の行がありません"
            return
        fi
    done
    pass "$n"
}

# 使い方: body_lacks <文字>。出力に渡した文字があれば 1 を返す
body_lacks() {
    ! grep -qF -- "$1" "$G/out"
}

# Trivy の CI の版を 0.60.0 から 0.61.1 に上げる本文。0.62.0 は書き換え先の版より新しい
trivy_body() {
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    trivy_list "0.62.0=$YOUNG" "0.61.1=$OLD" "0.61.0=$OLDER" "0.60.0=$OLDER"
    run_body trivy 0.61.1 0.60.0 - "$OLD" - -
}

# Node.js の CI と開発環境の版を 24.22.2 から 24.23.0 に上げる本文
node_body() {
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    node_list 24.23.0 24.22.2
    node_rel 24.23.0 "$OLD"
    run_body node 24.23.0 24.22.2 24.22.2 "$OLD" "$D3" "$OLD"
}

# Terraform の CI と開発環境の版を 1.17.1 から 1.17.2 に上げる本文
tf_body() {
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    tf_rel 1.17.1 "$OLDER"
    tf_list "1.17.2=$OLD" "1.17.1=$OLDER"
    run_body terraform 1.17.2 1.17.1 1.17.1 "$OLD" "$D3" "$OLD"
}

if want ci_title; then
    trivy_body
    if [ "$RC" = 0 ] && [ "$(head -n 1 "$G/out")" != "chore: CI の Trivy を 0.61.1 に上げる" ]; then
        fail "CI の版が変わる PR の題名に道具の名前と書き換え先の版が入る" "題名が「$(head -n 1 "$G/out")」です"
    else
        body_has "CI の版が変わる PR の題名に道具の名前と書き換え先の版が入る" "chore: CI の Trivy を 0.61.1 に上げる"
    fi
fi

if want dev_title; then
    # CI の版は 24.23.0 で、開発環境の版 24.22.2 だけを 24.23.0 にそろえる
    new_repo 24.23.0 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    node_list 24.23.0 24.22.2
    node_rel 24.23.0 "$OLD"
    run_body node 24.23.0 24.23.0 24.22.2 "$OLD" "$D3" "$OLD"
    if [ "$RC" = 0 ] && [ "$(head -n 1 "$G/out")" != "chore: Node.js の開発環境の版を CI の版 24.23.0 にそろえる" ]; then
        fail "開発環境の版だけが変わる PR の題名に道具の名前と書き換え先の版が入る" "題名が「$(head -n 1 "$G/out")」です"
    else
        body_has "開発環境の版だけが変わる PR の題名に道具の名前と書き換え先の版が入る" \
            "chore: Node.js の開発環境の版を CI の版 24.23.0 にそろえる"
    fi
fi

if want table_ci; then
    trivy_body
    if [ "$RC" = 0 ] && ! body_lacks "| 開発環境"; then
        fail "本文の版の表に今の CI の版と書き換え先の版が入る" "開発環境の無い Trivy の表に開発環境の行があります"
    else
        body_has "本文の版の表に今の CI の版と書き換え先の版が入る" \
            "| 書き場所 | 今の版 | 書き換え先の版 |" \
            "| CI(\`.github/workflows/container-scan.yaml\`) | 0.60.0 | 0.61.1 |"
    fi
fi

if want table_dev; then
    node_body
    body_has "Node.js と Terraform の本文の版の表に開発環境の行が入る(Node.js)" \
        "| CI(\`.github/workflows/ci.yaml\`、\`.github/workflows/codex-review.yml\`) | 24.22.2 | 24.23.0 |" \
        "| 開発環境(\`docker/frontend/Dockerfile\`) | 24.22.2 | 24.23.0 |"
    tf_body
    body_has "Node.js と Terraform の本文の版の表に開発環境の行が入る" \
        "| CI(\`.github/workflows/terraform-apply.yaml\`) | 1.17.1 | 1.17.2 |" \
        "| 開発環境(\`docker/terraform/Dockerfile\`) | 1.17.1 | 1.17.2 |"
fi

if want pub_source; then
    trivy_body
    body_has "本文に書き換え先の版の公開日時と取り先が入る" \
        "- 0.61.1 の公開日時: ${OLD}(取り先: https://api.github.com/repos/aquasecurity/trivy/releases/tags/v0.61.1 の \`published_at\`)"
fi

if want image; then
    trivy_body
    if [ "$RC" = 0 ] && ! body_lacks "配布元のイメージのタグ"; then
        fail "Node.js と Terraform の本文に配布元のイメージのタグと digest と公開日時が入る" "Trivy の本文にイメージのタグがあります"
    else
        node_body
        body_has "Node.js と Terraform の本文に配布元のイメージのタグと digest と公開日時が入る(Node.js)" \
            "- 配布元のイメージのタグ \`node:24.23.0-bookworm-slim\`" \
            "  - digest: \`${D3}\`" \
            "  - 公開日時: ${OLD}(取り先: https://hub.test/v2/namespaces/library/repositories/node/tags/24.23.0-bookworm-slim の \`tag_last_pushed\`)"
        tf_body
        body_has "Node.js と Terraform の本文に配布元のイメージのタグと digest と公開日時が入る" \
            "- 配布元のイメージのタグ \`hashicorp/terraform:1.17.2\`" \
            "  - digest: \`${D3}\`" \
            "  - 公開日時: ${OLD}(取り先: https://hub.test/v2/namespaces/hashicorp/repositories/terraform/tags/1.17.2 の \`tag_last_pushed\`)"
    fi
fi

if want notes_links; then
    # Trivy: 0.60.0 より新しく 0.61.1 以下の 0.61.1 と 0.61.0 だけ。0.62.0 と 0.60.0 は入らない
    trivy_body
    got=$(grep -F -- '- [' "$G/out")
    exp="- [0.61.1](https://github.com/aquasecurity/trivy/releases/tag/v0.61.1)
- [0.61.0](https://github.com/aquasecurity/trivy/releases/tag/v0.61.0)"
    if [ "$RC" != 0 ] || [ "$got" != "$exp" ]; then
        fail "今の版と書き換え先の版のあいだの版ごとに、変更点の文書のリンクが入る" "Trivy の変更点が「${got}」でした"
    else
        # Node.js: 開発環境の版 24.22.2 が CI の版 24.23.0 より古いので、24.22.2 より新しい版から数える
        new_repo 24.23.0 24.22.2 0.60.0 1.17.1 1.17.1
        finish
        node_list 24.23.0 24.22.3 24.22.2
        node_rel 24.23.0 "$OLD"
        node_rel 24.22.3 "$OLDER"
        run_body node 24.23.0 24.23.0 24.22.2 "$OLD" "$D3" "$OLD"
        got=$(grep -F -- '- [' "$G/out")
        exp="- [24.23.0](https://github.com/nodejs/node/releases/tag/v24.23.0)
- [24.22.3](https://github.com/nodejs/node/releases/tag/v24.22.3)"
        if [ "$RC" != 0 ] || [ "$got" != "$exp" ]; then
            fail "今の版と書き換え先の版のあいだの版ごとに、変更点の文書のリンクが入る" "Node.js の変更点が「${got}」でした"
        else
            pass "今の版と書き換え先の版のあいだの版ごとに、変更点の文書のリンクが入る"
        fi
    fi
fi

if want tf_section; then
    trivy_body
    if [ "$RC" = 0 ] && ! body_lacks "## 本番に適用する Terraform の版"; then
        fail "Terraform の本文に本番に適用する Terraform の版の節が入り、ほかの道具の本文には入らない" "Trivy の本文に節があります"
    else
        node_body
        if [ "$RC" = 0 ] && ! body_lacks "## 本番に適用する Terraform の版"; then
            fail "Terraform の本文に本番に適用する Terraform の版の節が入り、ほかの道具の本文には入らない" "Node.js の本文に節があります"
        else
            tf_body
            body_has "Terraform の本文に本番に適用する Terraform の版の節が入り、ほかの道具の本文には入らない" \
                "## 本番に適用する Terraform の版" \
                "本番に適用するワークフロー(\`.github/workflows/terraform-apply.yaml\`)の Terraform の版が、1.17.1 から 1.17.2 に変わります。新しい版が本番に使われるのは、この PR のマージのあとに、誰かが本番に適用するワークフローを動かしたときです。"
        fi
    fi
fi

if want refs_last; then
    trivy_body
    if [ "$RC" != 0 ] || [ "$(tail -n 1 "$G/out")" != "Refs: N/A" ]; then
        fail "本文の最後の行が Refs: N/A になる" "終了コード ${RC}、最後の行「$(tail -n 1 "$G/out")」でした"
    else
        pass "本文の最後の行が Refs: N/A になる"
    fi
fi

if want bad_values; then
    # 配布元が返した digest の形が違う
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    node_list 24.23.0 24.22.2
    node_rel 24.23.0 "$OLD"
    node_tag 24.23.0 "sha256:\$(id)" "$OLD"
    run_plan node
    if [ "$RC" != 1 ] || [ -s "$G/out" ] || ! grep -qF "digest の形が違います" "$G/err"; then
        fail "配布元が返した版か digest が形に当たらなければ、その道具を失敗にする" \
            "digest の形が違う plan が、終了コード ${RC}、出力「$(cat "$G/out")」、標準エラー「$(head -n 1 "$G/err")」でした"
    else
        # 版の形が違う値を本文に入れない
        trivy_list "0.61.1=$OLD" "0.60.0=$OLDER"
        run_body trivy '0.61.1`x' 0.60.0 - "$OLD" - -
        # lib の civ_gt も同じ言葉を出すので、body が出す文そのもので確かめる
        if [ "$RC" != 1 ] || [ -s "$G/out" ] || ! grep -qF '版の形が違います(0.61.1`x 0.60.0)' "$G/err"; then
            fail "配布元が返した版か digest が形に当たらなければ、その道具を失敗にする" \
                "版の形が違う body が、終了コード ${RC}、標準エラー「$(head -n 1 "$G/err")」でした"
        else
            run_body trivy 0.61.1 0.60.0 - '2026-01-01`x' - -
            if [ "$RC" != 1 ] || [ -s "$G/out" ] || ! grep -qF "の公開日時の形が違います" "$G/err"; then
                fail "配布元が返した版か digest が形に当たらなければ、その道具を失敗にする" \
                    "公開日時の形が違う body が、終了コード ${RC}、標準エラー「$(head -n 1 "$G/err")」でした"
            else
                # 開発環境の無い道具に、開発環境の版を渡さない
                run_body trivy 0.61.1 0.60.0 0.61.1 "$OLD" - -
                if [ "$RC" != 1 ] || [ -s "$G/out" ] || ! grep -qF "には開発環境の書き場所が無いのに" "$G/err"; then
                    fail "配布元が返した版か digest が形に当たらなければ、その道具を失敗にする" \
                        "開発環境の無い Trivy に開発環境の版を渡した body が、終了コード ${RC}、標準エラー「$(head -n 1 "$G/err")」でした"
                else
                    run_body node 24.23.0 24.22.2 24.22.2 "$OLD" "sha256:\$(id)" "$OLD"
                    expect_err "配布元が返した版か digest が形に当たらなければ、その道具を失敗にする" "digest か公開日時の形が違います"
                fi
            fi
        fi
    fi
fi

# --- 新しい版を調べられないとき ---------------------------------------------

if want ci_differ; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    sed -i "s|node-version: '24.22.2'|node-version: '24.22.1'|" "$G/work/.github/workflows/ci.yaml"
    finish
    run_plan node
    expect_err "CI の版が場所によって違えば、新しい版を調べられない" "CI の版が場所によって違います(24.22.1 24.22.2)"
fi

if want dev_major; then
    new_repo 24.22.2 22.20.0 0.60.0 1.17.1 1.17.1
    finish
    run_plan node
    expect_err "開発環境の版のメジャー版が CI の版と違えば、新しい版を調べられない" \
        "開発環境の版 22.20.0 のメジャー版が CI の版 24.22.2 と違います"
fi

if want no_hub; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    sed -i 's|"hub_repository": "library/node", ||' "$G/work/.github/ci-tool-versions.json"
    finish
    run_plan node
    expect_err "開発環境の hub_repository が無ければ、新しい版を調べられない" \
        "データのファイルの node の hub_repository か tag_suffix の形が違います"
fi

if want bad_args; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    (cd "$G/main" && bash "$SCRIPT" plan java >"$G/out" 2>"$G/err")
    RC=$?
    if [ "$RC" != 2 ] || [ -s "$G/out" ]; then
        expect "知らない道具を渡すと終了コード 2 になる" 2 ""
    else
        run_body java 0.61.1 0.60.0 - "$OLD" - -
        expect "知らない道具を渡すと終了コード 2 になる" 2 ""
    fi
fi

# --- ファイルを書き換えて、道具ごとに更新の PR を作る -----------------------

# 使い方: quiet <道具>...。渡した道具に、上げる先の版が無い応答を足す。
# 版は new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1 のリポジトリに合わせる
quiet() {
    local t
    for t in "$@"; do
        case "$t" in
        node) node_list 24.22.2 24.22.1 ;;
        trivy) trivy_list "0.60.0=$OLDER" ;;
        codex) fx curl "https://npm.test/@openai%2fcodex" 200 "{\"time\":{\"created\":\"$OLDER\",\"0.50.0\":\"$OLDER\"}}" ;;
        terraform)
            tf_rel 1.17.1 "$OLDER"
            tf_list "1.17.1=$OLDER"
            ;;
        esac
    done
}

# Node.js の CI と開発環境の版を 24.22.2 から 24.23.0 に上げる応答
node_up() {
    node_list 24.23.0 24.22.2
    node_rel 24.23.0 "$OLD"
    node_tag 24.23.0 "$D3" "$OLD"
}

# Trivy の CI の版を 0.60.0 から 0.61.1 に上げる応答
trivy_up() {
    trivy_list "0.61.1=$OLD" "0.60.0=$OLDER"
    trivy_rel 0.61.1 "$OLD"
}

# 使い方: run_run [GH_TOKEN]。$G/main で run を流し、$G/out と $G/err と RC に結果を入れる
run_run() {
    (cd "$G/main" && NOW_EPOCH="$NOW" GH_TOKEN="${1-bot-pat}" GITHUB_REPOSITORY=owner/repo \
        CI_TOOL_UPDATE_REPORT="$G/report.md" bash "$SCRIPT" run >"$G/out" 2>"$G/err")
    RC=$?
}

# 使い方: rgit <git の引数>...。bare のリモートで git を流す
rgit() {
    git -C "$G/remote.git" "$@"
}

# 使い方: branch_ok <名前> <道具> <ファイル>=<あるはずの行>...
# リモートの道具のブランチが、main を親とする1つのコミットで、作者が bot で、
# 渡したファイルに渡した行があれば通る
branch_ok() {
    local n="$1" b="refs/heads/chore/ci-tool-version-update-$2" p f l
    shift 2
    if [ "$RC" != 0 ]; then
        fail "$n" "終了コードが ${RC} で、0 ではありません。標準エラー: $(head -n 1 "$G/err")"
        return
    fi
    if ! rgit rev-parse -q --verify "$b" >/dev/null; then
        fail "$n" "リモートに ${b} がありません"
        return
    fi
    if [ "$(rgit rev-parse "${b}^")" != "$(rgit rev-parse refs/heads/main)" ]; then
        fail "$n" "${b} の親が main ではありません"
        return
    fi
    if [ "$(rgit log -1 --format='%an %ae' "$b")" != "keirekipro-ci-tool-update-bot ci-tool-update-bot@users.noreply.github.com" ]; then
        fail "$n" "コミットの作者が「$(rgit log -1 --format='%an %ae' "$b")」です"
        return
    fi
    for p in "$@"; do
        f="${p%%=*}"
        l="${p#*=}"
        if ! rgit show "${b}:${f}" | grep -qxF -- "$l"; then
            fail "$n" "${b} の ${f} に「${l}」の行がありません"
            return
        fi
    done
    pass "$n"
}

if want pr_one; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    node_up
    quiet trivy codex terraform
    run_run
    branch_ok "道具ごとのブランチに、CI の版と開発環境の版を書き換えたコミットを push し、PR を作る" node \
        ".github/workflows/ci.yaml=          node-version: '24.23.0'" \
        ".github/workflows/codex-review.yml=          node-version: '24.23.0'" \
        "docker/frontend/Dockerfile=FROM node:24.23.0-bookworm-slim@${D3}"
    n="更新の PR を、道具のブランチから main に、本文と同じ題名で作る"
    if [ "$RC" != 0 ]; then
        fail "$n" "終了コードが ${RC} です"
    elif ! grep -qF "gh pr create --repo owner/repo --base main --head chore/ci-tool-version-update-node " "$FAKE_LOG"; then
        fail "$n" "道具のブランチから main への pr create がありません"
    elif [ "$(cat "$FAKE_DIR/title-node" 2>/dev/null)" != "chore: CI の Node.js を 24.23.0 に上げる" ] ||
        [ "$(head -n 1 "$FAKE_DIR/body-node")" != "## 概要" ] ||
        [ "$(rgit log -1 --format=%s refs/heads/chore/ci-tool-version-update-node)" != "chore: CI の Node.js を 24.23.0 に上げる" ]; then
        fail "$n" "題名か本文かコミットの1行目が違います: $(cat "$FAKE_DIR/title-node" 2>/dev/null)"
    elif [ "$(grep -c 'gh pr create' "$FAKE_LOG")" != 1 ]; then
        fail "$n" "上げる先の版の無い道具にも PR を作りました"
    else
        pass "$n"
    fi
fi

if want pr_two; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    node_up
    trivy_up
    quiet codex terraform
    run_run
    n="2つの道具に書き換え先の版があれば、PR を2つ作る"
    if [ "$RC" != 0 ]; then
        fail "$n" "終了コードが ${RC} で、0 ではありません。標準エラー: $(head -n 1 "$G/err")"
    elif [ "$(grep -c 'gh pr create' "$FAKE_LOG")" != 2 ] ||
        [ "$(cat "$FAKE_DIR/title-trivy" 2>/dev/null)" != "chore: CI の Trivy を 0.61.1 に上げる" ] ||
        [ "$(cat "$FAKE_DIR/title-node" 2>/dev/null)" != "chore: CI の Node.js を 24.23.0 に上げる" ]; then
        fail "$n" "PR が道具ごとに1つずつありません: $(grep 'gh pr create' "$FAKE_LOG" | cut -c 1-120)"
    else
        branch_ok "$n" trivy ".github/workflows/container-scan.yaml=  TRIVY_VERSION: 0.61.1"
        # Trivy のブランチに Node.js の書き換えが混ざらない
        if rgit show refs/heads/chore/ci-tool-version-update-trivy:docker/frontend/Dockerfile | grep -qF 24.23.0; then
            fail "${n}(ブランチが分かれる)" "Trivy のブランチに Node.js の書き換えがあります"
        fi
    fi
    n="PR を閉じる操作とマージの操作を呼ばない"
    if grep -qE '^gh pr (close|merge)|^gh api .*(merge|state=closed)' "$FAKE_LOG"; then
        fail "$n" "$(grep -E '^gh pr (close|merge)|^gh api .*(merge|state=closed)' "$FAKE_LOG" | head -n 1)"
    elif [ "$(grep -c '^gh ' "$FAKE_LOG")" = 0 ]; then
        fail "$n" "gh が呼ばれていません"
    else
        pass "$n"
    fi
fi

if want pr_closed; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    # 所有者が閉じた PR のブランチ。main の上に、書き換えと関係の無い古いコミットが残っている
    git -C "$G/work" switch -q -c old
    echo stale >"$G/work/stale.txt"
    git -C "$G/work" add stale.txt
    git -C "$G/work" commit -q -m stale
    git -C "$G/work" push -q "$G/remote.git" old:refs/heads/chore/ci-tool-version-update-trivy
    trivy_up
    quiet node codex terraform
    run_run
    branch_ok "閉じた PR のブランチが残っていても、ブランチを作り直して PR を作る" trivy \
        ".github/workflows/container-scan.yaml=  TRIVY_VERSION: 0.61.1"
    if rgit cat-file -e refs/heads/chore/ci-tool-version-update-trivy:stale.txt 2>/dev/null; then
        fail "閉じた PR のブランチが残っていても、ブランチを作り直して PR を作る" "古いブランチのコミットが残っています"
    fi
fi

if want pr_token; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    trivy_up
    quiet node codex terraform
    run_run bot-pat
    n="GH_TOKEN の bot の PAT で push し、PR を作る"
    first=$(grep -n '^gh auth setup-git ' "$FAKE_LOG" | head -n 1 | cut -d: -f1)
    if [ "$RC" != 0 ]; then
        fail "$n" "終了コードが ${RC} です。標準エラー: $(head -n 1 "$G/err")"
    elif [ -z "$first" ] || ! grep -qF 'gh auth setup-git  GH_TOKEN=bot-pat' "$FAKE_LOG"; then
        fail "$n" "push の前に GH_TOKEN の PAT で gh auth setup-git を呼んでいません"
    elif [ "$first" -ne 1 ]; then
        fail "$n" "gh auth setup-git が最初の gh の呼び出しではありません"
    elif ! grep 'gh pr create' "$FAKE_LOG" | grep -qF 'GH_TOKEN=bot-pat'; then
        fail "$n" "pr create に GH_TOKEN の PAT が渡っていません"
    else
        pass "$n"
    fi
    # GH_TOKEN が無ければ、何も push せずに終了コード 2 で終わる
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    trivy_up
    quiet node codex terraform
    run_run ""
    if [ "$RC" != 2 ] || [ -s "$FAKE_LOG" ] || rgit rev-parse -q --verify refs/heads/chore/ci-tool-version-update-trivy >/dev/null; then
        fail "$n" "GH_TOKEN が無いのに終了コードが ${RC} で、問い合わせか push をしました"
    fi
fi

if want codex_once; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    fx curl "https://npm.test/@openai%2fcodex" 200 \
        "{\"time\":{\"created\":\"$OLDER\",\"0.50.0\":\"$OLDER\",\"0.51.0\":\"$OLD\",\"0.52.0\":\"$YOUNG\"}}"
    quiet node trivy terraform
    run_run
    branch_ok "Codex CLI の版を書き換えた PR を作る" codex \
        ".github/workflows/codex-review.yml=          codex-version: '0.51.0'"
    n="1回の実行で、npm の registry の Codex CLI の JSON を1回だけ取る"
    c=$(grep -cxF "curl https://npm.test/@openai%2fcodex" "$FAKE_LOG")
    if [ "$RC" != 0 ] || [ "$c" != 1 ]; then
        fail "$n" "終了コードが ${RC} で、JSON を ${c} 回取りました"
    else
        pass "$n"
    fi
fi

# --- 開いている PR を書き換える ---------------------------------------------

# 使い方: open_pr <道具> <P> <C> <D> <digest> <mergeable> [headRefOid]
# main から、道具の版を P に書き換えたブランチを作ってリモートに置き、開いている
# 更新の PR(番号 7)として pr list が返すようにする。headRefOid を渡さなければ、
# 置いたブランチの先頭にする
open_pr() {
    local b="chore/ci-tool-version-update-$1" oid
    if ! (cd "$G/main" && git switch -q -c "pr-$1" origin/main &&
        bash "$SCRIPT" rewrite "$1" "$2" "$3" "$4" "$5" >/dev/null 2>&1 &&
        git push -q origin "HEAD:refs/heads/$b" && git switch -q main); then
        fail "PR のブランチを置く" "$1 のブランチを置けませんでした"
    fi
    oid="${7:-$(rgit rev-parse "refs/heads/$b")}"
    printf '[{"number":7,"headRefOid":"%s","mergeable":"%s"}]\n' "$oid" "$6" >"$FAKE_DIR/prs-$1.json"
    PR_HEAD=$(rgit rev-parse "refs/heads/$b")
}

# 使い方: main_moves。PR を置いたあとに、書き換えと関係の無いコミットを main に足す
main_moves() {
    echo later >"$G/work/later.txt"
    git -C "$G/work" switch -q main
    git -C "$G/work" add later.txt
    git -C "$G/work" commit -q -m later
    git -C "$G/work" push -q "$G/remote.git" main
}

# 使い方: rebuilt <道具>。リモートの道具のブランチが、PR を置いたときの先頭から変わり、
# 今の main を親にしていれば 0 を返す
rebuilt() {
    local b="refs/heads/chore/ci-tool-version-update-$1"
    [ "$(rgit rev-parse "$b")" != "$PR_HEAD" ] && [ "$(rgit rev-parse "${b}^")" = "$(rgit rev-parse refs/heads/main)" ]
}

if want open_newer; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    open_pr node 24.22.3 24.22.2 24.22.2 "$D4" MERGEABLE
    main_moves
    node_up
    quiet trivy codex terraform
    run_run
    n="開いている PR の版より新しい版があれば、ブランチを作り直して PR を書き換える"
    if [ "$RC" != 0 ]; then
        fail "$n" "終了コードが ${RC} です。標準エラー: $(head -n 1 "$G/err")"
    elif ! rebuilt node; then
        fail "$n" "ブランチが今の main から作り直されていません"
    elif grep -qF 'gh pr create' "$FAKE_LOG"; then
        fail "$n" "開いている PR があるのに、新しい PR を作りました"
    elif [ "$(cat "$FAKE_DIR/edit-title-7" 2>/dev/null)" != "chore: CI の Node.js を 24.23.0 に上げる" ] ||
        [ "$(head -n 1 "$FAKE_DIR/edit-body-7")" != "## 概要" ]; then
        fail "$n" "PR 7 の題名と本文が書き換えられていません: $(cat "$FAKE_DIR/edit-title-7" 2>/dev/null)"
    else
        branch_ok "$n" node ".github/workflows/ci.yaml=          node-version: '24.23.0'" \
            "docker/frontend/Dockerfile=FROM node:24.23.0-bookworm-slim@${D3}"
    fi
fi

if want open_same; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    open_pr node 24.23.0 24.22.2 24.22.2 "$D3" MERGEABLE
    main_moves
    node_up
    quiet trivy codex terraform
    run_run
    n="開いている PR と同じ版で中身も同じなら push しない"
    if [ "$RC" != 0 ]; then
        fail "$n" "終了コードが ${RC} です。標準エラー: $(head -n 1 "$G/err")"
    elif [ "$(rgit rev-parse refs/heads/chore/ci-tool-version-update-node)" != "$PR_HEAD" ]; then
        fail "$n" "ブランチを push しました"
    elif grep -qE 'gh pr (create|edit)' "$FAKE_LOG"; then
        fail "$n" "PR を作るか書き換えました"
    else
        pass "$n"
    fi
fi

if want open_digest; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    # 配布元が 24.23.0 のタグを公開し直し、digest が D4 から D3 に変わった
    open_pr node 24.23.0 24.22.2 24.22.2 "$D4" MERGEABLE
    main_moves
    node_up
    quiet trivy codex terraform
    run_run
    n="開いている PR の FROM の digest が変わっていれば書き換える"
    if [ "$RC" != 0 ]; then
        fail "$n" "終了コードが ${RC} です。標準エラー: $(head -n 1 "$G/err")"
    elif ! rebuilt node || [ ! -f "$FAKE_DIR/edit-title-7" ]; then
        fail "$n" "ブランチを作り直して PR を書き換えていません"
    else
        branch_ok "$n" node "docker/frontend/Dockerfile=FROM node:24.23.0-bookworm-slim@${D3}"
    fi
fi

if want open_conflict; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    open_pr node 24.23.0 24.22.2 24.22.2 "$D3" CONFLICTING
    main_moves
    node_up
    quiet trivy codex terraform
    run_run
    n="開いている PR が CONFLICTING なら書き換える"
    if [ "$RC" != 0 ]; then
        fail "$n" "終了コードが ${RC} です。標準エラー: $(head -n 1 "$G/err")"
    elif ! rebuilt node || [ ! -f "$FAKE_DIR/edit-title-7" ]; then
        fail "$n" "ブランチを作り直して PR を書き換えていません"
    else
        pass "$n"
    fi
fi

# --- 失敗を報告のファイルに書く ---------------------------------------------

# 使い方: report_ok <行の始まり> [行の数]。run が 1 で終わり、報告のファイルが渡した数
# (既定 1)の行で、渡した文字で始まる行があれば 0 を返す。違えば WHY に理由を入れて 1 を返す
report_ok() {
    local c l
    c=$(grep -c . "$G/report.md" 2>/dev/null)
    if [ "$RC" != 1 ]; then
        WHY="終了コードが ${RC} で、1 ではありません"
        return 1
    fi
    if [ "${c:-0}" != "${2:-1}" ]; then
        WHY="報告のファイルの行の数が ${c:-0} です: $(cat "$G/report.md" 2>/dev/null)"
        return 1
    fi
    while IFS= read -r l; do
        [[ "$l" == "$1"* ]] && return 0
    done <"$G/report.md"
    WHY="報告のファイルに「$1」で始まる行がありません: $(cat "$G/report.md")"
    return 1
}

if want one_fail; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    # 最初に調べる Node.js の応答を置かないので、Node.js の問い合わせは失敗する
    trivy_up
    quiet codex terraform
    run_run
    n="1つの道具の問い合わせが失敗しても、ほかの道具の PR を作り、報告のファイルにその道具の1行を書いて 1 で終わる"
    if ! report_ok "- Node.js: 新しい版を調べられなかった("; then
        fail "$n" "$WHY"
    elif [ "$(cat "$FAKE_DIR/title-trivy" 2>/dev/null)" != "chore: CI の Trivy を 0.61.1 に上げる" ]; then
        fail "$n" "Trivy の PR を作っていません"
    else
        pass "$n"
    fi
fi

if want fail_query; then
    n="版の一覧とイメージのタグと変わる場所の判定のそれぞれの問い合わせが失敗したときと、イメージのタグが無いときに、PR を作らずに、新しい版を調べられなかったの1行を書く"
    bad=""
    for k in list tag_error tag_missing age; do
        new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
        finish
        quiet codex terraform
        case "$k" in
        list)
            quiet node
            want_line="- Trivy: 新しい版を調べられなかった(版の一覧を取れませんでした("
            ;;
        tag_error | tag_missing)
            quiet trivy
            node_list 24.23.0 24.22.2
            node_rel 24.23.0 "$OLD"
            if [ "$k" = tag_error ]; then
                fx curl "https://hub.test/v2/namespaces/library/repositories/node/tags/24.23.0-bookworm-slim" 500 '{}'
            fi
            want_line="- Node.js: 新しい版を調べられなかった(イメージのタグ library/node:24.23.0-bookworm-slim を取れませんでした("
            ;;
        age)
            quiet node
            # 一覧はあるが、書き換え先の版の公開日時を問い合わせると失敗する
            trivy_list "0.61.1=$OLD" "0.60.0=$OLDER"
            want_line="- Trivy: 新しい版を調べられなかった(変わる場所が公開からの時間の検査を通るかを調べられませんでした("
            ;;
        esac
        run_run
        if ! report_ok "$want_line"; then
            bad="${k}: ${WHY}"
            break
        elif grep -qF 'gh pr create' "$FAKE_LOG"; then
            bad="${k}: PR を作りました"
            break
        fi
    done
    if [ -n "$bad" ]; then fail "$n" "$bad"; else pass "$n"; fi
fi

if want fail_ci; then
    n="CI の版が場所によって違うときと、開発環境の版のメジャー版が CI の版と違うときに、新しい版を調べられなかったの1行を書く"
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    sed -i "s|node-version: '24.22.2'|node-version: '24.22.1'|" "$G/work/.github/workflows/ci.yaml"
    finish
    quiet trivy codex terraform
    run_run
    if ! report_ok "- Node.js: 新しい版を調べられなかった(CI の版が場所によって違います(24.22.1 24.22.2))"; then
        fail "$n" "CI の版が違うとき: $WHY"
    else
        new_repo 24.22.2 22.20.0 0.60.0 1.17.1 1.17.1
        finish
        quiet trivy codex terraform
        run_run
        if ! report_ok "- Node.js: 新しい版を調べられなかった(開発環境の版 22.20.0 のメジャー版が CI の版 24.22.2 と違います)"; then
            fail "$n" "メジャー版が違うとき: $WHY"
        else
            pass "$n"
        fi
    fi
fi

if want fail_create; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    trivy_up
    quiet node codex terraform
    FAKE_PR_CREATE_FAIL=1 run_run
    n="PR を作る操作が失敗したら、更新の PR を作れなかったの1行を書く"
    if ! report_ok "- Trivy: 更新の PR を作れなかった(PR を作る操作が失敗しました(pull request create failed: HTTP 422))"; then
        fail "$n" "$WHY"
    else
        pass "$n"
    fi
fi

if want fail_push; then
    new_repo 24.22.2 24.22.2 0.60.0 1.17.1 1.17.1
    finish
    # pr list が返す headRefOid を古くする。PR を見たあとに、ほかのワークフローが
    # ブランチを更新したときに当たる
    open_pr node 24.22.3 24.22.2 24.22.2 "$D4" MERGEABLE "$(rgit rev-parse refs/heads/main)"
    node_up
    quiet trivy codex terraform
    run_run
    n="書き換えの push が失敗したら、更新の PR を書き換えられなかったの1行を書く"
    if ! report_ok "- Node.js: 更新の PR を書き換えられなかった(ブランチを push できませんでした("; then
        fail "$n" "$WHY"
    elif [ "$(rgit rev-parse refs/heads/chore/ci-tool-version-update-node)" != "$PR_HEAD" ] || [ -f "$FAKE_DIR/edit-title-7" ]; then
        fail "$n" "古い headRefOid のまま、ブランチか PR を書き換えました"
    else
        pass "$n"
    fi
fi

if [ "$RAN" -eq 0 ]; then
    fail "場合の名前" "KP_TEST_CASE=${CASE} に当たる場合がありません"
fi
if [ "$FAILED" -ne 0 ]; then
    echo "::error::ci-tool-version-update.sh のテストが失敗しました。"
    exit 1
fi
echo "すべてのテストが通りました。"
