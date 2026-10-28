package com.example.keirekipro.presentation.auth.dto;

import com.example.keirekipro.usecase.auth.dto.VerifyEmailUseCaseDto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 確認のリンクを受け付けたときのレスポンス
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class VerifyEmailResponse {

    /**
     * 確認の結果
     */
    private String result;

    /**
     * パスワードの再設定のトークン
     * 結果が PASSWORD_RESET_READY のときだけ値を持つ
     */
    private String passwordResetToken;

    /**
     * ユースケースDTOからレスポンスへの変換を行う
     *
     * @param dto ユースケースDTO
     * @return レスポンス
     */
    public static VerifyEmailResponse convertToResponse(VerifyEmailUseCaseDto dto) {
        return new VerifyEmailResponse(dto.getResult().name(), dto.getPasswordResetToken());
    }
}
