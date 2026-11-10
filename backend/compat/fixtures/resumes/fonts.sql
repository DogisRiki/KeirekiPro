-- 2つのフォントのそれぞれで書き出して比べる経歴書。users/basic.sql の user1 のものである。
-- フォントは経歴書に保存せず、書き出しの要求で選ぶ。筋書きは、この経歴書を、fonts-NotoSansJP.json と fonts-NotoSerifJP.json の設定で書き出す。
-- すべての項目を持たせ、見出し、表、本文のどれにも両方のフォントの文字が現れるようにする。
-- 期間と日付は重ねず、ポートフォリオと SNS と自己PR の名前は頭の英大文字を変える(タスク3.5の実装のメモ、CB-001)。
INSERT INTO resumes (id, user_id, name, date, last_name, first_name, created_at, updated_at) VALUES
    ('00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-000000000001', 'フォントを比べる経歴書', '2026-02-04', '鈴木', '一郎',
     '2026-02-04 10:00:00', '2026-02-04 10:00:00');

INSERT INTO careers (id, resume_id, company_name, start_date, end_date, is_active) VALUES
    ('00000000-0000-4000-8000-000000401001', '00000000-0000-4000-8000-000000000401', '株式会社ひかく', '2012-04-01', '2018-03-01', FALSE),
    ('00000000-0000-4000-8000-000000401002', '00000000-0000-4000-8000-000000000401', 'Compare Systems 合同会社', '2018-04-01', NULL, TRUE);

INSERT INTO projects (id, resume_id, company_name, start_date, end_date, is_active, name, overview, team_comp, role, achievement,
                      requirements, basic_design, detailed_design, implementation, integration_test, system_test, maintenance) VALUES
    ('00000000-0000-4000-8000-000000402001', '00000000-0000-4000-8000-000000000401', '株式会社ひかく', '2012-04-01', '2015-09-01', FALSE,
     '会計のシステムの保守',
     '月次の締めの処理を受け持つ会計のシステムの保守と、法改正への対応を行った。',
     '全体8名',
     '保守の担当として、障害の調べと直しを受け持った。',
     '締めの処理の時間を40%短くした。' || chr(10) || '障害の件数を年に12件から3件に減らした。',
     FALSE, FALSE, TRUE, TRUE, TRUE, FALSE, TRUE),
    ('00000000-0000-4000-8000-000000402002', '00000000-0000-4000-8000-000000000401', 'Compare Systems 合同会社', '2018-04-01', '2021-12-01', FALSE,
     '予約のサイトの新規開発',
     '飲食店の予約を受け付けるサイトを、ゼロから作った。1日あたり約3万件の予約を受け付ける。',
     '全体5名(開発3名)',
     '開発のリーダーとして、技術の選定と設計と実装を受け持った。',
     '公開から半年で、予約の件数を前のサイトの2倍にした。',
     TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    ('00000000-0000-4000-8000-000000402003', '00000000-0000-4000-8000-000000000401', 'Compare Systems 合同会社', '2022-01-01', NULL, TRUE,
     '社内の基盤の移行',
     'オンプレミスのサーバで動かしていた社内のシステムを、クラウドへ移した。',
     '全体4名',
     '移行の計画と、基盤の構成の設計を受け持った。',
     'サーバの費用を年に約30%減らした。',
     TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE);

INSERT INTO project_tech_stacks (project_id, frontend_languages, frontend_framework, backend_languages, backend_framework, orm_tools, auth,
                                 clouds, containers, database, web_server, ci_cd_tool, iac_tools, monitoring_tools, logging_tools,
                                 source_control, project_management, communication_tool, documentation_tools, api_development_tools,
                                 design_tools, editor, development_environment) VALUES
    ('00000000-0000-4000-8000-000000402001', NULL, NULL, ARRAY['Java'], ARRAY['Struts'], NULL, NULL,
     NULL, NULL, ARRAY['Oracle Database'], ARRAY['Apache'], NULL, NULL, NULL, NULL,
     ARRAY['Subversion'], ARRAY['Redmine'], NULL, ARRAY['Excel'], NULL, NULL, ARRAY['Eclipse'], NULL),
    ('00000000-0000-4000-8000-000000402002', ARRAY['TypeScript'], ARRAY['React'], ARRAY['Java'], ARRAY['Spring Boot'], ARRAY['MyBatis'], ARRAY['Spring Security'],
     ARRAY['AWS'], ARRAY['Docker'], ARRAY['PostgreSQL'], ARRAY['Nginx'], ARRAY['GitHub Actions'], NULL, NULL, NULL,
     ARRAY['Git'], ARRAY['Jira'], ARRAY['Slack'], ARRAY['Confluence'], ARRAY['Postman'], ARRAY['Figma'], ARRAY['IntelliJ IDEA'], ARRAY['Docker Compose']),
    ('00000000-0000-4000-8000-000000402003', NULL, NULL, ARRAY['Go'], NULL, NULL, NULL,
     ARRAY['AWS'], ARRAY['Docker', 'Amazon ECS'], ARRAY['PostgreSQL'], NULL, ARRAY['GitHub Actions'], ARRAY['Terraform'], ARRAY['Amazon CloudWatch'], ARRAY['Fluent Bit'],
     ARRAY['Git'], ARRAY['Backlog'], ARRAY['Slack'], NULL, NULL, NULL, ARRAY['Visual Studio Code'], NULL);

INSERT INTO certifications (id, resume_id, name, date) VALUES
    ('00000000-0000-4000-8000-000000403001', '00000000-0000-4000-8000-000000000401', '基本情報技術者試験', '2012-11-01'),
    ('00000000-0000-4000-8000-000000403002', '00000000-0000-4000-8000-000000000401', '応用情報技術者試験', '2014-06-01'),
    ('00000000-0000-4000-8000-000000403003', '00000000-0000-4000-8000-000000000401', 'AWS Certified Solutions Architect - Associate', '2020-09-01');

INSERT INTO portfolios (id, resume_id, name, overview, tech_stack, link) VALUES
    ('00000000-0000-4000-8000-000000404001', '00000000-0000-4000-8000-000000000401', 'A 天気の通知', '毎朝、その日の天気と服装の目安を知らせる。', 'Go、AWS Lambda', 'https://example.com/portfolio/weather'),
    ('00000000-0000-4000-8000-000000404002', '00000000-0000-4000-8000-000000000401', 'B 献立の提案', '冷蔵庫にある食材から献立を提案する。', 'TypeScript、Next.js', 'https://example.com/portfolio/menu');

INSERT INTO sns_platforms (id, resume_id, name, link) VALUES
    ('00000000-0000-4000-8000-000000405001', '00000000-0000-4000-8000-000000000401', 'GitHub', 'https://github.com/example-compare'),
    ('00000000-0000-4000-8000-000000405002', '00000000-0000-4000-8000-000000000401', 'Qiita', 'https://qiita.com/example-compare'),
    ('00000000-0000-4000-8000-000000405003', '00000000-0000-4000-8000-000000000401', 'Zenn', 'https://zenn.dev/example-compare');

INSERT INTO self_promotions (id, resume_id, title, content) VALUES
    ('00000000-0000-4000-8000-000000406001', '00000000-0000-4000-8000-000000000401', 'A 設計から運用まで', '設計から運用までを通して受け持てます。' || chr(10) || '運用で見つけた困りごとを、次の設計に生かします。'),
    ('00000000-0000-4000-8000-000000406002', '00000000-0000-4000-8000-000000000401', 'B 数字で確かめる', '改善の前と後を、数字で比べて確かめることを大切にしています。');
