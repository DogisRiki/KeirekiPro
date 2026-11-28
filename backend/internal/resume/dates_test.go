package resume

import (
	"encoding/json"
	"fmt"
	"regexp"
	"testing"
)

// dateState は、1つの書き方を読んだ結果の種類である。
type dateState int

const (
	// dateRead は、値を読めたことである。
	dateRead dateState = iota
	// dateAbsent は、値が無いことである。入力の検査が入力必須の文言で断る。
	dateAbsent
	// dateUnreadable は、値を読めないことである。400 と空の errors で断る。
	dateUnreadable
)

func (s dateState) String() string {
	switch s {
	case dateRead:
		return "読めた"
	case dateAbsent:
		return "値が無い"
	case dateUnreadable:
		return "読めない"
	}
	return fmt.Sprintf("dateState(%d)", int(s))
}

// dateResult は、1つの書き方の答えである。
type dateResult struct {
	state dateState
	// value は、範囲の中の値を読めたときの値である。
	value string
	// outOfRange は、値を読めたが、入力の検査が1900年から2100年の範囲の外として断ることである。
	outOfRange bool
}

func (r dateResult) String() string {
	switch {
	case r.state != dateRead:
		return r.state.String()
	case r.outOfRange:
		return "読めたが範囲の外"
	}
	return "読めた " + r.value
}

// resultFromGo は、読み方の結果を、dateResult に直す。
func resultFromGo(err error, present bool, year int, value string) dateResult {
	switch {
	case err != nil:
		return dateResult{state: dateUnreadable}
	case !present:
		return dateResult{state: dateAbsent}
	case year < 1900 || year > 2100:
		// 入力の検査は、1900年から2100年までを受ける
		return dateResult{state: dateRead, outOfRange: true}
	}
	return dateResult{state: dateRead, value: value}
}

func formatYearMonth(ym YearMonth) string {
	return fmt.Sprintf("%04d-%02d", ym.Year, int(ym.Month))
}

func formatDate(d Date) string {
	return fmt.Sprintf("%04d-%02d-%02d", d.Year, int(d.Month), d.Day)
}

// 画面が送る書き方は、年月の入力欄と日付の入力欄が送る形の文字列と、空の文字列と null である。
var (
	screenYearMonth = regexp.MustCompile(`^(?:"[0-9]{4}-[0-9]{2}"|""|null)$`)
	screenDate      = regexp.MustCompile(`^(?:"[0-9]{4}-[0-9]{2}-[0-9]{2}"|""|null)$`)
)

// dateTest は、年月か日付の1つの書き方と、その答えである。
// cb は、Java 版と答えが違い、変えた動きの一覧に載せた番号である。
type dateTest struct {
	cb, input, want string
}

// yearMonthTests は、年月の書き方と答えである。年月は time.Parse の "2006-01" の形の文字列だけを読む。
var yearMonthTests = []dateTest{
	{"", "\"2024-01\"", "読めた 2024-01"},
	{"", "\"2024-1\"", "読めない"},
	{"", "\"2024-001\"", "読めない"},
	{"", "\"24-01\"", "読めない"},
	{"", "\"02024-01\"", "読めない"},
	{"", "\"+2024-01\"", "読めない"},
	{"", "\"-2024-01\"", "読めない"},
	{"CB-053", "\"+12024-01\"", "読めない"},
	{"", "\"12024-01\"", "読めない"},
	{"", "\"9999-12\"", "読めたが範囲の外"},
	{"CB-053", "\"0000-01\"", "読めたが範囲の外"},
	{"", "\"2024/01\"", "読めない"},
	{"", "\"202401\"", "読めない"},
	{"", "\"2024-01-15\"", "読めない"},
	{"", "\"2024-01-15T00:00:00\"", "読めない"},
	{"", "\"2024-01T00:00\"", "読めない"},
	{"", "\"2024-01+09:00\"", "読めない"},
	{"", "\"2024-01Z\"", "読めない"},
	{"", "\"2024-13\"", "読めない"},
	{"", "\"2024-00\"", "読めない"},
	{"", "\"1899-12\"", "読めたが範囲の外"},
	{"", "\"1900-01\"", "読めた 1900-01"},
	{"", "\"2100-12\"", "読めた 2100-12"},
	{"", "\"2101-01\"", "読めたが範囲の外"},
	{"CB-053", "\" 2024-01 \"", "読めない"},
	{"CB-053", "\"\\t2024-01\\n\"", "読めない"},
	{"", "\"\u30002024-01\"", "読めない"},
	{"CB-053", "\"2024-01 \"", "読めない"},
	{"", "\"2024- 01\"", "読めない"},
	{"", "\"２０２４-０１\"", "読めない"},
	{"", "\"2024-1-1\"", "読めない"},
	{"", "\"\"", "値が無い"},
	{"CB-053", "\"  \"", "読めない"},
	{"", "\"null\"", "読めない"},
	{"", "null", "値が無い"},
	{"CB-053", "[2024,1]", "読めない"},
	{"", "[2024,13]", "読めない"},
	{"CB-053", "[1899,12]", "読めない"},
	{"CB-053", "[2101,1]", "読めない"},
	{"", "[2024]", "読めない"},
	{"", "[2024,1,1]", "読めない"},
	{"CB-053", "[]", "読めない"},
	{"", "[\"2024\",\"1\"]", "読めない"},
	{"", "[\"2024\",1]", "読めない"},
	{"", "[\" 2024 \",1]", "読めない"},
	{"", "[2024.0,1]", "読めない"},
	{"", "[2024,1.5]", "読めない"},
	{"", "[2024,null]", "読めない"},
	{"", "[null,1]", "読めない"},
	{"", "[[2024],1]", "読めない"},
	{"", "202401", "読めない"},
	{"", "2024", "読めない"},
	{"", "0", "読めない"},
	{"", "-1", "読めない"},
	{"", "1.5", "読めない"},
	{"", "true", "読めない"},
	{"", "false", "読めない"},
	{"", "{}", "読めない"},
	{"", "{\"year\":2024,\"month\":1}", "読めない"},
	{"", "\"Invalid Date\"", "読めない"},
}

// dateTests は、日付の書き方と答えである。日付は time.Parse の "2006-01-02" の形の文字列だけを読む。
var dateTests = []dateTest{
	{"", "\"2024-01-15\"", "読めた 2024-01-15"},
	{"CB-053", "\" 2024-01-15 \"", "読めない"},
	{"CB-053", "\"\\t2024-01-15\\n\"", "読めない"},
	{"", "\"\u30002024-01-15\"", "読めない"},
	{"", "\"2024-1-15\"", "読めない"},
	{"", "\"2024-01-5\"", "読めない"},
	{"", "\"2024/01/15\"", "読めない"},
	{"", "\"20240115\"", "読めない"},
	{"", "\"2024-001\"", "読めない"},
	{"", "\"2024-W03-1\"", "読めない"},
	{"", "\"2024-02-29\"", "読めた 2024-02-29"},
	{"", "\"2023-02-29\"", "読めない"},
	{"", "\"2024-02-30\"", "読めない"},
	{"", "\"2024-04-31\"", "読めない"},
	{"", "\"2024-13-01\"", "読めない"},
	{"", "\"2024-00-10\"", "読めない"},
	{"", "\"2024-01-00\"", "読めない"},
	{"CB-053", "\"2024-01-15T10:00:00\"", "読めない"},
	{"CB-053", "\"2024-01-15T10:00\"", "読めない"},
	{"", "\"2024-01-15T10\"", "読めない"},
	{"", "\"2024-01-15T\"", "読めない"},
	{"", "\"2024-01-15T25:00\"", "読めない"},
	{"CB-053", "\"2024-01-15T10:00:00.123456789\"", "読めない"},
	{"", "\"2024-01-15T10:00:00.1234567891\"", "読めない"},
	{"CB-053", "\"2024-01-15T10:00:00Z\"", "読めない"},
	{"", "\"2024-01-15T10:00:00+09:00\"", "読めない"},
	{"", "\"2024-01-15+09:00\"", "読めない"},
	{"", "\"2024-01-15Z\"", "読めない"},
	{"", "\"2024-01-15t10:00\"", "読めない"},
	{"", "\"2024-01-15 10:00:00\"", "読めない"},
	{"", "\"2024-01\"", "読めない"},
	{"", "\"+2024-01-15\"", "読めない"},
	{"CB-053", "\"-2024-01-15\"", "読めない"},
	{"CB-053", "\"+12024-01-15\"", "読めない"},
	{"", "\"10000-01-01\"", "読めない"},
	{"", "\"1899-12-31\"", "読めたが範囲の外"},
	{"", "\"1900-01-01\"", "読めた 1900-01-01"},
	{"", "\"2100-12-31\"", "読めた 2100-12-31"},
	{"", "\"2101-01-01\"", "読めたが範囲の外"},
	{"", "\"２０２４-01-15\"", "読めない"},
	{"", "\"\"", "値が無い"},
	{"CB-053", "\"  \"", "読めない"},
	{"", "\"null\"", "読めない"},
	{"", "null", "値が無い"},
	{"CB-053", "[2024,1,15]", "読めない"},
	{"", "[2024,2,30]", "読めない"},
	{"CB-053", "[1899,12,31]", "読めない"},
	{"", "[2024,1]", "読めない"},
	{"", "[2024,1,15,0]", "読めない"},
	{"CB-053", "[]", "読めない"},
	{"", "[\"2024\",\"1\",\"15\"]", "読めない"},
	{"", "[2024,1,15.0]", "読めない"},
	{"CB-053", "19737", "読めない"},
	{"CB-053", "0", "読めない"},
	{"CB-053", "-1", "読めない"},
	{"CB-053", "-25567", "読めない"},
	{"CB-053", "73049", "読めない"},
	{"CB-053", "73050", "読めない"},
	{"", "\"19737\"", "読めない"},
	{"", "1.5", "読めない"},
	{"", "19737.0", "読めない"},
	{"", "1e3", "読めない"},
	{"", "true", "読めない"},
	{"", "{}", "読めない"},
	{"", "\"0000-01-15\"", "読めたが範囲の外"},
}

// checkDateTests は、表のすべての書き方で、read の答えが表の答えと同じになることと、
// cb のある書き方が、画面が送る書き方でないことを確かめる。screenDiff は、画面が送る書き方のうち、cb があってよい書き方である。
func checkDateTests(t *testing.T, tests []dateTest, read func(string) dateResult, screen *regexp.Regexp, screenDiff map[string]bool) {
	t.Helper()
	for _, tt := range tests {
		if got := read(tt.input).String(); got != tt.want {
			t.Errorf("書き方 %s: 答え %s, want %s", tt.input, got, tt.want)
		}
		if tt.cb != "" && screen.MatchString(tt.input) && !screenDiff[tt.input] {
			t.Errorf("書き方 %s は画面が送る書き方なのに、%s がある", tt.input, tt.cb)
		}
	}
}

// TestDates は、年月と日付の書き方の答えが表と同じになることと、
// Java 版と答えが違う書き方が、画面が送る書き方でないことを確かめる。
func TestDates(t *testing.T) {
	t.Run("年月", func(t *testing.T) {
		checkDateTests(t, yearMonthTests, func(input string) dateResult {
			var v jsonYearMonth
			err := json.Unmarshal([]byte(input), &v)
			return resultFromGo(err, v.Present, v.Value.Year, formatYearMonth(v.Value))
		}, screenYearMonth, map[string]bool{
			// 年が 0000 の年月は、Java 版が読めない値として断り、Go 版が読んで範囲の外として断る(CB-053)
			`"0000-01"`: true,
		})
		// 画面が年月の入力欄から送る Invalid Date は、Java 版と同じく読めない
		found := false
		for _, tt := range yearMonthTests {
			if tt.input == `"Invalid Date"` {
				found = true
				if tt.cb != "" || tt.want != "読めない" {
					t.Errorf(`年月の "Invalid Date" の答えが %s で、番号が %q である`, tt.want, tt.cb)
				}
			}
		}
		if !found {
			t.Error(`表に年月の "Invalid Date" が無い`)
		}
	})
	t.Run("日付", func(t *testing.T) {
		checkDateTests(t, dateTests, func(input string) dateResult {
			var v jsonDate
			err := json.Unmarshal([]byte(input), &v)
			return resultFromGo(err, v.Present, v.Value.Year, formatDate(v.Value))
		}, screenDate, nil)
	})
}

// dateDiffTable は、表の書き方のうち cb のある書き方と、その番号である。
func dateDiffTable(tests []dateTest) map[string]string {
	table := map[string]string{}
	for _, tt := range tests {
		if tt.cb != "" {
			table[tt.input] = tt.cb
		}
	}
	return table
}

// TestDates_DiffTableInChangedBehaviors は、年月と日付の表の番号が、変えた動きの一覧にあることを確かめる。
func TestDates_DiffTableInChangedBehaviors(t *testing.T) {
	t.Run("年月", func(t *testing.T) { checkDiffTableInChangedBehaviors(t, dateDiffTable(yearMonthTests)) })
	t.Run("日付", func(t *testing.T) { checkDiffTableInChangedBehaviors(t, dateDiffTable(dateTests)) })
}
