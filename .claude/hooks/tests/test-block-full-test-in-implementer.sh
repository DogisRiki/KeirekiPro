#!/bin/bash
# =====================================================================
# block-full-test-in-implementer.sh のテスト
#
# 実行: bash .claude/hooks/tests/test-block-full-test-in-implementer.sh
# フックに Bash ツールの入力(JSON)を渡して、終了コード(0 = 通す / 2 = 止める)を確かめる。
# 止めたときは、止めた理由が標準エラーに出ることも確かめる。
# 前提: bash・perl(JSON::PP・Text::ParseWords)。
# =====================================================================
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/block-full-test-in-implementer.sh"

pass=0
fail=0

# expect <期待する終了コード> <agent_type(空なら欄を付けない)> <コマンド>
expect() {
    local want="$1" agent="$2" cmd="$3" got err
    err=$(printf '%s' "$cmd" \
        | perl -MJSON::PP -e '
            local $/; my $c = <STDIN>;
            my %d = (hook_event_name => "PreToolUse", tool_name => "Bash", tool_input => {command => $c});
            $d{agent_type} = $ARGV[0] if length $ARGV[0];
            print JSON::PP->new->encode(\%d)' -- "$agent" \
        | bash "$HOOK" 2>&1 >/dev/null)
    got=$?
    if [ "$got" != "$want" ]; then
        fail=$((fail + 1))
        printf 'FAIL: 期待 %s / 実際 %s (%s): %s\n' "$want" "$got" "${agent:-なし}" "$(printf '%s' "$cmd" | head -1)"
        return
    fi
    if [ "$want" = 2 ]; then
        case "$err" in
            *'テストを全部流すコマンドを打てません'*'関係するテストだけを流してください'*) ;;
            *)
                fail=$((fail + 1))
                printf 'FAIL: 止めた理由が標準エラーに無い: %s\n' "$cmd"
                return
                ;;
        esac
    fi
    pass=$((pass + 1))
}

I=kiro-implementer

echo "--- 止める形(品質チェックのコマンド)"
expect 2 $I 'bash .claude/scripts/parallel/run-check.sh backend ./gradlew check'
expect 2 $I 'bash .claude/scripts/parallel/run-check.sh frontend pnpm test'
expect 2 $I 'bash .claude/scripts/parallel/run-check.sh frontend pnpm run coverage'

echo "--- 止める形(backend)"
expect 2 $I './gradlew test'
expect 2 $I './gradlew build'
expect 2 $I './gradlew :test'
expect 2 $I './gradlew --no-daemon -p backend check'
expect 2 $I './gradlew clean test --info'
expect 2 $I './gradlew jacocoTestReport'
expect 2 $I './gradlew jacocoTestCoverageVerification'
expect 2 $I './gradlew pitest'
expect 2 $I './gradlew test --tests FooTest check'
expect 2 $I 'gradlew.bat test'
expect 2 $I 'cd backend && ./gradlew test'
expect 2 $I 'docker compose exec -w /home/spring/app backend ./gradlew check'

echo "--- 止める形(frontend)"
expect 2 $I 'pnpm test'
expect 2 $I 'pnpm run test'
expect 2 $I 'pnpm test --run'
expect 2 $I 'pnpm test -- --reporter verbose'
expect 2 $I 'pnpm test -t "保存できる"'
expect 2 $I 'pnpm coverage'
expect 2 $I 'pnpm test src/a.test.ts --coverage'
expect 2 $I 'pnpm vitest run'
expect 2 $I 'pnpm exec vitest'
expect 2 $I 'pnpm --dir frontend test'
expect 2 $I 'pnpm -C frontend run test'
expect 2 $I 'npm test'
expect 2 $I 'npm run coverage'
expect 2 $I 'npx vitest run'
expect 2 $I 'npx stryker run'
expect 2 $I 'pnpm stryker run'
expect 2 $I 'node_modules/.bin/vitest run'
expect 2 $I 'yarn test'

echo "--- 止める形(つないだコマンドと sh -c の中)"
expect 2 $I 'pnpm run lint && pnpm test'
expect 2 $I 'pnpm run lint; pnpm test'
expect 2 $I 'pnpm run lint;pnpm test'
expect 2 $I 'pnpm test 2>&1 | tail -20'
expect 2 $I 'pnpm test > out.txt 2>&1'
expect 2 $I './gradlew test >out.txt'
expect 2 $I "bash -lc 'pnpm test'"
expect 2 $I 'pnpm run lint || pnpm test'
expect 2 $I 'pnpm test &'
expect 2 $I 'pnpm test src/a.test.ts | tail; ./gradlew check'
expect 2 $I "sh -c 'cd frontend && pnpm test'"
expect 2 $I 'bash -c "./gradlew check"'
expect 2 $I 'bash .claude/scripts/parallel/run-check.sh backend sh -c "./gradlew test --info"'
expect 2 $I 'pnpm run typecheck
pnpm test'

echo "--- 通す形(足したテストと関係するテストだけ)"
expect 0 $I 'bash .claude/scripts/parallel/run-check.sh backend ./gradlew test --tests com.example.keirekipro.unit.FooTest'
expect 0 $I "./gradlew test --tests 'com.example.keirekipro.unit.*'"
expect 0 $I './gradlew test --tests=FooTest'
expect 0 $I './gradlew :test --tests FooTest --info'
expect 0 $I 'bash .claude/scripts/parallel/run-check.sh frontend pnpm test src/features/a/Foo.test.tsx'
expect 0 $I 'pnpm test -- src/features/a'
expect 0 $I 'pnpm test src/a.test.ts -t "保存できる"'
expect 0 $I 'pnpm vitest run src/a.test.ts'
expect 0 $I 'npx vitest related src/a.ts'
expect 0 $I 'pnpm test --reporter verbose src/a.test.ts'

echo "--- 通す形(テストを流さないコマンド)"
expect 0 $I 'bash .claude/scripts/parallel/run-check.sh backend ./gradlew spotlessApply'
expect 0 $I './gradlew compileJava compileTestJava'
expect 0 $I 'bash .claude/scripts/parallel/run-check.sh frontend pnpm run lint'
expect 0 $I 'bash .claude/scripts/parallel/run-check.sh frontend pnpm run typecheck'
expect 0 $I 'bash .claude/scripts/parallel/run-check.sh frontend pnpm run format'
expect 0 $I 'pnpm install'
expect 0 $I 'git diff'
expect 0 $I 'grep -rn "pnpm test" .claude'
expect 0 $I "echo './gradlew check は親が流す'"
expect 0 $I 'pnpm test -t "保存 できる" src/a.test.ts'
expect 0 $I 'bash .claude/scripts/parallel/tests/test-session.sh'
expect 0 $I 'bash .claude/hooks/tests/test-protect-main.sh'

echo "--- 通す形(実装役でないとき)"
expect 0 '' './gradlew check'
expect 0 '' 'bash .claude/scripts/parallel/run-check.sh frontend pnpm test'
expect 0 general-purpose './gradlew check'
expect 0 general-purpose 'pnpm run coverage'
expect 0 Explore 'pnpm test'
expect 0 spec-reviewer './gradlew test'

echo "--- 通す形(入力が読めないとき)"
got=$(printf 'not json' | bash "$HOOK" >/dev/null 2>&1; echo $?)
if [ "$got" = 0 ]; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    printf 'FAIL: JSON でない入力で 期待 0 / 実際 %s\n' "$got"
fi
got=$(printf '{"agent_type":"kiro-implementer","tool_input":{}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)
if [ "$got" = 0 ]; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    printf 'FAIL: command の無い入力で 期待 0 / 実際 %s\n' "$got"
fi

echo
echo "結果: ${pass} 件成功 / ${fail} 件失敗"
[ "$fail" -eq 0 ]
