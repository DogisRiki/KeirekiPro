package com.example.keirekipro.unit.infrastructure.store.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.config.RedisTestContainerConfig;
import com.example.keirekipro.infrastructure.store.auth.RedisTwoFactorAuthChallengeStore;
import com.example.keirekipro.usecase.auth.dto.TwoFactorAuthChallenge;
import com.example.keirekipro.usecase.auth.store.TwoFactorAuthChallengeStore;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.data.redis.DataRedisTest;
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
        RedisTwoFactorAuthChallengeStoreTest.RedisTemplateTestConfig.class,
        RedisTwoFactorAuthChallengeStore.class
})
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class RedisTwoFactorAuthChallengeStoreTest {

    private final TwoFactorAuthChallengeStore twoFactorAuthChallengeStore;

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

        @Bean
        ObjectMapper objectMapper() {
            return new ObjectMapper();
        }
    }

    @Test
    @DisplayName("チャレンジトークンを保存し、トークンから正しく取得できる")
    void test1() {
        // テストデータ
        String token = "test-challenge-token";
        UUID userId = UUID.randomUUID();

        // 実行
        twoFactorAuthChallengeStore.store(token, userId, Duration.ofMinutes(1));

        // 検証
        Optional<TwoFactorAuthChallenge> result = twoFactorAuthChallengeStore.find(token);
        assertThat(result).isPresent();
        assertThat(result.get().getUserId()).isEqualTo(userId);
        assertThat(result.get().getAttempts()).isZero();
    }

    @Test
    @DisplayName("チャレンジトークンを有効期限付きで保存し、期限切れ後に取得できなくなる")
    void test2() throws InterruptedException {
        // テストデータ
        String token = "test-challenge-token-expire";
        UUID userId = UUID.randomUUID();
        Duration ttl = Duration.ofSeconds(1);

        // 実行
        twoFactorAuthChallengeStore.store(token, userId, ttl);

        // 保存直後は取得できる
        assertThat(twoFactorAuthChallengeStore.find(token)).isPresent();

        // 有効期限が切れるまで待機
        Thread.sleep(1200);

        // 期限切れ後は取得できない
        assertThat(twoFactorAuthChallengeStore.find(token)).isEmpty();
    }

    @Test
    @DisplayName("チャレンジトークンを削除できる")
    void test3() {
        // テストデータ
        String token = "test-challenge-token-remove";
        UUID userId = UUID.randomUUID();

        // 事前に保存
        twoFactorAuthChallengeStore.store(token, userId, Duration.ofMinutes(1));
        assertThat(twoFactorAuthChallengeStore.find(token)).isPresent();

        // 実行
        twoFactorAuthChallengeStore.remove(token);

        // 検証
        assertThat(twoFactorAuthChallengeStore.find(token)).isEmpty();
    }

    @Test
    @DisplayName("存在しないトークンを検索した場合、emptyが返る")
    void test4() {
        // テストデータ
        String token = "non-existent-token";

        // 実行
        Optional<TwoFactorAuthChallenge> result = twoFactorAuthChallengeStore.find(token);

        // 検証
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("試行回数を加算できる")
    void test5() {
        // テストデータ
        String token = "test-challenge-token-increment";
        UUID userId = UUID.randomUUID();

        // 事前に保存
        twoFactorAuthChallengeStore.store(token, userId, Duration.ofMinutes(1));

        // 実行
        int firstResult = twoFactorAuthChallengeStore.incrementAttempts(token);
        int secondResult = twoFactorAuthChallengeStore.incrementAttempts(token);

        // 検証
        assertThat(firstResult).isEqualTo(1);
        assertThat(secondResult).isEqualTo(2);
        Optional<TwoFactorAuthChallenge> stored = twoFactorAuthChallengeStore.find(token);
        assertThat(stored).isPresent();
        assertThat(stored.get().getAttempts()).isEqualTo(2);
    }

    @Test
    @DisplayName("存在しないトークンに対してincrementAttemptsを実行した場合、0が返る")
    void test6() {
        // テストデータ
        String token = "non-existent-token-increment";

        // 実行
        int result = twoFactorAuthChallengeStore.incrementAttempts(token);

        // 検証
        assertThat(result).isZero();
    }
}
