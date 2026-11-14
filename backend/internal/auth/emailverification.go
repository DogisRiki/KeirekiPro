package auth

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// このファイルは、Java 版の JwtEmailVerificationTokenCodec と RedisEmailVerificationCurrentTokenStore と
// RedisEmailVerificationSendLimiter と EmailVerificationMailer を写す。
//
// 確認のリンクの値は、HS256 の JWT で、項目は aud、jti、sub、purpose、email、lexp(リンクの期限の秒)である。
// exp を持たないので、値を読むときは期限を確かめない。期限は、値を読んだ側が lexp で確かめる。
// 今のリンクの記録は、キー email-verification:current:<sub> に jti を JSON の文字列で、リンクの有効な時間で置く。
// 新しいリンクを送ると記録が上書きされるので、前のリンクは使えなくなる。
// 送り直せる間隔の制限は、キー email-verification:rate:<メールアドレス> に "1" を60秒置く。

const (
	emailVerificationAudience           = "keirekipro-email-verification"
	emailVerificationKeyDerivationLabel = "keirekipro-email-verification-v1"
	emailVerificationCurrentKeyPrefix   = "email-verification:current:"
	emailVerificationRateKeyPrefix      = "email-verification:rate:"
	// emailVerificationSendInterval は、同じメールアドレスへ確認のメールを送り直せる間隔である(Java 版の INTERVAL)。
	emailVerificationSendInterval = 60 * time.Second
	// emailVerificationHeader は、Java 版の java-jwt が書くヘッダの JSON である。
	emailVerificationHeader = `{"alg":"HS256","typ":"JWT"}`
)

// emailVerificationPurpose は、確認のリンクの目的である。名前は Java 版の EmailVerificationPurpose と同じにする。
type emailVerificationPurpose string

const (
	purposeRegistration  emailVerificationPurpose = "REGISTRATION"
	purposeAccountEmail  emailVerificationPurpose = "ACCOUNT_EMAIL"
	purposePendingEmail  emailVerificationPurpose = "PENDING_EMAIL"
	purposePasswordReset emailVerificationPurpose = "PASSWORD_RESET"
)

// linkValidity は、目的ごとのリンクの有効な時間を返す。知らない目的のときは偽を返す。
func (p emailVerificationPurpose) linkValidity() (time.Duration, bool) {
	switch p {
	case purposeRegistration, purposeAccountEmail, purposePendingEmail:
		return 24 * time.Hour, true
	case purposePasswordReset:
		return 10 * time.Minute, true
	default:
		return 0, false
	}
}

// emailVerificationClaims は、確認のリンクの値の項目である(Java 版の EmailVerificationClaims)。
type emailVerificationClaims struct {
	JTI           string
	SubjectID     uuid.UUID
	Purpose       emailVerificationPurpose
	Email         string
	LinkExpiresAt time.Time
}

// emailVerificationPayload は、確認のリンクの値の本体の JSON である。項目の順は、Java 版の java-jwt が書く順と同じである。
type emailVerificationPayload struct {
	Audience      string `json:"aud"`
	JTI           string `json:"jti"`
	Subject       string `json:"sub"`
	Purpose       string `json:"purpose"`
	Email         string `json:"email"`
	LinkExpiresAt int64  `json:"lexp"`
}

// emailVerificationReadClaims は、確認のリンクの値を読むときの項目である。
// jti と sub は、RegisteredClaims の同じ名前の項目より浅い位置に置き、Java 版と同じく、項目が無い値と
// null の値を、空の文字列と分けて読む。aud は RegisteredClaims が読み、golang-jwt が確かめる。
type emailVerificationReadClaims struct {
	JTI           *string `json:"jti"`
	Subject       *string `json:"sub"`
	Purpose       *string `json:"purpose"`
	Email         *string `json:"email"`
	LinkExpiresAt *int64  `json:"lexp"`
	jwt.RegisteredClaims
}

// emailVerificationKey は、確認のリンクの署名の鍵を、Java 版と同じく、HMAC-SHA256(secret, ラベル)で導く。
// ログインの状態の値と鍵を分け、一方の値を他方として受け付けないようにするためである。
func emailVerificationKey(secret string) []byte {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(emailVerificationKeyDerivationLabel))
	return mac.Sum(nil)
}

// issueEmailVerificationToken は、確認のリンクの値を作る。Java 版の java-jwt と同じヘッダと、同じ順と書き方の本体を
// 組み立てて署名する。golang-jwt の SignedString は本体を json.Marshal で書き、< > & を逃がして Java 版と
// 違う値になるので、本体は encodeJSONText(Java 版の writeValueAsString と同じ書き方)で書く。
func (s *Service) issueEmailVerificationToken(c emailVerificationClaims) (string, error) {
	payload, err := encodeJSONText(emailVerificationPayload{
		Audience:      emailVerificationAudience,
		JTI:           c.JTI,
		Subject:       c.SubjectID.String(),
		Purpose:       string(c.Purpose),
		Email:         c.Email,
		LinkExpiresAt: c.LinkExpiresAt.Unix(),
	})
	if err != nil {
		return "", err
	}
	enc := base64.RawURLEncoding
	signing := enc.EncodeToString([]byte(emailVerificationHeader)) + "." + enc.EncodeToString([]byte(payload))
	sig, err := jwt.SigningMethodHS256.Sign(signing, emailVerificationKey(s.deps.JWT.Secret))
	if err != nil {
		return "", fmt.Errorf("auth: 確認のリンクの値に署名できない: %w", err)
	}
	return signing + "." + enc.EncodeToString(sig), nil
}

// readEmailVerificationToken は、確認のリンクの値を読む。Java 版の read と同じく、署名か aud が合わないとき、
// 5つの項目のどれかが無いとき、sub が UUID でないとき、purpose が知らない目的のときは、偽を返す。
// Java 版の java-jwt に合わせ、署名の方式を HS256 に限り、exp と nbf と iat があれば猶予無しで確かめ、
// base64url の末尾の = を受け付ける。
func (s *Service) readEmailVerificationToken(token string) (emailVerificationClaims, bool) {
	var c emailVerificationReadClaims
	_, err := jwt.ParseWithClaims(token, &c,
		func(*jwt.Token) (any, error) { return emailVerificationKey(s.deps.JWT.Secret), nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithAudience(emailVerificationAudience),
		jwt.WithIssuedAt(),
		jwt.WithPaddingAllowed(),
		jwt.WithTimeFunc(s.deps.Now),
	)
	if err != nil {
		return emailVerificationClaims{}, false
	}
	if c.JTI == nil || c.Subject == nil || c.Purpose == nil || c.Email == nil || c.LinkExpiresAt == nil {
		return emailVerificationClaims{}, false
	}
	subjectID, err := uuid.Parse(*c.Subject)
	if err != nil {
		return emailVerificationClaims{}, false
	}
	purpose := emailVerificationPurpose(*c.Purpose)
	if _, ok := purpose.linkValidity(); !ok {
		return emailVerificationClaims{}, false
	}
	return emailVerificationClaims{
		JTI:           *c.JTI,
		SubjectID:     subjectID,
		Purpose:       purpose,
		Email:         *c.Email,
		LinkExpiresAt: time.Unix(*c.LinkExpiresAt, 0),
	}, true
}

// putCurrentEmailVerification は、subjectID の今のリンクの jti を、ttl のあいだ置く(Java 版の put)。
func (s *Service) putCurrentEmailVerification(ctx context.Context, subjectID uuid.UUID, jti string, ttl time.Duration) error {
	return s.setJSON(ctx, emailVerificationCurrentKeyPrefix+subjectID.String(), jti, ttl)
}

// findCurrentEmailVerification は、subjectID の今のリンクの jti を返す。無いときは偽を返す(Java 版の find)。
func (s *Service) findCurrentEmailVerification(ctx context.Context, subjectID uuid.UUID) (string, bool, error) {
	return s.getJSONString(ctx, emailVerificationCurrentKeyPrefix+subjectID.String())
}

// consumeCurrentEmailVerification は、subjectID の今のリンクの jti が jti と同じときだけ記録を消し、消せたら真を返す
// (Java 版の consume)。
func (s *Service) consumeCurrentEmailVerification(ctx context.Context, subjectID uuid.UUID, jti string) (bool, error) {
	return s.consumeJSONIfEqual(ctx, emailVerificationCurrentKeyPrefix+subjectID.String(), jti)
}

// clearCurrentEmailVerification は、subjectID の今のリンクの記録を消す(Java 版の clear)。
func (s *Service) clearCurrentEmailVerification(ctx context.Context, subjectID uuid.UUID) error {
	return s.deleteKey(ctx, emailVerificationCurrentKeyPrefix+subjectID.String())
}

// tryAcquireEmailVerificationSend は、email へ確認のメールを送ってよいかを、送り直せる間隔の記録を置けるかで決める。
// 置けたら真を返す(Java 版の tryAcquire)。
func (s *Service) tryAcquireEmailVerificationSend(ctx context.Context, email string) (bool, error) {
	return s.setJSONNX(ctx, emailVerificationRateKeyPrefix+email, "1", emailVerificationSendInterval)
}

// releaseEmailVerificationSend は、email の送り直せる間隔の記録を消す(Java 版の release)。
func (s *Service) releaseEmailVerificationSend(ctx context.Context, email string) error {
	return s.deleteKey(ctx, emailVerificationRateKeyPrefix+email)
}

// sendEmailVerification は、Java 版の EmailVerificationMailer.send と同じ順で、email へ確認のメールを送る。
// 送り直せる間隔の中で送れないときは、何も置かずに偽を返す(Java 版の RATE_LIMITED)。送ったときは真を返す。
// メールを送れないときは、届かなかったメールのために送り直しを待たせないよう、送り直せる間隔の記録と
// 今のリンクの記録を消してから、誤りを返す。
func (s *Service) sendEmailVerification(ctx context.Context, email string, subjectID uuid.UUID, purpose emailVerificationPurpose) (bool, error) {
	validity, ok := purpose.linkValidity()
	if !ok {
		return false, fmt.Errorf("auth: 確認のリンクの目的 %q を知らない", purpose)
	}
	acquired, err := s.tryAcquireEmailVerificationSend(ctx, email)
	if err != nil || !acquired {
		return false, err
	}
	jti, err := uuid.NewRandomFromReader(readFunc(s.deps.Random))
	if err != nil {
		return false, fmt.Errorf("auth: 乱数を読めない: %w", err)
	}
	token, err := s.issueEmailVerificationToken(emailVerificationClaims{
		JTI:           jti.String(),
		SubjectID:     subjectID,
		Purpose:       purpose,
		Email:         email,
		LinkExpiresAt: s.deps.Now().Add(validity),
	})
	if err != nil {
		return false, err
	}
	// 前に送ったリンクを使えなくする
	if err := s.putCurrentEmailVerification(ctx, subjectID, jti.String(), validity); err != nil {
		return false, err
	}
	// 値を # のあとに置き、ブラウザが要求にも Referer にも載せないようにする
	link := s.deps.App.FrontendBaseURL + "/email/verify#" + token
	if sendErr := s.sendMail(ctx, email, emailVerificationMail(s.deps.App, link, linkLifetimeText(validity))); sendErr != nil {
		if err := s.releaseEmailVerificationSend(ctx, email); err != nil {
			return false, err
		}
		if err := s.clearCurrentEmailVerification(ctx, subjectID); err != nil {
			return false, err
		}
		return false, sendErr
	}
	return true, nil
}

// linkLifetimeText は、リンクの有効な時間を、Java 版の formatLifetime と同じく、分の端数が無ければ「24時間」のように
// 時間で、あれば「10分」のように分で書く。
func linkLifetimeText(d time.Duration) string {
	minutes := int64(d / time.Minute)
	if minutes%60 == 0 {
		return strconv.FormatInt(int64(d/time.Hour), 10) + "時間"
	}
	return strconv.FormatInt(minutes, 10) + "分"
}

// emailVerificationResult は、確認のリンクを使った結果の名前である。名前は Java 版の EmailVerificationResult と同じにする。
type emailVerificationResult string

const (
	resultVerified         emailVerificationResult = "VERIFIED"
	resultAlreadyVerified  emailVerificationResult = "ALREADY_VERIFIED"
	resultExpired          emailVerificationResult = "EXPIRED"
	resultInvalid          emailVerificationResult = "INVALID"
	resultRegistrationGone emailVerificationResult = "REGISTRATION_GONE"
	resultEmailTaken       emailVerificationResult = "EMAIL_TAKEN"
	// linkUsable は、Java 版の LinkState.USABLE にあたる分類である。結果の名前ではないので、応答に書かない。
	linkUsable emailVerificationResult = "USABLE"
)

// classifyEmailVerificationLink は、Java 版の EmailVerificationLinkClassifier.classify と同じ順と条件で、
// 確認のリンクを分類する。使えるリンクなら linkUsable を、使えなければ結果の名前を返す。
//
//  1. 利用者が居て、メールアドレスの確認が済み、メールアドレスがリンクと同じなら ALREADY_VERIFIED
//  2. 期限の前で、今のリンクの記録の値の ID がリンクと同じなら linkUsable
//  3. 目的が REGISTRATION なら、登録の途中の記録があれば EXPIRED、無ければ REGISTRATION_GONE
//  4. 利用者が居て、目的の宛先(PENDING_EMAIL なら設定待ちのメールアドレス、ほかはメールアドレス)が
//     リンクと同じなら EXPIRED、そうでなければ INVALID
func (s *Service) classifyEmailVerificationLink(ctx context.Context, c emailVerificationClaims) (emailVerificationResult, error) {
	user, found, err := s.findAccountByID(ctx, c.SubjectID)
	if err != nil {
		return "", err
	}
	if found && user.EmailVerified && user.Email.String == c.Email {
		return resultAlreadyVerified, nil
	}
	live, err := s.isLiveEmailVerificationLink(ctx, c)
	if err != nil {
		return "", err
	}
	if live {
		return linkUsable, nil
	}
	if c.Purpose == purposeRegistration {
		_, pending, err := s.findPendingRegistration(ctx, c.SubjectID)
		if err != nil {
			return "", err
		}
		if pending {
			return resultExpired, nil
		}
		return resultRegistrationGone, nil
	}
	target := user.Email
	if c.Purpose == purposePendingEmail {
		target = user.PendingEmail
	}
	if found && target.Valid && target.String == c.Email {
		return resultExpired, nil
	}
	return resultInvalid, nil
}

// isLiveEmailVerificationLink は、リンクが期限の前で、今のリンクの記録の値の ID と同じかを返す。
// Java 版と同じく、今の時刻が期限ちょうどなら期限の後とする。
func (s *Service) isLiveEmailVerificationLink(ctx context.Context, c emailVerificationClaims) (bool, error) {
	if !s.deps.Now().Before(c.LinkExpiresAt) {
		return false, nil
	}
	jti, found, err := s.findCurrentEmailVerification(ctx, c.SubjectID)
	if err != nil {
		return false, err
	}
	return found && jti == c.JTI, nil
}

// completeEmailVerification は、今のリンクの記録を消費したあとの書き換えを、目的ごとに行う。Java 版の
// VerifyEmailUseCase.complete のうち、目的が PASSWORD_RESET のとき以外を写す。PASSWORD_RESET のリンクは、
// 再設定の値を作る呼び出し元が扱うので、この関数は書き換えずに誤りを返す。
func (s *Service) completeEmailVerification(ctx context.Context, c emailVerificationClaims) (emailVerificationResult, error) {
	switch c.Purpose {
	case purposeRegistration:
		return s.completeRegistration(ctx, c)
	case purposePendingEmail:
		err := s.promotePendingEmail(ctx, c.SubjectID, c.Email)
		if isIntegrityViolation(err) {
			return resultEmailTaken, nil
		}
		if err != nil {
			return "", err
		}
		return resultVerified, nil
	case purposeAccountEmail:
		if err := s.verifyAccountEmail(ctx, c.SubjectID, c.Email); err != nil {
			return "", err
		}
		return resultVerified, nil
	default:
		return "", fmt.Errorf("auth: 目的 %s の確認のリンクは、呼び出し元が書き換える", c.Purpose)
	}
}

// completeRegistration は、Java 版の VerifyEmailUseCase.completeRegistration と同じく、登録の途中の記録から
// 利用者を作る。一意の制約などに当たれば、トランザクションの外で利用者を読み直し、確認済みで同じメールアドレスなら
// ALREADY_VERIFIED を、そうでなければ EMAIL_TAKEN を返す。この2つのときは、登録の途中の記録を消さない。
func (s *Service) completeRegistration(ctx context.Context, c emailVerificationClaims) (emailVerificationResult, error) {
	r, found, err := s.findPendingRegistration(ctx, c.SubjectID)
	if err != nil {
		return "", err
	}
	if !found {
		return resultRegistrationGone, nil
	}
	err = s.inTransaction(ctx, func(q *sqlcgen.Queries) error {
		return s.createVerifiedUser(ctx, q, r)
	})
	if isIntegrityViolation(err) {
		user, found, err := s.findAccountByID(ctx, c.SubjectID)
		if err != nil {
			return "", err
		}
		if found && user.EmailVerified && user.Email.String == c.Email {
			return resultAlreadyVerified, nil
		}
		return resultEmailTaken, nil
	}
	if err != nil {
		return "", err
	}
	if err := s.deletePendingRegistration(ctx, r); err != nil {
		return "", err
	}
	return resultVerified, nil
}

// createVerifiedUser は、Java 版の EmailVerificationCompletion.completeRegistration と同じく、
// 確認済みのメールアドレスと役割 USER を持つ利用者を保存し、世代の番号の行を 0 で足し、登録の完了のメールを送る。
// Java 版は、メールを送る処理をトランザクションの中で同期して動かすので、送れなければ足した行をすべて取り消す。
func (s *Service) createVerifiedUser(ctx context.Context, q *sqlcgen.Queries, r pendingRegistration) error {
	now := s.javaNow()
	id := pgtype.UUID{Bytes: r.ID, Valid: true}
	u := StoredUser{
		Row: sqlcgen.UpsertUserParams{
			ID:              id,
			Email:           nullableText(r.Email),
			Password:        nullableText(r.PasswordHash),
			Username:        nullableText(r.Username),
			CreatedAt:       now,
			UpdatedAt:       now,
			EmailVerifiedAt: now,
		},
		Roles: []string{"USER"},
	}
	if err := saveUser(ctx, q, u); err != nil {
		return err
	}
	if err := q.InsertTokenVersion(ctx, sqlcgen.InsertTokenVersionParams{UserID: id, UpdatedAt: now}); err != nil {
		return fmt.Errorf("auth: 世代の番号の行を足せない: %w", err)
	}
	return s.sendMail(ctx, r.Email, userRegisteredMail(s.deps.App, r.Username))
}

// verifyAccountEmail は、Java 版の EmailVerificationCompletion.verifyAccountEmail と同じく、利用者のメールアドレスが
// リンクと同じなら、確認した日時と更新日時を今の時刻にして保存する。確認済みなら、日時を変えずに同じ値を保存する。
func (s *Service) verifyAccountEmail(ctx context.Context, id uuid.UUID, email string) error {
	return s.inTransaction(ctx, func(q *sqlcgen.Queries) error {
		u, err := loadStoredUser(ctx, q, id)
		if err != nil {
			return err
		}
		if !u.Row.Email.Valid || u.Row.Email.String != email {
			return errBusiness(MessageInvalidVerificationLink)
		}
		if !u.Row.EmailVerifiedAt.Valid {
			now := s.javaNow()
			u.Row.UpdatedAt = now
			u.Row.EmailVerifiedAt = now
		}
		return saveUser(ctx, q, u)
	})
}

// promotePendingEmail は、Java 版の EmailVerificationCompletion.promotePendingEmail と User.promotePendingEmail と
// 同じく、設定待ちのメールアドレスがリンクと同じなら、それをメールアドレスに移して確認済みにし、設定待ちを空にして保存する。
func (s *Service) promotePendingEmail(ctx context.Context, id uuid.UUID, email string) error {
	return s.inTransaction(ctx, func(q *sqlcgen.Queries) error {
		u, err := loadStoredUser(ctx, q, id)
		if err != nil {
			return err
		}
		if !u.Row.PendingEmail.Valid || u.Row.PendingEmail.String != email {
			return errBusiness(MessageInvalidVerificationLink)
		}
		if u.Row.Email.Valid {
			return errBusiness(MessagePendingEmailMissing)
		}
		now := s.javaNow()
		u.Row.Email = u.Row.PendingEmail
		u.Row.PendingEmail = pgtype.Text{}
		u.Row.UpdatedAt = now
		u.Row.EmailVerifiedAt = now
		return saveUser(ctx, q, u)
	})
}

// javaNow は、今の時刻を、Java 版が TIMESTAMP の列に書くのと同じ Asia/Tokyo の時刻の見た目で返す。
func (s *Service) javaNow() pgtype.Timestamp {
	return pgtype.Timestamp{Time: s.deps.Now().In(javaZone), Valid: true}
}

// nullableText は、空の文字列を NULL にした文字列の列の値を作る。
func nullableText(v string) pgtype.Text {
	return pgtype.Text{String: v, Valid: v != ""}
}

// StoredUser は、Java 版の UserRepository.save が書く、利用者1人の行である。
type StoredUser struct {
	Row       sqlcgen.UpsertUserParams
	Providers []sqlcgen.InsertUserAuthProviderParams
	Roles     []string
}

// loadStoredUser は、トランザクションの中で利用者 id の行を読む。Java 版の UserRepository.findById と同じく、
// User.reconstruct の確かめに反すれば 400 の誤りを返す。居なければ、確認のリンクが無効な 400 の誤りを返す。
func loadStoredUser(ctx context.Context, q *sqlcgen.Queries, id uuid.UUID) (StoredUser, error) {
	return loadStoredUserOr(ctx, q, id, errBusiness(MessageInvalidVerificationLink))
}

// loadStoredUserOr は、loadStoredUser と同じく利用者 id の行を読み、居なければ notFound を返す。
func loadStoredUserOr(ctx context.Context, q *sqlcgen.Queries, id uuid.UUID, notFound error) (StoredUser, error) {
	rows, err := q.GetUserRowsByID(ctx, pgtype.UUID{Bytes: id, Valid: true})
	if err != nil {
		return StoredUser{}, fmt.Errorf("auth: 利用者を読めない: %w", err)
	}
	converted := make([]sqlcgen.GetUserRowsByEmailRow, len(rows))
	for i, r := range rows {
		converted[i] = sqlcgen.GetUserRowsByEmailRow(r)
	}
	acc, found, err := accountFromRows(converted)
	if err != nil {
		return StoredUser{}, err
	}
	if !found {
		return StoredUser{}, notFound
	}
	first := rows[0]
	u := StoredUser{
		Row: sqlcgen.UpsertUserParams{
			ID:                   first.UID,
			Email:                first.UEmail,
			Password:             first.UPassword,
			Username:             first.UUsername,
			ProfileImage:         first.UProfileImage,
			TwoFactorAuthEnabled: first.UTwoFactorAuthEnabled,
			CreatedAt:            first.UCreatedAt,
			UpdatedAt:            first.UUpdatedAt,
			EmailVerifiedAt:      first.UEmailVerifiedAt,
			PendingEmail:         first.UPendingEmail,
		},
		Roles: acc.Roles,
	}
	seen := map[[16]byte]bool{}
	for _, r := range rows {
		if !r.PID.Valid || seen[r.PID.Bytes] {
			continue
		}
		seen[r.PID.Bytes] = true
		u.Providers = append(u.Providers, sqlcgen.InsertUserAuthProviderParams{
			ID:             r.PID,
			UserID:         first.UID,
			ProviderName:   r.PProviderName.String,
			ProviderUserID: r.PProviderUserID.String,
			CreatedAt:      r.PCreatedAt,
			UpdatedAt:      r.PUpdatedAt,
		})
	}
	return u, nil
}

// saveUser は、Java 版の MyBatisUserRepository.save と同じ順で、利用者の行を書き、連携の行と役割の行を消して足し直す。
func saveUser(ctx context.Context, q *sqlcgen.Queries, u StoredUser) error {
	if err := q.UpsertUser(ctx, u.Row); err != nil {
		return fmt.Errorf("auth: 利用者の行を書けない: %w", err)
	}
	if err := q.DeleteUserAuthProviders(ctx, u.Row.ID); err != nil {
		return fmt.Errorf("auth: 連携の行を消せない: %w", err)
	}
	for _, p := range u.Providers {
		if err := q.InsertUserAuthProvider(ctx, p); err != nil {
			return fmt.Errorf("auth: 連携の行を足せない: %w", err)
		}
	}
	if err := q.DeleteUserRoles(ctx, u.Row.ID); err != nil {
		return fmt.Errorf("auth: 役割の行を消せない: %w", err)
	}
	for _, role := range u.Roles {
		if err := q.InsertUserRole(ctx, sqlcgen.InsertUserRoleParams{UserID: u.Row.ID, RoleName: role}); err != nil {
			return fmt.Errorf("auth: 役割の行を足せない: %w", err)
		}
	}
	return nil
}

// inTransaction は、fn を1つのトランザクションで動かす。fn が誤りを返せば、書いた行をすべて取り消す。
func (s *Service) inTransaction(ctx context.Context, fn func(q *sqlcgen.Queries) error) error {
	tx, err := s.deps.Pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("auth: トランザクションを始められない: %w", err)
	}
	defer func() { _ = tx.Rollback(context.WithoutCancel(ctx)) }()
	if err := fn(sqlcgen.New(tx)); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("auth: トランザクションを確定できない: %w", err)
	}
	return nil
}

// integrityViolationClasses は、Spring の SQLStateSQLExceptionTranslator が DataIntegrityViolationException に訳す
// SQLSTATE の分類(先頭の2文字)である。
var integrityViolationClasses = map[string]bool{"01": true, "02": true, "22": true, "23": true, "27": true, "44": true}

// isIntegrityViolation は、err が、Java 版の Spring が DataIntegrityViolationException(DuplicateKeyException を含む)に
// 訳す PostgreSQL の誤りかを返す。Spring は、sql-error-codes.xml の PostgreSQL の duplicateKeyCodes(21000 と 23505)と
// dataIntegrityViolationCodes(23000、23502、23503、23514)を先に照らし、当たらなければ SQLSTATE の分類で訳す。
func isIntegrityViolation(err error) bool {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		return false
	}
	if pgErr.Code == "21000" {
		return true
	}
	return len(pgErr.Code) >= 2 && integrityViolationClasses[pgErr.Code[:2]]
}
