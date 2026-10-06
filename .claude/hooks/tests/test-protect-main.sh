#!/bin/bash
# =====================================================================
# protect-main.sh のテスト
#
# 実行: bash .claude/hooks/tests/test-protect-main.sh
# 一時的な git リポジトリを feature ブランチと main ブランチの2つ作り、
# フックに Bash ツールの入力(JSON)を渡して、終了コード(0 = 通す / 2 = 止める)を確かめる。
# 前提: bash・perl(JSON::PP)・git。
# =====================================================================
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/protect-main.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

git init -q "$WORK/feature" && git -C "$WORK/feature" switch -q -c fix/sample
git init -q "$WORK/main" && git -C "$WORK/main" checkout -q -B main

pass=0
fail=0

# expect <期待する終了コード> <リポジトリ(feature|main)> <コマンド>
expect() {
    local want="$1" repo="$2" cmd="$3" got
    printf '%s' "$cmd" \
        | perl -MJSON::PP -e 'local $/; my $c = <STDIN>; print JSON::PP->new->encode({tool_input => {command => $c}, cwd => $ARGV[0]})' -- "$WORK/$repo" \
        | bash "$HOOK" >/dev/null 2>&1
    got=$?
    if [ "$got" = "$want" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: 期待 %s / 実際 %s (%s): %s\n' "$want" "$got" "$repo" "$(printf '%s' "$cmd" | head -1)"
    fi
}

echo "--- 通す形(許可ルールにそのまま当たる単独のコマンド)"
expect 0 feature 'git push -u origin fix/sample'
expect 0 feature 'git push origin fix/sample'
expect 0 feature 'git commit -F C:/Users/x/AppData/Local/Temp/msg.txt'
expect 0 feature 'git commit -F "C:/Users/x/my msg.txt"'
expect 0 feature "git commit -F 'msg.txt'"
expect 0 feature '  git push -u origin fix/sample  '
expect 0 feature 'git commit -F .git/MERGE_MSG'

echo "--- 止める形(2026-09-28・29 に判定へ回った書き方)"
expect 2 feature 'git push -q -u origin fix/sample'
expect 2 feature 'git push -u origin fix/sample 2>&1 | tail -2'
expect 2 feature 'git add a b && git commit -q -F - <<'"'"'EOF'"'"'
chore: x
EOF
git push -q -u origin fix/sample 2>&1 | grep -v "^remote:" | tail -2'

echo "--- 止める形(形のずれ)"
expect 2 feature 'cd /c/repo && git push -u origin fix/sample'
expect 2 feature "git commit -F - <<'EOF'
chore: x
EOF"
expect 2 feature 'git commit -q -F msg.txt'
expect 2 feature 'git commit -m "x"'
expect 2 feature 'git commit --amend --no-edit'
expect 2 feature 'git add a b && git commit -F msg.txt'
expect 2 feature 'git commit -F msg.txt && git log --oneline -1'
expect 2 feature 'git commit -F msg.txt; git push -u origin fix/sample'
expect 2 feature 'git -C /c/repo push -u origin fix/sample'
expect 2 feature 'GIT_EDITOR=true git commit -F msg.txt'
expect 2 feature 'git push origin --delete tmp/probe'
expect 2 feature 'git  push -u origin fix/sample'
expect 2 feature 'git push -u origin fix/sample # comment'
expect 2 feature "git push -u origin \"\$(git branch --show-current)\""
expect 2 feature 'git push'
expect 2 feature 'git push -u origin fix/sample:main'

echo "--- 止める形(前置きや制御構文の中に書いた push)"
expect 2 feature "for f in a b; do git push -u origin \$f; done"
expect 2 feature 'if git push -u origin fix/sample; then echo ok; fi'
expect 2 feature 'command git push -q -u origin fix/sample'
expect 2 feature 'env GIT_TRACE=1 git push -q -u origin fix/sample'
expect 2 feature 'time git push -q -u origin fix/sample'
expect 2 feature 'true && { git push -q -u origin fix/sample; }'
expect 2 feature 'bash -c "git push -q -u origin fix/sample"'
expect 2 feature "sh -c 'git commit -m x'"

echo "--- 止める形(既存の保護: main・強制push)"
expect 2 main 'git push -u origin fix/sample'
expect 2 main 'git commit -F msg.txt'
expect 2 feature 'git push -u origin main'
expect 2 feature 'git push -u origin fix/sample --force'
expect 2 feature 'git push --force-with-lease origin fix/sample'

echo "--- 巻き込まない形(commit / push を実行しないコマンド)"
expect 0 feature 'git stash push -m x'
expect 0 feature 'git log --oneline -3 | grep -v "git push"'
expect 0 feature 'grep -rn "git push" .claude/skills/'
expect 0 feature 'echo "git commit -F x"'
expect 0 feature 'git fetch origin && git merge origin/main'
expect 0 feature 'gh pr create --title x --body "git push"'
expect 0 feature 'git status --short && git log --oneline -1'
expect 0 feature 'git switch -c fix/other'
expect 0 feature 'git add a b'
expect 0 feature 'git diff --stat'
expect 0 feature 'printf "%s\n" "git push -u origin x" > notes.txt'
expect 0 main 'git status'

echo "--- 止めたときの案内"
msg=$(printf '%s' 'git push -q -u origin fix/sample' \
    | perl -MJSON::PP -e 'local $/; my $c = <STDIN>; print JSON::PP->new->encode({tool_input => {command => $c}, cwd => $ARGV[0]})' -- "$WORK/feature" \
    | bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$msg" | grep -q 'git push -u origin <ブランチ名>'; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL: 止めたときに正しい形が案内されない: $msg"
fi

echo
echo "成功 ${pass} 件 / 失敗 ${fail} 件"
[ "$fail" -eq 0 ]
