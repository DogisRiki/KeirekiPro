package com.example.keirekipro.presentation.auth.controller;

import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.presentation.shared.utils.BaseUrlResolver;
import com.example.keirekipro.presentation.shared.utils.CookieUtil;
import com.example.keirekipro.usecase.auth.HandleOidcCallbackUseCase;
import com.example.keirekipro.usecase.auth.oidc.OidcCallbackError;
import com.example.keirekipro.usecase.auth.oidc.OidcCallbackResult;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

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
@Tag(name = "auth", description = "認証・認可に関するエンドポイント")
public class OidcCallbackController {

    private final JwtProvider jwtProvider;
    private final HandleOidcCallbackUseCase handleOidcCallbackUseCase;
    private final BaseUrlResolver baseUrlResolver;

    @Value("${cookie.secure:false}")
    private boolean isSecureCookie;

    @Value("${frontend-base-url}")
    private String frontendBaseUrl;

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
    @Operation(summary = "OIDCコールバック", description = "OIDCプロバイダーからのコールバック処理を実行する")
    public void handle(
            @RequestParam(name = "code", required = false) String code,
            @RequestParam(name = "state", required = false) String state,
            @RequestParam(name = "error", required = false) String error,
            HttpServletRequest request,
            HttpServletResponse response) throws IOException {

        try {
            // リダイレクトURIの構築
            String baseUrl = baseUrlResolver.resolve(request);
            String redirectUri = baseUrl + "/api/auth/oidc/callback";

            // コールバック処理
            OidcCallbackResult result = handleOidcCallbackUseCase.execute(code, state, error, redirectUri);

            if (result instanceof OidcCallbackResult.Success success) {
                // JWT発行
                String userId = success.getUserId().toString();
                String accessToken = jwtProvider.createAccessToken(userId, success.getRoles());
                String refreshToken = jwtProvider.createRefreshToken(userId, success.getRoles());

                // レスポンスヘッダーにセット
                response.addHeader("Set-Cookie",
                        CookieUtil.createHttpOnlyCookie("accessToken", accessToken, isSecureCookie));
                response.addHeader("Set-Cookie",
                        CookieUtil.createHttpOnlyCookie("refreshToken", refreshToken, isSecureCookie));

                // 成功ページへリダイレクト
                response.sendRedirect(frontendBaseUrl + FRONTEND_REDIRECT_URL);
                return;
            }

            // 失敗時のメッセージ
            OidcCallbackError err = ((OidcCallbackResult.Failure) result).getError();
            if (err == OidcCallbackError.USERINFO_FETCH_FAILED) {
                redirectToErrorPage(response, "ユーザー情報の取得に失敗しました。しばらく時間を置いてから再度お試しください。");
                return;
            }
            redirectToErrorPage(response, "認証に失敗しました。しばらく時間を置いてから再度お試しください。");

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
        // 日本語を含むクエリパラメータをURLエンコード
        String encoded = URLEncoder.encode(errorMessage, StandardCharsets.UTF_8);
        String redirectUrl = frontendBaseUrl + ERROR_REDIRECT_URL + "?error=" + encoded;
        response.sendRedirect(redirectUrl);
    }
}
