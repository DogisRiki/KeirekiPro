package com.example.keirekipro.usecase.auth;

import java.util.Collections;

import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.presentation.auth.dto.UserRegistrationRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー新規登録ユースケース
 */
@Service
@RequiredArgsConstructor
public class UserRegistrationUseCase {

    private final UserRepository userRepository;

    private final PasswordEncoder passwordEncoder;

    /**
     * ユーザー新規登録ユースケースを実行する
     *
     * @param request リクエスト
     */
    public void execute(UserRegistrationRequest request) {

        // 重複チェック
        if (userRepository.findByEmail(request.getEmail()).isPresent()) {
            Notification notification = new Notification();
            notification.addError("email", "このメールアドレスは既に登録されています。");
            throw new UseCaseException(notification.getErrors());
        }

        // ユーザー新規登録
        Notification notification = new Notification();
        User user = User.create(
                notification,
                1,
                Email.create(
                        notification, request.getEmail()),
                passwordEncoder.encode(request.getPassword()),
                false,
                Collections.emptyMap(),
                null,
                request.getUsername());
        userRepository.save(user);
    }
}
