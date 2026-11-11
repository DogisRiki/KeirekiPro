package auth

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"strconv"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
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
