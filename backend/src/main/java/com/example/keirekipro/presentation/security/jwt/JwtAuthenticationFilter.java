package com.example.keirekipro.presentation.security.jwt;

import java.io.IOException;
import java.util.Arrays;
import java.util.Optional;

import com.auth0.jwt.exceptions.JWTVerificationException;

import org.springframework.lang.NonNull;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * 認証フィルター
 */
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    /**
     * JWTプロバイダー
     */
    private final JwtProvider jwtProvider;

    /**
     * クッキーの名前
     */
    private static final String COOKIE_NAME = "accessToken";

    /**
     * JWTを検証してSecurityContextに認証情報を設定する
     */
    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain)
            throws ServletException, IOException {

        // CookieからJWTを取得
        Optional<String> jwt = getJwtFromCookies(request);

        try {
            jwt.ifPresent(tok -> {
                // トークンの検証と認証情報の取得
                Authentication auth = jwtProvider.getAuthentication(tok);
                // SecurityContextに認証情報を設定
                SecurityContextHolder.getContext().setAuthentication(auth);
            });
        } catch (JWTVerificationException e) {
            // 不正JWTは「未認証」として扱う（公開エンドポイントを巻き込んで401にしない）
            SecurityContextHolder.clearContext();

            // 不正トークンCookieを失効させて再発を防ぐ
            Cookie expired = new Cookie(COOKIE_NAME, "");
            expired.setPath("/");
            expired.setMaxAge(0);
            response.addCookie(expired);
        }
        // 次のフィルタへ処理を移譲
        filterChain.doFilter(request, response);
    }

    /**
     * CookieからJWTを取得する
     *
     * @param request HTTPリクエスト
     * @return JWT文字列
     */
    private Optional<String> getJwtFromCookies(HttpServletRequest request) {
        if (request.getCookies() == null) {
            return Optional.empty();
        }
        return Arrays.stream(request.getCookies())
                .filter(cookie -> COOKIE_NAME.equals(cookie.getName()))
                .map(Cookie::getValue)
                .findFirst();
    }

    @Override
    protected boolean shouldNotFilter(@NonNull HttpServletRequest request) throws ServletException {
        String path = request.getServletPath();

        // Preflight(OPTIONS)ではJWT認証をスキップ
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            return true;
        }

        // /api/auth/ 以下のエンドポイントではフィルタをスキップする
        return path.startsWith("/api/auth");
    }
}
