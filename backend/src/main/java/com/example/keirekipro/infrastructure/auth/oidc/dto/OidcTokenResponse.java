package com.example.keirekipro.infrastructure.auth.oidc.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

import lombok.Data;

/**
 * OIDCプロバイダーのトークンエンドポイントからのレスポンスを表現するDTO
 */
@Data
public class OidcTokenResponse {

    /**
     * アクセストークン
     */
    @JsonProperty("access_token")
    private String accessToken;

    /**
     * トークンタイプ（通常は "Bearer" が設定される）
     */
    @JsonProperty("token_type")
    private String tokenType;

    /**
     * アクセストークンの有効期間（秒）
     * ※プロバイダーによっては含まれない場合もある
     */
    @JsonProperty("expires_in")
    private Integer expiresIn;

    /**
     * IDトークン
     */
    @JsonProperty("id_token")
    private String idToken;

    /**
     * リフレッシュトークン
     */
    @JsonProperty("refresh_token")
    private String refreshToken;

    /**
     * スコープ
     */
    private String scope;

    /**
     * エラーコード（エラー時のみ）
     */
    private String error;

    /**
     * エラー詳細（エラー時のみ）
     */
    @JsonProperty("error_description")
    private String errorDescription;

    /**
     * トークンレスポンスがエラーを含むかどうかを判定する。
     *
     * @return エラーが含まれている場合はtrue
     */
    public boolean hasError() {
        return error != null && !error.isEmpty();
    }
}
