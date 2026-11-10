-- 項目が空の経歴書。名前と日付だけを持ち、氏名と子の項目を持たない。users/basic.sql の user1 のものである。
INSERT INTO resumes (id, user_id, name, date, last_name, first_name, created_at, updated_at) VALUES
    ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000001', '空の経歴書', '2026-02-01', NULL, NULL,
     '2026-02-01 10:00:00', '2026-02-01 10:00:00');
