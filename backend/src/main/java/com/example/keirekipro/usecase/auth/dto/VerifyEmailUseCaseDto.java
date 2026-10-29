package com.example.keirekipro.usecase.auth.dto;

import com.example.keirekipro.usecase.auth.verification.EmailVerificationResult;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * 確認のリンクを受け付けるユースケースDTO
 */
@RequiredArgsConstructor
@Getter
public class VerifyEmailUseCaseDto {

    /**
     * 確認の結果
     */
    private final EmailVerificationResult result;

    /**
     * パスワードの再設定のトークン
     * 結果が PASSWORD_RESET_READY のときだけ値を持つ
     */
    private final String passwordResetToken;

    /**
     * 再設定のトークンを持たない結果を作る
     *
     * @param result 確認の結果
     * @return DTO
     */
    public static VerifyEmailUseCaseDto of(EmailVerificationResult result) {
        return new VerifyEmailUseCaseDto(result, null);
    }

    /**
     * パスワードの再設定に進める結果を作る
     *
     * @param passwordResetToken パスワードの再設定のトークン
     * @return DTO
     */
    public static VerifyEmailUseCaseDto passwordResetReady(String passwordResetToken) {
        return new VerifyEmailUseCaseDto(EmailVerificationResult.PASSWORD_RESET_READY, passwordResetToken);
    }
}
