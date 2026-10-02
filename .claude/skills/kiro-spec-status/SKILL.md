---
name: kiro-spec-status
description: Show specification status and progress
allowed-tools: Read, Glob, Grep
argument-hint: <feature-name>
---

# kiro-spec-status Skill

## Core Mission
- **Success Criteria**:
  - Show current phase and completion status
  - Identify next actions and blockers
  - Provide clear visibility into progress
  - Surface boundary readiness, upstream/downstream context, and likely revalidation needs when available

## Execution Steps

### Step 1: Load Spec Context
- Read `.kiro/specs/$ARGUMENTS/spec.json` for metadata and phase status
- Read `.kiro/specs/$ARGUMENTS/brief.md` if it exists
- Read existing files: `requirements.md`, `design.md`, `tasks.md` (if they exist)
- Check `.kiro/specs/$ARGUMENTS/` directory for available files
- Read `.kiro/steering/roadmap.md` if it exists and this spec appears in it

### Step 2: Analyze Status

**Parse each phase**:
- **Requirements**: Count requirements and acceptance criteria
- **Design**: Check for architecture, components, diagrams, and whether boundary sections are present
- **Tasks**: Count completed vs total tasks (parse `- [x]` vs `- [ ]`)
- **Approvals**: Check approval status in spec.json
- **Boundary context**:
  - From brief.md: note `Boundary Candidates`, `Upstream / Downstream`, and `Existing Spec Touchpoints` if present
  - From design.md: note `Boundary Commitments`, `Out of Boundary`, `Allowed Dependencies`, and `Revalidation Triggers` if present
  - spec.json の `spec_format` が2の spec では、見出しと目印を `.kiro/settings/rules/spec-writing.md` の対応表の新しい名前で読む。requirements.md は、`### Requirement N: 題名` を `### 要件N 題名` と読み、`#### Acceptance Criteria` の見出しが無いので、受入基準は各要件の番号付きの項目で数える。design.md は、`Boundary Commitments` を `## 作るものと作らないもの`・`## 使う既存の仕組み`・`## 設計を見直すきっかけ` の3つの節、`Out of Boundary` を `### 作らないもの`、`Allowed Dependencies` を `## 使う既存の仕組み`、`Revalidation Triggers` を `## 設計を見直すきっかけ` と読み替える。brief.md と roadmap.md の名前は変わらない。タスクの箱(`- [x]` `- [ ]`)の形も変わらない。`spec_format` の欄が無い spec では、今の名前のまま読む
  - From roadmap.md: note upstream dependencies and whether this spec is adjacent to `Existing Spec Updates`
- **Revalidation watchlist**:
  - Identify downstream specs, neighboring existing-spec updates, or rollout-sensitive design notes that may need revalidation if this spec changes
  - Call out when the current spec shape looks too broad and may want roadmap/design splitting instead of more local repair

### Step 3: Generate Report

Create report in the language specified in spec.json covering:
1. **Current Phase & Progress**: Where the spec is in the workflow
2. **Completion Status**: Percentage complete for each phase
3. **Task Breakdown**: If tasks exist, show completed/remaining counts
4. **Boundary Context**: Upstream/downstream, out-of-boundary, and allowed dependency notes when available
5. **Revalidation Watchlist**: Downstream or adjacent work likely affected by changes to this spec
6. **Next Actions**: What needs to be done next
7. **Blockers**: Any issues preventing progress

**Format**: Clear, scannable format with emojis for status

## Safety & Fallback

### Error Scenarios

**Spec Not Found**:
- **Message**: "No spec found for `$ARGUMENTS`. Check available specs in `.kiro/specs/`"
- **Action**: List available spec directories

**Incomplete Spec**:
- **Warning**: Identify which files are missing
- **Suggested Action**: Point to next phase command

### List All Specs

To see all available specs:
- Run with no argument or use wildcard
- Shows all specs in `.kiro/specs/` with their status
