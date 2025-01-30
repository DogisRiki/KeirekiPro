-- カテゴリマスタデータ
INSERT INTO tech_stack_category_mst (id, name) VALUES
    (1, '開発言語'),
    (2, 'フレームワーク'),
    (3, 'ライブラリ'),
    (4, 'テストツール'),
    (5, 'ORMツール'),
    (6, 'パッケージマネージャー'),
    (7, 'クラウド'),
    (8, 'コンテナ'),
    (9, 'データベース'),
    (10, 'Webサーバー'),
    (11, 'CI/CDツール'),
    (12, 'IaCツール'),
    (13, '監視ツール'),
    (14, 'ロギングツール'),
    (15, 'ソース管理'),
    (16, 'プロジェクト管理'),
    (17, 'コミュニケーション'),
    (18, 'ドキュメント'),
    (19, 'API開発'),
    (20, 'デザイン');

-- 開発言語
INSERT INTO tech_stack_mst (name, category)
SELECT
    ROW_NUMBER() OVER () AS id, name, category
FROM (
    VALUES
        -- コンパイル言語
        ('Java', 1),
        ('C++', 1),
        ('C#', 1),
        ('C', 1),
        ('Go', 1),
        ('Rust', 1),
        ('Swift', 1),
        ('Kotlin', 1),
        ('Scala', 1),
        ('Objective-C', 1),
        ('Visual Basic', 1),
        ('Delphi', 1),
        ('COBOL', 1),
        ('Fortran', 1),
        ('Ada', 1),
        ('Pascal', 1),
        ('Haskell', 1),

        -- インタープリタ言語
        ('Python', 1),
        ('JavaScript', 1),
        ('TypeScript', 1),
        ('PHP', 1),
        ('Ruby', 1),
        ('Perl', 1),
        ('R', 1),
        ('Lua', 1),
        ('MATLAB', 1),
        ('Dart', 1),
        ('Julia', 1),
        ('Groovy', 1),

        -- 関数型言語
        ('Erlang', 1),
        ('Elixir', 1),
        ('F#', 1),
        ('OCaml', 1),
        ('Clojure', 1),
        ('Lisp', 1),
        ('Scheme', 1),

    -- フレームワーク
        -- Java
        ('Spring Framework', 2),
        ('Spring Boot', 2),
        ('Jakarta EE', 2),

        -- Python
        ('Django', 2),
        ('Flask', 2),
        ('FastAPI', 2),

        -- JavaScript/TypeScript (Frontend)
        ('React', 2),
        ('Angular', 2),
        ('Vue.js', 2),
        ('Next.js', 2),
        ('Nuxt.js', 2),

        -- JavaScript/TypeScript (Backend)
        ('Express.js', 2),
        ('NestJS', 2),

        -- PHP
        ('Laravel', 2),
        ('Symfony', 2),
        ('CodeIgniter', 2),

        -- Ruby
        ('Ruby on Rails', 2),
        ('Sinatra', 2),

        -- Go
        ('Gin', 2),
        ('Echo', 2),

        -- .NET
        ('ASP.NET Core', 2),
        ('ASP.NET MVC', 2),

    -- ライブラリ
        -- =====================================================
        -- JavaScript/TypeScript
        -- =====================================================
        -- 状態管理
        ('Redux', 3),
        ('Zustand', 3),
        ('Recoil', 3),
        ('Jotai', 3),
        ('XState', 3),
        ('MobX', 3),
        ('Valtio', 3),

        -- データフェッチ/キャッシュ
        ('Tanstack Query', 3),
        ('SWR', 3),
        ('Apollo Client', 3),
        ('RTK Query', 3),
        ('urql', 3),

        -- HTTP
        ('Axios', 3),
        ('ky', 3),
        ('got', 3),

        -- バリデーション/型
        ('Zod', 3),
        ('Yup', 3),
        ('io-ts', 3),
        ('class-validator', 3),
        ('type-graphql', 3),

        -- フォーム
        ('React Hook Form', 3),
        ('Formik', 3),
        ('Final Form', 3),

        -- 日付/時間
        ('date-fns', 3),
        ('Day.js', 3),
        ('Luxon', 3),

        -- ユーティリティ
        ('Lodash', 3),
        ('Ramda', 3),
        ('fp-ts', 3),
        ('Radash', 3),

        -- アニメーション
        ('Framer Motion', 3),
        ('React Spring', 3),
        ('AutoAnimate', 3),
        ('GSAP', 3),

        -- チャート/ビジュアライゼーション
        ('D3.js', 3),
        ('Chart.js', 3),
        ('Recharts', 3),
        ('Victory', 3),
        ('Nivo', 3),

        -- UI関連
        ('clsx', 3),
        ('tailwind-merge', 3),
        ('class-variance-authority', 3),
        ('cmdk', 3),

        -- その他
        ('Storybook', 3),

        -- CSSフレームワーク/UIライブラリ
        ('Tailwind CSS', 3),
        ('Bootstrap', 3),
        ('Material-UI (MUI)', 3),
        ('Chakra UI', 3),
        ('Ant Design', 3),
        ('shadcn/ui', 3),
        ('DaisyUI', 3),
        ('Radix UI', 3),
        ('Mantine', 3),
        ('styled-components', 3),
        ('Emotion', 3),
        ('Sass', 3),
        ('Bulma', 3),
        ('Foundation', 3),
        ('WindiCSS', 3),
        ('UnoCSS', 3),
        ('PrimeReact', 3),
        ('NextUI', 3),
        ('Headless UI', 3),

        -- 静的解析/Linter
        ('ESLint', 3),
        ('TypeScript ESLint', 3),
        ('stylelint', 3),

        -- フォーマッター
        ('Prettier', 3),
        ('dprint', 3),
        ('Rome', 3),
        ('Biome', 3),

        -- =====================================================
        -- Python
        -- =====================================================
        -- データ処理/解析
        ('NumPy', 3),
        ('Pandas', 3),

        -- HTTP/ネットワーク
        ('Requests', 3),

        -- 画像処理
        ('Pillow', 3),

        -- データベース
        ('SQLAlchemy', 3),

        -- スクレイピング
        ('Beautiful Soup', 3),

        -- 静的解析/Linter
        ('Pylint', 3),
        ('Flake8', 3),
        ('mypy', 3),
        ('Pyright', 3),
        ('Ruff', 3),

        -- フォーマッター
        ('Black', 3),
        ('YAPF', 3),
        ('autopep8', 3),
        ('isort', 3),

        -- =====================================================
        -- Java
        -- =====================================================
        -- ユーティリティ
        ('Lombok', 3),
        ('Jackson', 3),
        ('Guava', 3),

        -- ロギング
        ('SLF4J', 3),
        ('Log4j', 3),

        -- 静的解析
        ('Checkstyle', 3),
        ('PMD', 3),
        ('SpotBugs', 3),
        ('SonarLint', 3),

        -- フォーマッター
        ('google-java-format', 3),
        ('Eclipse formatter', 3),

        -- =====================================================
        -- PHP
        -- =====================================================
        -- ユーティリティ
        ('Carbon', 3),
        ('Guzzle', 3),
        ('Monolog', 3),

        -- 静的解析
        ('PHP_CodeSniffer', 3),
        ('PHPStan', 3),
        ('PHP Mess Detector', 3),

        -- フォーマッター
        ('PHP-CS-Fixer', 3),

        -- =====================================================
        -- Ruby
        -- =====================================================
        -- ユーティリティ
        ('Nokogiri', 3),
        ('Faraday', 3),

        -- 静的解析
        ('RuboCop', 3),
        ('Reek', 3),

        -- =====================================================
        -- Go
        -- =====================================================
        -- ユーティリティ
        ('Gorm', 3),
        ('Cobra', 3),

        -- 静的解析
        ('golangci-lint', 3),
        ('staticcheck', 3),

        -- フォーマッター
        ('gofmt', 3),
        ('goimports', 3),

        -- =====================================================
        -- C#
        -- =====================================================
        -- ユーティリティ
        ('Newtonsoft.Json', 3),
        ('Serilog', 3),
        ('Dapper', 3),

        -- 静的解析
        ('StyleCop', 3),
        ('FxCop', 3),
        ('Roslynator', 3),

        -- フォーマッター
        ('CSharpier', 3),
        ('dotnet format', 3),

    -- テストツール
        -- =====================================================
        -- JavaScript/TypeScript
        -- =====================================================
        -- ユニットテスト
        ('Jest', 4),
        ('Vitest', 4),
        ('Mocha', 4),
        ('Jasmine', 4),
        ('AVA', 4),
        ('tape', 4),
        ('uvu', 4),

        -- UIテスト
        ('Testing Library', 4),
        ('Enzyme', 4),

        -- E2Eテスト
        ('Cypress', 4),
        ('Playwright', 4),
        ('Puppeteer', 4),
        ('TestCafe', 4),
        ('Nightwatch.js', 4),
        ('WebdriverIO', 4),

        -- ビジュアルリグレッションテスト
        ('Percy', 4),
        ('reg-suit', 4),
        ('Chromatic', 4),
        ('BackstopJS', 4),

        -- テストモック/スタブ
        ('Mock Service Worker (MSW)', 4),
        ('Sinon.js', 4),
        ('Nock', 4),
        ('testdouble.js', 4),

        -- スナップショットテスト
        ('Jest Snapshot', 4),
        ('Storyshots', 4),

        -- カバレッジ
        ('Istanbul', 4),
        ('c8', 4),

        -- テストデータ生成
        ('Faker.js', 4),
        ('Chance.js', 4),

        -- コンポーネントテスト
        ('Storybook', 4),
        ('Ladle', 4),
        ('Histoire', 4),

        -- =====================================================
        -- Python
        -- =====================================================
        -- ユニットテスト
        ('pytest', 4),
        ('unittest', 4),
        ('nose', 4),
        ('doctest', 4),

        -- モック
        ('pytest-mock', 4),
        ('unittest.mock', 4),
        ('responses', 4),

        -- カバレッジ
        ('Coverage.py', 4),
        ('pytest-cov', 4),

        -- ビヘイビアテスト
        ('behave', 4),
        ('pytest-bdd', 4),

        -- =====================================================
        -- Java
        -- =====================================================
        -- ユニットテスト
        ('JUnit', 4),
        ('TestNG', 4),

        -- モック
        ('Mockito', 4),
        ('PowerMock', 4),
        ('EasyMock', 4),

        -- アサーション
        ('AssertJ', 4),
        ('Hamcrest', 4),

        -- 統合テスト
        ('Arquillian', 4),
        ('Spring Test', 4),

        -- カバレッジ
        ('JaCoCo', 4),
        ('OpenClover', 4),

        -- E2E/UIテスト
        ('Selenium WebDriver', 4),
        ('Selenide', 4),

        -- パフォーマンステスト
        ('JMeter', 4),
        ('Gatling', 4),

        -- =====================================================
        -- PHP
        -- =====================================================
        -- ユニットテスト
        ('PHPUnit', 4),
        ('Pest', 4),
        ('Codeception', 4),
        ('PHPSpec', 4),

        -- モック
        ('Mockery', 4),
        ('Prophecy', 4),

        -- カバレッジ
        ('PHPUnit Code Coverage', 4),
        ('Xdebug', 4),

        -- ビヘイビアテスト
        ('Behat', 4),

        -- =====================================================
        -- Ruby
        -- =====================================================
        -- ユニットテスト
        ('RSpec', 4),
        ('Test::Unit', 4),
        ('Minitest', 4),

        -- モック
        ('RSpec Mocks', 4),
        ('Mocha', 4),

        -- 統合テスト
        ('Capybara', 4),

        -- ビヘイビアテスト
        ('Cucumber', 4),

        -- カバレッジ
        ('SimpleCov', 4),

        -- =====================================================
        -- Go
        -- =====================================================
        -- ユニットテスト
        ('testing package', 4),
        ('testify', 4),
        ('gocheck', 4),

        -- モック
        ('gomock', 4),
        ('go-sqlmock', 4),

        -- ビヘイビアテスト
        ('Ginkgo', 4),
        ('Gomega', 4),

        -- カバレッジ
        ('go test -cover', 4),

        -- =====================================================
        -- C#
        -- =====================================================
        -- ユニットテスト
        ('MSTest', 4),
        ('NUnit', 4),
        ('xUnit.net', 4),

        -- モック
        ('Moq', 4),
        ('NSubstitute', 4),
        ('FakeItEasy', 4),

        -- アサーション
        ('FluentAssertions', 4),
        ('Shouldly', 4),

        -- カバレッジ
        ('Visual Studio Code Coverage', 4),
        ('OpenCover', 4),
        ('dotCover', 4),

        -- UIテスト
        ('Selenium for C#', 4),
        ('SpecFlow', 4),
        ('Microsoft Playwright', 4),

    -- ORM
        -- =====================================================
        -- JavaScript/TypeScript
        -- =====================================================
        -- SQL系
        ('Prisma', 5),
        ('TypeORM', 5),
        ('Sequelize', 5),
        ('Knex.js', 5),
        ('MikroORM', 5),
        ('Objection.js', 5),
        ('Drizzle ORM', 5),

        -- NoSQL系
        ('Mongoose', 5),
        ('Typegoose', 5),

        -- GraphQL
        ('Prisma Client', 5),

        -- =====================================================
        -- Python
        -- =====================================================
        -- SQL系
        ('SQLAlchemy', 5),
        ('Django ORM', 5),
        ('Peewee', 5),
        ('Tortoise ORM', 5),
        ('SQLModel', 5),
        ('Pony ORM', 5),

        -- NoSQL系
        ('MongoEngine', 5),
        ('ODMantic', 5),
        ('Motor', 5),

        -- =====================================================
        -- Java
        -- =====================================================
        -- SQL系
        ('Hibernate', 5),
        ('EclipseLink', 5),
        ('MyBatis', 5),
        ('JOOQ', 5),
        ('Spring Data JPA', 5),

        -- NoSQL系
        ('Spring Data MongoDB', 5),
        ('Morphia', 5),

        -- =====================================================
        -- PHP
        -- =====================================================
        -- SQL系
        ('Doctrine', 5),
        ('Eloquent', 5),
        ('Propel', 5),

        -- NoSQL系
        ('Doctrine MongoDB ODM', 5),

        -- =====================================================
        -- Ruby
        -- =====================================================
        -- SQL系
        ('Active Record', 5),
        ('Sequel', 5),
        ('ROM', 5),

        -- NoSQL系
        ('Mongoid', 5),

        -- =====================================================
        -- Go
        -- =====================================================
        -- SQL系
        ('GORM', 5),
        ('SQLBoiler', 5),
        ('SQLX', 5),
        ('Ent', 5),

        -- NoSQL系
        ('MGM', 5),
        ('QMGO', 5),

        -- =====================================================
        -- C#
        -- =====================================================
        -- SQL系
        ('Entity Framework Core', 5),
        ('Dapper', 5),
        ('NHibernate', 5),
        ('ServiceStack.OrmLite', 5),

        -- NoSQL系
        ('MongoDB C# Driver', 5),
        ('Azure Cosmos DB SDK', 5),

    -- パッケージマネージャー
        -- =====================================================
        -- JavaScript/TypeScript
        -- =====================================================
        -- パッケージマネージャー
        ('npm', 6),
        ('yarn', 6),
        ('pnpm', 6),
        ('bun', 6),

        -- モノレポ
        ('Nx', 6),
        ('Turborepo', 6),
        ('Lerna', 6),

        -- =====================================================
        -- Python
        -- =====================================================
        -- パッケージマネージャー
        ('pip', 6),
        ('Poetry', 6),
        ('Pipenv', 6),
        ('conda', 6),

        -- 仮想環境
        ('venv', 6),
        ('virtualenv', 6),
        ('pyenv', 6),

        -- =====================================================
        -- Java
        -- =====================================================
        -- ビルド/依存関係
        ('Maven', 6),
        ('Gradle', 6),
        ('Ant', 6),
        ('Ivy', 6),

        -- =====================================================
        -- PHP
        -- =====================================================
        -- パッケージマネージャー
        ('Composer', 6),
        ('PEAR', 6),

        -- =====================================================
        -- Ruby
        -- =====================================================
        -- パッケージマネージャー
        ('RubyGems', 6),
        ('Bundler', 6),

        -- バージョン管理
        ('rbenv', 6),
        ('RVM', 6),

        -- =====================================================
        -- Go
        -- =====================================================
        -- モジュール管理
        ('Go Modules', 6),
        ('dep', 6),
        ('glide', 6),

        -- =====================================================
        -- C#
        -- =====================================================
        -- パッケージマネージャー
        ('NuGet', 6),
        ('dotnet CLI', 6),
        ('Paket', 6),

    -- クラウド
        -- =====================================================
        -- AWS
        -- =====================================================
        -- コンピュート
        ('AWS EC2', 7),
        ('AWS Lambda', 7),
        ('AWS ECS', 7),
        ('AWS EKS', 7),
        ('AWS Fargate', 7),
        ('AWS Batch', 7),
        ('AWS Lightsail', 7),

        -- ストレージ
        ('AWS S3', 7),
        ('AWS EBS', 7),
        ('AWS EFS', 7),
        ('AWS FSx', 7),
        ('AWS Storage Gateway', 7),

        -- データベース
        ('AWS RDS', 7),
        ('AWS DynamoDB', 7),
        ('AWS Aurora', 7),
        ('AWS ElastiCache', 7),
        ('AWS Redshift', 7),
        ('AWS DocumentDB', 7),
        ('AWS Neptune', 7),
        ('AWS Timestream', 7),

        -- ネットワーキング
        ('AWS VPC', 7),
        ('AWS Route 53', 7),
        ('AWS CloudFront', 7),
        ('AWS API Gateway', 7),
        ('AWS Direct Connect', 7),
        ('AWS Global Accelerator', 7),

        -- 開発者ツール
        ('AWS CodeBuild', 7),
        ('AWS CodePipeline', 7),
        ('AWS CodeDeploy', 7),
        ('AWS CodeCommit', 7),
        ('AWS Cloud9', 7),

        -- 監視/運用
        ('AWS CloudWatch', 7),
        ('AWS X-Ray', 7),
        ('AWS Systems Manager', 7),
        ('AWS CloudTrail', 7),
        ('AWS Config', 7),

        -- セキュリティ
        ('AWS IAM', 7),
        ('AWS KMS', 7),
        ('AWS WAF', 7),
        ('AWS Shield', 7),
        ('AWS GuardDuty', 7),
        ('AWS Secrets Manager', 7),

        -- 分析
        ('AWS Athena', 7),
        ('AWS EMR', 7),
        ('AWS Kinesis', 7),
        ('AWS QuickSight', 7),
        ('AWS Glue', 7),

        -- AI/ML
        ('AWS SageMaker', 7),
        ('AWS Rekognition', 7),
        ('AWS Comprehend', 7),
        ('AWS Polly', 7),
        ('AWS Textract', 7),

        -- アプリケーションサービス
        ('AWS SNS', 7),
        ('AWS SQS', 7),
        ('AWS AppSync', 7),
        ('AWS EventBridge', 7),

        -- =====================================================
        -- Microsoft Azure
        -- =====================================================
        -- コンピュート
        ('Azure Virtual Machines', 7),
        ('Azure Functions', 7),
        ('Azure Kubernetes Service', 7),
        ('Azure Container Instances', 7),
        ('Azure App Service', 7),
        ('Azure Service Fabric', 7),

        -- ストレージ
        ('Azure Blob Storage', 7),
        ('Azure Files', 7),
        ('Azure Disk Storage', 7),
        ('Azure Data Lake Storage', 7),

        -- データベース
        ('Azure SQL Database', 7),
        ('Azure Cosmos DB', 7),
        ('Azure Database for MySQL', 7),
        ('Azure Database for PostgreSQL', 7),
        ('Azure Cache for Redis', 7),
        ('Azure Synapse Analytics', 7),

        -- ネットワーキング
        ('Azure Virtual Network', 7),
        ('Azure Load Balancer', 7),
        ('Azure CDN', 7),
        ('Azure DNS', 7),
        ('Azure Front Door', 7),

        -- 開発者ツール
        ('Azure DevOps', 7),
        ('Azure Pipelines', 7),
        ('Azure Repos', 7),
        ('Azure Boards', 7),

        -- 監視/運用
        ('Azure Monitor', 7),
        ('Azure Log Analytics', 7),
        ('Azure Application Insights', 7),

        -- セキュリティ
        ('Azure Active Directory', 7),
        ('Azure Key Vault', 7),
        ('Azure Security Center', 7),
        ('Azure Sentinel', 7),

        -- AI/ML
        ('Azure Machine Learning', 7),
        ('Azure Cognitive Services', 7),
        ('Azure Bot Service', 7),

        -- =====================================================
        -- Google Cloud Platform
        -- =====================================================
        -- コンピュート
        ('Google Compute Engine', 7),
        ('Google Cloud Functions', 7),
        ('Google Kubernetes Engine', 7),
        ('Google Cloud Run', 7),
        ('Google App Engine', 7),

        -- ストレージ
        ('Google Cloud Storage', 7),
        ('Google Persistent Disk', 7),
        ('Google Filestore', 7),

        -- データベース
        ('Google Cloud SQL', 7),
        ('Google Cloud Spanner', 7),
        ('Google Cloud Bigtable', 7),
        ('Google Firebase Realtime Database', 7),
        ('Google Cloud Firestore', 7),
        ('Google Cloud Memorystore', 7),

        -- ネットワーキング
        ('Google Cloud VPC', 7),
        ('Google Cloud Load Balancing', 7),
        ('Google Cloud CDN', 7),
        ('Google Cloud DNS', 7),

        -- 開発者ツール
        ('Google Cloud Build', 7),
        ('Google Cloud Source Repositories', 7),
        ('Google Cloud Code', 7),

        -- 監視/運用
        ('Google Cloud Monitoring', 7),
        ('Google Cloud Logging', 7),
        ('Google Cloud Trace', 7),
        ('Google Cloud Debugger', 7),

        -- BigData
        ('Google BigQuery', 7),
        ('Google Cloud Dataflow', 7),
        ('Google Cloud Pub/Sub', 7),
        ('Google Cloud Dataproc', 7),

        -- AI/ML
        ('Google Cloud AI Platform', 7),
        ('Google Cloud Vision API', 7),
        ('Google Cloud Speech-to-Text', 7),
        ('Google Cloud Natural Language', 7),
        ('Google Cloud AutoML', 7),

        -- =====================================================
        -- その他のクラウド
        -- =====================================================
        -- 国産クラウド
        ('さくらのクラウド', 7),
        ('IDCFクラウド', 7),
        ('ニフクラ', 7),
        ('Alibaba Cloud', 7),
        ('Oracle Cloud', 7),
        ('IBM Cloud', 7),
        ('Vultr', 7),
        ('DigitalOcean', 7),
        ('Heroku', 7),
        ('Cloudflare', 7),
        ('Vercel', 7),
        ('Netlify', 7),
        ('Render', 7),

    -- コンテナ関連ツール
        -- コンテナ基盤
        ('Docker', 8),
        ('Docker Compose', 8),
        ('containerd', 8),
        ('Podman', 8),

        -- オーケストレーション
        ('Kubernetes', 8),
        ('OpenShift', 8),
        ('Docker Swarm', 8),

    -- データベース
        -- RDB
        ('PostgreSQL', 9),
        ('MySQL', 9),
        ('MariaDB', 9),
        ('Oracle Database', 9),
        ('SQL Server', 9),
        ('SQLite', 9),
        ('Amazon Aurora', 9),
        ('IBM Db2', 9),

        -- NoSQL - ドキュメント指向
        ('MongoDB', 9),
        ('CouchDB', 9),
        ('Amazon DocumentDB', 9),
        ('Azure Cosmos DB', 9),
        ('Couchbase', 9),
        ('RavenDB', 9),

        -- NoSQL - KVS
        ('Redis', 9),
        ('Memcached', 9),
        ('etcd', 9),
        ('Amazon DynamoDB', 9),
        ('Apache Cassandra', 9),

        -- NoSQL - ワイドカラム
        ('Apache HBase', 9),
        ('ScyllaDB', 9),

        -- NoSQL - グラフ
        ('Neo4j', 9),
        ('Amazon Neptune', 9),
        ('ArangoDB', 9),
        ('JanusGraph', 9),

        -- 検索エンジン
        ('Elasticsearch', 9),
        ('OpenSearch', 9),
        ('Solr', 9),
        ('Meilisearch', 9),
        ('Algolia', 9),

        -- 時系列DB
        ('InfluxDB', 9),
        ('TimescaleDB', 9),
        ('Prometheus TSDB', 9),
        ('Amazon Timestream', 9),

        -- NewSQL
        ('CockroachDB', 9),
        ('Google Cloud Spanner', 9),
        ('YugabyteDB', 9),

        -- 列指向DB
        ('ClickHouse', 9),
        ('Apache Druid', 9),
        ('Google BigQuery', 9),
        ('Amazon Redshift', 9),
        ('Snowflake', 9),

    -- Webサーバー
        ('Nginx', 10),
        ('Apache', 10),
        ('IIS', 10),
        ('Tomcat', 10),
        ('Jetty', 10),

    -- CI/CDツール
        ('Jenkins', 11),
        ('GitLab CI', 11),
        ('GitHub Actions', 11),
        ('CircleCI', 11),
        ('Travis CI', 11),
        ('TeamCity', 11),
        ('Drone', 11),
        ('Azure DevOps', 11),

    -- IaCツール
        ('Terraform', 12),
        ('AWS CloudFormation', 12),
        ('Ansible', 12),
        ('Puppet', 12),
        ('Chef', 12),
        ('Pulumi', 12),

    -- 監視ツール
        ('Prometheus', 13),
        ('Grafana', 13),
        ('Datadog', 13),
        ('New Relic', 13),
        ('Nagios', 13),
        ('Zabbix', 13),
        ('Mackerel', 13),

    -- ロギングツール
        ('Fluentd', 14),
        ('Logstash', 14),
        ('Elasticsearch', 14),
        ('Splunk', 14),
        ('Graylog', 14),
        ('rsyslog', 14),

    -- ソース管理
        -- バージョン管理システム
        ('Git', 15),
        ('Subversion', 15),
        ('Mercurial', 15),

        -- ホスティングサービス
        ('GitHub', 15),
        ('GitLab', 15),
        ('Bitbucket', 15),
        ('Azure DevOps', 15),

    -- プロジェクト管理
        -- タスク管理
        ('Jira', 16),
        ('Trello', 16),
        ('Asana', 16),
        ('GitHub Projects', 16),
        ('GitLab Issues', 16),
        ('Linear', 16),
        ('ClickUp', 16),
        ('Notion', 16),
        ('Redmine', 16),
        ('Monday.com', 16),
        ('Backlog', 16),

    -- コミュニケーション
        -- チャット/ビデオ会議
        ('Slack', 17),
        ('Microsoft Teams', 17),
        ('Discord', 17),
        ('Zoom', 17),
        ('Google Meet', 17),
        ('Mattermost', 17),
        ('Chatwork', 17),

    -- ドキュメント
        -- 文書作成/管理
        ('Notion', 18),
        ('Confluence', 18),
        ('Google Workspace', 18),
        ('Microsoft Office 365', 18),
        ('DocuWiki', 18),
        ('GitBook', 18),
        ('Markdown', 18),
        ('AsciiDoc', 18),

    -- API開発
        -- API設計/開発
        ('Swagger/OpenAPI', 19),
        ('Postman', 19),
        ('Insomnia', 19),
        ('Stoplight', 19),
        ('GraphQL', 19),
        ('gRPC', 19),
        ('REST', 19),
        ('AsyncAPI', 19),
        ('Hoppscotch', 19),

    -- デザイン
        -- UI/UXデザイン
        ('Figma', 20),
        ('Adobe XD', 20),
        ('Sketch', 20),
        ('Adobe Photoshop', 20),
        ('Adobe Illustrator', 20),
        ('Zeplin', 20),
        ('InVision', 20),
        ('Protopie', 20),
        ('Framer', 20)
) AS tech_stack(name, category);
