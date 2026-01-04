-- ユーザーテーブル
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE,
    password VARCHAR(255),
    username VARCHAR(255),
    profile_image VARCHAR(255),
    two_factor_auth_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL
);

COMMENT ON TABLE users IS 'ユーザー';
COMMENT ON COLUMN users.id IS '識別子';
COMMENT ON COLUMN users.email IS 'メールアドレス';
COMMENT ON COLUMN users.password IS 'パスワード';
COMMENT ON COLUMN users.username IS 'ユーザー名';
COMMENT ON COLUMN users.profile_image IS 'プロフィール画像';
COMMENT ON COLUMN users.two_factor_auth_enabled IS '二段階認証設定';
COMMENT ON COLUMN users.created_at IS '作成日時';
COMMENT ON COLUMN users.updated_at IS '更新日時';

-- 外部認証連携テーブル
CREATE TABLE user_auth_providers (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    provider_name VARCHAR(50) NOT NULL,
    provider_user_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL
);

COMMENT ON TABLE user_auth_providers IS '外部認証連携';
COMMENT ON COLUMN user_auth_providers.id IS '識別子';
COMMENT ON COLUMN user_auth_providers.user_id IS 'ユーザーID';
COMMENT ON COLUMN user_auth_providers.provider_name IS 'プロバイダー名';
COMMENT ON COLUMN user_auth_providers.provider_user_id IS 'プロバイダ側ユーザーID';
COMMENT ON COLUMN user_auth_providers.created_at IS '作成日時';
COMMENT ON COLUMN user_auth_providers.updated_at IS '更新日時';

-- ロールテーブル
CREATE TABLE roles (
    id UUID PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL
);

COMMENT ON TABLE roles IS 'ロール';
COMMENT ON COLUMN roles.id IS 'ロールID';
COMMENT ON COLUMN roles.name IS 'ロール名(例: USER, ADMIN)';
COMMENT ON COLUMN roles.created_at IS '作成日時';
COMMENT ON COLUMN roles.updated_at IS '更新日時';

-- ユーザーとロールの紐付け
CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id),
    created_at TIMESTAMP(6) NOT NULL,
    PRIMARY KEY (user_id, role_id)
);

COMMENT ON TABLE user_roles IS 'ユーザー-ロール紐付け';
COMMENT ON COLUMN user_roles.user_id IS 'ユーザーID';
COMMENT ON COLUMN user_roles.role_id IS 'ロールID';
COMMENT ON COLUMN user_roles.created_at IS '付与日時';

-- 職務経歴書テーブル
CREATE TABLE resumes (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    name VARCHAR(255) NOT NULL,
    date DATE NOT NULL,
    last_name VARCHAR(255),
    first_name VARCHAR(255),
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL
);

COMMENT ON TABLE resumes IS '職務経歴書';
COMMENT ON COLUMN resumes.id IS '識別子';
COMMENT ON COLUMN resumes.user_id IS 'ユーザーID';
COMMENT ON COLUMN resumes.name IS '職務経歴書名';
COMMENT ON COLUMN resumes.last_name IS '姓';
COMMENT ON COLUMN resumes.first_name IS '名';
COMMENT ON COLUMN resumes.date IS '作成日';
COMMENT ON COLUMN resumes.created_at IS '作成日時';
COMMENT ON COLUMN resumes.updated_at IS '更新日時';

-- 職歴テーブル
CREATE TABLE careers (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    company_name VARCHAR(255) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    is_active BOOLEAN NOT NULL
);

COMMENT ON TABLE careers IS '職歴';
COMMENT ON COLUMN careers.id IS '識別子';
COMMENT ON COLUMN careers.resume_id IS '職務経歴書ID';
COMMENT ON COLUMN careers.company_name IS '会社名';
COMMENT ON COLUMN careers.start_date IS '入社年月';
COMMENT ON COLUMN careers.end_date IS '退職年月';
COMMENT ON COLUMN careers.is_active IS '在籍中フラグ';

-- プロジェクトテーブル
CREATE TABLE projects (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    company_name VARCHAR(255) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    is_active BOOLEAN NOT NULL,
    name VARCHAR(255) NOT NULL,
    overview VARCHAR(255) NOT NULL,
    team_comp VARCHAR(255) NOT NULL,
    role VARCHAR(255) NOT NULL,
    achievement TEXT NOT NULL,
    requirements BOOLEAN NOT NULL,
    basic_design BOOLEAN NOT NULL,
    detailed_design BOOLEAN NOT NULL,
    implementation BOOLEAN NOT NULL,
    integration_test BOOLEAN NOT NULL,
    system_test BOOLEAN NOT NULL,
    maintenance BOOLEAN NOT NULL
);

COMMENT ON TABLE projects IS 'プロジェクト';
COMMENT ON COLUMN projects.id IS '識別子';
COMMENT ON COLUMN projects.resume_id IS '職務経歴書ID';
COMMENT ON COLUMN projects.company_name IS '会社名';
COMMENT ON COLUMN projects.start_date IS '開始年月';
COMMENT ON COLUMN projects.end_date IS '終了年月';
COMMENT ON COLUMN projects.is_active IS '継続中フラグ';
COMMENT ON COLUMN projects.name IS 'プロジェクト名';
COMMENT ON COLUMN projects.overview IS '概要';
COMMENT ON COLUMN projects.team_comp IS 'チーム構成';
COMMENT ON COLUMN projects.role IS '役割';
COMMENT ON COLUMN projects.achievement IS '成果';
COMMENT ON COLUMN projects.requirements IS '要件定義';
COMMENT ON COLUMN projects.basic_design IS '基本設計';
COMMENT ON COLUMN projects.detailed_design IS '詳細設計';
COMMENT ON COLUMN projects.implementation IS '実装・単体テスト';
COMMENT ON COLUMN projects.integration_test IS '結合テスト';
COMMENT ON COLUMN projects.system_test IS '総合テスト';
COMMENT ON COLUMN projects.maintenance IS '運用・保守';

-- プロジェクト技術スタックテーブル
CREATE TABLE project_tech_stacks (
    project_id UUID PRIMARY KEY REFERENCES projects(id),

    -- TechStack - Frontend
    frontend_languages TEXT[],
    frontend_framework TEXT[],
    frontend_libraries TEXT[],
    frontend_build_tool TEXT[],
    frontend_package_manager TEXT[],
    frontend_linters TEXT[],
    frontend_formatters TEXT[],
    frontend_testing_tools TEXT[],

    -- TechStack - Backend
    backend_languages TEXT[],
    backend_framework TEXT[],
    backend_libraries TEXT[],
    backend_build_tool TEXT[],
    backend_package_manager TEXT[],
    backend_linters TEXT[],
    backend_formatters TEXT[],
    backend_testing_tools TEXT[],
    orm_tools TEXT[],
    auth TEXT[],

    -- TechStack - Infrastructure
    clouds TEXT[],
    operating_system TEXT[],
    containers TEXT[],
    database TEXT[],
    web_server TEXT[],
    ci_cd_tool TEXT[],
    iac_tools TEXT[],
    monitoring_tools TEXT[],
    logging_tools TEXT[],

    -- TechStack - Tools
    source_control TEXT[],
    project_management TEXT[],
    communication_tool TEXT[],
    documentation_tools TEXT[],
    api_development_tools TEXT[],
    design_tools TEXT[],
    editor TEXT[],
    development_environment TEXT[]
);

COMMENT ON TABLE project_tech_stacks IS 'プロジェクト技術スタック';

-- TechStack - Frontend
COMMENT ON COLUMN project_tech_stacks.frontend_languages IS 'フロントエンド開発言語';
COMMENT ON COLUMN project_tech_stacks.frontend_framework IS 'フロントエンドフレームワーク';
COMMENT ON COLUMN project_tech_stacks.frontend_libraries IS 'フロントエンドライブラリ';
COMMENT ON COLUMN project_tech_stacks.frontend_build_tool IS 'フロントエンドビルドツール';
COMMENT ON COLUMN project_tech_stacks.frontend_package_manager IS 'フロントエンドパッケージマネージャー';
COMMENT ON COLUMN project_tech_stacks.frontend_linters IS 'フロントエンドリンター';
COMMENT ON COLUMN project_tech_stacks.frontend_formatters IS 'フロントエンドフォーマッター';
COMMENT ON COLUMN project_tech_stacks.frontend_testing_tools IS 'フロントエンドテストツール';

-- TechStack - Backend
COMMENT ON COLUMN project_tech_stacks.backend_languages IS 'バックエンド開発言語';
COMMENT ON COLUMN project_tech_stacks.backend_framework IS 'バックエンドフレームワーク';
COMMENT ON COLUMN project_tech_stacks.backend_libraries IS 'バックエンドライブラリ';
COMMENT ON COLUMN project_tech_stacks.backend_build_tool IS 'バックエンドビルドツール';
COMMENT ON COLUMN project_tech_stacks.backend_package_manager IS 'バックエンドパッケージマネージャー';
COMMENT ON COLUMN project_tech_stacks.backend_linters IS 'バックエンドリンター';
COMMENT ON COLUMN project_tech_stacks.backend_formatters IS 'バックエンドフォーマッター';
COMMENT ON COLUMN project_tech_stacks.backend_testing_tools IS 'バックエンドテストツール';
COMMENT ON COLUMN project_tech_stacks.orm_tools IS 'ORMツール';
COMMENT ON COLUMN project_tech_stacks.auth IS '認証関連技術';

-- TechStack - Infrastructure
COMMENT ON COLUMN project_tech_stacks.clouds IS 'クラウド';
COMMENT ON COLUMN project_tech_stacks.operating_system IS 'OS';
COMMENT ON COLUMN project_tech_stacks.containers IS 'コンテナ';
COMMENT ON COLUMN project_tech_stacks.database IS 'データベース';
COMMENT ON COLUMN project_tech_stacks.web_server IS 'Webサーバー';
COMMENT ON COLUMN project_tech_stacks.ci_cd_tool IS 'CI/CDツール';
COMMENT ON COLUMN project_tech_stacks.iac_tools IS 'IaCツール';
COMMENT ON COLUMN project_tech_stacks.monitoring_tools IS '監視ツール';
COMMENT ON COLUMN project_tech_stacks.logging_tools IS 'ロギングツール';

-- TechStack - Tools
COMMENT ON COLUMN project_tech_stacks.source_control IS 'ソース管理';
COMMENT ON COLUMN project_tech_stacks.project_management IS 'プロジェクト管理';
COMMENT ON COLUMN project_tech_stacks.communication_tool IS 'コミュニケーション';
COMMENT ON COLUMN project_tech_stacks.documentation_tools IS 'ドキュメント';
COMMENT ON COLUMN project_tech_stacks.api_development_tools IS 'API開発';
COMMENT ON COLUMN project_tech_stacks.design_tools IS 'デザイン';
COMMENT ON COLUMN project_tech_stacks.editor IS 'エディタ';
COMMENT ON COLUMN project_tech_stacks.development_environment IS '開発環境';

-- 資格テーブル
CREATE TABLE certifications (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    name VARCHAR(255) NOT NULL,
    date DATE NOT NULL
);

COMMENT ON TABLE certifications IS '資格';
COMMENT ON COLUMN certifications.id IS '識別子';
COMMENT ON COLUMN certifications.resume_id IS '職務経歴書ID';
COMMENT ON COLUMN certifications.name IS '資格名';
COMMENT ON COLUMN certifications.date IS '取得日';

-- ポートフォリオテーブル
CREATE TABLE portfolios (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    name VARCHAR(255) NOT NULL,
    overview VARCHAR(255) NOT NULL,
    tech_stack TEXT NOT NULL,
    link VARCHAR(255) NOT NULL
);

COMMENT ON TABLE portfolios IS 'ポートフォリオ';
COMMENT ON COLUMN portfolios.id IS '識別子';
COMMENT ON COLUMN portfolios.resume_id IS '職務経歴書ID';
COMMENT ON COLUMN portfolios.name IS 'ポートフォリオ名';
COMMENT ON COLUMN portfolios.overview IS '概要';
COMMENT ON COLUMN portfolios.tech_stack IS '技術スタック';
COMMENT ON COLUMN portfolios.link IS 'リンク';

-- SNSプラットフォームテーブル
CREATE TABLE sns_platforms (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    name VARCHAR(255) NOT NULL,
    link VARCHAR(255) NOT NULL
);

COMMENT ON TABLE sns_platforms IS 'SNSプラットフォーム';
COMMENT ON COLUMN sns_platforms.id IS '識別子';
COMMENT ON COLUMN sns_platforms.resume_id IS '職務経歴書ID';
COMMENT ON COLUMN sns_platforms.name IS 'プラットフォーム名';
COMMENT ON COLUMN sns_platforms.link IS 'リンク';

-- 自己PRテーブル
CREATE TABLE self_promotions (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL
);

COMMENT ON TABLE self_promotions IS '自己PR';
COMMENT ON COLUMN self_promotions.id IS '識別子';
COMMENT ON COLUMN self_promotions.resume_id IS '職務経歴書ID';
COMMENT ON COLUMN self_promotions.title IS 'タイトル';
COMMENT ON COLUMN self_promotions.content IS 'コンテンツ';

-- 技術スタックカテゴリマスタテーブル
CREATE TABLE tech_stack_category_mst (
    code VARCHAR(64) PRIMARY KEY,
    main_category VARCHAR(32) NOT NULL,
    sub_category VARCHAR(64) NOT NULL
);

COMMENT ON TABLE tech_stack_category_mst IS '技術スタックカテゴリマスタ';
COMMENT ON COLUMN tech_stack_category_mst.code IS 'カテゴリコード';
COMMENT ON COLUMN tech_stack_category_mst.main_category IS 'メインカテゴリ';
COMMENT ON COLUMN tech_stack_category_mst.sub_category IS 'サブカテゴリ';

-- 技術スタックマスタテーブル
CREATE TABLE tech_stack_mst (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category_code VARCHAR(64) NOT NULL REFERENCES tech_stack_category_mst(code)
);

COMMENT ON TABLE tech_stack_mst IS '技術スタックマスタ';
COMMENT ON COLUMN tech_stack_mst.id IS '識別子';
COMMENT ON COLUMN tech_stack_mst.name IS '技術名';
COMMENT ON COLUMN tech_stack_mst.category_code IS 'カテゴリコード';

-- 資格マスタテーブル
CREATE TABLE certification_mst (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

COMMENT ON TABLE certification_mst IS '資格マスタ';
COMMENT ON COLUMN certification_mst.id IS '識別子';
COMMENT ON COLUMN certification_mst.name IS '資格名';

-- SNSプラットフォームマスタテーブル
CREATE TABLE sns_platform_mst (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

COMMENT ON TABLE sns_platform_mst IS 'SNSプラットフォームマスタ';
COMMENT ON COLUMN sns_platform_mst.id IS '識別子';
COMMENT ON COLUMN sns_platform_mst.name IS 'プラットフォーム名';
