---
name: kiro-spec-requirements
description: Generate requirements based on project description and steering context (written per .kiro/settings/rules/spec-writing.md). Use when generating requirements from project description.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Agent, WebSearch, WebFetch, AskUserQuestion
metadata:
  shared-rules: "requirements-review-gate.md"
---

# kiro-spec-requirements Skill

## Core Mission
- **Success Criteria**:
  - Create complete requirements document aligned with steering context
  - `.kiro/settings/rules/spec-writing.md` の文の書き方と文書の組み立ての節に従う
  - Focus on core functionality without implementation details
  - Make inclusion/exclusion boundaries explicit when scope could otherwise be misread
  - Update metadata to track generation status

## Execution Steps

### Step 1: Gather Context

If steering/spec context is already available from conversation, skip redundant file reads.
Otherwise, load all necessary context:
- Read `.kiro/specs/{feature}/spec.json` for language and metadata
- Read `.kiro/specs/{feature}/brief.md` if it exists (discovery context: problem, approach, scope decisions, boundary candidates)
- Read `.kiro/specs/{feature}/requirements.md` for project description
- Core steering context: `product.md`, `tech.md`, `structure.md`
- Additional steering files only when directly relevant to feature scope, user personas, business/domain rules, compliance/security constraints, operational constraints, or existing product boundaries
- Relevant local agent skills or playbooks only when they clearly match the feature's host environment or use case and contain domain terminology or workflow rules that shape user-observable requirements

### Step 2: Read Guidelines
- Read `.kiro/settings/rules/spec-writing.md`. Its sections 文の書き方 and 文書の組み立て, the sample 見本1, and the 見出しと目印の一覧 are the writing standard for this spec
- Read `rules/requirements-review-gate.md` from this skill's directory for pre-write review criteria
- Read `.kiro/settings/templates/specs/requirements.md` for document structure

#### Parallel Research (subagent dispatch)

The following research areas are independent. Decide the optimal decomposition based on project complexity -- split, merge, add, or skip subagents as needed.

**Delegate to subagent via Agent tool** (keeps exploration out of main context):
- **Codebase hints** (brownfield projects): Dispatch a subagent to explore existing implementations that inform requirement scope. Example prompt: "Explore this codebase for existing features related to [feature area]. Summarize: (1) what already exists, (2) relevant interfaces/APIs, (3) patterns that new requirements should align with. Return a summary under 150 lines."
- **Domain research** (when external knowledge is needed): Dispatch a subagent for WebSearch/WebFetch to research domain-specific requirements, standards, or best practices. Return a concise findings summary.
- **Additional steering and playbooks**: If many steering files or local agent playbooks exist, dispatch a subagent to scan them and return only the sections relevant to this feature.

For greenfield projects with minimal codebase, skip subagent dispatch and load context directly.

After all research completes, synthesize findings in main context before generating requirements.

### Step 3: Generate Requirements Draft
- Create initial requirements draft based on project description
- Group related functionality into logical requirement areas
- `.kiro/settings/rules/spec-writing.md` の文の書き方と文書の組み立ての節に従う(each requirement is a `### 要件N 題名` heading, a paragraph on why the owner wants it, then numbered items; no `**Objective:**` line)
- Use language specified in spec.json
- Preserve terminology continuity across phases. `.kiro/settings/rules/spec-writing.md` の見出しと目印の一覧に従う(requirements = the `## 範囲` section with 「この spec で決めること」/「この spec で決めないこと」/「この spec が前提にしていること」; design = `## 作るものと作らないもの`, `## 使う既存の仕組み`, `## 設計を見直すきっかけ`; tasks = `_対象の部品:_`)
- If scope could be misread, add lightweight boundary context without introducing implementation or architecture ownership detail
- Keep this as a draft until the review gate passes; do not write `requirements.md` yet
- If spec.json has `additional_issues`, keep every existing requirement and its numbered items with their numbers unchanged, and add new requirements numbered after the last existing one
- Mark new, changed, and withdrawn items following the 「Issueの印」 rules in CLAUDE.md
- If spec.json has `additional_issues`, run the command below (replace `<feature>` with the feature name) to get only the total number of merged PRs returned (`total`) and the PRs whose body has a mismatched-spec line, with their numbers and those lines (`hits`). Do not use `--search`, so the result does not depend on how GitHub splits search terms. `--jq` is built into gh and does not depend on jq on the host

  ```bash
  gh pr list --state merged --limit 1000 --json number,body --jq '{total: length, hits: [.[] | select(.body | contains("- 食い違う spec: `.kiro/specs/<feature>/")) | {number, lines: [.body | split("\n")[] | select(startswith("- 食い違う spec: `.kiro/specs/<feature>/"))]}]}'
  ```

  - If `total` is 1000 (the limit), state in the generation report that older PRs were not checked
  - If `gh pr list` fails, do not stop the generation. State in the generation report that the search failed, and at the end of requirements.md leave one empty line followed by the line 「spec 無しのPRの検索に失敗したため、食い違いを拾えていない」
  - Among the places those lines point to, fix the ones in requirements.md to match the behavior the PR changed, and append `(PR #<そのPRの番号> で変更済み)` to the end of each fixed item. Do not use `(#N で変更)` for them: that behavior is not written in the body of the additional Issue #N and has already shipped. Do not fix places whose text already matches the PR's behavior

### Step 4: Review Requirements Draft
- Run the `Requirements Review Gate` from `rules/requirements-review-gate.md`
- Review coverage, ambiguity, adjacent expectations, and scope boundaries before finalizing. Also review that the draft follows the sections 文の書き方 and 文書の組み立て of `.kiro/settings/rules/spec-writing.md`
- If issues are local to the draft, repair the requirements and review again
- Keep the review bounded to at most 2 repair passes
- If the draft exposes a real scope ambiguity or contradiction, stop and ask the user to clarify instead of writing guessed requirements

### Step 5: Finalize and Update Metadata
- Write `.kiro/specs/{feature}/requirements.md` only after the requirements review gate passes
- Set `phase: "requirements-generated"`
- Set `approvals.requirements.generated: true`
- Update `updated_at` timestamp

## Important Constraints

### Requirements Scope: WHAT, not HOW
Requirements describe user-observable behavior, not implementation. Use this to decide what belongs here vs. in design:

**Ask the user about (requirements scope):**
- Functional scope — what is included and what is excluded
- User-observable behavior — "when X happens, what should the user see/experience?"
- Business rules and edge cases — limits, error conditions, special cases
- Non-functional requirements visible to users — response time expectations, availability, security level
- Adjacent expectations only when they change user-visible behavior or operator expectations — what this feature relies on, and what it explicitly does not own

**Do not ask about (design scope — defer to design phase):**
- Technology stack choices (database, framework, language)
- Architecture patterns (microservices, monolith, event-driven)
- API design, data models, internal component structure
- How to achieve non-functional requirements (caching strategy, scaling approach)
- Internal ownership mapping, component seams, or implementation boundaries that belong in design

**Litmus test**: If a numbered item of a requirement can be written without mentioning any technology, it belongs in requirements. If it requires a technology choice, it belongs in design.

### Other Constraints
- Each requirement must be testable and unambiguous. If the project description leaves room for multiple interpretations on scope, behavior, or boundary conditions, ask the user to clarify before generating that requirement. Ask as many questions as needed; do not generate requirements that contain your own assumptions.
- `.kiro/settings/rules/spec-writing.md` の文の書き方の節に従う(the subject of each sentence is the person or thing that actually acts)
- Write each requirement heading in requirements.md as `### 要件N 題名` with a numeric N (the 見出しと目印の一覧 in `.kiro/settings/rules/spec-writing.md`); do not use alphabetic IDs like "要件A".

## Output Description
Provide output in the language specified in spec.json with:

1. **Generated Requirements Summary**: Brief overview of major requirement areas (3-5 bullets)
2. **Document Status**: Confirm requirements.md updated and spec.json metadata updated
3. **Review Gate**: Confirm the requirements review gate passed
4. **Next Steps**: State that `/spec-review {feature} requirements` runs next, right after generation and before approval (CLAUDE.md requires running it immediately and not asking for approval until the review is complete). Then guide user on how to proceed after the review (approve and continue, or modify)

**Format Requirements**:
- Use Markdown headings for clarity
- Include file paths in code blocks
- Keep summary concise (under 300 words)

## Safety & Fallback

### Error Scenarios
- **Missing Project Description**: If requirements.md lacks project description, ask user for feature details
- **Template Missing**: If template files don't exist, use inline fallback structure with warning
- **Language Undefined**: Default to English (`en`) if spec.json doesn't specify language
- **Incomplete Requirements**: After generation, explicitly ask user if requirements cover all expected functionality
- **Steering Directory Empty**: Warn user that project context is missing and may affect requirement quality
- **Non-numeric Requirement Headings**: If existing headings do not include a leading numeric ID (for example, they use "要件A"), normalize them to numeric IDs and keep that mapping consistent (never mix numeric and alphabetic labels).

### Next Phase: Design Generation

**Right After Generation (before approval)**:
- Run `/spec-review {feature} requirements`. Do NOT ask for approval until the review is complete

**If Requirements Approved**:
- **Optional Gap Analysis** (for existing codebases):
  - Run `/kiro-validate-gap {feature}` to analyze implementation gap
  - Recommended for brownfield projects; skip for greenfield
- Run `/kiro-spec-design {feature}` to proceed to design phase

**If Modifications Needed**:
- Provide feedback and re-run `/kiro-spec-requirements {feature}`
