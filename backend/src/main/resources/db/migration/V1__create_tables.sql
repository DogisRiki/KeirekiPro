-- ユーザーテーブル
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    username VARCHAR(255) NOT NULL,
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
    provider_type VARCHAR(50) NOT NULL,
    provider_user_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL
);

COMMENT ON TABLE user_auth_providers IS '外部認証連携';
COMMENT ON COLUMN user_auth_providers.id IS '識別子';
COMMENT ON COLUMN user_auth_providers.user_id IS 'ユーザーID';
COMMENT ON COLUMN user_auth_providers.provider_type IS 'プロバイダー種別';
COMMENT ON COLUMN user_auth_providers.provider_user_id IS 'プロバイダ側ーID';
COMMENT ON COLUMN user_auth_providers.created_at IS '作成日時';
COMMENT ON COLUMN user_auth_providers.updated_at IS '更新日時';

-- 職務経歴書テーブル
CREATE TABLE resumes (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    name VARCHAR(255) NOT NULL,
    date DATE NOT NULL,
    auto_save_enabled BOOLEAN NOT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL,
    order_no INTEGER NOT NULL
);

COMMENT ON TABLE resumes IS '職務経歴書';
COMMENT ON COLUMN resumes.id IS '識別子';
COMMENT ON COLUMN resumes.user_id IS 'ユーザーID';
COMMENT ON COLUMN resumes.name IS '職務経歴書名';
COMMENT ON COLUMN resumes.date IS '作成日';
COMMENT ON COLUMN resumes.auto_save_enabled IS '自動保存有効フラグ';
COMMENT ON COLUMN resumes.created_at IS '作成日時';
COMMENT ON COLUMN resumes.updated_at IS '更新日時';
COMMENT ON COLUMN resumes.order_no IS '並び順';

-- 職歴テーブル
CREATE TABLE careers (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    company_name VARCHAR(255) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    is_active BOOLEAN NOT NULL,
    order_no INTEGER NOT NULL
);

COMMENT ON TABLE careers IS '職歴';
COMMENT ON COLUMN careers.id IS '識別子';
COMMENT ON COLUMN careers.resume_id IS '職務経歴書ID';
COMMENT ON COLUMN careers.company_name IS '会社名';
COMMENT ON COLUMN careers.start_date IS '入社年月';
COMMENT ON COLUMN careers.end_date IS '退職年月';
COMMENT ON COLUMN careers.is_active IS '在籍中フラグ';
COMMENT ON COLUMN careers.order_no IS '並び順';

-- プロジェクトテーブル
CREATE TABLE projects (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    company_name VARCHAR(255) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    is_active BOOLEAN NOT NULL,
    name VARCHAR(255) NOT NULL,
    overview VARCHAR(255),
    team_comp VARCHAR(255),
    role VARCHAR(255),
    achievement TEXT,
    requirements BOOLEAN,
    basic_design BOOLEAN,
    detailed_design BOOLEAN,
    implementation BOOLEAN,
    integration_test BOOLEAN,
    system_test BOOLEAN,
    maintenance BOOLEAN,
    languages ${text_array_type},
    frameworks ${text_array_type},
    libraries ${text_array_type},
    testing_tools ${text_array_type},
    orm_tools ${text_array_type},
    package_managers ${text_array_type},
    clouds ${text_array_type},
    containers ${text_array_type},
    databases ${text_array_type},
    web_servers ${text_array_type},
    ci_cd_tools ${text_array_type},
    iac_tools ${text_array_type},
    monitoring_tools ${text_array_type},
    logging_tools ${text_array_type},
    source_controls ${text_array_type},
    project_managements ${text_array_type},
    communication_tools ${text_array_type},
    documentation_tools ${text_array_type},
    api_development_tools ${text_array_type},
    design_tools ${text_array_type},
    order_no INTEGER NOT NULL
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
COMMENT ON COLUMN projects.languages IS '開発言語';
COMMENT ON COLUMN projects.frameworks IS 'フレームワーク';
COMMENT ON COLUMN projects.libraries IS 'ライブラリ';
COMMENT ON COLUMN projects.testing_tools IS 'テストツール';
COMMENT ON COLUMN projects.orm_tools IS 'ORMツール';
COMMENT ON COLUMN projects.package_managers IS 'パッケージマネージャー';
COMMENT ON COLUMN projects.clouds IS 'クラウド';
COMMENT ON COLUMN projects.containers IS 'コンテナ';
COMMENT ON COLUMN projects.databases IS 'データベース';
COMMENT ON COLUMN projects.web_servers IS 'Webサーバー';
COMMENT ON COLUMN projects.ci_cd_tools IS 'CI/CDツール';
COMMENT ON COLUMN projects.iac_tools IS 'IaCツール';
COMMENT ON COLUMN projects.monitoring_tools IS '監視ツール';
COMMENT ON COLUMN projects.logging_tools IS 'ロギングツール';
COMMENT ON COLUMN projects.source_controls IS 'ソース管理';
COMMENT ON COLUMN projects.project_managements IS 'プロジェクト管理';
COMMENT ON COLUMN projects.communication_tools IS 'コミュニケーション';
COMMENT ON COLUMN projects.documentation_tools IS 'ドキュメント';
COMMENT ON COLUMN projects.api_development_tools IS 'API開発';
COMMENT ON COLUMN projects.design_tools IS 'デザイン';
COMMENT ON COLUMN projects.order_no IS '並び順';

-- 資格テーブル
CREATE TABLE certifications (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    name VARCHAR(255),
    date DATE,
    order_no INTEGER NOT NULL
);

COMMENT ON TABLE certifications IS '資格';
COMMENT ON COLUMN certifications.id IS '識別子';
COMMENT ON COLUMN certifications.resume_id IS '職務経歴書ID';
COMMENT ON COLUMN certifications.name IS '資格名';
COMMENT ON COLUMN certifications.date IS '取得日';
COMMENT ON COLUMN certifications.order_no IS '並び順';

-- ポートフォリオテーブル
CREATE TABLE portfolios (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    name VARCHAR(255),
    overview VARCHAR(255),
    tech_stack TEXT,
    link VARCHAR(255),
    order_no INTEGER NOT NULL
);

COMMENT ON TABLE portfolios IS 'ポートフォリオ';
COMMENT ON COLUMN portfolios.id IS '識別子';
COMMENT ON COLUMN portfolios.resume_id IS '職務経歴書ID';
COMMENT ON COLUMN portfolios.name IS 'ポートフォリオ名';
COMMENT ON COLUMN portfolios.overview IS '概要';
COMMENT ON COLUMN portfolios.tech_stack IS '技術スタック';
COMMENT ON COLUMN portfolios.link IS 'リンク';
COMMENT ON COLUMN portfolios.order_no IS '並び順';

-- ソーシャルリンクテーブル
CREATE TABLE social_links (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    name VARCHAR(255),
    link VARCHAR(255),
    order_no INTEGER NOT NULL
);

COMMENT ON TABLE social_links IS 'ソーシャルリンク';
COMMENT ON COLUMN social_links.id IS '識別子';
COMMENT ON COLUMN social_links.resume_id IS '職務経歴書ID';
COMMENT ON COLUMN social_links.name IS 'ソーシャルリンク名';
COMMENT ON COLUMN social_links.link IS 'リンク';
COMMENT ON COLUMN social_links.order_no IS '並び順';

-- 自己PRテーブル
CREATE TABLE self_promotions (
    id UUID PRIMARY KEY,
    resume_id UUID NOT NULL REFERENCES resumes(id),
    title VARCHAR(255),
    content TEXT,
    order_no INTEGER NOT NULL
);

COMMENT ON TABLE self_promotions IS '自己PR';
COMMENT ON COLUMN self_promotions.id IS '識別子';
COMMENT ON COLUMN self_promotions.resume_id IS '職務経歴書ID';
COMMENT ON COLUMN self_promotions.title IS 'タイトル';
COMMENT ON COLUMN self_promotions.content IS 'コンテンツ';
COMMENT ON COLUMN self_promotions.order_no IS '並び順';

-- 技術スタックカテゴリマスタテーブル
CREATE TABLE tech_stack_category_mst (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);

COMMENT ON TABLE tech_stack_category_mst IS '技術スタックカテゴリマスタ';
COMMENT ON COLUMN tech_stack_category_mst.id IS '識別子';
COMMENT ON COLUMN tech_stack_category_mst.name IS 'カテゴリ名';

-- 技術スタックマスタテーブル
CREATE TABLE tech_stack_mst (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    category INTEGER NOT NULL REFERENCES tech_stack_category_mst(id)
);

COMMENT ON TABLE tech_stack_mst IS '技術スタックマスタ';
COMMENT ON COLUMN tech_stack_mst.id IS '識別子';
COMMENT ON COLUMN tech_stack_mst.name IS '技術名';
COMMENT ON COLUMN tech_stack_mst.category IS 'カテゴリ';
