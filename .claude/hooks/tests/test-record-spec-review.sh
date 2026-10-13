#!/bin/bash
# =====================================================================
# record-spec-review.sh のテスト(レビュー役のモデルによる証跡の記録の判定)
#
# 実行: bash .claude/hooks/tests/test-record-spec-review.sh
# 一時的なプロジェクトのディレクトリを場合ごとに作り、CLAUDE_PROJECT_DIR をそこに向けて
# フックに模擬の入力(JSON)を渡し、証跡が書かれたかどうかを確かめる。
# 審査の記録(完了の印のある review ファイル)と報告の構造化ブロックは、
# 証跡が書かれる状態にそろえ、レビュー役の記録のモデル名と入力の経路だけを場合ごとに変える。
# 受け入れるモデルは Fable 5.1 と Opus 5.5 で、それ以外のモデルの記録があれば証跡を書かない。
# 記録の無い経路(PostToolUse の SubagentHandback)では、モデルを確かめずに証跡を書く。
# 前提: bash・perl(JSON::PP)。
# =====================================================================
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/record-spec-review.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FEATURE="f"
STAGE="requirements"
REVIEW_REL=".kiro/specs/$FEATURE/reviews/${STAGE}-review.md"

# レビュー役の最終報告(構造化ブロック)。JSON の文字列に入れるため改行は \n で書く
REPORT="## 報告\n\n- FEATURE: $FEATURE\n- STAGE: $STAGE\n- CYCLE: 1\n- ROUND: 1\n- REVIEW_FILE: $REVIEW_REL\n- STATUS: converged\n"

pass=0
fail=0

# make_project <プロジェクト>: 完了の印のある review ファイルを作る
make_project() {
    mkdir -p "$1/.kiro/specs/$FEATURE/reviews"
    printf '# 審査\n\n## サイクル1 往復1\n\n指摘なし。\n\n- 往復: 1回で収束 / 未解決: 0件\n' > "$1/$REVIEW_REL"
}

# make_transcript <ファイル> <モデル名>: 模擬のサブエージェントの記録を作る(モデル名が空ならモデルの欄を書かない)
make_transcript() {
    if [ -n "$2" ]; then
        printf '{"type":"assistant","message":{"model":"%s","role":"assistant","content":[{"type":"text","text":"審査した"}]}}\n' "$2" > "$1"
    else
        printf '{"type":"user","message":{"role":"user","content":"審査して"}}\n' > "$1"
    fi
}

# subagent_stop_input <記録のファイル>: SubagentStop の入力
subagent_stop_input() {
    printf '{"hook_event_name":"SubagentStop","agent_type":"spec-reviewer","agent_transcript_path":"%s","last_assistant_message":"%s"}' "$1" "$REPORT"
}

# handback_input: PostToolUse(SubagentHandback)の入力。agent_transcript_path は無い
handback_input() {
    printf '{"hook_event_name":"PostToolUse","tool_name":"SubagentHandback","tool_input":{"message":"%s"}}' "$REPORT"
}

# run_hook <プロジェクト> <入力>
run_hook() {
    printf '%s' "$2" | CLAUDE_PROJECT_DIR="$1" bash "$SCRIPT" >/dev/null 2>&1
}

evidence_of() {
    printf '%s' "$1/.claude/.state/spec-review/${FEATURE}__${STAGE}.evidence"
}

ok() { pass=$((pass + 1)); printf 'ok:   %s\n' "$1"; }
ng() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; }

# expect_written <名前> <プロジェクト>: 証跡が書かれ、中身が報告と合うことを確かめる
expect_written() {
    local name="$1" ev
    ev=$(evidence_of "$2")
    if [ ! -f "$ev" ]; then
        ng "$name (証跡が書かれていない)"
        return
    fi
    if grep -qx "feature=$FEATURE" "$ev" && grep -qx "stage=$STAGE" "$ev" &&
        grep -qx 'status=converged' "$ev" && grep -qE '^review_hash=.+' "$ev"; then
        ok "$name"
    else
        ng "$name (証跡の中身が違う: $(tr '\n' ' ' < "$ev"))"
    fi
}

# expect_not_written <名前> <プロジェクト>
expect_not_written() {
    if [ -f "$(evidence_of "$2")" ]; then
        ng "$1 (証跡が書かれた)"
    else
        ok "$1"
    fi
}

echo "--- 1. 記録のモデルが Fable 5.1 なら証跡を書く"
P="$WORK/case1"
make_project "$P"
make_transcript "$WORK/case1.jsonl" claude-fable-5-1
run_hook "$P" "$(subagent_stop_input "$WORK/case1.jsonl")"
expect_written "Fable 5.1" "$P"

echo "--- 2. 記録のモデルが Opus 5.5 なら証跡を書く"
P="$WORK/case2"
make_project "$P"
make_transcript "$WORK/case2.jsonl" claude-opus-5-5
run_hook "$P" "$(subagent_stop_input "$WORK/case2.jsonl")"
expect_written "Opus 5.5" "$P"

echo "--- 3. 記録のモデルがそれ以外(Sonnet 5.5)なら証跡を書かない"
P="$WORK/case3"
make_project "$P"
make_transcript "$WORK/case3.jsonl" claude-sonnet-5-5
run_hook "$P" "$(subagent_stop_input "$WORK/case3.jsonl")"
expect_not_written "Sonnet 5.5" "$P"

echo "--- 4. 記録の無い経路(PostToolUse の SubagentHandback)では証跡を書く"
P="$WORK/case4"
make_project "$P"
run_hook "$P" "$(handback_input)"
expect_written "SubagentHandback の経路" "$P"

echo "--- 5. 記録にモデル名が無ければ、今までどおり証跡を書く"
P="$WORK/case5"
make_project "$P"
make_transcript "$WORK/case5.jsonl" ""
run_hook "$P" "$(subagent_stop_input "$WORK/case5.jsonl")"
expect_written "記録にモデル名なし" "$P"

echo
printf '結果: 成功 %d / 失敗 %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
