package com.example.keirekipro.usecase.auth;

import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * パスワードリセットユースケース
 */
@Service
@RequiredArgsConstructor
public class ResetPasswordUseCase {

    private final UserRepository userRepository;

    private final PasswordEncoder passwordEncoder;

    /**
     * パスワードリセットユースケースを実行する
     *
     * @param userId      対象ユーザーID
     * @param newPassword 新しいパスワード
     */
    @Transactional
    public void execute(UUID userId, String newPassword) {

        // 対象ユーザーを取得
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AccessDeniedException("不正なアクセスです。"));

        // パスワードハッシュ化
        String hashedPassword = passwordEncoder.encode(newPassword);

        // パスワードを変更
        user = user.resetPassword(hashedPassword);

        // 保存
        userRepository.save(user);
    }
}
