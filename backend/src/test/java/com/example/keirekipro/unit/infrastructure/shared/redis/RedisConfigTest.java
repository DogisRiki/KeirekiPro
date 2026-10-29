package com.example.keirekipro.unit.infrastructure.shared.redis;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import com.example.keirekipro.config.RedisTestContainerConfig;
import com.example.keirekipro.infrastructure.shared.json.JsonMapperConfig;
import com.example.keirekipro.infrastructure.shared.redis.RedisConfig;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.ImportAutoConfiguration;
import org.springframework.boot.data.redis.test.autoconfigure.DataRedisTest;
import org.springframework.boot.jackson.autoconfigure.JacksonAutoConfiguration;
import org.springframework.context.annotation.Import;
import org.springframework.core.io.ClassPathResource;
import org.springframework.data.redis.connection.RedisConnection;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.test.context.TestConstructor;

import lombok.RequiredArgsConstructor;

/**
 * RedisConfig の RedisTemplate が書く値のバイトが、Spring Boot 3(Jackson 2)のときと同じであることを確かめる
 *
 * 見本は、Spring Boot 3.5.16 の main(b585d9c6)の RedisConfig で書いた値のバイトで、src/test/resources/baseline-samples/redis/ にある
 */
@DataRedisTest
// RedisConfig が受け取る JsonMapper は Jackson の自動設定が作る。@DataRedisTest はこの自動設定を含まないため足す
@ImportAutoConfiguration(JacksonAutoConfiguration.class)
@Import({
        RedisTestContainerConfig.class,
        RedisConfig.class,
        JsonMapperConfig.class
})
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class RedisConfigTest {

    private final RedisTemplate<String, Object> redisTemplate;

    private final RedisConnectionFactory connectionFactory;

    private static final String JSON_STRING_KEY = "sample:json-string";

    private static final String EMOJI_STRING_KEY = "sample:emoji-string";

    private static final String JSON_STRING = "{\"a\":\"b\",\"n\":1}";

    private static final String EMOJI_STRING = "絵文字😀👍🏽を含む文字列";

    @AfterEach
    void deleteSample() {
        redisTemplate.delete(JSON_STRING_KEY);
        redisTemplate.delete(EMOJI_STRING_KEY);
    }

    @Test
    @DisplayName("JSONの文字列を書いたバイトが、見本と同じになる")
    void test1() throws IOException {
        redisTemplate.opsForValue().set(JSON_STRING_KEY, JSON_STRING);

        assertThat(rawValue(JSON_STRING_KEY)).isEqualTo(sample("template-json-string.bin"));
    }

    @Test
    @DisplayName("絵文字を含む文字列を書いたバイトが、絵文字をサロゲートの対の形で書いた見本と同じになる")
    void test2() throws IOException {
        redisTemplate.opsForValue().set(EMOJI_STRING_KEY, EMOJI_STRING);

        assertThat(rawValue(EMOJI_STRING_KEY)).isEqualTo(sample("template-emoji-string.bin"));
    }

    @Test
    @DisplayName("JSONの文字列の見本のバイトを読むと、元の文字列に戻る")
    void test3() throws IOException {
        putRawValue(JSON_STRING_KEY, sample("template-json-string.bin"));

        assertThat(redisTemplate.opsForValue().get(JSON_STRING_KEY)).isEqualTo(JSON_STRING);
    }

    @Test
    @DisplayName("絵文字を含む文字列の見本のバイトを読むと、元の文字列に戻る")
    void test4() throws IOException {
        putRawValue(EMOJI_STRING_KEY, sample("template-emoji-string.bin"));

        assertThat(redisTemplate.opsForValue().get(EMOJI_STRING_KEY)).isEqualTo(EMOJI_STRING);
    }

    private byte[] rawValue(String key) {
        try (RedisConnection connection = connectionFactory.getConnection()) {
            return connection.stringCommands().get(key.getBytes(StandardCharsets.UTF_8));
        }
    }

    private void putRawValue(String key, byte[] value) {
        try (RedisConnection connection = connectionFactory.getConnection()) {
            connection.stringCommands().set(key.getBytes(StandardCharsets.UTF_8), value);
        }
    }

    private static byte[] sample(String name) throws IOException {
        return new ClassPathResource("baseline-samples/redis/" + name).getContentAsByteArray();
    }
}
