package com.example.keirekipro.usecase.user;

import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.presentation.user.dto.ChangePasswordRequest;
import com.example.keirekipro.shared.ErrorCollector;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
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
                .orElseThrow(() -> new AuthenticationCredentialsNotFoundException("不正なアクセスです。"));

        ErrorCollector errorCollector = new ErrorCollector();

        if (!passwordEncoder.matches(request.getNowPassword(), user.getPasswordHash())) {
            errorCollector.addError("nowPassword", "現在のパスワードが正しくありません。");
        }
        if (passwordEncoder.matches(request.getNewPassword(), user.getPasswordHash())) {
            errorCollector.addError("newPassword", "新しいパスワードは現在のパスワードと異なる必要があります。");
        }
        if (errorCollector.hasErrors()) {
            throw new UseCaseException(errorCollector.getErrors());
        }

        String hashed = passwordEncoder.encode(request.getNewPassword());
        User updated = user.changePassword(new ErrorCollector(), hashed);
        userRepository.save(updated);
    }
}
