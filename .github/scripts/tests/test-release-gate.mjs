// release.yaml のデプロイゲートの振る舞いを固定するテスト。
//
// 検査するのは次の2つ。
//   1. main以外のrefからの起動を拒否するステップの条件が意図どおりであること
//   2. デプロイ対象コミットのCI成功を確認するスクリプトが、状態ごとに正しく落ちること
//
// 2は release.yaml に埋め込まれたJavaScriptをファイルから抽出し、
// GitHub APIをモックして実行する。実行方法: node .github/scripts/tests/test-release-gate.mjs

import { readFileSync } from 'node:fs';

const WORKFLOW_PATH = '.github/workflows/release.yaml';
const GUARD_STEP = 'Reject dispatch from non-main ref';
const VERIFY_STEP = 'Verify deploy commit passed CI on main';
const DEPLOY_SHA = 'a'.repeat(40);

const failures = [];

const check = (label, condition, detail) => {
    if (condition) {
        console.log(`  ok   ${label}`);
    } else {
        console.log(`  FAIL ${label}${detail ? ` -> ${detail}` : ''}`);
        failures.push(label);
    }
};

const workflow = readFileSync(WORKFLOW_PATH, 'utf8');
const lines = workflow.split(/\r?\n/);

// ---- 1. main以外のrefを拒否するステップ ----

const guardIndex = lines.findIndex((line) => line.includes(`- name: ${GUARD_STEP}`));
check('拒否ステップが存在する', guardIndex !== -1);

if (guardIndex !== -1) {
    const guardBlock = lines.slice(guardIndex, guardIndex + 8).join('\n');
    check(
        "拒否ステップの条件が github.ref != 'refs/heads/main' である",
        guardBlock.includes("if: github.ref != 'refs/heads/main'"),
        guardBlock.split('\n')[1],
    );
    check('拒否ステップが exit 1 で失敗する', guardBlock.includes('exit 1'));
}

// ---- 2. CI成功を確認するスクリプト ----

const extractScript = (stepName) => {
    const stepIndex = lines.findIndex((line) => line.includes(`- name: ${stepName}`));
    if (stepIndex === -1) {
        return null;
    }
    const scriptIndex = lines.findIndex((line, i) => i > stepIndex && line.trim() === 'script: |');
    if (scriptIndex === -1) {
        return null;
    }
    const indent = lines[scriptIndex].search(/\S/) + 2;
    const body = [];
    for (let i = scriptIndex + 1; i < lines.length; i += 1) {
        const line = lines[i];
        if (line.trim() !== '' && line.search(/\S/) < indent) {
            break;
        }
        body.push(line.slice(indent));
    }
    return body.join('\n');
};

const verifyScript = extractScript(VERIFY_STEP);
check('CI確認スクリプトを抽出できる', verifyScript !== null && verifyScript.includes('CI Workflow'));

const runVerify = async (runs) => {
    const result = { failed: null, infos: [] };
    const core = {
        setFailed: (message) => {
            result.failed = message;
        },
        info: (message) => result.infos.push(message),
    };
    const github = {
        paginate: async () => runs,
        rest: { actions: { listWorkflowRunsForRepo: 'listWorkflowRunsForRepo' } },
    };
    const context = { repo: { owner: 'DogisRiki', repo: 'KeirekiPro' }, sha: DEPLOY_SHA };
    const fn = new Function(
        'github',
        'context',
        'core',
        `return (async () => {\n${verifyScript}\n})();`,
    );
    await fn(github, context, core);
    return result;
};

if (verifyScript) {
    const successRun = { name: 'CI Workflow', head_branch: 'main', status: 'completed', conclusion: 'success' };

    const cases = [
        {
            label: 'mainでCIが成功していれば通過する',
            runs: [successRun],
            expectFailure: false,
        },
        {
            label: 'CIが未完了なら未完了として落ちる',
            runs: [{ name: 'CI Workflow', head_branch: 'main', status: 'in_progress', conclusion: null }],
            expectFailure: 'has not finished yet',
        },
        {
            label: 'CIが失敗していれば落ちる',
            runs: [{ name: 'CI Workflow', head_branch: 'main', status: 'completed', conclusion: 'failure' }],
            expectFailure: 'no successful main CI Workflow run',
        },
        {
            label: 'CI実行が1件も無ければ落ちる',
            runs: [],
            expectFailure: 'no successful main CI Workflow run',
        },
        {
            label: 'main以外のブランチのCI成功は採用しない',
            runs: [{ ...successRun, head_branch: 'feature/x' }],
            expectFailure: 'no successful main CI Workflow run',
        },
        {
            label: '別ワークフローの成功は採用しない',
            runs: [{ ...successRun, name: 'Guardrails' }],
            expectFailure: 'no successful main CI Workflow run',
        },
    ];

    for (const testCase of cases) {
        const result = await runVerify(testCase.runs);
        if (testCase.expectFailure === false) {
            check(testCase.label, result.failed === null, result.failed ?? '');
        } else {
            check(
                testCase.label,
                result.failed !== null && result.failed.includes(testCase.expectFailure),
                result.failed ?? '(落ちなかった)',
            );
        }
    }
}

if (failures.length > 0) {
    console.error(`\nrelease.yaml のデプロイゲート: ${failures.length} 件の検証に失敗しました。`);
    process.exit(1);
}

console.log('\nrelease.yaml のデプロイゲート: すべての検証に成功しました。');
