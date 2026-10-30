package com.example.keirekipro.unit.infrastructure.store.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.config.RedisTestContainerConfig;
import com.example.keirekipro.infrastructure.shared.json.JsonMapperConfig;
import com.example.keirekipro.infrastructure.shared.redis.RedisConfig;
import com.example.keirekipro.infrastructure.store.auth.RedisTwoFactorAuthChallengeStore;
import com.example.keirekipro.usecase.auth.dto.TwoFactorAuthChallenge;
import com.example.keirekipro.usecase.auth.store.TwoFactorAuthChallengeStore;
import tools.jackson.databind.json.JsonMapper;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.ImportAutoConfiguration;
import org.springframework.boot.data.redis.test.autoconfigure.DataRedisTest;
import org.springframework.boot.jackson.autoconfigure.JacksonAutoConfiguration;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.core.io.ClassPathResource;
import org.springframework.data.redis.connection.RedisConnection;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.StringRedisSerializer;
import org.springframework.test.context.NestedTestConfiguration;
import org.springframework.test.context.NestedTestConfiguration.EnclosingConfiguration;
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
        JsonMapper jsonMapper() {
            return JsonMapper.builder().build();
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

    /**
     * 上げる前の backend(Spring Boot 3.5.16)が本番の RedisTemplate で書いた値の見本を読む
     *
     * 見本は src/test/resources/baseline-samples/redis/ にある。値の書き方を本番と同じにするため、外側のテストの設定を引き継がず、
     * 本番の RedisConfig と Spring Boot の Jackson の設定を読み込む
     */
    @Nested
    @NestedTestConfiguration(EnclosingConfiguration.OVERRIDE)
    @DataRedisTest
    @ImportAutoConfiguration(JacksonAutoConfiguration.class)
    @Import({
            RedisTestContainerConfig.class,
            RedisConfig.class,
            JsonMapperConfig.class,
            RedisTwoFactorAuthChallengeStore.class
    })
    class BaselineSample {

        private static final UUID SAMPLE_USER_ID = UUID.fromString("66666666-7777-8888-9999-aaaaaaaaaaaa");

        private static final String SAMPLE_TOKEN = "sample-token";

        private static final String SAMPLE_KEY = "2fa:challenge:" + SAMPLE_TOKEN;

        @Autowired
        private TwoFactorAuthChallengeStore baselineStore;

        @Autowired
        private RedisConnectionFactory connectionFactory;

        @AfterEach
        void deleteSample() {
            try (RedisConnection connection = connectionFactory.getConnection()) {
                connection.keyCommands().del(bytes(SAMPLE_KEY));
            }
        }

        @Test
        @DisplayName("上げる前の backend が書いたチャレンジの見本を、find で読める")
        void test1() throws IOException {
            putSample("store-2fa-challenge.bin");

            Optional<TwoFactorAuthChallenge> result = baselineStore.find(SAMPLE_TOKEN);

            assertThat(result).isPresent();
            assertThat(result.get().getUserId()).isEqualTo(SAMPLE_USER_ID);
            assertThat(result.get().getAttempts()).isZero();
        }

        @Test
        @DisplayName("上げる前の backend が試行回数を加算したあとの見本を、find で読める")
        void test2() throws IOException {
            putSample("store-2fa-challenge-incremented.bin");

            Optional<TwoFactorAuthChallenge> result = baselineStore.find(SAMPLE_TOKEN);

            assertThat(result).isPresent();
            assertThat(result.get().getUserId()).isEqualTo(SAMPLE_USER_ID);
            assertThat(result.get().getAttempts()).isEqualTo(1);
        }

        @Test
        @DisplayName("上げる前の backend が書いたチャレンジの見本の試行回数を加算でき、加算した値を find で読める")
        void test3() throws IOException {
            putSample("store-2fa-challenge.bin");

            int attempts = baselineStore.incrementAttempts(SAMPLE_TOKEN);

            assertThat(attempts).isEqualTo(1);
            Optional<TwoFactorAuthChallenge> result = baselineStore.find(SAMPLE_TOKEN);
            assertThat(result).isPresent();
            assertThat(result.get().getUserId()).isEqualTo(SAMPLE_USER_ID);
            assertThat(result.get().getAttempts()).isEqualTo(1);
        }

        private void putSample(String name) throws IOException {
            try (RedisConnection connection = connectionFactory.getConnection()) {
                connection.stringCommands().set(bytes(SAMPLE_KEY), sample(name));
            }
        }

        private static byte[] bytes(String key) {
            return key.getBytes(StandardCharsets.UTF_8);
        }

        private static byte[] sample(String name) throws IOException {
            return new ClassPathResource("baseline-samples/redis/" + name).getContentAsByteArray();
        }
    }
}
