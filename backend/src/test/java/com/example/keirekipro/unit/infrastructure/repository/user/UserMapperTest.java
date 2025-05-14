package com.example.keirekipro.unit.infrastructure.repository.user;

import static org.assertj.core.api.Assertions.assertThat;

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

    @Test
    @DisplayName("selectById_ユーザーが存在する場合、正しく取得できる")
    void test1() {
        // セットアップ：ユーザーのみ登録
        UserDto dto = createUserDto();
        userMapper.upsertUser(dto);

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
        // セットアップ：ユーザーとgoogleプロバイダーを登録
        UserDto userDto = createUserDto();
        AuthProviderDto apDto = createGoogleAuthProviderDto();
        userMapper.upsertUser(userDto);
        userMapper.insertAuthProvider(apDto);

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
        // セットアップ：ユーザーとgoogleプロバイダー+githubプロバイダーを登録
        UserDto userDto = createUserDto();
        AuthProviderDto googleDto = createGoogleAuthProviderDto();
        AuthProviderDto githubDto = createGitHubAuthProviderDto();
        userMapper.upsertUser(userDto);
        userMapper.insertAuthProvider(googleDto);
        userMapper.insertAuthProvider(githubDto);

        // テスト実行
        Optional<UserDto> opt1 = userMapper.selectByProvider(GOOGLE_PROVIDER_NAME,
                GOOGLE_PROVIDER_USER_ID);
        Optional<UserDto> opt2 = userMapper.selectByProvider(GITHUB_PROVIDER_NAME,
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
        Optional<UserDto> opt = userMapper.selectByProvider(GOOGLE_PROVIDER_NAME, GOOGLE_PROVIDER_USER_ID);
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
        // セットアップ：ユーザーとgoogleプロバイダー+githubプロバイダーを登録
        UserDto userDto = createUserDto();
        AuthProviderDto googleDto = createGoogleAuthProviderDto();
        AuthProviderDto githubDto = createGitHubAuthProviderDto();
        userMapper.upsertUser(userDto);
        userMapper.insertAuthProvider(googleDto);
        userMapper.insertAuthProvider(githubDto);

        // 実行：削除
        userMapper.delete(USER_ID);

        // 検証
        assertThat(userMapper.selectById(USER_ID)).isEmpty();
    }

    @Test
    @DisplayName("insertAuthProvider_外部連携認証情報を登録できる")
    void test11() {
        // セットアップ：プロバイダー付きユーザーを登録
        UserDto userDto = createUserDto();
        AuthProviderDto apDto = createGoogleAuthProviderDto();
        userMapper.upsertUser(userDto);
        userMapper.insertAuthProvider(apDto);

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
    @DisplayName("deleteAuthProviderByName_プロバイダー名で外部連携認証情報を削除できる")
    void test12() {
        // セットアップ：ユーザーとgoogleプロバイダー+githubプロバイダーを登録
        UserDto userDto = createUserDto();
        AuthProviderDto googleDto = createGoogleAuthProviderDto();
        AuthProviderDto githubDto = createGitHubAuthProviderDto();
        userMapper.upsertUser(userDto);
        userMapper.insertAuthProvider(googleDto);
        userMapper.insertAuthProvider(githubDto);

        // テスト実行(1回目)
        userMapper.deleteAuthProviderByName(USER_ID, GOOGLE_PROVIDER_NAME);

        // 検証
        Optional<UserDto> opt1 = userMapper.selectById(USER_ID);
        assertThat(opt1).isPresent();
        UserDto loaded1 = opt1.get();
        assertThat(loaded1.getUpdatedAt()).isEqualTo(UPDATED_AT);
        assertThat(loaded1.getAuthProviders())
                .hasSize(1);

        // テスト実行(2回目)
        userMapper.deleteAuthProviderByName(USER_ID, GITHUB_PROVIDER_NAME);

        // 検証
        Optional<UserDto> opt2 = userMapper.selectById(USER_ID);
        assertThat(opt2).isPresent();
        UserDto loaded2 = opt2.get();
        assertThat(loaded2.getAuthProviders()).hasSize(0);
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
}
