package com.example.keirekipro.unit.infrastructure.query.resume;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Array;
import java.sql.Connection;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;

import com.example.keirekipro.config.PostgresTestContainerConfig;
import com.example.keirekipro.infrastructure.query.resume.ResumeQueryMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

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

    @Test
    @DisplayName("selectResumeForBackup_全データが存在する場合、バックアップ用JSON文字列が返る")
    void test15() throws Exception {
        final UUID userId = UUID.randomUUID();
        final UUID resumeId = UUID.randomUUID();

        insertUser(userId);
        insertResume(resumeId, userId);

        final UUID careerId = UUID.randomUUID();
        insertCareer(careerId, resumeId);

        final UUID projectId = UUID.randomUUID();
        insertProject(projectId, resumeId);
        insertProjectTechStacks(projectId);

        final UUID certificationId = UUID.randomUUID();
        insertCertification(certificationId, resumeId, "基本情報技術者");

        final UUID snsPlatformId = UUID.randomUUID();
        insertSnsPlatform(snsPlatformId, resumeId, "X", "https://x.example");

        final UUID portfolioId = UUID.randomUUID();
        insertPortfolio(portfolioId, resumeId, "PF1");

        final UUID selfPromotionId = UUID.randomUUID();
        insertSelfPromotion(selfPromotionId, resumeId, "PR1");

        String json = resumeQueryMapper.selectResumeForBackup(resumeId, userId);

        assertThat(json).isNotBlank();

        ObjectMapper objectMapper = new ObjectMapper();
        JsonNode root = objectMapper.readTree(json);

        // resume
        assertThat(root.get("resumeName").asText()).isEqualTo("resume");
        assertThat(root.get("date").asText()).isEqualTo("2025-01-01");
        assertThat(root.get("lastName").asText()).isEqualTo("山田");
        assertThat(root.get("firstName").asText()).isEqualTo("太郎");

        // careers
        JsonNode careers = root.get("careers");
        assertThat(careers.isArray()).isTrue();
        assertThat(careers).hasSize(1);
        assertThat(careers.get(0).get("companyName").asText()).isEqualTo("Company");
        assertThat(careers.get(0).get("startDate").asText()).isEqualTo("2020-01-01");
        assertThat(careers.get(0).get("endDate").isNull()).isTrue();
        assertThat(careers.get(0).get("active").asBoolean()).isTrue();

        // projects
        JsonNode projects = root.get("projects");
        assertThat(projects.isArray()).isTrue();
        assertThat(projects).hasSize(1);

        JsonNode project0 = projects.get(0);
        assertThat(project0.get("companyName").asText()).isEqualTo("Company");
        assertThat(project0.get("startDate").asText()).isEqualTo("2021-01-01");
        assertThat(project0.get("endDate").isNull()).isTrue();
        assertThat(project0.get("active").asBoolean()).isTrue();
        assertThat(project0.get("name").asText()).isEqualTo("Project");
        assertThat(project0.get("overview").asText()).isEqualTo("Overview");
        assertThat(project0.get("teamComp").asText()).isEqualTo("Team");
        assertThat(project0.get("role").asText()).isEqualTo("Role");
        assertThat(project0.get("achievement").asText()).isEqualTo("Achievement");

        JsonNode process = project0.get("process");
        assertThat(process.get("requirements").asBoolean()).isTrue();
        assertThat(process.get("basicDesign").asBoolean()).isTrue();
        assertThat(process.get("detailedDesign").asBoolean()).isTrue();
        assertThat(process.get("implementation").asBoolean()).isTrue();
        assertThat(process.get("integrationTest").asBoolean()).isTrue();
        assertThat(process.get("systemTest").asBoolean()).isTrue();
        assertThat(process.get("maintenance").asBoolean()).isTrue();

        JsonNode techStack = project0.get("techStack");
        // frontend
        JsonNode frontend = techStack.get("frontend");
        assertThat(frontend.get("languages")).hasSize(2);
        assertThat(frontend.get("languages").get(0).asText()).isEqualTo("TypeScript");
        assertThat(frontend.get("languages").get(1).asText()).isEqualTo("JavaScript");
        assertThat(frontend.get("frameworks")).hasSize(1);
        assertThat(frontend.get("frameworks").get(0).asText()).isEqualTo("React");
        assertThat(frontend.get("libraries")).hasSize(1);
        assertThat(frontend.get("libraries").get(0).asText()).isEqualTo("Redux");

        // backend
        JsonNode backend = techStack.get("backend");
        assertThat(backend.get("languages")).hasSize(1);
        assertThat(backend.get("languages").get(0).asText()).isEqualTo("Java");
        assertThat(backend.get("frameworks")).hasSize(1);
        assertThat(backend.get("frameworks").get(0).asText()).isEqualTo("Spring Boot");
        assertThat(backend.get("ormTools")).hasSize(1);
        assertThat(backend.get("ormTools").get(0).asText()).isEqualTo("MyBatis");
        assertThat(backend.get("auth")).hasSize(1);
        assertThat(backend.get("auth").get(0).asText()).isEqualTo("JWT");

        // infrastructure
        JsonNode infra = techStack.get("infrastructure");
        assertThat(infra.get("clouds")).hasSize(1);
        assertThat(infra.get("clouds").get(0).asText()).isEqualTo("AWS");
        assertThat(infra.get("databases")).hasSize(1);
        assertThat(infra.get("databases").get(0).asText()).isEqualTo("PostgreSQL");

        // tools
        JsonNode tools = techStack.get("tools");
        assertThat(tools.get("sourceControls")).hasSize(1);
        assertThat(tools.get("sourceControls").get(0).asText()).isEqualTo("Git");
        assertThat(tools.get("communicationTools")).hasSize(1);
        assertThat(tools.get("communicationTools").get(0).asText()).isEqualTo("Slack");

        // certifications
        JsonNode certifications = root.get("certifications");
        assertThat(certifications.isArray()).isTrue();
        assertThat(certifications).hasSize(1);
        assertThat(certifications.get(0).get("name").asText()).isEqualTo("基本情報技術者");
        assertThat(certifications.get(0).get("date").asText()).isEqualTo("2022-01-01");

        // portfolios
        JsonNode portfolios = root.get("portfolios");
        assertThat(portfolios.isArray()).isTrue();
        assertThat(portfolios).hasSize(1);
        assertThat(portfolios.get(0).get("name").asText()).isEqualTo("PF1");
        assertThat(portfolios.get(0).get("overview").asText()).isEqualTo("overview");
        assertThat(portfolios.get(0).get("techStack").asText()).isEqualTo("tech");
        assertThat(portfolios.get(0).get("link").asText()).isEqualTo("https://portfolio.example");

        // snsPlatforms
        JsonNode snsPlatforms = root.get("snsPlatforms");
        assertThat(snsPlatforms.isArray()).isTrue();
        assertThat(snsPlatforms).hasSize(1);
        assertThat(snsPlatforms.get(0).get("name").asText()).isEqualTo("X");
        assertThat(snsPlatforms.get(0).get("link").asText()).isEqualTo("https://x.example");

        // selfPromotions
        JsonNode selfPromotions = root.get("selfPromotions");
        assertThat(selfPromotions.isArray()).isTrue();
        assertThat(selfPromotions).hasSize(1);
        assertThat(selfPromotions.get(0).get("title").asText()).isEqualTo("PR1");
        assertThat(selfPromotions.get(0).get("content").asText()).isEqualTo("content");
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

    private void insertProjectTechStacks(UUID projectId) {
        String sql = """
                INSERT INTO project_tech_stacks (
                    project_id,
                    frontend_languages, frontend_framework, frontend_libraries, frontend_build_tool,
                    frontend_package_manager, frontend_linters, frontend_formatters, frontend_testing_tools,
                    backend_languages, backend_framework, backend_libraries, backend_build_tool,
                    backend_package_manager, backend_linters, backend_formatters, backend_testing_tools,
                    orm_tools, auth,
                    clouds, operating_system, containers, database, web_server, ci_cd_tool, iac_tools,
                    monitoring_tools, logging_tools,
                    source_control, project_management, communication_tool, documentation_tools,
                    api_development_tools, design_tools, editor, development_environment
                ) VALUES (
                    ?,
                    ?, ?, ?, ?,
                    ?, ?, ?, ?,
                    ?, ?, ?, ?,
                    ?, ?, ?, ?,
                    ?, ?,
                    ?, ?, ?, ?, ?, ?, ?,
                    ?, ?,
                    ?, ?, ?, ?,
                    ?, ?, ?, ?
                )
                """;

        jdbcTemplate.execute((Connection connection) -> {
            Array frontendLanguages = connection.createArrayOf("text", new String[] { "TypeScript", "JavaScript" });
            Array frontendFramework = connection.createArrayOf("text", new String[] { "React" });
            Array frontendLibraries = connection.createArrayOf("text", new String[] { "Redux" });
            Array frontendBuildTool = connection.createArrayOf("text", new String[] { "Vite" });
            Array frontendPackageManager = connection.createArrayOf("text", new String[] { "npm" });
            Array frontendLinters = connection.createArrayOf("text", new String[] { "ESLint" });
            Array frontendFormatters = connection.createArrayOf("text", new String[] { "Prettier" });
            Array frontendTestingTools = connection.createArrayOf("text", new String[] { "Jest" });

            Array backendLanguages = connection.createArrayOf("text", new String[] { "Java" });
            Array backendFramework = connection.createArrayOf("text", new String[] { "Spring Boot" });
            Array backendLibraries = connection.createArrayOf("text", new String[] { "Jackson" });
            Array backendBuildTool = connection.createArrayOf("text", new String[] { "Gradle" });
            Array backendPackageManager = connection.createArrayOf("text", new String[] { "Maven" });
            Array backendLinters = connection.createArrayOf("text", new String[] { "Checkstyle" });
            Array backendFormatters = connection.createArrayOf("text", new String[] { "Spotless" });
            Array backendTestingTools = connection.createArrayOf("text", new String[] { "JUnit" });
            Array ormTools = connection.createArrayOf("text", new String[] { "MyBatis" });
            Array auth = connection.createArrayOf("text", new String[] { "JWT" });

            Array clouds = connection.createArrayOf("text", new String[] { "AWS" });
            Array operatingSystem = connection.createArrayOf("text", new String[] { "Linux" });
            Array containers = connection.createArrayOf("text", new String[] { "Docker" });
            Array database = connection.createArrayOf("text", new String[] { "PostgreSQL" });
            Array webServer = connection.createArrayOf("text", new String[] { "Nginx" });
            Array ciCdTool = connection.createArrayOf("text", new String[] { "GitHub Actions" });
            Array iacTools = connection.createArrayOf("text", new String[] { "Terraform" });
            Array monitoringTools = connection.createArrayOf("text", new String[] { "CloudWatch" });
            Array loggingTools = connection.createArrayOf("text", new String[] { "OpenSearch" });

            Array sourceControl = connection.createArrayOf("text", new String[] { "Git" });
            Array projectManagement = connection.createArrayOf("text", new String[] { "Jira" });
            Array communicationTool = connection.createArrayOf("text", new String[] { "Slack" });
            Array documentationTools = connection.createArrayOf("text", new String[] { "Confluence" });
            Array apiDevelopmentTools = connection.createArrayOf("text", new String[] { "Postman" });
            Array designTools = connection.createArrayOf("text", new String[] { "Figma" });
            Array editor = connection.createArrayOf("text", new String[] { "IntelliJ IDEA" });
            Array developmentEnvironment = connection.createArrayOf("text", new String[] { "Docker Compose" });

            jdbcTemplate.update(
                    sql,
                    projectId,
                    frontendLanguages, frontendFramework, frontendLibraries, frontendBuildTool,
                    frontendPackageManager, frontendLinters, frontendFormatters, frontendTestingTools,
                    backendLanguages, backendFramework, backendLibraries, backendBuildTool,
                    backendPackageManager, backendLinters, backendFormatters, backendTestingTools,
                    ormTools, auth,
                    clouds, operatingSystem, containers, database, webServer, ciCdTool, iacTools,
                    monitoringTools, loggingTools,
                    sourceControl, projectManagement, communicationTool, documentationTools,
                    apiDevelopmentTools, designTools, editor, developmentEnvironment);

            return null;
        });
    }
}
