package com.example.keirekipro.unit.infrastructure.store.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.config.RedisTestContainerConfig;
import com.example.keirekipro.infrastructure.store.auth.RedisPendingRegistrationStore;
import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.json.JsonMapper;

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
        RedisPendingRegistrationStoreTest.RedisTemplateTestConfig.class,
        RedisPendingRegistrationStore.class
})
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class RedisPendingRegistrationStoreTest {

    private final PendingRegistrationStore pendingRegistrationStore;

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

        @Bean
        ObjectMapper objectMapper() {
            // 本番の ObjectMapper と同じく、Instant を読み書きできるようにする
            return JsonMapper.builder().findAndAddModules().build();
        }
    }

    private static PendingRegistration registration(String email, Instant createdAt) {
        return new PendingRegistration(UUID.randomUUID(), email, "hashed-password", "pending-user", createdAt);
    }

    private static String uniqueEmail() {
        return "pending-" + UUID.randomUUID() + "@keirekipro.click";
    }

    @Test
    @DisplayName("save した登録を findById で読むと同じ値が返る")
    void test1() {
        PendingRegistration saved = registration(uniqueEmail(), Instant.now().truncatedTo(ChronoUnit.MILLIS));

        pendingRegistrationStore.save(saved, TTL);

        assertThat(pendingRegistrationStore.findById(saved.id())).contains(saved);
        assertThat(pendingRegistrationStore.findById(UUID.randomUUID())).isEmpty();
    }

    @Test
    @DisplayName("save の有効期限が24時間になる")
    void test2() {
        String email = uniqueEmail();
        PendingRegistration saved = registration(email, Instant.now());

        pendingRegistrationStore.save(saved, TTL);

        Long registrationTtl = redisTemplate.getExpire("pending-registration:" + saved.id());
        Long emailSetTtl = redisTemplate.getExpire("pending-registration:email:" + email);
        assertThat(registrationTtl).isBetween(TTL.getSeconds() - 5, TTL.getSeconds());
        assertThat(emailSetTtl).isBetween(TTL.getSeconds() - 5, TTL.getSeconds());
    }

    @Test
    @DisplayName("同じメールアドレスの登録を2つ置くと findByEmail が新しい順に2つ返す")
    void test3() {
        String email = uniqueEmail();
        Instant now = Instant.now().truncatedTo(ChronoUnit.MILLIS);
        PendingRegistration older = registration(email, now.minus(1, ChronoUnit.HOURS));
        PendingRegistration newer = registration(email, now);
        PendingRegistration otherEmail = registration(uniqueEmail(), now);

        // 古い登録をあとから置いても、作った日時の新しい順に並ぶ
        pendingRegistrationStore.save(newer, TTL);
        pendingRegistrationStore.save(older, TTL);
        pendingRegistrationStore.save(otherEmail, TTL);

        assertThat(pendingRegistrationStore.findByEmail(email, 10)).containsExactly(newer, older);
        assertThat(pendingRegistrationStore.findByEmail(email, 1)).containsExactly(newer);
    }

    @Test
    @DisplayName("extend で有効期限を置き直す")
    void test4() {
        String email = uniqueEmail();
        PendingRegistration saved = registration(email, Instant.now());
        pendingRegistrationStore.save(saved, Duration.ofMinutes(1));

        pendingRegistrationStore.extend(saved.id(), TTL);

        Long registrationTtl = redisTemplate.getExpire("pending-registration:" + saved.id());
        Long emailSetTtl = redisTemplate.getExpire("pending-registration:email:" + email);
        assertThat(registrationTtl).isBetween(TTL.getSeconds() - 5, TTL.getSeconds());
        assertThat(emailSetTtl).isBetween(TTL.getSeconds() - 5, TTL.getSeconds());
    }

    @Test
    @DisplayName("消えた登録の ID を findByEmail が集合から取り除く")
    void test5() {
        String email = uniqueEmail();
        Instant now = Instant.now().truncatedTo(ChronoUnit.MILLIS);
        PendingRegistration expired = registration(email, now.minus(1, ChronoUnit.HOURS));
        PendingRegistration alive = registration(email, now);
        pendingRegistrationStore.save(expired, TTL);
        pendingRegistrationStore.save(alive, TTL);

        // 有効期限で消えたときと同じく、登録の本体だけを消す
        redisTemplate.delete("pending-registration:" + expired.id());

        assertThat(pendingRegistrationStore.findByEmail(email, 10)).containsExactly(alive);
        assertThat(redisTemplate.opsForSet().members("pending-registration:email:" + email))
                .containsExactly(alive.id().toString());
    }

    @Test
    @DisplayName("delete は登録と、メールアドレスの集合の中のその登録の ID を消す")
    void test6() {
        String email = uniqueEmail();
        Instant now = Instant.now().truncatedTo(ChronoUnit.MILLIS);
        PendingRegistration deleted = registration(email, now.minus(1, ChronoUnit.HOURS));
        PendingRegistration kept = registration(email, now);
        pendingRegistrationStore.save(deleted, TTL);
        pendingRegistrationStore.save(kept, TTL);

        pendingRegistrationStore.delete(deleted);

        Optional<PendingRegistration> found = pendingRegistrationStore.findById(deleted.id());
        List<PendingRegistration> byEmail = pendingRegistrationStore.findByEmail(email, 10);
        assertThat(found).isEmpty();
        assertThat(byEmail).containsExactly(kept);
        assertThat(redisTemplate.opsForSet().members("pending-registration:email:" + email))
                .containsExactly(kept.id().toString());
    }

    @Test
    @DisplayName("save は同じ ID の登録を上書きする")
    void test7() {
        String email = uniqueEmail();
        PendingRegistration original = registration(email, Instant.now().truncatedTo(ChronoUnit.MILLIS));
        PendingRegistration overwritten = new PendingRegistration(original.id(), email, "new-hash", "renamed",
                original.createdAt());

        pendingRegistrationStore.save(original, TTL);
        pendingRegistrationStore.save(overwritten, TTL);

        assertThat(pendingRegistrationStore.findById(original.id())).contains(overwritten);
        assertThat(pendingRegistrationStore.findByEmail(email, 10)).containsExactly(overwritten);
    }
}
