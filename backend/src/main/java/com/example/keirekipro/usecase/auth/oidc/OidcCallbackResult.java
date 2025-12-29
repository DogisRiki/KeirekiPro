package com.example.keirekipro.usecase.auth.oidc;

import java.util.UUID;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * OIDCコールバック処理結果
 */
public interface OidcCallbackResult {

    /**
     * 成功
     */
    @RequiredArgsConstructor
    @Getter
    class Success implements OidcCallbackResult {

        /**
         * ユーザーID
         */
        private final UUID userId;
    }

    /**
     * 失敗
     */
    @RequiredArgsConstructor
    @Getter
    class Failure implements OidcCallbackResult {

        /**
         * エラー種別
         */
        private final OidcCallbackError error;
    }
}
