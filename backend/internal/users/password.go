package users

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// SetEmailAndPasswordInput は、メールアドレスとパスワードの設定の要求の値である。
// Email と CurrentPassword は、要求の本文に無いか null のとき nil にする。
type SetEmailAndPasswordInput struct {
	UserID          uuid.UUID
	Email           *string
	Password        string
	CurrentPassword *string
}

// ChangePassword は、Java 版の ChangePasswordUseCase と同じ順で、利用者 userID のパスワードを newPassword に変える。
// Java 版と同じく、トランザクションを使わない。
//   - 利用者が居なければ、Cookie を消させる 401 の誤りを返す
//   - 今のパスワードが nowPassword と合わなければ項目 nowPassword に、newPassword と合えば項目 newPassword に文言を集め、
//     1つでもあれば 400 の入力の誤りを返す。パスワードを持たない利用者では、どちらの照合も合わない
//   - 新しいパスワードを強さ10でハッシュにして利用者の行を書き、すべての端末のログインの状態を使えなくする
func (s *Service) ChangePassword(ctx context.Context, userID uuid.UUID, nowPassword, newPassword string) error {
	q := sqlcgen.New(s.deps.Pool)
	u, err := auth.LoadUser(ctx, q, userID, auth.ErrCredentialsNotFound(MessageInvalidAccess))
	if err != nil {
		return err
	}

	nowMatches, err := auth.PasswordMatches(nowPassword, u.Row.Password)
	if err != nil {
		return err
	}
	sameAsNow, err := auth.PasswordMatches(newPassword, u.Row.Password)
	if err != nil {
		return err
	}
	f := auth.FieldErrors{}
	f.Check("nowPassword", nowMatches, MessageNowPhraseWrong)
	f.Check("newPassword", !sameAsNow, MessageNewPhraseSameAsNow)
	if e := f.Result(); e != nil {
		return e
	}

	if err := s.setPhrase(&u, newPassword); err != nil {
		return err
	}
	if err := auth.SaveUser(ctx, q, u); err != nil {
		return err
	}
	return s.deps.Auth.InvalidateSessions(ctx, userID)
}

// SetEmailAndPassword は、Java 版の SetEmailAndPasswordUseCase と User.setPendingEmail と同じ順で、1つのトランザクションの中で、
// 利用者にメールアドレスとパスワードを設定する。メールアドレスは設定待ちにし、確認が済むまで利用者のメールアドレスにしない。
//  1. 利用者を読む。居なければ、Cookie を消させる 401 の誤りを返す
//  2. メールアドレスがあれば、空と形の誤りの文言を項目 email に集める。ここでは返さない。続けて、そのメールアドレスを持つ
//     利用者が居れば、自分でも「このメールアドレスは登録できません。」の 400 を返す
//  3. 利用者がパスワードを持ち、今のパスワードが無いか合わなければ、「今のパスワードが正しくありません。」の 400 を返す
//  4. メールアドレスがあれば、利用者がすでにメールアドレスを持つときに項目 email に文言を足し、集めた文言が1つでもあれば
//     400 の入力の誤りを返す。無ければ、設定待ちのメールアドレスにする
//  5. パスワードを強さ10でハッシュにして、利用者の行を書く
//  6. メールアドレスがあれば、今の確認のリンクの記録を消し、設定待ちのメールアドレスへ目的 PENDING_EMAIL の確認のメールを送る。
//     送り直せる間隔の中で送れなかったときも、Java 版と同じく誤りにしない
//
// 確認のメールを送れないときは、トランザクションを戻して誤りを返す。Java 版も同じトランザクションの中で送る。
func (s *Service) SetEmailAndPassword(ctx context.Context, in SetEmailAndPasswordInput) error {
	return s.deps.Auth.InTransaction(ctx, func(q *sqlcgen.Queries) error {
		u, err := auth.LoadUser(ctx, q, in.UserID, auth.ErrCredentialsNotFound(MessageInvalidAccess))
		if err != nil {
			return err
		}

		f := auth.FieldErrors{}
		if in.Email != nil {
			for _, m := range auth.EmailCreateErrors(*in.Email) {
				f.Check("email", false, m)
			}
			inUse, err := s.deps.Auth.EmailInUse(ctx, *in.Email)
			if err != nil {
				return err
			}
			if inUse {
				return auth.ErrBusiness(auth.MessageEmailNotRegistrable)
			}
		}

		if u.Row.Password.Valid {
			matches := false
			if in.CurrentPassword != nil {
				if matches, err = auth.PasswordMatches(*in.CurrentPassword, u.Row.Password); err != nil {
					return err
				}
			}
			if !matches {
				return auth.ErrBusiness(MessageCurrentPhraseWrong)
			}
		}

		if in.Email != nil {
			f.Check("email", !u.Row.Email.Valid, MessageEmailAlreadySet)
			if e := f.Result(); e != nil {
				return e
			}
			u.Row.PendingEmail = pgtype.Text{String: *in.Email, Valid: true}
			u.Row.UpdatedAt = s.javaNow()
		}

		if err := s.setPhrase(&u, in.Password); err != nil {
			return err
		}
		if err := auth.SaveUser(ctx, q, u); err != nil {
			return err
		}

		if in.Email == nil {
			return nil
		}
		if err := s.deps.Auth.ClearCurrentEmailVerification(ctx, in.UserID); err != nil {
			return err
		}
		_, err = s.deps.Auth.SendEmailVerification(ctx, *in.Email, in.UserID, auth.PendingEmail)
		return err
	})
}

// setPhrase は、Java 版の User.changePassword と User.resetPassword と同じく、利用者 u のパスワードを phrase の
// 強さ10のハッシュにし、updated_at を今の時刻にする。
func (s *Service) setPhrase(u *auth.StoredUser, phrase string) error {
	hash, err := auth.HashPassword(phrase)
	if err != nil {
		return err
	}
	u.Row.Password = pgtype.Text{String: hash, Valid: true}
	u.Row.UpdatedAt = s.javaNow()
	return nil
}
