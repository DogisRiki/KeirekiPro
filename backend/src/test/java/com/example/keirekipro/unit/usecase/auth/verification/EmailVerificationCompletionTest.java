package com.example.keirekipro.unit.usecase.auth.verification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.event.user.UserRegisteredEvent;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.RoleName;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.shared.event.DomainEvent;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationCompletion;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;

@ExtendWith(MockitoExtension.class)
class EmailVerificationCompletionTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private UserTokenVersionStore userTokenVersionStore;

    @Mock
    private DomainEventPublisher eventPublisher;

    @InjectMocks
    private EmailVerificationCompletion completion;

    private static final UUID ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String OTHER_EMAIL = "other@keirekipro.click";
    private static final String PASSWORD_HASH = "hashedPassword";
    private static final String USERNAME = "test-user";

    private static User user(String email, LocalDateTime emailVerifiedAt, String pendingEmail) {
        ErrorCollector errorCollector = new ErrorCollector();
        return User.reconstruct(
                ID,
                email == null ? null : Email.create(errorCollector, email),
                PASSWORD_HASH,
                false,
                null,
                EnumSet.of(RoleName.USER),
                null,
                USERNAME,
                LocalDateTime.of(2024, 1, 1, 0, 0),
                null,
                emailVerifiedAt,
                pendingEmail == null ? null : Email.create(errorCollector, pendingEmail));
    }

    @Test
    @DisplayName("completeRegistration は登録と同じ ID とメールアドレスとパスワードとユーザー名で確認済みのアカウントを保存し、UserRegisteredEvent を発行する")
    void test1() {
        PendingRegistration registration = new PendingRegistration(ID, EMAIL, PASSWORD_HASH, USERNAME, Instant.now());

        completion.completeRegistration(registration);

        ArgumentCaptor<User> userCaptor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(userCaptor.capture());
        User saved = userCaptor.getValue();
        assertThat(saved.getId()).isEqualTo(ID);
        assertThat(saved.getEmail().getValue()).isEqualTo(EMAIL);
        assertThat(saved.getPasswordHash()).isEqualTo(PASSWORD_HASH);
        assertThat(saved.getUsername()).isEqualTo(USERNAME);
        assertThat(saved.isEmailVerified()).isTrue();

        verify(userTokenVersionStore).initialize(ID);

        ArgumentCaptor<DomainEvent> eventCaptor = ArgumentCaptor.forClass(DomainEvent.class);
        verify(eventPublisher).publish(eventCaptor.capture());
        assertThat(eventCaptor.getValue()).isInstanceOfSatisfying(UserRegisteredEvent.class, event -> {
            assertThat(event.getUserId()).isEqualTo(ID);
            assertThat(event.getEmail()).isEqualTo(EMAIL);
            assertThat(event.getUsername()).isEqualTo(USERNAME);
        });
    }

    @Test
    @DisplayName("completeRegistration は一意の制約に当たったら例外を返し、イベントを発行しない")
    void test2() {
        PendingRegistration registration = new PendingRegistration(ID, EMAIL, PASSWORD_HASH, USERNAME, Instant.now());
        DataIntegrityViolationException failure = new DataIntegrityViolationException("duplicate email");
        doThrow(failure).when(userRepository).save(any());

        assertThatThrownBy(() -> completion.completeRegistration(registration)).isSameAs(failure);

        verify(userTokenVersionStore, never()).initialize(any());
        verify(eventPublisher, never()).publish(any());
    }

    @Test
    @DisplayName("verifyAccountEmail はトークンの email と同じアカウントの email を確認済みにする")
    void test3() {
        when(userRepository.findById(ID)).thenReturn(Optional.of(user(EMAIL, null, null)));

        completion.verifyAccountEmail(ID, EMAIL);

        ArgumentCaptor<User> userCaptor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(userCaptor.capture());
        assertThat(userCaptor.getValue().getEmail().getValue()).isEqualTo(EMAIL);
        assertThat(userCaptor.getValue().isEmailVerified()).isTrue();
    }

    @Test
    @DisplayName("verifyAccountEmail はアカウントの email がトークンの email と違えば保存しない")
    void test4() {
        when(userRepository.findById(ID)).thenReturn(Optional.of(user(OTHER_EMAIL, null, null)));

        assertThatThrownBy(() -> completion.verifyAccountEmail(ID, EMAIL)).isInstanceOf(UseCaseException.class);

        verify(userRepository, never()).save(any());
    }

    @Test
    @DisplayName("verifyAccountEmail はアカウントが無ければ保存しない")
    void test5() {
        when(userRepository.findById(ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> completion.verifyAccountEmail(ID, EMAIL)).isInstanceOf(UseCaseException.class);

        verify(userRepository, never()).save(any());
    }

    @Test
    @DisplayName("promotePendingEmail は pending_email がトークンの email と同じときだけ移す")
    void test6() {
        when(userRepository.findById(ID)).thenReturn(Optional.of(user(null, null, EMAIL)));

        completion.promotePendingEmail(ID, EMAIL);

        ArgumentCaptor<User> userCaptor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(userCaptor.capture());
        User saved = userCaptor.getValue();
        assertThat(saved.getEmail().getValue()).isEqualTo(EMAIL);
        assertThat(saved.getPendingEmail()).isNull();
        assertThat(saved.isEmailVerified()).isTrue();
    }

    @Test
    @DisplayName("promotePendingEmail は pending_email がトークンの email と違えば保存しない")
    void test7() {
        when(userRepository.findById(ID)).thenReturn(Optional.of(user(null, null, OTHER_EMAIL)));

        assertThatThrownBy(() -> completion.promotePendingEmail(ID, EMAIL)).isInstanceOf(UseCaseException.class);

        verify(userRepository, never()).save(any());
    }
}
