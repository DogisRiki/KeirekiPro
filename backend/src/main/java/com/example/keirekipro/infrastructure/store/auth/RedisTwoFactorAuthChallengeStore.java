package com.example.keirekipro.infrastructure.store.auth;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.dto.TwoFactorAuthChallenge;
import com.example.keirekipro.usecase.auth.store.TwoFactorAuthChallengeStore;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * Redis二段階認証チャレンジトークンストア
 */
@Component
@RequiredArgsConstructor
public class RedisTwoFactorAuthChallengeStore implements TwoFactorAuthChallengeStore {

    /**
     * 二段階認証チャレンジトークン用キー接頭辞
     */
    private static final String PREFIX = "2fa:challenge:";

    /**
     * Redisテンプレート
     */
    private final RedisTemplate<String, Object> redisTemplate;

    /**
     * JSONシリアライザ
     */
    private final ObjectMapper objectMapper;

    /**
     * チャレンジトークンを保存する
     *
     * @param token チャレンジトークン
     * @param userId ユーザーID
     * @param ttl 有効期限
     */
    @Override
    public void store(String token, UUID userId, Duration ttl) {
        TwoFactorAuthChallenge challenge = TwoFactorAuthChallenge.builder()
                .userId(userId)
                .attempts(0)
                .build();
        try {
            String json = objectMapper.writeValueAsString(challenge);
            redisTemplate.opsForValue().set(PREFIX + token, json, ttl);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("チャレンジトークンのシリアライズに失敗しました。", e);
        }
    }

    /**
     * チャレンジトークンからチャレンジ情報を取得する
     *
     * @param token チャレンジトークン
     * @return チャレンジ情報（存在しない場合はempty）
     */
    @Override
    public Optional<TwoFactorAuthChallenge> find(String token) {
        Object value = redisTemplate.opsForValue().get(PREFIX + token);
        if (value == null) {
            return Optional.empty();
        }
        try {
            return Optional.of(objectMapper.readValue((String) value, TwoFactorAuthChallenge.class));
        } catch (JsonProcessingException e) {
            return Optional.empty();
        }
    }

    /**
     * 失敗試行回数を加算する
     *
     * @param token チャレンジトークン
     * @return 加算後の試行回数
     */
    @Override
    public int incrementAttempts(String token) {
        Optional<TwoFactorAuthChallenge> opt = find(token);
        if (opt.isEmpty()) {
            return 0;
        }
        TwoFactorAuthChallenge challenge = opt.get();
        challenge.setAttempts(challenge.getAttempts() + 1);
        Long ttlSec = redisTemplate.getExpire(PREFIX + token);
        Duration ttl = (ttlSec != null && ttlSec > 0) ? Duration.ofSeconds(ttlSec) : Duration.ofMinutes(10);
        try {
            String json = objectMapper.writeValueAsString(challenge);
            redisTemplate.opsForValue().set(PREFIX + token, json, ttl);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("チャレンジトークンのシリアライズに失敗しました。", e);
        }
        return challenge.getAttempts();
    }

    /**
     * チャレンジトークンを削除する
     *
     * @param token チャレンジトークン
     */
    @Override
    public void remove(String token) {
        redisTemplate.delete(PREFIX + token);
    }
}
