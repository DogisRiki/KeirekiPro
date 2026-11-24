package resume

import (
	"encoding/json"
	"errors"
	"testing"
	"time"
)

// backupNow は、書き出しのテストの今の時刻である。日本の時刻で渡し、世界標準時で書かれることを確かめる。
var backupNow = time.Date(2026, 11, 24, 10, 2, 3, 456_000_000, time.FixedZone("JST", 9*60*60))

// TestBackup_OmittedFields は、バックアップのファイルが、BackupResumeResponse と同じ欄の名前と並びで書かれ、
// 値の無い欄を書かないことを確かめる(要件3の受入基準1)。書かない欄は、無い姓と名、無い終わりの年月、項目の無い欄、
// 値の無い技術の分類の並び、無いポートフォリオの技術である。版は 1.0 と書き、書き出した日時は世界標準時で書く。
func TestBackup_OmittedFields(t *testing.T) {
	cases := []struct {
		name   string
		resume Resume
		want   string
	}{
		{
			name: "すべての欄を持つ経歴書",
			resume: Resume{
				Name: "経歴書", Date: Date{2026, 2, 4}, LastName: ptr("鈴木"), FirstName: ptr("一郎"),
				Careers: []Career{{CompanyName: "株式会社ひかく", Period: Period{
					StartDate: YearMonth{2012, 4}, EndDate: &YearMonth{2018, 3},
				}}},
				Projects: []Project{{
					CompanyName: "株式会社ひかく", Period: Period{StartDate: YearMonth{2016, 4}, Active: true},
					Name: "案件", Overview: "概要", TeamComp: "5名", Role: "開発", Achievement: "成果",
					Process: Process{Requirements: true, BasicDesign: true, Implementation: true},
					TechStack: TechStack{
						Frontend:       FrontendStacks[*string]{Languages: []*string{ptr("TypeScript")}},
						Backend:        BackendStacks[*string]{Auth: []*string{nil, ptr("JWT")}},
						Infrastructure: InfrastructureStacks[*string]{Clouds: []*string{}},
					},
				}},
				Certifications: []Certification{{Name: "基本情報技術者", Date: YearMonth{2010, 10}}},
				Portfolios: []Portfolio{
					{Name: "作品", Overview: "説明", TechStack: ptr("Go"), Link: "https://example.com"},
					{Name: "作品2", Overview: "説明2", Link: "https://example.com/2"},
				},
				SnsPlatforms:   []SnsPlatform{{Name: "GitHub", Link: "https://github.com/x"}},
				SelfPromotions: []SelfPromotion{{Title: "A 題", Content: "中身"}},
			},
			want: `{"version":"1.0","exportedAt":"2026-11-24T01:02:03.456Z","resume":{"resumeName":"経歴書","date":"2026-02-04",` +
				`"lastName":"鈴木","firstName":"一郎",` +
				`"careers":[{"companyName":"株式会社ひかく","startDate":"2012-04","endDate":"2018-03","active":false}],` +
				`"projects":[{"companyName":"株式会社ひかく","startDate":"2016-04","active":true,"name":"案件","overview":"概要",` +
				`"teamComp":"5名","role":"開発","achievement":"成果",` +
				`"process":{"requirements":true,"basicDesign":true,"detailedDesign":false,"implementation":true,` +
				`"integrationTest":false,"systemTest":false,"maintenance":false},` +
				`"techStack":{"frontend":{"languages":["TypeScript"]},"backend":{"auth":[null,"JWT"]},"infrastructure":{},"tools":{}}}],` +
				`"certifications":[{"name":"基本情報技術者","date":"2010-10"}],` +
				`"portfolios":[{"name":"作品","overview":"説明","techStack":"Go","link":"https://example.com"},` +
				`{"name":"作品2","overview":"説明2","link":"https://example.com/2"}],` +
				`"snsPlatforms":[{"name":"GitHub","link":"https://github.com/x"}],` +
				`"selfPromotions":[{"title":"A 題","content":"中身"}]}}`,
		},
		{
			name: "姓と名と項目の無い経歴書",
			resume: Resume{
				Name: "空の経歴書", Date: Date{2026, 1, 1},
				Careers: []Career{}, Projects: []Project{}, Certifications: []Certification{},
			},
			want: `{"version":"1.0","exportedAt":"2026-11-24T01:02:03.456Z","resume":{"resumeName":"空の経歴書","date":"2026-01-01"}}`,
		},
		{
			name: "姓と名が空の字の経歴書は、空の字を書く",
			resume: Resume{
				Name: "名前の空の経歴書", Date: Date{2026, 1, 1}, LastName: ptr(""), FirstName: ptr(""),
			},
			want: `{"version":"1.0","exportedAt":"2026-11-24T01:02:03.456Z","resume":{"resumeName":"名前の空の経歴書","date":"2026-01-01",` +
				`"lastName":"","firstName":""}}`,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := buildBackup(c.resume, backupNow)
			if err != nil {
				t.Fatalf("buildBackup の誤り: %v", err)
			}
			if string(got.Body) != c.want {
				t.Errorf("本文:\n got %s\nwant %s", got.Body, c.want)
			}
		})
	}
}

// TestBackup_ExportedAtFraction は、書き出した日時の秒の小数を、Java の Instant.toString と同じく、
// 0 なら書かず、0 でなければ 3、6、9 桁のうち値を表せる最も短い桁数で書くことを確かめる(要件3の受入基準1)。
func TestBackup_ExportedAtFraction(t *testing.T) {
	cases := []struct {
		nanos int
		want  string
	}{
		{0, "2026-11-24T01:02:03Z"},
		{456_000_000, "2026-11-24T01:02:03.456Z"},
		{1_000_000, "2026-11-24T01:02:03.001Z"},
		{100_000_000, "2026-11-24T01:02:03.100Z"},
		{456_700_000, "2026-11-24T01:02:03.456700Z"},
		{1_000, "2026-11-24T01:02:03.000001Z"},
		{456_789_012, "2026-11-24T01:02:03.456789012Z"},
		{882_047_430, "2026-11-24T01:02:03.882047430Z"},
		{1, "2026-11-24T01:02:03.000000001Z"},
	}
	for _, c := range cases {
		t.Run(c.want, func(t *testing.T) {
			now := time.Date(2026, 11, 24, 10, 2, 3, c.nanos, time.FixedZone("JST", 9*60*60))
			got, err := buildBackup(Resume{Name: "経歴書", Date: Date{2026, 1, 1}}, now)
			if err != nil {
				t.Fatalf("buildBackup の誤り: %v", err)
			}
			var f struct {
				Version    string `json:"version"`
				ExportedAt string `json:"exportedAt"`
			}
			if err := json.Unmarshal(got.Body, &f); err != nil {
				t.Fatalf("本文を読めない: %v: %s", err, got.Body)
			}
			if f.ExportedAt != c.want || f.Version != "1.0" {
				t.Errorf("exportedAt = %q、version = %q。want %q、1.0", f.ExportedAt, f.Version, c.want)
			}
		})
	}
}

// TestBackup_DateOutOfRange は、日付か年月の年が 1 から 9999 の外にあれば errBackupDate を返し、
// 1 と 9999 の年は4桁で書くことを確かめる。
func TestBackup_DateOutOfRange(t *testing.T) {
	base := func() Resume {
		return Resume{
			Name: "経歴書", Date: Date{2026, 1, 2},
			Careers: []Career{{CompanyName: "会社", Period: Period{
				StartDate: YearMonth{2010, 4}, EndDate: &YearMonth{2012, 3},
			}}},
			Projects: []Project{{CompanyName: "会社", Period: Period{
				StartDate: YearMonth{2010, 4}, EndDate: &YearMonth{2012, 3},
			}}},
			Certifications: []Certification{{Name: "資格", Date: YearMonth{2011, 5}}},
		}
	}
	bad := []struct {
		name   string
		mutate func(r *Resume)
	}{
		{"経歴書の日付の年が 0", func(r *Resume) { r.Date.Year = 0 }},
		{"経歴書の日付の年が 10000", func(r *Resume) { r.Date.Year = 10000 }},
		{"職歴の始まりの年が 0", func(r *Resume) { r.Careers[0].Period.StartDate.Year = 0 }},
		{"職歴の終わりの年が 10000", func(r *Resume) { r.Careers[0].Period.EndDate.Year = 10000 }},
		{"プロジェクトの始まりの年が -1", func(r *Resume) { r.Projects[0].Period.StartDate.Year = -1 }},
		{"プロジェクトの終わりの年が 10000", func(r *Resume) { r.Projects[0].Period.EndDate.Year = 10000 }},
		{"資格の年が 0", func(r *Resume) { r.Certifications[0].Date.Year = 0 }},
	}
	for _, c := range bad {
		t.Run(c.name, func(t *testing.T) {
			r := base()
			c.mutate(&r)
			if _, err := buildBackup(r, backupNow); !errors.Is(err, errBackupDate) {
				t.Errorf("誤り = %v。want errBackupDate", err)
			}
		})
	}
	t.Run("年が 1 と 9999 の日付は4桁で書く", func(t *testing.T) {
		r := base()
		r.Date = Date{1, 1, 1}
		r.Careers[0].Period = Period{StartDate: YearMonth{1, 1}, EndDate: &YearMonth{9999, 12}}
		r.Projects[0].Period = Period{StartDate: YearMonth{9999, 12}, EndDate: &YearMonth{1, 2}}
		r.Certifications[0].Date = YearMonth{9999, 12}
		got, err := buildBackup(r, backupNow)
		if err != nil {
			t.Fatalf("buildBackup の誤り: %v", err)
		}
		var f struct {
			Resume struct {
				Date    string `json:"date"`
				Careers []struct {
					StartDate string `json:"startDate"`
					EndDate   string `json:"endDate"`
				} `json:"careers"`
				Projects []struct {
					StartDate string `json:"startDate"`
					EndDate   string `json:"endDate"`
				} `json:"projects"`
				Certifications []struct {
					Date string `json:"date"`
				} `json:"certifications"`
			} `json:"resume"`
		}
		if err := json.Unmarshal(got.Body, &f); err != nil {
			t.Fatalf("本文を読めない: %v: %s", err, got.Body)
		}
		res := f.Resume
		if res.Date != "0001-01-01" || res.Careers[0].StartDate != "0001-01" || res.Careers[0].EndDate != "9999-12" ||
			res.Projects[0].StartDate != "9999-12" || res.Projects[0].EndDate != "0001-02" || res.Certifications[0].Date != "9999-12" {
			t.Errorf("日付の書き方が違う: %s", got.Body)
		}
	})
}

// TestBackup_FileName は、結果のファイル名が、経歴書の名前を sanitizeFileName で直した名前に _backup.json を付けた名前になり、
// Content-Type が application/json で、出し方が attachment になることを確かめる(要件3の受入基準4)。
func TestBackup_FileName(t *testing.T) {
	cases := []struct {
		name, resumeName, want string
	}{
		{"日本語の名前", "経歴書", "経歴書_backup.json"},
		{"使えない字は _ にする", ` 経歴書<1>/a:b `, "経歴書_1__a_b_backup.json"},
		{"空白だけの名前は resume にする", "  ", "resume_backup.json"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := buildBackup(Resume{Name: c.resumeName, Date: Date{2026, 1, 1}}, backupNow)
			if err != nil {
				t.Fatalf("buildBackup の誤り: %v", err)
			}
			if got.FileName != c.want || got.ContentType != "application/json" || got.Inline {
				t.Errorf("FileName = %q、ContentType = %q、Inline = %v。want %q、application/json、false",
					got.FileName, got.ContentType, got.Inline, c.want)
			}
		})
	}
}
