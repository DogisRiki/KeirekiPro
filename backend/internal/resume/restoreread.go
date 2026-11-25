package resume

import (
	"encoding/json"
	"math"
	"math/big"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"time"
)

// 戻しの本文の読み手
//
// readRestoreFile は、戻しの要求の本文を、Java 版の RestoreResumeRequest を Jackson(3.1.7)が読むのと同じ規則で読む。
// Java 版が読めない本文(400「入力エラーがあります。」で断る本文)を、readRestoreFile も読めない本文とする(要件4の受入基準6)。
// 規則は、Java 版の Jackson に本文を渡して確かめた答えに合わせてある。主な規則は次のとおりである。
//
//   - 一番外の値はオブジェクトでなければならない。最初の値のあとに続く字は読まない
//   - 知らない名前の欄は、どの深さでも読み飛ばす。ただし、どの数も、数字の数が maxNumberLength を超えてはならない
//   - 同じ名前の欄が2つあれば、Jackson は両方の値を読み、あとの値を使う。前の値を読めなければ、本文を読めない
//   - 無い欄と null の欄は、値が無いとする(要件2の受入基準2)

// rsFile は、戻しの要求の本文である。Java 版の RestoreResumeRequest にあたる。exportedAt は、読めるかだけを確かめ、持たない。
type rsFile struct {
	version *string
	resume  *rsResume
	// nullElement は、経歴書の6つの欄のどれかの並びに null の要素があることである。
	nullElement bool
}

// rsResume は、戻しの本文の経歴書である。Java 版の RestoreResumeRequest.ResumeDto にあたる。
// 6つの欄の並びは、欄が無いか null なら nil、並びの null の要素は nil の要素とする。
type rsResume struct {
	name           *string
	date           *Date
	lastName       *string
	firstName      *string
	careers        []*rsCareer
	projects       []*rsProject
	certifications []*rsCertification
	portfolios     []*rsPortfolio
	snsPlatforms   []*rsSnsPlatform
	selfPromotions []*rsSelfPromotion
}

// rsCareer は、戻しの本文の職歴である。
type rsCareer struct {
	companyName *string
	startDate   *YearMonth
	endDate     *YearMonth
	active      bool
}

// rsProject は、戻しの本文のプロジェクトである。techStack の欄が無いか null なら、35の小分類をすべて空の並びとする。
type rsProject struct {
	companyName *string
	startDate   *YearMonth
	endDate     *YearMonth
	active      bool
	name        *string
	overview    *string
	teamComp    *string
	role        *string
	achievement *string
	process     Process
	techStack   TechStack
}

// rsCertification は、戻しの本文の資格である。
type rsCertification struct {
	name *string
	date *YearMonth
}

// rsPortfolio は、戻しの本文のポートフォリオである。
type rsPortfolio struct {
	name      *string
	overview  *string
	techStack *string
	link      *string
}

// rsSnsPlatform は、戻しの本文の SNS である。
type rsSnsPlatform struct {
	name *string
	link *string
}

// rsSelfPromotion は、戻しの本文の自己 PR である。
type rsSelfPromotion struct {
	title   *string
	content *string
}

// readRestoreFile は、戻しの要求の本文 body を読む。Java 版が読めない本文なら false を返す。
func readRestoreFile(body []byte) (rsFile, bool) {
	root, ok := parseJTree(body)
	if !ok || root.kind != jvObject || !jvNumbersWithinLimit(root) {
		return rsFile{}, false
	}
	var f rsFile
	if !readRSObject(root, map[string]fieldReader{
		"version":    stringField(&f.version),
		"exportedAt": rsInstantReadable,
		"resume":     pojoField(&f.resume, readResume),
	}) {
		return rsFile{}, false
	}
	if r := f.resume; r != nil {
		f.nullElement = slices.Contains(r.careers, nil) || slices.Contains(r.projects, nil) ||
			slices.Contains(r.certifications, nil) || slices.Contains(r.portfolios, nil) ||
			slices.Contains(r.snsPlatforms, nil) || slices.Contains(r.selfPromotions, nil)
	}
	return f, true
}

// jvNumbersWithinLimit は、値の木 v の中のどの数も、数字の数が maxNumberLength を超えないかを返す。
// 本文を丸ごと numbersWithinLimit に渡さないのは、Jackson が読まない、最初の値のあとに続く字の数まで確かめてしまうためである。
func jvNumbersWithinLimit(v *jv) bool {
	switch v.kind {
	case jvNumber:
		return numbersWithinLimit(json.RawMessage(v.text))
	case jvArray:
		for _, item := range v.items {
			if !jvNumbersWithinLimit(item) {
				return false
			}
		}
	case jvObject:
		for _, m := range v.members {
			if !jvNumbersWithinLimit(m.value) {
				return false
			}
		}
	default:
	}
	return true
}

// オブジェクトの読み方

// fieldReader は、オブジェクトの1つの欄の値を読み、読めなければ false を返す。
type fieldReader func(v *jv) bool

// readRSObject は、オブジェクト o の欄を書かれた順に、名前ごとの読み方 fields で読む。知らない名前の欄は読み飛ばす。
// 同じ名前の欄が2つあれば、両方を読む。読み方があとの値で前の値を置き換えるので、あとの値が残る。
func readRSObject(o *jv, fields map[string]fieldReader) bool {
	for _, m := range o.members {
		if read, ok := fields[m.name]; ok && !read(m.value) {
			return false
		}
	}
	return true
}

// readPOJO は、オブジェクトの欄の値 v を read で読む。null なら値が無いとし、オブジェクトでも null でもなければ読めない。
func readPOJO[T any](v *jv, read func(o *jv) (*T, bool)) (*T, bool) {
	switch v.kind {
	case jvNull:
		return nil, true
	case jvObject:
		return read(v)
	default:
		return nil, false
	}
}

// pojoField は、オブジェクトの欄を読んで dst に入れる読み方である。
func pojoField[T any](dst **T, read func(o *jv) (*T, bool)) fieldReader {
	return func(v *jv) bool {
		var ok bool
		*dst, ok = readPOJO(v, read)
		return ok
	}
}

// entriesField は、6つの欄の並びを読んで dst に入れる読み方である。null なら nil とし、並びでも null でもなければ読めない。
// 並びの null の要素は nil の要素とし、オブジェクトでも null でもない要素は読めない。
func entriesField[T any](dst *[]*T, read func(o *jv) (*T, bool)) fieldReader {
	return func(v *jv) bool {
		*dst = nil
		switch v.kind {
		case jvNull:
			return true
		case jvArray:
			list := make([]*T, len(v.items))
			for i, item := range v.items {
				e, ok := readPOJO(item, read)
				if !ok {
					return false
				}
				list[i] = e
			}
			*dst = list
			return true
		default:
			return false
		}
	}
}

// stringField は、文字列の欄を読んで dst に入れる読み方である。
func stringField(dst **string) fieldReader {
	return func(v *jv) bool {
		var ok bool
		*dst, ok = rsString(v)
		return ok
	}
}

// boolField は、真偽の欄を読んで dst に入れる読み方である。
func boolField(dst *bool) fieldReader {
	return func(v *jv) bool {
		var ok bool
		*dst, ok = rsBool(v)
		return ok
	}
}

// yearMonthField は、年月の欄を読んで dst に入れる読み方である。
func yearMonthField(dst **YearMonth) fieldReader {
	return func(v *jv) bool {
		var ok bool
		*dst, ok = rsYearMonth(v)
		return ok
	}
}

// dateField は、日付の欄を読んで dst に入れる読み方である。
func dateField(dst **Date) fieldReader {
	return func(v *jv) bool {
		var ok bool
		*dst, ok = rsDate(v)
		return ok
	}
}

// processField は、工程の欄を読んで dst に入れる読み方である。null なら7つの工程をすべて偽とする。
func processField(dst *Process) fieldReader {
	return func(v *jv) bool {
		*dst = Process{}
		switch v.kind {
		case jvNull:
			return true
		case jvObject:
			return readRSObject(v, map[string]fieldReader{
				"requirements":    boolField(&dst.Requirements),
				"basicDesign":     boolField(&dst.BasicDesign),
				"detailedDesign":  boolField(&dst.DetailedDesign),
				"implementation":  boolField(&dst.Implementation),
				"integrationTest": boolField(&dst.IntegrationTest),
				"systemTest":      boolField(&dst.SystemTest),
				"maintenance":     boolField(&dst.Maintenance),
			})
		default:
			return false
		}
	}
}

// techStackField は、技術スタックの欄を読んで dst に入れる読み方である。null なら35の小分類をすべて空の並びとする。
// 大分類と小分類の欄の名前は、TechStackSet の json の名前である。無い大分類と小分類、null の大分類は、空の並びとする。
func techStackField(dst *TechStack) fieldReader {
	return func(v *jv) bool {
		*dst = emptyTechStack()
		switch v.kind {
		case jvNull:
			return true
		case jvObject:
			return readRSObject(v, techStackReaders(dst))
		default:
			return false
		}
	}
}

// emptyTechStack は、35の小分類をすべて空の並びにした技術スタックを返す。
func emptyTechStack() TechStack {
	var t TechStack
	root := reflect.ValueOf(&t).Elem()
	for i := range root.NumField() {
		resetStackLists(root.Field(i))
	}
	return t
}

// resetStackLists は、技術スタックの大分類 category のすべての小分類を空の並びにする。
func resetStackLists(category reflect.Value) {
	for i := range category.NumField() {
		category.Field(i).Set(reflect.ValueOf([]*string{}))
	}
}

// techStackReaders は、技術スタック ts の大分類の名前ごとの読み方を返す。大分類の欄を読むたびに、その大分類の
// 小分類をすべて空の並びに戻してから読む。Java 版の Jackson は、欄を読むたびに新しい値を作るためである。
func techStackReaders(ts *TechStack) map[string]fieldReader {
	root := reflect.ValueOf(ts).Elem()
	readers := make(map[string]fieldReader, root.NumField())
	for i := range root.NumField() {
		category := root.Field(i)
		lists := make(map[string]fieldReader, category.NumField())
		for j := range category.NumField() {
			list := category.Field(j)
			lists[category.Type().Field(j).Tag.Get("json")] = func(v *jv) bool {
				l, ok := rsStringList(v)
				list.Set(reflect.ValueOf(l))
				return ok
			}
		}
		readers[root.Type().Field(i).Tag.Get("json")] = func(v *jv) bool {
			resetStackLists(category)
			switch v.kind {
			case jvNull:
				return true
			case jvObject:
				return readRSObject(v, lists)
			default:
				return false
			}
		}
	}
	return readers
}

// 欄ごとの読み方

func readResume(o *jv) (*rsResume, bool) {
	r := &rsResume{}
	return r, readRSObject(o, map[string]fieldReader{
		"resumeName":     stringField(&r.name),
		"date":           dateField(&r.date),
		"lastName":       stringField(&r.lastName),
		"firstName":      stringField(&r.firstName),
		"careers":        entriesField(&r.careers, readCareer),
		"projects":       entriesField(&r.projects, readProject),
		"certifications": entriesField(&r.certifications, readCertification),
		"portfolios":     entriesField(&r.portfolios, readPortfolio),
		"snsPlatforms":   entriesField(&r.snsPlatforms, readSnsPlatform),
		"selfPromotions": entriesField(&r.selfPromotions, readSelfPromotion),
	})
}

func readCareer(o *jv) (*rsCareer, bool) {
	c := &rsCareer{}
	return c, readRSObject(o, map[string]fieldReader{
		"companyName": stringField(&c.companyName),
		"startDate":   yearMonthField(&c.startDate),
		"endDate":     yearMonthField(&c.endDate),
		"active":      boolField(&c.active),
	})
}

func readProject(o *jv) (*rsProject, bool) {
	p := &rsProject{techStack: emptyTechStack()}
	return p, readRSObject(o, map[string]fieldReader{
		"companyName": stringField(&p.companyName),
		"startDate":   yearMonthField(&p.startDate),
		"endDate":     yearMonthField(&p.endDate),
		"active":      boolField(&p.active),
		"name":        stringField(&p.name),
		"overview":    stringField(&p.overview),
		"teamComp":    stringField(&p.teamComp),
		"role":        stringField(&p.role),
		"achievement": stringField(&p.achievement),
		"process":     processField(&p.process),
		"techStack":   techStackField(&p.techStack),
	})
}

func readCertification(o *jv) (*rsCertification, bool) {
	c := &rsCertification{}
	return c, readRSObject(o, map[string]fieldReader{
		"name": stringField(&c.name),
		"date": yearMonthField(&c.date),
	})
}

func readPortfolio(o *jv) (*rsPortfolio, bool) {
	p := &rsPortfolio{}
	return p, readRSObject(o, map[string]fieldReader{
		"name":      stringField(&p.name),
		"overview":  stringField(&p.overview),
		"techStack": stringField(&p.techStack),
		"link":      stringField(&p.link),
	})
}

func readSnsPlatform(o *jv) (*rsSnsPlatform, bool) {
	s := &rsSnsPlatform{}
	return s, readRSObject(o, map[string]fieldReader{
		"name": stringField(&s.name),
		"link": stringField(&s.link),
	})
}

func readSelfPromotion(o *jv) (*rsSelfPromotion, bool) {
	s := &rsSelfPromotion{}
	return s, readRSObject(o, map[string]fieldReader{
		"title":   stringField(&s.title),
		"content": stringField(&s.content),
	})
}

// 値の種類ごとの読み方

// isIntToken は、数 text が、小数点と指数を持たない整数の書き方かを返す。Jackson は、整数と小数の書き方を別の種類として読む。
func isIntToken(text string) bool { return !strings.ContainsAny(text, ".eE") }

// rsString は、文字列の値 v を読む。数は書かれたままの字、真偽は true か false の字とする。並びとオブジェクトは読めない。
func rsString(v *jv) (*string, bool) {
	var s string
	switch v.kind {
	case jvNull:
		return nil, true
	case jvString, jvNumber:
		s = v.text
	case jvBool:
		s = strconv.FormatBool(v.truth)
	default:
		return nil, false
	}
	return &s, true
}

// rsBool は、真偽の値 v を読む。null は偽とする。整数は 0 でなければ真とし、小数の書き方の数は読めない。
// 文字列は、前後の空白を除いて、true と True と TRUE を真、false と False と FALSE と null と空を偽とし、ほかは読めない。
func rsBool(v *jv) (bool, bool) {
	switch v.kind {
	case jvNull:
		return false, true
	case jvBool:
		return v.truth, true
	case jvNumber:
		return strings.ContainsAny(v.text, "123456789"), isIntToken(v.text)
	case jvString:
		switch javaTrim(v.text) {
		case "true", "True", "TRUE":
			return true, true
		case "", "false", "False", "FALSE", "null":
			return false, true
		default:
			return false, false
		}
	default:
		return false, false
	}
}

// rsStringList は、技術スタックの小分類の並びの値 v を読む。null は空の並びとする。並びの要素は rsString で読み、
// null の要素は nil の要素とする。並びとオブジェクトの要素、並びでない値は読めない。
func rsStringList(v *jv) ([]*string, bool) {
	switch v.kind {
	case jvNull:
		return []*string{}, true
	case jvArray:
		list := make([]*string, len(v.items))
		for i, item := range v.items {
			s, ok := rsString(item)
			if !ok {
				return []*string{}, false
			}
			list[i] = s
		}
		return list, true
	default:
		return []*string{}, false
	}
}

// javaMaxYear は、Java の LocalDate と YearMonth が持てる年の上限である。下限は、この値の符号を逆にした値である。
const javaMaxYear = 999999999

// rsYearMonth は、年月の値 v を読む。null と空の文字列と空の並びは値が無いとする。
// 文字列は、前後の空白を除いて、parseYearMonthText で読む。並びは、年と月の2つの整数とする。
func rsYearMonth(v *jv) (*YearMonth, bool) {
	switch v.kind {
	case jvNull:
		return nil, true
	case jvString:
		s := javaTrim(v.text)
		if s == "" {
			return nil, true
		}
		return parseYearMonthText(s)
	case jvArray:
		if len(v.items) == 0 {
			return nil, true
		}
		n, ok := int32Items(v, 2)
		if !ok {
			return nil, false
		}
		return yearMonthOf(n[0], n[1])
	default:
		return nil, false
	}
}

// parseYearMonthText は、年月の文字列 s を読む。年は、- を付けられる1から19桁の数字で、先頭の 0 を許し、-0 を許さない。
// 年のあとに - と2桁の月が続き、そこで文字列が終わる。
func parseYearMonthText(s string) (*YearMonth, bool) {
	c := textCursor{s: s}
	minus := c.take('-')
	d := c.digits()
	if len(d) == 0 || len(d) > 19 {
		return nil, false
	}
	y, err := strconv.Atoi(d)
	if err != nil || (minus && y == 0) || !c.take('-') {
		return nil, false
	}
	m, ok := c.fixed2()
	if !ok || !c.done() {
		return nil, false
	}
	if minus {
		y = -y
	}
	return yearMonthOf(y, m)
}

// yearMonthOf は、年 y と月 m の年月を返す。年が Java の YearMonth の範囲の外か、月が 1 から 12 でなければ false を返す。
func yearMonthOf(y, m int) (*YearMonth, bool) {
	if y < -javaMaxYear || y > javaMaxYear || m < 1 || m > 12 {
		return nil, false
	}
	return &YearMonth{Year: y, Month: time.Month(m)}, true
}

// Java の LocalDate.ofEpochDay が受け付ける、1970年1月1日からの日数の範囲である。
const (
	minEpochDay = -365243219162
	maxEpochDay = 365241780471
)

// rsDate は、日付の値 v を読む。null と空の文字列と空の並びは値が無いとする。整数は、1970年1月1日からの日数とする。
// 文字列は、前後の空白を除いて、parseDateText で読む。並びは、年と月と日の3つの整数とする。
func rsDate(v *jv) (*Date, bool) {
	switch v.kind {
	case jvNull:
		return nil, true
	case jvNumber:
		n, err := strconv.Atoi(v.text)
		if err != nil || n < minEpochDay || n > maxEpochDay {
			return nil, false
		}
		y, m, d := civilFromDays(n)
		return &Date{Year: y, Month: time.Month(m), Day: d}, true
	case jvString:
		s := javaTrim(v.text)
		if s == "" {
			return nil, true
		}
		return parseDateText(s)
	case jvArray:
		if len(v.items) == 0 {
			return nil, true
		}
		n, ok := int32Items(v, 3)
		if !ok {
			return nil, false
		}
		return dateOf(n[0], n[1], n[2])
	default:
		return nil, false
	}
}

// parseDateText は、日付の文字列 s を読む。11字目が大文字の T なら、日時(ISO_LOCAL_DATE_TIME)として読み、日付だけを使う。
// そのとき、末尾の大文字の Z を1つ除いてから読む。11字目が T でなければ、日付(ISO_LOCAL_DATE)として読む。
func parseDateText(s string) (*Date, bool) {
	c := textCursor{s: s}
	dateTime := len(s) > 10 && s[10] == 'T'
	if dateTime {
		c.s = strings.TrimSuffix(s, "Z")
	}
	y, m, d, ok := c.isoDate()
	if !ok {
		return nil, false
	}
	if dateTime {
		if !c.take('T') {
			return nil, false
		}
		h, mi, sec, _, ok := c.clock(false)
		if !ok || h > 23 || mi > 59 || sec > 59 {
			return nil, false
		}
	}
	if !c.done() {
		return nil, false
	}
	return dateOf(y, m, d)
}

// dateOf は、年 y と月 m と日 d の日付を返す。年が Java の LocalDate の範囲の外か、暦に無い日付なら false を返す。
func dateOf(y, m, d int) (*Date, bool) {
	if y < -javaMaxYear || y > javaMaxYear || !validDate(y, m, d) {
		return nil, false
	}
	return &Date{Year: y, Month: time.Month(m), Day: d}, true
}

// int32Items は、並び v が n 個の整数だけを持ち、どの整数も Java の int の範囲に入るときに、その整数を返す。
func int32Items(v *jv, n int) ([]int, bool) {
	if len(v.items) != n {
		return nil, false
	}
	out := make([]int, n)
	for i, item := range v.items {
		if item.kind != jvNumber || !isIntToken(item.text) {
			return nil, false
		}
		x, err := strconv.Atoi(item.text)
		if err != nil || x < math.MinInt32 || x > math.MaxInt32 {
			return nil, false
		}
		out[i] = x
	}
	return out, true
}

// Java の Instant の、1970年1月1日0時(UTC)からの秒数の範囲である。
const (
	minInstantSecond = -31557014167219200
	maxInstantSecond = 31556889864403199
)

// rsInstantReadable は、exportedAt の値 v を、Java の Instant として読めるかを返す。null と空の文字列は読めるとする。
func rsInstantReadable(v *jv) bool {
	switch v.kind {
	case jvNull:
		return true
	case jvNumber:
		if isIntToken(v.text) {
			n, err := strconv.ParseInt(v.text, 10, 64)
			return err == nil && instantSecondOK(n)
		}
		d, ok := parseNumberToken(v.text)
		return ok && d.instantOK()
	case jvString:
		return instantTextReadable(javaTrim(v.text))
	default:
		return false
	}
}

// instantTextReadable は、前後の空白を除いた exportedAt の文字列 s を読めるかを返す。符号と数字と小数点だけの文字列は、
// 秒数として読む。ほかの文字列は、末尾の +00 と +0000 と +00:00 を Z に替えてから、ISO_INSTANT の日時として読む。
func instantTextReadable(s string) bool {
	if s == "" {
		return true
	}
	if dots, ok := countDecimalDots(s); ok {
		if len(s) > maxNumberLength {
			return false
		}
		switch dots {
		case 0:
			n, err := strconv.ParseInt(s, 10, 64)
			return err == nil && instantSecondOK(n)
		case 1:
			d, ok := parseDecimalText(s)
			return ok && d.instantOK()
		default:
			return false
		}
	}
	return isoInstantReadable(replaceZeroOffsetAsZ(s))
}

func instantSecondOK(n int64) bool { return n >= minInstantSecond && n <= maxInstantSecond }

// countDecimalDots は、s が、先頭の1つの + か - のあとに数字と小数点だけを持つときに、小数点の数を返す。
func countDecimalDots(s string) (int, bool) {
	if s[0] == '+' || s[0] == '-' {
		s = s[1:]
	}
	dots := 0
	for i := range len(s) {
		switch {
		case s[i] == '.':
			dots++
		case !isASCIIDigit(s[i]):
			return 0, false
		}
	}
	return dots, true
}

// replaceZeroOffsetAsZ は、s の最後の + のあとが 00 か 0000 か 00:00 だけなら、+ から後ろを Z に替える。
// Java 版の Jackson の InstantDeserializer が、日時の文字列を読む前にする置き換えである。
func replaceZeroOffsetAsZ(s string) string {
	i := strings.LastIndexByte(s, '+')
	if i < 0 {
		return s
	}
	switch s[i+1:] {
	case "00", "0000", "00:00":
		return s[:i] + "Z"
	default:
		return s
	}
}

// isoInstantReadable は、s を Java の DateTimeFormatter.ISO_INSTANT の日時として読めるかを返す。大文字と小文字を区別しない。
// 日時は、ISO の年月日、T、2桁の時と分と秒、0 から 9 桁の秒の小数、時差(Z か ±HH:MM か ±HH:MM:SS)の順に並ぶ。
// 24:00:00 は翌日の 0 時、23:59:60 は 23:59:59 とする。年は Java の LocalDate の範囲を超えてよいが、日時は Instant の範囲に入る。
func isoInstantReadable(s string) bool {
	c := textCursor{s: s}
	y, mo, d, ok := c.isoDate()
	if !ok || !c.takeFold('T') {
		return false
	}
	h, mi, sec, fracZero, ok := c.clock(true)
	if !ok {
		return false
	}
	offset, ok := c.offset()
	if !ok || !c.done() {
		return false
	}
	days := 0
	switch {
	case h == 24 && mi == 0 && sec == 0 && fracZero:
		h, days = 0, 1
	case h == 23 && mi == 59 && sec == 60:
		sec = 59
	default:
	}
	if h > 23 || mi > 59 || sec > 59 || !validDate(y, mo, d) {
		return false
	}
	secs := int64(daysFromCivil(y, mo, d)+days)*86400 + int64(h*3600+mi*60+sec-offset)
	return instantSecondOK(secs)
}

// 数の読み方

// javaDecimal は、Java の BigDecimal と同じく、整数 unscaled を 10 の scale 乗で割った数である。
type javaDecimal struct {
	unscaled *big.Int
	scale    int64
}

// parseNumberToken は、JSON の小数の書き方の数 text を、Java の BigDecimal(String) と同じく読む。
// 指数が Java の int の範囲に入らないか、scale が Java の int の範囲に入らなければ false を返す。
func parseNumberToken(text string) (javaDecimal, bool) {
	mantissa, exp, hasExp := strings.Cut(strings.ToLower(text), "e")
	d, ok := parseDecimalText(mantissa)
	if !ok {
		return javaDecimal{}, false
	}
	if hasExp {
		neg := strings.HasPrefix(exp, "-")
		digits := strings.TrimLeft(strings.TrimLeft(exp, "+-"), "0")
		if len(digits) > 10 {
			return javaDecimal{}, false
		}
		e, _ := strconv.ParseInt("0"+digits, 10, 64)
		if neg {
			e = -e
		}
		if e < math.MinInt32 || e > math.MaxInt32 {
			return javaDecimal{}, false
		}
		d.scale -= e
	}
	return d, d.scale >= math.MinInt32 && d.scale <= math.MaxInt32
}

// parseDecimalText は、先頭に + か - を1つ付けられる、数字と多くとも1つの小数点の数 s を読む。数字が1つも無ければ false を返す。
func parseDecimalText(s string) (javaDecimal, bool) {
	neg := strings.HasPrefix(s, "-")
	s = strings.TrimLeft(s, "+-")
	intPart, frac, _ := strings.Cut(s, ".")
	digits := intPart + frac
	if digits == "" {
		return javaDecimal{}, false
	}
	u, ok := new(big.Int).SetString(digits, 10)
	if !ok {
		return javaDecimal{}, false
	}
	if neg {
		u.Neg(u)
	}
	return javaDecimal{unscaled: u, scale: int64(len(frac))}, true
}

// instantOK は、d を秒数として Java の Instant にできるかを返す。Jackson の DecimalUtils.extractSecondsAndNanos と
// Instant.ofEpochSecond と同じく、秒は整数の部分の下位64ビット、ナノ秒は (d×10^9 − 秒×10^9) の整数の部分の下位32ビットとする。
func (d javaDecimal) instantOK() bool {
	nanoScale := d.scale - 9
	if nanoScale < math.MinInt32 {
		if d.unscaled.Sign() != 0 {
			return false
		}
		nanoScale = math.MinInt32
	}
	precision := int64(len(new(big.Int).Abs(d.unscaled).String()))
	if precision-nanoScale <= 0 || d.scale < -63 {
		return true
	}
	whole := new(big.Int)
	if d.scale >= 0 {
		whole.Quo(d.unscaled, pow10(d.scale))
	} else {
		whole.Mul(d.unscaled, pow10(-d.scale))
	}
	secs := lowBits(whole, 64)
	// d×10^9 − secs×10^9 の整数の部分。scale が 9 以下なら整数のまま引き、9 を超えるなら
	// (unscaled − secs×10^scale) を 10^(scale−9) で割って 0 の向きに丸める。
	var diff *big.Int
	if d.scale <= 9 {
		diff = new(big.Int).Mul(d.unscaled, pow10(9-d.scale))
		diff.Sub(diff, new(big.Int).Mul(big.NewInt(secs), pow10(9)))
	} else {
		diff = new(big.Int).Mul(big.NewInt(secs), pow10(d.scale))
		diff.Sub(d.unscaled, diff)
		diff.Quo(diff, pow10(d.scale-9))
	}
	nanos := lowBits(diff, 32)
	adjust := nanos / 1e9
	if nanos%1e9 < 0 {
		adjust--
	}
	if (adjust > 0 && secs > math.MaxInt64-adjust) || (adjust < 0 && secs < math.MinInt64-adjust) {
		return false
	}
	return instantSecondOK(secs + adjust)
}

func pow10(n int64) *big.Int { return new(big.Int).Exp(big.NewInt(10), big.NewInt(n), nil) }

// lowBits は、x の2の補数の下位 bits ビットを、符号付きの整数として返す。Java の BigInteger の longValue と intValue にあたる。
func lowBits(x *big.Int, bits uint) int64 {
	m := new(big.Int).Lsh(big.NewInt(1), bits)
	r := new(big.Int).Mod(x, m)
	if r.Cmp(new(big.Int).Rsh(m, 1)) >= 0 {
		r.Sub(r, m)
	}
	return r.Int64()
}

// 日時の字の読み方

// textCursor は、日時の文字列を頭から読むための、読みかけの位置である。
type textCursor struct {
	s string
	i int
}

func (c *textCursor) take(b byte) bool {
	if c.i < len(c.s) && c.s[c.i] == b {
		c.i++
		return true
	}
	return false
}

// takeFold は、大文字の b か、その小文字を読む。
func (c *textCursor) takeFold(b byte) bool { return c.take(b) || c.take(b+'a'-'A') }

// digits は、続く ASCII の数字をすべて読む。
func (c *textCursor) digits() string {
	start := c.i
	for c.i < len(c.s) && isASCIIDigit(c.s[c.i]) {
		c.i++
	}
	return c.s[start:c.i]
}

// fixed2 は、続く2桁の ASCII の数字を読む。
func (c *textCursor) fixed2() (int, bool) {
	if c.i+2 > len(c.s) || !isASCIIDigit(c.s[c.i]) || !isASCIIDigit(c.s[c.i+1]) {
		return 0, false
	}
	n := int(c.s[c.i]-'0')*10 + int(c.s[c.i+1]-'0')
	c.i += 2
	return n, true
}

func (c *textCursor) done() bool { return c.i == len(c.s) }

// isoYear は、ISO の年を読む。符号の無い年は4桁、+ の付いた年は5から10桁、- の付いた年は4から10桁とし、-0 を許さない。
func (c *textCursor) isoYear() (int, bool) {
	plus := c.take('+')
	minus := !plus && c.take('-')
	d := c.digits()
	switch {
	case len(d) < 4 || len(d) > 10, plus && len(d) == 4, !plus && !minus && len(d) != 4:
		return 0, false
	default:
	}
	y := 0
	for i := range len(d) {
		y = y*10 + int(d[i]-'0')
	}
	if minus {
		if y == 0 {
			return 0, false
		}
		y = -y
	}
	return y, true
}

// isoDate は、ISO の年月日(年、-、2桁の月、-、2桁の日)を読む。暦に有る日付かは確かめない。
func (c *textCursor) isoDate() (y, m, d int, ok bool) {
	if y, ok = c.isoYear(); !ok || !c.take('-') {
		return 0, 0, 0, false
	}
	if m, ok = c.fixed2(); !ok || !c.take('-') {
		return 0, 0, 0, false
	}
	if d, ok = c.fixed2(); !ok {
		return 0, 0, 0, false
	}
	return y, m, d, true
}

// clock は、2桁の時、:、2桁の分を読み、: が続けば2桁の秒を読み、秒のあとに . が続けば 0 から 9 桁の秒の小数を読む。
// needSeconds なら、秒を省けない。fracZero は、秒の小数が無いか、0 だけであることである。値の範囲は確かめない。
func (c *textCursor) clock(needSeconds bool) (h, m, s int, fracZero, ok bool) {
	h, okH := c.fixed2()
	okColon := c.take(':')
	m, okM := c.fixed2()
	if !okH || !okColon || !okM {
		return 0, 0, 0, false, false
	}
	fracZero = true
	if c.take(':') {
		if s, ok = c.fixed2(); !ok {
			return 0, 0, 0, false, false
		}
		if c.take('.') {
			frac := c.digits()
			if len(frac) > 9 {
				return 0, 0, 0, false, false
			}
			fracZero = strings.Trim(frac, "0") == ""
		}
	} else if needSeconds {
		return 0, 0, 0, false, false
	}
	return h, m, s, fracZero, true
}

// offset は、時差(Z か z、または ±HH:MM か ±HH:MM:SS)を読み、秒の数で返す。時差は ±18時間を超えてはならない。
func (c *textCursor) offset() (int, bool) {
	if c.takeFold('Z') {
		return 0, true
	}
	sign := 1
	switch {
	case c.take('+'):
	case c.take('-'):
		sign = -1
	default:
		return 0, false
	}
	h, okH := c.fixed2()
	okColon := c.take(':')
	m, okM := c.fixed2()
	if !okH || !okColon || !okM {
		return 0, false
	}
	s := 0
	if c.take(':') {
		var ok bool
		if s, ok = c.fixed2(); !ok {
			return 0, false
		}
	}
	total := h*3600 + m*60 + s
	if h > 23 || m > 59 || s > 59 || total > 18*3600 {
		return 0, false
	}
	return sign * total, true
}

// 暦

// validDate は、年 y の m 月 d 日が、先発グレゴリオ暦に有る日付かを返す。
func validDate(y, m, d int) bool {
	if m < 1 || m > 12 || d < 1 {
		return false
	}
	days := [...]int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}[m-1]
	if m == 2 && y%4 == 0 && (y%100 != 0 || y%400 == 0) {
		days = 29
	}
	return d <= days
}

// floorDiv は、a を b で割り、負の無限大の向きに丸めた商を返す。b は正とする。
func floorDiv(a, b int) int {
	q := a / b
	if a%b < 0 {
		q--
	}
	return q
}

// daysFromCivil は、先発グレゴリオ暦の y 年 m 月 d 日の、1970年1月1日からの日数を返す
// (Howard Hinnant の days_from_civil)。
func daysFromCivil(y, m, d int) int {
	if m <= 2 {
		y--
	}
	era := floorDiv(y, 400)
	yoe := y - era*400
	doy := (153*((m+9)%12)+2)/5 + d - 1
	doe := yoe*365 + yoe/4 - yoe/100 + doy
	return era*146097 + doe - 719468
}

// civilFromDays は、1970年1月1日からの日数 z の、先発グレゴリオ暦の年と月と日を返す(Howard Hinnant の civil_from_days)。
func civilFromDays(z int) (y, m, d int) {
	z += 719468
	era := floorDiv(z, 146097)
	doe := z - era*146097
	yoe := (doe - doe/1460 + doe/36524 - doe/146096) / 365
	doy := doe - (365*yoe + yoe/4 - yoe/100)
	mp := (5*doy + 2) / 153
	d = doy - (153*mp+2)/5 + 1
	m = mp + 3
	if m > 12 {
		m -= 12
	}
	y = yoe + era*400
	if m <= 2 {
		y++
	}
	return y, m, d
}
