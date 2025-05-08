package com.example.keirekipro.presentation.security.jwt;

import java.util.Date;
import java.util.List;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.auth0.jwt.interfaces.DecodedJWT;

import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * JWT操作用のユーティリティクラス
 * トークンの生成、検証、パースを行う
 */
@Component
@RequiredArgsConstructor
public class JwtProvider {

    /**
     * JWTプロパティ
     */
    private final JwtProperties jwtProperties;

    /**
     * アルゴリズムのインスタンスをキャッシュ
     */
    private Algorithm algorithm;

    /**
     * アルゴリズムを初期化する
     *
     * @return HMC256アルゴリズム
     */
    private Algorithm getAlgorithm() {
        if (algorithm == null) {
            algorithm = Algorithm.HMAC256(jwtProperties.getSecret());
        }
        return algorithm;
    }

    /**
     * アクセストークンを生成する
     *
     * @param userId ユーザーのID
     * @return 生成されたJWTトークン
     */
    public String createAccessToken(String userId) {
        return createToken(userId,
                jwtProperties.getAccessTokenValidityInMinutes());
    }

    /**
     * リフレッシュトークンを生成する
     *
     * @param userId ユーザーのID
     * @return 生成されたJWTトークン
     */
    public String createRefreshToken(String userId) {
        return createToken(userId,
                jwtProperties.getRefreshTokenValidityInDays() * 24 * 60);
    }

    /**
     * 実際のトークン生成処理を行う
     *
     * @param userId            ユーザーID
     * @param validityInMinutes 有効期間（分）
     * @return 生成されたトークン
     */
    private String createToken(String userId, double validityInMinutes) {
        Date now = new Date();
        long millis = (long) (validityInMinutes * 60_000); // 分→ミリ秒
        Date validity = new Date(now.getTime() + millis);

        return JWT.create()
                .withSubject(userId) // ユーザーIDを設定
                .withIssuedAt(now) // 発行時刻
                .withExpiresAt(validity) // 有効期限
                .sign(getAlgorithm()); // 署名
    }

    /**
     * トークンを検証し、認証情報を取得する
     *
     * @param token JWTトークン
     * @return Spring Securityの認証オブジェクト
     * @throws JWTVerificationException トークンが無効な場合
     */
    public Authentication getAuthentication(String token) throws JWTVerificationException {
        // トークンを検証し、デコードされたJWTを取得
        DecodedJWT jwt = JWT.require(getAlgorithm())
                .build()
                .verify(token);

        // ユーザーIDを取得
        String userId = jwt.getSubject();

        // Spring Securityの認証オブジェクトを作成
        // 今回は簡単のため、権限は設定しない
        return new UsernamePasswordAuthenticationToken(
                userId, // principal（ユーザーID）
                null, // credentials（パスワードなど、ここでは不要）
                List.of() // authorities（権限リスト、今回は空）
        );
    }

    /**
     * トークンの有効期限を取得する(トークンのリフレッシュ判断)
     *
     * @param token JWTトークン
     * @return 有効期限
     * @throws JWTVerificationException トークンが無効な場合
     */
    public Date getExpirationDate(String token) throws JWTVerificationException {
        DecodedJWT jwt = JWT.require(getAlgorithm())
                .build()
                .verify(token);
        return jwt.getExpiresAt();
    }
}
