package users

import (
	"context"
	"errors"
	"io/fs"
	"net/url"
	"os"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// presignKey は、testdata/presign/PresignExpected.java が署名する画像の名前と同じ名前である。
const presignKey = "/profile/image/0b6f3c2e-6a1d-4f7e-9c58-2d4a7e1b9f03.png"

// presignEndpoint は、Java 版の開発環境の設定 application-dev.yaml の AWS の接続先である。
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
		S3:                 &fakeS3{opts: s3.Options{Region: "ap-northeast-1", Credentials: provider}},
		Bucket:             "keirekipro-storage",
		AWSEndpoint:        endpoint,
		RewritePresignHost: rewrite,
		Now:                func() time.Time { return at },
	})
}

func dummyCredentials() aws.CredentialsProvider {
	return credentials.NewStaticCredentialsProvider("dummy", "dummy", "")
}

// expectedPresignURL は、Java 版の S3Presigner が作った正解の URL と、その URL の X-Amz-Date の時刻を返す。
func expectedPresignURL(t *testing.T) (string, time.Time) {
	t.Helper()
	b, err := fs.ReadFile(os.DirFS("testdata/presign"), "expected_url.txt")
	if err != nil {
		t.Fatalf("正解の URL を読めない: %v", err)
	}
	want := strings.TrimSpace(string(b))
	u, err := url.Parse(want)
	if err != nil {
		t.Fatalf("正解の URL を解けない: %v", err)
	}
	at, err := time.Parse("20060102T150405Z", u.Query().Get("X-Amz-Date"))
	if err != nil {
		t.Fatalf("正解の URL の X-Amz-Date を読めない: %v", err)
	}
	return want, at
}

// queryNames は、URL の問い合わせの項目の名前を、並んだ順に返す。
func queryNames(t *testing.T, raw string) []string {
	t.Helper()
	u, err := url.Parse(raw)
	if err != nil {
		t.Fatalf("URL を解けない: %v", err)
	}
	var names []string
	for item := range strings.SplitSeq(u.RawQuery, "&") {
		name, _, _ := strings.Cut(item, "=")
		names = append(names, name)
	}
	return names
}

func TestPresign_MatchesJava(t *testing.T) {
	t.Parallel()

	want, at := expectedPresignURL(t)
	got, err := presignService(dummyCredentials(), presignEndpoint, false, at).presign(t.Context(), presignKey, 600*time.Second)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	if got != want {
		t.Errorf("URL が Java 版と違う\n got  = %s\n want = %s", got, want)
	}
}

func TestPresign_SecurityTokenBeforeSignature(t *testing.T) {
	t.Parallel()

	at := time.Date(2026, 11, 13, 9, 0, 0, 0, time.UTC)
	provider := credentials.NewStaticCredentialsProvider("AKIDEXAMPLE", "examplesecret", "session/value+1")
	got, err := presignService(provider, "", false, at).presign(t.Context(), presignKey, 600*time.Second)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	wantNames := []string{
		"X-Amz-Algorithm", "X-Amz-Date", "X-Amz-SignedHeaders", "X-Amz-Credential", "X-Amz-Expires",
		"X-Amz-Security-Token", "X-Amz-Signature",
	}
	if names := queryNames(t, got); !slices.Equal(names, wantNames) {
		t.Errorf("問い合わせの項目の順 = %q、期待 = %q", names, wantNames)
	}
	// 接続先が無いときは、置き場所の名前をホストに入れた AWS の URL にする。画像の名前は / で始まるので、/ が2つ続く。
	wantPrefix := "https://keirekipro-storage.s3.ap-northeast-1.amazonaws.com/" + presignKey + "?"
	if !strings.HasPrefix(got, wantPrefix) {
		t.Errorf("URL = %s、期待する始まり = %s", got, wantPrefix)
	}
	u, err := url.Parse(got)
	if err != nil {
		t.Fatalf("URL を解けない: %v", err)
	}
	if v := u.Query().Get("X-Amz-Security-Token"); v != "session/value+1" {
		t.Errorf("X-Amz-Security-Token = %q", v)
	}
}

func TestPresign_LocalhostOnlyInDev(t *testing.T) {
	t.Parallel()

	want, at := expectedPresignURL(t)

	// 開発環境では、署名したあとに、接続先のホストの名前をすべて localhost に置き換える。署名は置き換える前の URL のものである。
	dev, err := presignService(dummyCredentials(), presignEndpoint, true, at).presign(t.Context(), presignKey, 600*time.Second)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	if wantDev := strings.ReplaceAll(want, "localstack", "localhost"); dev != wantDev {
		t.Errorf("開発環境の URL\n got  = %s\n want = %s", dev, wantDev)
	}

	// 開発環境でなければ、接続先があっても置き換えない。
	other, err := presignService(dummyCredentials(), presignEndpoint, false, at).presign(t.Context(), presignKey, 600*time.Second)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	if other != want {
		t.Errorf("開発環境でないときの URL\n got  = %s\n want = %s", other, want)
	}

	// 接続先が空のときは、置き換える設定でも置き換えない。
	prod, err := presignService(dummyCredentials(), "", true, at).presign(t.Context(), presignKey, 600*time.Second)
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

func TestPresign_BadEndpointAndKey(t *testing.T) {
	t.Parallel()

	at := time.Date(2026, 11, 13, 9, 0, 0, 0, time.UTC)
	if _, err := presignService(dummyCredentials(), "http://[::1", true, at).presign(t.Context(), presignKey, time.Minute); err == nil {
		t.Error("読めない接続先なのに誤りにならない")
	}
	if _, err := presignService(dummyCredentials(), presignEndpoint, false, at).presign(t.Context(), "/profile/image/%zz", time.Minute); err == nil {
		t.Error("URL にできない名前なのに誤りにならない")
	}
	// ホストの名前が空の接続先では、置き換える設定でも置き換えない。
	got, err := presignService(dummyCredentials(), "file:///storage", true, at).presign(t.Context(), presignKey, time.Minute)
	if err != nil {
		t.Fatalf("presign の誤り: %v", err)
	}
	if !strings.HasPrefix(got, "file:///storage/keirekipro-storage/"+presignKey+"?") || strings.Contains(got, "localhost") {
		t.Errorf("ホストの名前が空の接続先の URL = %s", got)
	}
}

func TestReorderPresignQuery(t *testing.T) {
	t.Parallel()

	const all = "X-Amz-Algorithm=a&X-Amz-Credential=c&X-Amz-Date=d&X-Amz-Expires=e&X-Amz-SignedHeaders=h"
	got, err := reorderPresignQuery("http://h/p?X-Amz-Signature=s&Z=1&" + all + "&A=2")
	if err != nil {
		t.Fatalf("並べ直しの誤り: %v", err)
	}
	want := "http://h/p?X-Amz-Algorithm=a&X-Amz-Date=d&X-Amz-SignedHeaders=h&X-Amz-Credential=c&X-Amz-Expires=e&Z=1&A=2&X-Amz-Signature=s"
	if got != want {
		t.Errorf("並べ直した URL = %s、期待 = %s", got, want)
	}

	for _, bad := range []string{
		"http://h/p",
		"http://h/p?" + all,
		"http://h/p?X-Amz-Algorithm=a&X-Amz-Credential=c&X-Amz-Date=d&X-Amz-SignedHeaders=h&X-Amz-Signature=s",
	} {
		if _, err := reorderPresignQuery(bad); err == nil {
			t.Errorf("%s を並べ直せてしまう", bad)
		}
	}
}
