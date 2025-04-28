package com.example.keirekipro.usecase.auth;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.presentation.auth.dto.LoginRequest;
import com.example.keirekipro.usecase.auth.dto.LoginUseCaseDto;

import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * ログインユースケース
 */
@Service
@RequiredArgsConstructor
public class LoginUseCase {

    private final UserRepository userRepository;

    private final PasswordEncoder passwordEncoder;

    /**
     * ログインのユースケースを実行する
     *
     * @param request リクエスト
     * @return ユーザー認証情報
     */
    public LoginUseCaseDto execute(LoginRequest request) {

        // ユーザーが存在するか
        User user = userRepository.findByEmail(request.getEmail())
                .orElseThrow(() -> new BadCredentialsException("メールアドレスまたはパスワードが正しくありません。"));

        // パスワードが一致するか
        if (!passwordEncoder.matches(request.getPassword(), user.getPasswordHash())) {
            throw new BadCredentialsException("メールアドレスまたはパスワードが正しくありません。");
        }

        return LoginUseCaseDto.builder()
                .id(user.getId())
                .email(user.getEmail().getValue())
                .twoFactorAuthEnabled(user.isTwoFactorAuthEnabled())
                .build();
    }
}
