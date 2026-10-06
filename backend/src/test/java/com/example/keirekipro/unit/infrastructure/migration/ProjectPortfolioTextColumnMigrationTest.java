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
class ProjectPortfolioTextColumnMigrationTest {

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:17.7-alpine")
            .withDatabaseName("testdb")
            .withUsername("test")
            .withPassword("test");

    private static final UUID USER_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID RESUME_ID = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static final UUID PROJECT_ID = UUID.fromString("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static final UUID PORTFOLIO_ID = UUID.fromString("dddddddd-dddd-dddd-dddd-dddddddddddd");

    private static final LocalDateTime NOW = LocalDateTime.of(2025, 1, 1, 0, 0);

    // 日本語と英数字を混ぜた255文字の文章(列ごとに中身を変え、取り違えも見つける)
    private static final String PROJECT_OVERVIEW = text255("概要Overview01");
    private static final String PROJECT_ROLE = text255("役割Role02");
    private static final String PORTFOLIO_OVERVIEW = text255("ポートフォリオ概要Portfolio03");

    @Test
    @DisplayName("V5 の時点で入れた文章が V6 のあとも変わらず、3つの列が text になる")
    void test1() throws SQLException {
        migrateTo("5");

        try (Connection conn = connect()) {
            insertRows(conn);
        }

        migrateTo("6");

        try (Connection conn = connect()) {
            assertThat(selectText(conn, "SELECT overview FROM projects WHERE id = ?", PROJECT_ID))
                    .isEqualTo(PROJECT_OVERVIEW);
            assertThat(selectText(conn, "SELECT role FROM projects WHERE id = ?", PROJECT_ID))
                    .isEqualTo(PROJECT_ROLE);
            assertThat(selectText(conn, "SELECT overview FROM portfolios WHERE id = ?", PORTFOLIO_ID))
                    .isEqualTo(PORTFOLIO_OVERVIEW);

            assertThat(dataType(conn, "projects", "overview")).isEqualTo("text");
            assertThat(dataType(conn, "projects", "role")).isEqualTo("text");
            assertThat(dataType(conn, "portfolios", "overview")).isEqualTo("text");
        }
    }

    private static String text255(String unit) {
        String text = unit.repeat(255 / unit.length() + 1).substring(0, 255);
        assertThat(text).hasSize(255);
        return text;
    }

    private static void migrateTo(String version) {
        Flyway.configure()
                .dataSource(POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword())
                .locations("classpath:db/migration")
                .target(version)
                .load()
                .migrate();
    }

    private static Connection connect() throws SQLException {
        return DriverManager.getConnection(POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword());
    }

    private static void insertRows(Connection conn) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO users (id, created_at, updated_at) VALUES (?, ?, ?)")) {
            ps.setObject(1, USER_ID);
            ps.setTimestamp(2, Timestamp.valueOf(NOW));
            ps.setTimestamp(3, Timestamp.valueOf(NOW));
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

        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO projects (id, resume_id, company_name, start_date, is_active, name, overview,"
                        + " team_comp, role, achievement, requirements, basic_design, detailed_design,"
                        + " implementation, integration_test, system_test, maintenance)"
                        + " VALUES (?, ?, ?, ?, TRUE, ?, ?, ?, ?, ?, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE)")) {
            ps.setObject(1, PROJECT_ID);
            ps.setObject(2, RESUME_ID);
            ps.setString(3, "株式会社テスト");
            ps.setDate(4, Date.valueOf(LocalDate.of(2024, 4, 1)));
            ps.setString(5, "プロジェクト");
            ps.setString(6, PROJECT_OVERVIEW);
            ps.setString(7, "5名");
            ps.setString(8, PROJECT_ROLE);
            ps.setString(9, "成果");
            ps.executeUpdate();
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO portfolios (id, resume_id, name, overview, link) VALUES (?, ?, ?, ?, ?)")) {
            ps.setObject(1, PORTFOLIO_ID);
            ps.setObject(2, RESUME_ID);
            ps.setString(3, "ポートフォリオ");
            ps.setString(4, PORTFOLIO_OVERVIEW);
            ps.setString(5, "https://example.com");
            ps.executeUpdate();
        }
    }

    private static String selectText(Connection conn, String sql, UUID id) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setObject(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                assertThat(rs.next()).isTrue();
                return rs.getString(1);
            }
        }
    }

    private static String dataType(Connection conn, String table, String column) throws SQLException {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT data_type FROM information_schema.columns WHERE table_name = ? AND column_name = ?")) {
            ps.setString(1, table);
            ps.setString(2, column);
            try (ResultSet rs = ps.executeQuery()) {
                assertThat(rs.next()).isTrue();
                return rs.getString(1);
            }
        }
    }
}
