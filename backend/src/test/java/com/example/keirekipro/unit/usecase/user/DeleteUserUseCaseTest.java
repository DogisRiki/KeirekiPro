package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.domain.shared.event.DomainEventPublisher;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.auth.session.AuthSessionInvalidator;
import com.example.keirekipro.usecase.shared.store.ObjectStore;
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

    @Mock
    private AuthSessionInvalidator authSessionInvalidator;

    @Mock
    private ObjectStore objectStore;

    @InjectMocks
    private DeleteUserUseCase deleteUserUseCase;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    /**
     * ユーザーのプロフィール画像が取り得るキー(許可する拡張子ごと)
     */
    private static final List<String> CANDIDATE_KEYS = List.of(
            "/profile/image/123e4567-e89b-12d3-a456-426614174000.jpg",
            "/profile/image/123e4567-e89b-12d3-a456-426614174000.jpeg",
            "/profile/image/123e4567-e89b-12d3-a456-426614174000.png",
            "/profile/image/123e4567-e89b-12d3-a456-426614174000.gif");

    @Test
    @DisplayName("ユーザー削除が正常に完了し、認証セッションが無効化される")
    void test1() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user(null)));

        assertThatCode(() -> deleteUserUseCase.execute(USER_ID)).doesNotThrowAnyException();

        verify(userRepository).delete(USER_ID);
        verify(authSessionInvalidator).invalidate(USER_ID);
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
        verify(authSessionInvalidator, never()).invalidate(any());
        verify(eventPublisher, never()).publish(any());
        verify(objectStore, never()).delete(any());
    }

    @Test
    @DisplayName("プロフィール画像を登録しているユーザーの場合、以前の拡張子の画像も含めて取り得るキーをすべて1回ずつ削除する")
    void test3() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user(CANDIDATE_KEYS.get(2))));

        assertThatCode(() -> deleteUserUseCase.execute(USER_ID)).doesNotThrowAnyException();

        CANDIDATE_KEYS.forEach(key -> verify(objectStore, times(1)).delete(key));
        verifyNoMoreInteractions(objectStore);
        verify(userRepository).delete(USER_ID);
        verify(authSessionInvalidator).invalidate(USER_ID);
    }

    @Test
    @DisplayName("プロフィール画像を登録していないユーザーの場合も、以前に登録した画像が残らないよう取り得るキーをすべて削除する")
    void test4() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user(null)));

        deleteUserUseCase.execute(USER_ID);

        CANDIDATE_KEYS.forEach(key -> verify(objectStore).delete(key));
        verifyNoMoreInteractions(objectStore);
    }

    @Test
    @DisplayName("命名規則の導入前に保存された画像を登録している場合、そのキーも削除する")
    void test5() {
        String legacyKey = "/profile/image/9b2f6c1e-0000-4000-8000-000000000000.png";
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user(legacyKey)));

        deleteUserUseCase.execute(USER_ID);

        verify(objectStore).delete(legacyKey);
        CANDIDATE_KEYS.forEach(key -> verify(objectStore).delete(key));
        verifyNoMoreInteractions(objectStore);
    }

    @Test
    @DisplayName("ストレージの画像削除に失敗した場合、例外が伝播し認証セッションの無効化とイベント発行は行われない")
    void test6() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user(CANDIDATE_KEYS.get(2))));
        doThrow(new RuntimeException("storage error")).when(objectStore).delete(any());

        assertThatThrownBy(() -> deleteUserUseCase.execute(USER_ID))
                .isInstanceOf(RuntimeException.class)
                .hasMessage("storage error");

        verify(authSessionInvalidator, never()).invalidate(any());
        verify(eventPublisher, never()).publish(any());
    }

    private static User user(String profileImage) {
        ErrorCollector errorCollector = new ErrorCollector();
        return User.create(
                errorCollector,
                Email.create(errorCollector, "test@example.com"),
                "passwordHash",
                null,
                profileImage,
                "test-user");
    }
}
