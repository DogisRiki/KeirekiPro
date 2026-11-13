#!/bin/bash
# =====================================================================
# record-spec-review.sh のテスト(レビュー役のモデルによる証跡の記録の判定)
#
# 実行: bash .claude/hooks/tests/test-record-spec-review.sh
# 場合を選んで流す: KP_TEST_CASE='t_fable_5_1_writes t_handback_writes' bash .claude/hooks/tests/test-record-spec-review.sh
#   KP_TEST_CASE に空白で区切って書いた関数の名前の場合だけを流す。知らない名前があれば何も流さずに失敗する
# 一時的なプロジェクトのディレクトリを場合ごとに作り、CLAUDE_PROJECT_DIR をそこに向けて
# フックに模擬の入力(JSON)を渡し、証跡が書かれたかどうかを確かめる。
# 審査の記録(完了の印のある review ファイル)と報告の構造化ブロックは、
# 証跡が書かれる状態にそろえ、レビュー役の記録のモデル名と入力の経路だけを場合ごとに変える。
# フックは agent-model.pl で記録の最後のモデルの系統を読み、Fable と Opus の系統なら版によらず証跡を書き、
# それ以外の系統(Sonnet、Haiku)なら証跡を書かない。
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

# expect_written <プロジェクト>: 証跡が書かれ、中身が報告と合うことを確かめる
expect_written() {
    local ev
    ev=$(evidence_of "$1")
    if [ ! -f "$ev" ]; then
        echo "証跡が書かれていない"
        return 1
    fi
    if grep -qx "feature=$FEATURE" "$ev" && grep -qx "stage=$STAGE" "$ev" &&
        grep -qx 'status=converged' "$ev" && grep -qE '^review_hash=.+' "$ev"; then
        return 0
    fi
    echo "証跡の中身が違う: $(tr '\n' ' ' < "$ev")"
    return 1
}

# expect_not_written <プロジェクト>
expect_not_written() {
    if [ -f "$(evidence_of "$1")" ]; then
        echo "証跡が書かれた"
        return 1
    fi
}

run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    if [ -n "${KP_TEST_CASE:-}" ]; then
        case " $KP_TEST_CASE " in *" $fn "*) ;; *) return 0 ;; esac
    fi
    rm -rf "$WORK/case"
    mkdir -p "$WORK/case"
    if out=$("$fn" 2>&1); then
        pass=$((pass + 1))
        printf 'ok:   %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

# --- 場合 ------------------------------------------------------------

t_fable_5_1_writes() {
    local p="$WORK/case/p"
    make_project "$p"
    make_transcript "$WORK/case/t.jsonl" claude-fable-5-1
    run_hook "$p" "$(subagent_stop_input "$WORK/case/t.jsonl")"
    expect_written "$p"
}

t_opus_5_5_writes() {
    local p="$WORK/case/p"
    make_project "$p"
    make_transcript "$WORK/case/t.jsonl" claude-opus-5-5
    run_hook "$p" "$(subagent_stop_input "$WORK/case/t.jsonl")"
    expect_written "$p"
}

t_sonnet_5_5_not_written() {
    local p="$WORK/case/p"
    make_project "$p"
    make_transcript "$WORK/case/t.jsonl" claude-sonnet-5-5
    run_hook "$p" "$(subagent_stop_input "$WORK/case/t.jsonl")"
    expect_not_written "$p"
}

t_handback_writes() {
    local p="$WORK/case/p"
    make_project "$p"
    run_hook "$p" "$(handback_input)"
    expect_written "$p"
}

t_no_model_writes() {
    local p="$WORK/case/p"
    make_project "$p"
    make_transcript "$WORK/case/t.jsonl" ""
    run_hook "$p" "$(subagent_stop_input "$WORK/case/t.jsonl")"
    expect_written "$p"
}

# 1つのモデルの記録で証跡が書かれることを確かめる
written_for_model() { # <モデル>
    local p="$WORK/case/p"
    make_project "$p"
    make_transcript "$WORK/case/t.jsonl" "$1"
    run_hook "$p" "$(subagent_stop_input "$WORK/case/t.jsonl")"
    expect_written "$p"
}

t_fable_5_2_writes() {
    written_for_model claude-fable-5-2
}

t_opus_5_6_writes() {
    written_for_model claude-opus-5-6
}

t_fable_6_writes() {
    written_for_model claude-fable-6
}

t_haiku_5_5_not_written() {
    local p="$WORK/case/p"
    make_project "$p"
    make_transcript "$WORK/case/t.jsonl" claude-haiku-5-5
    run_hook "$p" "$(subagent_stop_input "$WORK/case/t.jsonl")"
    expect_not_written "$p"
}

# 記録の最後の assistant の行が Sonnet なら、前の行が Fable でも証跡を書かない
t_last_sonnet_after_fable_not_written() {
    local p="$WORK/case/p" f="$WORK/case/t.jsonl" m
    make_project "$p"
    : >"$f"
    for m in claude-fable-5-1 claude-sonnet-5-5; do
        printf '{"type":"assistant","message":{"model":"%s","role":"assistant","content":[{"type":"text","text":"審査した"}]}}\n' "$m" >>"$f"
    done
    run_hook "$p" "$(subagent_stop_input "$f")"
    expect_not_written "$p"
}

# フックを agent-model.pl の無い一時フォルダに写して流すと、スクリプトが0でない終了コードで終わるので、
# モデルの記録がある入力で証跡を書かない
t_agent_model_missing_not_written() {
    local p="$WORK/case/p" lone="$WORK/case/lone"
    mkdir -p "$lone/.claude/hooks"
    cp "$SCRIPT" "$lone/.claude/hooks/record-spec-review.sh"
    make_project "$p"
    make_transcript "$WORK/case/t.jsonl" claude-fable-5-1
    printf '%s' "$(subagent_stop_input "$WORK/case/t.jsonl")" |
        CLAUDE_PROJECT_DIR="$p" bash "$lone/.claude/hooks/record-spec-review.sh" >/dev/null 2>&1
    expect_not_written "$p"
}

# ---------------------------------------------------------------------

# 知らない名前を選んだら、何も流さずに失敗する
for want in ${KP_TEST_CASE:-}; do
    case "$want" in
        t_*) declare -F "$want" >/dev/null && continue ;;
    esac
    echo "どの場合にも合わない名前: $want" >&2
    exit 2
done

run_test "1. 記録のモデルが Fable 5.1 なら証跡を書く" t_fable_5_1_writes
run_test "2. 記録のモデルが Opus 5.5 なら証跡を書く" t_opus_5_5_writes
run_test "3. 記録のモデルがそれ以外(Sonnet 5.5)なら証跡を書かない" t_sonnet_5_5_not_written
run_test "4. 記録の無い経路(PostToolUse の SubagentHandback)では証跡を書く" t_handback_writes
run_test "5. 記録にモデル名が無ければ、今までどおり証跡を書く" t_no_model_writes
run_test "6. 記録のモデルが Fable 5.2 なら証跡を書く(要件5.1)" t_fable_5_2_writes
run_test "7. 記録のモデルがまだ無い版の Opus 5.6 なら証跡を書く(要件5.2)" t_opus_5_6_writes
run_test "8. 記録のモデルがまだ無い版の Fable 6 なら証跡を書く(要件5.2)" t_fable_6_writes
run_test "9. 記録のモデルが Haiku 5.5 なら証跡を書かない(要件5.3)" t_haiku_5_5_not_written
run_test "10. 最後の assistant の行が Sonnet なら、前の行が Fable でも証跡を書かない(要件5.3)" t_last_sonnet_after_fable_not_written
run_test "11. agent-model.pl が無く0でない終了コードで終わったら、証跡を書かない" t_agent_model_missing_not_written

echo
printf '結果: 成功 %d / 失敗 %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
