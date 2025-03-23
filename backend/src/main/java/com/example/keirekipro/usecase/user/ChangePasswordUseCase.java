package com.example.keirekipro.usecase.user;

import java.util.UUID;

import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;
import com.example.keirekipro.presentation.user.dto.ChangePasswordRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * パスワード変更ユースケース
 */
@Service
@RequiredArgsConstructor
public class ChangePasswordUseCase {

    private final UserMapper userMapper;

    private final PasswordEncoder passwordEncoder;

    /**
     * パスワード変更ユースケースを実行する
     *
     * @param request リクエスト
     */
    public void execute(ChangePasswordRequest request, UUID userId) {

        String nowPassword = userMapper.selectPasswordById(userId)
                .orElseThrow(() -> new AccessDeniedException("不正なアクセスです。"));

        Notification notification = new Notification();

        // 旧パスワードが一致しているかを検証する
        if (!passwordEncoder.matches(request.getNowPassword(), nowPassword)) {
            notification.addError("nowPassword", "現在のパスワードが正しくありません。");
        }

        // 旧パスワードと新パスワードが異なることを検証する
        if (passwordEncoder.matches(request.getNewPassword(), nowPassword)) {
            notification.addError("newPassword", "新しいパスワードは現在のパスワードと異なる必要があります。");
        }

        // エラーチェック
        if (notification.hasErrors()) {
            throw new UseCaseException(notification.getErrors());
        }

        // 新しいパスワードを保存
        String newHashedPassword = passwordEncoder.encode(request.getNewPassword());
        userMapper.updatePassword(userId, newHashedPassword);
    }
}
