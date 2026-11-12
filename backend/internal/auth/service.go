// Package auth は、認証の13の操作の処理を、Java 版の usecase/auth のユースケースと同じ順で行う。
// このパッケージは HTTP の要求と応答を扱わない。HTTP の受け口は internal/httpapi が受け持つ。
package auth

import (
	"context"
	"crypto/rand"
	"io/fs"
	"net/http"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/ses"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
)

// oidcHTTPTimeout は、Google と GitHub を呼び出すときの打ち切りの時間である。
const oidcHTTPTimeout = 10 * time.Second

// SESClient は、Service がメールを送るのに使う SES のクライアントである。
// *ses.Client がこのインタフェースを満たす。単体テストでは、偽の送り先に差し替える。
type SESClient interface {
	SendEmail(ctx context.Context, params *ses.SendEmailInput, optFns ...func(*ses.Options)) (*ses.SendEmailOutput, error)
}

// Deps は、Service が使う部品の束である。
type Deps struct {
	// Pool は、データベースの接続の束である。sqlcgen の Queries とトランザクションに使う。
	Pool *pgxpool.Pool
	// Redis は、要求をまたぐ記録を置く Redis のクライアントである。
	Redis redis.UniversalClient
	// SES は、メールを送る SES のクライアントである。
	SES SESClient
	// App と JWT と OIDC は、設定の値である。
	App  config.App
	JWT  config.JWT
	OIDC config.OIDC
	// MailTemplates は、メールのひな形のファイルを読む fs.FS である(backend.MailTemplates の結果)。
	MailTemplates fs.FS
	// HTTPClient は、Google と GitHub を呼び出す HTTP のクライアントである。
	// nil のとき、New は、打ち切りを10秒にしたクライアントを使う。
	HTTPClient *http.Client
	// Now は、今の時刻を返す関数である。nil のとき、New は time.Now を使う。
	Now func() time.Time
	// Random は、乱数でバイトの並びを埋める関数である。nil のとき、New は crypto/rand.Read を使う。
	Random func([]byte) (int, error)
}

// Service は、認証の13の操作の処理の入口である。要求をまたぐ状態をメモリに持たず、
// すべて Redis とデータベースに置く。そのため、Java 版と Go 版が同じ Redis とデータベースを使えば、
// 利用者は版をまたいで手順を続けられる。
type Service struct {
	deps Deps
}

// New は、部品の束から Service を作る。時刻と乱数と HTTP のクライアントを渡さなければ、本番の値を使う。
func New(d Deps) *Service {
	if d.HTTPClient == nil {
		d.HTTPClient = &http.Client{Timeout: oidcHTTPTimeout}
	}
	if d.Now == nil {
		d.Now = time.Now
	}
	if d.Random == nil {
		d.Random = rand.Read
	}
	return &Service{deps: d}
}
