package users

import (
	"bytes"
	"errors"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// objectStoreService は、小タスク1.7 の偽の AWS につなぐ Service を作る。
func objectStoreService(t *testing.T) (*Service, *s3.Client) {
	t.Helper()
	client := newTestS3(t)
	return New(Deps{S3: client, Bucket: testBucket, AWSEndpoint: testAWSEndpoint}), client
}

func TestObjectStore_PutDelete(t *testing.T) {
	s, client := objectStoreService(t)
	key := "/profile/image/objectstore-put-delete.gif"
	content := []byte("GIF89a object store")

	if err := s.put(t.Context(), key, content, "image/gif"); err != nil {
		t.Fatalf("put の誤り: %v", err)
	}

	out, err := client.GetObject(t.Context(), &s3.GetObjectInput{Bucket: aws.String(testBucket), Key: aws.String(key)})
	if err != nil {
		t.Fatalf("置いた画像を読めない: %v", err)
	}
	body, err := io.ReadAll(out.Body)
	_ = out.Body.Close()
	if err != nil {
		t.Fatalf("置いた画像の中身を読めない: %v", err)
	}
	if !bytes.Equal(body, content) {
		t.Errorf("置いた画像の中身 = %q、期待 = %q", body, content)
	}
	if got := aws.ToString(out.ContentType); got != "image/gif" {
		t.Errorf("Content-Type = %q、期待 = image/gif", got)
	}
	if len(out.Metadata) != 1 || out.Metadata["content-type"] != "image/gif" {
		t.Errorf("メタデータ = %v、期待 = content-type が image/gif", out.Metadata)
	}

	// 署名付きの URL で、置いた画像を読める。偽の AWS は署名を調べないが、/ が2つ続くパスから同じ画像を探す。
	signed, err := s.presign(t.Context(), key, 10*time.Minute)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	req, err := http.NewRequestWithContext(t.Context(), http.MethodGet, signed, nil)
	if err != nil {
		t.Fatalf("要求を作れない: %v", err)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("署名付きの URL に届かない: %v", err)
	}
	got, err := io.ReadAll(res.Body)
	_ = res.Body.Close()
	if err != nil || res.StatusCode != http.StatusOK || !bytes.Equal(got, content) {
		t.Errorf("署名付きの URL の答え = %d %q (%v)", res.StatusCode, got, err)
	}

	if err := s.delete(t.Context(), key); err != nil {
		t.Fatalf("delete の誤り: %v", err)
	}
	_, err = client.GetObject(t.Context(), &s3.GetObjectInput{Bucket: aws.String(testBucket), Key: aws.String(key)})
	var missing *types.NoSuchKey
	if !errors.As(err, &missing) {
		t.Errorf("消したあとの GetObject の誤り = %v、期待 = NoSuchKey", err)
	}
}

func TestObjectStore_DeleteMissingKey(t *testing.T) {
	s, _ := objectStoreService(t)
	if err := s.delete(t.Context(), "/profile/image/objectstore-missing.png"); err != nil {
		t.Errorf("無い画像の delete の誤り: %v", err)
	}
}
