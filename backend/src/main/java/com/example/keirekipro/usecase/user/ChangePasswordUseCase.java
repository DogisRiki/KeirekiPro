package com.example.keirekipro.usecase.user;

import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
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

    private final UserRepository userRepository;

    private final PasswordEncoder passwordEncoder;

    /**
     * パスワード変更ユースケースを実行する
     *
     * @param request リクエスト
     */
    public void execute(ChangePasswordRequest request, UUID userId) {

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AccessDeniedException("不正なアクセスです。"));

        Notification notification = new Notification();

        if (!passwordEncoder.matches(request.getNowPassword(), user.getPasswordHash())) {
            notification.addError("nowPassword", "現在のパスワードが正しくありません。");
        }
        if (passwordEncoder.matches(request.getNewPassword(), user.getPasswordHash())) {
            notification.addError("newPassword", "新しいパスワードは現在のパスワードと異なる必要があります。");
        }
        if (notification.hasErrors()) {
            throw new UseCaseException(notification.getErrors());
        }

        String hashed = passwordEncoder.encode(request.getNewPassword());
        User updated = user.changePassword(new Notification(), hashed);
        userRepository.save(updated);
    }
}
