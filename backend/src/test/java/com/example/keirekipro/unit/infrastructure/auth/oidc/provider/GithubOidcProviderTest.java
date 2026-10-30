package com.example.keirekipro.unit.infrastructure.auth.oidc.provider;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import java.util.HashMap;
import java.util.Map;

import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.infrastructure.auth.oidc.provider.GithubOidcProvider;
import tools.jackson.databind.json.JsonMapper;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class GithubOidcProviderTest {

    private static final String EMAILS_URL = "https://api.github.com/user/emails";
    private static final String ACCESS_TOKEN = "github-access-token";
    private static final String PUBLIC_EMAIL = "public@example.com";
    private static final String PRIMARY_EMAIL = "primary@example.com";

    private MockRestServiceServer server;

    private GithubOidcProvider githubOidcProvider;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder();
        server = MockRestServiceServer.bindTo(builder).build();
        githubOidcProvider = new GithubOidcProvider(
                "https://github.com/login/oauth/authorize",
                "https://github.com/login/oauth/access_token",
                "https://api.github.com/user",
                "read:user user:email",
                "github-secret",
                builder.build(),
                JsonMapper.builder().build());
    }

    @Test
    @DisplayName("primary と verified が true の要素の email を返す")
    void test1() {
        server.expect(requestTo(EMAILS_URL))
                .andExpect(method(HttpMethod.GET))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer " + ACCESS_TOKEN))
                .andRespond(withSuccess(
                        """
                        [
                            { "email": "secondary@example.com", "primary": false, "verified": true },
                            { "email": "primary@example.com", "primary": true, "verified": true }
                        ]
                        """, MediaType.APPLICATION_JSON));

        OidcUserInfoDto result = githubOidcProvider.convertToStandardUserInfo(userInfo(PUBLIC_EMAIL));

        assertThat(result.getEmail()).isEqualTo(PRIMARY_EMAIL);
        assertThat(result.getProviderUserId()).isEqualTo("12345");
        assertThat(result.getUsername()).isEqualTo("github-user");
        assertThat(result.getProviderType()).isEqualTo("github");
        server.verify();
    }

    @Test
    @DisplayName("verified が false の primary は email を null にする")
    void test2() {
        server.expect(requestTo(EMAILS_URL))
                .andRespond(withSuccess(
                        """
                        [
                            { "email": "primary@example.com", "primary": true, "verified": false },
                            { "email": "secondary@example.com", "primary": false, "verified": true }
                        ]
                        """, MediaType.APPLICATION_JSON));

        OidcUserInfoDto result = githubOidcProvider.convertToStandardUserInfo(userInfo(PRIMARY_EMAIL));

        assertThat(result.getEmail()).isNull();
        server.verify();
    }

    @Test
    @DisplayName("GET /user の email を使わない")
    void test3() {
        server.expect(requestTo(EMAILS_URL))
                .andRespond(withSuccess("[]", MediaType.APPLICATION_JSON));

        OidcUserInfoDto result = githubOidcProvider.convertToStandardUserInfo(userInfo(PUBLIC_EMAIL));

        assertThat(result.getEmail()).isNull();
        server.verify();
    }

    @Test
    @DisplayName("GET /user/emails の呼び出しに失敗したら email を null にする")
    void test4() {
        server.expect(requestTo(EMAILS_URL))
                .andRespond(withServerError());

        OidcUserInfoDto result = githubOidcProvider.convertToStandardUserInfo(userInfo(PUBLIC_EMAIL));

        assertThat(result.getEmail()).isNull();
        assertThat(result.getProviderUserId()).isEqualTo("12345");
        server.verify();
    }

    private static Map<String, Object> userInfo(String email) {
        Map<String, Object> userInfo = new HashMap<>();
        userInfo.put("id", 12345);
        userInfo.put("email", email);
        userInfo.put("login", "github-user");
        userInfo.put("access_token", ACCESS_TOKEN);
        return userInfo;
    }
}
