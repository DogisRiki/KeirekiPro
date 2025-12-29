package com.example.keirekipro.infrastructure.auth.oidc;

import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcTokenResponse;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.usecase.auth.oidc.OidcGateway;
import com.example.keirekipro.usecase.auth.oidc.OidcToken;
import com.example.keirekipro.usecase.auth.oidc.OidcUserInfo;

import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * OidcClientをユースケース層のOidcGatewayとして提供するアダプタ
 */
@Component
@RequiredArgsConstructor
public class OidcGatewayAdapter implements OidcGateway {

    private final OidcClient oidcClient;

    @Override
    public String buildAuthorizationUrl(String provider, String redirectUri, String state, String codeChallenge) {
        return oidcClient.buildAuthorizationUrl(provider, redirectUri, state, codeChallenge);
    }

    @Override
    public OidcToken exchangeToken(String provider, String code, String redirectUri, String codeVerifier) {
        OidcTokenResponse res = oidcClient.getToken(provider, code, redirectUri, codeVerifier);
        if (res == null) {
            return new OidcToken(null, "server_error", "トークン取得処理中にエラーが発生しました");
        }
        return new OidcToken(res.getAccessToken(), res.getError(), res.getErrorDescription());
    }

    @Override
    public OidcUserInfo fetchUserInfo(String provider, String accessToken) {
        OidcUserInfoDto dto = oidcClient.getUserInfo(provider, accessToken);
        if (dto == null) {
            return null;
        }
        return OidcUserInfo.builder()
                .providerType(dto.getProviderType())
                .providerUserId(dto.getProviderUserId())
                .email(dto.getEmail())
                .username(dto.getUsername())
                .build();
    }
}
