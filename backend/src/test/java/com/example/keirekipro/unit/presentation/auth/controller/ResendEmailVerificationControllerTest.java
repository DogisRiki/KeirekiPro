package com.example.keirekipro.unit.presentation.auth.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.auth.controller.ResendEmailVerificationController;
import com.example.keirekipro.presentation.auth.dto.EmailVerificationTokenRequest;
import com.example.keirekipro.usecase.auth.ResendEmailVerificationUseCase;
import tools.jackson.databind.json.JsonMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(ResendEmailVerificationController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class ResendEmailVerificationControllerTest {

    @MockitoBean
    private final ResendEmailVerificationUseCase resendEmailVerificationUseCase;

    private final MockMvc mockMvc;

    private final JsonMapper objectMapper = JsonMapper.builder().build();

    private static final String ENDPOINT = "/api/auth/email-verification/resend";

    private static final String TOKEN = "mock-token";

    @Test
    @DisplayName("送り直すと 204 を返す")
    void test1() throws Exception {
        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody(TOKEN)))
                .andExpect(status().isNoContent());

        verify(resendEmailVerificationUseCase).execute(eq(TOKEN));
    }

    @Test
    @DisplayName("2049文字のトークンは 400 を返す")
    void test2() throws Exception {
        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody("a".repeat(2049))))
                .andExpect(status().isBadRequest());

        verify(resendEmailVerificationUseCase, never()).execute(any());
    }

    private String requestBody(String token) throws Exception {
        return objectMapper.writeValueAsString(new EmailVerificationTokenRequest(token));
    }
}
