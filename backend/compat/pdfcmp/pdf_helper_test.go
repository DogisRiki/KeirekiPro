//go:build compat

package pdfcmp

import (
	"bytes"
	"fmt"
	"strings"
	"testing"
)

// testPage は、テストの PDF の1ページである。content は、ページの内容のストリームの命令である。
type testPage struct {
	content string
}

// text は、フォント /F1 の size の大きさで、(x, y) に s を書く命令を返す。
func text(size, x, y float64, s string) string {
	return fmt.Sprintf("BT /F1 %g Tf %g %g Td (%s) Tj ET\n", size, x, y, s)
}

// rect は、色 (r, g, b)(0〜255)で、(x, y) から幅 w、高さ h の四角を塗る命令を返す。
func rect(r, g, b int, x, y, w, h float64) string {
	return fmt.Sprintf("q %.6f %.6f %.6f rg %g %g %g %g re f Q\n",
		float64(r)/255, float64(g)/255, float64(b)/255, x, y, w, h)
}

// makePDF は、フォント baseFont(標準の Type1 のフォントの名前に、付け足しを付けてよい)を使う、A4 の PDF を作る。
func makePDF(t *testing.T, baseFont string, pages ...testPage) []byte {
	t.Helper()
	n := len(pages)
	// 1: カタログ、2: ページの束、3: フォント、4 から: ページと内容を交互に置く
	objs := make([]string, 0, 3+2*n)
	kids := make([]string, 0, n)
	for i := range pages {
		kids = append(kids, fmt.Sprintf("%d 0 R", 4+2*i))
	}
	objs = append(objs,
		"<< /Type /Catalog /Pages 2 0 R >>",
		fmt.Sprintf("<< /Type /Pages /Kids [%s] /Count %d >>", strings.Join(kids, " "), n),
		fmt.Sprintf("<< /Type /Font /Subtype /Type1 /BaseFont /%s /Encoding /WinAnsiEncoding >>", baseFont),
	)
	for i, p := range pages {
		objs = append(objs,
			fmt.Sprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents %d 0 R >>", 5+2*i),
			fmt.Sprintf("<< /Length %d >>\nstream\n%sendstream", len(p.content), p.content),
		)
	}
	var b bytes.Buffer
	b.WriteString("%PDF-1.4\n")
	offsets := make([]int, len(objs))
	for i, o := range objs {
		offsets[i] = b.Len()
		fmt.Fprintf(&b, "%d 0 obj\n%s\nendobj\n", i+1, o)
	}
	xref := b.Len()
	fmt.Fprintf(&b, "xref\n0 %d\n0000000000 65535 f \n", len(objs)+1)
	for _, off := range offsets {
		fmt.Fprintf(&b, "%010d 00000 n \n", off)
	}
	fmt.Fprintf(&b, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(objs)+1, xref)
	return b.Bytes()
}
