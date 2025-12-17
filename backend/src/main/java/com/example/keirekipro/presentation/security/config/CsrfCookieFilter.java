package com.example.keirekipro.presentation.security.config;

import java.io.IOException;

import org.springframework.lang.NonNull;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.security.web.csrf.CsrfTokenRepository;
import org.springframework.web.filter.OncePerRequestFilter;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * CSRFトークン(XSRF-TOKEN)を確実にCookieへ載せるフィルタ
 * Spring Security6ではCSRFトークンのロードが遅延されるため、そのままだとXSRF-TOKENが払い出されないケースが起きる。
 */
@RequiredArgsConstructor
public class CsrfCookieFilter extends OncePerRequestFilter {

    private final CsrfTokenRepository csrfTokenRepository;

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain) throws ServletException, IOException {

        // CsrfFilterが作った(または遅延ロードされた)トークンがあれば取得
        CsrfToken csrfToken = (CsrfToken) request.getAttribute(CsrfToken.class.getName());

        if (csrfToken == null) {
            // CsrfFilterがトークンを触らないパス（例: /api/auth/**）ではここで補完する
            CsrfToken existing = csrfTokenRepository.loadToken(request);
            if (existing == null) {
                CsrfToken generated = csrfTokenRepository.generateToken(request);
                csrfTokenRepository.saveToken(generated, request, response);
                request.setAttribute(CsrfToken.class.getName(), generated);
                request.setAttribute(generated.getParameterName(), generated);
            } else {
                request.setAttribute(CsrfToken.class.getName(), existing);
                request.setAttribute(existing.getParameterName(), existing);
            }
        } else {
            // DeferredCsrfToken等の遅延実体でも、ここで値にアクセスしてCookie発行を促す
            csrfToken.getToken();
        }

        filterChain.doFilter(request, response);
    }

    @Override
    protected boolean shouldNotFilter(@NonNull HttpServletRequest request) {
        // PreflightではCookie発行を行わない（無駄なSet-Cookieを避ける）
        return "OPTIONS".equalsIgnoreCase(request.getMethod());
    }
}
