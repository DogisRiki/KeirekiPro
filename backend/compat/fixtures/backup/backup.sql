-- バックアップの書き出しと戻しを確かめる経歴書。users/basic.sql の user1 のものである。
-- 筋書きと結合テストは、users/basic.sql と resumes/fonts.sql のあとに、このファイルを読み込む。
--   経歴書 801: 6つの欄のすべてに1件ずつ項目を持つ。プロジェクトは7つの工程をすべて選び、project_tech_stacks のすべての列に値を入れる
--   経歴書 802: 終わりの年月の無い、今も続いている職歴とプロジェクトを1件ずつ持つ。技術の値の無い分類と、技術の無いポートフォリオも持つ
--   経歴書 803: 名前が日本語で、ファイル名に使えない \ / : * ? " < > | と、U+2028 を含む。姓と名と項目を持たない
--   経歴書 804: 経歴書の名前と項目の字に、< > & " '、改行、タブ、絵文字、U+2028、U+2029 を入れる
--   経歴書 805: 6つの欄のそれぞれに3件の項目を、経歴書を読み出すときの順と違う順に入れる
-- 経歴書 801 から 804 の各欄の項目は1件以下にする。Java 版の書き出しの項目の並びはデータベースの行の置かれ方で変わるので、
-- 項目が2件以上あると、Java 版と Go 版のファイルの字の並びが項目の順だけで違うことがあるためである。
-- 期間と日付は重ねず、ポートフォリオと SNS と自己PR の名前は頭の英大文字を変える(置き換えの spec backend-go-replacement のタスク3.5の実装のメモ、CB-001)。
-- 経歴書 801 から 805 は、どれも Java 版の戻しの値の決まりを満たす。筋書きが、Java 版が書き出したファイルを戻し、201 で答えられることを確かめるためである。
-- そのため、経歴書 804 の姓と名とリンクには記号を入れない。経歴書 803 と 804 の名前は、使えない字を含むが、改行の字(改行、U+2028、U+2029)も含むので、
-- Java 版の名前の値の決まり(ResumeName)で断られない。Java 版の決まりは、改行の字を含む名前では使えない字を確かめないためである。
-- 項目の ID は、末尾の12桁を「00000008」、経歴書の番号の下1桁、欄の番号(1 職歴、2 プロジェクト、3 資格、4 ポートフォリオ、5 SNS、6 自己PR)、
-- 「0」、項目の番号の順に並べた値にする。
INSERT INTO resumes (id, user_id, name, date, last_name, first_name, created_at, updated_at) VALUES
    ('00000000-0000-4000-8000-000000000801', '00000000-0000-4000-8000-000000000001', 'すべての欄を持つバックアップの経歴書', '2026-03-01', '佐藤', '花子',
     '2026-03-01 10:00:00', '2026-03-01 10:00:00'),
    ('00000000-0000-4000-8000-000000000802', '00000000-0000-4000-8000-000000000001', '今も続く仕事のバックアップの経歴書', '2026-03-02', '高橋', '次郎',
     '2026-03-02 10:00:00', '2026-03-02 10:00:00'),
    ('00000000-0000-4000-8000-000000000803', '00000000-0000-4000-8000-000000000001', '経歴書\/:*?"<>|' || chr(8232) || 'の名前', '2026-03-03', NULL, NULL,
     '2026-03-03 10:00:00', '2026-03-03 10:00:00'),
    ('00000000-0000-4000-8000-000000000804', '00000000-0000-4000-8000-000000000001',
     '記号<>&"''と' || chr(10) || '改行' || chr(9) || 'タブ😀' || chr(8232) || chr(8233) || 'の経歴書', '2026-03-04', '田中', '三郎',
     '2026-03-04 10:00:00', '2026-03-04 10:00:00'),
    ('00000000-0000-4000-8000-000000000805', '00000000-0000-4000-8000-000000000001', '項目の多いバックアップの経歴書', '2026-03-05', '伊藤', '四郎',
     '2026-03-05 10:00:00', '2026-03-05 10:00:00');

INSERT INTO careers (id, resume_id, company_name, start_date, end_date, is_active) VALUES
    ('00000000-0000-4000-8000-000000081101', '00000000-0000-4000-8000-000000000801', '株式会社書き出し', '2014-04-01', '2020-03-01', FALSE),
    ('00000000-0000-4000-8000-000000082101', '00000000-0000-4000-8000-000000000802', '継続システム株式会社', '2019-10-01', NULL, TRUE),
    ('00000000-0000-4000-8000-000000084101', '00000000-0000-4000-8000-000000000804',
     '記号<>&"''の' || chr(10) || '会社' || chr(9) || '😀' || chr(8232) || chr(8233), '2016-07-01', '2022-06-01', FALSE),
    -- 経歴書 805 は、読み出すときの順(期間の新しい順)と逆の、古い順に入れる
    ('00000000-0000-4000-8000-000000085101', '00000000-0000-4000-8000-000000000805', '並びの株式会社一', '2005-04-01', '2009-03-01', FALSE),
    ('00000000-0000-4000-8000-000000085102', '00000000-0000-4000-8000-000000000805', '並びの株式会社二', '2009-04-01', '2015-03-01', FALSE),
    ('00000000-0000-4000-8000-000000085103', '00000000-0000-4000-8000-000000000805', '並びの株式会社三', '2015-04-01', NULL, TRUE);

INSERT INTO projects (id, resume_id, company_name, start_date, end_date, is_active, name, overview, team_comp, role, achievement,
                      requirements, basic_design, detailed_design, implementation, integration_test, system_test, maintenance) VALUES
    ('00000000-0000-4000-8000-000000081201', '00000000-0000-4000-8000-000000000801', '株式会社書き出し', '2015-01-01', '2018-12-01', FALSE,
     '在庫のシステムの作り直し',
     '倉庫の在庫を数えるシステムを、新しい基盤で作り直した。',
     '全体6名',
     '設計から保守までのすべての工程を受け持った。',
     '棚卸しにかかる日数を5日から2日にした。',
     TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE),
    ('00000000-0000-4000-8000-000000082201', '00000000-0000-4000-8000-000000000802', '継続システム株式会社', '2020-01-01', NULL, TRUE,
     '問い合わせの窓口の運用',
     '利用者からの問い合わせを受け付ける窓口のシステムを運用している。',
     '全体3名',
     '運用の担当として、障害の調べを受け持っている。',
     '問い合わせへの返事にかかる時間を半分にした。',
     FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, TRUE),
    ('00000000-0000-4000-8000-000000084201', '00000000-0000-4000-8000-000000000804',
     '記号<>&"''の' || chr(10) || '会社' || chr(9) || '😀' || chr(8232) || chr(8233), '2017-01-01', '2021-12-01', FALSE,
     'プロジェクト<>&"''' || chr(10) || '😀',
     '概要<>&"''' || chr(10) || '改行' || chr(9) || 'タブ😀' || chr(8232) || chr(8233),
     '体制<>&"''😀',
     '役割<>&"''' || chr(10) || '😀' || chr(8232),
     '成果<>&"''' || chr(10) || '😀' || chr(8233),
     TRUE, FALSE, TRUE, FALSE, TRUE, FALSE, TRUE),
    -- 経歴書 805 は、読み出すときの順(期間の新しい順)と逆の、古い順に入れる
    ('00000000-0000-4000-8000-000000085201', '00000000-0000-4000-8000-000000000805', '並びの株式会社一', '2005-10-01', '2008-09-01', FALSE,
     '並びの案件一', '並びを確かめる1つ目の案件である。', '全体4名', '実装を受け持った。', '期日どおりに納めた。',
     FALSE, FALSE, TRUE, TRUE, TRUE, FALSE, FALSE),
    ('00000000-0000-4000-8000-000000085202', '00000000-0000-4000-8000-000000000805', '並びの株式会社二', '2010-01-01', '2014-06-01', FALSE,
     '並びの案件二', '並びを確かめる2つ目の案件である。', '全体7名', '設計と実装を受け持った。', '処理の時間を30%短くした。',
     FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    ('00000000-0000-4000-8000-000000085203', '00000000-0000-4000-8000-000000000805', '並びの株式会社三', '2016-01-01', NULL, TRUE,
     '並びの案件三', '並びを確かめる3つ目の案件である。', '全体5名', 'リーダーを受け持っている。', '障害の件数を半分にした。',
     TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, TRUE);

INSERT INTO project_tech_stacks (project_id,
                                 frontend_languages, frontend_framework, frontend_libraries, frontend_build_tool, frontend_package_manager,
                                 frontend_linters, frontend_formatters, frontend_testing_tools,
                                 backend_languages, backend_framework, backend_libraries, backend_build_tool, backend_package_manager,
                                 backend_linters, backend_formatters, backend_testing_tools, orm_tools, auth,
                                 clouds, operating_system, containers, database, web_server, ci_cd_tool, iac_tools, monitoring_tools, logging_tools,
                                 source_control, project_management, communication_tool, documentation_tools, api_development_tools,
                                 design_tools, editor, development_environment) VALUES
    -- 経歴書 801 は、すべての列に値を入れる
    ('00000000-0000-4000-8000-000000081201',
     ARRAY['TypeScript', 'JavaScript'], ARRAY['React'], ARRAY['Redux'], ARRAY['Vite'], ARRAY['pnpm'],
     ARRAY['ESLint'], ARRAY['Prettier'], ARRAY['Vitest'],
     ARRAY['Java'], ARRAY['Spring Boot'], ARRAY['Lombok'], ARRAY['Gradle'], ARRAY['Maven'],
     ARRAY['Checkstyle'], ARRAY['Spotless'], ARRAY['JUnit'], ARRAY['MyBatis'], ARRAY['Spring Security'],
     ARRAY['AWS'], ARRAY['Amazon Linux'], ARRAY['Docker'], ARRAY['PostgreSQL'], ARRAY['Nginx'], ARRAY['GitHub Actions'],
     ARRAY['Terraform'], ARRAY['Amazon CloudWatch'], ARRAY['Fluent Bit'],
     ARRAY['Git'], ARRAY['Jira'], ARRAY['Slack'], ARRAY['Confluence'], ARRAY['Postman'],
     ARRAY['Figma'], ARRAY['IntelliJ IDEA'], ARRAY['Docker Compose']),
    -- 経歴書 802 は、値の無い分類を持つ
    ('00000000-0000-4000-8000-000000082201',
     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     ARRAY['PHP'], ARRAY['Laravel'], NULL, NULL, ARRAY['Composer'], NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, ARRAY['MySQL'], ARRAY['Apache'], NULL, NULL, NULL, NULL,
     ARRAY['Git'], NULL, ARRAY['Microsoft Teams'], NULL, NULL, NULL, ARRAY['PhpStorm'], NULL),
    ('00000000-0000-4000-8000-000000084201',
     ARRAY['言語<>&"''😀'], NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     ARRAY['Kotlin'], NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     ARRAY['Git'], NULL, NULL, NULL, NULL, NULL, ARRAY['Vim'], NULL),
    ('00000000-0000-4000-8000-000000085201',
     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     ARRAY['C'], NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, ARRAY['Solaris'], NULL, ARRAY['Oracle Database'], NULL, NULL, NULL, NULL, NULL,
     ARRAY['CVS'], NULL, NULL, NULL, NULL, NULL, ARRAY['Emacs'], NULL),
    ('00000000-0000-4000-8000-000000085202',
     ARRAY['JavaScript'], ARRAY['jQuery'], NULL, NULL, NULL, NULL, NULL, NULL,
     ARRAY['Ruby'], ARRAY['Ruby on Rails'], NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, ARRAY['MySQL'], ARRAY['Nginx'], ARRAY['Jenkins'], NULL, NULL, NULL,
     ARRAY['Subversion'], ARRAY['Redmine'], NULL, NULL, NULL, NULL, ARRAY['Sublime Text'], NULL),
    ('00000000-0000-4000-8000-000000085203',
     ARRAY['TypeScript'], ARRAY['Vue.js'], NULL, NULL, NULL, NULL, NULL, NULL,
     ARRAY['Go'], NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     ARRAY['Google Cloud'], NULL, ARRAY['Kubernetes'], ARRAY['Cloud SQL'], NULL, ARRAY['Cloud Build'], NULL, NULL, NULL,
     ARRAY['Git'], ARRAY['Asana'], ARRAY['Slack'], NULL, NULL, NULL, ARRAY['GoLand'], NULL);

INSERT INTO certifications (id, resume_id, name, date) VALUES
    ('00000000-0000-4000-8000-000000081301', '00000000-0000-4000-8000-000000000801', 'データベーススペシャリスト試験', '2016-04-01'),
    ('00000000-0000-4000-8000-000000084301', '00000000-0000-4000-8000-000000000804',
     '資格<>&"''' || chr(10) || chr(9) || '😀' || chr(8232) || chr(8233), '2018-10-01'),
    -- 経歴書 805 は、読み出すときの順(取得の年月の新しい順)と逆の、古い順に入れる
    ('00000000-0000-4000-8000-000000085301', '00000000-0000-4000-8000-000000000805', '並びの資格一', '2006-05-01'),
    ('00000000-0000-4000-8000-000000085302', '00000000-0000-4000-8000-000000000805', '並びの資格二', '2011-11-01'),
    ('00000000-0000-4000-8000-000000085303', '00000000-0000-4000-8000-000000000805', '並びの資格三', '2019-07-01');

INSERT INTO portfolios (id, resume_id, name, overview, tech_stack, link) VALUES
    ('00000000-0000-4000-8000-000000081401', '00000000-0000-4000-8000-000000000801', 'A 家計簿', '毎月の支出をまとめて表にする。', 'Kotlin、Android', 'https://example.com/portfolio/household'),
    -- 経歴書 802 は、技術の無いポートフォリオを持つ
    ('00000000-0000-4000-8000-000000082401', '00000000-0000-4000-8000-000000000802', 'A 読書の記録', '読んだ本と感想を残す。', NULL, 'https://example.com/portfolio/books'),
    ('00000000-0000-4000-8000-000000084401', '00000000-0000-4000-8000-000000000804',
     'A 記号<>&"''😀', '概要<>&"''' || chr(10) || chr(9) || '😀' || chr(8232) || chr(8233), '技術<>&"''' || chr(10) || '😀',
     'https://example.com/portfolio/symbols?a=1&b=2'),
    -- 経歴書 805 は、読み出すときの順(名前の順)と違う順に入れる
    ('00000000-0000-4000-8000-000000085401', '00000000-0000-4000-8000-000000000805', 'C 並びの作品', '3つ目に並ぶ作品である。', 'Rust', 'https://example.com/portfolio/order-c'),
    ('00000000-0000-4000-8000-000000085402', '00000000-0000-4000-8000-000000000805', 'A 並びの作品', '1つ目に並ぶ作品である。', 'Python', 'https://example.com/portfolio/order-a'),
    ('00000000-0000-4000-8000-000000085403', '00000000-0000-4000-8000-000000000805', 'B 並びの作品', '2つ目に並ぶ作品である。', 'Swift', 'https://example.com/portfolio/order-b');

INSERT INTO sns_platforms (id, resume_id, name, link) VALUES
    ('00000000-0000-4000-8000-000000081501', '00000000-0000-4000-8000-000000000801', 'A GitHub', 'https://github.com/example-backup'),
    ('00000000-0000-4000-8000-000000084501', '00000000-0000-4000-8000-000000000804', 'A 記号<>&"''😀', 'https://example.com/sns/symbols?a=1&b=2'),
    -- 経歴書 805 は、読み出すときの順(名前の順)と違う順に入れる
    ('00000000-0000-4000-8000-000000085501', '00000000-0000-4000-8000-000000000805', 'B Qiita', 'https://qiita.com/example-order'),
    ('00000000-0000-4000-8000-000000085502', '00000000-0000-4000-8000-000000000805', 'C Zenn', 'https://zenn.dev/example-order'),
    ('00000000-0000-4000-8000-000000085503', '00000000-0000-4000-8000-000000000805', 'A GitHub', 'https://github.com/example-order');

INSERT INTO self_promotions (id, resume_id, title, content) VALUES
    ('00000000-0000-4000-8000-000000081601', '00000000-0000-4000-8000-000000000801', 'A 書き出しの得意', 'すべての工程を受け持てます。'),
    ('00000000-0000-4000-8000-000000084601', '00000000-0000-4000-8000-000000000804',
     'A 題<>&"''😀', '内容<>&"''' || chr(10) || '改行' || chr(9) || 'タブ😀' || chr(8232) || chr(8233)),
    -- 経歴書 805 は、読み出すときの順(題の順)と逆の順に入れる
    ('00000000-0000-4000-8000-000000085601', '00000000-0000-4000-8000-000000000805', 'C 並びの題', '3つ目に並ぶ自己PRである。'),
    ('00000000-0000-4000-8000-000000085602', '00000000-0000-4000-8000-000000000805', 'B 並びの題', '2つ目に並ぶ自己PRである。'),
    ('00000000-0000-4000-8000-000000085603', '00000000-0000-4000-8000-000000000805', 'A 並びの題', '1つ目に並ぶ自己PRである。');
