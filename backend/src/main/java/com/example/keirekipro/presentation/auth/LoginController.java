package com.example.keirekipro.presentation.auth;

import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.usecase.auth.LoginUseCase;
import com.example.keirekipro.usecase.auth.LoginUseCaseDto;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseCookie;
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
        response.addHeader("Set-Cookie", createHttpOnlyCookie("accessToken", accessToken));
        response.addHeader("Set-Cookie", createHttpOnlyCookie("refreshToken", refreshToken));
    }

    /**
     * HttpOnlyクッキーを作成する
     *
     * @param name  キー
     * @param value 値
     * @return HttpCookie文字列
     */
    private String createHttpOnlyCookie(String name, String value) {
        return ResponseCookie.from(name, value)
                .httpOnly(true)
                .secure(isSecureCookie)
                .sameSite("Lax")
                .path("/")
                .build()
                .toString();
    }
}
