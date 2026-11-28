package users

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	v4 "github.com/aws/aws-sdk-go-v2/aws/signer/v4"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// put は、Java 版の S3ObjectStore の putAs と同じく、画像を名前 key で置く。Content-Type と、ユーザー定義のメタデータの
// Content-Type の両方に、部分の Content-Type をそのまま入れる。
func (s *Service) put(ctx context.Context, key string, content []byte, contentType string) error {
	_, err := s.deps.S3.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(s.deps.Bucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(content),
		ContentType: aws.String(contentType),
		Metadata:    map[string]string{"Content-Type": contentType},
	})
	if err != nil {
		return fmt.Errorf("users: 画像 %s を置けません: %w", key, err)
	}
	return nil
}

// delete は、Java 版の S3ObjectStore の delete と同じく、名前 key の画像を消す。S3 は、無い名前の削除にも成功を返す。
func (s *Service) delete(ctx context.Context, key string) error {
	_, err := s.deps.S3.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.deps.Bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return fmt.Errorf("users: 画像 %s を消せません: %w", key, err)
	}
	return nil
}

// presign は、名前 key の画像を GET で読む、expires の間だけ使える URL を、SDK の署名付きの URL の部品で作る。
//
// 開発環境では、署名したあとに、URL の中の接続先のホストの名前を、すべて localhost に置き換える。画面を開くブラウザは、
// コンテナの中の接続先のホストの名前を引けないためである。
func (s *Service) presign(ctx context.Context, key string, expires time.Duration) (string, error) {
	opts := s.deps.S3.Options()
	if opts.Credentials == nil {
		return "", errors.New("users: 署名付きの URL の資格情報がありません")
	}
	var endpoint *url.URL
	if s.deps.AWSEndpoint != "" {
		var err error
		if endpoint, err = url.Parse(s.deps.AWSEndpoint); err != nil {
			return "", fmt.Errorf("users: AWS の接続先 %q を読めません: %w", s.deps.AWSEndpoint, err)
		}
	}
	presigner := s3.NewPresignClient(s3.New(opts), s3.WithPresignExpires(expires), func(o *s3.PresignOptions) {
		o.Presigner = clockPresigner{signer: v4.NewSigner(), now: s.deps.Now}
	})
	req, err := presigner.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.deps.Bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return "", fmt.Errorf("users: 画像 %s の署名付きの URL を作れません: %w", key, err)
	}
	signed := req.URL

	// 接続先のホストの名前が空のときは置き換えない。空の文字列を置き換えると、すべての字の間に localhost が入るためである。
	if s.deps.RewritePresignHost && endpoint != nil {
		if host := endpoint.Hostname(); host != "" {
			signed = strings.ReplaceAll(signed, host, "localhost")
		}
	}
	return signed, nil
}

// clockPresigner は、SDK の署名の部品に、署名する時刻として Service の時刻の関数の値を渡す。SDK は、そのままでは
// 今の時刻で署名するためである。
type clockPresigner struct {
	signer *v4.Signer
	now    func() time.Time
}

// PresignHTTP は、要求 r に、Service の時刻の関数の値の時刻で署名した URL を返す。
func (p clockPresigner) PresignHTTP(
	ctx context.Context, credentials aws.Credentials, r *http.Request, payloadHash, service, region string,
	_ time.Time, optFns ...func(*v4.SignerOptions),
) (string, http.Header, error) {
	return p.signer.PresignHTTP(ctx, credentials, r, payloadHash, service, region, p.now().UTC(), optFns...)
}
