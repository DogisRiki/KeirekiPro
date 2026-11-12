-- 認証の操作の筋書きの利用者。basic.sql と一緒に使う。パスワードは basic.sql と同じ Passw0rd!(BCrypt の強さ 10)である。
-- unverified は、メールアドレスの確認が済んでいない利用者である(email_verified_at が NULL)。
-- twofactor は、2段階認証を有効にした利用者である。Go 版は2段階認証を有効にする操作をまだ持たないので、初めのデータで置く。
INSERT INTO users (id, email, password, username, profile_image, two_factor_auth_enabled, created_at, updated_at, email_verified_at, pending_email) VALUES
    ('00000000-0000-4000-8000-000000000011', 'unverified@example.com', '$2a$10$/hGD5keoxMgQAHr4ML99Y.ojANrslhau/Z1ef5RbPpWQoKqsx/08W', '未確認 三郎', NULL, FALSE,
     '2026-01-07 09:00:00', '2026-01-07 09:00:00', NULL, NULL),
    ('00000000-0000-4000-8000-000000000012', 'twofactor@example.com', '$2a$10$/hGD5keoxMgQAHr4ML99Y.ojANrslhau/Z1ef5RbPpWQoKqsx/08W', '二段 四郎', NULL, TRUE,
     '2026-01-08 09:00:00', '2026-01-08 09:00:00', '2026-01-08 09:05:00', NULL);

INSERT INTO user_roles (user_id, role_id, created_at)
SELECT u.id, r.id, '2026-01-07 09:00:00' FROM users u CROSS JOIN roles r
WHERE u.id IN ('00000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-000000000012') AND r.name = 'USER';

-- ログインの状態の世代(basic.sql と同じ理由で置く)。unverified の行は、表を作ったときに
-- そのときの利用者すべてに行を作った Java 版の表の形の履歴(V3)と同じく、確認の前から持つ形にする。
INSERT INTO user_token_versions (user_id, token_version, updated_at) VALUES
    ('00000000-0000-4000-8000-000000000011', 0, '2026-01-07 09:00:00'),
    ('00000000-0000-4000-8000-000000000012', 0, '2026-01-08 09:05:00');
