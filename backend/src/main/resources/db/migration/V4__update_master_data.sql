-- =========================================================
-- V4: マスタデータ整備
--   - スペルミス・表記ゆれの修正
--   - 比較的利用頻度の高い技術スタック／資格／SNSプラットフォームの追加
-- =========================================================

-- =========================================================
-- 表記ゆれ・スペルミス修正
-- =========================================================

-- Bun は固有名詞として先頭大文字に統一
UPDATE tech_stack_mst
SET name = 'Bun'
WHERE id = 54
AND name = 'bun'
AND category_code = 'FRONTEND_PACKAGE_MANAGER';

-- typescript-eslint の公式表記に統一
UPDATE tech_stack_mst
SET name = 'typescript-eslint'
WHERE id = 63
AND name = 'TypeScript ESLint'
AND category_code = 'FRONTEND_LINTER';

-- Go の ORM は GORM 表記に統一
UPDATE tech_stack_mst
SET name = 'GORM'
WHERE id = 237
AND name = 'Gorm'
AND category_code = 'BACKEND_LIBRARY';

UPDATE tech_stack_mst
SET name = 'GORM'
WHERE id = 357
AND name = 'GORM'
AND category_code = 'BACKEND_ORM_TOOL';

-- Google Cloud 認定資格の正式名称寄せ
UPDATE certification_mst
SET name = 'Associate Cloud Engineer'
WHERE id = 303
AND name = 'Cloud Engineer';

-- Microsoft 365 現行ブランド名に統一
UPDATE tech_stack_mst
SET name = 'Microsoft 365'
WHERE id = 634
AND name = 'Microsoft Office 365'
AND category_code = 'TOOLS_DOCUMENTATION';

-- =========================================================
-- 技術スタックマスタ追加
-- =========================================================

INSERT INTO tech_stack_mst (id, name, category_code)
SELECT v.id, v.name, v.category_code
FROM (VALUES
    ----------------------------------------------------------------
    -- frontend: frameworks
    ----------------------------------------------------------------
    (18,  'Remix',                 'FRONTEND_FRAMEWORK'),
    (19,  'Astro',                 'FRONTEND_FRAMEWORK'),

    ----------------------------------------------------------------
    -- frontend: libraries
    ----------------------------------------------------------------
    (37,  'Emotion',               'FRONTEND_LIBRARY'),
    (38,  'Styled Components',     'FRONTEND_LIBRARY'),
    (39,  'React Native',          'FRONTEND_LIBRARY'),
    (40,  'jQuery',                'FRONTEND_LIBRARY'),

    ----------------------------------------------------------------
    -- frontend: build tools
    ----------------------------------------------------------------
    (45,  'esbuild',               'FRONTEND_BUILD_TOOL'),
    (46,  'Turbopack',             'FRONTEND_BUILD_TOOL'),
    (47,  'Rspack',                'FRONTEND_BUILD_TOOL'),

    ----------------------------------------------------------------
    -- frontend: linters / formatters / testing tools
    ----------------------------------------------------------------
    (64,  'Biome',                 'FRONTEND_LINTER'),
    (87,  'Mocha',                 'FRONTEND_TESTING_TOOL'),
    (88,  'happy-dom',             'FRONTEND_TESTING_TOOL'),
    (89,  'Husky',                 'FRONTEND_TESTING_TOOL'),
    (90,  'lint-staged',           'FRONTEND_TESTING_TOOL'),

    ----------------------------------------------------------------
    -- backend: languages
    ----------------------------------------------------------------
    (135, 'ShellScript',           'BACKEND_LANGUAGE'),
    (136, 'JSP',                   'BACKEND_LANGUAGE'),
    (137, 'VBScript',              'BACKEND_LANGUAGE'),

    ----------------------------------------------------------------
    -- backend: frameworks
    ----------------------------------------------------------------
    (218, 'Micronaut',             'BACKEND_FRAMEWORK'),
    (219, 'Quarkus',               'BACKEND_FRAMEWORK'),
    (220, 'Spring Cloud',          'BACKEND_FRAMEWORK'),

    ----------------------------------------------------------------
    -- backend: libraries
    ----------------------------------------------------------------
    (242, 'Apache Commons',        'BACKEND_LIBRARY'),
    (243, 'Apache PDFBox',         'BACKEND_LIBRARY'),
    (244, 'ICU4J',                 'BACKEND_LIBRARY'),
    (245, 'Flyway',                'BACKEND_LIBRARY'),
    (246, 'AspectJ',               'BACKEND_LIBRARY'),
    (247, 'FreeMarker',            'BACKEND_LIBRARY'),
    (248, 'boto3',                 'BACKEND_LIBRARY'),
    (249, 'Pydantic',              'BACKEND_LIBRARY'),
    (250, 'OpenCV',                'BACKEND_LIBRARY'),

    ----------------------------------------------------------------
    -- backend: package managers / linters / formatters / testing tools
    ----------------------------------------------------------------
    (271, 'uv',                    'BACKEND_PACKAGE_MANAGER'),
    (272, 'Maven Wrapper',         'BACKEND_PACKAGE_MANAGER'),
    (300, 'pre-commit',            'BACKEND_LINTER'),
    (312, 'Spotless',              'BACKEND_FORMATTER'),
    (338, 'JUnit 5',               'BACKEND_TESTING_TOOL'),
    (339, 'Testcontainers',        'BACKEND_TESTING_TOOL'),
    (340, 'pytest-asyncio',        'BACKEND_TESTING_TOOL'),

    ----------------------------------------------------------------
    -- backend: auth
    ----------------------------------------------------------------
    (374, 'Spring Authorization Server', 'BACKEND_AUTH'),
    (375, 'Firebase Authentication',     'BACKEND_AUTH'),
    (376, 'Amazon Cognito',              'BACKEND_AUTH'),
    (377, 'OAuth 2.0',                   'BACKEND_AUTH'),
    (378, 'OpenID Connect',              'BACKEND_AUTH'),

    ----------------------------------------------------------------
    -- infrastructure: clouds
    ----------------------------------------------------------------
    (412, 'Firebase',              'INFRA_CLOUD'),
    (413, 'Cloudflare',            'INFRA_CLOUD'),
    (414, 'Supabase',              'INFRA_CLOUD'),

    ----------------------------------------------------------------
    -- infrastructure: OS
    ----------------------------------------------------------------
    (426, 'Oracle Linux',          'INFRA_OS'),
    (427, 'CentOS',                'INFRA_OS'),
    (428, 'AlmaLinux',             'INFRA_OS'),
    (429, 'Rocky Linux',           'INFRA_OS'),

    ----------------------------------------------------------------
    -- infrastructure: containers
    ----------------------------------------------------------------
    (437, 'ECS',                   'INFRA_CONTAINER'),
    (438, 'EKS',                   'INFRA_CONTAINER'),
    (439, 'Fargate',               'INFRA_CONTAINER'),
    (440, 'Docker Swarm',          'INFRA_CONTAINER'),

    ----------------------------------------------------------------
    -- infrastructure: databases
    ----------------------------------------------------------------
    (451, 'Aurora MySQL',          'INFRA_DATABASE'),
    (452, 'Aurora PostgreSQL',     'INFRA_DATABASE'),
    (453, 'Cosmos DB',             'INFRA_DATABASE'),
    (454, 'ElastiCache Redis',     'INFRA_DATABASE'),
    (455, 'OpenSearch',            'INFRA_DATABASE'),
    (456, 'Elasticsearch',         'INFRA_DATABASE'),
    (457, 'Supabase PostgreSQL',   'INFRA_DATABASE'),

    ----------------------------------------------------------------
    -- infrastructure: web servers
    ----------------------------------------------------------------
    (465, 'Apache HTTP Server',    'INFRA_WEB_SERVER'),
    (466, 'Caddy',                 'INFRA_WEB_SERVER'),

    ----------------------------------------------------------------
    -- infrastructure: CI/CD tools
    ----------------------------------------------------------------
    (476, 'Azure Pipelines',       'INFRA_CICD_TOOL'),
    (477, 'Bitbucket Pipelines',   'INFRA_CICD_TOOL'),
    (478, 'Argo CD',               'INFRA_CICD_TOOL'),
    (479, 'CodePipeline',          'INFRA_CICD_TOOL'),
    (480, 'CodeBuild',             'INFRA_CICD_TOOL'),

    ----------------------------------------------------------------
    -- infrastructure: IaC tools
    ----------------------------------------------------------------
    (487, 'Bicep',                 'INFRA_IAC_TOOL'),
    (488, 'AWS CDK',               'INFRA_IAC_TOOL'),
    (489, 'Terragrunt',            'INFRA_IAC_TOOL'),
    (490, 'Kustomize',             'INFRA_IAC_TOOL'),

    ----------------------------------------------------------------
    -- infrastructure: monitoring / logging tools
    ----------------------------------------------------------------
    (497, 'Azure Monitor',         'INFRA_MONITORING_TOOL'),
    (498, 'Sentry',                'INFRA_MONITORING_TOOL'),
    (499, 'OpenTelemetry',         'INFRA_MONITORING_TOOL'),
    (500, 'Cloud Logging',         'INFRA_MONITORING_TOOL'),
    (506, 'CloudWatch Logs',       'INFRA_LOGGING_TOOL'),
    (507, 'Azure Monitor Logs',    'INFRA_LOGGING_TOOL'),
    (508, 'OpenSearch Dashboards', 'INFRA_LOGGING_TOOL'),

    ----------------------------------------------------------------
    -- tools: source control
    ----------------------------------------------------------------
    (606, 'GitBucket',             'TOOLS_SOURCE_CONTROL'),
    (607, 'AWS CodeCommit',        'TOOLS_SOURCE_CONTROL'),
    (608, 'Azure Repos',           'TOOLS_SOURCE_CONTROL'),

    ----------------------------------------------------------------
    -- tools: project management
    ----------------------------------------------------------------
    (617, 'GitHub Issues',         'TOOLS_PROJECT_MANAGEMENT'),
    (618, 'GitLab Issues',         'TOOLS_PROJECT_MANAGEMENT'),

    ----------------------------------------------------------------
    -- tools: communication
    ----------------------------------------------------------------
    (626, 'Chatwork',              'TOOLS_COMMUNICATION'),

    ----------------------------------------------------------------
    -- tools: documentation
    ----------------------------------------------------------------
    (636, 'Excel',                 'TOOLS_DOCUMENTATION'),
    (637, 'Mermaid',               'TOOLS_DOCUMENTATION'),
    (638, 'Draw.io',               'TOOLS_DOCUMENTATION'),
    (639, 'PlantUML',              'TOOLS_DOCUMENTATION'),
    (640, 'Sphinx',                'TOOLS_DOCUMENTATION'),

    ----------------------------------------------------------------
    -- tools: API development
    ----------------------------------------------------------------
    (647, 'Prism',                 'TOOLS_API_DEVELOPMENT'),
    (648, 'OpenAPI Generator',     'TOOLS_API_DEVELOPMENT'),
    (649, 'Swagger UI',            'TOOLS_API_DEVELOPMENT'),
    (650, 'curl',                  'TOOLS_API_DEVELOPMENT'),

    ----------------------------------------------------------------
    -- tools: design
    ----------------------------------------------------------------
    (656, 'Miro',                  'TOOLS_DESIGN'),

    ----------------------------------------------------------------
    -- tools: editors
    ----------------------------------------------------------------
    (665, 'Eclipse',               'TOOLS_EDITOR'),
    (666, 'Visual Studio',         'TOOLS_EDITOR'),
    (667, 'Cursor',                'TOOLS_EDITOR'),
    (668, 'Neovim',                'TOOLS_EDITOR'),

    ----------------------------------------------------------------
    -- tools: development environments
    ----------------------------------------------------------------
    (675, 'VirtualBox',            'TOOLS_DEV_ENVIRONMENT'),
    (676, 'Vagrant',               'TOOLS_DEV_ENVIRONMENT'),
    (677, 'Amazon WorkSpaces',     'TOOLS_DEV_ENVIRONMENT'),
    (678, 'GitHub Codespaces',     'TOOLS_DEV_ENVIRONMENT'),
    (679, 'Dev Containers',        'TOOLS_DEV_ENVIRONMENT')
) AS v(id, name, category_code)
WHERE NOT EXISTS (
    SELECT 1
    FROM tech_stack_mst t
    WHERE t.name = v.name
    AND t.category_code = v.category_code
);

-- =========================================================
-- 資格マスタ追加
-- =========================================================

INSERT INTO certification_mst (id, name)
SELECT v.id, v.name
FROM (VALUES
    ----------------------------------------------------------------
    -- IPA
    ----------------------------------------------------------------
    (14,   '情報処理安全確保支援士'),

    ----------------------------------------------------------------
    -- AWS
    ----------------------------------------------------------------
    (110,  'AWS Certified Advanced Networking - Specialty'),
    (111,  'AWS Certified Data Engineer - Associate'),
    (112,  'AWS Certified Machine Learning Engineer - Associate'),

    ----------------------------------------------------------------
    -- Microsoft
    ----------------------------------------------------------------
    (206,  'Microsoft Certified: Azure Developer Associate'),
    (207,  'Microsoft Certified: Azure Solutions Architect Expert'),
    (208,  'Microsoft Certified: DevOps Engineer Expert'),
    (209,  'Microsoft Certified: Azure AI Engineer Associate'),

    ----------------------------------------------------------------
    -- Google Cloud
    ----------------------------------------------------------------
    (313,  'Professional Cloud Architect'),
    (314,  'Professional Cloud Developer'),
    (315,  'Professional Cloud DevOps Engineer'),
    (316,  'Professional Cloud Database Engineer'),
    (317,  'Professional Cloud Security Engineer'),
    (318,  'Professional Data Engineer'),
    (319,  'Professional Machine Learning Engineer'),

    ----------------------------------------------------------------
    -- CompTIA
    ----------------------------------------------------------------
    (412,  'CompTIA Server+'),
    (413,  'CompTIA Project+'),

    ----------------------------------------------------------------
    -- CNCF
    ----------------------------------------------------------------
    (506,  'Prometheus Certified Associate (PCA)'),
    (507,  'Istio Certified Associate (ICA)'),

    ----------------------------------------------------------------
    -- HashiCorp
    ----------------------------------------------------------------
    (603,  'HashiCorp Certified: Vault Associate'),

    ----------------------------------------------------------------
    -- Scrum / Agile
    ----------------------------------------------------------------
    (2101, 'Certified ScrumMaster (CSM)'),
    (2102, 'Professional Scrum Master I (PSM I)'),

    ----------------------------------------------------------------
    -- Database / SQL
    ----------------------------------------------------------------
    (2201, 'PostgreSQL CE Bronze'),
    (2202, 'PostgreSQL CE Silver'),

    ----------------------------------------------------------------
    -- Security
    ----------------------------------------------------------------
    (2301, 'GIAC Security Essentials (GSEC)'),
    (2302, 'Certified Ethical Hacker (CEH)')
) AS v(id, name)
WHERE NOT EXISTS (
    SELECT 1
    FROM certification_mst c
    WHERE c.name = v.name
);

-- =========================================================
-- SNSプラットフォームマスタ追加
-- =========================================================

INSERT INTO sns_platform_mst (id, name)
SELECT v.id, v.name
FROM (VALUES
    (20, 'Wantedly'),
    (21, 'Forkwell'),
    (22, 'LAPRAS'),
    (23, 'AtCoder'),
    (24, 'LeetCode'),
    (25, 'Credly'),
    (26, 'Portfolio'),
    (27, 'Product Hunt')
) AS v(id, name)
WHERE NOT EXISTS (
    SELECT 1
    FROM sns_platform_mst s
    WHERE s.name = v.name
);
