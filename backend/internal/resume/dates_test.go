package resume

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"testing"
)

// datesCase は、testdata/dates.json の1つの書き方と、Java 版の答えである。
type datesCase struct {
	Input  string `json:"input"`
	Status int    `json:"status"`
	Value  string `json:"value"`
	Body   struct {
		Errors  map[string][]string `json:"errors"`
		Message string              `json:"message"`
	} `json:"body"`
}

// dateState は、1つの書き方を読んだ結果の種類である。
type dateState int

const (
	// dateRead は、値を読めたことである。
	dateRead dateState = iota
	// dateAbsent は、値が無いことである。Java 版は入力必須の文言で断る。
	dateAbsent
	// dateUnreadable は、値を読めないことである。Java 版は 400 と空の errors で断る。
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

// dateResult は、1つの書き方の答えである。Java 版の答えと Go 版の答えを、この形にそろえて比べる。
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

// resultFromJava は、Java 版の答えを、dateResult に直す。
// invalid と required は、その欄の範囲の外の文言と、入力必須の文言である。
func resultFromJava(t *testing.T, c datesCase, invalid, required string) dateResult {
	t.Helper()
	switch {
	case c.Status == 200 || c.Status == 201:
		return dateResult{state: dateRead, value: c.Value}
	case c.Status != 400 || c.Body.Message != MessageInvalidInput:
		t.Fatalf("書き方 %s の Java 版の答え %d %q は、控えの形に無い", c.Input, c.Status, c.Body.Message)
	case len(c.Body.Errors) == 0:
		return dateResult{state: dateUnreadable}
	}
	msgs := c.Body.Errors["date"]
	if len(c.Body.Errors) != 1 || len(msgs) != 1 {
		t.Fatalf("書き方 %s の Java 版の errors %v は、控えの形に無い", c.Input, c.Body.Errors)
	}
	switch msgs[0] {
	case required:
		return dateResult{state: dateAbsent}
	case invalid:
		return dateResult{state: dateRead, outOfRange: true}
	}
	t.Fatalf("書き方 %s の Java 版の文言 %q は、控えの形に無い", c.Input, msgs[0])
	return dateResult{}
}

// resultFromGo は、Go 版の読み方の結果を、dateResult に直す。
func resultFromGo(err error, present bool, year int, value string) dateResult {
	switch {
	case err != nil:
		return dateResult{state: dateUnreadable}
	case !present:
		return dateResult{state: dateAbsent}
	case year < 1900 || year > 2100:
		// Java 版と Go 版の入力の検査は、1900年から2100年までを受ける
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

// yearMonthDiffs は、年月の書き方のうち、Go 版の答えが Java 版と違う書き方と、違いを載せた一覧の番号である。
var yearMonthDiffs = map[string]string{
	`"+12024-01"`:   "CB-053",
	`"0000-01"`:     "CB-053",
	`" 2024-01 "`:   "CB-053",
	`"\t2024-01\n"`: "CB-053",
	`"2024-01 "`:    "CB-053",
	`"  "`:          "CB-053",
	`[2024,1]`:      "CB-053",
	`[1899,12]`:     "CB-053",
	`[2101,1]`:      "CB-053",
	`[]`:            "CB-053",
}

// dateDiffs は、日付の書き方のうち、Go 版の答えが Java 版と違う書き方と、違いを載せた一覧の番号である。
var dateDiffs = map[string]string{
	`" 2024-01-15 "`:                  "CB-053",
	`"\t2024-01-15\n"`:                "CB-053",
	`"2024-01-15T10:00:00"`:           "CB-053",
	`"2024-01-15T10:00"`:              "CB-053",
	`"2024-01-15T10:00:00.123456789"`: "CB-053",
	`"2024-01-15T10:00:00Z"`:          "CB-053",
	`"-2024-01-15"`:                   "CB-053",
	`"+12024-01-15"`:                  "CB-053",
	`"  "`:                            "CB-053",
	`[2024,1,15]`:                     "CB-053",
	`[1899,12,31]`:                    "CB-053",
	`[]`:                              "CB-053",
	`19737`:                           "CB-053",
	`0`:                               "CB-053",
	`-1`:                              "CB-053",
	`-25567`:                          "CB-053",
	`73049`:                           "CB-053",
	`73050`:                           "CB-053",
}

// 画面が送る書き方は、年月の入力欄と日付の入力欄が送る形の文字列と、空の文字列と null である。
var (
	screenYearMonth = regexp.MustCompile(`^(?:"[0-9]{4}-[0-9]{2}"|""|null)$`)
	screenDate      = regexp.MustCompile(`^(?:"[0-9]{4}-[0-9]{2}-[0-9]{2}"|""|null)$`)
)

func loadDatesCases(t *testing.T) (yearMonth, date []datesCase) {
	t.Helper()
	b, err := os.ReadFile("testdata/dates.json")
	if err != nil {
		t.Fatal(err)
	}
	var data struct {
		YearMonth []datesCase `json:"yearMonth"`
		Date      []datesCase `json:"date"`
	}
	if err := json.Unmarshal(b, &data); err != nil {
		t.Fatal(err)
	}
	if len(data.YearMonth) == 0 || len(data.Date) == 0 {
		t.Fatalf("控えの書き方が無い: 年月 %d 件、日付 %d 件", len(data.YearMonth), len(data.Date))
	}
	return data.YearMonth, data.Date
}

// checkAgainstJava は、1つの書き方の Go 版の答えを、Java 版の答えとテストの中の表と照らす。
// screen は、画面が送る書き方かどうかである。screenDiff は、画面が送る書き方のうち、表に載せてよい書き方である。
func checkAgainstJava(t *testing.T, input string, goRes, javaRes dateResult, diffs map[string]string, screen bool, screenDiff map[string]bool) {
	t.Helper()
	id, inTable := diffs[input]
	if goRes == javaRes {
		if inTable {
			t.Errorf("書き方 %s: Go 版の答えは Java 版と同じ %s なのに、表に %s がある", input, goRes, id)
		}
		return
	}
	if !inTable {
		t.Errorf("書き方 %s: Go 版の答え %s が Java 版の答え %s と違うのに、表に無い", input, goRes, javaRes)
		return
	}
	if screen && !screenDiff[input] {
		t.Errorf("書き方 %s は画面が送る書き方なのに、Go 版の答え %s が Java 版の答え %s と違う", input, goRes, javaRes)
	}
}

// TestDates_MatchesJava は、Java 版に送って testdata/dates.json に控えたすべての年月と日付の書き方で、
// 画面が送る書き方は Java 版と同じ答えになり、画面が送らない書き方で Java 版と違う答えになる書き方が、
// テストの中の表と合うことを確かめる。
func TestDates_MatchesJava(t *testing.T) {
	yearMonthCases, dateCases := loadDatesCases(t)

	t.Run("年月", func(t *testing.T) {
		seen := map[string]bool{}
		for _, c := range yearMonthCases {
			seen[c.Input] = true
			javaRes := resultFromJava(t, c, MessageCertificationDateInvalid, MessageCertificationDateRequired)
			var v jsonYearMonth
			err := json.Unmarshal([]byte(c.Input), &v)
			goRes := resultFromGo(err, v.Present, v.Value.Year, formatYearMonth(v.Value))
			// 年が 0000 の年月は、Java 版が読めない値として断り、Go 版が読んで範囲の外として断る(CB-053)
			checkAgainstJava(t, c.Input, goRes, javaRes, yearMonthDiffs,
				screenYearMonth.MatchString(c.Input), map[string]bool{`"0000-01"`: true})
		}
		// 画面が年月の入力欄から送る Invalid Date は、Java 版と同じく読めない
		if !seen[`"Invalid Date"`] {
			t.Error(`正解のファイルに年月の "Invalid Date" が無い`)
		}
		if _, ok := yearMonthDiffs[`"Invalid Date"`]; ok {
			t.Error(`年月の "Invalid Date" が表にある`)
		}
		for input := range yearMonthDiffs {
			if !seen[input] {
				t.Errorf("表の書き方 %s が、正解のファイルの年月に無い", input)
			}
		}
	})

	t.Run("日付", func(t *testing.T) {
		seen := map[string]bool{}
		for _, c := range dateCases {
			seen[c.Input] = true
			javaRes := resultFromJava(t, c, MessageDateInvalid, MessageDateRequired)
			var v jsonDate
			err := json.Unmarshal([]byte(c.Input), &v)
			goRes := resultFromGo(err, v.Present, v.Value.Year, formatDate(v.Value))
			checkAgainstJava(t, c.Input, goRes, javaRes, dateDiffs, screenDate.MatchString(c.Input), nil)
		}
		for input := range dateDiffs {
			if !seen[input] {
				t.Errorf("表の書き方 %s が、正解のファイルの日付に無い", input)
			}
		}
	})
}

// TestDates_DiffTableInChangedBehaviors は、年月と日付のテストの中の表の番号が、変えた動きの一覧にあることを確かめる。
func TestDates_DiffTableInChangedBehaviors(t *testing.T) {
	t.Run("年月", func(t *testing.T) { checkDiffTableInChangedBehaviors(t, yearMonthDiffs) })
	t.Run("日付", func(t *testing.T) { checkDiffTableInChangedBehaviors(t, dateDiffs) })
}
