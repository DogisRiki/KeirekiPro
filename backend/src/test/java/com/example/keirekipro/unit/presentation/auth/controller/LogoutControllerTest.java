package com.example.keirekipro.unit.presentation.auth.controller;

import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.auth.controller.LogoutController;
import com.example.keirekipro.usecase.auth.store.RefreshTokenStore;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.HttpHeaders;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.Cookie;

@WebMvcTest(LogoutController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class LogoutControllerTest {

    @MockitoBean
    private RefreshTokenStore refreshTokenStore;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/auth/logout";
    private static final String REFRESH_TOKEN = "mockRefreshToken";

    @Test
    @DisplayName("リフレッシュトークンが存在する場合、Redisから削除しCookieが削除される")
    void test1() throws Exception {
        Cookie refreshTokenCookie = new Cookie("refreshToken", REFRESH_TOKEN);

        mockMvc.perform(post(ENDPOINT).cookie(refreshTokenCookie))
                .andExpect(status().isNoContent())
                .andExpect(header().exists(HttpHeaders.SET_COOKIE))
                .andExpect(header().stringValues(
                        HttpHeaders.SET_COOKIE,
                        containsInAnyOrder(
                                containsString("accessToken="),
                                containsString("refreshToken="))))
                .andExpect(header().string(HttpHeaders.SET_COOKIE, containsString("Max-Age=0")));

        verify(refreshTokenStore).remove(REFRESH_TOKEN);
    }

    @Test
    @DisplayName("リフレッシュトークンが存在しない場合、Redis削除は行われずCookieのみ削除される")
    void test2() throws Exception {
        mockMvc.perform(post(ENDPOINT))
                .andExpect(status().isNoContent())
                .andExpect(header().exists(HttpHeaders.SET_COOKIE))
                .andExpect(header().stringValues(
                        HttpHeaders.SET_COOKIE,
                        containsInAnyOrder(
                                containsString("accessToken="),
                                containsString("refreshToken="))))
                .andExpect(header().string(HttpHeaders.SET_COOKIE, containsString("Max-Age=0")));

        verify(refreshTokenStore, never()).remove(any());
    }
}
