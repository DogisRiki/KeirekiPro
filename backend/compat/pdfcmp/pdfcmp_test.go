//go:build compat

package pdfcmp

import (
	"context"
	"fmt"
	"slices"
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

// hasLineOnOtherPage は、Java 版の javaPage ページの行 s が、Go 版で goPage ページにある「行の位置」の違いがあるかを返す。
func hasLineOnOtherPage(r Result, javaPage int, s string, goPage int) bool {
	for _, d := range r.Diffs {
		if d.Kind == KindLinePos && d.Page == javaPage &&
			strings.Contains(d.Java, fmt.Sprintf("ページ %d の行「%s」", javaPage, s)) &&
			strings.Contains(d.Go, fmt.Sprintf("ページ %d の行「%s」", goPage, s)) {
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
	t.Run("語の箱の高さの 0.35pt 以内の違いを止めない", func(t *testing.T) {
		// 12pt の語の箱の高さは 15.6pt、12.25pt では 15.925pt で、違いは 0.325pt である
		java := makePDF(t, font, testPage{content: text(12, 72, 700, "I")})
		goPDF := makePDF(t, font, testPage{content: text(12.25, 72, 700, "I")})
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
		t.Run(name+"ずれた行を止める", func(t *testing.T) {
			r := compare(t, java, makePDF(t, font, shifted))
			if !hasDiff(r, KindLinePos, 1) {
				t.Errorf("1ページ目に行の位置の違いがあるはずですが、%+v", r.Diffs)
			}
		})
	}
	t.Run("語の箱の高さが 0.35pt を超えて違う語を止める", func(t *testing.T) {
		// 12pt の語の箱の高さは 15.6pt、12.3pt では 15.99pt で、違いは 0.39pt である。「I」は細いので、箱の端のずれは 2pt に収まる
		java := makePDF(t, font, testPage{content: text(12, 72, 700, "I")})
		goPDF := makePDF(t, font, testPage{content: text(12.3, 72, 700, "I")})
		r := compare(t, java, goPDF)
		if !hasDiff(r, KindFontSize, 1) || hasDiff(r, KindLinePos, 1) {
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
		if !strings.HasPrefix(javaDetail, "["+KindDocText+"] ") || !strings.Contains(javaDetail, "Hello World") ||
			!strings.HasPrefix(goDetail, "["+KindDocText+"] ") || !strings.Contains(goDetail, "Hello Worle") {
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
		// 折り返しのまとまりが無いので、組になった「Bravo」の行の頁の違いを違いとする
		if !hasLineOnOtherPage(r, 1, "Bravo", 2) {
			t.Errorf("1ページ目の「Bravo」の行が Go 版で2ページ目にある違いがあるはずですが、%+v", r.Diffs)
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

func TestCompare_PageSizeTolerance(t *testing.T) {
	java := makePDF(t, font, twoLines(72, 700))
	t.Run("幅と高さの 0.5pt 以内の違いを止めない", func(t *testing.T) {
		page := twoLines(72, 700)
		page.width, page.height = 595.3, 842.3
		if r := compare(t, java, makePDF(t, font, page)); !r.Same() {
			t.Errorf("違いが無いはずですが、%+v", r.Diffs)
		}
	})
	for name, size := range map[string][2]float64{"幅": {595.6, 842}, "高さ": {595, 841.4}} {
		t.Run(name+"が 0.6pt 違うページを止める", func(t *testing.T) {
			page := twoLines(72, 700)
			page.width, page.height = size[0], size[1]
			r := compare(t, java, makePDF(t, font, page))
			if !hasDiff(r, KindPageSize, 1) {
				t.Errorf("1ページ目にページの大きさの違いがあるはずですが、%+v", r.Diffs)
			}
		})
	}
}

func TestNormalizeText(t *testing.T) {
	for name, tc := range map[string]struct{ in, want string }{
		"互換漢字を統合漢字にする":       {"塚朗", "塚朗"},
		"U+2011 を - にする":     {"2020‑2021", "2020-2021"},
		"「～」(U+FF5E)を「〜」にする": {"2020～2021", "2020〜2021"},
		"空白と改行と全角の空白を除く":     {" 期間\t2020 \n〜　2021 ", "期間2020〜2021"},
		"結合の記号の組を1つの字にする":    {"é", "é"},
		"ほかの字はそのままにする":       {"Hello-World", "Hello-World"},
	} {
		if got := normalizeText(tc.in); got != tc.want {
			t.Errorf("%s: normalizeText(%q) = %q, want %q", name, tc.in, got, tc.want)
		}
	}
}

func TestCompare_RejectsMissingChar(t *testing.T) {
	java := makePDF(t, font, twoLines(72, 700))
	goPDF := makePDF(t, font, testPage{content: text(12, 72, 700, "Hello Wrld") + text(12, 72, 680, "Second line")})
	r := compare(t, java, goPDF)
	if !hasDiff(r, KindDocText, 0) {
		t.Errorf("文書の字の並びの違いがあるはずですが、%+v", r.Diffs)
	}
	// 1字抜けた行は、字の数も違う
	if !hasDiff(r, KindFontColor, 0) {
		t.Errorf("フォントと色ごとの字の数の違いがあるはずですが、%+v", r.Diffs)
	}
}

func TestCompare_RejectsFontColorCount(t *testing.T) {
	// 「Hello World」は10字、「Second」は6字である。2つの版で、黒と赤の字の数が入れ替わる
	java := makePDF(t, font, testPage{content: text(12, 72, 700, "Hello World") + coloredText(255, 0, 0, 12, 72, 680, "Second")})
	t.Run("色ごとの字の数が同じなら止めない", func(t *testing.T) {
		goPDF := makePDF(t, font, testPage{content: coloredText(255, 0, 0, 12, 72, 680, "Second") + text(12, 72, 700, "Hello World")})
		if r := compare(t, java, goPDF); !r.Same() {
			t.Errorf("違いが無いはずですが、%+v", r.Diffs)
		}
	})
	t.Run("色ごとの字の数が違えば止める", func(t *testing.T) {
		goPDF := makePDF(t, font, testPage{content: coloredText(255, 0, 0, 12, 72, 700, "Hello World") + text(12, 72, 680, "Second")})
		r := compare(t, java, goPDF)
		if !hasDiff(r, KindFontColor, 0) || hasDiff(r, KindDocText, 0) || hasDiff(r, KindFont, 0) {
			t.Errorf("フォントと色の違いだけがあるはずですが、%+v", r.Diffs)
		}
		var details []string
		for _, d := range r.Diffs {
			if d.Kind == KindFontColor {
				details = append(details, d.Java+" / "+d.Go)
			}
		}
		want := []string{"Helvetica #000000: 10字 / Helvetica #000000: 6字", "Helvetica #ff0000: 6字 / Helvetica #ff0000: 10字"}
		if !slices.Equal(details, want) {
			t.Errorf("フォントと色の違いの説明 = %q, want %q", details, want)
		}
	})
}

func TestCompare_TwoColumnOrder(t *testing.T) {
	// 左の列に Alpha と Bravo、右の列に Charlie を置く。Java 版は Charlie を Alpha より 0.5pt 上に、Go 版は 0.5pt 下に置く。
	// 上からの位置だけで並べると、Java 版は Charlie, Alpha, Bravo、Go 版は Alpha, Charlie, Bravo の順になる
	java := makePDF(t, font, testPage{content: text(12, 72, 700, "Alpha") + text(12, 72, 680, "Bravo") + text(12, 300, 700.5, "Charlie")})
	t.Run("列、頁、上からの位置の順につないで同じ字の並びなら止めない", func(t *testing.T) {
		goPDF := makePDF(t, font, testPage{content: text(12, 300, 699.5, "Charlie") + text(12, 72, 680, "Bravo") + text(12, 72, 700, "Alpha")})
		if r := compare(t, java, goPDF); !r.Same() {
			t.Errorf("違いが無いはずですが、%+v", r.Diffs)
		}
	})
	t.Run("列の中の順が違えば止める", func(t *testing.T) {
		goPDF := makePDF(t, font, testPage{content: text(12, 72, 700, "Bravo") + text(12, 72, 680, "Alpha") + text(12, 300, 700.5, "Charlie")})
		if r := compare(t, java, goPDF); !hasDiff(r, KindDocText, 0) {
			t.Errorf("文書の字の並びの違いがあるはずですが、%+v", r.Diffs)
		}
	})
	t.Run("どの列にも入らない Go 版の行を止める", func(t *testing.T) {
		goPDF := makePDF(t, font, testPage{content: text(12, 72, 700, "Alpha") + text(12, 72, 680, "Bravo") + text(12, 400, 700.5, "Charlie")})
		r := compare(t, java, goPDF)
		found := false
		for _, d := range r.Diffs {
			if d.Kind == KindDocText && strings.Contains(d.Go, "Charlie") && strings.Contains(d.Java, "列がありません") {
				found = true
			}
		}
		if !found {
			t.Errorf("どの列にも入らない行の違いがあるはずですが、%+v", r.Diffs)
		}
	})
}

// wrappedThree は、「Alpha Bravo」と「Charlie」の2行に折り返した段落と、20pt 空けた「After」の行を書くページを返す。
// 段落の行の間は 20pt である。
func wrappedThree() testPage {
	return testPage{content: text(12, 72, 700, "Alpha Bravo") + text(12, 72, 680, "Charlie") + text(12, 72, 640, "After")}
}

// unwrapped は、wrappedThree の段落を1行に書き、「After」の行を y に書くページを返す。
func unwrapped(afterY float64) testPage {
	return testPage{content: text(12, 72, 700, "Alpha Bravo Charlie") + text(12, 72, afterY, "After")}
}

func TestCompare_AllowsFewerWrappedLines(t *testing.T) {
	t.Run("同じ字の段落を Go 版で1行少なく折り返した PDF を止めない", func(t *testing.T) {
		// Go 版の「After」の行は、減った1行の分の 20pt だけ上がる
		java := makePDF(t, font, wrappedThree())
		if r := compare(t, java, makePDF(t, font, unwrapped(660))); !r.Same() {
			t.Errorf("違いが無いはずですが、%+v", r.Diffs)
		}
	})
	t.Run("折り返しで行が減り、次の頁の行が前の頁に上がった PDF を止めない", func(t *testing.T) {
		java := makePDF(t, font,
			testPage{content: text(12, 72, 700, "Alpha Bravo") + text(12, 72, 680, "Charlie")},
			testPage{content: text(12, 72, 700, "Delta")})
		goPDF := makePDF(t, font, testPage{content: text(12, 72, 700, "Alpha Bravo Charlie") + text(12, 72, 680, "Delta")})
		if r := compare(t, java, goPDF); !r.Same() {
			t.Errorf("違いが無いはずですが、%+v", r.Diffs)
		}
	})
}

func TestCompare_RejectsMoreWrappedLines(t *testing.T) {
	java := makePDF(t, font, unwrapped(680))
	goPDF := makePDF(t, font, testPage{content: text(12, 72, 700, "Alpha Bravo") + text(12, 72, 680, "Charlie") + text(12, 72, 660, "After")})
	r := compare(t, java, goPDF)
	if !hasDiff(r, KindWrap, 1) {
		t.Errorf("1ページ目に折り返しの違いがあるはずですが、%+v", r.Diffs)
	}
}

func TestCompare_RejectsOverShiftAfterWrap(t *testing.T) {
	java := makePDF(t, font, wrappedThree())
	for name, afterY := range map[string]float64{
		// 減った行の分の 20pt と、許す 2pt を足した 22pt より 1pt 大きく上がる
		"減った行の高さより大きく上がった行を止める": 663,
		// 下に向かっては、減った行の分のずれを許さない
		"下に 2pt を超えてずれた行を止める": 637,
	} {
		t.Run(name, func(t *testing.T) {
			r := compare(t, java, makePDF(t, font, unwrapped(afterY)))
			found := false
			for _, d := range r.Diffs {
				if d.Kind == KindLinePos && d.Page == 1 && strings.Contains(d.Java, "After") {
					found = true
				}
			}
			if !found {
				t.Errorf("1ページ目の「After」の行に行の位置の違いがあるはずですが、%+v", r.Diffs)
			}
		})
	}
}

func TestCompare_RejectsPageBreakDiffWithoutWrap(t *testing.T) {
	java := makePDF(t, font, testPage{content: text(12, 72, 700, "Alpha") + text(12, 72, 680, "Bravo") + text(12, 72, 660, "Charlie")})
	goPDF := makePDF(t, font,
		testPage{content: text(12, 72, 700, "Alpha") + text(12, 72, 680, "Bravo")},
		testPage{content: text(12, 72, 660, "Charlie")})
	r := compare(t, java, goPDF)
	if !hasDiff(r, KindPages, 0) {
		t.Errorf("ページの数の違いがあるはずですが、%+v", r.Diffs)
	}
	if !hasLineOnOtherPage(r, 1, "Charlie", 2) {
		t.Errorf("1ページ目の「Charlie」の行が Go 版で2ページ目にある違いがあるはずですが、%+v", r.Diffs)
	}
}

func TestCompare_RejectsColorSetDiff(t *testing.T) {
	gray, blue, red := rect(200, 200, 200, 300, 100, 50, 20), rect(0, 0, 255, 400, 100, 50, 20), rect(255, 0, 0, 300, 200, 50, 20)
	line := text(12, 72, 700, "One")
	t.Run("Go 版に無い色の箱を止める", func(t *testing.T) {
		r := compare(t, makePDF(t, font, testPage{content: line + gray + blue}), makePDF(t, font, testPage{content: line + gray}))
		if len(r.Diffs) != 1 || !hasDiff(r, KindColor, 1) || !strings.Contains(r.Diffs[0].Java, "#0000FF") ||
			!strings.Contains(r.Diffs[0].Go, "箱がありません") {
			t.Errorf("1ページ目に Go 版に青の箱が無い違いだけがあるはずですが、%+v", r.Diffs)
		}
	})
	t.Run("Java 版に無い色の箱を止める", func(t *testing.T) {
		r := compare(t, makePDF(t, font, testPage{content: line + gray}), makePDF(t, font, testPage{content: line + gray + red}))
		if len(r.Diffs) != 1 || !hasDiff(r, KindColor, 1) || !strings.Contains(r.Diffs[0].Java, "箱がありません") ||
			!strings.Contains(r.Diffs[0].Go, "#FF0000") {
			t.Errorf("1ページ目に Java 版に赤の箱が無い違いだけがあるはずですが、%+v", r.Diffs)
		}
	})
	t.Run("折り返しのまとまりが無ければ、色の集まりを頁ごとに比べる", func(t *testing.T) {
		two := text(12, 72, 700, "Two")
		java := makePDF(t, font, testPage{content: line + gray}, testPage{content: two + blue})
		goPDF := makePDF(t, font, testPage{content: line + blue}, testPage{content: two + gray})
		if r := compare(t, java, goPDF); !hasDiff(r, KindColor, 1) || !hasDiff(r, KindColor, 2) {
			t.Errorf("1ページ目と2ページ目に表の色の違いがあるはずですが、%+v", r.Diffs)
		}
	})
	t.Run("折り返しのまとまりがあれば、色の集まりを文書の全体で比べる", func(t *testing.T) {
		two := text(12, 72, 700, "Two")
		java := makePDF(t, font,
			testPage{content: text(12, 72, 700, "Alpha Bravo") + text(12, 72, 680, "Charlie") + gray},
			testPage{content: two + blue})
		goPDF := makePDF(t, font,
			testPage{content: text(12, 72, 700, "Alpha Bravo Charlie") + blue},
			testPage{content: two + gray})
		if r := compare(t, java, goPDF); !r.Same() {
			t.Errorf("違いが無いはずですが、%+v", r.Diffs)
		}
	})
}
