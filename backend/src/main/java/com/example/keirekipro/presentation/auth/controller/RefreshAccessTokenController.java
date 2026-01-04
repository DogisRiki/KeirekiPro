package com.example.keirekipro.presentation.auth.controller;

import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

import com.auth0.jwt.exceptions.JWTVerificationException;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.presentation.shared.utils.CookieUtil;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
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

        // リフレッシュトークンから認証情報を取得
        Authentication auth = jwtProvider.getAuthentication(refreshToken.get());
        String userId = (String) auth.getPrincipal();

        // 現在の権限情報からロール名を抽出
        Set<String> roles = auth.getAuthorities().stream()
                .map(a -> a.getAuthority().replace("ROLE_", ""))
                .collect(Collectors.toSet());

        // 新しいアクセストークンを生成
        String newAccessToken = jwtProvider.createAccessToken(userId, roles);

        // レスポンスヘッダーにセット
        response.addHeader("Set-Cookie",
                CookieUtil.createHttpOnlyCookie("accessToken", newAccessToken, isSecureCookie));
    }
}
