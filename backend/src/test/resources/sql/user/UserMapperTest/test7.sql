INSERT INTO users (
    id,
    email,
    password,
    username,
    profile_image,
    two_factor_auth_enabled,
    created_at,
    updated_at
) VALUES (
    '123e4567-e89b-12d3-a456-426614174000',
    'test@example.com',
    'hashedPassword',
    'test-user',
    'profile/test-user.jpg',
    false,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
);

INSERT INTO user_auth_providers (
    id,
    user_id,
    provider_type,
    provider_user_id,
    created_at,
    updated_at
) VALUES (
    'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    '123e4567-e89b-12d3-a456-426614174000',
    'GOOGLE',
    '109876543210987654321',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
);
