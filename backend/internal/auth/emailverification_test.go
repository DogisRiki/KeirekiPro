package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"hash"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
)

// javaDevSigningKey は、Java 版の開発環境の jwt.secret(docker/localstack/init-localstack.sh の keirekipro/jwt)である。
// testdata/mail/email-verification.values.json の確認のリンクは、Java 版がこの鍵から導いた鍵で署名した。
const javaDevSigningKey = "vh8JBWqYFC2mJwZ4XD9pE7TKq3mN5RxS2HnUcL7VfAy"

// Java 版が送った確認のリンクの値の項目である。javaSampleIssuedAt は、Java 版がリンクを作った時刻の秒で、
// lexp は、この時刻に24時間を足した値である。
const (
	javaSampleJTI      = "b04d5b57-8d0c-4bb2-8a22-9379b7f3d1c0"
	javaSampleSubject  = "0a0d6b7d-385d-45a0-bdb3-ede0e6f3ea5d"
	javaSampleEmail    = "mailgen-1794378333@example.com"
	javaSampleIssuedAt = 1794378333
)

// javaSampleToken は、Java 版が送った確認のリンクの # のあとの値を返す。
func javaSampleToken(t *testing.T) string {
	t.Helper()
	var values map[string]string
	readMailJSON(t, "email-verification.values.json", &values)
	_, token, ok := strings.Cut(values["verificationLink"], "/email/verify#")
	if !ok {
		t.Fatalf("確認のリンク %q に値が無い", values["verificationLink"])
	}
	return token
}

// newEmailVerificationTokenService は、Java 版の開発環境と同じ鍵を使い、今の時刻を now に決めた Service を作る。
func newEmailVerificationTokenService(now time.Time) *Service {
	return New(Deps{
		JWT: config.JWT{Secret: javaDevSigningKey},
		Now: func() time.Time { return now },
	})
}

// rawJWT は、ヘッダと本体の JSON を、sign で署名した値にする。sign が nil なら署名を空にする。
func rawJWT(header, payload string, sign func(string) []byte) string {
	enc := base64.RawURLEncoding
	signing := enc.EncodeToString([]byte(header)) + "." + enc.EncodeToString([]byte(payload))
	if sign == nil {
		return signing + "."
	}
	return signing + "." + enc.EncodeToString(sign(signing))
}

// hmacSigner は、key を鍵にした HMAC で署名する関数を返す。
func hmacSigner(newHash func() hash.Hash, key []byte) func(string) []byte {
	return func(signing string) []byte {
		mac := hmac.New(newHash, key)
		mac.Write([]byte(signing))
		return mac.Sum(nil)
	}
}

// devKeySigner は、Java 版の開発環境の鍵から導いた鍵で、HS256 で署名する関数である。
var devKeySigner = hmacSigner(sha256.New, emailVerificationKey(javaDevSigningKey))

// testJWTHeader は、HS256 の JWT のヘッダの JSON である。
const testJWTHeader = `{"alg":"HS256","typ":"JWT"}`

// decodeJWTSegment は、JWT の i 番目の部分を base64url で戻し、JSON として読む。
func decodeJWTSegment(t *testing.T, token string, i int) map[string]any {
	t.Helper()
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("値 %q が3つの部分に分かれない", token)
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[i])
	if err != nil {
		t.Fatalf("%d 番目の部分を戻せない: %v", i, err)
	}
	var v map[string]any
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("%d 番目の部分を JSON として読めない: %v", i, err)
	}
	return v
}

// TestEmailVerificationToken_Issue は、リンクの値が、HS256 のヘッダと、aud、jti、sub、purpose、email、lexp の
// 6つの項目を持ち、Go 版が作った値と Java 版が送った値のどちらを読んでも同じ項目になることを確かめる。
// ECS の入れ替えの途中で、一方の版が送ったリンクを他方の版が読めるようにするためである。
// lexp は、時刻の秒の端数を切り捨てて書く。
func TestEmailVerificationToken_Issue(t *testing.T) {
	issuedAt := time.Unix(javaSampleIssuedAt, 900_000_000)
	svc := newEmailVerificationTokenService(issuedAt)
	want := emailVerificationClaims{
		JTI:           javaSampleJTI,
		SubjectID:     uuid.MustParse(javaSampleSubject),
		Purpose:       purposeRegistration,
		Email:         javaSampleEmail,
		LinkExpiresAt: time.Unix(javaSampleIssuedAt+24*3600, 0),
	}
	issueInput := want
	issueInput.LinkExpiresAt = issuedAt.Add(24 * time.Hour)
	got, err := svc.issueEmailVerificationToken(issueInput)
	if err != nil {
		t.Fatalf("issueEmailVerificationToken: %v", err)
	}
	wantHeader := map[string]any{"alg": "HS256", "typ": "JWT"}
	if header := decodeJWTSegment(t, got, 0); !reflect.DeepEqual(header, wantHeader) {
		t.Errorf("ヘッダ = %v, want %v", header, wantHeader)
	}
	wantPayload := map[string]any{
		"aud":     "keirekipro-email-verification",
		"jti":     javaSampleJTI,
		"sub":     javaSampleSubject,
		"purpose": "REGISTRATION",
		"email":   javaSampleEmail,
		"lexp":    float64(javaSampleIssuedAt + 24*3600),
	}
	if payload := decodeJWTSegment(t, got, 1); !reflect.DeepEqual(payload, wantPayload) {
		t.Errorf("本体 = %v, want %v", payload, wantPayload)
	}

	for name, token := range map[string]string{"Go 版が作った値": got, "Java 版が送った値": javaSampleToken(t)} {
		claims, ok := svc.readEmailVerificationToken(token)
		if !ok || !sameEmailVerificationClaims(claims, want) {
			t.Errorf("%sを読んだ項目 = %+v, %v, want %+v", name, claims, ok, want)
		}
	}
}

// sameEmailVerificationClaims は、2つの項目が同じかを返す。時刻は Equal で比べる。
func sameEmailVerificationClaims(a, b emailVerificationClaims) bool {
	return a.JTI == b.JTI && a.SubjectID == b.SubjectID && a.Purpose == b.Purpose && a.Email == b.Email &&
		a.LinkExpiresAt.Equal(b.LinkExpiresAt)
}

// samplePayload は、Java 版の値と同じ項目の本体の JSON に、extra の項目を足し、drop の項目を除いたものを作る。
// extra の値は JSON の書き方のまま書く。同じ名前の項目が extra にあれば、元の項目を extra の値に置き換える。
func samplePayload(drop string, extra ...string) string {
	fields := []string{
		`"aud":"keirekipro-email-verification"`,
		`"jti":"` + javaSampleJTI + `"`,
		`"sub":"` + javaSampleSubject + `"`,
		`"purpose":"REGISTRATION"`,
		`"email":"` + javaSampleEmail + `"`,
		`"lexp":1794464733`,
	}
	var out []string
	for _, f := range fields {
		name, _, _ := strings.Cut(f, ":")
		if name == `"`+drop+`"` {
			continue
		}
		replaced := false
		for _, e := range extra {
			if en, _, _ := strings.Cut(e, ":"); en == name {
				replaced = true
			}
		}
		if !replaced {
			out = append(out, f)
		}
	}
	out = append(out, extra...)
	return "{" + strings.Join(out, ",") + "}"
}

// TestEmailVerificationToken_ReadRejects は、署名か項目が合わない値を読まないことを確かめる。
func TestEmailVerificationToken_ReadRejects(t *testing.T) {
	now := time.Unix(javaSampleIssuedAt+60, 0)
	svc := newEmailVerificationTokenService(now)
	header := testJWTHeader
	sample := javaSampleToken(t)
	parts := strings.Split(sample, ".")
	cases := []struct {
		name  string
		token string
	}{
		{"空の文字列", ""},
		{"区切りの無い文字列", "abc"},
		{"署名の末尾に = がある", sample + "="},
		{"本体を書き換えた値", parts[0] + "." + base64.RawURLEncoding.EncodeToString([]byte(samplePayload("", `"email":"other@example.com"`))) + "." + parts[2]},
		{"鍵を導かずに設定の鍵で署名した値", rawJWT(header, samplePayload(""), hmacSigner(sha256.New, []byte(javaDevSigningKey)))},
		{"ほかの鍵から導いた鍵で署名した値", rawJWT(header, samplePayload(""), hmacSigner(sha256.New, emailVerificationKey(testSigningKey)))},
		{"署名の方式が none", rawJWT(`{"alg":"none","typ":"JWT"}`, samplePayload(""), nil)},
		{"署名の方式が HS512", rawJWT(`{"alg":"HS512","typ":"JWT"}`, samplePayload(""), hmacSigner(sha512.New, emailVerificationKey(javaDevSigningKey)))},
		{"aud が違う", rawJWT(header, samplePayload("", `"aud":"keirekipro-other"`), devKeySigner)},
		{"aud が無い", rawJWT(header, samplePayload("aud"), devKeySigner)},
		{"jti が無い", rawJWT(header, samplePayload("jti"), devKeySigner)},
		{"jti が null", rawJWT(header, samplePayload("", `"jti":null`), devKeySigner)},
		{"sub が無い", rawJWT(header, samplePayload("sub"), devKeySigner)},
		{"sub が null", rawJWT(header, samplePayload("", `"sub":null`), devKeySigner)},
		{"sub が UUID でない", rawJWT(header, samplePayload("", `"sub":"not-a-uuid"`), devKeySigner)},
		{"purpose が無い", rawJWT(header, samplePayload("purpose"), devKeySigner)},
		{"purpose が知らない目的", rawJWT(header, samplePayload("", `"purpose":"UNKNOWN"`), devKeySigner)},
		{"purpose が小文字", rawJWT(header, samplePayload("", `"purpose":"registration"`), devKeySigner)},
		{"purpose が数", rawJWT(header, samplePayload("", `"purpose":1`), devKeySigner)},
		{"email が無い", rawJWT(header, samplePayload("email"), devKeySigner)},
		{"email が null", rawJWT(header, samplePayload("", `"email":null`), devKeySigner)},
		{"lexp が無い", rawJWT(header, samplePayload("lexp"), devKeySigner)},
		{"lexp が null", rawJWT(header, samplePayload("", `"lexp":null`), devKeySigner)},
		{"lexp が文字列", rawJWT(header, samplePayload("", `"lexp":"1794464733"`), devKeySigner)},
		{"exp が過ぎた", rawJWT(header, samplePayload("", `"exp":1794378000`), devKeySigner)},
		{"nbf がまだ来ない", rawJWT(header, samplePayload("", `"nbf":1794390000`), devKeySigner)},
		{"iat がまだ来ない", rawJWT(header, samplePayload("", `"iat":1794390000`), devKeySigner)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if claims, ok := svc.readEmailVerificationToken(tc.token); ok {
				t.Errorf("readEmailVerificationToken = %+v, true, want 読まない", claims)
			}
		})
	}
}

// TestEmailVerificationToken_ReadAccepts は、Go 版が作らない形でも、署名と項目が合う値を読むことを確かめる。
func TestEmailVerificationToken_ReadAccepts(t *testing.T) {
	now := time.Unix(javaSampleIssuedAt+60, 0)
	svc := newEmailVerificationTokenService(now)
	header := testJWTHeader
	want := emailVerificationClaims{
		JTI:           javaSampleJTI,
		SubjectID:     uuid.MustParse(javaSampleSubject),
		Purpose:       purposeRegistration,
		Email:         javaSampleEmail,
		LinkExpiresAt: time.Unix(javaSampleIssuedAt+24*3600, 0),
	}
	emptyJTI := want
	emptyJTI.JTI = ""
	cases := []struct {
		name  string
		token string
		want  emailVerificationClaims
	}{
		{"aud が並びで、ほかの値も含む", rawJWT(header, samplePayload("", `"aud":["other","keirekipro-email-verification"]`), devKeySigner), want},
		{"jti が空の文字列", rawJWT(header, samplePayload("", `"jti":""`), devKeySigner), emptyJTI},
		{"exp と nbf と iat が今の時刻と合う", rawJWT(header, samplePayload("", `"exp":1794390000`, `"nbf":1794378000`, `"iat":1794378000`), devKeySigner), want},
		{"知らない項目がある", rawJWT(header, samplePayload("", `"x":{"y":[1,2]}`), devKeySigner), want},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			claims, ok := svc.readEmailVerificationToken(tc.token)
			if !ok || !sameEmailVerificationClaims(claims, tc.want) {
				t.Errorf("readEmailVerificationToken = %+v, %v, want %+v", claims, ok, tc.want)
			}
		})
	}
}

// TestEmailVerificationToken_PurposeValidity は、目的ごとのリンクの有効な時間が Java 版の EmailVerificationPurpose と
// 同じで、知らない目的を知らないとすることを確かめる。
func TestEmailVerificationToken_PurposeValidity(t *testing.T) {
	cases := []struct {
		purpose emailVerificationPurpose
		want    time.Duration
		ok      bool
	}{
		{purposeRegistration, 24 * time.Hour, true},
		{purposeAccountEmail, 24 * time.Hour, true},
		{purposePendingEmail, 24 * time.Hour, true},
		{purposePasswordReset, 10 * time.Minute, true},
		{"UNKNOWN", 0, false},
	}
	for _, tc := range cases {
		if got, ok := tc.purpose.linkValidity(); got != tc.want || ok != tc.ok {
			t.Errorf("%s の有効な時間 = %v, %v, want %v, %v", tc.purpose, got, ok, tc.want, tc.ok)
		}
	}
}

// TestEmailVerificationToken_LifetimeText は、リンクの有効な時間の文が、Java 版の formatLifetime と同じことを確かめる。
func TestEmailVerificationToken_LifetimeText(t *testing.T) {
	cases := []struct {
		d    time.Duration
		want string
	}{
		{24 * time.Hour, "24時間"},
		{time.Hour, "1時間"},
		{10 * time.Minute, "10分"},
		{90 * time.Minute, "90分"},
		{2*time.Hour + 30*time.Second, "2時間"},
	}
	for _, tc := range cases {
		if got := linkLifetimeText(tc.d); got != tc.want {
			t.Errorf("linkLifetimeText(%v) = %q, want %q", tc.d, got, tc.want)
		}
	}
}

// TestEmailVerificationComplete_IntegrityViolationCodes は、Spring の SQLErrorCodeSQLExceptionTranslator が
// DataIntegrityViolationException に訳す PostgreSQL の SQLSTATE を、同じく一意の制約などの違反と見なすことを確かめる。
// 21000 は sql-error-codes.xml の duplicateKeyCodes から、01 02 22 23 27 44 の分類は SQLStateSQLExceptionTranslator から来る。
func TestEmailVerificationComplete_IntegrityViolationCodes(t *testing.T) {
	for code, want := range map[string]bool{
		"23505": true, "23502": true, "23503": true, "23514": true, "23000": true, "23P01": true,
		"21000": true, "22001": true, "01000": true, "02000": true, "27000": true, "44000": true,
		"21001": false, "42P01": false, "40001": false, "08006": false, "57014": false, "2": false, "": false,
	} {
		if got := isIntegrityViolation(fmt.Errorf("包んだ誤り: %w", &pgconn.PgError{Code: code})); got != want {
			t.Errorf("isIntegrityViolation(%q) = %v, want %v", code, got, want)
		}
	}
	if isIntegrityViolation(errors.New("データベースの誤りでない")) {
		t.Error("isIntegrityViolation(データベースの誤りでない) = true, want false")
	}
}

// TestEmailVerificationComplete_PasswordResetLeftToCaller は、目的が PASSWORD_RESET のリンクの書き換えを、
// 再設定の値を作る呼び出し元に任せ、書き換えずに誤りを返すことを確かめる。
func TestEmailVerificationComplete_PasswordResetLeftToCaller(t *testing.T) {
	s := newEmailVerificationTokenService(time.Unix(javaSampleIssuedAt, 0))
	for _, p := range []emailVerificationPurpose{purposePasswordReset, "UNKNOWN"} {
		c := emailVerificationClaims{JTI: javaSampleJTI, SubjectID: uuid.New(), Purpose: p, Email: "a@example.com"}
		if got, err := s.completeEmailVerification(t.Context(), c); err == nil {
			t.Errorf("completeEmailVerification(%s) = %q, nil, want 誤り", p, got)
		}
	}
}
