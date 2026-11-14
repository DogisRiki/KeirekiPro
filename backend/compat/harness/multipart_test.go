//go:build compat

package harness

import (
	"bytes"
	"image"
	"io"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
)

// bodyServer は、受けた要求の Content-Type と本文の全体を記録するサーバである。
func bodyServer(t *testing.T) (*httptest.Server, func() []recorded) {
	t.Helper()
	var mu sync.Mutex
	var reqs []recorded
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, err := io.ReadAll(r.Body)
		if err != nil {
			t.Errorf("本文を読めません: %v", err)
		}
		mu.Lock()
		reqs = append(reqs, recorded{Method: r.Method, Path: r.URL.Path, ContentType: r.Header.Get("Content-Type"), Body: string(b)})
		mu.Unlock()
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(srv.Close)
	return srv, func() []recorded {
		mu.Lock()
		defer mu.Unlock()
		return slices.Clone(reqs)
	}
}

// imageFixture は、fixtures/images の下のファイル name の中身を返す。
func imageFixture(t *testing.T, name string) []byte {
	t.Helper()
	b, err := fs.ReadFile(os.DirFS(filepath.Join(FixturesDir(), imagesFixtureDir)), name)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestMultipartBody_FixedBoundary(t *testing.T) {
	if multipartBoundary != "KeirekiProCompatBoundary" {
		t.Errorf("multipartBoundary = %q", multipartBoundary)
	}
	newName, empty := "名前-{id}", ""
	step := Step{Name: "upload", Request: Request{Method: http.MethodPut, Path: "/api/users/me", Multipart: []MultipartPart{
		{Name: "username", Value: &newName},
		{Name: "twoFactorAuthEnabled", Value: &empty},
		{Name: "profileImage", File: "profile.png", Filename: "big.png", ContentType: "image/png"},
		{Name: "other", File: "profile.gif"},
	}}}
	png, gif := imageFixture(t, "profile.png"), imageFixture(t, "profile.gif")
	// 文字の部分は {名前} を置き換え、Content-Type を書かない。filename を書かない file の部分はファイルの名前を送り、
	// content_type を書かない file の部分は Content-Type を送らない
	want := "--KeirekiProCompatBoundary\r\n" +
		"Content-Disposition: form-data; name=\"username\"\r\n\r\n" +
		"名前-u-1\r\n" +
		"--KeirekiProCompatBoundary\r\n" +
		"Content-Disposition: form-data; name=\"twoFactorAuthEnabled\"\r\n\r\n" +
		"\r\n" +
		"--KeirekiProCompatBoundary\r\n" +
		"Content-Disposition: form-data; name=\"profileImage\"; filename=\"big.png\"\r\n" +
		"Content-Type: image/png\r\n\r\n" +
		string(png) + "\r\n" +
		"--KeirekiProCompatBoundary\r\n" +
		"Content-Disposition: form-data; name=\"other\"; filename=\"profile.gif\"\r\n\r\n" +
		string(gif) + "\r\n" +
		"--KeirekiProCompatBoundary--\r\n"
	srv, reqs := bodyServer(t)
	s := NewSession()
	s.vars["id"] = "u-1"
	// 2回送っても、同じ区切りの文字列で、同じバイトの並びになる
	for range 2 {
		if _, err := s.Send(t.Context(), srv.Client(), srv.URL, step); err != nil {
			t.Fatal(err)
		}
	}
	got := reqs()
	if len(got) != 2 {
		t.Fatalf("届いた要求 = %d 個, want 2", len(got))
	}
	for i, r := range got {
		if r.ContentType != "multipart/form-data; boundary=KeirekiProCompatBoundary" {
			t.Errorf("%d 回目の Content-Type = %q", i+1, r.ContentType)
		}
		if r.Body != want {
			t.Errorf("%d 回目の本文 = %q, want %q", i+1, r.Body, want)
		}
	}
	if step.Request.Multipart[0].Value == nil || *step.Request.Multipart[0].Value != "名前-{id}" {
		t.Errorf("筋書きの段が書き換わりました: %+v", step.Request.Multipart[0])
	}

	// 筋書きのヘッダの Content-Type は、組み立てた本文の Content-Type より先に立つ
	step.Request.Headers = map[string]string{"Content-Type": "multipart/form-data"}
	if _, err := s.Send(t.Context(), srv.Client(), srv.URL, step); err != nil {
		t.Fatal(err)
	}
	if got := reqs(); got[2].ContentType != "multipart/form-data" || got[2].Body != want {
		t.Errorf("ヘッダを書いた段の要求 = %q %q", got[2].ContentType, got[2].Body)
	}

	// 取り出していない名前の値と、無いファイルは、送る前に段の誤りにする
	for name, part := range map[string]MultipartPart{
		"取り出していない名前": {Name: "username", Value: &newName},
		"無いファイル":     {Name: "profileImage", File: "none.png"},
	} {
		bad := Step{Name: "bad", Request: Request{Method: http.MethodPut, Path: "/x", Multipart: []MultipartPart{part}}}
		_, err := NewSession().Send(t.Context(), srv.Client(), srv.URL, bad)
		if err == nil || !strings.Contains(err.Error(), "段 bad ") {
			t.Errorf("%s: 誤り = %v, want 段 bad の誤り", name, err)
		}
	}
	if got := reqs(); len(got) != 3 {
		t.Errorf("誤りの段の要求が届きました: %d 個", len(got))
	}
}

func TestMultipartBody_PadTo(t *testing.T) {
	png := imageFixture(t, "profile.png")
	step := Step{Name: "big", Request: Request{Method: http.MethodPut, Path: "/api/users/me", Multipart: []MultipartPart{
		{Name: "profileImage", File: "profile.png", Filename: "big.png", ContentType: "image/png", PadTo: 1048577},
	}}}
	body, contentType, err := NewSession().multipartBody(step)
	if err != nil {
		t.Fatal(err)
	}
	if contentType != "multipart/form-data; boundary=KeirekiProCompatBoundary" {
		t.Errorf("Content-Type = %q", contentType)
	}
	head := "--KeirekiProCompatBoundary\r\n" +
		"Content-Disposition: form-data; name=\"profileImage\"; filename=\"big.png\"\r\n" +
		"Content-Type: image/png\r\n\r\n"
	tail := "\r\n--KeirekiProCompatBoundary--\r\n"
	if !bytes.HasPrefix(body, []byte(head)) || !bytes.HasSuffix(body, []byte(tail)) {
		t.Fatalf("本文の始めと終わりが違います: %q ... %q", body[:min(len(body), len(head))], body[max(0, len(body)-len(tail)):])
	}
	data := body[len(head) : len(body)-len(tail)]
	if len(data) != 1048577 {
		t.Fatalf("画像の部分の大きさ = %d, want 1048577", len(data))
	}
	if !bytes.Equal(data[:len(png)], png) {
		t.Error("画像の部分の始めが profile.png と違います")
	}
	if bytes.ContainsFunc(data[len(png):], func(r rune) bool { return r != 0 }) {
		t.Error("足したバイトが0ではありません")
	}
	// 足した0のバイトは画像の終わりのあとにあるので、PNG として読める
	cfg, format, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || format != "png" || cfg.Width == 0 || cfg.Height == 0 {
		t.Errorf("1048577 バイトにした画像を読めません: %v %q %+v", err, format, cfg)
	}

	// pad_to がファイルの大きさと同じなら、0のバイトを足さない
	step.Request.Multipart[0].PadTo = len(png)
	body, _, err = NewSession().multipartBody(step)
	if err != nil {
		t.Fatal(err)
	}
	if got := body[len(head) : len(body)-len(tail)]; !bytes.Equal(got, png) {
		t.Errorf("pad_to がファイルと同じ大きさの画像の部分 = %d バイト, want %d", len(got), len(png))
	}
}
