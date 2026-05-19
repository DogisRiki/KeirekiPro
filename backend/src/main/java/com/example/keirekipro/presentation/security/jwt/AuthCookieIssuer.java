package com.example.keirekipro.presentation.security.jwt;

import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.presentation.shared.utils.CookieUtil;
import com.example.keirekipro.usecase.auth.store.RefreshTokenStore;
import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.HttpServletResponse;

/**
 * 認証成立後にアクセストークン・リフレッシュトークンを発行し、Cookieにセットするコンポーネント
 */
@Component
@RequiredArgsConstructor
public class AuthCookieIssuer {

    private final JwtProvider jwtProvider;

    private final RefreshTokenStore refreshTokenStore;

    private final UserTokenVersionStore userTokenVersionStore;

    @Value("${cookie.secure:false}")
    private boolean isSecureCookie;

    /**
     * アクセストークン・リフレッシュトークンを発行し、HttpOnly Cookieにセットする
     *
     * @param response HTTPレスポンス
     * @param userId ユーザーID
     * @param roles ロール
     */
    public void issue(HttpServletResponse response, UUID userId, Set<String> roles) {

        long tokenVersion = userTokenVersionStore.get(userId);

        String accessToken = jwtProvider.createAccessToken(userId.toString(), roles);
        String refreshToken = refreshTokenStore.issue(userId, roles, tokenVersion);

        response.addHeader("Set-Cookie", CookieUtil.createHttpOnlyCookie("accessToken", accessToken, isSecureCookie));
        response.addHeader("Set-Cookie", CookieUtil.createHttpOnlyCookie("refreshToken", refreshToken, isSecureCookie));
    }
}
