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
    'test@keirekipro.click',
    'hashedPassword',
    'test-user',
    'profile/test-user.jpg',
    false,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
);
