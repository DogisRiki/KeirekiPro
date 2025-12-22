package com.example.keirekipro.unit.infrastructure.query.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Date;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;

import com.example.keirekipro.config.PostgresTestContainerConfig;
import com.example.keirekipro.infrastructure.query.resume.ResumeQueryMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mybatis.spring.boot.test.autoconfigure.MybatisTest;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestPropertySource;

import lombok.RequiredArgsConstructor;

@MybatisTest
@ActiveProfiles("test")
@TestPropertySource(properties = "spring.flyway.target=1")
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Import(PostgresTestContainerConfig.class)
class ResumeQueryMapperTest {

    private final ResumeQueryMapper resumeQueryMapper;
    private final JdbcTemplate jdbcTemplate;

    @Test
    @DisplayName("countResumesByUserId_職務経歴書が存在しない場合、0が返る")
    void test1() {
        UUID userId = UUID.randomUUID();
        insertUser(userId);

        int count = resumeQueryMapper.countResumesByUserId(userId);

        assertThat(count).isZero();
    }

    @Test
    @DisplayName("countResumesByUserId_複数職務経歴書が存在する場合、ユーザーIDで絞り込んだ件数が返る")
    void test2() {
        UUID userId1 = UUID.randomUUID();
        UUID userId2 = UUID.randomUUID();
        insertUser(userId1);
        insertUser(userId2);

        insertResume(UUID.randomUUID(), userId1);
        insertResume(UUID.randomUUID(), userId1);
        insertResume(UUID.randomUUID(), userId1);

        insertResume(UUID.randomUUID(), userId2); // 別ユーザー分

        int count = resumeQueryMapper.countResumesByUserId(userId1);

        assertThat(count).isEqualTo(3);
    }

    @Test
    @DisplayName("countCareersByResumeId_職歴が存在しない場合、0が返る")
    void test3() {
        UUID userId = UUID.randomUUID();
        UUID resumeId = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId, userId);

        int count = resumeQueryMapper.countCareersByResumeId(resumeId);

        assertThat(count).isZero();
    }

    @Test
    @DisplayName("countCareersByResumeId_複数職歴が存在する場合、職務経歴書IDで絞り込んだ件数が返る")
    void test4() {
        UUID userId = UUID.randomUUID();
        UUID resumeId1 = UUID.randomUUID();
        UUID resumeId2 = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId1, userId);
        insertResume(resumeId2, userId);

        insertCareer(UUID.randomUUID(), resumeId1);
        insertCareer(UUID.randomUUID(), resumeId1);

        insertCareer(UUID.randomUUID(), resumeId2); // 別職務経歴書分

        int count = resumeQueryMapper.countCareersByResumeId(resumeId1);

        assertThat(count).isEqualTo(2);
    }

    @Test
    @DisplayName("countProjectsByResumeId_プロジェクトが存在しない場合、0が返る")
    void test5() {
        UUID userId = UUID.randomUUID();
        UUID resumeId = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId, userId);

        int count = resumeQueryMapper.countProjectsByResumeId(resumeId);

        assertThat(count).isZero();
    }

    @Test
    @DisplayName("countProjectsByResumeId_複数プロジェクトが存在する場合、職務経歴書IDで絞り込んだ件数が返る")
    void test6() {
        UUID userId = UUID.randomUUID();
        UUID resumeId1 = UUID.randomUUID();
        UUID resumeId2 = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId1, userId);
        insertResume(resumeId2, userId);

        insertProject(UUID.randomUUID(), resumeId1);
        insertProject(UUID.randomUUID(), resumeId1);
        insertProject(UUID.randomUUID(), resumeId1);

        insertProject(UUID.randomUUID(), resumeId2); // 別職務経歴書分

        int count = resumeQueryMapper.countProjectsByResumeId(resumeId1);

        assertThat(count).isEqualTo(3);
    }

    @Test
    @DisplayName("countCertificationsByResumeId_資格が存在しない場合、0が返る")
    void test7() {
        UUID userId = UUID.randomUUID();
        UUID resumeId = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId, userId);

        int count = resumeQueryMapper.countCertificationsByResumeId(resumeId);

        assertThat(count).isZero();
    }

    @Test
    @DisplayName("countCertificationsByResumeId_複数資格が存在する場合、職務経歴書IDで絞り込んだ件数が返る")
    void test8() {
        UUID userId = UUID.randomUUID();
        UUID resumeId1 = UUID.randomUUID();
        UUID resumeId2 = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId1, userId);
        insertResume(resumeId2, userId);

        insertCertification(UUID.randomUUID(), resumeId1, "基本情報技術者");
        insertCertification(UUID.randomUUID(), resumeId1, "応用情報技術者");

        insertCertification(UUID.randomUUID(), resumeId2, "AWS SAA"); // 別職務経歴書分

        int count = resumeQueryMapper.countCertificationsByResumeId(resumeId1);

        assertThat(count).isEqualTo(2);
    }

    @Test
    @DisplayName("countSnsPlatformsByResumeId_SNSプラットフォームが存在しない場合、0が返る")
    void test9() {
        UUID userId = UUID.randomUUID();
        UUID resumeId = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId, userId);

        int count = resumeQueryMapper.countSnsPlatformsByResumeId(resumeId);

        assertThat(count).isZero();
    }

    @Test
    @DisplayName("countSnsPlatformsByResumeId_複数SNSプラットフォームが存在する場合、職務経歴書IDで絞り込んだ件数が返る")
    void test10() {
        UUID userId = UUID.randomUUID();
        UUID resumeId1 = UUID.randomUUID();
        UUID resumeId2 = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId1, userId);
        insertResume(resumeId2, userId);

        insertSnsPlatform(UUID.randomUUID(), resumeId1, "X", "https://x.example");
        insertSnsPlatform(UUID.randomUUID(), resumeId1, "Instagram", "https://instagram.example");
        insertSnsPlatform(UUID.randomUUID(), resumeId1, "YouTube", "https://youtube.example");

        insertSnsPlatform(UUID.randomUUID(), resumeId2, "X", "https://x2.example"); // 別職務経歴書分

        int count = resumeQueryMapper.countSnsPlatformsByResumeId(resumeId1);

        assertThat(count).isEqualTo(3);
    }

    @Test
    @DisplayName("countPortfoliosByResumeId_ポートフォリオが存在しない場合、0が返る")
    void test11() {
        UUID userId = UUID.randomUUID();
        UUID resumeId = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId, userId);

        int count = resumeQueryMapper.countPortfoliosByResumeId(resumeId);

        assertThat(count).isZero();
    }

    @Test
    @DisplayName("countPortfoliosByResumeId_複数ポートフォリオが存在する場合、職務経歴書IDで絞り込んだ件数が返る")
    void test12() {
        UUID userId = UUID.randomUUID();
        UUID resumeId1 = UUID.randomUUID();
        UUID resumeId2 = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId1, userId);
        insertResume(resumeId2, userId);

        insertPortfolio(UUID.randomUUID(), resumeId1, "PF1");
        insertPortfolio(UUID.randomUUID(), resumeId1, "PF2");

        insertPortfolio(UUID.randomUUID(), resumeId2, "PF3"); // 別職務経歴書分

        int count = resumeQueryMapper.countPortfoliosByResumeId(resumeId1);

        assertThat(count).isEqualTo(2);
    }

    @Test
    @DisplayName("countSelfPromotionsByResumeId_自己PRが存在しない場合、0が返る")
    void test13() {
        UUID userId = UUID.randomUUID();
        UUID resumeId = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId, userId);

        int count = resumeQueryMapper.countSelfPromotionsByResumeId(resumeId);

        assertThat(count).isZero();
    }

    @Test
    @DisplayName("countSelfPromotionsByResumeId_複数自己PRが存在する場合、職務経歴書IDで絞り込んだ件数が返る")
    void test14() {
        UUID userId = UUID.randomUUID();
        UUID resumeId1 = UUID.randomUUID();
        UUID resumeId2 = UUID.randomUUID();
        insertUser(userId);
        insertResume(resumeId1, userId);
        insertResume(resumeId2, userId);

        insertSelfPromotion(UUID.randomUUID(), resumeId1, "PR1");
        insertSelfPromotion(UUID.randomUUID(), resumeId1, "PR2");
        insertSelfPromotion(UUID.randomUUID(), resumeId1, "PR3");

        insertSelfPromotion(UUID.randomUUID(), resumeId2, "PR4"); // 別職務経歴書分

        int count = resumeQueryMapper.countSelfPromotionsByResumeId(resumeId1);

        assertThat(count).isEqualTo(3);
    }

    private void insertUser(UUID userId) {
        Timestamp now = Timestamp.from(Instant.now());

        String sql = """
                INSERT INTO users (
                    id, email, password, username, profile_image,
                    two_factor_auth_enabled, created_at, updated_at
                ) VALUES (
                    ?, ?, ?, ?, ?,
                    ?, ?, ?
                )
                """;

        jdbcTemplate.update(
                sql,
                userId,
                "test-" + userId + "@example.com",
                "password",
                "username",
                null,
                false,
                now,
                now);
    }

    private void insertResume(UUID resumeId, UUID userId) {
        Timestamp now = Timestamp.from(Instant.now());

        String sql = """
                INSERT INTO resumes (
                    id, user_id, name, date, last_name, first_name, created_at, updated_at
                ) VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?
                )
                """;

        jdbcTemplate.update(
                sql,
                resumeId,
                userId,
                "resume",
                Date.valueOf("2025-01-01"),
                "山田",
                "太郎",
                now,
                now);
    }

    private void insertCareer(UUID careerId, UUID resumeId) {
        String sql = """
                INSERT INTO careers (
                    id, resume_id, company_name, start_date, end_date, is_active
                ) VALUES (
                    ?, ?, ?, ?, ?, ?
                )
                """;

        jdbcTemplate.update(
                sql,
                careerId,
                resumeId,
                "Company",
                Date.valueOf("2020-01-01"),
                null,
                true);
    }

    private void insertProject(UUID projectId, UUID resumeId) {
        String sql = """
                INSERT INTO projects (
                    id, resume_id, company_name, start_date, end_date, is_active,
                    name, overview, team_comp, role, achievement,
                    requirements, basic_design, detailed_design,
                    implementation, integration_test, system_test, maintenance
                ) VALUES (
                    ?, ?, ?, ?, ?, ?,
                    ?, ?, ?, ?, ?,
                    ?, ?, ?,
                    ?, ?, ?, ?
                )
                """;

        jdbcTemplate.update(
                sql,
                projectId,
                resumeId,
                "Company",
                Date.valueOf("2021-01-01"),
                null,
                true,
                "Project",
                "Overview",
                "Team",
                "Role",
                "Achievement",
                true,
                true,
                true,
                true,
                true,
                true,
                true);
    }

    private void insertCertification(UUID certificationId, UUID resumeId, String name) {
        jdbcTemplate.update(
                "INSERT INTO certifications (id, resume_id, name, date) VALUES (?, ?, ?, ?)",
                certificationId,
                resumeId,
                name,
                Date.valueOf("2022-01-01"));
    }

    private void insertSnsPlatform(UUID snsPlatformId, UUID resumeId, String name, String link) {
        jdbcTemplate.update(
                "INSERT INTO sns_platforms (id, resume_id, name, link) VALUES (?, ?, ?, ?)",
                snsPlatformId,
                resumeId,
                name,
                link);
    }

    private void insertPortfolio(UUID portfolioId, UUID resumeId, String name) {
        jdbcTemplate.update(
                "INSERT INTO portfolios (id, resume_id, name, overview, tech_stack, link) VALUES (?, ?, ?, ?, ?, ?)",
                portfolioId,
                resumeId,
                name,
                "overview",
                "tech",
                "https://portfolio.example");
    }

    private void insertSelfPromotion(UUID selfPromotionId, UUID resumeId, String title) {
        jdbcTemplate.update(
                "INSERT INTO self_promotions (id, resume_id, title, content) VALUES (?, ?, ?, ?)",
                selfPromotionId,
                resumeId,
                title,
                "content");
    }
}
