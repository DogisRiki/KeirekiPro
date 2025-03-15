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

    private static final String KEY = "testKey";

    private static final String VALUE = "testValue";

    private static final Duration TIMEOUT = Duration.ofSeconds(1);

    @Test
    @DisplayName("値を保存し、正しく取得できる")
    void test1() throws InterruptedException {
        redisClient.setValue(KEY, VALUE);
        Optional<String> retrievedValue = redisClient.getValue(KEY, String.class);

        assertThat(retrievedValue).isPresent();
        assertThat(retrievedValue.get()).isEqualTo(VALUE);
    }

    @Test
    @DisplayName("値を有効期限付きで保存し、正しく取得でき、期限切れ後に値が削除される")
    void test2() throws InterruptedException {
        redisClient.setValue(KEY, VALUE, TIMEOUT);

        // 保存直後は値が存在する
        assertThat(redisClient.getValue(KEY, String.class))
                .isPresent()
                .contains(VALUE);

        // 有効期限が切れるまで待機
        Thread.sleep(1200);

        // 有効期限切れにより値は削除される
        assertThat(redisClient.getValue(KEY, String.class)).isEmpty();
    }

    @Test
    @DisplayName("値を削除する")
    void test3() {
        // 通常の値設定後の削除
        redisClient.setValue(KEY, VALUE);
        assertThat(redisClient.deleteValue(KEY)).isTrue();
        assertThat(redisClient.getValue(KEY, String.class)).isEmpty();

        // 有効期限付き値設定後の削除
        redisClient.setValue(KEY, VALUE, TIMEOUT);
        assertThat(redisClient.deleteValue(KEY)).isTrue();
        assertThat(redisClient.getValue(KEY, String.class)).isEmpty();
    }

    @Test
    @DisplayName("キーの有効期限設定テスト")
    void test4() throws InterruptedException {
        redisClient.setValue(KEY, VALUE);

        // キーに有効期限を設定する
        assertThat(redisClient.expire(KEY, TIMEOUT)).isTrue();
        // 設定直後はキーが存在する
        assertThat(redisClient.hasKey(KEY)).isTrue();

        // 有効期限が切れるまで待機
        Thread.sleep(1200);

        // 有効期限切れによりキーが存在しなくなる
        assertThat(redisClient.hasKey(KEY)).isFalse();
    }

    @Test
    @DisplayName("キーの存在確認")
    void test5() {
        // 初期状態ではキーが存在しない
        assertThat(redisClient.hasKey(KEY)).isFalse();

        // 値をセットした後はキーが存在する
        redisClient.setValue(KEY, VALUE);
        assertThat(redisClient.hasKey(KEY)).isTrue();

        // キーを削除した後は再び存在しない
        redisClient.deleteValue(KEY);
        assertThat(redisClient.hasKey(KEY)).isFalse();
    }

    @Test
    @DisplayName("存在しないキーの取得")
    void test6() {
        // 存在しないキーに対してgetValueを呼び出す
        assertThat(redisClient.getValue("nonExistentKey", String.class)).isEmpty();
    }
}
