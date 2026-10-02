---
name: kiro-spec-design
description: Generate comprehensive technical design translating requirements (WHAT) into architecture (HOW) with discovery process (written per .kiro/settings/rules/spec-writing.md when spec.json has spec_format 2, otherwise with the old template). Use when creating architecture from requirements.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, WebSearch, WebFetch, Agent
argument-hint: <feature-name> [-y]
metadata:
  shared-rules: "design-principles.md, design-discovery-full.md, design-discovery-light.md, design-synthesis.md, design-review-gate.md"
---

# kiro-spec-design Skill

## Core Mission
- **Success Criteria**:
  - All requirements mapped to technical components with clear interfaces
  - The design makes responsibility boundaries explicit enough to guide task generation and review
  - Appropriate architecture discovery and research completed
  - Design aligns with steering context and existing patterns
  - Visual diagrams included for complex architectures

## Execution Steps

### Step 1: Gather Context

If steering/spec context is already available from conversation, skip redundant file reads.
Otherwise, load all necessary context:
- `.kiro/specs/{feature}/spec.json`, `requirements.md`, `design.md` (if exists)
  - From spec.json, read the `spec_format` field. `spec_format` is `2` for a new-format spec; the field is absent for a spec created before the new format. This field decides which template and rules the later steps use. Do NOT add, remove, or change `spec_format` (a spec without the field stays in the old format and is never rewritten in the new format)
- `.kiro/specs/{feature}/research.md` (if exists, contains gap analysis from `/kiro-validate-gap`)
- Core steering context: `product.md`, `tech.md`, `structure.md`
- Additional steering files only when directly relevant to requirement coverage, architecture boundaries, integrations, runtime prerequisites, security/performance constraints, or team conventions that affect implementation readiness
- Template for document structure, chosen by `spec_format`:
  - `spec_format` is `2`: `.kiro/settings/templates/specs/design.md`
  - `spec_format` is absent: `.kiro/settings/templates/specs-v1/design.md`
  - `spec_format` has any other value: stop and report it to the user; do not guess the format
- Writing rules: when `spec_format` is `2`, read `.kiro/settings/rules/spec-writing.md`. Its sections 文の書き方, 文書の組み立て, design.md の書き方, 繰り返しの扱い, the sample 見本2, and the 新旧の見出しと目印の対応表 are the writing standard for this spec's `design.md`
- Read `rules/design-principles.md` from this skill's directory for design principles (for both formats; it says which items read differently when `spec_format` is `2`)
- `.kiro/settings/templates/specs/research.md` for discovery log structure (for both formats; `research.md` has no old-format template and its writing is not changed by `spec_format`)

**Validate requirements approval**:
- If auto-approve flag is true: Auto-approve requirements in spec.json,
  recording `approved_by: "auto:-y"` and `approved_at` (ISO 8601) in the same
  object — auto-approval must never be recorded under a human's name
- Otherwise: Verify approval status (stop if unapproved, see Safety & Fallback)

### Step 2: Discovery & Analysis

**Critical: This phase ensures design is based on complete, accurate information.**

1. **Classify Feature Type**:
   - **New Feature** (greenfield) → Full discovery required
   - **Extension** (existing system) → Integration-focused discovery
   - **Simple Addition** (CRUD/UI) → Minimal or no discovery
   - **Complex Integration** → Comprehensive analysis required

2. **Execute Appropriate Discovery Process**:

   **For Complex/New Features**:
   - Read and execute `rules/design-discovery-full.md` from this skill's directory
   - Conduct thorough research using WebSearch/WebFetch:
     - Latest architectural patterns and best practices
     - External dependency verification (APIs, libraries, versions, compatibility)
     - Official documentation, migration guides, known issues
     - Performance benchmarks and security considerations

   **For Extensions**:
   - Read and execute `rules/design-discovery-light.md` from this skill's directory
   - Focus on integration points, existing patterns, compatibility
   - Use Grep to analyze existing codebase patterns

   **For Simple Additions**:
   - Skip formal discovery, quick pattern check only

#### Parallel Research (subagent dispatch)

The following research areas are independent and can be dispatched as **subagents** via the Agent tool. The agent should decide the optimal decomposition based on feature complexity — split, merge, add, or skip subagents as needed. Each subagent returns a **findings summary** (not raw data) to keep the main context clean for synthesis.

**Typical research areas** (adjust as appropriate):
- **Codebase analysis**: Existing architecture patterns, integration points, code conventions (using Grep/Glob)
- **External research**: Dependencies, APIs, latest best practices (using WebSearch/WebFetch)
- **Context loading** (usually main context): Steering files, design principles, discovery rules, templates

For simple additions, skip subagent dispatch entirely and do a quick pattern check in main context.

After all findings return, synthesize in main context before proceeding.

3. **Retain Discovery Findings for Step 3**:
   - External API contracts and constraints
   - Technology decisions with rationale
   - Existing patterns to follow or extend
   - Integration points and dependencies
   - Identified risks and mitigation strategies
   - Boundary candidates, out-of-boundary decisions, and likely revalidation triggers

4. **Persist Findings to Research Log**:
   - Create or update `.kiro/specs/{feature}/research.md` using the shared template `.kiro/settings/templates/specs/research.md` (the same template regardless of `spec_format`)
   - Summarize discovery scope and key findings
   - Record investigations with sources and implications
   - Document architecture pattern evaluation, design decisions, and risks
   - Use the language specified in spec.json when writing or updating `research.md`

### Step 3: Synthesis

**Apply design synthesis to discovery findings before writing.**

- Read and apply `rules/design-synthesis.md` from this skill's directory
- This step requires the full picture from discovery findings — execute in main context, not in a subagent
- Record synthesis outcomes (generalizations found, build-vs-adopt decisions, simplifications) in `research.md`

### Step 4: Generate Design Draft

1. **Generate Design Draft**:
   - `spec_format` が2の spec では、この指示の代わりに `.kiro/settings/rules/spec-writing.md` の design.md の書き方の節と、新しい design.md の雛形(`.kiro/settings/templates/specs/design.md`)に従う(follow its headings, its component block of 対応する要件 line plus Japanese fields, and the notes in its comments, which allow omitting fields and sections that do not apply). For specs without `spec_format`: **Follow specs-v1/design.md template structure and generation instructions strictly**
   - `spec_format` が2の spec では、この指示の代わりに `.kiro/settings/rules/spec-writing.md` の新旧の見出しと目印の対応表に従う(the boundary is written in `## 作るものと作らないもの` with `### 作るもの` and `### 作らないもの`, `## 使う既存の仕組み`, and `## 設計を見直すきっかけ`; a boundary section that does not apply to this spec may be omitted instead of left empty). For specs without `spec_format`: **Boundary-first requirement**: Before expanding supporting sections, make the boundary explicit. The draft must clearly define what this spec owns, what it does not own, which dependencies are allowed, and what changes would require downstream revalidation.
   - **Integrate all discovery findings and synthesis outcomes**: Use researched information (APIs, patterns, technologies) and synthesis decisions (generalizations, build-vs-adopt, simplifications) throughout component definitions, architecture decisions, and integration points
   - `spec_format` が2の spec では、この指示の代わりに `.kiro/settings/rules/spec-writing.md` の新旧の見出しと目印の対応表と、新しい design.md の雛形に従う(populate `## ファイルの構成` with concrete file paths and responsibilities; it drives the task `_対象の部品:_` annotations and implementation Task Briefs, and the rest of this instruction applies to it). For specs without `spec_format`: **File Structure Plan** (required): Populate the File Structure Plan section with concrete file paths and responsibilities. Analyze the codebase to determine which files need to be created vs. modified. Each file must have one clear responsibility. This section directly drives task `_Boundary:_` annotations and implementation Task Briefs — vague file structures produce vague implementations.
   - **Testing Strategy**: Derive test items from requirements' acceptance criteria, not generic patterns. Each test item should reference specific components and behaviors from this design. E2E paths must map to the critical user flows identified in requirements. Avoid vague entries like "test login works" -- instead specify what is being verified and why it matters.
   - If existing design.md found in Step 1, use it as reference context (merge mode)
   - Apply design rules: Type Safety, Visual Communication, Formal Tone. `spec_format` が2の spec では、Formal Tone の代わりに `.kiro/settings/rules/spec-writing.md` の文の書き方の節に従う
   - Use language specified in spec.json
   - Keep this as a draft until the review gate passes; do not write `design.md` yet

### Step 5: Review Design Draft

- Read and apply `rules/design-review-gate.md` from this skill's directory
- Verify requirements coverage, architecture readiness, and implementation executability before finalizing the design
- If issues are local to the draft, repair the design and review again
- Keep the review bounded to at most 2 repair passes
- If the draft exposes a real requirements/design gap, stop and return to requirements clarification instead of papering over it in `design.md`

### Step 6: Finalize Design Document

1. **Write Final Design**:
   - Write `.kiro/specs/{feature}/design.md` only after the design review gate passes
   - Write research.md with discovery findings and synthesis outcomes (if not already written)

2. **Update Metadata** in spec.json:

   - Set `phase: "design-generated"`
   - Set `approvals.design.generated: true, approved: false`
   - Set `approvals.requirements.approved: true`
   - Whenever setting any `approvals.*.approved: true`, also set `approved_by`
     and `approved_at` (ISO 8601) in the same object: `"DogisRiki"` when the
     user approved interactively in this conversation, `"auto:-y"` when via
     auto-approve. Never record auto-approval under a human's name, and never
     overwrite an existing `approved_by` / `approved_at`
   - Update `updated_at` timestamp

## Critical Constraints
 - **Type Safety**:
   - Enforce strong typing aligned with the project's technology stack.
   - For statically typed languages, define explicit types/interfaces and avoid unsafe casts.
   - For TypeScript, never use `any`; prefer precise types and generics.
   - For dynamically typed languages, provide type hints/annotations where available (e.g., Python type hints) and validate inputs at boundaries.
   - Document public interfaces and contracts clearly to ensure cross-component type safety.
- **Requirements Traceability IDs**: Use numeric requirement IDs only (e.g. "1.1", "1.2", "3.1", "3.3") exactly as defined in requirements.md. Do not invent new IDs or use alphabetic labels.

## Output Description

**Command execution output** (separate from design.md content):

Provide brief summary in the language specified in spec.json:

1. **Status**: Confirm design document generated at `.kiro/specs/{feature}/design.md`
2. **Discovery Type**: Which discovery process was executed (full/light/minimal)
3. **Key Findings**: 2-3 critical insights from discovery that shaped the design
4. **Review Gate**: Confirm the design review gate passed
5. **Next Action**: State that `/spec-review {feature} design` runs next, right after generation and before approval (CLAUDE.md requires running it immediately and not asking for approval until the review is complete). Then give approval workflow guidance for after the review (see Safety & Fallback)
6. **Research Log**: Confirm `research.md` updated with latest decisions

**Format**: Concise Markdown (under 200 words) - this is the command output, NOT the design document itself

**Note**: The actual design document follows `.kiro/settings/templates/specs/design.md` structure when `spec_format` is `2`, and `.kiro/settings/templates/specs-v1/design.md` structure when `spec_format` is absent.

## Safety & Fallback

### Error Scenarios

**Requirements Not Approved**:
- **Stop Execution**: Cannot proceed without approved requirements
- **User Message**: "Requirements not yet approved. Approval required before design generation."
- **Suggested Action**: "Ask the user to review `requirements.md` and approve it, then re-run this skill. Do not use `-y`: auto-approval is prohibited by CLAUDE.md"

**Missing Requirements**:
- **Stop Execution**: Requirements document must exist
- **User Message**: "No requirements.md found at `.kiro/specs/{feature}/requirements.md`"
- **Suggested Action**: "Run `/kiro-spec-requirements {feature}` to generate requirements first"

**Template Missing**:
- **User Message**: "Template file missing at `.kiro/settings/templates/specs/design.md`" (or `.kiro/settings/templates/specs-v1/design.md` for a spec without `spec_format`)
- **Suggested Action**: "Check repository setup or restore template file"
- **Fallback**: Use inline basic structure with warning

**Steering Context Missing**:
- **Warning**: "Steering directory empty or missing - design may not align with project standards"
- **Proceed**: Continue with generation but note limitation in output

**Invalid Requirement IDs**:
  - **Stop Execution**: If requirements.md is missing numeric IDs or uses non-numeric headings (for example, "Requirement A"), stop and instruct the user to fix requirements.md before continuing.

**Spec Gap Found During Design Review**:
- **Stop Execution**: Do not write a patched-over `design.md`
- **User Message**: "Design review found a real spec gap or ambiguity that must be resolved before design can be finalized."
- **Suggested Action**: Clarify or fix `requirements.md`, then re-run `/kiro-spec-design {feature}`

### Next Phase: Task Generation

**Right After Generation (before approval)**:
- Run `/spec-review {feature} design`. Do NOT ask for approval until the review is complete

**If Design Approved**:
- **Optional**: Run `/kiro-validate-design {feature}` for interactive quality review
- Run `/kiro-spec-tasks {feature}` to generate implementation tasks

**If Modifications Needed**:
- Provide feedback and re-run `/kiro-spec-design {feature}`
- Existing design used as reference (merge mode)
