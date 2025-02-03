package com.example.keirekipro.presentation.auth.controller;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.UUID;

import com.auth0.jwt.exceptions.JWTVerificationException;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import jakarta.servlet.http.Cookie;

@WebMvcTest(RefreshAccessTokenController.class)
@AutoConfigureMockMvc(addFilters = false)
class RefreshAccessTokenControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private JwtProvider jwtProvider;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String ACCESS_TOKEN = "mockAccessToken";
    private static final String NEW_ACCESS_TOKEN = "newMockAccessToken";
    private static final String REFRESH_TOKEN = "mockRefreshToken";

    @Test
    @DisplayName("有効なリフレッシュトークンの場合、新しいアクセストークンが返される")
    void test1() throws Exception {
        when(jwtProvider.createAccessToken(USER_ID.toString())).thenReturn(NEW_ACCESS_TOKEN);
        when(jwtProvider.getAuthentication(REFRESH_TOKEN))
                .thenReturn(new UsernamePasswordAuthenticationToken(USER_ID.toString(), null, List.of()));

        Cookie accessTokenCookie = new Cookie("accessToken", ACCESS_TOKEN);
        Cookie refreshTokenCookie = new Cookie("refreshToken", REFRESH_TOKEN);

        mockMvc.perform(post("/api/auth/token/refresh")
                .cookie(accessTokenCookie, refreshTokenCookie))
                .andExpect(status().isOk())
                .andExpect(header().string("Set-Cookie", containsString("accessToken=newMockAccessToken")));
    }

    @Test
    @DisplayName("リフレッシュトークンが存在しない場合、401が返る")
    void test2() throws Exception {
        Cookie accessTokenCookie = new Cookie("accessToken", ACCESS_TOKEN);
        mockMvc.perform(post("/api/auth/token/refresh")
                .cookie(accessTokenCookie))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("認証に失敗しました。"))
                .andExpect(jsonPath("$.errors").doesNotExist());
    }

    @Test
    @DisplayName("リフレッシュトークンの有効期限が切れている場合、401が返る")
    void test3() throws Exception {
        when(jwtProvider.getAuthentication(REFRESH_TOKEN))
                .thenThrow(new JWTVerificationException("トークンの有効期限が切れています。"));

        Cookie accessTokenCookie = new Cookie("accessToken", ACCESS_TOKEN);
        Cookie refreshTokenCookie = new Cookie("refreshToken", REFRESH_TOKEN);

        mockMvc.perform(post("/api/auth/token/refresh")
                .cookie(accessTokenCookie, refreshTokenCookie))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.message").value("認証に失敗しました。"))
                .andExpect(jsonPath("$.errors").doesNotExist());
    }
}
