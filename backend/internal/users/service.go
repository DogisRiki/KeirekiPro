// Package users は、利用者の7つの操作の処理を、Java 版の usecase/user のユースケースと同じ順で行う。
// このパッケージは HTTP の要求と応答を扱わない。HTTP の受け口は internal/httpapi が受け持つ。
package users

import (
	"context"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// S3Client は、Service が画像を置いて消し、署名付きの URL を作るのに使う S3 のクライアントである。
// *s3.Client がこのインタフェースを満たす。Options は、署名付きの URL を作るときの設定に使う。
type S3Client interface {
	PutObject(ctx context.Context, params *s3.PutObjectInput, optFns ...func(*s3.Options)) (*s3.PutObjectOutput, error)
	DeleteObject(ctx context.Context, params *s3.DeleteObjectInput, optFns ...func(*s3.Options)) (*s3.DeleteObjectOutput, error)
	Options() s3.Options
}

// *s3.Client が S3Client を満たすことを、ビルドのときに確かめる。
var _ S3Client = (*s3.Client)(nil)

// Deps は、Service が使う部品の束である。
type Deps struct {
	// Pool は、データベースの接続の束である。sqlcgen の Queries とトランザクションに使う。
	Pool *pgxpool.Pool
	// Redis は、要求をまたぐ記録を置く Redis のクライアントである。
	Redis redis.UniversalClient
	// Auth は、利用者の行の読み書きと、確認のメールと、ログインの状態を使えなくする処理と、
	// 退会の完了のメールを呼ぶ、認証の処理の入口である。
	Auth *auth.Service
	// S3 は、画像の置き場所の S3 のクライアントである。
	S3 S3Client
	// Bucket は、画像の置き場所の名前である(設定 App.S3Bucket の値)。
	Bucket string
	// RewritePresignHost は、署名付きの URL の中の AWS の接続先のホストの名前を localhost に置き換えるかどうかである。
	// 設定 Env が dev のときに true にする。Java 版の LocalstackPresignedUrlTransformer にあたる。
	RewritePresignHost bool
	// AWSEndpoint は、dev と test で AWS の代わりにつなぐ先の URL である。空のときは、ホストの名前を置き換えない。
	AWSEndpoint string
	// Now は、今の時刻を返す関数である。nil のとき、New は time.Now を使う。
	Now func() time.Time
}

// Service は、利用者の7つの操作の処理の入口である。要求をまたぐ状態をメモリに持たず、
// すべて Redis とデータベースと画像の置き場所に置く。
type Service struct {
	deps Deps
}

// New は、部品の束から Service を作る。時刻の関数を渡さなければ、time.Now を使う。
func New(d Deps) *Service {
	if d.Now == nil {
		d.Now = time.Now
	}
	return &Service{deps: d}
}
