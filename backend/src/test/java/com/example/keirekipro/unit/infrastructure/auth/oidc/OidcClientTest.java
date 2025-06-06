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
import java.util.List;
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
import org.springframework.util.MultiValueMap;
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

    private static final String PROVIDER_NAME = "google";
    private static final String REDIRECT_URI = "https://keirekipro.click/api/auth/oidc/callback";
    private static final String STATE = "random-state";
    private static final String CODE_CHALLENGE = "code-challenge";
    private static final String CODE_VERIFIER = "code-verifier";
    private static final String CODE = "authorization-code";
    private static final String ACCESS_TOKEN = "access-token";
    private static final String USER_INFO_ENDOPOINT = "https://openidconnect.googleapis.com/v1/userinfo";

    @Test
    @DisplayName("認可URLが正しく構築される")
    void test1() {
        // モックをセットアップ
        when(providerFactory.getProvider(PROVIDER_NAME)).thenReturn(oidcProvider);
        when(oidcProvider.getSecretName()).thenReturn("google-oidc-secret");
        when(oidcProvider.getAuthorizationEndpoint()).thenReturn("https://accounts.google.com/o/oauth2/auth");
        when(oidcProvider.getScopes()).thenReturn("openid email profile");

        // AWS Secrets ManagerからクライアントIDを取得する箇所をモック
        JsonNode jsonNode = objectMapper.createObjectNode();
        ((ObjectNode) jsonNode).put("client_id", "mock-client-id");
        when(secretsClient.getSecretJson("google-oidc-secret")).thenReturn(jsonNode);

        // 認可URLの構築を実行
        String result = oidcClient.buildAuthorizationUrl(PROVIDER_NAME, REDIRECT_URI, STATE, CODE_CHALLENGE);

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
        // モックをセットアップ
        when(providerFactory.getProvider(PROVIDER_NAME)).thenReturn(oidcProvider);
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
        String result = oidcClient.buildAuthorizationUrl(PROVIDER_NAME, REDIRECT_URI, STATE, CODE_CHALLENGE);

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
        // モックをセットアップ
        when(providerFactory.getProvider(PROVIDER_NAME)).thenReturn(oidcProvider);
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
        RestClient.ResponseSpec responseSpec = mock(RestClient.ResponseSpec.class);

        when(restClient.post()).thenReturn(requestBodyUriSpec);
        when(requestBodyUriSpec.uri(anyString())).thenReturn(requestBodySpec);
        when(requestBodySpec.contentType(any(MediaType.class))).thenReturn(requestBodySpec);
        when(requestBodySpec.header(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE)).thenReturn(requestBodySpec);
        when(requestBodySpec.body(any(MultiValueMap.class))).thenReturn(requestBodySpec);
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
        ArgumentCaptor<MultiValueMap<String, String>> formDataCaptor = ArgumentCaptor
                .forClass((Class) MultiValueMap.class);

        // アクセストークンの取得を実行
        OidcTokenResponse result = oidcClient.getToken(PROVIDER_NAME, CODE, REDIRECT_URI, CODE_VERIFIER);

        // requestBodySpec.bodyメソッドが呼ばれた際に渡されたパラメータをキャプチャするよう指定
        verify(requestBodySpec).body(formDataCaptor.capture());

        // .header()呼び出しが正しく行われているか検証
        verify(requestBodySpec).header(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE);

        // キャプチャの取得
        MultiValueMap<String, String> formData = formDataCaptor.getValue();

        // レスポンスの検証
        assertThat(result)
                .isNotNull()
                .isEqualTo(expectedResponse);

        // リクエストパラメータに必要なパラメータがすべて含まれているかをキャプチャから検証
        assertThat(formData)
                .containsEntry("grant_type", List.of("authorization_code"))
                .containsEntry("code", List.of(CODE))
                .containsEntry("redirect_uri", List.of(REDIRECT_URI))
                .containsEntry("code_verifier", List.of(CODE_VERIFIER));
    }

    @Test
    @DisplayName("プロバイダー固有のパラメータを付与した状態でアクセストークンを取得できる")
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void test4() {
        // モックをセットアップ
        when(providerFactory.getProvider(PROVIDER_NAME)).thenReturn(oidcProvider);
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
        when(requestBodySpec.header(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE)).thenReturn(requestBodySpec);
        when(requestBodySpec.body(any(MultiValueMap.class))).thenReturn(requestBodySpec);
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
        ArgumentCaptor<MultiValueMap<String, String>> formDataCaptor = ArgumentCaptor
                .forClass((Class) MultiValueMap.class);

        // アクセストークンの取得を実行
        OidcTokenResponse result = oidcClient.getToken(PROVIDER_NAME, CODE, REDIRECT_URI, CODE_VERIFIER);

        // requestBodySpec.bodyメソッドが呼ばれた際に渡されたパラメータをキャプチャするよう指定
        verify(requestBodySpec).body(formDataCaptor.capture());

        // キャプチャの取得
        MultiValueMap<String, String> formData = formDataCaptor.getValue();

        // レスポンスの検証
        assertThat(result)
                .isNotNull()
                .isEqualTo(expectedResponse);

        // リクエストパラメータに必要なパラメータがすべて含まれているかをキャプチャから検証
        assertThat(formData)
                .containsEntry("grant_type", List.of("authorization_code"))
                .containsEntry("code", List.of(CODE))
                .containsEntry("redirect_uri", List.of(REDIRECT_URI))
                .containsEntry("code_verifier", List.of(CODE_VERIFIER))
                .containsEntry("unique_param", List.of("mock-unique_param"));
    }

    @Test
    @DisplayName("アクセストークンの取得に失敗した場合、エラーレスポンスが返却される")
    void test5() {
        // モックをセットアップ
        when(providerFactory.getProvider(PROVIDER_NAME)).thenReturn(oidcProvider);
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
        when(requestBodySpec.header(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE)).thenReturn(requestBodySpec);
        when(requestBodySpec.body(anyMap())).thenReturn(requestBodySpec);
        // RestClientExceptionをスローするように設定
        when(requestBodySpec.retrieve()).thenThrow(new RestClientException("API call failed"));

        // アクセストークンの取得を実行
        OidcTokenResponse result = oidcClient.getToken(PROVIDER_NAME, CODE, REDIRECT_URI, CODE_VERIFIER);

        // 検証
        assertThat(result.getError()).isEqualTo("server_error");
        assertThat(result.getErrorDescription()).contains("トークン取得処理中にエラーが発生しました");
        assertThat(result.getErrorDescription()).contains("API call failed");
    }

    @Test
    @DisplayName("userinfoエンドポイントからユーザー情報を取得できる")
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void test6() {
        when(providerFactory.getProvider(PROVIDER_NAME)).thenReturn(oidcProvider);
        when(oidcProvider.getUserInfoEndpoint()).thenReturn(USER_INFO_ENDOPOINT);

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
                .providerType(PROVIDER_NAME)
                .build();

        // convertToStandardUserInfo内でaccess_tokenがuserInfoに追加されている前提で検証
        doAnswer(invocation -> {
            Map<String, Object> actualUserInfo = invocation.getArgument(0);
            assertThat(actualUserInfo.get("access_token")).isEqualTo(ACCESS_TOKEN);
            return expectedUserInfo;
        }).when(oidcProvider).convertToStandardUserInfo(any(Map.class));

        // 実行
        OidcUserInfoDto result = oidcClient.getUserInfo(PROVIDER_NAME, ACCESS_TOKEN);

        assertThat(result).isEqualTo(expectedUserInfo);
    }

    @Test
    @DisplayName("プロバイダー固有のヘッダーを付与した状態でuserinfoエンドポイントからユーザー情報の取得ができる")
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void test7() {
        // モックをセットアップ
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
        OidcUserInfoDto result = oidcClient.getUserInfo("github", ACCESS_TOKEN);

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
        assertThat(capturedHeaders.getFirst(HttpHeaders.AUTHORIZATION)).isEqualTo("Bearer " + ACCESS_TOKEN);

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
        // モックをセットアップ
        when(providerFactory.getProvider(PROVIDER_NAME)).thenReturn(oidcProvider);
        when(oidcProvider.getUserInfoEndpoint()).thenReturn(USER_INFO_ENDOPOINT);

        // RestClientをモック
        RestClient.RequestHeadersSpec requestHeadersSpec = mock(RestClient.RequestHeadersSpec.class);
        RestClient.RequestHeadersUriSpec requestHeadersUriSpec = mock(RestClient.RequestHeadersUriSpec.class);

        when(restClient.get()).thenReturn(requestHeadersUriSpec);
        when(requestHeadersUriSpec.uri(anyString())).thenReturn(requestHeadersSpec);
        when(requestHeadersSpec.headers(any())).thenReturn(requestHeadersSpec);
        when(requestHeadersSpec.retrieve()).thenThrow(new RestClientException("API call failed"));

        // ユーザー情報の取得を実行
        OidcUserInfoDto result = oidcClient.getUserInfo(PROVIDER_NAME, ACCESS_TOKEN);

        // 検証
        assertThat(result).isNull();
    }

    @Test
    @DisplayName("userinfoエンドポイントのレスポンスがnullの場合、nullが返却される")
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void test9() {
        // モックをセットアップ
        when(providerFactory.getProvider(PROVIDER_NAME)).thenReturn(oidcProvider);
        when(oidcProvider.getUserInfoEndpoint()).thenReturn(USER_INFO_ENDOPOINT);

        // RestClientをモック
        RestClient.RequestHeadersSpec requestHeadersSpec = mock(RestClient.RequestHeadersSpec.class);
        RestClient.RequestHeadersUriSpec requestHeadersUriSpec = mock(RestClient.RequestHeadersUriSpec.class);
        RestClient.ResponseSpec responseSpec = mock(RestClient.ResponseSpec.class);

        when(restClient.get()).thenReturn(requestHeadersUriSpec);
        when(requestHeadersUriSpec.uri(anyString())).thenReturn(requestHeadersSpec);
        when(requestHeadersSpec.headers(any())).thenReturn(requestHeadersSpec);
        when(requestHeadersSpec.retrieve()).thenReturn(responseSpec);

        // body() が null を返す設定
        when(responseSpec.body(any(ParameterizedTypeReference.class))).thenReturn(null);

        // 実行
        OidcUserInfoDto result = oidcClient.getUserInfo(PROVIDER_NAME, ACCESS_TOKEN);

        // 検証
        assertThat(result).isNull();
    }
}
