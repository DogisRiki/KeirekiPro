package com.example.keirekipro.usecase.auth.oidc;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * OIDCトークン取得結果
 */
@RequiredArgsConstructor
@Getter
public class OidcToken {

    /**
     * アクセストークン
     */
    private final String accessToken;

    /**
     * エラーコード（エラー時のみ）
     */
    private final String error;

    /**
     * エラー詳細（エラー時のみ）
     */
    private final String errorDescription;

    /**
     * トークンがエラーを含むかどうかを判定する
     *
     * @return エラーが含まれている場合はtrue
     */
    public boolean hasError() {
        return error != null && !error.isEmpty();
    }
}
