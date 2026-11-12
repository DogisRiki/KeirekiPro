//go:build compat

package harness

import (
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// authCrossSteps は、認証の筋書きごとに、その前の版に送る段と違う版に送られるべき段の名前を、筋書きの順に挙げる。
// 管理者の経路への段と、to: other を付けた、途中の手順の2つ目からの要求を送る段と作り直しの段とログアウトの段である。
// refresh-logout.yaml の refresh-after-logout と refresh-after-access-expired、password-reset.yaml の verify-used-token と
// reset-expired-token は、to: other を付けると前の to: other の段と2つ続いて元の版に戻るので、to: other を付けず、ここに挙げない。
var authCrossSteps = map[string][]string{
	"auth-login": {"admin-users-after-login"},
	"auth-two-factor": {
		"verify-code", "verify-wrong-code", "verify-wrong-code-again", "verify-code-after-wrong",
		"verify-wrong-1", "verify-wrong-2", "verify-wrong-3", "verify-wrong-4", "verify-wrong-5-limit", "verify-code-after-limit",
	},
	"auth-refresh-logout": {
		"refresh", "logout", "admin-users-after-logout", "admin-users-after-access-expired",
		"refresh-after-refresh-expired",
	},
	"auth-register": {"verify-registration-link", "verify-used-link"},
	"auth-email-verification": {
		"resend-expired-link", "verify-resent-link", "verify-previous-link", "login-after-previous-link",
		"verify-latest-link", "verify-login-resent-link",
	},
	"auth-password-reset": {
		"verify-reset-token", "login-other-device", "reset-password", "admin-users-after-reset",
		"reset-used-token", "verify-expired-token", "verify-missing-user-token", "reset-missing-user",
	},
	"auth-oidc-google": {
		"callback-new-user", "admin-users-new-user", "callback-registered-user", "admin-users-registered-user",
		"callback-unverified-user", "callback-denied", "callback-unknown-state",
	},
	"auth-oidc-github": {
		"callback-new-user", "admin-users-new-user", "callback-registered-user", "admin-users-registered-user",
		"callback-unverified-user", "callback-no-verified-email-user", "admin-users-no-verified-email-user", "callback-denied",
		"callback-unknown-state",
	},
}

// crossCheckedStep は、その前の版に送る段と違う版に送られるべき段かを返す。管理者の経路への段と、to: other の段である。
func crossCheckedStep(step Step) bool {
	if step.Kind() != StepVersion {
		return false
	}
	return step.To == ToOther || strings.HasPrefix(step.Request.Path, "/api/admin/")
}

// TestCrossRoute_AuthProcedureSteps は、認証の筋書きを読み、Java 版から Go 版の向きと Go 版から Java 版の向きのそれぞれで、
// 管理者の経路への段と、to: other を付けた段が、その前の版に送る段と違う版に送られることを確かめる。
// 段の to: other が外れると、版をまたいで確かめるはずの段が、ログインした版や手順を始めた版と同じ版に届き、
// 版をまたいでも操作を終えられるかを確かめなくなるためである。確かめる段は authCrossSteps と一致することも確かめる。
func TestCrossRoute_AuthProcedureSteps(t *testing.T) {
	scenarios, err := LoadScenarios(filepath.Join("..", "scenarios", "auth"), ModeCross)
	if err != nil {
		t.Fatalf("LoadScenarios: %v", err)
	}
	var names []string
	for _, s := range scenarios {
		names = append(names, s.Name)
	}
	for name := range authCrossSteps {
		if !slices.Contains(names, name) {
			t.Errorf("版をまたぐ筋書き %s がありません。読んだ筋書きは %v です", name, names)
		}
	}
	for _, s := range scenarios {
		want, ok := authCrossSteps[s.Name]
		if !ok {
			t.Errorf("筋書き %s の確かめる段が authCrossSteps にありません", s.Name)
			continue
		}
		var checked []string
		for _, step := range s.Steps {
			if crossCheckedStep(step) {
				checked = append(checked, step.Name)
			}
		}
		if !slices.Equal(checked, want) {
			t.Errorf("筋書き %s の、違う版に送る段 = %v, want %v", s.Name, checked, want)
		}
		for _, direction := range []string{CrossJavaToGo, CrossGoToJava} {
			route, err := CrossRoute(s, direction)
			if err != nil {
				t.Errorf("CrossRoute(%s, %s): %v", s.Name, direction, err)
				continue
			}
			prev := ""
			for i, step := range s.Steps {
				if step.Kind() != StepVersion {
					continue
				}
				if crossCheckedStep(step) && route[i] == prev {
					t.Errorf("筋書き %s の向き %s で、段 %d「%s」(%s %s)が、その前の版に送る段と同じ版 %s に送られます",
						s.Name, direction, i+1, step.Name, step.Request.Method, step.Request.Path, route[i])
				}
				prev = route[i]
			}
		}
	}
}
