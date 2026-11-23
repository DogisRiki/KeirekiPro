package resume

import (
	"fmt"
	"math/big"
	"regexp"
	"strings"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// 次の3つは、PDF の設定の値を直せないときの文言である(ResumePdfExportSettings の IllegalArgumentException)。
// Java 版の ExportResumeUseCase は、この文言を業務の誤り(UseCaseException)にする。
const (
	MessagePDFFontFamilyUnknown  = "存在しないフォント種類です。"
	MessagePDFFontSizeInvalid    = "フォントサイズが不正です。"
	MessagePDFTableHeaderInvalid = "表ヘッダー色が不正です。"
)

// pdfSettings は、直したあとの PDF の設定の値である。PDF のひな形は、この値を CSS に入れる。
type pdfSettings struct {
	// FontFamily は、CSS のフォントの名前(Noto Sans JP か Noto Serif JP)である。
	FontFamily string
	// 次の4つは、タイトル、日付、氏名、見出しの文字の大きさである。値は整数か、整数に 0.5 を足した値である。
	TitleFontSize          float64
	DateFontSize           float64
	FullNameFontSize       float64
	SectionHeadingFontSize float64
	// TableHeaderColor は、表の見出しの色の小文字の #rrggbb である。
	TableHeaderColor string
}

// exportPDFSettingsInput は、設定を付けた出力の本文の、直す前の PDF の設定の値である。
// 本文に無い欄は nil にする。本文の読み手は、断る条件で確かめたあとに、この値を normalizePDFSettings に渡す。
type exportPDFSettingsInput struct {
	FontFamily       *string
	FontSizes        *exportFontSizesInput
	TableHeaderColor *exportColorInput
}

// exportFontSizesInput は、直す前の4つの文字の大きさである。Java 版の BigDecimal と同じく、10進数の値を誤差無しに持つ。
type exportFontSizesInput struct {
	Title          *big.Rat
	Date           *big.Rat
	FullName       *big.Rat
	SectionHeading *big.Rat
}

// exportColorInput は、直す前の表の見出しの色である。16進数の6桁(# を付けない)か、赤と緑と青の値の、どちらか一方を持つ。
type exportColorInput struct {
	Hex *string
	RGB *exportRGBInput
}

// exportRGBInput は、直す前の赤と緑と青の値である。
type exportRGBInput struct {
	Red   *int
	Green *int
	Blue  *int
}

var (
	minFontSize = big.NewRat(6, 1)
	maxFontSize = big.NewRat(72, 1)
	cssColor    = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)
)

// defaultPDFSettings は、設定を付けない出力の既定の設定を返す(ResumePdfExportSettings.defaults)。
func defaultPDFSettings() pdfSettings {
	return pdfSettings{
		FontFamily:             "Noto Sans JP",
		TitleFontSize:          16,
		DateFontSize:           10,
		FullNameFontSize:       10,
		SectionHeadingFontSize: 11.5,
		TableHeaderColor:       "#d9d9d9",
	}
}

// normalizePDFSettings は、直す前の設定の値を、Java 版の ResumePdfExportSettings.normalize と同じに直す。
// Java 版と同じく、フォント、タイトル、日付、氏名、見出し、色の順に確かめ、最初に直せない値の文言を業務の誤りで返す。
func normalizePDFSettings(in exportPDFSettingsInput) (pdfSettings, error) {
	var s pdfSettings
	var ok bool
	if s.FontFamily, ok = toCSSFontFamily(in.FontFamily); !ok {
		return pdfSettings{}, auth.ErrBusiness(MessagePDFFontFamilyUnknown)
	}
	var sizes exportFontSizesInput
	if in.FontSizes != nil {
		sizes = *in.FontSizes
	}
	for _, f := range []struct {
		in  *big.Rat
		out *float64
	}{
		{sizes.Title, &s.TitleFontSize},
		{sizes.Date, &s.DateFontSize},
		{sizes.FullName, &s.FullNameFontSize},
		{sizes.SectionHeading, &s.SectionHeadingFontSize},
	} {
		if *f.out, ok = normalizeFontSize(f.in); !ok {
			return pdfSettings{}, auth.ErrBusiness(MessagePDFFontSizeInvalid)
		}
	}
	color := toCSSColor(in.TableHeaderColor)
	if !cssColor.MatchString(color) {
		return pdfSettings{}, auth.ErrBusiness(MessagePDFTableHeaderInvalid)
	}
	s.TableHeaderColor = strings.ToLower(color)
	return s, nil
}

// toCSSFontFamily は、本文のフォントの値を CSS のフォントの名前にする。決まった2つの値のほかは、ok を false にする。
func toCSSFontFamily(font *string) (string, bool) {
	if font == nil {
		return "", false
	}
	switch *font {
	case "NotoSansJP":
		return "Noto Sans JP", true
	case "NotoSerifJP":
		return "Noto Serif JP", true
	}
	return "", false
}

// normalizeFontSize は、文字の大きさを、整数の部分と10分の1の位で丸める。10分の1の位が2以下なら整数の部分、
// 7以下なら整数の部分に 0.5 を足した値、それより大きければ整数の部分に1を足した値にする。
// 6より小さいか72より大きい値は、ok を false にする。
func normalizeFontSize(v *big.Rat) (float64, bool) {
	if v == nil || v.Cmp(minFontSize) < 0 || v.Cmp(maxFontSize) > 0 {
		return 0, false
	}
	// 6 以上の値なので、整数の割り算の切り捨てが、小数点以下の切り捨てになる
	floor := new(big.Int).Quo(v.Num(), v.Denom())
	frac := new(big.Rat).Sub(v, new(big.Rat).SetInt(floor))
	scaled := frac.Mul(frac, big.NewRat(10, 1))
	tenths := new(big.Int).Quo(scaled.Num(), scaled.Denom()).Int64()
	base := float64(floor.Int64())
	switch {
	case tenths <= 2:
		return base, true
	case tenths <= 7:
		return base + 0.5, true
	default:
		return base + 1, true
	}
}

// toCSSColor は、表の見出しの色を、Java 版の ExportResumeRequest.TableHeaderColorRequest.toCssColor と同じく、
// 16進数なら # を付け、赤と緑と青の値なら #rrggbb の形に書く。どちらも無ければ空の文字列を返す。
// Java 版は、ここでも16進数を小文字にするが、normalizePDFSettings があとで色の全体を小文字にするので、ここでは小文字にしない。
func toCSSColor(c *exportColorInput) string {
	switch {
	case c == nil:
		return ""
	case c.Hex != nil:
		return "#" + *c.Hex
	case c.RGB != nil && c.RGB.Red != nil && c.RGB.Green != nil && c.RGB.Blue != nil:
		return fmt.Sprintf("#%02x%02x%02x", *c.RGB.Red, *c.RGB.Green, *c.RGB.Blue)
	}
	return ""
}
