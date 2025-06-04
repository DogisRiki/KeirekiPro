package com.example.keirekipro.unit.infrastructure.auth.oidc.provider;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.infrastructure.auth.oidc.provider.GithubOidcProvider;
import com.example.keirekipro.infrastructure.auth.oidc.provider.GoogleOidcProvider;
import com.example.keirekipro.infrastructure.auth.oidc.provider.OidcProvider;
import com.example.keirekipro.infrastructure.auth.oidc.provider.OidcProviderFactory;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;

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
                DUMMY_SECRET_NAME,
                mock(RestClient.class),
                mock(ObjectMapper.class));

        // OidcProviderFactoryに両プロバイダーを登録
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
    @DisplayName("GoogleOidcProvider_userInfoがnullの場合、nullを返す")
    void test4() {
        GoogleOidcProvider googleProvider = new GoogleOidcProvider(
                DUMMY_AUTH_ENDPOINT,
                DUMMY_TOKEN_ENDPOINT,
                DUMMY_USERINFO_ENDPOINT,
                DUMMY_SCOPES,
                DUMMY_SECRET_NAME);

        // 検証
        assertThat(googleProvider.convertToStandardUserInfo(null)).isNull();
    }

    @Test
    @DisplayName("GithubOidcProviderが正しくインスタンス化でき、OidcUserInfoDtoの情報が正しい")
    void test5() {
        RestClient mockRestClient = mock(RestClient.class);
        ObjectMapper mockObjectMapper = mock(ObjectMapper.class);

        GithubOidcProvider githubProvider = new GithubOidcProvider(
                DUMMY_AUTH_ENDPOINT,
                DUMMY_TOKEN_ENDPOINT,
                DUMMY_USERINFO_ENDPOINT,
                DUMMY_SCOPES,
                DUMMY_SECRET_NAME,
                mockRestClient,
                mockObjectMapper);

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

    @Test
    @DisplayName("GithubOidcProvider_userInfoがnullの場合、nullを返す")
    void test6() {
        RestClient mockRestClient = mock(RestClient.class);
        ObjectMapper mockObjectMapper = mock(ObjectMapper.class);

        GithubOidcProvider githubProvider = new GithubOidcProvider(
                DUMMY_AUTH_ENDPOINT,
                DUMMY_TOKEN_ENDPOINT,
                DUMMY_USERINFO_ENDPOINT,
                DUMMY_SCOPES,
                DUMMY_SECRET_NAME,
                mockRestClient,
                mockObjectMapper);

        // 検証
        assertThat(githubProvider.convertToStandardUserInfo(null)).isNull();
    }

    @Test
    @DisplayName("GithubOidcProvider_emailがnullの場合、fetchPrimaryEmailで補完される")
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void test7() throws Exception {
        // userInfoにemailが存在しないがaccess_tokenは存在する
        Map<String, Object> userInfo = new HashMap<>();
        userInfo.put("id", "githubId999");
        userInfo.put("email", null); // 明示的にnull
        userInfo.put("login", "NoEmailUser");
        userInfo.put("access_token", "dummy_token");

        // GitHub API から返されるダミーJSON
        String dummyEmailJson = """
                [
                    { "email": "primary@example.com", "primary": true, "verified": true },
                    { "email": "secondary@example.com", "primary": false, "verified": true }
                ]
                """;

        // RestClient関連のモック（ジェネリクスを避ける）
        RestClient restClient = mock(RestClient.class);
        RestClient.RequestHeadersUriSpec rawUriSpec = mock(RestClient.RequestHeadersUriSpec.class);
        RestClient.RequestHeadersSpec rawHeadersSpec = mock(RestClient.RequestHeadersSpec.class);
        RestClient.ResponseSpec responseSpec = mock(RestClient.ResponseSpec.class);

        // Mockitoはキャストで型を合わせる必要がある
        when(restClient.get()).thenReturn((RestClient.RequestHeadersUriSpec) rawUriSpec);
        when(rawUriSpec.uri(anyString())).thenReturn((RestClient.RequestHeadersSpec) rawHeadersSpec);
        when(rawHeadersSpec.headers(any())).thenReturn(rawHeadersSpec);
        when(rawHeadersSpec.retrieve()).thenReturn(responseSpec);
        when(responseSpec.body(String.class)).thenReturn(dummyEmailJson);

        // ObjectMapperモック設定
        ObjectMapper mockObjectMapper = mock(ObjectMapper.class);
        List<Map<String, Object>> dummyList = List.of(
                Map.of("email", "primary@example.com", "primary", true, "verified", true));
        when(mockObjectMapper.readValue(anyString(), any(TypeReference.class))).thenReturn(dummyList);

        // Provider作成
        GithubOidcProvider githubProvider = new GithubOidcProvider(
                "https://auth",
                "https://token",
                "https://userinfo",
                "openid email profile",
                "dummy-secret",
                restClient,
                mockObjectMapper);

        // 実行と検証
        OidcUserInfoDto dto = githubProvider.convertToStandardUserInfo(userInfo);
        assertThat(dto.getEmail()).isEqualTo("primary@example.com");
        assertThat(dto.getUsername()).isEqualTo("NoEmailUser");
        assertThat(dto.getProviderUserId()).isEqualTo("githubId999");
        assertThat(dto.getProviderType()).isEqualTo("github");
    }
}
