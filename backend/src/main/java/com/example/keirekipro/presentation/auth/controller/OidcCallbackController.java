package com.example.keirekipro.presentation.auth.controller;

import java.io.IOException;
import java.util.Optional;

import com.example.keirekipro.infrastructure.auth.oidc.OidcClient;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcTokenResponse;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.presentation.shared.utils.CookieUtil;
import com.example.keirekipro.presentation.shared.utils.UrlUtil;
import com.example.keirekipro.usecase.auth.OidcLoginUseCase;
import com.example.keirekipro.usecase.auth.dto.OidcLoginUseCaseDto;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * OIDCコールバック処理を行うコントローラー
 */
@RestController
@RequestMapping("/api/auth/oidc")
@RequiredArgsConstructor
public class OidcCallbackController {

    private final OidcClient oidcClient;

    private final JwtProvider jwtProvider;

    private final RedisClient redisClient;

    private final OidcLoginUseCase oidcLoginUseCase;

    @Value("${cookie.secure:false}")
    private boolean isSecureCookie;

    /**
     * フロントエンドのリダイレクトURL（認証成功後にリダイレクトする）
     */
    private static final String FRONTEND_REDIRECT_URL = "/resume/list";

    /**
     * エラー時のリダイレクトURL
     */
    private static final String ERROR_REDIRECT_URL = "/login";

    /**
     * OIDCプロバイダーからのコールバックを処理する
     * 認可コードを受け取り、アクセストークン取得・ユーザー情報取得・ログイン処理を行う
     *
     * @param code     認可コード
     * @param state    state値
     * @param error    エラーメッセージ（エラー発生時のみ）
     * @param request  HTTPリクエスト
     * @param response HTTPレスポンス
     */
    @GetMapping("/callback")
    public void handle(
            @RequestParam(required = false) String code,
            @RequestParam(required = false) String state,
            @RequestParam(required = false) String error,
            HttpServletRequest request,
            HttpServletResponse response) throws IOException {

        try {
            // エラーパラメータの確認
            if (error != null) {
                redirectToErrorPage(response, "認証に失敗しました。しばらく時間を置いてから再度お試しください。");
                return;
            }

            // 必須パラメータの確認
            if (code == null || state == null) {
                redirectToErrorPage(response, "認証に失敗しました。しばらく時間を置いてから再度お試しください。");
                return;
            }

            // stateの検証
            String stateKey = "oidc:state:" + state;
            if (!redisClient.hasKey(stateKey)) {
                redirectToErrorPage(response, "認証に失敗しました。しばらく時間を置いてから再度お試しください。");
                return;
            }

            // stateに関連付けられた情報を取得
            String providerKey = "oidc:provider:" + state;
            String codeVerifierKey = "oidc:code_verifier:" + state;

            Optional<String> providerOpt = redisClient.getValue(providerKey, String.class);
            Optional<String> codeVerifierOpt = redisClient.getValue(codeVerifierKey, String.class);

            if (providerOpt.isEmpty() || codeVerifierOpt.isEmpty()) {
                redirectToErrorPage(response, "認証に失敗しました。しばらく時間を置いてから再度お試しください。");
                return;
            }

            String provider = providerOpt.get();
            String codeVerifier = codeVerifierOpt.get();

            // リダイレクトURIの構築
            String baseUrl = UrlUtil.getBaseUrl(request);
            String redirectUri = baseUrl + "/api/auth/oidc/callback";

            // アクセストークンの取得
            OidcTokenResponse tokenResponse = oidcClient.getToken(
                    provider,
                    code,
                    redirectUri,
                    codeVerifier);

            // トークンレスポンスのエラー確認
            if (tokenResponse.hasError()) {
                redirectToErrorPage(response, "認証に失敗しました。しばらく時間を置いてから再度お試しください。");
                return;
            }

            // ユーザー情報の取得
            OidcUserInfoDto userInfo = oidcClient.getUserInfo(provider, tokenResponse.getAccessToken());

            if (userInfo == null) {
                redirectToErrorPage(response, "ユーザー情報の取得に失敗しました。しばらく時間を置いてから再度お試しください。");
                return;
            }

            // ログイン処理の実行
            OidcLoginUseCaseDto loginResult = oidcLoginUseCase.execute(userInfo);

            // 使用済みのstateとpkce関連のデータを削除
            redisClient.deleteValue(stateKey);
            redisClient.deleteValue(providerKey);
            redisClient.deleteValue(codeVerifierKey);

            // JWT発行
            String accessToken = jwtProvider.createAccessToken(loginResult.getId().toString());
            String refreshToken = jwtProvider.createRefreshToken(loginResult.getId().toString());

            // レスポンスヘッダーにセット
            response.addHeader("Set-Cookie",
                    CookieUtil.createHttpOnlyCookie("accessToken", accessToken, isSecureCookie));
            response.addHeader("Set-Cookie",
                    CookieUtil.createHttpOnlyCookie("refreshToken", refreshToken, isSecureCookie));

            // 成功ページへリダイレクト
            response.sendRedirect(baseUrl + FRONTEND_REDIRECT_URL);

        } catch (Exception e) {
            redirectToErrorPage(response, "認証に失敗しました。しばらく時間を置いてから再度お試しください。");
        }
    }

    /**
     * エラーページへリダイレクトする
     *
     * @param response     HTTPレスポンス
     * @param errorMessage エラーメッセージ
     */
    private void redirectToErrorPage(HttpServletResponse response, String errorMessage)
            throws IOException {
        String redirectUrl = ERROR_REDIRECT_URL + "?error=" + errorMessage;
        response.sendRedirect(redirectUrl);
    }
}
