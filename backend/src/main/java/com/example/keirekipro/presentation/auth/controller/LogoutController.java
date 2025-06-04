package com.example.keirekipro.presentation.auth.controller;

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

import jakarta.servlet.http.HttpServletResponse;

/**
 * ログアウトコントローラー
 */
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class LogoutController {

    @Value("${cookie.secure:false}")
    private boolean isSecureCookie;

    /**
     * ログアウトエンドポイント
     */
    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "ログアウト", description = "アクセストークンおよびリフレッシュトークンを無効化し、セッションを終了する")
    public void handle(HttpServletResponse response) {
        response.addHeader("Set-Cookie", CookieUtil.deleteCookie("accessToken", isSecureCookie));
        response.addHeader("Set-Cookie", CookieUtil.deleteCookie("refreshToken", isSecureCookie));
    }
}
