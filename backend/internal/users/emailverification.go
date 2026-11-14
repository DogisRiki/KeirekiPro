package users

import (
	"context"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// SendAccountEmailVerification は、Java 版の SendAccountEmailVerificationUseCase と同じく、利用者 userID に、
// 確認の済んでいないメールアドレスを確かめるメールを送る。
//   - 利用者が居なければ、Cookie を消させる 401 の誤りを返す
//   - 設定待ちのメールアドレスがあれば、そのメールアドレスへ、目的 PENDING_EMAIL のリンクを送る
//   - 設定待ちのメールアドレスが無く、メールアドレスの確認が済んでいなければ、メールアドレスへ、目的 ACCOUNT_EMAIL のリンクを送る
//   - どちらでもなければ、「確認が必要なメールアドレスはありません。」の 400 を返す
//   - 送り直せる間隔の中で送れなければ、「確認のメールは1分に1回まで送れます。…」の 400 を返す
//
// 送り直せる間隔と、新しいリンクを送ると前のリンクを使えなくすることは、認証の処理の SendEmailVerification が守る。
// Java 版のユースケースはトランザクションを持たないので、利用者の行はトランザクションの外で読む。
func (s *Service) SendAccountEmailVerification(ctx context.Context, userID uuid.UUID) error {
	u, err := auth.LoadUser(ctx, sqlcgen.New(s.deps.Pool), userID, auth.ErrCredentialsNotFound(MessageInvalidAccess))
	if err != nil {
		return err
	}

	var sent bool
	switch {
	case u.Row.PendingEmail.Valid:
		sent, err = s.deps.Auth.SendEmailVerification(ctx, u.Row.PendingEmail.String, userID, auth.PendingEmail)
	case u.Row.Email.Valid && !emailVerified(u):
		sent, err = s.deps.Auth.SendEmailVerification(ctx, u.Row.Email.String, userID, auth.AccountEmail)
	default:
		return auth.ErrBusiness(MessageNothingToVerify)
	}
	if err != nil {
		return err
	}
	if !sent {
		return auth.ErrBusiness(MessageResendRateLimited)
	}
	return nil
}
