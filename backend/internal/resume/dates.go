package resume

import (
	"encoding/json"
	"errors"
	"time"
)

// 年月と日付の書式である。画面の年月の入力欄と日付の入力欄が送る形にあたる。
const (
	yearMonthLayout = "2006-01"
	dateLayout      = "2006-01-02"
)

// errDateNotString は、年月と日付の欄の値が文字列でないことである。
var errDateNotString = errors.New("年月と日付の欄の値は文字列で書く")

// jsonYearMonth は、要求の本文の年月の欄である。
// JSON の文字列を time.Parse の書式 2006-01 で読む。空の文字列と null と鍵が無いことは、値が無いことにする。
// 前後の空白は除かない。文字列でない値と、書式に合わない文字列は読めない。
type jsonYearMonth struct {
	Value YearMonth
	// Present は、値があることである。
	Present bool
}

// UnmarshalJSON は、年月の欄を読む。
func (v *jsonYearMonth) UnmarshalJSON(b []byte) error {
	*v = jsonYearMonth{}
	t, ok, err := parseDateString(b, yearMonthLayout)
	if err != nil || !ok {
		return err
	}
	*v = jsonYearMonth{Value: YearMonth{Year: t.Year(), Month: t.Month()}, Present: true}
	return nil
}

// jsonDate は、要求の本文の日付の欄である。
// JSON の文字列を time.Parse の書式 2006-01-02 で読む。空の文字列と null と鍵が無いことは、値が無いことにする。
// 前後の空白は除かない。文字列でない値と、書式に合わない文字列は読めない。
type jsonDate struct {
	Value Date
	// Present は、値があることである。
	Present bool
}

// UnmarshalJSON は、日付の欄を読む。
func (v *jsonDate) UnmarshalJSON(b []byte) error {
	*v = jsonDate{}
	t, ok, err := parseDateString(b, dateLayout)
	if err != nil || !ok {
		return err
	}
	*v = jsonDate{Value: Date{Year: t.Year(), Month: t.Month(), Day: t.Day()}, Present: true}
	return nil
}

// parseDateString は、JSON の値を、layout の書式の文字列として読む。
// null と空の文字列は、値が無いことにして ok を false で返す。
func parseDateString(b []byte, layout string) (t time.Time, ok bool, err error) {
	if string(b) == "null" {
		return time.Time{}, false, nil
	}
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return time.Time{}, false, errDateNotString
	}
	if s == "" {
		return time.Time{}, false, nil
	}
	t, err = time.Parse(layout, s)
	if err != nil {
		return time.Time{}, false, err
	}
	return t, true, nil
}
