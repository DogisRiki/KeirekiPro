package com.example.keirekipro.unit.infrastructure.migration;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Connection;
import java.sql.Date;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@Testcontainers
class EmailVerificationColumnsMigrationTest {

    // マイグレーションは戻せないため、テストごとに新しいデータベースを使う
    @Container
    private final PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:17.7-alpine")
            .withDatabaseName("testdb")
            .withUsername("test")
            .withPassword("test");

    private static final UUID USER_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID RESUME_ID = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    private static final String EMAIL = "existing@example.com";
    private static final String PASSWORD_HASH = "$2a$10$hashedpassword";

    private static final LocalDateTime NOW = LocalDateTime.of(2025, 1, 1, 0, 0);

    @Test
    @DisplayName("V6 の時点で入れたアカウントの email_verified_at が V7 のあとに NULL になる")
    void test1() throws SQLException {
        migrateTo("6");

        try (Connection conn = connect()) {
            insertRows(conn);
        }

        migrateTo("7");

        try (Connection conn = connect();
                PreparedStatement ps = conn.prepareStatement(
                        "SELECT email_verified_at, pending_email FROM users WHERE id = ?")) {
            ps.setObject(1, USER_ID);
            try (ResultSet rs = ps.executeQuery()) {
                assertThat(rs.next()).isTrue();
                assertThat(rs.getTimestamp("email_verified_at")).isNull();
                assertThat(rs.getString("pending_email")).isNull();
            }
        }
    }

    @Test
    @DisplayName("V6 の時点で入れたアカウントと職務経歴書の行が V7 のあとも残る")
    void test2() throws SQLException {
        migrateTo("6");

        try (Connection conn = connect()) {
            insertRows(conn);
        }

        migrateTo("7");

        try (Connection conn = connect()) {
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT email, password, username FROM users WHERE id = ?")) {
                ps.setObject(1, USER_ID);
                try (ResultSet rs = ps.executeQuery()) {
                    assertThat(rs.next()).isTrue();
                    assertThat(rs.getString("email")).isEqualTo(EMAIL);
                    assertThat(rs.getString("password")).isEqualTo(PASSWORD_HASH);
                    assertThat(rs.getString("username")).isEqualTo("既存ユーザー");
                }
            }

            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT user_id, name FROM resumes WHERE id = ?")) {
                ps.setObject(1, RESUME_ID);
                try (ResultSet rs = ps.executeQuery()) {
                    assertThat(rs.next()).isTrue();
                    assertThat(rs.getObject("user_id", UUID.class)).isEqualTo(USER_ID);
                    assertThat(rs.getString("name")).isEqualTo("職務経歴書");
                }
            }
        }
    }

    private void migrateTo(String version) {
        Flyway.configure()
                .dataSource(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword())
                .locations("classpath:db/migration")
                .target(version)
                .load()
                .migrate();
    }

    private Connection connect() throws SQLException {
        return DriverManager.getConnection(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword());
    }

    private static void insertRows(Connection conn) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO users (id, email, password, username, created_at, updated_at)"
                        + " VALUES (?, ?, ?, ?, ?, ?)")) {
            ps.setObject(1, USER_ID);
            ps.setString(2, EMAIL);
            ps.setString(3, PASSWORD_HASH);
            ps.setString(4, "既存ユーザー");
            ps.setTimestamp(5, Timestamp.valueOf(NOW));
            ps.setTimestamp(6, Timestamp.valueOf(NOW));
            ps.executeUpdate();
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO resumes (id, user_id, name, date, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)")) {
            ps.setObject(1, RESUME_ID);
            ps.setObject(2, USER_ID);
            ps.setString(3, "職務経歴書");
            ps.setDate(4, Date.valueOf(LocalDate.of(2025, 1, 1)));
            ps.setTimestamp(5, Timestamp.valueOf(NOW));
            ps.setTimestamp(6, Timestamp.valueOf(NOW));
            ps.executeUpdate();
        }
    }
}
