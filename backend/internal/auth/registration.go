package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"math/big"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// このファイルは、Java 版の RedisPendingRegistrationStore を写す。
// 登録の途中の記録を、JSON にしてから、その JSON をさらに JSON の文字列にして pending-registration:<ID> に置き、
// メールアドレスごとの集合 pending-registration:email:<メールアドレス> に、記録の ID を JSON の文字列で足す。
//
// Java 版の Jackson が記録を読む規則は、開発環境の Java 版の Redis に記録を置いてログインを求めて調べた。
// 読めない記録は、Java 版と同じく、無い記録として扱う。

const (
	registrationKeyPrefix      = "pending-registration:"
	registrationEmailKeyPrefix = "pending-registration:email:"
	// registrationLifetime は、登録の途中の記録の有効な時間である。Java 版の
	// EmailVerificationPurpose.REGISTRATION の確認のリンクの有効な時間と同じである。
	registrationLifetime = 24 * time.Hour
	// maxPendingRegistrations は、メールアドレスで読む登録の途中の記録の数の上限である。
	maxPendingRegistrations = 5
)

// pendingRegistration は、Java 版の PendingRegistration と同じ項目を持つ、登録の途中の記録である。
// Java 版が null を置いた項目は、ゼロの値で持つ。CreatedAt のゼロの値は、作った日時が無いことを表す。
type pendingRegistration struct {
	ID           uuid.UUID
	Email        string
	PasswordHash string
	Username     string
	CreatedAt    time.Time
}

// registrationJSON は、記録を、Java 版の Jackson と同じ項目の順で JSON にするための形である。
type registrationJSON struct {
	ID           string `json:"id"`
	Email        string `json:"email"`
	PasswordHash string `json:"passwordHash"`
	Username     string `json:"username"`
	CreatedAt    any    `json:"createdAt"`
}

// savePendingRegistration は、Java 版の save と同じく、記録を置き、メールアドレスの集合に記録の ID を足して、
// どちらにも有効な時間 ttl を付ける。同じ ID の記録があれば上書きする。
func (s *Service) savePendingRegistration(ctx context.Context, r pendingRegistration, ttl time.Duration) error {
	var createdAt any
	if !r.CreatedAt.IsZero() {
		createdAt = formatJavaInstant(r.CreatedAt)
	}
	inner, err := encodeJSONText(registrationJSON{
		ID:           r.ID.String(),
		Email:        r.Email,
		PasswordHash: r.PasswordHash,
		Username:     r.Username,
		CreatedAt:    createdAt,
	})
	if err != nil {
		return err
	}
	if err := s.setJSON(ctx, registrationKeyPrefix+r.ID.String(), inner, ttl); err != nil {
		return err
	}
	return s.saddJSON(ctx, registrationEmailKeyPrefix+r.Email, ttl, r.ID.String())
}

// findPendingRegistration は、Java 版の findById と同じく、ID の記録を読む。
// 記録が無いとき、値が JSON の null のとき、中の JSON を記録として読めないときは、見つからないとする。
// 値が JSON の文字列でも null でもないときと、中の JSON が null のときは、Java 版が例外にするので、誤りを返す。
func (s *Service) findPendingRegistration(ctx context.Context, id uuid.UUID) (pendingRegistration, bool, error) {
	text, ok, err := s.getJSONString(ctx, registrationKeyPrefix+id.String())
	if err != nil || !ok {
		return pendingRegistration{}, false, err
	}
	return parsePendingRegistration(text)
}

// findPendingRegistrationsByEmail は、Java 版の findByEmail と同じく、メールアドレスの集合の記録を
// すべて読み、作った日時の新しい順に並べて、先頭の limit 件を返す。
// 記録が無い ID(有効な時間で消えた記録と、読めない記録)は、集合から取り除く。
// 読めた記録が2件以上あり、どれかに作った日時が無いときは、Java 版の並べ替えが例外にするので、誤りを返す。
// 集合の要素が JSON の文字列の UUID でないときは、Java 版の UUID.fromString などが例外にするので、誤りを返す。
func (s *Service) findPendingRegistrationsByEmail(ctx context.Context, email string, limit int) ([]pendingRegistration, error) {
	emailKey := registrationEmailKeyPrefix + email
	members, err := s.smembersJSON(ctx, emailKey)
	if err != nil {
		return nil, err
	}
	found := []pendingRegistration{}
	for _, m := range members {
		var text string
		if err := json.Unmarshal(m, &text); err != nil {
			return nil, fmt.Errorf("auth: 登録の途中の記録の集合の要素が JSON の文字列でない: %w", err)
		}
		id, err := parseJavaUUIDText(text)
		if err != nil {
			return nil, err
		}
		r, ok, err := s.findPendingRegistration(ctx, id)
		if err != nil {
			return nil, err
		}
		if !ok {
			if err := s.sremJSON(ctx, emailKey, text); err != nil {
				return nil, err
			}
			continue
		}
		found = append(found, r)
	}
	if len(found) >= 2 && slices.ContainsFunc(found, func(r pendingRegistration) bool { return r.CreatedAt.IsZero() }) {
		return nil, fmt.Errorf("auth: 作った日時の無い登録の途中の記録を並べられない")
	}
	slices.SortStableFunc(found, func(a, b pendingRegistration) int { return b.CreatedAt.Compare(a.CreatedAt) })
	return found[:min(limit, len(found))], nil
}

// extendPendingRegistration は、Java 版の extend と同じく、ID の記録を読み、読めたときだけ、
// 記録とメールアドレスの集合の有効な時間を ttl に置き直す。
func (s *Service) extendPendingRegistration(ctx context.Context, id uuid.UUID, ttl time.Duration) error {
	if err := checkTTL(ttl); err != nil {
		return err
	}
	r, ok, err := s.findPendingRegistration(ctx, id)
	if err != nil || !ok {
		return err
	}
	for _, key := range []string{registrationKeyPrefix + id.String(), registrationEmailKeyPrefix + r.Email} {
		if err := s.deps.Redis.Expire(ctx, key, ttl).Err(); err != nil {
			return fmt.Errorf("auth: 登録の途中の記録の有効な時間を置き直せない: %w", err)
		}
	}
	return nil
}

// deletePendingRegistration は、Java 版の delete と同じく、記録を消し、メールアドレスの集合から記録の ID を除く。
func (s *Service) deletePendingRegistration(ctx context.Context, r pendingRegistration) error {
	if err := s.deleteKey(ctx, registrationKeyPrefix+r.ID.String()); err != nil {
		return err
	}
	return s.sremJSON(ctx, registrationEmailKeyPrefix+r.Email, r.ID.String())
}

// parsePendingRegistration は、記録の中の JSON を、Java 版の Jackson と同じ規則で読む。
// 先頭の値の読み方は parseJacksonObject のとおりである。id は parseJacksonUUID、文字列の項目は
// parseJacksonString、createdAt は parseJacksonInstant の規則で読み、どれかが読めないときは見つからないとする。
// 無い項目は、Java 版と同じく null として扱う。
func parsePendingRegistration(text string) (pendingRegistration, bool, error) {
	fields, ok, err := parseJacksonObject(text)
	if err != nil || !ok {
		return pendingRegistration{}, false, err
	}
	var r pendingRegistration
	if raw, ok := fields["id"]; ok {
		id, ok := parseJacksonUUID(raw)
		if !ok {
			return pendingRegistration{}, false, nil
		}
		if id != nil {
			r.ID = *id
		}
	}
	for name, dst := range map[string]*string{"email": &r.Email, "passwordHash": &r.PasswordHash, "username": &r.Username} {
		if raw, ok := fields[name]; ok {
			if *dst, ok = parseJacksonString(raw); !ok {
				return pendingRegistration{}, false, nil
			}
		}
	}
	if raw, ok := fields["createdAt"]; ok {
		if r.CreatedAt, ok = parseJacksonInstant(raw); !ok {
			return pendingRegistration{}, false, nil
		}
	}
	return r, true, nil
}

// parseJacksonString は、Jackson が JSON の値を Java の String の項目に読む規則で、値を読む。
// 文字列はそのまま、null は空の文字列にする。数は書かれたままの文字の並びに、真偽は "true" か "false" にする。
// オブジェクトと並びは読めないとする。
func parseJacksonString(raw json.RawMessage) (string, bool) {
	var v any
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if dec.Decode(&v) != nil {
		return "", false
	}
	switch t := v.(type) {
	case nil:
		return "", true
	case string:
		return t, true
	case json.Number:
		return t.String(), true
	case bool:
		return strconv.FormatBool(t), true
	default:
		return "", false
	}
}

// parseJacksonInstant は、Jackson の InstantDeserializer の規則で、JSON の値を日時として読む。
// null はゼロの値(日時が無い)にする。数は、1970年1月1日からの秒の数(小数は秒より細かい部分)として読む。
// 文字列は前後の U+0020 以下の文字を除き、空ならゼロの値、秒の数の形なら数と同じに読み、
// ほかは ISO 8601 の日時(T と Z の大文字と小文字を問わず、Z か +09:00 のような時差を付けた形)として読む。
// 真偽、オブジェクト、並び、時差の無い日時、ほかの文字列は読めないとする。
func parseJacksonInstant(raw json.RawMessage) (time.Time, bool) {
	var v any
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if dec.Decode(&v) != nil {
		return time.Time{}, false
	}
	switch t := v.(type) {
	case nil:
		return time.Time{}, true
	case json.Number:
		return epochSecondsTime(t.String())
	case string:
		s := javaTrim(t)
		if s == "" {
			return time.Time{}, true
		}
		if isEpochSecondsText(s) {
			return epochSecondsTime(s)
		}
		parsed, err := time.Parse(time.RFC3339Nano, strings.ToUpper(s))
		if err != nil {
			return time.Time{}, false
		}
		return parsed.UTC(), true
	default:
		return time.Time{}, false
	}
}

// isEpochSecondsText は、s が、符号の付いてよい10進の整数か、それに小数の部分を付けた形かを返す。
func isEpochSecondsText(s string) bool {
	s = strings.TrimPrefix(s, "-")
	whole, frac, _ := strings.Cut(s, ".")
	return whole != "" && strings.Trim(whole, "0123456789") == "" && strings.Trim(frac, "0123456789") == ""
}

// epochSecondsTime は、秒の数を書いた text を、Jackson と同じく、ナノ秒より細かい部分を0の向きに切り捨てた日時にする。
func epochSecondsTime(text string) (time.Time, bool) {
	r, ok := new(big.Rat).SetString(text)
	if !ok {
		return time.Time{}, false
	}
	nanos := new(big.Int).Quo(new(big.Int).Mul(r.Num(), big.NewInt(int64(time.Second))), r.Denom())
	sec, nsec := new(big.Int).QuoRem(nanos, big.NewInt(int64(time.Second)), new(big.Int))
	if !sec.IsInt64() {
		return time.Time{}, false
	}
	return time.Unix(sec.Int64(), nsec.Int64()).UTC(), true
}

// formatJavaInstant は、日時を、Java の Instant を Jackson が書く形(DateTimeFormatter.ISO_INSTANT)にする。
// 秒より細かい部分は、0なら書かず、ほかは3桁、6桁、9桁のうち要る桁数で書き、最後に Z を付ける。
func formatJavaInstant(t time.Time) string {
	t = t.UTC()
	text := t.Format("2006-01-02T15:04:05")
	switch ns := t.Nanosecond(); {
	case ns == 0:
	case ns%int(time.Millisecond) == 0:
		text += fmt.Sprintf(".%03d", ns/int(time.Millisecond))
	case ns%int(time.Microsecond) == 0:
		text += fmt.Sprintf(".%06d", ns/int(time.Microsecond))
	default:
		text += fmt.Sprintf(".%09d", ns)
	}
	return text + "Z"
}

// parseJavaUUIDText は、集合の要素の文字列を、ハイフンで区切った36文字の UUID として読む。
// 読めないときは、Java 版の UUID.fromString が例外にするので、誤りを返す。
func parseJavaUUIDText(text string) (uuid.UUID, error) {
	id, err := uuid.Parse(text)
	if err != nil || len(text) != 36 {
		return uuid.Nil, fmt.Errorf("auth: 登録の途中の記録の集合の要素が UUID でない")
	}
	return id, nil
}
