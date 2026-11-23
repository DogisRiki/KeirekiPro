//go:build compat

// Package pdfcmp は、Java 版と Go 版の PDF を、poppler-utils で読んで比べる。
// 画素の割合では比べない。文字の位置が 1〜2pt ずれただけで、ずれた文字の画素がすべて違うと数えられ、
// 見た目の違いと区別できないためである(research.md の「PDF の見た目(H1)」)。
package pdfcmp

import (
	"bytes"
	"cmp"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"io/fs"
	"maps"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
)

// 許す違いの大きさ。design.md の「pdfcmp」の表のとおりにする。
const (
	// PositionTolerance は、語の箱の上下左右の端のずれとして許す大きさ(pt)である。
	PositionTolerance = 2.0
	// HeightTolerance は、語の箱の高さ(文字の大きさ)の違いとして許す大きさ(pt)である。
	HeightTolerance = 0.35
	// ColorTolerance は、表の色の R、G、B のそれぞれの違いとして許す大きさである。
	ColorTolerance = 2
	// PageSizeTolerance は、ページの幅と高さのそれぞれの違いとして許す大きさ(pt)である。
	PageSizeTolerance = 0.5
	// ColumnTolerance は、行の左の端を同じ列にまとめる幅(pt)である。
	ColumnTolerance = 2.0
)

// 違いの種類。報告に、この名前で書く。
const (
	KindPages     = "ページの数"
	KindPageSize  = "ページの大きさ"
	KindFont      = "フォント"
	KindDocText   = "文書の字の並び"
	KindFontColor = "フォントと色"
	KindWordPos   = "語の位置"
	KindFontSize  = "文字の大きさ"
	KindColor     = "表の色"
	// KindText は、ページごとの字の違いの種類である。部品は、ページごとの字を比べなくなったので、この種類の違いを作らない。
	// 改頁の位置の違いを確かめるテストが、この名前を使う。行の組で改頁の位置の違いを見つける比べ方にしたら消す。
	KindText = "ページの文字"
)

const (
	// epsilon は、poppler が小数で書いた位置を比べるときの、丸めの誤差の分である。
	epsilon = 1e-6
	// minBoxPixels は、表の色の箱として数える最小の画素の数である。1画素の幅の罫線を拾い、
	// 語の箱の外にはみ出した字形のかけらを拾わないための大きさである。
	minBoxPixels = 9
	// maxDetailDiffs は、Describe が説明に書く違いの数の上限である。ずれた PDF では語の違いが多くなるためである。
	maxDetailDiffs = 30
	// describeTimeout は、Describe が1組の PDF を比べるのに待つ長さである。
	describeTimeout = 2 * time.Minute
)

// Diff は、2つの PDF の1つの違いである。Page は 1 から数え、文書の全体の違いでは 0 にする。
type Diff struct {
	Kind string
	Page int
	Java string
	Go   string
}

// Result は、2つの PDF を比べた結果である。
type Result struct {
	Diffs []Diff
}

// Same は、許す幅を超える違いが無いかを返す。
func (r Result) Same() bool {
	return len(r.Diffs) == 0
}

// Describe は、2つの PDF を比べ、両方の版の違いの説明と、許す幅に収まるかを返す。
// 比べる検査の harness.PDFComparer の形に合わせてある。
func Describe(java, goPDF []byte) (javaDetail, goDetail string, same bool, err error) {
	ctx, cancel := context.WithTimeout(context.Background(), describeTimeout)
	defer cancel()
	r, err := Compare(ctx, java, goPDF)
	if err != nil {
		return "", "", false, err
	}
	if r.Same() {
		return "", "", true, nil
	}
	return r.detail(func(d Diff) string { return d.Java }), r.detail(func(d Diff) string { return d.Go }), false, nil
}

func (r Result) detail(value func(Diff) string) string {
	var b strings.Builder
	for i, d := range r.Diffs {
		if i == maxDetailDiffs {
			fmt.Fprintf(&b, "ほか %d 件の違い\n", len(r.Diffs)-maxDetailDiffs)
			break
		}
		if d.Page > 0 {
			fmt.Fprintf(&b, "[%s] ページ %d: %s\n", d.Kind, d.Page, value(d))
		} else {
			fmt.Fprintf(&b, "[%s] %s\n", d.Kind, value(d))
		}
	}
	return strings.TrimSuffix(b.String(), "\n")
}

// Compare は、Java 版の PDF java と Go 版の PDF goPDF を poppler-utils で読み、許す幅を超える違いを返す。
func Compare(ctx context.Context, java, goPDF []byte) (Result, error) {
	dir, err := os.MkdirTemp("", "pdfcmp-*")
	if err != nil {
		return Result{}, fmt.Errorf("pdfcmp: 作業のフォルダを作れません: %w", err)
	}
	defer func() { _ = os.RemoveAll(dir) }()
	jd, err := readDoc(ctx, dir, "java", java)
	if err != nil {
		return Result{}, fmt.Errorf("pdfcmp: Java 版の PDF を読めません: %w", err)
	}
	gd, err := readDoc(ctx, dir, "go", goPDF)
	if err != nil {
		return Result{}, fmt.Errorf("pdfcmp: Go 版の PDF を読めません: %w", err)
	}
	return compareDocs(jd, gd), nil
}

// word は、pdftotext -bbox-layout の1つの語である。位置の単位は pt で、ページの左上を原点にする。
type word struct {
	text                   string
	xMin, yMin, xMax, yMax float64
}

func (w word) describe() string {
	return fmt.Sprintf("「%s」 左 %.2f 上 %.2f 右 %.2f 下 %.2f", w.text, w.xMin, w.yMin, w.xMax, w.yMax)
}

// line は、pdftotext -bbox-layout の1つの行である。位置の単位は pt で、ページの左上を原点にする。
type line struct {
	// page は、行のあるページの番号で、1 から数える。
	page int
	// text は、行の語を空白でつないだ字である。norm は、text を normalizeText で直した字である。
	text, norm             string
	xMin, yMin, xMax, yMax float64
}

func (l line) describe() string {
	return fmt.Sprintf("ページ %d の行「%s」", l.page, l.text)
}

// pageSize は、pdfinfo が書いた1つのページの大きさである。raw は、pdfinfo が書いたままの字である。
type pageSize struct {
	width, height float64
	raw           string
}

// doc は、1つの PDF を poppler-utils で読んだものである。ページごとの値は、ページの順に並べる。
type doc struct {
	sizes []pageSize
	fonts []string
	// lines は、pdftotext -bbox-layout が書いた順の、文書の全体の行である。
	lines []line
	words [][]word
	// fontColors は、pdftohtml が写した字の、フォントの名前と色の組ごとの数である。
	fontColors map[string]int
	pages      []image.Image
}

// pdfFile は、版ごとの作業のフォルダに書く PDF の名前である。poppler-utils の道具は、版ごとの作業のフォルダで動かし、
// 引数をすべて決まった文字にする。外の道具に、変数の文字を引数として渡さないためである。
const pdfFile = "in.pdf"

// readDoc は、PDF を dir の下の版ごとの作業のフォルダ name に書き、poppler-utils で読む。
func readDoc(ctx context.Context, dir, name string, pdf []byte) (doc, error) {
	work := filepath.Join(dir, name)
	if err := os.Mkdir(work, 0o700); err != nil {
		return doc{}, fmt.Errorf("版ごとの作業のフォルダを作れません: %w", err)
	}
	if err := os.WriteFile(filepath.Join(work, pdfFile), pdf, 0o600); err != nil {
		return doc{}, fmt.Errorf("PDF を書けません: %w", err)
	}
	var d doc
	var err error
	if d.sizes, err = readSizes(ctx, work); err != nil {
		return doc{}, err
	}
	if d.fonts, err = readFonts(ctx, work); err != nil {
		return doc{}, err
	}
	if d.lines, d.words, err = readLayout(ctx, work); err != nil {
		return doc{}, err
	}
	if d.fontColors, err = readFontColors(ctx, work); err != nil {
		return doc{}, err
	}
	if d.pages, err = readImages(ctx, work); err != nil {
		return doc{}, err
	}
	return d, nil
}

// run は、poppler-utils の道具を、作業のフォルダ work で動かし、標準出力を返す。
func run(cmd *exec.Cmd, work string) ([]byte, error) {
	var stderr bytes.Buffer
	cmd.Dir = work
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("%s が失敗しました: %w: %s", filepath.Base(cmd.Path), err, strings.TrimSpace(stderr.String()))
	}
	return out, nil
}

var (
	pagesLine = regexp.MustCompile(`(?m)^Pages:\s+(\d+)\s*$`)
	sizeLine  = regexp.MustCompile(`(?m)^Page\s+\d+ size:\s+(([0-9.]+) x ([0-9.]+) pts.*?)\s*$`)
)

// readSizes は、pdfinfo で、ページごとの大きさを読む。ページの数は、返す値の数になる。
// 最後のページの番号に、どの PDF のページの数よりも大きい数を渡す。pdfinfo は、最後のページの番号をページの数に縮める。
func readSizes(ctx context.Context, work string) ([]pageSize, error) {
	out, err := run(exec.CommandContext(ctx, "pdfinfo", "-f", "1", "-l", "1000000", pdfFile), work)
	if err != nil {
		return nil, err
	}
	m := pagesLine.FindSubmatch(out)
	if m == nil {
		return nil, errors.New("pdfinfo の出力にページの数がありません")
	}
	var sizes []pageSize
	for _, s := range sizeLine.FindAllSubmatch(out, -1) {
		w, errW := strconv.ParseFloat(string(s[2]), 64)
		h, errH := strconv.ParseFloat(string(s[3]), 64)
		if err := errors.Join(errW, errH); err != nil {
			return nil, fmt.Errorf("pdfinfo のページの大きさ %q を読めません: %w", s[1], err)
		}
		sizes = append(sizes, pageSize{width: w, height: h, raw: string(s[1])})
	}
	if n, _ := strconv.Atoi(string(m[1])); len(sizes) != n {
		return nil, fmt.Errorf("pdfinfo の出力のページの大きさが %d 件で、ページの数 %d と合いません", len(sizes), n)
	}
	return sizes, nil
}

// subsetPrefix は、フォントを埋め込むときに名前の先頭に付ける6文字の付け足しである(例: ABCDEF+)。
var subsetPrefix = regexp.MustCompile(`^[A-Z]{6}\+`)

// readFonts は、pdffonts で、使っているフォントの名前を読む。名前の先頭の6文字の付け足しを除き、
// 重ならないように並べて返す。付け足しは、PDF を作るたびに変わり、見た目に関わらないためである。
func readFonts(ctx context.Context, work string) ([]string, error) {
	out, err := run(exec.CommandContext(ctx, "pdffonts", pdfFile), work)
	if err != nil {
		return nil, err
	}
	lines := strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	if len(lines) < 2 {
		return nil, errors.New("pdffonts の出力に見出しがありません")
	}
	var fonts []string
	for _, line := range lines[2:] {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		fonts = append(fonts, subsetPrefix.ReplaceAllString(fields[0], ""))
	}
	slices.Sort(fonts)
	return slices.Compact(fonts), nil
}

// normalizeText は、行の字を比べる形にする。
//   - Unicode の NFC で直す。Java 版の PDF から写した互換漢字を、Go 版と同じ統合漢字にするためである
//   - U+2011(改行しないハイフン)を「-」に直す。Java 版の PDF から写すと、「-」が U+2011 になるためである
//   - 「～」(U+FF5E)を「〜」(U+301C)に直す。Java 版の PDF から写すと、「〜」が「～」になるためである
//   - 空白を除く。2つの版で、語と行の区切りが違うためである
func normalizeText(s string) string {
	var b strings.Builder
	for _, r := range norm.NFC.String(s) {
		switch {
		case unicode.IsSpace(r):
			continue
		case r == '‑':
			r = '-'
		case r == '～':
			r = '〜'
		}
		b.WriteRune(r)
	}
	return b.String()
}

// readLayout は、pdftotext -bbox-layout で、文書の全体の行と、ページごとの語と、それぞれの箱を読む。
func readLayout(ctx context.Context, work string) ([]line, [][]word, error) {
	out, err := run(exec.CommandContext(ctx, "pdftotext", "-bbox-layout", "-enc", "UTF-8", pdfFile, "-"), work)
	if err != nil {
		return nil, nil, err
	}
	dec := xml.NewDecoder(bytes.NewReader(out))
	dec.Strict = false
	dec.AutoClose = xml.HTMLAutoClose
	dec.Entity = xml.HTMLEntity
	var (
		lines []line
		pages [][]word
		// cur は、読んでいる途中の行である。行の外では nil にする。
		cur   *line
		texts []string
	)
	for {
		tok, err := dec.Token()
		if errors.Is(err, io.EOF) {
			return lines, pages, nil
		}
		if err != nil {
			return nil, nil, fmt.Errorf("pdftotext -bbox-layout の出力を読めません: %w", err)
		}
		switch t := tok.(type) {
		case xml.StartElement:
			switch t.Name.Local {
			case "page":
				pages = append(pages, nil)
			case "line":
				if len(pages) == 0 {
					return nil, nil, errors.New("pdftotext -bbox-layout の出力で、ページの外に行があります")
				}
				l := line{page: len(pages)}
				if err := decodeBox(t, "行", &l.xMin, &l.yMin, &l.xMax, &l.yMax); err != nil {
					return nil, nil, err
				}
				cur, texts = &l, nil
			case "word":
				if cur == nil {
					return nil, nil, errors.New("pdftotext -bbox-layout の出力で、行の外に語があります")
				}
				w, err := decodeWord(dec, t)
				if err != nil {
					return nil, nil, err
				}
				pages[len(pages)-1] = append(pages[len(pages)-1], w)
				texts = append(texts, w.text)
			}
		case xml.EndElement:
			if t.Name.Local == "line" && cur != nil {
				cur.text = strings.Join(texts, " ")
				cur.norm = normalizeText(cur.text)
				lines = append(lines, *cur)
				cur = nil
			}
		}
	}
}

// decodeBox は、要素 start の xMin、yMin、xMax、yMax の属性を読む。what は、誤りに書く、要素の呼び名である。
func decodeBox(start xml.StartElement, what string, xMin, yMin, xMax, yMax *float64) error {
	targets := map[string]*float64{"xMin": xMin, "yMin": yMin, "xMax": xMax, "yMax": yMax}
	for _, a := range start.Attr {
		p, ok := targets[a.Name.Local]
		if !ok {
			continue
		}
		v, err := strconv.ParseFloat(a.Value, 64)
		if err != nil {
			return fmt.Errorf("%sの位置 %s=%q を読めません: %w", what, a.Name.Local, a.Value, err)
		}
		*p = v
		delete(targets, a.Name.Local)
	}
	if len(targets) > 0 {
		return fmt.Errorf("pdftotext -bbox-layout の%sに、位置の属性が足りません", what)
	}
	return nil
}

func decodeWord(dec *xml.Decoder, start xml.StartElement) (word, error) {
	var w word
	if err := decodeBox(start, "語", &w.xMin, &w.yMin, &w.xMax, &w.yMax); err != nil {
		return word{}, err
	}
	if err := dec.DecodeElement(&w.text, &start); err != nil {
		return word{}, fmt.Errorf("語の文字を読めません: %w", err)
	}
	return w, nil
}

// readFontColors は、pdftohtml -xml -fontfullname で、写した字を、フォントの名前と色の組ごとに数える。
// 空白は数えない。フォントの名前の先頭の6文字の付け足しを除く。pdftohtml は Go 版の一部の字を部首の字として写すので、
// 字そのものは比べる材料に使わず、数だけを使う。
func readFontColors(ctx context.Context, work string) (map[string]int, error) {
	out, err := run(exec.CommandContext(ctx, "pdftohtml", "-xml", "-stdout", "-i", "-q", "-fontfullname", pdfFile), work)
	if err != nil {
		return nil, err
	}
	dec := xml.NewDecoder(bytes.NewReader(out))
	dec.Strict = false
	dec.Entity = xml.HTMLEntity
	// pdftohtml は、フォントの番号を文書の全体で付け、番号を最初に使うページに fontspec を書く
	fonts := map[string]string{}
	counts := map[string]int{}
	for {
		tok, err := dec.Token()
		if errors.Is(err, io.EOF) {
			return counts, nil
		}
		if err != nil {
			return nil, fmt.Errorf("pdftohtml -xml の出力を読めません: %w", err)
		}
		start, ok := tok.(xml.StartElement)
		if !ok {
			continue
		}
		switch start.Name.Local {
		case "fontspec":
			fonts[attr(start, "id")] = subsetPrefix.ReplaceAllString(attr(start, "family"), "") + " " + attr(start, "color")
		case "text":
			key, ok := fonts[attr(start, "font")]
			if !ok {
				return nil, fmt.Errorf("pdftohtml -xml の出力の字が、書かれていないフォントの番号 %q を使います", attr(start, "font"))
			}
			n, err := countChars(dec)
			if err != nil {
				return nil, err
			}
			counts[key] += n
		}
	}
}

func attr(start xml.StartElement, name string) string {
	for _, a := range start.Attr {
		if a.Name.Local == name {
			return a.Value
		}
	}
	return ""
}

// countChars は、読み始めた要素の終わりまでの字のうち、空白でない字を数える。要素の中の b や i の要素の字も数える。
func countChars(dec *xml.Decoder) (int, error) {
	n := 0
	for depth := 1; depth > 0; {
		tok, err := dec.Token()
		if err != nil {
			return 0, fmt.Errorf("pdftohtml -xml の出力の字を読めません: %w", err)
		}
		switch t := tok.(type) {
		case xml.StartElement:
			depth++
		case xml.EndElement:
			depth--
		case xml.CharData:
			for _, r := range string(t) {
				if !unicode.IsSpace(r) {
					n++
				}
			}
		}
	}
	return n, nil
}

// readImages は、pdftoppm -r 72 で、ページごとの画像を作って読む。72dpi では、1画素が 1pt になる。
// 縁を滑らかにする処理は切る。縁の画素の色が位置のわずかなずれで変わり、表の色の箱を割ってしまうためである。
func readImages(ctx context.Context, work string) ([]image.Image, error) {
	if _, err := run(exec.CommandContext(ctx, "pdftoppm", "-r", "72", "-aa", "no", "-aaVector", "no", "-png", pdfFile, "page"), work); err != nil {
		return nil, err
	}
	root, err := os.OpenRoot(work)
	if err != nil {
		return nil, fmt.Errorf("作業のフォルダを開けません: %w", err)
	}
	defer func() { _ = root.Close() }()
	// pdftoppm は、ページの番号の桁をそろえて page-<番号>.png に書くので、名前の順がページの順になる
	files, err := fs.Glob(root.FS(), "page-*.png")
	if err != nil {
		return nil, fmt.Errorf("ページの画像を探せません: %w", err)
	}
	slices.Sort(files)
	images := make([]image.Image, 0, len(files))
	for _, f := range files {
		img, err := decodePNG(root, f)
		if err != nil {
			return nil, err
		}
		images = append(images, img)
	}
	return images, nil
}

func decodePNG(root *os.Root, file string) (image.Image, error) {
	f, err := root.Open(file)
	if err != nil {
		return nil, fmt.Errorf("ページの画像 %s を開けません: %w", file, err)
	}
	defer func() { _ = f.Close() }()
	img, err := png.Decode(f)
	if err != nil {
		return nil, fmt.Errorf("ページの画像 %s を読めません: %w", file, err)
	}
	return img, nil
}

func compareDocs(j, g doc) Result {
	var r Result
	add := func(kind string, page int, java, goVer string) {
		r.Diffs = append(r.Diffs, Diff{Kind: kind, Page: page, Java: java, Go: goVer})
	}
	if len(j.sizes) != len(g.sizes) {
		add(KindPages, 0, strconv.Itoa(len(j.sizes)), strconv.Itoa(len(g.sizes)))
	}
	if !slices.Equal(j.fonts, g.fonts) {
		add(KindFont, 0, strings.Join(j.fonts, ", "), strings.Join(g.fonts, ", "))
	}
	textDiffs, sameText := compareDocText(j.lines, g.lines)
	r.Diffs = append(r.Diffs, textDiffs...)
	r.Diffs = append(r.Diffs, compareFontColors(j.fontColors, g.fontColors)...)
	for i := range min(len(j.sizes), len(g.sizes)) {
		page := i + 1
		js, gs := j.sizes[i], g.sizes[i]
		if exceeds(js.width, gs.width, PageSizeTolerance) || exceeds(js.height, gs.height, PageSizeTolerance) {
			add(KindPageSize, page, js.raw, gs.raw)
		}
		// 字の並びが違う文書では、語の組がずれるので、語の位置と大きさを比べない
		if sameText && i < len(j.words) && i < len(g.words) {
			for _, d := range compareWords(j.words[i], g.words[i]) {
				add(d.Kind, page, d.Java, d.Go)
			}
		}
		if i < len(j.pages) && i < len(g.pages) {
			var jw, gw []word
			if i < len(j.words) {
				jw = j.words[i]
			}
			if i < len(g.words) {
				gw = g.words[i]
			}
			for _, d := range compareBoxes(findBoxes(j.pages[i], jw), findBoxes(g.pages[i], gw)) {
				add(KindColor, page, d.Java, d.Go)
			}
		}
	}
	return r
}

// column は、Java 版の行の左の端を ColumnTolerance 以内のものどうしでまとめた列である。lo と hi は、列の行の左の端の最小と最大である。
type column struct {
	lo, hi float64
}

// javaColumns は、Java 版の行の左の端を、隣との差が ColumnTolerance 以内のものどうしで列にまとめ、左から順に返す。
func javaColumns(lines []line) []column {
	xs := make([]float64, 0, len(lines))
	for _, l := range lines {
		xs = append(xs, l.xMin)
	}
	slices.Sort(xs)
	var cols []column
	for _, x := range xs {
		if n := len(cols); n > 0 && !exceeds(x, cols[n-1].hi, ColumnTolerance) {
			cols[n-1].hi = x
			continue
		}
		cols = append(cols, column{lo: x, hi: x})
	}
	return cols
}

// findColumn は、左の端 x の行に最も近い列の番号と、その列との差が ColumnTolerance 以内で、行が列に入るかを返す。
// 列が無ければ -1 を返す。
func findColumn(cols []column, x float64) (int, bool) {
	best, bestDist := -1, math.Inf(1)
	for k, c := range cols {
		d := 0.0
		if x < c.lo {
			d = c.lo - x
		} else if x > c.hi {
			d = x - c.hi
		}
		if d < bestDist {
			best, bestDist = k, d
		}
	}
	return best, best >= 0 && bestDist <= ColumnTolerance+epsilon
}

// textSeq は、列、ページ、上からの位置の順に並べた行の字をつないだものである。ends[k] は、lines[k] の字の終わりの位置である。
type textSeq struct {
	text  string
	lines []line
	ends  []int
}

// orderLines は、行を列、ページ、上からの位置の順に並べ、直した字をつなぐ。cols は、行ごとの列の番号である。
// 直した字が空の行は、つながない。
func orderLines(lines []line, cols []int) textSeq {
	idx := make([]int, 0, len(lines))
	for k := range lines {
		if lines[k].norm != "" {
			idx = append(idx, k)
		}
	}
	slices.SortStableFunc(idx, func(a, b int) int {
		la, lb := lines[a], lines[b]
		if c := cmp.Compare(cols[a], cols[b]); c != 0 {
			return c
		}
		if c := cmp.Compare(la.page, lb.page); c != 0 {
			return c
		}
		if c := cmp.Compare(la.yMin, lb.yMin); c != 0 {
			return c
		}
		return cmp.Compare(la.xMin, lb.xMin)
	})
	var s textSeq
	var b strings.Builder
	for _, k := range idx {
		b.WriteString(lines[k].norm)
		s.lines = append(s.lines, lines[k])
		s.ends = append(s.ends, b.Len())
	}
	s.text = b.String()
	return s
}

// lineAt は、つないだ字の位置 pos を含む行の説明を返す。pos が字の終わりなら、そのことを返す。
func (s textSeq) lineAt(pos int) string {
	k, _ := slices.BinarySearch(s.ends, pos+1)
	if k >= len(s.lines) {
		return "(字の並びの終わり)"
	}
	return s.lines[k].describe()
}

// compareDocText は、2つの版の文書の全体の行を、Java 版の行で決めた列、ページ、上からの位置の順につなぎ、字の並びを比べる。
// 列でまとめるのは、表の列の字が1行にまとまる順が2つの版で違うためである。どの列にも入らない Go 版の行は、1行ずつ違いにし、
// 字の並びの比べでは最も近い列に置く。字の並びが違えば、最初に違う字を含む行を、両方の版について書く。
// sameSeq は、つないだ字の並びが同じかを返す。
func compareDocText(j, g []line) (diffs []Diff, sameSeq bool) {
	cols := javaColumns(j)
	jc := make([]int, len(j))
	for k, l := range j {
		jc[k], _ = findColumn(cols, l.xMin)
	}
	gc := make([]int, len(g))
	for k, l := range g {
		var in bool
		if gc[k], in = findColumn(cols, l.xMin); !in {
			diffs = append(diffs, Diff{Kind: KindDocText, Java: "(入る列がありません)", Go: fmt.Sprintf("%s 左 %.2f", l.describe(), l.xMin)})
		}
	}
	js, gs := orderLines(j, jc), orderLines(g, gc)
	if js.text == gs.text {
		return diffs, true
	}
	pos := 0
	for pos < len(js.text) && pos < len(gs.text) && js.text[pos] == gs.text[pos] {
		pos++
	}
	// 2つの字の並びは pos の前まで同じなので、片方で字の途中なら、もう片方でも字の途中である。違う字の始まりまで戻す
	for pos > 0 && pos < len(js.text) && !utf8.RuneStart(js.text[pos]) {
		pos--
	}
	return append(diffs, Diff{Kind: KindDocText, Java: js.lineAt(pos), Go: gs.lineAt(pos)}), false
}

// compareFontColors は、フォントの名前と色の組ごとの字の数を比べ、数が違う組を、組の名前の順に1つずつ違いにする。
func compareFontColors(j, g map[string]int) []Diff {
	keys := slices.Sorted(maps.Keys(j))
	for k := range g {
		if _, ok := j[k]; !ok {
			keys = append(keys, k)
		}
	}
	slices.Sort(keys)
	var diffs []Diff
	for _, k := range keys {
		if j[k] != g[k] {
			diffs = append(diffs, Diff{Kind: KindFontColor, Java: fmt.Sprintf("%s: %d字", k, j[k]), Go: fmt.Sprintf("%s: %d字", k, g[k])})
		}
	}
	return diffs
}

// compareWords は、1つのページの語を、出てくる順で組にし、箱の端のずれと高さの違いを比べる。
func compareWords(j, g []word) []Diff {
	if len(j) != len(g) {
		return []Diff{{Kind: KindWordPos, Java: fmt.Sprintf("語の数 %d", len(j)), Go: fmt.Sprintf("語の数 %d", len(g))}}
	}
	var diffs []Diff
	for k := range j {
		a, b := j[k], g[k]
		if exceeds(a.xMin, b.xMin, PositionTolerance) || exceeds(a.yMin, b.yMin, PositionTolerance) ||
			exceeds(a.xMax, b.xMax, PositionTolerance) || exceeds(a.yMax, b.yMax, PositionTolerance) {
			diffs = append(diffs, Diff{Kind: KindWordPos, Java: a.describe(), Go: b.describe()})
		}
		if exceeds(a.yMax-a.yMin, b.yMax-b.yMin, HeightTolerance) {
			diffs = append(diffs, Diff{
				Kind: KindFontSize,
				Java: fmt.Sprintf("「%s」 高さ %.2f", a.text, a.yMax-a.yMin),
				Go:   fmt.Sprintf("「%s」 高さ %.2f", b.text, b.yMax-b.yMin),
			})
		}
	}
	return diffs
}

func exceeds(a, b, tolerance float64) bool {
	return math.Abs(a-b) > tolerance+epsilon
}

// box は、表の見出しや罫線の箱である。ページの画像で、白でない同じ色の画素がつながった広がりを1つの箱とする。
type box struct {
	color                  [3]uint8
	minX, minY, maxX, maxY int
}

func (b box) describe() string {
	return fmt.Sprintf("箱 (%d,%d)-(%d,%d) の色 #%02X%02X%02X", b.minX, b.minY, b.maxX, b.maxY, b.color[0], b.color[1], b.color[2])
}

func (b box) center() (float64, float64) {
	return float64(b.minX+b.maxX) / 2, float64(b.minY+b.maxY) / 2
}

// findBoxes は、ページの画像から、語の箱の画素を除き、白でない同じ色の画素が上下左右でつながった広がりを箱として集める。
// 箱の中の画素はすべて同じ色なので、箱の色は、その箱の画素の色の最頻値でもある。
func findBoxes(img image.Image, words []word) []box {
	bounds := img.Bounds()
	w, h := bounds.Dx(), bounds.Dy()
	masked := make([]bool, w*h)
	for _, wd := range words {
		// 語の箱を 1 画素広げて除く。字形の縁の画素が、箱の端の丸めで外に出るためである
		x0, y0 := max(int(math.Floor(wd.xMin))-1, 0), max(int(math.Floor(wd.yMin))-1, 0)
		x1, y1 := min(int(math.Ceil(wd.xMax))+1, w-1), min(int(math.Ceil(wd.yMax))+1, h-1)
		for y := y0; y <= y1; y++ {
			for x := x0; x <= x1; x++ {
				masked[y*w+x] = true
			}
		}
	}
	colors := make([][3]uint8, w*h)
	for y := range h {
		for x := range w {
			c, _ := color.NRGBAModel.Convert(img.At(bounds.Min.X+x, bounds.Min.Y+y)).(color.NRGBA)
			colors[y*w+x] = [3]uint8{c.R, c.G, c.B}
		}
	}
	white := [3]uint8{255, 255, 255}
	seen := make([]bool, w*h)
	var boxes []box
	var stack []int
	for start := range colors {
		if seen[start] || masked[start] || colors[start] == white {
			continue
		}
		c := colors[start]
		bx := box{color: c, minX: w, minY: h, maxX: -1, maxY: -1}
		count := 0
		seen[start] = true
		stack = append(stack[:0], start)
		for len(stack) > 0 {
			p := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			count++
			x, y := p%w, p/w
			bx.minX, bx.minY, bx.maxX, bx.maxY = min(bx.minX, x), min(bx.minY, y), max(bx.maxX, x), max(bx.maxY, y)
			for _, n := range [4]int{p - 1, p + 1, p - w, p + w} {
				if n < 0 || n >= w*h || (n == p-1 && x == 0) || (n == p+1 && x == w-1) {
					continue
				}
				if !seen[n] && !masked[n] && colors[n] == c {
					seen[n] = true
					stack = append(stack, n)
				}
			}
		}
		if count >= minBoxPixels {
			boxes = append(boxes, bx)
		}
	}
	return boxes
}

// compareBoxes は、Java 版の箱のそれぞれに、中心が最も近い Go 版の箱を組にし、色の R、G、B のそれぞれの違いを比べる。
// 組にならない箱は、片方の版にしか無い箱として違いにする。
func compareBoxes(j, g []box) []Diff {
	used := make([]bool, len(g))
	var diffs []Diff
	for _, a := range j {
		best, bestDist := -1, math.Inf(1)
		ax, ay := a.center()
		for k, b := range g {
			if used[k] {
				continue
			}
			bx, by := b.center()
			if d := (ax-bx)*(ax-bx) + (ay-by)*(ay-by); d < bestDist {
				best, bestDist = k, d
			}
		}
		if best < 0 {
			diffs = append(diffs, Diff{Kind: KindColor, Java: a.describe(), Go: "(箱がありません)"})
			continue
		}
		used[best] = true
		if !colorClose(a.color, g[best].color) {
			diffs = append(diffs, Diff{Kind: KindColor, Java: a.describe(), Go: g[best].describe()})
		}
	}
	for k, b := range g {
		if !used[k] {
			diffs = append(diffs, Diff{Kind: KindColor, Java: "(箱がありません)", Go: b.describe()})
		}
	}
	return diffs
}

func colorClose(a, b [3]uint8) bool {
	for i := range a {
		if d := int(a[i]) - int(b[i]); d > ColorTolerance || d < -ColorTolerance {
			return false
		}
	}
	return true
}
