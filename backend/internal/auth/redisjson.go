package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// この節の関数は、Java 版の RedisConfig の直列化と同じ形で、Redis に値を書いて読む。
// Java 版の RedisConfig は、キーを文字列にし、値とハッシュの値を Jackson の JSON にする。
// そのため、文字列の値は、"..." で囲まれた JSON の文字列になる。
// 誤りの文には、キーを書かない。キーには、ログインを続けるための値などの秘密が入るためである。
//
// 構造体の値は、Jackson と同じく項目の順に書かれる。map の値は、Go がキーの順に並べ替えて書くので、
// Java 版と同じ順に書きたい値には構造体を使う。

// encodeJSON は、値を、Java 版の Jackson と同じ形の JSON の文字列にする。
// encoding/json の Encoder に SetEscapeHTML(false) を付けて < > & を置き換えないようにし、末尾の改行を取る。
// そのうえで、Encoder が Jackson と違う形で書く3つを、Jackson の形に直す。
func encodeJSON(v any) (string, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return "", fmt.Errorf("auth: 値を JSON にできない: %w", err)
	}
	return toJacksonEscapes(bytes.TrimSuffix(buf.Bytes(), []byte("\n")), true), nil
}

// encodeJSONText は、値を、Java 版の jsonMapper.writeValueAsString と同じ形の JSON にする。
// writeValueAsString は文字の並びに書くので、encodeJSON と違い、U+10000 以上の文字(絵文字など)を
// UTF-16 の2つ組にせず、そのまま書く。Java 版が、記録を JSON にしてから RedisTemplate で置く値の、内側の JSON に使う。
func encodeJSONText(v any) (string, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return "", fmt.Errorf("auth: 値を JSON にできない: %w", err)
	}
	return toJacksonEscapes(bytes.TrimSuffix(buf.Bytes(), []byte("\n")), false), nil
}

// toJacksonEscapes は、Encoder が書いた JSON の文字の書き方を、Java 版の Jackson と同じにする。
// Java 版の Jackson は、application.yaml の use-jackson2-defaults と、JsonMapperConfig で
// COMBINE_UNICODE_SURROGATES_IN_UTF8 を切った設定で動く。Encoder とは、次の3つが違う。
//   - Encoder は、U+2028 と U+2029 を \u2028 と \u2029 に置き換えるが、Jackson はそのまま書く
//   - Encoder は、制御文字を小文字の16進で \u001f と書くが、Jackson は大文字の16進で \u001F と書く
//   - Encoder は、U+10000 以上の文字(絵文字など)を UTF-8 のまま書くが、Jackson は UTF-16 の2つ組にして、
//     大文字の16進で \uD83D\uDE00 のように書く。ただし、Jackson は、文字の並びに書くとき(writeValueAsString)は、
//     U+10000 以上の文字をそのまま書く。pairSupplementary が偽のときは、この3つ目を直さない
//
// Encoder が書いた JSON では、逆斜線は、文字列の中の逃がしの始まりにしか現れず、
// U+10000 以上の文字は、文字列の中にしか現れない。
// そのため、逆斜線ごとに、続く1文字(\u のときは続く5文字)を1つの逃がしとして読めば、
// 元の文字列にあった逆斜線のあとの文字を書き換えることはない。
func toJacksonEscapes(b []byte, pairSupplementary bool) string {
	out := make([]byte, 0, len(b))
	for i := 0; i < len(b); {
		switch {
		case b[i] == '\\' && b[i+1] != 'u':
			out = append(out, b[i], b[i+1])
			i += 2
		case b[i] == '\\':
			hex := b[i+2 : i+6]
			switch string(hex) {
			case "2028":
				out = utf8.AppendRune(out, 0x2028)
			case "2029":
				out = utf8.AppendRune(out, 0x2029)
			default:
				out = append(out, '\\', 'u')
				out = append(out, bytes.ToUpper(hex)...)
			}
			i += 6
		case b[i] >= utf8.RuneSelf:
			r, size := utf8.DecodeRune(b[i:])
			if r >= 0x10000 && pairSupplementary {
				high, low := utf16.EncodeRune(r)
				out = appendUnicodeEscape(appendUnicodeEscape(out, high), low)
			} else {
				out = append(out, b[i:i+size]...)
			}
			i += size
		default:
			out = append(out, b[i])
			i++
		}
	}
	return string(out)
}

// appendUnicodeEscape は、UTF-16 の1つの値を、Jackson と同じく、逆斜線と u と大文字の4桁の16進で書き足す。
func appendUnicodeEscape(out []byte, r rune) []byte {
	out = append(out, '\\', 'u')
	return fmt.Appendf(out, "%04X", r)
}

// encodeJSONAll は、値の並びを、1つずつ JSON の文字列にする。
func encodeJSONAll(vs []any) ([]any, error) {
	out := make([]any, len(vs))
	for i, v := range vs {
		text, err := encodeJSON(v)
		if err != nil {
			return nil, err
		}
		out[i] = text
	}
	return out, nil
}

// checkTTL は、値に付ける有効な時間が0より長いかを確かめる。
// 0 以下の時間で EXPIRE を送ると、Redis はキーを消すためである。
// また、go-redis の SET は、0 なら有効な時間の無いキーを置き、redis.KeepTTL(-1)なら前の有効な時間を残すためである。
func checkTTL(ttl time.Duration) error {
	if ttl <= 0 {
		return fmt.Errorf("auth: Redis の値に付ける有効な時間 %v が0以下である", ttl)
	}
	return nil
}

// setJSON は、値を JSON にして、有効な時間を付けて置く。Java 版の opsForValue().set(key, v, ttl) にあたる。
func (s *Service) setJSON(ctx context.Context, key string, v any, ttl time.Duration) error {
	if err := checkTTL(ttl); err != nil {
		return err
	}
	text, err := encodeJSON(v)
	if err != nil {
		return err
	}
	if err := s.deps.Redis.Set(ctx, key, text, ttl).Err(); err != nil {
		return fmt.Errorf("auth: Redis に値を置けない: %w", err)
	}
	return nil
}

// setJSONNX は、キーが無いときだけ、値を JSON にして、有効な時間を付けて置く。置けたら真を返す。
// Java 版の opsForValue().setIfAbsent(key, v, ttl) にあたる。
func (s *Service) setJSONNX(ctx context.Context, key string, v any, ttl time.Duration) (bool, error) {
	if err := checkTTL(ttl); err != nil {
		return false, err
	}
	text, err := encodeJSON(v)
	if err != nil {
		return false, err
	}
	ok, err := s.deps.Redis.SetNX(ctx, key, text, ttl).Result()
	if err != nil {
		return false, fmt.Errorf("auth: Redis に値を置けない: %w", err)
	}
	return ok, nil
}

// getJSON は、キーの値を読み、JSON として dst に入れる。キーが無いときは偽を返す。
// Java 版の opsForValue().get(key) にあたる。
func (s *Service) getJSON(ctx context.Context, key string, dst any) (bool, error) {
	raw, err := s.deps.Redis.Get(ctx, key).Bytes()
	if errors.Is(err, redis.Nil) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("auth: Redis の値を読めない: %w", err)
	}
	if err := json.Unmarshal(raw, dst); err != nil {
		return false, fmt.Errorf("auth: Redis の値を JSON として読めない: %w", err)
	}
	return true, nil
}

// hsetJSON は、ハッシュの項目の値を1つずつ JSON にして置き、キーに有効な時間を付ける。
// Java 版の opsForHash().put(key, field, v) を項目の数だけ呼び、expire(key, ttl) を呼ぶのにあたる。
// 項目を置くことと有効な時間を付けることを1つのトランザクションで送り、有効な時間の無いキーを残さない。
func (s *Service) hsetJSON(ctx context.Context, key string, fields map[string]any, ttl time.Duration) error {
	if err := checkTTL(ttl); err != nil {
		return err
	}
	values := make(map[string]any, len(fields))
	for name, v := range fields {
		text, err := encodeJSON(v)
		if err != nil {
			return err
		}
		values[name] = text
	}
	_, err := s.deps.Redis.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
		pipe.HSet(ctx, key, values)
		pipe.Expire(ctx, key, ttl)
		return nil
	})
	if err != nil {
		return fmt.Errorf("auth: Redis のハッシュに値を置けない: %w", err)
	}
	return nil
}

// hgetallJSON は、ハッシュのすべての項目を読み、項目の名前ごとの JSON を返す。キーが無いときは空の束を返す。
// Java 版の opsForHash().get(key, field) にあたる。呼ぶ側は、項目ごとに json.Unmarshal で読む。
func (s *Service) hgetallJSON(ctx context.Context, key string) (map[string]json.RawMessage, error) {
	raw, err := s.deps.Redis.HGetAll(ctx, key).Result()
	if err != nil {
		return nil, fmt.Errorf("auth: Redis のハッシュを読めない: %w", err)
	}
	out := make(map[string]json.RawMessage, len(raw))
	for name, text := range raw {
		out[name] = json.RawMessage(text)
	}
	return out, nil
}

// saddJSON は、集合に要素を1つずつ JSON にして足し、キーに有効な時間を付ける。
// Java 版の opsForSet().add(key, v) と expire(key, ttl) にあたる。
// 要素を足すことと有効な時間を付けることを1つのトランザクションで送り、有効な時間の無いキーを残さない。
func (s *Service) saddJSON(ctx context.Context, key string, ttl time.Duration, members ...any) error {
	if err := checkTTL(ttl); err != nil {
		return err
	}
	texts, err := encodeJSONAll(members)
	if err != nil {
		return err
	}
	_, err = s.deps.Redis.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
		pipe.SAdd(ctx, key, texts...)
		pipe.Expire(ctx, key, ttl)
		return nil
	})
	if err != nil {
		return fmt.Errorf("auth: Redis の集合に要素を足せない: %w", err)
	}
	return nil
}

// smembersJSON は、集合のすべての要素を、1つずつ JSON のまま返す。キーが無いときは空の並びを返す。
// Java 版の opsForSet().members(key) にあたる。呼ぶ側は、要素ごとに json.Unmarshal で読む。
func (s *Service) smembersJSON(ctx context.Context, key string) ([]json.RawMessage, error) {
	raw, err := s.deps.Redis.SMembers(ctx, key).Result()
	if err != nil {
		return nil, fmt.Errorf("auth: Redis の集合を読めない: %w", err)
	}
	out := make([]json.RawMessage, len(raw))
	for i, text := range raw {
		out[i] = json.RawMessage(text)
	}
	return out, nil
}

// sremJSON は、集合から要素を取り除く。要素は、saddJSON と同じく JSON にして比べる。
// Java 版の opsForSet().remove(key, v) にあたる。
func (s *Service) sremJSON(ctx context.Context, key string, members ...any) error {
	texts, err := encodeJSONAll(members)
	if err != nil {
		return err
	}
	if err := s.deps.Redis.SRem(ctx, key, texts...).Err(); err != nil {
		return fmt.Errorf("auth: Redis の集合から要素を取り除けない: %w", err)
	}
	return nil
}

// consumeJSONIfEqual は、キーの値が、v を JSON にした値と同じときだけキーを消す。消せたら真を返す。
// Java 版の RedisEmailVerificationCurrentTokenStore と同じスクリプト(redisstore.ConsumeIfEqual)を使う。
func (s *Service) consumeJSONIfEqual(ctx context.Context, key string, v any) (bool, error) {
	text, err := encodeJSON(v)
	if err != nil {
		return false, err
	}
	n, err := redisstore.ConsumeIfEqual.Run(ctx, s.deps.Redis, []string{key}, text).Int64()
	if err != nil {
		return false, fmt.Errorf("auth: Redis の値を比べて消せない: %w", err)
	}
	return n == 1, nil
}
