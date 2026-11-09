package awsclient

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/aws/aws-sdk-go-v2/service/ses"
	sestypes "github.com/aws/aws-sdk-go-v2/service/ses/types"
)

// request は、AWS の代わりのサーバが受けた要求の1件である。
type request struct {
	method string
	path   string
	target string
	action string
}

// fakeAWS は、受けた要求を記録し、S3 と SES と Secrets Manager の最小の応答を返すサーバである。
func fakeAWS(t *testing.T) (*httptest.Server, func() []request) {
	t.Helper()
	var mu sync.Mutex
	var got []request
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Errorf("要求の本文を読めません: %v", err)
		}
		mu.Lock()
		got = append(got, request{method: r.Method, path: r.URL.Path, target: r.Header.Get("X-Amz-Target"), action: r.PostForm.Get("Action")})
		mu.Unlock()
		switch {
		case r.Header.Get("X-Amz-Target") == "secretsmanager.GetSecretValue":
			w.Header().Set("Content-Type", "application/x-amz-json-1.1")
			_, _ = w.Write([]byte(`{"Name":"keirekipro/jwt","SecretString":"{}"}`))
		case r.PostForm.Get("Action") == "SendEmail":
			w.Header().Set("Content-Type", "text/xml")
			_, _ = w.Write([]byte(`<SendEmailResponse xmlns="http://ses.amazonaws.com/doc/2010-12-01/"><SendEmailResult><MessageId>m-1</MessageId></SendEmailResult></SendEmailResponse>`))
		default:
			w.WriteHeader(http.StatusOK)
		}
	}))
	t.Cleanup(server.Close)
	return server, func() []request {
		mu.Lock()
		defer mu.Unlock()
		return append([]request(nil), got...)
	}
}

// dev と test では、3つのクライアントが KEIREKIPRO_AWS_ENDPOINT の先につなぎ、S3 がパスの形を使うことを確かめる。
func TestNew_DevUsesPathStyleEndpoint(t *testing.T) {
	server, requests := fakeAWS(t)
	clients, err := New(t.Context(), Options{Region: "ap-northeast-1", Endpoint: server.URL})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	// テストのサーバの宛先は IP アドレスなので、S3 の部品は設定によらずパスの形で送る。
	// 開発環境の localstack のようにホストの名前で送るときにもパスの形になるよう、設定そのものを確かめる。
	if !clients.S3.Options().UsePathStyle {
		t.Error("S3 のパスの形 = false, want true")
	}

	if _, err := clients.S3.PutObject(t.Context(), &s3.PutObjectInput{
		Bucket: aws.String("keirekipro-storage"),
		Key:    aws.String("profile/image/a.png"),
		Body:   strings.NewReader("png"),
	}); err != nil {
		t.Fatalf("S3 の PutObject: %v", err)
	}
	if _, err := clients.SES.SendEmail(t.Context(), &ses.SendEmailInput{
		Source:      aws.String("no-reply@keirekipro.click"),
		Destination: &sestypes.Destination{ToAddresses: []string{"user@example.com"}},
		Message: &sestypes.Message{
			Subject: &sestypes.Content{Data: aws.String("件名")},
			Body:    &sestypes.Body{Text: &sestypes.Content{Data: aws.String("本文")}},
		},
	}); err != nil {
		t.Fatalf("SES の SendEmail: %v", err)
	}
	if _, err := clients.SecretsManager.GetSecretValue(t.Context(), &secretsmanager.GetSecretValueInput{
		SecretId: aws.String("keirekipro/jwt"),
	}); err != nil {
		t.Fatalf("Secrets Manager の GetSecretValue: %v", err)
	}

	want := []request{
		{method: http.MethodPut, path: "/keirekipro-storage/profile/image/a.png"},
		{method: http.MethodPost, path: "/", action: "SendEmail"},
		{method: http.MethodPost, path: "/", target: "secretsmanager.GetSecretValue"},
	}
	got := requests()
	if len(got) != len(want) {
		t.Fatalf("受けた要求 = %+v, want %+v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("%d 番目の要求 = %+v, want %+v", i+1, got[i], want[i])
		}
	}
}

// 本番では、接続先を替えず、S3 がパスの形を使わないことを確かめる。
func TestNew_ProdUsesDefaultEndpoint(t *testing.T) {
	clients, err := New(t.Context(), Options{Region: "ap-northeast-1"})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	s3Options := clients.S3.Options()
	if s3Options.BaseEndpoint != nil || s3Options.UsePathStyle {
		t.Errorf("S3 の接続先 = (%v, パスの形 %t), want (nil, false)", s3Options.BaseEndpoint, s3Options.UsePathStyle)
	}
	if s3Options.Region != "ap-northeast-1" {
		t.Errorf("S3 のリージョン = %q, want ap-northeast-1", s3Options.Region)
	}
	if endpoint := clients.SES.Options().BaseEndpoint; endpoint != nil {
		t.Errorf("SES の接続先 = %q, want nil", *endpoint)
	}
	if endpoint := clients.SecretsManager.Options().BaseEndpoint; endpoint != nil {
		t.Errorf("Secrets Manager の接続先 = %q, want nil", *endpoint)
	}
}

// リージョンが空なら、クライアントを作らずに誤りを返すことを確かめる。
func TestNew_RejectsEmptyRegion(t *testing.T) {
	_, err := New(t.Context(), Options{})
	if err == nil || !strings.Contains(err.Error(), "リージョン") {
		t.Errorf("New の誤り = %v, want リージョンが空であることの誤り", err)
	}
}
