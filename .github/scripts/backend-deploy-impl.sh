#!/usr/bin/env bash
# =====================================================================
# 出荷する backend の版を決める(backend-deploy.yaml の最初のステップから実行)
#
# 判定: 出荷の入力 backend_impl(current、java、go のどれか)と、今のタスク定義の
#   イメージを環境変数で受け取り、出荷する版を決める。
#     - java: Java 版
#     - go: Go 版
#     - current: 今のタスク定義のイメージのタグが go- で始まれば Go 版、
#       そうでなければ Java 版(今と同じ版をもう一度出荷する)
#   決めた版に合わせて、次の4つを GITHUB_OUTPUT のファイルに書き、exit 0。
#     impl: java か go
#     dockerfile: Java 版は ./docker/backend/Dockerfile.prod、
#       Go 版は ./docker/backend-go/Dockerfile.prod
#     context: どちらの版も ./backend
#     image_tag: Java 版はコミットの SHA、Go 版は go-<コミットの SHA>
#   入力の値を読めないときは、::error::<理由> を出し、GITHUB_OUTPUT に何も書かずに
#   exit 2。出荷はこのステップで止まり、本番は今の版のまま動き続ける。
#
# なぜ決めるか:
#   所有者が release.yaml を1回起動するだけで、Java 版から Go 版への切り替えと、
#   Go 版から Java 版への戻しができるようにするためである。入力の既定は current なので、
#   版を選ばずに出荷しても、本番で動いている版は替わらない。
#   Go 版のタグに go- を付けるのは、current のときに今の版をタグから見分けるためである。
#
# 外部には問い合わせない。今のタスク定義は、呼び出し側が
# aws ecs describe-task-definition で読んで渡す。
# テスト: .github/scripts/tests/test-backend-deploy-impl.sh
# 使い方: 次の環境変数を渡して backend-deploy-impl.sh を呼ぶ
#   BACKEND_IMPL: 出荷の入力(current、java、go のどれか)
#   CURRENT_IMAGE: 今のタスク定義の backend のコンテナのイメージ
#     (<リポジトリ>:<タグ> の形。タグだけでもよい。java と go のときは空でもよい)
#   GIT_SHA: 出荷するコミットの SHA(16進数の40文字)
#   GITHUB_OUTPUT: 値を書くファイル(GitHub Actions が入れる。無ければ標準出力に書く)
# =====================================================================
set -uo pipefail

impl_input="${BACKEND_IMPL:-}"
current_image="${CURRENT_IMAGE:-}"
sha="${GIT_SHA:-}"
output="${GITHUB_OUTPUT:-/dev/stdout}"

case "$impl_input" in
    current | java | go) ;;
    *)
        echo "::error::出荷の入力 backend_impl の値が current java go のどれでもありません(値: ${impl_input:-空})。release.yaml の入力の選択肢を確かめてください"
        exit 2
        ;;
esac

if ! printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$'; then
    echo "::error::コミットの SHA が16進数の40文字ではありません(値: ${sha:-空})。backend-deploy.yaml が渡す github.sha を確かめてください"
    exit 2
fi

impl="$impl_input"
if [ "$impl_input" = current ]; then
    if [ -z "$current_image" ]; then
        echo "::error::今のタスク定義のイメージを読めないため、current の版を決められません。backend-deploy.yaml の aws ecs describe-task-definition の結果を確かめてください"
        exit 2
    fi
    # タグは、最後の / より後ろの、: より後ろの文字列である。
    # リポジトリの名前やレジストリの場所に go- や : があっても、タグとして読まない。
    # / も : も無いときは、渡された値をタグとして読む。
    last_segment="${current_image##*/}"
    case "$current_image" in
        */*)
            case "$last_segment" in
                *:*) current_tag="${last_segment#*:}" ;;
                *) current_tag="" ;;
            esac
            ;;
        *:*) current_tag="${current_image#*:}" ;;
        *) current_tag="$current_image" ;;
    esac
    case "$current_tag" in
        go-*) impl=go ;;
        *) impl=java ;;
    esac
    echo "今のタスク定義のイメージのタグ: ${current_tag:-無し}"
fi

if [ "$impl" = go ]; then
    dockerfile=./docker/backend-go/Dockerfile.prod
    image_tag="go-${sha}"
else
    dockerfile=./docker/backend/Dockerfile.prod
    image_tag="$sha"
fi

{
    echo "impl=${impl}"
    echo "dockerfile=${dockerfile}"
    echo "context=./backend"
    echo "image_tag=${image_tag}"
} >>"$output" || {
    echo "::error::決めた版を GITHUB_OUTPUT のファイルに書けませんでした(ファイル: ${output})。GitHub Actions のランナーの状態を確かめてください"
    exit 2
}

echo "出荷する版: ${impl}(入力: ${impl_input}、Dockerfile: ${dockerfile}、イメージのタグ: ${image_tag})"
exit 0
