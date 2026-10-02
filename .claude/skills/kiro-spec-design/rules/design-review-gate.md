# Design Review Gate

Before writing `design.md`, review the draft design and repair local issues until the design passes or a true spec gap is discovered.

`spec_format` が2の spec では、この点検の項目が名前で指す節と表を、`.kiro/settings/rules/spec-writing.md` の新旧の見出しと目印の対応表の新しい名前で読む。

- `Boundary Commitments` → `## 作るものと作らないもの` の `### 作るもの`
- `Out of Boundary` → `## 作るものと作らないもの` の `### 作らないもの`
- `Allowed Dependencies` → `## 使う既存の仕組み`
- `Revalidation Triggers` → `## 設計を見直すきっかけ`
- `File Structure Plan` → `## ファイルの構成`
- design traceability mapping / requirements traceability → 各部品の「対応する要件」の行(新しい書き方の design.md には要件との対応の表が無い)

The checks themselves are the same for both formats. Specs without `spec_format` keep the names used below.

## Requirements Coverage Review

- Every numeric requirement ID from `requirements.md` must appear in the design traceability mapping (when `spec_format` is `2`: in the 「対応する要件」 line of at least one component) and be backed by one or more concrete components, contracts, flows, data models, or operational decisions.
- Every requirement that introduces an external dependency, integration point, runtime prerequisite, migration concern, observability need, security constraint, or performance target must be reflected explicitly in `design.md`.
- If coverage is missing because the design draft is incomplete, repair the draft and review again.
- If coverage cannot be completed cleanly because requirements are ambiguous, contradictory, or underspecified, stop and return to the requirements phase instead of inventing design detail.

## Architecture Readiness Review

- Component boundaries must be explicit enough that implementation tasks can be assigned without guessing ownership.
- Interfaces, contracts, state transitions, and integration boundaries must be concrete enough for implementation and validation.
- Build-vs-adopt decisions that materially affect architecture must be captured in `design.md`, with deeper investigation left in `research.md` when present.
- Runtime prerequisites, migrations, rollout constraints, validation hooks, and failure modes must be surfaced when they materially affect implementation order or risk.

## Boundary Readiness Review

- The design must explicitly state what this spec owns.
- The design must explicitly state what is out of boundary.
- Allowed dependencies must be concrete enough that reviewers can detect boundary violations later.
- If data, behavior, or integration responsibility appears shared across multiple areas without a clear seam, stop and repair the design.
- If downstream assumptions are embedded in upstream components "for convenience," stop and repair the design.
- If the boundary cannot be explained in a few direct bullets, it is probably still too vague for task generation.
- If the design reveals multiple independent responsibility seams that could move separately, stop and split the spec or return to roadmap discovery instead of forcing them into one spec.

## Executability Review

- The design must be implementable as a sequence of bounded tasks without hidden prerequisites.
- Parallel-safe boundaries should be visible where the architecture intends concurrent implementation.
- Avoid speculative abstraction: remove components, adapters, or interfaces that exist only for hypothetical future scope.
- If a section is too vague for tasks to reference directly, rewrite it before finalizing the design.

## Mechanical Checks

Before applying judgment, verify these mechanically:
- **Requirements traceability**: Extract all numeric requirement IDs from `requirements.md`. Scan the design draft for each ID. Report any IDs not found in the design. When `spec_format` is `2`, scan the 「対応する要件」 lines of the components.
- **Boundary section populated**: `Boundary Commitments`, `Out of Boundary`, `Allowed Dependencies`, and `Revalidation Triggers` must not be empty or placeholder-only. `spec_format` が2の spec では、この点検を `### 作るもの`、`### 作らないもの`、`## 使う既存の仕組み`、`## 設計を見直すきっかけ` について行う。ただし、その spec に当てはまらない境界の節(たとえば頼る既存の仕組みが無いときの `## 使う既存の仕組み`)は、空のまま残さず見出しごと省いてよい。省いた節は点検で欠けとして扱わない。書いた節が空や仮の文だけなら、欠けとして扱う。
- **File Structure Plan populated** (`spec_format` が2の spec では `## ファイルの構成` を点検する): The File Structure Plan section must contain concrete file paths (not just "TBD" or empty). Scan for placeholder text in that section.
- **Boundary ↔ file structure alignment**: The File Structure Plan must reflect the stated responsibility boundary. If files imply broader ownership than the boundary section claims, report a mismatch.
- **No orphan components**: Every component mentioned in the design must appear in the File Structure Plan with a file path. Scan for component names that have no corresponding file entry.

## Review Loop

- Run mechanical checks first, then judgment-based review.
- If issues are local to the draft, repair the draft and re-run the review gate.
- Keep the loop bounded: no more than 2 review-and-repair passes before escalating a real spec gap.
- Write `design.md` only after the review gate passes.
