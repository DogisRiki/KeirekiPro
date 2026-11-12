package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/crypto/bcrypt"
)

// このファイルは、Java 版の UserRegistrationUseCase と VerifyEmailUseCase と ResendEmailVerificationUseCase と
// ResendEmailVerificationForLoginUseCase を、処理を進める順も同じに写す。

// registerBcryptCost は、登録のパスワードのハッシュの強さである。Java 版の BCryptPasswordEncoder の既定と同じ10にする。
const registerBcryptCost = 10

// verifyEmailMaxAttempts は、確認のリンクの分類と今のリンクの記録の消費を繰り返す回数である(Java 版の MAX_ATTEMPTS)。
// 同じリンクが同時に使われたとき、あとの要求は2回目の分類で ALREADY_VERIFIED などになる。
const verifyEmailMaxAttempts = 2

// resultPasswordResetReady は、目的が PASSWORD_RESET のリンクで確認を終え、再設定の値を置いたときの結果の名前である。
const resultPasswordResetReady emailVerificationResult = "PASSWORD_RESET_READY"

// RegisterInput は、新規の登録の入力である。入力の検査(ValidateRegister)を通った値を渡す。
type RegisterInput struct {
	Email    string
	Username string
	Password string
}

// VerifyEmailResult は、メールアドレスの確認の結果である。
type VerifyEmailResult struct {
	// Result は、結果の名前である(Java 版の EmailVerificationResult)。
	Result string
	// PasswordResetToken は、結果が PASSWORD_RESET_READY のときの再設定の値である。ほかの結果では空である。
	PasswordResetToken string
}

// Register は、Java 版の UserRegistrationUseCase と同じ順で、新規の登録を受け付ける。
//
//  1. メールアドレスを Email.create と同じく確かめ、誤りを覚えておく
//  2. 同じメールアドレスの利用者が居れば、400 の「このメールアドレスは登録できません。」で断る
//  3. 1 で誤りがあれば、入力の誤りで断る(Java 版はパスワードのハッシュを作ってから断るが、答えは同じである)
//  4. パスワードのハッシュを作り、登録の途中の記録を24時間置き、目的 REGISTRATION の確認のメールを送る。
//     送り直せる間隔の中で送れなくても、受け付ける。メールを送れなければ、置いた記録を消してから誤りを返す
func (s *Service) Register(ctx context.Context, in RegisterInput) error {
	emailErrors := emailCreateErrors(in.Email)
	_, found, err := s.findAccountByEmail(ctx, in.Email)
	if err != nil {
		return err
	}
	if found {
		return errBusiness(MessageEmailNotRegistrable)
	}
	if emailErrors != nil {
		return errInvalidInput(map[string][]string{"email": emailErrors})
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), registerBcryptCost)
	if err != nil {
		return fmt.Errorf("auth: パスワードのハッシュを作れない: %w", err)
	}
	id, err := uuid.NewRandomFromReader(readFunc(s.deps.Random))
	if err != nil {
		return fmt.Errorf("auth: 乱数を読めない: %w", err)
	}
	r := pendingRegistration{
		ID:           id,
		Email:        in.Email,
		PasswordHash: string(hash),
		Username:     in.Username,
		CreatedAt:    s.deps.Now(),
	}
	if err := s.savePendingRegistration(ctx, r, registrationLifetime); err != nil {
		return err
	}
	if _, sendErr := s.sendEmailVerification(ctx, in.Email, r.ID, purposeRegistration); sendErr != nil {
		if err := s.deletePendingRegistration(ctx, r); err != nil {
			return errors.Join(sendErr, err)
		}
		return sendErr
	}
	return nil
}

// VerifyEmail は、Java 版の VerifyEmailUseCase と同じく、確認のリンクを使う。読めないリンクは INVALID にする。
// リンクを分類し、使えるリンクなら今のリンクの記録を消費して、目的ごとの書き換えを行う。消費できなければ(同じリンクが
// 同時に使われたとき)、分類からやり直す。2回とも消費できなければ INVALID にする。
func (s *Service) VerifyEmail(ctx context.Context, token string) (VerifyEmailResult, error) {
	c, ok := s.readEmailVerificationToken(token)
	if !ok {
		return VerifyEmailResult{Result: string(resultInvalid)}, nil
	}
	for range verifyEmailMaxAttempts {
		state, err := s.classifyEmailVerificationLink(ctx, c)
		if err != nil {
			return VerifyEmailResult{}, err
		}
		if state != linkUsable {
			return VerifyEmailResult{Result: string(state)}, nil
		}
		consumed, err := s.consumeCurrentEmailVerification(ctx, c.SubjectID, c.JTI)
		if err != nil {
			return VerifyEmailResult{}, err
		}
		if consumed {
			return s.finishEmailVerification(ctx, c)
		}
	}
	return VerifyEmailResult{Result: string(resultInvalid)}, nil
}

// finishEmailVerification は、今のリンクの記録を消費したあとの書き換えを行う。目的が PASSWORD_RESET なら、
// Java 版と同じく、メールアドレスを確認済みにし、確認のリンクの期限までを有効な時間にして再設定の値を置く。
// 有効な時間は、Java 版の Duration.toMillis と同じくミリ秒に切り捨てる。1ミリ秒より短いと、Java 版は Redis に
// 断られて 500 になるので、Go 版も置かずに誤りを返す(storePasswordResetToken が0以下を断る)。
func (s *Service) finishEmailVerification(ctx context.Context, c emailVerificationClaims) (VerifyEmailResult, error) {
	if c.Purpose != purposePasswordReset {
		result, err := s.completeEmailVerification(ctx, c)
		if err != nil {
			return VerifyEmailResult{}, err
		}
		return VerifyEmailResult{Result: string(result)}, nil
	}
	if err := s.verifyAccountEmail(ctx, c.SubjectID, c.Email); err != nil {
		return VerifyEmailResult{}, err
	}
	resetToken, err := randomToken(s.deps.Random)
	if err != nil {
		return VerifyEmailResult{}, err
	}
	ttl := c.LinkExpiresAt.Sub(s.deps.Now()).Truncate(time.Millisecond)
	if err := s.storePasswordResetToken(ctx, resetToken, c.SubjectID, ttl); err != nil {
		return VerifyEmailResult{}, err
	}
	return VerifyEmailResult{Result: string(resultPasswordResetReady), PasswordResetToken: resetToken}, nil
}

// ResendEmailVerification は、Java 版の ResendEmailVerificationUseCase と同じく、期限の切れた確認のリンク
// (分類が EXPIRED のリンク)と同じ宛先と目的で、確認のメールを送り直す。ほかのリンクは
// 「このリンクでは確認のメールを送り直せません。」で断る。目的が REGISTRATION なら、登録の途中の記録を24時間に延ばす。
func (s *Service) ResendEmailVerification(ctx context.Context, token string) error {
	c, ok := s.readEmailVerificationToken(token)
	if !ok {
		return errBusiness(MessageNotResendable)
	}
	state, err := s.classifyEmailVerificationLink(ctx, c)
	if err != nil {
		return err
	}
	if state != resultExpired {
		return errBusiness(MessageNotResendable)
	}
	if err := s.resendEmailVerification(ctx, c.Email, c.SubjectID, c.Purpose); err != nil {
		return err
	}
	if c.Purpose == purposeRegistration {
		return s.extendPendingRegistration(ctx, c.SubjectID, registrationLifetime)
	}
	return nil
}

// ResendEmailVerificationForLogin は、Java 版の ResendEmailVerificationForLoginUseCase と同じく、ログインの画面から
// 確認のメールを送り直す。利用者が居れば、パスワードが合い、確認が済んでいないときだけ、目的 ACCOUNT_EMAIL で送る。
// 利用者が居なければ、新しい順に5件までの登録の途中の記録のうち、最初にパスワードが合った記録に目的 REGISTRATION で送り、
// その記録を24時間に延ばす。送れないときは、ログインの失敗と同じ文言で断る。
func (s *Service) ResendEmailVerificationForLogin(ctx context.Context, email, password string) error {
	a, found, err := s.findAccountByEmail(ctx, email)
	if err != nil {
		return err
	}
	if found {
		match, err := passwordMatches(password, a.PasswordHash)
		if err != nil {
			return err
		}
		if !match || a.EmailVerified {
			return errInvalidCredentials()
		}
		return s.resendEmailVerification(ctx, email, a.ID, purposeAccountEmail)
	}
	pending, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrationsForLogin)
	if err != nil {
		return err
	}
	for _, r := range pending {
		match, err := passwordMatches(password, pgtype.Text{String: r.PasswordHash, Valid: true})
		if err != nil {
			return err
		}
		if !match {
			continue
		}
		if err := s.resendEmailVerification(ctx, email, r.ID, purposeRegistration); err != nil {
			return err
		}
		return s.extendPendingRegistration(ctx, r.ID, registrationLifetime)
	}
	return errInvalidCredentials()
}

// resendEmailVerification は、確認のメールを送り、送り直せる間隔の中で送れなければ
// 「確認のメールは1分に1回まで送れます。…」で断る。
func (s *Service) resendEmailVerification(ctx context.Context, email string, subjectID uuid.UUID, purpose emailVerificationPurpose) error {
	sent, err := s.sendEmailVerification(ctx, email, subjectID, purpose)
	if err != nil {
		return err
	}
	if !sent {
		return errBusiness(MessageResendRateLimited)
	}
	return nil
}
