package resume

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// fakePDFRenderer は、PDFRenderer の偽の部品である。受け取った HTML を控え、決まったバイトか誤りを返す。
// 小タスク4.4 の結合テストもこの部品を使うので、このパッケージのテストに偽の部品をほかに作らない。
type fakePDFRenderer struct {
	// Body は、Render が返すバイトである。
	Body []byte
	// Err は、Render が返す誤りである。
	Err error
	// Calls は、Render が呼ばれた回数である。
	Calls int
	// HTML は、最後に Render に渡された HTML である。
	HTML string
}

// Render は、渡された HTML を控え、Body と Err を返す。
func (f *fakePDFRenderer) Render(_ context.Context, html string) ([]byte, error) {
	f.Calls++
	f.HTML = html
	return f.Body, f.Err
}

// authErrorOf は、err が *auth.Error であることを確かめて返す。
func authErrorOf(t *testing.T, err error) *auth.Error {
	t.Helper()
	var e *auth.Error
	if !errors.As(err, &e) {
		t.Fatalf("誤りが *auth.Error でない: %v", err)
	}
	return e
}

// TestExport_RejectBodyFirst は、設定を付けた出力が、経歴書を読む前に本文を断る条件で確かめ、
// 断る本文には経歴書によらず本文の誤りで答えることを確かめる(要件3の受入基準4)。
// 経歴書の ID は読めない値にする。ID を先に確かめれば 404 になるので、答えが本文の誤りなら本文を先に確かめている。
func TestExport_RejectBodyFirst(t *testing.T) {
	svc := New(Deps{PDF: &fakePDFRenderer{}})
	for _, tc := range []struct {
		name   string
		body   string
		fields []string
	}{
		{name: "読めない本文", body: `{"format":`},
		{name: "断る条件に当たる本文", body: `{"format":"word","disposition":"attachment"}`, fields: []string{"format"}},
		{name: "PDF の設定の無い PDF の本文", body: `{"format":"pdf","disposition":"inline"}`, fields: []string{"pdfSettingsRequired"}},
		{
			name:   "形式が markdown でも PDF の設定が断る条件に当たる本文",
			body:   strings.Replace(strings.Replace(validExportPDFBody, `"pdf"`, `"markdown"`, 1), `"b4c7e7"`, `"zzzzzz"`, 1),
			fields: []string{"pdfSettings.tableHeaderColor.hex"},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := svc.ExportResumeWithSettings(context.Background(), uuid.New(), "読めない ID", []byte(tc.body))
			e := authErrorOf(t, err)
			if e.Status != http.StatusBadRequest || e.Message != auth.MessageInvalidInput {
				t.Fatalf("答えが %d %q。期待は 400 %q", e.Status, e.Message, auth.MessageInvalidInput)
			}
			if len(e.Errors) != len(tc.fields) {
				t.Fatalf("項目ごとの文言が %v。期待は %v の項目だけ", e.Errors, tc.fields)
			}
			for _, f := range tc.fields {
				if len(e.Errors[f]) == 0 {
					t.Fatalf("項目ごとの文言 %v に %s が無い", e.Errors, f)
				}
			}
			if strings.Contains(e.Message, "\n- ") {
				t.Fatalf("本文の誤りに足りない項目の一覧が入っている: %q", e.Message)
			}
		})
	}

	t.Run("断らない本文は経歴書の ID を確かめる", func(t *testing.T) {
		_, err := svc.ExportResumeWithSettings(context.Background(), uuid.New(), "読めない ID", []byte(validExportPDFBody))
		e := authErrorOf(t, err)
		if e.Status != http.StatusNotFound || e.Message != MessageResumeNotFound {
			t.Fatalf("答えが %d %q。期待は 404 %q", e.Status, e.Message, MessageResumeNotFound)
		}
	})
}

// TestExport_ResultFields は、出力の結果が、PDF と Markdown の Content-Type とファイル名と出し方を持つことを確かめる(要件1の受入基準1)。
func TestExport_ResultFields(t *testing.T) {
	settings := func() (pdfSettings, error) {
		s := defaultPDFSettings()
		s.TableHeaderColor = "#b4c7e7"
		return s, nil
	}
	pdfBytes := []byte("%PDF-偽の部品")

	t.Run("PDF", func(t *testing.T) {
		for _, inline := range []bool{false, true} {
			renderer := &fakePDFRenderer{Body: pdfBytes}
			svc := New(Deps{PDF: renderer})
			r := exportReadyResume()
			r.Name = "2026年/職務経歴書"
			got, err := svc.buildExport(context.Background(), *r, ExportPDF, settings, inline)
			if err != nil {
				t.Fatalf("誤り: %v", err)
			}
			want := Export{Body: pdfBytes, ContentType: "application/pdf", FileName: "2026年_職務経歴書.pdf", Inline: inline}
			if string(got.Body) != string(want.Body) || got.ContentType != want.ContentType || got.FileName != want.FileName || got.Inline != want.Inline {
				t.Fatalf("結果が %+v。期待は %+v", got, want)
			}
			if renderer.Calls != 1 || !strings.Contains(renderer.HTML, "background-color: #b4c7e7;") || !strings.Contains(renderer.HTML, "山田") {
				t.Fatalf("PDF の部品に、設定と経歴書から作った HTML が1回渡されていない(%d 回): %q", renderer.Calls, renderer.HTML)
			}
		}
	})

	t.Run("Markdown", func(t *testing.T) {
		renderer := &fakePDFRenderer{Body: pdfBytes}
		svc := New(Deps{PDF: renderer})
		r := exportReadyResume()
		settingsCalled := false
		noSettings := func() (pdfSettings, error) {
			settingsCalled = true
			return pdfSettings{}, errors.New("Markdown で PDF の設定を直した")
		}
		got, err := svc.buildExport(context.Background(), *r, ExportMarkdown, noSettings, true)
		if err != nil {
			t.Fatalf("誤り: %v", err)
		}
		wantBody, err := renderMarkdown(buildExportModel(*r))
		if err != nil {
			t.Fatalf("Markdown を作れない: %v", err)
		}
		if string(got.Body) != string(wantBody) || got.ContentType != "text/markdown;charset=utf-8" || got.FileName != "職務経歴書.md" || !got.Inline {
			t.Fatalf("結果が %+v", got)
		}
		if settingsCalled || renderer.Calls != 0 {
			t.Fatalf("Markdown の出力で PDF の設定を直したか PDF を作った(設定 %v、PDF %d 回)", settingsCalled, renderer.Calls)
		}
	})

	t.Run("名前の無い経歴書", func(t *testing.T) {
		svc := New(Deps{PDF: &fakePDFRenderer{Body: pdfBytes}})
		r := exportReadyResume()
		r.Name = ""
		got, err := svc.buildExport(context.Background(), *r, ExportMarkdown, settings, false)
		if err != nil || got.FileName != "resume.md" {
			t.Fatalf("ファイル名が %q(誤り %v)。期待は resume.md", got.FileName, err)
		}
	})

	t.Run("作れないとき", func(t *testing.T) {
		renderErr := errors.New("時間切れ")
		settingsErr := auth.ErrBusiness(MessagePDFFontFamilyUnknown)
		for _, tc := range []struct {
			name     string
			format   ExportFormat
			settings func() (pdfSettings, error)
			want     error
		}{
			{name: "PDF の部品の誤り", format: ExportPDF, settings: settings, want: renderErr},
			{name: "設定の値を直せない", format: ExportPDF, settings: func() (pdfSettings, error) { return pdfSettings{}, settingsErr }, want: settingsErr},
			{name: "フォントが決まった2つのほか", format: ExportPDF, settings: func() (pdfSettings, error) { return pdfSettings{FontFamily: "Arial"}, nil }, want: errPDFFontFamilyUnknown},
			{name: "知らない形式", format: ExportFormat("word"), settings: settings, want: errExportFormatUnknown},
		} {
			t.Run(tc.name, func(t *testing.T) {
				svc := New(Deps{PDF: &fakePDFRenderer{Body: pdfBytes, Err: renderErr}})
				got, err := svc.buildExport(context.Background(), *exportReadyResume(), tc.format, tc.settings, false)
				if !errors.Is(err, tc.want) || got.Body != nil {
					t.Fatalf("結果が %+v、誤りが %v。期待は誤り %v", got, err, tc.want)
				}
			})
		}
	})
}

// TestExport_NilPDFRenderer は、PDF の部品が nil のときに PDF を求めると、組み立ての誤りになることを確かめる。
// Markdown は PDF の部品を使わないので、同じ要求で経歴書の ID の確かめに進む。
func TestExport_NilPDFRenderer(t *testing.T) {
	svc := New(Deps{})
	ctx := context.Background()

	if _, err := svc.ExportResume(ctx, uuid.New(), "読めない ID", ExportPDF); !errors.Is(err, errPDFRendererMissing) {
		t.Fatalf("設定を付けない PDF の誤りが %v。期待は %v", err, errPDFRendererMissing)
	}
	if _, err := svc.ExportResumeWithSettings(ctx, uuid.New(), "読めない ID", []byte(validExportPDFBody)); !errors.Is(err, errPDFRendererMissing) {
		t.Fatalf("設定を付けた PDF の誤りが %v。期待は %v", err, errPDFRendererMissing)
	}
	var e *auth.Error
	if _, err := svc.ExportResume(ctx, uuid.New(), "読めない ID", ExportMarkdown); !errors.As(err, &e) || e.Status != http.StatusNotFound {
		t.Fatalf("Markdown の誤りが %v。期待は 404", err)
	}
}
