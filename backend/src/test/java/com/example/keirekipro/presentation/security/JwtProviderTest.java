package com.example.keirekipro.presentation.security;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.UUID;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.example.keirekipro.presentation.security.jwt.JwtProperties;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.Authentication;

class JwtProviderTest {

    private JwtProvider jwtProvider;

    private JwtProperties jwtProperties;

    private static final String USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000").toString();
    private static final String SECRET_KEY = "vh8JBWqYFC2mJwZ4XD9pE7TKq3mN5RxS2HnUcL7VfAy";
    private static final long ACCESS_TOKEN_VALIDITY = 30L;
    private static final long REFRESH_TOKEN_VALIDITY = 7L;
    private static final SimpleDateFormat sdf = new SimpleDateFormat("yyyy/MM/dd HH:mm:ss");

    @BeforeEach
    void setUp() {
        jwtProperties = new JwtProperties();
        jwtProperties.setSecret(SECRET_KEY);
        jwtProperties.setAccessTokenValidityInMinutes(ACCESS_TOKEN_VALIDITY);
        jwtProperties.setRefreshTokenValidityInDays(REFRESH_TOKEN_VALIDITY);
        jwtProvider = new JwtProvider(jwtProperties);
    }

    @Test
    @DisplayName("有効なアクセストークンを生成する")
    void test1() {
        String token = jwtProvider.createAccessToken(USER_ID);
        Authentication auth = jwtProvider.getAuthentication(token);

        // ユーザーIDが正しい値である。
        assertEquals(USER_ID, auth.getPrincipal());

        Date expiration = jwtProvider.getExpirationDate(token);
        Date now = new Date();

        // デバッグ用の時刻出力
        System.out.println("現在時刻 : " + sdf.format(now));
        System.out.println("有効期限 : " + sdf.format(expiration));

        // トークンの有効期限が現在時刻より後で、かつ31分以内である。
        // example
        // テスト実行時刻： 15:00:00
        // 期待される有効期限： 15:30:00 （30分後）
        // テストの許容範囲： 15:00:00 ～ 15:31:00
        // (トークン生成と有効期限チェックの時間差を考慮し、1分の余裕を持たせる)
        assertTrue(expiration.after(now));
        assertTrue(expiration.before(new Date(
                now.getTime() + (jwtProperties.getAccessTokenValidityInMinutes() + 1) * 60 * 1000)));
    }

    @Test
    @DisplayName("有効なリフレッシュトークンを生成する")
    void test2() {
        String token = jwtProvider.createRefreshToken(USER_ID);
        Authentication auth = jwtProvider.getAuthentication(token);

        // ユーザーIDが正しい値である。
        assertEquals(USER_ID, auth.getPrincipal());

        Date expiration = jwtProvider.getExpirationDate(token);
        Date now = new Date();

        // デバッグ用の時刻出力
        System.out.println("現在時刻 : " + sdf.format(now));
        System.out.println("有効期限 : " + sdf.format(expiration));

        // 7日間の有効期限をミリ秒に変換(1日=24時間, 1時間=60分, 1分=60秒, 1秒=1000ミリ秒)
        long daysInMillis = jwtProperties.getRefreshTokenValidityInDays() * 24 * 60 * 60 * 1000L;

        // トークンの有効期限が現在時刻より後で、かつ7日と1分以内である。
        // example
        // テスト実行時刻： 2025/01/01 15:00:00
        // 期待される有効期限： 2025/01/07 15:00:00 （7日後）
        // テストの許容範囲： 2025/01/01 15:00:00 ～ 2025/01/07 15:01:00
        // (トークン生成と有効期限チェックの時間差を考慮し、1分の余裕を持たせる)
        assertTrue(expiration.after(now));
        assertTrue(expiration.before(new Date(now.getTime() + daysInMillis + (60 * 1000))));
    }

    @Test
    @DisplayName("無効なトークンを検証する: 空トークン")
    void test3() {
        String invalidToken = "";
        // トークンが空の場合、JWTVerificationExceptionがスローされる
        assertThrows(JWTVerificationException.class, () -> jwtProvider.getAuthentication(invalidToken));
    }

    @Test
    @DisplayName("無効なトークンを検証する: 改ざんされたトークン")
    void test4() {
        String invalidToken = "eyJhbGciOiJIUzI1NiJ9."
                + "eyJzdWIiOiIxMjNlNDU2Ny1lODliLTEyZDMtYTQ1Ni00MjY2MTQxNzQwMDAiLCJpYXQiOjE2NzQ5MjYwMDB9"
                + ".invalid-signature";
        // 改ざんされたトークンの場合、JWTVerificationExceptionがスローされる
        assertThrows(JWTVerificationException.class, () -> jwtProvider.getAuthentication(invalidToken));
    }

    @Test
    @DisplayName("無効なトークンを検証する: 別の秘密鍵で署名されたトークン")
    void test5() {
        Algorithm wrongAlgorithm = Algorithm.HMAC256("different-secret-key");
        String invalidToken = JWT.create()
                .withSubject(USER_ID)
                .withIssuedAt(new Date())
                .withExpiresAt(new Date(System.currentTimeMillis() + 1000 * 60 * 30))
                .sign(wrongAlgorithm);
        // 別の秘密鍵で署名されたトークンの場合、JWTVerificationExceptionがスローされる
        assertThrows(JWTVerificationException.class, () -> jwtProvider.getAuthentication(invalidToken));
    }

    @Test
    @DisplayName("無効なトークンを検証する: 有効期限切れ")
    void test6() {
        String invalidToken = JWT.create()
                .withSubject(USER_ID)
                .withIssuedAt(new Date(System.currentTimeMillis() - 1000 * 60 * 30)) // 30分前
                .withExpiresAt(new Date(System.currentTimeMillis() - 1000 * 60)) // 1分前に期限切れ
                .sign(Algorithm.HMAC256(jwtProperties.getSecret()));
        // 有効期限切れのトークンの場合、JWTVerificationExceptionがスローされる
        assertThrows(JWTVerificationException.class, () -> jwtProvider.getAuthentication(invalidToken));
    }
}
