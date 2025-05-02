package com.example.keirekipro.unit.presentation.user.controller;

import static org.hamcrest.Matchers.hasItem;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.controller.SetEmailAndPasswordController;
import com.example.keirekipro.presentation.user.dto.SetEmailAndPasswordRequest;
import com.example.keirekipro.usecase.user.SetEmailAndPasswordUseCase;
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

@WebMvcTest(SetEmailAndPasswordController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class SetEmailAndPasswordControllerTest {

    @MockitoBean
    private final SetEmailAndPasswordUseCase setEmailAndPasswordUseCase;

    @MockitoBean
    private final CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String ENDPOINT = "/api/users/me/email-password";

    private static final String USER_ID = "123e4567-e89b-12d3-a456-426614174000";
    private static final String PASSWORD = "Password123";

    @Test
    @DisplayName("正常にメールアドレスとパスワードを設定できる")
    void test1() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(
                "test@example.com",
                "Password123",
                "Password123");

        String json = objectMapper.writeValueAsString(request);

        // モックユーザーIDを返すようにセット
        when(currentUserFacade.getUserId()).thenReturn(USER_ID);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json))
                .andExpect(status().isNoContent());

        verify(setEmailAndPasswordUseCase)
                .execute(UUID.fromString(USER_ID), request);
    }

    @Test
    @DisplayName("メールアドレス形式が不正な場合、バリデーションエラーとなる")
    void test2() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest("invalid-email", PASSWORD, PASSWORD);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email").exists())
                .andExpect(jsonPath("$.errors.email", hasItem("メールアドレスの形式が無効です。")));
    }

    @Test
    @DisplayName("メールアドレスが255文字を超える場合、バリデーションエラーとなる")
    void test3() throws Exception {
        String longEmail = "a".repeat(245) + "@example.com";
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(longEmail, PASSWORD, PASSWORD);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email").exists())
                .andExpect(jsonPath("$.errors.email", hasItem("メールアドレスは255文字以内で入力してください。")));
    }

    @Test
    @DisplayName("パスワードが空の場合、バリデーションエラーとなる")
    void test4() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest("test@example.com", "", "");

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password").exists())
                .andExpect(jsonPath("$.errors.password", hasItem("パスワードは入力必須です。")));
    }

    @Test
    @DisplayName("メールアドレスがnullでも設定可能")
    void test5() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(
                null,
                "Password123",
                "Password123");

        String json = objectMapper.writeValueAsString(request);

        when(currentUserFacade.getUserId()).thenReturn(USER_ID);

        mockMvc.perform(post(
                ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json))
                .andExpect(status().isNoContent());

        verify(setEmailAndPasswordUseCase)
                .execute(UUID.fromString(USER_ID), request);
    }

    @Test
    @DisplayName("パスワードがnullの場合、バリデーションエラーとなる")
    void test6() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(
                "test@example.com",
                null,
                null);

        String json = objectMapper.writeValueAsString(request);

        mockMvc.perform(post(
                ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("メールアドレスとパスワードの両方がnullの場合、バリデーションエラーとなる")
    void test7() throws Exception {
        SetEmailAndPasswordRequest request = new SetEmailAndPasswordRequest(
                null,
                null,
                null);

        String json = objectMapper.writeValueAsString(request);

        mockMvc.perform(post(ENDPOINT)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json))
                .andExpect(status().isBadRequest());
    }
}
