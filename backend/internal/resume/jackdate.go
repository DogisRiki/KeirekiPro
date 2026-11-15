package resume

import (
	"bytes"
	"encoding/json"
	"strconv"
	"strings"
	"time"
)

// jackState は、Java 版の Jackson の読み方で、年月か日付の欄の値を読んだ結果である。
type jackState int

const (
	// jackRead は、値を読めたことである。範囲(1900年から2100年)の検査は、入力の検査が受け持つ。
	jackRead jackState = iota
	// jackAbsent は、値が無いことである。null と、空白だけの文字列と、空の並びが当たる。
	jackAbsent
	// jackUnreadable は、値を読めないことである。Java 版は、400 と errors が空の答えを返す。
	jackUnreadable
)

const (
	// javaMaxYear は、java.time の年の上限である。下限はこの値の符号を変えた値である。
	javaMaxYear = 999_999_999
	// javaMinEpochDay と javaMaxEpochDay は、LocalDate.ofEpochDay が受ける日数の範囲である。
	javaMinEpochDay = -365_243_219_162
	javaMaxEpochDay = 365_241_780_471
)

// jackYearMonth は、年月の欄の JSON の値を、Java 版の要求の型の
// @JsonFormat(pattern = "yyyy-MM") の YearMonth と同じ規則で読む。
//   - 文字列: Java の String.trim と同じく前後の空白を除き、DateTimeFormatter.ofPattern("yyyy-MM") で読む。
//     年は紀元の年で、1 から 999999999 までである。4桁を超える年には + を付ける
//   - 並び: [年, 月] の2つの整数を読む。年は 0 と負の数も読む
//   - null と、空白だけの文字列と、空の並びは、値が無いことにする
//   - 数と真偽とオブジェクトは読めない
func jackYearMonth(raw json.RawMessage) (YearMonth, jackState) {
	v, ok := decodeJackValue(raw)
	if !ok {
		return YearMonth{}, jackUnreadable
	}
	switch x := v.(type) {
	case nil:
		return YearMonth{}, jackAbsent
	case string:
		s := javaTrim(x)
		if s == "" {
			return YearMonth{}, jackAbsent
		}
		ym, ok := parsePatternYearMonth(s)
		if !ok {
			return YearMonth{}, jackUnreadable
		}
		return ym, jackRead
	case []any:
		if len(x) == 0 {
			return YearMonth{}, jackAbsent
		}
		n, ok := jackInts(x, 2)
		if !ok || !validJavaYear(n[0]) || n[1] < 1 || n[1] > 12 {
			return YearMonth{}, jackUnreadable
		}
		return YearMonth{Year: int(n[0]), Month: time.Month(n[1])}, jackRead
	default:
		return YearMonth{}, jackUnreadable
	}
}

// jackDate は、日付の欄の JSON の値を、Java 版の LocalDate と同じ規則で読む。
//   - 文字列: Java の String.trim と同じく前後の空白を除く。11文字目が T なら日時として読み、日付だけを使う。
//     末尾が Z なら、Z を除いて日時として読む。ほかは DateTimeFormatter.ISO_LOCAL_DATE で読む
//   - 整数: 1970年1月1日からの日数として読む
//   - 並び: [年, 月, 日] の3つの整数を読む
//   - null と、空白だけの文字列と、空の並びは、値が無いことにする
//   - 小数の書き方の数と真偽とオブジェクトは読めない
func jackDate(raw json.RawMessage) (Date, jackState) {
	v, ok := decodeJackValue(raw)
	if !ok {
		return Date{}, jackUnreadable
	}
	switch x := v.(type) {
	case nil:
		return Date{}, jackAbsent
	case string:
		s := javaTrim(x)
		if s == "" {
			return Date{}, jackAbsent
		}
		d, ok := parseJackDateString(s)
		if !ok {
			return Date{}, jackUnreadable
		}
		return d, jackRead
	case json.Number:
		if !isJSONInteger(x) {
			return Date{}, jackUnreadable
		}
		days, err := strconv.ParseInt(string(x), 10, 64)
		if err != nil || days < javaMinEpochDay || days > javaMaxEpochDay {
			return Date{}, jackUnreadable
		}
		return dateFromEpochDay(days), jackRead
	case []any:
		if len(x) == 0 {
			return Date{}, jackAbsent
		}
		n, ok := jackInts(x, 3)
		if !ok || !validJavaYear(n[0]) || !validMonthDay(n[0], n[1], n[2]) {
			return Date{}, jackUnreadable
		}
		return Date{Year: int(n[0]), Month: time.Month(n[1]), Day: int(n[2])}, jackRead
	default:
		return Date{}, jackUnreadable
	}
}

// decodeJackValue は、1つの JSON の値を読む。数は、書き方のまま json.Number にする。
func decodeJackValue(raw json.RawMessage) (any, bool) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		return nil, false
	}
	return v, true
}

// jackInts は、並びの要素が want 個の整数であるときに、その整数を返す。
// Jackson の getIntValue と同じく、要素は小数の書き方を含まない数で、Java の int の範囲に収まらなければならない。
func jackInts(xs []any, want int) ([]int64, bool) {
	if len(xs) != want {
		return nil, false
	}
	out := make([]int64, want)
	for i, x := range xs {
		n, ok := x.(json.Number)
		if !ok || !isJSONInteger(n) {
			return nil, false
		}
		v, err := strconv.ParseInt(string(n), 10, 32)
		if err != nil {
			return nil, false
		}
		out[i] = v
	}
	return out, true
}

// isJSONInteger は、JSON の数の書き方が、小数点と指数を含まない整数の書き方であるかを返す。
func isJSONInteger(n json.Number) bool {
	return !strings.ContainsAny(string(n), ".eE")
}

// javaTrim は、Java の String.trim と同じく、前後から U+0020 以下の文字を除く。全角の空白は除かない。
func javaTrim(s string) string {
	return strings.TrimFunc(s, func(r rune) bool { return r <= ' ' })
}

// parsePatternYearMonth は、DateTimeFormatter.ofPattern("yyyy-MM") の既定の規則で、s の全体を読む。
func parsePatternYearMonth(s string) (YearMonth, bool) {
	year, rest, ok := parseJavaYear(s, 19)
	// yyyy は紀元の年なので、0 と負の数を受けない
	if !ok || year < 1 {
		return YearMonth{}, false
	}
	month, rest, ok := parseTwoDigitsAfter(rest, '-')
	if !ok || rest != "" || month < 1 || month > 12 {
		return YearMonth{}, false
	}
	return YearMonth{Year: int(year), Month: time.Month(month)}, true
}

// parseJackDateString は、Jackson の LocalDate の読み方で、前後の空白を除いた文字列を読む。
func parseJackDateString(s string) (Date, bool) {
	// Java は11文字目を UTF-16 の位置で調べる。読める書き方は ASCII の文字だけなので、ASCII でない文字を含む値は読めない
	for i := 0; i < len(s); i++ {
		if s[i] >= 0x80 {
			return Date{}, false
		}
	}
	if len(s) > 10 && s[10] == 'T' {
		return parseISOLocalDateTime(strings.TrimSuffix(s, "Z"))
	}
	d, rest, ok := parseISOLocalDate(s)
	if !ok || rest != "" {
		return Date{}, false
	}
	return d, true
}

// parseISOLocalDateTime は、DateTimeFormatter.ISO_LOCAL_DATE_TIME で s の全体を読み、日付だけを返す。
// 時刻は、時と分を必ず読み、秒と、0桁から9桁の秒の端数を読む。
func parseISOLocalDateTime(s string) (Date, bool) {
	d, rest, ok := parseISOLocalDate(s)
	if !ok || rest == "" || rest[0] != 'T' {
		return Date{}, false
	}
	hour, rest, ok := parseTwoDigitsAfter(rest, 'T')
	if !ok || hour > 23 {
		return Date{}, false
	}
	minute, rest, ok := parseTwoDigitsAfter(rest, ':')
	if !ok || minute > 59 {
		return Date{}, false
	}
	if rest == "" {
		return d, true
	}
	second, rest, ok := parseTwoDigitsAfter(rest, ':')
	if !ok || second > 59 {
		return Date{}, false
	}
	if rest == "" {
		return d, true
	}
	if rest[0] != '.' {
		return Date{}, false
	}
	// 秒の端数は、小数点のあとに0桁から9桁の数字である
	frac := rest[1:]
	if len(frac) > 9 || strings.TrimLeft(frac, "0123456789") != "" {
		return Date{}, false
	}
	return d, true
}

// parseISOLocalDate は、DateTimeFormatter.ISO_LOCAL_DATE で s の先頭の日付を読み、残りを返す。
func parseISOLocalDate(s string) (Date, string, bool) {
	year, rest, ok := parseJavaYear(s, 10)
	if !ok || !validJavaYear(year) {
		return Date{}, "", false
	}
	month, rest, ok := parseTwoDigitsAfter(rest, '-')
	if !ok {
		return Date{}, "", false
	}
	day, rest, ok := parseTwoDigitsAfter(rest, '-')
	if !ok || !validMonthDay(year, int64(month), int64(day)) {
		return Date{}, "", false
	}
	return Date{Year: int(year), Month: time.Month(month), Day: day}, rest, true
}

// parseJavaYear は、DateTimeFormatter の appendValue(年, 4, maxWidth, SignStyle.EXCEEDS_PAD) を
// 厳密な規則で読むのと同じく、s の先頭の年を読み、残りを返す。
//   - 符号が無いときは、ちょうど4桁を読む
//   - + のあとは、5桁から maxWidth 桁を読む
//   - - のあとは、4桁から maxWidth 桁を読む。値が 0 の年は読まない
//
// 値が java.time の年の範囲を超えるときも読めないことにする。超えた値は、どの欄でも読めないためである。
func parseJavaYear(s string, maxWidth int) (int64, string, bool) {
	var sign byte
	if s != "" && (s[0] == '+' || s[0] == '-') {
		sign = s[0]
		s = s[1:]
	}
	n := 0
	for n < len(s) && n < maxWidth && isASCIIDigit(s[n]) {
		n++
	}
	switch sign {
	case '+':
		if n <= 4 {
			return 0, "", false
		}
	case '-':
		if n < 4 {
			return 0, "", false
		}
	default:
		if n != 4 {
			return 0, "", false
		}
	}
	digits := strings.TrimLeft(s[:n], "0")
	if len(digits) > 9 {
		return 0, "", false
	}
	var year int64
	if digits != "" {
		year, _ = strconv.ParseInt(digits, 10, 64)
	}
	if sign == '-' {
		if year == 0 {
			return 0, "", false
		}
		year = -year
	}
	return year, s[n:], true
}

// parseTwoDigitsAfter は、s が区切りの文字 sep と2桁の数字で始まるときに、その数と残りを返す。
func parseTwoDigitsAfter(s string, sep byte) (int, string, bool) {
	if len(s) < 3 || s[0] != sep || !isASCIIDigit(s[1]) || !isASCIIDigit(s[2]) {
		return 0, "", false
	}
	return int(s[1]-'0')*10 + int(s[2]-'0'), s[3:], true
}

func isASCIIDigit(c byte) bool {
	return '0' <= c && c <= '9'
}

// validJavaYear は、年が java.time の年の範囲に収まるかを返す。
func validJavaYear(year int64) bool {
	return -javaMaxYear <= year && year <= javaMaxYear
}

// validMonthDay は、月と日が、その年の暦にある日かを返す。Java の IsoChronology と同じく、先発グレゴリオ暦で数える。
func validMonthDay(year, month, day int64) bool {
	if month < 1 || month > 12 || day < 1 {
		return false
	}
	return day <= monthLength(year, time.Month(month))
}

// monthLength は、その年の月の日数を返す。
func monthLength(year int64, month time.Month) int64 {
	switch month {
	case time.February:
		if isJavaLeapYear(year) {
			return 29
		}
		return 28
	case time.April, time.June, time.September, time.November:
		return 30
	default:
		return 31
	}
}

// isJavaLeapYear は、IsoChronology.isLeapYear の写しである。負の年も同じ規則で数える。
func isJavaLeapYear(year int64) bool {
	return year%4 == 0 && (year%100 != 0 || year%400 == 0)
}

// dateFromEpochDay は、LocalDate.ofEpochDay の写しである。days は javaMinEpochDay から javaMaxEpochDay までとする。
func dateFromEpochDay(days int64) Date {
	const (
		daysPerCycle   = 146_097
		days0000To1970 = daysPerCycle*5 - (30*365 + 7)
	)
	zeroDay := days + days0000To1970 - 60 // 3月1日から数える
	var adjust int64
	if zeroDay < 0 {
		adjustCycles := (zeroDay+1)/daysPerCycle - 1
		adjust = adjustCycles * 400
		zeroDay += -adjustCycles * daysPerCycle
	}
	yearEst := (400*zeroDay + 591) / daysPerCycle
	doyEst := zeroDay - (365*yearEst + yearEst/4 - yearEst/100 + yearEst/400)
	if doyEst < 0 {
		yearEst--
		doyEst = zeroDay - (365*yearEst + yearEst/4 - yearEst/100 + yearEst/400)
	}
	yearEst += adjust
	marchDoy0 := doyEst
	marchMonth0 := (marchDoy0*5 + 2) / 153
	month := (marchMonth0+2)%12 + 1
	dom := marchDoy0 - (marchMonth0*306+5)/10 + 1
	yearEst += marchMonth0 / 10
	return Date{Year: int(yearEst), Month: time.Month(month), Day: int(dom)}
}
