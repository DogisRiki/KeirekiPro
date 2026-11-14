//go:build compat

package fakeaws_test

import (
	"bytes"
	"errors"
	"io"
	"net/http"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// TestS3_DoubleSlashKey は、名前が / で始まる画像を、版が置いた名前のまま置き、読み、消せることを確かめる。
// path-style の URL では、この名前の画像のパスは /<置き場所>//profile/image/... と // を含む。
// 偽の AWS は、このパスを、/ を1つにしたパスへ移すように答えてはならない。
func TestS3_DoubleSlashKey(t *testing.T) {
	f := newFixture(t)
	ctx := t.Context()
	client := f.s3("go")
	const bucket = "keirekipro-storage"
	const key = "/profile/image/6f1c2a3b-0000-4000-8000-000000000001.png"
	image := []byte("\x89PNG\r\n\x1a\n名前が / で始まる画像")

	if _, err := client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(bucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(image),
		ContentType: aws.String("image/png"),
	}); err != nil {
		t.Fatalf("PutObject: %v", err)
	}
	objects := f.server.Objects("go")
	if len(objects) != 1 || objects[0].Bucket != bucket || objects[0].Key != key || !bytes.Equal(objects[0].Body, image) {
		t.Fatalf("置いたオブジェクト = %+v, want 置き場所 %q 名前 %q", objects, bucket, key)
	}

	out, err := client.GetObject(ctx, &s3.GetObjectInput{Bucket: aws.String(bucket), Key: aws.String(key)})
	if err != nil {
		t.Fatalf("GetObject: %v", err)
	}
	got, err := io.ReadAll(out.Body)
	_ = out.Body.Close()
	if err != nil || !bytes.Equal(got, image) {
		t.Errorf("GetObject の本文 = %q, %v, want %q", got, err, image)
	}

	// 移るように答えないことを、移る先へ進まない HTTP のクライアントで確かめる
	noRedirect := &http.Client{
		Transport:     f.client.Transport,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint("go")+"/"+bucket+"/"+key, nil)
	if err != nil {
		t.Fatalf("要求を作れない: %v", err)
	}
	res, err := noRedirect.Do(req)
	if err != nil {
		t.Fatalf("GET %s: %v", req.URL, err)
	}
	raw, err := io.ReadAll(res.Body)
	_ = res.Body.Close()
	if res.StatusCode != http.StatusOK || err != nil || !bytes.Equal(raw, image) {
		t.Errorf("GET %s = %d %q (Location %q), want 200 と画像", req.URL, res.StatusCode, raw, res.Header.Get("Location"))
	}

	if _, err := client.DeleteObject(ctx, &s3.DeleteObjectInput{Bucket: aws.String(bucket), Key: aws.String(key)}); err != nil {
		t.Fatalf("DeleteObject: %v", err)
	}
	if objects := f.server.Objects("go"); len(objects) != 0 {
		t.Errorf("消したあとのオブジェクト = %+v", objects)
	}
	_, err = client.GetObject(ctx, &s3.GetObjectInput{Bucket: aws.String(bucket), Key: aws.String(key)})
	var noSuchKey interface{ ErrorCode() string }
	if !errors.As(err, &noSuchKey) || noSuchKey.ErrorCode() != "NoSuchKey" {
		t.Errorf("消したあとの GetObject の誤り = %v, want NoSuchKey", err)
	}
}
