import java.util.ArrayList;
import java.util.List;

import org.springframework.web.util.UriComponentsBuilder;

// spring_query_test.go の TestSpringQuery_MatchesSpring が読む vectors.txt を、Java 版の OidcClient と同じ
// UriComponentsBuilder の fromUriString と queryParam と toUriString で作る。
// 1行が1つの URL で、「Spring が書いた URL」のあとに、タブで区切って、項目の名前と値を交互に並べる。
// 名前と値は、Go の文字列の形で書く。ASCII の印字できる文字のほかは、逆斜線と U と16進の8桁の形で書く。
// 使い方(Java 21。Java 版と同じ spring-web と spring-core と spring-jcl の jar を -cp に渡す):
//   java -cp <jars> Gen.java > vectors.txt
public class Gen {
    static final String ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth";

    public static void main(String[] args) {
        List<String[]> cases = new ArrayList<>();
        // ASCII のすべての文字を、1文字だけの値と、前後に文字を置いた値にする
        for (int c = 0; c < 0x80; c++) {
            String s = String.valueOf((char) c);
            cases.add(new String[] {"v", s});
            cases.add(new String[] {"v", "a" + s + "b"});
        }
        // ASCII のすべての文字を、項目の名前にも置く
        for (int c = 0; c < 0x80; c++) {
            cases.add(new String[] {"k" + (char) c, "v"});
        }
        String[] named = {
            "",
            " ",
            "openid email profile",
            "read:user user:email",
            "a+b",
            "/",
            ":",
            "!$'()*+,;:@/?",
            "=&#%",
            "%20%2B%zz",
            "{x}",
            "${x}{{.y}}",
            "http://localhost:5173/api/auth/oidc/callback?x=1&y=a b",
            "日本語",
            "こんにちは 世界+/:",
            new String(Character.toChars(0x80)),
            new String(Character.toChars(0xE9)),
            new String(Character.toChars(0x7FF)),
            new String(Character.toChars(0x800)),
            new String(Character.toChars(0xFFFD)),
            new String(Character.toChars(0xFFFF)),
            new String(Character.toChars(0x1F600)),
            new String(Character.toChars(0x10FFFF)),
            "a" + new String(Character.toChars(0x1F600)) + " b",
        };
        for (String s : named) {
            cases.add(new String[] {"v", s});
        }
        // Java 版の OidcClient と同じ7つの項目と順
        cases.add(new String[] {
            "client_id", "123-abc.apps.googleusercontent.com",
            "response_type", "code",
            "scope", "openid email profile",
            "redirect_uri", "http://localhost:8080/api/auth/oidc/callback",
            "state", "Ab_-0123456789abcdefghijklmnopqrstuvwxyzABCDE",
            "code_challenge", "xyz_-ABC0123456789abcdefghijklmnopqrstuvwxy",
            "code_challenge_method", "S256",
        });
        // 同じ名前が2回あるとき
        cases.add(new String[] {"v", "1", "v", "2 3"});

        for (String[] c : cases) {
            UriComponentsBuilder b = UriComponentsBuilder.fromUriString(ENDPOINT);
            for (int i = 0; i < c.length; i += 2) {
                b.queryParam(c[i], c[i + 1]);
            }
            StringBuilder line = new StringBuilder(b.toUriString());
            for (String s : c) {
                line.append('\t').append(quote(s));
            }
            System.out.println(line);
        }
    }

    static String quote(String s) {
        StringBuilder b = new StringBuilder("\"");
        s.codePoints().forEach(cp -> {
            if (cp == '"' || cp == '\\') {
                b.append('\\').append((char) cp);
            } else if (cp >= 0x20 && cp < 0x7F) {
                b.append((char) cp);
            } else {
                b.append('\\').append('U').append(String.format("%08X", cp));
            }
        });
        return b.append('"').toString();
    }
}
