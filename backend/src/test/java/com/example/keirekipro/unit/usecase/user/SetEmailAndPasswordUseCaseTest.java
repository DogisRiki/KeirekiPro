package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.RoleName;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.service.user.UserEmailDuplicationCheckService;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.usecase.auth.store.EmailVerificationCurrentTokenStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationMailer.SendOutcome;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;
import com.example.keirekipro.usecase.user.command.SetEmailAndPasswordCommand;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.user.SetEmailAndPasswordUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class SetEmailAndPasswordUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private DomainEventPublisher eventPublisher;

    @Mock
    private UserEmailDuplicationCheckService userEmailDuplicationCheckService;

    @Mock
    private EmailVerificationCurrentTokenStore currentTokenStore;

    @Mock
    private EmailVerificationMailer mailer;

    @InjectMocks
    private SetEmailAndPasswordUseCase setEmailAndPasswordUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String RAW_PASSWORD = "Password123";
    private static final String ENCODED_PASSWORD = "encoded-password";
    private static final String USERNAME = "test-user";
    private static final String CURRENT_PASSWORD = "CurrentPass1";
    private static final String CURRENT_PASSWORD_HASH = "current-password-hash";
    private static final String OLD_PENDING_EMAIL = "old-pending@keirekipro.click";
    private static final String WRONG_CURRENT_PASSWORD_MESSAGE = "今のパスワードが正しくありません。";

    @Test
    @DisplayName("パスワードのみを設定する")
    void test1() {
        // モックをセットアップ
        User user = User.reconstruct(
                USER_ID,
                Email.create(new ErrorCollector(), EMAIL),
                null,
                false,
                Map.of(),
                EnumSet.of(RoleName.USER),
                null,
                USERNAME,
                null,
                null,
                LocalDateTime.of(2024, 1, 1, 0, 0),
                null);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(passwordEncoder.encode(RAW_PASSWORD)).thenReturn(ENCODED_PASSWORD);

        SetEmailAndPasswordCommand request = new SetEmailAndPasswordCommand(USER_ID, null, RAW_PASSWORD, null);
        setEmailAndPasswordUseCase.execute(request);

        // 検証
        verify(userRepository).save(any(User.class));
    }

    @Test
    @DisplayName("メールアドレスとパスワードを設定する")
    void test2() {
        // モックをセットアップ
        User user = User.reconstruct(
                USER_ID,
                null,
                null,
                false,
                Map.of(),
                EnumSet.of(RoleName.USER),
                null,
                USERNAME,
                null,
                null,
                LocalDateTime.of(2024, 1, 1, 0, 0),
                null);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(passwordEncoder.encode(RAW_PASSWORD)).thenReturn(ENCODED_PASSWORD);

        SetEmailAndPasswordCommand request = new SetEmailAndPasswordCommand(USER_ID, EMAIL, RAW_PASSWORD, null);
        setEmailAndPasswordUseCase.execute(request);

        // 検証
        verify(userRepository).save(any(User.class));
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、AuthenticationCredentialsNotFoundExceptionがスローされる")
    void test3() {
        // モックをセットアップ
        when(userRepository.findById(eq(USER_ID))).thenReturn(Optional.empty());

        SetEmailAndPasswordCommand request = new SetEmailAndPasswordCommand(USER_ID, null, RAW_PASSWORD, null);
        assertThatThrownBy(() -> setEmailAndPasswordUseCase.execute(request))
                .isInstanceOf(AuthenticationCredentialsNotFoundException.class)
                .hasMessage("不正なアクセスです。");

        // 検証
        verify(userRepository, never()).save(any());
    }

    @Test
    @DisplayName("メールアドレスを設定待ちにし、パスワードを設定し、PENDING_EMAIL の確認のメールを送り、email を変えない")
    void test4() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(buildStoredUser(null, null)));
        when(passwordEncoder.encode(RAW_PASSWORD)).thenReturn(ENCODED_PASSWORD);
        when(mailer.send(EMAIL, USER_ID, EmailVerificationPurpose.PENDING_EMAIL)).thenReturn(SendOutcome.SENT);

        setEmailAndPasswordUseCase.execute(new SetEmailAndPasswordCommand(USER_ID, EMAIL, RAW_PASSWORD, null));

        ArgumentCaptor<Email> checkedEmail = ArgumentCaptor.forClass(Email.class);
        verify(userEmailDuplicationCheckService).execute(checkedEmail.capture());
        assertThat(checkedEmail.getValue().getValue()).isEqualTo(EMAIL);

        // 保存したあとに、前のリンクを使えなくしてから確認のメールを送る
        ArgumentCaptor<User> saved = ArgumentCaptor.forClass(User.class);
        InOrder inOrder = inOrder(userRepository, currentTokenStore, mailer);
        inOrder.verify(userRepository).save(saved.capture());
        inOrder.verify(currentTokenStore).clear(USER_ID);
        inOrder.verify(mailer).send(EMAIL, USER_ID, EmailVerificationPurpose.PENDING_EMAIL);

        assertThat(saved.getValue().getEmail()).isNull();
        assertThat(saved.getValue().getPendingEmail().getValue()).isEqualTo(EMAIL);
        assertThat(saved.getValue().getPasswordHash()).isEqualTo(ENCODED_PASSWORD);
    }

    @Test
    @DisplayName("パスワードを持つアカウントで currentPassword が合えば設定待ちのメールアドレスを置き換え、前のリンクを使えなくする")
    void test5() {
        when(userRepository.findById(USER_ID))
                .thenReturn(Optional.of(buildStoredUser(CURRENT_PASSWORD_HASH, OLD_PENDING_EMAIL)));
        when(passwordEncoder.matches(CURRENT_PASSWORD, CURRENT_PASSWORD_HASH)).thenReturn(true);
        when(passwordEncoder.encode(RAW_PASSWORD)).thenReturn(ENCODED_PASSWORD);
        when(mailer.send(EMAIL, USER_ID, EmailVerificationPurpose.PENDING_EMAIL)).thenReturn(SendOutcome.SENT);

        setEmailAndPasswordUseCase
                .execute(new SetEmailAndPasswordCommand(USER_ID, EMAIL, RAW_PASSWORD, CURRENT_PASSWORD));

        ArgumentCaptor<User> saved = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(saved.capture());
        assertThat(saved.getValue().getPendingEmail().getValue()).isEqualTo(EMAIL);
        assertThat(saved.getValue().getPasswordHash()).isEqualTo(ENCODED_PASSWORD);
        verify(currentTokenStore).clear(USER_ID);
        verify(mailer).send(EMAIL, USER_ID, EmailVerificationPurpose.PENDING_EMAIL);
    }

    @Test
    @DisplayName("currentPassword が無いときと合わないときは UseCaseException を投げ、何も保存しない")
    void test6() {
        when(userRepository.findById(USER_ID))
                .thenReturn(Optional.of(buildStoredUser(CURRENT_PASSWORD_HASH, OLD_PENDING_EMAIL)));
        when(passwordEncoder.matches("WrongPass1", CURRENT_PASSWORD_HASH)).thenReturn(false);

        assertThatThrownBy(() -> setEmailAndPasswordUseCase
                .execute(new SetEmailAndPasswordCommand(USER_ID, EMAIL, RAW_PASSWORD, null)))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage(WRONG_CURRENT_PASSWORD_MESSAGE);
        assertThatThrownBy(() -> setEmailAndPasswordUseCase
                .execute(new SetEmailAndPasswordCommand(USER_ID, EMAIL, RAW_PASSWORD, "WrongPass1")))
                .isExactlyInstanceOf(UseCaseException.class)
                .hasMessage(WRONG_CURRENT_PASSWORD_MESSAGE);

        verify(userRepository, never()).save(any());
        verify(currentTokenStore, never()).clear(any());
        verify(mailer, never()).send(any(), any(), any());
    }

    @Test
    @DisplayName("users にあるメールアドレスでは DomainException を投げる")
    void test7() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(buildStoredUser(null, null)));
        doThrow(new DomainException("このメールアドレスは登録できません。"))
                .when(userEmailDuplicationCheckService).execute(any(Email.class));

        assertThatThrownBy(() -> setEmailAndPasswordUseCase
                .execute(new SetEmailAndPasswordCommand(USER_ID, EMAIL, RAW_PASSWORD, null)))
                .isInstanceOf(DomainException.class)
                .hasMessage("このメールアドレスは登録できません。");

        verify(userRepository, never()).save(any());
        verify(mailer, never()).send(any(), any(), any());
    }

    @Test
    @DisplayName("RATE_LIMITED でも例外を投げない")
    void test8() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(buildStoredUser(null, null)));
        when(passwordEncoder.encode(RAW_PASSWORD)).thenReturn(ENCODED_PASSWORD);
        when(mailer.send(EMAIL, USER_ID, EmailVerificationPurpose.PENDING_EMAIL))
                .thenReturn(SendOutcome.RATE_LIMITED);

        assertThatCode(() -> setEmailAndPasswordUseCase
                .execute(new SetEmailAndPasswordCommand(USER_ID, EMAIL, RAW_PASSWORD, null)))
                .doesNotThrowAnyException();

        verify(userRepository).save(any(User.class));
        verify(mailer).send(EMAIL, USER_ID, EmailVerificationPurpose.PENDING_EMAIL);
    }

    private static User buildStoredUser(String passwordHash, String pendingEmail) {
        ErrorCollector errorCollector = new ErrorCollector();
        return User.reconstruct(
                USER_ID,
                null,
                passwordHash,
                false,
                Map.of(),
                EnumSet.of(RoleName.USER),
                null,
                USERNAME,
                null,
                null,
                null,
                pendingEmail == null ? null : Email.create(errorCollector, pendingEmail));
    }
}
