// release.yaml のデプロイゲートの振る舞いを固定するテスト。
// 拒否ステップの条件を検査し、CI成功確認のスクリプトを抽出してGitHub APIをモックして実行する。
// 実行方法: node .github/scripts/tests/test-release-gate.mjs

import { readFileSync } from 'node:fs';

const GUARD_STEP = 'Reject dispatch from non-main ref';
const VERIFY_STEP = 'Verify deploy commit passed CI on main';
const lines = readFileSync('.github/workflows/release.yaml', 'utf8').split(/\r?\n/);
const failures = [];

const check = (label, condition, detail) => {
    if (condition) {
        console.log(`  ok   ${label}`);
        return;
    }
    console.log(`  FAIL ${label}${detail ? ` -> ${detail}` : ''}`);
    failures.push(label);
};

// 1. main以外のrefを拒否するステップ
const guardIndex = lines.findIndex((line) => line.includes(`- name: ${GUARD_STEP}`));
check('拒否ステップが存在する', guardIndex !== -1);
if (guardIndex !== -1) {
    const block = lines.slice(guardIndex, guardIndex + 8).join('\n');
    check("拒否条件が github.ref != 'refs/heads/main'", block.includes("if: github.ref != 'refs/heads/main'"), block.split('\n')[1]);
    check('拒否ステップが exit 1 で失敗する', block.includes('exit 1'));
}

// 2. CI成功を確認するスクリプト(YAMLのブロックスカラーから本文を取り出す)
const extractScript = (stepName) => {
    const stepIndex = lines.findIndex((line) => line.includes(`- name: ${stepName}`));
    if (stepIndex === -1) return null;
    const scriptIndex = lines.findIndex((line, i) => i > stepIndex && line.trim() === 'script: |');
    if (scriptIndex === -1) return null;
    const indent = lines[scriptIndex].search(/\S/) + 2;
    const body = [];
    for (let i = scriptIndex + 1; i < lines.length; i += 1) {
        if (lines[i].trim() !== '' && lines[i].search(/\S/) < indent) break;
        body.push(lines[i].slice(indent));
    }
    return body.join('\n');
};

const script = extractScript(VERIFY_STEP);
check('CI確認スクリプトを抽出できる', script !== null && script.includes('CI Workflow'));

const runVerify = async (runs) => {
    let failed = null;
    const core = { setFailed: (message) => { failed = message; }, info: () => { } };
    const github = { paginate: async () => runs, rest: { actions: { listWorkflowRunsForRepo: 'x' } } };
    const context = { repo: { owner: 'DogisRiki', repo: 'KeirekiPro' }, sha: 'a'.repeat(40) };
    const fn = new Function('github', 'context', 'core', `return (async () => {\n${script}\n})();`);
    await fn(github, context, core);
    return failed;
};

if (script) {
    const ok = { name: 'CI Workflow', head_branch: 'main', status: 'completed', conclusion: 'success' };
    const noSuccess = 'no successful main CI Workflow run';
    const cases = [
        ['mainでCIが成功していれば通過する', [ok], false],
        ['CIが未完了なら未完了として落ちる', [{ ...ok, status: 'in_progress', conclusion: null }], 'has not finished yet'],
        ['CIが失敗していれば落ちる', [{ ...ok, conclusion: 'failure' }], noSuccess],
        ['CI実行が1件も無ければ落ちる', [], noSuccess],
        ['main以外のブランチのCI成功は採用しない', [{ ...ok, head_branch: 'feature/x' }], noSuccess],
        ['別ワークフローの成功は採用しない', [{ ...ok, name: 'Guardrails' }], noSuccess],
    ];
    for (const [label, runs, expected] of cases) {
        const failed = await runVerify(runs);
        if (expected === false) {
            check(label, failed === null, failed ?? '');
        } else {
            check(label, failed !== null && failed.includes(expected), failed ?? '(落ちなかった)');
        }
    }
}

if (failures.length > 0) {
    console.error(`\nrelease.yaml のデプロイゲート: ${failures.length} 件の検証に失敗しました。`);
    process.exit(1);
}
console.log('\nrelease.yaml のデプロイゲート: すべての検証に成功しました。');
