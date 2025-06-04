package com.example.keirekipro.unit.shared.utils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.example.keirekipro.shared.utils.SecurityUtil;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class SecurityUtilTest {

    private SecurityUtil securityUtil;

    @BeforeEach
    void setUp() {
        securityUtil = new SecurityUtil();
    }

    @Test
    @DisplayName("有効なランダム値のトークンを生成する")
    void test1() {
        String randomToken = securityUtil.generateRandomToken();

        assertThat(randomToken)
                .isNotNull() // Nullでない
                .hasSize(43) // 長さが43文字である
                .matches("[A-Za-z0-9\\-_]+"); // Base64URL文字のみを含む
    }

    @Test
    @DisplayName("2回実行するとそれぞれ異なるトークンが生成される")
    void test2() {
        String randomToken1 = securityUtil.generateRandomToken();
        String randomToken2 = securityUtil.generateRandomToken();

        assertThat(randomToken1).isNotEqualTo(randomToken2);
    }

    @Test
    @DisplayName("有効なcode_verifierを渡してcode_challengeを生成する")
    void test3() {
        String codeVerifier = securityUtil.generateRandomToken();
        String codeChallenge = securityUtil.generateCodeChallenge(codeVerifier);

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
        String actualChallenge = securityUtil.generateCodeChallenge(codeVerifier);

        assertThat(actualChallenge).isEqualTo(expectedChallenge);
    }

    @Test
    @DisplayName("異なるcode_verifierを入力した場合、生成されるcode_challengeも異なる")
    void test5() {
        String codeVerifier1 = "test-code-verifier-1";
        String codeVerifier2 = "test-code-verifier-2";
        String codeChallenge1 = securityUtil.generateCodeChallenge(codeVerifier1);
        String codeChallenge2 = securityUtil.generateCodeChallenge(codeVerifier2);

        assertThat(codeChallenge1).isNotEqualTo(codeChallenge2);
    }

    @Test
    @DisplayName("有効な桁数のランダム数値文字列を生成する")
    void test6() {
        String randomNumber = securityUtil.generateRandomNumber(6);

        assertThat(randomNumber)
                .isNotNull()
                .hasSize(6)
                .matches("^[0-9]+$");
    }

    @Test
    @DisplayName("0以下の桁数でランダム数値文字列を生成すると、IllegalArgumentExceptionがスローされる")
    void test7() {
        assertThatThrownBy(() -> {
            securityUtil.generateRandomNumber(0);
        }).isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("2回実行するとそれぞれ異なる数値文字列が生成される")
    void test8() {
        String randomNumber1 = securityUtil.generateRandomNumber(6);
        String randomNumber2 = securityUtil.generateRandomNumber(6);

        assertThat(randomNumber1).isNotEqualTo(randomNumber2);
    }
}
