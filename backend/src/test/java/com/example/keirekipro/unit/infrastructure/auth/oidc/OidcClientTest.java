package com.example.keirekipro.unit.infrastructure.auth.oidc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;

import com.example.keirekipro.infrastructure.auth.oidc.OidcClient;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcTokenResponse;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.infrastructure.auth.oidc.provider.OidcProvider;
import com.example.keirekipro.infrastructure.auth.oidc.provider.OidcProviderFactory;
import com.example.keirekipro.infrastructure.shared.aws.AwsSecretsManagerClient;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

@ExtendWith(MockitoExtension.class)
class OidcClientTest {

    @Mock
    private RestClient restClient;

    @Mock
    private OidcProviderFactory providerFactory;

    @Mock
    private AwsSecretsManagerClient secretsClient;

    @Mock
    private OidcProvider oidcProvider;

    @InjectMocks
    private OidcClient oidcClient;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private final String providerName = "google";
    private final String redirectUri = "https://keirekipro.click/api/auth/oidc/callback";
    private final String state = "random-state";
    private final String codeChallenge = "code-challenge";
    private final String codeVerifier = "code-verifier";
    private final String code = "authorization-code";
    private final String accessToken = "access-token";
    private final String userInfoEndopoint = "https://openidconnect.googleapis.com/v1/userinfo";

    @Test
    @DisplayName("認可URLが正しく構築される")
    void test1() {
        // モックの振る舞いをセットアップ
        when(providerFactory.getProvider(providerName)).thenReturn(oidcProvider);
        when(oidcProvider.getSecretName()).thenReturn("google-oidc-secret");
        when(oidcProvider.getAuthorizationEndpoint()).thenReturn("https://accounts.google.com/o/oauth2/auth");
        when(oidcProvider.getScopes()).thenReturn("openid email profile");

        // AWS Secrets ManagerからクライアントIDを取得する箇所をモック
        JsonNode jsonNode = objectMapper.createObjectNode();
        ((ObjectNode) jsonNode).put("client_id", "mock-client-id");
        when(secretsClient.getSecretJson("google-oidc-secret")).thenReturn(jsonNode);

        // 認可URLの構築を実行
        String result = oidcClient.buildAuthorizationUrl(providerName, redirectUri, state, codeChallenge);

        // 検証
        assertThat(result)
                .isNotNull()
                .contains("https://accounts.google.com/o/oauth2/auth")
                .contains("client_id=mock-client-id")
                .contains("response_type=code")
                .contains("scope=openid%20email%20profile")
                .contains("redirect_uri=https://keirekipro.click/api/auth/oidc/callback")
                .contains("state=random-state")
                .contains("code_challenge=code-challenge")
                .contains("code_challenge_method=S256");

        verify(oidcProvider).addAuthorizationUrlParameters(any());
    }

    @Test
    @DisplayName("プロバイダー固有のパラメータを付与した状態で認可URLが正しく構築される")
    void test2() {
        // モックの振る舞いをセットアップ
        when(providerFactory.getProvider(providerName)).thenReturn(oidcProvider);
        when(oidcProvider.getSecretName()).thenReturn("google-oidc-secret");
        when(oidcProvider.getAuthorizationEndpoint()).thenReturn("https://accounts.google.com/o/oauth2/auth");
        when(oidcProvider.getScopes()).thenReturn("openid email profile");

        // AWS Secrets ManagerからクライアントIDを取得する箇所をモック
        JsonNode jsonNode = objectMapper.createObjectNode();
        ((ObjectNode) jsonNode).put("client_id", "mock-client-id");
        when(secretsClient.getSecretJson("google-oidc-secret")).thenReturn(jsonNode);

        // doAnswer()の使い方
        // oidcProvider.addAuthorizationUrlParameters(...) が呼ばれたら、そのときは
        // doAnswer(...)に書いてあるラムダ式の動作をする という意味
        doAnswer(invocation -> {
            // addAuthorizationUrlParameters()の第1引数（Cosumer）を取り出す
            Consumer<Map<String, String>> consumer = invocation.getArgument(0);
            // プロバイダー固有のパラメータをMapに入れる
            Map<String, String> params = new HashMap<>();
            params.put("access_type", "offline");
            params.put("prompt", "consent");
            // 取り出したCosumerに対してparamsを引数として渡す
            consumer.accept(params);
            // 戻り値不要なためとりあえずnullを返しておく
            return null;
        }).when(oidcProvider).addAuthorizationUrlParameters(any());

        // 認可URLの構築を実行
        String result = oidcClient.buildAuthorizationUrl(providerName, redirectUri, state, codeChallenge);

        // 検証
        assertThat(result)
                .isNotNull()
                .contains("https://accounts.google.com/o/oauth2/auth")
                .contains("client_id=mock-client-id")
                .contains("response_type=code")
                .contains("scope=openid%20email%20profile")
                .contains("redirect_uri=https://keirekipro.click/api/auth/oidc/callback")
                .contains("state=random-state")
                .contains("code_challenge=code-challenge")
                .contains("code_challenge_method=S256")
                .contains("access_type=offline")
                .contains("prompt=consent");

        verify(oidcProvider).addAuthorizationUrlParameters(any());
    }

    @Test
    @DisplayName("アクセストークンを取得できる")
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void test3() {
        // モックセットアップ
        when(providerFactory.getProvider(providerName)).thenReturn(oidcProvider);
        when(oidcProvider.getSecretName()).thenReturn("google-oidc-secret");
        when(oidcProvider.getTokenEndpoint()).thenReturn("https://oauth2.googleapis.com/token");

        // AWS Secrets ManagerからクライアントIDを取得する箇所をモック
        JsonNode secretsNode = objectMapper.createObjectNode();
        ((ObjectNode) secretsNode).put("client_id", "mock-client-id");
        ((ObjectNode) secretsNode).put("client_secret", "mock-client-secret");
        when(secretsClient.getSecretJson("google-oidc-secret")).thenReturn(secretsNode);

        // RestClientをモック
        // リクエストボディとヘッダーなどを設定するためのインターフェースをモック化
        RestClient.RequestBodySpec requestBodySpec = mock(RestClient.RequestBodySpec.class);
        // URIを設定するためのインターフェースをモック化
        RestClient.RequestBodyUriSpec requestBodyUriSpec = mock(RestClient.RequestBodyUriSpec.class);
        // レスポンスを処理するためのインターフェースをモック化
        RestClient.ResponseSpec responseSpec = mock(RestClient.ResponseSpec.class);

        // restClient.post()が呼ばれたら、URIを設定するためのrequestBodyUriSpecを返すよう設定
        when(restClient.post()).thenReturn(requestBodyUriSpec);
        // requestBodyUriSpec.uri()が任意の文字列引数で呼ばれたら、requestBodySpecを返すよう設定
        when(requestBodyUriSpec.uri(anyString())).thenReturn(requestBodySpec);
        // requestBodySpec.contentType()が任意のMediaType引数で呼ばれたら、同じrequestBodySpecを返すよう設定（メソッドチェーン用）
        when(requestBodySpec.contentType(any(MediaType.class))).thenReturn(requestBodySpec);
        // requestBodySpec.body()が任意のMap引数で呼ばれたら、同じrequestBodySpecを返すよう設定（メソッドチェーン用）
        when(requestBodySpec.body(anyMap())).thenReturn(requestBodySpec);
        // requestBodySpec.retrieve()が呼ばれたら、レスポンス処理用のresponseSpecを返すよう設定
        when(requestBodySpec.retrieve()).thenReturn(responseSpec);

        // 期待されるレスポンス
        OidcTokenResponse expectedResponse = new OidcTokenResponse();
        expectedResponse.setAccessToken("access-token");
        expectedResponse.setIdToken("id-token");
        expectedResponse.setRefreshToken("refresh-token");
        expectedResponse.setTokenType("Bearer");
        expectedResponse.setExpiresIn(3600);
        when(responseSpec.body(OidcTokenResponse.class)).thenReturn(expectedResponse);

        // フォームデータの検証に使用するキャプチャを作成
        ArgumentCaptor<Map<String, String>> formDataCaptor = ArgumentCaptor.forClass((Class) Map.class);

        // アクセストークンの取得を実行
        OidcTokenResponse result = oidcClient.getToken(providerName, code, redirectUri, codeVerifier);

        // requestBodySpec.bodyメソッドが呼ばれた際に渡されたパラメータをキャプチャするよう指定
        verify(requestBodySpec).body(formDataCaptor.capture());

        // キャプチャの取得
        Map<String, String> formData = (Map<String, String>) formDataCaptor.getValue();

        // レスポンスの検証
        assertThat(result)
                .isNotNull()
                .isEqualTo(expectedResponse);

        // リクエストパラメータに必要なパラメータがすべて含まれているかをキャプチャから検証
        assertThat(formData)
                .containsEntry("grant_type", "authorization_code")
                .containsEntry("code", code)
                .containsEntry("redirect_uri", redirectUri)
                .containsEntry("code_verifier", codeVerifier);
    }

    @Test
    @DisplayName("プロバイダー固有のパラメータを付与した状態でアクセストークンを取得できる")
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void test4() {
        // モックセットアップ
        when(providerFactory.getProvider(providerName)).thenReturn(oidcProvider);
        when(oidcProvider.getSecretName()).thenReturn("google-oidc-secret");
        when(oidcProvider.getTokenEndpoint()).thenReturn("https://oauth2.googleapis.com/token");

        // AWS Secrets ManagerからクライアントIDを取得する箇所をモック
        JsonNode secretsNode = objectMapper.createObjectNode();
        ((ObjectNode) secretsNode).put("client_id", "mock-client-id");
        ((ObjectNode) secretsNode).put("client_secret", "mock-client-secret");
        when(secretsClient.getSecretJson("google-oidc-secret")).thenReturn(secretsNode);

        // プロバイダー固有のパラメータをMapに入れる
        doAnswer(invocation -> {
            Map<String, String> formData = new HashMap<>();
            formData.put("unique_param", "mock-unique_param");
            Consumer<Map<String, String>> consumer = invocation.getArgument(1);
            consumer.accept(formData);
            return null;
        }).when(oidcProvider).processSecrets(any(), any());

        // RestClientをモック
        RestClient.RequestBodySpec requestBodySpec = mock(RestClient.RequestBodySpec.class);
        RestClient.RequestBodyUriSpec requestBodyUriSpec = mock(RestClient.RequestBodyUriSpec.class);
        RestClient.ResponseSpec responseSpec = mock(RestClient.ResponseSpec.class);

        when(restClient.post()).thenReturn(requestBodyUriSpec);
        when(requestBodyUriSpec.uri(anyString())).thenReturn(requestBodySpec);
        when(requestBodySpec.contentType(any(MediaType.class))).thenReturn(requestBodySpec);
        when(requestBodySpec.body(anyMap())).thenReturn(requestBodySpec);
        when(requestBodySpec.retrieve()).thenReturn(responseSpec);

        // 期待されるレスポンス
        OidcTokenResponse expectedResponse = new OidcTokenResponse();
        expectedResponse.setAccessToken("access-token");
        expectedResponse.setIdToken("id-token");
        expectedResponse.setRefreshToken("refresh-token");
        expectedResponse.setTokenType("Bearer");
        expectedResponse.setExpiresIn(3600);
        when(responseSpec.body(OidcTokenResponse.class)).thenReturn(expectedResponse);

        // フォームデータの検証に使用するキャプチャを作成
        ArgumentCaptor<Map<String, String>> formDataCaptor = ArgumentCaptor.forClass((Class) Map.class);

        // アクセストークンの取得を実行
        OidcTokenResponse result = oidcClient.getToken(providerName, code, redirectUri, codeVerifier);

        // requestBodySpec.bodyメソッドが呼ばれた際に渡されたパラメータをキャプチャするよう指定
        verify(requestBodySpec).body(formDataCaptor.capture());

        // キャプチャの取得
        Map<String, String> formData = (Map<String, String>) formDataCaptor.getValue();

        // レスポンスの検証
        assertThat(result)
                .isNotNull()
                .isEqualTo(expectedResponse);

        // リクエストパラメータに必要なパラメータがすべて含まれているかをキャプチャから検証
        assertThat(formData)
                .containsEntry("grant_type", "authorization_code")
                .containsEntry("code", code)
                .containsEntry("redirect_uri", redirectUri)
                .containsEntry("code_verifier", codeVerifier)
                .containsEntry("unique_param", "mock-unique_param");
    }

    @Test
    @DisplayName("アクセストークンの取得に失敗した場合、エラーレスポンスが返却される")
    void test5() {
        // モックセットアップ
        when(providerFactory.getProvider(providerName)).thenReturn(oidcProvider);
        when(oidcProvider.getSecretName()).thenReturn("google-oidc-secret");
        when(oidcProvider.getTokenEndpoint()).thenReturn("https://oauth2.googleapis.com/token");

        // AWS Secrets ManagerからクライアントIDを取得する箇所をモック
        JsonNode secretsNode = objectMapper.createObjectNode();
        ((ObjectNode) secretsNode).put("client_id", "mock-client-id");
        ((ObjectNode) secretsNode).put("client_secret", "mock-client-secret");
        when(secretsClient.getSecretJson("google-oidc-secret")).thenReturn(secretsNode);

        // RestClientをモック
        RestClient.RequestBodySpec requestBodySpec = mock(RestClient.RequestBodySpec.class);
        RestClient.RequestBodyUriSpec requestBodyUriSpec = mock(RestClient.RequestBodyUriSpec.class);

        when(restClient.post()).thenReturn(requestBodyUriSpec);
        when(requestBodyUriSpec.uri(anyString())).thenReturn(requestBodySpec);
        when(requestBodySpec.contentType(any(MediaType.class))).thenReturn(requestBodySpec);
        when(requestBodySpec.body(anyMap())).thenReturn(requestBodySpec);
        // RestClientExceptionをスローするように設定
        when(requestBodySpec.retrieve()).thenThrow(new RestClientException("API call failed"));

        // アクセストークンの取得を実行
        OidcTokenResponse result = oidcClient.getToken(providerName, code, redirectUri, codeVerifier);

        // 検証
        assertThat(result.getError()).isEqualTo("server_error");
        assertThat(result.getErrorDescription()).contains("トークン取得処理中にエラーが発生しました");
        assertThat(result.getErrorDescription()).contains("API call failed");
    }

    @Test
    @DisplayName("userinfoエンドポイントからユーザー情報を取得できる")
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void test6() {
        // モックセットアップ
        when(providerFactory.getProvider(providerName)).thenReturn(oidcProvider);
        when(oidcProvider.getUserInfoEndpoint()).thenReturn(userInfoEndopoint);

        // RestClientをモック
        RestClient.RequestHeadersSpec requestHeadersSpec = mock(RestClient.RequestHeadersSpec.class);
        RestClient.RequestHeadersUriSpec requestHeadersUriSpec = mock(RestClient.RequestHeadersUriSpec.class);
        RestClient.ResponseSpec responseSpec = mock(RestClient.ResponseSpec.class);

        when(restClient.get()).thenReturn(requestHeadersUriSpec);
        when(requestHeadersUriSpec.uri(anyString())).thenReturn(requestHeadersSpec);
        when(requestHeadersSpec.headers(any())).thenReturn(requestHeadersSpec);
        when(requestHeadersSpec.retrieve()).thenReturn(responseSpec);

        // ユーザー情報のモック
        Map<String, Object> userInfoMap = new HashMap<>();
        userInfoMap.put("sub", "123456789");
        userInfoMap.put("name", "Test User");
        userInfoMap.put("email", "test@keirekipro.click");

        // レスポンスでuserInfoMapを返すように設定
        when(responseSpec.body(any(ParameterizedTypeReference.class))).thenReturn(userInfoMap);

        // 変換結果のモック
        OidcUserInfoDto expectedUserInfo = OidcUserInfoDto.builder()
                .providerUserId("123456789")
                .email("test@example.com")
                .username("Test User")
                .providerType(providerName)
                .build();

        // ユーザー情報変換時、expectedUserInfoを返すように設定
        when(oidcProvider.convertToStandardUserInfo(userInfoMap)).thenReturn(expectedUserInfo);

        // ユーザー情報の取得を実行
        OidcUserInfoDto result = oidcClient.getUserInfo(providerName, accessToken);

        // レスポンスの検証
        assertThat(result).isEqualTo(expectedUserInfo);

        // ヘッダーの検証に使用するキャプチャを作成
        ArgumentCaptor<Consumer> headersCaptor = ArgumentCaptor.forClass(Consumer.class);

        // requestHeadersSpec.headersメソッドが呼ばれた際に渡されたパラメータをキャプチャするよう指定
        verify(requestHeadersSpec).headers(headersCaptor.capture());

        // ヘッダーのBearerトークン検証
        HttpHeaders capturedHeaders = new HttpHeaders();
        ((Consumer<HttpHeaders>) headersCaptor.getValue()).accept(capturedHeaders);
        assertThat(capturedHeaders.getFirst(HttpHeaders.AUTHORIZATION)).isEqualTo("Bearer " + accessToken);
    }

    @Test
    @DisplayName("プロバイダー固有のヘッダーを付与した状態でuserinfoエンドポイントからユーザー情報の取得ができる")
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void test7() {
        // モックセットアップ
        when(providerFactory.getProvider("github")).thenReturn(oidcProvider);
        when(oidcProvider.getUserInfoEndpoint()).thenReturn("https://api.github.com/user");

        // プロバイダー固有のヘッダーをセット
        doAnswer(invocation -> {
            HttpHeaders headers = invocation.getArgument(0);
            headers.set(HttpHeaders.ACCEPT, "application/vnd.github+json");
            headers.set("X-GitHub-Api-Version", "2022-11-28");
            return null;
        }).when(oidcProvider).configureHeaders(any(HttpHeaders.class));

        // RestClientをモック
        RestClient.RequestHeadersSpec requestHeadersSpec = mock(RestClient.RequestHeadersSpec.class);
        RestClient.RequestHeadersUriSpec requestHeadersUriSpec = mock(RestClient.RequestHeadersUriSpec.class);
        RestClient.ResponseSpec responseSpec = mock(RestClient.ResponseSpec.class);

        when(restClient.get()).thenReturn(requestHeadersUriSpec);
        when(requestHeadersUriSpec.uri(anyString())).thenReturn(requestHeadersSpec);
        when(requestHeadersSpec.headers(any())).thenReturn(requestHeadersSpec);
        when(requestHeadersSpec.retrieve()).thenReturn(responseSpec);

        // ユーザー情報のモック
        Map<String, Object> userInfoMap = new HashMap<>();
        userInfoMap.put("sub", "123456789");
        userInfoMap.put("name", "Test User");
        userInfoMap.put("email", "test@keirekipro.click");

        // レスポンスでuserInfoMapを返すように設定
        when(responseSpec.body(any(ParameterizedTypeReference.class))).thenReturn(userInfoMap);

        // 変換結果のモック
        OidcUserInfoDto expectedUserInfo = OidcUserInfoDto.builder()
                .providerUserId("123456789")
                .email("test@example.com")
                .username("Test User")
                .providerType("github")
                .build();

        // ユーザー情報変換時、expectedUserInfoを返すように設定
        when(oidcProvider.convertToStandardUserInfo(userInfoMap)).thenReturn(expectedUserInfo);

        // ユーザー情報の取得を実行
        OidcUserInfoDto result = oidcClient.getUserInfo("github", accessToken);

        // レスポンスの検証
        assertThat(result).isEqualTo(expectedUserInfo);

        // ヘッダーの検証に使用するキャプチャを作成
        ArgumentCaptor<Consumer> headersCaptor = ArgumentCaptor.forClass(Consumer.class);

        // requestHeadersSpec.headersメソッドが呼ばれた際に渡されたパラメータをキャプチャするよう指定
        verify(requestHeadersSpec).headers(headersCaptor.capture());

        // ヘッダーのBearerトークンと固有ヘッダーの検証
        HttpHeaders capturedHeaders = new HttpHeaders();
        ((Consumer<HttpHeaders>) headersCaptor.getValue()).accept(capturedHeaders);

        // Bearerトークンが設定されていることを検証
        assertThat(capturedHeaders.getFirst(HttpHeaders.AUTHORIZATION)).isEqualTo("Bearer " + accessToken);

        // プロバイダー固有のヘッダーが設定されていることを検証
        assertThat(capturedHeaders.getFirst(HttpHeaders.ACCEPT)).isEqualTo("application/vnd.github+json");
        assertThat(capturedHeaders.getFirst("X-GitHub-Api-Version")).isEqualTo("2022-11-28");

        // configureHeadersが呼ばれたことを検証
        verify(oidcProvider).configureHeaders(any(HttpHeaders.class));
    }

    @Test
    @DisplayName("userinfoエンドポイントからユーザー情報の取得に失敗した場合、nullが返却される")
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void test8() {
        // モックセットアップ
        when(providerFactory.getProvider(providerName)).thenReturn(oidcProvider);
        when(oidcProvider.getUserInfoEndpoint()).thenReturn(userInfoEndopoint);

        // RestClientをモック
        RestClient.RequestHeadersSpec requestHeadersSpec = mock(RestClient.RequestHeadersSpec.class);
        RestClient.RequestHeadersUriSpec requestHeadersUriSpec = mock(RestClient.RequestHeadersUriSpec.class);

        when(restClient.get()).thenReturn(requestHeadersUriSpec);
        when(requestHeadersUriSpec.uri(anyString())).thenReturn(requestHeadersSpec);
        when(requestHeadersSpec.headers(any())).thenReturn(requestHeadersSpec);
        when(requestHeadersSpec.retrieve()).thenThrow(new RestClientException("API call failed"));

        // ユーザー情報の取得を実行
        OidcUserInfoDto result = oidcClient.getUserInfo(providerName, accessToken);

        // 検証
        assertThat(result).isNull();
    }
}
