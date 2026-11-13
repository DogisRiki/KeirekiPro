package users

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	v4 "github.com/aws/aws-sdk-go-v2/aws/signer/v4"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// presignQueryOrder は、Java 版の S3Presigner が作る署名付きの URL の、問い合わせの項目の順である。
// この5つのほかの項目は、5つのあと、X-Amz-Signature の前に、署名の部品が並べた順で置く。X-Amz-Signature は最後に置く。
var presignQueryOrder = []string{
	"X-Amz-Algorithm",
	"X-Amz-Date",
	"X-Amz-SignedHeaders",
	"X-Amz-Credential",
	"X-Amz-Expires",
}

// presignSignatureName は、署名付きの URL の署名の項目の名前である。
const presignSignatureName = "X-Amz-Signature"

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

// presign は、Java 版の S3ObjectStore の issueGetUrl と同じく、名前 key の画像を GET で読む、expires の間だけ使える URL を作る。
//
// URL は、Java 版の S3Presigner と1文字も違わない形にする。
//   - AWS の接続先があれば、<接続先>/<置き場所の名前>/<画像の名前> のパスの形にする。無ければ、置き場所の名前をホストに入れた
//     AWS の URL にする。画像の名前は / で始まるので、どちらの形でも / が2つ続く
//   - 画像の名前は、UUID と許可した拡張子だけからなるので、URL の中で置き換える字を含まない。署名は、パスの / を %2F に
//     置き換えずに計算する(S3 の決まり)
//   - 問い合わせの項目は、presignQueryOrder の順に並べ直す
//
// 開発環境では、Java 版の LocalstackPresignedUrlTransformer と同じく、署名したあとに、URL の中の接続先のホストの名前を、
// すべて localhost に置き換える。
func (s *Service) presign(ctx context.Context, key string, expires time.Duration) (string, error) {
	opts := s.deps.S3.Options()
	if opts.Credentials == nil {
		return "", errors.New("users: 署名付きの URL の資格情報がありません")
	}
	creds, err := opts.Credentials.Retrieve(ctx)
	if err != nil {
		return "", fmt.Errorf("users: 署名付きの URL の資格情報を取れません: %w", err)
	}

	base := "https://" + s.deps.Bucket + ".s3." + opts.Region + ".amazonaws.com"
	var endpoint *url.URL
	if s.deps.AWSEndpoint != "" {
		if endpoint, err = url.Parse(s.deps.AWSEndpoint); err != nil {
			return "", fmt.Errorf("users: AWS の接続先 %q を読めません: %w", s.deps.AWSEndpoint, err)
		}
		base = strings.TrimSuffix(s.deps.AWSEndpoint, "/") + "/" + s.deps.Bucket
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"/"+key, nil)
	if err != nil {
		return "", fmt.Errorf("users: 署名付きの URL を組み立てられません: %w", err)
	}
	req.URL.RawQuery = "X-Amz-Expires=" + strconv.FormatInt(int64(expires/time.Second), 10)

	signer := v4.NewSigner(func(o *v4.SignerOptions) { o.DisableURIPathEscaping = true })
	signed, _, err := signer.PresignHTTP(ctx, creds, req, "UNSIGNED-PAYLOAD", "s3", opts.Region, s.deps.Now().UTC())
	if err != nil {
		return "", fmt.Errorf("users: 署名付きの URL に署名できません: %w", err)
	}
	signed, err = reorderPresignQuery(signed)
	if err != nil {
		return "", err
	}

	// 接続先のホストの名前が空のときは置き換えない。空の文字列を置き換えると、すべての字の間に localhost が入るためである。
	if s.deps.RewritePresignHost && endpoint != nil {
		if host := endpoint.Hostname(); host != "" {
			signed = strings.ReplaceAll(signed, host, "localhost")
		}
	}
	return signed, nil
}

// reorderPresignQuery は、署名付きの URL の問い合わせの項目を、値の書き方を変えずに、presignQueryOrder の順に並べ直す。
func reorderPresignQuery(signed string) (string, error) {
	path, query, ok := strings.Cut(signed, "?")
	if !ok {
		return "", fmt.Errorf("users: 署名付きの URL に問い合わせがありません: %s", signed)
	}
	var head, others []string
	var signature string
	found := map[string]string{}
	for item := range strings.SplitSeq(query, "&") {
		name, _, _ := strings.Cut(item, "=")
		switch {
		case name == presignSignatureName:
			signature = item
		case slices.Contains(presignQueryOrder, name):
			found[name] = item
		default:
			others = append(others, item)
		}
	}
	for _, name := range presignQueryOrder {
		item, ok := found[name]
		if !ok {
			return "", fmt.Errorf("users: 署名付きの URL に %s がありません", name)
		}
		head = append(head, item)
	}
	if signature == "" {
		return "", fmt.Errorf("users: 署名付きの URL に %s がありません", presignSignatureName)
	}
	items := slices.Concat(head, others, []string{signature})
	return path + "?" + strings.Join(items, "&"), nil
}
