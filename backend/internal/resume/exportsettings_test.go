package resume

import (
	"errors"
	"reflect"
	"strconv"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// settingsInput は、テストの PDF の設定の値を作る。フォントは NotoSansJP、色は16進数の d9d9d9 にし、タイトル、日付、氏名、見出しの文字の大きさに、10進数の字の title、date、fullName、sectionHeading を入れる。
func settingsInput(t *testing.T, title, date, fullName, sectionHeading string) exportPDFSettingsInput {
	t.Helper()
	font, hex := "NotoSansJP", "d9d9d9"
	return exportPDFSettingsInput{
		FontFamily: &font,
		FontSizes: &exportFontSizesInput{
			Title:          num(t, title),
			Date:           num(t, date),
			FullName:       num(t, fullName),
			SectionHeading: num(t, sectionHeading),
		},
		TableHeaderColor: &exportColorInput{Hex: &hex},
	}
}

// num は、10進数の字 s を float64 にする。
func num(t *testing.T, s string) *float64 {
	t.Helper()
	f, err := strconv.ParseFloat(s, 64)
	if err != nil {
		t.Fatalf("数にできない: %q", s)
	}
	return &f
}

// checkSettingsError は、直し方の誤り err が、文言 want の業務の 400 の誤りであることを確かめる。
func checkSettingsError(t *testing.T, name string, err error, want string) {
	t.Helper()
	var got *auth.Error
	if !errors.As(err, &got) {
		t.Errorf("%s: 誤りが %v、期待は %q の 400", name, err, want)
		return
	}
	if !reflect.DeepEqual(got, businessError(want)) {
		t.Errorf("%s: 誤りが %+v、期待は %q の 400", name, got, want)
	}
}

// TestExportSettings_Defaults は、設定を付けない出力の既定の設定が、Java 版の ResumePdfExportSettings.defaults() と
// 同じであることを確かめる(要件2の受入基準1)。
func TestExportSettings_Defaults(t *testing.T) {
	want := pdfSettings{
		FontFamily:             "Noto Sans JP",
		TitleFontSize:          16,
		DateFontSize:           10,
		FullNameFontSize:       10,
		SectionHeadingFontSize: 11.5,
		TableHeaderColor:       "#d9d9d9",
	}
	if got := defaultPDFSettings(); got != want {
		t.Errorf("既定の設定が %+v、期待は %+v", got, want)
	}
}

// TestExportSettings_RoundSizes は、4つの文字の大きさを、10分の1の位が2以下なら整数の部分、7以下なら 0.5 を足した値、
// それより大きければ1を足した値に丸め、6 と 72 を直せる値にし、その外の値を誤りにすることを確かめる(要件1の受入基準1)。
func TestExportSettings_RoundSizes(t *testing.T) {
	cases := []struct {
		name  string
		sizes [4]string
		want  [4]float64
		err   string
	}{
		{name: "x.2 と x.3 の境界", sizes: [4]string{"10.2", "10.3", "10.29", "10.31"}, want: [4]float64{10, 10.5, 10, 10.5}},
		{name: "x.7 と x.8 の境界", sizes: [4]string{"10.7", "10.8", "10.79", "10.81"}, want: [4]float64{10.5, 11, 10.5, 11}},
		{name: "0.5 刻みの値はそのまま", sizes: [4]string{"16", "10", "10", "11.5"}, want: [4]float64{16, 10, 10, 11.5}},
		{name: "6 と 72 は直せる", sizes: [4]string{"6", "72", "6.0", "72.0"}, want: [4]float64{6, 72, 6, 72}},
		{name: "71.9 は 72 に丸まる", sizes: [4]string{"71.9", "6.1", "6.3", "6.8"}, want: [4]float64{72, 6, 6.5, 7}},
		// 次の4つは、float64 では 7.2999…、70.7999…、6.2999…、6.7999… になり、小数の部分を10倍して切り捨てると位を誤る
		{name: "float64 で少し小さくなる値", sizes: [4]string{"7.3", "70.8", "6.3", "6.8"}, want: [4]float64{7.5, 71, 6.5, 7}},
		{name: "タイトルが6より小さい", sizes: [4]string{"5.99", "10", "10", "10"}, err: "フォントサイズが不正です。"},
		{name: "日付が72より大きい", sizes: [4]string{"10", "72.01", "10", "10"}, err: "フォントサイズが不正です。"},
		{name: "氏名が負の値", sizes: [4]string{"10", "10", "-10", "10"}, err: "フォントサイズが不正です。"},
		{name: "見出しが72より大きい", sizes: [4]string{"10", "10", "10", "1000"}, err: "フォントサイズが不正です。"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := normalizePDFSettings(settingsInput(t, c.sizes[0], c.sizes[1], c.sizes[2], c.sizes[3]))
			if c.err != "" {
				checkSettingsError(t, c.name, err, c.err)
				return
			}
			if err != nil {
				t.Fatalf("誤りが %v", err)
			}
			gotSizes := [4]float64{got.TitleFontSize, got.DateFontSize, got.FullNameFontSize, got.SectionHeadingFontSize}
			if gotSizes != c.want {
				t.Errorf("文字の大きさが %v、期待は %v", gotSizes, c.want)
			}
		})
	}
}

// TestExportSettings_FontFamily は、本文のフォントの値を CSS のフォントの名前にし、ほかの値を誤りにすることを確かめる(要件1の受入基準1)。
func TestExportSettings_FontFamily(t *testing.T) {
	cases := []struct {
		font, want, err string
	}{
		{font: "NotoSansJP", want: "Noto Sans JP"},
		{font: "NotoSerifJP", want: "Noto Serif JP"},
		{font: "Noto Sans JP", err: "存在しないフォント種類です。"},
		{font: "notosansjp", err: "存在しないフォント種類です。"},
	}
	for _, c := range cases {
		t.Run(c.font, func(t *testing.T) {
			in := settingsInput(t, "16", "10", "10", "11.5")
			in.FontFamily = &c.font
			got, err := normalizePDFSettings(in)
			if c.err != "" {
				checkSettingsError(t, c.font, err, c.err)
				return
			}
			if err != nil || got.FontFamily != c.want {
				t.Errorf("フォントが %q(誤り %v)、期待は %q", got.FontFamily, err, c.want)
			}
		})
	}
}

// TestExportSettings_NormalizeColor は、大文字の16進数と、赤と緑と青の値の色を、小文字の #rrggbb にし、
// その形にできない色を誤りにすることを確かめる(要件1の受入基準1)。
func TestExportSettings_NormalizeColor(t *testing.T) {
	hex := func(s string) *exportColorInput { return &exportColorInput{Hex: &s} }
	rgb := func(r, g, b int) *exportColorInput {
		return &exportColorInput{RGB: &exportRGBInput{Red: &r, Green: &g, Blue: &b}}
	}
	cases := []struct {
		name  string
		color *exportColorInput
		want  string
		err   string
	}{
		{name: "大文字の16進数", color: hex("D9D9D9"), want: "#d9d9d9"},
		{name: "大文字と小文字の混ざった16進数", color: hex("AbCdEf"), want: "#abcdef"},
		{name: "小文字の16進数", color: hex("0a0b0c"), want: "#0a0b0c"},
		{name: "赤と緑と青の値", color: rgb(217, 217, 217), want: "#d9d9d9"},
		{name: "1桁の値は0を補う", color: rgb(255, 15, 1), want: "#ff0f01"},
		{name: "黒", color: rgb(0, 0, 0), want: "#000000"},
		{name: "16進数が5桁", color: hex("12345"), err: "表ヘッダー色が不正です。"},
		{name: "16進数に # が付く", color: hex("#123456"), err: "表ヘッダー色が不正です。"},
		{name: "赤が255より大きい", color: rgb(256, 0, 0), err: "表ヘッダー色が不正です。"},
		{name: "緑が負の値", color: rgb(0, -1, 0), err: "表ヘッダー色が不正です。"},
		{name: "16進数も赤と緑と青の値も無い", color: &exportColorInput{}, err: "表ヘッダー色が不正です。"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			in := settingsInput(t, "16", "10", "10", "11.5")
			in.TableHeaderColor = c.color
			got, err := normalizePDFSettings(in)
			if c.err != "" {
				checkSettingsError(t, c.name, err, c.err)
				return
			}
			if err != nil || got.TableHeaderColor != c.want {
				t.Errorf("色が %q(誤り %v)、期待は %q", got.TableHeaderColor, err, c.want)
			}
		})
	}
}
