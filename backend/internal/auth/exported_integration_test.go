package auth

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/crypto/bcrypt"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// exportedUser は、公開した関数のテストで使う、連携と役割を持つ利用者の行である。
func exportedUser(email string) (userRow, []providerRow) {
	u := userRow{
		Email:           someText(email),
		Password:        someText(javaBcryptSample),
		Username:        someText("山田太郎"),
		ProfileImage:    someText("/profile/image/a.png"),
		TwoFactor:       true,
		CreatedAt:       oldStamp,
		UpdatedAt:       oldStamp,
		EmailVerifiedAt: oldStamp,
	}
	return u, []providerRow{{ID: uuid.New(), Name: "google", ProviderUserID: "g-" + email, CreatedAt: oldStamp, UpdatedAt: oldStamp}}
}

// TestExported_LoadUser は、LoadUser が、loadStoredUserOr と同じ行を読み、居なければ渡された誤りを返すことを確かめる。
func TestExported_LoadUser(t *testing.T) {
	ctx := t.Context()
	id := uuid.New()
	u, providers := exportedUser(uniqueEmail())
	insertStoredUser(t, id, u, []string{"USER"}, providers, -1)
	q := sqlcgen.New(testPool)

	want, wantErr := loadStoredUserOr(ctx, q, id, errors.New("unused"))
	got, err := LoadUser(ctx, q, id, errors.New("unused"))
	if err != nil || wantErr != nil {
		t.Fatalf("LoadUser = %v, loadStoredUserOr = %v, want どちらも nil", err, wantErr)
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("LoadUser = %+v\nwant %+v", got, want)
	}
	if got.Row.Username.String != "山田太郎" || len(got.Providers) != 1 || !reflect.DeepEqual(got.Roles, []string{"USER"}) {
		t.Errorf("LoadUser = %+v, want 名前と1つの連携と役割 USER を持つ行", got)
	}

	notFound := errors.New("居ない")
	if _, err := LoadUser(ctx, q, uuid.New(), notFound); !errors.Is(err, notFound) {
		t.Errorf("居ない利用者の LoadUser の誤り = %v, want %v", err, notFound)
	}
}

// TestExported_SaveUser は、SaveUser が、saveUser と同じく、利用者の行と連携と役割を書き直すことを確かめる。
func TestExported_SaveUser(t *testing.T) {
	ctx := t.Context()
	id := uuid.New()
	u, providers := exportedUser(uniqueEmail())
	insertStoredUser(t, id, u, []string{"USER"}, providers, -1)
	q := sqlcgen.New(testPool)
	loaded, err := LoadUser(ctx, q, id, errors.New("居ない"))
	if err != nil {
		t.Fatal(err)
	}
	loaded.Row.Username = someText("佐藤花子")
	loaded.Providers = nil
	loaded.Roles = []string{"ADMIN", "USER"}
	if err := SaveUser(ctx, q, loaded); err != nil {
		t.Fatalf("SaveUser = %v", err)
	}
	u.Username = someText("佐藤花子")
	wantRows(t, id, storedRows{Found: true, User: u, Roles: []string{"ADMIN", "USER"}, Providers: []providerRow{}})
}

// TestExported_InTransaction は、InTransaction が、fn の誤りを返して書いた行を取り消し、誤りが無ければ確定することを確かめる。
func TestExported_InTransaction(t *testing.T) {
	ctx := t.Context()
	s, _, _ := newEmailVerificationService(t, completionNow, nil)
	u, _ := exportedUser(uniqueEmail())
	failing := errors.New("止める")
	rolledBack := uuid.New()
	err := s.InTransaction(ctx, func(q *sqlcgen.Queries) error {
		if err := SaveUser(ctx, q, StoredUser{Row: sqlcgen.UpsertUserParams{
			ID: pgtype.UUID{Bytes: rolledBack, Valid: true}, Email: u.Email, CreatedAt: oldStamp, UpdatedAt: oldStamp,
		}}); err != nil {
			return err
		}
		return failing
	})
	if !errors.Is(err, failing) {
		t.Errorf("InTransaction = %v, want %v", err, failing)
	}
	wantRows(t, rolledBack, noRows)

	committed := uuid.New()
	if err := s.InTransaction(ctx, func(q *sqlcgen.Queries) error {
		return SaveUser(ctx, q, StoredUser{Row: sqlcgen.UpsertUserParams{
			ID: pgtype.UUID{Bytes: committed, Valid: true}, Email: someText(uniqueEmail()), CreatedAt: oldStamp, UpdatedAt: oldStamp,
		}})
	}); err != nil {
		t.Fatalf("InTransaction = %v", err)
	}
	if !readStoredRows(t, committed).Found {
		t.Error("誤りの無い InTransaction の行が確定していない")
	}
}

// TestExported_Passwords は、PasswordMatches が passwordMatches と同じ結果を返し、HashPassword が強さ10のハッシュを作ることを確かめる。
func TestExported_Passwords(t *testing.T) {
	hashes := []pgtype.Text{someText(javaBcryptSample), {}, someText("not-a-hash"), someText("$2a$99$7GThZnQnlSFeXeoLg46eZ.KUwPbEaMbPjxFAByKOZsyrVgR9eLY4q")}
	for _, h := range hashes {
		for _, p := range []string{"password", "Password1!", ""} {
			got, gotErr := PasswordMatches(p, h)
			want, wantErr := passwordMatches(p, h)
			if got != want || (gotErr == nil) != (wantErr == nil) {
				t.Errorf("PasswordMatches(%q, %q) = %v, %v, want %v, %v", p, h.String, got, gotErr, want, wantErr)
			}
		}
	}

	hash, err := HashPassword("Password1!")
	if err != nil {
		t.Fatalf("HashPassword = %v", err)
	}
	if cost, err := bcrypt.Cost([]byte(hash)); err != nil || cost != 10 {
		t.Errorf("HashPassword の強さ = %d, %v, want 10", cost, err)
	}
	if ok, err := passwordMatches("Password1!", someText(hash)); !ok || err != nil {
		t.Errorf("HashPassword のハッシュの照合 = %v, %v, want 合う", ok, err)
	}
	if _, err := HashPassword(strings.Repeat("a", 73)); err == nil {
		t.Error("73バイトのパスワードの HashPassword が誤りを返さない")
	}
}

// TestExported_EmailVerification は、SendEmailVerification が確認のメールを送り、送り直せる間隔の中では偽を返すことと、
// ClearCurrentEmailVerification が今のリンクの記録を消すことを確かめる。
func TestExported_EmailVerification(t *testing.T) {
	ctx := t.Context()
	s, _, mailer := newEmailVerificationService(t, completionNow, nil)
	subject := uuid.New()
	email := uniqueEmail()

	for _, c := range []struct {
		purpose emailVerificationPurpose
		want    emailVerificationPurpose
	}{{AccountEmail, purposeAccountEmail}, {PendingEmail, purposePendingEmail}} {
		if c.purpose != c.want {
			t.Errorf("公開した目的 = %q, want %q", c.purpose, c.want)
		}
	}

	sent, err := s.SendEmailVerification(ctx, email, subject, AccountEmail)
	if err != nil || !sent {
		t.Fatalf("SendEmailVerification = %v, %v, want 送れた", sent, err)
	}
	if len(mailer.got) != 1 || mailer.got[0].Destination.ToAddresses[0] != email {
		t.Fatalf("送ったメール = %d 通, want %s への1通", len(mailer.got), email)
	}
	claims, ok := s.readEmailVerificationToken(mailedToken(t, mailer, 0))
	if !ok || claims.Purpose != purposeAccountEmail || claims.SubjectID != subject || claims.Email != email {
		t.Errorf("リンクの項目 = %+v, %v, want 目的 ACCOUNT_EMAIL と利用者 %s と %s", claims, ok, subject, email)
	}
	again, err := s.SendEmailVerification(ctx, email, subject, PendingEmail)
	if err != nil || again {
		t.Errorf("間隔の中の SendEmailVerification = %v, %v, want 偽", again, err)
	}

	if _, found, err := s.findCurrentEmailVerification(ctx, subject); err != nil || !found {
		t.Fatalf("今のリンクの記録 = %v, %v, want ある", found, err)
	}
	if err := s.ClearCurrentEmailVerification(ctx, subject); err != nil {
		t.Fatalf("ClearCurrentEmailVerification = %v", err)
	}
	if _, found, err := s.findCurrentEmailVerification(ctx, subject); err != nil || found {
		t.Errorf("消したあとの今のリンクの記録 = %v, %v, want 無い", found, err)
	}
}

// TestExported_Sessions は、InvalidateSessions が世代の番号を上げて値をすべて消し、RemoveAllRefreshTokens が
// 世代の番号を変えずに値をすべて消すことを確かめる。
func TestExported_Sessions(t *testing.T) {
	ctx := t.Context()
	s, client := newRefreshService(t, refreshValidity, nil)

	id := insertTestUser(t, 3)
	value, err := s.issueRefreshToken(ctx, id, []string{"USER"}, 3)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.RemoveAllRefreshTokens(ctx, id); err != nil {
		t.Fatalf("RemoveAllRefreshTokens = %v", err)
	}
	if _, found, err := s.findRefreshToken(ctx, value); err != nil || found {
		t.Errorf("RemoveAllRefreshTokens のあとの値 = %v, %v, want 無い", found, err)
	}
	if keyExists(t, client, userRefreshKeyPrefix+id.String()) {
		t.Error("RemoveAllRefreshTokens のあとに利用者の値の集合が残っている")
	}
	if v, _, _ := tokenVersionRow(t, id); v != 3 {
		t.Errorf("RemoveAllRefreshTokens のあとの世代の番号 = %d, want 3", v)
	}

	value, err = s.issueRefreshToken(ctx, id, []string{"USER"}, 3)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.InvalidateSessions(ctx, id); err != nil {
		t.Fatalf("InvalidateSessions = %v", err)
	}
	if _, found, err := s.findRefreshToken(ctx, value); err != nil || found {
		t.Errorf("InvalidateSessions のあとの値 = %v, %v, want 無い", found, err)
	}
	if v, _, _ := tokenVersionRow(t, id); v != 4 {
		t.Errorf("InvalidateSessions のあとの世代の番号 = %d, want 4", v)
	}
}

// TestExported_Errors は、誤りを作る関数と FieldErrors が、元の関数と同じ誤りを作ることを確かめる。
func TestExported_Errors(t *testing.T) {
	if got, want := ErrBusiness("断る"), errBusiness("断る"); !reflect.DeepEqual(got, want) {
		t.Errorf("ErrBusiness = %+v, want %+v", got, want)
	}
	fields := map[string][]string{"email": {"メールアドレスが空です。"}}
	if got, want := ErrInvalidInput(fields), errInvalidInput(fields); !reflect.DeepEqual(got, want) {
		t.Errorf("ErrInvalidInput = %+v, want %+v", got, want)
	}
	if got, want := ErrCredentialsNotFound(MessageInvalidAccess), errCredentialsNotFound(MessageInvalidAccess); !reflect.DeepEqual(got, want) {
		t.Errorf("ErrCredentialsNotFound = %+v, want %+v", got, want)
	}

	f := FieldErrors{}
	if f.Result() != nil {
		t.Error("文言の無い FieldErrors の Result が nil でない")
	}
	f.Check("password", true, "使わない")
	f.Check("password", false, "一つ目")
	f.Check("password", false, "二つ目")
	want := errInvalidInput(map[string][]string{"password": {"一つ目", "二つ目"}})
	if got := f.Result(); !reflect.DeepEqual(got, want) {
		t.Errorf("FieldErrors の Result = %+v, want %+v", got, want)
	}
}

// TestExported_Validators は、入力の検査の部品が、元の関数と同じ結果を返すことを確かめる。
func TestExported_Validators(t *testing.T) {
	inputs := []string{"", " ", "　", "abc", "Password1!", "a@example.com", "a@", "a@example.com.", "😀", strings.Repeat("a", 65) + "@example.com"}
	for _, in := range inputs {
		if NotBlank(in) != notBlank(in) {
			t.Errorf("NotBlank(%q) = %v, want %v", in, NotBlank(in), notBlank(in))
		}
		if UTF16Len(in) != utf16Len(in) {
			t.Errorf("UTF16Len(%q) = %d, want %d", in, UTF16Len(in), utf16Len(in))
		}
		if PasswordPatternOK(in) != passwordPatternOK(in) {
			t.Errorf("PasswordPatternOK(%q) = %v, want %v", in, PasswordPatternOK(in), passwordPatternOK(in))
		}
		if IsEmailLikeHibernate(in) != isEmailLikeHibernate(in) {
			t.Errorf("IsEmailLikeHibernate(%q) = %v, want %v", in, IsEmailLikeHibernate(in), isEmailLikeHibernate(in))
		}
		if !reflect.DeepEqual(EmailCreateErrors(in), emailCreateErrors(in)) {
			t.Errorf("EmailCreateErrors(%q) = %v, want %v", in, EmailCreateErrors(in), emailCreateErrors(in))
		}
	}
	for _, r := range []rune{' ', '\t', '　', ' ', 'a'} {
		if IsJavaWhitespace(r) != isJavaWhitespace(r) {
			t.Errorf("IsJavaWhitespace(%U) = %v, want %v", r, IsJavaWhitespace(r), isJavaWhitespace(r))
		}
	}
}

// TestExported_EmailInUse は、EmailInUse が、users の email の列にメールアドレスを持つ利用者が居るときだけ真を返すことを確かめる。
func TestExported_EmailInUse(t *testing.T) {
	ctx := t.Context()
	s, _, _ := newEmailVerificationService(t, completionNow, nil)
	email := uniqueEmail()
	pending := uniqueEmail()
	u, _ := exportedUser(email)
	u.PendingEmail = someText(pending)
	insertStoredUser(t, uuid.New(), u, []string{"USER"}, nil, -1)

	for _, c := range []struct {
		email string
		want  bool
	}{{email, true}, {pending, false}, {uniqueEmail(), false}} {
		got, err := s.EmailInUse(ctx, c.email)
		if err != nil || got != c.want {
			t.Errorf("EmailInUse(%q) = %v, %v, want %v", c.email, got, err, c.want)
		}
	}
}
