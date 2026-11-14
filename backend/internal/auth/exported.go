package auth

// このファイルは、認証の処理のうち、利用者の処理(internal/users)が使うものを、ほかのパッケージから呼べる形にする。
// ここの関数と型は処理の中身を持たず、今ある関数を呼ぶだけにする。

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/crypto/bcrypt"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// 確認のメールの目的のうち、利用者の処理が SendEmailVerification に渡す2つである。
const (
	// AccountEmail は、利用者のメールアドレスを確かめるリンクの目的である(Java 版の ACCOUNT_EMAIL)。
	AccountEmail = purposeAccountEmail
	// PendingEmail は、設定待ちのメールアドレスを確かめるリンクの目的である(Java 版の PENDING_EMAIL)。
	PendingEmail = purposePendingEmail
)

// FieldErrors は、項目ごとの文言を、検査した順に集める。
type FieldErrors = fieldErrors

// Check は、ok が偽のとき、項目 field に文言 message を足す。
func (f fieldErrors) Check(field string, ok bool, message string) {
	f.check(field, ok, message)
}

// Result は、文言が1つでもあれば入力の誤りを、無ければ nil を返す。
func (f fieldErrors) Result() *Error {
	return f.result()
}

// LoadUser は、トランザクションの問い合わせ q で利用者 id の行と連携と役割を読む。Java 版の UserRepository.findById にあたる。
// 利用者が居なければ notFound を返す。
func LoadUser(ctx context.Context, q *sqlcgen.Queries, id uuid.UUID, notFound error) (StoredUser, error) {
	return loadStoredUserOr(ctx, q, id, notFound)
}

// SaveUser は、Java 版の UserRepository.save と同じ順で、利用者の行と連携と役割を書く。
func SaveUser(ctx context.Context, q *sqlcgen.Queries, u StoredUser) error {
	return saveUser(ctx, q, u)
}

// InTransaction は、fn を1つのトランザクションで動かす。fn が誤りを返せば、書いた行をすべて取り消す。
func (s *Service) InTransaction(ctx context.Context, fn func(q *sqlcgen.Queries) error) error {
	return s.inTransaction(ctx, fn)
}

// PasswordMatches は、Spring Security の BCryptPasswordEncoder.matches と同じ規則で、パスワードとハッシュを照らす。
func PasswordMatches(password string, hash pgtype.Text) (bool, error) {
	return passwordMatches(password, hash)
}

// HashPassword は、Java 版の BCryptPasswordEncoder の既定と同じ強さ10で、パスワードのハッシュを作る。
func HashPassword(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), registerBcryptCost)
	if err != nil {
		return "", fmt.Errorf("auth: パスワードのハッシュを作れない: %w", err)
	}
	return string(hash), nil
}

// SendEmailVerification は、Java 版の EmailVerificationMailer.send と同じ順で、email へ確認のメールを送る。
// 送り直せる間隔の中で送れないときは偽を返し、送ったときは真を返す。purpose には AccountEmail か PendingEmail を渡す。
func (s *Service) SendEmailVerification(ctx context.Context, email string, subjectID uuid.UUID, purpose emailVerificationPurpose) (bool, error) {
	return s.sendEmailVerification(ctx, email, subjectID, purpose)
}

// ClearCurrentEmailVerification は、subjectID の今の確認のリンクの記録を消す。
func (s *Service) ClearCurrentEmailVerification(ctx context.Context, subjectID uuid.UUID) error {
	return s.clearCurrentEmailVerification(ctx, subjectID)
}

// InvalidateSessions は、ログインの状態の世代の番号を1つ上げ、利用者が持つログインを続けるための値をすべて消す。
// トランザクションの外で呼ぶ。
func (s *Service) InvalidateSessions(ctx context.Context, userID uuid.UUID) error {
	return s.invalidateSessions(ctx, userID)
}

// RemoveAllRefreshTokens は、利用者が持つログインを続けるための値をすべて消す。
func (s *Service) RemoveAllRefreshTokens(ctx context.Context, userID uuid.UUID) error {
	return s.removeAllRefreshTokens(ctx, userID)
}

// SendUserDeletedMail は、退会の完了のメールを to へ送る。Java 版の UserDeletedEventListener にあたる。
// 名前が無いときは、Java 版のひな形と同じく本文を作れないので、送らずに誤りを返す。
func (s *Service) SendUserDeletedMail(ctx context.Context, to string, username pgtype.Text) error {
	if !username.Valid {
		return errors.New("auth: 名前が無いので退会の完了のメールを作れない")
	}
	return s.sendMail(ctx, to, userDeletedMail(s.deps.App, username.String))
}

// ErrBusiness は、業務の決まりで断るときの 400 の誤りを作る。Java 版の UseCaseException にあたる。
func ErrBusiness(message string) *Error {
	return errBusiness(message)
}

// ErrInvalidInput は、項目ごとの入力の誤りのときの 400 の誤りを作る。
func ErrInvalidInput(fields map[string][]string) *Error {
	return errInvalidInput(fields)
}

// ErrCredentialsNotFound は、操作の相手の利用者が居ないときの 401 の誤りを作る。Cookie を消させる。
func ErrCredentialsNotFound(message string) *Error {
	return errCredentialsNotFound(message)
}

// NotBlank は、Jakarta Validation の @NotBlank と同じく、s が Java の空白でない文字を含むかを返す。
func NotBlank(s string) bool {
	return notBlank(s)
}

// UTF16Len は、Java の String.length と同じく、s を UTF-16 で数えた長さを返す。
func UTF16Len(s string) int {
	return utf16Len(s)
}

// IsJavaWhitespace は、Java の Character.isWhitespace と同じく、r が空白かを返す。
func IsJavaWhitespace(r rune) bool {
	return isJavaWhitespace(r)
}

// PasswordPatternOK は、Java 版のパスワードの形の決まりに s が合うかを返す。
func PasswordPatternOK(s string) bool {
	return passwordPatternOK(s)
}

// IsEmailLikeHibernate は、Hibernate Validator の @Email と同じく、s がメールアドレスの形かを返す。
func IsEmailLikeHibernate(s string) bool {
	return isEmailLikeHibernate(s)
}

// EmailCreateErrors は、Java 版の Email.create と同じく、メールアドレスの空と形の誤りの文言を返す。誤りが無ければ nil を返す。
func EmailCreateErrors(email string) []string {
	return emailCreateErrors(email)
}

// EmailInUse は、Java 版の UserEmailDuplicationCheckService と同じく、users の email の列に email を持つ利用者が居るかを返す。
func (s *Service) EmailInUse(ctx context.Context, email string) (bool, error) {
	_, found, err := s.findAccountByEmail(ctx, email)
	return found, err
}
