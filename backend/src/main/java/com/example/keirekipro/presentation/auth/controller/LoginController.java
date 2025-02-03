package com.example.keirekipro.presentation.auth.controller;

import com.example.keirekipro.presentation.auth.dto.LoginRequest;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.presentation.shared.utils.CookieUtil;
import com.example.keirekipro.usecase.auth.LoginUseCase;
import com.example.keirekipro.usecase.auth.dto.LoginUseCaseDto;

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
public class LoginController {

    private final LoginUseCase loginUseCase;

    private final JwtProvider jwtProvider;

    @Value("${cookie.secure:false}")
    private boolean isSecureCookie;

    /**
     * ログインエンドポイント
     */
    @PostMapping("/login")
    @ResponseStatus(HttpStatus.OK)
    public void login(@Valid @RequestBody LoginRequest request, HttpServletResponse response) {

        // ユースケース実行
        LoginUseCaseDto user = loginUseCase.execute(request);

        // JWT発行
        String accessToken = jwtProvider.createAccessToken(user.getId().toString());
        String refreshToken = jwtProvider.createRefreshToken(user.getId().toString());

        // レスポンスヘッダーにセット
        response.addHeader("Set-Cookie", CookieUtil.createHttpOnlyCookie("accessToken", accessToken, isSecureCookie));
        response.addHeader("Set-Cookie", CookieUtil.createHttpOnlyCookie("refreshToken", refreshToken, isSecureCookie));
    }
}
