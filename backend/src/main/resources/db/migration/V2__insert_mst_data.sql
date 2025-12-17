-- =========================================================
-- 技術スタックカテゴリマスタデータ
-- =========================================================
INSERT INTO tech_stack_category_mst (code, main_category, sub_category) VALUES
    -- frontend
    ('FRONTEND_LANGUAGE',          'frontend',      'languages'),
    ('FRONTEND_FRAMEWORK',         'frontend',      'framework'),
    ('FRONTEND_LIBRARY',           'frontend',      'libraries'),
    ('FRONTEND_BUILD_TOOL',        'frontend',      'buildTool'),
    ('FRONTEND_PACKAGE_MANAGER',   'frontend',      'packageManager'),
    ('FRONTEND_LINTER',            'frontend',      'linters'),
    ('FRONTEND_FORMATTER',         'frontend',      'formatters'),
    ('FRONTEND_TESTING_TOOL',      'frontend',      'testingTools'),

    -- backend
    ('BACKEND_LANGUAGE',           'backend',       'languages'),
    ('BACKEND_FRAMEWORK',          'backend',       'framework'),
    ('BACKEND_LIBRARY',            'backend',       'libraries'),
    ('BACKEND_BUILD_TOOL',         'backend',       'buildTool'),
    ('BACKEND_PACKAGE_MANAGER',    'backend',       'packageManager'),
    ('BACKEND_LINTER',             'backend',       'linters'),
    ('BACKEND_FORMATTER',          'backend',       'formatters'),
    ('BACKEND_TESTING_TOOL',       'backend',       'testingTools'),
    ('BACKEND_ORM_TOOL',           'backend',       'ormTools'),
    ('BACKEND_AUTH',               'backend',       'auth'),

    -- infrastructure
    ('INFRA_CLOUD',                'infrastructure','clouds'),
    ('INFRA_OS',                   'infrastructure','operatingSystem'),
    ('INFRA_CONTAINER',            'infrastructure','containers'),
    ('INFRA_DATABASE',             'infrastructure','database'),
    ('INFRA_WEB_SERVER',           'infrastructure','webServer'),
    ('INFRA_CICD_TOOL',            'infrastructure','ciCdTool'),
    ('INFRA_IAC_TOOL',             'infrastructure','iacTools'),
    ('INFRA_MONITORING_TOOL',      'infrastructure','monitoringTools'),
    ('INFRA_LOGGING_TOOL',         'infrastructure','loggingTools'),

    -- tools
    ('TOOLS_SOURCE_CONTROL',       'tools',         'sourceControl'),
    ('TOOLS_PROJECT_MANAGEMENT',   'tools',         'projectManagement'),
    ('TOOLS_COMMUNICATION',        'tools',         'communicationTool'),
    ('TOOLS_DOCUMENTATION',        'tools',         'documentationTools'),
    ('TOOLS_API_DEVELOPMENT',      'tools',         'apiDevelopmentTools'),
    ('TOOLS_DESIGN',               'tools',         'designTools'),
    ('TOOLS_EDITOR',               'tools',         'editor'),
    ('TOOLS_DEV_ENVIRONMENT',      'tools',         'developmentEnvironment');

-- =========================================================
-- 技術スタックマスタデータ
-- =========================================================
INSERT INTO tech_stack_mst (id, name, category_code) VALUES
    ----------------------------------------------------------------
    -- frontend: languages
    ----------------------------------------------------------------
    (1,   'JavaScript',            'FRONTEND_LANGUAGE'),
    (2,   'TypeScript',            'FRONTEND_LANGUAGE'),
    (3,   'HTML',                  'FRONTEND_LANGUAGE'),
    (4,   'CSS',                   'FRONTEND_LANGUAGE'),

    ----------------------------------------------------------------
    -- frontend: frameworks
    ----------------------------------------------------------------
    (11,  'React',                 'FRONTEND_FRAMEWORK'),
    (12,  'Next.js',               'FRONTEND_FRAMEWORK'),
    (13,  'Vue.js',                'FRONTEND_FRAMEWORK'),
    (14,  'Nuxt.js',               'FRONTEND_FRAMEWORK'),
    (15,  'Angular',               'FRONTEND_FRAMEWORK'),
    (16,  'Svelte',                'FRONTEND_FRAMEWORK'),
    (17,  'SolidJS',               'FRONTEND_FRAMEWORK'),

    ----------------------------------------------------------------
    -- frontend: libraries
    ----------------------------------------------------------------
    (21,  'Redux',                 'FRONTEND_LIBRARY'),
    (22,  'Zustand',               'FRONTEND_LIBRARY'),
    (23,  'TanStack Query',        'FRONTEND_LIBRARY'),
    (24,  'SWR',                   'FRONTEND_LIBRARY'),
    (25,  'Axios',                 'FRONTEND_LIBRARY'),
    (26,  'React Hook Form',       'FRONTEND_LIBRARY'),
    (27,  'Framer Motion',         'FRONTEND_LIBRARY'),
    (28,  'Chart.js',              'FRONTEND_LIBRARY'),
    (29,  'Recharts',              'FRONTEND_LIBRARY'),
    (30,  'MUI',                   'FRONTEND_LIBRARY'),
    (31,  'Tailwind CSS',          'FRONTEND_LIBRARY'),
    (32,  'Headless UI',           'FRONTEND_LIBRARY'),
    (33,  'Radix UI',              'FRONTEND_LIBRARY'),
    (34,  'Chakra UI',             'FRONTEND_LIBRARY'),
    (35,  'Ant Design',            'FRONTEND_LIBRARY'),
    (36,  'shadcn/ui',             'FRONTEND_LIBRARY'),

    ----------------------------------------------------------------
    -- frontend: build tools
    ----------------------------------------------------------------
    (41,  'Vite',                  'FRONTEND_BUILD_TOOL'),
    (42,  'webpack',               'FRONTEND_BUILD_TOOL'),
    (43,  'Rollup',                'FRONTEND_BUILD_TOOL'),
    (44,  'Parcel',                'FRONTEND_BUILD_TOOL'),

    ----------------------------------------------------------------
    -- frontend: package managers
    ----------------------------------------------------------------
    (51,  'npm',                   'FRONTEND_PACKAGE_MANAGER'),
    (52,  'Yarn',                  'FRONTEND_PACKAGE_MANAGER'),
    (53,  'pnpm',                  'FRONTEND_PACKAGE_MANAGER'),
    (54,  'bun',                   'FRONTEND_PACKAGE_MANAGER'),

    ----------------------------------------------------------------
    -- frontend: linters
    ----------------------------------------------------------------
    (61,  'ESLint',                'FRONTEND_LINTER'),
    (62,  'stylelint',             'FRONTEND_LINTER'),
    (63,  'TypeScript ESLint',     'FRONTEND_LINTER'),

    ----------------------------------------------------------------
    -- frontend: formatters
    ----------------------------------------------------------------
    (71,  'Prettier',              'FRONTEND_FORMATTER'),
    (72,  'dprint',                'FRONTEND_FORMATTER'),
    (73,  'Biome',                 'FRONTEND_FORMATTER'),

    ----------------------------------------------------------------
    -- frontend: testing tools
    ----------------------------------------------------------------
    (81,  'Jest',                  'FRONTEND_TESTING_TOOL'),
    (82,  'Vitest',                'FRONTEND_TESTING_TOOL'),
    (83,  'Testing Library',       'FRONTEND_TESTING_TOOL'),
    (84,  'Cypress',               'FRONTEND_TESTING_TOOL'),
    (85,  'Playwright',            'FRONTEND_TESTING_TOOL'),
    (86,  'Storybook',             'FRONTEND_TESTING_TOOL'),

    ----------------------------------------------------------------
    -- backend: languages（ここを厚めに拡張）
    ----------------------------------------------------------------
    (101, 'Java',                  'BACKEND_LANGUAGE'),
    (102, 'Kotlin',                'BACKEND_LANGUAGE'),
    (103, 'Python',                'BACKEND_LANGUAGE'),
    (104, 'Go',                    'BACKEND_LANGUAGE'),
    (105, 'C',                     'BACKEND_LANGUAGE'),
    (106, 'C++',                   'BACKEND_LANGUAGE'),
    (107, 'C#',                    'BACKEND_LANGUAGE'),
    (108, 'PHP',                   'BACKEND_LANGUAGE'),
    (109, 'Ruby',                  'BACKEND_LANGUAGE'),
    (110, 'Rust',                  'BACKEND_LANGUAGE'),
    (111, 'Scala',                 'BACKEND_LANGUAGE'),
    (112, 'Swift',                 'BACKEND_LANGUAGE'),
    (113, 'Objective-C',           'BACKEND_LANGUAGE'),
    (114, 'Visual Basic',          'BACKEND_LANGUAGE'),
    (115, 'Delphi',                'BACKEND_LANGUAGE'),
    (116, 'COBOL',                 'BACKEND_LANGUAGE'),
    (117, 'Fortran',               'BACKEND_LANGUAGE'),
    (118, 'Ada',                   'BACKEND_LANGUAGE'),
    (119, 'Pascal',                'BACKEND_LANGUAGE'),
    (120, 'Haskell',               'BACKEND_LANGUAGE'),
    (121, 'Perl',                  'BACKEND_LANGUAGE'),
    (122, 'R',                     'BACKEND_LANGUAGE'),
    (123, 'Lua',                   'BACKEND_LANGUAGE'),
    (124, 'MATLAB',                'BACKEND_LANGUAGE'),
    (125, 'Dart',                  'BACKEND_LANGUAGE'),
    (126, 'Julia',                 'BACKEND_LANGUAGE'),
    (127, 'Groovy',                'BACKEND_LANGUAGE'),
    (128, 'Erlang',                'BACKEND_LANGUAGE'),
    (129, 'Elixir',                'BACKEND_LANGUAGE'),
    (130, 'F#',                    'BACKEND_LANGUAGE'),
    (131, 'OCaml',                 'BACKEND_LANGUAGE'),
    (132, 'Clojure',               'BACKEND_LANGUAGE'),
    (133, 'Lisp',                  'BACKEND_LANGUAGE'),
    (134, 'Scheme',                'BACKEND_LANGUAGE'),

    ----------------------------------------------------------------
    -- backend: frameworks
    ----------------------------------------------------------------
    (201, 'Spring Boot',           'BACKEND_FRAMEWORK'),
    (202, 'Spring Framework',      'BACKEND_FRAMEWORK'),
    (203, 'Jakarta EE',            'BACKEND_FRAMEWORK'),
    (204, 'Django',                'BACKEND_FRAMEWORK'),
    (205, 'FastAPI',               'BACKEND_FRAMEWORK'),
    (206, 'Flask',                 'BACKEND_FRAMEWORK'),
    (207, 'Express.js',            'BACKEND_FRAMEWORK'),
    (208, 'NestJS',                'BACKEND_FRAMEWORK'),
    (209, 'Laravel',               'BACKEND_FRAMEWORK'),
    (210, 'Symfony',               'BACKEND_FRAMEWORK'),
    (211, 'CodeIgniter',           'BACKEND_FRAMEWORK'),
    (212, 'Ruby on Rails',         'BACKEND_FRAMEWORK'),
    (213, 'Sinatra',               'BACKEND_FRAMEWORK'),
    (214, 'Gin',                   'BACKEND_FRAMEWORK'),
    (215, 'Echo',                  'BACKEND_FRAMEWORK'),
    (216, 'ASP.NET Core',          'BACKEND_FRAMEWORK'),
    (217, 'ASP.NET MVC',           'BACKEND_FRAMEWORK'),

    ----------------------------------------------------------------
    -- backend: libraries
    ----------------------------------------------------------------
    (221, 'Lombok',                'BACKEND_LIBRARY'),
    (222, 'Jackson',               'BACKEND_LIBRARY'),
    (223, 'SLF4J',                 'BACKEND_LIBRARY'),
    (224, 'Log4j',                 'BACKEND_LIBRARY'),
    (225, 'Guava',                 'BACKEND_LIBRARY'),
    (226, 'NumPy',                 'BACKEND_LIBRARY'),
    (227, 'Pandas',                'BACKEND_LIBRARY'),
    (228, 'Requests',              'BACKEND_LIBRARY'),
    (229, 'Pillow',                'BACKEND_LIBRARY'),
    (230, 'SQLAlchemy',            'BACKEND_LIBRARY'),
    (231, 'Beautiful Soup',        'BACKEND_LIBRARY'),
    (232, 'Carbon',                'BACKEND_LIBRARY'),
    (233, 'Guzzle',                'BACKEND_LIBRARY'),
    (234, 'Monolog',               'BACKEND_LIBRARY'),
    (235, 'Nokogiri',              'BACKEND_LIBRARY'),
    (236, 'Faraday',               'BACKEND_LIBRARY'),
    (237, 'Gorm',                  'BACKEND_LIBRARY'),
    (238, 'Cobra',                 'BACKEND_LIBRARY'),
    (239, 'Newtonsoft.Json',       'BACKEND_LIBRARY'),
    (240, 'Serilog',               'BACKEND_LIBRARY'),
    (241, 'Dapper',                'BACKEND_LIBRARY'),

    ----------------------------------------------------------------
    -- backend: build tools
    ----------------------------------------------------------------
    (251, 'Maven',                 'BACKEND_BUILD_TOOL'),
    (252, 'Gradle',                'BACKEND_BUILD_TOOL'),
    (253, 'Ant',                   'BACKEND_BUILD_TOOL'),

    ----------------------------------------------------------------
    -- backend: package managers
    ----------------------------------------------------------------
    (261, 'pip',                   'BACKEND_PACKAGE_MANAGER'),
    (262, 'Poetry',                'BACKEND_PACKAGE_MANAGER'),
    (263, 'pipenv',                'BACKEND_PACKAGE_MANAGER'),
    (264, 'conda',                 'BACKEND_PACKAGE_MANAGER'),
    (265, 'Composer',              'BACKEND_PACKAGE_MANAGER'),
    (266, 'RubyGems',              'BACKEND_PACKAGE_MANAGER'),
    (267, 'Bundler',               'BACKEND_PACKAGE_MANAGER'),
    (268, 'Go Modules',            'BACKEND_PACKAGE_MANAGER'),
    (269, 'NuGet',                 'BACKEND_PACKAGE_MANAGER'),
    (270, 'dotnet CLI',            'BACKEND_PACKAGE_MANAGER'),

    ----------------------------------------------------------------
    -- backend: linters
    ----------------------------------------------------------------
    (281, 'Ruff',                  'BACKEND_LINTER'),
    (282, 'Pylint',                'BACKEND_LINTER'),
    (283, 'Flake8',                'BACKEND_LINTER'),
    (284, 'mypy',                  'BACKEND_LINTER'),
    (285, 'Pyright',               'BACKEND_LINTER'),
    (286, 'Checkstyle',            'BACKEND_LINTER'),
    (287, 'PMD',                   'BACKEND_LINTER'),
    (288, 'SpotBugs',              'BACKEND_LINTER'),
    (289, 'SonarLint',             'BACKEND_LINTER'),
    (290, 'PHP_CodeSniffer',       'BACKEND_LINTER'),
    (291, 'PHPStan',               'BACKEND_LINTER'),
    (292, 'PHP Mess Detector',     'BACKEND_LINTER'),
    (293, 'RuboCop',               'BACKEND_LINTER'),
    (294, 'Reek',                  'BACKEND_LINTER'),
    (295, 'golangci-lint',         'BACKEND_LINTER'),
    (296, 'staticcheck',           'BACKEND_LINTER'),
    (297, 'StyleCop',              'BACKEND_LINTER'),
    (298, 'FxCop',                 'BACKEND_LINTER'),
    (299, 'Roslynator',            'BACKEND_LINTER'),

    ----------------------------------------------------------------
    -- backend: formatters
    ----------------------------------------------------------------
    (301, 'Black',                 'BACKEND_FORMATTER'),
    (302, 'isort',                 'BACKEND_FORMATTER'),
    (303, 'YAPF',                  'BACKEND_FORMATTER'),
    (304, 'autopep8',              'BACKEND_FORMATTER'),
    (305, 'google-java-format',    'BACKEND_FORMATTER'),
    (306, 'Eclipse formatter',     'BACKEND_FORMATTER'),
    (307, 'PHP-CS-Fixer',          'BACKEND_FORMATTER'),
    (308, 'gofmt',                 'BACKEND_FORMATTER'),
    (309, 'goimports',             'BACKEND_FORMATTER'),
    (310, 'CSharpier',             'BACKEND_FORMATTER'),
    (311, 'dotnet format',         'BACKEND_FORMATTER'),

    ----------------------------------------------------------------
    -- backend: testing tools
    ----------------------------------------------------------------
    (321, 'JUnit',                 'BACKEND_TESTING_TOOL'),
    (322, 'TestNG',                'BACKEND_TESTING_TOOL'),
    (323, 'Mockito',               'BACKEND_TESTING_TOOL'),
    (324, 'pytest',                'BACKEND_TESTING_TOOL'),
    (325, 'pytest-mock',           'BACKEND_TESTING_TOOL'),
    (326, 'pytest-cov',            'BACKEND_TESTING_TOOL'),
    (327, 'PHPUnit',               'BACKEND_TESTING_TOOL'),
    (328, 'Pest',                  'BACKEND_TESTING_TOOL'),
    (329, 'Codeception',           'BACKEND_TESTING_TOOL'),
    (330, 'RSpec',                 'BACKEND_TESTING_TOOL'),
    (331, 'Minitest',              'BACKEND_TESTING_TOOL'),
    (332, 'testing package',       'BACKEND_TESTING_TOOL'),
    (333, 'testify',               'BACKEND_TESTING_TOOL'),
    (334, 'gomock',                'BACKEND_TESTING_TOOL'),
    (335, 'MSTest',                'BACKEND_TESTING_TOOL'),
    (336, 'NUnit',                 'BACKEND_TESTING_TOOL'),
    (337, 'xUnit.net',             'BACKEND_TESTING_TOOL'),

    ----------------------------------------------------------------
    -- backend: ORM tools
    ----------------------------------------------------------------
    (341, 'Prisma',                'BACKEND_ORM_TOOL'),
    (342, 'Prisma Client',         'BACKEND_ORM_TOOL'),
    (343, 'TypeORM',               'BACKEND_ORM_TOOL'),
    (344, 'Sequelize',             'BACKEND_ORM_TOOL'),
    (345, 'Knex.js',               'BACKEND_ORM_TOOL'),
    (346, 'MikroORM',              'BACKEND_ORM_TOOL'),
    (347, 'Drizzle ORM',           'BACKEND_ORM_TOOL'),
    (348, 'Mongoose',              'BACKEND_ORM_TOOL'),
    (349, 'SQLAlchemy',            'BACKEND_ORM_TOOL'),
    (350, 'Django ORM',            'BACKEND_ORM_TOOL'),
    (351, 'Hibernate',             'BACKEND_ORM_TOOL'),
    (352, 'EclipseLink',           'BACKEND_ORM_TOOL'),
    (353, 'MyBatis',               'BACKEND_ORM_TOOL'),
    (354, 'Spring Data JPA',       'BACKEND_ORM_TOOL'),
    (355, 'Doctrine',              'BACKEND_ORM_TOOL'),
    (356, 'Eloquent',              'BACKEND_ORM_TOOL'),
    (357, 'GORM',                  'BACKEND_ORM_TOOL'),
    (358, 'Entity Framework Core', 'BACKEND_ORM_TOOL'),
    (359, 'NHibernate',            'BACKEND_ORM_TOOL'),

    ----------------------------------------------------------------
    -- backend: auth
    ----------------------------------------------------------------
    (371, 'Spring Security',       'BACKEND_AUTH'),
    (372, 'Keycloak',              'BACKEND_AUTH'),
    (373, 'Auth0',                 'BACKEND_AUTH'),

    ----------------------------------------------------------------
    -- infrastructure: clouds
    ----------------------------------------------------------------
    (401, 'AWS',                   'INFRA_CLOUD'),
    (402, 'Azure',                 'INFRA_CLOUD'),
    (403, 'GCP',                   'INFRA_CLOUD'),
    (404, 'さくらのクラウド',       'INFRA_CLOUD'),
    (405, 'Alibaba Cloud',         'INFRA_CLOUD'),
    (406, 'Oracle Cloud',          'INFRA_CLOUD'),
    (407, 'IBM Cloud',             'INFRA_CLOUD'),
    (408, 'DigitalOcean',          'INFRA_CLOUD'),
    (409, 'Heroku',                'INFRA_CLOUD'),
    (410, 'Vercel',                'INFRA_CLOUD'),
    (411, 'Netlify',               'INFRA_CLOUD'),

    ----------------------------------------------------------------
    -- infrastructure: OS
    ----------------------------------------------------------------
    (421, 'Amazon Linux',          'INFRA_OS'),
    (422, 'Ubuntu',                'INFRA_OS'),
    (423, 'Debian',                'INFRA_OS'),
    (424, 'Windows Server',        'INFRA_OS'),
    (425, 'Red Hat Enterprise Linux','INFRA_OS'),

    ----------------------------------------------------------------
    -- infrastructure: containers
    ----------------------------------------------------------------
    (431, 'Docker',                'INFRA_CONTAINER'),
    (432, 'Docker Compose',        'INFRA_CONTAINER'),
    (433, 'Kubernetes',            'INFRA_CONTAINER'),
    (434, 'containerd',            'INFRA_CONTAINER'),
    (435, 'Podman',                'INFRA_CONTAINER'),
    (436, 'OpenShift',             'INFRA_CONTAINER'),

    ----------------------------------------------------------------
    -- infrastructure: databases
    ----------------------------------------------------------------
    (441, 'PostgreSQL',            'INFRA_DATABASE'),
    (442, 'MySQL',                 'INFRA_DATABASE'),
    (443, 'MariaDB',               'INFRA_DATABASE'),
    (444, 'Aurora',                'INFRA_DATABASE'),
    (445, 'Oracle Database',       'INFRA_DATABASE'),
    (446, 'SQL Server',            'INFRA_DATABASE'),
    (447, 'SQLite',                'INFRA_DATABASE'),
    (448, 'MongoDB',               'INFRA_DATABASE'),
    (449, 'Redis',                 'INFRA_DATABASE'),
    (450, 'DynamoDB',              'INFRA_DATABASE'),

    ----------------------------------------------------------------
    -- infrastructure: web servers
    ----------------------------------------------------------------
    (461, 'Nginx',                 'INFRA_WEB_SERVER'),
    (462, 'Apache',                'INFRA_WEB_SERVER'),
    (463, 'Tomcat',                'INFRA_WEB_SERVER'),
    (464, 'Jetty',                 'INFRA_WEB_SERVER'),

    ----------------------------------------------------------------
    -- infrastructure: CI/CD tools
    ----------------------------------------------------------------
    (471, 'GitHub Actions',        'INFRA_CICD_TOOL'),
    (472, 'GitLab CI',             'INFRA_CICD_TOOL'),
    (473, 'CircleCI',              'INFRA_CICD_TOOL'),
    (474, 'Jenkins',               'INFRA_CICD_TOOL'),
    (475, 'Travis CI',             'INFRA_CICD_TOOL'),

    ----------------------------------------------------------------
    -- infrastructure: IaC tools
    ----------------------------------------------------------------
    (481, 'Terraform',             'INFRA_IAC_TOOL'),
    (482, 'CloudFormation',        'INFRA_IAC_TOOL'),
    (483, 'Ansible',               'INFRA_IAC_TOOL'),
    (484, 'Pulumi',                'INFRA_IAC_TOOL'),
    (485, 'Chef',                  'INFRA_IAC_TOOL'),
    (486, 'Puppet',                'INFRA_IAC_TOOL'),

    ----------------------------------------------------------------
    -- infrastructure: monitoring tools
    ----------------------------------------------------------------
    (491, 'CloudWatch',            'INFRA_MONITORING_TOOL'),
    (492, 'Datadog',               'INFRA_MONITORING_TOOL'),
    (493, 'Grafana',               'INFRA_MONITORING_TOOL'),
    (494, 'Prometheus',            'INFRA_MONITORING_TOOL'),
    (495, 'New Relic',             'INFRA_MONITORING_TOOL'),
    (496, 'Zabbix',                'INFRA_MONITORING_TOOL'),

    ----------------------------------------------------------------
    -- infrastructure: logging tools
    ----------------------------------------------------------------
    (501, 'Fluentd',               'INFRA_LOGGING_TOOL'),
    (502, 'Logstash',              'INFRA_LOGGING_TOOL'),
    (503, 'Elasticsearch',         'INFRA_LOGGING_TOOL'),
    (504, 'Splunk',                'INFRA_LOGGING_TOOL'),
    (505, 'Loki',                  'INFRA_LOGGING_TOOL'),

    ----------------------------------------------------------------
    -- tools: source control
    ----------------------------------------------------------------
    (601, 'Git',                   'TOOLS_SOURCE_CONTROL'),
    (602, 'Subversion',            'TOOLS_SOURCE_CONTROL'),
    (603, 'GitHub',                'TOOLS_SOURCE_CONTROL'),
    (604, 'GitLab',                'TOOLS_SOURCE_CONTROL'),
    (605, 'Bitbucket',             'TOOLS_SOURCE_CONTROL'),

    ----------------------------------------------------------------
    -- tools: project management
    ----------------------------------------------------------------
    (611, 'Jira',                  'TOOLS_PROJECT_MANAGEMENT'),
    (612, 'Backlog',               'TOOLS_PROJECT_MANAGEMENT'),
    (613, 'Linear',                'TOOLS_PROJECT_MANAGEMENT'),
    (614, 'Asana',                 'TOOLS_PROJECT_MANAGEMENT'),
    (615, 'Trello',                'TOOLS_PROJECT_MANAGEMENT'),
    (616, 'Redmine',               'TOOLS_PROJECT_MANAGEMENT'),

    ----------------------------------------------------------------
    -- tools: communication
    ----------------------------------------------------------------
    (621, 'Slack',                 'TOOLS_COMMUNICATION'),
    (622, 'Microsoft Teams',       'TOOLS_COMMUNICATION'),
    (623, 'Discord',               'TOOLS_COMMUNICATION'),
    (624, 'Zoom',                  'TOOLS_COMMUNICATION'),
    (625, 'Google Meet',           'TOOLS_COMMUNICATION'),

    ----------------------------------------------------------------
    -- tools: documentation
    ----------------------------------------------------------------
    (631, 'Confluence',            'TOOLS_DOCUMENTATION'),
    (632, 'Notion',                'TOOLS_DOCUMENTATION'),
    (633, 'Google Workspace',      'TOOLS_DOCUMENTATION'),
    (634, 'Microsoft Office 365',  'TOOLS_DOCUMENTATION'),
    (635, 'Markdown',              'TOOLS_DOCUMENTATION'),

    ----------------------------------------------------------------
    -- tools: API development
    ----------------------------------------------------------------
    (641, 'Postman',               'TOOLS_API_DEVELOPMENT'),
    (642, 'Insomnia',              'TOOLS_API_DEVELOPMENT'),
    (643, 'Hoppscotch',            'TOOLS_API_DEVELOPMENT'),
    (644, 'Swagger/OpenAPI',       'TOOLS_API_DEVELOPMENT'),
    (645, 'GraphQL',               'TOOLS_API_DEVELOPMENT'),
    (646, 'gRPC',                  'TOOLS_API_DEVELOPMENT'),

    ----------------------------------------------------------------
    -- tools: design
    ----------------------------------------------------------------
    (651, 'Figma',                 'TOOLS_DESIGN'),
    (652, 'Adobe XD',              'TOOLS_DESIGN'),
    (653, 'Sketch',                'TOOLS_DESIGN'),
    (654, 'Adobe Photoshop',       'TOOLS_DESIGN'),
    (655, 'Adobe Illustrator',     'TOOLS_DESIGN'),

    ----------------------------------------------------------------
    -- tools: editors
    ----------------------------------------------------------------
    (661, 'VS Code',               'TOOLS_EDITOR'),
    (662, 'IntelliJ IDEA',         'TOOLS_EDITOR'),
    (663, 'PyCharm',               'TOOLS_EDITOR'),
    (664, 'WebStorm',              'TOOLS_EDITOR'),

    ----------------------------------------------------------------
    -- tools: development environments
    ----------------------------------------------------------------
    (671, 'WSL2',                  'TOOLS_DEV_ENVIRONMENT'),
    (672, 'Docker Compose',        'TOOLS_DEV_ENVIRONMENT'),
    (673, 'Localhost',             'TOOLS_DEV_ENVIRONMENT'),
    (674, 'Kubernetes cluster',    'TOOLS_DEV_ENVIRONMENT');
