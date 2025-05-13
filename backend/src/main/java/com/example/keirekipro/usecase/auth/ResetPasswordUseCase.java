package com.example.keirekipro.usecase.auth;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

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

    private final RedisClient redisClient;

    /**
     * パスワードリセットユースケースを実行する
     *
     * @param token       トークン
     * @param newPassword 新しいパスワード
     */
    @Transactional
    public void execute(String token, String newPassword) {

        String key = "password-reset:" + token;
        Optional<String> userIdOpt = redisClient.getValue(key, String.class);

        if (userIdOpt.isEmpty()) {
            throw new UseCaseException("リセットリンクが無効または期限切れです。もう一度最初からお試しください。");
        }

        // ユーザーIDを取得
        UUID userId = UUID.fromString(userIdOpt.get());

        // 対象ユーザーを取得
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AccessDeniedException("不正なアクセスです。"));

        // パスワードハッシュ化
        String hashedPassword = passwordEncoder.encode(newPassword);

        // パスワードを変更
        user = user.resetPassword(hashedPassword);

        // 保存
        userRepository.save(user);

        // 再利用防止のため削除
        redisClient.deleteValue(key);
    }
}
