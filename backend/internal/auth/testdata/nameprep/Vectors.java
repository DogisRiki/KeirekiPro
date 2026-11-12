import java.net.IDN;
import java.util.LinkedHashSet;
import java.util.Random;
import java.util.Set;

import jakarta.validation.constraints.Email;

import org.hibernate.validator.internal.constraintvalidators.bv.EmailValidator;

// validate_test.go の TestValidate_EmailLikeHibernate が読む email_vectors.txt を、Java 版と同じ
// Hibernate Validator 9.1.5 の EmailValidator(@Email の既定の設定)の判定で作る。
// 1行が1つのメールアドレスで、「true か false」とタブと、Go の文字列の形で書いたメールアドレスである。
// 文字列の中の ASCII の外の文字は、見えない文字を読めるように、すべて逆斜線と u と16進の4桁の形で書く。
// 使い方(Java 21。Hibernate Validator と jakarta.validation-api と jboss-logging と classmate の jar を -cp に渡す):
//   java -cp <jars> Vectors.java full > email_vectors.txt
//   java -cp <jars> Vectors.java idna > idna_vectors.txt
//   java -cp <jars> Vectors.java exhaustive > all.txt  (基本多言語面のすべての文字を4つの位置に置いた値。リポジトリに置かない)
public class Vectors {
    @Email
    static String field;

    static final EmailValidator V = new EmailValidator();

    public static void main(String[] args) throws Exception {
        V.initialize(Vectors.class.getDeclaredField("field").getAnnotation(Email.class));
        if (args[0].equals("idna")) {
            idna();
            return;
        }
        Set<String> out = new LinkedHashSet<>();
        if (args[0].equals("exhaustive")) {
            for (int cp = 0; cp <= 0xFFFF; cp++) {
                if (cp >= 0xD800 && cp <= 0xDFFF) {
                    continue;
                }
                String c = String.valueOf((char) cp);
                out.add("a" + c + "@b.jp");
                out.add("a@b" + c + "z.jp");
                out.add("a@" + c + ".jp");
                out.add("a@\u05D0" + c + "\u05D0.jp");
            }
        } else {
            hand(out);
            for (int cp = 0x80; cp <= 0xFFFF; cp += 37) {
                if (cp >= 0xD800 && cp <= 0xDFFF) {
                    continue;
                }
                out.add("a@b" + (char) cp + "z.jp");
            }
            for (int cp = 0x80; cp <= 0xFFFF; cp += 211) {
                if (cp >= 0xD800 && cp <= 0xDFFF) {
                    continue;
                }
                out.add("a" + (char) cp + "@b.jp");
            }
            random(out);
        }
        StringBuilder b = new StringBuilder();
        for (String s : out) {
            b.append(V.isValid(s, null)).append('\t').append(quote(s)).append('\n');
        }
        System.out.print(b);
    }

    static void hand(Set<String> o) {
        // 前の部分の形
        String[] simple = { "user@example.com", "USER@EXAMPLE.COM", "a.b@example.com", ".a@example.com", "a.@example.com",
                "a..b@example.com", "a+b-c_d@example.com", "\"a b\"@example.com", "\"a\\\\b\"@example.com",
                "\"a\\\"b\"@example.com", "\"a\"b\"@example.com", "\"\"@example.com", "\"a\".b@example.com",
                "\"a@b\"@example.com", "a@b@example.com", "@example.com", "noat", "a@", "a b@example.com",
                "\u3042\u3044\u3046@example.com", "a\u0000@example.com", "a\t@example.com", "\uD83D\uDE00@example.com",
                "a@\uD83D\uDE00.com",
                // 後ろの部分の形
                "a@example", "a@example.", "a@.example.com", "a@-example.com", "a@example-.com", "a@ex--ample.com",
                "a@ex_ample.com", "a@[127.0.0.1]", "a@[999.0.0.1]", "a@[1.2.3]", "a@[IPv6:2001:db8::1]",
                "a@[ipv6:2001:db8::1]", "a@[IPv6:fe80::1%eth0]", "a@[IPv6:FE80::1%eth0]", "a@[IPv6:fe80::1%\u212A]",
                "a@[IPv6:::ffff:1.2.3.4]", "a@[IPv6:::FFFF:1.2.3.4]", "a@[IPv6:1:2:3:4:5:6:7:8]",
                "a@[IPv6:1:2:3:4:5:6:7:8:9]",
                "a@\u4F8B\u3048.\u30C6\u30B9\u30C8", "a@\u4F8B\u3048\u3002\u30C6\u30B9\u30C8",
                "a@\u4F8B\u3048\uFF0E\u30C6\u30B9\u30C8", "a@\u4F8B\u3048\uFF61\u30C6\u30B9\u30C8", "a@\u4F8B\u3048\u3002",
                "a@\u3002", "a@.", "a@\u4F8B\u3048\u3002\u3002\u30C6\u30B9\u30C8",
                "a@\uFF25\uFF38\uFF21\uFF2D\uFF30\uFF2C\uFF25.com", "a@\uFF58\uFF4E--abc.com", "a@xn--abc.com",
                "a@xn--\u3042.com", "a@XN--\u3042.com", "a@\uFF58\uFF4E\uFF0D\uFF0D\u3042.com",
                "a@\u00DF.com", "a@\uFB01.com", "a@\u00C4.com", "a@a\u00ADb.com", "a@\u00AD.com", "a@a\u200Bb.com",
                "a@a\u3000b.com", "a@a\uFFFDb.com", "a@a\uE000b.com", "a@\u0221.com",
                // 書く向き
                "a@\u05D0\u05D1.com", "a@\u05D0a\u05D1.com", "a@a\u05D0.com", "a@\u05D01.com", "a@1\u05D0.com",
                "a@\u05D0\u05B8.com", "a@\u0627\u0644.com", "a@\u0627\u0653.com", "a@\u0627\u0653\u0627.com",
                "a@\u0661\u0627.com", "a@\uFB20.com",
                // 合成
                "a@e\u0301.com", "a@\u05D0e\u0301.com", "a@a\u0323\u0302.com", "a@a\u0302\u0323.com",
                "a@\u1100\u1161.com", "a@\u1100\u1161\u11A8.com", "a@\uAC00\u11A8.com", "a@\u0B47\u0B3E.com",
                "a@\u2126.com", "a@\u212B.com", "a@\u3300.com", "a@\u00BD.com", "a@\u2024.com" };
        for (String s : simple) {
            o.add(s);
        }
        // 長さの境目
        for (int n = 60; n <= 66; n++) {
            o.add("a".repeat(n) + "@example.com");
            o.add("a@" + "b".repeat(n) + ".com");
        }
        for (int n = 1; n <= 60; n++) {
            o.add("a@" + "\u3042".repeat(n) + ".com");
            o.add("a@x" + "\u00E9".repeat(n) + ".com");
            o.add("a@x" + "e\u0301".repeat(n) + ".com");
        }
        for (int n = 60; n <= 64; n++) {
            o.add("\u3042".repeat(n) + "@example.com");
        }
        for (char dot : new char[] { '.', '\u3002' }) {
            for (int total = 250; total <= 258; total++) {
                StringBuilder d = new StringBuilder();
                while (d.length() + 64 < total) {
                    d.append("c".repeat(63)).append(dot);
                }
                d.append("d".repeat(total - d.length()));
                o.add("a@" + d);
            }
        }
    }

    static void random(Set<String> o) {
        String[] pool = { "a", "Z", "0", "-", ".", "@", "\"", "\\", " ", "_", "\u3042", "\u6F22", "\u05D0", "\u05D1",
                "\u0627", "\u0661", "\u0301", "\u0323", "\u05B8", "\u0653", "\uFF21", "\uFF58", "\uFF0D", "\u3002", "\uFF0E",
                "\uFF61", "\u00DF", "\uFB01", "\u00C4", "\u00AD", "\u200B", "\u3000", "\u1100", "\u1161", "\u11A8",
                "\uAC00", "\u0221", "\uE000", "\u2126", "\u3300", "\u2024", "\uD83D\uDE00" };
        Random r = new Random(20261111L);
        int added = 0;
        while (added < 1500) {
            StringBuilder s = new StringBuilder();
            int localLen = 1 + r.nextInt(4);
            for (int i = 0; i < localLen; i++) {
                s.append(r.nextInt(3) == 0 ? pool[r.nextInt(pool.length)] : "a");
            }
            s.append('@');
            int domainLen = 1 + r.nextInt(8);
            for (int i = 0; i < domainLen; i++) {
                s.append(pool[r.nextInt(pool.length)]);
            }
            if (r.nextBoolean()) {
                s.append(".jp");
            }
            if (o.add(s.toString())) {
                added++;
            }
        }
    }

    // idna は、validate_test.go の TestValidate_IDNAToASCII が読む idna_vectors.txt を作る。
    // 1行が1つのドメインで、Go の文字列の形で書いたドメインと、タブと、java.net.IDN.toASCII の結果である。
    // IllegalArgumentException を投げたときは、結果を「!」と書く。
    static void idna() {
        String[] in = { "example.com", "\u4F8B\u3048.\u30C6\u30B9\u30C8", "b\u00FCcher.de", "M\u00FCnchen", "\u00C4\u00D6\u00DC", "\uFF58\uFF4E--abc", "\uFF25\uFF38\uFF21\uFF2D\uFF30\uFF2C\uFF25\u3002com",
                "\u0627\u0653", "e" + (char) 0x0301, "a" + (char) 0x00AD + "b", "\uAC00\u11A8", "\u1100" + "\u1161" + "\u11A8", "\u2126" + "\u212B", "\u3300", "\u00DF",
                "\uFB01", "\u05D0\u05D1", "abc\u3002", "\u3002", "\u65E5\u672C\u8A9E\u30C9\u30E1\u30A4\u30F3\u540D\u4F8B", "\u30D1\u30D5\u30A3\u30FCde\u30EB\u30F3\u30D0", "Maji\u3067Koi\u3059\u308B5\u79D2\u524D",
                "\u5B89\u5BA4\u5948\u7F8E\u6075-with-SUPER-MONKEYS", "\u0644\u064A\u0647\u0645\u0627\u0628\u062A\u0643\u0644\u0645\u0648\u0634\u0639\u0631\u0628\u064A\u061F", "x" + "\u00E9".repeat(20), "\u4E2D\u6587".repeat(5),
                "x" + "\u00E9".repeat(57), "x" + "\u00E9".repeat(58), "a..b", "", ".", "xn--\u3042", "XN--\u3042", "a\u05D0", "\u05D01", "1\u05D0",
                "a" + (char) 0x200B + "b", "a" + (char) 0xE000, "\u0221", "a" + (char) 0xFFFD, "\uFF58\uFF4E\uFF0D\uFF0D\u3042" };
        StringBuilder b = new StringBuilder();
        for (String s : in) {
            String r;
            try {
                r = IDN.toASCII(s);
            } catch (IllegalArgumentException e) {
                r = "!";
            }
            b.append(quote(s)).append('\t').append(r).append('\n');
        }
        System.out.print(b);
    }

    static String quote(String s) {
        StringBuilder b = new StringBuilder("\"");
        s.codePoints().forEach(c -> {
            if (c == '"' || c == '\\') {
                b.append('\\').append((char) c);
            } else if (c >= 0x20 && c < 0x7F) {
                b.append((char) c);
            } else if (c > 0xFFFF) {
                b.append(String.format("\\U%08X", c));
            } else {
                b.append(String.format("\\u%04X", c));
            }
        });
        return b.append('"').toString();
    }
}
