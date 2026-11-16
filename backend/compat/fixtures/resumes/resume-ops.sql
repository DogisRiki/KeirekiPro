-- マスタと経歴書の操作の筋書きの経歴書と利用者。users/basic.sql と一緒に使う。
-- ID は 00000000-0000-4000-8000-0000000003xx の範囲に置く。long-text.sql の経歴書の ID 000000000301 とは重ねない。
--   - 000000000320 と、000000000321 から 00000000032c: user1 の経歴書 A と、6つの欄に2つずつ置いた項目
--   - 000000000330 と、000000000331 から 000000000336: user1 の経歴書 B と、6つの欄に1つずつ置いた項目。
--     別の経歴書の項目の ID を組にした要求に使う
--   - 000000000340: 退会用の利用者。パスワードは basic.sql と同じ Passw0rd!(BCrypt の強さ 10)である
--   - 000000000350 と、000000000351 から 000000000356: 退会用の利用者の経歴書と、6つの欄に1つずつ置いた項目
-- 期間が同じ項目は Java 版で UUID の順に並び、版ごとに順が変わるので、期間と日付を重ねない(タスク3.5の実装のメモ)。
-- ポートフォリオと SNS と自己PR の名前は、日本語の並べ替えの規則によらず順が決まるように、頭の英大文字を変える(CB-001)。
INSERT INTO users (id, email, password, username, profile_image, two_factor_auth_enabled, created_at, updated_at, email_verified_at, pending_email) VALUES
    ('00000000-0000-4000-8000-000000000340', 'resume-withdraw@example.com', '$2a$10$/hGD5keoxMgQAHr4ML99Y.ojANrslhau/Z1ef5RbPpWQoKqsx/08W', '退会 三郎', NULL, FALSE,
     '2026-01-07 09:00:00', '2026-01-07 09:00:00', '2026-01-07 09:05:00', NULL);

INSERT INTO user_roles (user_id, role_id, created_at)
SELECT '00000000-0000-4000-8000-000000000340', r.id, '2026-01-07 09:00:00' FROM roles r WHERE r.name = 'USER';

-- ログインの状態の世代(basic.sql と同じ理由で置く)。世代の番号を 0 にするので、取り出したログインの状態の値は退会のあとも検査を通る。
INSERT INTO user_token_versions (user_id, token_version, updated_at) VALUES
    ('00000000-0000-4000-8000-000000000340', 0, '2026-01-07 09:05:00');

INSERT INTO resumes (id, user_id, name, date, last_name, first_name, created_at, updated_at) VALUES
    ('00000000-0000-4000-8000-000000000320', '00000000-0000-4000-8000-000000000001', '操作を確かめる経歴書', '2026-03-01', '比較', '一郎',
     '2026-03-01 10:00:00', '2026-03-01 10:00:00'),
    ('00000000-0000-4000-8000-000000000330', '00000000-0000-4000-8000-000000000001', '別の経歴書', '2026-03-02', NULL, NULL,
     '2026-03-02 10:00:00', '2026-03-02 11:30:00.123456'),
    ('00000000-0000-4000-8000-000000000350', '00000000-0000-4000-8000-000000000340', '退会する人の経歴書', '2026-03-03', '退会', '三郎',
     '2026-03-03 10:00:00', '2026-03-03 10:00:00');

INSERT INTO careers (id, resume_id, company_name, start_date, end_date, is_active) VALUES
    ('00000000-0000-4000-8000-000000000321', '00000000-0000-4000-8000-000000000320', '株式会社そうさ', '2015-04-01', '2019-03-01', FALSE),
    ('00000000-0000-4000-8000-000000000322', '00000000-0000-4000-8000-000000000320', 'Operation Works 株式会社', '2019-04-01', NULL, TRUE),
    ('00000000-0000-4000-8000-000000000331', '00000000-0000-4000-8000-000000000330', '株式会社べつ', '2016-04-01', '2020-03-01', FALSE),
    ('00000000-0000-4000-8000-000000000351', '00000000-0000-4000-8000-000000000350', '株式会社たいかい', '2017-04-01', NULL, TRUE);

-- 経歴書 A の2つのプロジェクトのうち、1つ目は技術スタックの35の列すべてに値を持ち、2つ目は NULL の列と空の並びの列を持つ。
INSERT INTO projects (id, resume_id, company_name, start_date, end_date, is_active, name, overview, team_comp, role, achievement,
                      requirements, basic_design, detailed_design, implementation, integration_test, system_test, maintenance) VALUES
    ('00000000-0000-4000-8000-000000000323', '00000000-0000-4000-8000-000000000320', '株式会社そうさ', '2015-04-01', '2017-03-01', FALSE,
     '在庫の管理のシステムの開発',
     '倉庫の在庫を管理するシステムを作った。',
     '全体6名',
     '開発の担当として、画面と API を作った。',
     '棚卸しの時間を半分にした。' || chr(10) || '入力の誤りを月に20件から2件に減らした。',
     TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE),
    ('00000000-0000-4000-8000-000000000324', '00000000-0000-4000-8000-000000000320', 'Operation Works 株式会社', '2019-04-01', NULL, TRUE,
     '社内の申請のシステムの保守',
     '社内の申請を受け付けるシステムを保守している。',
     '全体3名',
     '保守の担当として、問い合わせに答えている。',
     '問い合わせへの答えの時間を短くした。',
     FALSE, FALSE, FALSE, TRUE, FALSE, TRUE, TRUE),
    ('00000000-0000-4000-8000-000000000332', '00000000-0000-4000-8000-000000000330', '株式会社べつ', '2016-04-01', '2018-03-01', FALSE,
     '予約の受付の開発',
     '予約を受け付ける画面を作った。',
     '全体4名',
     '開発の担当',
     '予約の件数を増やした。',
     FALSE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE),
    ('00000000-0000-4000-8000-000000000352', '00000000-0000-4000-8000-000000000350', '株式会社たいかい', '2017-04-01', NULL, TRUE,
     '会員のサイトの運用',
     '会員のサイトを運用している。',
     '全体2名',
     '運用の担当',
     '障害の件数を減らした。',
     FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE);

INSERT INTO project_tech_stacks (project_id,
                                 frontend_languages, frontend_framework, frontend_libraries, frontend_build_tool, frontend_package_manager,
                                 frontend_linters, frontend_formatters, frontend_testing_tools,
                                 backend_languages, backend_framework, backend_libraries, backend_build_tool, backend_package_manager,
                                 backend_linters, backend_formatters, backend_testing_tools, orm_tools, auth,
                                 clouds, operating_system, containers, database, web_server, ci_cd_tool, iac_tools, monitoring_tools, logging_tools,
                                 source_control, project_management, communication_tool, documentation_tools, api_development_tools,
                                 design_tools, editor, development_environment) VALUES
    ('00000000-0000-4000-8000-000000000323',
     ARRAY['TypeScript', 'JavaScript'], ARRAY['React'], ARRAY['Redux'], ARRAY['Vite'], ARRAY['pnpm'],
     ARRAY['ESLint'], ARRAY['Prettier'], ARRAY['Vitest'],
     ARRAY['Java'], ARRAY['Spring Boot'], ARRAY['Lombok'], ARRAY['Gradle'], ARRAY['Maven'],
     ARRAY['Checkstyle'], ARRAY['Spotless'], ARRAY['JUnit'], ARRAY['MyBatis'], ARRAY['Spring Security'],
     ARRAY['AWS'], ARRAY['Linux'], ARRAY['Docker'], ARRAY['PostgreSQL'], ARRAY['Nginx'], ARRAY['GitHub Actions'], ARRAY['Terraform'],
     ARRAY['Amazon CloudWatch'], ARRAY['Fluent Bit'],
     ARRAY['Git'], ARRAY['Jira'], ARRAY['Slack'], ARRAY['Confluence'], ARRAY['Postman'],
     ARRAY['Figma'], ARRAY['IntelliJ IDEA'], ARRAY['Docker Compose']),
    ('00000000-0000-4000-8000-000000000324',
     NULL, '{}', NULL, NULL, NULL,
     NULL, NULL, NULL,
     ARRAY['Go'], '{}', NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL,
     '{}', NULL, NULL, ARRAY['MySQL'], NULL, NULL, NULL,
     NULL, NULL,
     ARRAY['Git'], NULL, '{}', NULL, NULL,
     NULL, NULL, NULL),
    ('00000000-0000-4000-8000-000000000332',
     ARRAY['JavaScript'], NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     ARRAY['PHP'], ARRAY['Laravel'], NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, ARRAY['MySQL'], NULL, NULL, NULL, NULL, NULL,
     ARRAY['Git'], NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('00000000-0000-4000-8000-000000000352',
     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     ARRAY['Ruby'], ARRAY['Ruby on Rails'], NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     ARRAY['AWS'], NULL, NULL, ARRAY['PostgreSQL'], NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

INSERT INTO certifications (id, resume_id, name, date) VALUES
    ('00000000-0000-4000-8000-000000000325', '00000000-0000-4000-8000-000000000320', '基本情報技術者試験', '2014-11-01'),
    ('00000000-0000-4000-8000-000000000326', '00000000-0000-4000-8000-000000000320', '応用情報技術者試験', '2016-06-01'),
    ('00000000-0000-4000-8000-000000000333', '00000000-0000-4000-8000-000000000330', 'データベーススペシャリスト試験', '2018-10-01'),
    ('00000000-0000-4000-8000-000000000353', '00000000-0000-4000-8000-000000000350', 'ITパスポート試験', '2017-05-01');

INSERT INTO portfolios (id, resume_id, name, overview, tech_stack, link) VALUES
    ('00000000-0000-4000-8000-000000000327', '00000000-0000-4000-8000-000000000320', 'A 家計簿', '毎月の支出を記録して集計する。', 'Go、PostgreSQL', 'https://example.com/portfolio/kakeibo'),
    ('00000000-0000-4000-8000-000000000328', '00000000-0000-4000-8000-000000000320', 'B 読書の記録', '読んだ本の感想を残す。', NULL, 'https://example.com/portfolio/books'),
    ('00000000-0000-4000-8000-000000000334', '00000000-0000-4000-8000-000000000330', 'C 散歩の地図', '歩いた道を地図に残す。', 'TypeScript', 'https://example.com/portfolio/walk'),
    ('00000000-0000-4000-8000-000000000354', '00000000-0000-4000-8000-000000000350', 'D 写真の整理', '写真を日付で分ける。', 'Python', 'https://example.com/portfolio/photos');

INSERT INTO sns_platforms (id, resume_id, name, link) VALUES
    ('00000000-0000-4000-8000-000000000329', '00000000-0000-4000-8000-000000000320', 'GitHub', 'https://github.com/example-ops'),
    ('00000000-0000-4000-8000-00000000032a', '00000000-0000-4000-8000-000000000320', 'Qiita', 'https://qiita.com/example-ops'),
    ('00000000-0000-4000-8000-000000000335', '00000000-0000-4000-8000-000000000330', 'Zenn', 'https://zenn.dev/example-ops'),
    ('00000000-0000-4000-8000-000000000355', '00000000-0000-4000-8000-000000000350', 'X', 'https://x.com/example-withdraw');

INSERT INTO self_promotions (id, resume_id, title, content) VALUES
    ('00000000-0000-4000-8000-00000000032b', '00000000-0000-4000-8000-000000000320', 'A 粘り強く調べる', '障害の原因を、最後まで調べて突き止めます。'),
    ('00000000-0000-4000-8000-00000000032c', '00000000-0000-4000-8000-000000000320', 'B 文書を残す', '調べたことを、ほかの人が読める文書に残します。' || chr(10) || '手順書も書きます。'),
    ('00000000-0000-4000-8000-000000000336', '00000000-0000-4000-8000-000000000330', 'C 人に教える', '新しく入った人に、仕事の進め方を教えてきました。'),
    ('00000000-0000-4000-8000-000000000356', '00000000-0000-4000-8000-000000000350', 'D 早く覚える', '新しい道具を早く覚えます。');
