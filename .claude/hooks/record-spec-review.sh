#!/bin/bash
# =====================================================================
# SubagentStop(spec-reviewer) / PostToolUse(SubagentHandback) hook:
# spec-review の実施証跡の記録
#
# レビュー役の最終報告にある構造化ブロックを読み、検証したうえで
# .claude/.state/spec-review/ に証跡を書く(Stop hookの検知材料)。
#
# 報告の届く経路は2つある。Claude Code v2.1.271 以降の auto mode では
# サブエージェントに SubagentHandback が付与され(tools/disallowedTools では
# 外せない)、報告は last_assistant_message ではなく
# PostToolUse(SubagentHandback) の tool_input.message に入る。
# 同じスクリプトを両方に登録し、どちらの経路でも拾う。
#
# 証跡にはreviewファイルのハッシュを含める。レビュー完了後に
# メインセッションがreviewファイルを書き換えた場合、Stop hookが検知する。
#
# 前提: Git for Windows(Git Bash同梱)。JSON解析は同梱perl(JSON::PP)を使用。
# 判定不能・不整合は証跡を書かずに終了する(fail-closed。Stop hookが止める)。
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
    ' -- "$@" 2>/dev/null
}

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 報告本文の取得(SubagentStop / PostToolUse の両方に対応)
report=$(extract last_assistant_message)
[ -z "$report" ] && report=$(extract tool_input message)
[ -z "$report" ] && exit 0

# 構造化ブロックの読み取り。値は1行1項目で、余分な空白を落とす
field() {
    printf '%s' "$report" | sed -n "s/^[[:space:]]*-[[:space:]]*$1:[[:space:]]*//p" | head -1 | tr -d '\r' | sed 's/[[:space:]]*$//'
}

feature=$(field FEATURE)
stage=$(field STAGE)
cycle=$(field CYCLE)
round=$(field ROUND)
review_file=$(field REVIEW_FILE)
status=$(field STATUS)

# 必須項目が欠けていれば証跡を書かない(スキル側がブロックのみの再起動を行う)
for v in "$feature" "$stage" "$cycle" "$round" "$review_file" "$status"; do
    [ -z "$v" ] && exit 0
done

# 値の検証。パスの細工(.. や絶対パス)と未知の段階を弾く
case "$stage" in
    requirements|design|tasks) ;;
    *) exit 0 ;;
esac
case "$status" in
    converged|unresolved) ;;
    *) exit 0 ;;
esac
printf '%s' "$feature" | grep -qE '^[A-Za-z0-9._-]+$' || exit 0
printf '%s' "$cycle" | grep -qE '^[0-9]+$' || exit 0
printf '%s' "$round" | grep -qE '^[0-9]+$' || exit 0

expected=".kiro/specs/${feature}/reviews/${stage}-review.md"
[ "$review_file" = "$expected" ] || exit 0

abs="$project_dir/$expected"
[ -f "$abs" ] || exit 0

# 完了の印の確認。reviewファイルの最終の非空行が「- 往復:」で始まること
marker=$(grep -v '^[[:space:]]*$' "$abs" | tail -1 | tr -d '\r')
printf '%s' "$marker" | grep -qE '^-[[:space:]]*往復:.*未解決:[[:space:]]*[0-9]+' || exit 0

# reviewファイルのハッシュ(完了後の書き換えの検知に使う)
if command -v sha256sum >/dev/null 2>&1; then
    hash=$(sha256sum "$abs" | awk '{print $1}')
else
    hash=$(cksum "$abs" | awk '{print $1"-"$2}')
fi

state_dir="$project_dir/.claude/.state/spec-review"
mkdir -p "$state_dir" 2>/dev/null || exit 0

{
    echo "recorded_at=$(date +%s)"
    echo "feature=$feature"
    echo "stage=$stage"
    echo "cycle=$cycle"
    echo "round=$round"
    echo "status=$status"
    echo "review_hash=$hash"
} > "$state_dir/${feature}__${stage}.evidence"

exit 0
