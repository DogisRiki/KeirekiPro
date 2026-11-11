package auth

import (
	"bytes"
	"context"
	"encoding/base64"
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
// Java 版は、途中の記録の中の JSON を、Jackson で TwoFactorAuthChallenge に読む。Jackson は、型の違う値を
// ゆるく読むので、Go 版も、開発環境の Java 版で確かめた同じ規則で読む(parseTwoFactorChallenge)。

const (
	twoFactorCodeKeyPrefix      = "2fa:"
	twoFactorChallengeKeyPrefix = "2fa:challenge:"
	// twoFactorLifetime は、確認のコードと途中の記録の有効な時間である(Java 版の Duration.ofMinutes(10))。
	twoFactorLifetime = 10 * time.Minute
	// twoFactorMaxAttempts は、確認のコードを誤ってよい回数の上限である(Java 版の MAX_ATTEMPTS)。
	twoFactorMaxAttempts = 5
)

// twoFactorChallenge は、Java 版の TwoFactorAuthChallenge と同じ項目と順の、途中の記録である。
// Java 版は、利用者の ID が無い記録も読み、ID を null として書き直すので、UserID は nil を取れる。
// Attempts は、Java 版の int と同じく、32ビットで数え、上限を越えると負の数に回る。
type twoFactorChallenge struct {
	UserID   *uuid.UUID `json:"userId"`
	Attempts int32      `json:"attempts"`
}

// codeKey は、途中の記録の利用者の確認のコードのキーを返す。利用者の ID が無いときは、Java 版の
// "2fa:" + null と同じく、2fa:null を返す。
func (c twoFactorChallenge) codeKey() string {
	if c.UserID == nil {
		return twoFactorCodeKeyPrefix + "null"
	}
	return twoFactorCodeKeyPrefix + c.UserID.String()
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
	if err := s.putTwoFactorChallenge(ctx, token, twoFactorChallenge{UserID: &userID}, twoFactorLifetime); err != nil {
		return "", err
	}
	if err := s.sendMail(ctx, email, twoFactorCodeMail(s.deps.App, code)); err != nil {
		return "", err
	}
	return token, nil
}

// checkTwoFactor は、Java 版の TwoFactorAuthVerifyUseCase のうち、利用者を読む前までを写す。
// 途中の記録の値 token と確認のコード code を照らし、合えば途中の記録と確認のコードを消して、利用者の ID を返す。
// 途中の記録に利用者の ID が無いときは、uuid.Nil を返す。照らす順と、消す順と、断るときの文言は Java 版と同じである。
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
	codeKey := challenge.codeKey()
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
	if challenge.UserID == nil {
		return uuid.Nil, nil
	}
	return *challenge.UserID, nil
}

// incrementTwoFactorAttempts は、Java 版の incrementAttempts と同じく、途中の記録を読み直して回数を1つ増やし、
// 残りの有効な時間のまま置き直して、増やしたあとの回数を返す。残りの有効な時間が0以下なら10分にする。
// 途中の記録が無いときは、何も置かずに0を返す。
func (s *Service) incrementTwoFactorAttempts(ctx context.Context, token string) (int32, error) {
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

// findTwoFactorChallenge は、途中の記録を読む。Java 版の find と同じく、キーが無いときと、
// 値が JSON の null のときと、中の JSON を途中の記録として読めないときは、見つからないとする。
// 値が JSON でないときと、JSON の文字列でも null でもないときは、Java 版が例外にするので、誤りを返す。
func (s *Service) findTwoFactorChallenge(ctx context.Context, token string) (twoFactorChallenge, bool, error) {
	text, ok, err := s.getJSONString(ctx, twoFactorChallengeKeyPrefix+token)
	if err != nil || !ok {
		return twoFactorChallenge{}, false, err
	}
	return parseTwoFactorChallenge(text)
}

// findTwoFactorCode は、確認のコードを読む。Java 版の find と同じく、キーが無いときと、値が JSON の null のときは、
// 見つからないとする。値が JSON でないときと、JSON の文字列でも null でもないときは、誤りを返す。
func (s *Service) findTwoFactorCode(ctx context.Context, key string) (string, bool, error) {
	return s.getJSONString(ctx, key)
}

// getJSONString は、キーの値を JSON として読み、JSON の文字列ならその文字列を返す。
// キーが無いときと、値が JSON の null のときは、偽を返す(Java 版の RedisTemplate の get が null を返す場合)。
// JSON の文字列でも null でもない値は、Java 版の (String) の型の変換が例外にするので、誤りを返す。
func (s *Service) getJSONString(ctx context.Context, key string) (string, bool, error) {
	var raw json.RawMessage
	ok, err := s.getJSON(ctx, key, &raw)
	if err != nil || !ok {
		return "", false, err
	}
	var v any
	if err := json.Unmarshal(raw, &v); err != nil {
		return "", false, fmt.Errorf("auth: Redis の値を JSON として読めない: %w", err)
	}
	switch t := v.(type) {
	case nil:
		return "", false, nil
	case string:
		return t, true, nil
	default:
		return "", false, fmt.Errorf("auth: Redis の値が JSON の文字列でない: %T", v)
	}
}

// deleteKey は、キーを消す。Java 版の redisTemplate.delete にあたり、キーが無くても誤りにしない。
func (s *Service) deleteKey(ctx context.Context, key string) error {
	if err := s.deps.Redis.Del(ctx, key).Err(); err != nil {
		return fmt.Errorf("auth: Redis の値を消せない: %w", err)
	}
	return nil
}

// parseTwoFactorChallenge は、途中の記録の中の JSON を、Java 版の Jackson の
// readValue(text, TwoFactorAuthChallenge.class) と同じ規則で読む。開発環境の Java 版で確かめた規則は次のとおりである。
//
//   - 先頭の1つの JSON の値だけを読み、そのあとの文字は見ない。読めないとき、または値が JSON のオブジェクトでないときは、
//     見つからないとする。値が null のときは、Java 版が例外にするので、誤りを返す
//   - 知らない項目は飛ばす。同じ項目が2回あるときは、あとの値を使う
//   - userId と attempts は、parseJacksonUUID と parseJacksonInt の規則で読む。読めないときは見つからないとする
func parseTwoFactorChallenge(text string) (twoFactorChallenge, bool, error) {
	var top json.RawMessage
	if err := json.NewDecoder(strings.NewReader(text)).Decode(&top); err != nil {
		return twoFactorChallenge{}, false, nil
	}
	top = bytes.TrimLeft(top, " \t\r\n")
	if bytes.Equal(top, []byte("null")) {
		return twoFactorChallenge{}, false, fmt.Errorf("auth: 2段階認証の途中の記録が null である")
	}
	var fields map[string]json.RawMessage
	if top[0] != '{' || json.Unmarshal(top, &fields) != nil {
		return twoFactorChallenge{}, false, nil
	}
	var c twoFactorChallenge
	if raw, ok := fields["userId"]; ok {
		id, ok := parseJacksonUUID(raw)
		if !ok {
			return twoFactorChallenge{}, false, nil
		}
		c.UserID = id
	}
	if raw, ok := fields["attempts"]; ok {
		n, ok := parseJacksonInt(raw)
		if !ok {
			return twoFactorChallenge{}, false, nil
		}
		c.Attempts = n
	}
	return c, true, nil
}

// parseJacksonUUID は、Jackson の UUIDDeserializer と同じ規則で、JSON の値を UUID として読む。
// null は nil とする。文字列は前後の U+0020 以下の文字を除き、空なら nil、36文字ならハイフンで区切った16進、
// 24文字なら16バイトの base64 として読む。ほかの文字列と、文字列でも null でもない値は読めないとする。
func parseJacksonUUID(raw json.RawMessage) (*uuid.UUID, bool) {
	var v any
	if json.Unmarshal(raw, &v) != nil {
		return nil, false
	}
	if v == nil {
		return nil, true
	}
	s, ok := v.(string)
	if !ok {
		return nil, false
	}
	s = javaTrim(s)
	switch len(s) {
	case 0:
		return nil, true
	case 36:
		id, err := uuid.Parse(s)
		if err != nil {
			return nil, false
		}
		return &id, true
	case 24:
		b, err := base64.StdEncoding.DecodeString(s)
		if err != nil {
			return nil, false
		}
		id, err := uuid.FromBytes(b)
		if err != nil {
			return nil, false
		}
		return &id, true
	default:
		return nil, false
	}
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
