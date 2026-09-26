#!/bin/bash
# =====================================================================
# Stop hook: spec-review 未実施の停止ブロック
#
# generated が true で人の承認が無い段階について、レビューが完了しているかを
# 検査し、満たしていなければ停止をブロックする(exit 2)。
#
# 同じ入力に対して2回までブロックし、3回目は通す。回数は prompt_id ごとに
# .claude/.state/spec-review/ に保存する。prompt_id が変われば数え直すため、
# 初期化の処理は不要。Claude Code 自体は8回連続のブロックで上書きするため、
# 2回はその手前で収まる。
#
# 判定は .claude/hooks/spec-review-scan.sh に集約している(notifyと共通)。
# 前提: Git for Windows(Git Bash同梱)。JSON解析は同梱perl(JSON::PP)を使用。
# =====================================================================
set -u

payload=$(cat)

extract() {
    printf '%s' "$payload" | perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
        exit 0 unless ref $d;
        my $v = $d;
        for my $k (@ARGV) { $v = eval { $v->{$k} }; last unless defined $v; }
        if (defined $v && !ref $v) { print $v }
        elsif (defined $v && JSON::PP::is_bool($v)) { print $v ? "true" : "false" }
    ' -- "$@" 2>/dev/null
}

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
scan_lib="$project_dir/.claude/hooks/spec-review-scan.sh"
[ -f "$scan_lib" ] || exit 0
# shellcheck source=/dev/null
. "$scan_lib"

prompt_id=$(extract prompt_id)
[ -z "$prompt_id" ] && prompt_id=$(extract session_id)
[ -z "$prompt_id" ] && prompt_id="unknown"

state_dir="$project_dir/.claude/.state/spec-review"
counter="$state_dir/block-counter.txt"

# 停止をブロックすべき段階を集める
blocked=""
while IFS='|' read -r feature stage blockers _unresolved; do
    [ -z "$feature" ] && continue
    [ -z "$blockers" ] && continue
    blocked="${blocked}  - ${feature} の ${stage}: ${blockers}
"
done <<EOF
$(spec_review_scan "$project_dir")
EOF

if [ -z "$blocked" ]; then
    exit 0
fi

# 回数の判定。prompt_id が変わっていれば 0 から数える
count=0
if [ -f "$counter" ]; then
    saved_id=$(sed -n 's/^prompt_id=//p' "$counter" | head -1)
    saved_count=$(sed -n 's/^count=//p' "$counter" | head -1)
    if [ "$saved_id" = "$prompt_id" ] && printf '%s' "$saved_count" | grep -qE '^[0-9]+$'; then
        count="$saved_count"
    fi
fi

if [ "$count" -ge 2 ]; then
    # 2回止めても解消しない。これ以上は止めずに所有者の判断に委ねる
    exit 0
fi

mkdir -p "$state_dir" 2>/dev/null || exit 0
{
    echo "prompt_id=$prompt_id"
    echo "count=$((count + 1))"
} > "$counter"

cat >&2 <<MSG
spec のレビューが完了していない段階があります。

${blocked}
対応:
  - レビューが未実施なら /spec-review <feature名> <段階> を実行する
  - 本文を直した後なら、同じコマンドでレビューし直す
  - 3往復で収束せず未解決として残す場合は、その旨を記録に書いてから所有者に報告する

このブロックは同じ入力に対して2回までです(現在 $((count + 1)) 回目)。
MSG
exit 2
