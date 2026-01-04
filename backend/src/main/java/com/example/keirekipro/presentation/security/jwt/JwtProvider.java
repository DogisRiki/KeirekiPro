package com.example.keirekipro.presentation.security.jwt;

import java.util.Date;
import java.util.List;
import java.util.Set;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.auth0.jwt.interfaces.DecodedJWT;

import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
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
     * ロール情報を格納するclaim名
     */
    private static final String ROLES_CLAIM = "roles";

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
     * @param roles  ロール名のSet
     * @return 生成されたJWTトークン
     */
    public String createAccessToken(String userId, Set<String> roles) {
        return createToken(userId, roles, jwtProperties.getAccessTokenValidityInMinutes());
    }

    /**
     * リフレッシュトークンを生成する
     *
     * @param userId ユーザーのID
     * @param roles  ロール名のSet
     * @return 生成されたJWTトークン
     */
    public String createRefreshToken(String userId, Set<String> roles) {
        return createToken(userId, roles, jwtProperties.getRefreshTokenValidityInDays() * 24 * 60);
    }

    /**
     * 実際のトークン生成処理を行う
     *
     * @param userId            ユーザーID
     * @param roles             ロール名のSet
     * @param validityInMinutes 有効期間（分）
     * @return 生成されたトークン
     */
    private String createToken(String userId, Set<String> roles, double validityInMinutes) {
        Date now = new Date();
        long millis = (long) (validityInMinutes * 60_000);
        Date validity = new Date(now.getTime() + millis);

        return JWT.create()
                .withSubject(userId)
                .withClaim(ROLES_CLAIM, roles != null ? roles.stream().toList() : List.of())
                .withIssuedAt(now)
                .withExpiresAt(validity)
                .sign(getAlgorithm());
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

        // JWTからロール情報を取得
        List<String> roles = jwt.getClaim(ROLES_CLAIM).asList(String.class);
        if (roles == null) {
            roles = List.of();
        }

        // Spring SecurityのGrantedAuthorityに変換
        // ROLE_プレフィックスを付与
        List<SimpleGrantedAuthority> authorities = roles.stream()
                .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();

        // Spring Securityの認証オブジェクトを作成
        return new UsernamePasswordAuthenticationToken(userId, null, authorities);
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
