package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// ErrInvalidToken は、ログインの状態の値を受け付けないときの誤りである。
// 署名か有効な時間か項目が合わないとき、または世代の番号がデータベースの今の番号と違うときに返す。
var ErrInvalidToken = errors.New("auth: ログインの状態の値を受け付けない")

// javaZone は、Java 版のコンテナの時間帯(Asia/Tokyo)である。Java 版は updated_at を、この時間帯の時刻の見た目で書く。
// 日本は夏時間を持たないので、時間帯のデータを読まずに、9時間の固定のずれで表す。
var javaZone = time.FixedZone("Asia/Tokyo", 9*3600)

// Principal は、受け付けたログインの状態の値が表す利用者である。
type Principal struct {
	UserID uuid.UUID
	// Roles は、役割の名前の並びである。値に役割が無いときは空の並びで、nil にしない。
	Roles []string
}

// accessClaims は、ログインの状態の値の項目である。Java 版の JwtProvider と同じ5つの項目を持つ。
type accessClaims struct {
	Roles        []string `json:"roles"`
	TokenVersion *int64   `json:"tokenVersion"`
	jwt.RegisteredClaims
}

// IssueAccessToken は、利用者のログインの状態の値を作る。
// 世代の番号は user_token_versions から読み、行が無ければ、Java 版と同じく 0 とする。
func (s *Service) IssueAccessToken(ctx context.Context, userID uuid.UUID, roles []string) (string, error) {
	version, err := s.tokenVersion(ctx, userID)
	if err != nil {
		return "", err
	}
	if roles == nil {
		roles = []string{}
	}
	// Java 版と同じく、時刻を秒に切り捨てて iat に書き、有効な時間を足して exp に書く。
	now := s.deps.Now().Truncate(time.Second)
	claims := accessClaims{
		Roles:        roles,
		TokenVersion: &version,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID.String(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.deps.JWT.AccessTokenValidity)),
		},
	}
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(s.deps.JWT.Secret))
	if err != nil {
		return "", fmt.Errorf("auth: ログインの状態の値に署名できない: %w", err)
	}
	return token, nil
}

// VerifyAccessToken は、ログインの状態の値を確かめ、値が表す利用者を返す。
// 署名の方式を HS256 に限り、exp を必須にし、時刻のずれの猶予を持たない(Java 版の java-jwt と同じ)。
// 受け付けないときは ErrInvalidToken を返す。データベースの誤りは ErrInvalidToken にせず、包んで返す。
func (s *Service) VerifyAccessToken(ctx context.Context, token string) (Principal, error) {
	var claims accessClaims
	_, err := jwt.ParseWithClaims(token, &claims,
		func(*jwt.Token) (any, error) { return []byte(s.deps.JWT.Secret), nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithExpirationRequired(),
		jwt.WithIssuedAt(),
		jwt.WithTimeFunc(s.deps.Now),
	)
	if err != nil {
		return Principal{}, fmt.Errorf("%w: %w", ErrInvalidToken, err)
	}
	userID, err := uuid.Parse(claims.Subject)
	if err != nil || claims.TokenVersion == nil {
		return Principal{}, ErrInvalidToken
	}
	version, err := s.tokenVersion(ctx, userID)
	if err != nil {
		return Principal{}, err
	}
	if *claims.TokenVersion != version {
		return Principal{}, ErrInvalidToken
	}
	roles := claims.Roles
	if roles == nil {
		roles = []string{}
	}
	return Principal{UserID: userID, Roles: roles}, nil
}

// BumpTokenVersion は、利用者の世代の番号を1つ上げ、updated_at を今の時刻にする。行が無ければ何もしない。
// q を渡すので、トランザクションの中でも外でも呼べる。
func (s *Service) BumpTokenVersion(ctx context.Context, q *sqlcgen.Queries, userID uuid.UUID) error {
	err := q.IncrementTokenVersion(ctx, sqlcgen.IncrementTokenVersionParams{
		UserID:    pgtype.UUID{Bytes: userID, Valid: true},
		UpdatedAt: pgtype.Timestamp{Time: s.deps.Now().In(javaZone), Valid: true},
	})
	if err != nil {
		return fmt.Errorf("auth: 世代の番号を上げられない: %w", err)
	}
	return nil
}

// tokenVersion は、利用者の今の世代の番号を読む。行が無ければ 0 を返す。
func (s *Service) tokenVersion(ctx context.Context, userID uuid.UUID) (int64, error) {
	version, err := sqlcgen.New(s.deps.Pool).GetTokenVersion(ctx, pgtype.UUID{Bytes: userID, Valid: true})
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	if err != nil {
		return 0, fmt.Errorf("auth: 世代の番号を読めない: %w", err)
	}
	return version, nil
}
