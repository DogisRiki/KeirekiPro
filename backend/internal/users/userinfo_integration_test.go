package users

import (
	"errors"
	"net/url"
	"reflect"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// testProfileImage は、insertUser が利用者の行に入れる画像の名前である。
const testProfileImage = "/profile/image/a.png"

// userInfoService は、テストの Postgres と偽の AWS につなぎ、今の時刻を testNow にした Service を作る。
func userInfoService(t *testing.T) *Service {
	t.Helper()
	return New(Deps{
		Pool:        testPool,
		S3:          newTestS3(t),
		Bucket:      testBucket,
		AWSEndpoint: testAWSEndpoint,
		Now:         func() time.Time { return testNow },
	})
}

// changeUser は、利用者 id の行と連携と役割を読み、change で変えてから書き戻す。
func changeUser(t *testing.T, id uuid.UUID, change func(u *auth.StoredUser)) {
	t.Helper()
	u := loadUser(t, id)
	change(&u)
	if err := auth.SaveUser(t.Context(), sqlcgen.New(testPool), u); err != nil {
		t.Fatalf("利用者 %s を書けません: %v", id, err)
	}
}

// providerOrder は、利用者の連携の名前を、データベースから読んだ順のまま返す。
func providerOrder(u auth.StoredUser) []string {
	names := make([]string, 0, len(u.Providers))
	for _, p := range u.Providers {
		names = append(names, p.ProviderName)
	}
	return names
}

// strPtr は、s を指すポインタを返す。
func strPtr(s string) *string { return &s }

// wantUserInfo は、GetUserInfo の答えが want と同じかを確かめる。
func wantUserInfo(t *testing.T, got, want UserInfo) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Errorf("利用者の情報\n 得た値: %s\n 期待:   %s", describeUserInfo(got), describeUserInfo(want))
	}
}

// describeUserInfo は、ポインタの指す値まで読める形で、利用者の情報を文字にする。
func describeUserInfo(u UserInfo) string {
	text := func(p *string) string {
		if p == nil {
			return "null"
		}
		return "\"" + *p + "\""
	}
	return "id=" + u.ID.String() +
		" email=" + text(u.Email) +
		" username=" + text(u.Username) +
		" hasPassword=" + boolText(u.HasPassword) +
		" profileImage=" + text(u.ProfileImage) +
		" twoFactorAuthEnabled=" + boolText(u.TwoFactorAuthEnabled) +
		" authProviders=" + sliceText(u.AuthProviders) +
		" roles=" + sliceText(u.Roles) +
		" emailVerified=" + boolText(u.EmailVerified) +
		" pendingEmail=" + text(u.PendingEmail)
}

func boolText(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

// sliceText は、nil の並びを null と、空の並びを [] と書き分ける。
func sliceText(s []string) string {
	if s == nil {
		return "null"
	}
	out := "["
	for i, v := range s {
		if i > 0 {
			out += ","
		}
		out += v
	}
	return out + "]"
}

func TestGetUserInfo_Fields(t *testing.T) {
	s := userInfoService(t)
	imageURL, err := s.presign(t.Context(), testProfileImage, 600*time.Second)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}

	cases := []struct {
		name string
		// make は、利用者の行を作り、利用者の ID と、期待する答えを返す。
		make func(t *testing.T) (uuid.UUID, UserInfo)
	}{
		{"すべての項目がある", func(t *testing.T) (uuid.UUID, UserInfo) {
			pending := uuid.NewString() + "@example.com"
			id := insertUser(t, userRow{
				Email:           someText("a@example.com"),
				Password:        someText("hash"),
				EmailVerifiedAt: oldStamp,
				PendingEmail:    someText(pending),
			}, "google")
			changeUser(t, id, func(u *auth.StoredUser) { u.Row.TwoFactorAuthEnabled = true })
			return id, UserInfo{
				ID:                   id,
				Email:                strPtr(id.String() + "-a@example.com"),
				Username:             strPtr("山田太郎"),
				HasPassword:          true,
				ProfileImage:         &imageURL,
				TwoFactorAuthEnabled: true,
				AuthProviders:        []string{"google"},
				Roles:                []string{"USER"},
				EmailVerified:        true,
				PendingEmail:         &pending,
			}
		}},
		{"メールアドレスもパスワードも名前も画像も無い", func(t *testing.T) (uuid.UUID, UserInfo) {
			id := insertUser(t, userRow{}, "github")
			changeUser(t, id, func(u *auth.StoredUser) {
				u.Row.Username = pgtype.Text{}
				u.Row.ProfileImage = pgtype.Text{}
			})
			return id, UserInfo{
				ID:            id,
				AuthProviders: []string{"github"},
				Roles:         []string{"USER"},
			}
		}},
		{"メールアドレスの確認が済んでいない", func(t *testing.T) (uuid.UUID, UserInfo) {
			id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("hash")})
			return id, UserInfo{
				ID:            id,
				Email:         strPtr(id.String() + "-a@example.com"),
				Username:      strPtr("山田太郎"),
				HasPassword:   true,
				ProfileImage:  &imageURL,
				AuthProviders: []string{},
				Roles:         []string{"USER"},
			}
		}},
		{"確認の日時はあるがメールアドレスが無い", func(t *testing.T) (uuid.UUID, UserInfo) {
			id := insertUser(t, userRow{EmailVerifiedAt: oldStamp}, "google")
			return id, UserInfo{
				ID:            id,
				Username:      strPtr("山田太郎"),
				ProfileImage:  &imageURL,
				AuthProviders: []string{"google"},
				Roles:         []string{"USER"},
			}
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			id, want := tc.make(t)
			got, err := s.GetUserInfo(t.Context(), id)
			if err != nil {
				t.Fatalf("GetUserInfo: %v", err)
			}
			wantUserInfo(t, got, want)
		})
	}
}

func TestGetUserInfo_NoImageIsNull(t *testing.T) {
	// 資格情報の無い S3 のクライアントでは、署名付きの URL を作ろうとすると誤りになる。誤りにならなければ、
	// 画像の無い利用者には URL を作らないことが分かる。
	s := New(Deps{
		Pool:   testPool,
		S3:     &fakeS3{opts: s3.Options{Region: testRegion}},
		Bucket: testBucket,
		Now:    func() time.Time { return testNow },
	})
	id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("hash")})
	changeUser(t, id, func(u *auth.StoredUser) { u.Row.ProfileImage = pgtype.Text{} })

	got, err := s.GetUserInfo(t.Context(), id)
	if err != nil {
		t.Fatalf("GetUserInfo: %v", err)
	}
	if got.ProfileImage != nil {
		t.Errorf("profileImage = %q、期待 = null", *got.ProfileImage)
	}
}

func TestGetUserInfo_PresignFails(t *testing.T) {
	s := New(Deps{
		Pool:   testPool,
		S3:     &fakeS3{opts: s3.Options{Region: testRegion}},
		Bucket: testBucket,
		Now:    func() time.Time { return testNow },
	})
	id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("hash")})

	got, err := s.GetUserInfo(t.Context(), id)
	if err == nil {
		t.Fatalf("誤り = nil、期待 = 署名付きの URL を作れない誤り。答え: %s", describeUserInfo(got))
	}
	var ae *auth.Error
	if errors.As(err, &ae) {
		t.Errorf("誤り = %d %q、期待 = 500 にする誤り(*auth.Error でない誤り)", ae.Status, ae.Message)
	}
}

func TestGetUserInfo_SortedProvidersAndRoles(t *testing.T) {
	s := userInfoService(t)
	// 名前の順と逆の順で行を足す。
	id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("hash"), EmailVerifiedAt: oldStamp}, "google", "github")
	// 管理者は2段階認証を使わない設定にできないので、役割 ADMIN を足す前に、2段階認証を使う設定にする。
	changeUser(t, id, func(u *auth.StoredUser) { u.Row.TwoFactorAuthEnabled = true })
	if err := sqlcgen.New(testPool).InsertUserRole(t.Context(), sqlcgen.InsertUserRoleParams{
		UserID: pgtype.UUID{Bytes: id, Valid: true}, RoleName: "ADMIN",
	}); err != nil {
		t.Fatalf("役割の行を足せません: %v", err)
	}
	// データベースは並びの順を決めない(問い合わせに ORDER BY が無い)。読んだ順を記録に残し、並べ直しを確かめた順が
	// 名前の順と逆だったかを、失敗したときに読めるようにする。
	stored := loadUser(t, id)
	t.Logf("データベースから読んだ順: 連携 %v、役割 %v", providerOrder(stored), stored.Roles)

	got, err := s.GetUserInfo(t.Context(), id)
	if err != nil {
		t.Fatalf("GetUserInfo: %v", err)
	}
	if !reflect.DeepEqual(got.AuthProviders, []string{"github", "google"}) {
		t.Errorf("authProviders = %v、期待 = [github google]", got.AuthProviders)
	}
	if !reflect.DeepEqual(got.Roles, []string{"ADMIN", "USER"}) {
		t.Errorf("roles = %v、期待 = [ADMIN USER]", got.Roles)
	}
}

func TestGetUserInfo_PresignExpires600(t *testing.T) {
	s := userInfoService(t)
	id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("hash")})

	got, err := s.GetUserInfo(t.Context(), id)
	if err != nil {
		t.Fatalf("GetUserInfo: %v", err)
	}
	if got.ProfileImage == nil {
		t.Fatal("profileImage = null、期待 = 署名付きの URL")
	}
	u, err := url.Parse(*got.ProfileImage)
	if err != nil {
		t.Fatalf("URL を読めません: %v", err)
	}
	if want := "/" + testBucket + "/" + testProfileImage; u.Path != want {
		t.Errorf("URL のパス = %q、期待 = %q", u.Path, want)
	}
	q := u.Query()
	if q.Get("X-Amz-Expires") != "600" {
		t.Errorf("X-Amz-Expires = %q、期待 = 600", q.Get("X-Amz-Expires"))
	}
	if want := testNow.UTC().Format("20060102T150405Z"); q.Get("X-Amz-Date") != want {
		t.Errorf("X-Amz-Date = %q、期待 = %q", q.Get("X-Amz-Date"), want)
	}
	if q.Get("X-Amz-Signature") == "" {
		t.Error("X-Amz-Signature が無い")
	}
}

func TestGetUserInfo_UserGone(t *testing.T) {
	_, err := userInfoService(t).GetUserInfo(t.Context(), uuid.New())
	var ae *auth.Error
	if !errors.As(err, &ae) {
		t.Fatalf("誤り = %v、期待 = 401 の誤り", err)
	}
	if ae.Status != 401 || ae.Message != MessageInvalidAccess || len(ae.Errors) != 0 || !ae.ClearSession {
		t.Errorf("誤り = %d %q %v Cookie を消す=%v、期待 = 401 %q {} Cookie を消す", ae.Status, ae.Message, ae.Errors, ae.ClearSession, MessageInvalidAccess)
	}
}
