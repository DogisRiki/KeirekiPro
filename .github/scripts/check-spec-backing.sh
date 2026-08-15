#!/usr/bin/env bash
# =====================================================================
# specの裏付けチェック(guardrails CI の size-check から実行)
#
# 200行超のPR(Lane A)が引用する spec の実在と中身を検証する。
# 判定: 次のすべてを満たせば exit 0(通過)。1つでも欠ければ exit 1(赤)
#   1. PR本文に「Spec: .kiro/specs/<feature>」がある(<feature> に使えるのは
#      英数字と - _ のみ。パス区切りや .. を含む指定は受け付けない)
#   2. spec ディレクトリに spec.json / requirements.md / design.md / tasks.md が
#      すべて存在し、空でない
#   3. 4ファイルにテンプレートのプレースホルダ({{...}})が残っていない
#      (テンプレートは {{DETAIL_ITEM_1}} のように数字を含む名前も使う)
#   4. spec.json で approvals.requirements / design / tasks の approved がすべて
#      true、かつ ready_for_implementation が true
#
# 限界(承知のうえでの設計):
#   4の承認フラグはAIの自己申告であり、人間が承認した証明にはならない(#177)。
#   このチェックが防ぐのは「存在しないspec・空のspec・書きかけのspec・未承認の
#   specを指して200行の上限を外す」という形の迂回である。
#
# 環境変数: PR_BODY(PR本文)
# テスト: .github/scripts/tests/test-check-spec-backing.sh
# 使い方: PR_BODY="..." check-spec-backing.sh
# =====================================================================
set -euo pipefail

PR_BODY="${PR_BODY:-}"

fail() {
    {
        echo "### :no_entry: specの裏付けが確認できません"
        echo ""
        echo '```'
        echo "$1"
        echo '```'
    } >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
    echo "::error::[specの裏付け] $1"
    exit 1
}

# jq は承認フラグの判定に必須。無い環境では判定できないため失敗させる(fail closed)。
# GitHub Actions の ubuntu ランナーには同梱されている
command -v jq >/dev/null || fail "jq が見つかりません。このチェックは jq を前提としています。"

spec_path=$(printf '%s' "$PR_BODY" | grep -oE 'Spec: *\.kiro/specs/[A-Za-z0-9_-]+' | head -1 | sed 's/Spec: *//' || true)
if [ -z "$spec_path" ]; then
    fail "PR本文に「Spec: .kiro/specs/<feature>」がありません。200行を超える変更は spec 駆動(Lane A)で行い、/kiro-spec-init で spec を作成して PR 本文に記載してください(<feature> に使えるのは英数字と - _ のみ)。"
fi

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
    and (.approvals.tasks.approved == true)
    and (.ready_for_implementation == true)' "$spec_path/spec.json" >/dev/null 2>&1; then
    fail "spec.json の3段階承認が完了していません(approvals.*.approved と ready_for_implementation がすべて true である必要があります)。承認は /kiro-spec-requirements → /kiro-spec-design → /kiro-spec-tasks の各段階で人間から得てください。"
fi

echo "spec(${spec_path})の裏付けを確認しました(必須ファイル・プレースホルダ・承認フラグ)。"
