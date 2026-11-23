package resume

import (
	"bytes"
	"encoding/json"
	"math"
	"math/big"
	"strconv"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/rangetable"

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

// exportNumberField は、本文の数の欄の1つである。key は本文の鍵、path は errors の鍵の最後の欄の名前である。
type exportNumberField struct {
	key, path                    string
	required, tooSmall, tooLarge string
}

// exportFontSizeFields は、4つの文字の大きさの欄である。Java 版の FontSizesRequest の欄の順に並べる。
var exportFontSizeFields = [4]exportNumberField{
	{"title", "title", "タイトルフォントサイズは入力必須です。", "タイトルフォントサイズは6以上で入力してください。", "タイトルフォントサイズは72以下で入力してください。"},
	{"date", "date", "日付フォントサイズは入力必須です。", "日付フォントサイズは6以上で入力してください。", "日付フォントサイズは72以下で入力してください。"},
	{"fullName", "fullName", "氏名フォントサイズは入力必須です。", "氏名フォントサイズは6以上で入力してください。", "氏名フォントサイズは72以下で入力してください。"},
	{"sectionHeading", "sectionHeading", "セクション見出しフォントサイズは入力必須です。", "セクション見出しフォントサイズは6以上で入力してください。", "セクション見出しフォントサイズは72以下で入力してください。"},
}

// exportRGBFields は、赤と緑と青の欄である。Java 版の RgbRequest は、本文の鍵を r、g、b にし、欄の名前を red、green、blue にする。
var exportRGBFields = [3]exportNumberField{
	{"r", "red", "Rは入力必須です。", "Rは0以上で入力してください。", "Rは255以下で入力してください。"},
	{"g", "green", "Gは入力必須です。", "Gは0以上で入力してください。", "Gは255以下で入力してください。"},
	{"b", "blue", "Bは入力必須です。", "Bは0以上で入力してください。", "Bは255以下で入力してください。"},
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

// exportBody は、読んだだけで、まだ断る条件で確かめていない本文である。本文に無い欄は nil にする。
type exportBody struct {
	format, disposition *string
	pdfSettings         *exportPDFSettingsInput
}

// decodeExportBody は、設定を付けた出力の本文を読み、Java 版の ExportResumeRequest の注釈と同じ断る条件で確かめる。
// 本文が読めなければ errUnreadableInput を、断る条件に当たれば項目ごとの文言を持つ入力の誤りを返す。
func decodeExportBody(body []byte) (exportRequest, error) {
	b, ok := readExportBody(body)
	if !ok {
		return exportRequest{}, errUnreadableInput()
	}
	if e := validateExportBody(b); e != nil {
		return exportRequest{}, e
	}
	return exportRequest{Format: *b.format, Disposition: *b.disposition, PDFSettings: b.pdfSettings}, nil
}

// maxNumberLength は、Java 版の Jackson が読む数の長さの上限である。Jackson の StreamReadConstraints の既定の値である。
// Jackson は、本文の中の数の字のうち数字の数が上限を超えれば、どの鍵の値でも本文を読まない。数の欄の文字列は、
// 前後の空白を除いた長さが上限を超えれば読まない。
const maxNumberLength = 1000

// readExportBody は、本文を Java 版の Jackson と同じに読む。最初の値だけを読み、あとに続く字を読まない。
// 読めない値が1つでもあれば、偽を返す。
func readExportBody(body []byte) (exportBody, bool) {
	var raw json.RawMessage
	if json.NewDecoder(bytes.NewReader(body)).Decode(&raw) != nil || !numbersWithinLimit(raw) {
		return exportBody{}, false
	}
	var b exportBody
	ok := readObject(raw, func(key string, v json.RawMessage) bool {
		var ok bool
		switch key {
		case "format":
			b.format, ok = readJavaString(v)
		case "disposition":
			b.disposition, ok = readJavaString(v)
		case "pdfSettings":
			b.pdfSettings, ok = readPDFSettings(v)
		default:
			ok = true
		}
		return ok
	})
	return b, ok
}

// readPDFSettings は、PDF の設定の欄を読む。null なら nil を返す。
func readPDFSettings(v json.RawMessage) (*exportPDFSettingsInput, bool) {
	if isJSONNull(v) {
		return nil, true
	}
	var s exportPDFSettingsInput
	ok := readObject(v, func(key string, v json.RawMessage) bool {
		var ok bool
		switch key {
		case "fontFamily":
			s.FontFamily, ok = readJavaString(v)
		case "fontSizes":
			s.FontSizes, ok = readFontSizes(v)
		case "tableHeaderColor":
			s.TableHeaderColor, ok = readTableHeaderColor(v)
		default:
			ok = true
		}
		return ok
	})
	return &s, ok
}

// readFontSizes は、4つの文字の大きさの欄を読む。null なら nil を返す。
func readFontSizes(v json.RawMessage) (*exportFontSizesInput, bool) {
	if isJSONNull(v) {
		return nil, true
	}
	var s exportFontSizesInput
	fields := map[string]**big.Rat{"title": &s.Title, "date": &s.Date, "fullName": &s.FullName, "sectionHeading": &s.SectionHeading}
	ok := readObject(v, func(key string, v json.RawMessage) bool {
		out, known := fields[key]
		if !known {
			return true
		}
		var ok bool
		*out, ok = readJavaDecimal(v)
		return ok
	})
	return &s, ok
}

// readTableHeaderColor は、表の見出しの色の欄を読む。null なら nil を返す。
func readTableHeaderColor(v json.RawMessage) (*exportColorInput, bool) {
	if isJSONNull(v) {
		return nil, true
	}
	var c exportColorInput
	ok := readObject(v, func(key string, v json.RawMessage) bool {
		var ok bool
		switch key {
		case "hex":
			c.Hex, ok = readJavaString(v)
		case "rgb":
			c.RGB, ok = readRGB(v)
		default:
			ok = true
		}
		return ok
	})
	return &c, ok
}

// readRGB は、赤と緑と青の欄を読む。null なら nil を返す。
func readRGB(v json.RawMessage) (*exportRGBInput, bool) {
	if isJSONNull(v) {
		return nil, true
	}
	var c exportRGBInput
	fields := map[string]**int{"r": &c.Red, "g": &c.Green, "b": &c.Blue}
	ok := readObject(v, func(key string, v json.RawMessage) bool {
		out, known := fields[key]
		if !known {
			return true
		}
		var ok bool
		*out, ok = readJavaInt(v)
		return ok
	})
	return &c, ok
}

// readObject は、v が JSON のオブジェクトなら、鍵と値を本文の順に field に渡し、field がすべて真を返せば真を返す。
// Jackson と同じく、同じ鍵が2つあれば、どちらの値も読み、あとの値を残す。v がオブジェクトでなければ偽を返す。
// v は読めた JSON の値なので、鍵と値の読み取りは失敗しない。
func readObject(v json.RawMessage, field func(key string, value json.RawMessage) bool) bool {
	dec := json.NewDecoder(bytes.NewReader(v))
	if tok, _ := dec.Token(); tok != json.Delim('{') {
		return false
	}
	for dec.More() {
		tok, _ := dec.Token()
		key, _ := tok.(string)
		var value json.RawMessage
		_ = dec.Decode(&value)
		if !field(key, value) {
			return false
		}
	}
	return true
}

// numbersWithinLimit は、v の中のどの数も、数字の数が maxNumberLength を超えないかを返す。Jackson は、指数の数字も数える。
func numbersWithinLimit(v json.RawMessage) bool {
	dec := json.NewDecoder(bytes.NewReader(v))
	dec.UseNumber()
	for {
		tok, err := dec.Token()
		if err != nil {
			return true
		}
		if n, ok := tok.(json.Number); ok && countASCIIDigits(string(n)) > maxNumberLength {
			return false
		}
	}
}

// countASCIIDigits は、s の中の 0 から 9 の字の数を返す。
func countASCIIDigits(s string) int {
	n := 0
	for i := 0; i < len(s); i++ {
		if isASCIIDigit(s[i]) {
			n++
		}
	}
	return n
}

func isASCIIDigit(c byte) bool { return c >= '0' && c <= '9' }

// isJSONNull は、v が JSON の null かを返す。
func isJSONNull(v json.RawMessage) bool {
	return string(v) == "null"
}

// readJavaString は、Jackson が Java の String の欄を読むのと同じに読む。文字列はそのまま、数と真偽は JSON に書かれた字のまま
// 文字列にし、null は nil にする。並びとオブジェクトは読めない値とする。
func readJavaString(v json.RawMessage) (*string, bool) {
	switch v[0] {
	case 'n':
		return nil, true
	case '[', '{':
		return nil, false
	case '"':
		var s string
		_ = json.Unmarshal(v, &s)
		return &s, true
	}
	s := string(v)
	return &s, true
}

// readNumberText は、Jackson が数の欄を読むときの、値の字を返す。null と、前後の空白を除いて空か "null" になる文字列は、
// 値が無いとして nil を返す。文字列は、前後の空白を除いた字を返し、isString を真にする。真偽と並びとオブジェクトと、
// 前後の空白を除いた長さが maxNumberLength を超える文字列は、読めない値とする。
func readNumberText(v json.RawMessage) (text *string, isString, ok bool) {
	switch v[0] {
	case 'n':
		return nil, false, true
	case '"':
		var s string
		_ = json.Unmarshal(v, &s)
		s = strings.TrimFunc(s, func(r rune) bool { return r <= ' ' })
		if s == "" || s == "null" {
			return nil, true, true
		}
		return &s, true, len(s) <= maxNumberLength
	case 't', 'f', '[', '{':
		return nil, false, false
	}
	s := string(v)
	return &s, false, true
}

// readJavaDecimal は、Jackson が Java の BigDecimal の欄を読むのと同じに読む。
func readJavaDecimal(v json.RawMessage) (*big.Rat, bool) {
	text, _, ok := readNumberText(v)
	if !ok || text == nil {
		return nil, ok
	}
	return parseJavaDecimal(*text)
}

// parseJavaDecimal は、Jackson が BigDecimal として読む10進数の字を読む。符号と、ASCII の数字と小数点と、指数を読む。
// 小数点のあとに数字の無い書き方に指数を付けた字と、Java の int に入らない指数と位取りは、読めない値とする。
func parseJavaDecimal(s string) (*big.Rat, bool) {
	i := 0
	neg := false
	if i < len(s) && (s[i] == '+' || s[i] == '-') {
		neg = s[i] == '-'
		i++
	}
	start := i
	for i < len(s) && isASCIIDigit(s[i]) {
		i++
	}
	intPart := s[start:i]
	dot := i < len(s) && s[i] == '.'
	var frac string
	if dot {
		i++
		start = i
		for i < len(s) && isASCIIDigit(s[i]) {
			i++
		}
		frac = s[start:i]
	}
	if intPart == "" && frac == "" {
		return nil, false
	}
	var exp int64
	if i < len(s) && (s[i] == 'e' || s[i] == 'E') {
		if dot && frac == "" {
			return nil, false
		}
		var ok bool
		if exp, i, ok = parseJavaExponent(s, i+1); !ok {
			return nil, false
		}
	}
	if i != len(s) {
		return nil, false
	}
	scale := int64(len(frac)) - exp
	if scale < math.MinInt32 || scale > math.MaxInt32 {
		return nil, false
	}
	return decimalRat(neg, intPart+frac, scale), true
}

// parseJavaExponent は、s の i バイト目から始まる指数の符号と数字を読み、指数と、読み終えた位置を返す。
// 頭の 0 を除いて、Java の int に入らない指数は、読めない値とする。
func parseJavaExponent(s string, i int) (int64, int, bool) {
	neg := false
	if i < len(s) && (s[i] == '+' || s[i] == '-') {
		neg = s[i] == '-'
		i++
	}
	start := i
	for i < len(s) && isASCIIDigit(s[i]) {
		i++
	}
	if start == i {
		return 0, i, false
	}
	digits := strings.TrimLeft(s[start:i], "0")
	if len(digits) > 10 {
		return 0, i, false
	}
	exp, _ := strconv.ParseInt("0"+digits, 10, 64)
	if neg {
		exp = -exp
	}
	return exp, i, exp >= math.MinInt32 && exp <= math.MaxInt32
}

// fontSizeMagnitudeLimit は、decimalRat が値をそのまま作る桁の範囲である。値が 10^-3 より小さいか 10^3 以上なら、
// 6 と 72 と比べた結果は変わらないので、decimalRat は、同じ比べ方の結果になる 0 か ±1000 を作る。
// Java の BigDecimal は、10^2147483647 のような値も持てるが、Go で同じ値を作ると、時間とメモリを使いすぎるためである。
const fontSizeMagnitudeLimit = 3

// decimalRat は、符号 neg と、数字の並び digits と、位取り scale から、digits×10^(-scale) の値を作る。
func decimalRat(neg bool, digits string, scale int64) *big.Rat {
	digits = strings.TrimLeft(digits, "0")
	if digits == "" {
		return new(big.Rat)
	}
	// 値は 10^(magnitude-1) 以上 10^magnitude 未満である
	magnitude := int64(len(digits)) - scale
	var r *big.Rat
	switch {
	case magnitude > fontSizeMagnitudeLimit:
		r = big.NewRat(1000, 1)
	case magnitude < -fontSizeMagnitudeLimit:
		return new(big.Rat)
	default:
		n, _ := new(big.Int).SetString(digits, 10)
		pow := new(big.Int).Exp(big.NewInt(10), big.NewInt(abs64(scale)), nil)
		if scale >= 0 {
			r = new(big.Rat).SetFrac(n, pow)
		} else {
			r = new(big.Rat).SetInt(n.Mul(n, pow))
		}
	}
	if neg {
		r.Neg(r)
	}
	return r
}

func abs64(n int64) int64 {
	if n < 0 {
		return -n
	}
	return n
}

// readJavaInt は、Jackson が Java の Integer の欄を読むのと同じに読む。小数点か指数の付いた数は、double に読んでから、
// int の範囲を確かめて 0 の向きに切り捨てる。文字列は、Java の Integer.parseInt と同じに読む。
func readJavaInt(v json.RawMessage) (*int, bool) {
	text, isString, ok := readNumberText(v)
	if !ok || text == nil {
		return nil, ok
	}
	s := *text
	var n int64
	switch {
	case isString:
		n, ok = parseJavaIntString(s)
	case strings.ContainsAny(s, ".eE"):
		// JSON の数なので、誤りは大きすぎるか小さすぎる値だけである。大きすぎれば ±Inf、小さすぎれば 0 になる
		f, _ := strconv.ParseFloat(s, 64)
		ok = f >= math.MinInt32 && f <= math.MaxInt32
		n = int64(f)
	default:
		var err error
		n, err = strconv.ParseInt(s, 10, 32)
		ok = err == nil
	}
	if !ok {
		return nil, false
	}
	i := int(n)
	return &i, true
}

// jdkUnicode は、Java 版を動かす JDK 21 の Unicode の版(15.0)で割り当てられた字の表である。
var jdkUnicode = rangetable.Assigned("15.0.0")

// parseJavaIntString は、Java の Integer.parseInt と同じに、符号と10進数の数字を読む。数字は、Java の Character.digit と同じく、
// 基本多言語面の Unicode の10進数の数字(全角の数字やアラビア文字の数字など)も読む。int に入らない値は読めない値とする。
func parseJavaIntString(s string) (int64, bool) {
	neg := false
	if s != "" && (s[0] == '+' || s[0] == '-') {
		neg = s[0] == '-'
		s = s[1:]
	}
	if s == "" {
		return 0, false
	}
	var n int64
	for _, r := range s {
		d, ok := javaDigit(r)
		if !ok {
			return 0, false
		}
		if n = n*10 + int64(d); n > math.MaxInt32+1 {
			return 0, false
		}
	}
	if neg {
		n = -n
	}
	return n, n >= math.MinInt32 && n <= math.MaxInt32
}

// javaDigit は、Java の Character.digit(r, 10) と同じく、r が10進数の数字なら、その値を返す。Java の String は UTF-16 で字を持ち、
// Integer.parseInt は UTF-16 の単位ごとに数字かを見るので、基本多言語面の外の字は数字としない。
// Unicode の10進数の数字は、0 から 9 の順に10字ずつ続けて並ぶので、続く数字の並びの初めからの位置で値を決める。
func javaDigit(r rune) (int, bool) {
	if r > 0xFFFF || !unicode.Is(unicode.Nd, r) || !unicode.Is(jdkUnicode, r) {
		return 0, false
	}
	first := r
	for unicode.Is(unicode.Nd, first-1) {
		first--
	}
	return int(r-first) % 10, true
}

// validateExportBody は、読んだ本文を、Java 版の ExportResumeRequest の注釈の断る条件で確かめる。1つの欄に2つの文言が付くときは、
// 文言を注釈の順に並べる。断る条件に当たらなければ nil を返す。
func validateExportBody(b exportBody) *auth.Error {
	f := auth.FieldErrors{}
	checkExportChoice(f, "format", b.format, MessageExportFormatRequired, MessageExportFormatInvalid, "pdf", "markdown")
	checkExportChoice(f, "disposition", b.disposition, MessageExportDispositionRequired, MessageExportDispositionInvalid, "inline", "attachment")
	f.Check("pdfSettingsRequired", b.format == nil || *b.format != "pdf" || b.pdfSettings != nil, MessageExportPDFSettingsRequired)
	if s := b.pdfSettings; s != nil {
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
	for i, v := range [4]*big.Rat{s.Title, s.Date, s.FullName, s.SectionHeading} {
		field := exportFontSizeFields[i]
		path := "pdfSettings.fontSizes." + field.path
		f.Check(path, v != nil, field.required)
		f.Check(path, v == nil || v.Cmp(minFontSize) >= 0, field.tooSmall)
		f.Check(path, v == nil || v.Cmp(maxFontSize) <= 0, field.tooLarge)
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
		if !isASCIIDigit(c) && (c < 'a' || c > 'f') && (c < 'A' || c > 'F') {
			return false
		}
	}
	return true
}
