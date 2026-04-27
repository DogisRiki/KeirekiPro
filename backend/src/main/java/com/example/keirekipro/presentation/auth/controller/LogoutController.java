package com.example.keirekipro.presentation.auth.controller;

import java.util.Optional;

import com.example.keirekipro.presentation.shared.utils.CookieUtil;
import com.example.keirekipro.usecase.auth.store.RefreshTokenStore;

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
 * ログアウトコントローラー
 */
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class LogoutController {

    private final RefreshTokenStore refreshTokenStore;

    @Value("${cookie.secure:false}")
    private boolean isSecureCookie;

    /**
     * ログアウトエンドポイント
     */
    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "ログアウト", description = "アクセストークンおよびリフレッシュトークンを無効化し、セッションを終了する")
    public void handle(HttpServletRequest request, HttpServletResponse response) {

        // Cookieのリフレッシュトークンが存在すれば削除
        Optional<String> refreshToken = CookieUtil.getCookieValue(request, "refreshToken");
        refreshToken.ifPresent(refreshTokenStore::remove);

        response.addHeader("Set-Cookie", CookieUtil.deleteCookie("accessToken", isSecureCookie));
        response.addHeader("Set-Cookie", CookieUtil.deleteCookie("refreshToken", isSecureCookie));
    }
}
