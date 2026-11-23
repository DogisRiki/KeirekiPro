package resume

import (
	"context"
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// exportFixtures は、出力の結合テストがデータベースに入れる、backend/compat/fixtures の SQL のファイルである。
// export/export.sql は resumes/many-pages.sql の経歴書に自己PR を足すので、最後に入れる。
var exportFixtures = []string{
	"users/basic.sql",
	"resumes/empty.sql",
	"resumes/many-pages.sql",
	"resumes/long-text.sql",
	"resumes/fonts.sql",
	"export/export.sql",
}

// 初期のデータの利用者と経歴書の ID である。経歴書はすべて user1 のものである。
var (
	exportUser1 = uuid.MustParse("00000000-0000-4000-8000-000000000001")
	exportUser2 = uuid.MustParse("00000000-0000-4000-8000-000000000002")
)

const (
	// exportEmptyResumeID は、名前と日付だけを持ち、出力の前提を満たさない resumes/empty.sql の経歴書である。
	exportEmptyResumeID = "00000000-0000-4000-8000-000000000101"
	// exportReadyResumeID は、出力の前提を満たす export/export.sql の項目の少ない経歴書である。
	exportReadyResumeID = "00000000-0000-4000-8000-000000000601"
	// exportFullResumeID は、6つの欄の項目をすべて持つ resumes/fonts.sql の経歴書である。
	exportFullResumeID = "00000000-0000-4000-8000-000000000401"
	// exportMissingResumeID は、データベースに無い経歴書の ID である。
	exportMissingResumeID = "00000000-0000-4000-8000-000000000999"
)

var (
	exportFixturesOnce sync.Once
	errExportFixtures  error
)

// loadExportFixtures は、出力の初期のデータを、テストの Postgres に1つのトランザクションで1度だけ入れる。
// 初期のデータの ID は決まった値なので、2度入れると重なって失敗するためである。
func loadExportFixtures(t *testing.T) {
	t.Helper()
	exportFixturesOnce.Do(func() {
		ctx := context.Background()
		errExportFixtures = pgx.BeginFunc(ctx, testPool, func(tx pgx.Tx) error {
			for _, name := range exportFixtures {
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
	if errExportFixtures != nil {
		t.Fatalf("出力の初期のデータを入れられません: %v", errExportFixtures)
	}
}

// exportService は、偽の PDF の部品を渡した Service を返す。
func exportService(renderer *fakePDFRenderer) *Service {
	return New(Deps{Pool: testPool, PDF: renderer})
}

// TestExportIntegration_MarkdownMatchesJava は、経歴書5件の設定を付けない Markdown が、
// Java 版の Markdown と1バイトも違わないことを確かめる(要件2の受入基準2)。
func TestExportIntegration_MarkdownMatchesJava(t *testing.T) {
	loadExportFixtures(t)
	svc := exportService(&fakePDFRenderer{})
	for _, n := range []string{"601", "201", "301", "401", "701"} {
		t.Run(n, func(t *testing.T) {
			want, err := fs.ReadFile(os.DirFS(filepath.Join("testdata", "export", "markdown")), n+".md")
			if err != nil {
				t.Fatalf("Java 版の Markdown を読めません: %v", err)
			}
			id := "00000000-0000-4000-8000-000000000" + n
			got, err := svc.ExportResume(t.Context(), exportUser1, id, ExportMarkdown)
			if err != nil {
				t.Fatalf("Markdown を出力できません: %v", err)
			}
			if string(got.Body) != string(want) {
				t.Errorf("Markdown が Java 版と違う。\n--- Go 版\n%s\n--- Java 版\n%s", got.Body, want)
			}
			if got.ContentType != contentTypeMarkdown || got.Inline {
				t.Errorf("Content-Type が %q、出し方の inline が %v。期待は %q と attachment", got.ContentType, got.Inline, contentTypeMarkdown)
			}
		})
	}
}

// TestExportIntegration_OtherUserIsNotFound は、無い経歴書に 404 と Java 版の文言で答え、ほかの利用者の経歴書に、
// 出力の前提を満たすときも満たさないときも、無い経歴書と同じ誤りを返すことを確かめる(要件3の受入基準3、要件4の受入基準1)。
func TestExportIntegration_OtherUserIsNotFound(t *testing.T) {
	loadExportFixtures(t)
	svc := exportService(&fakePDFRenderer{Body: []byte("%PDF")})
	ctx := t.Context()

	// 同じ経歴書を持ち主が求めると、出力できることと、出力の前提で断ることを先に確かめる。
	// ほかの利用者の答えが 404 になるのが、経歴書が出力の前提を満たさないためでないことを示すためである。
	if _, err := svc.ExportResume(ctx, exportUser1, exportReadyResumeID, ExportPDF); err != nil {
		t.Fatalf("持ち主が出力の前提を満たす経歴書を出力できない: %v", err)
	}
	_, err := svc.ExportResume(ctx, exportUser1, exportEmptyResumeID, ExportPDF)
	if e := authErrorOf(t, err); e.Status != 400 || !strings.HasPrefix(e.Message, MessageExportUnavailable+"\n- ") {
		t.Fatalf("持ち主の出力の前提を満たさない経歴書の誤りが %d %q", e.Status, e.Message)
	}

	missing, err := svc.ExportResume(ctx, exportUser1, exportMissingResumeID, ExportPDF)
	assertResumeNotFound(t, err)
	if e := authErrorOf(t, err); e.Status != 404 || e.Message != "対象の職務経歴書データが存在しません。" {
		t.Fatalf("無い経歴書の誤りが %d %q", e.Status, e.Message)
	}
	if missing.Body != nil {
		t.Fatalf("無い経歴書で本文を返した: %+v", missing)
	}

	for _, tc := range []struct{ name, resumeID string }{
		{name: "出力の前提を満たす", resumeID: exportReadyResumeID},
		{name: "出力の前提を満たさない", resumeID: exportEmptyResumeID},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for _, format := range []ExportFormat{ExportPDF, ExportMarkdown} {
				_, err := svc.ExportResume(ctx, exportUser2, tc.resumeID, format)
				assertResumeNotFound(t, err)
			}
			_, err := svc.ExportResumeWithSettings(ctx, exportUser2, tc.resumeID, []byte(strings.Replace(validExportPDFBody, `"attachment"`, `"inline"`, 1)))
			assertResumeNotFound(t, err)
		})
	}
}

// TestExportIntegration_RejectBodyFirst は、無い経歴書と、ほかの利用者の経歴書と、出力の前提を満たさない経歴書でも、
// 断る本文の要求に本文の誤りで答えることを確かめる(要件3の受入基準4)。
func TestExportIntegration_RejectBodyFirst(t *testing.T) {
	loadExportFixtures(t)
	svc := exportService(&fakePDFRenderer{Body: []byte("%PDF")})
	for _, body := range []string{
		`{"format":`,
		`{"format":"pdf","disposition":"inline"}`,
		exportPDFBody(t, `"title":16`, `"title":73`),
	} {
		_, wantErr := decodeExportBody([]byte(body))
		if wantErr == nil {
			t.Fatalf("本文 %s を断る条件で断らない", body)
		}
		for _, tc := range []struct {
			name     string
			userID   uuid.UUID
			resumeID string
		}{
			{name: "無い経歴書", userID: exportUser1, resumeID: exportMissingResumeID},
			{name: "ほかの利用者の経歴書", userID: exportUser2, resumeID: exportReadyResumeID},
			{name: "出力の前提を満たさない経歴書", userID: exportUser1, resumeID: exportEmptyResumeID},
		} {
			_, err := svc.ExportResumeWithSettings(t.Context(), tc.userID, tc.resumeID, []byte(body))
			if !reflect.DeepEqual(err, wantErr) {
				t.Errorf("%s に本文 %s を送った誤りが %#v。期待は本文の誤り %#v", tc.name, body, err, wantErr)
			}
		}
	}
}

// TestExportIntegration_DeletedUser は、退会してすでに居ない利用者の要求に、無い経歴書の 404 で答えることを確かめる(要件4の受入基準2)。
// 退会すると利用者の行と経歴書が消えるので、退会した利用者は、データベースに居ない利用者の ID で表す。
func TestExportIntegration_DeletedUser(t *testing.T) {
	loadExportFixtures(t)
	svc := exportService(&fakePDFRenderer{Body: []byte("%PDF")})
	deleted := uuid.New()
	for _, resumeID := range []string{exportMissingResumeID, exportReadyResumeID} {
		_, err := svc.ExportResume(t.Context(), deleted, resumeID, ExportPDF)
		assertResumeNotFound(t, err)
		_, err = svc.ExportResume(t.Context(), deleted, resumeID, ExportMarkdown)
		assertResumeNotFound(t, err)
		_, err = svc.ExportResumeWithSettings(t.Context(), deleted, resumeID, []byte(validExportPDFBody))
		assertResumeNotFound(t, err)
	}
}

// resumeSnapshot は、経歴書の行と、6つの欄の項目の行と、プロジェクトの技術スタックの行の、すべての列を1つの文字列にする。
func resumeSnapshot(t *testing.T, resumeID string) string {
	t.Helper()
	var s string
	if err := testPool.QueryRow(t.Context(), `
		SELECT jsonb_build_object(
			'resume', (SELECT to_jsonb(r) FROM resumes r WHERE r.id = $1::uuid),
			'careers', (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM careers c WHERE c.resume_id = $1::uuid),
			'projects', (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM projects p WHERE p.resume_id = $1::uuid),
			'techStacks', (SELECT jsonb_agg(to_jsonb(ts) ORDER BY ts.project_id) FROM project_tech_stacks ts
				JOIN projects p ON p.id = ts.project_id WHERE p.resume_id = $1::uuid),
			'certifications', (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM certifications c WHERE c.resume_id = $1::uuid),
			'portfolios', (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM portfolios p WHERE p.resume_id = $1::uuid),
			'snsPlatforms', (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM sns_platforms s WHERE s.resume_id = $1::uuid),
			'selfPromotions', (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM self_promotions s WHERE s.resume_id = $1::uuid)
		)::text`, resumeID).Scan(&s); err != nil {
		t.Fatalf("経歴書 %s の行を読めません: %v", resumeID, err)
	}
	return s
}

// assertSnapshotHasAllSections は、経歴書の行と、6つの欄の項目の行と、プロジェクトの技術スタックの行が、どれも1行以上あることを確かめる。
// どれかが無いと、その行を書き換える誤りを、書き込まないことのテストが見つけられないためである。
func assertSnapshotHasAllSections(t *testing.T, resumeID, snapshot string) {
	t.Helper()
	var sections map[string]json.RawMessage
	if err := json.Unmarshal([]byte(snapshot), &sections); err != nil {
		t.Fatalf("経歴書 %s の行を読めません: %v", resumeID, err)
	}
	for _, key := range []string{"resume", "careers", "projects", "techStacks", "certifications", "portfolios", "snsPlatforms", "selfPromotions"} {
		if v, ok := sections[key]; !ok || string(v) == "null" {
			t.Fatalf("経歴書 %s に %s の行が無い", resumeID, key)
		}
	}
}

// TestExportIntegration_NoWrite は、4種類の出力のあとに、経歴書の行と6つの欄の項目が変わっていないことを確かめる(要件6の受入基準1)。
func TestExportIntegration_NoWrite(t *testing.T) {
	loadExportFixtures(t)
	svc := exportService(&fakePDFRenderer{Body: []byte("%PDF")})
	ctx := t.Context()
	before := resumeSnapshot(t, exportFullResumeID)
	assertSnapshotHasAllSections(t, exportFullResumeID, before)
	markdownBody := strings.Replace(validExportPDFBody, `"pdf"`, `"markdown"`, 1)
	for name, export := range map[string]func() (Export, error){
		"設定を付けない PDF":      func() (Export, error) { return svc.ExportResume(ctx, exportUser1, exportFullResumeID, ExportPDF) },
		"設定を付けない Markdown": func() (Export, error) { return svc.ExportResume(ctx, exportUser1, exportFullResumeID, ExportMarkdown) },
		"設定を付けた PDF": func() (Export, error) {
			return svc.ExportResumeWithSettings(ctx, exportUser1, exportFullResumeID, []byte(validExportPDFBody))
		},
		"設定を付けた Markdown": func() (Export, error) {
			return svc.ExportResumeWithSettings(ctx, exportUser1, exportFullResumeID, []byte(markdownBody))
		},
	} {
		if _, err := export(); err != nil {
			t.Fatalf("%s を出力できません: %v", name, err)
		}
		if after := resumeSnapshot(t, exportFullResumeID); after != before {
			t.Fatalf("%s の出力のあとに経歴書の行が変わった。\n前: %s\n後: %s", name, before, after)
		}
	}
}

// TestExportIntegration_PDFReceivesHTML は、PDF を求めると、偽の部品に、設定の値を入れた HTML が渡り、
// 偽の部品が返したバイトが出力の本文になることを確かめる(要件2の受入基準1)。
func TestExportIntegration_PDFReceivesHTML(t *testing.T) {
	loadExportFixtures(t)
	ctx := t.Context()

	t.Run("設定を付けた出力", func(t *testing.T) {
		renderer := &fakePDFRenderer{Body: []byte("%PDF-設定を付けた出力")}
		body := `{"format":"pdf","disposition":"inline","pdfSettings":{"fontFamily":"NotoSerifJP",` +
			`"fontSizes":{"title":20.5,"date":9,"fullName":13,"sectionHeading":14.5},"tableHeaderColor":{"rgb":{"r":18,"g":52,"b":171}}}}`
		got, err := exportService(renderer).ExportResumeWithSettings(ctx, exportUser1, exportFullResumeID, []byte(body))
		if err != nil {
			t.Fatalf("PDF を出力できません: %v", err)
		}
		if renderer.Calls != 1 {
			t.Fatalf("偽の部品が %d 回呼ばれた。期待は1回", renderer.Calls)
		}
		for _, want := range []string{
			`font-family: "Noto Serif JP", sans-serif;`,
			"font-size: 20.5px;", "font-size: 9px;", "font-size: 13px;", "font-size: 14.5px;",
			"background-color: #1234ab;",
			"鈴木", "株式会社ひかく",
		} {
			if !strings.Contains(renderer.HTML, want) {
				t.Errorf("偽の部品に渡った HTML に %q が無い", want)
			}
		}
		if string(got.Body) != string(renderer.Body) || got.ContentType != contentTypePDF || got.FileName != "フォントを比べる経歴書.pdf" || !got.Inline {
			t.Errorf("出力の結果が %+v", got)
		}
	})

	t.Run("設定を付けない出力は既定の設定", func(t *testing.T) {
		renderer := &fakePDFRenderer{Body: []byte("%PDF-既定の設定")}
		got, err := exportService(renderer).ExportResume(ctx, exportUser1, exportFullResumeID, ExportPDF)
		if err != nil {
			t.Fatalf("PDF を出力できません: %v", err)
		}
		want, err := renderPDFHTML(buildExportModel(mustGetResume(t, exportUser1, exportFullResumeID)), defaultPDFSettings())
		if err != nil {
			t.Fatalf("既定の設定の HTML を作れません: %v", err)
		}
		if renderer.HTML != want {
			t.Errorf("偽の部品に渡った HTML が、既定の設定で作った HTML と違う")
		}
		if string(got.Body) != string(renderer.Body) || got.ContentType != contentTypePDF || got.FileName != "フォントを比べる経歴書.pdf" || got.Inline {
			t.Errorf("出力の結果が %+v", got)
		}
	})
}

// mustGetResume は、利用者の経歴書1件を、マスタと経歴書のまとまりの経歴書1件の取得で読む。
func mustGetResume(t *testing.T, userID uuid.UUID, resumeID string) Resume {
	t.Helper()
	r, err := New(Deps{Pool: testPool}).GetResume(t.Context(), userID, resumeID)
	if err != nil {
		t.Fatalf("経歴書 %s を読めません: %v", resumeID, err)
	}
	return r
}
