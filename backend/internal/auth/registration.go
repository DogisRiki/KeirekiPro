package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"time"

	"github.com/google/uuid"
)

// このファイルは、登録の途中の記録を Redis に置いて読む。
// 登録の途中の記録を、JSON にしてから、その JSON をさらに JSON の文字列にして pending-registration:<ID> に置き、
// メールアドレスごとの集合 pending-registration:email:<メールアドレス> に、記録の ID を JSON の文字列で足す。
// 読むときは、getText のとおり、JSON の文字列にした形と、そのままの形の、どちらでも読む。
// 記録の中の JSON は encoding/json で読み、読めない記録と、ID の無い記録は、無い記録として扱う。

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
// 記録の中の JSON を、この形で読む。null の項目と無い項目は、ゼロの値で持つ。CreatedAt のゼロの値は、作った日時が無いことを表す。
type pendingRegistration struct {
	ID           uuid.UUID `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"passwordHash"`
	Username     string    `json:"username"`
	CreatedAt    time.Time `json:"createdAt"`
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

// findPendingRegistration は、ID の記録を読む。
// 記録が無いとき、中の JSON を記録として読めないとき、記録に ID が無いときは、見つからないとする。
// 作った日時は、世界標準時に直して持つ。
func (s *Service) findPendingRegistration(ctx context.Context, id uuid.UUID) (pendingRegistration, bool, error) {
	text, ok, err := s.getText(ctx, registrationKeyPrefix+id.String())
	if err != nil || !ok {
		return pendingRegistration{}, false, err
	}
	var r pendingRegistration
	if json.Unmarshal([]byte(text), &r) != nil || r.ID == uuid.Nil {
		return pendingRegistration{}, false, nil
	}
	r.CreatedAt = r.CreatedAt.UTC()
	return r, true, nil
}

// findPendingRegistrationsByEmail は、メールアドレスの集合の記録をすべて読み、作った日時の新しい順に並べて、
// 先頭の limit 件を返す。作った日時の無い記録は、最も古い記録として並べる。
// 記録が無い ID(有効な時間で消えた記録と、読めない記録)は、集合から取り除く。
// 集合の要素が UUID でないときは、誤りを返す。
func (s *Service) findPendingRegistrationsByEmail(ctx context.Context, email string, limit int) ([]pendingRegistration, error) {
	emailKey := registrationEmailKeyPrefix + email
	members, err := s.deps.Redis.SMembers(ctx, emailKey).Result()
	if err != nil {
		return nil, fmt.Errorf("auth: Redis の集合を読めない: %w", err)
	}
	found := []pendingRegistration{}
	for _, m := range members {
		text, err := decodeStoredText(m)
		if err != nil {
			return nil, err
		}
		id, err := uuid.Parse(text)
		if err != nil {
			return nil, errors.New("auth: 登録の途中の記録の集合の要素が UUID でない")
		}
		r, ok, err := s.findPendingRegistration(ctx, id)
		if err != nil {
			return nil, err
		}
		if !ok {
			if err := s.deps.Redis.SRem(ctx, emailKey, m).Err(); err != nil {
				return nil, fmt.Errorf("auth: Redis の集合から要素を取り除けない: %w", err)
			}
			continue
		}
		found = append(found, r)
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

// deletePendingRegistration は、記録を消し、メールアドレスの集合から記録の ID を除く。
// 集合の要素は、JSON の文字列にした形と、そのままの形の、どちらも除く。
func (s *Service) deletePendingRegistration(ctx context.Context, r pendingRegistration) error {
	if err := s.deleteKey(ctx, registrationKeyPrefix+r.ID.String()); err != nil {
		return err
	}
	id := r.ID.String()
	if err := s.deps.Redis.SRem(ctx, registrationEmailKeyPrefix+r.Email, `"`+id+`"`, id).Err(); err != nil {
		return fmt.Errorf("auth: Redis の集合から要素を取り除けない: %w", err)
	}
	return nil
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
