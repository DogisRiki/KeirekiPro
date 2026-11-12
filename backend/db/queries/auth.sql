-- 認証の操作が読み書きする問い合わせ。
-- Java 版の MyBatis の問い合わせ(UserMapper.xml と UserTokenVersionMapper.xml)と、同じ列を同じ値で書く。
-- 時刻は、user_roles の付与日時だけをデータベースの NOW() で決め、ほかは呼ぶ側が渡す(Java 版と同じ)。
-- 利用者を読む3つの問い合わせは、外部認証の連携とロールを LEFT JOIN でつなぐため、
-- 連携の数とロールの数を掛けた数の行を返す。呼ぶ側が、重なった行をまとめる。

-- name: GetUserRowsByID :many
SELECT
    u.id AS u_id,
    u.email AS u_email,
    u.password AS u_password,
    u.username AS u_username,
    u.profile_image AS u_profile_image,
    u.two_factor_auth_enabled AS u_two_factor_auth_enabled,
    u.created_at AS u_created_at,
    u.updated_at AS u_updated_at,
    u.email_verified_at AS u_email_verified_at,
    u.pending_email AS u_pending_email,
    p.id AS p_id,
    p.provider_name AS p_provider_name,
    p.provider_user_id AS p_provider_user_id,
    p.created_at AS p_created_at,
    p.updated_at AS p_updated_at,
    r.name AS r_name
FROM users u
    LEFT JOIN user_auth_providers p ON p.user_id = u.id
    LEFT JOIN user_roles ur ON ur.user_id = u.id
    LEFT JOIN roles r ON r.id = ur.role_id
WHERE u.id = $1;

-- name: GetUserRowsByEmail :many
SELECT
    u.id AS u_id,
    u.email AS u_email,
    u.password AS u_password,
    u.username AS u_username,
    u.profile_image AS u_profile_image,
    u.two_factor_auth_enabled AS u_two_factor_auth_enabled,
    u.created_at AS u_created_at,
    u.updated_at AS u_updated_at,
    u.email_verified_at AS u_email_verified_at,
    u.pending_email AS u_pending_email,
    p.id AS p_id,
    p.provider_name AS p_provider_name,
    p.provider_user_id AS p_provider_user_id,
    p.created_at AS p_created_at,
    p.updated_at AS p_updated_at,
    r.name AS r_name
FROM users u
    LEFT JOIN user_auth_providers p ON p.user_id = u.id
    LEFT JOIN user_roles ur ON ur.user_id = u.id
    LEFT JOIN roles r ON r.id = ur.role_id
WHERE u.email = $1;

-- 外部認証の連携から利用者を探す。Java 版と同じく、連携は INNER JOIN でつなぐため、
-- 返る行の連携は、探した1件だけである。呼ぶ側は、見つけた利用者の id で GetUserRowsByID を呼び直す。
-- name: GetUserRowsByProvider :many
SELECT
    u.id AS u_id,
    u.email AS u_email,
    u.password AS u_password,
    u.username AS u_username,
    u.profile_image AS u_profile_image,
    u.two_factor_auth_enabled AS u_two_factor_auth_enabled,
    u.created_at AS u_created_at,
    u.updated_at AS u_updated_at,
    u.email_verified_at AS u_email_verified_at,
    u.pending_email AS u_pending_email,
    p.id AS p_id,
    p.provider_name AS p_provider_name,
    p.provider_user_id AS p_provider_user_id,
    p.created_at AS p_created_at,
    p.updated_at AS p_updated_at,
    r.name AS r_name
FROM users u
    INNER JOIN user_auth_providers p ON u.id = p.user_id
    LEFT JOIN user_roles ur ON ur.user_id = u.id
    LEFT JOIN roles r ON r.id = ur.role_id
WHERE p.provider_name = sqlc.arg(provider_name)
    AND p.provider_user_id = sqlc.arg(provider_user_id);

-- 利用者を作るか書き換える。作成日時は書き換えない(Java 版と同じ)。
-- メールアドレスの一意の制約に反したときは、データベースがエラーを返す。
-- name: UpsertUser :exec
INSERT INTO users (
    id,
    email,
    password,
    username,
    profile_image,
    two_factor_auth_enabled,
    created_at,
    updated_at,
    email_verified_at,
    pending_email
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
)
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    password = EXCLUDED.password,
    username = EXCLUDED.username,
    profile_image = EXCLUDED.profile_image,
    two_factor_auth_enabled = EXCLUDED.two_factor_auth_enabled,
    updated_at = EXCLUDED.updated_at,
    email_verified_at = EXCLUDED.email_verified_at,
    pending_email = EXCLUDED.pending_email;

-- name: DeleteUserAuthProviders :exec
DELETE FROM user_auth_providers WHERE user_id = $1;

-- name: InsertUserAuthProvider :exec
INSERT INTO user_auth_providers (
    id,
    user_id,
    provider_name,
    provider_user_id,
    created_at,
    updated_at
) VALUES (
    $1, $2, $3, $4, $5, $6
);

-- name: DeleteUserRoles :exec
DELETE FROM user_roles WHERE user_id = $1;

-- ロールの名前からロールの id を引いて付ける。名前の無いロールは付けない。
-- name: InsertUserRole :exec
INSERT INTO user_roles (user_id, role_id, created_at)
SELECT sqlc.arg(user_id)::uuid, id, NOW()
FROM roles
WHERE name = sqlc.arg(role_name)
ON CONFLICT (user_id, role_id) DO NOTHING;

-- 行が無いとき、呼ぶ側は世代の番号を 0 として扱う(Java 版と同じ)。
-- name: GetTokenVersion :one
SELECT token_version FROM user_token_versions WHERE user_id = $1;

-- name: InsertTokenVersion :exec
INSERT INTO user_token_versions (user_id, token_version, updated_at)
VALUES ($1, 0, $2);

-- 行が無ければ何もしない(Java 版と同じ)。
-- name: IncrementTokenVersion :exec
UPDATE user_token_versions
SET token_version = token_version + 1,
    updated_at = $2
WHERE user_id = $1;
