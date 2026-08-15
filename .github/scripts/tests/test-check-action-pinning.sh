#!/usr/bin/env bash
# =====================================================================
# check-action-pinning.sh の自動テスト(guardrails CI から実行)
#
# 一時gitリポジトリにワークフローを置き、終了コードを検証する。
#   0 = 緑(通過) / 1 = 赤(SHA固定されていない参照あり)
# 併せて、Summaryへ出す報告の内容も検証する。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-action-pinning.sh"
# 一時領域の確保に失敗したまま進むと rm -rf が意図しない絶対パスを対象にするため、
# ディレクトリが実在することを確認してから trap を設定する
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
FAILED=0

SHA_A=3d3c42e5aac5ba805825da76410c181273ba90b1
SHA_B=249970729cb0ef3589644e2896645e5dc5ba9c38

seed() {
    rm -rf "$WORK/repo"
    mkdir -p "$WORK/repo/.github/workflows"
    cd "$WORK/repo" || exit 1
    git init -q .
    cat >.github/workflows/base.yaml <<EOF
name: Base
on: [pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA_A # v7.0.1
      - uses: actions/setup-node@$SHA_B # v6.5.0
EOF
}

# 失敗させるケースが本物のジョブSummaryへ追記されないよう、
# 検査対象のSummaryは捨てる(内容の検証は check_summary が行う)
# 使い方: check <期待exit> <説明> <変更を加える関数>
check() {
    local want="$1" name="$2" mutate="$3" got
    seed
    "$mutate"
    git add -A
    GITHUB_STEP_SUMMARY=/dev/null bash "$SCRIPT" >/dev/null 2>&1
    got=$?
    if [ "$got" = "$want" ]; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s (期待 exit=%s / 実際 exit=%s)\n' "$name" "$want" "$got"
        FAILED=1
    fi
}

# 使い方: check_summary <期待する文字列> <説明> <変更を加える関数>
check_summary() {
    local want="$1" name="$2" mutate="$3" summary
    seed
    "$mutate"
    git add -A
    summary="$WORK/summary.md"
    : >"$summary"
    GITHUB_STEP_SUMMARY="$summary" bash "$SCRIPT" >/dev/null 2>&1
    if grep -q "$want" "$summary"; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s (Summaryに "%s" が無い)\n' "$name" "$want"
        FAILED=1
    fi
}

add_step() { printf '      - uses: %s\n' "$1" >>.github/workflows/base.yaml; }

m_none() { :; }
m_tag() { add_step "actions/cache@v5"; }
m_major_tag_with_comment() { add_step "actions/cache@v5 # v5.1.0"; }
m_branch() { add_step "actions/cache@main"; }
m_short_sha() { add_step "actions/cache@caa2961 # v5.1.0"; }
m_no_comment() { add_step "actions/cache@caa296126883cff596d87d8935842f9db880ef25"; }
m_empty_comment() { add_step "actions/cache@caa296126883cff596d87d8935842f9db880ef25 #"; }
m_docker() { add_step "docker://alpine:3.20"; }
m_local_workflow() { add_step "./.github/workflows/base.yaml"; }
m_subdir_action() { add_step "github/codeql-action/init@caa296126883cff596d87d8935842f9db880ef25 # v3.28.0"; }
m_uppercase_sha() { add_step "actions/cache@CAA296126883CFF596D87D8935842F9DB880EF25 # v5.1.0"; }
# composite action 側にタグ参照が入る経路
m_composite_action_tag() {
    mkdir -p .github/actions/setup
    printf 'runs:\n  using: composite\n  steps:\n    - uses: actions/cache@v5\n' >.github/actions/setup/action.yml
}
# 検査対象外のファイルに書かれたタグ参照で誤検知しない
m_unrelated_file() { printf 'uses: actions/cache@v5\n' >notes.md; }
# 深い階層とインデントでも読み取れる
m_deep_indent() { printf '        - uses: actions/cache@v5\n' >>.github/workflows/base.yaml; }

check 0 "すべてSHA固定" m_none
check 1 "タグ参照" m_tag
check 1 "タグ参照(コメント付きでも不可)" m_major_tag_with_comment
check 1 "ブランチ参照" m_branch
check 1 "短縮SHA" m_short_sha
check 1 "SHA固定だがバージョンのコメントが無い" m_no_comment
check 1 "コメント記号だけで中身が無い" m_empty_comment
check 1 "docker://参照" m_docker
check 1 "composite action 内のタグ参照" m_composite_action_tag
check 1 "深いインデントのタグ参照" m_deep_indent
check 0 "ローカル参照" m_local_workflow
check 0 "サブディレクトリを持つアクション" m_subdir_action
check 0 "大文字のSHA" m_uppercase_sha
check 0 "検査対象外のファイルのタグ参照" m_unrelated_file

check_summary "actions/cache@v5" "違反した参照がSummaryに出る" m_tag
check_summary "base.yaml:9" "違反した箇所のファイルと行番号がSummaryに出る" m_tag

if [ "$FAILED" -ne 0 ]; then
    echo "::error::check-action-pinning.sh のテストが失敗しました。"
    exit 1
fi
echo "全ケース成功。"
