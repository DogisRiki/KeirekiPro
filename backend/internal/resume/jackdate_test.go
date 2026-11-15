package resume

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"
)

// jackdateCase は、testdata/jackdate.json の1つの書き方と、Java 版の答えである。
type jackdateCase struct {
	Input  string `json:"input"`
	Status int    `json:"status"`
	Value  string `json:"value"`
	Body   struct {
		Errors  map[string][]string `json:"errors"`
		Message string              `json:"message"`
	} `json:"body"`
}

// jackdateExpect は、Java 版の答えから読み取った、読み手が返すべき結果である。
type jackdateExpect struct {
	state jackState
	// value は、Java 版が読んで答えに返した値である。state が jackRead で、範囲の中の値のときだけ持つ。
	value string
	// outOfRange は、Java 版が値を読み、入力の検査が範囲の外として断ったことである。
	outOfRange bool
}

// expectFromJava は、Java 版の答えを、読み手の結果に直す。
// invalid と required は、その欄の範囲の外の文言と、入力必須の文言である。
func expectFromJava(t *testing.T, c jackdateCase, invalid, required string) jackdateExpect {
	t.Helper()
	switch {
	case c.Status == 200 || c.Status == 201:
		return jackdateExpect{state: jackRead, value: c.Value}
	case c.Status != 400 || c.Body.Message != MessageInvalidInput:
		t.Fatalf("書き方 %s の Java 版の答え %d %q は、控えの形に無い", c.Input, c.Status, c.Body.Message)
	case len(c.Body.Errors) == 0:
		return jackdateExpect{state: jackUnreadable}
	}
	msgs := c.Body.Errors["date"]
	if len(c.Body.Errors) != 1 || len(msgs) != 1 {
		t.Fatalf("書き方 %s の Java 版の errors %v は、控えの形に無い", c.Input, c.Body.Errors)
	}
	switch msgs[0] {
	case required:
		return jackdateExpect{state: jackAbsent}
	case invalid:
		return jackdateExpect{state: jackRead, outOfRange: true}
	}
	t.Fatalf("書き方 %s の Java 版の文言 %q は、控えの形に無い", c.Input, msgs[0])
	return jackdateExpect{}
}

// checkJackResult は、読み手の結果が、Java 版の答えと合うかを確かめる。
func checkJackResult(t *testing.T, input string, year int, got string, state jackState, want jackdateExpect) {
	t.Helper()
	if state != want.state {
		t.Errorf("書き方 %s: 結果 = %d, want %d", input, state, want.state)
		return
	}
	if state != jackRead {
		return
	}
	if want.outOfRange {
		// Java 版の入力の検査は、1900年から2100年までを受ける
		if year >= 1900 && year <= 2100 {
			t.Errorf("書き方 %s: 読んだ値 %s は範囲の中にある。Java 版は範囲の外として断った", input, got)
		}
		return
	}
	if got != want.value {
		t.Errorf("書き方 %s: 読んだ値 = %s, want %s", input, got, want.value)
	}
}

func formatYearMonth(ym YearMonth) string {
	return fmt.Sprintf("%04d-%02d", ym.Year, int(ym.Month))
}

func formatDate(d Date) string {
	return fmt.Sprintf("%04d-%02d-%02d", d.Year, int(d.Month), d.Day)
}

// TestJackDate_MatchesJava は、小タスク1.1 で Java 版に送って控えた、すべての年月と日付の書き方で、
// 読み手が Java 版と同じ年月と日付を読むか、同じく読めないか、同じく値が無いとするかを確かめる。
func TestJackDate_MatchesJava(t *testing.T) {
	b, err := os.ReadFile("testdata/jackdate.json")
	if err != nil {
		t.Fatal(err)
	}
	var data struct {
		YearMonth []jackdateCase `json:"yearMonth"`
		Date      []jackdateCase `json:"date"`
	}
	if err := json.Unmarshal(b, &data); err != nil {
		t.Fatal(err)
	}
	if len(data.YearMonth) == 0 || len(data.Date) == 0 {
		t.Fatalf("控えの書き方が無い: 年月 %d 件、日付 %d 件", len(data.YearMonth), len(data.Date))
	}

	t.Run("年月", func(t *testing.T) {
		for _, c := range data.YearMonth {
			want := expectFromJava(t, c, MessageCertificationDateInvalid, MessageCertificationDateRequired)
			ym, state := jackYearMonth(json.RawMessage(c.Input))
			checkJackResult(t, c.Input, ym.Year, formatYearMonth(ym), state, want)
		}
	})

	t.Run("日付", func(t *testing.T) {
		for _, c := range data.Date {
			want := expectFromJava(t, c, MessageDateInvalid, MessageDateRequired)
			d, state := jackDate(json.RawMessage(c.Input))
			checkJackResult(t, c.Input, d.Year, formatDate(d), state, want)
		}
	})
}

// TestJackDate_JacksonEdgeCases は、控えに無い書き方の読み方を確かめる。期待する値は、2026-11-15 に、
// Java 版が動かしている jackson-databind 3.1.7 の JsonMapper で、要求の型と同じ注釈の型に読ませて確かめた値である。
func TestJackDate_JacksonEdgeCases(t *testing.T) {
	ymCases := []struct {
		input string
		want  *YearMonth
	}{
		{`"-12024-01"`, nil},
		{`"-02024-01"`, nil},
		{`"+0000000002024-01"`, &YearMonth{2024, time.January}},
		{`"+999999999-12"`, &YearMonth{999_999_999, time.December}},
		{`"+1000000000-01"`, nil},
		{`"+00002024-01"`, &YearMonth{2024, time.January}},
		{`[2147483648,1]`, nil},
		{`[-1,1]`, &YearMonth{-1, time.January}},
		{`[2024,-0]`, nil},
		{`[ 2024 , 1 ]`, &YearMonth{2024, time.January}},
		{`[0,1]`, &YearMonth{0, time.January}},
		{`[-2024,1]`, &YearMonth{-2024, time.January}},
		{`[999999999,12]`, &YearMonth{999_999_999, time.December}},
		{`[1000000000,1]`, nil},
	}
	for _, c := range ymCases {
		got, state := jackYearMonth(json.RawMessage(c.input))
		if c.want == nil {
			if state != jackUnreadable {
				t.Errorf("年月 %s: 結果 = %d %v, want 読めない", c.input, state, got)
			}
			continue
		}
		if state != jackRead || got != *c.want {
			t.Errorf("年月 %s: = %d %v, want %v", c.input, state, got, *c.want)
		}
	}

	dateCases := []struct {
		input string
		want  *Date
	}{
		{`"-12024-01-15"`, &Date{-12024, time.January, 15}},
		{`"-02024-01-15"`, &Date{-2024, time.January, 15}},
		{`"+0000002024-01-15"`, &Date{2024, time.January, 15}},
		{`"+00000002024-01-15"`, nil},
		{`"+999999999-12-31"`, &Date{999_999_999, time.December, 31}},
		{`"-999999999-01-01"`, &Date{-999_999_999, time.January, 1}},
		{`"-1000000000-01-01"`, nil},
		{`"2024-01-15T10:00:00."`, &Date{2024, time.January, 15}},
		{`"2024-01-15T24:00:00Z"`, nil},
		{`"2024-01-15T24:00:01Z"`, nil},
		{`"2024-01-15T23:59:60Z"`, nil},
		{`"2024-01-15T10:00Z"`, &Date{2024, time.January, 15}},
		{`"2024-01-15T10:00:00.123Z"`, &Date{2024, time.January, 15}},
		{`"2024-01-15T10:00:00.Z"`, &Date{2024, time.January, 15}},
		{`"2024-01-15T10:00:00.1234567891Z"`, nil},
		{`"+12024-01-15T10:00:00Z"`, nil},
		{`"-2024-01-15T10:00:00Z"`, nil},
		{`"2024-01-15TZ"`, nil},
		{`"2024-01-15T10:00:00+09:00Z"`, nil},
		{`"2024-01-15T10:00:60"`, nil},
		{`"2024-01-15T10:60"`, nil},
		{`"2024-02-30T10:00:00Z"`, nil},
		{`"2024-01-15T10:00:00ZZ"`, nil},
		{`"0000-01-01"`, &Date{0, time.January, 1}},
		{`"-0000-01-01"`, nil},
		{`365241780471`, &Date{999_999_999, time.December, 31}},
		{`365241780472`, nil},
		{`-365243219162`, &Date{-999_999_999, time.January, 1}},
		{`-365243219163`, nil},
		{`9223372036854775808`, nil},
		{`-0`, &Date{1970, time.January, 1}},
		{`[ 2024 , 1 , 15 ]`, &Date{2024, time.January, 15}},
		{`[2147483648,1,15]`, nil},
		{`[-1,1,1]`, &Date{-1, time.January, 1}},
		{`[2024,1,15,]`, nil},
		{`"2024-01-15T10:00:00.1234567890"`, nil},
		{`"  2024-01-15T10:00:00Z  "`, &Date{2024, time.January, 15}},
		{`"2024-01-15T00:00:00"`, &Date{2024, time.January, 15}},
	}
	for _, c := range dateCases {
		got, state := jackDate(json.RawMessage(c.input))
		if c.want == nil {
			if state != jackUnreadable {
				t.Errorf("日付 %s: 結果 = %d %v, want 読めない", c.input, state, got)
			}
			continue
		}
		if state != jackRead || got != *c.want {
			t.Errorf("日付 %s: = %d %v, want %v", c.input, state, got, *c.want)
		}
	}
}

// TestDateFromEpochDay は、1970年1月1日からの日数を日付に直す計算を、Go の time と比べて確かめる。
// 閏年の2月29日と、100年と400年の区切りの前後を含む。
func TestDateFromEpochDay(t *testing.T) {
	epoch := time.Date(1970, time.January, 1, 0, 0, 0, 0, time.UTC)
	for _, days := range []int64{-719_528, -719_469, -25_567, -1, 0, 59, 10_956, 11_016, 19_737, 47_540, 73_049, 2_932_896} {
		tm := epoch.AddDate(0, 0, int(days))
		want := Date{Year: tm.Year(), Month: tm.Month(), Day: tm.Day()}
		if got := dateFromEpochDay(days); got != want {
			t.Errorf("dateFromEpochDay(%d) = %v, want %v", days, got, want)
		}
	}
}
