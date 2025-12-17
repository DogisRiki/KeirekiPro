package com.example.keirekipro.unit.presentation.security.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.keirekipro.presentation.security.config.CsrfCookieFilter;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.security.web.csrf.CsrfTokenRepository;

import jakarta.servlet.FilterChain;

@ExtendWith(MockitoExtension.class)
class CsrfCookieFilterTest {

    @Mock
    private CsrfTokenRepository csrfTokenRepository;

    @Mock
    private FilterChain filterChain;

    @InjectMocks
    private CsrfCookieFilter filter;

    @Test
    @DisplayName("リクエスト属性にCSRFトークンがある場合、トークン値にアクセスしてフィルタチェーンへ処理を移譲する")
    void test1() throws Exception {
        CsrfToken csrfToken = mock(CsrfToken.class);

        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        mockRequest.setAttribute(CsrfToken.class.getName(), csrfToken);

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // トークン値にアクセスしてCookie発行を促す
        verify(csrfToken).getToken();

        // Repositoryは触らない
        verify(csrfTokenRepository, org.mockito.Mockito.never()).loadToken(mockRequest);
        verify(csrfTokenRepository, org.mockito.Mockito.never()).generateToken(mockRequest);
        verify(csrfTokenRepository, org.mockito.Mockito.never()).saveToken(org.mockito.Mockito.any(),
                org.mockito.Mockito.any(), org.mockito.Mockito.any());

        // フィルタチェーンが呼び出される
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }

    @Test
    @DisplayName("リクエスト属性にCSRFトークンがなくRepositoryにも存在しない場合、新規生成して保存しリクエスト属性へ設定する")
    void test2() throws Exception {
        CsrfToken generated = mock(CsrfToken.class);
        when(generated.getParameterName()).thenReturn("_csrf");

        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        when(csrfTokenRepository.loadToken(mockRequest)).thenReturn(null);
        when(csrfTokenRepository.generateToken(mockRequest)).thenReturn(generated);

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // トークン生成・保存が行われる
        verify(csrfTokenRepository).loadToken(mockRequest);
        verify(csrfTokenRepository).generateToken(mockRequest);
        verify(csrfTokenRepository).saveToken(generated, mockRequest, mockResponse);

        // リクエスト属性へ設定される
        assertThat(mockRequest.getAttribute(CsrfToken.class.getName()))
                .isEqualTo(generated);
        assertThat(mockRequest.getAttribute("_csrf"))
                .isEqualTo(generated);

        // フィルタチェーンが呼び出される
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }

    @Test
    @DisplayName("リクエスト属性にCSRFトークンがなくRepositoryに存在する場合、リクエスト属性へ設定してフィルタチェーンへ処理を移譲する")
    void test3() throws Exception {
        CsrfToken existing = mock(CsrfToken.class);
        when(existing.getParameterName()).thenReturn("_csrf");

        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        when(csrfTokenRepository.loadToken(mockRequest)).thenReturn(existing);

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // 既存トークンがロードされる
        verify(csrfTokenRepository).loadToken(mockRequest);

        // 生成・保存は行われない
        verify(csrfTokenRepository, org.mockito.Mockito.never()).generateToken(mockRequest);
        verify(csrfTokenRepository, org.mockito.Mockito.never()).saveToken(org.mockito.Mockito.any(),
                org.mockito.Mockito.any(), org.mockito.Mockito.any());

        // リクエスト属性へ設定される
        assertThat(mockRequest.getAttribute(CsrfToken.class.getName()))
                .isEqualTo(existing);
        assertThat(mockRequest.getAttribute("_csrf"))
                .isEqualTo(existing);

        // フィルタチェーンが呼び出される
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }

    @Test
    @DisplayName("Preflight(OPTIONS)ではフィルター処理がスキップされる")
    void test4() throws Exception {
        MockHttpServletRequest mockRequest = new MockHttpServletRequest();
        mockRequest.setMethod("OPTIONS");
        mockRequest.setServletPath("/api/resumes/xxx/careers/yyy");

        MockHttpServletResponse mockResponse = new MockHttpServletResponse();

        // フィルタを実行
        filter.doFilter(mockRequest, mockResponse, filterChain);

        // Repositoryは触らない（doFilterInternalが通っていない）
        verify(csrfTokenRepository, org.mockito.Mockito.never()).loadToken(mockRequest);
        verify(csrfTokenRepository, org.mockito.Mockito.never()).generateToken(mockRequest);
        verify(csrfTokenRepository, org.mockito.Mockito.never()).saveToken(org.mockito.Mockito.any(),
                org.mockito.Mockito.any(), org.mockito.Mockito.any());

        // フィルタチェーンがそのまま呼ばれる
        verify(filterChain).doFilter(mockRequest, mockResponse);
    }
}
