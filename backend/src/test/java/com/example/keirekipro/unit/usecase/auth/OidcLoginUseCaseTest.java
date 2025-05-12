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
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.auth.OidcLoginUseCase;
import com.example.keirekipro.usecase.auth.dto.OidcLoginUseCaseDto;

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

    @InjectMocks
    private OidcLoginUseCase oidcLoginUseCase;

    private static final String PROVIDER_USER_ID = "12345";
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PROVIDER_TYPE = "google";

    @Test
    @DisplayName("同一プロバイダーで既存ユーザーが存在する場合、既存ユーザーを返す（何も変更しない）")
    void test1() {
        Notification notification = new Notification();
        Map<String, AuthProvider> providers = Map.of(
                PROVIDER_TYPE, AuthProvider.create(notification, PROVIDER_TYPE, PROVIDER_USER_ID));
        User existingUser = User.create(notification, 1, Email.create(notification, EMAIL), null, false, providers,
                null, USERNAME);
        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID)).thenReturn(Optional.of(existingUser));

        OidcLoginUseCaseDto result = oidcLoginUseCase
                .execute(new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));

        assertThat(result.getId()).isEqualTo(existingUser.getId());
        verify(userRepository).findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID);
        verify(userRepository).save(existingUser);
        verify(eventPublisher, never()).publish(any());
    }

    @Test
    @DisplayName("別プロバイダーで既存ユーザーが存在する場合、新しいプロバイダーを追加する")
    void test2() {
        // 既存ユーザー（異なるプロバイダー連携済み）を返すように設定
        Notification notification = new Notification();
        Map<String, AuthProvider> existingProviders = Map.of(
                "github", AuthProvider.create(notification, "github", "github-id"));
        User existingUser = User.create(notification, 1, Email.create(notification, EMAIL), null, false,
                existingProviders, null, USERNAME);
        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID)).thenReturn(Optional.empty());
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(existingUser));

        // 実行
        OidcLoginUseCaseDto result = oidcLoginUseCase
                .execute(new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));

        // 検証
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        verify(userRepository).save(any(User.class));
        verify(eventPublisher, never()).publish(any());
    }

    @Test
    @DisplayName("メールアドレスが無く、同一プロバイダーで既存ユーザーが存在する場合、既存ユーザーを返す")
    void test3() {
        Notification notification = new Notification();
        Map<String, AuthProvider> providers = Map.of(
                PROVIDER_TYPE, AuthProvider.create(notification, PROVIDER_TYPE, PROVIDER_USER_ID));
        User existingUser = User.create(notification, 1, null, null, false, providers, null, USERNAME);
        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID)).thenReturn(Optional.of(existingUser));

        OidcLoginUseCaseDto result = oidcLoginUseCase
                .execute(new OidcUserInfoDto(PROVIDER_USER_ID, null, USERNAME, PROVIDER_TYPE));

        assertThat(result.getEmail()).isNull();
        verify(userRepository).save(existingUser);
        verify(eventPublisher, never()).publish(any());
    }

    @Test
    @DisplayName("プロバイダー・メールアドレスともに未連携の場合、新規ユーザーを作成しイベントを発行する")
    void test4() {
        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID)).thenReturn(Optional.empty());
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        OidcLoginUseCaseDto result = oidcLoginUseCase
                .execute(new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));

        assertThat(result.getEmail()).isEqualTo(EMAIL);
        verify(userRepository).save(any(User.class));
        verify(eventPublisher).publish(any());
    }

    @Test
    @DisplayName("メールアドレスが無い新規ユーザーは登録されるがイベントは発行されない")
    void test5() {
        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID)).thenReturn(Optional.empty());

        OidcLoginUseCaseDto result = oidcLoginUseCase
                .execute(new OidcUserInfoDto(PROVIDER_USER_ID, null, USERNAME, PROVIDER_TYPE));

        assertThat(result.getEmail()).isNull();
        verify(userRepository).save(any(User.class));
        verify(eventPublisher, never()).publish(any());
    }

    @Test
    @DisplayName("ユーザー保存時に例外が発生した場合、例外をスローしイベントは発行されない")
    void test6() {
        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID)).thenReturn(Optional.empty());
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        doThrow(new RuntimeException("DB Error")).when(userRepository).save(any(User.class));

        assertThrows(RuntimeException.class, () -> {
            oidcLoginUseCase.execute(new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));
        });

        verify(eventPublisher, never()).publish(any());
    }

    @Test
    @DisplayName("別プロバイダー連携済みユーザーがメールなしで存在し、ログインした場合はaddして保存される")
    void test7() {
        // プロバイダーでは見つからず、メールアドレスも null のため email 検索も呼ばれない
        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID)).thenReturn(Optional.empty());

        // 実行
        OidcLoginUseCaseDto result = oidcLoginUseCase
                .execute(new OidcUserInfoDto(PROVIDER_USER_ID, null, USERNAME, PROVIDER_TYPE));

        // 検証
        assertThat(result.getEmail()).isNull();
        verify(userRepository).save(any(User.class));
        verify(eventPublisher, never()).publish(any());
    }

    @Test
    @DisplayName("プロバイダーもメールも一致する既存ユーザーがいてもプロバイダー追加はされない")
    void test8() {
        Notification notification = new Notification();
        Map<String, AuthProvider> providers = Map.of(
                PROVIDER_TYPE, AuthProvider.create(notification, PROVIDER_TYPE, PROVIDER_USER_ID));
        User existingUser = User.create(notification, 1, Email.create(notification, EMAIL), null, false, providers,
                null, USERNAME);

        when(userRepository.findByProvider(PROVIDER_TYPE, PROVIDER_USER_ID)).thenReturn(Optional.of(existingUser));

        oidcLoginUseCase.execute(new OidcUserInfoDto(PROVIDER_USER_ID, EMAIL, USERNAME, PROVIDER_TYPE));

        verify(userRepository).save(existingUser);
        verify(eventPublisher, never()).publish(any());
    }
}
