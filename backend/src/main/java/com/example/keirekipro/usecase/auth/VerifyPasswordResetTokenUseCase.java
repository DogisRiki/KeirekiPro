package com.example.keirekipro.usecase.auth;

import com.example.keirekipro.usecase.auth.store.PasswordResetTokenStore;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * パスワードリセットトークン検証ユースケース
 */
@Service
@RequiredArgsConstructor
public class VerifyPasswordResetTokenUseCase {

    private final PasswordResetTokenStore passwordResetTokenStore;

    /**
     * パスワードリセットトークン検証ユースケースを実行する
     *
     * @param token リセットトークン
     */
    public void execute(String token) {

        if (passwordResetTokenStore.findUserId(token).isEmpty()) {
            throw new UseCaseException("リセットリンクが無効または期限切れです。もう一度最初からお試しください。");
        }
    }
}
