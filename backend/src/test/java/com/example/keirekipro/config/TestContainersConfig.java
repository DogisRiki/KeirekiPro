package com.example.keirekipro.config;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * TestContainers設定クラス
 */
@Testcontainers
@TestConfiguration
public abstract class TestContainersConfig {

    @SuppressWarnings("resource")
    protected static final GenericContainer<?> redisContainer = new GenericContainer<>("redis:7.4.2-alpine")
            .withExposedPorts(6379);

    static {
        redisContainer.start();
    }

    @DynamicPropertySource
    static void redisProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.redis.host", () -> redisContainer.getHost());
        registry.add("spring.redis.port", () -> redisContainer.getMappedPort(6379));
    }
}
