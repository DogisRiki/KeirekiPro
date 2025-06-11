package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.user.RemoveAuthProviderUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;

@ExtendWith(MockitoExtension.class)
class RemoveAuthProviderUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private RemoveAuthProviderUseCase removeAuthProviderUseCase;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String PROVIDER = "google";

    @Test
    @DisplayName("外部認証連携解除が正常に完了する")
    void test1() {
        // データ準備
        Notification notification = new Notification();
        AuthProvider authProvider = AuthProvider.create(notification, PROVIDER, "providerUserId");
        User user = User.reconstruct(
                USER_ID,
                Email.create(notification, "test@example.com"),
                "hashedPassword",
                false,
                Map.of(PROVIDER, authProvider),
                null,
                "test-user",
                null,
                null);

        // モックをセットアップ
        when(userRepository.findById(eq(USER_ID))).thenReturn(Optional.of(user));

        // ユースケース実行
        assertThatCode(() -> removeAuthProviderUseCase.execute(USER_ID, PROVIDER)).doesNotThrowAnyException();

        // 検証
        verify(userRepository).save(any(User.class));
    }

    @Test
    @DisplayName("存在しないユーザーIDの場合、AuthenticationCredentialsNotFoundExceptionがスローされる")
    void test2() {
        // モックをセットアップ
        when(userRepository.findById(eq(USER_ID))).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> removeAuthProviderUseCase.execute(USER_ID, PROVIDER))
                .isInstanceOf(AuthenticationCredentialsNotFoundException.class)
                .hasMessage("不正なアクセスです。");

        // 検証
        verify(userRepository, never()).save(any());
    }
}
