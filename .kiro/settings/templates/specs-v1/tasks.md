# Implementation Plan

## Task Format Template

Use whichever pattern fits the work breakdown:

### Major task only
- [ ] {{NUMBER}}. {{TASK_DESCRIPTION}}{{PARALLEL_MARK}}
  - {{DETAIL_ITEM_1}} *(Include details only when needed. If the task stands alone, omit bullet items.)*
  - _Requirements: {{REQUIREMENT_IDS}}_

### Major + Sub-task structure
- [ ] {{MAJOR_NUMBER}}. {{MAJOR_TASK_SUMMARY}}
- [ ] {{MAJOR_NUMBER}}.{{SUB_NUMBER}} {{SUB_TASK_DESCRIPTION}}{{SUB_PARALLEL_MARK}}
  - {{DETAIL_ITEM_1}}
  - {{DETAIL_ITEM_2}}
  - {{OBSERVABLE_COMPLETION_ITEM}} *(At least one detail item should state the observable completion condition for this task.)*
  - _Requirements: {{REQUIREMENT_IDS}}_ *(IDs only; do not add descriptions or parentheses.)*
  - _Boundary: {{COMPONENT_NAMES}}_ *(Only for (P) tasks. Omit when scope is obvious.)*
  - _Depends: {{TASK_IDS}}_ *(Only for non-obvious cross-boundary dependencies. Most tasks omit this.)*

> **Parallel marker**: Append ` (P)` only to tasks that can be executed in parallel. Omit the marker when running in `--sequential` mode.
>
> **Optional test coverage**: When a sub-task is deferrable test work tied to acceptance criteria, mark the checkbox as `- [ ]*` and explain the referenced requirements in the detail bullets.

## KeirekiPro 完了条件(全タスク共通)

各タスクの完了条件には、上記フォーマットに加えて必ず次を含める:

1. **acceptance criteria の引用とテスト対応付け**: タスクが実現する requirements.md の
   acceptance criteria を引用し、それを検証するテスト(ファイル名・テスト名)との対応を
   detail item に記載する。テストが無い受け入れ基準を残さない
2. **verify の実行**: タスクの変更領域に応じた verify Skill
   (`/verify-frontend` / `/verify-backend` / `/verify-terraform`)が全てPASSしていること
3. **ゴールハック禁止**: テストskip・アサーション削除・カバレッジ/lint除外の追加で
   完了条件を満たさない(escape-hatch CIが機械検知する)
4. 新規テストは対象コードを一時的に壊して赤くなることを確認してから戻す
