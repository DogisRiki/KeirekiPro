package com.example.keirekipro.unit.presentation.auth.controller;

import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import com.example.keirekipro.presentation.auth.controller.TwoFactorAuthController;
import com.example.keirekipro.presentation.auth.dto.TwoFactorAuthRequest;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.usecase.auth.TwoFactorAuthVerifyUseCase;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(TwoFactorAuthController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class TwoFactorAuthControllerTest {

    @MockitoBean
    private TwoFactorAuthVerifyUseCase twoFactorAuthIssueUseCase;

    @MockitoBean
    private JwtProvider jwtProvider;

    private final MockMvc mockMvc;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String ENDPOINT = "/api/auth/2fa/verify";

    private static final String USER_ID = UUID.randomUUID().toString();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String ACCESS_TOKEN = "mockAccessToken";
    private static final String REFRESH_TOKEN = "mockRefreshToken";

    @Test
    @DisplayName("二段階認証コードの検証がOKの場合、JWTがSet-Cookieに設定される")
    void test1() throws Exception {
        // モックをセットアップ
        when(jwtProvider.createAccessToken(USER_ID))
                .thenReturn(ACCESS_TOKEN);
        when(jwtProvider.createRefreshToken(USER_ID))
                .thenReturn(REFRESH_TOKEN);

        // リクエストを準備
        TwoFactorAuthRequest request = new TwoFactorAuthRequest(USER_ID, EMAIL);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isOk())
                .andExpect(header().exists("Set-Cookie"))
                .andExpect(header().stringValues(
                        "Set-Cookie",
                        containsInAnyOrder(
                                containsString("accessToken=mockAccessToken"),
                                containsString("refreshToken=mockRefreshToken"))));

        // 呼び出し検証を追加
        verify(twoFactorAuthIssueUseCase).execute(UUID.fromString(USER_ID), EMAIL);
        verify(jwtProvider).createAccessToken(USER_ID);
        verify(jwtProvider).createRefreshToken(USER_ID);
    }

    @Test
    @DisplayName("バリデーションエラーの場合、適切なエラーレスポンスが返される")
    void test2() throws Exception {
        // リクエストを準備(codeが空)
        TwoFactorAuthRequest request = new TwoFactorAuthRequest(USER_ID, "");
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.code").isArray())
                .andExpect(jsonPath("$.errors.code[0]").value("認証コードは入力必須です。"));
    }
}
