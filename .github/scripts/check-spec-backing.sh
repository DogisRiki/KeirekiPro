#!/usr/bin/env bash
# =====================================================================
# specの裏付けか所有者の承認のチェック(guardrails CI の size-check から実行)
#
# 200行超のPRを、次のどちらかで通す。
#   A. PR本文に Spec の行がある PR(Lane A): 引用する spec の実在と中身を検証する
#   B. PR本文に Spec の行が無い PR(spec 無しの PR): 所有者がその PR の最新の
#      コミットを承認していれば通す(#975)。200行を超えることと spec が要ることは
#      別の話で、spec の要否は着手のときに /start が決める。spec の要らない変更を
#      上限のためだけに spec にしたり、無理に分けたりしないため、所有者が差分を
#      見て通す道を設ける
#
# A の判定: 次のすべてを満たせば exit 0(通過)。1つでも欠ければ exit 1(赤)
#   1. PR本文に「Spec: .kiro/specs/<feature>」がある(<feature> に使えるのは
#      英数字と - _ のみ。パス区切りや .. を含む指定は受け付けない)
#   2. spec ディレクトリに spec.json / requirements.md / design.md / tasks.md が
#      すべて存在し、空でない
#   3. 4ファイルにテンプレートのプレースホルダ({{...}})が残っていない
#      (テンプレートは {{DETAIL_ITEM_1}} のように数字を含む名前も使う)
#   4. spec.json で approvals.requirements / design / tasks の approved がすべて true
# A では所有者の承認で通さない。Spec の行を書いた PR は spec を確かめる。
# 誤った Spec の行を、承認で見逃さないためである
#
# B の判定: OWNER_APPROVED が true なら exit 0、それ以外は exit 1(赤)
#   OWNER_APPROVED は、ワークフローが escape-hatch と同じ手順で求める。
#   所有者の PR のレビューのうち、PR の最新のコミット(head)に付いたものの、
#   最後の状態が APPROVED のときに true になる。承認のあとにコミットを足すと
#   head が変わるので、承認は無効になる
#
# 限界(承知のうえでの設計):
#   4の承認フラグはAIの自己申告であり、人間が承認した証明にはならない(#177)。
#   このチェックが防ぐのは「存在しないspec・空のspec・書きかけのspec・未承認の
#   specを指して200行の上限を外す」という形の迂回である。
#
# 環境変数: PR_BODY(PR本文)、OWNER_APPROVED(所有者の承認。true か false)
# テスト: .github/scripts/tests/test-check-spec-backing.sh
# 使い方: PR_BODY="..." OWNER_APPROVED=false check-spec-backing.sh
# =====================================================================
set -euo pipefail

PR_BODY="${PR_BODY:-}"
OWNER_APPROVED="${OWNER_APPROVED:-false}"

fail() {
    {
        echo "### :no_entry: specの裏付けか所有者の承認が確認できません"
        echo ""
        echo '```'
        echo "$1"
        echo '```'
    } >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
    echo "::error::[specの裏付けか所有者の承認] $1"
    exit 1
}

spec_path=$(printf '%s' "$PR_BODY" | grep -oE 'Spec: *\.kiro/specs/[A-Za-z0-9_-]+' | head -1 | sed 's/Spec: *//' || true)
if [ -z "$spec_path" ]; then
    # Spec の行が無い PR(spec 無しの PR)は、所有者の承認だけで判定する
    if [ "$OWNER_APPROVED" = "true" ]; then
        echo "PR本文に Spec の行が無いため、所有者の承認を確かめました。所有者がこの PR の最新のコミットを承認しているので通します。"
        exit 0
    fi
    fail "200行を超える spec の無い PR は、所有者がこの PR の最新のコミットを承認するまで通りません。所有者が PR を承認すると、この検査がもう一度動いて通ります。承認のあとにコミットを足したときは、承認し直す必要があります。spec で進めた PR なら、PR本文に「Spec: .kiro/specs/<feature>」を書いてください(<feature> に使えるのは英数字と - _ のみ)。"
fi

# jq は承認フラグの判定に必須。無い環境では判定できないため失敗させる(fail closed)。
# GitHub Actions の ubuntu ランナーには同梱されている
command -v jq >/dev/null || fail "jq が見つかりません。このチェックは jq を前提としています。"

if [ ! -d "$spec_path" ]; then
    fail "spec ディレクトリ ${spec_path} が存在しません。"
fi

missing=""
for f in spec.json requirements.md design.md tasks.md; do
    if [ ! -f "$spec_path/$f" ] || [ ! -s "$spec_path/$f" ]; then
        missing+="${spec_path}/${f}"$'\n'
    fi
done
if [ -n "$missing" ]; then
    fail "spec に必要なファイルが存在しないか空です:
$missing"
fi

# grep は -q 無しで全入力を読む
placeholders=$(grep -nE '\{\{[A-Z0-9_]+\}\}' \
    "$spec_path/spec.json" "$spec_path/requirements.md" \
    "$spec_path/design.md" "$spec_path/tasks.md" || true)
if [ -n "$placeholders" ]; then
    fail "spec にテンプレートのプレースホルダが残っています。生成が完了していません:
$placeholders"
fi

if ! jq -e '(.approvals.requirements.approved == true)
    and (.approvals.design.approved == true)
    and (.approvals.tasks.approved == true)' "$spec_path/spec.json" >/dev/null 2>&1; then
    fail "spec.json の3段階承認が完了していません(approvals.*.approved がすべて true である必要があります)。承認は /kiro-spec-requirements → /kiro-spec-design → /kiro-spec-tasks の各段階で人間から得てください。"
fi

echo "spec(${spec_path})の裏付けを確認しました(必須ファイル・プレースホルダ・承認フラグ)。"
