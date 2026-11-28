package resume

import (
	"reflect"
	"testing"
)

// TestReadRestoreFile_Reads は、readRestoreFile が、戻しの本文を encoding/json の決まりで読むことを確かめる。
func TestReadRestoreFile_Reads(t *testing.T) {
	t.Parallel()

	t.Run("欄の値を読み、知らない鍵と書き出しの日時を読み飛ばす", func(t *testing.T) {
		t.Parallel()
		f, ok := readRestoreFile([]byte(`{"version":"1.0","exportedAt":"x","unknown":[1,{"a":2}],"resume":{` +
			`"resumeName":"経歴書","date":"2026-01-02","lastName":"山田","firstName":"太郎","extra":true,` +
			`"careers":[{"companyName":"会社","startDate":"2020-04","endDate":null,"active":true}],` +
			`"certifications":[{"name":"資格","date":"2021-05"}]}}`))
		if !ok {
			t.Fatal("読めない")
		}
		if f.Version == nil || *f.Version != "1.0" || f.Resume == nil {
			t.Fatalf("版 = %v、経歴書 = %v", f.Version, f.Resume)
		}
		r := f.Resume
		if *r.Name != "経歴書" || r.Date != dt(2026, 1, 2) || *r.LastName != "山田" || *r.FirstName != "太郎" {
			t.Errorf("経歴書 = %+v", r)
		}
		want := []*rsCareer{{CompanyName: ptr("会社"), StartDate: ym(2020, 4), Active: true}}
		if !reflect.DeepEqual(r.Careers, want) {
			t.Errorf("職歴 = %+v", r.Careers)
		}
		if len(r.Certifications) != 1 || r.Certifications[0].Date != ym(2021, 5) {
			t.Errorf("資格 = %+v", r.Certifications)
		}
	})

	t.Run("鍵の大文字と小文字を区別せず、同じ鍵が2つあればあとの値を使う", func(t *testing.T) {
		t.Parallel()
		f, ok := readRestoreFile([]byte(`{"VERSION":"1.0","resume":{"ResumeName":"一","resumeName":"二"}}`))
		if !ok || f.Version == nil || *f.Version != "1.0" || f.Resume == nil || *f.Resume.Name != "二" {
			t.Errorf("ok = %v、本文 = %+v", ok, f)
		}
	})

	t.Run("並びの null の要素は nil の要素にする", func(t *testing.T) {
		t.Parallel()
		f, ok := readRestoreFile([]byte(`{"resume":{"careers":[null],"projects":[null],"selfPromotions":null}}`))
		if !ok || len(f.Resume.Careers) != 1 || f.Resume.Careers[0] != nil || len(f.Resume.Projects) != 1 ||
			f.Resume.Projects[0] != nil || f.Resume.SelfPromotions != nil {
			t.Errorf("ok = %v、経歴書 = %+v", ok, f.Resume)
		}
	})

	t.Run("工程と技術スタックの無いプロジェクトは、工程をすべて偽、小分類を空の並びにする", func(t *testing.T) {
		t.Parallel()
		f, ok := readRestoreFile([]byte(`{"resume":{"projects":[{"process":null,"techStack":{"backend":{"languages":["Go"]}}}]}}`))
		if !ok {
			t.Fatal("読めない")
		}
		p := f.Resume.Projects[0]
		want := emptyStacks()
		want.Backend.Languages = []*string{ptr("Go")}
		if p.Process != (bkProcess{}) || !reflect.DeepEqual(p.TechStack, want) {
			t.Errorf("工程 = %+v、技術 = %+v", p.Process, p.TechStack)
		}
	})

	t.Run("対になっていないサロゲートと UTF-8 として誤ったバイトは U+FFFD にする", func(t *testing.T) {
		t.Parallel()
		f, ok := readRestoreFile([]byte("{\"resume\":{\"resumeName\":\"a\\ud800b\\udc00\",\"lastName\":\"c\xffd\"}}"))
		if !ok || *f.Resume.Name != "a�b�" || *f.Resume.LastName != "c�d" {
			t.Errorf("ok = %v、名前 = %q、姓 = %q", ok, *f.Resume.Name, *f.Resume.LastName)
		}
	})
}

// TestReadRestoreFile_Rejects は、readRestoreFile が、JSON として読めない本文と、欄の型の違う本文を断ることを確かめる。
func TestReadRestoreFile_Rejects(t *testing.T) {
	t.Parallel()

	for _, body := range []string{
		``,
		`{"version":`,
		`{"version":"1.0"} {}`,
		`{"version":"1.0"}x`,
		`[]`,
		`"1.0"`,
		`{"version":1.0}`,
		`{"resume":[]}`,
		`{"resume":{"resumeName":1}}`,
		`{"resume":{"careers":{}}}`,
		`{"resume":{"careers":[{"active":"true"}]}}`,
		`{"resume":{"careers":[1]}}`,
		`{"resume":{"date":"2026-13-01"}}`,
		`{"resume":{"certifications":[{"date":"2026-1"}]}}`,
		`{"resume":{"projects":[{"process":{"requirements":1}}]}}`,
		`{"resume":{"projects":[{"techStack":{"backend":{"languages":"Go"}}}]}}`,
	} {
		t.Run(body, func(t *testing.T) {
			t.Parallel()
			if _, ok := readRestoreFile([]byte(body)); ok {
				t.Errorf("読めない本文 %s を読んだ", body)
			}
		})
	}
}

// TestReadRestoreFile_Null は、一番外の null を、版も経歴書も無い本文として読むことを確かめる。RestoreResume は版の誤りにする。
func TestReadRestoreFile_Null(t *testing.T) {
	t.Parallel()

	f, ok := readRestoreFile([]byte(`null`))
	if !ok || f.Version != nil || f.Resume != nil {
		t.Errorf("ok = %v、本文 = %+v", ok, f)
	}
}

// TestBuildRestored_NilEntries は、6つの欄のどれかに nil の要素があると、buildRestored が断ることを確かめる。
func TestBuildRestored_NilEntries(t *testing.T) {
	t.Parallel()

	cases := map[string]func(r *rsResume){
		"職歴":      func(r *rsResume) { r.Careers = append(r.Careers, nil) },
		"プロジェクト":  func(r *rsResume) { r.Projects = append(r.Projects, nil) },
		"資格":      func(r *rsResume) { r.Certifications = append(r.Certifications, nil) },
		"ポートフォリオ": func(r *rsResume) { r.Portfolios = append(r.Portfolios, nil) },
		"SNS":     func(r *rsResume) { r.SnsPlatforms = append(r.SnsPlatforms, nil) },
		"自己PR":    func(r *rsResume) { r.SelfPromotions = append(r.SelfPromotions, nil) },
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			r := validRestore()
			mutate(r)
			if _, ok := buildRestored(r, restoreUser); ok {
				t.Error("nil の要素を持つ欄を断らない")
			}
		})
	}
}
