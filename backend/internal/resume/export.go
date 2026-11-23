package resume

import (
	"context"
	"errors"

	"github.com/google/uuid"
)

// ExportFormat は、出力の形式である。
type ExportFormat string

// 出力の形式。値は、設定を付けた出力の本文の format の値と同じである。
const (
	ExportPDF      ExportFormat = "pdf"
	ExportMarkdown ExportFormat = "markdown"
)

// 出力の結果の Content-Type。Java 版の答えの Content-Type と同じである。
const (
	contentTypePDF      = "application/pdf"
	contentTypeMarkdown = "text/markdown;charset=utf-8"
)

// PDFRenderer は、PDF の HTML から PDF を作る部品である。internal/platform/pdf の *Engine が満たす。
type PDFRenderer interface {
	Render(ctx context.Context, html string) ([]byte, error)
}

// Export は、出力の結果である。HTTP の受け口は、この値から答えのヘッダと本文を書く。
type Export struct {
	// Body は、PDF か Markdown のバイトである。
	Body []byte
	// ContentType は、答えの Content-Type である。
	ContentType string
	// FileName は、経歴書の名前から作った名前に、.pdf か .md を付けたファイル名である。
	FileName string
	// Inline は、設定を付けた出力で出し方が inline のとき真である。
	Inline bool
}

var (
	// errPDFRendererMissing は、Deps の PDF が nil のときに PDF を求められた、組み立ての誤りである。
	errPDFRendererMissing = errors.New("resume: PDF を作る部品が渡されていない")
	// errExportFormatUnknown は、知らない出力の形式を求められた、呼び出し方の誤りである。
	errExportFormatUnknown = errors.New("resume: 知らない出力の形式")
)

// ExportResume は、設定を付けずに経歴書を出力する。PDF は既定の設定で作り、出し方は attachment にする。
// 写す元は Java 版の ExportResumeUseCase である。
func (s *Service) ExportResume(ctx context.Context, userID uuid.UUID, resumeID string, format ExportFormat) (Export, error) {
	return s.export(ctx, userID, resumeID, format, func() (pdfSettings, error) { return defaultPDFSettings(), nil }, false)
}

// ExportResumeWithSettings は、本文の設定を付けて経歴書を出力する。body は読まずに受け取った本文のバイトの並びである。
// Java 版と同じく、経歴書を読む前に本文を断る条件で確かめ、断る本文には経歴書によらず本文の誤りで答える。
// 形式が markdown のときは、本文に PDF の設定があっても使わず、直さない。
func (s *Service) ExportResumeWithSettings(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (Export, error) {
	req, err := decodeExportBody(body)
	if err != nil {
		return Export{}, err
	}
	settings := func() (pdfSettings, error) { return normalizePDFSettings(*req.PDFSettings) }
	return s.export(ctx, userID, resumeID, ExportFormat(req.Format), settings, req.Disposition == "inline")
}

// export は、経歴書を読み、出力の前提を確かめてから、出力を作る。PDF の部品が無いときは、データベースを読む前に誤りを返す。
// 経歴書の ID が読めないとき、経歴書が無いとき、ほかの利用者の経歴書のときは、どれも 404 の誤りを返す。
func (s *Service) export(ctx context.Context, userID uuid.UUID, resumeID string, format ExportFormat,
	settings func() (pdfSettings, error), inline bool,
) (Export, error) {
	if format == ExportPDF && s.deps.PDF == nil {
		return Export{}, errPDFRendererMissing
	}
	id, ok := parseID(resumeID)
	if !ok {
		return Export{}, errResumeNotFound()
	}
	r, found, err := poolStore(s.deps.Pool).findResume(ctx, userID, id)
	if err != nil {
		return Export{}, err
	}
	if !found {
		return Export{}, errResumeNotFound()
	}
	if e := checkExportRule(&r, inline); e != nil {
		return Export{}, e
	}
	return s.buildExport(ctx, r, format, settings, inline)
}

// buildExport は、出力の前提を満たす経歴書から、形式ごとの本文と Content-Type とファイル名を作る。
// PDF の設定は、PDF を作るときだけ settings で求める。PDF の部品の誤りと時間切れは、そのまま返す。
func (s *Service) buildExport(ctx context.Context, r Resume, format ExportFormat,
	settings func() (pdfSettings, error), inline bool,
) (Export, error) {
	m := buildExportModel(r)
	name := sanitizeFileName(r.Name)
	switch format {
	case ExportMarkdown:
		body, err := renderMarkdown(m)
		if err != nil {
			return Export{}, err
		}
		return Export{Body: body, ContentType: contentTypeMarkdown, FileName: name + ".md", Inline: inline}, nil
	case ExportPDF:
		ps, err := settings()
		if err != nil {
			return Export{}, err
		}
		html, err := renderPDFHTML(m, ps)
		if err != nil {
			return Export{}, err
		}
		body, err := s.deps.PDF.Render(ctx, html)
		if err != nil {
			return Export{}, err
		}
		return Export{Body: body, ContentType: contentTypePDF, FileName: name + ".pdf", Inline: inline}, nil
	}
	return Export{}, errExportFormatUnknown
}
