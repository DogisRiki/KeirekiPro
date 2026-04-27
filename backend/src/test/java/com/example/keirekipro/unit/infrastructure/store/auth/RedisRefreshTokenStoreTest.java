package com.example.keirekipro.unit.infrastructure.store.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.config.RedisTestContainerConfig;
import com.example.keirekipro.infrastructure.store.auth.RedisRefreshTokenStore;
import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.dto.RefreshTokenInfo;
import com.example.keirekipro.usecase.auth.store.RefreshTokenStore;

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
import org.springframework.test.context.TestPropertySource;

import lombok.RequiredArgsConstructor;

@DataRedisTest
@Import({
        RedisTestContainerConfig.class,
        RedisRefreshTokenStoreTest.RedisTemplateTestConfig.class,
        SecurityUtil.class,
        RedisRefreshTokenStore.class
})
@TestPropertySource(properties = {
        "jwt.refresh-token-validity-in-days=7"
})
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class RedisRefreshTokenStoreTest {

    private final RefreshTokenStore refreshTokenStore;

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
    @DisplayName("リフレッシュトークンを発行し、findで正しく取得できる")
    void test1() {
        // テストデータ
        UUID userId = UUID.randomUUID();
        Set<String> roles = Set.of("USER");
        long tokenVersion = 0L;

        // 実行
        String token = refreshTokenStore.issue(userId, roles, tokenVersion);

        // 検証
        assertThat(token).isNotBlank();
        Optional<RefreshTokenInfo> result = refreshTokenStore.find(token);
        assertThat(result).isPresent();
        assertThat(result.get().getUserId()).isEqualTo(userId);
        assertThat(result.get().getRoles()).containsExactlyInAnyOrderElementsOf(roles);
        assertThat(result.get().getTokenVersion()).isEqualTo(tokenVersion);
    }

    @Test
    @DisplayName("複数ロールを持つリフレッシュトークンを発行し、findで正しく取得できる")
    void test2() {
        // テストデータ
        UUID userId = UUID.randomUUID();
        Set<String> roles = Set.of("USER", "ADMIN");
        long tokenVersion = 5L;

        // 実行
        String token = refreshTokenStore.issue(userId, roles, tokenVersion);

        // 検証
        Optional<RefreshTokenInfo> result = refreshTokenStore.find(token);
        assertThat(result).isPresent();
        assertThat(result.get().getRoles()).containsExactlyInAnyOrder("USER", "ADMIN");
        assertThat(result.get().getTokenVersion()).isEqualTo(tokenVersion);
    }

    @Test
    @DisplayName("リフレッシュトークンを削除できる")
    void test3() {
        // テストデータ
        UUID userId = UUID.randomUUID();
        Set<String> roles = Set.of("USER");

        // 事前に発行
        String token = refreshTokenStore.issue(userId, roles, 0L);
        assertThat(refreshTokenStore.find(token)).isPresent();

        // 実行
        refreshTokenStore.remove(token);

        // 検証
        assertThat(refreshTokenStore.find(token)).isEmpty();
    }

    @Test
    @DisplayName("存在しないトークンを検索した場合、emptyが返る")
    void test4() {
        // テストデータ
        String token = "non-existent-" + UUID.randomUUID();

        // 実行
        Optional<RefreshTokenInfo> result = refreshTokenStore.find(token);

        // 検証
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("removeAllByUserで該当ユーザーのリフレッシュトークンが全て削除される")
    @SuppressWarnings("checkstyle:VariableDeclarationUsageDistance")
    void test5() {
        // テストデータ
        UUID userId = UUID.randomUUID();
        UUID otherUserId = UUID.randomUUID();
        Set<String> roles = Set.of("USER");

        String token1 = refreshTokenStore.issue(userId, roles, 0L);
        String token2 = refreshTokenStore.issue(userId, roles, 0L);
        String otherToken = refreshTokenStore.issue(otherUserId, roles, 0L);

        // 実行
        refreshTokenStore.removeAllByUser(userId);

        // 検証
        assertThat(refreshTokenStore.find(token1)).isEmpty();
        assertThat(refreshTokenStore.find(token2)).isEmpty();
        // 他ユーザーのトークンは残ること
        assertThat(refreshTokenStore.find(otherToken)).isPresent();
    }
}
