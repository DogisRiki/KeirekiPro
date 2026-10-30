package com.example.keirekipro.unit.presentation.auth.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.auth.controller.ResendEmailVerificationController;
import com.example.keirekipro.presentation.auth.controller.ResendEmailVerificationForLoginController;
import com.example.keirekipro.presentation.auth.controller.VerifyEmailController;
import com.example.keirekipro.presentation.security.config.SecurityConfig;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.usecase.auth.ResendEmailVerificationForLoginUseCase;
import com.example.keirekipro.usecase.auth.ResendEmailVerificationUseCase;
import com.example.keirekipro.usecase.auth.VerifyEmailUseCase;
import com.example.keirekipro.usecase.auth.dto.VerifyEmailUseCaseDto;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationResult;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

/**
 * 確認と送り直しの API が、ログインしていない要求を受け付けることを、本番のセキュリティの設定で確かめる
 */
@WebMvcTest({ VerifyEmailController.class, ResendEmailVerificationController.class,
        ResendEmailVerificationForLoginController.class })
@Import(SecurityConfig.class)
@TestPropertySource(properties = "cors.allowed-origins=http://localhost:5173")
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class EmailVerificationSecurityTest {

    @MockitoBean
    private final VerifyEmailUseCase verifyEmailUseCase;

    @MockitoBean
    private final ResendEmailVerificationUseCase resendEmailVerificationUseCase;

    @MockitoBean
    private final ResendEmailVerificationForLoginUseCase resendEmailVerificationForLoginUseCase;

    @MockitoBean
    private final JwtProvider jwtProvider;

    private final MockMvc mockMvc;

    private static final String TOKEN_BODY = "{\"token\":\"mock-token\"}";

    @Test
    @DisplayName("ログインしていない要求でも、確認のリンクを受け付ける API は 200 を返す")
    void test1() throws Exception {
        when(verifyEmailUseCase.execute(any()))
                .thenReturn(VerifyEmailUseCaseDto.of(EmailVerificationResult.VERIFIED));

        mockMvc.perform(post("/api/auth/email-verification/verify")
                .contentType(MediaType.APPLICATION_JSON)
                .content(TOKEN_BODY))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("ログインしていない要求でも、確認のメールを送り直す API は 204 を返す")
    void test2() throws Exception {
        mockMvc.perform(post("/api/auth/email-verification/resend")
                .contentType(MediaType.APPLICATION_JSON)
                .content(TOKEN_BODY))
                .andExpect(status().isNoContent());
    }

    @Test
    @DisplayName("ログインしていない要求でも、ログインの画面から確認のメールを送る API は 204 を返す")
    void test3() throws Exception {
        mockMvc.perform(post("/api/auth/email-verification/resend-for-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"test@keirekipro.click\",\"password\":\"hashedPassword\"}"))
                .andExpect(status().isNoContent());
    }
}
