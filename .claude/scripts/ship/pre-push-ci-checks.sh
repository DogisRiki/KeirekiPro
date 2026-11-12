#!/usr/bin/env bash
# =====================================================================
# push の前に、CI で push のあとに初めて赤になっていた検査を手元で流す(/ship の手順1が呼ぶ)
#
# 使い方: bash .claude/scripts/ship/pre-push-ci-checks.sh [--base <コミット>]
#   作業フォルダの中で動かす。対象は、基準のコミットから HEAD までのコミットと、まだ commit していない変更
#   (git add -A で入る変更。.gitignore で除いたファイルは入らない)である。
#   --base  基準のコミット。既定は git merge-base origin/main HEAD(PR の比べる先に当たる)
#
# 流す検査(CI の名前と、手元でのやり方):
#   gitleaks  CI(guardrails.yaml の gitleaks)の gitleaks-action v3.0.0 が入れる版と同じ 8.24.3 の公式のイメージで、
#             CI と同じ git log の範囲の読み方(--no-merges --first-parent)と、同じ設定のファイル
#             (対象のコミットの .gitleaksignore と .gitleaks.toml)で調べる。
#             CI の gitleaks-action は PR の最初の30のコミットしか読まない(PR のコミットの一覧を1ページだけ読む)が、
#             ここでは基準から HEAD までのすべてを読む
#
# 終了コード: 0 = すべて通った / 1 = 止まった検査がある / 2 = 調べられなかった検査がある(止まった検査は無い)
#             3 = 使い方の誤りか、調べる準備ができなかった
# 前提: bash・git・perl(JSON::PP)・docker。jq には依存しない。
# 使う外部の道具: ghcr.io/gitleaks/gitleaks(版とダイジェストで固定する)。gitleaks はコンテナの中で動き、
#   リポジトリの中身を外へ送らない(コンテナはネットワークにつながない)。
# =====================================================================
set -uo pipefail

# Windows の Git Bash が docker と git に渡す引数のパスを書き換えないようにする
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

GITLEAKS_IMAGE='ghcr.io/gitleaks/gitleaks:v8.24.3@sha256:e1b35e12a8c6fa8901f060459cfb6b2fc4c484d3afbe3b029733a3bbfab07055'

BASE_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
    --base) BASE_ARG="${2:-}"; shift 2 ;;
    *) echo "使い方: bash .claude/scripts/ship/pre-push-ci-checks.sh [--base <コミット>]" >&2; exit 3 ;;
    esac
done

# Windows では、docker と git(Windows のプログラム)に C:/ の形のパスを渡す
host_path() { (cd "$1" && { pwd -W 2>/dev/null || pwd; }); }

fail_setup() { echo "準備ができませんでした: $*" >&2; exit 3; }

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || fail_setup "git の作業フォルダの中で動かしてください"
TOP=$(host_path "$TOP")

if [ -n "$BASE_ARG" ]; then
    BASE=$(git -C "$TOP" rev-parse --verify --quiet "${BASE_ARG}^{commit}") || fail_setup "基準のコミット $BASE_ARG が無い"
else
    BASE=$(git -C "$TOP" merge-base origin/main HEAD) || fail_setup "origin/main との分かれ目を求められない"
fi
HEAD_SHA=$(git -C "$TOP" rev-parse HEAD) || fail_setup "HEAD を読めない"

TMP_RAW=$(mktemp -d) || fail_setup "一時のフォルダを作れない"
TMP=$(host_path "$TMP_RAW")
trap 'rm -rf "$TMP_RAW"' EXIT
mkdir -p "$TMP/out"

# --- 調べる履歴を一時のフォルダに用意する -------------------------------------------
# worktree の .git は Windows のパスを指すので、コンテナの中の git から読めない。
# HEAD までの履歴を一時のリポジトリに取り出し、まだ commit していない変更は、その一時のリポジトリの中に
# 仮のコミットとして作る(作業フォルダのリポジトリの ref と index は変えない)。
REPO="$TMP/repo"
git init -q "$REPO" || fail_setup "一時のリポジトリを作れない"
git -C "$REPO" fetch -q --no-tags "$TOP" HEAD || fail_setup "HEAD までの履歴を取り出せない"
git -C "$REPO" cat-file -e "${BASE}^{commit}" 2>/dev/null ||
    fail_setup "基準のコミット $BASE が HEAD の履歴に無い(--base で HEAD の祖先を渡す)"

TARGET="$HEAD_SHA"
idx="$TMP/index"
if GIT_INDEX_FILE="$idx" git --git-dir="$REPO/.git" --work-tree="$TOP" read-tree "$HEAD_SHA" &&
    GIT_INDEX_FILE="$idx" git --git-dir="$REPO/.git" --work-tree="$TOP" add -A &&
    tree=$(GIT_INDEX_FILE="$idx" git --git-dir="$REPO/.git" write-tree); then
    if [ "$tree" != "$(git -C "$REPO" rev-parse "${HEAD_SHA}^{tree}")" ]; then
        TARGET=$(GIT_AUTHOR_NAME=pre-push-ci-checks GIT_AUTHOR_EMAIL=pre-push@localhost \
            GIT_COMMITTER_NAME=pre-push-ci-checks GIT_COMMITTER_EMAIL=pre-push@localhost \
            git -C "$REPO" commit-tree "$tree" -p "$HEAD_SHA" -m "まだ commit していない変更") ||
            fail_setup "まだ commit していない変更を仮のコミットにできない"
    fi
else
    fail_setup "まだ commit していない変更を読めない"
fi

echo "基準: ${BASE}"
echo "対象: ${HEAD_SHA}$([ "$TARGET" != "$HEAD_SHA" ] && echo "(と、まだ commit していない変更 = 仮のコミット ${TARGET})")"
echo ""

declare -A RESULT
declare -A DETAIL

# --- gitleaks ---------------------------------------------------------------------
# 設定のファイルは、CI と同じく対象のコミットのものを使う(CI は PR の head を checkout して読む)
for f in .gitleaksignore .gitleaks.toml; do
    git -C "$REPO" show "${TARGET}:${f}" >"$REPO/$f" 2>/dev/null || rm -f "$REPO/$f"
done
git -C "$REPO" update-ref refs/heads/target "$TARGET"
docker run --rm --network none -v "$REPO:/repo:ro" -v "$TMP/out:/out" "$GITLEAKS_IMAGE" \
    detect --source /repo --no-banner --redact -v --exit-code=2 \
    --report-format=json --report-path=/out/gitleaks.json \
    --log-opts="--no-merges --first-parent ${BASE}..${TARGET}" >"$TMP/gitleaks.log" 2>&1
rc=$?
case "$rc" in
0) RESULT[gitleaks]=通った ;;
2)
    RESULT[gitleaks]=止まった
    DETAIL[gitleaks]=$(perl -MJSON::PP -e '
        local $/; my $j = decode_json(<STDIN>);
        for my $f (@$j) {
            printf "  - %s:%s 規則 %s(%s)\n    指紋: %s\n", $f->{File}, $f->{StartLine}, $f->{RuleID},
                $f->{Description} // "", $f->{Fingerprint};
        }' <"$TMP/out/gitleaks.json")
    ;;
*)
    RESULT[gitleaks]=調べられなかった
    DETAIL[gitleaks]=$(tail -n 5 "$TMP/gitleaks.log" | sed 's/^/  /')
    ;;
esac

# --- 報告 -------------------------------------------------------------------------
declare -A LABEL=([gitleaks]="gitleaks(秘密の値)")
CHECKS=(gitleaks)
status=0
for key in "${CHECKS[@]}"; do
    echo "${LABEL[$key]}: ${RESULT[$key]}"
    [ -z "${DETAIL[$key]:-}" ] || echo "${DETAIL[$key]}"
    case "${RESULT[$key]}" in
    止まった) status=1 ;;
    調べられなかった) [ "$status" -eq 1 ] || status=2 ;;
    esac
done
exit "$status"
