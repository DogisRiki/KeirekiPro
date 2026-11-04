#!/usr/bin/env bash
# =====================================================================
# check-ci-tool-release-age.sh の自動テスト(guardrails CI の escape-hatch から実行)
#
# 一時のフォルダに、分かれ目のコミットと head のブランチを持つリモートを作り、
# head のブランチを履歴の深さ1で取った写しの中で検査を流す。PATH の先頭に偽の gh と
# curl を置き、比較の API の応答と PR の本文と配布元の応答を場合ごとに返す。
# 偽の gh と curl は、呼ばれた取り先を記録する。記録で、配布元に問い合わせたかを確かめる。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-ci-tool-release-age.sh"
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

mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = api ] || { echo "偽の gh: 知らない呼び方です: $*" >&2; exit 9; }
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
export FAKE_MAP FAKE_LOG
# git の設定は、この PC の設定を読まず、コミットの名前とメールを環境変数で渡す
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test

D1="sha256:c86ecead9e55a5210ac1727de38a4ca840bf03dcaf34dc9749addbf383b1920c"
D2="sha256:a5d5a5a892c98f60fcbfa81eac2a40fc19e7b3fa7719bccae10ff6111d22524a"
# 2026-11-04T00:00:00Z
NOW=1793750400
# 2026-11-06T01:00:00Z。2026-11-03T00:00:00Z に公開した版が通る日時のあと
LATER=1793926800
YOUNG=2026-11-03T00:00:00Z
OLD=2026-10-01T00:00:00Z

# 使い方: fx <gh|curl> <取り先> <HTTP の状態> <応答の本文>
fx() {
    local f
    f="$WORK/fx$N-$(wc -l <"$FAKE_MAP" | tr -d ' ').json"
    printf '%s\n' "$4" >"$f"
    printf '%s %s\t%s\t%s\n' "$1" "$2" "$3" "$f" >>"$FAKE_MAP"
}

# 使い方: node_rel <版> <公開日時> / trivy_rel <版> <公開日時>。GitHub の Release の応答を足す
node_rel() {
    fx gh "repos/nodejs/node/releases/tags/v$1" 200 "{\"tag_name\":\"v$1\",\"published_at\":\"$2\"}"
}
trivy_rel() {
    fx gh "repos/aquasecurity/trivy/releases/tags/v$1" 200 "{\"tag_name\":\"v$1\",\"published_at\":\"$2\"}"
}

# 使い方: node_tag <版> <digest> <tag_last_pushed>。Docker Hub の node のタグの応答を足す
node_tag() {
    fx curl "https://hub.test/v2/namespaces/library/repositories/node/tags/$1-bookworm-slim" 200 \
        "{\"name\":\"$1-bookworm-slim\",\"digest\":\"$2\",\"tag_last_pushed\":\"$3\"}"
}

# 使い方: pr_body <本文>。PR #7 の本文の応答を足す
pr_body() {
    fx gh "repos/o/r/pulls/7" 200 "$(jq -n --arg b "$1" '{number: 7, body: $b}')"
}

# 使い方: drop_pr。PR #7 の本文の応答を消す
drop_pr() {
    awk -F '\t' -v k="gh repos/o/r/pulls/7" '$1 != k' "$FAKE_MAP" >"$FAKE_MAP.new"
    mv "$FAKE_MAP.new" "$FAKE_MAP"
}

# 使い方: mark <記録の JSON>。記録の目印の行を出す
mark() {
    printf '<!-- ci-tool-cooldown-exception data=%s -->' "$(printf '%s' "$1" | base64 | tr -d '\n')"
}

# 使い方: entry <道具> <版> <署名の結果>。記録の entries の要素を出す
entry() {
    printf '{"tool":"%s","version":"%s","signature":{"result":"%s","method":"x"}}' "$1" "$2" "$3"
}

# --- リモートの作り方 -------------------------------------------------------
# 作業のリポジトリ $G/work の main に分かれ目のコミットを作り、head のブランチで
# PR の変更をコミットする。両方を $G/remote.git に push し、head のブランチを
# 履歴の深さ1で $G/head に取る。検査は $G/head の中で流す。

# 使い方: new_repo [nodata]。分かれ目のコミットの並びのファイルを $G/work に置く。
# nodata を渡すと、データのファイルを置かない。
# a.yaml の版の行は、Trivy が 0.60.0、Terraform が 1.17.0、Node.js が 24.1.0。
# 開発環境は、Node.js が 24.1.0 で digest は D1、Terraform が 1.17.0。
new_repo() {
    N=$((N + 1))
    G="$WORK/g$N"
    FAKE_MAP="$WORK/map$N.tsv"
    FAKE_LOG="$WORK/log$N.txt"
    : >"$FAKE_MAP"
    : >"$FAKE_LOG"
    mkdir -p "$G/work/.github/workflows" "$G/work/docker/frontend" "$G/work/docker/terraform"
    git init -q -b main "$G/work"
    cat >"$G/work/.github/workflows/a.yaml" <<'YAML'
name: a
env:
  TRIVY_VERSION: 0.60.0
  TF_VERSION: 1.17.0
jobs:
  a:
    steps:
      - uses: actions/setup-node@0123456789abcdef0123456789abcdef01234567 # v4.0.0
        with:
          node-version: '24.1.0'
YAML
    printf 'FROM node:24.1.0-bookworm-slim@%s\n' "$D1" >"$G/work/docker/frontend/Dockerfile"
    printf 'FROM hashicorp/terraform:1.17.0\n' >"$G/work/docker/terraform/Dockerfile"
    echo "readme" >"$G/work/README.md"
    [ "${1:-}" = nodata ] || write_data
}

write_data() {
    cat >"$G/work/.github/ci-tool-versions.json" <<'JSON'
{
  "schema": 1,
  "tools": {
    "node": {
      "name": "Node.js", "inventory_name": "Node.js", "keys": ["node-version"],
      "ci": [{ "file": ".github/workflows/a.yaml", "key": "node-version" }],
      "dev": { "file": "docker/frontend/Dockerfile", "image": "node", "hub_repository": "library/node", "tag_suffix": "-bookworm-slim" }
    },
    "trivy": {
      "name": "Trivy", "inventory_name": "Trivy", "keys": ["TRIVY_VERSION"],
      "ci": [{ "file": ".github/workflows/a.yaml", "key": "TRIVY_VERSION" }]
    },
    "terraform": {
      "name": "Terraform", "inventory_name": "Terraform", "keys": ["TF_VERSION"],
      "ci": [{ "file": ".github/workflows/a.yaml", "key": "TF_VERSION" }],
      "dev": { "file": "docker/terraform/Dockerfile", "image": "hashicorp/terraform", "hub_repository": "hashicorp/terraform", "tag_suffix": "" }
    }
  },
  "excluded": []
}
JSON
}

# 使い方: commit_as <変数の名前>。作業のリポジトリの変更をコミットし、SHA を変数に入れる
commit_as() {
    git -C "$G/work" add -A
    git -C "$G/work" commit -q -m "$1"
    printf -v "$1" '%s' "$(git -C "$G/work" rev-parse HEAD)"
}

# 使い方: base_commit。分かれ目のコミットを作り、MB と MAIN_SHA に入れる
base_commit() {
    commit_as MB
    MAIN_SHA="$MB"
}

# 使い方: branch_head。分かれ目のコミットから head のブランチを作る
branch_head() {
    git -C "$G/work" checkout -q -b head "$MB"
}

# 使い方: finish。head のコミットを作り、リモートに push して、head を履歴の深さ1で取る。
# 比較の API の応答に、分かれ目のコミットを返す。
finish() {
    commit_as HEAD_SHA
    git init -q --bare "$G/remote.git"
    git -C "$G/remote.git" config uploadpack.allowAnySHA1InWant true
    git -C "$G/work" push -q "file://$G/remote.git" main head 2>/dev/null
    git clone -q --depth 1 --branch head "file://$G/remote.git" "$G/head" 2>/dev/null
    fx gh "repos/o/r/compare/${MAIN_SHA}...${HEAD_SHA}" 200 \
        "{\"status\":\"ahead\",\"merge_base_commit\":{\"sha\":\"${MB}\"}}"
}

# 使い方: edit <根からのパス> <前の文字> <後の文字>。作業のリポジトリのファイルの中の
# 最初の <前の文字> を <後の文字> に替える。そのままの文字で比べる。無ければ失敗にする
edit() {
    local c
    c=$(cat "$G/work/$1")
    if [[ "$c" != *"$2"* ]]; then
        fail "テストの準備" "$1 に「$2」がありません"
        return 1
    fi
    printf '%s\n' "${c/"$2"/"$3"}" >"$G/work/$1"
}

# 使い方: run [<今の時刻>]。head の写しの中で検査を流す。呼ばれた取り先の記録を空にしてから流す。
# 標準出力を $WORK/out.txt に、終了コードを $RC に入れる
run() {
    : >"$FAKE_LOG"
    : >"$WORK/summary.md"
    rm -f "$WORK/changed.tsv"
    (cd "$G/head" && GITHUB_REPOSITORY=o/r PR_NUMBER=7 CI_TOOL_CHANGED_FILE="$WORK/changed.tsv" \
        GITHUB_STEP_SUMMARY="$WORK/summary.md" NOW_EPOCH="${1:-$NOW}" \
        bash "$SCRIPT" "$MAIN_SHA" "$HEAD_SHA") >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
}

# 使い方: expect <説明> <終了コード> [<確かめ> <値>]...
# 確かめは次のどれか。値はそのままの文字で比べる。
#   out / summary / changed / log: そのファイルに、値と同じ行がある
#   no-out / no-summary / no-log: そのファイルに、値を含む行が無い
#   lines-changed / lines-log: そのファイルの行の数が値と同じ
expect() {
    local name="$1" rc="$2" kind f
    shift 2
    if [ "$RC" -ne "$rc" ]; then
        fail "$name" "終了コードが ${RC}(期待は ${rc})。出力: $(head -c 800 "$WORK/out.txt") / 標準エラー: $(head -c 300 "$WORK/err.txt")"
        return
    fi
    while [ "$#" -ge 2 ]; do
        kind="$1"
        case "${kind#*-}" in
        out) f="$WORK/out.txt" ;;
        summary) f="$WORK/summary.md" ;;
        changed) f="$WORK/changed.tsv" ;;
        log) f="$FAKE_LOG" ;;
        esac
        case "$kind" in
        no-*)
            if grep -qF -- "$2" "$f"; then
                fail "$name" "${kind#no-} に「$2」を含む行があります: $(grep -F -- "$2" "$f" | head -n 1)"
                return
            fi
            ;;
        lines-*)
            if [ "$(grep -c '' "$f" 2>/dev/null)" != "$2" ]; then
                fail "$name" "${kind#lines-} の行の数が $(grep -c '' "$f" 2>/dev/null)(期待は $2)。中身: $(tr '\n' '|' <"$f" 2>/dev/null)"
                return
            fi
            ;;
        *)
            if ! grep -qxF -- "$2" "$f" 2>/dev/null; then
                fail "$name" "${kind} に「$2」の行がありません。中身: $(head -c 800 "$f" 2>/dev/null)"
                return
            fi
            ;;
        esac
        shift 2
    done
    pass "$name"
}

NOCHANGE="CI の道具の公開からの時間の検査: 4つの道具の版の変更はありません。"
HEADER="| 道具 | 場所 | 版 | 公開日時 | 通る日時 | 結果 |"

# --- 版を変えない PR ---------------------------------------------------------

if want no_change; then
    new_repo
    base_commit
    branch_head
    edit README.md readme "readme の変更"
    finish
    run
    expect "4つの道具の版を変えない PR が配布元に問い合わせずに通る" 0 \
        out "$NOCHANGE" summary "4つの道具の版の変更はありません。" \
        log "gh repos/o/r/compare/${MAIN_SHA}...${HEAD_SHA}" lines-log 1 lines-changed 0
fi

if want old_main; then
    new_repo
    base_commit
    # 分かれ目のあと、main だけで Trivy と開発環境の Node.js の版を上げる
    edit .github/workflows/a.yaml "TRIVY_VERSION: 0.60.0" "TRIVY_VERSION: 0.62.0"
    edit docker/frontend/Dockerfile "node:24.1.0" "node:24.3.0"
    commit_as MAIN_SHA
    branch_head
    edit README.md readme "readme の変更"
    finish
    run
    expect "古い main から分けたブランチの PR で、main だけで変わった版を変更としない" 0 \
        out "$NOCHANGE" lines-log 1 lines-changed 0
fi

if want no_data_at_base; then
    new_repo nodata
    base_commit
    branch_head
    write_data
    finish
    run
    expect "分かれ目にデータのファイルが無く、版を変えない PR が通る" 0 \
        out "$NOCHANGE" lines-log 1 lines-changed 0
fi

if want digest_only; then
    new_repo
    base_commit
    branch_head
    edit docker/frontend/Dockerfile "$D1" "$D2"
    finish
    run
    expect "digest だけの変更で通る" 0 out "$NOCHANGE" lines-log 1
fi

if want line_shift; then
    new_repo
    base_commit
    branch_head
    edit .github/workflows/a.yaml "env:" "on: push
permissions: {}
env:
  LOG_LEVEL: info"
    finish
    run
    expect "版の行より上に行を足しただけの PR で、版の変更としない" 0 out "$NOCHANGE" lines-log 1
fi

# --- 72時間経っていない版 ------------------------------------------------------

if want ci_young; then
    new_repo
    base_commit
    branch_head
    edit .github/workflows/a.yaml "TRIVY_VERSION: 0.60.0" "TRIVY_VERSION: 0.61.0"
    finish
    trivy_rel 0.61.0 "$YOUNG"
    pr_body "版を上げます"
    run
    expect "72時間経っていない CI の版で失敗する" 1
    expect "止めた変更の道具と版と公開日時と通る日時を GITHUB_STEP_SUMMARY と ::error:: に出す" 1 \
        summary "$HEADER" \
        summary "| Trivy | CI | 0.61.0 | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 止めました(公開から72時間経っていません) |" \
        out "::error::CI の Trivy の版 0.61.0 を止めました: 公開から72時間経っていません。公開日時は 2026-11-03T00:00:00Z、検査が通るようになる日時は 2026-11-06T00:00:00Z です。その日時を過ぎてから、ジョブを Re-run してください"
    run "$LATER"
    expect "今の時刻を通る日時のあとにすると、同じ版で通る" 0 \
        summary "| Trivy | CI | 0.61.0 | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 通しました |" \
        no-out "::error::"
fi

if want dev_young; then
    new_repo
    base_commit
    branch_head
    edit docker/frontend/Dockerfile "node:24.1.0" "node:24.2.0"
    finish
    # 版の公開は古く、イメージのタグの公開が新しい
    node_rel 24.2.0 "$OLD"
    node_tag 24.2.0 "$D1" "2026-11-03T00:00:00.123456Z"
    run
    expect "開発環境のタグが72時間経っていないと失敗する" 1 \
        summary "| Node.js | 開発環境 | 24.2.0 | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 止めました(公開から72時間経っていません) |" \
        out "::error::開発環境の Node.js の版 24.2.0 を止めました: 公開から72時間経っていません。公開日時は 2026-11-03T00:00:00Z、検査が通るようになる日時は 2026-11-06T00:00:00Z です。その日時を過ぎてから、ジョブを Re-run してください" \
        no-log "gh repos/o/r/pulls/7" lines-changed 0
    run "$LATER"
    expect "開発環境のタグが72時間経っていれば通る" 0 \
        summary "| Node.js | 開発環境 | 24.2.0 | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 通しました |"
fi

if want dev_digest; then
    new_repo
    base_commit
    branch_head
    edit docker/frontend/Dockerfile "node:24.1.0-bookworm-slim@$D1" "node:24.2.0-bookworm-slim@$D2"
    finish
    node_rel 24.2.0 "$OLD"
    node_tag 24.2.0 "$D1" "$OLD"
    run
    expect "開発環境の digest がタグの今の digest と違うと失敗する" 1 \
        summary "| Node.js | 開発環境 | 24.2.0 | 2026-10-01T00:00:00Z | 2026-10-04T00:00:00Z | 止めました(digest が配布元のイメージのタグ library/node:24.2.0-bookworm-slim の今の digest ${D1} と違います) |"
fi

if want query_fail; then
    new_repo
    base_commit
    branch_head
    edit .github/workflows/a.yaml "TRIVY_VERSION: 0.60.0" "TRIVY_VERSION: 0.61.0"
    finish
    fx gh "repos/aquasecurity/trivy/releases/tags/v0.61.0" 502 '{"message":"Bad Gateway"}'
    pr_body ""
    run
    expect "公開日時の問い合わせが失敗すると、取れなかった理由を出して失敗する" 1 \
        summary "| Trivy | CI | 0.61.0 | 取れなかった | 取れなかった | 止めました(trivy 0.61.0: GitHub の repos/aquasecurity/trivy/releases/tags/v0.61.0 から published_at を取れませんでした(HTTP 502)) |" \
        out "::error::CI の Trivy の版 0.61.0 を止めました: 公開日時か digest を取れませんでした(trivy 0.61.0: GitHub の repos/aquasecurity/trivy/releases/tags/v0.61.0 から published_at を取れませんでした(HTTP 502))。ジョブを Re-run してください"
fi

# --- 記録の例外 ---------------------------------------------------------------

if want exception_ci; then
    new_repo
    base_commit
    branch_head
    edit .github/workflows/a.yaml "node-version: '24.1.0'" "node-version: '24.2.0'"
    edit .github/workflows/a.yaml "TRIVY_VERSION: 0.60.0" "TRIVY_VERSION: 0.61.0"
    finish
    trivy_rel 0.61.0 "$YOUNG"
    pr_body "Node.js を急いで上げます
$(mark "{\"schema\":1,\"entries\":[$(entry node v24.2.0 verified)]}")"
    run
    expect "記録の道具の CI の版だけを通し、同じ PR のほかの道具の変更を通さない" 1 \
        summary "| Node.js | CI | 24.2.0 | - | - | 記録の例外で通しました |" \
        summary "| Trivy | CI | 0.61.0 | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 止めました(公開から72時間経っていません) |" \
        no-out "::error::CI の Node.js" no-log "gh repos/nodejs/node"
    expect "例外で通した版も含めて、変わった CI の版を CI_TOOL_CHANGED_FILE に書く" 1 \
        changed "$(printf 'node\t24.2.0')" changed "$(printf 'trivy\t0.61.0')" lines-changed 2
fi

if want exception_dev; then
    new_repo
    base_commit
    branch_head
    edit .github/workflows/a.yaml "node-version: '24.1.0'" "node-version: '24.2.0'"
    edit docker/frontend/Dockerfile "node:24.1.0" "node:24.2.0"
    finish
    node_rel 24.2.0 "$OLD"
    node_tag 24.2.0 "$D1" "$YOUNG"
    pr_body "$(mark "{\"schema\":1,\"entries\":[$(entry node 24.2.0 verified)]}")"
    run
    expect "同じ PR の開発環境の版の変更を通さない" 1 \
        summary "| Node.js | CI | 24.2.0 | - | - | 記録の例外で通しました |" \
        summary "| Node.js | 開発環境 | 24.2.0 | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 止めました(公開から72時間経っていません) |" \
        changed "$(printf 'node\t24.2.0')" lines-changed 1
fi

if want exception_unverified; then
    new_repo
    base_commit
    branch_head
    edit .github/workflows/a.yaml "TRIVY_VERSION: 0.60.0" "TRIVY_VERSION: 0.61.0"
    finish
    trivy_rel 0.61.0 "$YOUNG"
    pr_body "$(mark "{\"schema\":1,\"entries\":[$(entry trivy 0.61.0 failed)]}")"
    run
    expect "署名の結果が verified でない記録では通さない" 1 \
        summary "| Trivy | CI | 0.61.0 | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 止めました(公開から72時間経っていません) |" \
        no-summary "記録の例外で通しました"
fi

if want exception_malformed; then
    new_repo
    base_commit
    branch_head
    edit .github/workflows/a.yaml "TRIVY_VERSION: 0.60.0" "TRIVY_VERSION: 0.61.0"
    finish
    trivy_rel 0.61.0 "$YOUNG"
    STOP="| Trivy | CI | 0.61.0 | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 止めました(公開から72時間経っていません) |"
    WARN="::warning::PR #7 の本文の記録の目印の行の形が違うため、記録の例外を1つも当てずに調べます"
    GOOD=$(mark "{\"schema\":1,\"entries\":[$(entry trivy 0.61.0 verified)]}")
    # 正しい記録に、JSON として読めない記録が並ぶ
    pr_body "$GOOD
$(mark "not json")"
    run
    expect "形の違う記録の目印の行では例外を当てない(JSON として読めない記録が並ぶ)" 1 \
        summary "$STOP" out "$WARN" no-summary "記録の例外で通しました"
    # 正しい記録に、signature の無い記録が並ぶ
    drop_pr
    pr_body "$GOOD
$(mark '{"schema":1,"entries":[{"tool":"node","version":"24.2.0"}]}')"
    run
    expect "形の違う記録の目印の行では例外を当てない(signature の無い記録が並ぶ)" 1 \
        summary "$STOP" out "$WARN" no-summary "記録の例外で通しました"
    # 正しい記録に、data の後ろが壊れた目印の行が並ぶ
    drop_pr
    pr_body "$GOOD
<!-- ci-tool-cooldown-exception data=eyJ9 x -->"
    run
    expect "形の違う記録の目印の行では例外を当てない(目印の行の形が違う)" 1 \
        summary "$STOP" out "$WARN" no-summary "記録の例外で通しました"
    # 正しい記録だけなら通す
    drop_pr
    pr_body "$GOOD"
    run
    expect "形の正しい記録の目印の行だけなら例外を当てる" 0 \
        summary "| Trivy | CI | 0.61.0 | - | - | 記録の例外で通しました |" no-log "gh repos/aquasecurity"
fi

# --- 読まないもの -------------------------------------------------------------

if want no_author; then
    # 更新の PR と手で書き換えた PR を同じく調べるため、作者とブランチの名前を読まない
    if [ ! -f "$SCRIPT" ] || grep -nE 'user\.login|"user"|head\.ref|head_ref|HEAD_REF|GITHUB_ACTOR|github\.actor|\.author' "$SCRIPT" | grep -v '^[0-9]*: *#'; then
        fail "PR の作者とブランチの名前を読まない" "検査のスクリプトが作者かブランチの名前を読んでいます"
    else
        pass "PR の作者とブランチの名前を読まない"
    fi
fi

# --- 調べられないとき -----------------------------------------------------------

if want bad_args; then
    new_repo
    base_commit
    branch_head
    edit README.md readme "readme の変更"
    finish
    (cd "$G/head" && GITHUB_REPOSITORY=o/r PR_NUMBER=7 CI_TOOL_CHANGED_FILE="$WORK/changed.tsv" \
        bash "$SCRIPT") >"$WORK/out.txt" 2>&1
    RC=$?
    expect "引数か環境変数の形が違うと終了コード 2 になる(引数が無い)" 2 lines-log 0
    (cd "$G/head" && GITHUB_REPOSITORY=o/r PR_NUMBER=x CI_TOOL_CHANGED_FILE="$WORK/changed.tsv" \
        bash "$SCRIPT" "$MAIN_SHA" "$HEAD_SHA") >"$WORK/out.txt" 2>&1
    RC=$?
    expect "引数か環境変数の形が違うと終了コード 2 になる(PR_NUMBER の形が違う)" 2 lines-log 0
    (cd "$G/head" && GITHUB_REPOSITORY=o/r PR_NUMBER=7 CI_TOOL_CHANGED_FILE="" \
        bash "$SCRIPT" "$MAIN_SHA" "$HEAD_SHA") >"$WORK/out.txt" 2>&1
    RC=$?
    expect "引数か環境変数の形が違うと終了コード 2 になる(CI_TOOL_CHANGED_FILE が無い)" 2 lines-log 0
    rm -f "$G/head/.github/ci-tool-versions.json"
    run
    expect "データのファイルを読めないと終了コード 2 になる" 2 \
        out "::error::データのファイル .github/ci-tool-versions.json を読めませんでした"
fi

if want judge_no_rows; then
    new_repo
    base_commit
    branch_head
    edit .github/workflows/a.yaml "TRIVY_VERSION: 0.60.0" "TRIVY_VERSION: 0.61.0"
    finish
    trivy_rel 0.61.0 "$OLD"
    pr_body "版を上げます"
    # 偽の mktemp は、検査の一時のフォルダを作る1回目だけ本物を呼び、2回目からは失敗する。
    # 判定の関数は、一時のフォルダを作れないと、結果の行を出さずに失敗を返す
    mkdir -p "$WORK/mkt"
    cat >"$WORK/mkt/mktemp" <<SH
#!/usr/bin/env bash
n=\$(cat "$WORK/mkt/count" 2>/dev/null || echo 0)
echo \$((n + 1)) >"$WORK/mkt/count"
[ "\$n" -eq 0 ] && exec "$(command -v mktemp)" "\$@"
echo "偽の mktemp: 作れません" >&2
exit 1
SH
    chmod +x "$WORK/mkt/mktemp"
    rm -f "$WORK/mkt/count"
    PATH="$WORK/mkt:$PATH" run
    expect "判定の関数が結果の行を出さずに失敗すると、その変更を止める" 1 \
        summary "| Trivy | CI | 0.61.0 | 取れなかった | 取れなかった | 止めました(判定の結果を読めませんでした) |" \
        out "::error::CI の Trivy の版 0.61.0 を止めました: 判定の結果を読めませんでした(偽の mktemp: 作れません)。ジョブを Re-run してください" \
        no-summary "通しました"
fi

if want compare_fail; then
    new_repo
    base_commit
    branch_head
    edit README.md readme "readme の変更"
    finish
    : >"$FAKE_MAP"
    run
    expect "分かれ目のコミットを取れないと失敗する" 1 \
        out "::error::分かれ目のコミットを取れませんでした(比較の API が失敗しました: gh: Not Found (HTTP 404))。ジョブを Re-run してください"
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: 場合「${CASE}」はありません"
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "失敗したテストがあります。"
    exit 1
fi
echo "すべてのテストが通りました。"
