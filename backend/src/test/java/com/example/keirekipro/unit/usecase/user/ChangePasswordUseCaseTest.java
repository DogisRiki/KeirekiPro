package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Collections;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.presentation.user.dto.ChangePasswordRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;
import com.example.keirekipro.usecase.user.ChangePasswordUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class ChangePasswordUseCaseTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @InjectMocks
    private ChangePasswordUseCase changePasswordUseCase;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String CURRENT_PASSWORD = "currentPassword";
    private static final String NEW_PASSWORD = "newPassword";
    private static final String HASHED_CURRENT_PASSWORD = "hashedCurrentPassword";
    private static final String HASHED_NEW_PASSWORD = "hashedNewPassword";

    @Test
    @DisplayName("パスワード変更が正常に完了する")
    void test1() {
        // リクエスト作成
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, NEW_PASSWORD);

        // テスト用ユーザー生成
        Notification notification = new Notification();
        User user = User.create(notification, 1, Email.create(notification, "test@keirekipro.click"),
                HASHED_CURRENT_PASSWORD, false, Collections.emptyMap(), null, "tester");

        // モックをセットアップ
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches(CURRENT_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(true);
        when(passwordEncoder.matches(NEW_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(false);
        when(passwordEncoder.encode(NEW_PASSWORD)).thenReturn(HASHED_NEW_PASSWORD);

        // ユースケース実行
        assertThatCode(() -> changePasswordUseCase.execute(request, USER_ID)).doesNotThrowAnyException();

        // 検証
        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        User saved = captor.getValue();
        assert saved.getPasswordHash().equals(HASHED_NEW_PASSWORD);
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、AuthenticationCredentialsNotFoundExceptionがスローされる")
    void test2() {
        // リクエスト作成
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, NEW_PASSWORD);

        // モックをセットアップ
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> changePasswordUseCase.execute(request, USER_ID))
                .isInstanceOf(AuthenticationCredentialsNotFoundException.class)
                .hasMessage("不正なアクセスです。");

        // 検証
        verify(userRepository, never()).save(any());
    }

    @Test
    @DisplayName("現在のパスワードが一致しない場合、UseCaseExceptionがスローされる")
    void test3() {
        // リクエスト作成
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, NEW_PASSWORD);

        // テスト用ユーザー生成
        Notification notification = new Notification();
        User user = User.create(notification, 1, Email.create(notification, "test@keirekipro.click"),
                HASHED_CURRENT_PASSWORD, false, Collections.emptyMap(), null, "tester");

        // モックをセットアップ
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches(CURRENT_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(false);

        // ユースケース実行
        assertThatThrownBy(() -> changePasswordUseCase.execute(request, USER_ID))
                .isInstanceOf(UseCaseException.class)
                .matches(e -> {
                    UseCaseException ex = (UseCaseException) e;
                    return ex.getErrors().containsKey("nowPassword")
                            && ex.getErrors().get("nowPassword").contains("現在のパスワードが正しくありません。");
                });

        // 検証
        verify(userRepository, never()).save(any());
    }

    @Test
    @DisplayName("新しいパスワードが現在のパスワードと同じ場合、UseCaseExceptionがスローされる")
    void test4() {
        // リクエスト作成
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, NEW_PASSWORD);

        // テスト用ユーザー生成
        Notification notification = new Notification();
        User user = User.create(notification, 1, Email.create(notification, "test@keirekipro.click"),
                HASHED_CURRENT_PASSWORD, false, Collections.emptyMap(), null, "tester");

        // モックをセットアップ
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches(CURRENT_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(true);
        when(passwordEncoder.matches(NEW_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(true);

        // ユースケース実行
        assertThatThrownBy(() -> changePasswordUseCase.execute(request, USER_ID))
                .isInstanceOf(UseCaseException.class)
                .matches(e -> {
                    UseCaseException ex = (UseCaseException) e;
                    return ex.getErrors().containsKey("newPassword")
                            && ex.getErrors().get("newPassword")
                                    .contains("新しいパスワードは現在のパスワードと異なる必要があります。");
                });

        // 検証
        verify(userRepository, never()).save(any());
    }

    @Test
    @DisplayName("現在のパスワードが一致せず、新しいパスワードも現在のパスワードと同じ場合、UseCaseExceptionがスローされる")
    void test5() {
        // リクエスト作成
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, NEW_PASSWORD);

        // テスト用ユーザー生成
        Notification notification = new Notification();
        User user = User.create(notification, 1, Email.create(notification, "test@keirekipro.click"),
                HASHED_CURRENT_PASSWORD, false, Collections.emptyMap(), null, "tester");

        // モックをセットアップ
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches(CURRENT_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(false);
        when(passwordEncoder.matches(NEW_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(true);

        // ユースケース実行
        assertThatThrownBy(() -> changePasswordUseCase.execute(request, USER_ID))
                .isInstanceOf(UseCaseException.class)
                .matches(e -> {
                    UseCaseException ex = (UseCaseException) e;
                    return ex.getErrors().containsKey("nowPassword")
                            && ex.getErrors().get("nowPassword").contains("現在のパスワードが正しくありません。")
                            && ex.getErrors().containsKey("newPassword")
                            && ex.getErrors().get("newPassword")
                                    .contains("新しいパスワードは現在のパスワードと異なる必要があります。");
                });

        // 検証
        verify(userRepository, never()).save(any());
    }
}
