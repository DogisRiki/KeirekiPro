package auth

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/crypto/bcrypt"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// このファイルは、Java 版の LoginController と LoginUseCase、TwoFactorAuthController と TwoFactorAuthVerifyUseCase、
// RefreshAccessTokenController、LogoutController と、それらが使う AuthCookieIssuer を写す。
// 処理を進める順と、断るときの文言は Java 版と同じである。

// maxPendingRegistrationsForLogin は、アカウントが無いときに照らす登録の途中の記録の数の上限である
// (Java 版の LoginUseCase の MAX_PENDING_REGISTRATIONS)。
const maxPendingRegistrationsForLogin = 5

// knownRoles は、Java 版の RoleName の値を、Go 版が役割を並べる順に並べたものである。
// Java 版は役割を順の決まらない集合で持つので、Go 版は、この順に決める。
var knownRoles = []string{"USER", "ADMIN"}

// SessionTokens は、ログインの状態の値と、ログインを続けるための値である。
// 認証の受け口は、この順に Cookie accessToken と refreshToken を書く。
type SessionTokens struct {
	AccessToken  string
	RefreshToken string
}

// LoginResult は、ログインの結果である。2段階認証が有効な利用者なら、TwoFactorChallenge に
// 途中の記録の値が入り、Session は空である。そうでなければ、TwoFactorChallenge は空で、Session に値が入る。
type LoginResult struct {
	TwoFactorChallenge string
	Session            SessionTokens
}

// account は、利用者の行のうち、ログインと2段階認証の確認が使う項目である。
type account struct {
	ID    uuid.UUID
	Email pgtype.Text
	// PasswordHash は、パスワードのハッシュである。Google か GitHub のログインだけの利用者は Valid が偽である。
	PasswordHash     pgtype.Text
	TwoFactorEnabled bool
	// EmailVerified は、Java 版の User.isEmailVerified と同じく、メールアドレスと確認した日時の両方があるときに真である。
	EmailVerified bool
	// PendingEmail は、確認を待っている設定待ちのメールアドレスである。無ければ Valid が偽である。
	PendingEmail pgtype.Text
	// Roles は、knownRoles の順に並べた役割の名前である。役割が無ければ空の並びで、nil にしない。
	Roles []string
}

// Login は、メールアドレスとパスワードでログインする。Java 版の LoginUseCase と同じく、
// 利用者が無ければ登録の途中の記録を照らし、パスワードを照らし、メールアドレスの確認が済んでいるかを
// 確かめてから、2段階認証が有効なら確認のコードを送り、そうでなければログインの状態の値2つを発行する。
func (s *Service) Login(ctx context.Context, email, password string) (LoginResult, error) {
	user, ok, err := s.findAccountByEmail(ctx, email)
	if err != nil {
		return LoginResult{}, err
	}
	if !ok {
		return LoginResult{}, s.rejectWithoutAccount(ctx, email, password)
	}
	match, err := passwordMatches(password, user.PasswordHash)
	if err != nil {
		return LoginResult{}, err
	}
	if !match {
		return LoginResult{}, errInvalidCredentials()
	}
	if !user.EmailVerified {
		return LoginResult{}, errEmailNotVerified(KindUnverifiedAccountEmail)
	}
	if user.TwoFactorEnabled {
		challenge, err := s.issueTwoFactor(ctx, user.ID, user.Email.String)
		if err != nil {
			return LoginResult{}, err
		}
		return LoginResult{TwoFactorChallenge: challenge}, nil
	}
	session, err := s.issueSession(ctx, user.ID, user.Roles)
	if err != nil {
		return LoginResult{}, err
	}
	return LoginResult{Session: session}, nil
}

// rejectWithoutAccount は、アカウントが無いときの誤りを返す。Java 版と同じく、メールアドレスの登録の途中の記録を
// 最大5件読み、どれかのパスワードが合えば 409 の PENDING_REGISTRATION、どれも合わなければ、パスワードが違うときと
// 同じ誤りにする。
func (s *Service) rejectWithoutAccount(ctx context.Context, email, password string) error {
	pending, err := s.findPendingRegistrationsByEmail(ctx, email, maxPendingRegistrationsForLogin)
	if err != nil {
		return err
	}
	for _, r := range pending {
		match, err := passwordMatches(password, pgtype.Text{String: r.PasswordHash, Valid: true})
		if err != nil {
			return err
		}
		if match {
			return errEmailNotVerified(KindPendingRegistration)
		}
	}
	return errInvalidCredentials()
}

// VerifyTwoFactor は、2段階認証の途中の記録の値 challenge と確認のコード code を照らし、合えば
// ログインの状態の値2つを発行する。Java 版と同じく、途中の記録と確認のコードを消してから利用者を読み、
// 利用者が居なければ MessageUserInfoUnavailable で断る。Cookie が無いときも、受け口は空の challenge を渡す。
func (s *Service) VerifyTwoFactor(ctx context.Context, challenge, code string) (SessionTokens, error) {
	userID, err := s.checkTwoFactor(ctx, challenge, code)
	if err != nil {
		return SessionTokens{}, err
	}
	user, ok, err := s.findAccountByID(ctx, userID)
	if err != nil {
		return SessionTokens{}, err
	}
	if !ok {
		return SessionTokens{}, errBusiness(MessageUserInfoUnavailable)
	}
	return s.issueSession(ctx, user.ID, user.Roles)
}

// Refresh は、ログインを続けるための値から、新しいログインの状態の値を作る。Java 版の
// RefreshAccessTokenController と同じく、値が無いか見つからないときは 401 で断り、値の世代の番号が
// 今の世代の番号と違うときは、値を消してから 401 で断る。空の値は、Cookie が無いときと同じに扱う。
func (s *Service) Refresh(ctx context.Context, refreshToken string) (string, error) {
	if refreshToken == "" {
		return "", errUnauthenticated()
	}
	info, ok, err := s.findRefreshToken(ctx, refreshToken)
	if err != nil {
		return "", err
	}
	if !ok {
		return "", errUnauthenticated()
	}
	version, err := s.tokenVersion(ctx, info.UserID)
	if err != nil {
		return "", err
	}
	if info.TokenVersion != version {
		if err := s.removeRefreshToken(ctx, refreshToken); err != nil {
			return "", err
		}
		return "", errUnauthenticated()
	}
	return s.IssueAccessToken(ctx, info.UserID, info.Roles)
}

// Logout は、Java 版の LogoutController と同じく、ログインを続けるための値から、無ければログインの状態の値から
// 利用者を特定し、特定できたら利用者のログインの状態をすべて使えなくし、最後にログインを続けるための値を消す。
// ログインの状態の値を受け付けないときは、利用者を特定できなかったとする。データベースの誤りは返す。
// 空の値は、Cookie が無いときと同じに扱う。
func (s *Service) Logout(ctx context.Context, refreshToken, accessToken string) error {
	userID, ok, err := s.logoutUser(ctx, refreshToken, accessToken)
	if err != nil {
		return err
	}
	if ok {
		if err := s.invalidateSessions(ctx, userID); err != nil {
			return err
		}
	}
	if refreshToken != "" {
		return s.removeRefreshToken(ctx, refreshToken)
	}
	return nil
}

// logoutUser は、ログアウトする利用者を、ログインを続けるための値から、無ければログインの状態の値から特定する。
func (s *Service) logoutUser(ctx context.Context, refreshToken, accessToken string) (uuid.UUID, bool, error) {
	if refreshToken != "" {
		info, ok, err := s.findRefreshToken(ctx, refreshToken)
		if err != nil {
			return uuid.Nil, false, err
		}
		if ok {
			return info.UserID, true, nil
		}
	}
	if accessToken == "" {
		return uuid.Nil, false, nil
	}
	p, err := s.VerifyAccessToken(ctx, accessToken)
	if errors.Is(err, ErrInvalidToken) {
		return uuid.Nil, false, nil
	}
	if err != nil {
		return uuid.Nil, false, err
	}
	return p.UserID, true, nil
}

// issueSession は、Java 版の AuthCookieIssuer と同じく、世代の番号を読み、ログインの状態の値を作り、
// 読んだ世代の番号でログインを続けるための値を作る。
func (s *Service) issueSession(ctx context.Context, userID uuid.UUID, roles []string) (SessionTokens, error) {
	version, err := s.tokenVersion(ctx, userID)
	if err != nil {
		return SessionTokens{}, err
	}
	access, err := s.IssueAccessToken(ctx, userID, roles)
	if err != nil {
		return SessionTokens{}, err
	}
	refresh, err := s.issueRefreshToken(ctx, userID, roles, version)
	if err != nil {
		return SessionTokens{}, err
	}
	return SessionTokens{AccessToken: access, RefreshToken: refresh}, nil
}

// findAccountByEmail は、メールアドレスが email の利用者を読む。居なければ偽を返す。
func (s *Service) findAccountByEmail(ctx context.Context, email string) (account, bool, error) {
	rows, err := sqlcgen.New(s.deps.Pool).GetUserRowsByEmail(ctx, pgtype.Text{String: email, Valid: true})
	if err != nil {
		return account{}, false, fmt.Errorf("auth: 利用者を読めない: %w", err)
	}
	return accountFromRows(rows)
}

// findAccountByID は、ID が id の利用者を読む。居なければ偽を返す。
func (s *Service) findAccountByID(ctx context.Context, id uuid.UUID) (account, bool, error) {
	rows, err := sqlcgen.New(s.deps.Pool).GetUserRowsByID(ctx, pgtype.UUID{Bytes: id, Valid: true})
	if err != nil {
		return account{}, false, fmt.Errorf("auth: 利用者を読めない: %w", err)
	}
	converted := make([]sqlcgen.GetUserRowsByEmailRow, len(rows))
	for i, r := range rows {
		converted[i] = sqlcgen.GetUserRowsByEmailRow(r)
	}
	return accountFromRows(converted)
}

// accountFromRows は、利用者の行を1人の利用者にまとめる。問い合わせは、外部のログインの連携と役割の
// 組み合わせごとに1行を返すので、役割の名前を集める。Java 版の RoleName に無い名前は読み飛ばす。
func accountFromRows(rows []sqlcgen.GetUserRowsByEmailRow) (account, bool, error) {
	if len(rows) == 0 {
		return account{}, false, nil
	}
	first := rows[0]
	if !first.UID.Valid {
		return account{}, false, errors.New("auth: 利用者の行に ID が無い")
	}
	names := map[string]bool{}
	for _, r := range rows {
		if r.RName.Valid {
			names[r.RName.String] = true
		}
	}
	roles := []string{}
	for _, name := range knownRoles {
		if names[name] {
			roles = append(roles, name)
		}
	}
	// Java 版の User.reconstruct は、利用者を読むたびに次の2つを確かめ、DomainException で 400 にする。
	// Go 版も、利用者を読むたびに同じ順で確かめ、パスワードを照らす前に同じ答えで断る。
	if first.UTwoFactorAuthEnabled && (!first.UEmail.Valid || !first.UPassword.Valid) {
		return account{}, false, errBusiness(MessageTwoFactorPrerequisiteMissing)
	}
	if names["ADMIN"] && !first.UTwoFactorAuthEnabled {
		return account{}, false, errBusiness(MessageAdminNeedsTwoFactor)
	}
	return account{
		ID:               first.UID.Bytes,
		Email:            first.UEmail,
		PasswordHash:     first.UPassword,
		TwoFactorEnabled: first.UTwoFactorAuthEnabled,
		EmailVerified:    first.UEmail.Valid && first.UEmailVerifiedAt.Valid,
		PendingEmail:     first.UPendingEmail,
		Roles:            roles,
	}, true, nil
}

// springBcryptPattern は、Spring Security の BCryptPasswordEncoder が照らす前に確かめるハッシュの形である。
// Spring は版の文字の無い $2$ も受け付けるが、Go の bcrypt は、Spring と違って $2$ でも鍵の末尾に0のバイトを
// 足して計算し、結果が合わないので、Go 版は $2$ を照らさずに合わないとする。
var springBcryptPattern = regexp.MustCompile(`^\$2[aby]\$(\d\d)\$[./0-9A-Za-z]{53}$`)

// bcryptAlphabet は、bcrypt の base64 の文字の並びである。
const bcryptAlphabet = "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

// passwordMatches は、Spring Security の BCryptPasswordEncoder.matches と同じ規則で、パスワードとハッシュを照らす。
// 開発環境の Java 版で確かめた規則は次のとおりである。
//   - ハッシュが無いか空なら、合わない
//   - ハッシュの形が springBcryptPattern に合わなければ、合わない
//   - 強さが4から31の外なら、Java 版は例外にして 500 で答えるので、誤りを返す
//   - 塩の22文字目に、使われない下位の4ビットが立っていれば、Java 版は塩を正規の形に書き直して比べるので、合わない
//   - パスワードは、先頭の72バイトだけを使う。Go の bcrypt.CompareHashAndPassword も先頭の72バイトだけを使うので、切り詰めない
//     (72バイトを超えると誤りにするのは、ハッシュを作る bcrypt.GenerateFromPassword だけである)
func passwordMatches(password string, hash pgtype.Text) (bool, error) {
	if !hash.Valid || hash.String == "" {
		return false, nil
	}
	m := springBcryptPattern.FindStringSubmatch(hash.String)
	if m == nil {
		return false, nil
	}
	if cost, _ := strconv.Atoi(m[1]); cost < bcrypt.MinCost || cost > bcrypt.MaxCost {
		return false, fmt.Errorf("auth: パスワードのハッシュの強さ %d が範囲の外にある", cost)
	}
	const saltLastIndex = len("$2a$10$") + 21
	if strings.IndexByte(bcryptAlphabet, hash.String[saltLastIndex])%16 != 0 {
		return false, nil
	}
	err := bcrypt.CompareHashAndPassword([]byte(hash.String), []byte(password))
	if errors.Is(err, bcrypt.ErrMismatchedHashAndPassword) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("auth: パスワードを照らせない: %w", err)
	}
	return true, nil
}
