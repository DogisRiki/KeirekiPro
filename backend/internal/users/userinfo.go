package users

import (
	"context"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// profileImageURLLifetime は、利用者の情報の画像の署名付きの URL を使える時間である。
// Java 版の GetUserInfoUseCase の Duration.ofMinutes(10) と同じ600秒にする。
const profileImageURLLifetime = 10 * time.Minute

// UserInfo は、Java 版の UserInfoResponse と同じ10の項目を、同じ順で持つ利用者の情報である。
// 無い値は nil にする。応答の本文では null になる。
type UserInfo struct {
	// ID は、利用者の ID である。
	ID uuid.UUID
	// Email は、メールアドレスである。
	Email *string
	// Username は、名前である。
	Username *string
	// HasPassword は、パスワードのハッシュがあるかどうかである。
	HasPassword bool
	// ProfileImage は、画像の名前の署名付きの URL である。
	ProfileImage *string
	// TwoFactorAuthEnabled は、2段階認証を使うかどうかである。
	TwoFactorAuthEnabled bool
	// AuthProviders は、連携している提供元の名前を、名前の順に並べたものである。連携が無ければ空の並びにする。
	AuthProviders []string
	// Roles は、役割の名前を、名前の順に並べたものである。役割が無ければ空の並びにする。
	Roles []string
	// EmailVerified は、メールアドレスの確認が済んでいるかどうかである。
	EmailVerified bool
	// PendingEmail は、設定待ちのメールアドレスである。
	PendingEmail *string
}

// GetUserInfo は、Java 版の GetUserInfoUseCase と UserInfoResponse.convertToResponse と同じく、利用者 userID の情報を返す。
//   - 利用者が居なければ、Cookie を消させる 401 の誤りを返す
//   - 画像があれば、その名前の、600秒の間使える署名付きの URL を作る。作れなければ、その誤りを返す
//   - 連携の名前と役割の名前は、名前の順に並べる。Java 版の並びは HashMap と Set の順で、決まった順を持たない
//
// Java 版のユースケースはトランザクションを持たないので、利用者の行はトランザクションの外で読む。
func (s *Service) GetUserInfo(ctx context.Context, userID uuid.UUID) (UserInfo, error) {
	u, err := auth.LoadUser(ctx, sqlcgen.New(s.deps.Pool), userID, auth.ErrCredentialsNotFound(MessageInvalidAccess))
	if err != nil {
		return UserInfo{}, err
	}

	var image *string
	if u.Row.ProfileImage.Valid {
		signed, err := s.presign(ctx, u.Row.ProfileImage.String, profileImageURLLifetime)
		if err != nil {
			return UserInfo{}, err
		}
		image = &signed
	}

	providers := make([]string, 0, len(u.Providers))
	for _, p := range u.Providers {
		providers = append(providers, p.ProviderName)
	}
	slices.Sort(providers)
	roles := append(make([]string, 0, len(u.Roles)), u.Roles...)
	slices.Sort(roles)

	return UserInfo{
		ID:                   u.Row.ID.Bytes,
		Email:                textPointer(u.Row.Email),
		Username:             textPointer(u.Row.Username),
		HasPassword:          u.Row.Password.Valid,
		ProfileImage:         image,
		TwoFactorAuthEnabled: u.Row.TwoFactorAuthEnabled,
		AuthProviders:        providers,
		Roles:                roles,
		EmailVerified:        emailVerified(u),
		PendingEmail:         textPointer(u.Row.PendingEmail),
	}, nil
}

// textPointer は、値のある文字の列の値を指すポインタを返す。値が無ければ nil を返す。
func textPointer(t pgtype.Text) *string {
	if !t.Valid {
		return nil
	}
	return &t.String
}
