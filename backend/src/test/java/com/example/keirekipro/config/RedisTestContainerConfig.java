package com.example.keirekipro.config;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * Redis Testcontainers設定クラス
 */
@TestConfiguration
public class RedisTestContainerConfig {

    /**
     * Redisコンテナ(本番のElastiCacheと同じValkey 8.0を使う)
     */
    @Bean
    @ServiceConnection(name = "redis")
    @SuppressWarnings("resource")
    public GenericContainer<?> redisContainer() {
        return new GenericContainer<>(
                DockerImageName.parse("valkey/valkey:8.0.11-alpine"))
                .withExposedPorts(6379);
    }
}
