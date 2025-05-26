package com.example.keirekipro.unit.presentation.shared;

import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.Map;

import com.example.keirekipro.presentation.shared.AppExceptionHandler;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest({ TestController.class, AppExceptionHandler.class })
@AutoConfigureMockMvc(addFilters = false)
@ExtendWith(MockitoExtension.class)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class AppExceptionHandlerTest {

    private final MockMvc mockMvc;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    @DisplayName("JWT認証エラー発生時、401が返る")
    void test1() throws Exception {
        mockMvc.perform(get("/test/test1")
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("認証に失敗しました。"))
                .andExpect(jsonPath("$.errors").isEmpty());
    }

    @Test
    @DisplayName("認証エラー発生時、401が返る")
    void test2() throws Exception {
        mockMvc.perform(get("/test/test2")
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("不正なアクセスです。"))
                .andExpect(jsonPath("$.errors").isEmpty());
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
        Map<String, String> map = Map.of("value1", "abcde", "value2", "abcde");
        String requestBody = objectMapper.writeValueAsString(map);
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

    @Test
    @DisplayName("UseCaseException: メッセージのみの場合")
    void test5() throws Exception {
        mockMvc.perform(get("/test/test5")
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("ユースケースエラーが発生しました。"))
                .andExpect(jsonPath("$.errors").isEmpty());
    }

    @Test
    @DisplayName("DomainException: メッセージのみの場合")
    void test6() throws Exception {
        mockMvc.perform(get("/test/test6")
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("ドメインエラーが発生しました。"))
                .andExpect(jsonPath("$.errors").isEmpty());
    }

    @Test
    @DisplayName("UseCaseException: メッセージとフィールドエラーの場合")
    void test7() throws Exception {
        mockMvc.perform(get("/test/test7")
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("ユースケースフィールドエラー"))
                .andExpect(jsonPath("$.errors.field1[0]").value("フィールド1エラー"))
                .andExpect(jsonPath("$.errors.field2[0]").value("フィールド2エラー"));
    }

    @Test
    @DisplayName("DomainException: メッセージとフィールドエラーの場合")
    void test8() throws Exception {
        mockMvc.perform(get("/test/test8")
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("ドメインフィールドエラー"))
                .andExpect(jsonPath("$.errors.field1[0]").value("フィールド1ドメインエラー"))
                .andExpect(jsonPath("$.errors.field2[0]").value("フィールド2ドメインエラー"));
    }
}
