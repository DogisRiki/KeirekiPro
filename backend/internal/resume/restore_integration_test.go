package resume

import (
	"bytes"
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// restoreLimitUser は、経歴書を上限の50件持つ resumes/resume-limits.sql の利用者である。
var restoreLimitUser = uuid.MustParse("00000000-0000-4000-8000-000000000500")

// restoreFile は、戻しで確かめる値の決まりをすべて満たす、6つの欄に1件ずつ項目を持つ戻しの本文の値を返す。
// mutate が nil でなければ、mutate で本文の値を変えてから返す。
func restoreFile(mutate func(file, resume map[string]any)) map[string]any {
	resume := map[string]any{
		"resumeName": "戻す経歴書", "date": "2026-02-05", "lastName": "高橋", "firstName": "次郎",
		"careers": []any{
			map[string]any{"companyName": "株式会社もどす", "startDate": "2016-04", "endDate": "2020-03", "active": false},
		},
		"projects": []any{map[string]any{
			"companyName": "株式会社もどす", "startDate": "2016-04", "endDate": "2019-09", "active": false,
			"name": "在庫の管理の画面の開発", "overview": "概要", "teamComp": "全体6名", "role": "実装", "achievement": "成果",
			"process": map[string]any{"basicDesign": true, "implementation": true},
		}},
		"certifications": []any{map[string]any{"name": "基本情報技術者", "date": "2015-10"}},
		"portfolios": []any{
			map[string]any{"name": "作品", "overview": "説明", "techStack": "Go", "link": "https://example.com/works"},
		},
		"snsPlatforms":   []any{map[string]any{"name": "GitHub", "link": "https://github.com/restore"}},
		"selfPromotions": []any{map[string]any{"title": "題", "content": "中身"}},
	}
	file := map[string]any{"version": "1.0", "exportedAt": "2026-02-05T01:00:00Z", "resume": resume}
	if mutate != nil {
		mutate(file, resume)
	}
	return file
}

// endBeforeStart は、職歴の終わりの年月を始まりの年月より前にして、本文を値の決まりを満たさないものにする。
func endBeforeStart(_, resume map[string]any) {
	resume["careers"] = []any{
		map[string]any{"companyName": "株式会社もどす", "startDate": "2016-04", "endDate": "2016-03", "active": false},
	}
}

// TestRestoreIntegration_Order は、戻しが、本文、ファイルの版、経歴書の数、経歴書の中身、
// 名前の重なり、値の決まりの順に確かめ、2つ以上の条件に当たる要求が順の早い条件の誤りになることを確かめる
// (要件4の受入基準1と3と4)。
func TestRestoreIntegration_Order(t *testing.T) {
	loadBackupFixtures(t)
	svc := New(Deps{Pool: testPool})
	user := insertTestUser(t)
	dupUser := insertTestUser(t)
	saveResume(t, emptyResume(dupUser, "重なる経歴書"))
	// 名前の重なりは、名前の値の決まりより先に確かめるので、使えない字を含む名前も重なる
	saveResume(t, emptyResume(dupUser, "経歴書/一"))
	saveResume(t, emptyResume(dupUser, "重なる�"))

	unsupported := auth.ErrBusiness(MessageUnsupportedBackupVersion)
	invalid := auth.ErrBusiness(MessageInvalidBackupFile)
	limit := resumeLimit.check(resumeLimit.limit)
	cases := []struct {
		name   string
		userID uuid.UUID
		body   []byte
		want   error
	}{
		{"読めない本文は、上限の利用者でも本文の誤り", restoreLimitUser, []byte(`{"version":`), errUnreadableInput()},
		{"版の誤りは、経歴書の数の上限より先", restoreLimitUser, jsonBody(t, restoreFile(func(f, _ map[string]any) {
			f["version"] = "2.0"
		})), unsupported},
		{"版の無いファイルは版の誤り", user, jsonBody(t, restoreFile(func(f, _ map[string]any) {
			delete(f, "version")
		})), unsupported},
		{"版の誤りは、経歴書の中身が無いことより先", user, jsonBody(t, restoreFile(func(f, _ map[string]any) {
			f["version"], f["resume"] = "1.1", nil
		})), unsupported},
		{"経歴書の数の上限", restoreLimitUser, jsonBody(t, restoreFile(nil)), limit},
		{"経歴書の数の上限は、経歴書の中身が無いことより先", restoreLimitUser, jsonBody(t, restoreFile(func(f, _ map[string]any) {
			delete(f, "resume")
		})), limit},
		{"経歴書の数の上限は、名前の重なりと値の決まりより先", restoreLimitUser, jsonBody(t, restoreFile(func(f, r map[string]any) {
			r["resumeName"] = "上限の経歴書01"
			endBeforeStart(f, r)
		})), limit},
		{"経歴書の中身が無いファイルは値の決まりの誤り", user, jsonBody(t, restoreFile(func(f, _ map[string]any) {
			delete(f, "resume")
		})), invalid},
		{"名前の重なり", dupUser, jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["resumeName"] = "重なる経歴書"
		})), errResumeNameDuplicated()},
		{"名前の重なりは、値の決まりより先", dupUser, jsonBody(t, restoreFile(func(f, r map[string]any) {
			r["resumeName"] = "重なる経歴書"
			endBeforeStart(f, r)
		})), errResumeNameDuplicated()},
		{"名前の重なりは、名前の値の決まりより先", dupUser, jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["resumeName"] = "経歴書/一"
		})), errResumeNameDuplicated()},
		// 対になっていないサロゲートの書き方は U+FFFD として読むので、U+FFFD を含む名前の経歴書と重なる
		{"対になっていないサロゲートの名前の重なり", dupUser, bytes.Replace(jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["resumeName"] = "重なるSURROGATE"
		})), []byte("SURROGATE"), []byte(`\ud800`), 1), errResumeNameDuplicated()},
		{"名前の無いファイルは、名前の重なりを確かめずに値の決まりの誤り", dupUser, jsonBody(t, restoreFile(func(_, r map[string]any) {
			delete(r, "resumeName")
		})), invalid},
		{"値の決まりを満たさないファイル", user, jsonBody(t, restoreFile(endBeforeStart)), invalid},
		{"値の無い要素を持つ欄は値の決まりの誤り", user, jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["careers"] = []any{nil}
		})), invalid},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := svc.RestoreResume(t.Context(), c.userID, c.body)
			if want, ok := c.want.(*auth.Error); ok {
				assertError(t, c.name, err, want)
			} else if !errors.Is(err, c.want) {
				t.Errorf("誤り: got %#v, want %#v", err, c.want)
			}
			if got.ID != uuid.Nil {
				t.Errorf("誤りのときに経歴書を返した: %+v", got)
			}
		})
	}
	if n := countUserResumes(t, user); n != 0 {
		t.Errorf("断った要求のあとの経歴書の数 = %d。want 0", n)
	}
	if n := countUserResumes(t, dupUser); n != 3 {
		t.Errorf("断った要求のあとの経歴書の数 = %d。want 3", n)
	}
}

// TestRestoreIntegration_Owner は、戻した経歴書が要求を送った利用者の経歴書になり、ほかの利用者からは無い経歴書になることと、
// データベースに入れた経歴書と答えの経歴書が同じことを確かめる(要件2の受入基準3)。
func TestRestoreIntegration_Owner(t *testing.T) {
	loadBackupFixtures(t)
	now := japanTime(2026, time.November, 24, 12, 34, 56, 789_000)
	svc := New(Deps{Pool: testPool, Now: fixedNow(now)})
	owner := insertTestUser(t)
	other := insertTestUser(t)

	got, err := svc.RestoreResume(t.Context(), owner, jsonBody(t, restoreFile(nil)))
	if err != nil {
		t.Fatalf("戻せません: %v", err)
	}
	if got.UserID != owner || got.Name != "戻す経歴書" || !got.CreatedAt.Equal(now) || !got.UpdatedAt.Equal(now) {
		t.Errorf("利用者 = %s、名前 = %q、作った日時 = %v、直した日時 = %v。want %s、戻す経歴書、%v、%v",
			got.UserID, got.Name, got.CreatedAt, got.UpdatedAt, owner, now, now)
	}
	stored := mustGetResume(t, owner, got.ID.String())
	if !reflect.DeepEqual(stored, got) {
		t.Errorf("データベースの経歴書が答えと違う:\n  db %+v\ngot %+v", stored, got)
	}
	if _, err := svc.GetResume(t.Context(), other, got.ID.String()); err == nil {
		t.Error("ほかの利用者が戻した経歴書を読めた")
	} else {
		assertResumeNotFound(t, err)
	}
	if n := countUserResumes(t, owner); n != 1 {
		t.Errorf("持ち主の経歴書の数 = %d。want 1", n)
	}
	if n := countUserResumes(t, other); n != 0 {
		t.Errorf("ほかの利用者の経歴書の数 = %d。want 0", n)
	}
}

// TestRestoreIntegration_NoLeftover は、値の決まりを満たさない要求と、データベースの列の長さを超える値の要求のあとに、
// 経歴書と項目の行の数が変わらないことを確かめる(要件4の受入基準1)。
func TestRestoreIntegration_NoLeftover(t *testing.T) {
	loadBackupFixtures(t)
	svc := New(Deps{Pool: testPool})
	user := insertTestUser(t)
	cases := []struct {
		name    string
		mutate  func(file, resume map[string]any)
		authErr bool
	}{
		{"値の決まりを満たさない要求", endBeforeStart, true},
		// ポートフォリオの link の列は 255 字までで、経歴書と職歴とプロジェクトと資格の行を入れたあとに断られる
		{"データベースの列の長さを超える値の要求", func(_, r map[string]any) {
			r["portfolios"] = []any{map[string]any{
				"name": "作品", "overview": "説明", "link": "https://example.com/" + strings.Repeat("a", 300),
			}}
		}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			before := countAllResumeRows(t)
			_, err := svc.RestoreResume(t.Context(), user, jsonBody(t, restoreFile(c.mutate)))
			var ae *auth.Error
			if err == nil || errors.As(err, &ae) != c.authErr {
				t.Errorf("誤り = %#v。want 400 の誤りか = %v", err, c.authErr)
			}
			if after := countAllResumeRows(t); after != before {
				t.Errorf("断った要求のあとの行の数 = %d。want %d", after, before)
			}
			if n := countUserResumes(t, user); n != 0 {
				t.Errorf("断った要求のあとの経歴書の数 = %d。want 0", n)
			}
		})
	}
}

// countAllResumeRows は、経歴書の表と、6つの欄の項目の表と、プロジェクトの技術スタックの表の行を合わせた数を返す。
func countAllResumeRows(t *testing.T) int {
	t.Helper()
	var n int
	if err := testPool.QueryRow(t.Context(), `
		SELECT (SELECT count(*) FROM resumes) + (SELECT count(*) FROM careers) + (SELECT count(*) FROM projects)
		     + (SELECT count(*) FROM project_tech_stacks) + (SELECT count(*) FROM certifications)
		     + (SELECT count(*) FROM portfolios) + (SELECT count(*) FROM sns_platforms) + (SELECT count(*) FROM self_promotions)`,
	).Scan(&n); err != nil {
		t.Fatalf("行を数えられません: %v", err)
	}
	return n
}

// TestRestoreIntegration_DeletedUser は、退会してすでに居ない利用者の要求のうち、変えた動きの一覧の CB-063 と CB-066 の
// 2つの戻しが 404 と「対象の職務経歴書データが存在しません。」になり、CB-064 と CB-065 の2つの戻しと、版の誤りと
// 読めない本文と値の決まりを満たさない本文が、利用者が居るときと同じ 400 になることを確かめる(要件5の受入基準3)。
func TestRestoreIntegration_DeletedUser(t *testing.T) {
	loadBackupFixtures(t)
	svc := New(Deps{Pool: testPool})
	user := insertTestUser(t)
	if _, err := testPool.Exec(t.Context(), `DELETE FROM users WHERE id = $1::uuid`, user.String()); err != nil {
		t.Fatalf("退会した利用者の行を消せません: %v", err)
	}
	const linkPrefix = "https://example.com/"
	cases := []struct {
		name string
		body []byte
		want *auth.Error
	}{
		{"CB-063 版の正しいファイル", jsonBody(t, restoreFile(nil)), errResumeNotFound()},
		{"CB-064 項目の並びに値の無い要素を持つファイル", jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["careers"] = []any{nil}
		})), auth.ErrBusiness(MessageInvalidBackupFile)},
		{"CB-065 経歴書の中身が無いファイル", jsonBody(t, restoreFile(func(f, _ map[string]any) {
			delete(f, "resume")
		})), auth.ErrBusiness(MessageInvalidBackupFile)},
		{"CB-066 256文字のリンクを持つファイル", jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["portfolios"] = []any{map[string]any{
				"name": "作品", "overview": "説明", "link": linkPrefix + strings.Repeat("a", 256-len(linkPrefix)),
			}}
		})), errResumeNotFound()},
		{"版の誤り", jsonBody(t, restoreFile(func(f, _ map[string]any) {
			f["version"] = "2.0"
		})), auth.ErrBusiness(MessageUnsupportedBackupVersion)},
		{"読めない本文", []byte(`{"version":`), errUnreadableInput()},
		{"値を読めない本文", jsonBody(t, restoreFile(func(_, r map[string]any) {
			r["date"] = "not-a-date"
		})), errUnreadableInput()},
		{"値の決まりを満たさない本文", jsonBody(t, restoreFile(endBeforeStart)), auth.ErrBusiness(MessageInvalidBackupFile)},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := svc.RestoreResume(t.Context(), user, c.body)
			assertError(t, c.name, err, c.want)
			if got.ID != uuid.Nil {
				t.Errorf("誤りのときに経歴書を返した: %+v", got)
			}
		})
	}
}
