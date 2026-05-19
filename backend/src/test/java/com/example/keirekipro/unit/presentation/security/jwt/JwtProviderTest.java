package com.example.keirekipro.unit.presentation.security.jwt;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

import java.util.Date;
import java.util.Set;
import java.util.UUID;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.example.keirekipro.presentation.security.jwt.JwtProperties;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;
import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.core.Authentication;

@ExtendWith(MockitoExtension.class)
class JwtProviderTest {

    @Mock
    private UserTokenVersionStore userTokenVersionStore;

    private JwtProvider jwtProvider;

    private JwtProperties jwtProperties;

    private static final UUID USER_UUID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String USER_ID = USER_UUID.toString();
    private static final String SECRET_KEY = "vh8JBWqYFC2mJwZ4XD9pE7TKq3mN5RxS2HnUcL7VfAy";
    private static final long ACCESS_TOKEN_VALIDITY = 10L;
    private static final long REFRESH_TOKEN_VALIDITY = 7L;

    @BeforeEach
    void setUp() {
        jwtProperties = new JwtProperties();
        jwtProperties.setSecret(SECRET_KEY);
        jwtProperties.setAccessTokenValidityInMinutes(ACCESS_TOKEN_VALIDITY);
        jwtProperties.setRefreshTokenValidityInDays(REFRESH_TOKEN_VALIDITY);
        jwtProvider = new JwtProvider(jwtProperties, userTokenVersionStore);
    }

    @Test
    @DisplayName("有効なアクセストークンを生成する")
    void test1() {
        when(userTokenVersionStore.get(USER_UUID)).thenReturn(0L);

        Set<String> roles = Set.of("USER");
        String token = jwtProvider.createAccessToken(USER_ID, roles);
        Authentication auth = jwtProvider.getAuthentication(token);

        // ユーザーIDが正しい値である
        assertThat(auth.getPrincipal()).isEqualTo(USER_ID);

        // ロールが正しい値である
        assertThat(auth.getAuthorities())
                .extracting("authority")
                .containsExactlyInAnyOrder("ROLE_USER");

        Date expiration = jwtProvider.getExpirationDate(token);
        Date now = new Date();

        // トークンの有効期限が現在時刻より後で、かつ11分以内である
        // example
        // テスト実行時刻： 15:00:00
        // 期待される有効期限： 15:10:00 （10分後）
        // テストの許容範囲： 15:00:00 ～ 15:11:00
        // (トークン生成と有効期限チェックの時間差を考慮し、1分の余裕を持たせる)
        assertThat(expiration)
                .isAfter(now)
                .isBefore(new Date(now.getTime() + (ACCESS_TOKEN_VALIDITY + 1) * 60 * 1000));
    }

    @Test
    @DisplayName("アクセストークンにtokenVersionクレームが含まれる")
    void test2() {
        when(userTokenVersionStore.get(USER_UUID)).thenReturn(7L);

        Set<String> roles = Set.of("USER");
        String token = jwtProvider.createAccessToken(USER_ID, roles);

        // tokenVersionクレームを直接デコードして検証
        long tokenVersion = JWT.require(Algorithm.HMAC256(jwtProperties.getSecret()))
                .build()
                .verify(token)
                .getClaim("tokenVersion")
                .asLong();

        assertThat(tokenVersion).isEqualTo(7L);
    }

    @Test
    @DisplayName("無効なトークンを検証する: 空トークン")
    void test3() {
        String invalidToken = "";
        // トークンが空の場合、JWTVerificationExceptionがスローされる
        assertThatThrownBy(() -> jwtProvider.getAuthentication(invalidToken))
                .isInstanceOf(JWTVerificationException.class);
    }

    @Test
    @DisplayName("無効なトークンを検証する: 改ざんされたトークン")
    void test4() {
        String invalidToken = "eyJhbGciOiJIUzI1NiJ9."
                + "eyJzdWIiOiIxMjNlNDU2Ny1lODliLTEyZDMtYTQ1Ni00MjY2MTQxNzQwMDAiLCJpYXQiOjE2NzQ5MjYwMDB9"
                + ".invalid-signature";
        // 改ざんされたトークンの場合、JWTVerificationExceptionがスローされる
        assertThatThrownBy(() -> jwtProvider.getAuthentication(invalidToken))
                .isInstanceOf(JWTVerificationException.class);
    }

    @Test
    @DisplayName("無効なトークンを検証する: 別の秘密鍵で署名されたトークン")
    void test5() {
        Algorithm wrongAlgorithm = Algorithm.HMAC256("different-secret-key");
        String invalidToken = JWT.create()
                .withSubject(USER_ID)
                .withIssuedAt(new Date())
                .withExpiresAt(new Date(System.currentTimeMillis() + 10 * 60 * 1000))
                .sign(wrongAlgorithm);
        // 別の秘密鍵で署名されたトークンの場合、JWTVerificationExceptionがスローされる
        assertThatThrownBy(() -> jwtProvider.getAuthentication(invalidToken))
                .isInstanceOf(JWTVerificationException.class);
    }

    @Test
    @DisplayName("無効なトークンを検証する: 有効期限切れ")
    void test6() {
        String expiredToken = JWT.create()
                .withSubject(USER_ID)
                .withIssuedAt(new Date(System.currentTimeMillis() - 30 * 60 * 1000))
                .withExpiresAt(new Date(System.currentTimeMillis() - 60 * 1000))
                .sign(Algorithm.HMAC256(jwtProperties.getSecret()));
        // 有効期限切れのトークンの場合、JWTVerificationExceptionがスローされる
        assertThatThrownBy(() -> jwtProvider.getAuthentication(expiredToken))
                .isInstanceOf(JWTVerificationException.class);
    }

    @Test
    @DisplayName("roles claimが無いトークンは権限が空で認証できる")
    void test7() {
        String tokenWithoutRoles = JWT.create()
                .withSubject(USER_ID)
                .withIssuedAt(new Date())
                .withExpiresAt(new Date(System.currentTimeMillis() + 10 * 60 * 1000))
                .sign(Algorithm.HMAC256(jwtProperties.getSecret()));

        Authentication auth = jwtProvider.getAuthentication(tokenWithoutRoles);

        // ユーザーIDが正しい値である
        assertThat(auth.getPrincipal()).isEqualTo(USER_ID);

        // ロールが空である
        assertThat(auth.getAuthorities()).isEmpty();
    }
}
