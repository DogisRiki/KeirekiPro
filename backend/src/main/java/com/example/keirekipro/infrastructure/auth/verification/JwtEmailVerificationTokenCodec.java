package com.example.keirekipro.infrastructure.auth.verification;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import com.auth0.jwt.JWT;
import com.auth0.jwt.JWTVerifier;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.auth0.jwt.interfaces.DecodedJWT;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationClaims;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationTokenCodec;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * java-jwt で確認のリンクのトークンを作り、読む実装
 * 署名の鍵は jwt.secret から導いた別の鍵で、アクセストークンの鍵とは異なる
 */
@Component
public final class JwtEmailVerificationTokenCodec implements EmailVerificationTokenCodec {

    private static final String AUDIENCE = "keirekipro-email-verification";

    private static final String KEY_DERIVATION_LABEL = "keirekipro-email-verification-v1";

    private static final String HMAC_SHA256 = "HmacSHA256";

    private static final String PURPOSE_CLAIM = "purpose";

    private static final String EMAIL_CLAIM = "email";

    private static final String LINK_EXPIRES_AT_CLAIM = "lexp";

    private final Algorithm algorithm;

    private final JWTVerifier verifier;

    /**
     * jwt.secret から署名の鍵を導いて初期化する
     *
     * @param secret アクセストークンの署名に使う jwt.secret
     */
    public JwtEmailVerificationTokenCodec(@Value("${jwt.secret}") String secret) {
        this.algorithm = Algorithm.HMAC256(deriveKey(secret));
        // exp を付けないため、JWTVerifier はリンクの期限を確かめない
        this.verifier = JWT.require(algorithm).withAudience(AUDIENCE).build();
    }

    @Override
    public String issue(EmailVerificationClaims claims) {
        return JWT.create()
                .withAudience(AUDIENCE)
                .withJWTId(claims.jti())
                .withSubject(claims.subjectId().toString())
                .withClaim(PURPOSE_CLAIM, claims.purpose().name())
                .withClaim(EMAIL_CLAIM, claims.email())
                .withClaim(LINK_EXPIRES_AT_CLAIM, claims.linkExpiresAt().getEpochSecond())
                .sign(algorithm);
    }

    @Override
    public Optional<EmailVerificationClaims> read(String token) {
        if (token == null) {
            return Optional.empty();
        }

        DecodedJWT jwt;
        try {
            jwt = verifier.verify(token);
        } catch (JWTVerificationException e) {
            return Optional.empty();
        }

        String jti = jwt.getId();
        String subject = jwt.getSubject();
        String purpose = jwt.getClaim(PURPOSE_CLAIM).asString();
        String email = jwt.getClaim(EMAIL_CLAIM).asString();
        Long linkExpiresAt = jwt.getClaim(LINK_EXPIRES_AT_CLAIM).asLong();
        if (jti == null || subject == null || purpose == null || email == null || linkExpiresAt == null) {
            return Optional.empty();
        }

        try {
            return Optional.of(new EmailVerificationClaims(
                    jti,
                    UUID.fromString(subject),
                    EmailVerificationPurpose.valueOf(purpose),
                    email,
                    Instant.ofEpochSecond(linkExpiresAt)));
        } catch (IllegalArgumentException e) {
            // sub が UUID でないとき、または purpose が知らない種類のとき
            return Optional.empty();
        }
    }

    /**
     * jwt.secret を鍵にした HMAC-SHA256 で固定の文字列を署名し、確認のリンクの署名の鍵を導く
     */
    private static byte[] deriveKey(String secret) {
        try {
            Mac mac = Mac.getInstance(HMAC_SHA256);
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), HMAC_SHA256));
            return mac.doFinal(KEY_DERIVATION_LABEL.getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("確認のリンクの署名の鍵を導けません。", e);
        }
    }
}
