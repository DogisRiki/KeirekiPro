-- 経歴書の操作が読み書きする問い合わせ。
-- Java 版の ResumeMapper.xml と ResumeQueryMapper.xml と、同じ表の同じ列を読み書きする。
-- 書くときは、操作ごとに、変わる行だけを書く(design の「読み書き」の節)。書く問い合わせは、呼ぶ側が1つのトランザクションの中で呼ぶ。
-- 日時と日付は、呼ぶ側が日本の時刻と日本の日付で渡す。
-- 6つの欄の項目の並べ方は、Java 版と同じく指定しない。呼ぶ側が Java 版と同じ規則で並べる。
-- 項目を書き換えて消す問い合わせは、項目の ID と経歴書の ID を組で指定し、別の経歴書の項目を書き換えない。

-- 経歴書

-- 利用者の経歴書を、作成の日時の順に読む。Java 版の selectAllByUserId と同じ並べ方である。
-- name: ListResumesByUserID :many
SELECT
    id,
    user_id,
    name,
    date,
    last_name,
    first_name,
    created_at,
    updated_at
FROM
    resumes
WHERE
    user_id = $1
ORDER BY
    created_at;

-- 利用者の経歴書を1件読む。ほかの利用者の経歴書は読まない。
-- name: GetResume :one
SELECT
    id,
    user_id,
    name,
    date,
    last_name,
    first_name,
    created_at,
    updated_at
FROM
    resumes
WHERE
    id = $1
    AND user_id = $2;

-- 利用者の経歴書を1件読み、トランザクションを確定するまで、ほかのトランザクションが書き換えないように行を固定する。
-- name: GetResumeForUpdate :one
SELECT
    id,
    user_id,
    name,
    date,
    last_name,
    first_name,
    created_at,
    updated_at
FROM
    resumes
WHERE
    id = $1
    AND user_id = $2
FOR UPDATE;

-- name: CountResumesByUserID :one
SELECT
    COUNT(*)
FROM
    resumes
WHERE
    user_id = $1;

-- 利用者が同じ名前の経歴書を持っているかを読む。Java 版の ResumeNameDuplicationCheckService と同じく、名前が完全に同じものを探す。
-- name: ExistsResumeName :one
SELECT
    EXISTS (
        SELECT
            1
        FROM
            resumes
        WHERE
            user_id = $1
            AND name = $2
    );

-- name: InsertResume :exec
INSERT INTO resumes (
    id,
    user_id,
    name,
    date,
    last_name,
    first_name,
    created_at,
    updated_at
)
VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8
);

-- name: UpdateResumeBasic :exec
UPDATE
    resumes
SET
    name = $2,
    date = $3,
    last_name = $4,
    first_name = $5,
    updated_at = $6
WHERE
    id = $1;

-- name: UpdateResumeUpdatedAt :exec
UPDATE
    resumes
SET
    updated_at = $2
WHERE
    id = $1;

-- 経歴書を消す8つの問い合わせ。呼ぶ側は、子の表の行を消してから経歴書の行を消すので、このファイルに並べた順に呼ぶ。

-- name: DeleteResumeProjectTechStacks :exec
DELETE FROM project_tech_stacks
WHERE project_id IN (SELECT id FROM projects WHERE resume_id = $1);

-- name: DeleteResumeProjects :exec
DELETE FROM projects
WHERE resume_id = $1;

-- name: DeleteResumeCareers :exec
DELETE FROM careers
WHERE resume_id = $1;

-- name: DeleteResumeCertifications :exec
DELETE FROM certifications
WHERE resume_id = $1;

-- name: DeleteResumePortfolios :exec
DELETE FROM portfolios
WHERE resume_id = $1;

-- name: DeleteResumeSnsPlatforms :exec
DELETE FROM sns_platforms
WHERE resume_id = $1;

-- name: DeleteResumeSelfPromotions :exec
DELETE FROM self_promotions
WHERE resume_id = $1;

-- name: DeleteResume :exec
DELETE FROM resumes
WHERE id = $1;

-- 職歴

-- name: ListCareers :many
SELECT
    id,
    company_name,
    start_date,
    end_date,
    is_active
FROM
    careers
WHERE
    resume_id = $1;

-- name: CountCareers :one
SELECT
    COUNT(*)
FROM
    careers
WHERE
    resume_id = $1;

-- name: InsertCareer :exec
INSERT INTO careers (
    id,
    resume_id,
    company_name,
    start_date,
    end_date,
    is_active
)
VALUES (
    $1, $2, $3, $4, $5, $6
);

-- name: UpdateCareer :execrows
UPDATE
    careers
SET
    company_name = $3,
    start_date = $4,
    end_date = $5,
    is_active = $6
WHERE
    id = $1
    AND resume_id = $2;

-- name: DeleteCareer :execrows
DELETE FROM careers
WHERE
    id = $1
    AND resume_id = $2;

-- プロジェクト
-- 技術スタックの列は TEXT[] で、要素に NULL を含むことがある。sqlc は TEXT[] の列を Go の []string にするが、[]string は
-- 要素の NULL を読めない。そこで、技術スタックは JSON を通して読み書きする。読むときは to_jsonb で行を JSON にし、
-- 書くときは jsonb_populate_record で JSON を行にする。JSON の鍵は表の列の名前である。呼ぶ側は、JSON の配列の
-- 要素の null を Go の nil として読み書きする。技術スタックの行が無いプロジェクトでは、tech_stacks は NULL になる。

-- name: ListProjects :many
SELECT
    p.id,
    p.company_name,
    p.start_date,
    p.end_date,
    p.is_active,
    p.name,
    p.overview,
    p.team_comp,
    p.role,
    p.achievement,
    p.requirements,
    p.basic_design,
    p.detailed_design,
    p.implementation,
    p.integration_test,
    p.system_test,
    p.maintenance,
    to_jsonb(pts) AS tech_stacks
FROM
    projects p
    LEFT JOIN project_tech_stacks pts ON pts.project_id = p.id
WHERE
    p.resume_id = $1;

-- name: CountProjects :one
SELECT
    COUNT(*)
FROM
    projects
WHERE
    resume_id = $1;

-- name: InsertProject :exec
INSERT INTO projects (
    id,
    resume_id,
    company_name,
    start_date,
    end_date,
    is_active,
    name,
    overview,
    team_comp,
    role,
    achievement,
    requirements,
    basic_design,
    detailed_design,
    implementation,
    integration_test,
    system_test,
    maintenance
)
VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18
);

-- name: InsertProjectTechStacks :exec
INSERT INTO project_tech_stacks (
    project_id,
    frontend_languages,
    frontend_framework,
    frontend_libraries,
    frontend_build_tool,
    frontend_package_manager,
    frontend_linters,
    frontend_formatters,
    frontend_testing_tools,
    backend_languages,
    backend_framework,
    backend_libraries,
    backend_build_tool,
    backend_package_manager,
    backend_linters,
    backend_formatters,
    backend_testing_tools,
    orm_tools,
    auth,
    clouds,
    operating_system,
    containers,
    database,
    web_server,
    ci_cd_tool,
    iac_tools,
    monitoring_tools,
    logging_tools,
    source_control,
    project_management,
    communication_tool,
    documentation_tools,
    api_development_tools,
    design_tools,
    editor,
    development_environment
)
SELECT
    sqlc.arg(project_id)::uuid,
    r.frontend_languages,
    r.frontend_framework,
    r.frontend_libraries,
    r.frontend_build_tool,
    r.frontend_package_manager,
    r.frontend_linters,
    r.frontend_formatters,
    r.frontend_testing_tools,
    r.backend_languages,
    r.backend_framework,
    r.backend_libraries,
    r.backend_build_tool,
    r.backend_package_manager,
    r.backend_linters,
    r.backend_formatters,
    r.backend_testing_tools,
    r.orm_tools,
    r.auth,
    r.clouds,
    r.operating_system,
    r.containers,
    r.database,
    r.web_server,
    r.ci_cd_tool,
    r.iac_tools,
    r.monitoring_tools,
    r.logging_tools,
    r.source_control,
    r.project_management,
    r.communication_tool,
    r.documentation_tools,
    r.api_development_tools,
    r.design_tools,
    r.editor,
    r.development_environment
FROM
    jsonb_populate_record(NULL::project_tech_stacks, sqlc.arg(tech_stacks)::jsonb) r;

-- name: UpdateProject :execrows
UPDATE
    projects
SET
    company_name = $3,
    start_date = $4,
    end_date = $5,
    is_active = $6,
    name = $7,
    overview = $8,
    team_comp = $9,
    role = $10,
    achievement = $11,
    requirements = $12,
    basic_design = $13,
    detailed_design = $14,
    implementation = $15,
    integration_test = $16,
    system_test = $17,
    maintenance = $18
WHERE
    id = $1
    AND resume_id = $2;

-- Java 版と同じく、技術スタックの行が無ければ何も書かない。
-- name: UpdateProjectTechStacks :exec
UPDATE
    project_tech_stacks t
SET
    frontend_languages = r.frontend_languages,
    frontend_framework = r.frontend_framework,
    frontend_libraries = r.frontend_libraries,
    frontend_build_tool = r.frontend_build_tool,
    frontend_package_manager = r.frontend_package_manager,
    frontend_linters = r.frontend_linters,
    frontend_formatters = r.frontend_formatters,
    frontend_testing_tools = r.frontend_testing_tools,
    backend_languages = r.backend_languages,
    backend_framework = r.backend_framework,
    backend_libraries = r.backend_libraries,
    backend_build_tool = r.backend_build_tool,
    backend_package_manager = r.backend_package_manager,
    backend_linters = r.backend_linters,
    backend_formatters = r.backend_formatters,
    backend_testing_tools = r.backend_testing_tools,
    orm_tools = r.orm_tools,
    auth = r.auth,
    clouds = r.clouds,
    operating_system = r.operating_system,
    containers = r.containers,
    database = r.database,
    web_server = r.web_server,
    ci_cd_tool = r.ci_cd_tool,
    iac_tools = r.iac_tools,
    monitoring_tools = r.monitoring_tools,
    logging_tools = r.logging_tools,
    source_control = r.source_control,
    project_management = r.project_management,
    communication_tool = r.communication_tool,
    documentation_tools = r.documentation_tools,
    api_development_tools = r.api_development_tools,
    design_tools = r.design_tools,
    editor = r.editor,
    development_environment = r.development_environment
FROM
    jsonb_populate_record(NULL::project_tech_stacks, sqlc.arg(tech_stacks)::jsonb) r
WHERE
    t.project_id = sqlc.arg(project_id)::uuid
    AND t.project_id IN (SELECT id FROM projects WHERE resume_id = sqlc.arg(resume_id)::uuid);

-- プロジェクトを消すときは、技術スタックの行を消してから、プロジェクトの行を消す。
-- name: DeleteProjectTechStacks :exec
DELETE FROM project_tech_stacks
WHERE project_id = sqlc.arg(project_id)::uuid
    AND project_id IN (SELECT id FROM projects WHERE resume_id = sqlc.arg(resume_id)::uuid);

-- name: DeleteProject :execrows
DELETE FROM projects
WHERE
    id = $1
    AND resume_id = $2;

-- 資格

-- name: ListCertifications :many
SELECT
    id,
    name,
    date
FROM
    certifications
WHERE
    resume_id = $1;

-- name: CountCertifications :one
SELECT
    COUNT(*)
FROM
    certifications
WHERE
    resume_id = $1;

-- name: InsertCertification :exec
INSERT INTO certifications (
    id,
    resume_id,
    name,
    date
)
VALUES (
    $1, $2, $3, $4
);

-- name: UpdateCertification :execrows
UPDATE
    certifications
SET
    name = $3,
    date = $4
WHERE
    id = $1
    AND resume_id = $2;

-- name: DeleteCertification :execrows
DELETE FROM certifications
WHERE
    id = $1
    AND resume_id = $2;

-- ポートフォリオ

-- name: ListPortfolios :many
SELECT
    id,
    name,
    overview,
    tech_stack,
    link
FROM
    portfolios
WHERE
    resume_id = $1;

-- name: CountPortfolios :one
SELECT
    COUNT(*)
FROM
    portfolios
WHERE
    resume_id = $1;

-- name: InsertPortfolio :exec
INSERT INTO portfolios (
    id,
    resume_id,
    name,
    overview,
    tech_stack,
    link
)
VALUES (
    $1, $2, $3, $4, $5, $6
);

-- name: UpdatePortfolio :execrows
UPDATE
    portfolios
SET
    name = $3,
    overview = $4,
    tech_stack = $5,
    link = $6
WHERE
    id = $1
    AND resume_id = $2;

-- name: DeletePortfolio :execrows
DELETE FROM portfolios
WHERE
    id = $1
    AND resume_id = $2;

-- SNS

-- name: ListSnsPlatforms :many
SELECT
    id,
    name,
    link
FROM
    sns_platforms
WHERE
    resume_id = $1;

-- name: CountSnsPlatforms :one
SELECT
    COUNT(*)
FROM
    sns_platforms
WHERE
    resume_id = $1;

-- name: InsertSnsPlatform :exec
INSERT INTO sns_platforms (
    id,
    resume_id,
    name,
    link
)
VALUES (
    $1, $2, $3, $4
);

-- name: UpdateSnsPlatform :execrows
UPDATE
    sns_platforms
SET
    name = $3,
    link = $4
WHERE
    id = $1
    AND resume_id = $2;

-- name: DeleteSnsPlatform :execrows
DELETE FROM sns_platforms
WHERE
    id = $1
    AND resume_id = $2;

-- 自己PR

-- name: ListSelfPromotions :many
SELECT
    id,
    title,
    content
FROM
    self_promotions
WHERE
    resume_id = $1;

-- name: CountSelfPromotions :one
SELECT
    COUNT(*)
FROM
    self_promotions
WHERE
    resume_id = $1;

-- name: InsertSelfPromotion :exec
INSERT INTO self_promotions (
    id,
    resume_id,
    title,
    content
)
VALUES (
    $1, $2, $3, $4
);

-- name: UpdateSelfPromotion :execrows
UPDATE
    self_promotions
SET
    title = $3,
    content = $4
WHERE
    id = $1
    AND resume_id = $2;

-- name: DeleteSelfPromotion :execrows
DELETE FROM self_promotions
WHERE
    id = $1
    AND resume_id = $2;
