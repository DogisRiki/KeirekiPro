package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;

import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.StartOidcAuthorizationUseCase;
import com.example.keirekipro.usecase.auth.oidc.OidcGateway;
import com.example.keirekipro.usecase.auth.store.OidcAuthorizationSessionStore;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class StartOidcAuthorizationUseCaseTest {

    @Mock
    private OidcGateway oidcGateway;

    @Mock
    private OidcAuthorizationSessionStore oidcAuthorizationSessionStore;

    @Mock
    private SecurityUtil securityUtil;

    @InjectMocks
    private StartOidcAuthorizationUseCase startOidcAuthorizationUseCase;

    private static final String PROVIDER = "google";
    private static final String REDIRECT_URI = "https://keirekipro.click/api/auth/oidc/callback";

    @Test
    @DisplayName("OIDC認可フローを開始し、state/provider/code_verifierを保存して認可URLを返す")
    void test1() {
        // モックのセットアップ
        when(securityUtil.generateRandomToken()).thenReturn("code-verifier", "state");
        when(securityUtil.generateCodeChallenge("code-verifier")).thenReturn("code-challenge");
        when(oidcGateway.buildAuthorizationUrl(PROVIDER, REDIRECT_URI, "state", "code-challenge"))
                .thenReturn("https://accounts.google.com/o/oauth2/auth?...");

        // 実行
        String result = startOidcAuthorizationUseCase.execute(PROVIDER, REDIRECT_URI);

        // 検証
        assertThat(result).isEqualTo("https://accounts.google.com/o/oauth2/auth?...");

        // storeに渡された値をキャプチャして検証
        ArgumentCaptor<String> stateCaptor = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<String> providerCaptor = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<String> codeVerifierCaptor = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Duration> ttlCaptor = ArgumentCaptor.forClass(Duration.class);

        verify(oidcAuthorizationSessionStore).store(
                stateCaptor.capture(),
                providerCaptor.capture(),
                codeVerifierCaptor.capture(),
                ttlCaptor.capture());

        assertThat(stateCaptor.getValue()).isEqualTo("state");
        assertThat(providerCaptor.getValue()).isEqualTo(PROVIDER);
        assertThat(codeVerifierCaptor.getValue()).isEqualTo("code-verifier");
        assertThat(ttlCaptor.getValue()).isEqualTo(Duration.ofMinutes(10));

        verify(oidcGateway).buildAuthorizationUrl(eq(PROVIDER), eq(REDIRECT_URI), eq("state"), eq("code-challenge"));
    }
}
