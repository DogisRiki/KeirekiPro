package com.example.keirekipro.unit.infrastructure.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import io.awspring.cloud.secretsmanager.SecretsManagerPropertySource;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.boot.data.redis.autoconfigure.DataRedisProperties;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.core.env.StandardEnvironment;

import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueResponse;

/**
 * Secrets Manager のシークレットの JSON にある点を含むキーが、同じ名前の設定として読まれることを確かめる
 */
@ExtendWith(MockitoExtension.class)
class SecretsManagerDottedKeyTest {

    @Mock
    private SecretsManagerClient secretsManagerClient;

    @Test
    @DisplayName("点を含むキーが、キャッシュの接続先とユーザー名の設定として読まれる")
    void test1() {
        // テストデータ
        String secretJson = """
                {
                  "redis-host": "keirekipro-cache.example.com",
                  "redis-port": "6379",
                  "redis-password": "dummy-password",
                  "spring.data.redis.cluster.nodes": "keirekipro-cache.example.com:6379",
                  "spring.data.redis.username": "keirekipro-app"
                }
                """;
        when(secretsManagerClient.getSecretValue(any(GetSecretValueRequest.class)))
                .thenReturn(GetSecretValueResponse.builder().name("keirekipro/redis").secretString(secretJson).build());

        // 実行
        SecretsManagerPropertySource propertySource = new SecretsManagerPropertySource("keirekipro/redis",
                secretsManagerClient);
        propertySource.init();
        StandardEnvironment environment = new StandardEnvironment();
        environment.getPropertySources().addFirst(propertySource);
        DataRedisProperties redisProperties = Binder.get(environment)
                .bind("spring.data.redis", DataRedisProperties.class)
                .get();

        // 検証
        assertThat(environment.getProperty("spring.data.redis.cluster.nodes"))
                .isEqualTo("keirekipro-cache.example.com:6379");
        assertThat(environment.getProperty("spring.data.redis.username")).isEqualTo("keirekipro-app");
        assertThat(redisProperties.getCluster().getNodes()).containsExactly("keirekipro-cache.example.com:6379");
        assertThat(redisProperties.getUsername()).isEqualTo("keirekipro-app");
    }
}
