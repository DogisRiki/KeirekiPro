#!/bin/bash
# =====================================================================
# agent-model.pl(補助役が実際に動いたモデルを会話の記録から読むスクリプト)のテスト
#
# 実行: bash .claude/scripts/spec-review/tests/test-agent-model.sh
# 場合を選んで流す: KP_TEST_CASE='t_transcript_fable_5_2 t_agent_id_found' bash .claude/scripts/spec-review/tests/test-agent-model.sh
#   KP_TEST_CASE に空白で区切って書いた関数の名前の場合だけを流す。知らない名前があれば何も流さずに失敗する
# 一時フォルダに偽の会話の記録と一時的な HOME を作り、スクリプトの出力の3行と終了コードを確かめる。
# 本物の会話の記録(~/.claude/projects)には触れない。
# 前提: bash と perl(JSON::PP)。ホストの Git Bash から流す。
# =====================================================================
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/agent-model.pl"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
WORK=$(cd "$TMP_ROOT" && pwd)

pass=0
fail=0

run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    if [ -n "${KP_TEST_CASE:-}" ]; then
        case " $KP_TEST_CASE " in *" $fn "*) ;; *) return 0 ;; esac
    fi
    rm -rf "$WORK/case"
    mkdir -p "$WORK/case"
    if out=$("$fn" 2>&1); then
        pass=$((pass + 1))
        printf 'ok: %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

# assistant の行を1行出す(モデルの ID を渡す)
assistant_line() { # <model>
    printf '{"type":"assistant","message":{"model":"%s","role":"assistant","content":[{"type":"text","text":"ok"}]}}\n' "$1"
}

user_line() {
    printf '{"type":"user","message":{"role":"user","content":"review"}}\n'
}

# スクリプトを流し、標準出力を $OUT、終了コードを $RC、標準エラーを $ERR に入れる
call() { # <引数>...
    OUT=$(perl "$SCRIPT" "$@" 2>"$WORK/case/stderr.txt")
    RC=$?
    ERR=$(cat "$WORK/case/stderr.txt")
}

# HOME と USERPROFILE を一時フォルダに向けてスクリプトを流す
call_home() { # <HOME> <USERPROFILE> <引数>...
    local home="$1" profile="$2"
    shift 2
    OUT=$(HOME="$home" USERPROFILE="$profile" perl "$SCRIPT" "$@" 2>"$WORK/case/stderr.txt")
    RC=$?
    ERR=$(cat "$WORK/case/stderr.txt")
}

expect() { # <model> <family> <name>
    local want
    want=$(printf 'model=%s\nfamily=%s\nname=%s' "$1" "$2" "$3")
    [ "$RC" -eq 0 ] || {
        echo "終了コードが0でない: $RC($ERR)"
        return 1
    }
    [ "$OUT" = "$want" ] || {
        printf '出力が違う\n--- 期待\n%s\n--- 実際\n%s\n' "$want" "$OUT"
        return 1
    }
}

expect_empty() {
    expect "" "" ""
}

expect_usage_error() {
    [ "$RC" -eq 2 ] || {
        echo "終了コードが2でない: $RC(出力: $OUT)"
        return 1
    }
    [ -n "$ERR" ] || {
        echo "標準エラーに理由が無い"
        return 1
    }
}

# 一時的な HOME の下に、補助役の会話の記録を置く
place_agent() { # <HOME> <project> <session> <agentId> <model>
    local d="$1/.claude/projects/$2/$3/subagents"
    mkdir -p "$d"
    {
        user_line
        assistant_line "$5"
    } >"$d/agent-$4.jsonl"
}

# --- --transcript で読む ------------------------------------------------

t_transcript_fable_5_2() {
    local f="$WORK/case/t.jsonl"
    {
        user_line
        assistant_line claude-fable-5-2
    } >"$f"
    call --transcript "$f"
    expect claude-fable-5-2 fable "Fable 5.2"
}

t_transcript_new_versions() {
    local f="$WORK/case/t.jsonl"
    assistant_line claude-opus-5-6 >"$f"
    call --transcript "$f"
    expect claude-opus-5-6 opus "Opus 5.6" || return 1
    assistant_line claude-fable-6 >"$f"
    call --transcript "$f"
    expect claude-fable-6 fable "Fable 6"
}

t_last_line_synthetic_uses_previous() {
    local f="$WORK/case/t.jsonl"
    {
        user_line
        assistant_line claude-opus-5-5
        user_line
        assistant_line claude-fable-5-2
        assistant_line '<synthetic>'
    } >"$f"
    call --transcript "$f"
    expect claude-fable-5-2 fable "Fable 5.2"
}

t_sonnet_family() {
    local f="$WORK/case/t.jsonl"
    assistant_line claude-sonnet-5-5 >"$f"
    call --transcript "$f"
    expect claude-sonnet-5-5 sonnet "Sonnet 5.5"
}

t_strips_date_and_bracket() {
    local f="$WORK/case/t.jsonl"
    assistant_line 'claude-opus-5-5-20261101[1m]' >"$f"
    call --transcript "$f"
    expect 'claude-opus-5-5-20261101[1m]' opus "Opus 5.5"
}

t_missing_file() {
    call --transcript "$WORK/case/none.jsonl"
    expect_empty
}

t_not_json() {
    local f="$WORK/case/t.jsonl"
    printf 'this is not json\n{"type":"assistant",\n' >"$f"
    call --transcript "$f"
    expect_empty
}

t_no_assistant_line() {
    local f="$WORK/case/t.jsonl"
    {
        user_line
        printf '{"type":"system","message":{"model":"claude-fable-5-2"}}\n'
    } >"$f"
    call --transcript "$f"
    expect_empty
}

# --- --agent-id で探す ------------------------------------------------

t_agent_id_found() {
    local home="$WORK/case/home"
    place_agent "$home" C--repo sess-1 a1b2c3 claude-fable-5-2
    call_home "$home" "$home" --agent-id a1b2c3
    expect claude-fable-5-2 fable "Fable 5.2"
}

t_agent_id_not_found() {
    local home="$WORK/case/home"
    place_agent "$home" C--repo sess-1 a1b2c3 claude-fable-5-2
    call_home "$home" "$home" --agent-id zzz999
    expect_empty
}

t_agent_id_two_found() {
    local home="$WORK/case/home"
    place_agent "$home" C--repo sess-1 a1b2c3 claude-fable-5-2
    place_agent "$home" C--other sess-2 a1b2c3 claude-opus-5-5
    call_home "$home" "$home" --agent-id a1b2c3
    expect_empty
}

# Git Bash の perl では、同じフォルダでも HOME(/c/...)と USERPROFILE(C:\...)の書き方が違う。
# 書き方をそろえずに比べると、同じ記録を2つ見つけて、読み取れなかったとみなす
t_agent_id_same_dir_two_forms() {
    local home="$WORK/case/home" win unix
    place_agent "$home" C--repo sess-1 a1b2c3 claude-opus-5-5
    if win=$(cd "$home" && pwd -W 2>/dev/null); then
        # C:/x/y を /c/x/y と C:\x\y の2つの書き方にする
        unix=$(printf '%s' "$win" | sed -E 's#^([A-Za-z]):#/\L\1#')
        win=${win//\//\\}
    else
        unix="$home"
        win="$home/"
    fi
    call_home "$unix" "$win" --agent-id a1b2c3
    expect claude-opus-5-5 opus "Opus 5.5"
}

t_usage_errors() {
    call
    expect_usage_error || {
        echo "(引数なし)"
        return 1
    }
    call --unknown x
    expect_usage_error || {
        echo "(知らない引数)"
        return 1
    }
    # --agent-id を渡す場合は、HOME と USERPROFILE を一時フォルダに向け、本物の会話の記録を探さない
    local home="$WORK/case/home"
    place_agent "$home" C--repo sess-1 x claude-fable-5-2
    call_home "$home" "$home" --agent-id
    expect_usage_error || {
        echo "(--agent-id の値が無い)"
        return 1
    }
    call_home "$home" "$home" --agent-id '../etc/x'
    expect_usage_error || {
        echo "(agentId の形が違う)"
        return 1
    }
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

echo "--- --transcript で読む"
run_test "Fable 5.2 の記録から model と family と name を出す(要件4.1、5.1)" t_transcript_fable_5_2
run_test "まだ無い版の Opus 5.6 と Fable 6 を出す(要件1.3、5.2)" t_transcript_new_versions
run_test "最後の行が <synthetic> ならその前の行のモデルを出す(要件4.3)" t_last_line_synthetic_uses_previous
run_test "Sonnet の記録から family=sonnet を出す(要件5.3)" t_sonnet_family
run_test "末尾の日付と [1m] を外して系統と名前を作る" t_strips_date_and_bracket
run_test "記録が無ければ3行とも空で0で終わる(要件4.4)" t_missing_file
run_test "JSON でなければ3行とも空で0で終わる(要件4.4)" t_not_json
run_test "assistant の行が無ければ3行とも空で0で終わる(要件4.4)" t_no_assistant_line

echo "--- --agent-id で探す"
run_test "一時的な HOME の下の記録を見つけて読む" t_agent_id_found
run_test "見つからなければ3行とも空で0で終わる" t_agent_id_not_found
run_test "2つ見つかれば3行とも空で0で終わる" t_agent_id_two_found
run_test "HOME と USERPROFILE が書き方の違う同じフォルダなら1つに数える" t_agent_id_same_dir_two_forms
run_test "引数の誤りと agentId の形の誤りは終了コード2" t_usage_errors

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
