# TDD Task Implementation Protocol

## Role
This is the protocol that the conversation's Claude running `/kiro-impl` follows when it implements a single task itself. `/kiro-impl` does not dispatch an implementer subagent. Setup, task sequencing, task-state updates, and commits follow the steps in `SKILL.md`; this protocol covers only the implementation and validation work for the task.

## Gather Before Implementing
- Feature name and task identifier/text
- Paths to spec files: `requirements.md`, `design.md`, `tasks.md`
- Exact numbered sections from `requirements.md` and `design.md` that this task must satisfy (source numbering, e.g., `1.2`, `3.1`, `A.2`)
- `_対象の部品:_` scope constraints and the `_依存:_` information checked in Step 2 of `SKILL.md`
- spec の見出しと目印は、`.kiro/settings/rules/spec-writing.md` の「見出しと目印の一覧」の名前で読む
- Project steering context and the validation commands discovered in the Preflight of `SKILL.md` (tests/build/smoke when available)
- Whether the task is behavioral (Feature Flag Protocol) or non-behavioral

## Execution Protocol

### Step 1: Load Task-Relevant Context
- Read the referenced sections of `requirements.md` and `design.md` for this task
- Preserve the original section numbering; do NOT invent `REQ-*` aliases
- Expand any file globs or path patterns before reading files
- Inspect existing code patterns only in the declared boundary
- Read only the task-relevant steering; do not bulk-load unrelated skills or playbooks

### Step 2: Build Task Brief
Before writing any code, synthesize a concrete Task Brief from the spec sections you just read:

- **Acceptance criteria**: What observable behaviors must be true when done? Extract from the requirement sections. Be specific (e.g., "POST /auth/login returns JWT on valid credentials, 401 on invalid"), not vague.
- **Completion definition**: What files, functions, tests, or artifacts must exist? Derive from design.md component structure and task boundary.
- **Design constraints**: What specific technical decisions from design.md must be followed? (e.g., "use bcrypt for hashing", "implement as Express middleware"). If design says "use X", you must use X.
- **Verification method**: How to confirm the task works. Derive from the requirement's testability and the validation commands from the Preflight.

If any of these cannot be determined from the spec — the requirements are too vague, the design doesn't specify the approach, or the task description is ambiguous — set the status to **NEEDS_CONTEXT** immediately with what's missing. Do not guess or fill gaps with assumptions.

### Step 3: Implement with TDD
- For behavioral tasks, follow the Feature Flag Protocol:
  1. Add a flag defaulting OFF
  2. RED: write/adjust tests so they fail with the flag OFF. **Run tests and capture the failing output.** You will include this in the status report as evidence.
  3. GREEN: enable the flag and implement until tests pass
  4. Remove the flag and confirm tests still pass
- For non-behavioral tasks, use a standard RED → GREEN → REFACTOR cycle. **Run tests after writing them (before implementation) and capture the failing output.**
- Use the acceptance criteria from the Task Brief to drive test design
- Follow the design constraints exactly
- Keep changes tightly scoped to the assigned task
- Run only the tests you added and the tests that cover the code you changed, by naming them (e.g. `./gradlew test --tests <class>`, `pnpm test <test file>`). Do NOT run the full suite at any point (see Critical Constraints)

### Step 4: Validate
- Run the validation commands from the Preflight needed to establish confidence for this task, narrowed to the tests you added and the tests that cover the changed code
- Prefer the canonical commands from the Preflight over inventing new ones; only add a task-local verification command when that set does not cover the task, and explain why
- The reviewer runs the full suite and the quality gates for this task after you write the status report, so you do not need to run them
- Re-read the referenced requirement and design sections and compare them against the changed code and tests
- Confirm the verification method from the Task Brief passes
- If a validation command fails because of a pre-existing unrelated issue, report that precisely instead of masking it

### Step 5: Self-Review
- Review your own changes before writing the status report
- Verify each acceptance criterion from the Task Brief is satisfied by concrete behavior
- Verify each design constraint is reflected in the implementation
- Verify the implementation is NOT a mock, stub, placeholder, fake, or TODO-only path unless the task explicitly requires one
- Verify there are no TBD, TODO, or FIXME markers left in changed files
- Verify the tests prove the required behavior, not just scaffolding or a happy-path shell
- Verify that any namespace or qualified-name access used at runtime (for example `React.X`, `module.Foo`, `pkg.Bar`) has a real value import or runtime binding, not only a type-only import or ambient type reference
- Verify that any newly introduced runtime-sensitive dependency or packaging assumption (native modules, module-format boundaries, generated assets, required env vars, boot-time config) is reflected in validation or called out explicitly in `CONCERNS`
- If any review check fails, fix the implementation, re-run validation, and repeat this step

## Critical Constraints
- Do NOT mark the task `[x]` in `tasks.md` or create commits before the reviewer returns `APPROVED` (Step 3 d and e of `SKILL.md`)
- Do NOT run the full test suite or the quality gates while implementing: `./gradlew check` / `build`, `./gradlew test` without `--tests`, `pnpm test` without test files, `pnpm run coverage`, mutation tests, or the `/verify-frontend` `/verify-backend` skills. The reviewer runs them for each task, and running them here too doubles the time and cost
- Do NOT expand scope beyond the assigned task and boundary
- Do NOT silently work around requirement or design mismatches
- Use the exact section numbers from `requirements.md` and `design.md` in all notes and reports; do NOT invent `REQ-*` aliases
- Do NOT stop at a mock, stub, placeholder, fake, or TODO-only implementation unless the task explicitly requires it
- Prefer the minimal implementation that satisfies the Task Brief and tests

## Status Report

After the self-review, write this structured status block. Step 3 b of `SKILL.md` reads the exact `- STATUS:` line, and Step 3 c passes the block to the reviewer. Do NOT rename the heading, omit the block, or replace the allowed status values with synonyms. Write exactly one status block per attempt. Put extra explanation inside the defined fields, not after the block.


```
## Status Report
- STATUS: READY_FOR_REVIEW | BLOCKED | NEEDS_CONTEXT
- TASK: <task-id>
- TASK_BRIEF: <one-line summary of the acceptance criteria you derived>
- FILES_CHANGED: <comma-separated list of changed files>
- REQUIREMENTS_CHECKED: <exact section numbers from requirements.md>
- DESIGN_CHECKED: <exact section numbers from design.md>
- RED_PHASE_OUTPUT: <test command and failing output from before implementation -- proves tests were written first>
- TESTS_RUN: <test commands and final passing results>
- CONCERNS: <optional -- describe any non-blocking concerns the reviewer should pay attention to>
- BLOCKER: <only for BLOCKED -- describe what prevents completion>
- BLOCKER_REMEDIATION: <only for BLOCKED -- what would unblock this? e.g., "design.md section 3.2 specifies API X but it doesn't exist; update design or provide alternative">
- MISSING: <only for NEEDS_CONTEXT -- describe exactly what additional context is needed and where it might be found>
- EVIDENCE: <concrete code paths, functions, and tests that prove the behavior>
```
