---
name: kiro-spec-tasks
description: Generate implementation tasks from requirements and design (written per .kiro/settings/rules/spec-writing.md). Use when creating actionable task lists.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Agent
argument-hint: <feature-name> [-y] [--sequential]
metadata:
  shared-rules: "tasks-generation.md, tasks-parallel-analysis.md"
---

# kiro-spec-tasks Skill

## Core Mission
- **Success Criteria**:
  - All requirements mapped to specific tasks
  - Tasks properly sized (1-3 hours each)
  - Clear task progression with proper hierarchy
  - Natural language descriptions focused on capabilities
  - A lightweight task-plan sanity review confirms the task graph is executable before `tasks.md` is written

## Execution Steps

### Step 1: Gather Context

If steering/spec context is already available from conversation, skip redundant file reads.
Otherwise, load all necessary context:
- `.kiro/specs/{feature}/spec.json`, `requirements.md`, `design.md`
- `.kiro/specs/{feature}/tasks.md` (if exists, for merge mode)
- Core steering context: `product.md`, `tech.md`, `structure.md`
- Additional steering files only when directly relevant to requirements coverage, design boundaries, runtime prerequisites, or team conventions that affect task executability

- Determine execution mode:
  - `sequential = (sequential flag is true)`

**Validate approvals**:
- If auto-approve flag (`-y`) is true: Auto-approve requirements and design in spec.json,
  recording `approved_by: "auto:-y"` and `approved_at` (ISO 8601) in each approval
  object — auto-approval must never be recorded under a human's name.
  Tasks approval is also handled automatically in Step 4.
- Otherwise: Verify both approved (stop if not, see Safety & Fallback)

### Step 2: Generate Implementation Tasks

- Read `rules/tasks-generation.md` from this skill's directory for principles
- Read `rules/tasks-parallel-analysis.md` from this skill's directory for parallel judgement criteria
- Template for format: Read `.kiro/settings/templates/specs/tasks.md` (supports `(並行可)` markers)
- Writing rules: read `.kiro/settings/rules/spec-writing.md`. Its sections 文の書き方, 文書の組み立て, 繰り返しの扱い, テストと品質チェックの書き方, Issueの印, the sample tasks.md の見本, and the 見出しと目印の一覧 are the writing standard for this spec's `tasks.md`

#### Parallel Research

The following research areas are independent and can be executed in parallel:
1. **Context loading**: Spec documents (requirements.md, design.md), steering files
2. **Rules loading**: tasks-generation.md, tasks-parallel-analysis.md, tasks template, and spec-writing.md

After all parallel research completes, synthesize findings before generating tasks.

**Generate task list following all rules**:
- Use language specified in spec.json
- Map all requirements to tasks and list numeric requirement IDs only (comma-separated) without descriptive suffixes, parentheses, translations, or free-form labels
- Ensure all design components included
- Verify task progression is logical and incremental
- Ensure each executable sub-task includes at least one detail bullet that states what "done" looks like in observable terms
- Keep normal implementation tasks within a single responsibility boundary; if work crosses boundaries, make it an explicit integration task
- tasks.md の雛形(`.kiro/settings/templates/specs/tasks.md`)と `.kiro/settings/rules/spec-writing.md` の tasks.md の見本に従い、`(並行可)` の印を付ける:
- Append ` (並行可)` to the end of the title of each task that satisfies parallel criteria when `!sequential`
- Explicitly note dependencies preventing `(並行可)` when tasks appear parallel but are not safe
- If sequential mode is true, omit `(並行可)` entirely
- If existing tasks.md found, merge with new content
- Do not create tasks from requirement or design items marked `(PR #… で変更済み)`: their behavior was already implemented in the PR named by the mark

### Step 3: Review Task Plan

- Keep the draft task plan in working memory; do NOT write `tasks.md` yet
- Run the `Task Plan Review Gate` from `rules/tasks-generation.md`
- Review coverage:
  - Every requirement ID appears in at least one task
  - Every design component, contract, integration point, runtime prerequisite, and validation concern is represented
- Review executability:
  - Each sub-task is an executable 1-3 hour work unit
  - Each sub-task has a verifiable deliverable
  - Each executable sub-task includes an observable completion bullet
  - No implicit prerequisites remain hidden
  - `_依存:_`, `_対象の部品:_`, and `(並行可)` markers still match the dependency graph and architecture boundaries (the 見出しと目印の一覧 in `.kiro/settings/rules/spec-writing.md`)
- If issues are task-plan-local, repair the draft and re-run the review gate before writing
- Keep the review bounded to at most 2 repair passes
- If review exposes a real requirements/design gap or contradiction, stop and send the user back to requirements/design instead of inventing filler tasks

### Step 3.5: Run Task-Graph Sanity Review

Before writing `tasks.md`, run one lightweight independent sanity review of the task graph.

- If fresh subagent dispatch is available, spawn one fresh review subagent for this step. Otherwise perform the same review in the current context.
- Provide only file paths, the draft task plan, and merge context if an existing `tasks.md` is being updated. The reviewer should read `requirements.md`, `design.md`, and the task-generation rules directly instead of relying on a parent-synthesized coverage summary.
- Check only:
  - hidden prerequisites or missing setup tasks
  - dependency or ordering mistakes
  - boundary overlap or ambiguous ownership between tasks
  - tasks that are too large, too vague, cross boundaries without being explicit integration tasks, or are missing a verifiable deliverable
  - contradictions introduced between requirements, design, and the task graph
- Return one verdict:
  - `PASS`
  - `NEEDS_FIXES`
  - `RETURN_TO_DESIGN`
- If `NEEDS_FIXES`, repair the draft once and re-run the sanity review one time.
- If `RETURN_TO_DESIGN`, stop without writing `tasks.md` and point back to the exact gap in requirements/design.
- Keep this bounded. Do not turn it into a second full planning cycle.

### Step 4: Finalize

**Write tasks.md**:
- Create/update `.kiro/specs/{feature}/tasks.md`
- Update spec.json metadata:
  - Set `phase: "tasks-generated"`
  - Set `approvals.tasks.generated: true, approved: false`
  - Set `approvals.requirements.approved: true`
  - Set `approvals.design.approved: true`
  - Whenever setting any `approvals.*.approved: true`, also set `approved_by`
    and `approved_at` (ISO 8601) in the same object: `"DogisRiki"` when the
    user approved interactively in this conversation, `"auto:-y"` when via
    auto-approve. Never record auto-approval under a human's name, and never
    overwrite an existing `approved_by` / `approved_at`. The user typing this
    command without `-y` is the interactive approval of design, also when they
    typed `/clear` just before it. If an approval is
    already `true` but carries no `approved_by` (approved in an earlier
    conversation), record `"unknown:pre-existing"` rather than a human's name
  - Update `updated_at` timestamp

**Approval**:

This skill's **Right After Generation (before approval)** item under Next Phase requires running `/spec-review` right after generation and not asking for approval until the review is complete, so this skill does NOT ask for approval right after writing `tasks.md`.

- If auto-approve flag (`-y`) is true:
  - Set `approvals.tasks.approved: true` in spec.json, with `approved_by: "auto:-y"`
    and `approved_at` (ISO 8601)
  - Display task summary (task count, major groups, parallel markers)
  - Respond: 「タスクを作り、自動で承認しました。`/kiro-impl {feature}` を打つと、実装が始まります。」
  - Note: CLAUDE.md prohibits `-y`; this branch is kept only as the upstream behavior. Do not add any other automatic approval path
- Otherwise (interactive):
  1. Display a summary of the generated tasks (task count, major groups, parallel markers)
  2. Do NOT ask for approval yet. Run `/spec-review {feature} tasks` next
  3. Only after `/spec-review {feature} tasks` has finished, ask the user: 「タスクを作り、審査も終わりました。タスクを承認して、実装に進みますか。」
  - If the user approves:
    - Set `approvals.tasks.approved: true` in spec.json, with `approved_by: "DogisRiki"`
      and `approved_at` (ISO 8601)
    - Respond: 「タスクの承認を記録しました。`/clear` を打ってから `/kiro-impl {feature}` を打つと、実装が始まります。」 `/clear` keeps the spec stages' skill text and review exchange out of the implementation conversation; spec.json, tasks.md and the review records carry everything `/kiro-impl` needs. Do not ask the user to type `/clear` or `/kiro-impl` again in the middle of implementation
  - If the user wants changes:
    - Keep `approvals.tasks.approved: false`
    - Respond with guidance on what to adjust and re-run

## Critical Constraints
- **Task Integration**: Every task must connect to the system (no orphaned work)
- **Boundary annotations**: tasks.md の雛形の注記と `.kiro/settings/rules/spec-writing.md` の tasks.md の見本に従う(write `_対象の部品: ComponentName_` with design.md component names on `(並行可)` tasks; omit it when the scope is obvious)
- **Explicit dependencies**: tasks.md の雛形の注記に従う(declare cross-boundary non-obvious dependencies with `_依存: X.X_`)
- **Executable deliverable granularity**: Each task must produce a verifiable deliverable (file, endpoint, UI component, config). Infrastructure tasks (project scaffolding, manifest, host integration, build config) must be explicit — never assume they exist
- **Observable done state**: Each executable sub-task must include at least one detail bullet that makes the completed state visible without adding new bookkeeping fields
- **No implicit prerequisites**: If a task requires a runtime, SDK, framework setup, or config file, that setup must be a separate preceding task

## Output Description

Provide brief summary in the language specified in spec.json:

1. **Status**: Confirm tasks generated at `.kiro/specs/{feature}/tasks.md`
2. **Task Summary**:
   - Number of major tasks: X
   - Number of sub-tasks: Y
   - Write these two numbers on separate lines, not joined in one line
   - All Z requirements covered
   - Average task size: 1-3 hours per sub-task
3. **Quality Validation**:
   - All requirements mapped to tasks
   - Design coverage and runtime prerequisites reviewed
   - Task dependencies verified
   - Task plan review gate passed
   - Independent task-graph sanity review passed
   - Testing tasks included
4. **Next Action**: State that `/spec-review {feature} tasks` runs next, right after generation and before approval (this skill's **Right After Generation (before approval)** item under Next Phase requires running it immediately and not asking for approval until the review is complete). Then ask for approval after the review (see Step 4)

**Format**: Concise (under 200 words)

**Note**: The actual tasks document follows `.kiro/settings/templates/specs/tasks.md` structure.

## Safety & Fallback

### Error Scenarios

**Requirements or Design Not Approved**:
- **Stop Execution**: Cannot proceed without approved requirements and design
- **User Message**: 「タスクを作る前に、要件と設計の承認が要ります。」
- **Suggested Action**: 「まだ承認されていない要件か設計を読んで承認してから、もう一度 `/kiro-spec-tasks {feature}` を打ってください。CLAUDE.md が自動の承認を禁じているので、`-y` は付けないでください。」

**Missing Requirements or Design**:
- **Stop Execution**: Both documents must exist
- **User Message**: 「`.kiro/specs/{feature}/` に、`requirements.md` か `design.md` がありません。」
- **Suggested Action**: 「先に、`/kiro-spec-requirements {feature}` と `/kiro-spec-design {feature}` のうち、まだ打っていないコマンドを打ち、要件と設計を作って承認してください。そのあと、もう一度 `/kiro-spec-tasks {feature}` を打ってください。」

**Incomplete Requirements Coverage**:
- **Warning**: 「どのタスクにも割り当てられていない要件があります。Claude は、その要件の番号を下に並べます。わざとタスクにしていない要件か、Claude がタスクを作り直す要件かを、この会話で答えてください。」
- **User Action Required**: Confirm intentional gaps or regenerate tasks

**Spec Gap Found During Task Review**:
- **Stop Execution**: Do not write a patched-over `tasks.md`
- **User Message**: 「タスクを作る途中で、要件か設計に足りない点か、2通りに読める点が見つかりました。Claude は、足りない点と2通りに読める点を、下に並べます。要件か設計をどう直すかを、この会話で答えてください。」
- **Suggested Action**: Refine requirements.md or design.md following the owner's answer, then re-run `/kiro-spec-tasks {feature}`

**Template/Rules Missing**:
- **User Message**: 「`.kiro/settings/` に、タスクの雛形か決まりのファイルがありません。」 (the template is `.kiro/settings/templates/specs/tasks.md`)
- **Fallback**: Use inline basic structure with warning
- **Suggested Action**: 「Claude は、雛形か決まりのファイルが無いので、それを使わずにタスクを作りました。雛形と決まりのとおりに作り直すときは、Claude が main から雛形と決まりのファイルを戻すので、この会話でそう書いてください。」
- **Missing Numeric Requirement IDs**:
  - **Stop Execution**: All requirements in requirements.md MUST have numeric IDs. If any requirement lacks a numeric ID, stop and request that requirements.md be fixed before generating tasks.

### Next Phase: Implementation

**Right After Generation (before approval)**:
- Run `/spec-review {feature} tasks`. Do NOT ask for approval until the review is complete

Tasks are approved in Step 4 via user confirmation after the review. Once approved:
- Autonomous implementation: `/kiro-impl {feature}`
- Specific tasks only: `/kiro-impl {feature} 1.1,1.2`
