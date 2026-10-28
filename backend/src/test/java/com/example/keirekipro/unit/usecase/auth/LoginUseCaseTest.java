package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.RoleName;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.usecase.auth.command.LoginCommand;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.LoginUseCase;
import com.example.keirekipro.usecase.auth.dto.LoginUseCaseDto;
import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import com.example.keirekipro.usecase.shared.exception.EmailNotVerifiedUseCaseException;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class LoginUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private PendingRegistrationStore pendingRegistrationStore;

    @InjectMocks
    private LoginUseCase loginUseCase;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@example.com";
    private static final String HASHED_PWD = "hashedPassword";
    private static final String RAW_PASSWORD = "rawPassword";

    @Test
    @DisplayName("正しいメールアドレスとパスワードでログインする")
    void test1() {
        // モックをセットアップ
        when(userRepository.findByEmail(EMAIL))
                .thenReturn(Optional.of(buildStoredUser(HASHED_PWD)));
        when(passwordEncoder.matches(RAW_PASSWORD, HASHED_PWD)).thenReturn(true);

        // ユースケース実行
        LoginUseCaseDto dto = loginUseCase.execute(new LoginCommand(EMAIL, RAW_PASSWORD));

        // 検証
        assertThat(dto).isNotNull();
        assertThat(dto.getId()).isEqualTo(USER_ID);
        assertThat(dto.getEmail()).isEqualTo(EMAIL);
        assertThat(dto.isTwoFactorAuthEnabled()).isFalse();
        assertThat(dto.getRoles()).containsExactly(RoleName.USER.name());
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、UseCaseExceptionが発生する")
    void test2() {
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> loginUseCase.execute(new LoginCommand(EMAIL, RAW_PASSWORD)))
                .isInstanceOf(UseCaseException.class)
                .hasMessage("メールアドレスまたはパスワードが正しくありません。");
    }

    @Test
    @DisplayName("パスワードが正しくない場合、UseCaseExceptionが発生する")
    void test3() {
        when(userRepository.findByEmail(EMAIL))
                .thenReturn(Optional.of(buildStoredUser(HASHED_PWD)));
        when(passwordEncoder.matches(RAW_PASSWORD, HASHED_PWD)).thenReturn(false);

        assertThatThrownBy(() -> loginUseCase.execute(new LoginCommand(EMAIL, RAW_PASSWORD)))
                .isInstanceOf(
                        UseCaseException.class)
                .hasMessage("メールアドレスまたはパスワードが正しくありません。");
    }

    @Test
    @DisplayName("アカウントが無く、確認前の登録のパスワードが合えば kind が PENDING_REGISTRATION の例外を投げる")
    void test4() {
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        when(pendingRegistrationStore.findByEmail(EMAIL, 5)).thenReturn(List.of(
                buildRegistration("newerHash"), buildRegistration("olderHash")));
        when(passwordEncoder.matches(RAW_PASSWORD, "newerHash")).thenReturn(false);
        when(passwordEncoder.matches(RAW_PASSWORD, "olderHash")).thenReturn(true);

        assertThatThrownBy(() -> loginUseCase.execute(new LoginCommand(EMAIL, RAW_PASSWORD)))
                .isInstanceOfSatisfying(EmailNotVerifiedUseCaseException.class,
                        e -> assertThat(e.getKind())
                                .isEqualTo(EmailNotVerifiedUseCaseException.Kind.PENDING_REGISTRATION));

        // 照らし合わせる確認前の登録は、新しい順に5件まで
        verify(pendingRegistrationStore).findByEmail(EMAIL, 5);
    }

    @Test
    @DisplayName("確認前のアカウントのパスワードが合えば kind が UNVERIFIED_ACCOUNT_EMAIL の例外を投げ、2段階認証に進まない")
    void test5() {
        when(userRepository.findByEmail(EMAIL))
                .thenReturn(Optional.of(buildStoredUser(HASHED_PWD, true, null)));
        when(passwordEncoder.matches(RAW_PASSWORD, HASHED_PWD)).thenReturn(true);

        assertThatThrownBy(() -> loginUseCase.execute(new LoginCommand(EMAIL, RAW_PASSWORD)))
                .isInstanceOfSatisfying(EmailNotVerifiedUseCaseException.class,
                        e -> assertThat(e.getKind())
                                .isEqualTo(EmailNotVerifiedUseCaseException.Kind.UNVERIFIED_ACCOUNT_EMAIL));

        verify(pendingRegistrationStore, never()).findByEmail(any(), anyInt());
    }

    @Test
    @DisplayName("確認前でもパスワードが違えば今と同じ UseCaseException を投げる")
    void test6() {
        when(userRepository.findByEmail(EMAIL))
                .thenReturn(Optional.of(buildStoredUser(HASHED_PWD, false, null)));
        when(passwordEncoder.matches(RAW_PASSWORD, HASHED_PWD)).thenReturn(false);

        assertThatThrownBy(() -> loginUseCase.execute(new LoginCommand(EMAIL, RAW_PASSWORD)))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage("メールアドレスまたはパスワードが正しくありません。");
    }

    @Test
    @DisplayName("確認前の登録でもパスワードが違えば今と同じ UseCaseException を投げる")
    void test7() {
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        when(pendingRegistrationStore.findByEmail(EMAIL, 5)).thenReturn(List.of(buildRegistration("otherHash")));
        when(passwordEncoder.matches(RAW_PASSWORD, "otherHash")).thenReturn(false);

        assertThatThrownBy(() -> loginUseCase.execute(new LoginCommand(EMAIL, RAW_PASSWORD)))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage("メールアドレスまたはパスワードが正しくありません。");
    }

    @Test
    @DisplayName("設定待ちのメールアドレスでは今と同じ UseCaseException を投げる")
    void test8() {
        // findByEmail は users の email だけを探すため、設定待ちのメールアドレスではアカウントが見つからない
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        when(pendingRegistrationStore.findByEmail(EMAIL, 5)).thenReturn(List.of());

        assertThatThrownBy(() -> loginUseCase.execute(new LoginCommand(EMAIL, RAW_PASSWORD)))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage("メールアドレスまたはパスワードが正しくありません。");
    }

    @Test
    @DisplayName("確認済みのアカウントは今と同じくログインする")
    void test9() {
        when(userRepository.findByEmail(EMAIL))
                .thenReturn(Optional.of(buildStoredUser(HASHED_PWD, true, LocalDateTime.of(2024, 1, 1, 0, 0))));
        when(passwordEncoder.matches(RAW_PASSWORD, HASHED_PWD)).thenReturn(true);

        LoginUseCaseDto dto = loginUseCase.execute(new LoginCommand(EMAIL, RAW_PASSWORD));

        assertThat(dto.getId()).isEqualTo(USER_ID);
        assertThat(dto.getEmail()).isEqualTo(EMAIL);
        assertThat(dto.isTwoFactorAuthEnabled()).isTrue();
        verify(pendingRegistrationStore, never()).findByEmail(any(), anyInt());
    }

    private static PendingRegistration buildRegistration(String passwordHash) {
        return new PendingRegistration(UUID.randomUUID(), EMAIL, passwordHash, "tester", Instant.now());
    }

    // テスト用ユーザー生成ヘルパー
    private static User buildStoredUser(String passwordHash) {
        return buildStoredUser(passwordHash, false, LocalDateTime.of(2024, 1, 1, 0, 0));
    }

    private static User buildStoredUser(String passwordHash, boolean twoFactorAuthEnabled,
            LocalDateTime emailVerifiedAt) {
        ErrorCollector n = new ErrorCollector();
        return User.reconstruct(
                USER_ID,
                Email.create(n, EMAIL),
                passwordHash,
                twoFactorAuthEnabled,
                Collections.emptyMap(),
                EnumSet.of(RoleName.USER),
                null,
                "tester",
                LocalDateTime.now(),
                LocalDateTime.now(),
                emailVerifiedAt,
                null);
    }
}
