-- 職歴と案件が多く、PDF が3ページ以上になる経歴書。users/basic.sql の user1 のものである。
-- 職歴は12件で、2年ずつ重ならずに並び、最後の1件だけが在籍中である。案件は職歴ごとに1年ずつ2件で、期間はすべて違う。
-- 期間が同じ要素は Java 版で UUID の順に並び、版ごとに順が変わるので、期間を重ねない(タスク3.5の実装のメモ)。
INSERT INTO resumes (id, user_id, name, date, last_name, first_name, created_at, updated_at) VALUES
    ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000001', '職歴と案件の多い経歴書', '2026-02-02', '山田', '太郎',
     '2026-02-02 10:00:00', '2026-02-02 10:00:00');

INSERT INTO careers (id, resume_id, company_name, start_date, end_date, is_active)
SELECT ('00000000-0000-4000-8000-' || lpad((201000 + n)::text, 12, '0'))::uuid,
       '00000000-0000-4000-8000-000000000201',
       '株式会社サンプル' || lpad(n::text, 2, '0'),
       DATE '2000-01-01' + make_interval(months => (n - 1) * 24),
       CASE WHEN n = 12 THEN NULL ELSE DATE '2000-01-01' + make_interval(months => (n - 1) * 24 + 23) END,
       n = 12
FROM generate_series(1, 12) AS n;

INSERT INTO projects (id, resume_id, company_name, start_date, end_date, is_active, name, overview, team_comp, role, achievement,
                      requirements, basic_design, detailed_design, implementation, integration_test, system_test, maintenance)
SELECT ('00000000-0000-4000-8000-' || lpad((202000 + k)::text, 12, '0'))::uuid,
       '00000000-0000-4000-8000-000000000201',
       '株式会社サンプル' || lpad(((k + 1) / 2)::text, 2, '0'),
       DATE '2000-01-01' + make_interval(months => (k - 1) * 12),
       DATE '2000-01-01' + make_interval(months => (k - 1) * 12 + 11),
       FALSE,
       '業務システムの開発 第' || k || '期',
       '受発注と在庫を管理する社内の業務システムを、利用者の要望に合わせて段階的に作り直した案件である。' || chr(10) ||
       '既存の画面と帳票の動きを保ったまま、処理の速さと保守のしやすさを高めることを目的とした。',
       '全体' || (5 + k % 7) || '名(開発' || (3 + k % 4) || '名、試験2名)',
       'チームの開発の担当として、設計からリリースまでを受け持った。' || chr(10) ||
       'レビューの方針を決め、新しく入った人の立ち上がりを支えた。',
       '画面の表示にかかる時間を平均で' || (20 + k) || '%短くした。' || chr(10) ||
       '自動テストを整え、リリースの前の確認にかかる時間を半分にした。' || chr(10) ||
       '障害の件数を前の年より' || (10 + k) || '件減らした。',
       k % 2 = 0, TRUE, TRUE, TRUE, TRUE, k % 3 = 0, k % 4 = 0
FROM generate_series(1, 24) AS k;

INSERT INTO project_tech_stacks (project_id, frontend_languages, frontend_framework, frontend_libraries, frontend_build_tool,
                                 backend_languages, backend_framework, backend_libraries, backend_build_tool, orm_tools,
                                 clouds, operating_system, containers, database, ci_cd_tool, source_control, communication_tool, editor)
SELECT ('00000000-0000-4000-8000-' || lpad((202000 + k)::text, 12, '0'))::uuid,
       ARRAY['TypeScript', 'HTML', 'CSS'], ARRAY['React'], ARRAY['Redux', 'React Router', '社内の部品 その' || k], ARRAY['Vite'],
       ARRAY['Java'], ARRAY['Spring Boot'], ARRAY['Lombok'], ARRAY['Gradle'], ARRAY['MyBatis'],
       ARRAY['AWS'], ARRAY['Linux'], ARRAY['Docker'], ARRAY['PostgreSQL'], ARRAY['GitHub Actions'],
       ARRAY['Git'], ARRAY['Slack'], ARRAY['Visual Studio Code']
FROM generate_series(1, 24) AS k;

INSERT INTO certifications (id, resume_id, name, date)
SELECT ('00000000-0000-4000-8000-' || lpad((203000 + n)::text, 12, '0'))::uuid,
       '00000000-0000-4000-8000-000000000201',
       '情報処理の資格 その' || n,
       DATE '2001-04-01' + make_interval(months => (n - 1) * 30)
FROM generate_series(1, 8) AS n;
