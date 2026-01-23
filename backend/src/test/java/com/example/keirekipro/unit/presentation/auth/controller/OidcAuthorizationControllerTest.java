package com.example.keirekipro.unit.presentation.auth.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.presentation.auth.controller.OidcAuthorizationController;
import com.example.keirekipro.presentation.shared.utils.BaseUrlResolver;
import com.example.keirekipro.usecase.auth.StartOidcAuthorizationUseCase;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.HttpServletRequest;

@WebMvcTest(OidcAuthorizationController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class OidcAuthorizationControllerTest {

    @MockitoBean
    private StartOidcAuthorizationUseCase startOidcAuthorizationUseCase;

    @MockitoBean
    private BaseUrlResolver baseUrlResolver;

    private final MockMvc mockMvc;

    private static final String ENDPOINT = "/api/auth/oidc/authorize";
    private static final String PROVIDER_PARAM = "google";
    private static final String API_BASE_URL = "http://localhost";
    private static final String EXPECTED_URL = "https://accounts.google.com/o/oauth2/auth?...";

    @BeforeEach
    void setUp() {
        when(baseUrlResolver.resolve(any(HttpServletRequest.class))).thenReturn(API_BASE_URL);
    }

    @Test
    @DisplayName("認可URLが返却される")
    void test1() throws Exception {
        // モックをセットアップ
        when(startOidcAuthorizationUseCase.execute(eq(PROVIDER_PARAM), anyString()))
                .thenReturn(EXPECTED_URL);

        // リクエストを実行
        mockMvc.perform(get(ENDPOINT)
                .param("provider", PROVIDER_PARAM))
                .andExpect(status().isOk())
                .andExpect(content().string(EXPECTED_URL));

        // 呼び出し検証
        verify(startOidcAuthorizationUseCase).execute(eq(PROVIDER_PARAM), anyString());
    }
}
