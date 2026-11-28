package users

import (
	"context"
	"errors"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// presignKey は、署名付きの URL のテストで署名する画像の名前である。画像の名前は / で始まる。
const presignKey = "/profile/image/0b6f3c2e-6a1d-4f7e-9c58-2d4a7e1b9f03.png"

// presignEndpoint は、開発環境の AWS の接続先である。
const presignEndpoint = "http://localstack:4566"

// fakeS3 は、S3Client の偽物である。PutObject と DeleteObject は、渡された要求を覚え、err を返す。
type fakeS3 struct {
	opts    s3.Options
	err     error
	puts    []*s3.PutObjectInput
	deletes []*s3.DeleteObjectInput
}

func (f *fakeS3) PutObject(_ context.Context, in *s3.PutObjectInput, _ ...func(*s3.Options)) (*s3.PutObjectOutput, error) {
	f.puts = append(f.puts, in)
	if f.err != nil {
		return nil, f.err
	}
	return &s3.PutObjectOutput{}, nil
}

func (f *fakeS3) DeleteObject(_ context.Context, in *s3.DeleteObjectInput, _ ...func(*s3.Options)) (*s3.DeleteObjectOutput, error) {
	f.deletes = append(f.deletes, in)
	if f.err != nil {
		return nil, f.err
	}
	return &s3.DeleteObjectOutput{}, nil
}

func (f *fakeS3) Options() s3.Options { return f.opts }

// presignService は、地域 ap-northeast-1 と、渡した資格情報と接続先で、時刻 at に署名する Service を作る。
func presignService(provider aws.CredentialsProvider, endpoint string, rewrite bool, at time.Time) *Service {
	return New(Deps{
		S3:                 &fakeS3{opts: presignOptions(provider, endpoint)},
		Bucket:             "keirekipro-storage",
		AWSEndpoint:        endpoint,
		RewritePresignHost: rewrite,
		Now:                func() time.Time { return at },
	})
}

func dummyCredentials() aws.CredentialsProvider {
	return credentials.NewStaticCredentialsProvider("dummy", "dummy", "")
}

// presignOptions は、awsclient と同じく、接続先があればパスの形の URL にする S3 の設定を返す。
func presignOptions(provider aws.CredentialsProvider, endpoint string) s3.Options {
	opts := s3.Options{Region: "ap-northeast-1", Credentials: provider}
	if endpoint != "" {
		opts.BaseEndpoint = aws.String(endpoint)
		opts.UsePathStyle = true
	}
	return opts
}

// presignAt は、署名付きの URL のテストで署名する時刻である。
var presignAt = time.Date(2026, 11, 13, 9, 0, 0, 0, time.UTC)

// parsePresigned は、署名付きの URL を解き、問い合わせの項目を返す。
func parsePresigned(t *testing.T, raw string) (*url.URL, url.Values) {
	t.Helper()
	u, err := url.Parse(raw)
	if err != nil {
		t.Fatalf("URL を解けない: %v", err)
	}
	return u, u.Query()
}

func TestPresign_URL(t *testing.T) {
	t.Parallel()

	s := presignService(dummyCredentials(), presignEndpoint, false, presignAt)
	got, err := s.presign(t.Context(), presignKey, 600*time.Second)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	// 接続先があれば、<接続先>/<置き場所の名前>/<画像の名前> のパスの形にする。画像の名前は / で始まるので、/ が2つ続く。
	u, q := parsePresigned(t, got)
	if base := u.Scheme + "://" + u.Host + u.EscapedPath(); base != presignEndpoint+"/keirekipro-storage/"+presignKey {
		t.Errorf("URL の問い合わせの前 = %s", base)
	}
	want := map[string]string{
		"X-Amz-Algorithm":     "AWS4-HMAC-SHA256",
		"X-Amz-Credential":    "dummy/20261113/ap-northeast-1/s3/aws4_request",
		"X-Amz-Date":          "20261113T090000Z",
		"X-Amz-Expires":       "600",
		"X-Amz-SignedHeaders": "host",
	}
	for name, v := range want {
		if q.Get(name) != v {
			t.Errorf("%s = %q、期待 = %q", name, q.Get(name), v)
		}
	}
	if len(q.Get("X-Amz-Signature")) != 64 {
		t.Errorf("X-Amz-Signature = %q", q.Get("X-Amz-Signature"))
	}
	if q.Has("X-Amz-Security-Token") {
		t.Error("一時的でない資格情報なのに X-Amz-Security-Token がある")
	}

	// 同じ時刻に署名すれば、同じ URL になる。
	again, err := s.presign(t.Context(), presignKey, 600*time.Second)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	if again != got {
		t.Errorf("同じ時刻の URL が違う\n 1回目 = %s\n 2回目 = %s", got, again)
	}
}

func TestPresign_SecurityToken(t *testing.T) {
	t.Parallel()

	provider := credentials.NewStaticCredentialsProvider("AKIDEXAMPLE", "examplesecret", "session/value+1")
	got, err := presignService(provider, "", false, presignAt).presign(t.Context(), presignKey, 600*time.Second)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	// 接続先が無いときは、置き場所の名前をホストに入れた AWS の URL にする。
	wantPrefix := "https://keirekipro-storage.s3.ap-northeast-1.amazonaws.com/" + presignKey + "?"
	if !strings.HasPrefix(got, wantPrefix) {
		t.Errorf("URL = %s、期待する始まり = %s", got, wantPrefix)
	}
	if _, q := parsePresigned(t, got); q.Get("X-Amz-Security-Token") != "session/value+1" {
		t.Errorf("X-Amz-Security-Token = %q", q.Get("X-Amz-Security-Token"))
	}
}

func TestPresign_LocalhostOnlyInDev(t *testing.T) {
	t.Parallel()

	// 開発環境でなければ、接続先があっても置き換えない。
	other, err := presignService(dummyCredentials(), presignEndpoint, false, presignAt).presign(t.Context(), presignKey, 600*time.Second)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	if !strings.HasPrefix(other, presignEndpoint+"/") {
		t.Errorf("開発環境でないときの URL = %s", other)
	}

	// 開発環境では、署名したあとに、接続先のホストの名前をすべて localhost に置き換える。署名は置き換える前の URL のものである。
	dev, err := presignService(dummyCredentials(), presignEndpoint, true, presignAt).presign(t.Context(), presignKey, 600*time.Second)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	if want := strings.ReplaceAll(other, "localstack", "localhost"); dev != want {
		t.Errorf("開発環境の URL\n got  = %s\n want = %s", dev, want)
	}

	// 接続先が空のときは、置き換える設定でも置き換えない。
	prod, err := presignService(dummyCredentials(), "", true, presignAt).presign(t.Context(), presignKey, 600*time.Second)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	if !strings.HasPrefix(prod, "https://keirekipro-storage.s3.ap-northeast-1.amazonaws.com/") || strings.Contains(prod, "localhost") {
		t.Errorf("接続先が空のときの URL = %s", prod)
	}
}

func TestPresign_CredentialsError(t *testing.T) {
	t.Parallel()

	at := time.Date(2026, 11, 13, 9, 0, 0, 0, time.UTC)
	if _, err := presignService(nil, presignEndpoint, false, at).presign(t.Context(), presignKey, time.Minute); err == nil {
		t.Error("資格情報が無いのに誤りにならない")
	}
	failing := aws.CredentialsProviderFunc(func(context.Context) (aws.Credentials, error) {
		return aws.Credentials{}, errors.New("資格情報を取れない")
	})
	if _, err := presignService(failing, presignEndpoint, false, at).presign(t.Context(), presignKey, time.Minute); err == nil {
		t.Error("資格情報を取れないのに誤りにならない")
	}
}

func TestObjectStore_PutDeleteRequests(t *testing.T) {
	t.Parallel()

	f := &fakeS3{}
	s := New(Deps{S3: f, Bucket: "keirekipro-storage"})
	if err := s.put(t.Context(), presignKey, []byte("abc"), "image/png"); err != nil {
		t.Fatalf("put の誤り: %v", err)
	}
	if err := s.delete(t.Context(), presignKey); err != nil {
		t.Fatalf("delete の誤り: %v", err)
	}
	if len(f.puts) != 1 || len(f.deletes) != 1 {
		t.Fatalf("PutObject %d 回、DeleteObject %d 回", len(f.puts), len(f.deletes))
	}
	p := f.puts[0]
	if aws.ToString(p.Bucket) != "keirekipro-storage" || aws.ToString(p.Key) != presignKey || aws.ToString(p.ContentType) != "image/png" {
		t.Errorf("PutObject の置き場所 = %q、名前 = %q、Content-Type = %q", aws.ToString(p.Bucket), aws.ToString(p.Key), aws.ToString(p.ContentType))
	}
	if len(p.Metadata) != 1 || p.Metadata["Content-Type"] != "image/png" {
		t.Errorf("PutObject のメタデータ = %v", p.Metadata)
	}
	d := f.deletes[0]
	if aws.ToString(d.Bucket) != "keirekipro-storage" || aws.ToString(d.Key) != presignKey {
		t.Errorf("DeleteObject の置き場所 = %q、名前 = %q", aws.ToString(d.Bucket), aws.ToString(d.Key))
	}
}

func TestObjectStore_WrapsErrors(t *testing.T) {
	t.Parallel()

	cause := errors.New("S3 に届かない")
	s := New(Deps{S3: &fakeS3{err: cause}, Bucket: "keirekipro-storage"})
	if err := s.put(t.Context(), presignKey, []byte("abc"), "image/png"); !errors.Is(err, cause) {
		t.Errorf("put の誤り = %v、元の誤りを包んでいない", err)
	}
	if err := s.delete(t.Context(), presignKey); !errors.Is(err, cause) {
		t.Errorf("delete の誤り = %v、元の誤りを包んでいない", err)
	}
}

func TestPresign_BadEndpoint(t *testing.T) {
	t.Parallel()

	at := time.Date(2026, 11, 13, 9, 0, 0, 0, time.UTC)
	if _, err := presignService(dummyCredentials(), "http://[::1", true, at).presign(t.Context(), presignKey, time.Minute); err == nil {
		t.Error("読めない接続先なのに誤りにならない")
	}
	// ホストの名前が空の接続先では、置き換える設定でも置き換えない。
	got, err := presignService(dummyCredentials(), "http://:4566", true, at).presign(t.Context(), presignKey, time.Minute)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	if !strings.HasPrefix(got, "http://:4566/keirekipro-storage/"+presignKey+"?") || strings.Contains(got, "localhost") {
		t.Errorf("ホストの名前が空の接続先の URL = %s", got)
	}
}
