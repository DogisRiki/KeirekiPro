package com.example.keirekipro.unit.presentation.security.jwt;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.auth0.jwt.exceptions.JWTVerificationException;
import com.example.keirekipro.presentation.security.jwt.JwtAuthenticationFilter;
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

        // SecurityContextに認証情報が設定される
        assertThat(SecurityContextHolder.getContext().getAuthentication())
                .isEqualTo(authentication);
        // フィルタチェーンが呼び出される
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }

    @Test
    @DisplayName("無効なJWTの場合、401にせず未認証として継続し、accessToken Cookieを失効させる")
    void test2() throws Exception {
        String invalidToken = "invalid.jwt.token";

        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        mockRequest.setCookies(new Cookie("accessToken", invalidToken));

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        // jwtProviderが無効なトークンで例外をスローするよう設定
        doThrow(new JWTVerificationException("Invalid token"))
                .when(jwtProvider).getAuthentication(invalidToken);

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // 変更後は sendError しないため、ステータスはデフォルト(200)のまま
        assertThat(mockResponse.getStatus()).isEqualTo(200);

        // SecurityContextに認証情報が設定されない（未認証扱い）
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();

        // 変更後はフィルタチェーンが継続される
        verify(filterChain).doFilter(mockRequest, mockResponse);

        // 不正トークンCookieを失効させていることを確認
        Cookie expired = findCookie(mockResponse, "accessToken");
        assertThat(expired).isNotNull();
        assertThat(expired.getMaxAge()).isEqualTo(0);
        assertThat(expired.getPath()).isEqualTo("/");
    }

    @Test
    @DisplayName("JWTが存在しない場合、認証情報がSecurityContextに設定されない")
    void test3() throws Exception {
        // MockHttpServletRequest に Cookie を設定しない（JWTが存在しない状況を作成）
        MockHttpServletRequest mockRequest = new MockHttpServletRequest();

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // SecurityContext に認証情報が設定されない
        assertThat(SecurityContextHolder.getContext().getAuthentication())
                .isNull();
        // フィルタチェーンが呼び出される
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }

    @Test
    @DisplayName("有効期限切れ等でJWT検証に失敗した場合、401にせず未認証として継続し、accessToken Cookieを失効させる")
    void test4() throws Exception {
        // ※変更後の挙動では、期限切れ/不正JWTでも sendError せず、未認証として続行する

        // 期限切れ扱いのトークン文字列（中身の生成は不要。jwtProvider側が例外を投げる想定）
        String expiredToken = "expired.jwt.token";

        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        mockRequest.setCookies(new Cookie("accessToken", expiredToken));

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        // jwtProvider がトークンの期限切れで例外をスロー
        doThrow(new JWTVerificationException("Token expired"))
                .when(jwtProvider).getAuthentication(expiredToken);

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // 変更後は sendError しないため、ステータスはデフォルト(200)のまま
        assertThat(mockResponse.getStatus()).isEqualTo(200);

        // SecurityContextに認証情報が設定されない（未認証扱い）
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();

        // 変更後はフィルタチェーンが継続される
        verify(filterChain).doFilter(mockRequest, mockResponse);

        // 不正トークンCookieを失効させていることを確認
        Cookie expired = findCookie(mockResponse, "accessToken");
        assertThat(expired).isNotNull();
        assertThat(expired.getMaxAge()).isEqualTo(0);
        assertThat(expired.getPath()).isEqualTo("/");
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

        // SecurityContext に認証情報が設定される
        assertThat(SecurityContextHolder.getContext().getAuthentication())
                .isEqualTo(authentication);
        // フィルタチェーンが呼び出される
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }

    @Test
    @DisplayName("shouldNotFilterに該当するパスではフィルター処理がスキップされる")
    void test6() throws Exception {
        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        mockRequest.setServletPath("/api/auth/token/refresh");

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // SecurityContextに認証情報が設定されていない（スキップされた）
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();

        // フィルタチェーンがそのまま呼ばれる（doFilterInternalが通っていない）
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }

    @Test
    @DisplayName("Preflight(OPTIONS)ではJWT認証がスキップされる")
    void test7() throws Exception {
        String validToken = "valid.jwt.token";

        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        mockRequest.setMethod("OPTIONS");
        mockRequest.setServletPath("/api/resumes/xxx/careers/yyy");
        mockRequest.setCookies(new Cookie("accessToken", validToken));

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // SecurityContextに認証情報が設定されない（スキップされた）
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();

        // jwtProviderが呼ばれない（doFilterInternalが通っていない）
        verify(jwtProvider, org.mockito.Mockito.never()).getAuthentication(validToken);

        // フィルタチェーンがそのまま呼ばれる
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }

    @Test
    @DisplayName("無効なJWTが来た場合、既存のSecurityContextの認証情報もクリアされる")
    void test8() throws Exception {
        // 既に認証済みの状態を作る
        Authentication existingAuth = mock(Authentication.class);
        SecurityContextHolder.getContext().setAuthentication(existingAuth);
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isEqualTo(existingAuth);

        String invalidToken = "invalid.jwt.token";

        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        mockRequest.setCookies(new Cookie("accessToken", invalidToken));

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        // jwtProviderが無効なトークンで例外をスローするよう設定
        doThrow(new JWTVerificationException("Invalid token"))
                .when(jwtProvider).getAuthentication(invalidToken);

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // 変更後は SecurityContextHolder.clearContext() される
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();

        // フィルタチェーンが継続される
        verify(filterChain).doFilter(mockRequest, mockResponse);

        // 不正トークンCookieを失効させていることを確認
        Cookie expired = findCookie(mockResponse, "accessToken");
        assertThat(expired).isNotNull();
        assertThat(expired.getMaxAge()).isEqualTo(0);
        assertThat(expired.getPath()).isEqualTo("/");
    }

    /**
     * MockHttpServletResponseから指定名のCookieを検索する
     *
     * @param response Mockレスポンス
     * @param name     Cookie名
     * @return 見つかればCookie、なければnull
     */
    private static Cookie findCookie(MockHttpServletResponse response, String name) {
        for (Cookie c : response.getCookies()) {
            if (name.equals(c.getName())) {
                return c;
            }
        }
        return null;
    }
}
