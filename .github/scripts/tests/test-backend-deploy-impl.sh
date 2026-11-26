#!/usr/bin/env bash
# =====================================================================
# backend-deploy-impl.sh の自動テスト(guardrails CI の escape-hatch から実行)
#
# 出荷の入力と今のタスク定義のイメージを環境変数で渡して版の決め方を流し、
# 終了コードと、GITHUB_OUTPUT のファイルに書いた値と、::error の行を確かめる。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

# CI のジョブにいつも入っている GITHUB_OUTPUT を、場合ごとに作るファイルに替えるため、
# 先に消しておく。
unset GITHUB_OUTPUT

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/backend-deploy-impl.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
OUT=""
RC=0
OUTPUTS=""

SHA="0123456789abcdef0123456789abcdef01234567"
REPO="123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/keirekipro-backend"

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

# 使い方: decide <出荷の入力> <今のタスク定義のイメージ> <コミットの SHA>
decide() {
    local file="$WORK/output-$RAN"
    : >"$file"
    OUT=$(BACKEND_IMPL="$1" CURRENT_IMAGE="$2" GIT_SHA="$3" GITHUB_OUTPUT="$file" \
        bash "$SCRIPT" 2>&1)
    RC=$?
    OUTPUTS=$(cat "$file")
}

# 使い方: expect_ok <場合の説明> <版> <Dockerfile> <イメージのタグ>
expect_ok() {
    local name="$1" want
    want=$(printf 'impl=%s\ndockerfile=%s\ncontext=./backend\nimage_tag=%s' "$2" "$3" "$4")
    if [ "$RC" != 0 ]; then
        fail "$name" "終了コード: 期待 0 / 実際 $RC。出力: $OUT"
        return
    fi
    if [ "$OUTPUTS" != "$want" ]; then
        fail "$name" "GITHUB_OUTPUT の中身: 期待 [$want] / 実際 [$OUTPUTS]"
        return
    fi
    case "$OUT" in
        *"出荷する版: $2"*) ;;
        *)
            fail "$name" "出力に「出荷する版: $2」がありません。出力: $OUT"
            return
            ;;
    esac
    pass "$name"
}

# 使い方: expect_error <場合の説明> <出力に含まれるはずの文字列>
expect_error() {
    local name="$1" s="$2"
    if [ "$RC" != 2 ]; then
        fail "$name" "終了コード: 期待 2 / 実際 $RC。出力: $OUT"
        return
    fi
    if [ -n "$OUTPUTS" ]; then
        fail "$name" "失敗したのに GITHUB_OUTPUT に値を書きました: [$OUTPUTS]"
        return
    fi
    case "$OUT" in
        *"::error::$s"*) ;;
        *)
            fail "$name" "出力に「::error::$s」がありません。出力: $OUT"
            return
            ;;
    esac
    pass "$name"
}

JAVA_DOCKERFILE=./docker/backend/Dockerfile.prod
GO_DOCKERFILE=./docker/backend-go/Dockerfile.prod

if want go_selected; then
    decide go "$REPO:abcdef0" "$SHA"
    expect_ok "go を選ぶと Go 版の Dockerfile と go- のタグ" go "$GO_DOCKERFILE" "go-$SHA"
fi

if want java_selected; then
    decide java "$REPO:go-abcdef0" "$SHA"
    expect_ok "java を選ぶと Java 版の Dockerfile と SHA のタグ" java "$JAVA_DOCKERFILE" "$SHA"
fi

if want current_sha_tag; then
    decide current "$REPO:abcdef0123456789abcdef0123456789abcdef01" "$SHA"
    expect_ok "current で今のタグが SHA なら Java 版" java "$JAVA_DOCKERFILE" "$SHA"
fi

if want current_go_tag; then
    decide current "$REPO:go-abcdef0123456789abcdef0123456789abcdef01" "$SHA"
    expect_ok "current で今のタグが go- なら Go 版" go "$GO_DOCKERFILE" "go-$SHA"
fi

if want current_tag_only; then
    decide current "go-abcdef0" "$SHA"
    expect_ok "current でリポジトリの無いタグだけを渡しても go- なら Go 版" go "$GO_DOCKERFILE" "go-$SHA"
fi

if want current_go_in_repo_name; then
    decide current "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/go-backend:abcdef0" "$SHA"
    expect_ok "current でリポジトリの名前が go- で始まってもタグが SHA なら Java 版" java "$JAVA_DOCKERFILE" "$SHA"
fi

if want current_no_tag; then
    decide current "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/go-backend" "$SHA"
    expect_ok "current でイメージにタグが無ければ、リポジトリの名前が go- で始まっても Java 版" java "$JAVA_DOCKERFILE" "$SHA"
fi

if want go_ignores_current; then
    decide go "" "$SHA"
    expect_ok "go を選べば今のタスク定義のイメージが空でも Go 版" go "$GO_DOCKERFILE" "go-$SHA"
fi

if want unknown_impl; then
    decide golang "$REPO:abcdef0" "$SHA"
    expect_error "出荷の入力が current java go のどれでもなければ失敗する" "出荷の入力 backend_impl の値が current java go のどれでもありません(値: golang)"
fi

if want empty_impl; then
    decide "" "$REPO:abcdef0" "$SHA"
    expect_error "出荷の入力が空なら失敗する" "出荷の入力 backend_impl の値が current java go のどれでもありません(値: 空)"
fi

if want current_empty_image; then
    decide current "" "$SHA"
    expect_error "current で今のタスク定義のイメージが空なら失敗する" "今のタスク定義のイメージを読めないため、current の版を決められません"
fi

if want empty_sha; then
    decide go "$REPO:abcdef0" ""
    expect_error "コミットの SHA が空なら失敗する" "コミットの SHA が16進数の40文字ではありません(値: 空)"
fi

if want bad_sha; then
    decide java "$REPO:abcdef0" "main"
    expect_error "コミットの SHA が16進数の40文字でなければ失敗する" "コミットの SHA が16進数の40文字ではありません(値: main)"
fi

if want output_not_writable; then
    OUT=$(BACKEND_IMPL=go CURRENT_IMAGE="" GIT_SHA="$SHA" GITHUB_OUTPUT="$WORK/no-such-dir/output" \
        bash "$SCRIPT" 2>&1)
    RC=$?
    OUTPUTS=""
    expect_error "GITHUB_OUTPUT のファイルに書けなければ失敗する" "決めた版を GITHUB_OUTPUT のファイルに書けませんでした"
fi

if [ "$RAN" = 0 ]; then
    echo "FAIL: KP_TEST_CASE=$CASE に当たる場合がありません"
    exit 1
fi
if [ "$FAILED" != 0 ]; then
    echo "test-backend-deploy-impl.sh: 失敗した場合があります"
    exit 1
fi
echo "test-backend-deploy-impl.sh: すべての場合が通りました($RAN 件)"
exit 0
