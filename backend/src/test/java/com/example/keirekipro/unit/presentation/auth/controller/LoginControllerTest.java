package com.example.keirekipro.unit.presentation.auth.controller;

import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anySet;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.presentation.auth.controller.LoginController;
import com.example.keirekipro.presentation.auth.dto.LoginRequest;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.usecase.auth.LoginUseCase;
import com.example.keirekipro.usecase.auth.TwoFactorAuthIssueUseCase;
import com.example.keirekipro.usecase.auth.dto.LoginUseCaseDto;
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

@WebMvcTest(LoginController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class LoginControllerTest {

    @MockitoBean
    private LoginUseCase loginUseCase;

    @MockitoBean
    private TwoFactorAuthIssueUseCase twoFactorAuthIssueUseCase;

    @MockitoBean
    private JwtProvider jwtProvider;

    private final MockMvc mockMvc;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String ENDPOINT = "/api/auth/login";

    private static final UUID USER_ID = UUID.randomUUID();
    private static final String EMAIL = "test@keirekipro.click";
    private static final String PASSWORD = "hashedPassword";
    private static final String ACCESS_TOKEN = "mockAccessToken";
    private static final String REFRESH_TOKEN = "mockRefreshToken";

    @Test
    @DisplayName("二段階認証設定が無効の場合、JWTがSet-Cookieに設定される")
    void test1() throws Exception {
        // モックをセットアップ
        Set<String> roles = Set.of("USER");
        when(loginUseCase.execute(any()))
                .thenReturn(LoginUseCaseDto.builder()
                        .id(USER_ID)
                        .email(EMAIL)
                        .twoFactorAuthEnabled(false)
                        .roles(roles)
                        .build());
        when(jwtProvider.createAccessToken(USER_ID.toString(), roles))
                .thenReturn(ACCESS_TOKEN);
        when(jwtProvider.createRefreshToken(USER_ID.toString(), roles))
                .thenReturn(REFRESH_TOKEN);

        // リクエストを準備
        LoginRequest request = new LoginRequest(EMAIL, PASSWORD);
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

        // 呼び出しを検証
        verify(loginUseCase).execute(request);
        verify(twoFactorAuthIssueUseCase, never()).execute(any(), any());
        verify(jwtProvider).createAccessToken(USER_ID.toString(), roles);
        verify(jwtProvider).createRefreshToken((USER_ID.toString()), roles);
    }

    @Test
    @DisplayName("二段階認証設定が有効の場合、二段階認証発行ユースケースが実行される")
    void test2() throws Exception {
        // モックをセットアップ
        Set<String> roles = Set.of("USER");
        when(loginUseCase.execute(any()))
                .thenReturn(LoginUseCaseDto.builder()
                        .id(USER_ID)
                        .email(EMAIL)
                        .twoFactorAuthEnabled(true)
                        .roles(roles)
                        .build());

        // リクエストを準備
        LoginRequest request = new LoginRequest(EMAIL, PASSWORD);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isAccepted())
                // JWTは発行されないためSet-Cookieヘッダーが存在しない
                .andExpect(header().doesNotExist("Set-Cookie"))
                .andExpect(jsonPath("$").value(USER_ID.toString()));

        // 呼び出しを検証
        verify(loginUseCase).execute(request);
        verify(twoFactorAuthIssueUseCase).execute(USER_ID, EMAIL);
        verify(jwtProvider, never()).createAccessToken(anyString(), anySet());
        verify(jwtProvider, never()).createRefreshToken(anyString(), anySet());
    }

    @Test
    @DisplayName("バリデーションエラーの場合、適切なエラーレスポンスが返される")
    void test3() throws Exception {
        // リクエストを準備(emailが空)
        LoginRequest emailEmptyRequest = new LoginRequest("", PASSWORD);
        String emailEmptyRequestBody = objectMapper.writeValueAsString(emailEmptyRequest);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(emailEmptyRequestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email[0]").value("メールアドレスは入力必須です。"))
                .andExpect(jsonPath("$.errors.password").doesNotExist());

        // リクエストを準備(passwordが空)
        LoginRequest passwordEmptyRequest = new LoginRequest(EMAIL, null);
        String passwordEmptyRequestBody = objectMapper.writeValueAsString(passwordEmptyRequest);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(passwordEmptyRequestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password[0]").value("パスワードは入力必須です。"))
                .andExpect(jsonPath("$.errors.email").doesNotExist());

        // リクエストを準備(emailとpasswordが空)
        LoginRequest bothEmptyRequest = new LoginRequest("", null);
        String bothEmptyRequestBody = objectMapper.writeValueAsString(bothEmptyRequest);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(bothEmptyRequestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email[0]").value("メールアドレスは入力必須です。"))
                .andExpect(jsonPath("$.errors.password[0]").value("パスワードは入力必須です。"));
    }
}
