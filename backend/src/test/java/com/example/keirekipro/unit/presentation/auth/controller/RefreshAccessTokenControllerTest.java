package com.example.keirekipro.unit.presentation.auth.controller;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.presentation.auth.controller.RefreshAccessTokenController;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.usecase.auth.dto.RefreshTokenInfo;
import com.example.keirekipro.usecase.auth.store.RefreshTokenStore;
import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.Cookie;

@WebMvcTest(RefreshAccessTokenController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class RefreshAccessTokenControllerTest {

    @MockitoBean
    private JwtProvider jwtProvider;

    @MockitoBean
    private RefreshTokenStore refreshTokenStore;

    @MockitoBean
    private UserTokenVersionStore userTokenVersionStore;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/auth/token/refresh";

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String ACCESS_TOKEN = "mockAccessToken";
    private static final String NEW_ACCESS_TOKEN = "newMockAccessToken";
    private static final String REFRESH_TOKEN = "mockRefreshToken";
    private static final Set<String> ROLES = Set.of("USER");

    @Test
    @DisplayName("有効なリフレッシュトークンでtokenVersion一致の場合、新しいアクセストークンが返される")
    void test1() throws Exception {
        // モックをセットアップ
        when(refreshTokenStore.find(REFRESH_TOKEN))
                .thenReturn(Optional.of(new RefreshTokenInfo(USER_ID, ROLES, 0L)));
        when(userTokenVersionStore.get(USER_ID)).thenReturn(0L);
        when(jwtProvider.createAccessToken(eq(USER_ID.toString()), eq(ROLES))).thenReturn(NEW_ACCESS_TOKEN);

        Cookie accessTokenCookie = new Cookie("accessToken", ACCESS_TOKEN);
        Cookie refreshTokenCookie = new Cookie("refreshToken", REFRESH_TOKEN);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .cookie(accessTokenCookie, refreshTokenCookie))
                .andExpect(status().isOk())
                .andExpect(header().string("Set-Cookie", containsString("accessToken=newMockAccessToken")));

        // 呼び出し検証
        verify(refreshTokenStore).find(REFRESH_TOKEN);
        verify(userTokenVersionStore).get(USER_ID);
        verify(jwtProvider).createAccessToken(USER_ID.toString(), ROLES);
        verify(refreshTokenStore, never()).remove(REFRESH_TOKEN);
    }

    @Test
    @DisplayName("リフレッシュトークンが存在しない場合、401が返る")
    void test2() throws Exception {
        Cookie accessTokenCookie = new Cookie("accessToken", ACCESS_TOKEN);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .cookie(accessTokenCookie))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("認証に失敗しました。"))
                .andExpect(jsonPath("$.errors").isEmpty());
    }

    @Test
    @DisplayName("Redisにリフレッシュトークン情報が存在しない場合、401が返る")
    void test3() throws Exception {
        // モックをセットアップ
        when(refreshTokenStore.find(REFRESH_TOKEN)).thenReturn(Optional.empty());

        Cookie accessTokenCookie = new Cookie("accessToken", ACCESS_TOKEN);
        Cookie refreshTokenCookie = new Cookie("refreshToken", REFRESH_TOKEN);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .cookie(accessTokenCookie, refreshTokenCookie))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("認証に失敗しました。"))
                .andExpect(jsonPath("$.errors").isEmpty());
    }

    @Test
    @DisplayName("tokenVersionが不一致の場合、当該リフレッシュトークンが削除され401が返る")
    void test4() throws Exception {
        // モックをセットアップ
        when(refreshTokenStore.find(REFRESH_TOKEN))
                .thenReturn(Optional.of(new RefreshTokenInfo(USER_ID, ROLES, 0L)));
        when(userTokenVersionStore.get(USER_ID)).thenReturn(1L);

        Cookie accessTokenCookie = new Cookie("accessToken", ACCESS_TOKEN);
        Cookie refreshTokenCookie = new Cookie("refreshToken", REFRESH_TOKEN);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .cookie(accessTokenCookie, refreshTokenCookie))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("認証に失敗しました。"))
                .andExpect(jsonPath("$.errors").isEmpty());

        // 呼び出し検証
        verify(refreshTokenStore).remove(REFRESH_TOKEN);
        verify(jwtProvider, never()).createAccessToken(any(), any());
    }
}
