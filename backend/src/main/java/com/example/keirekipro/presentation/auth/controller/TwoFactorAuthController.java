package com.example.keirekipro.presentation.auth.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.auth.dto.TwoFactorAuthRequest;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.presentation.shared.utils.CookieUtil;
import com.example.keirekipro.usecase.auth.TwoFactorAuthVerifyUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;

/**
 * 二段階認証検証コントローラ
 */
@RestController
@RequestMapping("/api/auth/2fa")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class TwoFactorAuthController {

    private final TwoFactorAuthVerifyUseCase twoFactorAuthVerifyUseCase;

    private final JwtProvider jwtProvider;

    @Value("${cookie.secure:false}")
    private boolean isSecureCookie;

    /**
     * 二段階認証検証エンドポイント
     */
    @PostMapping("/verify")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "二段階認証の実行", description = "二段階認証コードの検証を行う")
    public void handle(@Valid @RequestBody TwoFactorAuthRequest request, HttpServletResponse response)
            throws Exception {

        if (request.getUserId() == null) {
            throw new AuthenticationCredentialsNotFoundException("不正なアクセスです。");
        }

        // ユースケース実行
        twoFactorAuthVerifyUseCase.execute(UUID.fromString(request.getUserId()), request.getCode());

        // JWT発行
        String accessToken = jwtProvider.createAccessToken(request.getUserId());
        String refreshToken = jwtProvider.createRefreshToken(request.getUserId());

        // レスポンスヘッダーにセット
        response.addHeader("Set-Cookie", CookieUtil.createHttpOnlyCookie("accessToken", accessToken, isSecureCookie));
        response.addHeader("Set-Cookie", CookieUtil.createHttpOnlyCookie("refreshToken", refreshToken, isSecureCookie));
    }
}
