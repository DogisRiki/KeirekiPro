-- 数の上限を確かめる筋書きの利用者と経歴書。users/basic.sql と一緒に使う。パスワードは basic.sql と同じ Passw0rd!(BCrypt の強さ 10)である。
-- ID は 00000000-0000-4000-8000-0000000005xx と 0000005xxxxx の範囲に置く。
--   - 000000000500: 経歴書を上限の50件持つ利用者
--   - 000000000501 から 000000000550: その利用者の50件の経歴書
--   - 000000000501 の経歴書は、6つの欄の項目を、それぞれ上限の数だけ持つ。上限の数は Java 版の ResumeLimits と同じである
--     (職歴30、プロジェクト100、資格50、ポートフォリオ50、SNS 10、自己PR 5)。項目の ID は 0000005 と欄の番号と3桁の連番である
-- 期間が同じ項目は Java 版で UUID の順に並び、版ごとに順が変わるので、期間と日付を重ねない(タスク3.5の実装のメモ)。
-- ポートフォリオと SNS と自己PR の名前は、日本語の並べ替えの規則によらず順が決まるように、英字と空白と同じ桁数の連番で書く(CB-001)。
INSERT INTO users (id, email, password, username, profile_image, two_factor_auth_enabled, created_at, updated_at, email_verified_at, pending_email) VALUES
    ('00000000-0000-4000-8000-000000000500', 'resume-limits@example.com', '$2a$10$/hGD5keoxMgQAHr4ML99Y.ojANrslhau/Z1ef5RbPpWQoKqsx/08W', '上限 四郎', NULL, FALSE,
     '2026-01-08 09:00:00', '2026-01-08 09:00:00', '2026-01-08 09:05:00', NULL);

INSERT INTO user_roles (user_id, role_id, created_at)
SELECT '00000000-0000-4000-8000-000000000500', r.id, '2026-01-08 09:00:00' FROM roles r WHERE r.name = 'USER';

-- ログインの状態の世代(basic.sql と同じ理由で置く)。
INSERT INTO user_token_versions (user_id, token_version, updated_at) VALUES
    ('00000000-0000-4000-8000-000000000500', 0, '2026-01-08 09:05:00');

INSERT INTO resumes (id, user_id, name, date, last_name, first_name, created_at, updated_at)
SELECT ('00000000-0000-4000-8000-' || lpad((500 + n)::text, 12, '0'))::uuid,
       '00000000-0000-4000-8000-000000000500',
       '上限の経歴書' || lpad(n::text, 2, '0'),
       DATE '2026-04-01',
       '上限',
       '四郎',
       TIMESTAMP '2026-04-01 10:00:00' + make_interval(mins => n),
       TIMESTAMP '2026-04-01 10:00:00' + make_interval(mins => n)
FROM generate_series(1, 50) AS n;

INSERT INTO careers (id, resume_id, company_name, start_date, end_date, is_active)
SELECT ('00000000-0000-4000-8000-' || lpad((501000 + n)::text, 12, '0'))::uuid,
       '00000000-0000-4000-8000-000000000501',
       '株式会社じょうげん' || lpad(n::text, 2, '0'),
       DATE '1990-01-01' + make_interval(months => (n - 1) * 12),
       DATE '1990-01-01' + make_interval(months => (n - 1) * 12 + 11),
       FALSE
FROM generate_series(1, 30) AS n;

INSERT INTO projects (id, resume_id, company_name, start_date, end_date, is_active, name, overview, team_comp, role, achievement,
                      requirements, basic_design, detailed_design, implementation, integration_test, system_test, maintenance)
SELECT ('00000000-0000-4000-8000-' || lpad((502000 + n)::text, 12, '0'))::uuid,
       '00000000-0000-4000-8000-000000000501',
       '株式会社じょうげん01',
       DATE '2000-01-01' + make_interval(months => n - 1),
       DATE '2000-01-01' + make_interval(months => n - 1),
       FALSE,
       'プロジェクト' || lpad(n::text, 3, '0'),
       '上限を確かめるプロジェクト',
       '全体3名',
       '開発の担当',
       '予定どおりに終えた。',
       TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE
FROM generate_series(1, 100) AS n;

INSERT INTO project_tech_stacks (project_id, backend_languages, backend_libraries)
SELECT ('00000000-0000-4000-8000-' || lpad((502000 + n)::text, 12, '0'))::uuid, ARRAY['Java'], ARRAY['library-' || lpad(n::text, 3, '0')]
FROM generate_series(1, 100) AS n;

INSERT INTO certifications (id, resume_id, name, date)
SELECT ('00000000-0000-4000-8000-' || lpad((503000 + n)::text, 12, '0'))::uuid,
       '00000000-0000-4000-8000-000000000501',
       '資格' || lpad(n::text, 2, '0'),
       DATE '2000-01-01' + make_interval(months => n - 1)
FROM generate_series(1, 50) AS n;

INSERT INTO portfolios (id, resume_id, name, overview, tech_stack, link)
SELECT ('00000000-0000-4000-8000-' || lpad((504000 + n)::text, 12, '0'))::uuid,
       '00000000-0000-4000-8000-000000000501',
       'Portfolio ' || lpad(n::text, 2, '0'),
       '上限を確かめるポートフォリオ',
       'Go',
       'https://example.com/limits/portfolio/' || n
FROM generate_series(1, 50) AS n;

INSERT INTO sns_platforms (id, resume_id, name, link)
SELECT ('00000000-0000-4000-8000-' || lpad((505000 + n)::text, 12, '0'))::uuid,
       '00000000-0000-4000-8000-000000000501',
       'SNS ' || lpad(n::text, 2, '0'),
       'https://example.com/limits/sns/' || n
FROM generate_series(1, 10) AS n;

INSERT INTO self_promotions (id, resume_id, title, content)
SELECT ('00000000-0000-4000-8000-' || lpad((506000 + n)::text, 12, '0'))::uuid,
       '00000000-0000-4000-8000-000000000501',
       'Title ' || n,
       '上限を確かめる自己PR'
FROM generate_series(1, 5) AS n;
