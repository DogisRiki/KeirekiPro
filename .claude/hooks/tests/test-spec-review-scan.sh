#!/bin/bash
# =====================================================================
# spec-review-scan.sh のテスト(書き方の点検の記録の判定)
#
# 実行: bash .claude/hooks/tests/test-spec-review-scan.sh
# 一時的なプロジェクトのディレクトリを場合ごとに作り、check-spec-review-before-stop.sh と
# 同じく scan を source して spec_review_scan を呼び、出力の理由の欄を確かめる。
# 審査の記録・対応の記録・証跡は、審査についての理由が出ない状態にそろえ、
# 点検の記録と本文の変更日時だけを場合ごとに変える。
# 前提: bash・perl(JSON::PP)。
# =====================================================================
set -u

SCAN="$(cd "$(dirname "$0")/.." && pwd)/spec-review-scan.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

NO_RECORD="書き方の点検の記録がない"
BODY_NEWER="本文が書き方の点検より新しい"

T_BODY="2026-01-01 00:00:00"
T_REVIEW="2026-01-02 00:00:00"

pass=0
fail=0

# make_spec <プロジェクト> <feature> <spec.json の中身>
make_spec() {
    mkdir -p "$1/.kiro/specs/$2/reviews"
    printf '%s\n' "$3" > "$1/.kiro/specs/$2/spec.json"
}

# make_stage <プロジェクト> <feature> <段階>
# 本文・審査の記録・対応の記録・証跡を、審査についての理由が出ない状態で作る
make_stage() {
    local proj="$1" feature="$2" stage="$3"
    local dir="$proj/.kiro/specs/$feature"
    local review="$dir/reviews/${stage}-review.md"
    local state="$proj/.claude/.state/spec-review"
    local hash
    printf '# %s\n\n本文。\n' "$stage" > "$dir/${stage}.md"
    printf '# 審査\n\n## サイクル1 往復1\n\n指摘なし。\n\n- 往復: 1 未解決: 0\n' > "$review"
    printf '# 対応\n\n| ID | 処置 | 内容 |\n|---|---|---|\n' > "$dir/reviews/${stage}-response.md"
    mkdir -p "$state"
    if command -v sha256sum >/dev/null 2>&1; then
        hash=$(sha256sum "$review" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        hash=$(shasum -a 256 "$review" | awk '{print $1}')
    else
        hash=$(cksum "$review" | awk '{print $1"-"$2}')
    fi
    printf 'review_hash=%s\n' "$hash" > "$state/${feature}__${stage}.evidence"
    touch -d "$T_BODY" "$dir/${stage}.md"
    touch -d "$T_REVIEW" "$review"
}

# make_style <プロジェクト> <feature> <段階> <変更日時>
make_style() {
    local f="$1/.kiro/specs/$2/reviews/${3}-style.md"
    printf '# 点検\n\n## 点検 2026-01-01T00:00:00Z\n' > "$f"
    touch -d "$4" "$f"
}

# scan_line <プロジェクト> <feature> <段階>: 該当する行を出す(無ければ空)
scan_line() {
    (
        # shellcheck source=/dev/null
        . "$SCAN"
        spec_review_scan "$1"
    ) | awk -F'|' -v f="$2" -v s="$3" '$1 == f && $2 == s'
}

# reasons_of <行>: 理由の欄を出す
reasons_of() {
    printf '%s' "$1" | awk -F'|' '{print $3}'
}

ok() { pass=$((pass + 1)); printf 'ok:   %s\n' "$1"; }
ng() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; }

# expect_reasons <名前> <プロジェクト> <feature> <段階> <期待する理由の欄>
# 行が出ていて、理由の欄が期待どおりであることを確かめる
expect_reasons() {
    local name="$1" line got
    line=$(scan_line "$2" "$3" "$4")
    if [ -z "$line" ]; then
        ng "$name (行が出ていない。期待: '$5')"
        return
    fi
    got=$(reasons_of "$line")
    if [ "$got" = "$5" ]; then
        ok "$name"
    else
        ng "$name (期待: '$5' / 実際: '$got')"
    fi
}

# expect_no_style_reason <名前> <プロジェクト> <feature> <段階>
# 行が無いか、行の理由の欄に点検についての理由が無いことを確かめる
expect_no_style_reason() {
    local name="$1" line got
    line=$(scan_line "$2" "$3" "$4")
    got=$(reasons_of "$line")
    case "$got" in
        *"$NO_RECORD"* | *"$BODY_NEWER"*) ng "$name (実際: '$got')" ;;
        *) ok "$name" ;;
    esac
}

SPEC_V1='{"feature_name":"f","phase":"requirements-generated","approvals":{"requirements":{"generated":true,"approved":false}}}'
SPEC_V2='{"feature_name":"f","spec_format":2,"phase":"requirements-generated","approvals":{"requirements":{"generated":true,"approved":false}}}'

echo "--- 1. spec_format の欄が無い spec では、点検の記録が無くても理由を出さない"
P="$WORK/case1"
make_spec "$P" v1spec "$SPEC_V1"
make_stage "$P" v1spec requirements
expect_reasons "欄の無い spec・記録なし" "$P" v1spec requirements ""

echo "--- 2. spec_format が2の spec で点検の記録が無ければ「$NO_RECORD」を出す"
P="$WORK/case2"
make_spec "$P" v2spec "$SPEC_V2"
make_stage "$P" v2spec requirements
expect_reasons "記録なし" "$P" v2spec requirements "$NO_RECORD"

echo "--- 3. 本文が点検の記録より新しければ「$BODY_NEWER」を出す"
P="$WORK/case3"
make_spec "$P" v2spec "$SPEC_V2"
make_stage "$P" v2spec requirements
make_style "$P" v2spec requirements "2025-12-31 00:00:00"
expect_reasons "本文が記録より新しい" "$P" v2spec requirements "$BODY_NEWER"

echo "--- 4. 点検の記録が本文より新しければ、点検についての理由を出さない"
P="$WORK/case4"
make_spec "$P" v2spec "$SPEC_V2"
make_stage "$P" v2spec requirements
make_style "$P" v2spec requirements "2026-01-03 00:00:00"
expect_reasons "記録が本文より新しい" "$P" v2spec requirements ""

echo "--- 5. 人が承認した段階では、点検の記録が無くても理由を出さない"
P="$WORK/case5"
make_spec "$P" v2spec '{"feature_name":"f","spec_format":2,"phase":"design-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"dogis","approved_at":"2026-01-01T00:00:00Z"},"design":{"generated":true,"approved":false}}}'
make_stage "$P" v2spec requirements
make_stage "$P" v2spec design
expect_no_style_reason "人が承認した段階・記録なし" "$P" v2spec requirements
# 同じ spec の未承認の段階は判定される(承認の有無だけで分かれていることの確かめ)
expect_reasons "同じ spec の未承認の段階・記録なし" "$P" v2spec design "$NO_RECORD"

echo "--- 5b. approved_by が ':' を含む承認(自動の承認)は人の承認ではないので判定する"
P="$WORK/case5b"
make_spec "$P" v2spec '{"feature_name":"f","spec_format":2,"phase":"requirements-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"auto:-y"}}}'
make_stage "$P" v2spec requirements
expect_reasons "自動の承認・記録なし" "$P" v2spec requirements "$NO_RECORD"

echo
printf '結果: 成功 %d / 失敗 %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
