package com.example.keirekipro.unit.presentation.auth.controller;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.keirekipro.infrastructure.auth.oidc.OidcClient;
import com.example.keirekipro.infrastructure.shared.redis.RedisClient;
import com.example.keirekipro.presentation.auth.controller.OidcAuthorizationController;
import com.example.keirekipro.presentation.security.utils.SecurityUtil;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import lombok.RequiredArgsConstructor;

@WebMvcTest(OidcAuthorizationController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class OidcAuthorizationControllerTest {

    @MockitoBean
    private OidcClient oidcClient;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private RedisClient redisClient;

    private final MockMvc mockMvc;

    private static final String PROVIDER_PARAM = "google";
    private static final String REDIRECT_URI = "https://keirekipro.click/api/auth/oidc/callback";
    private static final String CODE_VERIFIER = "randomVerifier";
    private static final String CODE_CHALLENGE = "randomCodeChallenge";
    private static final String STATE_VALUE = "randomState";

    // 想定する認可URL
    private static final String EXPECTED_URL = REDIRECT_URI
            + "?client_id=randomClientId"
            + "&response_type=code"
            + "&scope=openid email profile"
            + "&redirect_uri=/api/auth/oidc/callback"
            + "&state=" + STATE_VALUE
            + "&code_challenge=" + CODE_CHALLENGE
            + "&code_challenge_method=S256";

    @Test
    @DisplayName("認可URLが返却される")
    void test1() throws Exception {
        // モックをセットアップ
        // securityUtil.generateRandomToken()は2回呼ばれるので、1回目にcodeVerifier、2回目にstateを返す
        when(securityUtil.generateRandomToken()).thenReturn(CODE_VERIFIER, STATE_VALUE);
        when(securityUtil.generateCodeChallenge(CODE_VERIFIER)).thenReturn(CODE_CHALLENGE);
        when(oidcClient.buildAuthorizationUrl(
                eq(PROVIDER_PARAM),
                anyString(), // 実際のコード上はUrlUtil.getBaseUrl() + "/api/auth/oidc/callback"
                eq(STATE_VALUE),
                eq(CODE_CHALLENGE))).thenReturn(EXPECTED_URL);

        // リクエストを実行
        mockMvc.perform(get("/api/auth/oidc/authorize")
                .param("provider", PROVIDER_PARAM))
                .andExpect(status().isOk())
                .andExpect(content().string(EXPECTED_URL));
    }
}
