package httpapi

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
)

// paramErrorHandler が、経路によらず、値の形の誤りを 400 と入力の誤りの本文にすることを確かめる。項目の ID は
// 文字列で受け取るので、経路を通して経路の値の形の誤りを起こせない。そのため、生成したコードが渡す誤りを直接渡す。
func TestParamErrorHandler(t *testing.T) {
	paramErr := &gen.InvalidParamFormatError{ParamName: "resumeId", Err: errors.New("invalid UUID")}
	for _, path := range []string{"/api/auth/oidc/authorize", "/api/resumes/not-a-uuid"} {
		t.Run(path, func(t *testing.T) {
			rec := httptest.NewRecorder()
			paramErrorHandler(rec, httptest.NewRequest(http.MethodGet, path, nil), paramErr)

			const want = `{"message":"入力エラーがあります。","errors":{}}`
			if rec.Code != http.StatusBadRequest || strings.TrimSpace(rec.Body.String()) != want {
				t.Errorf("応答 = %d %s, want 400 %s", rec.Code, rec.Body.String(), want)
			}
			if got := rec.Header().Get("Content-Type"); got != "application/json" {
				t.Errorf("Content-Type = %q, want application/json", got)
			}
		})
	}
}
