import {
    BasicInfoSection,
    CareerSection,
    CertificationSection,
    PortfolioSection,
    ProcessMap,
    ProjectSection,
    SectionInfo,
    SelfPromotionSection,
    SociealLinkSection,
} from "@/features/resume";
import { TechStack } from "@/types";

/**
 * セクション情報一覧
 */
export const sections: SectionInfo[] = [
    { key: "basicInfo", label: "基本", type: "single", component: BasicInfoSection },
    { key: "career", label: "職歴", type: "list", component: CareerSection },
    { key: "project", label: "職務内容", type: "list", component: ProjectSection },
    { key: "certification", label: "保有資格", type: "list", component: CertificationSection },
    { key: "portfolio", label: "ポートフォリオ", type: "list", component: PortfolioSection },
    { key: "socialLink", label: "SNS", type: "list", component: SociealLinkSection },
    { key: "selfPromotion", label: "自己PR", type: "list", component: SelfPromotionSection },
] as const;

/**
 * 作業工程のマッピング
 */
export const processList: ProcessMap = {
    requirements: "要件定義",
    basicDesign: "基本設計",
    detailedDesign: "詳細設計",
    implementation: "実装・単体テスト",
    integrationTest: "結合テスト",
    systemTest: "総合テスト",
    maintenance: "運用・保守",
} as const;

/**
 * 技術スタックのカテゴリマッピング
 */
export const techStackInfo = [
    {
        title: "フロントエンド",
        fields: [
            { label: "言語", path: ["frontend", "languages"] },
            { label: "フレームワーク", path: ["frontend", "frameworks"] },
            { label: "ライブラリ", path: ["frontend", "libraries"] },
            { label: "ビルドツール", path: ["frontend", "buildTools"] },
            { label: "パッケージマネージャー", path: ["frontend", "packageManagers"] },
            { label: "リンター", path: ["frontend", "linters"] },
            { label: "フォーマッター", path: ["frontend", "formatters"] },
            { label: "テストツール", path: ["frontend", "testingTools"] },
        ],
    },
    {
        title: "バックエンド",
        fields: [
            { label: "言語", path: ["backend", "languages"] },
            { label: "フレームワーク", path: ["backend", "frameworks"] },
            { label: "ライブラリ", path: ["backend", "libraries"] },
            { label: "ビルドツール", path: ["backend", "buildTools"] },
            { label: "パッケージマネージャー", path: ["backend", "packageManagers"] },
            { label: "リンター", path: ["backend", "linters"] },
            { label: "フォーマッター", path: ["backend", "formatters"] },
            { label: "テストツール", path: ["backend", "testingTools"] },
            { label: "ORM", path: ["backend", "ormTools"] },
            { label: "認証/認可", path: ["backend", "auth"] },
        ],
    },
    {
        title: "インフラ",
        fields: [
            { label: "クラウド", path: ["infrastructure", "clouds"] },
            { label: "OS", path: ["infrastructure", "operatingSystems"] },
            { label: "コンテナ", path: ["infrastructure", "containers"] },
            { label: "データベース", path: ["infrastructure", "databases"] },
            { label: "Webサーバー", path: ["infrastructure", "webServers"] },
            { label: "CI/CD", path: ["infrastructure", "ciCdTools"] },
            { label: "IaC", path: ["infrastructure", "iacTools"] },
            { label: "監視", path: ["infrastructure", "monitoringTools"] },
            { label: "ロギング", path: ["infrastructure", "loggingTools"] },
        ],
    },
    {
        title: "開発支援ツール",
        fields: [
            { label: "ソース管理", path: ["tools", "sourceControls"] },
            { label: "プロジェクト管理", path: ["tools", "projectManagements"] },
            { label: "コミュニケーション", path: ["tools", "communicationTools"] },
            { label: "ドキュメント", path: ["tools", "documentationTools"] },
            { label: "API開発", path: ["tools", "apiDevelopmentTools"] },
            { label: "デザイン", path: ["tools", "designTools"] },
            { label: "エディタ/IDE", path: ["tools", "editors"] },
            { label: "開発環境", path: ["tools", "developmentEnvironments"] },
        ],
    },
] as const;

/**
 * 共通で利用する候補一覧
 */
const commonLanguages = [
    "TypeScript",
    "JavaScript",
    "HTML",
    "CSS",
    "Sass/SCSS",
    "WebAssembly",
    "Dart",
    "Go",
    "Python",
    "Java",
    "Ruby",
    "PHP",
    "Rust",
    "Node.js",
    "C#",
    "Kotlin",
    "Scala",
    "Elixir",
    "Swift",
    "C++",
    "Perl",
].sort();

const commonFrameworks = [
    // JavaScript/TypeScript
    "React",
    "Angular",
    "Vue.js",
    "Svelte",
    // JavaScript/TypeScript (サーバーサイド)
    "Express",
    "NestJS",
    "Koa",
    "Hapi",
    // Python
    "Django",
    "Flask",
    "FastAPI",
    "Pyramid",
    // Java
    "Spring",
    "Struts",
    "JSF",
    "Play Framework",
    // Ruby
    "Ruby on Rails",
    "Sinatra",
    "Hanami",
    // PHP
    "Laravel",
    "Symfony",
    "CodeIgniter",
    "CakePHP",
    // .NET
    "ASP.NET Core",
    "Blazor",
    "NancyFX",
    // CSS
    "Bootstrap",
    "Tailwind CSS",
    "Foundation",
    "Bulma",
    "Materialize",
    // その他の言語/プラットフォーム
    "React Native",
    "Flutter",
    "Ionic",
    "Electron",
    "Qt",
].sort();

const commonLibraries = [
    // JavaScript/TypeScript
    "ESLint",
    "Prettier",
    "Axios",
    "TanStack Query",
    "Redux",
    "Lodash",
    "Moment.js",
    "RxJS",
    "Chart.js",
    // Python
    "NumPy",
    "pandas",
    "Requests",
    "Matplotlib",
    "BeautifulSoup",
    // Java
    "Apache Commons",
    "Guava",
    "Jackson",
    "Log4j",
    "SLF4J",
    // Ruby
    "Nokogiri",
    "Prawn",
    "Oj",
    "Faraday",
    "Sidekiq",
    // PHP
    "Guzzle",
    "Monolog",
    "Carbon",
    "SwiftMailer",
    "Symfony Components",
];

const commonTestingTools = [
    // JavaScript/TypeScript
    "Jest",
    "Mocha",
    "Chai",
    "Jasmine",
    "Karma",
    "Cypress",
    "TestCafe",
    "Puppeteer",
    "Playwright",
    // Java
    "JUnit",
    "TestNG",
    // .NET
    "NUnit",
    "xUnit",
    "MSTest",
    // Python
    "pytest",
    "unittest",
    "nose",
    // Ruby
    "RSpec",
    "Minitest",
    "Cucumber",
    // PHP
    "PHPUnit",
    "Behat",
    // Go
    "GoConvey",
    "Testify",
    // C/C++
    "Google Test",
    "CppUnit",
    // 汎用・クロスプラットフォーム
    "Selenium",
    "Robot Framework",
].sort();

const ormToolsList = [
    // JavaScript/TypeScript
    "TypeORM",
    "Sequelize",
    "Objection.js",
    "Prisma",
    // Python
    "SQLAlchemy",
    "Django ORM",
    "Peewee",
    // Ruby
    "ActiveRecord",
    "Sequel",
    // Java
    "Hibernate",
    "MyBatis",
    "EclipseLink",
    // .NET
    "Entity Framework",
    "Dapper",
    // PHP
    "Doctrine",
    "Eloquent",
    // Go
    "GORM",
    "Ent",
    "XORM",
    // Ruby
    "ROM",
    // その他汎用または複数言語対応
    "SQLAlchemy Core",
    "Knex.js",
].sort();

const packageManagersList = [
    // JavaScript/TypeScript
    "npm",
    "Yarn",
    "pnpm",
    // Python
    "pip",
    "conda",
    "Poetry",
    // Ruby
    "gem",
    "Bundler",
    // Java
    "Maven",
    "Gradle",
    // PHP
    "Composer",
    // .NET
    "NuGet",
    // Rust
    "Cargo",
    // Go
    "Go Modules",
    // Dart/Flutter
    "pub",
    // Swift/Objective-C
    "CocoaPods",
    "Carthage",
    "Swift Package Manager",
];

/**
 * 技術スタック一覧
 * ※DB管理にしたい
 */
export const teckStackList: TechStack = {
    frontend: {
        languages: commonLanguages,
        frameworks: commonFrameworks,
        libraries: commonLibraries,
        buildTools: ["Webpack", "Vite", "Rollup", "Parcel", "Gulp", "Grunt"],
        packageManagers: packageManagersList,
        linters: ["ESLint", "TSLint", "Stylelint"],
        formatters: ["Prettier"],
        testingTools: commonTestingTools,
    },
    backend: {
        languages: commonLanguages,
        frameworks: commonFrameworks,
        libraries: commonLibraries,
        buildTools: ["Maven", "Gradle", "SBT", "Ant", "Make", "CMake", "Bazel"],
        packageManagers: packageManagersList,
        linters: ["Checkstyle", "PMD", "SpotBugs", "SonarQube"],
        formatters: ["google-java-format", "clang-format", "ktlint"],
        testingTools: commonTestingTools,
        ormTools: ormToolsList,
        auth: ["OAuth2", "OpenID Connect", "JWT", "Keycloak", "Auth0", "AWS Cognito", "Okta"],
    },
    infrastructure: {
        clouds: [
            "AWS",
            "Google Cloud",
            "Azure",
            "Heroku",
            "DigitalOcean",
            "Vercel",
            "Firebase",
            "IBM Cloud",
            "Oracle Cloud",
            "Linode",
        ],
        operatingSystems: [
            "Linux",
            "Ubuntu",
            "Red Hat Enterprise Linux",
            "CentOS",
            "Debian",
            "Alpine Linux",
            "Amazon Linux",
            "Windows",
            "Windows Server",
            "macOS",
        ],
        containers: [
            "Docker",
            "Kubernetes",
            "Amazon ECS",
            "Google GKE",
            "Azure AKS",
            "Docker Compose",
            "Podman",
            "OpenShift",
            "Nomad",
        ],
        databases: [
            // リレーショナルデータベース
            "PostgreSQL",
            "MySQL",
            "MariaDB",
            "SQLite",
            "Microsoft SQL Server",
            "Oracle Database",
            "IBM Db2",
            // NoSQLデータベース
            "MongoDB",
            "Cassandra",
            "Redis",
            "CouchDB",
            "Elasticsearch",
            "Neo4j",
            // その他
            "Firebase Realtime Database",
            "Amazon DynamoDB",
            "Google Cloud Spanner",
        ].sort(),
        webServers: [
            "Apache",
            "Nginx",
            "Microsoft IIS",
            "Caddy",
            "LiteSpeed",
            "Tomcat",
            "Jetty",
            "Node.js",
            "Gunicorn",
            "uWSGI",
        ].sort(),
        ciCdTools: [
            "GitHub Actions",
            "CircleCI",
            "Jenkins",
            "GitLab CI",
            "ArgoCD",
            "Travis CI",
            "Drone CI",
            "Azure Pipelines",
            "AWS CodePipeline",
            "Bitbucket Pipelines",
        ],
        iacTools: [
            "Terraform",
            "AWS CDK",
            "Pulumi",
            "CloudFormation",
            "Ansible",
            "Chef",
            "Puppet",
            "SaltStack",
            "Vagrant",
        ],
        monitoringTools: [
            "Datadog",
            "Prometheus",
            "Grafana",
            "New Relic",
            "Sentry",
            "Dynatrace",
            "AppDynamics",
            "Nagios",
            "Zabbix",
            "Splunk Observability",
        ],
        loggingTools: [
            "CloudWatch Logs",
            "OpenSearch",
            "Elasticsearch",
            "Splunk",
            "Logstash",
            "Fluentd",
            "Loki",
            "Graylog",
            "Papertrail",
        ],
    },
    tools: {
        sourceControls: [
            "GitHub Enterprise",
            "GitLab",
            "Bitbucket",
            "Azure DevOps",
            "AWS CodeCommit",
            "Gerrit",
            "Gitea",
            "Perforce",
        ],
        projectManagements: [
            "Jira",
            "Monday.com",
            "Trello",
            "Asana",
            "ClickUp",
            "Shortcut",
            "Azure Boards",
            "Wrike",
            "Kanbanize",
        ],
        communicationTools: [
            "Slack",
            "Microsoft Teams",
            "Discord",
            "Zoom",
            "Google Meet",
            "Mattermost",
            "RocketChat",
            "Webex",
        ],
        documentationTools: [
            "Notion",
            "Confluence",
            "GitBook",
            "DocuSaurus",
            "VuePress",
            "MkDocs",
            "Wiki.js",
            "Obsidian",
        ],
        apiDevelopmentTools: [
            "OpenAPI (Swagger)",
            "Postman",
            "Insomnia",
            "GraphQL",
            "Apollo Studio",
            "Stoplight",
            "Hoppscotch",
            "gRPC",
        ],
        designTools: ["Figma", "Adobe XD", "Sketch", "InVision", "Zeplin", "Protopie", "Framer", "Canva", "Balsamiq"],
        editors: [
            "Visual Studio Code",
            "IntelliJ IDEA",
            "WebStorm",
            "PyCharm",
            "Rider",
            "Eclipse",
            "NetBeans",
            "Vim",
            "Neovim",
            "Emacs",
        ],
        developmentEnvironments: [
            "Windows",
            "macOS",
            "Linux",
            "WSL",
            "Docker Desktop",
            "GitHub Codespaces",
            "Local VM",
        ],
    },
} as const;
