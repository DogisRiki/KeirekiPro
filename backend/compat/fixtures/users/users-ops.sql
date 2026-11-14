-- 利用者の操作の筋書きの利用者。basic.sql と auth-users.sql と一緒に使う。パスワードは basic.sql と同じ Passw0rd!(BCrypt の強さ 10)である。
-- google-only は、パスワードもメールアドレスも持たず、Google の連携を1つだけ持つ利用者である。筋書きは Google のアカウントでログインする。
-- admin-ops は、役割 USER と ADMIN を持ち、2段階認証を使う利用者である。役割 ADMIN の利用者は2段階認証を使う設定でないと情報を読めない。
-- noname は、確認の済んだメールアドレスとパスワードを持ち、名前を持たない利用者である。
-- unverified-linked は、確認の済んでいないメールアドレスとパスワードと、Google の連携を1つ持つ利用者である。
-- メールアドレスの確認が済んでいないのでパスワードではログインできず、筋書きは Google のアカウントでログインする。
-- two-providers は、確認の済んだメールアドレスとパスワード、Google と GitHub の連携、4つの拡張子(jpg jpeg png gif)に
-- 当たらない画像の名前を持つ利用者である。画像は、筋書きの始めに偽の AWS に置く。
INSERT INTO users (id, email, password, username, profile_image, two_factor_auth_enabled, created_at, updated_at, email_verified_at, pending_email) VALUES
    ('00000000-0000-4000-8000-000000000021', NULL, NULL, 'グーグル 五郎', NULL, FALSE,
     '2026-01-09 09:00:00', '2026-01-09 09:00:00', NULL, NULL),
    ('00000000-0000-4000-8000-000000000022', 'admin-ops@example.com', '$2a$10$/hGD5keoxMgQAHr4ML99Y.ojANrslhau/Z1ef5RbPpWQoKqsx/08W', '管理 六郎', NULL, TRUE,
     '2026-01-10 09:00:00', '2026-01-10 09:00:00', '2026-01-10 09:05:00', NULL),
    ('00000000-0000-4000-8000-000000000023', 'noname@example.com', '$2a$10$/hGD5keoxMgQAHr4ML99Y.ojANrslhau/Z1ef5RbPpWQoKqsx/08W', NULL, NULL, FALSE,
     '2026-01-11 09:00:00', '2026-01-11 09:00:00', '2026-01-11 09:05:00', NULL),
    ('00000000-0000-4000-8000-000000000024', 'unverified-linked@example.com', '$2a$10$/hGD5keoxMgQAHr4ML99Y.ojANrslhau/Z1ef5RbPpWQoKqsx/08W', '未確認 七郎', NULL, FALSE,
     '2026-01-12 09:00:00', '2026-01-12 09:00:00', NULL, NULL),
    ('00000000-0000-4000-8000-000000000025', 'two-providers@example.com', '$2a$10$/hGD5keoxMgQAHr4ML99Y.ojANrslhau/Z1ef5RbPpWQoKqsx/08W', '連携 八郎',
     '/profile/image/00000000-0000-4000-8000-000000000025.webp', FALSE,
     '2026-01-13 09:00:00', '2026-01-13 09:00:00', '2026-01-13 09:05:00', NULL);

INSERT INTO user_roles (user_id, role_id, created_at)
SELECT u.id, r.id, '2026-01-09 09:00:00' FROM users u CROSS JOIN roles r
WHERE u.id IN ('00000000-0000-4000-8000-000000000021', '00000000-0000-4000-8000-000000000022', '00000000-0000-4000-8000-000000000023',
               '00000000-0000-4000-8000-000000000024', '00000000-0000-4000-8000-000000000025') AND r.name = 'USER';

INSERT INTO user_roles (user_id, role_id, created_at)
SELECT '00000000-0000-4000-8000-000000000022', r.id, '2026-01-10 09:00:00' FROM roles r WHERE r.name = 'ADMIN';

-- 連携の名前は、Java 版と Go 版がログインのときに書く小文字の名前にする。連携の利用者の ID は、筋書きの oidc_users の sub と
-- GitHub の利用者の id に合わせる。
INSERT INTO user_auth_providers (id, user_id, provider_name, provider_user_id, created_at, updated_at) VALUES
    ('00000000-0000-4000-8000-000000000121', '00000000-0000-4000-8000-000000000021', 'google', 'google-sub-google-only',
     '2026-01-09 09:00:00', '2026-01-09 09:00:00'),
    ('00000000-0000-4000-8000-000000000124', '00000000-0000-4000-8000-000000000024', 'google', 'google-sub-unverified-linked',
     '2026-01-12 09:00:00', '2026-01-12 09:00:00'),
    ('00000000-0000-4000-8000-000000000125', '00000000-0000-4000-8000-000000000025', 'google', 'google-sub-two-providers',
     '2026-01-13 09:00:00', '2026-01-13 09:00:00'),
    ('00000000-0000-4000-8000-000000000126', '00000000-0000-4000-8000-000000000025', 'github', '80000025',
     '2026-01-13 09:00:00', '2026-01-13 09:00:00');

-- ログインの状態の世代(basic.sql と同じ理由で置く)。
INSERT INTO user_token_versions (user_id, token_version, updated_at) VALUES
    ('00000000-0000-4000-8000-000000000021', 0, '2026-01-09 09:00:00'),
    ('00000000-0000-4000-8000-000000000022', 0, '2026-01-10 09:05:00'),
    ('00000000-0000-4000-8000-000000000023', 0, '2026-01-11 09:05:00'),
    ('00000000-0000-4000-8000-000000000024', 0, '2026-01-12 09:00:00'),
    ('00000000-0000-4000-8000-000000000025', 0, '2026-01-13 09:05:00');
