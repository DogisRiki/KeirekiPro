package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.presentation.user.dto.SetEmailAndPasswordRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.user.SetEmailAndPasswordUseCase;
import com.example.keirekipro.usecase.user.dto.UserInfoUseCaseDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class SetEmailAndPasswordUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private DomainEventPublisher eventPublisher;

    @InjectMocks
    private SetEmailAndPasswordUseCase setEmailAndPasswordUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String RAW_PASSWORD = "Password123";
    private static final String ENCODED_PASSWORD = "encoded-password";
    private static final String USERNAME = "test-user";
    private static final String PROVIDER_NAME = "google";
    private static final String PROVIDER_USER_ID = "109876543210987654321";

    @Test
    @DisplayName("パスワードのみを設定する")
    void test1() {
        // モックセットアップ
        Email email = Email.create(new Notification(), EMAIL);
        AuthProvider authProvider = AuthProvider.create(new Notification(), PROVIDER_NAME, PROVIDER_USER_ID);
        User user = User.reconstruct(
                USER_ID,
                1,
                email,
                null,
                false,
                Map.of(PROVIDER_NAME, authProvider),
                null,
                USERNAME,
                null,
                null);

        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(passwordEncoder.encode(RAW_PASSWORD)).thenReturn(ENCODED_PASSWORD);

        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(null, RAW_PASSWORD, RAW_PASSWORD);
        UserInfoUseCaseDto result = setEmailAndPasswordUseCase.execute(USER_ID, request);

        // 検証
        verify(userRepository).save(any(User.class));

        assertThat(result.getId()).isEqualTo(USER_ID);
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.isHasPassword()).isTrue();
        assertThat(result.getProfileImage()).isNull();
        assertThat(result.isTwoFactorAuthEnabled()).isFalse();
        assertThat(
                result.getAuthProviders().stream()
                        .map(UserInfoUseCaseDto.AuthProviderInfo::getProviderName)
                        .collect(Collectors.toList()))
                .containsExactly(PROVIDER_NAME);
    }

    @Test
    @DisplayName("メールアドレスとパスワードを設定する")
    void test2() {
        // モックセットアップ
        AuthProvider authProvider = AuthProvider.create(new Notification(), PROVIDER_NAME, PROVIDER_USER_ID);
        User user = User.reconstruct(
                USER_ID,
                1,
                null,
                null,
                false,
                Map.of(PROVIDER_NAME, authProvider),
                null,
                USERNAME,
                null,
                null);

        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(passwordEncoder.encode(RAW_PASSWORD)).thenReturn(ENCODED_PASSWORD);

        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(EMAIL, RAW_PASSWORD, RAW_PASSWORD);
        UserInfoUseCaseDto result = setEmailAndPasswordUseCase.execute(USER_ID, request);

        // 検証
        verify(userRepository).save(any(User.class));

        assertThat(result.getId()).isEqualTo(USER_ID);
        assertThat(result.getEmail()).isEqualTo(EMAIL);
        assertThat(result.getUsername()).isEqualTo(USERNAME);
        assertThat(result.isHasPassword()).isTrue();
        assertThat(result.getProfileImage()).isNull();
        assertThat(result.isTwoFactorAuthEnabled()).isFalse();
        assertThat(
                result.getAuthProviders().stream()
                        .map(UserInfoUseCaseDto.AuthProviderInfo::getProviderName)
                        .collect(Collectors.toList()))
                .containsExactly(PROVIDER_NAME);
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、AccessDeniedExceptionがスローされる")
    void test3() {
        when(userRepository.findById(eq(USER_ID))).thenReturn(Optional.empty());

        assertThatThrownBy(() -> setEmailAndPasswordUseCase.execute(USER_ID, any()))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessage("不正なアクセスです。");

        verify(userRepository, never()).save(any());
    }
}
