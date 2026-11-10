//go:build compat

// Package pdfcmp は、Java 版と Go 版の PDF を、poppler-utils で読んで比べる。
// 画素の割合では比べない。文字の位置が 1〜2pt ずれただけで、ずれた文字の画素がすべて違うと数えられ、
// 見た目の違いと区別できないためである(research.md の「PDF の見た目(H1)」)。
package pdfcmp

import (
	"bytes"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"io/fs"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
)

// 許す違いの大きさ。design.md の「pdfcmp」の表のとおりにする。
const (
	// PositionTolerance は、語の箱の上下左右の端のずれとして許す大きさ(pt)である。
	PositionTolerance = 2.0
	// HeightTolerance は、語の箱の高さ(文字の大きさ)の違いとして許す大きさ(pt)である。
	HeightTolerance = 0.5
	// ColorTolerance は、表の色の R、G、B のそれぞれの違いとして許す大きさである。
	ColorTolerance = 2
)

// 違いの種類。報告に、この名前で書く。
const (
	KindPages    = "ページの数"
	KindPageSize = "ページの大きさ"
	KindFont     = "フォント"
	KindText     = "ページの文字"
	KindWordPos  = "語の位置"
	KindFontSize = "文字の大きさ"
	KindColor    = "表の色"
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

// doc は、1つの PDF を poppler-utils で読んだものである。ページごとの値は、ページの順に並べる。
type doc struct {
	sizes []string
	fonts []string
	texts []string
	words [][]word
	pages []image.Image
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
	if d.texts, err = readTexts(ctx, work); err != nil {
		return doc{}, err
	}
	if d.words, err = readWords(ctx, work); err != nil {
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
	sizeLine  = regexp.MustCompile(`(?m)^Page\s+\d+ size:\s+(.+?)\s*$`)
)

// readSizes は、pdfinfo で、ページごとの大きさを読む。ページの数は、返す値の数になる。
// 最後のページの番号に、どの PDF のページの数よりも大きい数を渡す。pdfinfo は、最後のページの番号をページの数に縮める。
func readSizes(ctx context.Context, work string) ([]string, error) {
	out, err := run(exec.CommandContext(ctx, "pdfinfo", "-f", "1", "-l", "1000000", pdfFile), work)
	if err != nil {
		return nil, err
	}
	m := pagesLine.FindSubmatch(out)
	if m == nil {
		return nil, errors.New("pdfinfo の出力にページの数がありません")
	}
	var sizes []string
	for _, s := range sizeLine.FindAllSubmatch(out, -1) {
		sizes = append(sizes, string(s[1]))
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

// readTexts は、pdftotext -layout で、ページごとの文字を読む。
func readTexts(ctx context.Context, work string) ([]string, error) {
	out, err := run(exec.CommandContext(ctx, "pdftotext", "-layout", "-enc", "UTF-8", pdfFile, "-"), work)
	if err != nil {
		return nil, err
	}
	pages := strings.Split(string(out), "\f")
	// pdftotext は、各ページの終わりに改ページの文字を書くので、最後の要素は空になる
	pages = pages[:len(pages)-1]
	texts := make([]string, len(pages))
	for i, p := range pages {
		texts[i] = normalizeText(p)
	}
	return texts, nil
}

var spaces = regexp.MustCompile(`[ \t]+`)

// normalizeText は、ページの文字を比べる形にする。
//   - Java 版の PDF から写すと「〜」(U+301C)が「～」(U+FF5E)になるので、「～」を「〜」に直す
//   - 行の中の空白の続きを1つの空白にし、行の前後の空白と空の行を除く。-layout は、文字の位置から空白と空の行の数を決めるので、
//     許す幅の中のずれでも数が変わるためである。位置の違いは、語の位置で比べる
func normalizeText(s string) string {
	s = strings.ReplaceAll(s, "～", "〜")
	var lines []string
	for line := range strings.SplitSeq(s, "\n") {
		line = strings.TrimSpace(spaces.ReplaceAllString(line, " "))
		if line != "" {
			lines = append(lines, line)
		}
	}
	return strings.Join(lines, "\n")
}

// readWords は、pdftotext -bbox-layout で、ページごとの語と、その箱を読む。
func readWords(ctx context.Context, work string) ([][]word, error) {
	out, err := run(exec.CommandContext(ctx, "pdftotext", "-bbox-layout", "-enc", "UTF-8", pdfFile, "-"), work)
	if err != nil {
		return nil, err
	}
	dec := xml.NewDecoder(bytes.NewReader(out))
	dec.Strict = false
	dec.AutoClose = xml.HTMLAutoClose
	dec.Entity = xml.HTMLEntity
	var pages [][]word
	for {
		tok, err := dec.Token()
		if errors.Is(err, io.EOF) {
			return pages, nil
		}
		if err != nil {
			return nil, fmt.Errorf("pdftotext -bbox-layout の出力を読めません: %w", err)
		}
		start, ok := tok.(xml.StartElement)
		if !ok {
			continue
		}
		switch start.Name.Local {
		case "page":
			pages = append(pages, nil)
		case "word":
			if len(pages) == 0 {
				return nil, errors.New("pdftotext -bbox-layout の出力で、ページの外に語があります")
			}
			w, err := decodeWord(dec, start)
			if err != nil {
				return nil, err
			}
			pages[len(pages)-1] = append(pages[len(pages)-1], w)
		}
	}
}

func decodeWord(dec *xml.Decoder, start xml.StartElement) (word, error) {
	var w word
	targets := map[string]*float64{"xMin": &w.xMin, "yMin": &w.yMin, "xMax": &w.xMax, "yMax": &w.yMax}
	for _, a := range start.Attr {
		p, ok := targets[a.Name.Local]
		if !ok {
			continue
		}
		v, err := strconv.ParseFloat(a.Value, 64)
		if err != nil {
			return word{}, fmt.Errorf("語の位置 %s=%q を読めません: %w", a.Name.Local, a.Value, err)
		}
		*p = v
		delete(targets, a.Name.Local)
	}
	if len(targets) > 0 {
		return word{}, errors.New("pdftotext -bbox-layout の語に、位置の属性が足りません")
	}
	var text string
	if err := dec.DecodeElement(&text, &start); err != nil {
		return word{}, fmt.Errorf("語の文字を読めません: %w", err)
	}
	w.text = strings.ReplaceAll(text, "～", "〜")
	return w, nil
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
	for i := range min(len(j.sizes), len(g.sizes)) {
		page := i + 1
		if j.sizes[i] != g.sizes[i] {
			add(KindPageSize, page, j.sizes[i], g.sizes[i])
		}
		if i < len(j.texts) && i < len(g.texts) && j.texts[i] != g.texts[i] {
			jl, gl := firstDifferentLine(j.texts[i], g.texts[i])
			add(KindText, page, jl, gl)
		} else if i < len(j.words) && i < len(g.words) {
			// 文字が違うページでは、語の組がずれるので、語の位置と大きさを比べない
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

// firstDifferentLine は、2つのページの文字のうち、最初に違う行を、行の番号を付けて返す。
func firstDifferentLine(j, g string) (string, string) {
	jl, gl := strings.Split(j, "\n"), strings.Split(g, "\n")
	for k := range max(len(jl), len(gl)) {
		a, b := lineAt(jl, k), lineAt(gl, k)
		if a != b {
			return fmt.Sprintf("行 %d: %s", k+1, a), fmt.Sprintf("行 %d: %s", k+1, b)
		}
	}
	return j, g
}

func lineAt(lines []string, k int) string {
	if k < len(lines) {
		return lines[k]
	}
	return "(行がありません)"
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
