package com.example.keirekipro.unit.presentation.auth.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.auth.controller.VerifyEmailController;
import com.example.keirekipro.presentation.auth.dto.EmailVerificationTokenRequest;
import com.example.keirekipro.usecase.auth.VerifyEmailUseCase;
import com.example.keirekipro.usecase.auth.dto.VerifyEmailUseCaseDto;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationResult;
import tools.jackson.databind.json.JsonMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(VerifyEmailController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class VerifyEmailControllerTest {

    @MockitoBean
    private final VerifyEmailUseCase verifyEmailUseCase;

    private final MockMvc mockMvc;

    private final JsonMapper objectMapper = JsonMapper.builder().build();

    private static final String ENDPOINT = "/api/auth/email-verification/verify";

    private static final String TOKEN = "mock-token";

    private static final String PASSWORD_RESET_TOKEN = "password-reset-token";

    @Test
    @DisplayName("結果と再設定のトークンを 200 で返す")
    void test1() throws Exception {
        when(verifyEmailUseCase.execute(eq(TOKEN)))
                .thenReturn(VerifyEmailUseCaseDto.passwordResetReady(PASSWORD_RESET_TOKEN));

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody(TOKEN)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result").value("PASSWORD_RESET_READY"))
                .andExpect(jsonPath("$.passwordResetToken").value(PASSWORD_RESET_TOKEN));

        verify(verifyEmailUseCase).execute(eq(TOKEN));
    }

    @ParameterizedTest
    @EnumSource(EmailVerificationResult.class)
    @DisplayName("どの結果でも 200 で結果を返す")
    void test2(EmailVerificationResult result) throws Exception {
        when(verifyEmailUseCase.execute(eq(TOKEN))).thenReturn(VerifyEmailUseCaseDto.of(result));

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody(TOKEN)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result").value(result.name()));
    }

    @Test
    @DisplayName("2048文字のトークンは受け付ける")
    void test3() throws Exception {
        String token = "a".repeat(2048);
        when(verifyEmailUseCase.execute(eq(token)))
                .thenReturn(VerifyEmailUseCaseDto.of(EmailVerificationResult.INVALID));

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody(token)))
                .andExpect(status().isOk());

        verify(verifyEmailUseCase).execute(eq(token));
    }

    @Test
    @DisplayName("2049文字のトークンは 400 を返す")
    void test4() throws Exception {
        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody("a".repeat(2049))))
                .andExpect(status().isBadRequest());

        verify(verifyEmailUseCase, never()).execute(any());
    }

    @Test
    @DisplayName("空のトークンは 400 を返す")
    void test5() throws Exception {
        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody("")))
                .andExpect(status().isBadRequest());

        verify(verifyEmailUseCase, never()).execute(any());
    }

    private String requestBody(String token) throws Exception {
        return objectMapper.writeValueAsString(new EmailVerificationTokenRequest(token));
    }
}
