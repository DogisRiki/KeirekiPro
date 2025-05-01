package com.example.keirekipro.unit.presentation.auth.controller;

import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.auth.oidc.OidcClient;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcTokenResponse;
import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.presentation.auth.controller.OidcCallbackController;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.usecase.auth.OidcLoginUseCase;
import com.example.keirekipro.usecase.auth.dto.OidcLoginUseCaseDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(OidcCallbackController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class OidcCallbackControllerTest {

    @MockitoBean
    private OidcClient oidcClient;

    @MockitoBean
    private JwtProvider jwtProvider;

    @MockitoBean
    private RedisClient redisClient;

    @MockitoBean
    private OidcLoginUseCase oidcLoginUseCase;

    private final MockMvc mockMvc;

    private static final String CODE_VALUE = "randomCode";
    private static final String STATE_VALUE = "randomState";
    private static final String PROVIDER_VALUE = "google";
    private static final String CODE_VERIFIER = "randomVerifier";
    private static final String ACCESS_TOKEN = "randomAccessToken";
    private static final String ID_TOKEN = "randomIdToken";
    private static final UUID ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PROVIDER_USER_ID = "999";
    private static final String CALLBACK_PATH = "/api/auth/oidc/callback";
    private static final String FRONTEND_REDIRECT_PATH = "/resume/list";
    private static final String AUTH_ERROR_REDIRECT_URL = "/login?error=認証に失敗しました。しばらく時間を置いてから再度お試しください。";
    private static final String USER_ERROR_REDIRECT_URL = "/login?error=ユーザー情報の取得に失敗しました。しばらく時間を置いてから再度お試しください。";

    @Test
    @DisplayName("OIDCコールバックで認証に成功し、成功ページへリダイレクトされる")
    void test1() throws Exception {
        // stateの検証をモック
        when(redisClient.hasKey("oidc:state:" + STATE_VALUE)).thenReturn(true);
        // プロバイダーの取得をモック
        when(redisClient.getValue(eq("oidc:provider:" + STATE_VALUE), eq(String.class)))
                .thenReturn(Optional.of(PROVIDER_VALUE));
        // codeVerifierの取得をモック
        when(redisClient.getValue(eq("oidc:code_verifier:" + STATE_VALUE), eq(String.class)))
                .thenReturn(Optional.of(CODE_VERIFIER));

        // テスト用のOidcTokenResponseを作成
        OidcTokenResponse tokenResponse = new OidcTokenResponse();
        tokenResponse.setAccessToken(ACCESS_TOKEN);
        tokenResponse.setIdToken(ID_TOKEN);
        tokenResponse.setError(null);
        tokenResponse.setErrorDescription(null);
        // getToken()実行時、テスト用のOidcTokenResponseを返すようにモック
        when(oidcClient.getToken(eq(PROVIDER_VALUE), eq(CODE_VALUE), anyString(), eq(CODE_VERIFIER)))
                .thenReturn(tokenResponse);

        // テスト用のOidcUserInfoDtoを作成
        OidcUserInfoDto userInfoDto = OidcUserInfoDto.builder()
                .providerUserId(PROVIDER_USER_ID)
                .email(EMAIL)
                .username(USERNAME)
                .providerType(PROVIDER_VALUE)
                .build();
        // getUserInfo()実行時、テスト用のOidcUserInfoDtoを返すようにモック
        when(oidcClient.getUserInfo(PROVIDER_VALUE, ACCESS_TOKEN)).thenReturn(userInfoDto);

        // テスト用のOidcLoginUseCaseDtoを作成
        OidcLoginUseCaseDto loginResult = OidcLoginUseCaseDto.builder()
                .id(ID)
                .email(EMAIL)
                .username(USERNAME)
                .providerType(PROVIDER_VALUE)
                .build();
        // ユースケース実行時、テスト用のOidcLoginUseCaseDtoを返すようにモック
        when(oidcLoginUseCase.execute(userInfoDto)).thenReturn(loginResult);

        // モックをセットアップ
        when(jwtProvider.createAccessToken(eq(ID.toString()))).thenReturn("mockAccessToken");
        when(jwtProvider.createRefreshToken(eq(ID.toString()))).thenReturn("mockRefreshToken");

        // リクエストを実行
        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection()) // 302が返る
                .andExpect(redirectedUrl("http://localhost" + FRONTEND_REDIRECT_PATH)) // リダイレクト先が正しい
                .andExpect(header().exists("Set-Cookie"))
                .andExpect(header().stringValues(
                        "Set-Cookie",
                        containsInAnyOrder(
                                containsString("accessToken=mockAccessToken"),
                                containsString("refreshToken=mockRefreshToken"))));

        // 呼び出し検証を追加
        verify(oidcClient).getToken(eq(PROVIDER_VALUE), eq(CODE_VALUE), anyString(), eq(CODE_VERIFIER));
        verify(oidcClient).getUserInfo(PROVIDER_VALUE, ACCESS_TOKEN);
        verify(oidcLoginUseCase).execute(userInfoDto);
        verify(redisClient).deleteValue("oidc:state:" + STATE_VALUE);
        verify(redisClient).deleteValue("oidc:provider:" + STATE_VALUE);
        verify(redisClient).deleteValue("oidc:code_verifier:" + STATE_VALUE);
        verify(jwtProvider).createAccessToken(ID.toString());
        verify(jwtProvider).createRefreshToken(ID.toString());
    }

    @Test
    @DisplayName("errorパラメータが存在する場合、エラーページへリダイレクトされる")
    void test2() throws Exception {
        mockMvc.perform(get(CALLBACK_PATH)
                .param("error", "access_denied")) // エラーパラメータを付与
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(AUTH_ERROR_REDIRECT_URL));
    }

    @Test
    @DisplayName("codeまたはstateがnullの場合、エラーページへリダイレクトされる")
    void test3() throws Exception {
        // codeが無い
        mockMvc.perform(get(CALLBACK_PATH)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(AUTH_ERROR_REDIRECT_URL));

        // stateがない
        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(AUTH_ERROR_REDIRECT_URL));
    }

    @Test
    @DisplayName("stateがRedisに存在しない場合、エラーページへリダイレクトされる")
    void test4() throws Exception {
        // モックをセットアップ
        when(redisClient.hasKey("oidc:state:" + STATE_VALUE)).thenReturn(false);

        // リクエストを実行
        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(AUTH_ERROR_REDIRECT_URL));
    }

    @Test
    @DisplayName("プロバイダー情報またはcodeVerifierがRedisに存在しない場合、エラーページへリダイレクトされる")
    void test5() throws Exception {
        // モックをセットアップ
        when(redisClient.hasKey("oidc:state:" + STATE_VALUE)).thenReturn(true);
        when(redisClient.getValue(eq("oidc:provider:" + STATE_VALUE), eq(String.class)))
                .thenReturn(Optional.empty());
        when(redisClient.getValue(eq("oidc:code_verifier:" + STATE_VALUE), eq(String.class)))
                .thenReturn(Optional.of(CODE_VERIFIER));

        // リクエストを実行
        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(AUTH_ERROR_REDIRECT_URL));

        // 2回目
        when(redisClient.hasKey("oidc:state:" + STATE_VALUE)).thenReturn(true);
        when(redisClient.getValue(eq("oidc:provider:" + STATE_VALUE), eq(String.class)))
                .thenReturn(Optional.of(PROVIDER_VALUE));
        when(redisClient.getValue(eq("oidc:code_verifier:" + STATE_VALUE), eq(String.class)))
                .thenReturn(Optional.empty());

        // リクエストを実行
        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(AUTH_ERROR_REDIRECT_URL));
    }

    @Test
    @DisplayName("アクセストークン取得結果にエラーが入っている場合、エラーページへリダイレクトされる")
    void test6() throws Exception {
        // モックをセットアップ
        when(redisClient.hasKey("oidc:state:" + STATE_VALUE)).thenReturn(true);
        when(redisClient.getValue(eq("oidc:provider:" + STATE_VALUE), eq(String.class)))
                .thenReturn(Optional.of(PROVIDER_VALUE));
        when(redisClient.getValue(eq("oidc:code_verifier:" + STATE_VALUE), eq(String.class)))
                .thenReturn(Optional.of(CODE_VERIFIER));

        // テスト用のOidcTokenResponseを作成
        OidcTokenResponse tokenResponse = new OidcTokenResponse();
        tokenResponse.setError("invalid_request");
        tokenResponse.setErrorDescription("some error");
        // getToken()実行時、テスト用のOidcTokenResponseを返すようにモック
        when(oidcClient.getToken(eq(PROVIDER_VALUE), eq(CODE_VALUE), anyString(), eq(CODE_VERIFIER)))
                .thenReturn(tokenResponse);

        // リクエストを実行
        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(AUTH_ERROR_REDIRECT_URL));
    }

    @Test
    @DisplayName("ユーザー取得結果がnullの場合、エラーページへリダイレクトされる")
    void test7() throws Exception {
        // モックをセットアップ
        when(redisClient.hasKey("oidc:state:" + STATE_VALUE)).thenReturn(true);
        when(redisClient.getValue(eq("oidc:provider:" + STATE_VALUE), eq(String.class)))
                .thenReturn(Optional.of(PROVIDER_VALUE));
        when(redisClient.getValue(eq("oidc:code_verifier:" + STATE_VALUE), eq(String.class)))
                .thenReturn(Optional.of(CODE_VERIFIER));

        // テスト用のOidcTokenResponseを作成(エラーなし)
        OidcTokenResponse tokenResponse = new OidcTokenResponse();
        tokenResponse.setAccessToken(ACCESS_TOKEN);
        tokenResponse.setError(null);
        // getToken()実行時、テスト用のOidcTokenResponseを返すようにモック
        when(oidcClient.getToken(eq(PROVIDER_VALUE), eq(CODE_VALUE), anyString(), eq(CODE_VERIFIER)))
                .thenReturn(tokenResponse);

        // getUserInfo()実行時、nullを返すようにモック
        when(oidcClient.getUserInfo(PROVIDER_VALUE, ACCESS_TOKEN)).thenReturn(null);

        // リクエストを実行
        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(USER_ERROR_REDIRECT_URL));
    }
}
