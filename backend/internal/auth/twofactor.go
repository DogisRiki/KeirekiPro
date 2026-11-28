package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// このファイルは、Java 版の TwoFactorAuthIssueUseCase と TwoFactorAuthVerifyUseCase の、確認のコードと途中の記録の
// 発行と照合と、RedisTwoFactorAuthCodeStore と RedisTwoFactorAuthChallengeStore を写す。
// 確認のコードは、キー 2fa:<利用者の ID> に、6桁の数字の JSON の文字列で置く。
// 途中の記録は、キー 2fa:challenge:<値> に、{"userId":"…","attempts":n} の JSON を、さらに JSON の文字列にして置く。
// どちらも有効な時間は10分である。
//
// 読むときは、getText のとおり、JSON の文字列にした形と、そのままの形の、どちらでも読む。
// 途中の記録は、encoding/json で読み、読めない記録と、利用者の ID の無い記録は、見つからないとする。

const (
	twoFactorCodeKeyPrefix      = "2fa:"
	twoFactorChallengeKeyPrefix = "2fa:challenge:"
	// twoFactorLifetime は、確認のコードと途中の記録の有効な時間である(Java 版の Duration.ofMinutes(10))。
	twoFactorLifetime = 10 * time.Minute
	// twoFactorMaxAttempts は、確認のコードを誤ってよい回数の上限である(Java 版の MAX_ATTEMPTS)。
	twoFactorMaxAttempts = 5
)

// twoFactorChallenge は、途中の記録である。項目の名前と順は、Java 版が読み書きする形と同じにする。
type twoFactorChallenge struct {
	UserID   uuid.UUID `json:"userId"`
	Attempts int       `json:"attempts"`
}

// issueTwoFactor は、Java 版の TwoFactorAuthIssueUseCase と同じく、6桁の確認のコードを置き、途中の記録を置き、
// 確認のコードのメールを email へ送って、途中の記録の値を返す。メールを送れないときは、置いた値を残したまま誤りを返す。
func (s *Service) issueTwoFactor(ctx context.Context, userID uuid.UUID, email string) (string, error) {
	code, err := randomCode(s.deps.Random)
	if err != nil {
		return "", err
	}
	if err := s.setJSON(ctx, twoFactorCodeKeyPrefix+userID.String(), code, twoFactorLifetime); err != nil {
		return "", err
	}
	token, err := randomToken(s.deps.Random)
	if err != nil {
		return "", err
	}
	if err := s.putTwoFactorChallenge(ctx, token, twoFactorChallenge{UserID: userID}, twoFactorLifetime); err != nil {
		return "", err
	}
	if err := s.sendMail(ctx, email, twoFactorCodeMail(s.deps.App, code)); err != nil {
		return "", err
	}
	return token, nil
}

// checkTwoFactor は、Java 版の TwoFactorAuthVerifyUseCase のうち、利用者を読む前までを写す。
// 途中の記録の値 token と確認のコード code を照らし、合えば途中の記録と確認のコードを消して、利用者の ID を返す。
// 照らす順と、消す順と、断るときの文言は Java 版と同じである。
func (s *Service) checkTwoFactor(ctx context.Context, token, code string) (uuid.UUID, error) {
	if !notBlank(token) {
		return uuid.Nil, errBusiness(MessageInvalidTwoFactorSession)
	}
	challenge, ok, err := s.findTwoFactorChallenge(ctx, token)
	if err != nil {
		return uuid.Nil, err
	}
	if !ok {
		return uuid.Nil, errBusiness(MessageInvalidTwoFactorSession)
	}
	challengeKey := twoFactorChallengeKeyPrefix + token
	codeKey := twoFactorCodeKeyPrefix + challenge.UserID.String()
	saved, ok, err := s.findTwoFactorCode(ctx, codeKey)
	if err != nil {
		return uuid.Nil, err
	}
	if !ok {
		if err := s.deleteKey(ctx, challengeKey); err != nil {
			return uuid.Nil, err
		}
		return uuid.Nil, errBusiness(MessageInvalidTwoFactorCode)
	}
	if saved != code {
		attempts, err := s.incrementTwoFactorAttempts(ctx, token)
		if err != nil {
			return uuid.Nil, err
		}
		if attempts >= twoFactorMaxAttempts {
			if err := s.deleteKey(ctx, challengeKey); err != nil {
				return uuid.Nil, err
			}
			if err := s.deleteKey(ctx, codeKey); err != nil {
				return uuid.Nil, err
			}
			return uuid.Nil, errBusiness(MessageTwoFactorAttemptsExceeded)
		}
		return uuid.Nil, errBusiness(MessageInvalidTwoFactorCode)
	}
	if err := s.deleteKey(ctx, challengeKey); err != nil {
		return uuid.Nil, err
	}
	if err := s.deleteKey(ctx, codeKey); err != nil {
		return uuid.Nil, err
	}
	return challenge.UserID, nil
}

// incrementTwoFactorAttempts は、Java 版の incrementAttempts と同じく、途中の記録を読み直して回数を1つ増やし、
// 残りの有効な時間のまま置き直して、増やしたあとの回数を返す。残りの有効な時間が0以下なら10分にする。
// 途中の記録が無いときは、何も置かずに0を返す。
func (s *Service) incrementTwoFactorAttempts(ctx context.Context, token string) (int, error) {
	challenge, ok, err := s.findTwoFactorChallenge(ctx, token)
	if err != nil || !ok {
		return 0, err
	}
	challenge.Attempts++
	key := twoFactorChallengeKeyPrefix + token
	ttl, err := s.deps.Redis.TTL(ctx, key).Result()
	if err != nil {
		return 0, fmt.Errorf("auth: 2段階認証の途中の記録の有効な時間を読めない: %w", err)
	}
	if ttl <= 0 {
		ttl = twoFactorLifetime
	}
	if err := s.putTwoFactorChallenge(ctx, token, challenge, ttl); err != nil {
		return 0, err
	}
	return challenge.Attempts, nil
}

// putTwoFactorChallenge は、途中の記録を JSON にし、その JSON をさらに JSON の文字列にして置く。
// Java 版の jsonMapper.writeValueAsString と、RedisTemplate の値の直列化を2回重ねた形である。
func (s *Service) putTwoFactorChallenge(ctx context.Context, token string, c twoFactorChallenge, ttl time.Duration) error {
	inner, err := encodeJSON(c)
	if err != nil {
		return err
	}
	return s.setJSON(ctx, twoFactorChallengeKeyPrefix+token, inner, ttl)
}

// findTwoFactorChallenge は、途中の記録を読む。キーが無いときと、記録を JSON として読めないときと、
// 記録に利用者の ID が無いときは、見つからないとする。
func (s *Service) findTwoFactorChallenge(ctx context.Context, token string) (twoFactorChallenge, bool, error) {
	text, ok, err := s.getText(ctx, twoFactorChallengeKeyPrefix+token)
	if err != nil || !ok {
		return twoFactorChallenge{}, false, err
	}
	var c twoFactorChallenge
	if json.Unmarshal([]byte(text), &c) != nil || c.UserID == uuid.Nil {
		return twoFactorChallenge{}, false, nil
	}
	return c, true, nil
}

// findTwoFactorCode は、確認のコードを読む。キーが無いときは、見つからないとする。
func (s *Service) findTwoFactorCode(ctx context.Context, key string) (string, bool, error) {
	return s.getText(ctx, key)
}

// deleteKey は、キーを消す。Java 版の redisTemplate.delete にあたり、キーが無くても誤りにしない。
func (s *Service) deleteKey(ctx context.Context, key string) error {
	if err := s.deps.Redis.Del(ctx, key).Err(); err != nil {
		return fmt.Errorf("auth: Redis の値を消せない: %w", err)
	}
	return nil
}

// parseJacksonInt は、Jackson が JSON の値を Java の int の項目に読む規則で、値を読む。
// null は0とする。整数は int の範囲なら読む。小数と指数の数は、int の範囲なら0の向きに切り捨てる。
// 文字列は前後の U+0020 以下の文字を除き、空か "null" なら0、符号の付いてよい10進の整数で int の範囲なら読む。
// ほかの値(真偽、オブジェクト、配列、範囲の外の数、ほかの文字列)は読めないとする。
func parseJacksonInt(raw json.RawMessage) (int32, bool) {
	var v any
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if dec.Decode(&v) != nil {
		return 0, false
	}
	switch t := v.(type) {
	case nil:
		return 0, true
	case json.Number:
		text := t.String()
		if !strings.ContainsAny(text, ".eE") {
			n, err := strconv.ParseInt(text, 10, 32)
			return int32(n), err == nil
		}
		f, err := strconv.ParseFloat(text, 64)
		if err != nil || f < math.MinInt32 || f > math.MaxInt32 {
			return 0, false
		}
		return int32(math.Trunc(f)), true
	case string:
		s := javaTrim(t)
		if s == "" || s == "null" {
			return 0, true
		}
		n, err := strconv.ParseInt(s, 10, 32)
		return int32(n), err == nil
	default:
		return 0, false
	}
}

// javaTrim は、Java の String.trim と同じく、前後の U+0020 以下の文字を除く。
func javaTrim(s string) string {
	return strings.TrimFunc(s, func(r rune) bool { return r <= ' ' })
}
