package com.example.keirekipro.usecase.auth.oidc;

/**
 * OIDCコールバック処理の失敗理由
 */
public enum OidcCallbackError {

    /**
     * プロバイダーからerrorパラメータが返却された
     */
    PROVIDER_ERROR_PARAMETER,

    /**
     * 必須パラメータ（code/state）が不足している
     */
    MISSING_REQUIRED_PARAMETER,

    /**
     * stateが無効、または有効期限切れ
     */
    INVALID_OR_EXPIRED_STATE,

    /**
     * トークン交換に失敗した
     */
    TOKEN_EXCHANGE_FAILED,

    /**
     * userinfo取得に失敗した
     */
    USERINFO_FETCH_FAILED,

    /**
     * ログイン処理に失敗した
     */
    LOGIN_FAILED
}
