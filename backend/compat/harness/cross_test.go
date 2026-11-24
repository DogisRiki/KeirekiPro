//go:build compat

package harness

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// authCrossSteps は、認証の筋書きごとに、その前の版に送る段と違う版に送られるべき段の名前を、筋書きの順に挙げる。
// 管理者の経路への段と、to: other を付けた、途中の手順の2つ目からの要求を送る段と作り直しの段とログアウトの段である。
// to: other の段が2つ続くと元の版に戻るので、値を出した版と違う版に届けたい段が2つ続くときは、その間に、値を出した版へ戻す段
// (名前の終わりが -same-version の段か、password-reset.yaml の login-old-password)を置く。
var authCrossSteps = map[string][]string{
	"auth-login": {"admin-users-after-login"},
	"auth-two-factor": {
		"verify-code", "verify-wrong-code", "verify-wrong-code-again", "verify-code-after-wrong",
		"verify-wrong-1", "verify-wrong-2", "verify-wrong-3", "verify-wrong-4", "verify-wrong-5-limit", "verify-code-after-limit",
	},
	"auth-refresh-logout": {
		"refresh", "logout", "admin-users-after-logout", "admin-users-after-logout-same-version", "refresh-after-logout",
		"admin-users-after-access-expired", "admin-users-after-access-expired-same-version", "refresh-after-access-expired",
		"refresh-after-refresh-expired",
	},
	"auth-register": {"verify-registration-link", "verify-used-link"},
	"auth-email-verification": {
		"resend-expired-link", "verify-resent-link", "verify-previous-link", "login-after-previous-link",
		"verify-latest-link", "verify-login-resent-link",
	},
	"auth-password-reset": {
		"verify-reset-token", "login-other-device", "reset-password", "admin-users-after-reset", "login-old-password",
		"verify-used-token", "reset-used-token", "verify-expired-token", "verify-expired-token-same-version",
		"reset-expired-token", "verify-missing-user-token", "reset-missing-user",
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

// userCrossPair は、利用者の操作の版をまたぐ筋書きの、確かめるものを変える段 Changed と、変えたあとをもう一方の版で
// 確かめる段 Checked の名前の組である。
type userCrossPair struct {
	Changed string
	Checked string
}

// userCrossFiles は、利用者の操作の、版をまたいで確かめる筋書きのファイルである。
var userCrossFiles = []string{"cross-update.yaml", "cross-email-password.yaml", "cross-invalidate.yaml"}

// userCrossSteps は、利用者の操作の版をまたぐ筋書きごとに、変える段と、変える段と違う版に送られるべき確かめる段の組を挙げる。
// 確かめる段は、expect の values か body_file を持つ段と、前のログインの状態の値を Cookie ヘッダで送る段と、
// 設定したか変えたパスワードでもう一方の版にログインする段である。
var userCrossSteps = map[string][]userCrossPair{
	"users-cross-update": {
		{Changed: "update-username", Checked: "get-user-info-after-username"},
		{Changed: "update-image-png", Checked: "read-image-png"},
		{Changed: "update-image-jpeg", Checked: "read-image-jpeg"},
		{Changed: "enable-two-factor", Checked: "get-user-info-after-two-factor"},
		{Changed: "remove-github", Checked: "get-user-info-after-remove-github"},
	},
	"users-cross-email-password": {
		{Changed: "set-email-and-password", Checked: "verify-set-email"},
		{Changed: "set-email-and-password", Checked: "login-with-set-email"},
		{Changed: "change-password", Checked: "login-new-password"},
		{Changed: "set-email-and-password", Checked: "get-user-info-after-change"},
	},
	"users-cross-invalidate": {
		{Changed: "change-password", Checked: "get-user-info-with-before-change-access"},
		{Changed: "delete-user2", Checked: "get-user-info-with-before-delete-access"},
	},
}

// userCheckedStep は、変えたあとをもう一方の版で確かめる段かを返す。expect の values か body_file を持つ段と、
// 前のログインの状態の値を Cookie ヘッダで送る段である。
func userCheckedStep(step Step) bool {
	if len(step.Expect.Values) > 0 || step.Expect.BodyFile != "" {
		return true
	}
	for name, value := range step.Request.Headers {
		if strings.EqualFold(name, "Cookie") && strings.Contains(value, "accessToken=") {
			return true
		}
	}
	return false
}

// readingVersions は、送り先の組の段ごとの版 route から、段ごとに、答えを返した版を求める。版に送る段は送った版である。
// 絶対の URL の段は、その前の版に送る段の版とする。絶対の URL の段が読む署名付きの URL は、その前の段の版が返したためである。
func readingVersions(s Scenario, route []string) []string {
	versions := make([]string, len(route))
	prev := ""
	for i, step := range s.Steps {
		switch step.Kind() {
		case StepVersion:
			prev = route[i]
			versions[i] = prev
		case StepAbsoluteURL:
			versions[i] = prev
		}
	}
	return versions
}

// TestCrossRoute_UserSteps は、利用者の操作の版をまたぐ筋書きを読み、Java 版から Go 版の向きと Go 版から Java 版の向きの
// それぞれで、確かめる段が、userCrossSteps の組の変える段と違う版から答えを受けることを確かめる。
// 段の to: other が外れると、変えた版と同じ版で確かめることになり、一方の版が保存したものをもう一方の版が読めるかを
// 確かめなくなるためである。expect の values か body_file を持つ段と、前のログインの状態の値を送る段は、どれも
// userCrossSteps の確かめる段に挙げてあることも確かめる。3つの筋書きのファイルのどれかが無ければ失敗する。
func TestCrossRoute_UserSteps(t *testing.T) {
	dir := filepath.Join("..", "scenarios", "users")
	for _, file := range userCrossFiles {
		if _, err := os.Stat(filepath.Join(dir, file)); err != nil {
			t.Errorf("版をまたぐ筋書き %s がありません: %v", file, err)
		}
	}
	scenarios, err := LoadScenarios(dir, ModeCross)
	if err != nil {
		t.Fatalf("LoadScenarios: %v", err)
	}
	var names []string
	for _, s := range scenarios {
		names = append(names, s.Name)
	}
	for name := range userCrossSteps {
		if !slices.Contains(names, name) {
			t.Errorf("版をまたぐ筋書き %s がありません。読んだ筋書きは %v です", name, names)
		}
	}
	for _, s := range scenarios {
		pairs, ok := userCrossSteps[s.Name]
		if !ok {
			t.Errorf("筋書き %s の確かめる段が userCrossSteps にありません", s.Name)
			continue
		}
		index := map[string]int{}
		for i, step := range s.Steps {
			index[step.Name] = i
		}
		var listed []string
		for _, p := range pairs {
			listed = append(listed, p.Checked)
			changed, okChanged := index[p.Changed]
			checked, okChecked := index[p.Checked]
			if !okChanged || !okChecked {
				t.Errorf("筋書き %s に、変える段 %s か確かめる段 %s がありません", s.Name, p.Changed, p.Checked)
				continue
			}
			if changed >= checked || s.Steps[changed].Kind() != StepVersion {
				t.Errorf("筋書き %s の変える段 %s は、確かめる段 %s より前の、版に送る段でなければなりません", s.Name, p.Changed, p.Checked)
			}
		}
		for _, step := range s.Steps {
			if userCheckedStep(step) && !slices.Contains(listed, step.Name) {
				t.Errorf("筋書き %s の段 %s は、もう一方の版で確かめる段ですが、userCrossSteps に変える段との組がありません", s.Name, step.Name)
			}
		}
		for _, direction := range []string{CrossJavaToGo, CrossGoToJava} {
			route, err := CrossRoute(s, direction)
			if err != nil {
				t.Errorf("CrossRoute(%s, %s): %v", s.Name, direction, err)
				continue
			}
			reading := readingVersions(s, route)
			for _, p := range pairs {
				changed, okChanged := index[p.Changed]
				checked, okChecked := index[p.Checked]
				if !okChanged || !okChecked {
					continue
				}
				if reading[checked] == "" || reading[checked] == route[changed] {
					t.Errorf("筋書き %s の向き %s で、確かめる段「%s」が、変える段「%s」と同じ版 %s から答えを受けます",
						s.Name, direction, p.Checked, p.Changed, route[changed])
				}
			}
		}
	}
}

// resumeCrossFiles は、マスタと経歴書の操作の、版をまたいで確かめる筋書きのファイルである。
var resumeCrossFiles = []string{"cross-resume.yaml"}

// resumeChangingStep は、経歴書と項目を変える段かを返す。GET でない、版に送る段である。
func resumeChangingStep(step Step) bool {
	return step.Kind() == StepVersion && step.Request.Method != "GET"
}

// TestCrossRoute_ResumeSteps は、マスタと経歴書の操作の版をまたぐ筋書きを読み、Java 版から Go 版の向きと Go 版から
// Java 版の向きのそれぞれで、expect の values を持つ段が、その前の変える段(GET でない、版に送る段)と違う版から答えを
// 受けることを確かめる。段の to: other が外れると、保存した版と同じ版で読み直すことになり、一方の版が保存した経歴書と項目を
// もう一方の版が読めるかを確かめなくなるためである。筋書きの最後の段は、CrossRoute が、その前の版に送る段と違う版に送る。
// 筋書きのファイルが無いときと、expect の values を持つ段が1つも無いときは失敗する。
func TestCrossRoute_ResumeSteps(t *testing.T) {
	dir := filepath.Join("..", "scenarios", "resumes")
	for _, file := range resumeCrossFiles {
		if _, err := os.Stat(filepath.Join(dir, file)); err != nil {
			t.Errorf("版をまたぐ筋書き %s がありません: %v", file, err)
		}
	}
	scenarios, err := LoadScenarios(dir, ModeCross)
	if err != nil {
		t.Fatalf("LoadScenarios: %v", err)
	}
	if len(scenarios) == 0 {
		t.Fatalf("%s に、版をまたぐ動かし方の筋書きがありません", dir)
	}
	for _, s := range scenarios {
		checkedSteps := 0
		for _, step := range s.Steps {
			if len(step.Expect.Values) > 0 {
				checkedSteps++
			}
		}
		if checkedSteps == 0 {
			t.Errorf("筋書き %s に、expect の values を持つ段がありません", s.Name)
		}
		for _, direction := range []string{CrossJavaToGo, CrossGoToJava} {
			route, err := CrossRoute(s, direction)
			if err != nil {
				t.Errorf("CrossRoute(%s, %s): %v", s.Name, direction, err)
				continue
			}
			changed := -1
			for i, step := range s.Steps {
				if len(step.Expect.Values) > 0 {
					switch {
					case changed < 0:
						t.Errorf("筋書き %s の段「%s」は expect の values を持ちますが、その前に変える段がありません", s.Name, step.Name)
					case route[i] == "" || route[i] == route[changed]:
						t.Errorf("筋書き %s の向き %s で、確かめる段「%s」が、その前の変える段「%s」と同じ版 %s から答えを受けます",
							s.Name, direction, step.Name, s.Steps[changed].Name, route[changed])
					}
				}
				if resumeChangingStep(step) {
					changed = i
				}
			}
		}
	}
}

// exportCrossFiles は、出力の操作の、版をまたいで確かめる筋書きのファイルである。
var exportCrossFiles = []string{"cross-export.yaml"}

// exportStep は、出力の操作の段かを返す。版に送る、経路が /export で終わる段である。
func exportStep(step Step) bool {
	return step.Kind() == StepVersion && strings.HasSuffix(step.Request.Path, "/export")
}

// TestCrossRoute_ExportSteps は、出力の操作の版をまたぐ筋書きを読み、Java 版から Go 版の向きと Go 版から Java 版の向きの
// それぞれで、出力の2つの段(設定を付けない出力と設定を付けた出力)が、その前の、経歴書か項目を変える段(出力の段でない、
// GET でない、版に送る段)と違う版に送られることを確かめる。段の to: other が外れると、経歴書を保存した版と同じ版で出力する
// ことになり、一方の版が保存した経歴書をもう一方の版が出力できるかを確かめなくなるためである。
// 筋書きのファイルが無いときと、出力の段が GET と POST の1つずつでないときは失敗する。
func TestCrossRoute_ExportSteps(t *testing.T) {
	dir := filepath.Join("..", "scenarios", "export")
	for _, file := range exportCrossFiles {
		if _, err := os.Stat(filepath.Join(dir, file)); err != nil {
			t.Errorf("版をまたぐ筋書き %s がありません: %v", file, err)
		}
	}
	scenarios, err := LoadScenarios(dir, ModeCross)
	if err != nil {
		t.Fatalf("LoadScenarios: %v", err)
	}
	if len(scenarios) == 0 {
		t.Fatalf("%s に、版をまたぐ動かし方の筋書きがありません", dir)
	}
	for _, s := range scenarios {
		methods := map[string]int{}
		for _, step := range s.Steps {
			if exportStep(step) {
				methods[step.Request.Method]++
			}
		}
		if methods["GET"] != 1 || methods["POST"] != 1 || len(methods) != 2 {
			t.Errorf("筋書き %s の出力の段 = %v, want GET と POST の1つずつ", s.Name, methods)
		}
		for _, direction := range []string{CrossJavaToGo, CrossGoToJava} {
			route, err := CrossRoute(s, direction)
			if err != nil {
				t.Errorf("CrossRoute(%s, %s): %v", s.Name, direction, err)
				continue
			}
			changed := -1
			for i, step := range s.Steps {
				switch {
				case exportStep(step):
					switch {
					case changed < 0:
						t.Errorf("筋書き %s の出力の段「%s」の前に、経歴書か項目を変える段がありません", s.Name, step.Name)
					case route[i] == "" || route[i] == route[changed]:
						t.Errorf("筋書き %s の向き %s で、出力の段「%s」が、その前の変える段「%s」と同じ版 %s に送られます",
							s.Name, direction, step.Name, s.Steps[changed].Name, route[changed])
					}
				case resumeChangingStep(step):
					changed = i
				}
			}
		}
	}
}

// backupCrossFiles は、バックアップの操作の、版をまたいで確かめる筋書きのファイルである。
var backupCrossFiles = []string{"cross-backup.yaml"}

// backupStep は、バックアップの書き出しの段かを返す。版に送る、経路が /backup で終わる GET の段である。
func backupStep(step Step) bool {
	return step.Kind() == StepVersion && step.Request.Method == "GET" && strings.HasSuffix(step.Request.Path, "/backup")
}

// restoreStep は、バックアップの戻しの段かを返す。版に送る、/api/resumes/restore への POST の段である。
func restoreStep(step Step) bool {
	return step.Kind() == StepVersion && step.Request.Method == "POST" && step.Request.Path == "/api/resumes/restore"
}

// TestCrossRoute_BackupSteps は、バックアップの操作の版をまたぐ筋書きを読み、Java 版から Go 版の向きと Go 版から Java 版の向きの
// それぞれで、戻しの段が書き出しの段と違う版に送られ、最後の読む段が書き出しの段と同じ版に送られることを確かめる。
// 戻しの段が書き出しの段と同じ版に送られると、一方の版で書き出したファイルをもう一方の版で戻せるかを確かめなくなる。
// 最後の段が書き出しの段と違う版に送られると、戻した経歴書を最初の版で読めるかを確かめなくなる。
// 筋書きのファイルが無いときと、書き出しの段と戻しの段が1つずつでないときと、最後の段が経歴書を読む GET でないときは失敗する。
func TestCrossRoute_BackupSteps(t *testing.T) {
	dir := filepath.Join("..", "scenarios", "backup")
	for _, file := range backupCrossFiles {
		if _, err := os.Stat(filepath.Join(dir, file)); err != nil {
			t.Errorf("版をまたぐ筋書き %s がありません: %v", file, err)
		}
	}
	scenarios, err := LoadScenarios(dir, ModeCross)
	if err != nil {
		t.Fatalf("LoadScenarios: %v", err)
	}
	if len(scenarios) == 0 {
		t.Fatalf("%s に、版をまたぐ動かし方の筋書きがありません", dir)
	}
	for _, s := range scenarios {
		var backups, restores []int
		for i, step := range s.Steps {
			switch {
			case backupStep(step):
				backups = append(backups, i)
			case restoreStep(step):
				restores = append(restores, i)
			}
		}
		if len(backups) != 1 || len(restores) != 1 || restores[0] < backups[0] {
			t.Errorf("筋書き %s の書き出しの段 = %v と戻しの段 = %v, want 書き出しの段のあとに戻しの段が1つずつ", s.Name, backups, restores)
			continue
		}
		backup, restore, last := backups[0], restores[0], len(s.Steps)-1
		if l := s.Steps[last]; l.Kind() != StepVersion || l.Request.Method != "GET" || !strings.HasPrefix(l.Request.Path, "/api/resumes/") {
			t.Errorf("筋書き %s の最後の段「%s」が、経歴書を読む GET の段ではありません", s.Name, l.Name)
		}
		for _, direction := range []string{CrossJavaToGo, CrossGoToJava} {
			route, err := CrossRoute(s, direction)
			if err != nil {
				t.Errorf("CrossRoute(%s, %s): %v", s.Name, direction, err)
				continue
			}
			if route[backup] == "" || route[restore] == route[backup] {
				t.Errorf("筋書き %s の向き %s で、戻しの段「%s」が、書き出しの段「%s」と同じ版 %s に送られます",
					s.Name, direction, s.Steps[restore].Name, s.Steps[backup].Name, route[backup])
			}
			if route[last] != route[backup] {
				t.Errorf("筋書き %s の向き %s で、最後の段「%s」が版 %s に送られます, want 書き出しの段「%s」と同じ版 %s",
					s.Name, direction, s.Steps[last].Name, route[last], s.Steps[backup].Name, route[backup])
			}
		}
	}
}
