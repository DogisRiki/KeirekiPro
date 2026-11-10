//go:build compat

package fakeaws_test

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"reflect"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/aws/aws-sdk-go-v2/service/ses"
	sestypes "github.com/aws/aws-sdk-go-v2/service/ses/types"
	"github.com/aws/smithy-go"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
	"github.com/DogisRiki/KeirekiPro/backend/compat/harness"
)

// fixture は、テストの処理の中で動かす fakeaws と、宛先のホスト名にかかわらずそのサーバにつなぐ HTTP のクライアントである。
type fixture struct {
	server *fakeaws.Server
	client *http.Client
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	server := fakeaws.NewServer()
	srv := httptest.NewServer(server)
	t.Cleanup(srv.Close)
	addr := srv.Listener.Addr().String()
	return fixture{
		server: server,
		client: &http.Client{Transport: &http.Transport{
			DialContext: func(ctx context.Context, network, _ string) (net.Conn, error) {
				var d net.Dialer
				return d.DialContext(ctx, network, addr)
			},
		}},
	}
}

// endpoint は、版 version の Java 版か Go 版がつなぐ先の URL である。
func endpoint(version string) string {
	return "http://" + fakeaws.HostPrefix + version + ":" + fakeaws.Port
}

func (f fixture) awsConfig(version string) aws.Config {
	return aws.Config{
		Region:       "ap-northeast-1",
		Credentials:  credentials.NewStaticCredentialsProvider("dummy", "dummy", ""),
		HTTPClient:   f.client,
		BaseEndpoint: aws.String(endpoint(version)),
	}
}

func (f fixture) s3(version string) *s3.Client {
	return s3.NewFromConfig(f.awsConfig(version), func(o *s3.Options) { o.UsePathStyle = true })
}

func TestS3_PutGetDelete(t *testing.T) {
	f := newFixture(t)
	ctx := t.Context()
	java, goClient := f.s3("java"), f.s3("go")
	image := []byte("\x89PNG\r\n\x1a\nJava 版の画像")

	_, err := java.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String("keirekipro"),
		Key:         aws.String("users/u1/profile.png"),
		Body:        bytes.NewReader(image),
		ContentType: aws.String("image/png"),
		Metadata:    map[string]string{"Content-Type": "image/png"},
	})
	if err != nil {
		t.Fatalf("PutObject: %v", err)
	}

	out, err := java.GetObject(ctx, &s3.GetObjectInput{Bucket: aws.String("keirekipro"), Key: aws.String("users/u1/profile.png")})
	if err != nil {
		t.Fatalf("GetObject: %v", err)
	}
	got, err := io.ReadAll(out.Body)
	_ = out.Body.Close()
	if err != nil || !bytes.Equal(got, image) {
		t.Errorf("GetObject の本文 = %q, %v, want %q", got, err, image)
	}
	if aws.ToString(out.ContentType) != "image/png" || out.Metadata["content-type"] != "image/png" {
		t.Errorf("GetObject の Content-Type と metadata = %q %v", aws.ToString(out.ContentType), out.Metadata)
	}

	// 比べる検査は、版が置いたオブジェクトを読める。ほかの版には見えない
	objects := f.server.Objects("java")
	if len(objects) != 1 || objects[0].Bucket != "keirekipro" || objects[0].Key != "users/u1/profile.png" ||
		objects[0].ContentType != "image/png" || !bytes.Equal(objects[0].Body, image) {
		t.Errorf("java の版のオブジェクト = %+v", objects)
	}
	if objects := f.server.Objects("go"); len(objects) != 0 {
		t.Errorf("go の版に java の版のオブジェクトが見えます: %+v", objects)
	}
	_, err = goClient.GetObject(ctx, &s3.GetObjectInput{Bucket: aws.String("keirekipro"), Key: aws.String("users/u1/profile.png")})
	var noSuchKey interface{ ErrorCode() string }
	if !errors.As(err, &noSuchKey) || noSuchKey.ErrorCode() != "NoSuchKey" {
		t.Errorf("go の版の GetObject の誤り = %v, want NoSuchKey", err)
	}

	if _, err := java.DeleteObject(ctx, &s3.DeleteObjectInput{Bucket: aws.String("keirekipro"), Key: aws.String("users/u1/profile.png")}); err != nil {
		t.Fatalf("DeleteObject: %v", err)
	}
	if objects := f.server.Objects("java"); len(objects) != 0 {
		t.Errorf("消したあとのオブジェクト = %+v", objects)
	}
	_, err = java.GetObject(ctx, &s3.GetObjectInput{Bucket: aws.String("keirekipro"), Key: aws.String("users/u1/profile.png")})
	if !errors.As(err, &noSuchKey) || noSuchKey.ErrorCode() != "NoSuchKey" {
		t.Errorf("消したあとの GetObject の誤り = %v, want NoSuchKey", err)
	}
}

func TestS3_PresignedGet(t *testing.T) {
	f := newFixture(t)
	ctx := t.Context()
	pdf := []byte("%PDF-1.7 Go 版の職務経歴書")
	if _, err := f.s3("go").PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String("keirekipro"),
		Key:         aws.String("exports/resume.pdf"),
		Body:        bytes.NewReader(pdf),
		ContentType: aws.String("application/pdf"),
	}); err != nil {
		t.Fatalf("PutObject: %v", err)
	}

	presigned, err := s3.NewPresignClient(f.s3("go")).PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String("keirekipro"), Key: aws.String("exports/resume.pdf"),
	}, s3.WithPresignExpires(5*time.Minute))
	if err != nil {
		t.Fatalf("PresignGetObject: %v", err)
	}
	if !strings.Contains(presigned.URL, "X-Amz-Signature=") {
		t.Fatalf("署名付きの URL に署名がありません: %s", presigned.URL)
	}

	// 利用者の画面と同じく、署名付きの URL に、署名のほかに何も付けずに GET を送る
	get := func(url string) (int, []byte, string) {
		t.Helper()
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
		if err != nil {
			t.Fatal(err)
		}
		resp, err := f.client.Do(req)
		if err != nil {
			t.Fatalf("GET %s: %v", url, err)
		}
		defer func() { _ = resp.Body.Close() }()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			t.Fatal(err)
		}
		return resp.StatusCode, body, resp.Header.Get("Content-Type")
	}
	status, body, contentType := get(presigned.URL)
	if status != http.StatusOK || !bytes.Equal(body, pdf) || contentType != "application/pdf" {
		t.Errorf("署名付きの URL の GET = %d %q %q, want 200 の PDF", status, body, contentType)
	}
	// 署名付きの URL も、宛先のホスト名の版のオブジェクトだけを返す
	other := strings.Replace(presigned.URL, endpoint("go"), endpoint("java"), 1)
	if status, _, _ := get(other); status != http.StatusNotFound {
		t.Errorf("java の版への署名付きの URL の GET = %d, want 404", status)
	}
}

func TestSendEmail_RecordsPerVersion(t *testing.T) {
	f := newFixture(t)
	ctx := t.Context()
	send := func(version, subject, body string) {
		t.Helper()
		out, err := ses.NewFromConfig(f.awsConfig(version)).SendEmail(ctx, &ses.SendEmailInput{
			Source:      aws.String("no-reply@keirekipro.example"),
			Destination: &sestypes.Destination{ToAddresses: []string{"user1@example.com", "user2@example.com"}},
			Message: &sestypes.Message{
				Subject: &sestypes.Content{Data: aws.String(subject), Charset: aws.String("UTF-8")},
				Body:    &sestypes.Body{Text: &sestypes.Content{Data: aws.String(body), Charset: aws.String("UTF-8")}},
			},
		})
		if err != nil {
			t.Fatalf("%s の版の SendEmail: %v", version, err)
		}
		if aws.ToString(out.MessageId) == "" {
			t.Errorf("%s の版の SendEmail の MessageId が空です", version)
		}
	}
	send("java", "【KeirekiPro】認証コード", "認証コードは 123456 です。")
	send("go", "【KeirekiPro】認証コード", "認証コードは 654321 です。")
	send("go", "【KeirekiPro】パスワードの再設定", "次の URL から再設定してください。")

	java := f.server.Emails("java")
	if len(java) != 1 {
		t.Fatalf("java の版のメール = %+v, want 1通", java)
	}
	want := fakeaws.Email{
		Source:  "no-reply@keirekipro.example",
		To:      []string{"user1@example.com", "user2@example.com"},
		Subject: "【KeirekiPro】認証コード",
		Text:    "認証コードは 123456 です。",
	}
	if !reflect.DeepEqual(java[0], want) {
		t.Errorf("java の版のメール = %+v, want %+v", java[0], want)
	}
	goMails := f.server.Emails("go")
	if len(goMails) != 2 || goMails[0].Text != "認証コードは 654321 です。" || goMails[1].Subject != "【KeirekiPro】パスワードの再設定" {
		t.Errorf("go の版のメール = %+v, want 送った順の2通", goMails)
	}

	// 比べる検査は、筋書きの始めに記録を空にする
	f.server.ClearRecords()
	if n := len(f.server.Emails("java")) + len(f.server.Emails("go")); n != 0 {
		t.Errorf("記録を空にしたあとのメール = %d通, want 0通", n)
	}
}

func TestSecretsManager_GetSecretValue(t *testing.T) {
	f := newFixture(t)
	ctx := t.Context()
	const rds = `{"host":"postgres-java","port":"5432","username":"keirekipro","password":"keirekipro","dbname":"keirekipro"}`
	f.server.SetSecret("java", "keirekipro/rds", rds)

	client := secretsmanager.NewFromConfig(f.awsConfig("java"))
	out, err := client.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{SecretId: aws.String("keirekipro/rds")})
	if err != nil {
		t.Fatalf("GetSecretValue: %v", err)
	}
	if aws.ToString(out.SecretString) != rds || aws.ToString(out.Name) != "keirekipro/rds" {
		t.Errorf("GetSecretValue = %q %q, want 登録した値", aws.ToString(out.Name), aws.ToString(out.SecretString))
	}

	// 登録していない名前と、ほかの版に登録した名前は、AWS と同じ誤りにする
	for _, tc := range []struct{ version, name string }{{"java", "keirekipro/jwt"}, {"go", "keirekipro/rds"}} {
		_, err := secretsmanager.NewFromConfig(f.awsConfig(tc.version)).
			GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{SecretId: aws.String(tc.name)})
		var apiErr smithy.APIError
		if !errors.As(err, &apiErr) || apiErr.ErrorCode() != "ResourceNotFoundException" {
			t.Errorf("%s の版の %s の誤り = %v, want ResourceNotFoundException", tc.version, tc.name, err)
		}
	}
}

// TestS3_PutAWSChunked は、Java 版の AWS の SDK が送る aws-chunked の形の本文から、中身だけを覚えることを確かめる。
func TestS3_PutAWSChunked(t *testing.T) {
	f := newFixture(t)
	body := "5;chunk-signature=aaaa\r\nhello\r\n6;chunk-signature=bbbb\r\n world\r\n0;chunk-signature=cccc\r\n" +
		"x-amz-checksum-crc32:DUoRhQ==\r\n\r\n"
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPut, endpoint("java")+"/keirekipro/chunked.txt", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Encoding", "aws-chunked")
	req.Header.Set("X-Amz-Content-Sha256", "STREAMING-AWS4-HMAC-SHA256-PAYLOAD-TRAILER")
	req.Header.Set("X-Amz-Decoded-Content-Length", "11")
	req.Header.Set("Content-Type", "text/plain")
	resp, err := f.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("PUT の応答 = %d, want 200", resp.StatusCode)
	}
	objects := f.server.Objects("java")
	if len(objects) != 1 || string(objects[0].Body) != "hello world" {
		t.Errorf("覚えた本文 = %+v, want hello world", objects)
	}
}

// TestImage_ServesOnNetwork は、Dockerfile で組み立てたイメージが、ネットワークの中の名前で版を分けて受けることを確かめる。
func TestImage_ServesOnNetwork(t *testing.T) {
	root, err := harness.RepoRoot()
	if err != nil {
		t.Fatal(err)
	}
	ctx := t.Context()
	var buildLog bytes.Buffer
	images, err := harness.BuildImages(ctx, root, &buildLog, harness.ImageFakeAWS)
	t.Cleanup(func() {
		if err := images.Remove(context.Background()); err != nil {
			t.Errorf("組み立てたイメージを消せません: %v", err)
		}
	})
	if err != nil {
		t.Fatalf("BuildImages: %v\n%s", err, buildLog.String())
	}
	env, err := harness.NewEnv(ctx)
	if err != nil {
		t.Fatal(err)
	}
	env.Cleanup(t)
	c, err := env.Start(ctx, harness.ContainerSpec{
		Name:         "fakeaws-java",
		Image:        images[harness.ImageFakeAWS],
		ExposedPorts: []string{fakeaws.Port + "/tcp"},
	})
	if err != nil {
		t.Fatal(err)
	}
	baseURL, err := c.BaseURL(ctx, fakeaws.Port+"/tcp")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := harness.WaitHealthz(ctx, harness.NewHTTPClient(), baseURL+"/_compat", time.Now()); err != nil {
		t.Fatal(err)
	}

	// コンテナの外から、宛先のホスト名を fakeaws-java にして秘密の値を登録し、Secrets Manager の形で読む
	put, err := http.NewRequestWithContext(ctx, http.MethodPut, baseURL+"/_compat/java/secrets/keirekipro/jwt", strings.NewReader("secret-value"))
	if err != nil {
		t.Fatal(err)
	}
	resp, err := harness.NewHTTPClient().Do(put)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("秘密の値の登録 = %d, want 204", resp.StatusCode)
	}
	cfg := aws.Config{
		Region:       "ap-northeast-1",
		Credentials:  credentials.NewStaticCredentialsProvider("dummy", "dummy", ""),
		BaseEndpoint: aws.String(baseURL),
		HTTPClient:   &http.Client{Transport: hostRewriter{host: fakeaws.HostPrefix + "java"}},
	}
	out, err := secretsmanager.NewFromConfig(cfg).GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{SecretId: aws.String("keirekipro/jwt")})
	if err != nil || aws.ToString(out.SecretString) != "secret-value" {
		t.Errorf("コンテナの GetSecretValue = %v, %v, want secret-value", out, err)
	}
	logs, err := c.Logs(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = logs.Close() }()
	text, _ := io.ReadAll(logs)
	if !slices.ContainsFunc(strings.Split(string(text), "\n"), func(l string) bool { return strings.Contains(l, "ポート 4566 で受けます") }) {
		t.Errorf("コンテナのログ = %q, want 起動の行", text)
	}
}

// hostRewriter は、要求の宛先のホスト名を host に替えて送る。外に出したポートへ送りながら、版を名前で選ぶためである。
type hostRewriter struct{ host string }

func (h hostRewriter) RoundTrip(req *http.Request) (*http.Response, error) {
	req = req.Clone(req.Context())
	req.Host = h.host
	return http.DefaultTransport.RoundTrip(req)
}

// TestUnknownOperation_Returns501 は、受けると決めていない操作を、比べる検査で見つかるように 501 で断ることを確かめる。
func TestUnknownOperation_Returns501(t *testing.T) {
	f := newFixture(t)
	_, err := f.s3("java").ListObjectsV2(t.Context(), &s3.ListObjectsV2Input{Bucket: aws.String("keirekipro")})
	var apiErr smithy.APIError
	if !errors.As(err, &apiErr) || apiErr.ErrorCode() != "NotImplemented" {
		t.Errorf("ListObjectsV2 の誤り = %v, want NotImplemented", err)
	}

	// 問い合わせの値を付けずに、キーの無いパスを読む要求も断る
	req, err := http.NewRequestWithContext(t.Context(), http.MethodGet, endpoint("java")+"/keirekipro/", http.NoBody)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := f.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusNotImplemented {
		t.Errorf("GET /keirekipro/ の応答 = %d, want 501", resp.StatusCode)
	}
}

// TestUnknownObjectOperation_Returns501 は、オブジェクトへの、受けると決めていない操作を 501 で断ることを確かめる。
func TestUnknownObjectOperation_Returns501(t *testing.T) {
	f := newFixture(t)
	_, err := f.s3("java").GetObjectTagging(t.Context(), &s3.GetObjectTaggingInput{
		Bucket: aws.String("keirekipro"), Key: aws.String("users/u1/profile.png"),
	})
	var apiErr smithy.APIError
	if !errors.As(err, &apiErr) || apiErr.ErrorCode() != "NotImplemented" {
		t.Errorf("GetObjectTagging の誤り = %v, want NotImplemented", err)
	}
}

// TestUnexpectedRequests_Return501AndLog は、SES と Secrets Manager の受けると決めていない操作と、
// 末尾に / の無いバケットの単位のパスを、501 で断り、fakeaws_unexpected_request をログに出すことを確かめる。
func TestUnexpectedRequests_Return501AndLog(t *testing.T) {
	f := newFixture(t)
	logs := captureLog(t)
	ctx := t.Context()

	_, err := ses.NewFromConfig(f.awsConfig("java")).SendRawEmail(ctx, &ses.SendRawEmailInput{
		RawMessage: &sestypes.RawMessage{Data: []byte("Subject: x\r\n\r\nbody")},
	})
	assertStatus501(t, "SES の SendRawEmail", err)
	_, err = secretsmanager.NewFromConfig(f.awsConfig("java")).ListSecrets(ctx, &secretsmanager.ListSecretsInput{})
	assertStatus501(t, "Secrets Manager の ListSecrets", err)

	// 転送をたどらないクライアントで、ServeMux が /keirekipro/ へ転送せずに 501 で断ることを確かめる
	noRedirect := *f.client
	noRedirect.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, endpoint("java")+"/keirekipro", http.NoBody)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := noRedirect.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusNotImplemented {
		t.Errorf("PUT /keirekipro の応答 = %d, want 501", resp.StatusCode)
	}

	got := logs.String()
	for _, operation := range []string{`"operation":"SES SendRawEmail"`, `"operation":"secretsmanager.ListSecrets"`, `"operation":"PUT /keirekipro"`} {
		if !strings.Contains(got, `"msg":"fakeaws_unexpected_request"`) || !strings.Contains(got, operation) {
			t.Errorf("ログに fakeaws_unexpected_request の %s がありません: %s", operation, got)
		}
	}
}

func assertStatus501(t *testing.T, name string, err error) {
	t.Helper()
	var respErr *awshttp.ResponseError
	if !errors.As(err, &respErr) || respErr.HTTPStatusCode() != http.StatusNotImplemented {
		t.Errorf("%s の誤り = %v, want 501", name, err)
	}
}

// syncBuffer は、サーバの処理とテストの処理が同時に読み書きできる bytes.Buffer である。
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// captureLog は、テストのあいだ、slog の既定の出力を JSON の形で読めるようにする。
func captureLog(t *testing.T) *syncBuffer {
	t.Helper()
	logs := &syncBuffer{}
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(logs, nil)))
	t.Cleanup(func() { slog.SetDefault(previous) })
	return logs
}
