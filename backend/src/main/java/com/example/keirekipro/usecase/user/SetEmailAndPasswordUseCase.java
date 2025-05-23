package com.example.keirekipro.usecase.user;

import java.util.UUID;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.presentation.user.dto.SetEmailAndPasswordRequest;
import com.example.keirekipro.shared.Notification;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * メールアドレス+パスワード設定ユースケース
 */
@Service
@RequiredArgsConstructor
public class SetEmailAndPasswordUseCase {

    private final UserRepository userRepository;

    private final PasswordEncoder passwordEncoder;

    /**
     * メールアドレス+パスワードの設定ユースケースを実行する
     *
     * @param userId  ユーザーID
     * @param request リクエスト
     */
    @Transactional
    public void execute(UUID userId, SetEmailAndPasswordRequest request) {

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AccessDeniedException("不正なアクセスです。"));

        Notification notification = new Notification();

        if (request.getEmail() != null) {
            Email email = Email.create(notification, request.getEmail());
            user = user.setEmail(notification, email);
        }

        if (request.getPassword() != null) {
            String passwordHash = passwordEncoder.encode(request.getPassword());
            user = user.resetPassword(passwordHash);
        }

        userRepository.save(user);
    }
}
