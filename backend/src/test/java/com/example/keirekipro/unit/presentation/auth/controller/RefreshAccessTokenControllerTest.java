package com.example.keirekipro.unit.presentation.auth.controller;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import com.auth0.jwt.exceptions.JWTVerificationException;
import com.example.keirekipro.presentation.auth.controller.RefreshAccessTokenController;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
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

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/auth/token/refresh";

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String ACCESS_TOKEN = "mockAccessToken";
    private static final String NEW_ACCESS_TOKEN = "newMockAccessToken";
    private static final String REFRESH_TOKEN = "mockRefreshToken";

    @Test
    @DisplayName("有効なリフレッシュトークンの場合、新しいアクセストークンが返される")
    void test1() throws Exception {
        // モックをセットアップ
        Set<String> roles = Set.of("USER");
        when(jwtProvider.createAccessToken(eq(USER_ID.toString()), eq(roles))).thenReturn(NEW_ACCESS_TOKEN);
        when(jwtProvider.getAuthentication(REFRESH_TOKEN))
                .thenReturn(new UsernamePasswordAuthenticationToken(
                        USER_ID.toString(),
                        null,
                        List.of(new SimpleGrantedAuthority("ROLE_USER"))));

        Cookie accessTokenCookie = new Cookie("accessToken", ACCESS_TOKEN);
        Cookie refreshTokenCookie = new Cookie("refreshToken", REFRESH_TOKEN);

        // リクエストを実行
        mockMvc.perform(post(
                ENDPOINT)
                .cookie(accessTokenCookie, refreshTokenCookie))
                .andExpect(status().isOk())
                .andExpect(header().string("Set-Cookie", containsString("accessToken=newMockAccessToken")));

        // 呼び出し検証を追加
        verify(jwtProvider).getAuthentication(REFRESH_TOKEN);
        verify(jwtProvider).createAccessToken(USER_ID.toString(), roles);
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
    @DisplayName("リフレッシュトークンの有効期限が切れている場合、401が返る")
    void test3() throws Exception {
        // モックをセットアップ
        when(jwtProvider.getAuthentication(REFRESH_TOKEN))
                .thenThrow(new JWTVerificationException("トークンの有効期限が切れています。"));

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
}
