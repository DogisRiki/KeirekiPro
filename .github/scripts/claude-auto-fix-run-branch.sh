#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix の run-branch ジョブで、対象ごとの実行を起動する専用のブランチを、main の最新のコミットに
# 合わせるスクリプト(design.md の claude-auto-fix-run-branch.sh の節)
#
# 専用のブランチの名前は、lib-claude-auto-fix.sh の CAF_RUN_BRANCH から読む。
# 1. gh api repos/<owner>/<repo>/git/ref/heads/main で、main の最新のコミットの SHA を読む
# 2. PATCH repos/<owner>/<repo>/git/refs/heads/<専用のブランチ> に、その SHA と force=true を渡して合わせる
# 3. ブランチが無い(GitHub が 404 か 422 を返した)ときは、POST repos/<owner>/<repo>/git/refs に
#    ref=refs/heads/<専用のブランチ> とその SHA を渡して作る
# 4. 合わせた SHA を GITHUB_STEP_SUMMARY に書く
#
# force=true を渡すのは、2つの実行が同時に動くと、あとに合わせた実行が、専用のブランチを少し古い main の
# コミットに戻すことがあるためである。戻した先も main のコミットなので、対象ごとの実行が動かすのは、
# main にあるワークフローとスクリプトである。
# このスクリプトは、main と、専用のブランチのほかのブランチを変えない。
# 同じ状態で何度呼んでも、ブランチは main の最新のコミットを指す。
#
# 環境変数:
#   GITHUB_REPOSITORY    owner/name
#   GH_TOKEN             bot の PAT(run-branch ジョブが secrets.BOT_GITHUB_TOKEN を渡す)
#   GITHUB_STEP_SUMMARY  合わせた SHA を書くファイル(無ければ書かない)
#
# 終わり方: 0 合わせたか作った / 1 main を読めないか、ブランチを合わせられないか作れない / 2 呼び方が違う
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/lib-claude-auto-fix.sh
. "$HERE/lib-claude-auto-fix.sh" || exit 2

fail() {
    echo "::error::claude-auto-fix-run-branch: $1" >&2
    exit 1
}
if [ "$#" -ne 0 ]; then
    echo "::error::claude-auto-fix-run-branch: 引数は要りません" >&2
    echo "使い方: claude-auto-fix-run-branch.sh(引数なし)" >&2
    exit 2
fi
REPO=$(_caf_repo) || exit 2

# 1. main の最新のコミットの SHA
main_ref=$(gh api "repos/${REPO}/git/ref/heads/main" </dev/null) || fail "main の最新のコミットを読めません"
sha=$(jq -r '.object.sha? // empty' <<<"$main_ref" 2>/dev/null) || sha=""
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || fail "main の参照の応答に、コミットの SHA がありません"

# 2. 専用のブランチを合わせる。gh は失敗したとき「gh: Not Found (HTTP 404)」の形の行を標準エラーに出す
done_what=""
if patch_err=$(gh api -X PATCH "repos/${REPO}/git/refs/heads/${CAF_RUN_BRANCH}" -f sha="$sha" -F force=true \
    </dev/null 2>&1 >/dev/null); then
    done_what="合わせました"
else
    status=$(printf '%s' "$patch_err" | grep -oE 'HTTP [0-9]{3}' | tail -1 | cut -d' ' -f2 || true)
    case "$status" in
    404 | 422)
        # 3. ブランチが無いので作る
        gh api -X POST "repos/${REPO}/git/refs" -f ref="refs/heads/${CAF_RUN_BRANCH}" -f sha="$sha" \
            </dev/null >/dev/null || fail "専用のブランチ ${CAF_RUN_BRANCH} を作れません"
        done_what="作りました"
        ;;
    *)
        fail "専用のブランチ ${CAF_RUN_BRANCH} を main のコミットに合わせられません(HTTP ${status:-不明})"
        ;;
    esac
fi

# 4. 合わせた SHA を書く
echo "claude-auto-fix-run-branch: 専用のブランチ ${CAF_RUN_BRANCH} を main のコミット ${sha} で${done_what}"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf "専用のブランチ \`%s\` を、main の最新のコミット \`%s\` で%s。\n" "$CAF_RUN_BRANCH" "$sha" "$done_what" \
        >>"$GITHUB_STEP_SUMMARY" || fail "GITHUB_STEP_SUMMARY に書けません"
fi
exit 0
