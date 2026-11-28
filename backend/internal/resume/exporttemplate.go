package resume

import (
	"bytes"
	_ "embed"
	"errors"
	htmltemplate "html/template"
	"io"
	"strings"
	"text/template"
)

// markdownTemplateText は、Markdown のひな形である。Java 版の templates/resume/markdown/default.md を写した。
// Java 版のひな形の字は、Thymeleaf の印を除いて、そのまま残す。Thymeleaf は、本文が改行で始まり改行で終わる繰り返しでは、
// 2回目からの繰り返しの先頭の改行を出さない。Go のひな形は、その繰り返しの先頭の改行を、1回目だけ出す。
//
//go:embed templates/resume.md.tmpl
var markdownTemplateText string

// exportTextEscaper は、利用者が書いた字を、Java 版の Thymeleaf と同じ形に書き換える。
var exportTextEscaper = strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;", "'", "&#39;")

// exportTemplateFuncs は、ひな形から呼ぶ関数である。
var exportTemplateFuncs = template.FuncMap{
	// esc は、字を書き換えて出す。
	"esc": exportTextEscaper.Replace,
	// join は、技術スタックの名前を、Java 版の #strings.listJoin と同じく「, 」でつなぎ、字を書き換えて出す。
	"join": func(v []string) string { return exportTextEscaper.Replace(strings.Join(v, ", ")) },
	// notBlank は、値があり、Java の Character.isWhitespace に当たらない字を含むかを返す。Thymeleaf の #strings.isEmpty の逆である。
	"notBlank": func(s *string) bool { return s != nil && notBlank(*s) },
	// deref は、値のある文字列の中身を返す。
	"deref": func(s *string) string { return *s },
}

// markdownTemplate は、起動のときに1度だけ読み込んだ Markdown のひな形である。読み込みに失敗すれば起動で止まる。
var markdownTemplate = template.Must(template.New("resume.md").Funcs(exportTemplateFuncs).Parse(markdownTemplateText))

// exportExecutor は、ひな形に値を入れて書く部品である。text/template と html/template のひな形が満たす。
type exportExecutor interface {
	Execute(w io.Writer, data any) error
}

// executeExportTemplate は、ひな形に値を入れた結果を返す。
func executeExportTemplate(t exportExecutor, data any) ([]byte, error) {
	var b bytes.Buffer
	if err := t.Execute(&b, data); err != nil {
		return nil, err
	}
	return b.Bytes(), nil
}

// renderMarkdown は、出力のモデルから Markdown を作る。
func renderMarkdown(m exportModel) ([]byte, error) {
	return executeExportTemplate(markdownTemplate, m)
}

// pdfHTMLTemplateText は、PDF の HTML のひな形である。Java 版の templates/resume/pdf/simple.html を写し、
// Chromium で Java 版と同じ見た目にするための CSS を足した。
//
//go:embed templates/resume.html.tmpl
var pdfHTMLTemplateText string

// pdfHTMLTemplateFuncs は、PDF のひな形から呼ぶ関数である。利用者が書いた字は html/template が書き換えるので、書き換える関数は持たない。
var pdfHTMLTemplateFuncs = htmltemplate.FuncMap{
	// notBlank は、値があり、Java の Character.isWhitespace に当たらない字を含むかを返す。Thymeleaf の #strings.isEmpty の逆である。
	"notBlank": func(s *string) bool { return s != nil && notBlank(*s) },
	// notBlankText は、notBlank の、値が必ずある文字列の版である。
	"notBlankText": notBlank,
	// deref は、値のある文字列の中身を返す。
	"deref": func(s *string) string { return *s },
}

// pdfHTMLTemplate は、起動のときに1度だけ読み込んだ PDF の HTML のひな形である。読み込みに失敗すれば起動で止まる。
var pdfHTMLTemplate = htmltemplate.Must(htmltemplate.New("resume.html").Funcs(pdfHTMLTemplateFuncs).Parse(pdfHTMLTemplateText))

// errPDFFontFamilyUnknown は、PDF の設定のフォントの名前が、ひな形に入れられる2つの名前のどちらでもないことを表す。
var errPDFFontFamilyUnknown = errors.New("resume: PDF のひな形に入れられないフォントの名前")

// pdfHTMLData は、PDF のひな形が読む値である。Java 版のひな形の export と pdfSettings に当たる。
type pdfHTMLData struct {
	Export exportModel
	PDF    pdfSettings
}

// renderPDFHTML は、出力のモデルと PDF の設定から、PDF にする HTML を作る。
// フォントの名前は、決まった2つの値のどちらかでなければ誤りにする。文字の大きさは数として、色は #rrggbb として CSS に入る。
func renderPDFHTML(m exportModel, s pdfSettings) (string, error) {
	if s.FontFamily != cssFontSansJP && s.FontFamily != cssFontSerifJP {
		return "", errPDFFontFamilyUnknown
	}
	b, err := executeExportTemplate(pdfHTMLTemplate, pdfHTMLData{Export: m, PDF: s})
	return string(b), err
}
