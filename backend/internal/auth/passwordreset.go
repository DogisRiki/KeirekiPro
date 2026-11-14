package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/crypto/bcrypt"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// このファイルは、Java 版の RedisPasswordResetTokenStore と、RequestPasswordResetUseCase と
// VerifyPasswordResetTokenUseCase と ResetPasswordUseCase を写す。
// 再設定の値の記録は、キー password-reset:<値> に、利用者の ID を JSON の文字列で、渡された有効な時間だけ置く。

const (
	passwordResetKeyPrefix = "password-reset:"
	// passwordResetTokenValidity は、再設定の申し込みで作る再設定の値の有効な時間である(Java 版の RequestPasswordResetUseCase)。
	// メールアドレスの確認から作る再設定の値には、Java 版の VerifyEmailUseCase と同じく、確認のリンクの残りの時間を付ける。
	passwordResetTokenValidity = 10 * time.Minute
)

// errPasswordResetUserID は、再設定の値の記録が UUID の文字列でないことを表す。
// Java 版は UUID.fromString が例外にし、500 で答える。
var errPasswordResetUserID = errors.New("auth: パスワードの再設定の値の記録が UUID でない")

// storePasswordResetToken は、再設定の値 token に、利用者の ID を ttl のあいだ置く(Java 版の store)。
// ttl が0以下のときは、記録を置かずに誤りを返す。
func (s *Service) storePasswordResetToken(ctx context.Context, token string, userID uuid.UUID, ttl time.Duration) error {
	return s.setJSON(ctx, passwordResetKeyPrefix+token, userID.String(), ttl)
}

// findPasswordResetUserID は、再設定の値 token の利用者の ID を返す。記録が無いときと、記録が JSON の null のときは、
// 偽を返す(Java 版の findUserId)。記録が文字列でないときと、UUID でないときは、Java 版が例外にするので、誤りを返す。
func (s *Service) findPasswordResetUserID(ctx context.Context, token string) (uuid.UUID, bool, error) {
	text, ok, err := s.getJSONString(ctx, passwordResetKeyPrefix+token)
	if err != nil || !ok {
		return uuid.Nil, false, err
	}
	userID, err := parseJavaUUIDText(text)
	if err != nil {
		return uuid.Nil, false, errPasswordResetUserID
	}
	return userID, true, nil
}

// removePasswordResetToken は、再設定の値 token の記録を消す(Java 版の remove)。記録が無くても誤りにしない。
func (s *Service) removePasswordResetToken(ctx context.Context, token string) error {
	return s.deleteKey(ctx, passwordResetKeyPrefix+token)
}

// passwordResetBcryptCost は、再設定する新しいパスワードのハッシュの強さである。
// Java 版の SecurityConfig の BCryptPasswordEncoder の既定と同じ10にする。
const passwordResetBcryptCost = 10

// RequestPasswordReset は、Java 版の RequestPasswordResetUseCase と同じく、パスワードの再設定を受け付ける。
// アカウントが無ければ何もしない。確認の済んでいないアカウントには、再設定のメールの代わりに目的 PASSWORD_RESET の
// 確認のメールを申し込んだメールアドレスに送り、送り直せる間隔の中で送れなくても同じに答える。確認済みなら、
// 再設定の値を10分置き、再設定のリンクのメールを利用者のメールアドレスに送る。メールを送れなければ誤りを返す。
func (s *Service) RequestPasswordReset(ctx context.Context, email string) error {
	a, found, err := s.findAccountByEmail(ctx, email)
	if err != nil || !found {
		return err
	}
	if !a.EmailVerified {
		_, err := s.sendEmailVerification(ctx, email, a.ID, purposePasswordReset)
		return err
	}
	token, err := randomToken(s.deps.Random)
	if err != nil {
		return err
	}
	if err := s.storePasswordResetToken(ctx, token, a.ID, passwordResetTokenValidity); err != nil {
		return err
	}
	link := s.deps.App.FrontendBaseURL + "/password/reset/" + token
	return s.sendMail(ctx, a.Email.String, passwordResetMail(s.deps.App, link))
}

// VerifyPasswordResetToken は、Java 版の VerifyPasswordResetTokenUseCase と同じく、再設定の値の記録があるかを確かめる。
// 無ければ 400 の「リセットリンクが無効または期限切れです。…」で断る。
func (s *Service) VerifyPasswordResetToken(ctx context.Context, token string) error {
	_, ok, err := s.findPasswordResetUserID(ctx, token)
	if err != nil {
		return err
	}
	if !ok {
		return errBusiness(MessageInvalidResetLink)
	}
	return nil
}

// ResetPassword は、Java 版の ResetPasswordUseCase と同じ順で、パスワードを再設定する。
//
//  1. 再設定の値の記録が無ければ、400 の「リセットリンクが無効または期限切れです。…」で断る
//  2. 1つのトランザクションで、利用者を読み(居なければ Cookie を消させる 401 の「不正なアクセスです。」)、
//     新しいパスワードのハッシュと更新日時を書き、再設定の値の記録を消し、世代の番号を1つ上げ、
//     ログインを続けるための値をすべて消す。途中で誤りがあれば、データベースの書き換えを取り消す
func (s *Service) ResetPassword(ctx context.Context, token, newPassword string) error {
	userID, ok, err := s.findPasswordResetUserID(ctx, token)
	if err != nil {
		return err
	}
	if !ok {
		return errBusiness(MessageInvalidResetLink)
	}
	return s.inTransaction(ctx, func(q *sqlcgen.Queries) error {
		u, err := loadStoredUserOr(ctx, q, userID, errCredentialsNotFound(MessageInvalidAccess))
		if err != nil {
			return err
		}
		hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), passwordResetBcryptCost)
		if err != nil {
			return fmt.Errorf("auth: パスワードのハッシュを作れない: %w", err)
		}
		u.Row.Password = pgtype.Text{String: string(hash), Valid: true}
		u.Row.UpdatedAt = s.javaNow()
		if err := saveUser(ctx, q, u); err != nil {
			return err
		}
		if err := s.removePasswordResetToken(ctx, token); err != nil {
			return err
		}
		if err := s.BumpTokenVersion(ctx, q, userID); err != nil {
			return err
		}
		return s.removeAllRefreshTokens(ctx, userID)
	})
}
