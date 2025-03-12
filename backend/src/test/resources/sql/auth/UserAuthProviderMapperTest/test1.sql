INSERT INTO users (
    id,
    email,
    password,
    username,
    two_factor_auth_enabled,
    created_at,
    updated_at
) VALUES (
    '123e4567-e89b-12d3-a456-426614174000',
    'test@example.com',
    'hashedPassword',
    'testuser',
    false,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
);
INSERT INTO user_auth_providers(
    id,
    user_id,
    provider_type,
    provider_user_id,
    created_at,
    updated_at
)
VALUES(
    'fedc4646-ee66-4565-bc29-17bf4cb22603',
    '123e4567-e89b-12d3-a456-426614174000',
    'GOOGLE',
    'google-uid-12345',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
);
