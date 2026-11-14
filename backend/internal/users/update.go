package users

import (
	"context"
	"slices"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// 名前と画像の決まりである。どれも Java 版の User と ProfileImageKeys の値を写した。
const (
	// usernameMaxLength は、前後の空白を除いた名前の長さの上限である。Java 版の String.length と同じく、UTF-16 の単位で数える。
	usernameMaxLength = 50
	// profileImagePrefix は、画像の名前の前に付ける文字列である(ProfileImageKeys.PREFIX)。
	profileImagePrefix = "/profile/image/"
)

// UpdateInput は、名前と画像と2段階認証の設定の変更の要求である。nil の項目は、要求に無かった項目で、変えない。
type UpdateInput struct {
	// UserID は、ログインしている利用者の ID である。
	UserID uuid.UUID
	// Username は、新しい名前である。
	Username *string
	// ProfileImage は、新しい画像である。中身が空の画像は、画像が無いものとして扱う。
	ProfileImage *ImageInput
	// TwoFactorAuthEnabled は、2段階認証を使うかどうかの新しい設定である。
	TwoFactorAuthEnabled *bool
}

// UpdateUserInfo は、Java 版の UpdateUserInfoUseCase と、User の changeUsername changeProfileImage
// changeTwoFactorAuthEnabled と同じ順で、利用者の名前と画像と2段階認証の設定を変える。
//  1. 画像があれば検査し、誤りがあれば、項目 profileImage の文言をすべて付けた 400 を返す
//  2. 利用者を読む。居なければ、Cookie を消させる 401 の誤りを返す
//  3. 画像があれば、/profile/image/<利用者の ID>.<拡張子> の名前で置く
//  4. 名前があれば、前後の空白を除いて確かめ、誤りがあれば、項目 username の文言を付けた 400 を返す。
//     今の名前と同じなら変えない
//  5. 画像を置いたなら、画像の名前を置いた名前にする
//  6. 2段階認証の設定があれば、変えられるかを確かめ、変えられなければ、項目 twoFactorAuthEnabled の文言を付けた 400 を返す
//  7. 利用者の行を書く
//
// 名前と2段階認証の設定の誤りは、見つけた時点で処理を止める。Java 版の User の変更の決まりが、その時点で例外を投げるためである。
// 置いたあとで断るときも、置いた画像を消さない。Java 版も消さない。
// Java 版のユースケースはトランザクションを持たないので、利用者の行の読み書きはトランザクションの外で行う。
func (s *Service) UpdateUserInfo(ctx context.Context, in UpdateInput) error {
	image := in.ProfileImage
	if image != nil && len(image.Content) == 0 {
		image = nil
	}
	if image != nil {
		if messages := checkImage(*image); len(messages) > 0 {
			f := auth.FieldErrors{}
			for _, m := range messages {
				f.Check("profileImage", false, m)
			}
			return f.Result()
		}
	}

	q := sqlcgen.New(s.deps.Pool)
	u, err := auth.LoadUser(ctx, q, in.UserID, auth.ErrCredentialsNotFound(MessageInvalidAccess))
	if err != nil {
		return err
	}

	var imageKey string
	if image != nil {
		imageKey = profileImageKey(in.UserID, imageExtension(image.FileName))
		if err := s.put(ctx, imageKey, image.Content, image.ContentType); err != nil {
			return err
		}
	}

	if in.Username != nil {
		name, message := normalizeUsername(*in.Username)
		if message != "" {
			f := auth.FieldErrors{}
			f.Check("username", false, message)
			return f.Result()
		}
		// Java 版の changeUsername は、今の名前と同じなら、updated_at も変えずに同じ利用者を返す。
		if !u.Row.Username.Valid || u.Row.Username.String != name {
			u.Row.Username = pgtype.Text{String: name, Valid: true}
			u.Row.UpdatedAt = s.javaNow()
		}
	}

	if image != nil {
		u.Row.ProfileImage = pgtype.Text{String: imageKey, Valid: true}
		u.Row.UpdatedAt = s.javaNow()
	}

	if in.TwoFactorAuthEnabled != nil {
		enabled := *in.TwoFactorAuthEnabled
		f := auth.FieldErrors{}
		// 2つの条件は、一方が使わない設定、もう一方が使う設定のときに当たるので、同時には当たらない。
		f.Check("twoFactorAuthEnabled", !isAdmin(u) || enabled, MessageAdminTwoFactorRequired)
		f.Check("twoFactorAuthEnabled", !enabled || (emailVerified(u) && u.Row.Password.Valid), MessageTwoFactorPrerequisiteMissing)
		if e := f.Result(); e != nil {
			return e
		}
		// Java 版の changeTwoFactorAuthEnabled は、設定が変わらなくても updated_at を今の時刻にする。
		u.Row.TwoFactorAuthEnabled = enabled
		u.Row.UpdatedAt = s.javaNow()
	}

	return auth.SaveUser(ctx, q, u)
}

// normalizeUsername は、Java 版の User.changeUsername と同じく、名前の前後から Java の String.strip() が取り除く空白を除き、
// 除いた名前を返す。除いた名前が空か、UTF-16 の単位で50を超えるときは、項目 username の文言を返す。誤りが無ければ文言は空にする。
func normalizeUsername(name string) (string, string) {
	stripped := strings.TrimFunc(name, auth.IsJavaWhitespace)
	switch {
	case stripped == "":
		return "", MessageUsernameRequired
	case auth.UTF16Len(stripped) > usernameMaxLength:
		return "", MessageUsernameTooLong
	}
	return stripped, ""
}

// profileImageKey は、Java 版の ProfileImageKeys の PREFIX と fileName と同じく、利用者 id の画像の名前を作る。
// 拡張子が空か空白だけなら、. も付けない(String.isBlank)。
func profileImageKey(id uuid.UUID, ext string) string {
	if strings.TrimFunc(ext, auth.IsJavaWhitespace) == "" {
		return profileImagePrefix + id.String()
	}
	return profileImagePrefix + id.String() + "." + ext
}

// isAdmin は、Java 版の User.isAdmin と同じく、利用者が役割 ADMIN を持つかを返す。
func isAdmin(u auth.StoredUser) bool {
	return slices.Contains(u.Roles, "ADMIN")
}
