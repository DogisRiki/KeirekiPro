package com.example.keirekipro.unit.presentation.user.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.security.config.SecurityConfig;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.presentation.user.controller.SendAccountEmailVerificationController;
import com.example.keirekipro.usecase.user.SendAccountEmailVerificationUseCase;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.Cookie;

/**
 * ログインの要否を確かめるため、本番のセキュリティの設定を読み込んで動かす
 */
@WebMvcTest(SendAccountEmailVerificationController.class)
@Import({ SecurityConfig.class, CurrentUserFacade.class })
@TestPropertySource(properties = "cors.allowed-origins=http://localhost:5173")
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class SendAccountEmailVerificationControllerTest {

    @MockitoBean
    private final SendAccountEmailVerificationUseCase sendAccountEmailVerificationUseCase;

    @MockitoBean
    private final JwtProvider jwtProvider;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/users/me/email-verification";

    private static final String ACCESS_TOKEN = "access-token";

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    @Test
    @DisplayName("ログインした利用者のアカウントに確認のメールを送り 204 を返す")
    void test1() throws Exception {
        when(jwtProvider.getAuthentication(ACCESS_TOKEN))
                .thenReturn(new UsernamePasswordAuthenticationToken(USER_ID.toString(), null, List.of()));

        mockMvc.perform(post(ENDPOINT)
                .cookie(new Cookie("accessToken", ACCESS_TOKEN))
                .with(csrf()))
                .andExpect(status().isNoContent());

        verify(sendAccountEmailVerificationUseCase).execute(USER_ID);
    }

    @Test
    @DisplayName("ログインしていない要求には 401 を返し、確認のメールを送らない")
    void test2() throws Exception {
        mockMvc.perform(post(ENDPOINT)
                .with(csrf()))
                .andExpect(status().isUnauthorized());

        verify(sendAccountEmailVerificationUseCase, never()).execute(any());
    }
}
