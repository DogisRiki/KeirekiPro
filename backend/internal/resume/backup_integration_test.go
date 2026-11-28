package resume

import (
	"context"
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

// backupFixtures は、バックアップの結合テストが、出力の初期のデータのあとにデータベースに入れる、
// backend/compat/fixtures の SQL のファイルである。backup/backup.sql は経歴書 801 から 805 を、
// resumes/resume-limits.sql は経歴書を上限の数だけ持つ利用者を入れる。
var backupFixtures = []string{
	"backup/backup.sql",
	"resumes/resume-limits.sql",
}

// backupEntryOrderResumeID は、6つの欄のそれぞれに3件の項目を、読み出すときの順と違う順に入れた経歴書である。
const backupEntryOrderResumeID = "00000000-0000-4000-8000-000000000805"

var (
	backupFixturesOnce sync.Once
	errBackupFixtures  error
)

// loadBackupFixtures は、出力の初期のデータを入れてから、バックアップの初期のデータを、
// テストの Postgres に1つのトランザクションで1度だけ入れる。出力の初期のデータは users/basic.sql と resumes/fonts.sql を含み、
// 同じファイルを2度入れると ID が重なって失敗するので、loadExportFixtures に入れさせる。
func loadBackupFixtures(t *testing.T) {
	t.Helper()
	loadExportFixtures(t)
	backupFixturesOnce.Do(func() {
		ctx := context.Background()
		errBackupFixtures = pgx.BeginFunc(ctx, testPool, func(tx pgx.Tx) error {
			for _, name := range backupFixtures {
				script, err := fs.ReadFile(os.DirFS(filepath.Join("..", "..", "compat", "fixtures")), name)
				if err != nil {
					return err
				}
				// 引数の無い Exec は、ファイルの中の複数の文を1回で送る
				if _, err := tx.Exec(ctx, string(script)); err != nil {
					return err
				}
			}
			return nil
		})
	})
	if errBackupFixtures != nil {
		t.Fatalf("バックアップの初期のデータを入れられません: %v", errBackupFixtures)
	}
}

// backupTestNow は、バックアップの結合テストの書き出した日時である。
var backupTestNow = time.Date(2026, 11, 24, 3, 22, 14, 899_978_346, time.UTC)

// TestBackupIntegration_SameValuesAsJavaFile は、経歴書 801 から 804 の書き出しの本文を JSON として読んだ値が、
// exportedAt の値を除いて、Java 版が書き出したファイル compat/fixtures/backups/java-801.json から java-804.json を
// 読んだ値と同じことと、結果の Content-Type が application/json で、ファイル名が、使えない字を直した経歴書の名前に
// _backup.json を付けた名前であることを確かめる(要件3の受入基準1、3、4)。字の逃がし方と欄の間の空白は比べない。
func TestBackupIntegration_SameValuesAsJavaFile(t *testing.T) {
	loadBackupFixtures(t)
	svc := New(Deps{Pool: testPool, Now: func() time.Time { return backupTestNow }})
	cases := []struct {
		n        string
		fileName string
	}{
		{"801", "すべての欄を持つバックアップの経歴書_backup.json"},
		{"802", "今も続く仕事のバックアップの経歴書_backup.json"},
		// \ / : * ? " < > | の9字は _ にし、U+2028 は制御の字でないので残す
		{"803", "経歴書_________\u2028の名前_backup.json"},
		// < > " は _ にし、改行とタブは制御の字なので除く。& と ' と絵文字と U+2028 と U+2029 は残す
		{"804", "記号__&_'と改行タブ\U0001F600\u2028\u2029の経歴書_backup.json"},
	}
	for _, c := range cases {
		t.Run(c.n, func(t *testing.T) {
			java, err := fs.ReadFile(os.DirFS(filepath.Join("..", "..", "compat", "fixtures", "backups")), "java-"+c.n+".json")
			if err != nil {
				t.Fatalf("Java 版のファイルを読めません: %v", err)
			}
			got, err := svc.BackupResume(t.Context(), exportUser1, "00000000-0000-4000-8000-000000000"+c.n)
			if err != nil {
				t.Fatalf("書き出せません: %v", err)
			}
			gotValue, wantValue := backupValue(t, got.Body), backupValue(t, java)
			if at := gotValue["exportedAt"]; at != "2026-11-24T03:22:14.899978346Z" {
				t.Errorf("exportedAt = %v", at)
			}
			if _, ok := wantValue["exportedAt"]; !ok {
				t.Fatalf("Java 版のファイルに exportedAt の欄が無い: %s", java)
			}
			wantValue["exportedAt"] = gotValue["exportedAt"]
			if !reflect.DeepEqual(gotValue, wantValue) {
				t.Errorf("本文の値が Java 版と違う。\n--- Go 版\n%s\n--- Java 版\n%s", got.Body, java)
			}
			if got.ContentType != "application/json" || got.FileName != c.fileName || got.Inline {
				t.Errorf("Content-Type = %q、ファイル名 = %q、Inline = %v。want application/json、%q、false",
					got.ContentType, got.FileName, got.Inline, c.fileName)
			}
		})
	}
}

// backupValue は、バックアップのファイルの本文 body を JSON として読んだ値を返す。
func backupValue(t *testing.T, body []byte) map[string]any {
	t.Helper()
	var v map[string]any
	if err := json.Unmarshal(body, &v); err != nil {
		t.Fatalf("本文を JSON として読めません: %v: %s", err, body)
	}
	return v
}

// backupOrderView は、書き出しの本文の6つの欄の項目を、項目ごとに1つの字で表した並びである。
type backupOrderView struct {
	Careers        []string
	Projects       []string
	Certifications []string
	Portfolios     []string
	SnsPlatforms   []string
	SelfPromotions []string
}

// TestBackupIntegration_EntryOrder は、経歴書 805 の書き出しの項目が、6つの欄のそれぞれで、
// GetResume が返す順に並ぶことを確かめる(要件3の受入基準2。要件6の受入基準2の、項目の順を Go 版のテストで確かめること)。
// 経歴書 805 は、どの欄の項目も、データベースに入れた順と読み出すときの順が違う。
func TestBackupIntegration_EntryOrder(t *testing.T) {
	loadBackupFixtures(t)
	got, err := New(Deps{Pool: testPool}).BackupResume(t.Context(), exportUser1, backupEntryOrderResumeID)
	if err != nil {
		t.Fatalf("書き出せません: %v", err)
	}
	var f struct {
		Resume struct {
			Careers []struct {
				CompanyName string `json:"companyName"`
				StartDate   string `json:"startDate"`
			} `json:"careers"`
			Projects []struct {
				Name      string `json:"name"`
				StartDate string `json:"startDate"`
			} `json:"projects"`
			Certifications []struct {
				Name string `json:"name"`
			} `json:"certifications"`
			Portfolios []struct {
				Name string `json:"name"`
			} `json:"portfolios"`
			SnsPlatforms []struct {
				Name string `json:"name"`
			} `json:"snsPlatforms"`
			SelfPromotions []struct {
				Title string `json:"title"`
			} `json:"selfPromotions"`
		} `json:"resume"`
	}
	if err := json.Unmarshal(got.Body, &f); err != nil {
		t.Fatalf("本文を読めません: %v: %s", err, got.Body)
	}
	var gotView backupOrderView
	for _, c := range f.Resume.Careers {
		gotView.Careers = append(gotView.Careers, c.CompanyName+" "+c.StartDate)
	}
	for _, p := range f.Resume.Projects {
		gotView.Projects = append(gotView.Projects, p.Name+" "+p.StartDate)
	}
	for _, c := range f.Resume.Certifications {
		gotView.Certifications = append(gotView.Certifications, c.Name)
	}
	for _, p := range f.Resume.Portfolios {
		gotView.Portfolios = append(gotView.Portfolios, p.Name)
	}
	for _, s := range f.Resume.SnsPlatforms {
		gotView.SnsPlatforms = append(gotView.SnsPlatforms, s.Name)
	}
	for _, s := range f.Resume.SelfPromotions {
		gotView.SelfPromotions = append(gotView.SelfPromotions, s.Title)
	}

	r := mustGetResume(t, exportUser1, backupEntryOrderResumeID)
	var wantView backupOrderView
	for _, c := range r.Careers {
		wantView.Careers = append(wantView.Careers, c.CompanyName+" "+backupYearMonth(c.Period.StartDate))
	}
	for _, p := range r.Projects {
		wantView.Projects = append(wantView.Projects, p.Name+" "+backupYearMonth(p.Period.StartDate))
	}
	for _, c := range r.Certifications {
		wantView.Certifications = append(wantView.Certifications, c.Name)
	}
	for _, p := range r.Portfolios {
		wantView.Portfolios = append(wantView.Portfolios, p.Name)
	}
	for _, s := range r.SnsPlatforms {
		wantView.SnsPlatforms = append(wantView.SnsPlatforms, s.Name)
	}
	for _, s := range r.SelfPromotions {
		wantView.SelfPromotions = append(wantView.SelfPromotions, s.Title)
	}

	for name, n := range map[string]int{
		"careers": len(wantView.Careers), "projects": len(wantView.Projects), "certifications": len(wantView.Certifications),
		"portfolios": len(wantView.Portfolios), "snsPlatforms": len(wantView.SnsPlatforms), "selfPromotions": len(wantView.SelfPromotions),
	} {
		if n != 3 {
			t.Errorf("経歴書 805 の %s の項目が %d 件。want 3 件", name, n)
		}
	}
	if !reflect.DeepEqual(gotView, wantView) {
		t.Errorf("書き出しの項目の順が GetResume と違う。\n got %+v\nwant %+v", gotView, wantView)
	}
}

// TestBackupIntegration_OtherUserIsNotFound は、無い経歴書と、ID の形でない値と、ほかの利用者の経歴書の書き出しが、
// どれも無い経歴書の誤りになることを確かめる(要件5の受入基準1と2)。
func TestBackupIntegration_OtherUserIsNotFound(t *testing.T) {
	loadBackupFixtures(t)
	svc := New(Deps{Pool: testPool})
	ctx := t.Context()
	const ownedResumeID = "00000000-0000-4000-8000-000000000801"

	// 同じ経歴書を持ち主が求めると書き出せることを先に確かめる。ほかの利用者の答えが 404 になるのが、
	// 経歴書を書き出せないためでないことを示すためである。
	if _, err := svc.BackupResume(ctx, exportUser1, ownedResumeID); err != nil {
		t.Fatalf("持ち主が経歴書を書き出せない: %v", err)
	}
	cases := []struct {
		name, resumeID string
	}{
		{"無い経歴書", exportMissingResumeID},
		{"ID の形でない値", "abc"},
		{"ほかの利用者の経歴書", ownedResumeID},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			userID := exportUser1
			if c.name == "ほかの利用者の経歴書" {
				userID = exportUser2
			}
			got, err := svc.BackupResume(ctx, userID, c.resumeID)
			assertResumeNotFound(t, err)
			if got.Body != nil {
				t.Errorf("誤りのときに本文を返した: %s", got.Body)
			}
		})
	}
}
