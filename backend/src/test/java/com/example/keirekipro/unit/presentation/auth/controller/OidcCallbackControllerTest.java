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

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.presentation.auth.controller.OidcCallbackController;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.usecase.auth.HandleOidcCallbackUseCase;
import com.example.keirekipro.usecase.auth.oidc.OidcCallbackError;
import com.example.keirekipro.usecase.auth.oidc.OidcCallbackResult;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(OidcCallbackController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
@TestPropertySource(properties = { "frontend-base-url=http://localhost:3000" })
class OidcCallbackControllerTest {

    @MockitoBean
    private JwtProvider jwtProvider;

    @MockitoBean
    private HandleOidcCallbackUseCase handleOidcCallbackUseCase;

    private final MockMvc mockMvc;

    private static final String CODE_VALUE = "randomCode";
    private static final String STATE_VALUE = "randomState";
    private static final UUID ID = UUID.randomUUID();

    private static final String CALLBACK_PATH = "/api/auth/oidc/callback";
    private static final String FRONTEND_REDIRECT_PATH = "/resume/list";

    private static final String AUTH_ERROR_REDIRECT_URL = "/login?error="
            + URLEncoder.encode("認証に失敗しました。しばらく時間を置いてから再度お試しください。", StandardCharsets.UTF_8);

    private static final String USER_ERROR_REDIRECT_URL = "/login?error="
            + URLEncoder.encode("ユーザー情報の取得に失敗しました。しばらく時間を置いてから再度お試しください。", StandardCharsets.UTF_8);

    private static final String FRONTEND_BASE_URL = "http://localhost:3000";

    @Test
    @DisplayName("OIDCコールバックで認証に成功し、成功ページへリダイレクトされる")
    void test1() throws Exception {
        // モックをセットアップ
        Set<String> roles = Set.of("USER");
        when(handleOidcCallbackUseCase.execute(eq(CODE_VALUE), eq(STATE_VALUE), eq(null), anyString()))
                .thenReturn(new OidcCallbackResult.Success(ID, roles));

        when(jwtProvider.createAccessToken(eq(ID.toString()), eq(roles))).thenReturn("mockAccessToken");
        when(jwtProvider.createRefreshToken(eq(ID.toString()), eq(roles))).thenReturn("mockRefreshToken");

        // リクエストを実行
        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(FRONTEND_BASE_URL + FRONTEND_REDIRECT_PATH))
                .andExpect(header().exists("Set-Cookie"))
                .andExpect(header().stringValues(
                        "Set-Cookie",
                        containsInAnyOrder(
                                containsString("accessToken=mockAccessToken"),
                                containsString("refreshToken=mockRefreshToken"))));

        // 呼び出し検証
        verify(handleOidcCallbackUseCase).execute(eq(CODE_VALUE), eq(STATE_VALUE), eq(null), anyString());
        verify(jwtProvider).createAccessToken(ID.toString(), roles);
        verify(jwtProvider).createRefreshToken(ID.toString(), roles);
    }

    @Test
    @DisplayName("errorパラメータが存在する場合、エラーページへリダイレクトされる")
    void test2() throws Exception {
        when(handleOidcCallbackUseCase.execute(eq(null), eq(null), eq("access_denied"), anyString()))
                .thenReturn(new OidcCallbackResult.Failure(OidcCallbackError.PROVIDER_ERROR_PARAMETER));

        mockMvc.perform(get(CALLBACK_PATH)
                .param("error", "access_denied"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(FRONTEND_BASE_URL + AUTH_ERROR_REDIRECT_URL));

        verify(handleOidcCallbackUseCase).execute(eq(null), eq(null), eq("access_denied"), anyString());
    }

    @Test
    @DisplayName("codeまたはstateがnullの場合、エラーページへリダイレクトされる")
    void test3() throws Exception {
        // codeが無い
        when(handleOidcCallbackUseCase.execute(eq(null), eq(STATE_VALUE), eq(null), anyString()))
                .thenReturn(new OidcCallbackResult.Failure(OidcCallbackError.MISSING_REQUIRED_PARAMETER));

        mockMvc.perform(get(CALLBACK_PATH)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(FRONTEND_BASE_URL + AUTH_ERROR_REDIRECT_URL));

        verify(handleOidcCallbackUseCase).execute(eq(null), eq(STATE_VALUE), eq(null), anyString());

        // stateがない
        when(handleOidcCallbackUseCase.execute(eq(CODE_VALUE), eq(null), eq(null), anyString()))
                .thenReturn(new OidcCallbackResult.Failure(OidcCallbackError.MISSING_REQUIRED_PARAMETER));

        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(FRONTEND_BASE_URL + AUTH_ERROR_REDIRECT_URL));

        verify(handleOidcCallbackUseCase).execute(eq(CODE_VALUE), eq(null), eq(null), anyString());
    }

    @Test
    @DisplayName("コールバック処理が失敗し、USERINFO_FETCH_FAILEDの場合はユーザー情報エラーでリダイレクトされる")
    void test4() throws Exception {
        when(handleOidcCallbackUseCase.execute(eq(CODE_VALUE), eq(STATE_VALUE), eq(null), anyString()))
                .thenReturn(new OidcCallbackResult.Failure(OidcCallbackError.USERINFO_FETCH_FAILED));

        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(FRONTEND_BASE_URL + USER_ERROR_REDIRECT_URL));

        verify(handleOidcCallbackUseCase).execute(eq(CODE_VALUE), eq(STATE_VALUE), eq(null), anyString());
    }

    @Test
    @DisplayName("コールバック処理が失敗し、USERINFO_FETCH_FAILED以外の場合は認証エラーでリダイレクトされる")
    void test5() throws Exception {
        when(handleOidcCallbackUseCase.execute(eq(CODE_VALUE), eq(STATE_VALUE), eq(null), anyString()))
                .thenReturn(new OidcCallbackResult.Failure(OidcCallbackError.INVALID_OR_EXPIRED_STATE));

        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(FRONTEND_BASE_URL + AUTH_ERROR_REDIRECT_URL));

        verify(handleOidcCallbackUseCase).execute(eq(CODE_VALUE), eq(STATE_VALUE), eq(null), anyString());
    }

    @Test
    @DisplayName("例外が発生した場合、認証エラーでリダイレクトされる")
    void test6() throws Exception {
        when(handleOidcCallbackUseCase.execute(eq(CODE_VALUE), eq(STATE_VALUE), eq(null), anyString()))
                .thenThrow(new RuntimeException("unexpected"));

        mockMvc.perform(get(CALLBACK_PATH)
                .param("code", CODE_VALUE)
                .param("state", STATE_VALUE))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl(FRONTEND_BASE_URL + AUTH_ERROR_REDIRECT_URL));

        verify(handleOidcCallbackUseCase).execute(eq(CODE_VALUE), eq(STATE_VALUE), eq(null), anyString());
    }
}
