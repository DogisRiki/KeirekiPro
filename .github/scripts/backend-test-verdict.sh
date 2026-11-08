#!/usr/bin/env bash
# =====================================================================
# backend-test の判定(ci.yaml のまとめの仕事 backend-test から実行)
#
# 判定: 3つの見分け(backend_java、backend_go、backend_compat)と、それぞれに
#   対応する3つの仕事(backend-java、backend-go、backend-compat)の結果を、
#   環境変数で受け取る。次のどれかに当たれば、当たった仕事ごとに
#   ::error::<理由> を出し、全部を調べてから exit 1(赤)。どれにも当たらなければ
#   exit 0(緑)。
#     1. 見分けが当たったのに、仕事が飛ばされた(skipped)
#     2. 見分けが当たったのに、仕事の結果が success でない
#     3. 見分けが当たらないのに、仕事が動いて success でも skipped でもない結果になった
#   見分けの値が true と false のどちらでもないときは、全部を調べてから exit 2。
#   見分けを出す仕事 detect-changes が失敗すると見分けの値が空になり、
#   どの仕事も見分けが当たらないまま緑になってしまうためである。
#
# なぜ判定するか:
#   必須の検査は backend-test の1つだけで、Java 版の検査、Go 版の検査、Java 版と
#   Go 版を比べる検査は、それぞれ別の仕事で動く。見分けが当たった仕事が失敗するか
#   飛ばされたまま backend-test が緑になると、検査を通っていない変更が main に入る。
#   3 は、見分けが当たらない仕事は ci.yaml の if で飛ばされるはずなので、動いて
#   失敗したときは、ci.yaml の条件の誤りとして止める。
#
# 外部には問い合わせない。
# テスト: .github/scripts/tests/test-backend-test-verdict.sh
# 使い方: 次の環境変数を渡して backend-test-verdict.sh を呼ぶ
#   BACKEND_JAVA BACKEND_GO BACKEND_COMPAT: 見分けの値(true か false)
#   JAVA_RESULT GO_RESULT COMPAT_RESULT: 仕事の結果
#     (needs.<仕事>.result の値。success、failure、cancelled、skipped のどれか)
# =====================================================================
set -uo pipefail

problems=0
bad_input=0

# 使い方: judge <仕事の名前> <見分けの名前> <見分けの値> <仕事の結果>
judge() {
    local job="$1" flag_name="$2" flag="$3" result="$4"
    case "$flag" in
        true)
            case "$result" in
                success)
                    echo "${job}: 見分け ${flag_name} が当たり、仕事が通りました"
                    ;;
                skipped)
                    echo "::error::見分け ${flag_name} が当たったのに、仕事 ${job} が飛ばされました。${job} の動く条件(if)と、${job} が待つ仕事(needs)の結果を確かめてください"
                    problems=$((problems + 1))
                    ;;
                *)
                    echo "::error::見分け ${flag_name} が当たったのに、仕事 ${job} の結果が success ではありません(結果: ${result:-空})。${job} のログを確かめてください"
                    problems=$((problems + 1))
                    ;;
            esac
            ;;
        false)
            case "$result" in
                skipped | success)
                    echo "${job}: 見分け ${flag_name} が当たらないので、仕事の結果(${result})を判定に使いません"
                    ;;
                *)
                    echo "::error::見分け ${flag_name} が当たらないのに、仕事 ${job} が動いて success ではない結果になりました(結果: ${result:-空})。ci.yaml の ${job} の動く条件(if)を確かめてください"
                    problems=$((problems + 1))
                    ;;
            esac
            ;;
        *)
            echo "::error::見分け ${flag_name} の値が true でも false でもありません(値: ${flag:-空})。見分けを出す仕事 detect-changes の結果を確かめてください"
            bad_input=1
            ;;
    esac
}

judge backend-java backend_java "${BACKEND_JAVA:-}" "${JAVA_RESULT:-}"
judge backend-go backend_go "${BACKEND_GO:-}" "${GO_RESULT:-}"
judge backend-compat backend_compat "${BACKEND_COMPAT:-}" "${COMPAT_RESULT:-}"

if [ "$bad_input" = 1 ]; then
    echo "backend-test の判定: 見分けの値を読めないため、判定できませんでした。"
    exit 2
fi
if [ "$problems" -gt 0 ]; then
    echo "backend-test の判定: ${problems} 件の問題があります。"
    exit 1
fi
echo "backend-test の判定: 見分けが当たった仕事はすべて通りました。"
exit 0
