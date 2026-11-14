//go:build compat

package harness

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
)

// テストの UUID である。java と go で別の乱数を使った場面を表す。
const (
	javaUser   = "11111111-1111-4111-8111-111111111111"
	javaResume = "22222222-2222-4222-8222-222222222222"
	javaOther  = "33333333-3333-4333-8333-333333333333"
	goUser     = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	goResume   = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
	goOther    = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
)

// テストの、URL の中のトークンである。Java 版の SecurityUtil と同じく、32バイトを base64url にした43文字の形にしている。
const (
	javaURLWord = "Q3VzdG9tVG9rZW5Gb3JKYXZhVmVyc2lvbjAxMjM0NTY"
	goURLWord   = "R29WZXJzaW9uVG9rZW5WYWx1ZUZvckNvbXBhcmUwOTg"
	otherWord   = "T3RoZXJUb2tlblZhbHVlRm9yQ29tcGFyaXNvbjEyMzQ"
)

var step1 = StepRef{Index: 1, Name: "段1", Operation: "getResume"}

func jsonResponse(status int, body string) Response {
	return Response{Status: status, Header: http.Header{"Content-Type": {"application/json"}}, Body: []byte(body)}
}

func compareJSONBodies(java, goBody string) []Diff {
	c := NewComparer("筋書き")
	c.CompareResponse(step1, jsonResponse(200, java), jsonResponse(200, goBody))
	return c.Diffs()
}

func assertNoDiff(t *testing.T, diffs []Diff) {
	t.Helper()
	if len(diffs) != 0 {
		t.Fatalf("違いが無いはずですが、%d 件ありました: %+v", len(diffs), diffs)
	}
}

func assertOneDiff(t *testing.T, diffs []Diff, target, path, java, goValue string) {
	t.Helper()
	if len(diffs) != 1 {
		t.Fatalf("違いは1件のはずですが、%d 件ありました: %+v", len(diffs), diffs)
	}
	d := diffs[0]
	if d.Target != target || d.Path != path || d.Java != java || d.Go != goValue {
		t.Fatalf("違い = {%s %s %q %q}, want {%s %s %q %q}", d.Target, d.Path, d.Java, d.Go, target, path, java, goValue)
	}
	if d.Scenario == "" || d.Step.Index == 0 {
		t.Fatalf("違いに筋書きと段がありません: %+v", d)
	}
}

func TestCompareJSON_UUIDNumbering(t *testing.T) {
	t.Run("本文: UUID は現れた順の番号で比べる", func(t *testing.T) {
		java := `{"id":"` + javaUser + `","resumes":[{"id":"` + javaResume + `","owner":"` + javaUser + `"}]}`
		goBody := `{"id":"` + goUser + `","resumes":[{"id":"` + goResume + `","owner":"` + goUser + `"}]}`
		assertNoDiff(t, compareJSONBodies(java, goBody))
	})
	t.Run("本文: 指す先の違う UUID は違いになる", func(t *testing.T) {
		java := `{"id":"` + javaUser + `","resumes":[{"id":"` + javaResume + `","owner":"` + javaUser + `"}]}`
		goBody := `{"id":"` + goUser + `","resumes":[{"id":"` + goResume + `","owner":"` + goResume + `"}]}`
		assertOneDiff(t, compareJSONBodies(java, goBody), TargetBody, "$.resumes[0].owner", `"<uuid:1>"`, `"<uuid:2>"`)
	})
	t.Run("本文: 大文字の UUID も同じ番号になる", func(t *testing.T) {
		java := `["` + javaUser + `","` + strings.ToUpper(javaUser) + `"]`
		goBody := `["` + goUser + `","` + goUser + `"]`
		assertNoDiff(t, compareJSONBodies(java, goBody))
	})
	t.Run("本文: 日時は時刻でなく形を比べる", func(t *testing.T) {
		assertNoDiff(t, compareJSONBodies(`{"at":"2026-11-09T10:00:00.123"}`, `{"at":"2025-01-02T03:04:05.5"}`))
		assertNoDiff(t, compareJSONBodies(`{"at":"2026-11-09T10:00:00"}`, `{"at":"2025-01-02T03:04:05.123456"}`))
		assertOneDiff(t, compareJSONBodies(`{"at":"2026-11-09T10:00:00"}`, `{"at":"2026-11-09T10:00:00Z"}`),
			TargetBody, "$.at", `"<datetime:yyyy-MM-ddTHH:mm:ss>"`, `"<datetime:yyyy-MM-ddTHH:mm:ssZ>"`)
		assertOneDiff(t, compareJSONBodies(`{"at":"2026-11-09T10:00:00+09:00"}`, `{"at":"2026-11-09 10:00:00+09:00"}`),
			TargetBody, "$.at", `"<datetime:yyyy-MM-ddTHH:mm:ss+hh:mm>"`, `"<datetime:yyyy-MM-dd HH:mm:ss+hh:mm>"`)
	})
	t.Run("本文: 日付だけの値と暦に無い日時は置き換えない", func(t *testing.T) {
		assertOneDiff(t, compareJSONBodies(`{"d":"2024-01-01"}`, `{"d":"2024-01-02"}`), TargetBody, "$.d", `"2024-01-01"`, `"2024-01-02"`)
		assertOneDiff(t, compareJSONBodies(`{"d":"2024-13-01T00:00:00"}`, `{"d":"2024-12-01T00:00:00"}`),
			TargetBody, "$.d", `"2024-13-01T00:00:00"`, `"<datetime:yyyy-MM-ddTHH:mm:ss>"`)
	})
	t.Run("本文: 値の違いを場所ごとに報告する", func(t *testing.T) {
		diffs := compareJSONBodies(`{"name":"太郎","tags":["a","b"],"n":1,"x-y":true}`, `{"name":"次郎","tags":["a","b","c"],"n":1.0,"extra":null}`)
		want := []struct{ path, java, goValue string }{
			{"$.extra", absent, "null"},
			{"$.n", "1", "1.0"},
			{"$.name", `"太郎"`, `"次郎"`},
			{"$.tags", `["a","b"]`, `["a","b","c"]`},
			{`$["x-y"]`, "true", absent},
		}
		if len(diffs) != len(want) {
			t.Fatalf("違い = %+v, want %d 件", diffs, len(want))
		}
		for i, w := range want {
			if diffs[i].Path != w.path || diffs[i].Java != w.java || diffs[i].Go != w.goValue {
				t.Errorf("違い[%d] = {%s %q %q}, want {%s %q %q}", i, diffs[i].Path, diffs[i].Java, diffs[i].Go, w.path, w.java, w.goValue)
			}
		}
	})
	t.Run("本文: JSON として読めない本文は文字で比べる", func(t *testing.T) {
		assertOneDiff(t, compareJSONBodies(`{"a":`, `{"a":1}`), TargetBody, "1 行目", `"{\"a\":"`, `"{\"a\":1}"`)
	})
	t.Run("ステータス", func(t *testing.T) {
		c := NewComparer("筋書き")
		got := c.CompareResponse(step1, jsonResponse(200, `{}`), jsonResponse(404, `{}`))
		assertOneDiff(t, c.Diffs(), TargetStatus, "", "200", "404")
		if got.JavaStatus != 200 || got.GoStatus != 404 || c.Diffs()[0].Step.GoStatus != 404 {
			t.Fatalf("段のステータス = %+v, 違い = %+v", got, c.Diffs())
		}
	})
	t.Run("Markdown は1文字も違わない", func(t *testing.T) {
		markdown := func(id, at, tail string) Response {
			body := "# 職務経歴書\n\nID: " + id + "\n更新: " + at + "\n\n- 経歴" + tail + "\n"
			return Response{Status: 200, Header: http.Header{"Content-Type": {"text/markdown; charset=utf-8"}}, Body: []byte(body)}
		}
		c := NewComparer("筋書き")
		c.CompareResponse(step1, markdown(javaResume, "2026-11-09T10:00:00", ""), markdown(goResume, "2025-01-01T00:00:00", ""))
		assertNoDiff(t, c.Diffs())

		c = NewComparer("筋書き")
		c.CompareResponse(step1, markdown(javaResume, "2026-11-09T10:00:00", ""), markdown(goResume, "2025-01-01T00:00:00", " "))
		assertOneDiff(t, c.Diffs(), TargetBody, "6 行目", `"- 経歴"`, `"- 経歴 "`)

		c = NewComparer("筋書き")
		c.CompareResponse(step1, markdown(javaResume, "2026-11-09T10:00:00", ""), markdown(goResume, "2025-01-01T00:00:00", "\n"))
		assertOneDiff(t, c.Diffs(), TargetBody, "8 行目", absent, `""`)
	})
	t.Run("本文: JSON と文字のほかの本文はバイトで比べる", func(t *testing.T) {
		image := func(b string) Response {
			return Response{Status: 200, Header: http.Header{"Content-Type": {"image/png"}}, Body: []byte(b)}
		}
		c := NewComparer("筋書き")
		c.CompareResponse(step1, image("png"), image("png"))
		assertNoDiff(t, c.Diffs())
		c.CompareResponse(step1, image("png"), image("pnG"))
		if len(c.Diffs()) != 1 || !strings.HasPrefix(c.Diffs()[0].Java, "3 バイト sha256:") || c.Diffs()[0].Java == c.Diffs()[0].Go {
			t.Fatalf("違い = %+v", c.Diffs())
		}
	})
	t.Run("PDF は PDF の比べ方に任せる", func(t *testing.T) {
		pdf := Response{Status: 200, Header: http.Header{"Content-Type": {"application/pdf"}}, Body: []byte("%PDF")}
		c := NewComparer("筋書き")
		c.CompareResponse(step1, pdf, pdf)
		if len(c.Diffs()) != 1 || c.Diffs()[0].Target != TargetPDF {
			t.Fatalf("比べ方の無い PDF の違い = %+v", c.Diffs())
		}
		c = NewComparer("筋書き")
		c.PDF = func(_, _ []byte) (string, string, bool, error) { return "", "", true, nil }
		c.CompareResponse(step1, pdf, pdf)
		assertNoDiff(t, c.Diffs())
		c.PDF = func(_, _ []byte) (string, string, bool, error) { return "1ページ目", "2ページ目", false, nil }
		c.CompareResponse(step1, pdf, pdf)
		assertOneDiff(t, c.Diffs(), TargetPDF, "", "1ページ目", "2ページ目")
	})
}

// jwt は、署名を検めない比べのための JWT を作る。署名の部分は形だけである。
func jwt(t *testing.T, header, claims map[string]any) string {
	t.Helper()
	enc := func(v map[string]any) string {
		b, err := json.Marshal(v)
		if err != nil {
			t.Fatal(err)
		}
		return base64.RawURLEncoding.EncodeToString(b)
	}
	return enc(header) + "." + enc(claims) + ".c2lnbmF0dXJl"
}

func TestCompareJSON_TokenClaims(t *testing.T) {
	hs256 := map[string]any{"alg": "HS256", "typ": "JWT"}
	claims := func(sub string, iat, exp int64, jti string, extra map[string]any) map[string]any {
		c := map[string]any{"sub": sub, "iat": iat, "exp": exp, "jti": jti, "type": "access"}
		for k, v := range extra {
			c[k] = v
		}
		return c
	}
	body := func(id, token string) string { return `{"id":"` + id + `","token":"` + token + `"}` }

	t.Run("iat と exp と jti は比べず、exp から iat を引いた長さを比べる", func(t *testing.T) {
		java := jwt(t, hs256, claims(javaUser, 1000, 1900, "jti-java", nil))
		goToken := jwt(t, hs256, claims(goUser, 5000, 5900, "jti-go", nil))
		assertNoDiff(t, compareJSONBodies(body(javaUser, java), body(goUser, goToken)))
	})
	t.Run("有効な長さが違えば違いになる", func(t *testing.T) {
		java := jwt(t, hs256, claims(javaUser, 1000, 1900, "j", nil))
		goToken := jwt(t, hs256, claims(goUser, 1000, 2800, "g", nil))
		diffs := compareJSONBodies(body(javaUser, java), body(goUser, goToken))
		assertOneDiff(t, diffs, TargetBody, "$.token",
			`"<jwt:{\"exp-iat\":900,\"sub\":\"<uuid:1>\",\"type\":\"access\"}>"`,
			`"<jwt:{\"exp-iat\":1800,\"sub\":\"<uuid:1>\",\"type\":\"access\"}>"`)
	})
	t.Run("項目の値と項目の有無を比べる", func(t *testing.T) {
		java := jwt(t, hs256, claims(javaUser, 1000, 1900, "j", nil))
		goToken := jwt(t, hs256, claims(goUser, 1000, 1900, "g", map[string]any{"type": "refresh"}))
		if diffs := compareJSONBodies(body(javaUser, java), body(goUser, goToken)); len(diffs) != 1 || diffs[0].Path != "$.token" {
			t.Fatalf("違い = %+v", diffs)
		}
		goToken = jwt(t, hs256, claims(goUser, 1000, 1900, "g", map[string]any{"role": "admin"}))
		if diffs := compareJSONBodies(body(javaUser, java), body(goUser, goToken)); len(diffs) != 1 || !strings.Contains(diffs[0].Go, "role") {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("中身の UUID は本文と同じ番号で比べる", func(t *testing.T) {
		java := jwt(t, hs256, claims(javaUser, 1000, 1900, "j", nil))
		goToken := jwt(t, hs256, claims(goOther, 1000, 1900, "g", nil))
		diffs := compareJSONBodies(body(javaUser, java), body(goUser, goToken))
		if len(diffs) != 1 || !strings.Contains(diffs[0].Java, `<uuid:1>`) || !strings.Contains(diffs[0].Go, `<uuid:2>`) {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("頭に alg の無いものは JWT とみなさない", func(t *testing.T) {
		java := jwt(t, map[string]any{"typ": "x"}, claims(javaUser, 1000, 1900, "j", nil))
		goToken := jwt(t, map[string]any{"typ": "x"}, claims(javaUser, 1000, 1900, "g", nil))
		if diffs := compareJSONBodies(body(javaUser, java), body(goUser, goToken)); len(diffs) != 1 || strings.Contains(diffs[0].Java, "<jwt:") {
			t.Fatalf("違い = %+v", diffs)
		}
	})
}

func TestCompareHeaders_OnlySelected(t *testing.T) {
	base := func() http.Header {
		return http.Header{
			"Content-Type":        {"application/json"},
			"Content-Disposition": {`attachment; filename="resume.md"`},
			"Cache-Control":       {"no-cache, no-store"},
			"Set-Cookie": {
				"accessToken=abc; Path=/; Max-Age=900; Expires=Mon, 09 Nov 2026 10:00:00 GMT; HttpOnly; SameSite=Lax",
				"XSRF-TOKEN=xyz; Path=/",
			},
		}
	}
	compare := func(java, goHeader http.Header) []Diff {
		c := NewComparer("筋書き")
		c.CompareResponse(step1, Response{Status: 200, Header: java}, Response{Status: 200, Header: goHeader})
		return c.Diffs()
	}

	t.Run("ヘッダ: 決めたヘッダのほかは比べない", func(t *testing.T) {
		g := base()
		g.Set("Date", "Tue, 10 Nov 2026 00:00:00 GMT")
		g.Set("X-Request-Id", "other")
		g.Set("Vary", "Origin")
		assertNoDiff(t, compare(base(), g))
	})
	t.Run("ヘッダ: 決めたヘッダの値の違いを報告する", func(t *testing.T) {
		g := base()
		g.Set("Content-Type", "application/json;charset=UTF-8")
		assertOneDiff(t, compare(base(), g), TargetHeader, "Content-Type", "application/json", "application/json;charset=UTF-8")
		g = base()
		g.Del("Cache-Control")
		assertOneDiff(t, compare(base(), g), TargetHeader, "Cache-Control", "no-cache, no-store", absent)
		g = base()
		g.Set("Content-Disposition", `attachment; filename="resume.pdf"`)
		assertOneDiff(t, compare(base(), g), TargetHeader, "Content-Disposition", `attachment; filename="resume.md"`, `attachment; filename="resume.pdf"`)
	})
	t.Run("ヘッダ: Set-Cookie は名前と性質だけを比べる", func(t *testing.T) {
		g := base()
		g["Set-Cookie"] = []string{
			"XSRF-TOKEN=other; path=/",
			"accessToken=def; samesite=Lax; httponly; Max-Age=900; Path=/; Expires=Thu, 01 Jan 2026 00:00:00 GMT; Domain=localhost",
		}
		assertNoDiff(t, compare(base(), g))
	})
	t.Run("ヘッダ: Set-Cookie の性質の違いを報告する", func(t *testing.T) {
		g := base()
		g["Set-Cookie"] = []string{"accessToken=abc; Path=/; Max-Age=1800; HttpOnly; SameSite=Lax", "XSRF-TOKEN=xyz; Path=/"}
		assertOneDiff(t, compare(base(), g), TargetHeader, "Set-Cookie",
			"XSRF-TOKEN; Path=/\naccessToken; Path=/; Max-Age=900; HttpOnly; SameSite=Lax",
			"XSRF-TOKEN; Path=/\naccessToken; Path=/; Max-Age=1800; HttpOnly; SameSite=Lax")
		g["Set-Cookie"] = []string{"accessToken=abc; Path=/; Max-Age=900; SameSite=Lax; Secure", "XSRF-TOKEN=xyz; Path=/"}
		if diffs := compare(base(), g); len(diffs) != 1 || !strings.Contains(diffs[0].Go, "Secure") || strings.Contains(diffs[0].Go, "HttpOnly") {
			t.Fatalf("違い = %+v", diffs)
		}
		g["Set-Cookie"] = []string{"accessToken=abc; Path=/; Max-Age=900; HttpOnly; SameSite=Lax"}
		if diffs := compare(base(), g); len(diffs) != 1 || diffs[0].Path != "Set-Cookie" {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("ヘッダ: Location の URL の中のトークンと UUID は置き換えて比べる", func(t *testing.T) {
		location := func(word, id string) http.Header {
			h := http.Header{}
			h.Set("Location", "http://fakeoidc:8080/o/oauth2/v2/auth?client_id=test-google-client&state="+word+"&resume="+id)
			return h
		}
		assertNoDiff(t, compare(location(javaURLWord, javaResume), location(goURLWord, goResume)))
		g := location(goURLWord, goResume)
		g.Set("Location", strings.Replace(g.Get("Location"), "test-google-client", "test-github-client", 1))
		diffs := compare(location(javaURLWord, javaResume), g)
		if len(diffs) != 1 || diffs[0].Path != "Location" || !strings.Contains(diffs[0].Java, "state=<token:1>") || !strings.Contains(diffs[0].Go, "test-github-client") {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("ヘッダ: Location のトークンでない値と問い合わせの名前は置き換えない", func(t *testing.T) {
		location := func(u string) http.Header {
			h := http.Header{}
			h.Set("Location", u)
			return h
		}
		// 画面が読む値は、16文字以上で _ を含んでも、トークンとみなさない。
		diffs := compare(location("http://localhost:5173/login?error=unverified_email"), location("http://localhost:5173/login?error=email_unverified"))
		if len(diffs) != 1 || diffs[0].Path != "Location" || !strings.Contains(diffs[0].Java, "error=unverified_email") || !strings.Contains(diffs[0].Go, "error=email_unverified") {
			t.Fatalf("違い = %+v", diffs)
		}
		// 問い合わせの名前は、43文字でも置き換えない。
		authorize := func(name, challenge string) http.Header {
			return location("http://fakeoidc:8080/o/oauth2/v2/auth?" + name + "=S256&code_challenge=" + challenge)
		}
		assertNoDiff(t, compare(authorize("code_challenge_method", javaURLWord), authorize("code_challenge_method", goURLWord)))
		diffs = compare(authorize(otherWord, javaURLWord), authorize(goURLWord, goURLWord))
		if len(diffs) != 1 || !strings.Contains(diffs[0].Java, otherWord+"=S256&code_challenge=<token:1>") || !strings.Contains(diffs[0].Go, goURLWord+"=S256&code_challenge=<token:1>") {
			t.Fatalf("違い = %+v", diffs)
		}
		// 43文字でない語は、乱数らしい語でもトークンとみなさない。
		diffs = compare(location("http://localhost:5173/a/Abc123_defGhi456"), location("http://localhost:5173/a/Xyz789_uvwRst012"))
		if len(diffs) != 1 || !strings.Contains(diffs[0].Java, "Abc123_defGhi456") {
			t.Fatalf("違い = %+v", diffs)
		}
		// # のあとの値も、問い合わせと同じく置き換える。
		assertNoDiff(t, compare(location("http://localhost:5173/cb#state="+javaURLWord+"&x"), location("http://localhost:5173/cb#state="+goURLWord+"&x")))
	})
}

func TestCompareDB_SortsAfterNormalize(t *testing.T) {
	const at1, at2 = "2026-11-09T10:00:00.123456", "2025-01-01T00:00:00.5"
	user := func(id, at string) map[string]any {
		return map[string]any{"id": id, "email": "taro@example.com", "created_at": at}
	}
	resume := func(id, owner, name string) map[string]any {
		return map[string]any{"id": id, "user_id": owner, "name": name}
	}

	t.Run("データベース: 並びと UUID と日時の違いは違いにしない", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.CompareDB(step1,
			DBSnapshot{"users": {user(javaUser, at1)}, "resumes": {resume(javaResume, javaUser, "a"), resume(javaOther, javaUser, "b")}},
			DBSnapshot{"users": {user(goUser, at2)}, "resumes": {resume(goOther, goUser, "b"), resume(goResume, goUser, "a")}})
		assertNoDiff(t, c.Diffs())
	})
	t.Run("データベース: 応答に現れた UUID は応答と同じ番号になる", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.CompareResponse(step1, jsonResponse(200, `{"id":"`+javaResume+`"}`), jsonResponse(200, `{"id":"`+goResume+`"}`))
		// Go 版は、応答で返した経歴書と別の経歴書に名前 a を付けた。
		c.CompareDB(step1,
			DBSnapshot{"resumes": {resume(javaResume, javaUser, "a"), resume(javaOther, javaUser, "b")}},
			DBSnapshot{"resumes": {resume(goResume, goUser, "b"), resume(goOther, goUser, "a")}})
		diffs := c.Diffs()
		if len(diffs) != 1 || diffs[0].Target != TargetDB || diffs[0].Path != "resumes" {
			t.Fatalf("違い = %+v", diffs)
		}
		if !strings.Contains(diffs[0].Java, `"id":"<uuid:1>","name":"a"`) || !strings.Contains(diffs[0].Go, `"id":"<uuid:1>","name":"b"`) {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("データベース: 応答に現れない UUID はほかの列の順に番号を付ける", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.CompareDB(step1,
			DBSnapshot{"resumes": {resume(javaResume, javaUser, "a"), resume(javaOther, javaUser, "b")}, "users": {user(javaUser, at1)}},
			DBSnapshot{"resumes": {resume(goOther, goUser, "b"), resume(goResume, goUser, "a")}, "users": {user(goUser, at2)}})
		assertNoDiff(t, c.Diffs())
		// 表の外の UUID を指す行は、指す先の番号が違うので違いになる。
		c.CompareDB(step1,
			DBSnapshot{"links": {{"resume_id": javaResume}}},
			DBSnapshot{"links": {{"resume_id": goOther}}})
		if diffs := c.Diffs(); len(diffs) != 1 || diffs[0].Path != "links" {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("データベース: パスワードのハッシュは版と強さだけを比べる", func(t *testing.T) {
		hash := func(cost, salt string) map[string]any {
			return map[string]any{"password": "$2a$" + cost + "$" + strings.Repeat(salt, 53)}
		}
		c := NewComparer("筋書き")
		c.CompareDB(step1, DBSnapshot{"users": {hash("10", "a")}}, DBSnapshot{"users": {hash("10", "b")}})
		assertNoDiff(t, c.Diffs())
		c.CompareDB(step1, DBSnapshot{"users": {hash("10", "a")}}, DBSnapshot{"users": {hash("12", "a")}})
		if diffs := c.Diffs(); len(diffs) != 1 || !strings.Contains(diffs[0].Java, "<bcrypt:$2a$10$>") || !strings.Contains(diffs[0].Go, "<bcrypt:$2a$12$>") {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("データベース: 片方にしか無い行と表を報告する", func(t *testing.T) {
		c := NewComparer("筋書き")
		c.CompareDB(step1,
			DBSnapshot{"users": {user(javaUser, at1)}, "only_java": {}},
			DBSnapshot{"users": {user(goUser, at2), user(goOther, at2)}, "resumes": {}})
		diffs := c.Diffs()
		if len(diffs) != 3 {
			t.Fatalf("違い = %+v", diffs)
		}
		if diffs[0].Path != "only_java" || diffs[0].Java != "表がある" || diffs[0].Go != "表が無い" {
			t.Errorf("違い[0] = %+v", diffs[0])
		}
		if diffs[1].Path != "resumes" || diffs[1].Java != "表が無い" {
			t.Errorf("違い[1] = %+v", diffs[1])
		}
		if diffs[2].Path != "users" || diffs[2].Java != absent || !strings.Contains(diffs[2].Go, "<uuid:2>") {
			t.Errorf("違い[2] = %+v", diffs[2])
		}
	})
	t.Run("S3: キーの形と中身のバイトを比べる", func(t *testing.T) {
		object := func(id, body string) fakeaws.Object {
			return fakeaws.Object{Bucket: "keirekipro", Key: "profile-images/" + id + ".png", ContentType: "image/png", Body: []byte(body)}
		}
		c := NewComparer("筋書き")
		c.CompareS3(step1, []fakeaws.Object{object(javaUser, "x"), object(javaOther, "y")}, []fakeaws.Object{object(goOther, "y"), object(goUser, "x")})
		assertNoDiff(t, c.Diffs())

		c.CompareS3(step1, []fakeaws.Object{object(javaUser, "x")}, []fakeaws.Object{object(goUser, "z")})
		if diffs := c.Diffs(); len(diffs) != 1 || diffs[0].Target != TargetS3 || diffs[0].Path != "keirekipro/profile-images/<uuid:1>.png" || diffs[0].Java == diffs[0].Go {
			t.Fatalf("違い = %+v", diffs)
		}

		c = NewComparer("筋書き")
		jo := object(javaUser, "x")
		goObj := object(goUser, "x")
		goObj.Key = "profile-image/" + goUser + ".png"
		c.CompareS3(step1, []fakeaws.Object{jo}, []fakeaws.Object{goObj})
		if diffs := c.Diffs(); len(diffs) != 2 || diffs[0].Java != absent || diffs[1].Go != absent {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("S3: キーは UUID のほかを置き換えない", func(t *testing.T) {
		object := func(key string) fakeaws.Object {
			return fakeaws.Object{Bucket: "keirekipro", Key: key, Body: []byte("x")}
		}
		c := NewComparer("筋書き")
		c.CompareS3(step1, []fakeaws.Object{object("exports/" + javaURLWord)}, []fakeaws.Object{object("exports/" + goURLWord)})
		if diffs := c.Diffs(); len(diffs) != 2 || diffs[0].Path != "keirekipro/exports/"+javaURLWord || diffs[1].Path != "keirekipro/exports/"+goURLWord {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("S3: 正規化したキーが重なっても、記録を捨てない", func(t *testing.T) {
		object := fakeaws.Object{Bucket: "keirekipro", Key: "a", Body: []byte("x")}
		c := NewComparer("筋書き")
		c.CompareS3(step1, []fakeaws.Object{object, object}, []fakeaws.Object{object})
		if diffs := c.Diffs(); len(diffs) != 1 || diffs[0].Path != "keirekipro/a (同じ形の 2 個目)" || diffs[0].Go != absent {
			t.Fatalf("違い = %+v", diffs)
		}
	})
}

func TestCompareRedis_TTLTolerance5s(t *testing.T) {
	entry := func(key, value string, ttl time.Duration) RedisEntry {
		return RedisEntry{Key: key, Type: "string", Value: value, TTL: ttl}
	}
	compare := func(java, goEntries []RedisEntry) []Diff {
		c := NewComparer("筋書き")
		c.CompareRedis(step1, java, goEntries)
		return c.Diffs()
	}

	t.Run("有効な時間は5秒のずれまで許す", func(t *testing.T) {
		assertNoDiff(t, compare([]RedisEntry{entry("k", "v", 900*time.Second)}, []RedisEntry{entry("k", "v", 895*time.Second)}))
		assertNoDiff(t, compare([]RedisEntry{entry("k", "v", 900*time.Second)}, []RedisEntry{entry("k", "v", 905*time.Second)}))
		assertOneDiff(t, compare([]RedisEntry{entry("k", "v", 900*time.Second)}, []RedisEntry{entry("k", "v", 894*time.Second)}),
			TargetRedis, "k", "string v (残り 15m0s)", "string v (残り 14m54s)")
	})
	t.Run("有効な時間の有無は同じでなければならない", func(t *testing.T) {
		assertNoDiff(t, compare([]RedisEntry{entry("k", "v", -1)}, []RedisEntry{entry("k", "v", -1)}))
		assertOneDiff(t, compare([]RedisEntry{entry("k", "v", -1)}, []RedisEntry{entry("k", "v", 3*time.Second)}),
			TargetRedis, "k", "string v (有効な時間なし)", "string v (残り 3s)")
	})
	t.Run("キーと値のトークンと UUID は置き換えて比べる", func(t *testing.T) {
		java := []RedisEntry{entry("password-reset:"+javaURLWord, javaUser, time.Hour), entry("refresh:"+otherWord, javaUser, time.Hour)}
		goEntries := []RedisEntry{entry("refresh:"+goURLWord, goUser, time.Hour), entry("password-reset:"+otherWord, goUser, time.Hour)}
		assertNoDiff(t, compare(java, goEntries))
	})
	t.Run("JSON の文字列を JSON の配列にした集合の値のトークンも置き換えて比べる", func(t *testing.T) {
		// 集合 user-refresh-tokens:<利用者の ID> の値は、DumpRedis が、JSON の文字列の要素を JSON の配列にしたものである
		set := func(key, token string) RedisEntry {
			return RedisEntry{Key: key, Type: "set", Value: canonicalJSON([]string{`"` + token + `"`}), TTL: time.Hour}
		}
		java := []RedisEntry{set("user-refresh-tokens:"+javaUser, javaURLWord)}
		goEntries := []RedisEntry{set("user-refresh-tokens:"+goUser, goURLWord)}
		assertNoDiff(t, compare(java, goEntries))
	})
	t.Run("集合の要素は、トークンを番号に置き換えたあとの順で比べる", func(t *testing.T) {
		// 集合の要素は、DumpRedis が置き換える前の値の順に並べる。トークンの番号は現れた順に付くので、
		// 置き換えたあとの順は版ごとに違いうる。ここでは、Java 版は2つ目の要素が、Go 版は1つ目の要素が、先の段で番号 1 を受ける
		javaFirst, goSecond := "P"+javaURLWord[1:], "S"+goURLWord[1:]
		set := func(key string, tokens ...string) RedisEntry {
			members := make([]string, len(tokens))
			for i, tok := range tokens {
				members[i] = `"` + tok + `"`
			}
			return RedisEntry{Key: key, Type: "set", Value: canonicalJSON(members), TTL: time.Hour}
		}
		c := NewComparer("筋書き")
		c.CompareRedis(step1, []RedisEntry{entry("seen", javaURLWord, -1)}, []RedisEntry{entry("seen", goURLWord, -1)})
		c.CompareRedis(step1,
			[]RedisEntry{set("user-refresh-tokens:"+javaUser, javaFirst, javaURLWord)},
			[]RedisEntry{set("user-refresh-tokens:"+goUser, goURLWord, goSecond)})
		assertNoDiff(t, c.Diffs())
	})
	t.Run("正規化したキーが重なっても、記録を捨てない", func(t *testing.T) {
		java := []RedisEntry{entry("a:2026-11-09T10:00:00", "1", -1), entry("a:2026-11-10T10:00:00", "1", -1)}
		diffs := compare(java, []RedisEntry{entry("a:2026-11-09T10:00:00", "1", -1)})
		if len(diffs) != 1 || !strings.HasSuffix(diffs[0].Path, " (同じ形の 2 個目)") || diffs[0].Go != absent {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("キーと型と値の違いを報告する", func(t *testing.T) {
		assertOneDiff(t, compare([]RedisEntry{entry("k", "v", -1)}, []RedisEntry{entry("k", "w", -1)}), TargetRedis, "k", "string v (有効な時間なし)", "string w (有効な時間なし)")
		set := RedisEntry{Key: "k", Type: "set", Value: `["v"]`, TTL: -1}
		assertOneDiff(t, compare([]RedisEntry{entry("k", `["v"]`, -1)}, []RedisEntry{set}), TargetRedis, "k", `string ["v"] (有効な時間なし)`, `set ["v"] (有効な時間なし)`)
		assertOneDiff(t, compare([]RedisEntry{entry("a", "v", -1)}, nil), TargetRedis, "a", "string v (有効な時間なし)", absent)
		assertOneDiff(t, compare(nil, []RedisEntry{entry("b", "v", -1)}), TargetRedis, "b", absent, "string v (有効な時間なし)")
	})
}

func TestCompareMail_TokenInURL(t *testing.T) {
	mail := func(word, subject string) fakeaws.Email {
		link := "http://localhost:5173/password/reset/" + word
		return fakeaws.Email{
			Source: "info@keirekipro.click", To: []string{"taro@example.com"}, Subject: subject,
			Text: "次の URL から再設定してください。\n" + link + "\n",
			HTML: `<a href="` + link + `?a=1&amp;t=` + word + `">再設定</a>`,
		}
	}
	compare := func(c *Comparer, java, goMails []fakeaws.Email) []Diff {
		c.CompareMail(step1, java, goMails)
		return c.Diffs()
	}

	t.Run("メール: URL の中のトークンは置き換えて比べる", func(t *testing.T) {
		assertNoDiff(t, compare(NewComparer("筋書き"), []fakeaws.Email{mail(javaURLWord, "再設定")}, []fakeaws.Email{mail(goURLWord, "再設定")}))
	})
	t.Run("メール: URL の中の JWT は中身で比べる", func(t *testing.T) {
		hs256 := map[string]any{"alg": "HS256"}
		jm := mail("", "確認")
		jm.Text = "http://localhost:5173/verify?token=" + jwt(t, hs256, map[string]any{"sub": javaUser, "iat": 1, "exp": 86401, "jti": "a"})
		gm := mail("", "確認")
		gm.Text = "http://localhost:5173/verify?token=" + jwt(t, hs256, map[string]any{"sub": goUser, "iat": 9, "exp": 86409, "jti": "b"})
		assertNoDiff(t, compare(NewComparer("筋書き"), []fakeaws.Email{jm}, []fakeaws.Email{gm}))
		gm.Text = "http://localhost:5173/verify?token=" + jwt(t, hs256, map[string]any{"sub": goUser, "iat": 9, "exp": 99, "jti": "b"})
		if diffs := compare(NewComparer("筋書き"), []fakeaws.Email{jm}, []fakeaws.Email{gm}); len(diffs) != 1 || diffs[0].Path != "1 通目の本文" {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("メール: Redis のキーのトークンはメールと同じ番号になる", func(t *testing.T) {
		c := NewComparer("筋書き")
		compare(c, []fakeaws.Email{mail(javaURLWord, "再設定")}, []fakeaws.Email{mail(goURLWord, "再設定")})
		// Go 版は、メールで送ったトークンと別のトークンを Redis に書いた。
		c.CompareRedis(step1,
			[]RedisEntry{{Key: "password-reset:" + javaURLWord, Type: "string", Value: "1", TTL: -1}},
			[]RedisEntry{{Key: "password-reset:" + otherWord, Type: "string", Value: "1", TTL: -1}})
		diffs := c.Diffs()
		if len(diffs) != 2 || diffs[0].Path != "password-reset:<token:1>" || diffs[1].Path != "password-reset:<token:2>" {
			t.Fatalf("違い = %+v", diffs)
		}
	})
	t.Run("メール: 送り元と宛先と件名と本文の違いを報告する", func(t *testing.T) {
		assertOneDiff(t, compare(NewComparer("筋書き"), []fakeaws.Email{mail(javaURLWord, "再設定")}, []fakeaws.Email{mail(goURLWord, "再設定のご案内")}),
			TargetMail, "1 通目の件名", "再設定", "再設定のご案内")
		gm := mail(goURLWord, "再設定")
		gm.To = []string{"jiro@example.com"}
		gm.Source = "no-reply@keirekipro.click"
		gm.Text = strings.Replace(gm.Text, "次の", "下の", 1)
		diffs := compare(NewComparer("筋書き"), []fakeaws.Email{mail(javaURLWord, "再設定")}, []fakeaws.Email{gm})
		if len(diffs) != 3 || diffs[0].Path != "1 通目の送り元" || diffs[1].Path != "1 通目の宛先" || diffs[2].Path != "1 通目の本文" {
			t.Fatalf("違い = %+v", diffs)
		}
		gm = mail(goURLWord, "再設定")
		gm.HTML = strings.Replace(gm.HTML, "?a=1", "?a=2", 1)
		assertOneDiff(t, compare(NewComparer("筋書き"), []fakeaws.Email{mail(javaURLWord, "再設定")}, []fakeaws.Email{gm}),
			TargetMail, "1 通目のHTML の本文",
			`<a href="http://localhost:5173/password/reset/<token:1>?a=1&amp;t=<token:1>">再設定</a>`,
			`<a href="http://localhost:5173/password/reset/<token:1>?a=2&amp;t=<token:1>">再設定</a>`)
	})
	t.Run("メール: 片方にしか無いメールを報告する", func(t *testing.T) {
		diffs := compare(NewComparer("筋書き"), []fakeaws.Email{mail(javaURLWord, "再設定")}, []fakeaws.Email{mail(goURLWord, "再設定"), mail(otherWord, "二通目")})
		if len(diffs) != 1 || diffs[0].Path != "2 通目" || diffs[0].Java != absent || !strings.Contains(diffs[0].Go, "件名: 二通目") {
			t.Fatalf("違い = %+v", diffs)
		}
		diffs = compare(NewComparer("筋書き"), []fakeaws.Email{mail(javaURLWord, "再設定")}, nil)
		if len(diffs) != 1 || diffs[0].Go != absent {
			t.Fatalf("違い = %+v", diffs)
		}
	})
}

func TestCompareObjects_ContentTypeAndMetadata(t *testing.T) {
	png := []byte("\x89PNG\r\n\x1a\nimage")
	object := func(user, contentType string, metadata map[string]string, body []byte) fakeaws.Object {
		return fakeaws.Object{Bucket: "keirekipro-storage", Key: user + "/a.png", ContentType: contentType, Metadata: metadata, Body: body}
	}
	meta := func(contentType string) map[string]string { return map[string]string{"content-type": contentType} }
	compare := func(java, goObject []fakeaws.Object) []Diff {
		c := NewComparer("筋書き")
		c.CompareS3(step1, java, goObject)
		return c.Diffs()
	}
	const key = "keirekipro-storage/<uuid:1>/a.png"
	pngText := describeBytes(png)

	t.Run("置き場所の名前とバイトの並びと Content-Type とメタデータが同じなら、違いは無い", func(t *testing.T) {
		assertNoDiff(t, compare(
			[]fakeaws.Object{object(javaUser, "image/png", meta("image/png"), png)},
			[]fakeaws.Object{object(goUser, "image/png", meta("image/png"), png)}))
	})
	t.Run("メタデータが無いことと、空のメタデータは同じとみなす", func(t *testing.T) {
		assertNoDiff(t, compare(
			[]fakeaws.Object{object(javaUser, "image/png", nil, png)},
			[]fakeaws.Object{object(goUser, "image/png", map[string]string{}, png)}))
	})

	cases := []struct {
		name        string
		java, goVer []fakeaws.Object
		wantJava    string
		wantGo      string
	}{
		{
			name:     "Content-Type だけが違う",
			java:     []fakeaws.Object{object(javaUser, "image/png", meta("image/png"), png)},
			goVer:    []fakeaws.Object{object(goUser, "image/png;charset=UTF-8", meta("image/png"), png)},
			wantJava: pngText + ` Content-Type "image/png" メタデータ {"content-type":"image/png"}`,
			wantGo:   pngText + ` Content-Type "image/png;charset=UTF-8" メタデータ {"content-type":"image/png"}`,
		},
		{
			name:     "メタデータの値だけが違う",
			java:     []fakeaws.Object{object(javaUser, "image/png", meta("image/png"), png)},
			goVer:    []fakeaws.Object{object(goUser, "image/png", meta("image/jpeg"), png)},
			wantJava: pngText + ` Content-Type "image/png" メタデータ {"content-type":"image/png"}`,
			wantGo:   pngText + ` Content-Type "image/png" メタデータ {"content-type":"image/jpeg"}`,
		},
		{
			name:     "メタデータの項目が片方の版にだけある",
			java:     []fakeaws.Object{object(javaUser, "image/png", nil, png)},
			goVer:    []fakeaws.Object{object(goUser, "image/png", meta("image/png"), png)},
			wantJava: pngText + ` Content-Type "image/png" メタデータ {}`,
			wantGo:   pngText + ` Content-Type "image/png" メタデータ {"content-type":"image/png"}`,
		},
		{
			name:     "バイトの並びだけが違う",
			java:     []fakeaws.Object{object(javaUser, "image/png", meta("image/png"), png)},
			goVer:    []fakeaws.Object{object(goUser, "image/png", meta("image/png"), []byte("GIF89a"))},
			wantJava: pngText + ` Content-Type "image/png" メタデータ {"content-type":"image/png"}`,
			wantGo:   describeBytes([]byte("GIF89a")) + ` Content-Type "image/png" メタデータ {"content-type":"image/png"}`,
		},
		{
			name:     "画像が Go 版にだけある",
			java:     nil,
			goVer:    []fakeaws.Object{object(goUser, "", meta("image/png"), png)},
			wantJava: absent,
			wantGo:   pngText + ` Content-Type "" メタデータ {"content-type":"image/png"}`,
		},
		{
			name:     "画像が Java 版にだけある",
			java:     []fakeaws.Object{object(javaUser, "image/gif", nil, png)},
			goVer:    nil,
			wantJava: pngText + ` Content-Type "image/gif" メタデータ {}`,
			wantGo:   absent,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			diffs := compare(tc.java, tc.goVer)
			if len(diffs) != 1 {
				t.Fatalf("違い = %+v, want 1 つ", diffs)
			}
			d := diffs[0]
			if d.Target != TargetS3 || d.Path != key || d.Java != tc.wantJava || d.Go != tc.wantGo {
				t.Errorf("違い = %s %s\nJava %s\nGo   %s\nwant %s %s\nJava %s\nGo   %s", d.Target, d.Path, d.Java, d.Go, TargetS3, key, tc.wantJava, tc.wantGo)
			}
		})
	}
}
