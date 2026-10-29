package com.example.keirekipro.infrastructure.store.auth;

import java.time.Duration;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.store.EmailVerificationCurrentTokenStore;

import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * Redis最新の確認のリンクのIDストア
 */
@Component
@RequiredArgsConstructor
public class RedisEmailVerificationCurrentTokenStore implements EmailVerificationCurrentTokenStore {

    /**
     * 最新の確認のリンクのID用キー接頭辞
     */
    private static final String PREFIX = "email-verification:current:";

    /**
     * 置いてある値が渡した値と同じときだけ消すスクリプト
     * 比べることと消すことを、ほかの要求を間に挟まずに行う
     */
    private static final RedisScript<Long> CONSUME_SCRIPT = new DefaultRedisScript<>(
            "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) else return 0 end",
            Long.class);

    /**
     * Redisテンプレート
     */
    private final RedisTemplate<String, Object> redisTemplate;

    /**
     * 最新のjtiを置き換える
     *
     * @param subjectId 対象のID
     * @param jti リンクのID
     * @param ttl そのリンクの期限までの時間
     */
    @Override
    public void put(UUID subjectId, String jti, Duration ttl) {
        redisTemplate.opsForValue().set(PREFIX + subjectId, jti, ttl);
    }

    /**
     * 最新のjtiを読む
     *
     * @param subjectId 対象のID
     * @return jti（存在しない場合はempty）
     */
    @Override
    public Optional<String> find(UUID subjectId) {
        Object value = redisTemplate.opsForValue().get(PREFIX + subjectId);
        if (value == null) {
            return Optional.empty();
        }
        return Optional.of((String) value);
    }

    /**
     * 置いてある値がjtiと同じときだけ消す
     *
     * @param subjectId 対象のID
     * @param jti リンクのID
     * @return 消せた場合はtrue
     */
    @Override
    public boolean consume(UUID subjectId, String jti) {
        Long deleted = redisTemplate.execute(CONSUME_SCRIPT, List.of(PREFIX + subjectId), jti);
        return deleted != null && deleted > 0;
    }

    /**
     * 最新のjtiを消す
     *
     * @param subjectId 対象のID
     */
    @Override
    public void clear(UUID subjectId) {
        redisTemplate.delete(PREFIX + subjectId);
    }
}
