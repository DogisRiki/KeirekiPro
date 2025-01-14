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
        title: "開発言語",
        fields: [{ label: "プログラミング言語", path: ["languages"] }],
    },
    {
        title: "依存関係",
        fields: [
            { label: "フレームワーク", path: ["dependencies", "frameworks"] },
            { label: "ライブラリ", path: ["dependencies", "libraries"] },
            { label: "テストツール", path: ["dependencies", "testingTools"] },
            { label: "ORM", path: ["dependencies", "ormTools"] },
            { label: "パッケージマネージャー", path: ["dependencies", "packageManagers"] },
        ],
    },
    {
        title: "インフラ・開発環境",
        fields: [
            { label: "クラウド", path: ["infrastructure", "clouds"] },
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
        title: "開発ツール・プロジェクト管理",
        fields: [
            { label: "ソース管理", path: ["tools", "sourceControls"] },
            { label: "プロジェクト管理", path: ["tools", "projectManagements"] },
            { label: "コミュニケーション", path: ["tools", "communicationTools"] },
            { label: "ドキュメント", path: ["tools", "documentationTools"] },
            { label: "API開発", path: ["tools", "apiDevelopmentTools"] },
            { label: "デザイン", path: ["tools", "designTools"] },
        ],
    },
];

/**
 * 技術スタック一覧
 * ※DB管理にしたい
 */
export const teckStackList: TechStack = {
    languages: [
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
    ].sort(),
    dependencies: {
        frameworks: [
            // JavaScript/TypeScript
            "React",
            "Angular",
            "Vue.js",
            "Svelte",
            // JavaScript/TypeScript
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
        ].sort(),
        libraries: [
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
        ],
        testingTools: [
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
        ].sort(),
        ormTools: [
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
        ].sort(),
        packageManagers: [
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
        ],
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
    },
} as const;
