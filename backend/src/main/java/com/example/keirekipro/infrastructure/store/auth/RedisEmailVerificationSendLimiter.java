package com.example.keirekipro.infrastructure.store.auth;

import java.time.Duration;

import com.example.keirekipro.usecase.auth.store.EmailVerificationSendLimiter;

import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * Redis確認のメールの送信間隔の制限
 */
@Component
@RequiredArgsConstructor
public class RedisEmailVerificationSendLimiter implements EmailVerificationSendLimiter {

    /**
     * 送信間隔の制限用キー接頭辞
     */
    private static final String PREFIX = "email-verification:rate:";

    /**
     * 同じメールアドレスへ送る間隔
     */
    private static final Duration INTERVAL = Duration.ofSeconds(60);

    /**
     * Redisテンプレート
     */
    private final RedisTemplate<String, Object> redisTemplate;

    /**
     * 送ってよいかを判定し、送ったことを記録する
     * キーが無いときだけ置く命令1つで行うため、サーバーが複数台でも1分に1通に限られる
     *
     * @param email メールアドレス
     * @return 送ってよい場合はtrue
     */
    @Override
    public boolean tryAcquire(String email) {
        Boolean acquired = redisTemplate.opsForValue().setIfAbsent(PREFIX + email, "1", INTERVAL);
        return Boolean.TRUE.equals(acquired);
    }

    /**
     * 送ったことの記録を消す
     *
     * @param email メールアドレス
     */
    @Override
    public void release(String email) {
        redisTemplate.delete(PREFIX + email);
    }
}
