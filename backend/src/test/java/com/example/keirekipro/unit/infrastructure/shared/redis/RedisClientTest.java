package com.example.keirekipro.unit.infrastructure.shared.redis;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.Optional;

import com.example.keirekipro.config.RedisTestConfiguration;
import com.example.keirekipro.config.TestContainersConfig;
import com.example.keirekipro.infrastructure.shared.redis.RedisClient;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.data.redis.DataRedisTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.TestConstructor;

import lombok.RequiredArgsConstructor;

@DataRedisTest
@Import({ RedisTestConfiguration.class, TestContainersConfig.class })
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class RedisClientTest extends TestContainersConfig {

    private final RedisClient redisClient;

    private final String key = "testKey";

    private final String value = "testValue";

    private final Duration timeout = Duration.ofSeconds(1);

    @Test
    @DisplayName("値を保存し、正しく取得できる")
    void test1() throws InterruptedException {
        redisClient.setValue(key, value);
        Optional<String> retrievedValue = redisClient.getValue(key, String.class);

        assertThat(retrievedValue).isPresent();
        assertThat(retrievedValue.get()).isEqualTo(value);
    }

    @Test
    @DisplayName("値を有効期限付きで保存し、正しく取得でき、期限切れ後に値が削除される")
    void test2() throws InterruptedException {
        redisClient.setValue(key, value, timeout);

        // 保存直後は値が存在する
        assertThat(redisClient.getValue(key, String.class))
                .isPresent()
                .contains(value);

        // 有効期限が切れるまで待機
        Thread.sleep(1200);

        // 有効期限切れにより値は削除される
        assertThat(redisClient.getValue(key, String.class)).isEmpty();
    }

    @Test
    @DisplayName("値を削除する")
    void test3() {
        // 通常の値設定後の削除
        redisClient.setValue(key, value);
        assertThat(redisClient.deleteValue(key)).isTrue();
        assertThat(redisClient.getValue(key, String.class)).isEmpty();

        // 有効期限付き値設定後の削除
        redisClient.setValue(key, value, timeout);
        assertThat(redisClient.deleteValue(key)).isTrue();
        assertThat(redisClient.getValue(key, String.class)).isEmpty();
    }

    @Test
    @DisplayName("キーの有効期限設定テスト")
    void test4() throws InterruptedException {
        redisClient.setValue(key, value);

        // キーに有効期限を設定する
        assertThat(redisClient.expire(key, timeout)).isTrue();
        // 設定直後はキーが存在する
        assertThat(redisClient.hasKey(key)).isTrue();

        // 有効期限が切れるまで待機
        Thread.sleep(1200);

        // 有効期限切れによりキーが存在しなくなる
        assertThat(redisClient.hasKey(key)).isFalse();
    }

    @Test
    @DisplayName("キーの存在確認")
    void test5() {
        // 初期状態ではキーが存在しない
        assertThat(redisClient.hasKey(key)).isFalse();

        // 値をセットした後はキーが存在する
        redisClient.setValue(key, value);
        assertThat(redisClient.hasKey(key)).isTrue();

        // キーを削除した後は再び存在しない
        redisClient.deleteValue(key);
        assertThat(redisClient.hasKey(key)).isFalse();
    }

    @Test
    @DisplayName("存在しないキーの取得")
    void test6() {
        // 存在しないキーに対してgetValueを呼び出す
        assertThat(redisClient.getValue("nonExistentKey", String.class)).isEmpty();
    }
}
