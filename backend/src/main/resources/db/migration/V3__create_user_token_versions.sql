-- ユーザートークンバージョンテーブル
CREATE TABLE user_token_versions (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    token_version BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP(6) NOT NULL
);

COMMENT ON TABLE user_token_versions IS 'ユーザートークンバージョン';
COMMENT ON COLUMN user_token_versions.user_id IS 'ユーザーID';
COMMENT ON COLUMN user_token_versions.token_version IS 'トークンバージョン';
COMMENT ON COLUMN user_token_versions.updated_at IS '更新日時';

-- 既存ユーザー全員分のレコードを一括INSERT
INSERT INTO user_token_versions(user_id, token_version, updated_at)
SELECT id, 0, NOW()
FROM users;
