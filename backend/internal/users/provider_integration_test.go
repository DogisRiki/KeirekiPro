package users

import (
	"errors"
	"reflect"
	"slices"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// oldStamp は、テストで前もって足す行の日時である。
var oldStamp = pgtype.Timestamp{Time: time.Date(2026, 1, 2, 3, 4, 5, 678901000, time.UTC), Valid: true}

// testNow は、利用者の操作のテストの今の時刻である。データベースの TIMESTAMP(6) で丸められないよう、マイクロ秒までにする。
var testNow = time.Date(2026, 11, 13, 1, 2, 3, 456789000, time.UTC)

// testJavaZone は、Java 版のコンテナの時間帯(Asia/Tokyo)である。テストは、処理の側の値に頼らずに期待の値を作る。
var testJavaZone = time.FixedZone("Asia/Tokyo", 9*3600)

// javaWallClock は、Java 版が時刻 t を TIMESTAMP の列に書いた値を、pgx で読んだときの値である。
// Java 版は Asia/Tokyo の時刻の見た目で書き、pgx は時間帯の無い列を UTC の時刻として読む。
func javaWallClock(t time.Time) pgtype.Timestamp {
	w := t.In(testJavaZone)
	return pgtype.Timestamp{
		Time:  time.Date(w.Year(), w.Month(), w.Day(), w.Hour(), w.Minute(), w.Second(), w.Nanosecond(), time.UTC),
		Valid: true,
	}
}

// someText は、NULL でない文字列の列の値を作る。
func someText(s string) pgtype.Text {
	return pgtype.Text{String: s, Valid: true}
}

// userRow は、テストで足す利用者の行の、変えたい列だけを持つ。
type userRow struct {
	Email           pgtype.Text
	Password        pgtype.Text
	EmailVerifiedAt pgtype.Timestamp
	PendingEmail    pgtype.Text
}

// insertUser は、利用者の行と、providers の名前の連携と、役割 USER を足し、利用者の ID を返す。
// メールアドレスは、ほかのテストの行と重ならない値にする。
func insertUser(t *testing.T, row userRow, providers ...string) uuid.UUID {
	t.Helper()
	id := uuid.New()
	q := sqlcgen.New(testPool)
	if row.Email.Valid {
		row.Email = someText(id.String() + "-" + row.Email.String)
	}
	if err := q.UpsertUser(t.Context(), sqlcgen.UpsertUserParams{
		ID:              pgtype.UUID{Bytes: id, Valid: true},
		Email:           row.Email,
		Password:        row.Password,
		Username:        someText("山田太郎"),
		ProfileImage:    someText("/profile/image/a.png"),
		CreatedAt:       oldStamp,
		UpdatedAt:       oldStamp,
		EmailVerifiedAt: row.EmailVerifiedAt,
		PendingEmail:    row.PendingEmail,
	}); err != nil {
		t.Fatalf("利用者の行を足せません: %v", err)
	}
	for _, name := range providers {
		if err := q.InsertUserAuthProvider(t.Context(), sqlcgen.InsertUserAuthProviderParams{
			ID:             pgtype.UUID{Bytes: uuid.New(), Valid: true},
			UserID:         pgtype.UUID{Bytes: id, Valid: true},
			ProviderName:   name,
			ProviderUserID: name + "-" + id.String(),
			CreatedAt:      oldStamp,
			UpdatedAt:      oldStamp,
		}); err != nil {
			t.Fatalf("連携 %s の行を足せません: %v", name, err)
		}
	}
	if err := q.InsertUserRole(t.Context(), sqlcgen.InsertUserRoleParams{UserID: pgtype.UUID{Bytes: id, Valid: true}, RoleName: "USER"}); err != nil {
		t.Fatalf("役割の行を足せません: %v", err)
	}
	return id
}

// loadUser は、利用者 id の行と連携と役割を読む。
func loadUser(t *testing.T, id uuid.UUID) auth.StoredUser {
	t.Helper()
	u, err := auth.LoadUser(t.Context(), sqlcgen.New(testPool), id, errors.New("利用者が居ない"))
	if err != nil {
		t.Fatalf("利用者 %s を読めません: %v", id, err)
	}
	return u
}

// providerNames は、利用者の連携の名前を、名前の順に並べて返す。
func providerNames(u auth.StoredUser) []string {
	names := make([]string, 0, len(u.Providers))
	for _, p := range u.Providers {
		names = append(names, p.ProviderName)
	}
	slices.Sort(names)
	return names
}

// providerService は、テストの Postgres につなぎ、今の時刻を testNow にした Service を作る。
func providerService() *Service {
	now := func() time.Time { return testNow }
	return New(Deps{Pool: testPool, Auth: auth.New(auth.Deps{Pool: testPool, Now: now}), Now: now})
}

// wantFieldError は、err が、項目 authProviders に文言 message だけを持つ 400 の入力の誤りかを確かめる。
func wantFieldError(t *testing.T, err error, message string) {
	t.Helper()
	var e *auth.Error
	if !errors.As(err, &e) {
		t.Fatalf("誤り = %v、期待 = 400 の入力の誤り", err)
	}
	want := map[string][]string{"authProviders": {message}}
	if e.Status != 400 || e.Message != auth.MessageInvalidInput || !reflect.DeepEqual(map[string][]string(e.Errors), want) || e.ClearSession {
		t.Errorf("誤り = %d %q %v Cookie を消す=%v、期待 = 400 %q %v", e.Status, e.Message, e.Errors, e.ClearSession, auth.MessageInvalidInput, want)
	}
}

// wantUnchanged は、利用者 id の行と連携と役割が before から変わっていないかを確かめる。
func wantUnchanged(t *testing.T, id uuid.UUID, before auth.StoredUser) {
	t.Helper()
	after := loadUser(t, id)
	if !reflect.DeepEqual(after, before) {
		t.Errorf("断ったのに行が変わった\n 前: %+v\n 後: %+v", before, after)
	}
}

func TestRemoveAuthProvider_LastProviderWithoutPassword(t *testing.T) {
	s := providerService()
	tests := []struct {
		name string
		row  userRow
	}{
		{"確認の済んだメールアドレスはあるがパスワードが無い", userRow{Email: someText("a@example.com"), EmailVerifiedAt: oldStamp}},
		{"パスワードはあるがメールアドレスの確認が済んでいない", userRow{Email: someText("a@example.com"), Password: someText("$2a$10$hash")}},
		{"パスワードはあるがメールアドレスが無い", userRow{Password: someText("$2a$10$hash")}},
		// 表の形に、メールアドレスが無ければ確認の日時も無いという決まりは無い。Java 版の User.isEmailVerified は、
		// メールアドレスが null なら、確認の日時があっても確認済みとしない。
		{"パスワードと確認の日時はあるがメールアドレスが無い", userRow{Password: someText("$2a$10$hash"), EmailVerifiedAt: oldStamp}},
		{"パスワードはあるがメールアドレスが設定待ちだけ", userRow{Password: someText("$2a$10$hash"), PendingEmail: someText("p@example.com")}},
		{"メールアドレスもパスワードも無い", userRow{}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			id := insertUser(t, tt.row, "google")
			before := loadUser(t, id)
			wantFieldError(t, s.RemoveAuthProvider(t.Context(), id, "google"), MessageProviderLastOne)
			wantUnchanged(t, id, before)
		})
	}

	t.Run("連携が2つあれば、パスワードが無くても1つを解除できる", func(t *testing.T) {
		id := insertUser(t, userRow{Email: someText("a@example.com"), EmailVerifiedAt: oldStamp}, "google", "github")
		if err := s.RemoveAuthProvider(t.Context(), id, "google"); err != nil {
			t.Fatalf("解除の誤り: %v", err)
		}
		if got := providerNames(loadUser(t, id)); !reflect.DeepEqual(got, []string{"github"}) {
			t.Errorf("残った連携 = %v、期待 = [github]", got)
		}
	})
}

func TestRemoveAuthProvider_NotLinked(t *testing.T) {
	s := providerService()
	tests := []struct {
		name     string
		row      userRow
		provider string
	}{
		{"連携していない提供元", userRow{Email: someText("a@example.com"), Password: someText("$2a$10$hash"), EmailVerifiedAt: oldStamp}, "github"},
		{"知らない提供元", userRow{Email: someText("a@example.com"), Password: someText("$2a$10$hash"), EmailVerifiedAt: oldStamp}, "twitter"},
		{"空の名前", userRow{Email: someText("a@example.com"), Password: someText("$2a$10$hash"), EmailVerifiedAt: oldStamp}, ""},
		// 連携していないときは、最後の1つの連携の文言を足さない(Java 版の if と else if)
		{"パスワードが無く、連携していない提供元", userRow{}, "github"},
		// ASCII でない字は小文字にしないので、連携が見つからない。Java 版も、İ を i と結合の点の2文字にし、全角の字は全角の小文字にする
		{"トルコ語の点の付いた I", userRow{Email: someText("a@example.com"), Password: someText("$2a$10$hash"), EmailVerifiedAt: oldStamp}, "G\u0130THUB"},
		{"全角の英大文字", userRow{Email: someText("a@example.com"), Password: someText("$2a$10$hash"), EmailVerifiedAt: oldStamp}, "\uff27\uff2f\uff2f\uff27\uff2c\uff25"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			linked := "google"
			if tt.provider == "G\u0130THUB" {
				linked = "github"
			}
			id := insertUser(t, tt.row, linked)
			before := loadUser(t, id)
			wantFieldError(t, s.RemoveAuthProvider(t.Context(), id, tt.provider), MessageProviderRemoveFailed)
			wantUnchanged(t, id, before)
		})
	}
}

func TestRemoveAuthProvider_UpperCaseName(t *testing.T) {
	s := providerService()
	for _, provider := range []string{"GOOGLE", "Google", "gOoGlE"} {
		t.Run(provider, func(t *testing.T) {
			id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("$2a$10$hash"), EmailVerifiedAt: oldStamp}, "google", "github")
			if err := s.RemoveAuthProvider(t.Context(), id, provider); err != nil {
				t.Fatalf("解除の誤り: %v", err)
			}
			if got := providerNames(loadUser(t, id)); !reflect.DeepEqual(got, []string{"github"}) {
				t.Errorf("残った連携 = %v、期待 = [github]", got)
			}
		})
	}
}

func TestRemoveAuthProvider_Success(t *testing.T) {
	s := providerService()

	t.Run("確認の済んだメールアドレスとパスワードがあれば、最後の1つの連携を解除できる", func(t *testing.T) {
		id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("$2a$10$hash"), EmailVerifiedAt: oldStamp}, "github")
		before := loadUser(t, id)
		if err := s.RemoveAuthProvider(t.Context(), id, "github"); err != nil {
			t.Fatalf("解除の誤り: %v", err)
		}
		after := loadUser(t, id)
		if len(after.Providers) != 0 {
			t.Errorf("残った連携 = %v、期待 = なし", providerNames(after))
		}
		// updated_at だけが今の時刻になり、ほかの列と役割は変わらない
		want := before
		want.Row.UpdatedAt = javaWallClock(testNow)
		want.Providers = after.Providers
		if !reflect.DeepEqual(after, want) {
			t.Errorf("解除したあとの行\n 得た: %+v\n 期待: %+v", after, want)
		}
	})

	t.Run("2つのうち1つを解除すると、もう1つの連携の行は変わらない", func(t *testing.T) {
		id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("$2a$10$hash"), EmailVerifiedAt: oldStamp}, "google", "github")
		before := loadUser(t, id)
		if err := s.RemoveAuthProvider(t.Context(), id, "github"); err != nil {
			t.Fatalf("解除の誤り: %v", err)
		}
		after := loadUser(t, id)
		var wantProviders []sqlcgen.InsertUserAuthProviderParams
		for _, p := range before.Providers {
			if p.ProviderName != "github" {
				wantProviders = append(wantProviders, p)
			}
		}
		if !reflect.DeepEqual(after.Providers, wantProviders) {
			t.Errorf("残った連携\n 得た: %+v\n 期待: %+v", after.Providers, wantProviders)
		}
		if after.Row.UpdatedAt != javaWallClock(testNow) {
			t.Errorf("updated_at = %v、期待 = %v", after.Row.UpdatedAt, javaWallClock(testNow))
		}
	})
}

func TestRemoveAuthProvider_UserGone(t *testing.T) {
	s := providerService()
	err := s.RemoveAuthProvider(t.Context(), uuid.New(), "google")
	var e *auth.Error
	if !errors.As(err, &e) {
		t.Fatalf("誤り = %v、期待 = 401 の誤り", err)
	}
	if e.Status != 401 || e.Message != MessageInvalidAccess || len(e.Errors) != 0 || !e.ClearSession {
		t.Errorf("誤り = %d %q %v Cookie を消す=%v、期待 = 401 %q {} Cookie を消す", e.Status, e.Message, e.Errors, e.ClearSession, MessageInvalidAccess)
	}
}
