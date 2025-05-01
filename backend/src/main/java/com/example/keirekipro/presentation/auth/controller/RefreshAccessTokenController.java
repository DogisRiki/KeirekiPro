package com.example.keirekipro.presentation.auth.controller;

import java.util.Optional;

import com.auth0.jwt.exceptions.JWTVerificationException;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.presentation.shared.utils.CookieUtil;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * リフレッシュアクセストークンコントローラー
 */
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class RefreshAccessTokenController {

    private final JwtProvider jwtProvider;

    @Value("${cookie.secure:false}")
    private boolean isSecureCookie;

    /**
     * リフレッシュトークンによるアクセストークン再発行エンドポイント
     */
    @PostMapping("/token/refresh")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "アクセストークンの再発行", description = "リフレッシュトークンによってアクセストークンを再発行する")
    public void handle(HttpServletRequest request, HttpServletResponse response) {

        // Cookieからリフレッシュトークンを取得
        Optional<String> refreshToken = CookieUtil.getCookieValue(request, "refreshToken");

        // リフレッシュトークンが存在しない場合、401とする
        if (refreshToken.isEmpty()) {
            throw new JWTVerificationException("リフレッシュトークンが存在しません。");
        }

        // リフレッシュトークンの検証とユーザーIDの取得
        String userId = (String) jwtProvider.getAuthentication(refreshToken.get()).getPrincipal();

        // 新しいアクセストークンを生成
        String newAccessToken = jwtProvider.createAccessToken(userId);

        // レスポンスヘッダーにセット
        response.addHeader("Set-Cookie",
                CookieUtil.createHttpOnlyCookie("accessToken", newAccessToken, isSecureCookie));
    }
}
