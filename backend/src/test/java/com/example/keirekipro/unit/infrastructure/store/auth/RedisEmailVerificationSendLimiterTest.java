package com.example.keirekipro.unit.infrastructure.store.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;

import com.example.keirekipro.config.RedisTestContainerConfig;
import com.example.keirekipro.infrastructure.store.auth.RedisEmailVerificationSendLimiter;
import com.example.keirekipro.usecase.auth.store.EmailVerificationSendLimiter;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.data.redis.test.autoconfigure.DataRedisTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.StringRedisSerializer;
import org.springframework.test.context.TestConstructor;

import lombok.RequiredArgsConstructor;

@DataRedisTest
@Import({
        RedisTestContainerConfig.class,
        RedisEmailVerificationSendLimiterTest.RedisTemplateTestConfig.class,
        RedisEmailVerificationSendLimiter.class
})
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class RedisEmailVerificationSendLimiterTest {

    private final EmailVerificationSendLimiter sendLimiter;

    private final RedisTemplate<String, Object> redisTemplate;

    @TestConfiguration
    static class RedisTemplateTestConfig {

        @Bean
        RedisTemplate<String, Object> redisTemplate(RedisConnectionFactory connectionFactory) {
            RedisTemplate<String, Object> template = new RedisTemplate<>();
            template.setConnectionFactory(connectionFactory);

            // 本テストでは String を保存・取得するため、文字列シリアライザで統一
            StringRedisSerializer stringSerializer = new StringRedisSerializer();
            template.setKeySerializer(stringSerializer);
            template.setValueSerializer(stringSerializer);
            template.setHashKeySerializer(stringSerializer);
            template.setHashValueSerializer(stringSerializer);

            template.afterPropertiesSet();
            return template;
        }
    }

    private static String uniqueEmail() {
        return "rate-" + UUID.randomUUID() + "@keirekipro.click";
    }

    @Test
    @DisplayName("同じメールアドレスの2回目の tryAcquire は60秒の間 false を返す")
    void test1() {
        String email = uniqueEmail();

        assertThat(sendLimiter.tryAcquire(email)).isTrue();
        assertThat(sendLimiter.tryAcquire(email)).isFalse();

        Long ttl = redisTemplate.getExpire("email-verification:rate:" + email);
        assertThat(ttl).isBetween(55L, 60L);
    }

    @Test
    @DisplayName("release のあとは tryAcquire が true を返す")
    void test2() {
        String email = uniqueEmail();
        sendLimiter.tryAcquire(email);

        sendLimiter.release(email);

        assertThat(sendLimiter.tryAcquire(email)).isTrue();
    }

    @Test
    @DisplayName("別のメールアドレスの tryAcquire は互いに影響しない")
    void test3() {
        String email = uniqueEmail();
        String otherEmail = uniqueEmail();

        assertThat(sendLimiter.tryAcquire(email)).isTrue();
        assertThat(sendLimiter.tryAcquire(otherEmail)).isTrue();
    }
}
