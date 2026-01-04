package com.example.keirekipro.unit.usecase.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.HandleOidcCallbackUseCase;
import com.example.keirekipro.usecase.auth.OidcLoginUseCase;
import com.example.keirekipro.usecase.auth.dto.OidcLoginUseCaseDto;
import com.example.keirekipro.usecase.auth.oidc.OidcAuthorizationSession;
import com.example.keirekipro.usecase.auth.oidc.OidcCallbackError;
import com.example.keirekipro.usecase.auth.oidc.OidcCallbackResult;
import com.example.keirekipro.usecase.auth.oidc.OidcGateway;
import com.example.keirekipro.usecase.auth.oidc.OidcToken;
import com.example.keirekipro.usecase.auth.oidc.OidcUserInfo;
import com.example.keirekipro.usecase.auth.store.OidcAuthorizationSessionStore;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class HandleOidcCallbackUseCaseTest {

    @Mock
    private OidcGateway oidcGateway;

    @Mock
    private OidcAuthorizationSessionStore oidcAuthorizationSessionStore;

    @Mock
    private OidcLoginUseCase oidcLoginUseCase;

    @InjectMocks
    private HandleOidcCallbackUseCase handleOidcCallbackUseCase;

    private static final String PROVIDER = "google";
    private static final String CODE = "authorization-code";
    private static final String STATE = "random-state";
    private static final String CODE_VERIFIER = "code-verifier";
    private static final String REDIRECT_URI = "https://keirekipro.click/api/auth/oidc/callback";
    private static final String ACCESS_TOKEN = "access-token";

    @Test
    @DisplayName("errorパラメータがある場合、PROVIDER_ERROR_PARAMETERで失敗しstateは削除される")
    void test1() {
        OidcCallbackResult result = handleOidcCallbackUseCase.execute(CODE, STATE, "some-error", REDIRECT_URI);

        assertThat(result).isInstanceOf(OidcCallbackResult.Failure.class);
        assertThat(((OidcCallbackResult.Failure) result).getError())
                .isEqualTo(OidcCallbackError.PROVIDER_ERROR_PARAMETER);

        verify(oidcAuthorizationSessionStore).remove(STATE);
        verify(oidcAuthorizationSessionStore, never()).find(any());
        verify(oidcGateway, never()).exchangeToken(any(), any(), any(), any());
        verify(oidcGateway, never()).fetchUserInfo(any(), any());
        verify(oidcLoginUseCase, never()).execute(any());
    }

    @Test
    @DisplayName("必須パラメータが欠ける場合、MISSING_REQUIRED_PARAMETERで失敗しstateは削除される")
    void test2() {
        OidcCallbackResult result = handleOidcCallbackUseCase.execute(null, STATE, null, REDIRECT_URI);

        assertThat(result).isInstanceOf(OidcCallbackResult.Failure.class);
        assertThat(((OidcCallbackResult.Failure) result).getError())
                .isEqualTo(OidcCallbackError.MISSING_REQUIRED_PARAMETER);

        verify(oidcAuthorizationSessionStore).remove(STATE);
        verify(oidcAuthorizationSessionStore, never()).find(any());
        verify(oidcGateway, never()).exchangeToken(any(), any(), any(), any());
        verify(oidcGateway, never()).fetchUserInfo(any(), any());
        verify(oidcLoginUseCase, never()).execute(any());
    }

    @Test
    @DisplayName("stateが無効または期限切れの場合、INVALID_OR_EXPIRED_STATEで失敗しstateは削除される")
    void test3() {
        when(oidcAuthorizationSessionStore.find(STATE)).thenReturn(Optional.empty());

        OidcCallbackResult result = handleOidcCallbackUseCase.execute(CODE, STATE, null, REDIRECT_URI);

        assertThat(result).isInstanceOf(OidcCallbackResult.Failure.class);
        assertThat(((OidcCallbackResult.Failure) result).getError())
                .isEqualTo(OidcCallbackError.INVALID_OR_EXPIRED_STATE);

        verify(oidcAuthorizationSessionStore).find(STATE);
        verify(oidcAuthorizationSessionStore).remove(STATE);
        verify(oidcGateway, never()).exchangeToken(any(), any(), any(), any());
        verify(oidcGateway, never()).fetchUserInfo(any(), any());
        verify(oidcLoginUseCase, never()).execute(any());
    }

    @Test
    @DisplayName("トークン交換に失敗した場合、TOKEN_EXCHANGE_FAILEDで失敗しstateは削除される")
    void test4() {
        when(oidcAuthorizationSessionStore.find(STATE)).thenReturn(Optional.of(OidcAuthorizationSession.builder()
                .state(STATE)
                .provider(PROVIDER)
                .codeVerifier(CODE_VERIFIER)
                .build()));
        when(oidcGateway.exchangeToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER))
                .thenReturn(new OidcToken(null, "server_error", "error"));

        OidcCallbackResult result = handleOidcCallbackUseCase.execute(CODE, STATE, null, REDIRECT_URI);

        assertThat(result).isInstanceOf(OidcCallbackResult.Failure.class);
        assertThat(((OidcCallbackResult.Failure) result).getError())
                .isEqualTo(OidcCallbackError.TOKEN_EXCHANGE_FAILED);

        verify(oidcAuthorizationSessionStore).find(STATE);
        verify(oidcGateway).exchangeToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER);
        verify(oidcGateway, never()).fetchUserInfo(any(), any());
        verify(oidcLoginUseCase, never()).execute(any());
        verify(oidcAuthorizationSessionStore).remove(STATE);
    }

    @Test
    @DisplayName("ユーザー情報取得に失敗した場合、USERINFO_FETCH_FAILEDで失敗しstateは削除される")
    void test5() {
        when(oidcAuthorizationSessionStore.find(STATE)).thenReturn(Optional.of(OidcAuthorizationSession.builder()
                .state(STATE)
                .provider(PROVIDER)
                .codeVerifier(CODE_VERIFIER)
                .build()));
        when(oidcGateway.exchangeToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER))
                .thenReturn(new OidcToken(ACCESS_TOKEN, null, null));
        when(oidcGateway.fetchUserInfo(PROVIDER, ACCESS_TOKEN)).thenReturn(null);

        OidcCallbackResult result = handleOidcCallbackUseCase.execute(CODE, STATE, null, REDIRECT_URI);

        assertThat(result).isInstanceOf(OidcCallbackResult.Failure.class);
        assertThat(((OidcCallbackResult.Failure) result).getError())
                .isEqualTo(OidcCallbackError.USERINFO_FETCH_FAILED);

        verify(oidcAuthorizationSessionStore).find(STATE);
        verify(oidcGateway).exchangeToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER);
        verify(oidcGateway).fetchUserInfo(PROVIDER, ACCESS_TOKEN);
        verify(oidcLoginUseCase, never()).execute(any());
        verify(oidcAuthorizationSessionStore).remove(STATE);
    }

    @Test
    @DisplayName("ログイン処理が成功した場合、Success(userId)を返しstateは削除される")
    void test6() {
        UUID userId = UUID.randomUUID();
        Set<String> roles = Set.of("USER");

        when(oidcAuthorizationSessionStore.find(STATE)).thenReturn(Optional.of(OidcAuthorizationSession.builder()
                .state(STATE)
                .provider(PROVIDER)
                .codeVerifier(CODE_VERIFIER)
                .build()));
        when(oidcGateway.exchangeToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER))
                .thenReturn(new OidcToken(ACCESS_TOKEN, null, null));
        when(oidcGateway.fetchUserInfo(PROVIDER, ACCESS_TOKEN)).thenReturn(OidcUserInfo.builder()
                .providerType(PROVIDER)
                .providerUserId("provider-user-id")
                .email("test@keirekipro.click")
                .username("test-user")
                .build());
        when(oidcLoginUseCase.execute(any(OidcUserInfo.class))).thenReturn(OidcLoginUseCaseDto.builder()
                .id(userId)
                .username("test-user")
                .email("test@keirekipro.click")
                .providerType(PROVIDER)
                .roles(roles)
                .build());

        OidcCallbackResult result = handleOidcCallbackUseCase.execute(CODE, STATE, null, REDIRECT_URI);

        assertThat(result).isInstanceOf(OidcCallbackResult.Success.class);
        assertThat(((OidcCallbackResult.Success) result).getUserId()).isEqualTo(userId);
        assertThat(((OidcCallbackResult.Success) result).getRoles()).isEqualTo(roles);

        verify(oidcAuthorizationSessionStore).find(STATE);
        verify(oidcGateway).exchangeToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER);
        verify(oidcGateway).fetchUserInfo(PROVIDER, ACCESS_TOKEN);
        verify(oidcLoginUseCase).execute(any(OidcUserInfo.class));
        verify(oidcAuthorizationSessionStore).remove(STATE);
    }

    @Test
    @DisplayName("ログイン処理で例外が発生した場合、LOGIN_FAILEDで失敗しstateは削除される")
    void test7() {
        when(oidcAuthorizationSessionStore.find(STATE)).thenReturn(Optional.of(OidcAuthorizationSession.builder()
                .state(STATE)
                .provider(PROVIDER)
                .codeVerifier(CODE_VERIFIER)
                .build()));
        when(oidcGateway.exchangeToken(PROVIDER, CODE, REDIRECT_URI, CODE_VERIFIER))
                .thenReturn(new OidcToken(ACCESS_TOKEN, null, null));
        when(oidcGateway.fetchUserInfo(PROVIDER, ACCESS_TOKEN)).thenReturn(OidcUserInfo.builder()
                .providerType(PROVIDER)
                .providerUserId("provider-user-id")
                .email("test@keirekipro.click")
                .username("test-user")
                .build());
        when(oidcLoginUseCase.execute(any(OidcUserInfo.class))).thenThrow(new RuntimeException("login failed"));

        OidcCallbackResult result = handleOidcCallbackUseCase.execute(CODE, STATE, null, REDIRECT_URI);

        assertThat(result).isInstanceOf(OidcCallbackResult.Failure.class);
        assertThat(((OidcCallbackResult.Failure) result).getError())
                .isEqualTo(OidcCallbackError.LOGIN_FAILED);

        verify(oidcAuthorizationSessionStore).remove(STATE);
    }

    @Test
    @DisplayName("stateがnullの場合、finallyでremoveは呼ばれない")
    void test8() {
        OidcCallbackResult result = handleOidcCallbackUseCase.execute(CODE, null, "some-error", REDIRECT_URI);

        assertThat(result).isInstanceOf(OidcCallbackResult.Failure.class);
        assertThat(((OidcCallbackResult.Failure) result).getError())
                .isEqualTo(OidcCallbackError.PROVIDER_ERROR_PARAMETER);

        verify(oidcAuthorizationSessionStore, never()).remove(any());
    }
}
