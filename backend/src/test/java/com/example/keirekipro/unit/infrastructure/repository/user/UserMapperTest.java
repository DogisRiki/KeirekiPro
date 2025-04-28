package com.example.keirekipro.unit.infrastructure.repository.user;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
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

    private static final UUID USERID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PROFILE_IMAGE = "profile/test-user.jpg";
    private static final String PASSWORD = "hashedPassword";
    private static final UUID AUTH_PROVIDER_ID = UUID.fromString("f47ac10b-58cc-4372-a567-0e02b2c3d479");
    private static final String PROVIDER_NAME = "google";
    private static final String PROVIDER_USER_ID = "109876543210987654321";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2023, 1, 1, 0, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2023, 1, 2, 0, 0);

    @Test
    @DisplayName("selectById_ユーザーが存在する場合、正しく取得できる")
    void test1() {
        // セットアップ：ユーザーと外部認証プロバイダーを登録
        UserDto dto = new UserDto();
        dto.setId(USERID);
        dto.setEmail(EMAIL);
        dto.setPassword(PASSWORD);
        dto.setUsername(USERNAME);
        dto.setProfileImage(PROFILE_IMAGE);
        dto.setTwoFactorAuthEnabled(false);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        AuthProviderDto ap = new AuthProviderDto();
        ap.setId(AUTH_PROVIDER_ID);
        ap.setProviderName(PROVIDER_NAME);
        ap.setProviderUserId(PROVIDER_USER_ID);
        ap.setCreatedAt(CREATED_AT);
        ap.setUpdatedAt(UPDATED_AT);
        dto.setAuthProviders(List.of(ap));
        userMapper.upsert(dto);

        // テスト実行
        Optional<UserDto> opt = userMapper.selectById(USERID);

        // 検証
        assertThat(opt).isPresent();
        UserDto loaded = opt.get();
        assertThat(loaded.getId()).isEqualTo(USERID);
        assertThat(loaded.getEmail()).isEqualTo(EMAIL);
        assertThat(loaded.getUsername()).isEqualTo(USERNAME);
        assertThat(loaded.getProfileImage()).isEqualTo(PROFILE_IMAGE);
        assertThat(loaded.isTwoFactorAuthEnabled()).isFalse();
        assertThat(loaded.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(loaded.getUpdatedAt()).isEqualTo(UPDATED_AT);
        assertThat(loaded.getAuthProviders())
                .hasSize(1)
                .first()
                .satisfies(p -> {
                    assertThat(p.getId()).isEqualTo(AUTH_PROVIDER_ID);
                    assertThat(p.getProviderName()).isEqualTo(PROVIDER_NAME);
                    assertThat(p.getProviderUserId()).isEqualTo(PROVIDER_USER_ID);
                });
    }

    @Test
    @DisplayName("selectById_ユーザーが存在しない場合、空のOptionalが返る")
    void test2() {
        Optional<UserDto> opt = userMapper.selectById(USERID);
        assertThat(opt).isEmpty();
    }

    @Test
    @DisplayName("selectByEmail_ユーザーが存在する場合、正しく取得できる")
    void test3() {
        // セットアップ：ユーザーを登録（プロバイダーなし）
        UserDto dto = new UserDto();
        dto.setId(USERID);
        dto.setEmail(EMAIL);
        dto.setPassword(PASSWORD);
        dto.setUsername(USERNAME);
        dto.setProfileImage(PROFILE_IMAGE);
        dto.setTwoFactorAuthEnabled(true);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        dto.setAuthProviders(Collections.emptyList());
        userMapper.upsert(dto);

        // テスト実行
        Optional<UserDto> opt = userMapper.selectByEmail(EMAIL);

        // 検証
        assertThat(opt).isPresent();
        UserDto loaded = opt.get();
        assertThat(loaded.getEmail()).isEqualTo(EMAIL);
        assertThat(loaded.getUsername()).isEqualTo(USERNAME);
        assertThat(loaded.isTwoFactorAuthEnabled()).isTrue();
        assertThat(loaded.getAuthProviders()).isEmpty();
    }

    @Test
    @DisplayName("selectByEmail_ユーザーが存在しない場合、空のOptionalが返る")
    void test4() {
        Optional<UserDto> opt = userMapper.selectByEmail(EMAIL);
        assertThat(opt).isEmpty();
    }

    @Test
    @DisplayName("selectById_プロバイダーなしの場合、authProvidersは空のリストになる")
    void test5() {
        // セットアップ：プロバイダーなしユーザー登録
        UserDto dto = new UserDto();
        dto.setId(USERID);
        dto.setEmail(EMAIL);
        dto.setPassword(PASSWORD);
        dto.setUsername(USERNAME);
        dto.setProfileImage(PROFILE_IMAGE);
        dto.setTwoFactorAuthEnabled(false);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        dto.setAuthProviders(Collections.emptyList());
        userMapper.upsert(dto);

        // テスト実行
        UserDto loaded = userMapper.selectById(USERID).orElseThrow();
        assertThat(loaded.getAuthProviders()).isEmpty();
    }

    @Test
    @DisplayName("selectByEmail_プロバイダーなしの場合、authProvidersは空のリストになる")
    void test6() {
        // セットアップ：プロバイダーなしユーザー登録
        UserDto dto = new UserDto();
        dto.setId(USERID);
        dto.setEmail(EMAIL);
        dto.setPassword(PASSWORD);
        dto.setUsername(USERNAME);
        dto.setProfileImage(PROFILE_IMAGE);
        dto.setTwoFactorAuthEnabled(false);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        dto.setAuthProviders(Collections.emptyList());
        userMapper.upsert(dto);

        // テスト実行
        UserDto loaded = userMapper.selectByEmail(EMAIL).orElseThrow();
        assertThat(loaded.getAuthProviders()).isEmpty();
    }

    @Test
    @DisplayName("upsert_新規作成時にusersとuser_auth_providersにレコードが登録される")
    void test7() {
        // セットアップなし（空DB）
        UserDto dto = new UserDto();
        dto.setId(USERID);
        dto.setEmail(EMAIL);
        dto.setPassword(PASSWORD);
        dto.setUsername(USERNAME);
        dto.setProfileImage(PROFILE_IMAGE);
        dto.setTwoFactorAuthEnabled(true);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        AuthProviderDto ap = new AuthProviderDto();
        ap.setId(AUTH_PROVIDER_ID);
        ap.setProviderName(PROVIDER_NAME);
        ap.setProviderUserId(PROVIDER_USER_ID);
        ap.setCreatedAt(CREATED_AT);
        ap.setUpdatedAt(UPDATED_AT);
        dto.setAuthProviders(List.of(ap));

        // 実行
        userMapper.upsert(dto);

        // 検証
        UserDto loaded = userMapper.selectById(USERID).orElseThrow();
        assertThat(loaded.getUsername()).isEqualTo(USERNAME);
        assertThat(loaded.getAuthProviders()).hasSize(1);
    }

    @Test
    @DisplayName("upsert_既存ユーザーを更新するとユーザー情報が更新される")
    void test8() {
        // セットアップ：初回登録
        UserDto dto = new UserDto();
        dto.setId(USERID);
        dto.setEmail(EMAIL);
        dto.setPassword(PASSWORD);
        dto.setUsername(USERNAME);
        dto.setProfileImage(PROFILE_IMAGE);
        dto.setTwoFactorAuthEnabled(false);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        dto.setAuthProviders(Collections.emptyList());
        userMapper.upsert(dto);

        // 更新用DTO
        UserDto updated = new UserDto();
        updated.setId(USERID);
        updated.setEmail(EMAIL);
        updated.setPassword(PASSWORD);
        updated.setUsername(USERNAME + "-upd");
        updated.setProfileImage(PROFILE_IMAGE + ".upd");
        updated.setTwoFactorAuthEnabled(true);
        updated.setCreatedAt(CREATED_AT);
        updated.setUpdatedAt(UPDATED_AT.plusDays(1));
        updated.setAuthProviders(Collections.emptyList());

        // 実行
        userMapper.upsert(updated);

        // 検証
        UserDto loaded = userMapper.selectById(USERID).orElseThrow();
        assertThat(loaded.getUsername()).isEqualTo(USERNAME + "-upd");
        assertThat(loaded.getProfileImage()).endsWith(".upd");
        assertThat(loaded.isTwoFactorAuthEnabled()).isTrue();
    }

    @Test
    @DisplayName("upsert_プロバイダーリストを空にすると関連情報が削除される")
    void test9() {
        // セットアップ：プロバイダーありで初回登録
        UserDto dto = new UserDto();
        dto.setId(USERID);
        dto.setEmail(EMAIL);
        dto.setPassword(PASSWORD);
        dto.setUsername(USERNAME);
        dto.setProfileImage(PROFILE_IMAGE);
        dto.setTwoFactorAuthEnabled(false);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        AuthProviderDto ap = new AuthProviderDto();
        ap.setId(AUTH_PROVIDER_ID);
        ap.setProviderName(PROVIDER_NAME);
        ap.setProviderUserId(PROVIDER_USER_ID);
        ap.setCreatedAt(CREATED_AT);
        ap.setUpdatedAt(UPDATED_AT);
        dto.setAuthProviders(List.of(ap));
        userMapper.upsert(dto);

        // プロバイダーを空にして再登録
        dto.setAuthProviders(Collections.emptyList());
        userMapper.upsert(dto);

        // 検証
        UserDto loaded = userMapper.selectById(USERID).orElseThrow();
        assertThat(loaded.getAuthProviders()).isEmpty();
    }

    @Test
    @DisplayName("delete_ユーザーとプロバイダー情報を削除できる")
    void test10() {
        // セットアップ：プロバイダーありで登録
        UserDto dto = new UserDto();
        dto.setId(USERID);
        dto.setEmail(EMAIL);
        dto.setPassword(PASSWORD);
        dto.setUsername(USERNAME);
        dto.setProfileImage(PROFILE_IMAGE);
        dto.setTwoFactorAuthEnabled(true);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        AuthProviderDto ap = new AuthProviderDto();
        ap.setId(AUTH_PROVIDER_ID);
        ap.setProviderName(PROVIDER_NAME);
        ap.setProviderUserId(PROVIDER_USER_ID);
        ap.setCreatedAt(CREATED_AT);
        ap.setUpdatedAt(UPDATED_AT);
        dto.setAuthProviders(List.of(ap));
        userMapper.upsert(dto);

        // 実行：削除
        userMapper.delete(USERID);

        // 検証
        assertThat(userMapper.selectById(USERID)).isEmpty();
        assertThat(userMapper.selectByEmail(EMAIL)).isEmpty();
    }
}
