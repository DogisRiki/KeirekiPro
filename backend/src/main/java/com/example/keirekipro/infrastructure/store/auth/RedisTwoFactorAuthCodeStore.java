package com.example.keirekipro.infrastructure.store.auth;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.store.TwoFactorAuthCodeStore;

import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * Redis二段階認証コードストア
 */
@Component
@RequiredArgsConstructor
public class RedisTwoFactorAuthCodeStore implements TwoFactorAuthCodeStore {

    /**
     * 二段階認証コード用キー接頭辞
     */
    private static final String PREFIX = "2fa:";

    /**
     * Redisテンプレート
     */
    private final RedisTemplate<String, Object> redisTemplate;

    /**
     * 認証コードを保存する
     *
     * @param userId ユーザーID
     * @param code   認証コード
     * @param ttl    有効期限
     */
    @Override
    public void store(UUID userId, String code, Duration ttl) {
        redisTemplate.opsForValue().set(PREFIX + userId, code, ttl);
    }

    /**
     * 認証コードを取得する
     *
     * @param userId ユーザーID
     * @return 認証コード（存在しない場合はempty）
     */
    @Override
    public Optional<String> find(UUID userId) {
        Object value = redisTemplate.opsForValue().get(PREFIX + userId);
        if (value == null) {
            return Optional.empty();
        }
        return Optional.of((String) value);
    }

    /**
     * 認証コードを削除する
     *
     * @param userId ユーザーID
     */
    @Override
    public void remove(UUID userId) {
        redisTemplate.delete(PREFIX + userId);
    }
}
