package com.example.keirekipro.presentation.auth.controller;

import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import com.example.keirekipro.presentation.auth.dto.LoginRequest;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.usecase.auth.LoginUseCase;
import com.example.keirekipro.usecase.auth.dto.LoginUseCaseDto;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(LoginController.class)
@AutoConfigureMockMvc(addFilters = false)
class LoginControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private LoginUseCase loginUseCase;

    @MockitoBean
    private JwtProvider jwtProvider;

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@kexample.com";
    private static final String PASSWORD = "hashedPassword";
    private static final String ACCESS_TOKEN = "mockAccessToken";
    private static final String REFRESH_TOKEN = "mockRefreshToken";

    private final ObjectMapper objectMapper = new ObjectMapper();

    @BeforeEach
    void setUp() {
        when(loginUseCase.execute(Mockito.any()))
                .thenReturn(new LoginUseCaseDto(USER_ID));

        when(jwtProvider.createAccessToken(USER_ID.toString()))
                .thenReturn(ACCESS_TOKEN);

        when(jwtProvider.createRefreshToken(USER_ID.toString()))
                .thenReturn(REFRESH_TOKEN);
    }

    @Test
    @DisplayName("正しい認証情報の場合、JWTがSet-Cookieに設定される")
    void test1() throws Exception {
        LoginRequest request = new LoginRequest(EMAIL, PASSWORD);
        String requestBody = objectMapper.writeValueAsString(request);
        mockMvc.perform(post("/api/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isOk())
                .andExpect(header().exists("Set-Cookie"))
                .andExpect(header().stringValues(
                        "Set-Cookie",
                        containsInAnyOrder(
                                containsString("accessToken=mockAccessToken"),
                                containsString("refreshToken=mockRefreshToken"))));
    }
}
