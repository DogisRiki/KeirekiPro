package com.example.keirekipro.unit.presentation.auth.controller;

import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.auth.controller.LogoutController;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.HttpHeaders;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(LogoutController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class LogoutControllerTest {

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/auth/logout";

    @Test
    @DisplayName("アクセストークンとリフレッシュトークンのCookieが削除される")
    void test1() throws Exception {
        mockMvc.perform(post(ENDPOINT))
                .andExpect(status().isNoContent())
                .andExpect(header().exists(HttpHeaders.SET_COOKIE))
                .andExpect(header().stringValues(
                        HttpHeaders.SET_COOKIE,
                        containsInAnyOrder(
                                containsString("accessToken="),
                                containsString("refreshToken="))))
                .andExpect(header().string(HttpHeaders.SET_COOKIE, containsString("Max-Age=0")));
    }
}
