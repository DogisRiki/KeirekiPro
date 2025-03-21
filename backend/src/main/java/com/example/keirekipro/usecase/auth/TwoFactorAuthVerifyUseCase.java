package com.example.keirekipro.usecase.auth;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.shared.redis.RedisClient;

import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 2段階認証コード検証ユースケース
 */
@Service
@RequiredArgsConstructor
public class TwoFactorAuthVerifyUseCase {

    private final RedisClient redisClient;

    /**
     * 2段階認証コード検証ユースケースを実行する
     *
     * @param userId ユーザーID
     * @param code   2段階認証用コード
     */
    public void execute(UUID userId, String code) {
        // 保存されたコードを取得
        String key = "2fa:" + userId;
        Optional<String> storedOpt = redisClient.getValue(key, String.class);

        // 期限切れ or そもそも未発行の場合
        if (storedOpt.isEmpty()) {
            throw new BadCredentialsException("二段階認証コードが期限切れです。再度認証を行ってください。");
        }

        // 検証NGの場合
        if (!storedOpt.get().equals(code)) {
            throw new BadCredentialsException("二段階認証コードが正しくありません。");
        }

        // 検証OKの場合は再利用防止のため、コードを削除
        redisClient.deleteValue(key);
    }
}
