package com.example.keirekipro.infrastructure.store.auth;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.store.PasswordResetTokenStore;

import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * Redisパスワードリセットトークンストア
 */
@Component
@RequiredArgsConstructor
public class RedisPasswordResetTokenStore implements PasswordResetTokenStore {

    /**
     * パスワードリセット用キー接頭辞
     */
    private static final String PREFIX = "password-reset:";

    /**
     * Redisテンプレート
     */
    private final RedisTemplate<String, Object> redisTemplate;

    /**
     * トークンを保存する
     *
     * @param token  トークン
     * @param userId ユーザーID
     * @param ttl    有効期限
     */
    @Override
    public void store(String token, UUID userId, Duration ttl) {
        redisTemplate.opsForValue().set(PREFIX + token, userId.toString(), ttl);
    }

    /**
     * トークンからユーザーIDを取得する
     *
     * @param token トークン
     * @return ユーザーID（存在しない場合はempty）
     */
    @Override
    public Optional<UUID> findUserId(String token) {
        Object value = redisTemplate.opsForValue().get(PREFIX + token);
        if (value == null) {
            return Optional.empty();
        }
        return Optional.of(UUID.fromString((String) value));
    }

    /**
     * トークンを削除する
     *
     * @param token トークン
     */
    @Override
    public void remove(String token) {
        redisTemplate.delete(PREFIX + token);
    }
}
