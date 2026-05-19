# AGENTS.md

## Project overview

KeirekiPro is a full-stack web application for engineers to create and manage resumes and career-history documents.

The application supports detailed project and skill records, PDF/Markdown export, profile images, authentication, backup/restore, and infrastructure managed on AWS.

## Repository map

- `backend` - Spring Boot backend API
- `frontend` - React/Vite frontend SPA
- `terraform` - AWS infrastructure as code
- `docker` and `compose.yaml` - Docker and devcontainer configuration
- `.github/workflows` - GitHub Actions CI/CD workflows
- `doc` - architecture and project documentation

Agents may inspect the whole repository to understand context, but changes must stay limited to the requested task scope.

## Core rules

- Do not modify unrelated files.
- Do not remove existing comments unless the task explicitly requires it.
- Do not rewrite files only for style.
- Do not introduce new libraries, frameworks, tools, or runtime dependencies unless explicitly requested.
- Do not change public behavior, API contracts, database schema, infrastructure settings, CI/CD behavior, or deployment behavior unless explicitly requested.
- Do not commit, push, merge, deploy, or run destructive commands unless explicitly requested.
- Verify the final diff before reporting completion.

## Git

Run Git commands from the repository root.

```bash
git status
git diff --stat
git diff
```

Before reporting completion, confirm that only intended files changed.

## Backend

The backend uses Java 21, Spring Boot, Gradle, MyBatis, Flyway, Spring Security, JWT, JUnit 5, Mockito, AssertJ, Testcontainers, Spotless, Checkstyle, JaCoCo, and SpotBugs.

In a backend devcontainer, the workspace is already the backend working directory. Do not run `cd backend` unless the current shell is at the repository root.

Backend quality gates include formatting, Checkstyle, tests, JaCoCo, and SpotBugs.

Before completing backend changes, run:

```bash
./gradlew spotlessApply
./gradlew check
```

Use narrower commands only while diagnosing failures:

```bash
./gradlew test
./gradlew spotlessCheck
./gradlew checkstyleMain checkstyleTest
./gradlew spotbugsMain spotbugsTest
./gradlew jacocoTestReport
```

Backend design facts:

- The backend follows Onion Architecture, DDD, and CQRS.
- Domain logic belongs in `domain`.
- Use case orchestration belongs in `usecase`.
- Query interfaces belong in `usecase/query`; query implementations belong in `infrastructure/query`.
- Framework, database, storage, and external service concerns belong in `presentation` or `infrastructure`.
- Controllers use one public `handle()` method per class.
- Use cases use one public `execute()` method per class.
- Domain model methods may return updated instances. Do not ignore those return values.
- SpotBugs warnings should be fixed in code when they indicate real correctness or design issues. Use exclusions only for confirmed tool/framework noise.

## Frontend

The frontend uses TypeScript, React 18, Vite, React Router v7, MUI, Zustand, TanStack Query, ESLint, Prettier, Vitest, and Testing Library.

In a frontend devcontainer, the workspace is already the frontend working directory. Do not run `cd frontend` unless the current shell is at the repository root.

Before completing frontend changes, run:

```bash
npm run format
npm run lint
npm test
npm run coverage
```

Run a production build when the task affects build output, routing, environment variables, or deployment behavior:

```bash
npm run build
```

Frontend design facts:

- The frontend follows a feature-based structure based on Bulletproof React.
- Feature code belongs in `src/features/{feature-name}`.
- Shared UI belongs in `src/components`.
- Shared hooks belong in `src/hooks`.
- Global state belongs in `src/stores`.
- API access and query logic should follow existing feature conventions.
- Formatting is checked by Prettier.
- Linting is checked by ESLint.
- Tests and coverage are checked by Vitest.

## Terraform

In a terraform devcontainer, the workspace is already the terraform working directory. Do not run `cd terraform` unless the current shell is at the repository root.

Before completing Terraform changes, run the relevant checks:

```bash
terraform fmt -check -recursive
terraform validate
tflint --recursive
checkov -d .
```

Terraform rules:

- Do not modify production-impacting infrastructure unless explicitly requested.
- Do not change resource names, state-sensitive identifiers, backend settings, or provider settings unless explicitly requested.
- Do not commit secrets, credentials, `.tfvars` containing secrets, state files, or generated plan files.
- Report any resource replacement risk.

## Docker and devcontainers

Docker and devcontainer files are under:

```text
docker
compose.yaml
```

Rules:

- Backend, frontend, and terraform containers must be able to inspect the repository root.
- Each container should keep its primary working directory aligned with its task area.
- Do not change container users, working directories, mounted paths, service names, or installed packages unless explicitly requested.

## CI/CD

GitHub Actions workflows are under:

```text
.github/workflows
```

CI/CD facts:

- Pull requests run checks only.
- Deploy workflows run after the relevant CI job succeeds on `main`, or by explicit manual dispatch.
- Backend CI runs `./gradlew check`.
- Frontend CI runs format, lint, test, and coverage.
- Backend deploy builds and pushes a Docker image to ECR and deploys to ECS Fargate.
- Frontend deploy builds the SPA, syncs to S3, and invalidates CloudFront.

CI/CD rules:

- Do not change AWS roles, regions, service names, S3 buckets, CloudFront distributions, ECR repositories, ECS services, or deployment triggers unless explicitly requested.
- Do not make deploy workflows run directly and independently on `push` if that bypasses CI success.

## Documentation

Documentation is under:

```text
doc
```

Rules:

- Update documentation only when the requested change affects documented behavior, setup, architecture, commands, or operations.
- Do not rewrite documentation broadly when a targeted update is sufficient.
- Prefer pointers to authoritative files over copied code snippets.

## Hooks and skills

No repository-level hooks, Claude Code hooks, custom skills, or subagents are required at this time.

Quality gates are represented by project commands and CI workflows. Agents should run the relevant commands directly instead of relying on tool-specific automation.

Reconsider hooks or skills only if the same manual agent workflow is repeated frequently and cannot be represented clearly by project commands or CI.

## Completion report

When reporting completion, use this format:

```text
Changed files:
- ...

Commands:
- ... -> PASS
- ... -> FAIL

Notes:
- ...
```

If a command fails and the failure is within scope, fix it. If it is outside scope, report the exact command and relevant output.
