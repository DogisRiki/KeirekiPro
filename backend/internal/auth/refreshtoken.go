package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// このファイルは、Java 版の RedisRefreshTokenStore と AuthSessionInvalidator を写す。
// ログインを続けるための値ごとに、ハッシュ refresh-token:<値> に項目 userId roles tokenVersion を置き、
// 利用者ごとの集合 user-refresh-tokens:<利用者の ID> に値を足す。項目の値と集合の要素は、Java 版と同じく
// JSON の文字列で置く。世代の番号も、Java 版の String.valueOf と同じく "0" のような文字列にする。

const (
	refreshTokenKeyPrefix = "refresh-token:"
	userRefreshKeyPrefix  = "user-refresh-tokens:"
	refreshFieldUserID    = "userId"
	refreshFieldRoles     = "roles"
	refreshFieldVersion   = "tokenVersion"
)

// refreshTokenInfo は、ログインを続けるための値に結び付いた、利用者の ID と役割と世代の番号である。
type refreshTokenInfo struct {
	UserID       uuid.UUID
	Roles        []string
	TokenVersion int64
}

// issueRefreshToken は、32バイトの乱数の base64url の値を作り、ハッシュと利用者の集合に置いて、値を返す。
// どちらにも、設定の JWT.RefreshTokenValidity の有効な時間を付ける。
func (s *Service) issueRefreshToken(ctx context.Context, userID uuid.UUID, roles []string, version int64) (string, error) {
	value, err := randomToken(s.deps.Random)
	if err != nil {
		return "", err
	}
	ttl := s.deps.JWT.RefreshTokenValidity
	fields := map[string]any{
		refreshFieldUserID:  userID.String(),
		refreshFieldRoles:   strings.Join(roles, ","),
		refreshFieldVersion: strconv.FormatInt(version, 10),
	}
	if err := s.hsetJSON(ctx, refreshTokenKeyPrefix+value, fields, ttl); err != nil {
		return "", err
	}
	if err := s.saddJSON(ctx, userRefreshKeyPrefix+userID.String(), ttl, value); err != nil {
		return "", err
	}
	return value, nil
}

// findRefreshToken は、値のハッシュを読む。Java 版の find と同じく、ハッシュが無いときと、
// 3つの項目のどれかが無いか JSON の文字列でないときは、見つからないとする。
// 利用者の ID か世代の番号を読めないときは、Java 版が例外にするので、誤りを返す。
func (s *Service) findRefreshToken(ctx context.Context, value string) (refreshTokenInfo, bool, error) {
	fields, err := s.hgetallJSON(ctx, refreshTokenKeyPrefix+value)
	if err != nil {
		return refreshTokenInfo{}, false, err
	}
	userIDText, ok1, err := jsonStringField(fields, refreshFieldUserID)
	if err != nil {
		return refreshTokenInfo{}, false, err
	}
	rolesText, ok2, err := jsonStringField(fields, refreshFieldRoles)
	if err != nil {
		return refreshTokenInfo{}, false, err
	}
	versionText, ok3, err := jsonStringField(fields, refreshFieldVersion)
	if err != nil {
		return refreshTokenInfo{}, false, err
	}
	if !ok1 || !ok2 || !ok3 {
		return refreshTokenInfo{}, false, nil
	}
	userID, err := uuid.Parse(userIDText)
	if err != nil {
		return refreshTokenInfo{}, false, fmt.Errorf("auth: ログインを続けるための値の利用者の ID を読めない: %w", err)
	}
	version, err := strconv.ParseInt(versionText, 10, 64)
	if err != nil {
		return refreshTokenInfo{}, false, fmt.Errorf("auth: ログインを続けるための値の世代の番号を読めない: %w", err)
	}
	roles := []string{}
	if rolesText != "" {
		roles = strings.Split(rolesText, ",")
	}
	return refreshTokenInfo{UserID: userID, Roles: roles, TokenVersion: version}, true, nil
}

// removeRefreshToken は、Java 版の remove と同じく、ハッシュの利用者の ID を読んでからハッシュを消し、
// 利用者の ID が読めたときは、その利用者の集合から値を除く。無い値を消しても誤りにしない。
func (s *Service) removeRefreshToken(ctx context.Context, value string) error {
	key := refreshTokenKeyPrefix + value
	fields, err := s.hgetallJSON(ctx, key)
	if err != nil {
		return err
	}
	userIDText, ok, err := jsonStringField(fields, refreshFieldUserID)
	if err != nil {
		return err
	}
	if err := s.deps.Redis.Del(ctx, key).Err(); err != nil {
		return fmt.Errorf("auth: ログインを続けるための値を消せない: %w", err)
	}
	if ok {
		return s.sremJSON(ctx, userRefreshKeyPrefix+userIDText, value)
	}
	return nil
}

// invalidateSessions は、Java 版の AuthSessionInvalidator と同じく、ログインの状態の世代の番号を1つ上げ、
// 利用者が持つログインを続けるための値をすべて消す。世代の番号を上げられないときは、値を消さずに誤りを返す。
func (s *Service) invalidateSessions(ctx context.Context, userID uuid.UUID) error {
	if err := s.BumpTokenVersion(ctx, sqlcgen.New(s.deps.Pool), userID); err != nil {
		return err
	}
	return s.removeAllRefreshTokens(ctx, userID)
}

// removeAllRefreshTokens は、Java 版の removeAllByUser と同じく、利用者の集合の要素ごとにハッシュを消し、
// 集合も消す。JSON の文字列でない要素は飛ばす。
func (s *Service) removeAllRefreshTokens(ctx context.Context, userID uuid.UUID) error {
	setKey := userRefreshKeyPrefix + userID.String()
	members, err := s.smembersJSON(ctx, setKey)
	if err != nil {
		return err
	}
	for _, m := range members {
		var value string
		if json.Unmarshal(m, &value) != nil {
			continue
		}
		if err := s.deps.Redis.Del(ctx, refreshTokenKeyPrefix+value).Err(); err != nil {
			return fmt.Errorf("auth: ログインを続けるための値を消せない: %w", err)
		}
	}
	if err := s.deps.Redis.Del(ctx, setKey).Err(); err != nil {
		return fmt.Errorf("auth: ログインを続けるための値の集合を消せない: %w", err)
	}
	return nil
}

// jsonStringField は、ハッシュの項目を JSON として読み、JSON の文字列なら、その文字列と真を返す。
// 項目が無いときと、JSON の文字列でない値(数、null、並びなど)のときは偽を返す。
// 項目が JSON として読めないときは、Java 版の直列化の部品が例外にするので、誤りを返す。
func jsonStringField(fields map[string]json.RawMessage, name string) (string, bool, error) {
	raw, ok := fields[name]
	if !ok {
		return "", false, nil
	}
	var v any
	if err := json.Unmarshal(raw, &v); err != nil {
		return "", false, fmt.Errorf("auth: ハッシュの項目 %s を JSON として読めない: %w", name, err)
	}
	text, ok := v.(string)
	return text, ok, nil
}
