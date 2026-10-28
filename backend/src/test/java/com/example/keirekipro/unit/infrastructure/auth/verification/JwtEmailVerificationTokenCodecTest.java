package com.example.keirekipro.unit.infrastructure.auth.verification;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import java.util.UUID;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.interfaces.DecodedJWT;
import com.example.keirekipro.infrastructure.auth.verification.JwtEmailVerificationTokenCodec;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationClaims;
import com.example.keirekipro.usecase.auth.verification.EmailVerificationPurpose;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class JwtEmailVerificationTokenCodecTest {

    private static final String SECRET = "test-jwt-secret";
    private static final String AUDIENCE = "keirekipro-email-verification";
    private static final UUID SUBJECT_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String JTI = "0f8fad5b-d9cb-469f-a165-70867728950e";
    private static final String EMAIL = "verify@keirekipro.click";

    private final JwtEmailVerificationTokenCodec codec = new JwtEmailVerificationTokenCodec(SECRET);

    // 設計書のとおり、jwt.secret を鍵にした HMAC-SHA256 で固定の文字列を署名した32バイトを、テストの側でも求める
    private static byte[] derivedKey() {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(SECRET.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return mac.doFinal("keirekipro-email-verification-v1".getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    private static EmailVerificationClaims claims(Instant linkExpiresAt) {
        return new EmailVerificationClaims(JTI, SUBJECT_ID, EmailVerificationPurpose.REGISTRATION, EMAIL,
                linkExpiresAt);
    }

    @Test
    @DisplayName("issue で作ったトークンを read すると同じ中身が返る")
    void test1() {
        Instant linkExpiresAt = Instant.now().plus(1, ChronoUnit.HOURS).truncatedTo(ChronoUnit.SECONDS);
        EmailVerificationClaims original = new EmailVerificationClaims(JTI, SUBJECT_ID,
                EmailVerificationPurpose.PENDING_EMAIL, EMAIL, linkExpiresAt);

        Optional<EmailVerificationClaims> actual = codec.read(codec.issue(original));

        assertThat(actual).contains(original);
    }

    @Test
    @DisplayName("issue は aud と lexp を持ち exp を持たないトークンを作る")
    void test2() {
        Instant linkExpiresAt = Instant.now().plus(1, ChronoUnit.HOURS).truncatedTo(ChronoUnit.SECONDS);

        DecodedJWT decoded = JWT.decode(codec.issue(claims(linkExpiresAt)));

        assertThat(decoded.getAudience()).containsExactly(AUDIENCE);
        assertThat(decoded.getId()).isEqualTo(JTI);
        assertThat(decoded.getSubject()).isEqualTo(SUBJECT_ID.toString());
        assertThat(decoded.getClaim("purpose").asString()).isEqualTo("REGISTRATION");
        assertThat(decoded.getClaim("email").asString()).isEqualTo(EMAIL);
        assertThat(decoded.getClaim("lexp").asLong()).isEqualTo(linkExpiresAt.getEpochSecond());
        assertThat(decoded.getExpiresAt()).isNull();
    }

    @Test
    @DisplayName("lexp を過ぎたトークンも署名が正しければ中身を返す")
    void test3() {
        Instant linkExpiresAt = Instant.now().minus(1, ChronoUnit.DAYS).truncatedTo(ChronoUnit.SECONDS);

        Optional<EmailVerificationClaims> actual = codec.read(codec.issue(claims(linkExpiresAt)));

        assertThat(actual).contains(claims(linkExpiresAt));
    }

    @Test
    @DisplayName("署名を変えたトークン、aud の違うトークン、アクセストークンの鍵で署名したトークンは空を返す")
    void test4() {
        Instant linkExpiresAt = Instant.now().plus(1, ChronoUnit.HOURS).truncatedTo(ChronoUnit.SECONDS);
        String token = codec.issue(claims(linkExpiresAt));

        // 署名の部分の先頭の1文字を替える
        int signatureStart = token.lastIndexOf('.') + 1;
        char replaced = token.charAt(signatureStart) == 'A' ? 'B' : 'A';
        String tampered = token.substring(0, signatureStart) + replaced + token.substring(signatureStart + 1);

        String wrongAudience = JWT.create()
                .withAudience("keirekipro-other")
                .withJWTId(JTI)
                .withSubject(SUBJECT_ID.toString())
                .withClaim("purpose", "REGISTRATION")
                .withClaim("email", EMAIL)
                .withClaim("lexp", linkExpiresAt.getEpochSecond())
                .sign(Algorithm.HMAC256(derivedKey()));

        String signedWithAccessTokenKey = JWT.create()
                .withAudience(AUDIENCE)
                .withJWTId(JTI)
                .withSubject(SUBJECT_ID.toString())
                .withClaim("purpose", "REGISTRATION")
                .withClaim("email", EMAIL)
                .withClaim("lexp", linkExpiresAt.getEpochSecond())
                .sign(Algorithm.HMAC256(SECRET));

        assertThat(codec.read(tampered)).isEmpty();
        assertThat(codec.read(wrongAudience)).isEmpty();
        assertThat(codec.read(signedWithAccessTokenKey)).isEmpty();
    }

    @Test
    @DisplayName("claim が欠けているか形が違うトークンと、JWT の形でない文字列は空を返す")
    void test5() {
        Instant linkExpiresAt = Instant.now().plus(1, ChronoUnit.HOURS).truncatedTo(ChronoUnit.SECONDS);
        Algorithm algorithm = Algorithm.HMAC256(derivedKey());

        String missingEmail = JWT.create()
                .withAudience(AUDIENCE)
                .withJWTId(JTI)
                .withSubject(SUBJECT_ID.toString())
                .withClaim("purpose", "REGISTRATION")
                .withClaim("lexp", linkExpiresAt.getEpochSecond())
                .sign(algorithm);

        String unknownPurpose = JWT.create()
                .withAudience(AUDIENCE)
                .withJWTId(JTI)
                .withSubject(SUBJECT_ID.toString())
                .withClaim("purpose", "UNKNOWN")
                .withClaim("email", EMAIL)
                .withClaim("lexp", linkExpiresAt.getEpochSecond())
                .sign(algorithm);

        String invalidSubject = JWT.create()
                .withAudience(AUDIENCE)
                .withJWTId(JTI)
                .withSubject("not-a-uuid")
                .withClaim("purpose", "REGISTRATION")
                .withClaim("email", EMAIL)
                .withClaim("lexp", linkExpiresAt.getEpochSecond())
                .sign(algorithm);

        String missingLexp = JWT.create()
                .withAudience(AUDIENCE)
                .withJWTId(JTI)
                .withSubject(SUBJECT_ID.toString())
                .withClaim("purpose", "REGISTRATION")
                .withClaim("email", EMAIL)
                .sign(algorithm);

        assertThat(codec.read(missingEmail)).isEmpty();
        assertThat(codec.read(unknownPurpose)).isEmpty();
        assertThat(codec.read(invalidSubject)).isEmpty();
        assertThat(codec.read(missingLexp)).isEmpty();
        assertThat(codec.read("not-a-jwt")).isEmpty();
    }
}
