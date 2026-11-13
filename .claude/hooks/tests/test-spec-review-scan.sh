#!/bin/bash
# =====================================================================
# spec-review-scan.sh のテスト(書き方の点検の記録の判定)
#
# 実行: bash .claude/hooks/tests/test-spec-review-scan.sh
# 一時的なプロジェクトのディレクトリを場合ごとに作り、check-spec-review-before-stop.sh と
# 同じく scan を source して spec_review_scan を呼び、出力の理由の欄を確かめる。
# 審査の記録・対応の記録・証跡は、審査についての理由が出ない状態にそろえ、
# 点検の記録と本文の変更日時と承認の記録だけを場合ごとに変える。
# 点検の記録は、spec.json の欄に依らず、人の承認の無い段階のすべてで判定される。
# 人の承認には、所有者が出した承認のほか、特例で承認済みにした段階
# (approved_by が DogisRiki で、approval_history に特例の要素を持つ段階)も含まれる。
# 後半では、判定の対象の段階の選び方と、spec が多いときに Stop フックと
# 知らせるフックがフックの時間の上限の内に終わることを確かめる(#828)。
# 前提: bash・perl(JSON::PP)。
# =====================================================================
set -u

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$HOOKS/spec-review-scan.sh"
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

# requirements が生成済みで未承認の spec
SPEC_UNAPPROVED='{"feature_name":"f","phase":"requirements-generated","approvals":{"requirements":{"generated":true,"approved":false}}}'

echo "--- 1. 印の無い spec でも、点検の記録が無ければ「$NO_RECORD」を出す"
P="$WORK/case1"
make_spec "$P" plain "$SPEC_UNAPPROVED"
make_stage "$P" plain requirements
expect_reasons "印の無い spec・記録なし" "$P" plain requirements "$NO_RECORD"

echo "--- 2. 点検の記録が無ければ「$NO_RECORD」を出す"
P="$WORK/case2"
make_spec "$P" spec "$SPEC_UNAPPROVED"
make_stage "$P" spec requirements
expect_reasons "記録なし" "$P" spec requirements "$NO_RECORD"

echo "--- 3. 本文が点検の記録より新しければ「$BODY_NEWER」を出す"
P="$WORK/case3"
make_spec "$P" spec "$SPEC_UNAPPROVED"
make_stage "$P" spec requirements
make_style "$P" spec requirements "2025-12-31 00:00:00"
expect_reasons "本文が記録より新しい" "$P" spec requirements "$BODY_NEWER"

echo "--- 4. 点検の記録が本文より新しければ、点検についての理由を出さない"
P="$WORK/case4"
make_spec "$P" spec "$SPEC_UNAPPROVED"
make_stage "$P" spec requirements
make_style "$P" spec requirements "2026-01-03 00:00:00"
expect_reasons "記録が本文より新しい" "$P" spec requirements ""

echo "--- 5. 人が承認した段階では、点検の記録が無くても理由を出さない"
P="$WORK/case5"
make_spec "$P" spec '{"feature_name":"f","phase":"design-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"dogis","approved_at":"2026-01-01T00:00:00Z"},"design":{"generated":true,"approved":false}}}'
make_stage "$P" spec requirements
make_stage "$P" spec design
expect_no_style_reason "人が承認した段階・記録なし" "$P" spec requirements
# 同じ spec の未承認の段階は判定される(承認の有無だけで分かれていることの確かめ)
expect_reasons "同じ spec の未承認の段階・記録なし" "$P" spec design "$NO_RECORD"

echo "--- 5b. approved_by が ':' を含む承認(自動の承認)は人の承認ではないので判定する"
P="$WORK/case5b"
make_spec "$P" spec '{"feature_name":"f","phase":"requirements-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"auto:-y"}}}'
make_stage "$P" spec requirements
expect_reasons "自動の承認・記録なし" "$P" spec requirements "$NO_RECORD"

echo "--- 6. 特例で承認済みにした段階では、点検の記録が無くても理由を出さない"
P="$WORK/case6"
make_spec "$P" spec '{"feature_name":"f","issue":100,"phase":"design-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"DogisRiki","approved_at":"2026-02-01T00:00:00Z"},"design":{"generated":true,"approved":false}},"approval_history":[{"stage":"requirements","approved_by":"dogis","approved_at":"2026-01-01T00:00:00Z","issues":[100],"revoked_at":"2026-02-01T00:00:00Z","revoked_for":"Issue #477 の特例: 新しい書き方へ書き換えた。書き換えの前後で中身が同じと Fable 5.1 が確かめた(reviews/rewrite-check.md)。この時点からの承認は特例によるもので、所有者は本文を読んで承認し直していない"}]}'
make_stage "$P" spec requirements
make_stage "$P" spec design
expect_no_style_reason "特例で承認済みにした段階・記録なし" "$P" spec requirements
# 同じ spec の未承認の段階は判定される(承認の有無だけで分かれていることの確かめ)
expect_reasons "特例の spec の未承認の段階・記録なし" "$P" spec design "$NO_RECORD"

# scan_targets <プロジェクト>: 出た行の "<feature>|<stage>" を出た順に出す
scan_targets() {
    (
        # shellcheck source=/dev/null
        . "$SCAN"
        spec_review_scan "$1"
    ) | awk -F'|' '{print $1 "|" $2}'
}

# expect_targets <名前> <プロジェクト> <期待する "<feature>|<stage>" の並び(改行区切り)>
expect_targets() {
    local got
    got=$(scan_targets "$2")
    if [ "$got" = "$3" ]; then
        ok "$1"
    else
        ng "$1 (期待: '$(printf '%s' "$3" | tr '\n' ' ')' / 実際: '$(printf '%s' "$got" | tr '\n' ' ')')"
    fi
}

SPEC_APPROVED='{"feature_name":"f","phase":"tasks-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"dogis"},"design":{"generated":true,"approved":true,"approved_by":"dogis"},"tasks":{"generated":true,"approved":true,"approved_by":"dogis"}}}'

echo "--- 7. phase が initialized の spec は、生成済みの段階があっても判定しない"
P="$WORK/case7"
make_spec "$P" init '{"feature_name":"f","phase":"initialized","approvals":{"requirements":{"generated":true,"approved":false}}}'
expect_targets "initialized の spec" "$P" ""

echo "--- 8. JSON として読めない spec.json は飛ばし、ほかの spec は判定する"
P="$WORK/case8"
make_spec "$P" a-broken '{"feature_name":'
make_spec "$P" b-array '[1,2]'
make_spec "$P" c-ok "$SPEC_UNAPPROVED"
expect_targets "読めない spec.json を飛ばす" "$P" "c-ok|requirements"

echo "--- 9. 判定の対象の段階を、spec の名前の順、段階の順に出す"
P="$WORK/case9"
make_spec "$P" a '{"feature_name":"a","phase":"tasks-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"dogis"},"design":{"generated":true,"approved":false},"tasks":{"generated":true,"approved":true,"approved_by":"auto:batch"}}}'
make_spec "$P" b '{"feature_name":"b","phase":"requirements-generated","approvals":{"requirements":{"generated":"true","approved":true,"approved_by":""},"design":{"generated":false,"approved":false}}}'
make_spec "$P" c "$SPEC_APPROVED"
expect_targets "対象の段階の並び" "$P" "a|design
a|tasks
b|requirements"

echo "--- 10. spec が多くても、2つのフックが時間の上限の内に終わり、審査の残りを示す"
# 上限は settings.json の notify-spec-review.sh の 20 秒(Stop フックは 30 秒)
LIMIT=20
P="$WORK/case10"
mkdir -p "$P/.claude/hooks"
cp "$SCAN" "$P/.claude/hooks/spec-review-scan.sh"
i=0
while [ "$i" -lt 80 ]; do
    make_spec "$P" "approved-$i" "$SPEC_APPROVED"
    i=$((i + 1))
done
make_spec "$P" z-pending "$SPEC_UNAPPROVED"

start=$SECONDS
err=$(printf '{"prompt_id":"p10","session_id":"s10"}' \
    | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/check-spec-review-before-stop.sh" 2>&1 >/dev/null)
code=$?
took=$((SECONDS - start))
if [ "$code" -eq 2 ] && printf '%s' "$err" | grep -q 'z-pending の requirements: レビュー未実施'; then
    ok "Stop フックが審査の残りで止める"
else
    ng "Stop フックが審査の残りで止める (終了コード: $code / 出力: $err)"
fi
if [ "$took" -lt "$LIMIT" ]; then
    ok "Stop フックが ${LIMIT} 秒より前に終わる (${took} 秒)"
else
    ng "Stop フックが ${LIMIT} 秒より前に終わる (${took} 秒)"
fi

start=$SECONDS
out=$(printf '{"prompt":"x"}' | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/notify-spec-review.sh" 2>/dev/null)
code=$?
took=$((SECONDS - start))
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'z-pending / requirements: レビュー未完了(レビュー未実施'; then
    ok "知らせるフックが審査の残りを示す"
else
    ng "知らせるフックが審査の残りを示す (終了コード: $code / 出力: $out)"
fi
if [ "$took" -lt "$LIMIT" ]; then
    ok "知らせるフックが ${LIMIT} 秒より前に終わる (${took} 秒)"
else
    ng "知らせるフックが ${LIMIT} 秒より前に終わる (${took} 秒)"
fi

echo "--- 11. 審査の残りが無ければ、Stop フックは止めない"
P="$WORK/case11"
mkdir -p "$P/.claude/hooks"
cp "$SCAN" "$P/.claude/hooks/spec-review-scan.sh"
make_spec "$P" approved "$SPEC_APPROVED"
printf '{"prompt_id":"p11"}' | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/check-spec-review-before-stop.sh" >/dev/null 2>&1
code=$?
if [ "$code" -eq 0 ]; then
    ok "審査の残りが無ければ止めない"
else
    ng "審査の残りが無ければ止めない (終了コード: $code)"
fi

echo
printf '結果: 成功 %d / 失敗 %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
