// release.yaml のデプロイゲートの振る舞いを固定するテスト。
// ステップの属性(条件・無効化フラグ)を検査し、CI成功確認のスクリプトを抽出して
// GitHub APIをモックして実行する。APIに渡すクエリも検証する。
// 実行方法: node .github/scripts/tests/test-release-gate.mjs

import { readFileSync } from 'node:fs';

const GUARD_STEP = 'Reject dispatch from non-main ref';
const VERIFY_STEP = 'Verify deploy commit passed CI on main';
const DEPLOY_SHA = 'a'.repeat(40);
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

// ステップ名から、そのステップの行だけを取り出す(次のステップの直前まで)
const stepBlock = (stepName) => {
    const start = lines.findIndex((line) => line.includes(`- name: ${stepName}`));
    if (start === -1) return null;
    const indent = lines[start].search(/\S/);
    const body = [lines[start]];
    for (let i = start + 1; i < lines.length; i += 1) {
        const line = lines[i];
        if (line.trim() !== '' && line.search(/\S/) <= indent) break;
        body.push(line);
    }
    return body;
};

// 1. main以外のrefを拒否するステップ
const guard = stepBlock(GUARD_STEP);
check('拒否ステップが存在する', guard !== null);
if (guard) {
    const block = guard.join('\n');
    check("拒否条件が github.ref != 'refs/heads/main'", block.includes("if: github.ref != 'refs/heads/main'"), guard[1]);
    check('拒否ステップが exit 1 で失敗する', block.includes('exit 1'));
    check('拒否ステップが continue-on-error で無効化されていない', !block.includes('continue-on-error'));
}

// 2. CI成功を確認するステップ
const verify = stepBlock(VERIFY_STEP);
check('CI確認ステップが存在する', verify !== null);
if (verify) {
    const block = verify.join('\n');
    check('CI確認ステップが continue-on-error で無効化されていない', !block.includes('continue-on-error'));
    check('CI確認ステップが if で無効化されていない', !/^\s+if:/m.test(block));
}

// 3. CI成功を確認するスクリプト(YAMLのブロックスカラーから本文を取り出す)
const extractScript = () => {
    if (!verify) return null;
    const scriptIndex = verify.findIndex((line) => line.trim() === 'script: |');
    if (scriptIndex === -1) return null;
    const indent = verify[scriptIndex].search(/\S/) + 2;
    return verify.slice(scriptIndex + 1).map((line) => line.slice(indent)).join('\n');
};

const script = extractScript();
check('CI確認スクリプトを抽出できる', script !== null && script.includes('CI Workflow'));

const runVerify = async (runs) => {
    let failed = null;
    let query = null;
    const core = { setFailed: (message) => { failed = message; }, info: () => { } };
    const github = {
        paginate: async (_route, params) => { query = params; return runs; },
        rest: { actions: { listWorkflowRunsForRepo: 'listWorkflowRunsForRepo' } },
    };
    const context = { repo: { owner: 'DogisRiki', repo: 'KeirekiPro' }, sha: DEPLOY_SHA };
    const fn = new Function('github', 'context', 'core', `return (async () => {\n${script}\n})();`);
    await fn(github, context, core);
    return { failed, query };
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
        const { failed } = await runVerify(runs);
        if (expected === false) {
            check(label, failed === null, failed ?? '');
        } else {
            check(label, failed !== null && failed.includes(expected), failed ?? '(落ちなかった)');
        }
    }

    // APIに渡すクエリの検証。head_sha を外すとmainの全成功runを見てしまい、
    // 未検証コミットでもゲートが通過する
    const { query } = await runVerify([ok]);
    check('デプロイ対象SHAでCI実行を絞り込んでいる', query?.head_sha === DEPLOY_SHA, JSON.stringify(query));
    check('pushイベントのCI実行に絞り込んでいる', query?.event === 'push', JSON.stringify(query));
}

if (failures.length > 0) {
    console.error(`\nrelease.yaml のデプロイゲート: ${failures.length} 件の検証に失敗しました。`);
    process.exit(1);
}
console.log('\nrelease.yaml のデプロイゲート: すべての検証に成功しました。');
