package com.example.keirekipro.unit.infrastructure.repository.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.infrastructure.repository.user.MyBatisUserRepository;
import com.example.keirekipro.infrastructure.repository.user.UserDto;
import com.example.keirekipro.infrastructure.repository.user.UserDto.AuthProviderDto;
import com.example.keirekipro.infrastructure.repository.user.UserMapper;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class MyBatisUserRepositoryTest {

    @Mock
    private UserMapper mapper;

    @InjectMocks
    private MyBatisUserRepository repository;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PASSWORD = "hashedPassword";

    private static final UUID GOOGLE_AUTH_PROVIDER_ID = UUID.fromString("f47ac10b-58cc-4372-a567-0e02b2c3d479");
    private static final String GOOGLE_PROVIDER_NAME = "google";
    private static final String GOOGLE_PROVIDER_USER_ID = "109876543210987654321";

    private static final UUID GITHUB_AUTH_PROVIDER_ID = UUID.fromString("3f8e7f2e-34a1-4c5b-9d7a-8f6e2c1b0a9f");
    private static final String GITHUB_PROVIDER_NAME = "github";
    private static final String GITHUB_PROVIDER_USER_ID = "482915736";

    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2023, 5, 1, 0, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2023, 5, 2, 0, 0);

    @Test
    @DisplayName("findById_DTOがエンティティに変換されて返却される")
    void test1() {
        // セットアップ：複数プロバイダーを含むDTOを返すようにモック設定
        UserDto dto = buildDto();
        when(mapper.selectById(USER_ID)).thenReturn(Optional.of(dto));

        // テスト実行
        Optional<User> opt = repository.findById(USER_ID);

        // 検証：存在チェック
        assertThat(opt).isPresent();
        User user = opt.get();

        // 基本フィールド
        assertThat(user.getId()).isEqualTo(USER_ID);
        assertThat(user.getEmail()).isEqualTo(Email.create(new Notification(), EMAIL));
        assertThat(user.getPasswordHash()).isEqualTo(PASSWORD);
        assertThat(user.getUsername()).isEqualTo(USERNAME);

        // 外部認証連携：キーが google と github の 2つであること
        Map<String, AuthProvider> providers = user.getAuthProviders();
        assertThat(providers)
                .containsOnlyKeys(GOOGLE_PROVIDER_NAME, GITHUB_PROVIDER_NAME);

        // Googleプロバイダーの検証
        AuthProvider google = providers.get(GOOGLE_PROVIDER_NAME);
        assertThat(google.getProviderName()).isEqualTo(GOOGLE_PROVIDER_NAME);
        assertThat(google.getProviderUserId()).isEqualTo(GOOGLE_PROVIDER_USER_ID);
        assertThat(google.getId()).isEqualTo(GOOGLE_AUTH_PROVIDER_ID);
        assertThat(google.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(google.getUpdatedAt()).isEqualTo(UPDATED_AT);

        // GitHubプロバイダーの検証
        AuthProvider github = providers.get(GITHUB_PROVIDER_NAME);
        assertThat(github.getProviderName()).isEqualTo(GITHUB_PROVIDER_NAME);
        assertThat(github.getProviderUserId()).isEqualTo(GITHUB_PROVIDER_USER_ID);
        assertThat(github.getId()).isEqualTo(GITHUB_AUTH_PROVIDER_ID);
        assertThat(github.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(github.getUpdatedAt()).isEqualTo(UPDATED_AT);
    }

    @Test
    @DisplayName("save_UserエンティティがDTOに変換されてupsertUserとプロバイダー削除・挿入が実行される")
    void test2() {
        // 外部認証プロバイダーを再構成
        AuthProvider authProvider = AuthProvider.reconstruct(
                GOOGLE_AUTH_PROVIDER_ID,
                GOOGLE_PROVIDER_NAME,
                GOOGLE_PROVIDER_USER_ID,
                CREATED_AT,
                UPDATED_AT);

        // Userエンティティを再構成（プロバイダーはgoogleのみ）
        User entity = User.reconstruct(
                USER_ID,
                1,
                Email.create(new Notification(), EMAIL),
                PASSWORD,
                false,
                Collections.singletonMap(GOOGLE_PROVIDER_NAME, authProvider),
                null,
                USERNAME,
                CREATED_AT,
                UPDATED_AT);

        // UserDtoのキャプチャ用
        ArgumentCaptor<UserDto> captor = ArgumentCaptor.forClass(UserDto.class);

        // 実行
        repository.save(entity);

        // upsertUserが呼ばれること
        verify(mapper).upsertUser(captor.capture());
        UserDto dto = captor.getValue();

        // プロバイダー削除 → 挿入 が呼ばれること
        verify(mapper).deleteAuthProviderByName(USER_ID, GOOGLE_PROVIDER_NAME);
        verify(mapper).insertAuthProvider(any(UserDto.AuthProviderDto.class));

        // DTOの内容を検証
        assertThat(dto.getId()).isEqualTo(USER_ID);
        assertThat(dto.getEmail()).isEqualTo(EMAIL);
        assertThat(dto.getPassword()).isEqualTo(PASSWORD);
        assertThat(dto.getUsername()).isEqualTo(USERNAME);
        assertThat(dto.isTwoFactorAuthEnabled()).isFalse();
        assertThat(dto.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(dto.getUpdatedAt()).isEqualTo(UPDATED_AT);

        // AuthProviderDtoの内容を検証
        UserDto.AuthProviderDto apDto = dto.getAuthProviders().get(0);
        assertThat(apDto.getId()).isEqualTo(GOOGLE_AUTH_PROVIDER_ID);
        assertThat(apDto.getUserId()).isEqualTo(USER_ID);
        assertThat(apDto.getProviderName()).isEqualTo(GOOGLE_PROVIDER_NAME);
        assertThat(apDto.getProviderUserId()).isEqualTo(GOOGLE_PROVIDER_USER_ID);
        assertThat(apDto.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(apDto.getUpdatedAt()).isEqualTo(UPDATED_AT);
    }

    @Test
    @DisplayName("findByEmail_DTOがエンティティに変換されて返却される")
    void test3() {
        // セットアップ：複数プロバイダーを含むDTOを返すようにモック設定
        UserDto dto = buildDto();
        when(mapper.selectByEmail(EMAIL)).thenReturn(Optional.of(dto));

        // テスト実行
        Optional<User> opt = repository.findByEmail(EMAIL);

        // 検証：存在チェック
        assertThat(opt).isPresent();
        User user = opt.get();

        // 基本フィールド
        assertThat(user.getId()).isEqualTo(USER_ID);
        assertThat(user.getEmail()).isEqualTo(Email.create(new Notification(), EMAIL));
        assertThat(user.getPasswordHash()).isEqualTo(PASSWORD);
        assertThat(user.getUsername()).isEqualTo(USERNAME);

        // 外部認証連携：キーがgoogleとgithubの2つであること
        Map<String, AuthProvider> providers = user.getAuthProviders();
        assertThat(providers)
                .containsOnlyKeys(GOOGLE_PROVIDER_NAME, GITHUB_PROVIDER_NAME);

        // Googleプロバイダーの検証
        AuthProvider google = providers.get(GOOGLE_PROVIDER_NAME);
        assertThat(google.getProviderName()).isEqualTo(GOOGLE_PROVIDER_NAME);
        assertThat(google.getProviderUserId()).isEqualTo(GOOGLE_PROVIDER_USER_ID);
        assertThat(google.getId()).isEqualTo(GOOGLE_AUTH_PROVIDER_ID);
        assertThat(google.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(google.getUpdatedAt()).isEqualTo(UPDATED_AT);

        // GitHubプロバイダーの検証
        AuthProvider github = providers.get(GITHUB_PROVIDER_NAME);
        assertThat(github.getProviderName()).isEqualTo(GITHUB_PROVIDER_NAME);
        assertThat(github.getProviderUserId()).isEqualTo(GITHUB_PROVIDER_USER_ID);
        assertThat(github.getId()).isEqualTo(GITHUB_AUTH_PROVIDER_ID);
        assertThat(github.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(github.getUpdatedAt()).isEqualTo(UPDATED_AT);
    }

    @Test
    @DisplayName("findByProvider_DTOがエンティティに変換されて返却される")
    void test4() {
        // セットアップ：複数プロバイダーを含むDTOを返すようにモック設定
        UserDto dto = buildDto();
        when(mapper.selectByProvider(GOOGLE_PROVIDER_NAME, GOOGLE_PROVIDER_USER_ID))
                .thenReturn(Optional.of(dto));

        // テスト実行
        Optional<User> opt = repository.findByProvider(GOOGLE_PROVIDER_NAME, GOOGLE_PROVIDER_USER_ID);

        // 検証：存在チェック
        assertThat(opt).isPresent();
        User user = opt.get();

        // 基本フィールド
        assertThat(user.getId()).isEqualTo(USER_ID);
        assertThat(user.getUsername()).isEqualTo(USERNAME);

        // 外部認証連携：キーがgoogleとgithubの2つであること
        Map<String, AuthProvider> providers = user.getAuthProviders();
        assertThat(providers)
                .containsOnlyKeys(GOOGLE_PROVIDER_NAME, GITHUB_PROVIDER_NAME);

        // 指定したGoogleプロバイダーが含まれていること
        AuthProvider google = providers.get(GOOGLE_PROVIDER_NAME);
        assertThat(google.getProviderUserId()).isEqualTo(GOOGLE_PROVIDER_USER_ID);
    }

    /**
     * テスト用DTOビルダー
     */
    private static UserDto buildDto() {
        AuthProviderDto googleDto = new AuthProviderDto();
        googleDto.setId(GOOGLE_AUTH_PROVIDER_ID);
        googleDto.setUserId(USER_ID);
        googleDto.setProviderName(GOOGLE_PROVIDER_NAME);
        googleDto.setProviderUserId(GOOGLE_PROVIDER_USER_ID);
        googleDto.setCreatedAt(CREATED_AT);
        googleDto.setUpdatedAt(UPDATED_AT);

        AuthProviderDto githubDto = new AuthProviderDto();
        githubDto.setId(GITHUB_AUTH_PROVIDER_ID);
        githubDto.setUserId(USER_ID);
        githubDto.setProviderName(GITHUB_PROVIDER_NAME);
        githubDto.setProviderUserId(GITHUB_PROVIDER_USER_ID);
        githubDto.setCreatedAt(CREATED_AT);
        githubDto.setUpdatedAt(UPDATED_AT);

        UserDto dto = new UserDto();
        dto.setId(USER_ID);
        dto.setEmail(EMAIL);
        dto.setPassword(PASSWORD);
        dto.setUsername(USERNAME);
        dto.setProfileImage(null);
        dto.setTwoFactorAuthEnabled(false);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        dto.setAuthProviders(List.of(googleDto, githubDto));
        return dto;
    }
}
