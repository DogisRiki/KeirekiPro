package com.example.keirekipro.config;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.PostgreSQLContainer;

/**
 * Postgres Testcontainers設定クラス
 */
@TestConfiguration
public class PostgresTestContainerConfig {

    /**
     * Postgresコンテナ
     */
    @Bean
    @ServiceConnection(name = "postgres")
    @SuppressWarnings("resource")
    public PostgreSQLContainer<?> postgresContainer() {
        return new PostgreSQLContainer<>("postgres:17.2-alpine")
                .withDatabaseName("testdb")
                .withUsername("test")
                .withPassword("test")
                .withExposedPorts(5432);
    }
}
