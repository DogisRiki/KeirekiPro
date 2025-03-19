package com.example.keirekipro.unit.presentation.security.jwt;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Date;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.example.keirekipro.presentation.security.jwt.JwtAuthenticationFilter;
import com.example.keirekipro.presentation.security.jwt.JwtProperties;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import jakarta.servlet.FilterChain;
import jakarta.servlet.http.Cookie;

@ExtendWith(MockitoExtension.class)
class JwtAuthenticationFilterTest {

    @Mock
    private JwtProvider jwtProvider;

    @Mock
    private FilterChain filterChain;

    @InjectMocks
    private JwtAuthenticationFilter filter;

    @BeforeEach
    void setUp() {
        // SecurityContextHolderを毎回クリアする
        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("有効なJWTの場合、認証情報がSecurityContextに設定される")
    void test1() throws Exception {
        String validToken = "valid.jwt.token";
        Authentication authentication = mock(Authentication.class);

        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        mockRequest.setCookies(new Cookie("accessToken", validToken));

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();
        when(jwtProvider.getAuthentication(validToken)).thenReturn(authentication);

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // SecurityContextに認証情報が設定されている。
        assertThat(SecurityContextHolder.getContext().getAuthentication())
                .isEqualTo(authentication);
        // フィルタチェーンが呼び出されている。
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }

    @Test
    @DisplayName("無効なJWTの場合、認証情報がSecurityContextに設定されない")
    void test2() throws Exception {
        String invalidToken = "invalid.jwt.token";

        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        mockRequest.setCookies(new Cookie("accessToken", invalidToken));

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        // jwtProviderが無効なトークンで例外をスローするよう設定
        doThrow(new JWTVerificationException("Invalid token"))
                .when(jwtProvider).getAuthentication(invalidToken);

        // JWTVerificationExceptionがスローされる。
        assertThatThrownBy(() -> {
            filter.doFilter(mockRequest, mockResponse, filterChain);
        }).isInstanceOf(JWTVerificationException.class);

        // SecurityContextに認証情報が設定されていないことを確認
        assertThat(SecurityContextHolder.getContext().getAuthentication())
                .isNull();
        // フィルタチェーンが呼び出されていることを確認
    }

    @Test
    @DisplayName("JWTが存在しない場合、認証情報がSecurityContextに設定されない")
    void test3() throws Exception {
        // MockHttpServletRequest に Cookie を設定しない（JWTが存在しない状況を作成）
        MockHttpServletRequest mockRequest = new MockHttpServletRequest();

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // SecurityContext に認証情報が設定されていない。
        assertThat(SecurityContextHolder.getContext().getAuthentication())
                .isNull();
        // フィルタチェーンが呼び出されている。
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }

    @Test
    @DisplayName("有効期限切れのJWTの場合、認証情報がSecurityContextに設定されない")
    void test4() {
        JwtProperties jwtProperties = new JwtProperties();
        jwtProperties.setSecret("test-secret");
        // 期限切れトークン
        String expiredToken = JWT.create()
                .withSubject("user_id")
                .withIssuedAt(new Date(System.currentTimeMillis() - 1000 * 60 * 30)) // 30分前に発行
                .withExpiresAt(new Date(System.currentTimeMillis() - 1000 * 60)) // 1分前に有効期限切れ
                .sign(Algorithm.HMAC256(jwtProperties.getSecret()));

        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        mockRequest.setCookies(new Cookie("accessToken", expiredToken));

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        doThrow(new JWTVerificationException("Token expired"))
                .when(jwtProvider).getAuthentication(expiredToken);

        // JWTVerificationExceptionがスローされる。
        assertThatThrownBy(() -> {
            filter.doFilter(mockRequest, mockResponse, filterChain);
        }).isInstanceOf(JWTVerificationException.class);

        // SecurityContext に認証情報が設定されていない。
        assertThat(SecurityContextHolder.getContext().getAuthentication())
                .isNull();
    }

    @Test
    @DisplayName("複数のCookieが存在する場合、accessTokenのCookieが適切に選択される")
    void test5() throws Exception {
        String validToken = "valid.jwt.token";
        Authentication authentication = mock(Authentication.class);

        Cookie irrelevantCookie1 = new Cookie("sessionId", "random-session-value");
        Cookie irrelevantCookie2 = new Cookie("preferences", "dark-mode=true");
        Cookie accessTokenCookie = new Cookie("accessToken", validToken); // 正しいトークン

        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        mockRequest.setCookies(irrelevantCookie1, irrelevantCookie2, accessTokenCookie);

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        when(jwtProvider.getAuthentication(validToken)).thenReturn(authentication);

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // SecurityContext に認証情報が設定されている。
        assertThat(SecurityContextHolder.getContext().getAuthentication())
                .isEqualTo(authentication);
        // フィルタチェーンが呼び出されている。
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }
}
