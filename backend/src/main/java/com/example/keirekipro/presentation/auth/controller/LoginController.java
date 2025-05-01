package com.example.keirekipro.presentation.auth.controller;

import com.example.keirekipro.presentation.auth.dto.LoginRequest;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.presentation.shared.utils.CookieUtil;
import com.example.keirekipro.usecase.auth.LoginUseCase;
import com.example.keirekipro.usecase.auth.TwoFactorAuthIssueUseCase;
import com.example.keirekipro.usecase.auth.dto.LoginUseCaseDto;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;

/**
 * ログインコントローラー
 */
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class LoginController {

    private final LoginUseCase loginUseCase;

    private final TwoFactorAuthIssueUseCase twoFactorAuthIssueUseCase;

    private final JwtProvider jwtProvider;

    @Value("${cookie.secure:false}")
    private boolean isSecureCookie;

    /**
     * ログインエンドポイント
     */
    @PostMapping("/login")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "ログイン", description = "メールアドレスとパスワードによるログイン")
    public void handle(@Valid @RequestBody LoginRequest request, HttpServletResponse response) {

        // ユースケース実行
        LoginUseCaseDto user = loginUseCase.execute(request);

        // ユーザーの二段階認証設定をチェックし、有効なら二段階認証発行ユースケースを実行
        if (user.isTwoFactorAuthEnabled()) {
            twoFactorAuthIssueUseCase.execute(user.getId(), user.getEmail());
            return;
        }

        // JWT発行
        String accessToken = jwtProvider.createAccessToken(user.getId().toString());
        String refreshToken = jwtProvider.createRefreshToken(user.getId().toString());

        // レスポンスヘッダーにセット
        response.addHeader("Set-Cookie", CookieUtil.createHttpOnlyCookie("accessToken", accessToken, isSecureCookie));
        response.addHeader("Set-Cookie", CookieUtil.createHttpOnlyCookie("refreshToken", refreshToken, isSecureCookie));
    }
}
