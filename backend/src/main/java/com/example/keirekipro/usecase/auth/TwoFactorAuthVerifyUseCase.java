package com.example.keirekipro.usecase.auth;

import java.util.UUID;

import com.example.keirekipro.usecase.auth.store.TwoFactorAuthCodeStore;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 2段階認証コード検証ユースケース
 */
@Service
@RequiredArgsConstructor
public class TwoFactorAuthVerifyUseCase {

    private final TwoFactorAuthCodeStore twoFactorAuthCodeStore;

    /**
     * 2段階認証コード検証ユースケースを実行する
     *
     * @param userId ユーザーID
     * @param code   認証コード
     */
    public void execute(UUID userId, String code) {

        String saved = twoFactorAuthCodeStore.find(userId)
                .orElseThrow(() -> new UseCaseException("認証コードが無効または期限切れです。もう一度最初からお試しください。"));

        if (!saved.equals(code)) {
            throw new UseCaseException("認証コードが無効または期限切れです。もう一度最初からお試しください。");
        }

        // 再利用防止のため削除
        twoFactorAuthCodeStore.remove(userId);
    }
}
