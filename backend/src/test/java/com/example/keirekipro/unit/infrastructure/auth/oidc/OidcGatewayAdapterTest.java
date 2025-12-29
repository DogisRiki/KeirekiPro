package com.example.keirekipro.unit.infrastructure.auth.oidc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.keirekipro.infrastructure.auth.oidc.OidcClient;
import com.example.keirekipro.infrastructure.auth.oidc.OidcGatewayAdapter;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcTokenResponse;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.usecase.auth.oidc.OidcToken;
import com.example.keirekipro.usecase.auth.oidc.OidcUserInfo;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class OidcGatewayAdapterTest {

    @Mock
    private OidcClient oidcClient;

    @InjectMocks
    private OidcGatewayAdapter oidcGatewayAdapter;

    private static final String PROVIDER = "google";
    private static final String REDIRECT_URI = "https://keirekipro.click/api/auth/oidc/callback";
    private static final String STATE = "random-state";
    private static final String CODE_CHALLENGE = "code-challenge";
    private static final String CODE = "authorization-code";
    private static final String CODE_VERIFIER = "code-verifier";
    private static final String ACCESS_TOKEN = "access-token";

    @Test
    @DisplayName("認可URLがOidcClientへ委譲され、結果が返却される")
    void test1() {
        // モックをセットアップ
        String expected = "https://accounts.google.com/o/oauth2/auth?client_id=xxx";
        when(oidcClient.buildAuthorizationUrl(PROVIDER, REDIRECT_URI, STATE, CODE_CHALLENGE)).thenReturn(expected);

        // 実行
        String result = oidcGatewayAdapter.buildAuthorizationUrl(PROVIDER, REDIRECT_URI, STATE, CODE_CHALLENGE);

        // 検証
        assertThat(result).isEqualTo(expected);
        verify(oidcClient).buildAuthorizationUrl(PROVIDER, REDIRECT_URI, STATE, CODE_CHALLENGE);
    }

    @Test
    @DisplayName("トークン交換がOidcClientへ委譲され、OidcTokenへ変換される")
    void test2() {
        // モックをセットアップ
        OidcTokenResponse tokenResponse = new OidcTokenResponse();
        tokenResponse.setAccessToken(ACCESS_TOKEN);
        tokenResponse.setError(null);
        tokenResponse.setErrorDescription(null);

        when(oidcClient.getToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER)).thenReturn(tokenResponse);

        // 実行
        OidcToken result = oidcGatewayAdapter.exchangeToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER);

        // 検証
        assertThat(result).isNotNull();
        assertThat(result.getAccessToken()).isEqualTo(ACCESS_TOKEN);
        assertThat(result.getError()).isNull();
        assertThat(result.getErrorDescription()).isNull();
        assertThat(result.hasError()).isFalse();

        verify(oidcClient).getToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER);
    }

    @Test
    @DisplayName("トークン交換の結果がnullの場合、エラーのOidcTokenが返却される")
    void test3() {
        // モックをセットアップ
        when(oidcClient.getToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER)).thenReturn(null);

        // 実行
        OidcToken result = oidcGatewayAdapter.exchangeToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER);

        // 検証
        assertThat(result).isNotNull();
        assertThat(result.getAccessToken()).isNull();
        assertThat(result.getError()).isEqualTo("server_error");
        assertThat(result.getErrorDescription()).isEqualTo("トークン取得処理中にエラーが発生しました");
        assertThat(result.hasError()).isTrue();

        verify(oidcClient).getToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER);
    }

    @Test
    @DisplayName("userinfo取得の結果がnullの場合、nullが返却される")
    void test4() {
        // モックをセットアップ
        when(oidcClient.getUserInfo(PROVIDER, ACCESS_TOKEN)).thenReturn(null);

        // 実行
        OidcUserInfo result = oidcGatewayAdapter.fetchUserInfo(PROVIDER, ACCESS_TOKEN);

        // 検証
        assertThat(result).isNull();
        verify(oidcClient).getUserInfo(PROVIDER, ACCESS_TOKEN);
    }

    @Test
    @DisplayName("userinfo取得がOidcClientへ委譲され、OidcUserInfoへ変換される")
    void test5() {
        // モックをセットアップ
        OidcUserInfoDto dto = OidcUserInfoDto.builder()
                .providerType(PROVIDER)
                .providerUserId("provider-user-id")
                .email("test@keirekipro.click")
                .username("test-user")
                .build();

        when(oidcClient.getUserInfo(PROVIDER, ACCESS_TOKEN)).thenReturn(dto);

        // 実行
        OidcUserInfo result = oidcGatewayAdapter.fetchUserInfo(PROVIDER, ACCESS_TOKEN);

        // 検証
        assertThat(result).isNotNull();
        assertThat(result.getProviderType()).isEqualTo(PROVIDER);
        assertThat(result.getProviderUserId()).isEqualTo("provider-user-id");
        assertThat(result.getEmail()).isEqualTo("test@keirekipro.click");
        assertThat(result.getUsername()).isEqualTo("test-user");

        verify(oidcClient).getUserInfo(PROVIDER, ACCESS_TOKEN);
    }
}
