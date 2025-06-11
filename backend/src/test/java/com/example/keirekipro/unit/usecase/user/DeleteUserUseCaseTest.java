package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.user.DeleteUserUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;

@ExtendWith(MockitoExtension.class)
class DeleteUserUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private DomainEventPublisher eventPublisher;

    @InjectMocks
    private DeleteUserUseCase deleteUserUseCase;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    @Test
    @DisplayName("ユーザー削除が正常に完了する")
    void test1() {
        Notification notification = new Notification();
        User user = User.create(notification, Email.create(notification, "test@example.com"),
                "passwordHash", false, null, null, "test-user");

        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));

        assertThatCode(() -> deleteUserUseCase.execute(USER_ID)).doesNotThrowAnyException();

        verify(userRepository).delete(USER_ID);
        verify(eventPublisher, atLeastOnce()).publish(any());
    }

    @Test
    @DisplayName("ユーザーが存在しない場合はAuthenticationCredentialsNotFoundExceptionがスローされる")
    void test2() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> deleteUserUseCase.execute(USER_ID))
                .isInstanceOf(AuthenticationCredentialsNotFoundException.class)
                .hasMessage("不正なアクセスです。");

        verify(userRepository, never()).delete(any());
        verify(eventPublisher, never()).publish(any());
    }
}
