package httpapi

import (
	"bytes"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/logging"
)

// paramErrorHandler が、/api/auth/ の下の問い合わせの誤りを 400 と Java 版の入力の誤りの本文にし、ほかの経路の値の
// 誤りを Java 版と同じ 500 にして、ログに誤りの型だけを書くことを確かめる。項目の ID は文字列で受け取るので、
// 経路を通して値の形の誤りを起こせない。そのため、生成したコードが渡す誤りを直接渡す。
func TestParamErrorHandler(t *testing.T) {
	const secret = "not-a-uuid"
	paramErr := &gen.InvalidParamFormatError{ParamName: "resumeId", Err: errors.New("invalid UUID " + secret)}
	for _, tc := range []struct {
		name, path string
		status     int
		body       string
		logged     bool
	}{
		{
			name: "/api/auth/ の下の問い合わせの誤りは 400", path: "/api/auth/oidc/authorize",
			status: http.StatusBadRequest, body: `{"message":"入力エラーがあります。","errors":{}}`,
		},
		{
			name: "ほかの経路の値の誤りは 500", path: "/api/resumes/" + secret,
			status: http.StatusInternalServerError, body: `{"message":"予期せぬエラーが発生しました。","errors":{}}`,
			logged: true,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			logs := &bytes.Buffer{}
			handle := paramErrorHandler(logging.New(logs, logging.Options{Service: logging.Service{Name: "keirekipro"}}))
			rec := httptest.NewRecorder()
			handle(rec, httptest.NewRequest(http.MethodGet, tc.path, nil), paramErr)

			if rec.Code != tc.status || strings.TrimSpace(rec.Body.String()) != tc.body {
				t.Errorf("応答 = %d %s, want %d %s", rec.Code, rec.Body.String(), tc.status, tc.body)
			}
			if got := rec.Header().Get("Content-Type"); got != "application/json" {
				t.Errorf("Content-Type = %q, want application/json", got)
			}
			if !tc.logged {
				if logs.Len() != 0 {
					t.Errorf("入力の誤りをログに書きました: %s", logs.String())
				}
				return
			}
			if !strings.Contains(logs.String(), `"unexpected_exception"`) ||
				!strings.Contains(logs.String(), `"type":"*gen.InvalidParamFormatError"`) {
				t.Errorf("ログ = %s, want 想定外の誤りと誤りの型", logs.String())
			}
			if strings.Contains(logs.String(), "invalid UUID") || strings.Contains(logs.String(), "resumeId") {
				t.Errorf("ログに誤りの文を書きました: %s", logs.String())
			}
		})
	}
}
