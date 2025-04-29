package com.example.keirekipro.unit.presentation.auth.controller;

import static org.hamcrest.Matchers.hasItem;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.auth.controller.RequestPasswordResetController;
import com.example.keirekipro.presentation.auth.dto.RequestPasswordResetRequest;
import com.example.keirekipro.usecase.auth.RequestPasswordResetUseCase;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(RequestPasswordResetController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class RequestPasswordResetControllerTest {

    @MockitoBean
    private final RequestPasswordResetUseCase requestPasswordResetUseCase;

    private final MockMvc mockMvc;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String VALID_EMAIL = "test@keirekipro.click";

    @Test
    @DisplayName("パスワードリセット要求が正常に完了する")
    void test1() throws Exception {
        RequestPasswordResetRequest request = new RequestPasswordResetRequest(VALID_EMAIL);
        String requestBody = objectMapper.writeValueAsString(request);

        mockMvc.perform(post("/auth/password/reset/request")
                .contentType("application/json")
                .content(requestBody))
                .andExpect(status().isNoContent());

        verify(requestPasswordResetUseCase).execute(VALID_EMAIL);
    }

    @Test
    @DisplayName("メールアドレスが空の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        RequestPasswordResetRequest request = new RequestPasswordResetRequest("");
        String requestBody = objectMapper.writeValueAsString(request);

        mockMvc.perform(post("/auth/password/reset/request")
                .contentType("application/json")
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email").isArray())
                .andExpect(jsonPath("$.errors.email", hasItem("メールアドレスは入力必須です。")));

        verify(requestPasswordResetUseCase, never()).execute(anyString());
    }

    @Test
    @DisplayName("メールアドレス形式が不正の場合、バリデーションエラーとなる")
    void test3() throws Exception {
        RequestPasswordResetRequest request = new RequestPasswordResetRequest("invalid-email");
        String requestBody = objectMapper.writeValueAsString(request);

        mockMvc.perform(post("/auth/password/reset/request")
                .contentType("application/json")
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email").isArray())
                .andExpect(jsonPath("$.errors.email", hasItem("メールアドレスの形式が無効です。")));

        verify(requestPasswordResetUseCase, never()).execute(anyString());
    }
}
