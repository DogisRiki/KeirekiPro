package com.example.keirekipro.unit.presentation.shared;

import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.shared.AppExceptionHandler;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest({ TestController.class, AppExceptionHandler.class })
@AutoConfigureMockMvc(addFilters = false) // Spring Securityのフィルタを除外する
class AppExceptionHandlerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("JWT認証エラー発生時、401が返る")
    void test1() throws Exception {
        mockMvc.perform(get("/test/test1")
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("認証に失敗しました。"))
                .andExpect(jsonPath("$.errors").doesNotExist());
    }

    @Test
    @DisplayName("認証エラー発生時、403が返る")
    void test2() throws Exception {
        mockMvc.perform(get("/test/test2")
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isForbidden())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("メールアドレスまたはパスワードが違います。"))
                .andExpect(jsonPath("$.errors").doesNotExist());
    }

    @Test
    @DisplayName("バリデーションエラー: 1フィールドに1アノテーションの場合")
    void test3() throws Exception {
        mockMvc.perform(post("/test/test3")
                .content("{}")
                .contentType(MediaType.APPLICATION_JSON)
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.value1[0]").value("値1は入力必須です。"))
                .andExpect(jsonPath("$.errors.value2[0]").value("値2は入力必須です。"));
    }

    @Test
    @DisplayName("バリデーションエラー: 1フィールドに2アノテーションの場合")
    void test4() throws Exception {
        String requestBody = "{\"value1\": \"abcde\", \"value2\": \"abcde\"}";
        mockMvc.perform(post("/test/test4")
                .content(requestBody)
                .contentType(MediaType.APPLICATION_JSON)
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("入力エラーがあります。"))
                .andExpect(jsonPath("$.errors.value1", containsInAnyOrder("値1は数字でなければなりません", "値1は1～4桁を入力してください")))
                .andExpect(jsonPath("$.errors.value2", containsInAnyOrder("値2は数字でなければなりません", "値2は1～4桁を入力してください")));
    }
}
