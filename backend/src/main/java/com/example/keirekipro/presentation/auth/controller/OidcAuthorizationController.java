package com.example.keirekipro.presentation.auth.controller;

import com.example.keirekipro.presentation.shared.utils.UrlUtil;
import com.example.keirekipro.usecase.auth.StartOidcAuthorizationUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.HttpServletRequest;

/**
 * OIDCの認可フローを開始するコントローラー
 */
@RestController
@RequestMapping("/api/auth/oidc")
@RequiredArgsConstructor
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class OidcAuthorizationController {

    private final StartOidcAuthorizationUseCase startOidcAuthorizationUseCase;

    /**
     * OIDCプロバイダーへの認可リクエストを開始する
     *
     * @param provider       プロバイダー名
     * @param servletRequest HTTPサーブレットリクエスト
     * @return 認可URL
     */
    @GetMapping("/authorize")
    @ResponseStatus(HttpStatus.OK)
    @Operation(summary = "OIDC認可フローの開始", description = "OIDCの認可フローを開始し、認可URLを生成する")
    public String handle(@RequestParam("provider") String provider, HttpServletRequest servletRequest) {

        // コールバックURLの構築
        String baseUrl = UrlUtil.getBaseUrl(servletRequest);
        String redirectUri = baseUrl + "/api/auth/oidc/callback";

        // 認可URLの構築
        return startOidcAuthorizationUseCase.execute(provider, redirectUri);
    }
}
