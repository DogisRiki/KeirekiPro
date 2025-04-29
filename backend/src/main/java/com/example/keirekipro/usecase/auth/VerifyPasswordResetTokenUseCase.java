package com.example.keirekipro.usecase.auth;

import java.util.Optional;

import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * パスワードリセットトークン検証ユースケース
 */
@Service
@RequiredArgsConstructor
public class VerifyPasswordResetTokenUseCase {

    private final RedisClient redisClient;

    /**
     * パスワードリセットトークン検証ユースケースを実行する
     *
     * @param token リセットトークン
     */
    public void execute(String token) {

        // Redisから取得
        String key = "password-reset:" + token;
        Optional<String> userIdOpt = redisClient.getValue(key, String.class);

        if (userIdOpt.isEmpty()) {
            throw new UseCaseException("リセットリンクが無効または期限切れです。もう一度最初からお試しください。");
        }

        // 取得できたら削除（再利用防止）
        redisClient.deleteValue(key);
    }
}
