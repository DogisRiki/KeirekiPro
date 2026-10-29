---
name: kiro-impl
description: Implement approved tasks using TDD in the main context, with an independent reviewer subagent per task. Runs all pending tasks autonomously or selected tasks manually.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, MultiEdit, Bash, Glob, Grep, Agent, WebSearch, WebFetch
argument-hint: <feature-name> [task-numbers]
---

# kiro-impl Skill

## Role
You operate in two modes:
- **Autonomous mode** (no task numbers): Implement each task yourself in the main context, then dispatch a fresh reviewer subagent for independent review after each
- **Manual mode** (task numbers provided): Execute selected tasks directly in the main context

## Core Mission
- **Success Criteria**:
  - All tests written before implementation code
  - Code passes all tests with no regressions
  - Tasks marked as completed in tasks.md
  - Implementation aligns with design and requirements
  - Independent reviewer approves each task before completion

## Execution Steps

### Step 1: Gather Context

If steering/spec context is already available from conversation, skip redundant file reads.
Otherwise, load all necessary context:
- `.kiro/specs/{feature}/spec.json`, `requirements.md`, `design.md`, `tasks.md`
- Core steering context: `product.md`, `tech.md`, `structure.md`
- Additional steering files only when directly relevant to the selected task's boundary, runtime prerequisites, integrations, domain rules, security/performance constraints, or team conventions that affect implementation or validation
- Relevant local agent skills or playbooks only when they clearly match the task's host environment or use case; read the specific artifact(s) you need, not entire directories

#### Parallel Research

The following research areas are independent and can be executed in parallel:
1. **Spec context loading**: spec.json, requirements.md, design.md, tasks.md
2. **Steering, playbooks, & patterns**: Core steering, task-relevant extra steering, matching local agent skills/playbooks, and existing code patterns

After all parallel research completes, synthesize implementation brief before starting.

#### Preflight

**Validate approvals**:
- Verify tasks are approved in spec.json (stop if not, see Safety & Fallback)

**Discover validation commands**:
- Inspect repository-local sources of truth in this order: project scripts/manifests (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, app manifests), task runners (`Makefile`, `justfile`), CI/workflow files, existing e2e/integration configs, then `README*`
- Derive a canonical validation set for this repo: `TEST_COMMANDS`, `BUILD_COMMANDS`, and `SMOKE_COMMANDS`
- Prefer commands already used by repo automation over ad hoc shell pipelines
- For `SMOKE_COMMANDS`, choose the lightest trustworthy runtime-liveness check for the app shape (for example: root URL load, Electron launch, CLI `--help`, service health endpoint, mobile simulator/e2e harness if one already exists)
- Keep the full command set in the main context, and pass only the task-relevant subset to reviewer subagents
- While implementing a task, run only commands that run specific tests (e.g. `bash .claude/scripts/parallel/run-check.sh backend ./gradlew test --tests <class>`, `bash .claude/scripts/parallel/run-check.sh frontend pnpm test <test file>`), not the full-suite or quality-gate commands (`./gradlew check`, `./gradlew test` without `--tests`, `pnpm test` without test files, `pnpm run coverage`). The reviewer runs the quality gates once per major task (`1.`, `2.`), in the review of its last sub-task (see Step 3 c)

**Establish repo baseline**:
- Run `git status --porcelain` and note any pre-existing uncommitted changes

### Step 2: Select Tasks & Determine Mode

**Parse arguments**:
- Extract feature name from first argument
- If task numbers provided (e.g., "1.1" or "1,2,3"): **manual mode**
- If no task numbers: **autonomous mode** (all pending tasks)

**Build task queue**:
- spec の見出しと目印は、`.kiro/settings/rules/spec-writing.md` の「見出しと目印の一覧」の名前で読む。タスクの箱(`- [ ]` `- [x]` `- [ ]*`)とタスク番号(`1.` `1.1`)は、この形で読む
- Read tasks.md, identify actionable sub-tasks (X.Y numbering like 1.1, 2.3)
- Major tasks (1., 2.) are grouping headers, not execution units
- Skip tasks with `_保留:_` annotation
- For each selected task, check `_依存:_` annotations -- verify referenced tasks are `[x]`
- If prerequisites incomplete, execute them first or warn the user
- Use `_対象の部品:_` annotations to understand the task's component scope

### Step 3: Execute Implementation

#### Autonomous Mode (implement in the main context, review by subagent)

**Iteration discipline**: Process exactly ONE sub-task (e.g., 1.1) per iteration. Do NOT batch multiple sub-tasks into a single implementation or review. Each iteration follows the full cycle: implement → review → commit → re-read tasks.md → next.

**Context management**: At the start of each iteration, re-read `tasks.md` to determine the next actionable sub-task. Do NOT rely on accumulated memory of previous iterations. After completing each iteration, retain only a one-line summary (e.g., "1.1: APPROVED, 3 files changed") and discard the full status report and reviewer details.

**Reading limits**: Do NOT read large files whole, in this conversation or in the reviewer's. This applies to requirements.md, design.md, tasks.md, and the code and scripts this feature changes. Find the place with `grep -n`, then read only the lines the current task needs. For the per-iteration re-read of `tasks.md`, read the task checkboxes with `grep -n` and then only the current task's lines and the `## 実装のメモ` section. For requirements.md and design.md, read only the sections the current task references. Re-reading the same whole file every iteration fills the context and causes repeated automatic summaries, which makes every later response cost more.

For each task (one at a time):

**a) Implement the task yourself**:
- Do NOT dispatch an implementer subagent. The owner decided that the conversation's Claude implements each task, because an implementer subagent adds cost and time; only the review goes to a separate subagent
- Read `templates/implementation-protocol.md` from this skill's directory and follow it for this task, using this task-specific context:
  - Task description and boundary scope
  - Paths to spec files: requirements.md, design.md, tasks.md
  - Exact requirement and design section numbers this task must satisfy (using source numbering, NOT invented `REQ-*` aliases)
  - Task-relevant steering context and the validation commands from the Preflight (tests/build/smoke as relevant)
  - Whether the task is behavioral (Feature Flag Protocol) or non-behavioral
  - **Previous learnings**: Use any `## 実装のメモ` entries from tasks.md that are relevant to this task's boundary or dependencies (e.g., "better-sqlite3 requires separate rebuild for Electron"). This prevents the same mistakes from recurring.
- Build the Task Brief (acceptance criteria, completion definition, design constraints, verification method) from the spec files before writing code, and end with the Status Report block defined in the protocol

**b) Handle your status**:
- Decide the next step only from the `- STATUS:` field of your Status Report block. Do NOT proceed to review without a `READY_FOR_REVIEW | BLOCKED | NEEDS_CONTEXT` value in that field.
- **READY_FOR_REVIEW** → proceed to review
- **BLOCKED** → dispatch debug subagent (see section below); do NOT immediately skip
- **NEEDS_CONTEXT** → look once for the missing context in the spec files, steering, and existing code, then retry the task; if still unresolved → dispatch debug subagent

**c) Dispatch reviewer**:
- Read `templates/reviewer-prompt.md` from this skill's directory
- Construct a review prompt with:
  - The task description and relevant spec section numbers
  - Paths to spec files (requirements.md, design.md) so the reviewer can read them directly
  - Your Status Report from a) (for reference only — reviewer must verify independently)
  - The template's `## Reading and Verification Limits` section, unchanged. The reviewer subagent does not see this skill, so the limits reach it only through the review prompt
- The reviewer must apply the `kiro-review` protocol to this task-local review.
- Preserve the existing task-specific context: task text, spec refs, `_対象の部品:_` scope, validation commands, your Status Report, and the actual `git diff` as the primary source of truth.
- Pass the validation commands for Regression Safety by the position of this task in its major task (`1.`, `2.`):
  - **Every task**: the commands that run, by name, the tests that use the files this task changed (the tests you found and ran in a)). The reviewer runs these instead of the full suite
  - **The last task of its major task**: in addition, the quality-gate commands (the commands listed in the Steps of the `/verify-frontend` `/verify-backend` `/verify-terraform` skills) of every area that the sub-tasks of this major task changed. A task is the last task of its major task when, once it is marked `[x]`, no sub-task of the same major task is left `- [ ]` except those with `_保留:_`. Do not pass the quality gates for the other tasks
- In tasks.md approved before Issue #663, completion condition 2 reads `タスクで変えた領域の verify のスキル(...)が、すべて成功している`. Read it as the current template's condition 2: it is satisfied for every sub-task of a major task when the quality gates pass in the review of its last task. The owner decided this in Issue #663; do not rewrite the text of those tasks.md files
- You do not run the tests or the quality gates in the reviewer's place, so the reviewer's output is the fresh evidence for `kiro-verify-completion`
- The reviewer subagent will run `git diff` itself to read the actual code changes and verify against the spec
- Dispatch via **Agent tool** as a fresh subagent with `subagent_type: general-purpose`

**d) Handle reviewer verdict**:
- Parse reviewer verdict only from the exact `## Review Verdict` block and `- VERDICT:` field.
- If `VERDICT` is missing, ambiguous, or replaced with prose, re-dispatch the reviewer once requesting the exact structured verdict only. Do NOT mark the task complete, commit, or continue to the next task without a parseable `APPROVED | REJECTED` value.
- **APPROVED** → before marking the task `[x]` or making any success claim, apply `kiro-verify-completion` using fresh evidence from the current code state; then mark task `[x]` in tasks.md and perform selective git commit
- **REJECTED (round 1-2)** → fix the findings yourself following the protocol, write a new Status Report, and dispatch a fresh reviewer
- **REJECTED (round 3)** → dispatch debug subagent (see section below)

**e) Commit** (main context only, selective staging):
- Stage only the files actually changed for this task, plus tasks.md
- **NEVER** use `git add -A` or `git add .`
- Use `git add <file1> <file2> ...` with explicit file paths
- Commit message format: `feat(<feature-name>): <task description>`
- Write the commit message to a file in the scratchpad first, then run `git commit -F <message-file>` as a standalone command. Do not use `-m`, a heredoc, extra options such as `-q`, or chain it with `&&` / `;` / `|` (e.g. `cd ... && git commit`). `.claude/hooks/protect-main.sh` blocks any other form, because only this form matches the `Bash(git commit *)` allow rule and stays out of the auto mode classifier. Run `git add` and `git log` as separate commands

**f) Record learnings**:
- If this task revealed cross-cutting insights, append a one-line note to the `## 実装のメモ` section at the bottom of tasks.md

**g) Debug subagent** (triggered by BLOCKED, NEEDS_CONTEXT unresolved, or REJECTED after 2 remediation rounds):

The debug subagent runs in a **fresh context** — it receives only the error information, not the failed implementation history. This avoids the context pollution that causes infinite retry loops.

- Read `templates/debugger-prompt.md` from this skill's directory
- Construct a debug prompt with:
  - The error description / blocker reason / reviewer rejection findings
  - `git diff` of the current uncommitted changes
  - The task description and relevant spec section numbers
  - Paths to spec files so the debugger can read them
- The debugger must apply the `kiro-debug` protocol to this failure investigation.
- Preserve rich failure context: error output, reviewer findings, current `git diff`, task/spec refs, and any relevant `## 実装のメモ` entries.
- When available, the debugger should inspect runtime/config state and use web or official documentation research to validate root-cause hypotheses before proposing a fix plan.
- Dispatch via **Agent tool** as a fresh subagent

**Handle debug report**:
- Parse `NEXT_ACTION` from the debug report's exact structured field.
- If `NEXT_ACTION: STOP_FOR_HUMAN` → append `_保留: <ROOT_CAUSE>_` to tasks.md, stop the feature run, and report that human review is required before continuing
- If `NEXT_ACTION: BLOCK_TASK` → append `_保留: <ROOT_CAUSE>_` to tasks.md, skip to next task
- If `NEXT_ACTION: RETRY_TASK` → preserve the current worktree; do NOT reset or discard unrelated changes. Repair the task yourself with explicit edits only, following the debug report's `FIX_PLAN` and `NOTES` and the current `git diff`
  - If the repair succeeds (READY_FOR_REVIEW → reviewer APPROVED) → normal flow
  - If the repair also fails → repeat debug cycle (max 2 debug rounds total). After 2 failed debug rounds → append `_保留: debug attempted twice, still failing — <ROOT_CAUSE>_` to tasks.md, skip
- **Max 2 debug rounds per task**. Each round: fresh debug subagent → your repair. If still failing after 2 rounds, the task is blocked.
- Record debug findings in `## 実装のメモ` (this helps subsequent tasks avoid the same issue)

**`(並行可)` markers**: Tasks marked `(並行可)` in tasks.md indicate they have no inter-dependencies and could theoretically run in parallel. However, kiro-impl processes them sequentially (one at a time) to avoid git conflicts and simplify review. The `(並行可)` marker is informational for task planning, not an execution directive.

**Completion check**: If all remaining tasks are BLOCKED, stop and report blocked tasks with reasons to the user.

#### Manual Mode (main context)

For each selected task:

**1. Build Task Brief**:
Before writing any code, read the relevant sections of requirements.md and design.md for this task and clarify:
- What observable behaviors must be true when done (acceptance criteria)
- What files/functions/tests must exist (completion definition)
- What technical decisions to follow from design.md (design constraints)
- How to confirm the task works (verification method)

**2. Execute TDD cycle** (Kent Beck's RED → GREEN → REFACTOR):
- **RED**: Write test for the next small piece of functionality based on the acceptance criteria. Test should fail.
- **GREEN**: Implement simplest solution to make test pass, following the design constraints.
- **REFACTOR**: Improve code structure, remove duplication. All tests must still pass.
- **VERIFY**: The tests that use the files this task changed pass, by name. Run the quality gates only when this task is the last task of its major task, by the same rule as Step 3 c. Confirm verification method passes.
- **REVIEW**: Apply `kiro-review` before marking the task complete. If the host supports fresh subagents in manual mode, use a fresh reviewer; otherwise perform the review in the main context using the `kiro-review` protocol. Do NOT continue until the verdict is parseably `APPROVED`.
- **MARK COMPLETE**: Only after review returns `APPROVED`, apply `kiro-verify-completion`, then update the checkbox from `- [ ]` to `- [x]` in tasks.md.

### Step 4: Final Validation

**Autonomous mode**:
- After all tasks complete, run `/kiro-validate-impl {feature}` as a GO/NO-GO gate
- If validation returns GO → before reporting feature success, apply `kiro-verify-completion` to the feature-level claim using the validation result and fresh supporting evidence
- If validation returns NO-GO:
  - Fix only concrete findings from the validation report
  - Cap remediation at 3 rounds; if still NO-GO, stop and report remaining findings
- If validation returns MANUAL_VERIFY_REQUIRED → stop and report the missing verification step

**Manual mode**:
- Suggest running `/kiro-validate-impl {feature}` but do not auto-execute

## Feature Flag Protocol

For tasks that add or change behavior, enforce RED → GREEN with a feature flag:

1. **Add flag** (OFF by default): Introduce a toggle appropriate to the codebase (env var, config constant, boolean, conditional -- agent chooses the mechanism)
2. **RED -- flag OFF**: Write tests for the new behavior. Run tests → must FAIL. If tests pass with flag OFF, the tests are not testing the right thing. Rewrite.
3. **GREEN -- flag ON + implement**: Enable the flag, write implementation. Run tests → must PASS.
4. **Remove flag**: Make the code unconditional. Run tests → must still PASS.

**Skip this protocol for**: refactoring, configuration, documentation, or tasks with no behavioral change.

## Critical Constraints
- **Strict Handoff Parsing**: Never infer your `STATUS` or the reviewer's `VERDICT` from surrounding prose; only the exact structured fields count
- **No Destructive Reset**: Never use `git checkout .`, `git reset --hard`, or similar destructive rollback inside the implementation loop
- **Selective Staging**: NEVER use `git add -A` or `git add .`; always stage explicit file paths
- **Bounded Review Rounds**: Max 2 rounds of fixing the reviewer's findings yourself, then debug
- **Bounded Debug**: Max 2 debug rounds per task (debug + re-implementation per round); if still failing → BLOCKED
- **Bounded Remediation**: Cap final-validation remediation at 3 rounds

## Output Description

**Autonomous mode**: For each task, report the following in Japanese. Do not show the structured values (`READY_FOR_REVIEW`, `BLOCKED`, `NEEDS_CONTEXT`, `APPROVED`, `REJECTED`, `GO`, `NO-GO`, `MANUAL_VERIFY_REQUIRED`) as they are; write them as the Japanese words below
1. タスクの番号と、実装のチェックの判定。`APPROVED` は「合格」、`REJECTED` は「差し戻し」と書く。実装が止まったときは、止まった理由を書く
2. 変えたファイルと、コミットのハッシュ
3. すべてのタスクのあと: `/kiro-validate-impl` の判定。`GO` は「出荷してよい」、`NO-GO` は「直すところがある」、`MANUAL_VERIFY_REQUIRED` は「所有者が手で確かめることがある」と書く

**Manual mode**:
1. Tasks executed: task numbers and test results
2. Status: completed tasks marked in tasks.md, remaining tasks count

**Format**: Concise, in the language specified in spec.json.

## Safety & Fallback

### Error Scenarios

**Tasks Not Approved or Missing Spec Files**:
- **Stop Execution**: All spec files must exist and tasks must be approved
- **Suggested Action**: 「spec のファイルがそろっていないか、タスクがまだ承認されていません。`/kiro-spec-requirements`、`/kiro-spec-design`、`/kiro-spec-tasks` のうち、終わっていない段階のコマンドを打ち、その段階を承認してください。」

**Test Failures**:
- **Stop Implementation**: Fix failing tests before continuing
- **Action**: Debug and fix, then re-run

**All Tasks Blocked**:
- Stop and report all blocked tasks with reasons
- Human review needed to resolve blockers

**Spec Conflicts with Reality**:
- If a requirement or design conflicts with reality (API doesn't exist, platform limitation), block the task with `_保留: <reason>_` -- do not silently work around it

**Upstream Ownership Detected**:
- If review, debug, or validation shows that the root cause belongs to an upstream, foundation, shared-platform, or dependency spec, do not patch around it inside the downstream feature
- Route the fix back to the owning upstream spec, keep the downstream task blocked until that contract is repaired, and re-run validation/smoke for dependent specs after the upstream fix lands

**Task Plan Invalidated During Implementation**:
- If debug returns `NEXT_ACTION: STOP_FOR_HUMAN` because of task ordering, boundary, or decomposition problems, stop and return for human review of `tasks.md` or the approved plan instead of forcing a code workaround
