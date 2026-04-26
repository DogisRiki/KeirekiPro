package com.example.keirekipro.unit.presentation.security.jwt;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.presentation.security.jwt.AuthCookieIssuer;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;

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

    @InjectMocks
    private AuthCookieIssuer authCookieIssuer;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final Set<String> ROLES = Set.of("USER");
    private static final String ACCESS_TOKEN = "mockAccessToken";
    private static final String REFRESH_TOKEN = "mockRefreshToken";

    @Test
    @DisplayName("アクセストークン・リフレッシュトークンが発行され、Set-Cookieヘッダにセットされる")
    void test1() {
        // モックをセットアップ
        when(jwtProvider.createAccessToken(USER_ID.toString(), ROLES)).thenReturn(ACCESS_TOKEN);
        when(jwtProvider.createRefreshToken(USER_ID.toString(), ROLES)).thenReturn(REFRESH_TOKEN);

        MockHttpServletResponse response = new MockHttpServletResponse();

        // 実行
        authCookieIssuer.issue(response, USER_ID, ROLES);

        // 検証
        List<String> cookies = response.getHeaders("Set-Cookie");
        assertThat(cookies).hasSize(2);
        assertThat(cookies).anyMatch(c -> c.contains("accessToken=" + ACCESS_TOKEN));
        assertThat(cookies).anyMatch(c -> c.contains("refreshToken=" + REFRESH_TOKEN));

        verify(jwtProvider).createAccessToken(USER_ID.toString(), ROLES);
        verify(jwtProvider).createRefreshToken(USER_ID.toString(), ROLES);
    }

    @Test
    @DisplayName("Cookieは HttpOnly・SameSite=Lax 属性が付与される")
    void test2() {
        // モックをセットアップ
        when(jwtProvider.createAccessToken(USER_ID.toString(), ROLES)).thenReturn(ACCESS_TOKEN);
        when(jwtProvider.createRefreshToken(USER_ID.toString(), ROLES)).thenReturn(REFRESH_TOKEN);

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
        when(jwtProvider.createAccessToken(USER_ID.toString(), ROLES)).thenReturn(ACCESS_TOKEN);
        when(jwtProvider.createRefreshToken(USER_ID.toString(), ROLES)).thenReturn(REFRESH_TOKEN);

        // isSecureCookieをtrueに設定
        ReflectionTestUtils.setField(authCookieIssuer, "isSecureCookie", true);

        MockHttpServletResponse response = new MockHttpServletResponse();

        // 実行
        authCookieIssuer.issue(response, USER_ID, ROLES);

        // 検証
        List<String> cookies = response.getHeaders("Set-Cookie");
        assertThat(cookies).allMatch(c -> c.contains("Secure"));
    }
}
