package com.example.keirekipro.usecase.auth;

import java.util.UUID;

import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;
import com.example.keirekipro.presentation.auth.dto.UserRegistrationRequest;
import com.example.keirekipro.usecase.shared.UseCaseException;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー新規登録ユースケース
 */
@Service
@RequiredArgsConstructor
public class UserRegistrationUseCase {

    private final UserMapper userMapper;

    private final PasswordEncoder passwordEncoder;

    /**
     * ユーザー新規登録ユースケースを実行する
     *
     * @param request リクエスト
     */
    public void execute(UserRegistrationRequest request) {
        // 重複チェック
        userMapper.findByEmail(request.getEmail()).ifPresent(user -> {
            throw new UseCaseException("このメールアドレスは既に登録されています。");
        });

        // ユーザー新規登録
        String hashedPassword = passwordEncoder.encode(request.getPassword());
        userMapper.registerUser(UUID.randomUUID(), request.getEmail(), hashedPassword, request.getUsername());
    }
}
