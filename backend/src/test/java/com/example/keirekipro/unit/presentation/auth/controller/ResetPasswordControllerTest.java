package com.example.keirekipro.unit.presentation.auth.controller;

import static org.hamcrest.Matchers.hasItem;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.auth.controller.ResetPasswordController;
import com.example.keirekipro.presentation.auth.dto.ResetPasswordRequest;
import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.usecase.auth.ResetPasswordUseCase;
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

@WebMvcTest(ResetPasswordController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class ResetPasswordControllerTest {

    @MockitoBean
    private final ResetPasswordUseCase resetPasswordUseCase;

    @MockitoBean
    private final CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String PASSWORD = "Password123";
    private static final String INVALID_PASSWORD = "short";

    @Test
    @DisplayName("新しいパスワードが空の場合、バリデーションエラーとなる")
    void test1() throws Exception {
        ResetPasswordRequest request = new ResetPasswordRequest("", "");

        String requestBody = objectMapper.writeValueAsString(request);

        mockMvc.perform(post("/auth/password/reset")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password").isArray())
                .andExpect(jsonPath("$.errors.password", hasItem("新しいパスワードは入力必須です。")))
                .andExpect(jsonPath("$.errors.confirmPassword").isArray())
                .andExpect(jsonPath("$.errors.confirmPassword", hasItem("新しいパスワード(確認用)は入力必須です。")));
    }

    @Test
    @DisplayName("新しいパスワードが8文字未満の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        ResetPasswordRequest request = new ResetPasswordRequest(INVALID_PASSWORD, INVALID_PASSWORD);

        String requestBody = objectMapper.writeValueAsString(request);

        mockMvc.perform(post("/auth/password/reset")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password").isArray())
                .andExpect(jsonPath("$.errors.password", hasItem("新しいパスワードは8文字以上20文字以内で入力してください。")))
                .andExpect(jsonPath("$.errors.password", hasItem("新しいパスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")));
    }

    @Test
    @DisplayName("新しいパスワードと確認パスワードが一致しない場合、バリデーションエラーとなる")
    void test3() throws Exception {
        ResetPasswordRequest request = new ResetPasswordRequest(PASSWORD, "DifferentPassword123");

        String requestBody = objectMapper.writeValueAsString(request);

        mockMvc.perform(post("/auth/password/reset")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.passwordMatching").isArray())
                .andExpect(jsonPath("$.errors.passwordMatching", hasItem("新しいパスワードと新しいパスワード(確認用)が一致していません。")));
    }
}
