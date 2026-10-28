package com.example.keirekipro.unit.presentation.auth.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.auth.controller.ResendEmailVerificationForLoginController;
import com.example.keirekipro.presentation.auth.dto.ResendEmailVerificationForLoginRequest;
import com.example.keirekipro.usecase.auth.ResendEmailVerificationForLoginUseCase;
import com.example.keirekipro.usecase.auth.command.ResendEmailVerificationForLoginCommand;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(ResendEmailVerificationForLoginController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class ResendEmailVerificationForLoginControllerTest {

    @MockitoBean
    private final ResendEmailVerificationForLoginUseCase resendEmailVerificationForLoginUseCase;

    private final MockMvc mockMvc;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String ENDPOINT = "/api/auth/email-verification/resend-for-login";

    private static final String EMAIL = "test@keirekipro.click";

    private static final String PASSWORD = "hashedPassword";

    @Test
    @DisplayName("メールアドレスとパスワードで送ると 204 を返す")
    void test1() throws Exception {
        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody(EMAIL, PASSWORD)))
                .andExpect(status().isNoContent());

        ArgumentCaptor<ResendEmailVerificationForLoginCommand> captor = ArgumentCaptor
                .forClass(ResendEmailVerificationForLoginCommand.class);
        verify(resendEmailVerificationForLoginUseCase).execute(captor.capture());
        assertThat(captor.getValue().getEmail()).isEqualTo(EMAIL);
        assertThat(captor.getValue().getPassword()).isEqualTo(PASSWORD);
    }

    @Test
    @DisplayName("メールアドレスが空なら 400 を返す")
    void test2() throws Exception {
        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody("", PASSWORD)))
                .andExpect(status().isBadRequest());

        verify(resendEmailVerificationForLoginUseCase, never()).execute(any());
    }

    @Test
    @DisplayName("パスワードが空なら 400 を返す")
    void test3() throws Exception {
        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody(EMAIL, "")))
                .andExpect(status().isBadRequest());

        verify(resendEmailVerificationForLoginUseCase, never()).execute(any());
    }

    private String requestBody(String email, String password) throws Exception {
        return objectMapper.writeValueAsString(new ResendEmailVerificationForLoginRequest(email, password));
    }
}
