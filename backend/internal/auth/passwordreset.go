package auth

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
)

// このファイルは、Java 版の RedisPasswordResetTokenStore を写す。
// 再設定の値の記録は、キー password-reset:<値> に、利用者の ID を JSON の文字列で、渡された有効な時間だけ置く。

const (
	passwordResetKeyPrefix = "password-reset:"
	// passwordResetTokenValidity は、再設定の申し込みで作る再設定の値の有効な時間である(Java 版の RequestPasswordResetUseCase)。
	// メールアドレスの確認から作る再設定の値には、Java 版の VerifyEmailUseCase と同じく、確認のリンクの残りの時間を付ける。
	passwordResetTokenValidity = 10 * time.Minute
)

// errPasswordResetUserID は、再設定の値の記録が UUID の文字列でないことを表す。
// Java 版は UUID.fromString が例外にし、500 で答える。
var errPasswordResetUserID = errors.New("auth: パスワードの再設定の値の記録が UUID でない")

// storePasswordResetToken は、再設定の値 token に、利用者の ID を ttl のあいだ置く(Java 版の store)。
// ttl が0以下のときは、記録を置かずに誤りを返す。
func (s *Service) storePasswordResetToken(ctx context.Context, token string, userID uuid.UUID, ttl time.Duration) error {
	return s.setJSON(ctx, passwordResetKeyPrefix+token, userID.String(), ttl)
}

// findPasswordResetUserID は、再設定の値 token の利用者の ID を返す。記録が無いときと、記録が JSON の null のときは、
// 偽を返す(Java 版の findUserId)。記録が文字列でないときと、UUID でないときは、Java 版が例外にするので、誤りを返す。
func (s *Service) findPasswordResetUserID(ctx context.Context, token string) (uuid.UUID, bool, error) {
	text, ok, err := s.getJSONString(ctx, passwordResetKeyPrefix+token)
	if err != nil || !ok {
		return uuid.Nil, false, err
	}
	userID, err := parseJavaUUIDText(text)
	if err != nil {
		return uuid.Nil, false, errPasswordResetUserID
	}
	return userID, true, nil
}

// removePasswordResetToken は、再設定の値 token の記録を消す(Java 版の remove)。記録が無くても誤りにしない。
func (s *Service) removePasswordResetToken(ctx context.Context, token string) error {
	return s.deleteKey(ctx, passwordResetKeyPrefix+token)
}
