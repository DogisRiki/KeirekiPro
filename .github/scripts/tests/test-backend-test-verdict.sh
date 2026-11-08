#!/usr/bin/env bash
# =====================================================================
# backend-test-verdict.sh の自動テスト(guardrails CI の escape-hatch から実行)
#
# 3つの見分けと3つの仕事の結果を環境変数で渡して判定を流し、終了コードと
# ::error の行を確かめる。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/backend-test-verdict.sh"
FAILED=0
CASE="${KP_TEST_CASE:-}"
OUT=""
RC=0

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1 ($2)"
    FAILED=1
}

RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        return 0
    fi
    return 1
}

# 使い方: verdict <java の見分け> <go の見分け> <compat の見分け> <java の結果> <go の結果> <compat の結果>
verdict() {
    OUT=$(BACKEND_JAVA="$1" BACKEND_GO="$2" BACKEND_COMPAT="$3" \
        JAVA_RESULT="$4" GO_RESULT="$5" COMPAT_RESULT="$6" \
        bash "$SCRIPT" 2>&1)
    RC=$?
}

# 使い方: expect <場合の説明> <期待する終了コード> <::error の行の数> [<出力に含まれるはずの文字列>...]
expect() {
    local name="$1" want_rc="$2" want_errors="$3" errors s
    shift 3
    errors=$(printf '%s\n' "$OUT" | grep -c '^::error::')
    if [ "$RC" != "$want_rc" ]; then
        fail "$name" "終了コード: 期待 $want_rc / 実際 $RC。出力: $OUT"
        return
    fi
    if [ "$errors" != "$want_errors" ]; then
        fail "$name" "::error の行の数: 期待 $want_errors / 実際 $errors。出力: $OUT"
        return
    fi
    for s in "$@"; do
        case "$OUT" in
            *"$s"*) ;;
            *)
                fail "$name" "出力に「$s」がありません。出力: $OUT"
                return
                ;;
        esac
    done
    pass "$name"
}

if want java_only_success; then
    verdict true false false success skipped skipped
    expect "backend_go と backend_compat が当たらず backend-java が success なら成功する" 0 0 \
        "backend-test の判定: 見分けが当たった仕事はすべて通りました。"
fi

if want hit_skipped; then
    verdict true true false success skipped skipped
    expect "見分けが当たった仕事が skipped なら失敗する" 1 1 \
        "::error::見分け backend_go が当たったのに、仕事 backend-go が飛ばされました。" \
        "backend-test の判定: 1 件の問題があります。"
fi

if want compat_failure; then
    verdict true true true success success failure
    expect "backend-compat が failure なら失敗する" 1 1 \
        "::error::見分け backend_compat が当たったのに、仕事 backend-compat の結果が success ではありません(結果: failure)。"
fi

if want all_success; then
    verdict true true true success success success
    expect "3つの見分けが当たり、3つの仕事が success なら成功する" 0 0
fi

if want hit_not_success; then
    verdict true false false failure skipped skipped
    expect "見分けが当たった backend-java が failure なら失敗する" 1 1 \
        "::error::見分け backend_java が当たったのに、仕事 backend-java の結果が success ではありません(結果: failure)。"
    verdict false true false skipped cancelled skipped
    expect "見分けが当たった backend-go が cancelled なら失敗する" 1 1 \
        "::error::見分け backend_go が当たったのに、仕事 backend-go の結果が success ではありません(結果: cancelled)。"
    verdict false true false skipped "" skipped
    expect "見分けが当たった仕事の結果が空なら失敗する" 1 1 "(結果: 空)"
fi

if want not_hit; then
    verdict false false false skipped skipped skipped
    expect "どの見分けも当たらず、どの仕事も飛ばされたなら成功する" 0 0
    verdict true false false success success skipped
    expect "見分けが当たらない仕事が success でも成功する" 0 0
    verdict true false false success failure skipped
    expect "見分けが当たらないのに動いて failure になった仕事があれば失敗する" 1 1 \
        "::error::見分け backend_go が当たらないのに、仕事 backend-go が動いて success ではない結果になりました(結果: failure)。"
fi

if want all_problems; then
    verdict true true true failure skipped cancelled
    expect "問題が3つあれば、全部を調べてから 3 件と出して失敗する" 1 3 \
        "仕事 backend-java の結果が success ではありません(結果: failure)" \
        "仕事 backend-go が飛ばされました" \
        "仕事 backend-compat の結果が success ではありません(結果: cancelled)" \
        "backend-test の判定: 3 件の問題があります。"
fi

if want bad_flag; then
    verdict "" "" "" skipped skipped skipped
    expect "見分けの値が空なら終了コード 2 で失敗する" 2 3 \
        "::error::見分け backend_java の値が true でも false でもありません(値: 空)。" \
        "backend-test の判定: 見分けの値を読めないため、判定できませんでした。"
    verdict true TRUE false success success skipped
    expect "見分けの値が true と false のどちらでもなければ終了コード 2 で失敗する" 2 1 \
        "::error::見分け backend_go の値が true でも false でもありません(値: TRUE)。"
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: 場合 ${CASE} がありません"
    exit 1
fi

exit "$FAILED"
