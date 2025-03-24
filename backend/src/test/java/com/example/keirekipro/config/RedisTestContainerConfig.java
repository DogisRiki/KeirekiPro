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
     * Redisコンテナ
     */
    @Bean
    @ServiceConnection(name = "redis")
    @SuppressWarnings("resource")
    public GenericContainer<?> redisContainer() {
        return new GenericContainer<>(
                DockerImageName.parse("redis:7.4.2-alpine"))
                .withExposedPorts(6379);
    }
}
