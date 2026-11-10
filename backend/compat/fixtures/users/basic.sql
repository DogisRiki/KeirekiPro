-- 比べる検査の利用者。パスワードはどちらも Passw0rd!(BCrypt の強さ 10)である。
-- user1 は筋書きでログインして操作する利用者、user2 は権限の無い操作を確かめるための、ほかの利用者である。
-- 経歴書は resumes/ のファイルが user1 に作る。
INSERT INTO users (id, email, password, username, profile_image, two_factor_auth_enabled, created_at, updated_at, email_verified_at, pending_email) VALUES
    ('00000000-0000-4000-8000-000000000001', 'user1@example.com', '$2a$10$/hGD5keoxMgQAHr4ML99Y.ojANrslhau/Z1ef5RbPpWQoKqsx/08W', '比較 一郎', NULL, FALSE,
     '2026-01-05 09:00:00', '2026-01-05 09:00:00', '2026-01-05 09:05:00', NULL),
    ('00000000-0000-4000-8000-000000000002', 'user2@example.com', '$2a$10$/hGD5keoxMgQAHr4ML99Y.ojANrslhau/Z1ef5RbPpWQoKqsx/08W', '比較 二郎', NULL, FALSE,
     '2026-01-06 09:00:00', '2026-01-06 09:00:00', '2026-01-06 09:05:00', NULL);

INSERT INTO user_roles (user_id, role_id, created_at)
SELECT u.id, r.id, '2026-01-05 09:00:00' FROM users u CROSS JOIN roles r
WHERE u.id IN ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002') AND r.name = 'USER';
