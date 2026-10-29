package com.example.keirekipro.unit.infrastructure.store.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.UUID;

import com.example.keirekipro.config.RedisTestContainerConfig;
import com.example.keirekipro.infrastructure.store.auth.RedisEmailVerificationCurrentTokenStore;
import com.example.keirekipro.usecase.auth.store.EmailVerificationCurrentTokenStore;

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
        RedisEmailVerificationCurrentTokenStoreTest.RedisTemplateTestConfig.class,
        RedisEmailVerificationCurrentTokenStore.class
})
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class RedisEmailVerificationCurrentTokenStoreTest {

    private final EmailVerificationCurrentTokenStore currentTokenStore;

    private final RedisTemplate<String, Object> redisTemplate;

    private static final Duration TTL = Duration.ofHours(24);

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

    @Test
    @DisplayName("put した jti を find で読める")
    void test1() {
        UUID subjectId = UUID.randomUUID();

        currentTokenStore.put(subjectId, "jti-1", TTL);

        assertThat(currentTokenStore.find(subjectId)).contains("jti-1");
        assertThat(currentTokenStore.find(UUID.randomUUID())).isEmpty();
    }

    @Test
    @DisplayName("put の有効期限が渡した時間になる")
    void test2() {
        UUID subjectId = UUID.randomUUID();

        currentTokenStore.put(subjectId, "jti-1", TTL);

        Long ttl = redisTemplate.getExpire("email-verification:current:" + subjectId);
        assertThat(ttl).isBetween(TTL.getSeconds() - 5, TTL.getSeconds());
    }

    @Test
    @DisplayName("同じ jti の consume は1回目だけ true を返す")
    void test3() {
        UUID subjectId = UUID.randomUUID();
        currentTokenStore.put(subjectId, "jti-1", TTL);

        assertThat(currentTokenStore.consume(subjectId, "jti-1")).isTrue();
        assertThat(currentTokenStore.consume(subjectId, "jti-1")).isFalse();
        assertThat(currentTokenStore.find(subjectId)).isEmpty();
    }

    @Test
    @DisplayName("put で置き換えたあとは前の jti の consume が false を返す")
    void test4() {
        UUID subjectId = UUID.randomUUID();
        currentTokenStore.put(subjectId, "jti-old", TTL);

        currentTokenStore.put(subjectId, "jti-new", TTL);

        assertThat(currentTokenStore.consume(subjectId, "jti-old")).isFalse();
        // 値が違うときは消さないので、新しい jti はそのまま使える
        assertThat(currentTokenStore.find(subjectId)).contains("jti-new");
        assertThat(currentTokenStore.consume(subjectId, "jti-new")).isTrue();
    }

    @Test
    @DisplayName("値が無い対象の consume は false を返す")
    void test5() {
        assertThat(currentTokenStore.consume(UUID.randomUUID(), "jti-1")).isFalse();
    }

    @Test
    @DisplayName("clear のあとは find が empty を返し、consume が false を返す")
    void test6() {
        UUID subjectId = UUID.randomUUID();
        currentTokenStore.put(subjectId, "jti-1", TTL);

        currentTokenStore.clear(subjectId);

        assertThat(currentTokenStore.find(subjectId)).isEmpty();
        assertThat(currentTokenStore.consume(subjectId, "jti-1")).isFalse();
    }
}
