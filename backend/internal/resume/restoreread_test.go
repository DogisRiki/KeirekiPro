package resume

import (
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"testing"
)

// 戻しの本文の読み手のテスト
//
// 期待する答えは、Java 版の Jackson(3.1.7)に同じ本文を RestoreResumeRequest として読ませた答えである(要件4の受入基準6)。
// 「ERR」は Java 版が読めなかった本文(400「入力エラーがあります。」で断る本文)、「nil」は値が無いこと、「OK」は読めたことである。
// 年月と日付は、Java 版の toString の形で比べる。YearMonth は 10000 年以上でも + を付けず、LocalDate は付ける。

// rsKindCase は、欄に置く値 in と、読んだ値を字にしたときに期待する字 want である。
type rsKindCase struct{ in, want string }

// readKindCases は、型紙 tmpl の @ を各場合の値に置き換えた本文を読み、show で読んだ値を字にして期待と比べる。
func readKindCases(t *testing.T, tmpl string, cases []rsKindCase, show func(f rsFile) string) {
	t.Helper()
	for _, c := range cases {
		body := strings.Replace(tmpl, "@", c.in, 1)
		got := "ERR"
		if f, ok := readRestoreFile([]byte(body)); ok {
			got = show(f)
		}
		if got != c.want {
			t.Errorf("readRestoreFile(%q) = %q, want %q", body, got, c.want)
		}
	}
}

const rsNoItem = "(項目が無い)"

// showCareer は、最初の職歴を show で字にする。
func showCareer(show func(c *rsCareer) string) func(f rsFile) string {
	return func(f rsFile) string {
		if f.resume == nil || len(f.resume.careers) == 0 || f.resume.careers[0] == nil {
			return rsNoItem
		}
		return show(f.resume.careers[0])
	}
}

// showProject は、最初のプロジェクトを show で字にする。
func showProject(show func(p *rsProject) string) func(f rsFile) string {
	return func(f rsFile) string {
		if f.resume == nil || len(f.resume.projects) == 0 || f.resume.projects[0] == nil {
			return rsNoItem
		}
		return show(f.resume.projects[0])
	}
}

func showString(s *string) string {
	if s == nil {
		return "nil"
	}
	return *s
}

// javaYear は、年 y を Java 版の java.time の toString の形で書く。plus は 10000 年以上に + を付けることである。
func javaYear(y int, plus bool) string {
	switch {
	case y < 0 && y > -1000:
		return fmt.Sprintf("-%04d", -y)
	case y >= 0 && y < 1000:
		return fmt.Sprintf("%04d", y)
	case y > 9999 && plus:
		return "+" + strconv.Itoa(y)
	default:
		return strconv.Itoa(y)
	}
}

func showYearMonth(v *YearMonth) string {
	if v == nil {
		return "nil"
	}
	return fmt.Sprintf("%s-%02d", javaYear(v.Year, false), int(v.Month))
}

func showDate(v *Date) string {
	if v == nil {
		return "nil"
	}
	return fmt.Sprintf("%s-%02d-%02d", javaYear(v.Year, true), int(v.Month), v.Day)
}

// showList は、字の並びを Java 版の List の toString の形で書く。
func showList(list []*string) string {
	items := make([]string, len(list))
	for i, s := range list {
		items[i] = "null"
		if s != nil {
			items[i] = *s
		}
	}
	return "[" + strings.Join(items, ", ") + "]"
}

func showOK(rsFile) string { return "OK" }

// TestReadRestoreFile_FieldKinds は、7つの種類の欄を、Java 版と同じ規則で読むことを確かめる(要件4の受入基準6)。
func TestReadRestoreFile_FieldKinds(t *testing.T) {
	t.Run("文字列", func(t *testing.T) {
		readKindCases(t, `{"resume":{"careers":[{"companyName":@}]}}`, []rsKindCase{
			{"\"x\"", "x"},
			{"123", "123"},
			{"-0", "-0"},
			{"1.50", "1.50"},
			{"1e3", "1e3"},
			{"1E3", "1E3"},
			{"-1.0e-5", "-1.0e-5"},
			{"true", "true"},
			{"false", "false"},
			{"null", "nil"},
			{"[]", "ERR"},
			{"[\"a\"]", "ERR"},
			{"{}", "ERR"},
			{"\"\"", ""},
			{"\"\ud7ff\"", "\ud7ff"},
			{"0", "0"},
			{"-0.0e+00", "-0.0e+00"},
			// 対になっていないサロゲートは、Go の文字列では WTF-8 の3バイトで持つ
			{`"a\ud800b"`, "a\xed\xa0\x80b"},
		}, showCareer(func(c *rsCareer) string { return showString(c.companyName) }))
		readKindCases(t, `{"version":"1.0","resume":{"resumeName":@}}`, []rsKindCase{
			{`"name"`, "name"}, {"12", "12"}, {"true", "true"}, {"null", "nil"}, {"[]", "ERR"}, {"{}", "ERR"},
		}, func(f rsFile) string { return showString(f.resume.name) })
		readKindCases(t, `{"version":@}`, []rsKindCase{
			{`"0.9"`, "0.9"}, {"{}", "ERR"}, {"null", "nil"},
		}, func(f rsFile) string { return showString(f.version) })
	})
	t.Run("真偽", func(t *testing.T) {
		readKindCases(t, `{"resume":{"careers":[{"active":@}]}}`, []rsKindCase{
			{"true", "true"},
			{"false", "false"},
			{"0", "false"},
			{"1", "true"},
			{"-0", "false"},
			{"-1", "true"},
			{"2", "true"},
			{"99999999999999999999", "true"},
			{"0.0", "ERR"},
			{"1.0", "ERR"},
			{"1e0", "ERR"},
			{"-0.0", "ERR"},
			{"null", "false"},
			{"\"true\"", "true"},
			{"\"True\"", "true"},
			{"\"TRUE\"", "true"},
			{"\"tRUE\"", "ERR"},
			{"\"false\"", "false"},
			{"\"False\"", "false"},
			{"\"FALSE\"", "false"},
			{"\"fALSE\"", "ERR"},
			{"\"\"", "false"},
			{"\" \"", "false"},
			{"\"\\t\"", "false"},
			{"\" true \"", "true"},
			{"\"\u3000true\"", "ERR"},
			{"\"null\"", "false"},
			{"\"NULL\"", "ERR"},
			{"\" null \"", "false"},
			{"\"0\"", "ERR"},
			{"\"1\"", "ERR"},
			{"\"yes\"", "ERR"},
			{"[]", "ERR"},
			{"[true]", "ERR"},
			{"{}", "ERR"},
			{"\"Null\"", "ERR"},
			{"\"\u00a0true\"", "ERR"},
			{"\"true\u0085\"", "ERR"},
		}, showCareer(func(c *rsCareer) string { return strconv.FormatBool(c.active) }))
	})
	t.Run("年月", func(t *testing.T) {
		readKindCases(t, `{"resume":{"careers":[{"startDate":@}]}}`, []rsKindCase{
			{"\"2015-04\"", "2015-04"},
			{"\"0000-04\"", "0000-04"},
			{"\"-0000-04\"", "ERR"},
			{"\"-0001-04\"", "-0001-04"},
			{"\"-1-04\"", "-0001-04"},
			{"\"1-04\"", "0001-04"},
			{"\"12016-04\"", "12016-04"},
			{"\"+12016-04\"", "ERR"},
			{"\"+2016-04\"", "ERR"},
			{"\"00002016-04\"", "2016-04"},
			{"\"999999999-12\"", "999999999-12"},
			{"\"1000000000-01\"", "ERR"},
			{"\"-999999999-01\"", "-999999999-01"},
			{"\"-1000000000-01\"", "ERR"},
			{"\"1234567890123456789-01\"", "ERR"},
			{"\"12345678901234567890-01\"", "ERR"},
			{"\"2015-4\"", "ERR"},
			{"\"2015-004\"", "ERR"},
			{"\"2015-+4\"", "ERR"},
			{"\"2015-13\"", "ERR"},
			{"\"2015-00\"", "ERR"},
			{"\" 2015-04 \"", "2015-04"},
			{"\"2015-04 \"", "2015-04"},
			{"\"2015-04x\"", "ERR"},
			{"\"2015/04\"", "ERR"},
			{"\"2015-04-01\"", "ERR"},
			{"\"\u30002015-04\"", "ERR"},
			{"\"2015-04T\"", "ERR"},
			{"\"-\"", "ERR"},
			{"\"2015-\"", "ERR"},
			{"\"\"", "nil"},
			{"\"  \"", "nil"},
			{"\"0-01\"", "0000-01"},
			{"\"00-01\"", "0000-01"},
			{"\"-00-01\"", "ERR"},
			{"\"-01-01\"", "-0001-01"},
			{"\"--01-01\"", "ERR"},
			{"\"2015--04\"", "ERR"},
			{"\"\uff12015-04\"", "ERR"},
			{"[2015,4]", "2015-04"},
			{"[2015,13]", "ERR"},
			{"[2015,0]", "ERR"},
			{"[2015]", "ERR"},
			{"[2015,4,1]", "ERR"},
			{"[\"2015\",4]", "ERR"},
			{"[2015,\"4\"]", "ERR"},
			{"[2015.0,4]", "ERR"},
			{"[2015,4.0]", "ERR"},
			{"[2147483648,4]", "ERR"},
			{"[999999999,12]", "999999999-12"},
			{"[1000000000,1]", "ERR"},
			{"[-999999999,1]", "-999999999-01"},
			{"[2015,-1]", "ERR"},
			{"[2015,null]", "ERR"},
			{"[null,4]", "ERR"},
			{"[]", "nil"},
			{"[[2015,4]]", "ERR"},
			{"[2015,[4]]", "ERR"},
			{"2015", "ERR"},
			{"true", "ERR"},
			{"{}", "ERR"},
			{"null", "nil"},
			{"[\"2015-04\"]", "ERR"},
			{"[-1000000000,1]", "ERR"},
			{"[-2147483648,1]", "ERR"},
			{"[2015,4,null]", "ERR"},
		}, showCareer(func(c *rsCareer) string { return showYearMonth(c.startDate) }))
	})
	t.Run("日付", func(t *testing.T) {
		readKindCases(t, `{"resume":{"date":@}}`, []rsKindCase{
			{"\"2026-02-05\"", "2026-02-05"},
			{"\"2026-02-05T10:00\"", "2026-02-05"},
			{"\"2026-02-05T10:00:00\"", "2026-02-05"},
			{"\"2026-02-05T10:00:00.\"", "2026-02-05"},
			{"\"2026-02-05T10:00:00.1234567891\"", "ERR"},
			{"\"2026-02-05T10:00:00Z\"", "2026-02-05"},
			{"\"2026-02-05T10:00:00z\"", "ERR"},
			{"\"2026-02-05t10:00\"", "ERR"},
			{"\"2026-02-05T24:00\"", "ERR"},
			{"\"2026-02-05T23:59:60\"", "ERR"},
			{"\"2026-02-05T10:00Z\"", "2026-02-05"},
			{"\"2026-02-05T10:00+09:00\"", "ERR"},
			{"\"2026-02-05TZ\"", "ERR"},
			{"\"2026-02-05T\"", "ERR"},
			{"\"2026-02-05Tx\"", "ERR"},
			{"\"+12026-02-05\"", "+12026-02-05"},
			{"\"12026-02-05\"", "ERR"},
			{"\"-12026-02-05\"", "-12026-02-05"},
			{"\"-2026-02-05\"", "-2026-02-05"},
			{"\"+2026-02-05\"", "ERR"},
			{"\"-0000-02-05\"", "ERR"},
			{"\"0000-02-05\"", "0000-02-05"},
			{"\"+0000-02-05\"", "ERR"},
			{"\"+00000-02-05\"", "0000-02-05"},
			{"\"+999999999-12-31\"", "+999999999-12-31"},
			{"\"+1000000000-01-01\"", "ERR"},
			{"\"-999999999-01-01\"", "-999999999-01-01"},
			{"\"-1000000000-01-01\"", "ERR"},
			{"\"2026-02-30\"", "ERR"},
			{"\"2024-02-29\"", "2024-02-29"},
			{"\"2023-02-29\"", "ERR"},
			{"\"2026-13-01\"", "ERR"},
			{"\"2026-00-01\"", "ERR"},
			{"\"2026-02-00\"", "ERR"},
			{"\" 2026-02-05 \"", "2026-02-05"},
			{"\"2026-02-05 \"", "2026-02-05"},
			{"\"2026-02-05x\"", "ERR"},
			{"\"+12026-02-05T10:00\"", "ERR"},
			{"\"2026-02-05T10:00:00.123Z\"", "2026-02-05"},
			{"\"2026-02-05T10:00:00.Z\"", "2026-02-05"},
			{"\"2026-02-05T10Z\"", "ERR"},
			{"\"\uff12026-02-05\"", "ERR"},
			{"\"2026-02-05T10:00:00.123456789\"", "2026-02-05"},
			{"\"2026-02-05T10:00:00ZZ\"", "ERR"},
			{"\"2026-02-05T10:00ZZ\"", "ERR"},
			{"\"-00001-01-01\"", "-0001-01-01"},
			{"\"-00000-01-01\"", "ERR"},
			{"\"+0001-01-01\"", "ERR"},
			{"\"-0001-01-01\"", "-0001-01-01"},
			{"\"-001-01-01\"", "ERR"},
			{"\"2026-02-05T10:0\"", "ERR"},
			{"\"2026-02-05T1:00\"", "ERR"},
			{"\"2026-02-05TT10:00\"", "ERR"},
			{"\"\"", "nil"},
			{"\"  \"", "nil"},
			{"\"2026-02-05 x\"", "ERR"},
			{"\"2026-02-05Tz\"", "ERR"},
			{"\"2026-02-05T10:00:00Z \"", "2026-02-05"},
			{"\"2026-02-05T10:00:00 Z\"", "ERR"},
			{"20489", "2026-02-05"},
			{"-1", "1969-12-31"},
			{"0", "1970-01-01"},
			{"365241780471", "+999999999-12-31"},
			{"365241780472", "ERR"},
			{"-365243219162", "-999999999-01-01"},
			{"-365243219163", "ERR"},
			{"9223372036854775807", "ERR"},
			{"9223372036854775808", "ERR"},
			{"1.0", "ERR"},
			{"1e3", "ERR"},
			{"-0", "1970-01-01"},
			{"[2026,2,5]", "2026-02-05"},
			{"[2026,2,30]", "ERR"},
			{"[2026,2]", "ERR"},
			{"[2026,2,5,1]", "ERR"},
			{"[2026,\"2\",5]", "ERR"},
			{"[2026.0,2,5]", "ERR"},
			{"[2147483648,1,1]", "ERR"},
			{"[999999999,12,31]", "+999999999-12-31"},
			{"[1000000000,1,1]", "ERR"},
			{"[-0,1,1]", "0000-01-01"},
			{"[2026,2,-0]", "ERR"},
			{"[]", "nil"},
			{"[null]", "ERR"},
			{"[[]]", "ERR"},
			{"{}", "ERR"},
			{"true", "ERR"},
			{"null", "nil"},
			{"[2026,2,5,null]", "ERR"},
			{"[2026,2,5", "ERR"},
			{"[\"2026-02-05\"]", "ERR"},
			{`"-999999999-01-01T00:00Z"`, "ERR"},
			{`"2026-02-5"`, "ERR"},
			{`"2026-02-05T10:00:5"`, "ERR"},
			{`"1-02-05"`, "ERR"},
			{`"1-02-05xyzT10:00"`, "ERR"},
		}, func(f rsFile) string { return showDate(f.resume.date) })
	})
	t.Run("書き出した時刻", func(t *testing.T) {
		readKindCases(t, `{"exportedAt":@}`, []rsKindCase{
			{"\"2026-02-05T01:00:00Z\"", "OK"},
			{"\"2026-02-05t01:00:00z\"", "OK"},
			{"\"2026-02-05T01:00:00+09:00\"", "OK"},
			{"\"2026-02-05T01:00:00-09:00\"", "OK"},
			{"\"2026-02-05T01:00:00+00:00\"", "OK"},
			{"\"2026-02-05T01:00:00-00:00\"", "OK"},
			{"\"2026-02-05T01:00:00+00\"", "OK"},
			{"\"2026-02-05T01:00:00+0000\"", "OK"},
			{"\"2026-02-05T01:00:00+09\"", "ERR"},
			{"\"2026-02-05T01:00:00+0900\"", "ERR"},
			{"\"2026-02-05T01:00:00+9:00\"", "ERR"},
			{"\"2026-02-05T01:00:00+09:00:30\"", "OK"},
			{"\"2026-02-05T01:00:00+09:00:3\"", "ERR"},
			{"\"2026-02-05T01:00:00+24:00\"", "ERR"},
			{"\"2026-02-05T01:00:00+23:59:59\"", "ERR"},
			{"\"2026-02-05T01:00:00-00\"", "ERR"},
			{"\"2026-02-05T01:00:00.Z\"", "OK"},
			{"\"2026-02-05T01:00:00.1234567891Z\"", "ERR"},
			{"\"2026-02-05T01:00:00.123456789Z\"", "OK"},
			{"\"2026-02-05T01:00Z\"", "ERR"},
			{"\"2026-02-05T24:00:00Z\"", "OK"},
			{"\"2026-02-05T24:00:01Z\"", "ERR"},
			{"\"2026-02-05T23:59:60Z\"", "OK"},
			{"\"2026-02-05T23:59:60.5Z\"", "OK"},
			{"\"2026-02-05T22:59:60Z\"", "ERR"},
			{"\"2026-02-29T00:00:00Z\"", "ERR"},
			{"\"2024-02-29T00:00:00Z\"", "OK"},
			{"\"+12026-02-05T01:00:00Z\"", "OK"},
			{"\"12026-02-05T01:00:00Z\"", "ERR"},
			{"\"-2026-02-05T01:00:00Z\"", "OK"},
			{"\"-12026-02-05T01:00:00Z\"", "OK"},
			{"\"+2026-02-05T01:00:00Z\"", "ERR"},
			{"\"-0000-02-05T01:00:00Z\"", "ERR"},
			{"\"0000-02-05T01:00:00Z\"", "OK"},
			{"\"+1000000000-12-31T23:59:59Z\"", "OK"},
			{"\"+1000000001-01-01T00:00:00Z\"", "ERR"},
			{"\"-1000000000-01-01T00:00:00Z\"", "OK"},
			{"\"-1000000001-12-31T23:59:59Z\"", "ERR"},
			{"\"+999999999-12-31T23:59:59.999999999Z\"", "OK"},
			{"\"2026-02-05 01:00:00Z\"", "ERR"},
			{"\"2026-02-05T01:00:00ZZ\"", "ERR"},
			{"\" 2026-02-05T01:00:00Z \"", "OK"},
			{"\"2026-2-05T01:00:00Z\"", "ERR"},
			{"\"2026-02-05T1:00:00Z\"", "ERR"},
			{"\"1770253200\"", "OK"},
			{"\"+1770253200\"", "OK"},
			{"\"-1770253200\"", "OK"},
			{"\"1770253200.5\"", "OK"},
			{"\"1.\"", "OK"},
			{"\".5\"", "OK"},
			{"\"-.5\"", "OK"},
			{"\"+.5\"", "OK"},
			{"\".\"", "ERR"},
			{"\"-\"", "ERR"},
			{"\"+\"", "ERR"},
			{"\"1.2.3\"", "ERR"},
			{"\"00012\"", "OK"},
			{"\"1e3\"", "ERR"},
			{"\"31556889864403199\"", "OK"},
			{"\"31556889864403200\"", "ERR"},
			{"\"-31557014167219200\"", "OK"},
			{"\"-31557014167219201\"", "ERR"},
			{"\"9223372036854775807\"", "ERR"},
			{"\"9223372036854775808\"", "ERR"},
			{"\"31556889864403199.999999999\"", "OK"},
			{"\"31556889864403199.9999999999\"", "OK"},
			{"\"-31557014167219200.5\"", "ERR"},
			{"\"-31557014167219199.5\"", "OK"},
			{"\"2026-02-05T01:00:00+00:00:00\"", "OK"},
			{"\"2026-02-05T01:00:00Z+00\"", "ERR"},
			{"\"2026-02-05T01:00:00+0\"", "ERR"},
			{"\"2026-02-05T01:00:00+000\"", "ERR"},
			{"\"2026-02-05T01:00:00+00:0\"", "ERR"},
			{"\"2026-02-05T01:00:60Z\"", "ERR"},
			{"\"2026-02-05T01:60:00Z\"", "ERR"},
			{"\"2026-02-05T01:00:00+00:00+00\"", "ERR"},
			{"\"2026-02-05T01:00:00-09:00+00\"", "ERR"},
			{"\"x+00\"", "ERR"},
			{"\"2026-02-05T01:00:00Z+0000\"", "ERR"},
			{"\"2026-02-05T01:00:00+01:00\"", "OK"},
			{"\"2026-02-05T01:00:00+18:00\"", "OK"},
			{"\"2026-02-05T01:00:00+18:01\"", "ERR"},
			{"\"2026-02-05T01:00:00.000000000+00:00\"", "OK"},
			{"\"-0\"", "OK"},
			{"\"+0\"", "OK"},
			{"\"-0.0\"", "OK"},
			{"\"0.\"", "OK"},
			{"\"1..\"", "ERR"},
			{"\"1.5.\"", "ERR"},
			{"1770253200", "OK"},
			{"-1770253200", "OK"},
			{"1770253200.5", "OK"},
			{"1e3", "OK"},
			{"1E+3", "OK"},
			{"1e64", "OK"},
			{"1e63", "ERR"},
			{"1e-10", "OK"},
			{"1e-9", "OK"},
			{"0.0", "OK"},
			{"-0.0", "OK"},
			{"1e19", "ERR"},
			{"1e20", "ERR"},
			{"31556889864403199", "OK"},
			{"31556889864403200", "ERR"},
			{"-31557014167219200", "OK"},
			{"-31557014167219201", "ERR"},
			{"9223372036854775807", "ERR"},
			{"9223372036854775808", "ERR"},
			{"18446744073709551616", "ERR"},
			{"18446744073709551616.5", "OK"},
			{"1.5e10", "OK"},
			{"-1.5", "OK"},
			{"31556889864403199.9999999999", "OK"},
			{"-31557014167219200.000000001", "ERR"},
			{"1e2147483647", "ERR"},
			{"1e-2147483647", "OK"},
			{"1e2147483648", "ERR"},
			{"0.1e-2147483647", "ERR"},
			{"123456789012345678901234567890.123", "ERR"},
			{"-9.3e18", "ERR"},
			{"9.3e18", "ERR"},
			{"4.2949672965", "OK"},
			{"12345678901234567890e-10", "OK"},
			{"true", "ERR"},
			{"false", "ERR"},
			{"[]", "ERR"},
			{"{}", "ERR"},
			{"null", "OK"},
			// 符号の付いた数だけの字は、時差を読む前に、秒の数として読む
			{`"+00"`, "OK"},
			{`"+0000"`, "OK"},
			{`"+12"`, "OK"},
			{`"-12"`, "OK"},
			{`"+0"`, "OK"},
			{`"2026-02-05T24:00:00.0Z"`, "OK"},
			{`"2026-02-05T24:00:00.1Z"`, "ERR"},
			{`"2026-02-05T01:00:00+01:00:00"`, "OK"},
			{`"2026-02-05T01:00:00+18:00:01"`, "ERR"},
			{`"2026-02-05T01:00:00-18:00"`, "OK"},
			{`"2026-02-05T01:00:00+00:60"`, "ERR"},
			{`"9999999999-12-31T23:59:59Z"`, "ERR"},
			{`"+9999999999-12-31T23:59:59Z"`, "ERR"},
			{"0e2147483647", "OK"},
			{"0e-2147483648", "ERR"},
			{"1e-2147483648", "ERR"},
			{"1e12345678901", "ERR"},
			{"1e0000000000000000005", "OK"},
			{"-0.5", "OK"},
			{"-31557014167219200.5e0", "ERR"},
			{"9223372036854775808.5", "ERR"},
			{"18446744073709551615.9", "OK"},
			// 字の時刻の数字の数は、数と同じく maxNumberLength(1000)までである
			{`"` + strings.Repeat("1", 1000) + `"`, "ERR"},
			{`"` + strings.Repeat("1", 1001) + `"`, "ERR"},
			{`"0.` + strings.Repeat("0", 998) + `"`, "OK"},
			{`"0.` + strings.Repeat("0", 999) + `"`, "ERR"},
			{`"-0.` + strings.Repeat("0", 998) + `"`, "ERR"},
		}, showOK)
	})
	t.Run("文字列の並び", func(t *testing.T) {
		readKindCases(t, `{"resume":{"projects":[{"techStack":{"frontend":{"languages":@}}}]}}`, []rsKindCase{
			{"null", "[]"},
			{"[]", "[]"},
			{"[\"a\",null,1,1.5,true,false]", "[a, null, 1, 1.5, true, false]"},
			{"[[\"a\"]]", "ERR"},
			{"[{}]", "ERR"},
			{"\"a\"", "ERR"},
			{"\"\"", "ERR"},
			{"1", "ERR"},
			{"true", "ERR"},
			{"{}", "ERR"},
			{"[[]]", "ERR"},
			{"[-0,1e3,1.50]", "[-0, 1e3, 1.50]"},
			{"[null]", "[null]"},
		}, showProject(func(p *rsProject) string { return showList(p.techStack.Frontend.Languages) }))
	})
	t.Run("オブジェクトの欄", func(t *testing.T) {
		readKindCases(t, `{"resume":{"projects":[{"process":@}]}}`, []rsKindCase{
			{"null", "false"},
			{"{}", "false"},
			{"{\"requirements\":1}", "true"},
			{"[]", "ERR"},
			{"\"\"", "ERR"},
			{"\"x\"", "ERR"},
			{"1", "ERR"},
			{"true", "ERR"},
			{"{\"requirements\":\"x\"}", "ERR"},
			{"{\"requirements\":null,\"basicDesign\":\"true\",\"x\":1}", "false"},
		}, showProject(func(p *rsProject) string { return strconv.FormatBool(p.process.Requirements) }))
		readKindCases(t, `{"resume":{"projects":[{"techStack":@}]}}`, []rsKindCase{
			{"null", "[]"},
			{"{}", "[]"},
			{"{\"frontend\":null}", "[]"},
			{"{\"frontend\":{}}", "[]"},
			{"{\"frontend\":[]}", "ERR"},
			{"{\"frontend\":\"\"}", "ERR"},
			{"\"\"", "ERR"},
			{"[]", "ERR"},
			{"{\"frontend\":{\"languages\":null}}", "[]"},
			{"{\"backend\":{\"languages\":[1]}}", "[]"},
			{"{\"tools\":{\"editors\":\"x\"}}", "ERR"},
			{"{\"x\":{}}", "[]"},
			{"{\"frontend\":{\"x\":[]}}", "[]"},
		}, showProject(func(p *rsProject) string { return showList(p.techStack.Frontend.Languages) }))
		readKindCases(t, `{"resume":@}`, []rsKindCase{
			{"null", "nil"}, {"{}", "OK"}, {"1", "ERR"}, {`""`, "ERR"}, {"[]", "ERR"},
		}, func(f rsFile) string {
			if f.resume == nil {
				return "nil"
			}
			return "OK"
		})
	})
}

// rsSectionNames は、経歴書の6つの欄の名前である。rsResume の持ち物の名前と同じにしてある。
var rsSectionNames = []string{"careers", "projects", "certifications", "portfolios", "snsPlatforms", "selfPromotions"}

// rsBadItem は、欄ごとの、Java 版が読めない項目である。
var rsBadItem = map[string]string{
	"careers":        `{"active":"x"}`,
	"projects":       `{"active":"x"}`,
	"certifications": `{"date":"x"}`,
	"portfolios":     `{"name":[]}`,
	"snsPlatforms":   `{"link":[]}`,
	"selfPromotions": `{"title":[]}`,
}

// section は、読んだ本文 f の経歴書の、名前 name の欄の並びである。
func section(f rsFile, name string) reflect.Value {
	return reflect.ValueOf(f.resume).Elem().FieldByName(name)
}

// checkEmptyTechStack は、技術スタックの35の小分類が、すべて空の並び(nil でない)であることを確かめる。
func checkEmptyTechStack(t *testing.T, categories reflect.Value, skip ...string) {
	t.Helper()
	n := 0
	for i := range categories.NumField() {
		category := categories.Field(i)
		for j := range category.NumField() {
			n++
			name := categories.Type().Field(i).Name + "." + category.Type().Field(j).Name
			if list := category.Field(j); !slices.Contains(skip, name) && (list.IsNil() || list.Len() != 0) {
				t.Errorf("techStack の %s = %v, want 空の並び", name, list)
			}
		}
	}
	if n != 35 {
		t.Errorf("techStack の小分類の数 = %d, want 35", n)
	}
}

// TestReadRestoreFile_Sections は、6つの欄の並びと項目の読み方を確かめる(要件2の受入基準2、要件4の受入基準6)。
func TestReadRestoreFile_Sections(t *testing.T) {
	for _, name := range rsSectionNames {
		t.Run(name, func(t *testing.T) {
			read := func(list string) (rsFile, bool) {
				return readRestoreFile([]byte(`{"resume":{"` + name + `":` + list + `}}`))
			}
			if f, ok := readRestoreFile([]byte(`{"resume":{}}`)); !ok || !section(f, name).IsNil() || f.nullElement {
				t.Errorf("無い欄: ok=%v, nil=%v, nullElement=%v, want true, true, false", ok, ok && section(f, name).IsNil(), f.nullElement)
			}
			if f, ok := read("null"); !ok || !section(f, name).IsNil() || f.nullElement {
				t.Errorf("null の欄: ok=%v, want 読めて値が無い", ok)
			}
			if f, ok := read("[]"); !ok || section(f, name).IsNil() || section(f, name).Len() != 0 || f.nullElement {
				t.Errorf("空の並び: ok=%v, want 読めて空の並び", ok)
			}
			if f, ok := read("[null]"); !ok || !f.nullElement || section(f, name).Len() != 1 || !section(f, name).Index(0).IsNil() {
				t.Errorf("null の要素: ok=%v, nullElement=%v, want true, true", ok, f.nullElement)
			}
			if f, ok := read("[{},null]"); !ok || !f.nullElement || section(f, name).Len() != 2 {
				t.Errorf("項目のあとの null の要素: ok=%v, nullElement=%v, want true, true", ok, f.nullElement)
			}
			if f, ok := read("[{}]"); !ok || f.nullElement {
				t.Errorf("欄が無い項目: ok=%v, nullElement=%v, want true, false", ok, f.nullElement)
			} else {
				checkEmptyItem(t, section(f, name).Index(0).Elem())
			}
			// null の要素があっても、項目を読めなければ、本文を読めない
			for _, list := range []string{
				"[null," + rsBadItem[name] + "]", "[" + rsBadItem[name] + ",null]",
				`[1]`, `[""]`, `["x"]`, `[[]]`, `[true]`, `{}`, `""`, `1`, `"x"`, `true`,
			} {
				if _, ok := read(list); ok {
					t.Errorf("readRestoreFile(%s の欄が %s) = 読めた, want 読めない", name, list)
				}
			}
		})
	}
	t.Run("経歴書と技術スタックの無い欄", readsAbsentFields)
}

// checkEmptyItem は、欄が1つも無い項目 item を、値が無い項目として読んだことを確かめる(要件2の受入基準2)。
func checkEmptyItem(t *testing.T, item reflect.Value) {
	t.Helper()
	for i := range item.NumField() {
		field, name := item.Field(i), item.Type().Field(i).Name
		switch {
		case field.Kind() == reflect.Pointer:
			if !field.IsNil() {
				t.Errorf("%s = %v, want nil", name, field)
			}
		case field.Kind() == reflect.Bool:
			if field.Bool() {
				t.Errorf("%s = true, want false", name)
			}
		case field.Type() == reflect.TypeFor[Process]():
			if !field.IsZero() {
				t.Errorf("%s = %v, want どの工程も false", name, field)
			}
		case field.Type() == reflect.TypeFor[TechStack]():
			checkEmptyTechStack(t, field)
		default:
			t.Errorf("%s の種類 %s を確かめていない", name, field.Type())
		}
	}
}

// readsAbsentFields は、経歴書と技術スタックの、無い欄と null の欄を値が無いとすることを確かめる(要件2の受入基準2)。
func readsAbsentFields(t *testing.T) {
	f, ok := readRestoreFile([]byte(`{}`))
	if !ok || f.version != nil || f.resume != nil || f.nullElement {
		t.Errorf("readRestoreFile({}) = %+v, %v, want 値が無い, true", f, ok)
	}
	f, ok = readRestoreFile([]byte(`{"resume":{}}`))
	if !ok || f.resume == nil {
		t.Fatalf("readRestoreFile({\"resume\":{}}) = %v, want 読めて経歴書がある", ok)
	}
	if r := f.resume; r.name != nil || r.date != nil || r.lastName != nil || r.firstName != nil {
		t.Errorf("欄の無い経歴書 = %+v, want 名前と日付と姓と名が nil", r)
	}
	for _, techStack := range []string{"null", "{}", `{"frontend":null}`, `{"frontend":{}}`, `{"x":{}}`} {
		f, ok := readRestoreFile([]byte(`{"resume":{"projects":[{"techStack":` + techStack + `}]}}`))
		if !ok {
			t.Errorf("techStack %s = 読めない, want 読める", techStack)
			continue
		}
		checkEmptyTechStack(t, reflect.ValueOf(f.resume.projects[0].techStack))
	}
	f, ok = readRestoreFile([]byte(`{"resume":{"projects":[{"techStack":{"backend":{"languages":[1]},"tools":{"editors":["vim",null]}}}]}}`))
	if !ok {
		t.Fatal("techStack の2つの小分類 = 読めない, want 読める")
	}
	ts := f.resume.projects[0].techStack
	if got := showList(ts.Backend.Languages) + showList(ts.Tools.Editors); got != "[1][vim, null]" {
		t.Errorf("techStack の2つの小分類 = %s, want [1][vim, null]", got)
	}
	checkEmptyTechStack(t, reflect.ValueOf(ts), "Backend.Languages", "Tools.Editors")
	f, ok = readRestoreFile([]byte(`{"resume":{"projects":[{"process":{"requirements":true,"maintenance":1,"systemTest":"TRUE"}}]}}`))
	if want := (Process{Requirements: true, Maintenance: true, SystemTest: true}); !ok || f.resume.projects[0].process != want {
		t.Errorf("process = %+v, %v, want %+v, true", f.resume, ok, want)
	}
}

// readsDuplicateKeys は、同じ名前の欄が2つある本文を、前の値も読み、あとの値を使って読むことを確かめる。
func readsDuplicateKeys(t *testing.T) {
	f, ok := readRestoreFile([]byte(`{"version":"0.9","version":"1.0"}`))
	if !ok || showString(f.version) != "1.0" {
		t.Errorf("version が2つ = %q, %v, want 1.0, true", showString(f.version), ok)
	}
	f, ok = readRestoreFile([]byte(`{"resume":{"careers":[null],"careers":[]},"version":"1.0"}`))
	if !ok || f.nullElement || f.resume.careers == nil || len(f.resume.careers) != 0 {
		t.Errorf("前の careers に null の要素 = nullElement %v, %v, want false, true", f.nullElement, ok)
	}
	for _, c := range []rsKindCase{
		{`{"version":{},"version":"1.0","resume":null}`, "ERR"},
		{`{"version":"1.0","version":{},"resume":null}`, "ERR"},
		{`{"exportedAt":"x","exportedAt":"2026-02-05T01:00:00Z","version":"1.0"}`, "ERR"},
		{`{"resume":1,"resume":{"resumeName":"a"},"version":"1.0"}`, "ERR"},
		{`{"resume":{"date":"x"},"resume":{"resumeName":"a"},"version":"1.0"}`, "ERR"},
		{`{"resume":{"careers":[1],"careers":[]},"version":"1.0"}`, "ERR"},
		{`{"resume":{"careers":[{"active":"x","active":true}]},"version":"1.0"}`, "ERR"},
		{`{"resume":{"projects":[{"techStack":{"frontend":{"languages":{},"languages":["a"]}}}]},"version":"1.0"}`, "ERR"},
		{`{"x":1,"x":{},"version":"1.0"}`, "OK"},
	} {
		readKindCases(t, "@", []rsKindCase{c}, showOK)
	}
}

// TestReadRestoreFile_Root は、一番外の値と、知らない欄と、数の長さと、同じ名前の欄の読み方を確かめ、
// Java 版の戻しの答えを控えた本文を Java 版と同じに読むことを確かめる(要件1の受入基準1、要件4の受入基準6)。
func TestReadRestoreFile_Root(t *testing.T) {
	readKindCases(t, "@", []rsKindCase{
		{`{}`, "OK"},
		{`  {}  `, "OK"},
		{"\ufeff{}", "OK"},
		{`{"version":null,"exportedAt":null,"resume":null}`, "OK"},
		// 最初の値のあとに続く字は読まない
		{`{} {"x":`, "OK"},
		{"{} " + strings.Repeat("1", 1001), "OK"},
		{`[] {}`, "ERR"},
		{`"x" {}`, "ERR"},
		{`[]`, "ERR"},
		{`"x"`, "ERR"},
		{`1`, "ERR"},
		{`null`, "ERR"},
		{``, "ERR"},
		{`{`, "ERR"},
		// 知らない欄は、どの深さでも読み飛ばす
		{`{"x":1,"version":"1.0"}`, "OK"},
		{`{"x":[1,{"a":"b"}],"resume":{"y":{"z":[]},"careers":[{"w":null}]}}`, "OK"},
		{`{"x":` + strings.Repeat("[", 400) + strings.Repeat("]", 400) + `}`, "OK"},
		// 知らない欄の数も、数字の数は maxNumberLength(1000)までである。小数点のあとと指数の数字も数える
		{`{"x":` + strings.Repeat("1", 1000) + `}`, "OK"},
		{`{"x":` + strings.Repeat("1", 1001) + `}`, "ERR"},
		{`{"x":1.` + strings.Repeat("1", 999) + `}`, "OK"},
		{`{"x":1.` + strings.Repeat("1", 1000) + `}`, "ERR"},
		{`{"x":1e` + strings.Repeat("1", 999) + `}`, "OK"},
		{`{"x":1.1e` + strings.Repeat("1", 999) + `}`, "ERR"},
	}, showOK)
	t.Run("同じ名前の欄", readsDuplicateKeys)
	t.Run("Java 版の答えを控えた本文", matchesJavaAnswers)
}

// matchesJavaAnswers は、Java 版の戻しの答えを控えた testdata/backup/restore.json の本文を読み、
// Java 版が 400「入力エラーがあります。」で断った本文だけを読めないとすることを確かめる(要件4の受入基準6)。
func matchesJavaAnswers(t *testing.T) {
	raw, err := os.ReadFile("testdata/backup/restore.json")
	if err != nil {
		t.Fatal(err)
	}
	var file struct {
		Cases []struct {
			Name     string `json:"name"`
			Body     string `json:"body"`
			Status   int    `json:"status"`
			Response string `json:"response"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		t.Fatal(err)
	}
	rejected := 0
	for _, c := range file.Cases {
		var response struct {
			Message string `json:"message"`
		}
		if err := json.Unmarshal([]byte(c.Response), &response); err != nil {
			t.Fatalf("%s の答え: %v", c.Name, err)
		}
		want := c.Status != 400 || response.Message != "入力エラーがあります。"
		if !want {
			rejected++
		}
		if _, ok := readRestoreFile([]byte(c.Body)); ok != want {
			t.Errorf("%s: readRestoreFile = %v, want %v(Java 版の答えは %d %s)", c.Name, ok, want, c.Status, response.Message)
		}
	}
	if len(file.Cases) != 423 || rejected != 113 {
		t.Errorf("場合の数 = %d、断った数 = %d, want 423, 113", len(file.Cases), rejected)
	}
}
