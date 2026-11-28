package resume

import (
	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// 設定を付けた出力の本文を断るときの文言である。Java 版の ExportResumeRequest の注釈の文字列を写した。
const (
	MessageExportFormatRequired           = "エクスポート形式は入力必須です。"
	MessageExportFormatInvalid            = "エクスポート形式が不正です。"
	MessageExportDispositionRequired      = "出力方法は入力必須です。"
	MessageExportDispositionInvalid       = "出力方法が不正です。"
	MessageExportPDFSettingsRequired      = "PDF設定は入力必須です。"
	MessageExportFontFamilyRequired       = "フォント種類は入力必須です。"
	MessageExportFontFamilyInvalid        = "フォント種類が不正です。"
	MessageExportFontSizesRequired        = "フォントサイズは入力必須です。"
	MessageExportTableHeaderColorRequired = "表ヘッダー色は入力必須です。"
	MessageExportHexInvalid               = "カラーコードが不正です。"
	MessageExportTableHeaderColorInvalid  = "表ヘッダー色が不正です。"
)

// exportNumberField は、本文の数の欄の1つの、errors の鍵の最後の欄の名前と文言である。
type exportNumberField struct {
	path                         string
	required, tooSmall, tooLarge string
}

// exportFontSizeFields は、4つの文字の大きさの欄である。Java 版の FontSizesRequest の欄の順に並べる。
var exportFontSizeFields = [4]exportNumberField{
	{"title", "タイトルフォントサイズは入力必須です。", "タイトルフォントサイズは6以上で入力してください。", "タイトルフォントサイズは72以下で入力してください。"},
	{"date", "日付フォントサイズは入力必須です。", "日付フォントサイズは6以上で入力してください。", "日付フォントサイズは72以下で入力してください。"},
	{"fullName", "氏名フォントサイズは入力必須です。", "氏名フォントサイズは6以上で入力してください。", "氏名フォントサイズは72以下で入力してください。"},
	{"sectionHeading", "セクション見出しフォントサイズは入力必須です。", "セクション見出しフォントサイズは6以上で入力してください。", "セクション見出しフォントサイズは72以下で入力してください。"},
}

// exportRGBFields は、赤と緑と青の欄である。本文の鍵は r、g、b で(exportRGBInput)、errors の鍵の欄の名前は red、green、blue にする。
var exportRGBFields = [3]exportNumberField{
	{"red", "Rは入力必須です。", "Rは0以上で入力してください。", "Rは255以下で入力してください。"},
	{"green", "Gは入力必須です。", "Gは0以上で入力してください。", "Gは255以下で入力してください。"},
	{"blue", "Bは入力必須です。", "Bは0以上で入力してください。", "Bは255以下で入力してください。"},
}

// exportRequest は、断る条件で確かめた、設定を付けた出力の本文である。
type exportRequest struct {
	// Format は、形式の pdf か markdown である。
	Format string
	// Disposition は、出し方の inline か attachment である。
	Disposition string
	// PDFSettings は、直す前の PDF の設定である。本文に無ければ nil にする。
	PDFSettings *exportPDFSettingsInput
}

// exportBody は、読んだだけで、まだ断る条件で確かめていない本文である。本文に無い欄と null の欄は nil にする。
type exportBody struct {
	Format      *string                 `json:"format"`
	Disposition *string                 `json:"disposition"`
	PDFSettings *exportPDFSettingsInput `json:"pdfSettings"`
}

// decodeExportBody は、設定を付けた出力の本文を decodeBody で読み、Java 版の ExportResumeRequest の注釈と同じ断る条件で確かめる。
// 文字の大きさは float64、赤と緑と青は int で読むので、型の違う値と、float64 か int に入らない数は読めない。
// 本文が読めなければ errUnreadableInput を、断る条件に当たれば項目ごとの文言を持つ入力の誤りを返す。
// Java 版と違う読み方は、変えた動きの一覧の CB-102 から CB-108 に載せた。
func decodeExportBody(body []byte) (exportRequest, error) {
	b, err := decodeBody[exportBody](body)
	if err != nil {
		return exportRequest{}, errUnreadableInput()
	}
	if e := validateExportBody(b); e != nil {
		return exportRequest{}, e
	}
	return exportRequest{Format: *b.Format, Disposition: *b.Disposition, PDFSettings: b.PDFSettings}, nil
}

// validateExportBody は、読んだ本文を、Java 版の ExportResumeRequest の注釈の断る条件で確かめる。1つの欄に2つの文言が付くときは、
// 文言を注釈の順に並べる。断る条件に当たらなければ nil を返す。
func validateExportBody(b exportBody) *auth.Error {
	f := auth.FieldErrors{}
	checkExportChoice(f, "format", b.Format, MessageExportFormatRequired, MessageExportFormatInvalid, "pdf", "markdown")
	checkExportChoice(f, "disposition", b.Disposition, MessageExportDispositionRequired, MessageExportDispositionInvalid, "inline", "attachment")
	f.Check("pdfSettingsRequired", b.Format == nil || *b.Format != "pdf" || b.PDFSettings != nil, MessageExportPDFSettingsRequired)
	if s := b.PDFSettings; s != nil {
		checkExportChoice(f, "pdfSettings.fontFamily", s.FontFamily, MessageExportFontFamilyRequired, MessageExportFontFamilyInvalid, "NotoSansJP", "NotoSerifJP")
		f.Check("pdfSettings.fontSizes", s.FontSizes != nil, MessageExportFontSizesRequired)
		if s.FontSizes != nil {
			checkFontSizes(f, *s.FontSizes)
		}
		f.Check("pdfSettings.tableHeaderColor", s.TableHeaderColor != nil, MessageExportTableHeaderColorRequired)
		if c := s.TableHeaderColor; c != nil {
			checkTableHeaderColor(f, *c)
		}
	}
	return f.Result()
}

// checkExportChoice は、Java 版の @NotBlank と、選べる値を | でつないだ @Pattern を写す。
func checkExportChoice(f auth.FieldErrors, field string, s *string, required, invalid string, choices ...string) {
	f.Check(field, s != nil && auth.NotBlank(*s), required)
	f.Check(field, s == nil || containsString(choices, *s), invalid)
}

func containsString(list []string, s string) bool {
	for _, c := range list {
		if c == s {
			return true
		}
	}
	return false
}

// checkFontSizes は、4つの文字の大きさを、Java 版の @NotNull と、6.0 と 72.0 を含む @DecimalMin と @DecimalMax で確かめる。
func checkFontSizes(f auth.FieldErrors, s exportFontSizesInput) {
	for i, v := range [4]*float64{s.Title, s.Date, s.FullName, s.SectionHeading} {
		field := exportFontSizeFields[i]
		path := "pdfSettings.fontSizes." + field.path
		f.Check(path, v != nil, field.required)
		f.Check(path, v == nil || *v >= minFontSize, field.tooSmall)
		f.Check(path, v == nil || *v <= maxFontSize, field.tooLarge)
	}
}

// checkTableHeaderColor は、表の見出しの色を、Java 版の TableHeaderColorRequest の注釈で確かめる。
func checkTableHeaderColor(f auth.FieldErrors, c exportColorInput) {
	f.Check("pdfSettings.tableHeaderColor.hex", c.Hex == nil || isHexColor(*c.Hex), MessageExportHexInvalid)
	if c.RGB != nil {
		for i, v := range [3]*int{c.RGB.Red, c.RGB.Green, c.RGB.Blue} {
			field := exportRGBFields[i]
			path := "pdfSettings.tableHeaderColor.rgb." + field.path
			f.Check(path, v != nil, field.required)
			f.Check(path, v == nil || *v >= 0, field.tooSmall)
			f.Check(path, v == nil || *v <= 255, field.tooLarge)
		}
	}
	f.Check("pdfSettings.tableHeaderColor.specifiedOnce", (c.Hex != nil) != (c.RGB != nil), MessageExportTableHeaderColorInvalid)
}

// isHexColor は、Java 版の @Pattern(regexp = "^[0-9a-fA-F]{6}$") と同じく、s が16進数の6桁かを返す。
func isHexColor(s string) bool {
	if len(s) != 6 {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') && (c < 'A' || c > 'F') {
			return false
		}
	}
	return true
}
