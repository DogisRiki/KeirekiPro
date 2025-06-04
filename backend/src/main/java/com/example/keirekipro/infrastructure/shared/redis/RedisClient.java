package com.example.keirekipro.infrastructure.shared.redis;

import java.time.Duration;
import java.util.Optional;

import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * Redisクライアント
 */
@Component
@RequiredArgsConstructor
public class RedisClient {

    private final RedisTemplate<String, Object> redisTemplate;

    /**
     * 値をRedisに保存する
     *
     * @param key   キー
     * @param value 値
     */
    public void setValue(String key, Object value) {
        redisTemplate.opsForValue().set(key, value);
    }

    /**
     * 値をRedisに保存し、有効期限を設定する
     *
     * @param key     キー
     * @param value   値
     * @param timeout 有効期限
     */
    public void setValue(String key, Object value, Duration timeout) {
        redisTemplate.opsForValue().set(key, value, timeout);
    }

    /**
     * Redisから値を取得する
     *
     * @param key キー
     * @return 値をラップしたOptional（存在しない場合はempty）
     */
    public <T> Optional<T> getValue(String key, Class<T> type) {
        Object value = redisTemplate.opsForValue().get(key);
        if (value == null) {
            return Optional.empty();
        }

        return Optional.of(type.cast(value));
    }

    /**
     * Redisから指定されたキーの値を削除する
     *
     * @param key キー
     * @return 削除に成功した場合はtrue
     */
    public boolean deleteValue(String key) {
        return Boolean.TRUE.equals(redisTemplate.delete(key));
    }

    /**
     * キーの有効期限を設定する
     *
     * @param key     キー
     * @param timeout 有効期限
     * @return 成功した場合はtrue
     */
    public boolean expire(String key, Duration timeout) {
        return Boolean.TRUE.equals(redisTemplate.expire(key, timeout));
    }

    /**
     * キーが存在するか確認する
     *
     * @param key キー
     * @return 存在する場合はtrue
     */
    public boolean hasKey(String key) {
        return Boolean.TRUE.equals(redisTemplate.hasKey(key));
    }
}
