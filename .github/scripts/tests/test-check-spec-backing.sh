#!/usr/bin/env bash
# =====================================================================
# check-spec-backing.sh の自動テスト(guardrails CI から実行)
#
# 一時ディレクトリに spec のフィクスチャを作り、終了コードを検証する。
#   0 = 緑(specの裏付けあり) / 1 = 赤(裏付けなし)
# 併せて、Summaryへ出す報告の内容も検証する。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-spec-backing.sh"
# 一時領域の確保に失敗したまま進むと rm -rf が意図しない絶対パスを対象にするため、
# ディレクトリが実在することを確認してから trap を設定する
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

SPEC_DIR=".kiro/specs/demo-feature"

# 使い方: write_spec_json <req承認> <design承認> <tasks承認> <ready>
write_spec_json() {
    cat >"$SPEC_DIR/spec.json" <<EOF
{
  "feature_name": "demo-feature",
  "language": "ja",
  "phase": "tasks-generated",
  "approvals": {
    "requirements": { "generated": true, "approved": $1, "approved_by": "DogisRiki", "approved_at": "2026-08-15T00:00:00Z" },
    "design": { "generated": true, "approved": $2, "approved_by": "DogisRiki", "approved_at": "2026-08-15T00:00:00Z" },
    "tasks": { "generated": true, "approved": $3, "approved_by": "DogisRiki", "approved_at": "2026-08-15T00:00:00Z" }
  },
  "ready_for_implementation": $4
}
EOF
}

seed() {
    rm -rf "$WORK/repo"
    mkdir -p "$WORK/repo/$SPEC_DIR"
    # traversal ケース(.kiro/specs/x/../demo-feature)が実在のspecへ解決される状況を
    # 作っておく。パスの制限が緩むと解決されて通ってしまうことを検出するため
    mkdir -p "$WORK/repo/.kiro/specs/x"
    cd "$WORK/repo" || exit 1
    write_spec_json true true true true
    printf '# Requirements Document\n\n## Requirements\n\n本文。\n' >"$SPEC_DIR/requirements.md"
    printf '# Design Document\n\n## Overview\n\n本文。\n' >"$SPEC_DIR/design.md"
    printf '# Implementation Plan\n\n- [ ] 1. タスク\n' >"$SPEC_DIR/tasks.md"
}

BODY_OK="変更概要。

Spec: $SPEC_DIR
Refs: #999"
BODY_NONE="変更概要。

Refs: #999"
BODY_MISSING="Spec: .kiro/specs/other-feature"
# パス区切りや .. を含む指定は受け付けない(実在のspecへ解決されるとしても弾く)
BODY_TRAVERSAL="Spec: .kiro/specs/x/../demo-feature"

# 失敗させるケースが本物のジョブSummaryへ追記されないよう、
# 検査対象のSummaryは捨てる(内容の検証は check_summary が行う)
# 使い方: check <期待exit> <説明> <PR本文> <変更を加える関数>
check() {
    local want="$1" name="$2" body="$3" mutate="$4" got
    seed
    "$mutate"
    GITHUB_STEP_SUMMARY=/dev/null PR_BODY="$body" bash "$SCRIPT" >/dev/null 2>&1
    got=$?
    if [ "$got" = "$want" ]; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s (期待 exit=%s / 実際 exit=%s)\n' "$name" "$want" "$got"
        FAILED=1
    fi
}

# 使い方: check_summary <期待する文字列> <説明> <PR本文> <変更を加える関数>
check_summary() {
    local want="$1" name="$2" body="$3" mutate="$4" summary
    seed
    "$mutate"
    summary="$WORK/summary.md"
    : >"$summary"
    GITHUB_STEP_SUMMARY="$summary" PR_BODY="$body" bash "$SCRIPT" >/dev/null 2>&1
    if grep -q "$want" "$summary"; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s (Summaryに "%s" が無い)\n' "$name" "$want"
        FAILED=1
    fi
}

m_valid() { :; }
m_rm_design() { rm "$SPEC_DIR/design.md"; }
# ディレクトリは -s で真になるため、-f と併せて判定しないとすり抜ける
m_dir_design() { rm "$SPEC_DIR/design.md"; mkdir "$SPEC_DIR/design.md"; }
m_empty_req() { : >"$SPEC_DIR/requirements.md"; }
m_placeholder_tasks() { printf -- '- [ ] 2. {{TASK_DESCRIPTION}}\n' >>"$SPEC_DIR/tasks.md"; }
# テンプレートが実際に使う数字入りの名前(tasks.md の {{DETAIL_ITEM_1}} など)
m_placeholder_digit() { printf -- '  - {{DETAIL_ITEM_1}}\n' >>"$SPEC_DIR/tasks.md"; }
m_placeholder_json() { sed -i 's/"demo-feature"/"{{FEATURE_NAME}}"/' "$SPEC_DIR/spec.json"; }
m_tasks_unapproved() { write_spec_json true true false true; }
m_design_unapproved() { write_spec_json true false true true; }
m_not_ready() { write_spec_json true true true false; }
m_broken_json() { echo '{ broken' >"$SPEC_DIR/spec.json"; }
m_no_approvals_key() { echo '{ "ready_for_implementation": true }' >"$SPEC_DIR/spec.json"; }

check 0 "承認済みspecの裏付けあり" "$BODY_OK" m_valid
check 1 "PR本文にSpec行が無い" "$BODY_NONE" m_valid
check 1 "Spec行のディレクトリが存在しない" "$BODY_MISSING" m_valid
check 1 "パス区切りや .. を含むSpec指定" "$BODY_TRAVERSAL" m_valid
check 1 "design.md が無い" "$BODY_OK" m_rm_design
check 1 "requirements.md が空" "$BODY_OK" m_empty_req
check 1 "tasks.md にプレースホルダが残っている" "$BODY_OK" m_placeholder_tasks
check 1 "spec.json にプレースホルダが残っている" "$BODY_OK" m_placeholder_json
check 1 "数字を含むプレースホルダが残っている" "$BODY_OK" m_placeholder_digit
check 1 "design.md がディレクトリ" "$BODY_OK" m_dir_design
check 1 "tasks が未承認" "$BODY_OK" m_tasks_unapproved
check 1 "design が未承認" "$BODY_OK" m_design_unapproved
check 1 "ready_for_implementation が false" "$BODY_OK" m_not_ready
check 1 "spec.json が壊れたJSON" "$BODY_OK" m_broken_json
check 1 "spec.json に approvals が無い" "$BODY_OK" m_no_approvals_key

check_summary "プレースホルダ" "プレースホルダ残存がSummaryに出る" "$BODY_OK" m_placeholder_tasks
check_summary "3段階承認" "未承認がSummaryに出る" "$BODY_OK" m_tasks_unapproved

if [ "$FAILED" -ne 0 ]; then
    echo "::error::check-spec-backing.sh のテストが失敗しました。"
    exit 1
fi
echo "全ケース成功。"
