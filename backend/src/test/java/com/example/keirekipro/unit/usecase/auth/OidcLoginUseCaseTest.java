package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Map;
import java.util.Optional;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.OidcLoginUseCase;
import com.example.keirekipro.usecase.auth.dto.OidcLoginUseCaseDto;
import com.example.keirekipro.usecase.auth.oidc.OidcUserInfo;
import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class OidcLoginUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private DomainEventPublisher eventPublisher;

    @Mock
    private UserTokenVersionStore userTokenVersionStore;

    @InjectMocks
    private OidcLoginUseCase oidcLoginUseCase;

    private static final String PROVIDER_USER_ID = "12345";
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PROVIDER_TYPE = "google";

    @Test
    @DisplayName("同一プロバイダーで既存ユーザーが存在する場合、既存ユーザーを返す（トークンバージョン初期化は呼ばれない）")
    void test1() {
        ErrorCollector errorCollector = new ErrorCollector();
        Map<String, AuthProvider> providers = Map.of(
                PROVIDER_TYPE, AuthProvider.create(errorCollector, PROVIDER_TYPE, PROVIDER_USER_ID));
        User existingUser = User.create(
                errorCollector,
                Email.create(errorCollector, EMAIL),
                null,
                providers,
                null,
                USERNAME);

        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID))
                .thenReturn(Optional.of(existingUser));
        when(userRepository.findById(existingUser.getId()))
                .thenReturn(Optional.of(existingUser));

        OidcLoginUseCaseDto result = oidcLoginUseCase.execute(OidcUserInfo.builder()
                .providerUserId(PROVIDER_USER_ID)
                .email(EMAIL)
                .username(USERNAME)
                .providerType(PROVIDER_TYPE)
                .build());

        assertThat(result.getId()).isEqualTo(existingUser.getId());
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);
        assertThat(result.getRoles()).containsExactlyInAnyOrder("USER");
        verify(userRepository).findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID);
        verify(userRepository).findById(existingUser.getId());
        verify(userRepository).save(existingUser);
        verify(eventPublisher, never()).publish(any());
        verify(userTokenVersionStore, never()).initialize(any());
    }

    @Test
    @DisplayName("別プロバイダーで既存ユーザーが存在する場合、新しいプロバイダーを追加する（トークンバージョン初期化は呼ばれない）")
    void test2() {
        ErrorCollector errorCollector = new ErrorCollector();
        Map<String, AuthProvider> existingProviders = Map.of(
                "github", AuthProvider.create(errorCollector, "github", "github-id"));
        User existingUser = User.create(
                errorCollector,
                Email.create(errorCollector, EMAIL),
                null,
                existingProviders,
                null,
                USERNAME);

        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID))
                .thenReturn(Optional.empty());
        when(userRepository.findByEmail(EMAIL))
                .thenReturn(Optional.of(existingUser));
        when(userRepository.findById(existingUser.getId()))
                .thenReturn(Optional.of(existingUser));

        OidcLoginUseCaseDto result = oidcLoginUseCase.execute(OidcUserInfo.builder()
                .providerUserId(PROVIDER_USER_ID)
                .email(EMAIL)
                .username(USERNAME)
                .providerType(PROVIDER_TYPE)
                .build());

        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);
        assertThat(result.getRoles()).containsExactlyInAnyOrder("USER");
        verify(userRepository).findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID);
        verify(userRepository).findByEmail(EMAIL);
        verify(userRepository).findById(existingUser.getId());
        verify(userRepository).save(any(User.class));
        verify(eventPublisher, never()).publish(any());
        verify(userTokenVersionStore, never()).initialize(any());
    }

    @Test
    @DisplayName("メールアドレスが無く、同一プロバイダーで既存ユーザーが存在する場合、既存ユーザーを返す（トークンバージョン初期化は呼ばれない）")
    void test3() {
        ErrorCollector errorCollector = new ErrorCollector();
        Map<String, AuthProvider> providers = Map.of(
                PROVIDER_TYPE, AuthProvider.create(errorCollector, PROVIDER_TYPE, PROVIDER_USER_ID));
        User existingUser = User.create(
                errorCollector,
                null,
                null,
                providers,
                null,
                USERNAME);

        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID))
                .thenReturn(Optional.of(existingUser));
        when(userRepository.findById(existingUser.getId()))
                .thenReturn(Optional.of(existingUser));

        OidcLoginUseCaseDto result = oidcLoginUseCase.execute(OidcUserInfo.builder()
                .providerUserId(PROVIDER_USER_ID)
                .email(null)
                .username(USERNAME)
                .providerType(PROVIDER_TYPE)
                .build());

        assertThat(result.getEmail()).isNull();
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);
        assertThat(result.getRoles()).containsExactlyInAnyOrder("USER");
        verify(userRepository).findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID);
        verify(userRepository).findById(existingUser.getId());
        verify(userRepository).save(existingUser);
        verify(eventPublisher, never()).publish(any());
        verify(userTokenVersionStore, never()).initialize(any());
    }

    @Test
    @DisplayName("プロバイダー・メールアドレスともに未連携の場合、新規ユーザーを作成しトークンバージョンを初期化する")
    void test4() {
        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID))
                .thenReturn(Optional.empty());
        when(userRepository.findByEmail(EMAIL))
                .thenReturn(Optional.empty());

        OidcLoginUseCaseDto result = oidcLoginUseCase.execute(OidcUserInfo.builder()
                .providerUserId(PROVIDER_USER_ID)
                .email(EMAIL)
                .username(USERNAME)
                .providerType(PROVIDER_TYPE)
                .build());

        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);
        assertThat(result.getRoles()).containsExactlyInAnyOrder("USER");
        verify(userRepository).save(any(User.class));
        verify(eventPublisher).publish(any());
        verify(userTokenVersionStore).initialize(result.getId());
    }

    @Test
    @DisplayName("メールアドレスが無い新規ユーザーは登録されイベントは発行されないが、トークンバージョンは初期化される")
    void test5() {
        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID))
                .thenReturn(Optional.empty());

        OidcLoginUseCaseDto result = oidcLoginUseCase.execute(OidcUserInfo.builder()
                .providerUserId(PROVIDER_USER_ID)
                .email(null)
                .username(USERNAME)
                .providerType(PROVIDER_TYPE)
                .build());

        assertThat(result.getEmail()).isNull();
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);
        assertThat(result.getRoles()).containsExactlyInAnyOrder("USER");
        verify(userRepository).save(any(User.class));
        verify(eventPublisher, never()).publish(any());
        verify(userTokenVersionStore).initialize(result.getId());
    }

    @Test
    @DisplayName("ユーザー保存時に例外が発生した場合、例外をスローしイベントもトークンバージョン初期化も行われない")
    void test6() {
        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID))
                .thenReturn(Optional.empty());
        when(userRepository.findByEmail(EMAIL))
                .thenReturn(Optional.empty());
        doThrow(new RuntimeException("DB Error"))
                .when(userRepository).save(any(User.class));

        assertThrows(RuntimeException.class, () -> {
            oidcLoginUseCase.execute(OidcUserInfo.builder()
                    .providerUserId(PROVIDER_USER_ID)
                    .email(EMAIL)
                    .username(USERNAME)
                    .providerType(PROVIDER_TYPE)
                    .build());
        });

        verify(eventPublisher, never()).publish(any());
        verify(userTokenVersionStore, never()).initialize(any());
    }

    @Test
    @DisplayName("別プロバイダー連携済みユーザーがメールなしで存在し、ログインした場合はaddして保存される（トークンバージョン初期化は呼ばれない）")
    void test7() {
        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID))
                .thenReturn(Optional.empty());

        OidcLoginUseCaseDto result = oidcLoginUseCase.execute(OidcUserInfo.builder()
                .providerUserId(PROVIDER_USER_ID)
                .email(null)
                .username(USERNAME)
                .providerType(PROVIDER_TYPE)
                .build());

        assertThat(result.getEmail()).isNull();
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);
        assertThat(result.getRoles()).containsExactlyInAnyOrder("USER");
        verify(userRepository).save(any(User.class));
        verify(eventPublisher, never()).publish(any());
        verify(userTokenVersionStore).initialize(result.getId());
    }

    @Test
    @DisplayName("プロバイダーもメールも一致する既存ユーザーがいてもプロバイダー追加はされない（トークンバージョン初期化は呼ばれない）")
    void test8() {
        ErrorCollector errorCollector = new ErrorCollector();
        Map<String, AuthProvider> providers = Map.of(
                PROVIDER_TYPE, AuthProvider.create(errorCollector, PROVIDER_TYPE, PROVIDER_USER_ID));
        User existingUser = User.create(
                errorCollector,
                Email.create(errorCollector, EMAIL),
                null,
                providers,
                null,
                USERNAME);

        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID))
                .thenReturn(Optional.of(existingUser));
        when(userRepository.findById(existingUser.getId()))
                .thenReturn(Optional.of(existingUser));

        OidcLoginUseCaseDto result = oidcLoginUseCase.execute(OidcUserInfo.builder()
                .providerUserId(PROVIDER_USER_ID)
                .email(EMAIL)
                .username(USERNAME)
                .providerType(PROVIDER_TYPE)
                .build());

        assertThat(result.getId()).isEqualTo(existingUser.getId());
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.getProviderType()).isEqualTo(PROVIDER_TYPE);
        assertThat(result.getRoles()).containsExactlyInAnyOrder("USER");
        verify(userRepository).findById(existingUser.getId());
        verify(userRepository).save(existingUser);
        verify(eventPublisher, never()).publish(any());
        verify(userTokenVersionStore, never()).initialize(any());
    }
}
