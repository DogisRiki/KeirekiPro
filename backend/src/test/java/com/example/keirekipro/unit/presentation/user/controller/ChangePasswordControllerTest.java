package com.example.keirekipro.unit.presentation.user.controller;

import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasSize;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.user.controller.ChangePasswordController;
import com.example.keirekipro.presentation.user.dto.ChangePasswordRequest;
import com.example.keirekipro.usecase.user.ChangePasswordUseCase;
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

@WebMvcTest(ChangePasswordController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class ChangePasswordControllerTest {

    @MockitoBean
    private ChangePasswordUseCase changePasswordUseCase;

    @MockitoBean
    private CurrentUserFacade currentUserFacade;

    private final MockMvc mockMvc;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String CURRENT_PASSWORD = "CurrentPassword123";
    private static final String NEW_PASSWORD = "NewPassword123";
    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    @Test
    @DisplayName("正常なリクエストの場合、204が返される")
    void test1() throws Exception {
        // リクエストを準備
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, NEW_PASSWORD);
        String requestBody = objectMapper.writeValueAsString(request);

        // モックをセットアップ
        when(currentUserFacade.getUserId()).thenReturn(USER_ID.toString());

        // リクエストを実行
        mockMvc.perform(patch("/api/users/me/password")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isNoContent());

        // 呼び出しを検証
        verify(currentUserFacade).getUserId();
        verify(changePasswordUseCase).execute(request, USER_ID);
    }

    @Test
    @DisplayName("現在のパスワードが空の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        // リクエストを準備（現在のパスワードが空）
        ChangePasswordRequest request = new ChangePasswordRequest("", NEW_PASSWORD);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(patch("/api/users/me/password")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.nowPassword").isArray())
                .andExpect(jsonPath("$.errors.nowPassword", hasItem("現在のパスワードは入力必須です。")));
    }

    @Test
    @DisplayName("新しいパスワードが空の場合、バリデーションエラーとなる")
    void test3() throws Exception {
        // リクエストを準備（新しいパスワードが空）
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, "");
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(patch("/api/users/me/password")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.newPassword").isArray())
                .andExpect(jsonPath("$.errors.newPassword", hasItem("新しいパスワードは入力必須です。")));
    }

    @Test
    @DisplayName("新しいパスワードが8文字未満の場合、バリデーションエラーとなる")
    void test4() throws Exception {
        // 7文字のパスワード
        String shortPassword = "Pass123";

        // リクエストを準備
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, shortPassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(patch("/api/users/me/password")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.newPassword").isArray())
                .andExpect(jsonPath("$.errors.newPassword", hasItem("新しいパスワードは8文字以上20文字以内で入力してください。")));
    }

    @Test
    @DisplayName("新しいパスワードが20文字を超える場合、バリデーションエラーとなる")
    void test5() throws Exception {
        // 21文字のパスワード
        String longPassword = "Password123Password12";

        // リクエストを準備
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, longPassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(patch("/api/users/me/password")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.newPassword").isArray())
                .andExpect(jsonPath("$.errors.newPassword", hasItem("新しいパスワードは8文字以上20文字以内で入力してください。")));
    }

    @Test
    @DisplayName("新しいパスワードに英小文字を含まない場合、バリデーションエラーとなる")
    void test6() throws Exception {
        // 英小文字を含まないパスワード
        String noLowerCasePassword = "PASSWORD123";

        // リクエストを準備
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, noLowerCasePassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(patch("/api/users/me/password")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.newPassword").isArray())
                .andExpect(jsonPath("$.errors.newPassword", hasItem("新しいパスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")));
    }

    @Test
    @DisplayName("新しいパスワードに英大文字を含まない場合、バリデーションエラーとなる")
    void test7() throws Exception {
        // 英大文字を含まないパスワード
        String noUpperCasePassword = "password123";

        // リクエストを準備
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, noUpperCasePassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(patch("/api/users/me/password")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.newPassword").isArray())
                .andExpect(jsonPath("$.errors.newPassword", hasItem("新しいパスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")));
    }

    @Test
    @DisplayName("新しいパスワードに数字を含まない場合、バリデーションエラーとなる")
    void test8() throws Exception {
        // 数字を含まないパスワード
        String noDigitPassword = "PasswordTest";

        // リクエストを準備
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, noDigitPassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(patch("/api/users/me/password")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.newPassword").isArray())
                .andExpect(jsonPath("$.errors.newPassword", hasItem("新しいパスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")));
    }

    @Test
    @DisplayName("新しいパスワードが短すぎかつパターン違反の場合、複数のバリデーションエラーが返される")
    void test9() throws Exception {
        // 短すぎかつパターン違反（英小文字のみ）のパスワード
        String invalidPassword = "short";

        // リクエストを準備
        ChangePasswordRequest request = new ChangePasswordRequest(CURRENT_PASSWORD, invalidPassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(patch("/api/users/me/password")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.newPassword", hasSize(2)))
                .andExpect(jsonPath("$.errors.newPassword", hasItem("新しいパスワードは8文字以上20文字以内で入力してください。")))
                .andExpect(jsonPath("$.errors.newPassword", hasItem("新しいパスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")));
    }

    @Test
    @DisplayName("両方のパスワードが空の場合、両方にバリデーションエラーが返される")
    void test10() throws Exception {
        // リクエストを準備（両方のパスワードが空）
        ChangePasswordRequest request = new ChangePasswordRequest("", "");
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(patch("/api/users/me/password")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.nowPassword").exists())
                .andExpect(jsonPath("$.errors.newPassword").exists())
                .andExpect(jsonPath("$.errors.nowPassword", hasItem("現在のパスワードは入力必須です。")))
                .andExpect(jsonPath("$.errors.newPassword", hasItem("新しいパスワードは入力必須です。")));
    }
}
