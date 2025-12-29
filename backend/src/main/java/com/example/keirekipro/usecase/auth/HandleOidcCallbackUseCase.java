package com.example.keirekipro.usecase.auth;

import java.util.Optional;

import com.example.keirekipro.usecase.auth.dto.OidcLoginUseCaseDto;
import com.example.keirekipro.usecase.auth.oidc.OidcAuthorizationSession;
import com.example.keirekipro.usecase.auth.oidc.OidcCallbackError;
import com.example.keirekipro.usecase.auth.oidc.OidcCallbackResult;
import com.example.keirekipro.usecase.auth.oidc.OidcGateway;
import com.example.keirekipro.usecase.auth.oidc.OidcToken;
import com.example.keirekipro.usecase.auth.oidc.OidcUserInfo;
import com.example.keirekipro.usecase.auth.store.OidcAuthorizationSessionStore;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * OIDCコールバック処理ユースケース
 */
@Service
@RequiredArgsConstructor
public class HandleOidcCallbackUseCase {

    private final OidcGateway oidcGateway;
    private final OidcAuthorizationSessionStore oidcAuthorizationSessionStore;
    private final OidcLoginUseCase oidcLoginUseCase;

    /**
     * OIDCプロバイダーからのコールバックを処理する
     *
     * @param code        認可コード
     * @param state       state値
     * @param error       エラーパラメータ
     * @param redirectUri リダイレクトURI
     * @return 処理結果
     */
    public OidcCallbackResult execute(String code, String state, String error, String redirectUri) {

        try {
            // エラーパラメータの確認
            if (error != null) {
                return new OidcCallbackResult.Failure(OidcCallbackError.PROVIDER_ERROR_PARAMETER);
            }

            // 必須パラメータの確認
            if (code == null || state == null) {
                return new OidcCallbackResult.Failure(OidcCallbackError.MISSING_REQUIRED_PARAMETER);
            }

            // stateに紐づくセッションを取得
            Optional<OidcAuthorizationSession> sessionOpt = oidcAuthorizationSessionStore.find(state);
            if (sessionOpt.isEmpty()) {
                return new OidcCallbackResult.Failure(OidcCallbackError.INVALID_OR_EXPIRED_STATE);
            }

            OidcAuthorizationSession session = sessionOpt.get();
            String provider = session.getProvider();
            String codeVerifier = session.getCodeVerifier();

            // アクセストークンの取得
            OidcToken token = oidcGateway.exchangeToken(provider, code, redirectUri, codeVerifier);
            if (token == null || token.hasError()) {
                return new OidcCallbackResult.Failure(OidcCallbackError.TOKEN_EXCHANGE_FAILED);
            }

            // ユーザー情報の取得
            OidcUserInfo userInfo = oidcGateway.fetchUserInfo(provider, token.getAccessToken());
            if (userInfo == null) {
                return new OidcCallbackResult.Failure(OidcCallbackError.USERINFO_FETCH_FAILED);
            }

            // ログイン処理の実行
            OidcLoginUseCaseDto loginResult = oidcLoginUseCase.execute(userInfo);

            return new OidcCallbackResult.Success(loginResult.getId());

        } catch (Exception e) {
            return new OidcCallbackResult.Failure(OidcCallbackError.LOGIN_FAILED);
        } finally {
            // 再利用防止のため、stateがある場合は確実に削除する
            if (state != null) {
                oidcAuthorizationSessionStore.remove(state);
            }
        }
    }
}
