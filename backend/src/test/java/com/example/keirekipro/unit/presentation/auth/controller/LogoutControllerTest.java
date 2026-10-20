package com.example.keirekipro.unit.presentation.auth.controller;

import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import com.auth0.jwt.exceptions.JWTVerificationException;
import com.example.keirekipro.presentation.auth.controller.LogoutController;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.usecase.auth.dto.RefreshTokenInfo;
import com.example.keirekipro.usecase.auth.session.AuthSessionInvalidator;
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

    @MockitoBean
    private JwtProvider jwtProvider;

    @MockitoBean
    private AuthSessionInvalidator authSessionInvalidator;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/auth/logout";
    private static final String REFRESH_TOKEN = "mockRefreshToken";
    private static final String ACCESS_TOKEN = "mockAccessToken";
    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

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
        verify(authSessionInvalidator, never()).invalidate(any());
    }

    @Test
    @DisplayName("リフレッシュトークンから利用者を特定できる場合、その利用者の全端末のトークンを無効化する")
    void test3() throws Exception {
        when(refreshTokenStore.find(REFRESH_TOKEN)).thenReturn(Optional.of(
                new RefreshTokenInfo(USER_ID, Set.of("USER"), 0L)));

        mockMvc.perform(post(ENDPOINT).cookie(new Cookie("refreshToken", REFRESH_TOKEN)))
                .andExpect(status().isNoContent());

        verify(authSessionInvalidator).invalidate(USER_ID);
        verify(jwtProvider, never()).getUserId(any());
    }

    @Test
    @DisplayName("リフレッシュトークンで特定できない場合、アクセストークンから利用者を特定して無効化する")
    void test4() throws Exception {
        when(refreshTokenStore.find(REFRESH_TOKEN)).thenReturn(Optional.empty());
        when(jwtProvider.getUserId(ACCESS_TOKEN)).thenReturn(USER_ID);

        mockMvc.perform(post(ENDPOINT)
                .cookie(new Cookie("refreshToken", REFRESH_TOKEN), new Cookie("accessToken", ACCESS_TOKEN)))
                .andExpect(status().isNoContent());

        verify(authSessionInvalidator).invalidate(USER_ID);
        verify(refreshTokenStore).remove(REFRESH_TOKEN);
    }

    @Test
    @DisplayName("アクセストークンが無効な場合、無効化は行わずCookieのみ削除される")
    void test5() throws Exception {
        when(jwtProvider.getUserId(ACCESS_TOKEN)).thenThrow(new JWTVerificationException("invalid"));

        mockMvc.perform(post(ENDPOINT).cookie(new Cookie("accessToken", ACCESS_TOKEN)))
                .andExpect(status().isNoContent())
                .andExpect(header().string(HttpHeaders.SET_COOKIE, containsString("Max-Age=0")));

        verify(authSessionInvalidator, never()).invalidate(any());
    }
}
