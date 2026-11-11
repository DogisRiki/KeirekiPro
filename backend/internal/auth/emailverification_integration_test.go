package auth

import (
	"errors"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// newEmailVerificationService は、テストの Valkey と偽の SES と、Java 版の開発環境と同じ設定の値と鍵を使い、
// 今の時刻を now に決めた Service と、Redis に直に読み書きするクライアントと、偽の SES を作る。
// random が nil なら、本番と同じ乱数を使う。
func newEmailVerificationService(t *testing.T, now time.Time, random func([]byte) (int, error)) (*Service, redis.UniversalClient, *fakeSES) {
	t.Helper()
	templates, err := backend.MailTemplates()
	if err != nil {
		t.Fatal(err)
	}
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	t.Cleanup(func() { _ = client.Close() })
	mailer := &fakeSES{}
	return New(Deps{
		Pool:          testPool,
		Redis:         client,
		SES:           mailer,
		App:           javaDevApp(t),
		MailTemplates: templates,
		JWT:           config.JWT{Secret: javaDevSigningKey},
		Now:           func() time.Time { return now },
		Random:        random,
	}), client, mailer
}

// mailedBody は、偽の SES が i 番目に受けたメールの本文を返す。
func mailedBody(t *testing.T, mailer *fakeSES, i int) string {
	t.Helper()
	if len(mailer.got) <= i {
		t.Fatalf("SendEmail の呼び出し = %d 回, want %d 回以上", len(mailer.got), i+1)
	}
	return deref(mailer.got[i].Message.Body.Text.Data)
}

// mailedToken は、偽の SES が i 番目に受けたメールの確認のリンクの # のあとの値を返す。
func mailedToken(t *testing.T, mailer *fakeSES, i int) string {
	t.Helper()
	body := mailedBody(t, mailer, i)
	_, rest, ok := strings.Cut(body, "http://localhost:5173/email/verify#")
	if !ok {
		t.Fatalf("本文 %q に確認のリンクが無い", body)
	}
	token, _, _ := strings.Cut(rest, "\n")
	return strings.TrimSpace(token)
}

// mustSend は、確認のメールを送り、送れたことを確かめる。
func mustSend(t *testing.T, s *Service, email string, subject uuid.UUID, purpose emailVerificationPurpose) {
	t.Helper()
	sent, err := s.sendEmailVerification(t.Context(), email, subject, purpose)
	if err != nil || !sent {
		t.Fatalf("sendEmailVerification = %v, %v, want 送れた", sent, err)
	}
}

// TestEmailVerificationToken_SendMatchesJavaMail は、Java 版と同じ鍵と時刻と乱数と宛先で確認のメールを送ると、
// Java 版が送ったメールと同じメールを送り、今のリンクの記録と送り直せる間隔の記録を Java 版と同じ形で置くことを確かめる。
func TestEmailVerificationToken_SendMatchesJavaMail(t *testing.T) {
	jti := uuid.MustParse(javaSampleJTI)
	s, client, mailer := newEmailVerificationService(t, time.Unix(javaSampleIssuedAt, 250_000_000), fixedRandom(jti[:]))
	subject := uuid.MustParse(javaSampleSubject)
	currentKey := "email-verification:current:" + javaSampleSubject
	rateKey := "email-verification:rate:" + javaSampleEmail
	t.Cleanup(func() { client.Del(t.Context(), currentKey, rateKey) })

	mustSend(t, s, javaSampleEmail, subject, purposeRegistration)

	var want struct {
		To      []string `json:"to"`
		Subject string   `json:"subject"`
		Body    string   `json:"body"`
	}
	readMailJSON(t, "email-verification.json", &want)
	in := mailer.got[0]
	if strings.Join(in.Destination.ToAddresses, ",") != strings.Join(want.To, ",") {
		t.Errorf("宛先 = %v, want %v", in.Destination.ToAddresses, want.To)
	}
	if got := deref(in.Message.Subject.Data); got != want.Subject {
		t.Errorf("件名 = %q, want %q", got, want.Subject)
	}
	if got := mailedBody(t, mailer, 0); got != want.Body {
		t.Errorf("本文 = %q\nwant %q", got, want.Body)
	}
	if got := rawValue(t, client, currentKey); got != `"`+javaSampleJTI+`"` {
		t.Errorf("今のリンクの記録 = %q, want %q", got, `"`+javaSampleJTI+`"`)
	}
	assertTTL(t, client, currentKey, 24*time.Hour)
	if got := rawValue(t, client, rateKey); got != `"1"` {
		t.Errorf("送り直せる間隔の記録 = %q, want %q", got, `"1"`)
	}
	assertTTL(t, client, rateKey, 60*time.Second)
}

// TestEmailVerificationToken_TTLByPurpose は、目的ごとに、リンクの値の lexp と今のリンクの記録の有効な時間と
// メールに書くリンクの有効な時間が、Java 版と同じ長さになることを確かめる(要件3の受入基準3)。
func TestEmailVerificationToken_TTLByPurpose(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 5, 6, 700_000_000, time.UTC)
	cases := []struct {
		purpose  emailVerificationPurpose
		validity time.Duration
		lifetime string
	}{
		{purposeRegistration, 24 * time.Hour, "24時間"},
		{purposeAccountEmail, 24 * time.Hour, "24時間"},
		{purposePendingEmail, 24 * time.Hour, "24時間"},
		{purposePasswordReset, 10 * time.Minute, "10分"},
	}
	for _, tc := range cases {
		t.Run(string(tc.purpose), func(t *testing.T) {
			s, client, mailer := newEmailVerificationService(t, now, nil)
			email, subject := uniqueEmail(), uuid.New()
			mustSend(t, s, email, subject, tc.purpose)

			claims, ok := s.readEmailVerificationToken(mailedToken(t, mailer, 0))
			if !ok {
				t.Fatal("送ったリンクの値を読めない")
			}
			if claims.Purpose != tc.purpose || claims.Email != email || claims.SubjectID != subject {
				t.Errorf("リンクの値の項目 = %+v, want 目的 %s、宛先 %s、ID %s", claims, tc.purpose, email, subject)
			}
			if want := time.Unix(now.Add(tc.validity).Unix(), 0); !claims.LinkExpiresAt.Equal(want) {
				t.Errorf("リンクの期限 = %v, want %v", claims.LinkExpiresAt, want)
			}
			currentKey := "email-verification:current:" + subject.String()
			if got := rawValue(t, client, currentKey); got != `"`+claims.JTI+`"` {
				t.Errorf("今のリンクの記録 = %q, want リンクの jti %q", got, claims.JTI)
			}
			if _, err := uuid.Parse(claims.JTI); err != nil {
				t.Errorf("jti %q が UUID でない", claims.JTI)
			}
			assertTTL(t, client, currentKey, tc.validity)
			if body := mailedBody(t, mailer, 0); !strings.Contains(body, "受信後から"+tc.lifetime+"以内") {
				t.Errorf("本文 %q に有効な時間 %q が無い", body, tc.lifetime)
			}
		})
	}
}

// TestEmailVerificationToken_NewLinkReplacesOld は、新しいリンクを送ると、今のリンクの記録が新しいリンクの jti に
// 置き換わり、前のリンクの jti では消し込めなくなることを確かめる(要件3の受入基準3)。
// また、消し込みは同じ jti で1回だけ成り立ち、記録を消すと読めなくなることを確かめる。
func TestEmailVerificationToken_NewLinkReplacesOld(t *testing.T) {
	ctx := t.Context()
	s, _, mailer := newEmailVerificationService(t, time.Now(), nil)
	email, subject := uniqueEmail(), uuid.New()

	mustSend(t, s, email, subject, purposeRegistration)
	if err := s.releaseEmailVerificationSend(ctx, email); err != nil {
		t.Fatal(err)
	}
	mustSend(t, s, email, subject, purposeRegistration)
	oldClaims, ok1 := s.readEmailVerificationToken(mailedToken(t, mailer, 0))
	newClaims, ok2 := s.readEmailVerificationToken(mailedToken(t, mailer, 1))
	if !ok1 || !ok2 || oldClaims.JTI == newClaims.JTI {
		t.Fatalf("2つのリンクの jti = %q と %q, want 読めて違う値", oldClaims.JTI, newClaims.JTI)
	}

	if got, found, err := s.findCurrentEmailVerification(ctx, subject); err != nil || !found || got != newClaims.JTI {
		t.Errorf("今のリンク = %q, %v, %v, want 新しいリンクの jti %q", got, found, err, newClaims.JTI)
	}
	if consumed, err := s.consumeCurrentEmailVerification(ctx, subject, oldClaims.JTI); err != nil || consumed {
		t.Errorf("前のリンクの消し込み = %v, %v, want 消し込めない", consumed, err)
	}
	if got, found, _ := s.findCurrentEmailVerification(ctx, subject); !found || got != newClaims.JTI {
		t.Errorf("前のリンクで消し込もうとしたあとの今のリンク = %q, %v, want %q のまま", got, found, newClaims.JTI)
	}
	if consumed, err := s.consumeCurrentEmailVerification(ctx, subject, newClaims.JTI); err != nil || !consumed {
		t.Errorf("新しいリンクの消し込み = %v, %v, want 消し込める", consumed, err)
	}
	if consumed, err := s.consumeCurrentEmailVerification(ctx, subject, newClaims.JTI); err != nil || consumed {
		t.Errorf("同じリンクの2回目の消し込み = %v, %v, want 消し込めない", consumed, err)
	}
	if got, found, err := s.findCurrentEmailVerification(ctx, subject); err != nil || found {
		t.Errorf("消し込んだあとの今のリンク = %q, %v, %v, want 無い", got, found, err)
	}

	if err := s.putCurrentEmailVerification(ctx, subject, "x", time.Minute); err != nil {
		t.Fatal(err)
	}
	if err := s.clearCurrentEmailVerification(ctx, subject); err != nil {
		t.Fatal(err)
	}
	if got, found, err := s.findCurrentEmailVerification(ctx, subject); err != nil || found {
		t.Errorf("消したあとの今のリンク = %q, %v, %v, want 無い", got, found, err)
	}
}

// TestEmailVerificationRate_60Seconds は、同じメールアドレスへは60秒のあいだ送り直せず、そのあいだは何も置かずに
// 送れないと返し、ほかのメールアドレスへは送れることを確かめる(要件3の受入基準4)。
func TestEmailVerificationRate_60Seconds(t *testing.T) {
	ctx := t.Context()
	s, client, mailer := newEmailVerificationService(t, time.Now(), nil)
	email, first, second := uniqueEmail(), uuid.New(), uuid.New()
	rateKey := "email-verification:rate:" + email

	mustSend(t, s, email, first, purposeRegistration)
	assertTTL(t, client, rateKey, 60*time.Second)

	sent, err := s.sendEmailVerification(ctx, email, second, purposeAccountEmail)
	if err != nil || sent {
		t.Errorf("60秒のあいだの送り直し = %v, %v, want 送れない", sent, err)
	}
	if len(mailer.got) != 1 {
		t.Errorf("SendEmail の呼び出し = %d 回, want 1 回", len(mailer.got))
	}
	if keyExists(t, client, "email-verification:current:"+second.String()) {
		t.Error("送れなかったのに、今のリンクの記録が置かれた")
	}
	assertTTL(t, client, rateKey, 60*time.Second)

	mustSend(t, s, uniqueEmail(), second, purposeAccountEmail)

	if err := s.releaseEmailVerificationSend(ctx, email); err != nil {
		t.Fatal(err)
	}
	mustSend(t, s, email, second, purposeAccountEmail)
	if len(mailer.got) != 3 {
		t.Errorf("SendEmail の呼び出し = %d 回, want 3 回", len(mailer.got))
	}
}

// TestEmailVerificationRate_ReleasedWhenMailFails は、メールを送れないとき、送り直せる間隔の記録と今のリンクの記録を
// 消して誤りを返し、すぐに送り直せることを確かめる。前に送ったリンクも使えなくなる(Java 版も同じ)。
func TestEmailVerificationRate_ReleasedWhenMailFails(t *testing.T) {
	ctx := t.Context()
	s, client, mailer := newEmailVerificationService(t, time.Now(), nil)
	email, subject := uniqueEmail(), uuid.New()
	currentKey := "email-verification:current:" + subject.String()
	if err := s.putCurrentEmailVerification(ctx, subject, "earlier-jti", time.Hour); err != nil {
		t.Fatal(err)
	}

	sesErr := errors.New("SES に届かない")
	mailer.err = sesErr
	sent, err := s.sendEmailVerification(ctx, email, subject, purposeRegistration)
	if !errors.Is(err, sesErr) || sent {
		t.Errorf("sendEmailVerification = %v, %v, want SES の誤り", sent, err)
	}
	if keyExists(t, client, "email-verification:rate:"+email) {
		t.Error("送れなかったのに、送り直せる間隔の記録が残った")
	}
	if keyExists(t, client, currentKey) {
		t.Error("送れなかったのに、今のリンクの記録が残った")
	}

	mailer.err = nil
	mustSend(t, s, email, subject, purposeRegistration)
}

// completionNow は、確認の書き換えのテストの今の時刻である。データベースの TIMESTAMP(6) で丸められないよう、マイクロ秒までにする。
var completionNow = time.Date(2026, 11, 11, 3, 4, 5, 123456000, time.UTC)

// oldStamp は、テストで前もって足す行の日時である。
var oldStamp = pgtype.Timestamp{Time: time.Date(2026, 1, 2, 3, 4, 5, 678901000, time.UTC), Valid: true}

// javaWallClock は、Java 版が時刻 t を TIMESTAMP の列に書いた値を、pgx で読んだときの値である。
// Java 版は Asia/Tokyo の時刻の見た目で書き、pgx は時間帯の無い列を UTC の時刻として読む。
func javaWallClock(t time.Time) pgtype.Timestamp {
	w := t.In(javaZone)
	return pgtype.Timestamp{
		Time:  time.Date(w.Year(), w.Month(), w.Day(), w.Hour(), w.Minute(), w.Second(), w.Nanosecond(), time.UTC),
		Valid: true,
	}
}

// someText は、NULL でない文字列の列の値を作る。
func someText(s string) pgtype.Text {
	return pgtype.Text{String: s, Valid: true}
}

// userRow は、users の行の id 以外の列である。
type userRow struct {
	Email           pgtype.Text
	Password        pgtype.Text
	Username        pgtype.Text
	ProfileImage    pgtype.Text
	TwoFactor       bool
	CreatedAt       pgtype.Timestamp
	UpdatedAt       pgtype.Timestamp
	EmailVerifiedAt pgtype.Timestamp
	PendingEmail    pgtype.Text
}

// providerRow は、user_auth_providers の行の user_id 以外の列である。
type providerRow struct {
	ID             uuid.UUID
	Name           string
	ProviderUserID string
	CreatedAt      pgtype.Timestamp
	UpdatedAt      pgtype.Timestamp
}

// storedRows は、利用者1人の users と user_roles と user_auth_providers と user_token_versions の行である。
// 役割の行の付与日時は、Java 版も保存のたびに付け直すので、比べない。
type storedRows struct {
	Found      bool
	User       userRow
	Roles      []string
	Providers  []providerRow
	HasVersion bool
	Version    int64
	VersionAt  time.Time
}

// insertStoredUser は、利用者の行と、役割の行と、連携の行を足す。version が負でなければ、世代の番号の行も足す。
func insertStoredUser(t *testing.T, id uuid.UUID, u userRow, roles []string, providers []providerRow, version int64) {
	t.Helper()
	ctx := t.Context()
	if _, err := testPool.Exec(ctx,
		`INSERT INTO users (id, email, password, username, profile_image, two_factor_auth_enabled,
		                    created_at, updated_at, email_verified_at, pending_email)
		 VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
		id.String(), u.Email, u.Password, u.Username, u.ProfileImage, u.TwoFactor,
		u.CreatedAt, u.UpdatedAt, u.EmailVerifiedAt, u.PendingEmail); err != nil {
		t.Fatalf("利用者の行を足せない: %v", err)
	}
	for _, role := range roles {
		if _, err := testPool.Exec(ctx,
			`INSERT INTO user_roles (user_id, role_id, created_at) SELECT $1::uuid, id, now() FROM roles WHERE name = $2`,
			id.String(), role); err != nil {
			t.Fatalf("役割の行を足せない: %v", err)
		}
	}
	for _, p := range providers {
		if _, err := testPool.Exec(ctx,
			`INSERT INTO user_auth_providers (id, user_id, provider_name, provider_user_id, created_at, updated_at)
			 VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6)`,
			p.ID.String(), id.String(), p.Name, p.ProviderUserID, p.CreatedAt, p.UpdatedAt); err != nil {
			t.Fatalf("連携の行を足せない: %v", err)
		}
	}
	if version >= 0 {
		if _, err := testPool.Exec(ctx,
			`INSERT INTO user_token_versions (user_id, token_version, updated_at) VALUES ($1::uuid, $2, $3)`,
			id.String(), version, oldStamp); err != nil {
			t.Fatalf("世代の番号の行を足せない: %v", err)
		}
	}
}

// readStoredRows は、利用者 id の行を読む。役割は名前の順に、連携は ID の順に並べる。
func readStoredRows(t *testing.T, id uuid.UUID) storedRows {
	t.Helper()
	ctx := t.Context()
	r := storedRows{Roles: []string{}, Providers: []providerRow{}}
	err := testPool.QueryRow(ctx,
		`SELECT email, password, username, profile_image, two_factor_auth_enabled,
		        created_at, updated_at, email_verified_at, pending_email
		 FROM users WHERE id = $1::uuid`, id.String()).Scan(
		&r.User.Email, &r.User.Password, &r.User.Username, &r.User.ProfileImage, &r.User.TwoFactor,
		&r.User.CreatedAt, &r.User.UpdatedAt, &r.User.EmailVerifiedAt, &r.User.PendingEmail)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
	case err != nil:
		t.Fatalf("利用者の行を読めない: %v", err)
	default:
		r.Found = true
	}
	roles, err := testPool.Query(ctx,
		`SELECT r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = $1::uuid ORDER BY r.name`,
		id.String())
	if err != nil {
		t.Fatalf("役割の行を読めない: %v", err)
	}
	for roles.Next() {
		var name string
		if err := roles.Scan(&name); err != nil {
			t.Fatalf("役割の行を読めない: %v", err)
		}
		r.Roles = append(r.Roles, name)
	}
	roles.Close()
	providers, err := testPool.Query(ctx,
		`SELECT id, provider_name, provider_user_id, created_at, updated_at
		 FROM user_auth_providers WHERE user_id = $1::uuid ORDER BY id`, id.String())
	if err != nil {
		t.Fatalf("連携の行を読めない: %v", err)
	}
	for providers.Next() {
		var p providerRow
		var pid pgtype.UUID
		if err := providers.Scan(&pid, &p.Name, &p.ProviderUserID, &p.CreatedAt, &p.UpdatedAt); err != nil {
			t.Fatalf("連携の行を読めない: %v", err)
		}
		p.ID = pid.Bytes
		r.Providers = append(r.Providers, p)
	}
	providers.Close()
	r.Version, r.VersionAt, r.HasVersion = tokenVersionRow(t, id)
	return r
}

// savedRegistration は、登録の途中の記録を置いて返す。
func savedRegistration(t *testing.T, s *Service) pendingRegistration {
	t.Helper()
	r := pendingRegistration{
		ID:           uuid.New(),
		Email:        uniqueEmail(),
		PasswordHash: javaBcryptSample,
		Username:     "山田<&>太郎",
		CreatedAt:    completionNow.Add(-time.Hour),
	}
	if err := s.savePendingRegistration(t.Context(), r, registrationLifetime); err != nil {
		t.Fatal(err)
	}
	return r
}

// usableClaims は、目的 purpose で、利用者 id とメールアドレス email を指す、期限の前のリンクの項目である。
func usableClaims(id uuid.UUID, purpose emailVerificationPurpose, email string) emailVerificationClaims {
	return emailVerificationClaims{
		JTI:           uuid.NewString(),
		SubjectID:     id,
		Purpose:       purpose,
		Email:         email,
		LinkExpiresAt: completionNow.Add(time.Hour),
	}
}

// wantPending は、登録の途中の記録が残っているかが want であることを確かめる。
func wantPending(t *testing.T, s *Service, id uuid.UUID, want bool) {
	t.Helper()
	if _, found, err := s.findPendingRegistration(t.Context(), id); err != nil || found != want {
		t.Errorf("登録の途中の記録 = %v, %v, want %v", found, err, want)
	}
}

// wantRows は、利用者 id の行が want と同じであることを確かめる。
func wantRows(t *testing.T, id uuid.UUID, want storedRows) {
	t.Helper()
	if got := readStoredRows(t, id); !reflect.DeepEqual(got, want) {
		t.Errorf("行 = %+v\nwant %+v", got, want)
	}
}

// noRows は、利用者の行がひとつも無いときの storedRows である。
var noRows = storedRows{Roles: []string{}, Providers: []providerRow{}}

// linkSetup は、分類のテストで、利用者 id とメールアドレス email と値の ID jti に合わせて前もって置く記録を作る。
type linkSetup func(t *testing.T, id uuid.UUID, email, jti string)

// TestEmailVerificationComplete_ClassifyLink は、Java 版の EmailVerificationLinkClassifier と同じ順と条件で、
// 確認のリンクを分類することを確かめる。
func TestEmailVerificationComplete_ClassifyLink(t *testing.T) {
	ctx := t.Context()
	s, client, _ := newEmailVerificationService(t, completionNow, nil)
	live := completionNow.Add(time.Hour)
	expired := completionNow.Add(-time.Second)
	unverified := func(email string) userRow {
		return userRow{Email: someText(email), CreatedAt: oldStamp, UpdatedAt: oldStamp}
	}
	verified := func(email string) userRow {
		u := unverified(email)
		u.EmailVerifiedAt = oldStamp
		return u
	}
	pendingOnly := func(email string) userRow {
		return userRow{PendingEmail: someText(email), CreatedAt: oldStamp, UpdatedAt: oldStamp}
	}
	user := func(u func(string) userRow, other bool) linkSetup {
		return func(t *testing.T, id uuid.UUID, email, _ string) {
			if other {
				email = uniqueEmail()
			}
			insertStoredUser(t, id, u(email), []string{"USER"}, nil, 0)
		}
	}
	pending := func(t *testing.T, id uuid.UUID, email, _ string) {
		r := pendingRegistration{ID: id, Email: email, PasswordHash: javaBcryptSample, Username: "u", CreatedAt: completionNow}
		if err := s.savePendingRegistration(ctx, r, registrationLifetime); err != nil {
			t.Fatal(err)
		}
	}
	current := func(t *testing.T, id uuid.UUID, _, jti string) {
		if err := s.putCurrentEmailVerification(ctx, id, jti, time.Hour); err != nil {
			t.Fatal(err)
		}
	}
	otherCurrent := func(t *testing.T, id uuid.UUID, email, _ string) {
		current(t, id, email, uuid.NewString())
	}
	all := func(steps ...linkSetup) linkSetup {
		return func(t *testing.T, id uuid.UUID, email, jti string) {
			for _, step := range steps {
				step(t, id, email, jti)
			}
		}
	}
	nothing := all()

	for _, tc := range []struct {
		name      string
		purpose   emailVerificationPurpose
		expiresAt time.Time
		setup     linkSetup
		want      emailVerificationResult
	}{
		{"確認済みで同じメールアドレスなら、期限が切れていても ALREADY_VERIFIED", purposeAccountEmail, expired, user(verified, false), resultAlreadyVerified},
		{"確認済みで同じメールアドレスなら、今のリンクでも ALREADY_VERIFIED", purposeRegistration, live, all(user(verified, false), current, pending), resultAlreadyVerified},
		{"確認済みでもメールアドレスが違えば、今のリンクを使える", purposeAccountEmail, live, all(user(verified, true), current), linkUsable},
		{"期限の前の今のリンクを使える", purposeRegistration, live, all(pending, current), linkUsable},
		{"期限の1ナノ秒前の今のリンクを使える", purposeRegistration, completionNow.Add(time.Nanosecond), all(pending, current), linkUsable},
		{"期限ちょうどの今のリンクは、途中の記録があれば EXPIRED", purposeRegistration, completionNow, all(pending, current), resultExpired},
		{"今のリンクでない登録のリンクは、途中の記録があれば EXPIRED", purposeRegistration, live, all(pending, otherCurrent), resultExpired},
		{"今のリンクの記録が無い登録のリンクは、途中の記録が無ければ REGISTRATION_GONE", purposeRegistration, live, nothing, resultRegistrationGone},
		{"登録のリンクは、確認前の同じメールアドレスの利用者が居ても、途中の記録が無ければ REGISTRATION_GONE", purposeRegistration, expired, user(unverified, false), resultRegistrationGone},
		{"期限の切れたリンクは、確認前の同じメールアドレスなら EXPIRED", purposeAccountEmail, expired, all(user(unverified, false), current), resultExpired},
		{"今のリンクでないリンクは、確認前の同じメールアドレスなら EXPIRED", purposeAccountEmail, live, all(user(unverified, false), otherCurrent), resultExpired},
		{"メールアドレスが違えば INVALID", purposeAccountEmail, live, user(unverified, true), resultInvalid},
		{"利用者が居なければ INVALID", purposeAccountEmail, live, nothing, resultInvalid},
		{"メールアドレスが無く設定待ちのメールアドレスだけが同じなら INVALID", purposeAccountEmail, live, user(pendingOnly, false), resultInvalid},
		{"設定待ちのメールアドレスのリンクは、設定待ちのメールアドレスが同じなら EXPIRED", purposePendingEmail, live, user(pendingOnly, false), resultExpired},
		{"設定待ちのメールアドレスのリンクは、メールアドレスだけが同じなら INVALID", purposePendingEmail, live, user(unverified, false), resultInvalid},
		{"再設定のリンクは、確認前の同じメールアドレスなら EXPIRED", purposePasswordReset, live, user(unverified, false), resultExpired},
	} {
		t.Run(tc.name, func(t *testing.T) {
			id, email, jti := uuid.New(), uniqueEmail(), uuid.NewString()
			tc.setup(t, id, email, jti)
			c := emailVerificationClaims{JTI: jti, SubjectID: id, Purpose: tc.purpose, Email: email, LinkExpiresAt: tc.expiresAt}
			if got, err := s.classifyEmailVerificationLink(ctx, c); err != nil || got != tc.want {
				t.Errorf("classifyEmailVerificationLink = %q, %v, want %q", got, err, tc.want)
			}
		})
	}

	t.Run("利用者の行が User.reconstruct の確かめに反すれば 400", func(t *testing.T) {
		// Java 版の findById は、2段階認証が有効でパスワードが無い利用者を DomainException で断る
		id, email := uuid.New(), uniqueEmail()
		u := verified(email)
		u.TwoFactor = true
		insertStoredUser(t, id, u, []string{"USER"}, nil, 0)
		_, err := s.classifyEmailVerificationLink(ctx, usableClaims(id, purposeAccountEmail, email))
		wantBusinessError(t, err, MessageTwoFactorPrerequisiteMissing)
	})

	t.Run("今のリンクの記録が JSON でなければ誤り", func(t *testing.T) {
		id, email := uuid.New(), uniqueEmail()
		if err := client.Set(ctx, "email-verification:current:"+id.String(), "not-json", time.Minute).Err(); err != nil {
			t.Fatal(err)
		}
		if got, err := s.classifyEmailVerificationLink(ctx, usableClaims(id, purposeAccountEmail, email)); err == nil {
			t.Errorf("classifyEmailVerificationLink = %q, nil, want 誤り", got)
		}
	})
}

// TestEmailVerificationComplete_SecondUseAlreadyVerified は、送った確認のリンクを1回使うと書き換えが済み、
// 同じリンクを2回目に分類すると ALREADY_VERIFIED になることを、目的ごとに確かめる(要件3の受入基準3)。
func TestEmailVerificationComplete_SecondUseAlreadyVerified(t *testing.T) {
	ctx := t.Context()
	for _, tc := range []struct {
		purpose emailVerificationPurpose
		setup   func(t *testing.T, s *Service) (uuid.UUID, string)
	}{
		{purposeRegistration, func(t *testing.T, s *Service) (uuid.UUID, string) {
			r := savedRegistration(t, s)
			return r.ID, r.Email
		}},
		{purposeAccountEmail, func(t *testing.T, _ *Service) (uuid.UUID, string) {
			id, email := uuid.New(), uniqueEmail()
			insertStoredUser(t, id, userRow{Email: someText(email), Password: someText(javaBcryptSample), CreatedAt: oldStamp, UpdatedAt: oldStamp}, []string{"USER"}, nil, 0)
			return id, email
		}},
		{purposePendingEmail, func(t *testing.T, _ *Service) (uuid.UUID, string) {
			id, email := uuid.New(), uniqueEmail()
			insertStoredUser(t, id, userRow{PendingEmail: someText(email), CreatedAt: oldStamp, UpdatedAt: oldStamp}, []string{"USER"}, nil, 0)
			return id, email
		}},
	} {
		t.Run(string(tc.purpose), func(t *testing.T) {
			s, _, mailer := newEmailVerificationService(t, completionNow, nil)
			id, email := tc.setup(t, s)
			mustSend(t, s, email, id, tc.purpose)
			c, ok := s.readEmailVerificationToken(mailedToken(t, mailer, 0))
			if !ok {
				t.Fatal("送ったリンクの値を読めない")
			}
			if got, err := s.classifyEmailVerificationLink(ctx, c); err != nil || got != linkUsable {
				t.Fatalf("1回目の分類 = %q, %v, want %q", got, err, linkUsable)
			}
			if consumed, err := s.consumeCurrentEmailVerification(ctx, id, c.JTI); err != nil || !consumed {
				t.Fatalf("consumeCurrentEmailVerification = %v, %v", consumed, err)
			}
			if got, err := s.completeEmailVerification(ctx, c); err != nil || got != resultVerified {
				t.Fatalf("completeEmailVerification = %q, %v, want %q", got, err, resultVerified)
			}
			if got, err := s.classifyEmailVerificationLink(ctx, c); err != nil || got != resultAlreadyVerified {
				t.Errorf("2回目の分類 = %q, %v, want %q", got, err, resultAlreadyVerified)
			}
		})
	}
}

// TestEmailVerificationComplete_RowsInOneTransaction は、登録の完了が、Java 版の EmailVerificationCompletion と同じ列と値で
// 利用者と役割と世代の番号の行を1つのトランザクションで足し、登録の完了のメールをその中で送ることを確かめる
// (要件4の受入基準2)。メールを送れなければ、Java 版と同じく、足した行をすべて取り消す。
func TestEmailVerificationComplete_RowsInOneTransaction(t *testing.T) {
	ctx := t.Context()

	t.Run("利用者と役割と世代の番号の行を足し、登録の完了のメールを送り、途中の記録を消す", func(t *testing.T) {
		s, client, mailer := newEmailVerificationService(t, completionNow, nil)
		r := savedRegistration(t, s)
		if got, err := s.completeEmailVerification(ctx, usableClaims(r.ID, purposeRegistration, r.Email)); err != nil || got != resultVerified {
			t.Fatalf("completeEmailVerification = %q, %v, want %q", got, err, resultVerified)
		}
		now := javaWallClock(completionNow)
		wantRows(t, r.ID, storedRows{
			Found: true,
			User: userRow{
				Email:           someText(r.Email),
				Password:        someText(r.PasswordHash),
				Username:        someText(r.Username),
				CreatedAt:       now,
				UpdatedAt:       now,
				EmailVerifiedAt: now,
			},
			Roles:      []string{"USER"},
			Providers:  []providerRow{},
			HasVersion: true,
			Version:    0,
			VersionAt:  now.Time,
		})
		m := userRegisteredMail(s.deps.App, r.Username)
		body, err := renderMail(s.deps.MailTemplates, m)
		if err != nil {
			t.Fatal(err)
		}
		if len(mailer.got) != 1 {
			t.Fatalf("SendEmail の呼び出し = %d 回, want 1 回", len(mailer.got))
		}
		in := mailer.got[0]
		if !slices.Equal(in.Destination.ToAddresses, []string{r.Email}) || deref(in.Message.Subject.Data) != m.subject || deref(in.Message.Body.Text.Data) != body {
			t.Errorf("メール = %v %q %q, want %v %q %q", in.Destination.ToAddresses, deref(in.Message.Subject.Data), deref(in.Message.Body.Text.Data), r.Email, m.subject, body)
		}
		wantPending(t, s, r.ID, false)
		if keyExists(t, client, "pending-registration:email:"+r.Email) {
			t.Error("メールアドレスごとの集合が残った")
		}
	})

	t.Run("登録の完了のメールを送れなければ、足した行をすべて取り消し、途中の記録を残す", func(t *testing.T) {
		s, _, mailer := newEmailVerificationService(t, completionNow, nil)
		mailer.err = errors.New("SES を使えない")
		r := savedRegistration(t, s)
		if got, err := s.completeEmailVerification(ctx, usableClaims(r.ID, purposeRegistration, r.Email)); !errors.Is(err, mailer.err) {
			t.Fatalf("completeEmailVerification = %q, %v, want メールの誤り", got, err)
		}
		if len(mailer.got) != 1 {
			t.Errorf("SendEmail の呼び出し = %d 回, want 1 回", len(mailer.got))
		}
		wantRows(t, r.ID, noRows)
		wantPending(t, s, r.ID, true)
	})

	t.Run("途中の記録が無ければ REGISTRATION_GONE で、行を足さない", func(t *testing.T) {
		s, _, mailer := newEmailVerificationService(t, completionNow, nil)
		id := uuid.New()
		if got, err := s.completeEmailVerification(ctx, usableClaims(id, purposeRegistration, uniqueEmail())); err != nil || got != resultRegistrationGone {
			t.Errorf("completeEmailVerification = %q, %v, want %q", got, err, resultRegistrationGone)
		}
		wantRows(t, id, noRows)
		if len(mailer.got) != 0 {
			t.Errorf("SendEmail の呼び出し = %d 回, want 0 回", len(mailer.got))
		}
	})
}

// TestEmailVerificationComplete_EmailTaken は、登録の完了が一意の制約に当たったとき、Java 版の
// DataIntegrityViolationException の扱いと同じく、トランザクションの外で利用者を読み直し、確認済みで同じメールアドレスなら
// ALREADY_VERIFIED を、そうでなければ EMAIL_TAKEN を返し、行と登録の途中の記録を変えないことを確かめる(要件4の受入基準2)。
func TestEmailVerificationComplete_EmailTaken(t *testing.T) {
	ctx := t.Context()
	for _, tc := range []struct {
		name string
		// sameID が真なら、登録の途中の記録と同じ ID の利用者を足す。偽なら、ほかの ID の利用者を足す
		sameID   bool
		verified bool
		// otherEmail が真なら、足す利用者のメールアドレスを、登録の途中の記録と違うものにする
		otherEmail bool
		want       emailVerificationResult
	}{
		{name: "ほかの利用者が確認済みのメールアドレスに使っていれば EMAIL_TAKEN", verified: true, want: resultEmailTaken},
		{name: "ほかの利用者が確認前のメールアドレスに使っていれば EMAIL_TAKEN", want: resultEmailTaken},
		{name: "同じ ID の確認済みの利用者を別の版が先に作っていれば ALREADY_VERIFIED", sameID: true, verified: true, want: resultAlreadyVerified},
		{name: "同じ ID の確認前の利用者が居れば EMAIL_TAKEN", sameID: true, want: resultEmailTaken},
		{name: "同じ ID の確認済みの利用者のメールアドレスが違えば EMAIL_TAKEN", sameID: true, verified: true, otherEmail: true, want: resultEmailTaken},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, _, mailer := newEmailVerificationService(t, completionNow, nil)
			r := savedRegistration(t, s)
			id, email := uuid.New(), r.Email
			if tc.sameID {
				id = r.ID
			}
			if tc.otherEmail {
				email = uniqueEmail()
			}
			u := userRow{Email: someText(email), Password: someText(javaBcryptSample), CreatedAt: oldStamp, UpdatedAt: oldStamp}
			if tc.verified {
				u.EmailVerifiedAt = oldStamp
			}
			insertStoredUser(t, id, u, []string{"USER"}, nil, 3)
			before := readStoredRows(t, id)
			if got, err := s.completeEmailVerification(ctx, usableClaims(r.ID, purposeRegistration, r.Email)); err != nil || got != tc.want {
				t.Errorf("completeEmailVerification = %q, %v, want %q", got, err, tc.want)
			}
			wantRows(t, id, before)
			if !tc.sameID {
				wantRows(t, r.ID, noRows)
			}
			// Java 版は、EMAIL_TAKEN の登録の途中の記録を消さず、有効な時間が過ぎて消えるのを待つ
			wantPending(t, s, r.ID, true)
			if len(mailer.got) != 0 {
				t.Errorf("SendEmail の呼び出し = %d 回, want 0 回", len(mailer.got))
			}
		})
	}
}

// accountEmailUser は、確認前のメールアドレスと、パスワードと、名前と、画像と、2段階認証と、Google の連携を持つ利用者の行である。
func accountEmailUser(email string) (userRow, []providerRow) {
	return userRow{
		Email:        someText(email),
		Password:     someText(javaBcryptSample),
		Username:     someText("花子"),
		ProfileImage: someText("profile/a.png"),
		TwoFactor:    true,
		CreatedAt:    oldStamp,
		UpdatedAt:    oldStamp,
	}, []providerRow{{
		ID: uuid.New(), Name: "google", ProviderUserID: "g-123", CreatedAt: oldStamp, UpdatedAt: oldStamp,
	}}
}

// TestEmailVerificationComplete_AccountEmailVerified は、目的が ACCOUNT_EMAIL のリンクで、Java 版の User.verifyEmail と
// UserRepository.save と同じく、確認した日時と更新日時だけを今の時刻に書き換え、ほかの列と役割と連携の行を残すことを確かめる。
func TestEmailVerificationComplete_AccountEmailVerified(t *testing.T) {
	ctx := t.Context()
	s, _, mailer := newEmailVerificationService(t, completionNow, nil)

	t.Run("確認前のメールアドレスを確認済みにする", func(t *testing.T) {
		id, email := uuid.New(), uniqueEmail()
		u, providers := accountEmailUser(email)
		insertStoredUser(t, id, u, []string{"USER", "ADMIN"}, providers, 5)
		want := readStoredRows(t, id)
		want.User.UpdatedAt = javaWallClock(completionNow)
		want.User.EmailVerifiedAt = javaWallClock(completionNow)
		if got, err := s.completeEmailVerification(ctx, usableClaims(id, purposeAccountEmail, email)); err != nil || got != resultVerified {
			t.Fatalf("completeEmailVerification = %q, %v, want %q", got, err, resultVerified)
		}
		wantRows(t, id, want)
	})

	t.Run("確認済みなら日時を変えない", func(t *testing.T) {
		// Java 版の verifyEmail は、確認済みなら同じ利用者を返し、save は同じ値を書く
		id, email := uuid.New(), uniqueEmail()
		u, providers := accountEmailUser(email)
		u.EmailVerifiedAt = oldStamp
		insertStoredUser(t, id, u, []string{"USER"}, providers, 5)
		before := readStoredRows(t, id)
		if got, err := s.completeEmailVerification(ctx, usableClaims(id, purposeAccountEmail, email)); err != nil || got != resultVerified {
			t.Fatalf("completeEmailVerification = %q, %v, want %q", got, err, resultVerified)
		}
		wantRows(t, id, before)
	})

	for _, tc := range []struct {
		name    string
		user    func(email string) userRow
		roles   []string
		message string
	}{
		{"メールアドレスが違えば 400", func(string) userRow { u, _ := accountEmailUser(uniqueEmail()); return u }, []string{"USER"}, MessageInvalidVerificationLink},
		{"メールアドレスが無ければ 400", func(email string) userRow {
			return userRow{PendingEmail: someText(email), CreatedAt: oldStamp, UpdatedAt: oldStamp}
		}, []string{"USER"}, MessageInvalidVerificationLink},
		{"利用者が居なければ 400", nil, nil, MessageInvalidVerificationLink},
		{"利用者の行が User.reconstruct の確かめに反すれば 400", func(email string) userRow {
			u, _ := accountEmailUser(email)
			u.TwoFactor = false
			return u
		}, []string{"ADMIN"}, MessageAdminNeedsTwoFactor},
	} {
		t.Run(tc.name, func(t *testing.T) {
			id, email := uuid.New(), uniqueEmail()
			if tc.user != nil {
				insertStoredUser(t, id, tc.user(email), tc.roles, nil, 5)
			}
			before := readStoredRows(t, id)
			_, err := s.completeEmailVerification(ctx, usableClaims(id, purposeAccountEmail, email))
			wantBusinessError(t, err, tc.message)
			wantRows(t, id, before)
		})
	}
	if len(mailer.got) != 0 {
		t.Errorf("SendEmail の呼び出し = %d 回, want 0 回", len(mailer.got))
	}
}

// pendingEmailUser は、メールアドレスが無く、設定待ちのメールアドレスと GitHub の連携を持つ利用者の行である。
func pendingEmailUser(pending string) (userRow, []providerRow) {
	return userRow{
		Username:     someText("次郎"),
		PendingEmail: someText(pending),
		CreatedAt:    oldStamp,
		UpdatedAt:    oldStamp,
	}, []providerRow{{
		ID: uuid.New(), Name: "github", ProviderUserID: "gh-456", CreatedAt: oldStamp, UpdatedAt: oldStamp,
	}}
}

// TestEmailVerificationComplete_PendingEmailPromoted は、目的が PENDING_EMAIL のリンクで、Java 版の
// User.promotePendingEmail と同じく、設定待ちのメールアドレスをメールアドレスに移して確認済みにし、設定待ちを空にすることを確かめる。
func TestEmailVerificationComplete_PendingEmailPromoted(t *testing.T) {
	ctx := t.Context()
	s, _, mailer := newEmailVerificationService(t, completionNow, nil)

	t.Run("設定待ちのメールアドレスをメールアドレスにして確認済みにする", func(t *testing.T) {
		id, email := uuid.New(), uniqueEmail()
		u, providers := pendingEmailUser(email)
		insertStoredUser(t, id, u, []string{"USER"}, providers, 2)
		want := readStoredRows(t, id)
		want.User.Email = someText(email)
		want.User.PendingEmail = pgtype.Text{}
		want.User.UpdatedAt = javaWallClock(completionNow)
		want.User.EmailVerifiedAt = javaWallClock(completionNow)
		if got, err := s.completeEmailVerification(ctx, usableClaims(id, purposePendingEmail, email)); err != nil || got != resultVerified {
			t.Fatalf("completeEmailVerification = %q, %v, want %q", got, err, resultVerified)
		}
		wantRows(t, id, want)
	})

	for _, tc := range []struct {
		name    string
		user    func(email string) userRow
		message string
	}{
		{"設定待ちのメールアドレスが違えば 400", func(string) userRow { u, _ := pendingEmailUser(uniqueEmail()); return u }, MessageInvalidVerificationLink},
		{"設定待ちのメールアドレスが無ければ 400", func(email string) userRow {
			return userRow{Email: someText(email), CreatedAt: oldStamp, UpdatedAt: oldStamp}
		}, MessageInvalidVerificationLink},
		{"メールアドレスがすでにあれば 400", func(email string) userRow {
			u, _ := pendingEmailUser(email)
			u.Email = someText(uniqueEmail())
			return u
		}, MessagePendingEmailMissing},
		{"利用者が居なければ 400", nil, MessageInvalidVerificationLink},
	} {
		t.Run(tc.name, func(t *testing.T) {
			id, email := uuid.New(), uniqueEmail()
			if tc.user != nil {
				insertStoredUser(t, id, tc.user(email), []string{"USER"}, nil, 2)
			}
			before := readStoredRows(t, id)
			_, err := s.completeEmailVerification(ctx, usableClaims(id, purposePendingEmail, email))
			wantBusinessError(t, err, tc.message)
			wantRows(t, id, before)
		})
	}
	if len(mailer.got) != 0 {
		t.Errorf("SendEmail の呼び出し = %d 回, want 0 回", len(mailer.got))
	}
}

// TestEmailVerificationComplete_PendingEmailTaken は、付け替え先のメールアドレスをほかの利用者が使っていれば、
// Java 版と同じく EMAIL_TAKEN を返し、どちらの利用者の行も変えないことを確かめる。
func TestEmailVerificationComplete_PendingEmailTaken(t *testing.T) {
	ctx := t.Context()
	s, _, _ := newEmailVerificationService(t, completionNow, nil)
	id, other, email := uuid.New(), uuid.New(), uniqueEmail()
	u, providers := pendingEmailUser(email)
	insertStoredUser(t, id, u, []string{"USER"}, providers, 2)
	insertStoredUser(t, other, userRow{Email: someText(email), CreatedAt: oldStamp, UpdatedAt: oldStamp, EmailVerifiedAt: oldStamp}, []string{"USER"}, nil, 0)
	before, otherBefore := readStoredRows(t, id), readStoredRows(t, other)
	if got, err := s.completeEmailVerification(ctx, usableClaims(id, purposePendingEmail, email)); err != nil || got != resultEmailTaken {
		t.Errorf("completeEmailVerification = %q, %v, want %q", got, err, resultEmailTaken)
	}
	wantRows(t, id, before)
	wantRows(t, other, otherBefore)
}

// TestEmailVerificationComplete_DatabaseErrors は、データベースを使えないとき、分類と書き換えが誤りを返すことを確かめる。
func TestEmailVerificationComplete_DatabaseErrors(t *testing.T) {
	ctx := t.Context()
	s, _, _ := newEmailVerificationService(t, completionNow, nil)
	closed, err := pgxpool.New(ctx, testPool.Config().ConnString())
	if err != nil {
		t.Fatal(err)
	}
	closed.Close()
	s.deps.Pool = closed
	r := savedRegistration(t, s)
	if _, err := s.classifyEmailVerificationLink(ctx, usableClaims(r.ID, purposeRegistration, r.Email)); err == nil {
		t.Error("classifyEmailVerificationLink が誤りを返さない")
	}
	for _, c := range []emailVerificationClaims{
		usableClaims(r.ID, purposeRegistration, r.Email),
		usableClaims(uuid.New(), purposeAccountEmail, uniqueEmail()),
		usableClaims(uuid.New(), purposePendingEmail, uniqueEmail()),
	} {
		if got, err := s.completeEmailVerification(ctx, c); err == nil {
			t.Errorf("completeEmailVerification(%s) = %q, nil, want 誤り", c.Purpose, got)
		}
	}
	wantPending(t, s, r.ID, true)
}
