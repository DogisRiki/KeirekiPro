#!/bin/bash
# =====================================================================
# UserPromptExpansion(kiro-spec-design|kiro-spec-tasks|kiro-impl)
# / UserPromptSubmit hook: 未解決とレビュー未完了の提示
#
# cc-sddでは「次の段階のコマンドを人が打つこと」が前の段階の承認になる。
# その入力の時点で、未解決の指摘とレビュー未完了の段階を一覧で出し、
# 所有者の了承を得てから進めるようにする(止めはしない)。
#
# UserPromptExpansion は人が /コマンド を直接打った経路で発火する。
# UserPromptSubmit は自由文の入力に備えて同じ内容を出す(tasks段階の承認は
# 「はい」等の自由文で行われるため、コマンド名では拾えない)。
# 両イベントの標準出力は、Claudeが読める文脈として追加される。
#
# 出力は1万字までのため、件数と指摘IDの要約にとどめる。
# 判定は .claude/hooks/spec-review-scan.sh に集約している(Stopと共通)。
# =====================================================================
set -u

# 入力は読み捨てる(このフックは判定に使わない)
cat >/dev/null 2>&1

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
scan_lib="$project_dir/.claude/hooks/spec-review-scan.sh"
[ -f "$scan_lib" ] || exit 0
# shellcheck source=/dev/null
. "$scan_lib"

lines=""
while IFS='|' read -r feature stage blockers unresolved; do
    [ -z "$feature" ] && continue
    if [ -n "$blockers" ]; then
        lines="${lines}- ${feature} / ${stage}: レビュー未完了(${blockers})
"
    elif [ "${unresolved:-0}" -gt 0 ] 2>/dev/null; then
        ids=$(grep -oE '\b[RDT][0-9]+-[0-9]+-[0-9]+\b' \
            "$project_dir/.kiro/specs/$feature/reviews/${stage}-review.md" 2>/dev/null \
            | sort -u | tail -10 | tr '\n' ' ')
        lines="${lines}- ${feature} / ${stage}: 未解決 ${unresolved}件(${ids})
"
    fi
done <<EOF
$(spec_review_scan "$project_dir")
EOF

[ -z "$lines" ] && exit 0

cat <<MSG
[spec-review] 承認の前に確認が必要な段階があります。

${lines}
この段階の承認にあたる操作(次の段階のコマンド、または承認の返答)を進める前に、
上の一覧を所有者に提示し、了承を得てください。未解決があっても機械的には止めません。
記録は .kiro/specs/<feature>/reviews/ にあります。
MSG
exit 0
