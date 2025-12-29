package com.example.keirekipro.unit.infrastructure.repository.user;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.config.PostgresTestContainerConfig;
import com.example.keirekipro.infrastructure.repository.user.UserDto;
import com.example.keirekipro.infrastructure.repository.user.UserDto.AuthProviderDto;
import com.example.keirekipro.infrastructure.repository.user.UserMapper;

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
class UserMapperTest {

    private final UserMapper userMapper;
    private final JdbcTemplate jdbcTemplate;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PROFILE_IMAGE = "profile/test-user.jpg";
    private static final String PASSWORD = "hashedPassword";

    private static final UUID GOOGLE_AUTH_PROVIDER_ID = UUID.fromString("f47ac10b-58cc-4372-a567-0e02b2c3d479");
    private static final String GOOGLE_PROVIDER_NAME = "google";
    private static final String GOOGLE_PROVIDER_USER_ID = "109876543210987654321";

    private static final UUID GITHUB_AUTH_PROVIDER_ID = UUID.fromString("3f8e7f2e-34a1-4c5b-9d7a-8f6e2c1b0a9f");
    private static final String GITHUB_PROVIDER_NAME = "github";
    private static final String GITHUB_PROVIDER_USER_ID = "482915736";

    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2023, 1, 1, 0, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2023, 1, 2, 0, 0);

    private static final UUID RESUME_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID CAREER_ID = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static final UUID PROJECT_ID = UUID.fromString("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static final UUID CERTIFICATION_ID = UUID.fromString("dddddddd-dddd-dddd-dddd-dddddddddddd");
    private static final UUID PORTFOLIO_ID = UUID.fromString("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
    private static final UUID SNS_PLATFORM_ID = UUID.fromString("ffffffff-ffff-ffff-ffff-ffffffffffff");
    private static final UUID SELF_PROMOTION_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");

    private static final LocalDate RESUME_DATE = LocalDate.of(2023, 1, 1);
    private static final LocalDate CAREER_START_DATE = LocalDate.of(2020, 4, 1);
    private static final LocalDate PROJECT_START_DATE = LocalDate.of(2021, 1, 1);
    private static final LocalDate CERTIFICATION_DATE = LocalDate.of(2022, 6, 1);

    @Test
    @DisplayName("selectById_ユーザーが存在する場合、正しく取得できる")
    void test1() {
        // セットアップ：ユーザーのみ登録（JdbcTemplateで直接INSERT）
        insertUser(
                USER_ID,
                EMAIL,
                PASSWORD,
                USERNAME,
                PROFILE_IMAGE,
                true,
                CREATED_AT,
                UPDATED_AT);

        // テスト実行
        Optional<UserDto> opt = userMapper.selectById(USER_ID);

        // 検証
        assertThat(opt).isPresent();
        UserDto loaded = opt.get();
        assertThat(loaded.getId()).isEqualTo(USER_ID);
        assertThat(loaded.getEmail()).isEqualTo(EMAIL);
        assertThat(loaded.getUsername()).isEqualTo(USERNAME);
        assertThat(loaded.getProfileImage()).isEqualTo(PROFILE_IMAGE);
        assertThat(loaded.isTwoFactorAuthEnabled()).isTrue();
        assertThat(loaded.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(loaded.getUpdatedAt()).isEqualTo(UPDATED_AT);
        assertThat(loaded.getAuthProviders()).isEmpty();
    }

    @Test
    @DisplayName("selectById_ユーザーが存在しない場合、空のOptionalが返る")
    void test2() {
        Optional<UserDto> opt = userMapper.selectById(USER_ID);
        assertThat(opt).isEmpty();
    }

    @Test
    @DisplayName("selectByEmail_ユーザーが存在する場合、正しく取得できる")
    void test3() {
        // セットアップ：ユーザーとgoogleプロバイダーを登録（JdbcTemplateで直接INSERT）
        insertUser(
                USER_ID,
                EMAIL,
                PASSWORD,
                USERNAME,
                PROFILE_IMAGE,
                true,
                CREATED_AT,
                UPDATED_AT);

        AuthProviderDto googleDto = createGoogleAuthProviderDto();
        insertAuthProvider(googleDto);

        // テスト実行
        Optional<UserDto> opt = userMapper.selectByEmail(EMAIL);

        // 検証
        assertThat(opt).isPresent();
        UserDto loaded = opt.get();
        assertThat(loaded.getId()).isEqualTo(USER_ID);
        assertThat(loaded.getEmail()).isEqualTo(EMAIL);
        assertThat(loaded.getUsername()).isEqualTo(USERNAME);
        assertThat(loaded.getProfileImage()).isEqualTo(PROFILE_IMAGE);
        assertThat(loaded.isTwoFactorAuthEnabled()).isTrue();
        assertThat(loaded.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(loaded.getUpdatedAt()).isEqualTo(UPDATED_AT);
        assertThat(loaded.getAuthProviders())
                .hasSize(1)
                .first()
                .satisfies(p -> {
                    assertThat(p.getId()).isEqualTo(GOOGLE_AUTH_PROVIDER_ID);
                    assertThat(p.getProviderName()).isEqualTo(GOOGLE_PROVIDER_NAME);
                    assertThat(p.getProviderUserId()).isEqualTo(GOOGLE_PROVIDER_USER_ID);
                });
    }

    @Test
    @DisplayName("selectByEmail_ユーザーが存在しない場合、空のOptionalが返る")
    void test4() {
        Optional<UserDto> opt = userMapper.selectByEmail(EMAIL);
        assertThat(opt).isEmpty();
    }

    @Test
    @DisplayName("selectByProvider_ユーザーが存在する場合、正しく取得できる")
    void test5() {
        // セットアップ：ユーザーとgoogleプロバイダー+githubプロバイダーを登録（JdbcTemplateで直接INSERT）
        insertUser(
                USER_ID,
                EMAIL,
                PASSWORD,
                USERNAME,
                PROFILE_IMAGE,
                true,
                CREATED_AT,
                UPDATED_AT);

        AuthProviderDto googleDto = createGoogleAuthProviderDto();
        AuthProviderDto githubDto = createGitHubAuthProviderDto();
        insertAuthProvider(googleDto);
        insertAuthProvider(githubDto);

        // テスト実行
        Optional<UserDto> opt1 = userMapper.selectByProvider(
                GOOGLE_PROVIDER_NAME,
                GOOGLE_PROVIDER_USER_ID);
        Optional<UserDto> opt2 = userMapper.selectByProvider(
                GITHUB_PROVIDER_NAME,
                GITHUB_PROVIDER_USER_ID);

        // 検証
        assertThat(opt1).isPresent();
        UserDto loaded1 = opt1.get();
        assertThat(loaded1.getId()).isEqualTo(USER_ID);
        assertThat(loaded1.getEmail()).isEqualTo(EMAIL);
        assertThat(loaded1.getUsername()).isEqualTo(USERNAME);
        assertThat(loaded1.getProfileImage()).isEqualTo(PROFILE_IMAGE);
        assertThat(loaded1.isTwoFactorAuthEnabled()).isTrue();
        assertThat(loaded1.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(loaded1.getUpdatedAt()).isEqualTo(UPDATED_AT);
        assertThat(loaded1.getAuthProviders())
                .hasSize(1)
                .anySatisfy(p -> {
                    assertThat(p.getId()).isEqualTo(GOOGLE_AUTH_PROVIDER_ID);
                    assertThat(p.getProviderName()).isEqualTo(GOOGLE_PROVIDER_NAME);
                    assertThat(p.getProviderUserId()).isEqualTo(GOOGLE_PROVIDER_USER_ID);
                });

        assertThat(opt2).isPresent();
        UserDto loaded2 = opt2.get();
        assertThat(loaded2.getId()).isEqualTo(USER_ID);
        assertThat(loaded2.getEmail()).isEqualTo(EMAIL);
        assertThat(loaded2.getUsername()).isEqualTo(USERNAME);
        assertThat(loaded2.getProfileImage()).isEqualTo(PROFILE_IMAGE);
        assertThat(loaded2.isTwoFactorAuthEnabled()).isTrue();
        assertThat(loaded2.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(loaded2.getUpdatedAt()).isEqualTo(UPDATED_AT);
        assertThat(loaded2.getAuthProviders())
                .hasSize(1)
                .anySatisfy(p -> {
                    assertThat(p.getId()).isEqualTo(GITHUB_AUTH_PROVIDER_ID);
                    assertThat(p.getProviderName()).isEqualTo(GITHUB_PROVIDER_NAME);
                    assertThat(p.getProviderUserId()).isEqualTo(GITHUB_PROVIDER_USER_ID);
                });
    }

    @Test
    @DisplayName("selectByProvider_ユーザーが存在しない場合、空のOptionalが返る")
    void test6() {
        Optional<UserDto> opt = userMapper.selectByProvider(
                GOOGLE_PROVIDER_NAME,
                GOOGLE_PROVIDER_USER_ID);
        assertThat(opt).isEmpty();
    }

    @Test
    @DisplayName("upsert_ユーザー情報を新規登録できる")
    void test7() {
        // 挿入用データ
        UserDto dto = createUserDto();

        // 実行
        userMapper.upsertUser(dto);

        // 検証
        Optional<UserDto> opt = userMapper.selectById(USER_ID);
        assertThat(opt).isPresent();
        UserDto loaded = opt.get();
        assertThat(loaded.getId()).isEqualTo(USER_ID);
        assertThat(loaded.getEmail()).isEqualTo(EMAIL);
        assertThat(loaded.getUsername()).isEqualTo(USERNAME);
        assertThat(loaded.getProfileImage()).isEqualTo(PROFILE_IMAGE);
        assertThat(loaded.isTwoFactorAuthEnabled()).isTrue();
        assertThat(loaded.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(loaded.getUpdatedAt()).isEqualTo(UPDATED_AT);
        assertThat(loaded.getAuthProviders()).isEmpty();
    }

    @Test
    @DisplayName("upsert_既存ユーザーを更新するとユーザー情報が更新される")
    void test8() {
        // 挿入用データ
        UserDto dto = createUserDto();

        // 実行
        userMapper.upsertUser(dto);

        // 更新用DTO
        UserDto updated = createUserDto();
        updated.setEmail(EMAIL + "-upd");
        updated.setPassword(PASSWORD + "-upd");
        updated.setUsername(USERNAME + "-upd");
        updated.setProfileImage(PROFILE_IMAGE + ".upd");
        updated.setTwoFactorAuthEnabled(false);
        updated.setUpdatedAt(LocalDateTime.now());

        // 実行
        userMapper.upsertUser(updated);

        // 検証
        Optional<UserDto> opt = userMapper.selectById(USER_ID);
        assertThat(opt).isPresent();
        UserDto loaded = opt.get();
        assertThat(loaded.getEmail()).isEqualTo(EMAIL + "-upd");
        assertThat(loaded.getPassword()).isEqualTo(PASSWORD + "-upd");
        assertThat(loaded.getUsername()).isEqualTo(USERNAME + "-upd");
        assertThat(loaded.getProfileImage()).isEqualTo(PROFILE_IMAGE + ".upd");
        assertThat(loaded.isTwoFactorAuthEnabled()).isFalse();
        assertThat(loaded.getCreatedAt()).isEqualTo(dto.getCreatedAt());
        assertThat(loaded.getUpdatedAt()).isNotEqualTo(dto.getUpdatedAt());
    }

    @Test
    @DisplayName("delete_ユーザーとプロバイダー情報を削除できる")
    void test9() {
        // セットアップ：ユーザーとgoogleプロバイダー+githubプロバイダーを登録（JdbcTemplateで直接INSERT）
        insertUser(
                USER_ID,
                EMAIL,
                PASSWORD,
                USERNAME,
                PROFILE_IMAGE,
                true,
                CREATED_AT,
                UPDATED_AT);

        AuthProviderDto googleDto = createGoogleAuthProviderDto();
        AuthProviderDto githubDto = createGitHubAuthProviderDto();
        insertAuthProvider(googleDto);
        insertAuthProvider(githubDto);

        // セットアップ：resume関連データも登録（deleteで連鎖削除されることを検証するため）
        insertResumeRelatedData(USER_ID);

        // 事前検証：データが存在する
        assertThat(countByUserId("users", "id", USER_ID)).isEqualTo(1);
        assertThat(countByUserId("user_auth_providers", "user_id", USER_ID)).isEqualTo(2);
        assertThat(countByUserId("resumes", "user_id", USER_ID)).isEqualTo(1);

        assertThat(countByResumeId("careers", "resume_id", RESUME_ID)).isEqualTo(1);
        assertThat(countByResumeId("projects", "resume_id", RESUME_ID)).isEqualTo(1);
        assertThat(countByProjectId("project_tech_stacks", "project_id", PROJECT_ID)).isEqualTo(1);
        assertThat(countByResumeId("certifications", "resume_id", RESUME_ID)).isEqualTo(1);
        assertThat(countByResumeId("portfolios", "resume_id", RESUME_ID)).isEqualTo(1);
        assertThat(countByResumeId("sns_platforms", "resume_id", RESUME_ID)).isEqualTo(1);
        assertThat(countByResumeId("self_promotions", "resume_id", RESUME_ID)).isEqualTo(1);

        // 実行：削除
        userMapper.delete(USER_ID);

        // 検証：ユーザーが存在しない
        assertThat(userMapper.selectById(USER_ID)).isEmpty();

        // 検証：関連データも削除されている
        assertThat(countByUserId("users", "id", USER_ID)).isEqualTo(0);
        assertThat(countByUserId("user_auth_providers", "user_id", USER_ID)).isEqualTo(0);
        assertThat(countByUserId("resumes", "user_id", USER_ID)).isEqualTo(0);

        assertThat(countByResumeId("careers", "resume_id", RESUME_ID)).isEqualTo(0);
        assertThat(countByResumeId("projects", "resume_id", RESUME_ID)).isEqualTo(0);
        assertThat(countByProjectId("project_tech_stacks", "project_id", PROJECT_ID)).isEqualTo(0);
        assertThat(countByResumeId("certifications", "resume_id", RESUME_ID)).isEqualTo(0);
        assertThat(countByResumeId("portfolios", "resume_id", RESUME_ID)).isEqualTo(0);
        assertThat(countByResumeId("sns_platforms", "resume_id", RESUME_ID)).isEqualTo(0);
        assertThat(countByResumeId("self_promotions", "resume_id", RESUME_ID)).isEqualTo(0);
    }

    @Test
    @DisplayName("insertAuthProvider_外部連携認証情報を登録できる")
    void test11() {
        // セットアップ：プロバイダー付きユーザーを登録（JdbcTemplateで直接INSERT）
        insertUser(
                USER_ID,
                EMAIL,
                PASSWORD,
                USERNAME,
                PROFILE_IMAGE,
                true,
                CREATED_AT,
                UPDATED_AT);

        AuthProviderDto googleDto = createGoogleAuthProviderDto();
        insertAuthProvider(googleDto);

        // テスト実行
        Optional<UserDto> opt = userMapper.selectByEmail(EMAIL);

        // 検証
        assertThat(opt).isPresent();
        UserDto loaded = opt.get();
        assertThat(loaded.getId()).isEqualTo(USER_ID);
        assertThat(loaded.getEmail()).isEqualTo(EMAIL);
        assertThat(loaded.getUsername()).isEqualTo(USERNAME);
        assertThat(loaded.getProfileImage()).isEqualTo(PROFILE_IMAGE);
        assertThat(loaded.isTwoFactorAuthEnabled()).isTrue();
        assertThat(loaded.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(loaded.getUpdatedAt()).isEqualTo(UPDATED_AT);
        assertThat(loaded.getAuthProviders())
                .hasSize(1)
                .first()
                .satisfies(p -> {
                    assertThat(p.getId()).isEqualTo(GOOGLE_AUTH_PROVIDER_ID);
                    assertThat(p.getProviderName()).isEqualTo(GOOGLE_PROVIDER_NAME);
                    assertThat(p.getProviderUserId()).isEqualTo(GOOGLE_PROVIDER_USER_ID);
                });
    }

    @Test
    @DisplayName("deleteAuthProvidersByUserId_外部連携認証情報を削除できる")
    void test12() {
        // セットアップ：ユーザーとgoogleプロバイダー+githubプロバイダーを登録（JdbcTemplateで直接INSERT）
        insertUser(
                USER_ID,
                EMAIL,
                PASSWORD,
                USERNAME,
                PROFILE_IMAGE,
                true,
                CREATED_AT,
                UPDATED_AT);

        AuthProviderDto googleDto = createGoogleAuthProviderDto();
        AuthProviderDto githubDto = createGitHubAuthProviderDto();
        insertAuthProvider(googleDto);
        insertAuthProvider(githubDto);

        // テスト実行
        userMapper.deleteAuthProvidersByUserId(USER_ID);

        // 検証：外部連携認証情報が存在しない
        Optional<UserDto> optUser = userMapper.selectById(USER_ID);
        assertThat(optUser).isPresent();
        UserDto loadedUser = optUser.get();
        assertThat(loadedUser.getUpdatedAt()).isEqualTo(UPDATED_AT);
        assertThat(loadedUser.getAuthProviders()).isEmpty();

        // DB直接検証：user_auth_providersが0件
        assertThat(countByUserId("user_auth_providers", "user_id", USER_ID)).isEqualTo(0);
    }

    /**
     * Google用のAuthProviderDtoを作成するヘルパーメソッド
     */
    private AuthProviderDto createGoogleAuthProviderDto() {
        AuthProviderDto dto = new AuthProviderDto();
        dto.setId(GOOGLE_AUTH_PROVIDER_ID);
        dto.setUserId(USER_ID);
        dto.setProviderName(GOOGLE_PROVIDER_NAME);
        dto.setProviderUserId(GOOGLE_PROVIDER_USER_ID);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        return dto;
    }

    /**
     * GitHub用のAuthProviderDtoを作成するヘルパーメソッド
     */
    private AuthProviderDto createGitHubAuthProviderDto() {
        AuthProviderDto dto = new AuthProviderDto();
        dto.setId(GITHUB_AUTH_PROVIDER_ID);
        dto.setUserId(USER_ID);
        dto.setProviderName(GITHUB_PROVIDER_NAME);
        dto.setProviderUserId(GITHUB_PROVIDER_USER_ID);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        return dto;
    }

    /**
     * UserDtoを作成するヘルパーメソッド
     */
    private UserDto createUserDto() {
        UserDto dto = new UserDto();
        dto.setId(USER_ID);
        dto.setEmail(EMAIL);
        dto.setPassword(PASSWORD);
        dto.setUsername(USERNAME);
        dto.setProfileImage(PROFILE_IMAGE);
        dto.setTwoFactorAuthEnabled(true);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        dto.setAuthProviders(Collections.emptyList());
        return dto;
    }

    /**
     * usersにテストデータを挿入するヘルパーメソッド
     */
    private void insertUser(
            UUID id,
            String email,
            String password,
            String username,
            String profileImage,
            boolean twoFactorAuthEnabled,
            LocalDateTime createdAt,
            LocalDateTime updatedAt) {

        String sql = "INSERT INTO users "
                + "(id, email, password, username, profile_image, "
                + "two_factor_auth_enabled, created_at, updated_at) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
        jdbcTemplate.update(
                sql,
                id,
                email,
                password,
                username,
                profileImage,
                twoFactorAuthEnabled,
                createdAt,
                updatedAt);
    }

    /**
     * user_auth_providersにテストデータを挿入するヘルパーメソッド
     */
    private void insertAuthProvider(AuthProviderDto dto) {
        String sql = "INSERT INTO user_auth_providers "
                + "(id, user_id, provider_name, provider_user_id, created_at, updated_at) "
                + "VALUES (?, ?, ?, ?, ?, ?)";
        jdbcTemplate.update(
                sql,
                dto.getId(),
                dto.getUserId(),
                dto.getProviderName(),
                dto.getProviderUserId(),
                dto.getCreatedAt(),
                dto.getUpdatedAt());
    }

    /**
     * resumes配下の関連テーブルにテストデータを挿入するヘルパーメソッド
     */
    private void insertResumeRelatedData(UUID userId) {
        // resumes
        jdbcTemplate.update(
                "INSERT INTO resumes "
                        + "(id, user_id, name, date, last_name, first_name, created_at, updated_at) "
                        + "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                RESUME_ID,
                userId,
                "resume-name",
                RESUME_DATE,
                "last",
                "first",
                CREATED_AT,
                UPDATED_AT);

        // careers
        jdbcTemplate.update(
                "INSERT INTO careers "
                        + "(id, resume_id, company_name, start_date, end_date, is_active) "
                        + "VALUES (?, ?, ?, ?, ?, ?)",
                CAREER_ID,
                RESUME_ID,
                "company-career",
                CAREER_START_DATE,
                null,
                true);

        // projects
        String projectSql = "INSERT INTO projects "
                + "(id, resume_id, company_name, start_date, end_date, is_active, "
                + "name, overview, team_comp, role, achievement, "
                + "requirements, basic_design, detailed_design, implementation, "
                + "integration_test, system_test, maintenance) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        jdbcTemplate.update(
                projectSql,
                PROJECT_ID,
                RESUME_ID,
                "company-project",
                PROJECT_START_DATE,
                null,
                true,
                "project-name",
                "overview",
                "team",
                "role",
                "achievement",
                true,
                true,
                true,
                true,
                false,
                false,
                false);

        // project_tech_stacks（他カラムはNULL許容のためproject_idのみ）
        jdbcTemplate.update(
                "INSERT INTO project_tech_stacks (project_id) VALUES (?)",
                PROJECT_ID);

        // certifications
        jdbcTemplate.update(
                "INSERT INTO certifications (id, resume_id, name, date) VALUES (?, ?, ?, ?)",
                CERTIFICATION_ID,
                RESUME_ID,
                "cert-name",
                CERTIFICATION_DATE);

        // portfolios
        jdbcTemplate.update(
                "INSERT INTO portfolios "
                        + "(id, resume_id, name, overview, tech_stack, link) "
                        + "VALUES (?, ?, ?, ?, ?, ?)",
                PORTFOLIO_ID,
                RESUME_ID,
                "portfolio-name",
                "portfolio-overview",
                "tech-stack",
                "https://example.com");

        // sns_platforms
        jdbcTemplate.update(
                "INSERT INTO sns_platforms (id, resume_id, name, link) VALUES (?, ?, ?, ?)",
                SNS_PLATFORM_ID,
                RESUME_ID,
                "sns-name",
                "https://sns.example.com");

        // self_promotions
        jdbcTemplate.update(
                "INSERT INTO self_promotions (id, resume_id, title, content) VALUES (?, ?, ?, ?)",
                SELF_PROMOTION_ID,
                RESUME_ID,
                "title",
                "content");
    }

    private int countByUserId(String tableName, String columnName, UUID userId) {
        String sql = "SELECT COUNT(*) FROM " + tableName + " WHERE " + columnName + " = ?";
        Integer cnt = jdbcTemplate.queryForObject(sql, Integer.class, userId);
        return cnt == null ? 0 : cnt;
    }

    private int countByResumeId(String tableName, String columnName, UUID resumeId) {
        String sql = "SELECT COUNT(*) FROM " + tableName + " WHERE " + columnName + " = ?";
        Integer cnt = jdbcTemplate.queryForObject(sql, Integer.class, resumeId);
        return cnt == null ? 0 : cnt;
    }

    private int countByProjectId(String tableName, String columnName, UUID projectId) {
        String sql = "SELECT COUNT(*) FROM " + tableName + " WHERE " + columnName + " = ?";
        Integer cnt = jdbcTemplate.queryForObject(sql, Integer.class, projectId);
        return cnt == null ? 0 : cnt;
    }
}
