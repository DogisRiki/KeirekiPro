package com.example.keirekipro.unit.infrastructure.store.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.config.RedisTestContainerConfig;
import com.example.keirekipro.usecase.auth.store.TwoFactorAuthCodeStore;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.data.redis.DataRedisTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Import;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.StringRedisSerializer;
import org.springframework.test.context.TestConstructor;

import lombok.RequiredArgsConstructor;

@DataRedisTest
@Import({
        RedisTestContainerConfig.class,
        RedisTwoFactorAuthCodeStoreTest.RedisTemplateTestConfig.class
})
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
@ComponentScan(basePackages = "com.example.keirekipro.infrastructure.store.auth")
class RedisTwoFactorAuthCodeStoreTest {

    private final TwoFactorAuthCodeStore twoFactorAuthCodeStore;

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
    @DisplayName("認証コードを保存し、ユーザーIDから正しく取得できる")
    void test1() {
        // テストデータ
        UUID userId = UUID.randomUUID();
        String code = "012345";

        // 実行
        twoFactorAuthCodeStore.store(userId, code, Duration.ofMinutes(1));

        // 検証
        Optional<String> result = twoFactorAuthCodeStore.find(userId);
        assertThat(result).isPresent();
        assertThat(result.get()).isEqualTo(code);
    }

    @Test
    @DisplayName("認証コードを有効期限付きで保存し、期限切れ後に取得できなくなる")
    void test2() throws InterruptedException {
        // テストデータ
        UUID userId = UUID.randomUUID();
        String code = "654321";
        Duration ttl = Duration.ofSeconds(1);

        // 実行
        twoFactorAuthCodeStore.store(userId, code, ttl);

        // 保存直後は取得できる
        assertThat(twoFactorAuthCodeStore.find(userId))
                .isPresent()
                .contains(code);

        // 有効期限が切れるまで待機
        Thread.sleep(1200);

        // 期限切れ後は取得できない
        assertThat(twoFactorAuthCodeStore.find(userId)).isEmpty();
    }

    @Test
    @DisplayName("認証コードを削除できる")
    void test3() {
        // テストデータ
        UUID userId = UUID.randomUUID();
        String code = "999999";

        // 事前に保存
        twoFactorAuthCodeStore.store(userId, code, Duration.ofMinutes(1));
        assertThat(twoFactorAuthCodeStore.find(userId)).isPresent();

        // 実行
        twoFactorAuthCodeStore.remove(userId);

        // 検証
        assertThat(twoFactorAuthCodeStore.find(userId)).isEmpty();
    }

    @Test
    @DisplayName("存在しないユーザーIDを検索した場合、emptyが返る")
    void test4() {
        // テストデータ
        UUID userId = UUID.randomUUID();

        // 実行
        Optional<String> result = twoFactorAuthCodeStore.find(userId);

        // 検証
        assertThat(result).isEmpty();
    }
}
