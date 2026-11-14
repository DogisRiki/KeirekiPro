//go:build compat

package harness

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
)

// twoFactorTestSubject は、Java 版が2段階認証の確認のコードを送るメールの件名である。
const twoFactorTestSubject = "【KeirekiPro】2段階認証コードのお知らせ"

// twoFactorTestMail は、本文の1行目が確認のコード code で、本文の終わりに footer を書いたメールを返す。
func twoFactorTestMail(subject, code, footer string) fakeaws.Email {
	return fakeaws.Email{
		Source: "no-reply@keirekipro.click", To: []string{"taro@example.com"}, Subject: subject,
		Text: code + "\n\n上記の認証コードを入力して、認証を完了させてください。\n" + footer + "\n",
	}
}

func compareMails(c *Comparer, java, goMail fakeaws.Email) []Diff {
	c.CompareMail(step1, []fakeaws.Email{java}, []fakeaws.Email{goMail})
	return c.Diffs()
}

func TestNormalizeTwoFactorCode_OnlyTargetPlaces(t *testing.T) {
	t.Run("2段階認証のメールの本文の1行目のコードは番号に置き換え、ほかの行の6桁の数字は置き換えない", func(t *testing.T) {
		assertNoDiff(t, compareMails(NewComparer("筋書き"),
			twoFactorTestMail(twoFactorTestSubject, "137175", "受付番号 000001"),
			twoFactorTestMail(twoFactorTestSubject, "246802", "受付番号 000001")))
		assertOneDiff(t, compareMails(NewComparer("筋書き"),
			twoFactorTestMail(twoFactorTestSubject, "137175", "受付番号 000001"),
			twoFactorTestMail(twoFactorTestSubject, "246802", "受付番号 000002")),
			TargetMail, "1 通目の本文",
			"<code:1>\n\n上記の認証コードを入力して、認証を完了させてください。\n受付番号 000001\n",
			"<code:1>\n\n上記の認証コードを入力して、認証を完了させてください。\n受付番号 000002\n")
	})
	t.Run("件名が違うメールの1行目の6桁の数字は置き換えない", func(t *testing.T) {
		subject := "【KeirekiPro】パスワード再設定のお知らせ"
		assertOneDiff(t, compareMails(NewComparer("筋書き"),
			twoFactorTestMail(subject, "137175", "x"), twoFactorTestMail(subject, "246802", "x")),
			TargetMail, "1 通目の本文",
			"137175\n\n上記の認証コードを入力して、認証を完了させてください。\nx\n",
			"246802\n\n上記の認証コードを入力して、認証を完了させてください。\nx\n")
	})
	t.Run("本文が1行だけのメールでもコードを置き換える", func(t *testing.T) {
		java := fakeaws.Email{Subject: twoFactorTestSubject, Text: "137175"}
		goMail := fakeaws.Email{Subject: twoFactorTestSubject, Text: "246802"}
		assertNoDiff(t, compareMails(NewComparer("筋書き"), java, goMail))
	})
	t.Run("Redis のキー 2fa:<UUID> の値のコードは番号に置き換える", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.CompareRedis(step1,
			[]RedisEntry{{Key: "2fa:" + javaUser, Type: "string", Value: `"137175"`, TTL: -1}},
			[]RedisEntry{{Key: "2fa:" + goUser, Type: "string", Value: `"246802"`, TTL: -1}})
		assertNoDiff(t, c.Diffs())
	})
	t.Run("メールと Redis の同じコードは同じ番号になる", func(t *testing.T) {
		c := NewComparer("筋書き")
		assertNoDiff(t, compareMails(c,
			twoFactorTestMail(twoFactorTestSubject, "137175", "x"), twoFactorTestMail(twoFactorTestSubject, "246802", "x")))
		// Go 版は、メールで送ったコードと別のコードを Redis に書いた。
		c.CompareRedis(step1,
			[]RedisEntry{{Key: "2fa:" + javaUser, Type: "string", Value: `"137175"`, TTL: -1}},
			[]RedisEntry{{Key: "2fa:" + goUser, Type: "string", Value: `"999999"`, TTL: -1}})
		assertOneDiff(t, c.Diffs(), TargetRedis, "2fa:<uuid:1>", `string "<code:1>" (有効な時間なし)`, `string "<code:2>" (有効な時間なし)`)
	})
	t.Run("Redis のほかのキーの値の6桁の数字は置き換えない", func(t *testing.T) {
		for _, tt := range []struct{ name, javaKey, goKey, path string }{
			{"2段階認証の途中の記録", "2fa:challenge:" + javaURLWord, "2fa:challenge:" + goURLWord, "2fa:challenge:<token:1>"},
			{"ほかの名前のキー", "session:" + javaUser, "session:" + goUser, "session:<uuid:1>"},
			{"2fa: のあとが UUID だけでないキー", "2fa:" + javaUser + ":x", "2fa:" + goUser + ":x", "2fa:<uuid:1>:x"},
			{"2fa: で始まらないキー", "x2fa:" + javaUser, "x2fa:" + goUser, "x2fa:<uuid:1>"},
		} {
			t.Run(tt.name, func(t *testing.T) {
				c := NewComparer("筋書き")
				c.CompareRedis(step1,
					[]RedisEntry{{Key: tt.javaKey, Type: "string", Value: `"137175"`, TTL: -1}},
					[]RedisEntry{{Key: tt.goKey, Type: "string", Value: `"246802"`, TTL: -1}})
				assertOneDiff(t, c.Diffs(), TargetRedis, tt.path, `string "137175" (有効な時間なし)`, `string "246802" (有効な時間なし)`)
			})
		}
	})
}

// verificationClaims は、メールアドレスの確認のリンクの値の項目である。
type verificationClaims struct {
	aud, jti, sub, purpose, email string
	lexp                          int64
}

func verificationTestMail(t *testing.T, c verificationClaims) fakeaws.Email {
	t.Helper()
	token := jwt(t, map[string]any{"alg": "HS256", "typ": "JWT"}, map[string]any{
		"aud": c.aud, "jti": c.jti, "sub": c.sub, "purpose": c.purpose, "email": c.email, "lexp": c.lexp,
	})
	return fakeaws.Email{
		Source: "no-reply@keirekipro.click", To: []string{"taro@example.com"}, Subject: "【KeirekiPro】メールアドレスのご確認",
		Text: "次のリンクを開いてください。\nhttps://app.keirekipro.click/email/verify#" + token + "\n",
	}
}

func TestNormalizeEmailVerificationJWT_LexpAsDelta(t *testing.T) {
	javaAt := time.Date(2026, 11, 11, 9, 0, 0, 0, time.UTC)
	goAt := javaAt.Add(37 * time.Second)
	const validity = 86400
	javaClaims := verificationClaims{
		aud: "keirekipro-email-verification", jti: javaOther, sub: javaUser,
		purpose: "REGISTRATION", email: "taro@example.com", lexp: javaAt.Unix() + validity,
	}
	goClaims := func(lexpDrift int64) verificationClaims {
		g := javaClaims
		g.jti, g.sub, g.lexp = goOther, goUser, goAt.Unix()+validity+lexpDrift
		return g
	}
	compare := func(j, g verificationClaims) []Diff {
		c := NewComparer("筋書き")
		c.CompareResponse(step1, Response{Status: http.StatusNoContent, Received: javaAt}, Response{Status: http.StatusNoContent, Received: goAt})
		return compareMails(c, verificationTestMail(t, j), verificationTestMail(t, g))
	}

	t.Run("lexp は応答を受けた時刻との差で比べ、4秒のずれを許す", func(t *testing.T) {
		for _, drift := range []int64{0, 4, -4} {
			assertNoDiff(t, compare(javaClaims, goClaims(drift)))
		}
	})
	t.Run("lexp の6秒のずれは違いにする", func(t *testing.T) {
		for _, drift := range []int64{6, -6} {
			diffs := compare(javaClaims, goClaims(drift))
			if len(diffs) != 1 || diffs[0].Path != "1 通目の本文" {
				t.Fatalf("ずれ %d 秒の違い = %+v", drift, diffs)
			}
			wantJava := `"lexp":"<lexp:+86400>"`
			wantGo := `"lexp":"<lexp:+` + strconv.FormatInt(validity+drift, 10) + `>"`
			if !strings.Contains(diffs[0].Java, wantJava) || !strings.Contains(diffs[0].Go, wantGo) {
				t.Errorf("違いの値に lexp の差がありません: Java %q Go %q", diffs[0].Java, diffs[0].Go)
			}
		}
	})
	t.Run("aud と sub と purpose と email の違いを報告する", func(t *testing.T) {
		for _, mutate := range []func(c *verificationClaims){
			func(c *verificationClaims) { c.aud = "keirekipro-other" },
			func(c *verificationClaims) { c.sub = "user-1" },
			func(c *verificationClaims) { c.purpose = "PASSWORD_RESET" },
			func(c *verificationClaims) { c.email = "jiro@example.com" },
		} {
			g := goClaims(0)
			mutate(&g)
			if diffs := compare(javaClaims, g); len(diffs) != 1 || diffs[0].Path != "1 通目の本文" {
				t.Errorf("項目を変えた値 %+v の違い = %+v", g, diffs)
			}
		}
	})
	t.Run("メールを初めて見た段の応答の時刻を基準にする", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.CompareResponse(step1, Response{Status: http.StatusNoContent, Received: javaAt}, Response{Status: http.StatusNoContent, Received: goAt})
		java, goMail := verificationTestMail(t, javaClaims), verificationTestMail(t, goClaims(0))
		assertNoDiff(t, compareMails(c, java, goMail))
		// 次の段の応答を受けた時刻は、版ごとにずれる。前の段のメールの lexp の基準は変えず、
		// 次の段で届いた2通目のメールは、次の段の応答の時刻を基準にする
		step2 := StepRef{Index: 2, Name: "段2", Operation: "getResume"}
		javaAt2, goAt2 := javaAt.Add(100*time.Second), goAt.Add(300*time.Second)
		c.CompareResponse(step2, Response{Status: http.StatusOK, Received: javaAt2}, Response{Status: http.StatusOK, Received: goAt2})
		java2, go2 := javaClaims, goClaims(0)
		java2.lexp, go2.lexp = javaAt2.Unix()+validity, goAt2.Unix()+validity
		c.CompareMail(step2,
			[]fakeaws.Email{java, verificationTestMail(t, java2)},
			[]fakeaws.Email{goMail, verificationTestMail(t, go2)})
		assertNoDiff(t, c.Diffs())
	})
	t.Run("版に送った段の応答に、受けた時刻が入る", func(t *testing.T) {
		srv, _ := recordingServer(t, func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) })
		s := NewSession()
		s.now = func() time.Time { return javaAt }
		resp, err := s.Send(context.Background(), srv.Client(), srv.URL, get("段", "/"))
		if err != nil {
			t.Fatal(err)
		}
		if !resp.Received.Equal(javaAt) {
			t.Errorf("応答を受けた時刻が %v でした。期待は %v です", resp.Received, javaAt)
		}
	})
}

func TestNormalizeTextBodyURL_StateAndChallenge(t *testing.T) {
	authURL := func(clientID, state, challenge string) string {
		return "https://accounts.google.com/o/oauth2/v2/auth?response_type=code&client_id=" + clientID +
			"&scope=openid%20email&state=" + state + "&redirect_uri=http://compat.test/api/auth/oidc/callback&code_challenge=" +
			challenge + "&code_challenge_method=S256"
	}
	response := func(contentType, body string) Response {
		return Response{Status: http.StatusOK, Header: http.Header{"Content-Type": {contentType}}, Body: []byte(body)}
	}
	// application/json でも、本文が JSON として読めないときは、文字の本文として比べる
	for _, contentType := range []string{"text/plain;charset=UTF-8", "application/json"} {
		t.Run(contentType, func(t *testing.T) {
			c := NewComparer("筋書き")
			c.CompareResponse(step1,
				response(contentType, authURL("google-client", javaURLWord, otherWord)),
				response(contentType, authURL("google-client", goURLWord, javaURLWord)))
			assertNoDiff(t, c.Diffs())

			c = NewComparer("筋書き")
			c.CompareResponse(step1,
				response(contentType, authURL("google-client", javaURLWord, otherWord)),
				response(contentType, authURL("other-client", goURLWord, javaURLWord)))
			assertOneDiff(t, c.Diffs(), TargetBody, "1 行目",
				strconv.Quote(authURL("google-client", "<token:1>", "<token:2>")),
				strconv.Quote(authURL("other-client", "<token:1>", "<token:2>")))
		})
	}
}

func TestNormalizeURLFragment_JWTWithoutEquals(t *testing.T) {
	token := jwt(t, map[string]any{"alg": "HS256"}, map[string]any{"sub": javaUser, "purpose": "REGISTRATION", "jti": "x"})
	tests := []struct{ name, in, want string }{
		{
			name: "# のあとの JWT",
			in:   "リンク: https://app.keirekipro.click/email/verify#" + token + " です",
			want: `リンク: https://app.keirekipro.click/email/verify#<jwt:{"purpose":"REGISTRATION","sub":"<uuid:1>"}> です`,
		},
		{name: "# のあとの UUID", in: "http://a.test/x#" + javaUser, want: "http://a.test/x#<uuid:1>"},
		{name: "# のあとのトークン", in: "http://a.test/x#" + javaURLWord, want: "http://a.test/x#<token:1>"},
		{name: "# のあとのほかの語は変えない", in: "http://a.test/x#section", want: "http://a.test/x#section"},
		{name: "# のあとの 名前=値 の組と = の無い部分", in: "http://a.test/x#a=" + javaURLWord + "&" + goURLWord + "&b", want: "http://a.test/x#a=<token:1>&<token:2>&b"},
		{name: "問い合わせの = の無い部分は変えない", in: "http://a.test/x?" + javaURLWord, want: "http://a.test/x?" + javaURLWord},
		{name: "問い合わせと # のあとの両方", in: "http://a.test/x?t=" + javaURLWord + "#" + goURLWord, want: "http://a.test/x?t=<token:1>#<token:2>"},
		{name: "パスと # のあと", in: "http://a.test/p/" + javaURLWord + "#" + token, want: `http://a.test/p/<token:1>#<jwt:{"purpose":"REGISTRATION","sub":"<uuid:1>"}>`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := NewNormalizer().URLs(tt.in); got != tt.want {
				t.Errorf("URLs(%q)\n got  %q\n want %q", tt.in, got, tt.want)
			}
		})
	}
}

func TestNormalize_PresignedURL(t *testing.T) {
	const user = "0b9a3c1e-6f2d-4a8b-9c7e-1d2f3a4b5c6d"
	// signed は、版が返す形の署名付きの URL である。date と credDate と sig は、要求のたびに違う値である
	signed := func(date, credDate, sig, expires string) string {
		return "http://localhost:4566/keirekipro-storage//" + user + "/a.png?X-Amz-Algorithm=AWS4-HMAC-SHA256" +
			"&X-Amz-Credential=test%2F" + credDate + "%2Fap-northeast-1%2Fs3%2Faws4_request&X-Amz-Date=" + date +
			"&X-Amz-Expires=" + expires + "&X-Amz-SignedHeaders=host&X-Amz-Signature=" + sig
	}
	java := signed("20261114T010203Z", "20261114", strings.Repeat("a", 64), "600")
	goURL := signed("20261115T235959Z", "20261115", strings.Repeat("b", 64), "600")
	// X-Amz-Date の値と X-Amz-Credential の中の日付と X-Amz-Signature の値だけを置き換え、
	// X-Amz-Expires と項目の並ぶ順と URL のパスは変えない。パスの中の利用者の ID は、今の UUID の置き換えで比べる
	want := "http://localhost:4566/keirekipro-storage//<uuid:1>/a.png?X-Amz-Algorithm=AWS4-HMAC-SHA256" +
		"&X-Amz-Credential=test%2F<amz-credential-date>%2Fap-northeast-1%2Fs3%2Faws4_request&X-Amz-Date=<amz-date>" +
		"&X-Amz-Expires=600&X-Amz-SignedHeaders=host&X-Amz-Signature=<amz-signature>"
	if got := NewNormalizer().Text(java); got != want {
		t.Errorf("Java 版の URL =\n%s\nwant\n%s", got, want)
	}
	if got := NewNormalizer().Text(goURL); got != want {
		t.Errorf("Go 版の URL =\n%s\nwant\n%s", got, want)
	}

	// JSON の本文の値と、文字の本文の中の URL も置き換える。X-Amz-Credential の / が %2F でなくても日付を置き換える
	raw := strings.ReplaceAll(java, "%2F", "/")
	gotJSON := NewNormalizer().value(map[string]any{"profileImage": java, "list": []any{"画像は " + raw + " です"}}, true)
	wantJSON := map[string]any{"profileImage": want, "list": []any{"画像は " + strings.ReplaceAll(want, "%2F", "/") + " です"}}
	if canonicalJSON(gotJSON) != canonicalJSON(wantJSON) {
		t.Errorf("JSON の本文 =\n%s\nwant\n%s", canonicalJSON(gotJSON), canonicalJSON(wantJSON))
	}

	// 使える時間と、項目の並ぶ順と、パスが違う URL は、置き換えたあとも違いとして残る
	reordered := strings.Replace(java, "X-Amz-Algorithm=AWS4-HMAC-SHA256&", "", 1) + "&X-Amz-Algorithm=AWS4-HMAC-SHA256"
	for name, other := range map[string]string{
		"使える時間": signed("20261114T010203Z", "20261114", strings.Repeat("a", 64), "3600"),
		"項目の順":  reordered,
		"パス":    strings.Replace(java, "/a.png?", "/b.png?", 1),
	} {
		if got := NewNormalizer().Text(other); got == want {
			t.Errorf("%s の違う URL が、置き換えたあとに同じになりました: %s", name, got)
		}
	}

	// 問い合わせに X-Amz-Signature を持たない URL は、X-Amz-Date も変えない
	for _, s := range []string{
		"http://localhost:4566/b/k?X-Amz-Date=20261114T010203Z&X-Amz-Credential=test%2F20261114%2Fr",
		"http://localhost:4566/b/k?X-Amz-Date=20261114T010203Z#a&X-Amz-Signature=" + strings.Repeat("a", 64),
		"http://localhost:4566/b/k?X-Amz-Signature-Version=1&X-Amz-Date=20261114T010203Z",
	} {
		if got := NewNormalizer().Text(s); got != s {
			t.Errorf("X-Amz-Signature の無い URL = %s, want そのまま %s", got, s)
		}
	}
}
