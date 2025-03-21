package com.example.keirekipro.unit.presentation.auth.controller;

import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.auth.controller.UserRegistrationController;
import com.example.keirekipro.presentation.auth.dto.UserRegistrationRequest;
import com.example.keirekipro.usecase.auth.UserRegistrationUseCase;
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

@WebMvcTest(UserRegistrationController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class UserRegistrationControllerTest {

    @MockitoBean
    private UserRegistrationUseCase userRegistrationUseCase;

    private final MockMvc mockMvc;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final String EMAIL = "test@keirekipro.click";
    private static final String USERNAME = "test-user";
    private static final String PASSWORD = "Password123";
    private static final String CONFIRM_PASSWORD = "Password123";

    @Test
    @DisplayName("正常なリクエストの場合、201が返される")
    void test1() throws Exception {
        // リクエストを準備
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, PASSWORD, CONFIRM_PASSWORD);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isCreated());
    }

    @Test
    @DisplayName("メールアドレスが空の場合、バリデーションエラーとなる")
    void test2() throws Exception {
        // リクエストを準備（メールアドレスが空）
        UserRegistrationRequest request = new UserRegistrationRequest("", USERNAME, PASSWORD, CONFIRM_PASSWORD);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email").isArray())
                .andExpect(jsonPath("$.errors.email", hasItem("メールアドレスは入力必須です。")));
    }

    @Test
    @DisplayName("メールアドレスが255文字を超える場合、バリデーションエラーとなる")
    void test3() throws Exception {
        // 256文字のメールアドレスを生成
        String longEmail = "a".repeat(245) + "@example.com"; // 245 + 12 = 257文字

        // リクエストを準備
        UserRegistrationRequest request = new UserRegistrationRequest(longEmail, USERNAME, PASSWORD, CONFIRM_PASSWORD);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email").isArray())
                .andExpect(jsonPath("$.errors.email", hasItem("メールアドレスは255文字以内で入力してください。")));
    }

    @Test
    @DisplayName("メールアドレス形式が不正な場合、バリデーションエラーとなる")
    void test4() throws Exception {
        // リクエストを準備（不正なメールアドレス形式）
        UserRegistrationRequest request = new UserRegistrationRequest("invalid-email", USERNAME, PASSWORD,
                CONFIRM_PASSWORD);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email").isArray())
                .andExpect(jsonPath("$.errors.email", hasItem("メールアドレスの形式が無効です。")));
    }

    @Test
    @DisplayName("ユーザー名が空の場合、バリデーションエラーとなる")
    void test5() throws Exception {
        // リクエストを準備（ユーザー名が空）
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, "", PASSWORD, CONFIRM_PASSWORD);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.username").isArray())
                .andExpect(jsonPath("$.errors.username", hasItem("ユーザー名は入力必須です。")));
    }

    @Test
    @DisplayName("ユーザー名が50文字を超える場合、バリデーションエラーとなる")
    void test6() throws Exception {
        // 51文字のユーザー名を生成
        String longUsername = "a".repeat(51);

        // リクエストを準備
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, longUsername, PASSWORD, CONFIRM_PASSWORD);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.username").isArray())
                .andExpect(jsonPath("$.errors.username", hasItem("ユーザー名は50文字以内で入力してください。")));
    }

    @Test
    @DisplayName("パスワードが空の場合、バリデーションエラーとなる")
    void test7() throws Exception {
        // リクエストを準備（パスワードが空）
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, "", CONFIRM_PASSWORD);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password").isArray())
                .andExpect(jsonPath("$.errors.password", hasItem("パスワードは入力必須です。")));
    }

    @Test
    @DisplayName("パスワードが8文字未満の場合、バリデーションエラーとなる")
    void test8() throws Exception {
        // 7文字のパスワード
        String shortPassword = "Pass123";

        // リクエストを準備
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, shortPassword, shortPassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password").isArray())
                .andExpect(jsonPath("$.errors.password", hasItem("パスワードは8文字以上20文字以内で入力してください。")));
    }

    @Test
    @DisplayName("パスワードが20文字を超える場合、バリデーションエラーとなる")
    void test9() throws Exception {
        // 21文字のパスワード
        String longPassword = "Password123Password12";

        // リクエストを準備
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, longPassword, longPassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password").isArray())
                .andExpect(jsonPath("$.errors.password", hasItem("パスワードは8文字以上20文字以内で入力してください。")));
    }

    @Test
    @DisplayName("パスワードに英小文字を含まない場合、バリデーションエラーとなる")
    void test10() throws Exception {
        // 英小文字を含まないパスワード
        String noLowerCasePassword = "PASSWORD123";

        // リクエストを準備
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, noLowerCasePassword,
                noLowerCasePassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password").isArray())
                .andExpect(jsonPath("$.errors.password", hasItem("パスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")));
    }

    @Test
    @DisplayName("パスワードに英大文字を含まない場合、バリデーションエラーとなる")
    void test11() throws Exception {
        // 英大文字を含まないパスワード
        String noUpperCasePassword = "password123";

        // リクエストを準備
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, noUpperCasePassword,
                noUpperCasePassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password").isArray())
                .andExpect(jsonPath("$.errors.password", hasItem("パスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")));
    }

    @Test
    @DisplayName("パスワードに数字を含まない場合、バリデーションエラーとなる")
    void test12() throws Exception {
        // 数字を含まないパスワード
        String noDigitPassword = "PasswordTest";

        // リクエストを準備
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, noDigitPassword,
                noDigitPassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password").isArray())
                .andExpect(jsonPath("$.errors.password", hasItem("パスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")));
    }

    @Test
    @DisplayName("確認用パスワードが空の場合、バリデーションエラーとなる")
    void test13() throws Exception {
        // リクエストを準備（確認用パスワードが空）
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, PASSWORD, "");
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.confirmPassword").isArray())
                .andExpect(jsonPath("$.errors.confirmPassword", hasItem("パスワード(確認用)は入力必須です。")));
    }

    @Test
    @DisplayName("パスワードと確認用パスワードが一致しない場合、バリデーションエラーとなる")
    void test14() throws Exception {
        // リクエストを準備（パスワードと確認用パスワードが不一致）
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, PASSWORD, "Password321");
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.passwordMatching").isArray())
                .andExpect(jsonPath("$.errors.passwordMatching", hasItem("パスワードとパスワード(確認用)が一致していません。")));
    }

    @Test
    @DisplayName("複数のバリデーションエラーがある場合、すべてのエラーが返される")
    void test15() throws Exception {
        // リクエストを準備（複数のバリデーションエラー）
        UserRegistrationRequest request = new UserRegistrationRequest("", "", "", "");
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email").exists())
                .andExpect(jsonPath("$.errors.username").exists())
                .andExpect(jsonPath("$.errors.password").exists())
                .andExpect(jsonPath("$.errors.confirmPassword").exists());
    }

    @Test
    @DisplayName("パスワードに関する複合的なバリデーションエラーをテスト（長さとパターン両方に違反）")
    void test16() throws Exception {
        // 短すぎかつパターン違反（大文字なし、数字なし）のパスワード
        String invalidPassword = "short";
        UserRegistrationRequest request = new UserRegistrationRequest(EMAIL, USERNAME, invalidPassword,
                invalidPassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.password", hasSize(2)))
                .andExpect(jsonPath("$.errors.password", hasItem("パスワードは8文字以上20文字以内で入力してください。")))
                .andExpect(jsonPath("$.errors.password", hasItem("パスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")));
    }

    @Test
    @DisplayName("メールアドレスとパスワードの複合エラー（メール形式不正とパスワード不一致）")
    void test17() throws Exception {
        // 不正なメールアドレスと一致しないパスワード
        UserRegistrationRequest request = new UserRegistrationRequest(
                "invalid-email",
                USERNAME,
                PASSWORD,
                "DifferentPassword123");
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email", hasItem("メールアドレスの形式が無効です。")))
                .andExpect(jsonPath("$.errors.passwordMatching", hasItem("パスワードとパスワード(確認用)が一致していません。")));
    }

    @Test
    @DisplayName("すべてのフィールドに特定のバリデーション違反がある複雑なケース")
    void test18() throws Exception {
        // 256文字のメールアドレス + 51文字のユーザー名 + 不正なパスワード + 異なる確認用パスワード
        String longEmail = "a".repeat(245) + "@example.com"; // 257文字
        String longUsername = "u".repeat(51);
        String invalidPassword = "PasswordTest";
        String differentPassword = "DifferentTest1";

        UserRegistrationRequest request = new UserRegistrationRequest(
                longEmail,
                longUsername,
                invalidPassword,
                differentPassword);
        String requestBody = objectMapper.writeValueAsString(request);

        // リクエストを実行
        mockMvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.email", hasItem("メールアドレスは255文字以内で入力してください。")))
                .andExpect(jsonPath("$.errors.username", hasItem("ユーザー名は50文字以内で入力してください。")))
                .andExpect(jsonPath("$.errors.password", hasItem("パスワードには英小文字、英大文字、数字をそれぞれ1文字以上含める必要があります。")))
                .andExpect(jsonPath("$.errors.passwordMatching", hasItem("パスワードとパスワード(確認用)が一致していません。")));
    }
}
