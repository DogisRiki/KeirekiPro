---
name: kiro-spec-init
description: Initialize a new specification with detailed project description, or reopen an existing spec for a new Issue
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
argument-hint: "<project-description | #issue-number [existing-feature]>"
---

# Spec Initialization

<instructions>
## Core Task
Generate a unique feature name from the project description ($ARGUMENTS) and initialize the specification structure. When given `#<N> <existing-feature>`, reopen that existing spec for Issue #N instead (see Mode Selection).

## Mode Selection
Decide the mode from $ARGUMENTS before doing anything else:
- **Update mode**: the 1st token is `#<N>` (a GitHub Issue number) AND the 2nd token is the name of an existing feature, i.e. `.kiro/specs/<2nd token>/spec.json` exists. Reopen that existing spec for Issue #N. Follow **Update Mode Steps** below and skip **Execution Steps**.
- **Missing feature (error)**: $ARGUMENTS is exactly `#<N>` plus one feature-name-shaped token (kebab-case, no spaces), but `.kiro/specs/<token>/spec.json` does not exist. The owner asked to update a spec that is not there: report the missing path as an error and write nothing. Do NOT fall back to creating a new spec.
- **New-spec mode**: anything else. This includes `#<N>` alone, and `#<N>` followed by a description whose 2nd token is not an existing feature name (treat the whole input as the conventional new-spec request). Follow **Execution Steps**.

## Execution Steps
0. **Resolve Issue Reference**: If $ARGUMENTS is (or contains) a GitHub Issue reference such as `#182`, fetch the issue with `gh issue view <number>` and construct the project description from its title and body before proceeding. The body is the owner's request. Do NOT read the comments (`--comments`): they are not the request, and anything taken from them would enter requirements.md, which spec-review and codex-review use as the judging basis.
1. **Check for Brief**: If `.kiro/specs/{feature-name}/brief.md` exists (created by `/kiro-discovery`), read it. The brief contains problem, approach, scope, and constraints from the discovery session. Use this to pre-fill the project description and skip clarification questions that the brief already answers.
2. **Clarify Intent**: The Project Description in requirements.md (the `## 元の要望` section of the template) must contain three elements: (a) who has the problem, (b) current situation, (c) what should change. If a brief.md or the referenced Issue covers these, skip to step 3. Otherwise, ask the user to clarify before proceeding. Ask as many questions as needed; do not fill in gaps with your own assumptions.
3. **Check Uniqueness**: Run `bash .claude/scripts/parallel/session.sh spec-names` as a single command. It prints, one per line, the spec directory names under `.kiro/specs/` of every working folder of this repository (the main folder and all worktrees), so names that other sessions are creating in other worktrees are included. Treat the feature name as a naming conflict if it appears in that list. If the command fails (non-zero exit code), report the exit code and its stderr to the owner and stop; do not fall back to checking only the local `.kiro/specs/`. If the directory already exists with only `brief.md` (no `spec.json`), use that directory (discovery created it).
4. **Create Directory**: `.kiro/specs/[feature-name]/` (skip if already exists from discovery)
5. **Initialize Files Using Templates**:
   - Use the templates in `.kiro/settings/templates/specs/`
   - Read `.kiro/settings/templates/specs/init.json`
   - Read `.kiro/settings/templates/specs/requirements-init.md` (headings: `# 要件`, `## 元の要望`, `## 要件`)
   - Keep every key of init.json as it is. Keep every heading and comment of requirements-init.md as it is. Change only the placeholders below
   - Replace placeholders:
     - `{{FEATURE_NAME}}` → generated feature name
     - `{{ISSUE_NUMBER}}` → the GitHub Issue number resolved in step 0, or `null` if no issue was referenced. This ties issue → spec → PR (`Refs:` / `Closes:`) together with one number
     - `{{TIMESTAMP}}` → current ISO 8601 timestamp
     - `{{PROJECT_DESCRIPTION}}` (under `## 元の要望`) → from brief.md if available, otherwise $ARGUMENTS
     - `ja` → language code (detect from user's input language, default to `en`)
   - Write `spec.json` and `requirements.md` to spec directory

## Update Mode Steps(更新の形)
Reopen the existing spec `.kiro/specs/<feature>/` for the new Issue #N. Steps 1-2 only read, and steps 2a-2d only check for other sessions and bring in the latest main; do not write any file of the spec until step 3 (or step 4 on the repair path). The only change to the working folder before then is the `git merge origin/main` of step 2d.

1. **Read the new Issue**: Run `gh issue view <N> --json number,title,body,state`. The body is the owner's request. Do NOT read the comments (no `comments` field, no `--comments`), for the same reason as step 0 of the Execution Steps. If the command fails or the Issue does not exist, report it and write nothing.
2. **Check the existing files** (read only):
   - The **anchor line** (the line that starts the section where requests are recorded) is the first line of `requirements.md` that starts with `## 元の要望` (the line may continue after these characters, e.g. `## 元の要望(Issue #474 の本文)`)
   - Read `requirements.md`. If it has no anchor line, report it as an error (name the expected anchor) and write nothing (there is no place to append the new request).
   - Read `spec.json`: if N equals `issue` or is already in `additional_issues`:
     - If `requirements.md` already has the heading `### 追加の要望(Issue #<N>)` (or N equals `issue`), write nothing. Report that the spec already covers #N, its current progress (`phase` and each stage's `generated` / `approved`), and the next command the owner should type.
     - If N is in `additional_issues` but `requirements.md` has no `### 追加の要望(Issue #<N>)` heading, the previous run wrote `spec.json` but failed to write `requirements.md`. Do NOT redo step 3 (the approvals are already revoked and recorded). Run steps 2a-2d, then redo only step 4, then step 5, and say that this run repaired the missing request in requirements.md.
   - Otherwise, run steps 2a-2d, then continue with step 3.

**Steps 2a-2d (before writing the spec)**: These steps check that no other working session is editing the same spec, and bring the latest main into this branch. Do NOT run them when step 2 decided to write nothing (the spec already covers #N). Run them before step 3 on the normal path, and before step 4 on the repair path. Until they finish, do not write any file of the spec.

2a. **Fetch**: Run `git fetch origin` as a standalone command. If it fails, tell the owner that it failed and show git's message, write nothing, and stop.
2b. **Check other sessions**: Run `bash .claude/scripts/parallel/session.sh check-spec <feature> --issue <N> --session <ID>` as a standalone command.
   - Take the session ID from the line `[parallel] このセッションのID: <ID>` that the SessionStart hook gave at the start of the conversation (the same way as `/start`). If that line is not found, omit `--session <ID>`.
   - If the exit code is not 0 (64: wrong arguments, 69: the check could not finish), tell the owner the exit code and its stderr, write nothing, and stop. Do not treat a failed check as "no conflicts".
   - On exit code 0, stdout is one line of JSON: `{"conflicts":[{"folder","session_id","started_at","last_seen","issue","reason"}, ...]}`. Each element is another working session that is editing this spec, oldest `started_at` first.
2c. **If `conflicts` is not empty, ask and stop**: Show the spec name (`<feature>`) and, for each element:
   - the working folder (`folder`)
   - the Issue number that session is working on (`issue`; say "unknown" when it is `null`)
   - when that session started (`started_at`) and when it was last used (`last_seen`), as readable local dates and times
   - what the session is doing, from `reason`: `changes` means that session has changes to this spec that are not in main yet; `starting` means that session has just started reopening this spec and has not written its changes yet

   For each element, ask the owner whether that session was abandoned (quit and will not be continued). Write the questions in the chat text, not with AskUserQuestion (its preamble and preview are not shown to the owner). Then stop and wait for the answers.
   - If the owner answers "abandoned" for every element, call `bash .claude/scripts/parallel/session.sh end <session_id>` once for each element, then redo step 2b. If `end` exits with a non-zero code, tell the owner the exit code and its stderr, write nothing, and stop.
   - If any answer is not "abandoned", write nothing and stop. Tell the owner to type the same command again after that session's PR is merged.
2d. **Bring in the latest main** (only when `conflicts` is empty): Run `git merge-base --is-ancestor origin/main HEAD`.
   - Exit code 0: this branch already contains `origin/main`. Go on to step 3 (or step 4 on the repair path).
   - Otherwise, run `git merge origin/main` as a standalone command (exactly this form, with no other options).
     - If the merge fails, check whether a merge is still in progress with `git rev-parse -q --verify MERGE_HEAD`. Only if that succeeds, run `git merge --abort`. Then tell the owner that main could not be brought in and why (git's message), write nothing, and stop.
     - If the merge succeeds, the spec files may have changed. Redo step 2 from the start and follow the path it decides. If it decides to write nothing, stop as step 2 says. Otherwise run steps 2a-2d again; this time step 2d finds that the branch already contains `origin/main` and does nothing more.

3. **Update `spec.json` (write this file first)**:
   - **Record the approvals being revoked**: For each stage in `approvals` (`requirements`, `design`, `tasks`) whose `approved` is `true`, append one element to `approval_history` (create the array if missing):
     ```json
     {
       "stage": "requirements",
       "approved_by": "<approvals.requirements.approved_by>",
       "approved_at": "<approvals.requirements.approved_at>",
       "issues": [<issue>, <each number in additional_issues>],
       "revoked_at": "<current ISO 8601 timestamp>",
       "revoked_for": "Issue #<N> のための更新"
     }
     ```
     - `issues` = the Issues the spec covered when it was approved: `issue` followed by the current `additional_issues` (before N is added)
     - `approval_history` is append-only. Never rewrite or remove an existing element
   - **Revoke all three stages**: Set `generated: false` and `approved: false` on `requirements`, `design`, and `tasks`, and delete the `approved_by` and `approved_at` keys from each
   - Set `phase` to `"initialized"` and `updated_at` to the current ISO 8601 timestamp
   - Append N to `additional_issues` (create the array if missing). Do NOT change `issue` (the original Issue)
   - Write `spec.json`. **If this write fails, stop and report the error. Do NOT edit `requirements.md`.**
4. **Append to `requirements.md`**:
   - **Demote the headings in the Issue body by two levels**: Issue bodies use `##` headings (file-issue format), which would otherwise end the anchor section (the section that starts at the anchor line chosen in step 2). In the body, change every Markdown heading line by two levels: `#` → `###`, `##` → `####`, `###` → `#####`, `####` or deeper → `######`. Lines inside code blocks (```` ``` ```` fences) are not headings; leave them. Apart from demoting headings, do NOT change the body (no rewording, no additions, no removals).
   - **Find the insertion point in the current file, before inserting**: the end of the anchor section is the line just before the first line after the anchor line (`## 元の要望...`) that starts with `## ` (exactly two `#` and a space, e.g. `## 要件`). If there is no such line, the section ends at the end of the file. Earlier `### 追加の要望(...)` blocks and their demoted headings (`####` or deeper) are part of the section, so a new block always goes after them.
   - Insert this block there (keep one blank line before it and before the next `## ` heading):
     ```markdown
     ### 追加の要望(Issue #<N>)
     <new Issue title>

     <new Issue body, with headings demoted by two levels>
     ```
   - Do not change anything else in requirements.md (existing requirements, their numbered items, and their numbers stay as they are).
5. **Show the next step**: Show `/kiro-spec-requirements <feature>` as the command the owner types next, and list which stage approvals were revoked (with their approver and date as recorded in `approval_history`).

## Important Constraints
- Do NOT generate requirements, design, or tasks. This skill only creates spec.json and requirements.md (or, in update mode, updates them).
- In update mode, do NOT create a new directory or a new feature name.
- In update mode, do NOT write any file of the spec until steps 2a-2d have finished. If another working session is editing the spec, or the check or the merge of main fails, stop without writing.
</instructions>

## Output Description
Provide output in the language specified in `spec.json` with the following structure:

1. **Generated Feature Name**: `feature-name` format with 1-2 sentence rationale
2. **Project Summary**: Brief summary (1 sentence)
3. **Created Files**: Bullet list with full paths
4. **Next Step**: Command block showing `/kiro-spec-requirements <feature-name>`

In update mode, use this structure instead:

1. **Updated Spec**: `feature-name` and the added Issue (`#N` and its title)
2. **Revoked Approvals**: Each revoked stage with its approver and approval date (as written to `approval_history`), or "none" if no stage was approved
3. **Updated Files**: Bullet list of `spec.json` and `requirements.md` with full paths
4. **Next Step**: Command block showing `/kiro-spec-requirements <feature-name>`

If #N was already in the spec (Update Mode Step 2), report only that fact, the current progress, and the next command; say that nothing was written. If Step 2 found the requirements.md block missing and only Step 4 was redone, say so and list only `requirements.md` as updated.

If update mode stopped in steps 2a-2d (the fetch, the check, or the merge of main failed, or another working session is editing the spec), use none of the structures above. Report why it stopped, as those steps say, and that nothing was written. When it stopped to ask about other sessions, end with the questions.

**Format Requirements**:
- Use Markdown headings (##, ###)
- Wrap commands in code blocks
- Keep total output concise (under 250 words)
- Use clear, professional language per `spec.json.language`

## Safety & Fallback
- **Ambiguous Feature Name**: If feature name generation is unclear, propose 2-3 options and ask user to select
- **Template Missing**: If template files don't exist in `.kiro/settings/templates/specs/`, report error with specific missing file path and suggest checking repository setup
- **Directory Conflict**: If feature name already exists (appears in the `session.sh spec-names` list of Execution Step 3), append numeric suffix (e.g., `feature-name-2`) and notify user of automatic conflict resolution. New-spec mode only; this is NOT used in update mode (an existing feature name there means "update this spec")
- **Missing Feature in Update Mode**: If `.kiro/specs/<feature>/spec.json` does not exist, report the error with the path and write nothing
- **Write Failure**: Report error with specific path and suggest checking permissions or disk space
