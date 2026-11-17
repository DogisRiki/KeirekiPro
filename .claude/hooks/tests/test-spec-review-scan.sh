#!/bin/bash
# =====================================================================
# spec-review-scan.sh のテスト
#
# 実行: bash .claude/hooks/tests/test-spec-review-scan.sh
# 場合を選んで流す: KP_TEST_CASE='t_kept_fix_unreviewed t_kept_fix_hooks' bash .claude/hooks/tests/test-spec-review-scan.sh
#   KP_TEST_CASE に空白で区切って書いた関数の名前の場合だけを流す。知らない名前があれば何も流さずに失敗する
# 一時的なプロジェクトのディレクトリを場合ごとに作り、check-spec-review-before-stop.sh と
# 同じく scan を source して spec_review_scan を呼び、出力の理由の欄を確かめる。
#
# 前半は、書き方の点検の記録の判定を確かめる。審査の記録・対応の記録・証跡は、
# 審査についての理由が出ない状態にそろえ、点検の記録と本文の変更日時と承認の記録だけを
# 場合ごとに変える。点検の記録は、spec.json の欄に依らず、人の承認の無い段階のすべてで
# 判定される。人の承認には、所有者が出した承認のほか、特例で承認済みにした段階
# (approved_by が DogisRiki で、approval_history に特例の要素を持つ段階)も含まれる。
# 中ほどでは、判定の対象の段階の選び方と、spec が多いときに Stop フックと
# 知らせるフックがフックの時間の上限の内に終わることを確かめる(#828)。
# 後半では、承認を残して直した前の段階が、見つけた段階でレビューされるまで
# 走査が行を出すことを確かめる(#900)。
# 前提: bash・perl(JSON::PP)。
# =====================================================================
set -u

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$HOOKS/spec-review-scan.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

NO_RECORD="書き方の点検の記録がない"
BODY_NEWER="本文が書き方の点検より新しい"
KEPT_TASKS="承認を残して直したあとの審査がない(tasks の審査)"

T_BODY="2026-01-01 00:00:00"
T_REVIEW="2026-01-02 00:00:00"
T_STYLE="2026-01-03 00:00:00"
T_FIXED="2026-01-04 00:00:00"

pass=0
fail=0

# run_test <テスト名> <関数>: 場合を1つ流す。関数が 0 以外で終われば失敗とする
run_test() {
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

# scan_all <プロジェクト>: 走査の出力をそのまま出す
scan_all() {
    (
        # shellcheck source=/dev/null
        . "$SCAN"
        spec_review_scan "$1"
    )
}

# scan_line <プロジェクト> <feature> <段階>: 該当する行を出す(無ければ空)
scan_line() {
    scan_all "$1" | awk -F'|' -v f="$2" -v s="$3" '$1 == f && $2 == s'
}

# reasons_of <行>: 理由の欄を出す
reasons_of() {
    printf '%s' "$1" | awk -F'|' '{print $3}'
}

# expect_reasons <名前> <プロジェクト> <feature> <段階> <期待する理由の欄>
# 行が出ていて、理由の欄が期待どおりであることを確かめる
expect_reasons() {
    local name="$1" line got
    line=$(scan_line "$2" "$3" "$4")
    if [ -z "$line" ]; then
        echo "$name (行が出ていない。期待: '$5')"
        return 1
    fi
    got=$(reasons_of "$line")
    if [ "$got" != "$5" ]; then
        echo "$name (期待: '$5' / 実際: '$got')"
        return 1
    fi
}

# expect_no_style_reason <名前> <プロジェクト> <feature> <段階>
# 行が無いか、行の理由の欄に点検についての理由が無いことを確かめる
expect_no_style_reason() {
    local name="$1" line got
    line=$(scan_line "$2" "$3" "$4")
    got=$(reasons_of "$line")
    case "$got" in
        *"$NO_RECORD"* | *"$BODY_NEWER"*)
            echo "$name (実際: '$got')"
            return 1
            ;;
    esac
}

# expect_line_count <名前> <プロジェクト> <feature> <段階> <期待する行の数>
expect_line_count() {
    local name="$1" got
    got=$(scan_line "$2" "$3" "$4" | grep -c .)
    if [ "$got" -ne "$5" ]; then
        echo "$name (行の数の期待: $5 / 実際: $got)"
        scan_line "$2" "$3" "$4" | sed 's/^/      /'
        return 1
    fi
}

# scan_targets <プロジェクト>: 出た行の "<feature>|<stage>" を出た順に出す
scan_targets() {
    scan_all "$1" | awk -F'|' '{print $1 "|" $2}'
}

# expect_targets <名前> <プロジェクト> <期待する "<feature>|<stage>" の並び(改行区切り)>
expect_targets() {
    local got
    got=$(scan_targets "$2")
    if [ "$got" != "$3" ]; then
        echo "$1 (期待: '$(printf '%s' "$3" | tr '\n' ' ')' / 実際: '$(printf '%s' "$got" | tr '\n' ' ')')"
        return 1
    fi
}

# use_project_scan <プロジェクト>: フックが読む場所に走査を置く
use_project_scan() {
    mkdir -p "$1/.claude/hooks"
    cp "$SCAN" "$1/.claude/hooks/spec-review-scan.sh"
}

# requirements が生成済みで未承認の spec
SPEC_UNAPPROVED='{"feature_name":"f","phase":"requirements-generated","approvals":{"requirements":{"generated":true,"approved":false}}}'

SPEC_APPROVED='{"feature_name":"f","phase":"tasks-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"dogis"},"design":{"generated":true,"approved":true,"approved_by":"dogis"},"tasks":{"generated":true,"approved":true,"approved_by":"dogis"}}}'

# ---------------------------------------------------------------------
# 書き方の点検の記録の判定

# 印の無い spec でも、点検の記録が無ければ「書き方の点検の記録がない」を出す
t_style_plain_spec_no_record() {
    local P="$WORK/case"
    make_spec "$P" plain "$SPEC_UNAPPROVED"
    make_stage "$P" plain requirements
    expect_reasons "印の無い spec・記録なし" "$P" plain requirements "$NO_RECORD"
}

# 点検の記録が無ければ「書き方の点検の記録がない」を出す
t_style_no_record() {
    local P="$WORK/case"
    make_spec "$P" spec "$SPEC_UNAPPROVED"
    make_stage "$P" spec requirements
    expect_reasons "記録なし" "$P" spec requirements "$NO_RECORD"
}

# 本文が点検の記録より新しければ「本文が書き方の点検より新しい」を出す
t_style_body_newer() {
    local P="$WORK/case"
    make_spec "$P" spec "$SPEC_UNAPPROVED"
    make_stage "$P" spec requirements
    make_style "$P" spec requirements "2025-12-31 00:00:00"
    expect_reasons "本文が記録より新しい" "$P" spec requirements "$BODY_NEWER"
}

# 点検の記録が本文より新しければ、点検についての理由を出さない
t_style_record_newer() {
    local P="$WORK/case"
    make_spec "$P" spec "$SPEC_UNAPPROVED"
    make_stage "$P" spec requirements
    make_style "$P" spec requirements "$T_STYLE"
    expect_reasons "記録が本文より新しい" "$P" spec requirements ""
}

# 人が承認した段階では、点検の記録が無くても理由を出さない
t_style_human_approved() {
    local P="$WORK/case" rc=0
    make_spec "$P" spec '{"feature_name":"f","phase":"design-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"dogis","approved_at":"2026-01-01T00:00:00Z"},"design":{"generated":true,"approved":false}}}'
    make_stage "$P" spec requirements
    make_stage "$P" spec design
    expect_no_style_reason "人が承認した段階・記録なし" "$P" spec requirements || rc=1
    # 同じ spec の未承認の段階は判定される(承認の有無だけで分かれていることの確かめ)
    expect_reasons "同じ spec の未承認の段階・記録なし" "$P" spec design "$NO_RECORD" || rc=1
    return $rc
}

# approved_by が ':' を含む承認(自動の承認)は人の承認ではないので判定する
t_style_auto_approved() {
    local P="$WORK/case"
    make_spec "$P" spec '{"feature_name":"f","phase":"requirements-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"auto:-y"}}}'
    make_stage "$P" spec requirements
    expect_reasons "自動の承認・記録なし" "$P" spec requirements "$NO_RECORD"
}

# 特例で承認済みにした段階では、点検の記録が無くても理由を出さない
t_style_special_approved() {
    local P="$WORK/case" rc=0
    make_spec "$P" spec '{"feature_name":"f","issue":100,"phase":"design-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"DogisRiki","approved_at":"2026-02-01T00:00:00Z"},"design":{"generated":true,"approved":false}},"approval_history":[{"stage":"requirements","approved_by":"dogis","approved_at":"2026-01-01T00:00:00Z","issues":[100],"revoked_at":"2026-02-01T00:00:00Z","revoked_for":"Issue #477 の特例: 新しい書き方へ書き換えた。書き換えの前後で中身が同じと Fable 5.1 が確かめた(reviews/rewrite-check.md)。この時点からの承認は特例によるもので、所有者は本文を読んで承認し直していない"}]}'
    make_stage "$P" spec requirements
    make_stage "$P" spec design
    expect_no_style_reason "特例で承認済みにした段階・記録なし" "$P" spec requirements || rc=1
    # 同じ spec の未承認の段階は判定される(承認の有無だけで分かれていることの確かめ)
    expect_reasons "特例の spec の未承認の段階・記録なし" "$P" spec design "$NO_RECORD" || rc=1
    return $rc
}

# ---------------------------------------------------------------------
# 判定の対象の段階の選び方と、フックの時間の上限(#828)

# phase が initialized の spec は、生成済みの段階があっても判定しない
t_targets_initialized() {
    local P="$WORK/case"
    make_spec "$P" init '{"feature_name":"f","phase":"initialized","approvals":{"requirements":{"generated":true,"approved":false}}}'
    expect_targets "initialized の spec" "$P" ""
}

# JSON として読めない spec.json は飛ばし、ほかの spec は判定する
t_targets_skip_broken_json() {
    local P="$WORK/case"
    make_spec "$P" a-broken '{"feature_name":'
    make_spec "$P" b-array '[1,2]'
    make_spec "$P" c-ok "$SPEC_UNAPPROVED"
    expect_targets "読めない spec.json を飛ばす" "$P" "c-ok|requirements"
}

# 判定の対象の段階を、spec の名前の順、段階の順に出す
t_targets_order() {
    local P="$WORK/case"
    make_spec "$P" a '{"feature_name":"a","phase":"tasks-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"dogis"},"design":{"generated":true,"approved":false},"tasks":{"generated":true,"approved":true,"approved_by":"auto:batch"}}}'
    make_spec "$P" b '{"feature_name":"b","phase":"requirements-generated","approvals":{"requirements":{"generated":"true","approved":true,"approved_by":""},"design":{"generated":false,"approved":false}}}'
    make_spec "$P" c "$SPEC_APPROVED"
    expect_targets "対象の段階の並び" "$P" "a|design
a|tasks
b|requirements"
}

# spec が多くても、2つのフックが時間の上限の内に終わり、審査の残りを示す
t_hooks_many_specs_within_limit() {
    # 上限は settings.json の notify-spec-review.sh の 20 秒(Stop フックは 30 秒)
    local LIMIT=20 P="$WORK/case" rc=0 i start err out code took
    use_project_scan "$P"
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
    if ! { [ "$code" -eq 2 ] && printf '%s' "$err" | grep -q 'z-pending の requirements: レビュー未実施'; }; then
        echo "Stop フックが審査の残りで止める (終了コード: $code / 出力: $err)"
        rc=1
    fi
    if [ "$took" -ge "$LIMIT" ]; then
        echo "Stop フックが ${LIMIT} 秒より前に終わる (${took} 秒)"
        rc=1
    fi

    start=$SECONDS
    out=$(printf '{"prompt":"x"}' | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/notify-spec-review.sh" 2>/dev/null)
    code=$?
    took=$((SECONDS - start))
    if ! { [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'z-pending / requirements: レビュー未完了(レビュー未実施'; }; then
        echo "知らせるフックが審査の残りを示す (終了コード: $code / 出力: $out)"
        rc=1
    fi
    if [ "$took" -ge "$LIMIT" ]; then
        echo "知らせるフックが ${LIMIT} 秒より前に終わる (${took} 秒)"
        rc=1
    fi
    return $rc
}

# 審査の残りが無ければ、Stop フックは止めない
t_stop_hook_passes_when_clean() {
    local P="$WORK/case" code
    use_project_scan "$P"
    make_spec "$P" approved "$SPEC_APPROVED"
    printf '{"prompt_id":"p11"}' | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/check-spec-review-before-stop.sh" >/dev/null 2>&1
    code=$?
    if [ "$code" -ne 0 ]; then
        echo "審査の残りが無ければ止めない (終了コード: $code)"
        return 1
    fi
}

# ---------------------------------------------------------------------
# 承認を残して直した前の段階の判定(#900)

# kept_spec <tasks の承認> <design の承認> <kept_approval_fixes の JSON(空なら欄を書かない)>
# requirements は人の承認あり。承認は "human" か "none"
kept_spec() {
    local tasks_appr design_appr kept=""
    case "$1" in
        human) tasks_appr='"approved":true,"approved_by":"dogis","approved_at":"2026-01-05T00:00:00Z"' ;;
        *) tasks_appr='"approved":false' ;;
    esac
    case "$2" in
        human) design_appr='"approved":true,"approved_by":"dogis","approved_at":"2026-01-01T00:00:00Z"' ;;
        *) design_appr='"approved":false' ;;
    esac
    [ -n "$3" ] && kept=",\"kept_approval_fixes\":$3"
    printf '{"feature_name":"k","phase":"tasks-generated","approvals":{"requirements":{"generated":true,"approved":true,"approved_by":"dogis","approved_at":"2026-01-01T00:00:00Z"},"design":{"generated":true,%s},"tasks":{"generated":true,%s}}%s}' \
        "$design_appr" "$tasks_appr" "$kept"
}

KEPT_DESIGN='[{"no":1,"kind":"fix","stage":"design","found_in":"tasks","finding_ids":["T1-1-1"],"fixed_at":"2026-01-04T00:00:00Z","review_cycle":1,"review_round":2}]'

# make_kept_state <プロジェクト> <tasks の承認> <design の承認> <kept_approval_fixes の JSON> <design.md の変更日時>
# 3つの段階の本文を作り、tasks を審査についての理由が出ない状態にし、design.md の変更日時を変える
make_kept_state() {
    local P="$1"
    make_spec "$P" k "$(kept_spec "$2" "$3" "$4")"
    make_stage "$P" k requirements
    make_stage "$P" k design
    make_stage "$P" k tasks
    make_style "$P" k requirements "$T_STYLE"
    make_style "$P" k design "$T_STYLE"
    make_style "$P" k tasks "$T_STYLE"
    touch -d "$5" "$P/.kiro/specs/k/design.md"
}

# 項目23: design を承認を残して直し、design.md が tasks-review.md より新しいとき、design の行を出す
t_kept_fix_unreviewed() {
    local P="$WORK/case"
    make_kept_state "$P" none human "$KEPT_DESIGN" "$T_FIXED"
    expect_reasons "承認を残した直しがまだ審査されていない" "$P" k design "$KEPT_TASKS"
}

# 項目24: tasks-review.md が design.md より新しいとき、design の行を出さない
t_kept_fix_reviewed() {
    local P="$WORK/case" rc=0
    make_kept_state "$P" none human "$KEPT_DESIGN" "$T_BODY"
    expect_line_count "承認を残した直しが審査済み" "$P" k design 0 || rc=1
    # tasks の行は今までどおり出る(審査についての理由は無い)
    expect_reasons "tasks の行" "$P" k tasks "" || rc=1
    return $rc
}

# 項目25: tasks-review.md が無いとき、design の行を出す
t_kept_fix_no_review_file() {
    local P="$WORK/case"
    make_kept_state "$P" none human "$KEPT_DESIGN" "$T_BODY"
    rm -f "$P/.kiro/specs/k/reviews/tasks-review.md"
    expect_reasons "見つけた段階の審査の記録が無い" "$P" k design "$KEPT_TASKS"
}

# 項目26: tasks が人の承認ありになったとき、design の行を出さない
t_kept_fix_later_approved() {
    local P="$WORK/case" rc=0
    make_kept_state "$P" human human "$KEPT_DESIGN" "$T_FIXED"
    expect_line_count "見つけた段階が承認済み" "$P" k design 0 || rc=1
    # requirements だけを承認なしにして、spec が走査の出力に残る状態でも、design の行を出さない
    make_spec "$P" k "$(kept_spec human human "$KEPT_DESIGN" | sed 's/"requirements":{"generated":true,"approved":true,"approved_by":"dogis","approved_at":"2026-01-01T00:00:00Z"}/"requirements":{"generated":true,"approved":false}/')"
    expect_line_count "requirements が承認なしの spec の requirements の行" "$P" k requirements 1 || rc=1
    expect_line_count "requirements が承認なしの spec の design の行" "$P" k design 0 || rc=1
    return $rc
}

# 項目27: design が承認なしのとき、design の行を「承認を残して直したあとの審査がない」で出さない
t_kept_fix_earlier_unapproved() {
    local P="$WORK/case" rc=0 got
    make_kept_state "$P" none none "$KEPT_DESIGN" "$T_FIXED"
    # 今の段階ごとの判定の行だけが、1行出る
    expect_line_count "直した段階が承認なし" "$P" k design 1 || rc=1
    got=$(reasons_of "$(scan_line "$P" k design)")
    case "$got" in
        *"承認を残して直したあとの審査がない"*)
            echo "直した段階が承認なしのときに承認を残した直しの理由が出た (実際: '$got')"
            rc=1
            ;;
    esac
    return $rc
}

# 項目28: kept_approval_fixes が無い spec と、配列でない spec と、段階の名前でない要素だけの spec で、
# 走査の出力が変わらない
t_no_kept_fixes() {
    local P="$WORK/case" rc=0 base got kept
    make_kept_state "$P" none human "" "$T_FIXED"
    base=$(scan_all "$P")
    if [ -z "$base" ]; then
        echo "kept_approval_fixes の無い spec で走査が何も出さない"
        return 1
    fi
    for kept in '{"no":1,"stage":"design","found_in":"tasks"}' '"design"' '1' \
        '[{"no":1,"kind":"fix","stage":"foo","found_in":"tasks"},{"no":2,"kind":"fix","stage":"design","found_in":"bar"},{"no":3,"kind":"fix"},"x"]'; do
        make_spec "$P" k "$(kept_spec none human "$kept")"
        got=$(scan_all "$P")
        if [ "$got" != "$base" ]; then
            echo "kept_approval_fixes が $kept のとき出力が変わった"
            printf '      期待: %s\n      実際: %s\n' "$base" "$got"
            rc=1
        fi
    done
    return $rc
}

# 項目29: requirements と design の両方の要素があり、同じ組が2つあっても、段階ごとに1行ずつ出す
t_kept_fix_two_stages() {
    local P="$WORK/case" rc=0
    make_kept_state "$P" none human '[{"no":1,"kind":"fix","stage":"requirements","found_in":"tasks","finding_ids":["T1-1-1"],"fixed_at":"2026-01-04T00:00:00Z","review_cycle":1,"review_round":2},{"no":2,"kind":"fix","stage":"design","found_in":"tasks","finding_ids":["T1-1-2"],"fixed_at":"2026-01-04T00:00:00Z","review_cycle":1,"review_round":2},{"no":3,"kind":"fix","stage":"design","found_in":"tasks","finding_ids":["T1-2-1"],"fixed_at":"2026-01-04T00:00:00Z","review_cycle":1,"review_round":3}]' "$T_FIXED"
    touch -d "$T_FIXED" "$P/.kiro/specs/k/requirements.md"
    expect_line_count "requirements の行は1行" "$P" k requirements 1 || rc=1
    expect_reasons "requirements の行の理由" "$P" k requirements "$KEPT_TASKS" || rc=1
    expect_line_count "同じ組の要素が2つある design の行は1行" "$P" k design 1 || rc=1
    expect_reasons "design の行の理由" "$P" k design "$KEPT_TASKS" || rc=1
    return $rc
}

# 項目30: 承認を残した直しがまだ審査されていないとき、停止をブロックするフックが終了を止め、
# 通知フックが一覧に design の行を出す
t_kept_fix_hooks() {
    local P="$WORK/case" rc=0 err out code
    use_project_scan "$P"
    make_kept_state "$P" none human "$KEPT_DESIGN" "$T_FIXED"

    err=$(printf '{"prompt_id":"p30"}' \
        | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/check-spec-review-before-stop.sh" 2>&1 >/dev/null)
    code=$?
    if ! { [ "$code" -eq 2 ] && printf '%s' "$err" | grep -qF "k の design: $KEPT_TASKS"; }; then
        echo "Stop フックが承認を残した直しで止める (終了コード: $code / 出力: $err)"
        rc=1
    fi

    out=$(printf '{"prompt":"x"}' | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/notify-spec-review.sh" 2>/dev/null)
    code=$?
    if ! { [ "$code" -eq 0 ] && printf '%s' "$out" | grep -qF "k / design: レビュー未完了($KEPT_TASKS)"; }; then
        echo "知らせるフックが承認を残した直しを示す (終了コード: $code / 出力: $out)"
        rc=1
    fi
    return $rc
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

echo "--- 書き方の点検の記録の判定"
run_test "印の無い spec でも、点検の記録が無ければ「$NO_RECORD」を出す" t_style_plain_spec_no_record
run_test "点検の記録が無ければ「$NO_RECORD」を出す" t_style_no_record
run_test "本文が点検の記録より新しければ「$BODY_NEWER」を出す" t_style_body_newer
run_test "点検の記録が本文より新しければ、点検についての理由を出さない" t_style_record_newer
run_test "人が承認した段階では、点検の記録が無くても理由を出さない" t_style_human_approved
run_test "approved_by が ':' を含む承認(自動の承認)は人の承認ではないので判定する" t_style_auto_approved
run_test "特例で承認済みにした段階では、点検の記録が無くても理由を出さない" t_style_special_approved

echo "--- 判定の対象の段階の選び方と、フックの時間の上限(#828)"
run_test "phase が initialized の spec は、生成済みの段階があっても判定しない" t_targets_initialized
run_test "JSON として読めない spec.json は飛ばし、ほかの spec は判定する" t_targets_skip_broken_json
run_test "判定の対象の段階を、spec の名前の順、段階の順に出す" t_targets_order
run_test "spec が多くても、2つのフックが時間の上限の内に終わり、審査の残りを示す" t_hooks_many_specs_within_limit
run_test "審査の残りが無ければ、Stop フックは止めない" t_stop_hook_passes_when_clean

echo "--- 承認を残して直した前の段階の判定(#900)"
run_test "承認を残して直した design が tasks の審査より新しければ design の行を出す(項目23)" t_kept_fix_unreviewed
run_test "tasks の審査が直した design より新しければ design の行を出さない(項目24)" t_kept_fix_reviewed
run_test "tasks の審査の記録が無ければ design の行を出す(項目25)" t_kept_fix_no_review_file
run_test "tasks が人の承認ありなら design の行を出さない(項目26)" t_kept_fix_later_approved
run_test "design が承認なしなら承認を残した直しの理由を出さない(項目27)" t_kept_fix_earlier_unapproved
run_test "kept_approval_fixes が無いか読めなければ出力が変わらない(項目28)" t_no_kept_fixes
run_test "requirements と design の直しを段階ごとに1行ずつ出し、同じ組を1つにまとめる(項目29)" t_kept_fix_two_stages
run_test "承認を残した直しが審査されていなければ2つのフックが止めて示す(項目30)" t_kept_fix_hooks

echo
printf '結果: 成功 %d / 失敗 %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
