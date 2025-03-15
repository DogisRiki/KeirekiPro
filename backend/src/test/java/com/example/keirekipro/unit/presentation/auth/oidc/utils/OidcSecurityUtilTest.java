package com.example.keirekipro.unit.presentation.auth.oidc.utils;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.keirekipro.presentation.auth.oidc.utils.OidcSecurityUtil;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class OidcSecurityUtilTest {

    private OidcSecurityUtil oidcSecurityUtil;

    @BeforeEach
    void setUp() {
        oidcSecurityUtil = new OidcSecurityUtil();
    }

    @Test
    @DisplayName("有効なランダム値のトークンを生成する")
    void test1() {
        String randomToken = oidcSecurityUtil.generateRandomToken();

        assertThat(randomToken)
                .isNotNull() // Nullでない
                .hasSize(43) // 長さが43文字である
                .matches("[A-Za-z0-9\\-_]+"); // Base64URL文字のみを含む
    }

    @Test
    @DisplayName("2回実行するとそれぞれ異なるトークンが生成される")
    void test2() {
        String randomToken1 = oidcSecurityUtil.generateRandomToken();
        String randomToken2 = oidcSecurityUtil.generateRandomToken();

        assertThat(randomToken1).isNotEqualTo(randomToken2);
    }

    @Test
    @DisplayName("有効なcode_verifierを渡してcode_challengeを生成する")
    void test3() {
        String codeVerifier = oidcSecurityUtil.generateRandomToken();
        String codeChallenge = oidcSecurityUtil.generateCodeChallenge(codeVerifier);

        assertThat(
                codeChallenge)
                .isNotNull() // Nullでない
                .hasSize(43) // 長さが43文字である
                .matches("[A-Za-z0-9\\-_]+"); // Base64URL文字のみを含む
    }

    @Test
    @DisplayName("固定の入力（test-code-verifier）に対して、事前に算出した期待値と一致する")
    void test4() {
        String codeVerifier = "test-code-verifier";
        String expectedChallenge = "0FLIKahrX7kqxncwhV5WD82lu_wi5GA8FsRSLubaOpU";
        String actualChallenge = oidcSecurityUtil.generateCodeChallenge(codeVerifier);

        assertThat(actualChallenge).isEqualTo(expectedChallenge);
    }

    @Test
    @DisplayName("異なるcode_verifierを入力した場合、生成されるcode_challengeも異なる")
    void test5() {
        String codeVerifier1 = "test-code-verifier-1";
        String codeVerifier2 = "test-code-verifier-2";
        String codeChallenge1 = oidcSecurityUtil.generateCodeChallenge(codeVerifier1);
        String codeChallenge2 = oidcSecurityUtil.generateCodeChallenge(codeVerifier2);

        assertThat(codeChallenge1).isNotEqualTo(codeChallenge2);
    }
}
