package com.example.keirekipro.usecase.auth;

import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.usecase.auth.dto.TwoFactorAuthChallenge;
import com.example.keirekipro.usecase.auth.dto.TwoFactorAuthVerifyResultDto;
import com.example.keirekipro.usecase.auth.store.TwoFactorAuthChallengeStore;
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

    private final TwoFactorAuthChallengeStore twoFactorAuthChallengeStore;

    private final UserRepository userRepository;

    /**
     * 失敗試行回数の上限
     */
    private static final int MAX_ATTEMPTS = 5;

    /**
     *
     * @param challengeToken チャレンジトークン
     * @param code 認証コード
     * @return 検証結果
     */
    public TwoFactorAuthVerifyResultDto execute(String challengeToken, String code) {

        if (challengeToken == null || challengeToken.isBlank()) {
            throw new UseCaseException("認証セッションが無効または期限切れです。もう一度最初からお試しください。");
        }

        TwoFactorAuthChallenge challenge = twoFactorAuthChallengeStore.find(challengeToken)
                .orElseThrow(() -> new UseCaseException("認証セッションが無効または期限切れです。もう一度最初からお試しください。"));

        UUID userId = challenge.getUserId();

        String saved = twoFactorAuthCodeStore.find(userId)
                .orElseThrow(() -> {
                    twoFactorAuthChallengeStore.remove(challengeToken);
                    return new UseCaseException("認証コードが無効または期限切れです。もう一度最初からお試しください。");
                });

        if (!saved.equals(code)) {
            int attempts = twoFactorAuthChallengeStore.incrementAttempts(challengeToken);
            if (attempts >= MAX_ATTEMPTS) {
                twoFactorAuthChallengeStore.remove(challengeToken);
                twoFactorAuthCodeStore.remove(userId);
                throw new UseCaseException("試行回数の上限に達しました。もう一度最初からお試しください。");
            }
            throw new UseCaseException("認証コードが無効または期限切れです。もう一度最初からお試しください。");
        }

        // 再利用防止のため削除
        twoFactorAuthChallengeStore.remove(challengeToken);
        twoFactorAuthCodeStore.remove(userId);

        // ユーザー情報を取得してロール情報を返す
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UseCaseException("ユーザー情報の取得に失敗しました。"));

        return TwoFactorAuthVerifyResultDto.builder()
                .userId(user.getId())
                .roles(user.getRoleNames())
                .build();
    }
}
