package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;
import com.example.keirekipro.presentation.user.dto.ChangePasswordRequest;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;
import com.example.keirekipro.usecase.user.ChangePasswordUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class ChangePasswordUseCaseTest {

    @Mock
    private UserMapper userMapper;

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

        // モックをセットアップ
        when(userMapper.findPasswordById(USER_ID)).thenReturn(Optional.of(HASHED_CURRENT_PASSWORD));
        when(passwordEncoder.matches(CURRENT_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(true);
        when(passwordEncoder.matches(NEW_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(false);
        when(passwordEncoder.encode(NEW_PASSWORD)).thenReturn(HASHED_NEW_PASSWORD);

        // ユースケース実行
        assertThatCode(() -> {
            changePasswordUseCase.execute(request, USER_ID);
        }).doesNotThrowAnyException();

        // 検証
        verify(userMapper).changePassword(USER_ID, HASHED_NEW_PASSWORD);
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、AccessDeniedExceptionがスローされる")
    void test2() {
        // リクエスト作成
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, NEW_PASSWORD);

        // モックをセットアップ
        when(userMapper.findPasswordById(USER_ID)).thenReturn(Optional.empty());

        // ユースケース実行
        assertThatThrownBy(() -> {
            changePasswordUseCase.execute(request, USER_ID);
        })
                .isInstanceOf(AccessDeniedException.class)
                .hasMessage("不正なアクセスです。");

        // 検証
        verify(userMapper, never()).changePassword(any(UUID.class), anyString());
    }

    @Test
    @DisplayName("現在のパスワードが一致しない場合、UseCaseExceptionがスローされる")
    void test3() {
        // リクエスト作成
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, NEW_PASSWORD);

        // モックをセットアップ
        when(userMapper.findPasswordById(USER_ID)).thenReturn(Optional.of(HASHED_CURRENT_PASSWORD));
        when(passwordEncoder.matches(CURRENT_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(false);

        // ユースケース実行
        assertThatThrownBy(() -> changePasswordUseCase.execute(request,
                USER_ID))
                .isInstanceOf(UseCaseException.class)
                .matches(e -> {
                    UseCaseException exception = (UseCaseException) e;
                    return exception.getErrors().containsKey("nowPassword")
                            && exception.getErrors().get("nowPassword").contains("現在のパスワードが正しくありません。");
                });

        // 検証
        verify(userMapper, never()).changePassword(any(UUID.class), anyString());
    }

    @Test
    @DisplayName("新しいパスワードが現在のパスワードと同じ場合、UseCaseExceptionがスローされる")
    void test4() {
        // リクエスト作成
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, NEW_PASSWORD);

        // モックをセットアップ
        when(userMapper.findPasswordById(USER_ID)).thenReturn(Optional.of(HASHED_CURRENT_PASSWORD));
        when(passwordEncoder.matches(CURRENT_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(true);
        when(passwordEncoder.matches(NEW_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(true);

        // ユースケース実行
        assertThatThrownBy(() -> changePasswordUseCase.execute(request,
                USER_ID))
                .isInstanceOf(UseCaseException.class)
                .matches(e -> {
                    UseCaseException exception = (UseCaseException) e;
                    return exception.getErrors().containsKey("newPassword")
                            && exception.getErrors().get("newPassword").contains("新しいパスワードは現在のパスワードと異なる必要があります。");
                });

        // 検証
        verify(userMapper, never()).changePassword(any(UUID.class), anyString());
    }

    @Test
    @DisplayName("現在のパスワードが一致せず、新しいパスワードも現在のパスワードと同じ場合、UseCaseExceptionがスローされる")
    void test5() {
        // リクエスト作成
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, NEW_PASSWORD);

        // モックをセットアップ
        when(userMapper.findPasswordById(USER_ID)).thenReturn(Optional.of(HASHED_CURRENT_PASSWORD));
        when(passwordEncoder.matches(CURRENT_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(false);
        when(passwordEncoder.matches(NEW_PASSWORD, HASHED_CURRENT_PASSWORD)).thenReturn(true);

        // ユースケース実行
        assertThatThrownBy(() -> changePasswordUseCase.execute(request,
                USER_ID))
                .isInstanceOf(UseCaseException.class)
                .matches(e -> {
                    UseCaseException exception = (UseCaseException) e;
                    return exception.getErrors().containsKey("nowPassword")
                            && exception.getErrors().get("nowPassword").contains("現在のパスワードが正しくありません。")
                            && exception.getErrors().containsKey("newPassword")
                            && exception.getErrors().get("newPassword").contains("新しいパスワードは現在のパスワードと異なる必要があります。");
                });

        // 検証
        verify(userMapper, never()).changePassword(any(UUID.class), anyString());
    }
}
