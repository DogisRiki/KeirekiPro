package com.example.keirekipro.unit.presentation.auth.controller;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.auth.controller.VerifyPasswordResetTokenController;
import com.example.keirekipro.presentation.auth.dto.RequestPasswordResetVerifyRequest;
import com.example.keirekipro.usecase.auth.VerifyPasswordResetTokenUseCase;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(VerifyPasswordResetTokenController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class VerifyPasswordResetTokenControllerTest {

    @MockitoBean
    private final VerifyPasswordResetTokenUseCase verifyPasswordResetTokenUseCase;

    private final MockMvc mockMvc;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String ENDPOINT = "/api/auth/password/reset/verify";

    private static final String TOKEN = "mock-token";

    @Test
    @DisplayName("パスワードリセットトークン検証が成功する")
    void test1() throws Exception {
        // モックをセットアップ
        doNothing().when(verifyPasswordResetTokenUseCase).execute(eq(TOKEN));

        // リクエストを準備
        RequestPasswordResetVerifyRequest request = new RequestPasswordResetVerifyRequest(TOKEN);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .contentType("application/json")
                .content(requestBody))
                .andExpect(status().isNoContent());

        // 呼び出し検証
        verify(verifyPasswordResetTokenUseCase).execute(eq(TOKEN));
    }
}
