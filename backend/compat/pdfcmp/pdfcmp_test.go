//go:build compat

package pdfcmp

import (
	"context"
	"strings"
	"testing"
)

const font = "ABCDEF+Helvetica"

func compare(t *testing.T, java, goPDF []byte) Result {
	t.Helper()
	r, err := Compare(context.Background(), java, goPDF)
	if err != nil {
		t.Fatalf("比べられません: %v", err)
	}
	return r
}

func hasDiff(r Result, kind string, page int) bool {
	for _, d := range r.Diffs {
		if d.Kind == kind && d.Page == page {
			return true
		}
	}
	return false
}

// twoLines は、(x, y) から、2行の文字を書くページを返す。
func twoLines(x, y float64) testPage {
	return testPage{content: text(12, x, y, "Hello World") + text(12, x, y-20, "Second line")}
}

func TestCompare_Allows2ptShift(t *testing.T) {
	t.Run("語が上下左右に 2pt ずれても止めない", func(t *testing.T) {
		java := makePDF(t, font, twoLines(72, 700))
		for _, shifted := range []testPage{twoLines(74, 700), twoLines(70, 700), twoLines(72, 702), twoLines(72, 698), twoLines(74, 698)} {
			if r := compare(t, java, makePDF(t, font, shifted)); !r.Same() {
				t.Errorf("違いが無いはずですが、%+v", r.Diffs)
			}
		}
	})
	t.Run("語の箱の高さの 0.5pt 以内の違いを止めない", func(t *testing.T) {
		// 12pt の語の箱の高さは 15.6pt、12.3pt では 15.99pt で、違いは 0.39pt である
		java := makePDF(t, font, testPage{content: text(12, 72, 700, "I")})
		goPDF := makePDF(t, font, testPage{content: text(12.3, 72, 700, "I")})
		if r := compare(t, java, goPDF); !r.Same() {
			t.Errorf("違いが無いはずですが、%+v", r.Diffs)
		}
	})
}

func TestCompare_Rejects2_5ptShift(t *testing.T) {
	java := makePDF(t, font, twoLines(72, 700))
	for name, shifted := range map[string]testPage{
		"右に 2.5pt": twoLines(74.5, 700),
		"左に 2.5pt": twoLines(69.5, 700),
		"上に 2.5pt": twoLines(72, 702.5),
		"下に 2.5pt": twoLines(72, 697.5),
	} {
		t.Run(name+"ずれた語を止める", func(t *testing.T) {
			r := compare(t, java, makePDF(t, font, shifted))
			if !hasDiff(r, KindWordPos, 1) {
				t.Errorf("1ページ目に語の位置の違いがあるはずですが、%+v", r.Diffs)
			}
		})
	}
	t.Run("語の箱の高さが 0.5pt を超えて違う語を止める", func(t *testing.T) {
		// 12pt の語の箱の高さは 15.6pt、13pt では 16.9pt である。「I」は細いので、箱の端のずれは 2pt に収まる
		java := makePDF(t, font, testPage{content: text(12, 72, 700, "I")})
		goPDF := makePDF(t, font, testPage{content: text(13, 72, 700, "I")})
		r := compare(t, java, goPDF)
		if !hasDiff(r, KindFontSize, 1) || hasDiff(r, KindWordPos, 1) {
			t.Errorf("文字の大きさの違いだけがあるはずですが、%+v", r.Diffs)
		}
	})
}

func TestCompare_RejectsOneCharDiff(t *testing.T) {
	t.Run("1文字違うページを止める", func(t *testing.T) {
		java := makePDF(t, font, twoLines(72, 700))
		goPDF := makePDF(t, font, testPage{content: text(12, 72, 700, "Hello Worle") + text(12, 72, 680, "Second line")})
		javaDetail, goDetail, same, err := Describe(java, goPDF)
		if err != nil {
			t.Fatalf("比べられません: %v", err)
		}
		if same {
			t.Fatal("違いがあるはずですが、同じと読みました")
		}
		if javaDetail != "[ページの文字] ページ 1: 行 1: Hello World" || goDetail != "[ページの文字] ページ 1: 行 1: Hello Worle" {
			t.Errorf("違いの説明 = %q / %q", javaDetail, goDetail)
		}
	})
	t.Run("「～」と「〜」を同じ文字として読む", func(t *testing.T) {
		if normalizeText("期間 2020～2021") != normalizeText("期間 2020〜2021") {
			t.Error("「～」と「〜」を同じに読むはずですが、違うと読みました")
		}
		if normalizeText("期間 2020-2021") == normalizeText("期間 2020〜2021") {
			t.Error("「-」と「〜」を違うと読むはずですが、同じと読みました")
		}
	})
}

func TestCompare_RejectsPageBreakDiff(t *testing.T) {
	t.Run("同じページの数で、改頁の位置が違う PDF を止める", func(t *testing.T) {
		a, b, c := text(12, 72, 700, "Alpha"), text(12, 72, 680, "Bravo"), text(12, 72, 660, "Charlie")
		java := makePDF(t, font, testPage{content: a + b}, testPage{content: c})
		goPDF := makePDF(t, font, testPage{content: a}, testPage{content: b + c})
		r := compare(t, java, goPDF)
		if !hasDiff(r, KindText, 1) || !hasDiff(r, KindText, 2) {
			t.Errorf("1ページ目と2ページ目に文字の違いがあるはずですが、%+v", r.Diffs)
		}
	})
	t.Run("ページの数が違う PDF を止める", func(t *testing.T) {
		java := makePDF(t, font, twoLines(72, 700))
		goPDF := makePDF(t, font, twoLines(72, 700), testPage{content: text(12, 72, 700, "Next")})
		r := compare(t, java, goPDF)
		if !hasDiff(r, KindPages, 0) {
			t.Errorf("ページの数の違いがあるはずですが、%+v", r.Diffs)
		}
	})
}

func TestCompare_FontSubsetPrefixIgnored(t *testing.T) {
	t.Run("先頭の6文字の付け足しだけが違うフォントを同じと読む", func(t *testing.T) {
		java := makePDF(t, "ABCDEF+Helvetica", twoLines(72, 700))
		goPDF := makePDF(t, "GHIJKL+Helvetica", twoLines(72, 700))
		if r := compare(t, java, goPDF); !r.Same() {
			t.Errorf("違いが無いはずですが、%+v", r.Diffs)
		}
	})
	t.Run("名前が違うフォントを止める", func(t *testing.T) {
		java := makePDF(t, "ABCDEF+Helvetica", twoLines(72, 700))
		goPDF := makePDF(t, "ABCDEF+Helvetica-Bold", twoLines(72, 700))
		r := compare(t, java, goPDF)
		if !hasDiff(r, KindFont, 0) {
			t.Errorf("フォントの違いがあるはずですが、%+v", r.Diffs)
		}
	})
}

// header は、色 (r, g, b) の表の見出しの箱と、その中の文字を書くページを返す。文字は (72, ty) に書く。
func header(r, g, b int, ty float64) testPage {
	return testPage{content: rect(r, g, b, 60, 680, 200, 40) + text(12, 72, ty, "Period")}
}

func TestCompare_TableColorTolerance(t *testing.T) {
	java := makePDF(t, font, header(230, 230, 230, 695))
	t.Run("RGB のそれぞれが 2 以内の違いを止めない", func(t *testing.T) {
		// 箱の中の文字を 2pt ずらしても、文字の箱を除いて色を比べるので、箱の色の違いにならない
		goPDF := makePDF(t, font, header(232, 228, 232, 697))
		if r := compare(t, java, goPDF); !r.Same() {
			t.Errorf("違いが無いはずですが、%+v", r.Diffs)
		}
	})
	for name, rgb := range map[string][3]int{"R": {233, 230, 230}, "G": {230, 227, 230}, "B": {230, 230, 233}} {
		t.Run(name+" が 3 違う色を止める", func(t *testing.T) {
			r := compare(t, java, makePDF(t, font, header(rgb[0], rgb[1], rgb[2], 695)))
			if !hasDiff(r, KindColor, 1) {
				t.Errorf("1ページ目に表の色の違いがあるはずですが、%+v", r.Diffs)
			}
		})
	}
	t.Run("片方の版にしか無い箱を止める", func(t *testing.T) {
		goPDF := makePDF(t, font, testPage{content: text(12, 72, 695, "Period")})
		r := compare(t, java, goPDF)
		if !hasDiff(r, KindColor, 1) || !strings.Contains(r.Diffs[0].Go, "箱がありません") {
			t.Errorf("Go 版に箱が無い違いがあるはずですが、%+v", r.Diffs)
		}
	})
}
