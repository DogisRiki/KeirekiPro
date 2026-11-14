package users

import (
	"bytes"
	"errors"
	"io"
	"reflect"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// boolPtr は、b を指すポインタを返す。
func boolPtr(b bool) *bool { return &b }

// wantInputErrors は、err が、want の項目と文言だけを持つ 400 の入力の誤りかを確かめる。
func wantInputErrors(t *testing.T, err error, want map[string][]string) {
	t.Helper()
	var e *auth.Error
	if !errors.As(err, &e) {
		t.Fatalf("誤り = %v、期待 = 400 の入力の誤り %v", err, want)
	}
	if e.Status != 400 || e.Message != auth.MessageInvalidInput || !reflect.DeepEqual(map[string][]string(e.Errors), want) || e.ClearSession {
		t.Errorf("誤り = %d %q %v Cookie を消す=%v、期待 = 400 %q %v", e.Status, e.Message, e.Errors, e.ClearSession, auth.MessageInvalidInput, want)
	}
}

// storedObject は、偽の AWS の置き場所から、名前 key の画像の中身と Content-Type を読む。画像が無ければ ok を偽にする。
func storedObject(t *testing.T, key string) (content []byte, contentType string, ok bool) {
	t.Helper()
	out, err := newTestS3(t).GetObject(t.Context(), &s3.GetObjectInput{Bucket: aws.String(testBucket), Key: aws.String(key)})
	if err != nil {
		var missing *types.NoSuchKey
		if errors.As(err, &missing) {
			return nil, "", false
		}
		t.Fatalf("画像 %s を読めません: %v", key, err)
	}
	body, err := io.ReadAll(out.Body)
	_ = out.Body.Close()
	if err != nil {
		t.Fatalf("画像 %s の中身を読めません: %v", key, err)
	}
	return body, aws.ToString(out.ContentType), true
}

// imageKeyOf は、利用者 id の画像を拡張子 ext で置いたときの名前である。期待の値は、処理の側の関数に頼らずに組み立てる。
func imageKeyOf(id uuid.UUID, ext string) string {
	return "/profile/image/" + id.String() + "." + ext
}

// adminUser は、確認の済んだメールアドレスとパスワードを持ち、2段階認証を使う設定の、役割 ADMIN の利用者を作る。
func adminUser(t *testing.T) uuid.UUID {
	t.Helper()
	id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("hash"), EmailVerifiedAt: oldStamp})
	changeUser(t, id, func(u *auth.StoredUser) { u.Row.TwoFactorAuthEnabled = true })
	if err := sqlcgen.New(testPool).InsertUserRole(t.Context(), sqlcgen.InsertUserRoleParams{
		UserID: pgtype.UUID{Bytes: id, Valid: true}, RoleName: "ADMIN",
	}); err != nil {
		t.Fatalf("役割の行を足せません: %v", err)
	}
	return id
}

func TestUpdateUserInfo_AdminCannotDisable2FA(t *testing.T) {
	s := userInfoService(t)

	t.Run("管理者が使わない設定にする", func(t *testing.T) {
		id := adminUser(t)
		before := loadUser(t, id)
		err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, TwoFactorAuthEnabled: boolPtr(false)})
		wantInputErrors(t, err, map[string][]string{"twoFactorAuthEnabled": {MessageAdminTwoFactorRequired}})
		wantUnchanged(t, id, before)
	})

	t.Run("管理者が名前を変えて使わない設定にする", func(t *testing.T) {
		id := adminUser(t)
		before := loadUser(t, id)
		err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, Username: strPtr("佐藤"), TwoFactorAuthEnabled: boolPtr(false)})
		wantInputErrors(t, err, map[string][]string{"twoFactorAuthEnabled": {MessageAdminTwoFactorRequired}})
		wantUnchanged(t, id, before)
	})

	t.Run("管理者が使う設定のままにする", func(t *testing.T) {
		id := adminUser(t)
		if err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, TwoFactorAuthEnabled: boolPtr(true)}); err != nil {
			t.Fatalf("UpdateUserInfo: %v", err)
		}
		after := loadUser(t, id)
		if !after.Row.TwoFactorAuthEnabled {
			t.Error("2段階認証の設定 = 使わない、期待 = 使う")
		}
		// Java 版の changeTwoFactorAuthEnabled は、値が変わらなくても updated_at を今の時刻にする。
		if after.Row.UpdatedAt != javaWallClock(testNow) {
			t.Errorf("updated_at = %v、期待 = %v", after.Row.UpdatedAt, javaWallClock(testNow))
		}
	})
}

func TestUpdateUserInfo_Enable2FARequiresEmailAndPassword(t *testing.T) {
	s := userInfoService(t)
	refused := []struct {
		name string
		row  userRow
	}{
		{"確認の済んだメールアドレスはあるがパスワードが無い", userRow{Email: someText("a@example.com"), EmailVerifiedAt: oldStamp}},
		{"パスワードはあるがメールアドレスの確認が済んでいない", userRow{Email: someText("a@example.com"), Password: someText("hash")}},
		{"パスワードと確認の日時はあるがメールアドレスが無い", userRow{Password: someText("hash"), EmailVerifiedAt: oldStamp}},
		{"パスワードはあるがメールアドレスが設定待ちだけ", userRow{Password: someText("hash"), PendingEmail: someText(uuid.NewString() + "@example.com")}},
		{"メールアドレスもパスワードも無い", userRow{}},
	}
	for _, tt := range refused {
		t.Run(tt.name, func(t *testing.T) {
			id := insertUser(t, tt.row, "google")
			before := loadUser(t, id)
			err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, TwoFactorAuthEnabled: boolPtr(true)})
			wantInputErrors(t, err, map[string][]string{"twoFactorAuthEnabled": {MessageTwoFactorPrerequisiteMissing}})
			wantUnchanged(t, id, before)
		})
	}

	t.Run("確認の済んだメールアドレスとパスワードがある", func(t *testing.T) {
		id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("hash"), EmailVerifiedAt: oldStamp})
		if err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, TwoFactorAuthEnabled: boolPtr(true)}); err != nil {
			t.Fatalf("UpdateUserInfo: %v", err)
		}
		after := loadUser(t, id)
		if !after.Row.TwoFactorAuthEnabled || after.Row.UpdatedAt != javaWallClock(testNow) {
			t.Errorf("2段階認証 = %v updated_at = %v、期待 = 使う %v", after.Row.TwoFactorAuthEnabled, after.Row.UpdatedAt, javaWallClock(testNow))
		}
	})

	t.Run("メールアドレスもパスワードも無い利用者が使わない設定にする", func(t *testing.T) {
		id := insertUser(t, userRow{}, "google")
		if err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, TwoFactorAuthEnabled: boolPtr(false)}); err != nil {
			t.Fatalf("UpdateUserInfo: %v", err)
		}
		after := loadUser(t, id)
		if after.Row.TwoFactorAuthEnabled || after.Row.UpdatedAt != javaWallClock(testNow) {
			t.Errorf("2段階認証 = %v updated_at = %v、期待 = 使わない %v", after.Row.TwoFactorAuthEnabled, after.Row.UpdatedAt, javaWallClock(testNow))
		}
	})
}

func TestUpdateUserInfo_ReplaceImage(t *testing.T) {
	s := userInfoService(t)
	png := pngBytes(t, 1, 1)
	tests := []struct {
		name  string
		image ImageInput
		ext   string
	}{
		// Java 版の getExtension と同じく、拡張子を小文字にした名前で置く。
		{"PNG", ImageInput{FileName: "顔.PNG", ContentType: "image/png", Content: png}, "png"},
		{"JPEG", ImageInput{FileName: "a.b.jpeg", ContentType: "image/jpeg", Content: sampleImage(t, "small.jpg")}, "jpeg"},
		{"GIF", ImageInput{FileName: "a.gif", ContentType: "image/gif", Content: sampleImage(t, "small.gif")}, "gif"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("hash")})
			image := tt.image
			if err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, ProfileImage: &image}); err != nil {
				t.Fatalf("UpdateUserInfo: %v", err)
			}
			key := imageKeyOf(id, tt.ext)
			content, contentType, ok := storedObject(t, key)
			if !ok {
				t.Fatalf("画像 %s が置かれていない", key)
			}
			if !bytes.Equal(content, tt.image.Content) || contentType != tt.image.ContentType {
				t.Errorf("置いた画像 = %d バイト %q、期待 = %d バイト %q", len(content), contentType, len(tt.image.Content), tt.image.ContentType)
			}
			after := loadUser(t, id)
			if after.Row.ProfileImage != someText(key) {
				t.Errorf("画像の名前 = %v、期待 = %q", after.Row.ProfileImage, key)
			}
			if after.Row.UpdatedAt != javaWallClock(testNow) {
				t.Errorf("updated_at = %v、期待 = %v", after.Row.UpdatedAt, javaWallClock(testNow))
			}
			// 名前は送っていないので変えない。
			if after.Row.Username != someText("山田太郎") {
				t.Errorf("名前 = %v、期待 = 山田太郎", after.Row.Username)
			}
		})
	}

	t.Run("中身の空の画像は置かない", func(t *testing.T) {
		id := insertUser(t, userRow{Email: someText("a@example.com"), Password: someText("hash")})
		before := loadUser(t, id)
		// Java 版の ProfileImageCommand.isEmpty と同じく、中身が空なら、形式も拡張子も検査せず、画像が無いものとして扱う。
		image := ImageInput{FileName: "a.txt", ContentType: "text/plain"}
		if err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, ProfileImage: &image}); err != nil {
			t.Fatalf("UpdateUserInfo: %v", err)
		}
		if _, _, ok := storedObject(t, "/profile/image/"+id.String()+".txt"); ok {
			t.Error("中身の空の画像が置かれた")
		}
		wantUnchanged(t, id, before)
	})
}

func TestUpdateUserInfo_ImageKeptOnUsernameError(t *testing.T) {
	s := userInfoService(t)
	id := insertUser(t, userRow{})
	before := loadUser(t, id)
	image := validPNG(t)

	// 名前の誤りは、2段階認証の設定を確かめる前に処理を止める。2段階認証を使う設定にできない利用者でも、名前の文言だけを返す。
	err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, Username: strPtr(" 　"), ProfileImage: &image, TwoFactorAuthEnabled: boolPtr(true)})
	wantInputErrors(t, err, map[string][]string{"username": {MessageUsernameRequired}})

	// Java 版と同じく、置いた画像を消さない。利用者の行は変わらない。
	key := imageKeyOf(id, "png")
	if content, _, ok := storedObject(t, key); !ok || !bytes.Equal(content, image.Content) {
		t.Errorf("画像 %s が残っていない(ある = %v)", key, ok)
	}
	wantUnchanged(t, id, before)
}

func TestUpdateUserInfo_Username(t *testing.T) {
	s := userInfoService(t)

	t.Run("前後の空白を除いて保存する", func(t *testing.T) {
		id := insertUser(t, userRow{})
		if err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, Username: strPtr("\t佐藤 花子　")}); err != nil {
			t.Fatalf("UpdateUserInfo: %v", err)
		}
		after := loadUser(t, id)
		if after.Row.Username != someText("佐藤 花子") || after.Row.UpdatedAt != javaWallClock(testNow) {
			t.Errorf("名前 = %v updated_at = %v、期待 = \"佐藤 花子\" %v", after.Row.Username, after.Row.UpdatedAt, javaWallClock(testNow))
		}
	})

	t.Run("同じ名前なら変えない", func(t *testing.T) {
		id := insertUser(t, userRow{})
		before := loadUser(t, id)
		// Java 版の changeUsername は、空白を除いた名前が今の名前と同じなら、updated_at も変えない。
		if err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, Username: strPtr(" 山田太郎 ")}); err != nil {
			t.Fatalf("UpdateUserInfo: %v", err)
		}
		wantUnchanged(t, id, before)
	})

	t.Run("名前の無い利用者に名前を付ける", func(t *testing.T) {
		id := insertUser(t, userRow{})
		changeUser(t, id, func(u *auth.StoredUser) { u.Row.Username = pgtype.Text{} })
		if err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, Username: strPtr("山田太郎")}); err != nil {
			t.Fatalf("UpdateUserInfo: %v", err)
		}
		after := loadUser(t, id)
		if after.Row.Username != someText("山田太郎") || after.Row.UpdatedAt != javaWallClock(testNow) {
			t.Errorf("名前 = %v updated_at = %v、期待 = 山田太郎 %v", after.Row.Username, after.Row.UpdatedAt, javaWallClock(testNow))
		}
	})

	t.Run("長すぎる名前", func(t *testing.T) {
		id := insertUser(t, userRow{})
		before := loadUser(t, id)
		long := string(bytes.Repeat([]byte("a"), 51))
		err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, Username: &long})
		wantInputErrors(t, err, map[string][]string{"username": {MessageUsernameTooLong}})
		wantUnchanged(t, id, before)
	})

	t.Run("何も送らない", func(t *testing.T) {
		id := insertUser(t, userRow{})
		before := loadUser(t, id)
		if err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id}); err != nil {
			t.Fatalf("UpdateUserInfo: %v", err)
		}
		wantUnchanged(t, id, before)
	})
}

func TestUpdateUserInfo_InvalidImage(t *testing.T) {
	s := userInfoService(t)
	id := insertUser(t, userRow{})
	before := loadUser(t, id)
	// 形式と拡張子と中身の誤りを、すべて集めて返す。
	image := ImageInput{FileName: "a.bmp", ContentType: "image/bmp", Content: []byte("BM not an image")}
	err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, Username: strPtr("佐藤"), ProfileImage: &image})
	wantInputErrors(t, err, map[string][]string{"profileImage": {MessageImageTypeNotAllowed, MessageImageExtensionNotAllowed, MessageImageInvalid}})
	if _, _, ok := storedObject(t, imageKeyOf(id, "bmp")); ok {
		t.Error("誤りのある画像が置かれた")
	}
	wantUnchanged(t, id, before)
}

func TestUpdateUserInfo_UserGone(t *testing.T) {
	s := userInfoService(t)

	t.Run("正しい要求", func(t *testing.T) {
		id := uuid.New()
		image := validPNG(t)
		err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, Username: strPtr("佐藤"), ProfileImage: &image, TwoFactorAuthEnabled: boolPtr(false)})
		var ae *auth.Error
		if !errors.As(err, &ae) {
			t.Fatalf("誤り = %v、期待 = 401 の誤り", err)
		}
		if ae.Status != 401 || ae.Message != MessageInvalidAccess || len(ae.Errors) != 0 || !ae.ClearSession {
			t.Errorf("誤り = %d %q %v Cookie を消す=%v、期待 = 401 %q {} Cookie を消す", ae.Status, ae.Message, ae.Errors, ae.ClearSession, MessageInvalidAccess)
		}
		// Java 版は、利用者を読んでから画像を置くので、居ない利用者の画像を置かない。
		if _, _, ok := storedObject(t, imageKeyOf(id, "png")); ok {
			t.Error("居ない利用者の画像が置かれた")
		}
	})

	t.Run("誤りのある画像", func(t *testing.T) {
		// Java 版は、利用者を読む前に画像を検査するので、居ない利用者でも画像の誤りの 400 を返す。
		image := ImageInput{FileName: "a.png", ContentType: "image/png", Content: []byte("not an image")}
		err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: uuid.New(), ProfileImage: &image})
		wantInputErrors(t, err, map[string][]string{"profileImage": {MessageImageInvalid}})
	})
}

func TestUpdateUserInfo_PutFails(t *testing.T) {
	putErr := errors.New("置き場所に書けない")
	s := New(Deps{Pool: testPool, S3: &fakeS3{err: putErr}, Bucket: testBucket, Now: func() time.Time { return testNow }})
	id := insertUser(t, userRow{})
	before := loadUser(t, id)
	image := validPNG(t)

	// 画像を置けなければ、その誤りを返し、利用者の行を書かない。受け口は 500 で答える。
	err := s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, Username: strPtr("佐藤"), ProfileImage: &image})
	if !errors.Is(err, putErr) {
		t.Errorf("誤り = %v、期待 = 置き場所の誤りを包んだ誤り", err)
	}
	var ae *auth.Error
	if errors.As(err, &ae) {
		t.Errorf("誤り = %d %q、期待 = 500 にする誤り(*auth.Error でない誤り)", ae.Status, ae.Message)
	}
	wantUnchanged(t, id, before)
}
