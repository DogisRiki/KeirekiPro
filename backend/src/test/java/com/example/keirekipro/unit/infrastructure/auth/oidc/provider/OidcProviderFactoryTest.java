package com.example.keirekipro.unit.infrastructure.auth.oidc.provider;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import java.util.Map;

import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.infrastructure.auth.oidc.provider.GithubOidcProvider;
import com.example.keirekipro.infrastructure.auth.oidc.provider.GoogleOidcProvider;
import com.example.keirekipro.infrastructure.auth.oidc.provider.OidcProvider;
import com.example.keirekipro.infrastructure.auth.oidc.provider.OidcProviderFactory;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class OidcProviderFactoryTest {

    // テスト用のダミー設定値
    private static final String DUMMY_AUTH_ENDPOINT = "https://dummy-auth.example.com";
    private static final String DUMMY_TOKEN_ENDPOINT = "https://dummy-token.example.com";
    private static final String DUMMY_USERINFO_ENDPOINT = "https://dummy-userinfo.example.com";
    private static final String DUMMY_SCOPES = "openid email profile";
    private static final String DUMMY_SECRET_NAME = "dummySecret";

    @Test
    @DisplayName("有効なプロバイダー名で正しくプロバイダーが取得できる")
    void test1() {
        // 実際のプロバイダー実装を生成（コンストラクタにダミー値を渡す）
        GoogleOidcProvider googleProvider = new GoogleOidcProvider(
                DUMMY_AUTH_ENDPOINT,
                DUMMY_TOKEN_ENDPOINT,
                DUMMY_USERINFO_ENDPOINT,
                DUMMY_SCOPES,
                DUMMY_SECRET_NAME);
        GithubOidcProvider githubProvider = new GithubOidcProvider(
                DUMMY_AUTH_ENDPOINT,
                DUMMY_TOKEN_ENDPOINT,
                DUMMY_USERINFO_ENDPOINT,
                DUMMY_SCOPES,
                DUMMY_SECRET_NAME);
        // OidcProviderFactory に両プロバイダーを登録
        OidcProviderFactory factory = new OidcProviderFactory(List.of(googleProvider, githubProvider));

        // 小文字・大文字混在でも正しいプロバイダーが返る
        OidcProvider p1 = factory.getProvider("Google");
        assertThat(p1).isInstanceOf(GoogleOidcProvider.class);

        OidcProvider p2 = factory.getProvider("GITHUB");
        assertThat(p2).isInstanceOf(GithubOidcProvider.class);
    }

    @Test
    @DisplayName("無効なプロバイダー名の場合、例外がスローされる")
    void test2() {
        GoogleOidcProvider googleProvider = new GoogleOidcProvider(
                DUMMY_AUTH_ENDPOINT,
                DUMMY_TOKEN_ENDPOINT,
                DUMMY_USERINFO_ENDPOINT,
                DUMMY_SCOPES,
                DUMMY_SECRET_NAME);
        OidcProviderFactory factory = new OidcProviderFactory(List.of(googleProvider));

        assertThatThrownBy(() -> {
            factory.getProvider("nonexistent");
        }).isInstanceOf(RuntimeException.class);
    }

    @Test
    @DisplayName("GoogleOidcProviderが正しくインスタンス化でき、OidcUserInfoDtoの情報が正しい")
    void test3() {
        GoogleOidcProvider googleProvider = new GoogleOidcProvider(
                DUMMY_AUTH_ENDPOINT,
                DUMMY_TOKEN_ENDPOINT,
                DUMMY_USERINFO_ENDPOINT,
                DUMMY_SCOPES,
                DUMMY_SECRET_NAME);

        // Googleの場合、ユーザー情報のキーは "sub", "email", "name" を利用する
        Map<String, Object> userInfo = Map.of(
                "sub", "googleSub123",
                "email", "google@example.com",
                "name", "Google User");

        OidcUserInfoDto standardUserInfo = googleProvider.convertToStandardUserInfo(userInfo);
        assertThat(standardUserInfo).isNotNull();
        assertThat(standardUserInfo.getProviderUserId()).isEqualTo("googleSub123");
        assertThat(standardUserInfo.getEmail()).isEqualTo("google@example.com");
        assertThat(standardUserInfo.getUsername()).isEqualTo("Google User");
        assertThat(standardUserInfo.getProviderType()).isEqualTo("google");
    }

    @Test
    @DisplayName("GithubOidcProviderが正しくインスタンス化でき、OidcUserInfoDtoの情報が正しい")
    void test4() {
        GithubOidcProvider githubProvider = new GithubOidcProvider(
                DUMMY_AUTH_ENDPOINT,
                DUMMY_TOKEN_ENDPOINT,
                DUMMY_USERINFO_ENDPOINT,
                DUMMY_SCOPES,
                DUMMY_SECRET_NAME);

        // GitHubの場合、ユーザー情報のキーは "id", "email", "login" を利用する
        Map<String, Object> userInfo = Map.of(
                "id", "githubId456",
                "email", "github@example.com",
                "login", "GithubUser");

        OidcUserInfoDto standardUserInfo = githubProvider.convertToStandardUserInfo(userInfo);
        assertThat(standardUserInfo).isNotNull();
        assertThat(standardUserInfo.getProviderUserId()).isEqualTo("githubId456");
        assertThat(standardUserInfo.getEmail()).isEqualTo("github@example.com");
        assertThat(standardUserInfo.getUsername()).isEqualTo("GithubUser");
        assertThat(standardUserInfo.getProviderType()).isEqualTo("github");
    }
}
