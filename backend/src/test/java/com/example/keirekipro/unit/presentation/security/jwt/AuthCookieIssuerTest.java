package com.example.keirekipro.unit.presentation.security.jwt;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.presentation.security.jwt.AuthCookieIssuer;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.usecase.auth.store.RefreshTokenStore;
import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class AuthCookieIssuerTest {

    @Mock
    private JwtProvider jwtProvider;

    @Mock
    private RefreshTokenStore refreshTokenStore;

    @Mock
    private UserTokenVersionStore userTokenVersionStore;

    @InjectMocks
    private AuthCookieIssuer authCookieIssuer;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final Set<String> ROLES = Set.of("USER");
    private static final String ACCESS_TOKEN = "mockAccessToken";
    private static final String REFRESH_TOKEN = "mockRefreshToken";
    private static final long TOKEN_VERSION = 0L;

    @Test
    @DisplayName("アクセストークンとリフレッシュトークンが発行され、Set-Cookieヘッダにセットされる")
    void test1() {
        // モックをセットアップ
        when(userTokenVersionStore.get(USER_ID)).thenReturn(TOKEN_VERSION);
        when(jwtProvider.createAccessToken(USER_ID.toString(), ROLES)).thenReturn(ACCESS_TOKEN);
        when(refreshTokenStore.issue(USER_ID, ROLES, TOKEN_VERSION)).thenReturn(REFRESH_TOKEN);

        MockHttpServletResponse response = new MockHttpServletResponse();

        // 実行
        authCookieIssuer.issue(response, USER_ID, ROLES);

        // 検証
        List<String> cookies = response.getHeaders("Set-Cookie");
        assertThat(cookies).hasSize(2);
        assertThat(cookies).anyMatch(c -> c.contains("accessToken=" + ACCESS_TOKEN));
        assertThat(cookies).anyMatch(c -> c.contains("refreshToken=" + REFRESH_TOKEN));

        verify(userTokenVersionStore).get(USER_ID);
        verify(jwtProvider).createAccessToken(USER_ID.toString(), ROLES);
        verify(refreshTokenStore).issue(USER_ID, ROLES, TOKEN_VERSION);
    }

    @Test
    @DisplayName("CookieはHttpOnly・SameSite=Lax属性が付与される")
    void test2() {
        // モックをセットアップ
        when(userTokenVersionStore.get(USER_ID)).thenReturn(TOKEN_VERSION);
        when(jwtProvider.createAccessToken(USER_ID.toString(), ROLES)).thenReturn(ACCESS_TOKEN);
        when(refreshTokenStore.issue(USER_ID, ROLES, TOKEN_VERSION)).thenReturn(REFRESH_TOKEN);

        MockHttpServletResponse response = new MockHttpServletResponse();

        // 実行
        authCookieIssuer.issue(response, USER_ID, ROLES);

        // 検証
        List<String> cookies = response.getHeaders("Set-Cookie");
        assertThat(cookies).allMatch(c -> c.contains("HttpOnly"));
        assertThat(cookies).allMatch(c -> c.contains("SameSite=Lax"));
    }

    @Test
    @DisplayName("isSecureCookieがtrueの場合、Secure属性が付与される")
    void test3() {
        // モックをセットアップ
        when(userTokenVersionStore.get(USER_ID)).thenReturn(TOKEN_VERSION);
        when(jwtProvider.createAccessToken(USER_ID.toString(), ROLES)).thenReturn(ACCESS_TOKEN);
        when(refreshTokenStore.issue(USER_ID, ROLES, TOKEN_VERSION)).thenReturn(REFRESH_TOKEN);

        ReflectionTestUtils.setField(authCookieIssuer, "isSecureCookie", true);

        MockHttpServletResponse response = new MockHttpServletResponse();

        // 実行
        authCookieIssuer.issue(response, USER_ID, ROLES);

        // 検証
        List<String> cookies = response.getHeaders("Set-Cookie");
        assertThat(cookies).allMatch(c -> c.contains("Secure"));
    }
}
