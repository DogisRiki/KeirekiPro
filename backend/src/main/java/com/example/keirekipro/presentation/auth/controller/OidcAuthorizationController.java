package com.example.keirekipro.presentation.auth.controller;

import java.time.Duration;

import com.example.keirekipro.infrastructure.auth.oidc.OidcClient;
import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.presentation.auth.oidc.utils.OidcSecurityUtil;
import com.example.keirekipro.presentation.shared.utils.UrlUtil;

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
public class OidcAuthorizationController {

    private final OidcClient oidcClient;

    private final OidcSecurityUtil securityUtil;

    private final RedisClient redisClient;

    /**
     * OIDCプロバイダーへの認可リクエストを開始する
     *
     * @param provider       プロバイダー名
     * @param servletRequest HTTPサーブレットリクエスト
     * @return 認可URL
     */
    @GetMapping("/authorize")
    @ResponseStatus(HttpStatus.OK)
    public String authorize(@RequestParam String provider, HttpServletRequest servletRequest) {

        // PKCEパラメータを生成
        String codeVerifier = securityUtil.generateRandomToken();
        String codeChallenge = securityUtil.generateCodeChallenge(codeVerifier);

        // state値を生成
        String state = securityUtil.generateRandomToken();

        // コールバックURLの構築
        String baseUrl = UrlUtil.getBaseUrl(servletRequest);
        String redirectUri = baseUrl + "/api/auth/oidc/callback";

        // 認可URLの構築
        final String authorizationUrl = oidcClient.buildAuthorizationUrl(provider, redirectUri, state, codeChallenge);

        // 有効期限を10分に設定
        Duration expiration = Duration.ofMinutes(10);
        // コールバック時にどのプロバイダーの認証フローかを判断する為にプロバイダー名を保存
        redisClient.setValue("oidc:provider:" + state, provider, expiration);
        // stateを保存
        redisClient.setValue("oidc:state:" + state, state, expiration);
        // code_verifierを保存
        redisClient.setValue("oidc:code_verifier:" + state, codeVerifier, expiration);

        return authorizationUrl;
    }

}
