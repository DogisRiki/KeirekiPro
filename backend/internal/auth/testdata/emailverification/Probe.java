// emailverification_test.go の TestEmailVerificationToken_ReadRejects と TestEmailVerificationToken_ReadAcceptsLikeJava の
// 表と同じ形の値を作り、Java 版の JwtEmailVerificationTokenCodec.read と同じ手順で読んで、読めたか(OK)、
// 読まなかったか(EMPTY と理由)を1行ずつ書く。Go 版のテストの期待は、この結果を写したものである。
// nbf と iat の「まだ来ない」と exp の「過ぎた」は、動かす日によらないよう、遠い未来と遠い過去の時刻を使う。
// 使い方(Java 21。Java 版と同じ java-jwt 4.6.2 と、jackson-databind と jackson-core 2.21.7 と jackson-annotations 2.21 の jar を -cp に渡す):
//   java -cp <jars> Probe.java
import com.auth0.jwt.JWT;
import com.auth0.jwt.JWTVerifier;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.exceptions.JWTVerificationException;
import com.auth0.jwt.interfaces.DecodedJWT;
import java.nio.charset.StandardCharsets;
import java.util.*;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public class Probe {
    static final String SECRET = "vh8JBWqYFC2mJwZ4XD9pE7TKq3mN5RxS2HnUcL7VfAy";
    static final String SAMPLE = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJrZWlyZWtpcHJvLWVtYWlsLXZlcmlmaWNhdGlvbiIsImp0aSI6ImIwNGQ1YjU3LThkMGMtNGJiMi04YTIyLTkzNzliN2YzZDFjMCIsInN1YiI6IjBhMGQ2YjdkLTM4NWQtNDVhMC1iZGIzLWVkZTBlNmYzZWE1ZCIsInB1cnBvc2UiOiJSRUdJU1RSQVRJT04iLCJlbWFpbCI6Im1haWxnZW4tMTc5NDM3ODMzM0BleGFtcGxlLmNvbSIsImxleHAiOjE3OTQ0NjQ3MzN9.ZEFdhpRC2tyTrQXYKSo85Pq78Z44A7zJ1Htoj8MoK1g";
    static final String H = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";

    static byte[] hmac(byte[] key, String data, String alg) throws Exception {
        Mac mac = Mac.getInstance(alg);
        mac.init(new SecretKeySpec(key, alg));
        return mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
    }

    static byte[] derived() throws Exception {
        return hmac(SECRET.getBytes(StandardCharsets.UTF_8), "keirekipro-email-verification-v1", "HmacSHA256");
    }

    static String enc(byte[] b) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }

    static String raw(String header, String payload, byte[] key, String alg) throws Exception {
        String s = enc(header.getBytes(StandardCharsets.UTF_8)) + "." + enc(payload.getBytes(StandardCharsets.UTF_8));
        if (key == null) return s + ".";
        return s + "." + enc(hmac(key, s, alg));
    }

    static String dev(String payload) throws Exception {
        return raw(H, payload, derived(), "HmacSHA256");
    }

    static String payload(String drop, String... extra) {
        String[] fields = {
            "\"aud\":\"keirekipro-email-verification\"",
            "\"jti\":\"b04d5b57-8d0c-4bb2-8a22-9379b7f3d1c0\"",
            "\"sub\":\"0a0d6b7d-385d-45a0-bdb3-ede0e6f3ea5d\"",
            "\"purpose\":\"REGISTRATION\"",
            "\"email\":\"mailgen-1794378333@example.com\"",
            "\"lexp\":1794464733",
        };
        List<String> out = new ArrayList<>();
        for (String f : fields) {
            String name = f.substring(0, f.indexOf(':'));
            if (name.equals("\"" + drop + "\"")) continue;
            boolean replaced = false;
            for (String e : extra) if (e.substring(0, e.indexOf(':')).equals(name)) replaced = true;
            if (!replaced) out.add(f);
        }
        out.addAll(Arrays.asList(extra));
        return "{" + String.join(",", out) + "}";
    }

    static String read(JWTVerifier verifier, String token) {
        DecodedJWT jwt;
        try {
            jwt = verifier.verify(token);
        } catch (JWTVerificationException e) {
            return "EMPTY(" + e.getClass().getSimpleName() + ")";
        }
        String jti = jwt.getId();
        String subject = jwt.getSubject();
        String purpose = jwt.getClaim("purpose").asString();
        String email = jwt.getClaim("email").asString();
        Long lexp = jwt.getClaim("lexp").asLong();
        if (jti == null || subject == null || purpose == null || email == null || lexp == null) return "EMPTY(null)";
        try {
            UUID.fromString(subject);
            Enum.valueOf(P.class, purpose);
        } catch (IllegalArgumentException e) {
            return "EMPTY(arg)";
        }
        return "OK jti=[" + jti + "] lexp=" + lexp;
    }

    enum P { REGISTRATION, ACCOUNT_EMAIL, PENDING_EMAIL, PASSWORD_RESET }

    public static void main(String[] args) throws Exception {
        JWTVerifier v = JWT.require(Algorithm.HMAC256(derived())).withAudience("keirekipro-email-verification").build();
        String[] parts = SAMPLE.split("\\.");
        long future = 4102444800L, past = 1000000000L;
        Object[][] cases = {
            {"sample", SAMPLE},
            {"empty", ""},
            {"tampered", parts[0] + "." + enc(payload("", "\"email\":\"other@example.com\"").getBytes(StandardCharsets.UTF_8)) + "." + parts[2]},
            {"no dots", "abc"},
            {"other derived key", raw(H, payload(""), hmac("test-jwt-secret-0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.UTF_8), "keirekipro-email-verification-v1", "HmacSHA256"), "HmacSHA256")},
            {"raw secret key", raw(H, payload(""), SECRET.getBytes(StandardCharsets.UTF_8), "HmacSHA256")},
            {"none", raw("{\"alg\":\"none\",\"typ\":\"JWT\"}", payload(""), null, null)},
            {"HS512", raw("{\"alg\":\"HS512\",\"typ\":\"JWT\"}", payload(""), derived(), "HmacSHA512")},
            {"aud other", dev(payload("", "\"aud\":\"keirekipro-other\""))},
            {"aud missing", dev(payload("aud"))},
            {"jti missing", dev(payload("jti"))},
            {"sub missing", dev(payload("sub"))},
            {"purpose missing", dev(payload("purpose"))},
            {"purpose unknown", dev(payload("", "\"purpose\":\"UNKNOWN\""))},
            {"email missing", dev(payload("email"))},
            {"lexp missing", dev(payload("lexp"))},
            {"jti null", dev(payload("", "\"jti\":null"))},
            {"sub null", dev(payload("", "\"sub\":null"))},
            {"sub not uuid", dev(payload("", "\"sub\":\"not-a-uuid\""))},
            {"purpose lower", dev(payload("", "\"purpose\":\"registration\""))},
            {"purpose number", dev(payload("", "\"purpose\":1"))},
            {"email null", dev(payload("", "\"email\":null"))},
            {"lexp null", dev(payload("", "\"lexp\":null"))},
            {"lexp string", dev(payload("", "\"lexp\":\"1794464733\""))},
            {"exp past", dev(payload("", "\"exp\":" + past))},
            {"nbf future", dev(payload("", "\"nbf\":" + future))},
            {"iat future", dev(payload("", "\"iat\":" + future))},
            {"sig padded =", SAMPLE + "="},
            {"aud array with other", dev(payload("", "\"aud\":[\"other\",\"keirekipro-email-verification\"]"))},
            {"jti empty", dev(payload("", "\"jti\":\"\""))},
            {"exp nbf iat ok", dev(payload("", "\"exp\":" + future, "\"nbf\":" + past, "\"iat\":" + past))},
            {"unknown field", dev(payload("", "\"x\":{\"y\":[1,2]}"))},
        };
        for (Object[] c : cases) System.out.println(c[0] + " => " + read(v, (String) c[1]));
    }
}
