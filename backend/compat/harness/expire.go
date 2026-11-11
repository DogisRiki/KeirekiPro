//go:build compat

package harness

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// emailLinkLabel は、Java 版と Go 版が、メールアドレスの確認のリンクの値の署名の鍵を、HMAC-SHA256(JWT.Secret, この文字)で導くときの文字である。
const emailLinkLabel = "keirekipro-email-verification-v1"

// Expire は、値を期限切れにする段 step で、筋書きの中の JWT の値を期限の過ぎた値に書き換え、jwtKey(両方の版に渡した JWT.Secret)で署名し直す。
// expire.cookie なら Cookie の束のその名前の Cookie を、expire.var ならその名前の取り出した値を書き換える。
// 本体に aud がある値はメールアドレスの確認のリンクの値として lexp を今の1分前にし、無い値はログインの状態の値として
// iat を今の11分前に、exp を今の1分前にする。ほかの項目は写すので、利用者の ID と世代の番号と jti は残る。
// 書き換える値が無いときと、値が JWT として読めないときは、何も書き換えずに誤りを返す。
func (s *Session) Expire(step Step, jwtKey string) error {
	e := step.Expire
	if e == nil {
		return fmt.Errorf("harness: 段 %s は expire を持ちません", step.Name)
	}
	if e.Cookie != "" {
		var keys []cookieKey
		for key := range s.cookies {
			if key.name == e.Cookie {
				keys = append(keys, key)
			}
		}
		if len(keys) == 0 {
			return fmt.Errorf("harness: 段 %s で期限を切らす Cookie %s が、Cookie の束にありません", step.Name, e.Cookie)
		}
		expired := make(map[cookieKey]string, len(keys))
		for _, key := range keys {
			v, err := s.expireJWT(s.cookies[key], jwtKey)
			if err != nil {
				return fmt.Errorf("harness: 段 %s の Cookie %s を期限切れにできません: %w", step.Name, e.Cookie, err)
			}
			expired[key] = v
		}
		for key, v := range expired {
			s.cookies[key] = v
		}
		return nil
	}
	value, ok := s.vars[e.Var]
	if !ok {
		return fmt.Errorf("harness: 段 %s で期限を切らす値 %s を、前の段の capture で取り出していません", step.Name, e.Var)
	}
	v, err := s.expireJWT(value, jwtKey)
	if err != nil {
		return fmt.Errorf("harness: 段 %s の取り出した値 %s を期限切れにできません: %w", step.Name, e.Var, err)
	}
	s.vars[e.Var] = v
	return nil
}

// expireJWT は、JWT の値 token の期限の項目を過去にし、ヘッダはそのままで署名し直した値を返す。
func (s *Session) expireJWT(token, jwtKey string) (string, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return "", fmt.Errorf("値が、点で区切った3つの部分の JWT の形ではありません")
	}
	enc := base64.RawURLEncoding
	raw, err := enc.DecodeString(parts[1])
	if err != nil {
		return "", fmt.Errorf("JWT の本体を base64url として読めません: %w", err)
	}
	var claims map[string]json.RawMessage
	if err := json.Unmarshal(raw, &claims); err != nil {
		return "", fmt.Errorf("JWT の本体を JSON のオブジェクトとして読めません: %w", err)
	}
	if claims == nil {
		return "", fmt.Errorf("JWT の本体が JSON のオブジェクトではありません")
	}
	now := s.now()
	seconds := func(t time.Time) json.RawMessage { return json.RawMessage(strconv.FormatInt(t.Unix(), 10)) }
	key := []byte(jwtKey)
	if _, ok := claims["aud"]; ok {
		claims["lexp"] = seconds(now.Add(-time.Minute))
		mac := hmac.New(sha256.New, key)
		mac.Write([]byte(emailLinkLabel))
		key = mac.Sum(nil)
	} else {
		claims["iat"] = seconds(now.Add(-11 * time.Minute))
		claims["exp"] = seconds(now.Add(-time.Minute))
	}
	// json.Marshal は項目を名前の順に並べ、< > & を \u の形に逃がす。読む側の JSON の値は変わらない
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", fmt.Errorf("JWT の本体を JSON にできません: %w", err)
	}
	signing := parts[0] + "." + enc.EncodeToString(payload)
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(signing))
	return signing + "." + enc.EncodeToString(mac.Sum(nil)), nil
}
