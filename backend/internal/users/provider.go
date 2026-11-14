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

// javaZone は、Java 版のコンテナの時間帯(Asia/Tokyo)である。Java 版は updated_at を、LocalDateTime.now() で、
// この時間帯の時刻の見た目で書く。認証の spec の javaZone と同じ値である。
var javaZone = time.FixedZone("Asia/Tokyo", 9*3600)

// javaNow は、Java 版が LocalDateTime.now() で updated_at に書く値と同じ見た目の、今の時刻を返す。
func (s *Service) javaNow() pgtype.Timestamp {
	return pgtype.Timestamp{Time: s.deps.Now().In(javaZone), Valid: true}
}

// RemoveAuthProvider は、Java 版の RemoveAuthProviderUseCase と User.removeAuthProvider と同じく、利用者 userID の、
// 提供元 provider との連携を解除する。
//   - 利用者が居なければ、Cookie を消させる 401 の誤りを返す
//   - provider を小文字にした名前の連携が無ければ、項目 authProviders に「連携の解除に失敗しました。」を付けた 400 を返す
//   - 確認の済んだメールアドレスかパスワードが無く、連携が1つだけなら、項目 authProviders に
//     「メールアドレスとパスワードが設定済みでないと、連携を解除できません。」を付けた 400 を返す
//
// どちらでもなければ、連携を除き、updated_at を今の時刻にした利用者の行を書く。
func (s *Service) RemoveAuthProvider(ctx context.Context, userID uuid.UUID, provider string) error {
	return s.deps.Auth.InTransaction(ctx, func(q *sqlcgen.Queries) error {
		u, err := auth.LoadUser(ctx, q, userID, auth.ErrCredentialsNotFound(MessageInvalidAccess))
		if err != nil {
			return err
		}

		// Java 版の String.toLowerCase() は JVM の言語の設定で小文字にするが、提供元の名前は google と github だけで、
		// どちらも ASCII の字なので、ASCII の英大文字だけを小文字にしても、連携が見つかるかどうかは同じになる。
		key := asciiLower(provider)
		index := slices.IndexFunc(u.Providers, func(p sqlcgen.InsertUserAuthProviderParams) bool {
			return p.ProviderName == key
		})
		f := auth.FieldErrors{}
		switch {
		case index < 0:
			f.Check("authProviders", false, MessageProviderRemoveFailed)
		case (!emailVerified(u) || !u.Row.Password.Valid) && len(u.Providers) == 1:
			f.Check("authProviders", false, MessageProviderLastOne)
		}
		if e := f.Result(); e != nil {
			return e
		}

		u.Providers = slices.Delete(u.Providers, index, index+1)
		u.Row.UpdatedAt = s.javaNow()
		return auth.SaveUser(ctx, q, u)
	})
}

// emailVerified は、Java 版の User.isEmailVerified と同じく、メールアドレスがあり、その確認が済んでいるかを返す。
// 設定待ちのメールアドレスは見ない。
func emailVerified(u auth.StoredUser) bool {
	return u.Row.Email.Valid && u.Row.EmailVerifiedAt.Valid
}
