package httpapi

import (
	"errors"
	"fmt"
	"strings"
	"testing"
)

// multipartWant は、テストで確かめる部分の値である。
type multipartWant struct {
	FieldName   string
	FileName    string
	HasFileName bool
	Body        string
}

// summarizeParts は、部分のうちテストで確かめる値を取り出す。
func summarizeParts(parts []multipartPart) []multipartWant {
	got := make([]multipartWant, 0, len(parts))
	for _, p := range parts {
		got = append(got, multipartWant{FieldName: p.FieldName, FileName: p.FileName, HasFileName: p.HasFileName, Body: string(p.Body)})
	}
	return got
}

// assertParts は、parseMultipart が誤り無しに want の部分を返すことを確かめる。
func assertParts(t *testing.T, contentType, body string, want []multipartWant) []multipartPart {
	t.Helper()
	parts, err := parseMultipart(contentType, []byte(body))
	if err != nil {
		t.Fatalf("parseMultipart の誤り: %v", err)
	}
	got := summarizeParts(parts)
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Errorf("parseMultipart = %+v, want %+v", got, want)
	}
	return parts
}

const multipartCT = "multipart/form-data; boundary=AB"

// TestMultipart_ControlCharInHeader は、部分の見出しに制御文字があっても、Tomcat と同じく読むことを確かめる。
// Go の標準の mime/multipart は、この本文の全体を誤りにする(research.md の試作の記録の P4)。
func TestMultipart_ControlCharInHeader(t *testing.T) {
	body := "--AB\r\n" +
		"Content-Disposition: form-data; name=\"im\x01age\"; filename=\"a\x07b.png\"\r\n" +
		"X-Ctrl: a\x00\x1b[31m\x7f\r\n" +
		"\x01Content-Type:\x02 image/png\x03\r\n" +
		"\r\n" +
		"PNG\r\n" +
		"--AB--\r\n"
	parts := assertParts(t, multipartCT, body, []multipartWant{{FieldName: "im\x01age", FileName: "a\x07b.png", HasFileName: true, Body: "PNG"}})
	h := parts[0].Headers
	if v, ok := h.get("x-ctrl"); !ok || v != "a\x00\x1b[31m\x7f" {
		t.Errorf("X-Ctrl = %q, %v", v, ok)
	}
	// 見出しの名前と値の前後の制御文字は、Java の trim で除く
	if v, ok := h.get("CONTENT-TYPE"); !ok || v != "image/png" {
		t.Errorf("Content-Type = %q, %v", v, ok)
	}
}

// TestMultipart_Malformed は、Tomcat 11.0.27 が例外を投げる本文で、誤りを返すことを確かめる。
// どの本文も、Tomcat の FileUpload に同じ上限を渡して例外になることを確かめた。
// ただし、Shift_JIS と EUC-KR の文字コードの名前を使う5つの本文は、Tomcat は解いて受け付け、Go 版はわざと誤りにする(research.md の試作の記録の P4)。
func TestMultipart_Malformed(t *testing.T) {
	part := func(cd, body string) string {
		return "--AB\r\nContent-Disposition: " + cd + "\r\n\r\n" + body + "\r\n"
	}
	many := strings.Repeat(part("form-data; name=a", "x"), multipartMaxPartCount+1) + "--AB--"
	tests := []struct {
		name        string
		contentType string
		body        string
	}{
		{name: "multipart でない", contentType: "text/plain; boundary=AB", body: "--AB--"},
		{name: "境界の文字列が無い", contentType: "multipart/form-data", body: "--AB--"},
		{name: "境界の文字列が空", contentType: `multipart/form-data; boundary=""`, body: "--AB--"},
		{name: "境界の文字列に値が無い", contentType: "multipart/form-data; boundary", body: "--AB--"},
		{name: "境界の文字列が長すぎる", contentType: "multipart/form-data; boundary=" + strings.Repeat("b", tomcatBufferSize-4), body: "--AB--"},
		{name: "見出しの途中で終わる", contentType: multipartCT, body: "--AB\r\nContent-Disposition: form-data; name=a\r\n"},
		{name: "見出しが長すぎる", contentType: multipartCT, body: "--AB\r\nX: " + strings.Repeat("a", multipartMaxPartHeaderSize) + "\r\n\r\n\r\n--AB--"},
		{name: "中身の途中で終わる", contentType: multipartCT, body: part("form-data; name=a", "x")[:len(part("form-data; name=a", "x"))-2]},
		{name: "名前の無い部分の中身の途中で終わる", contentType: multipartCT, body: "--AB\r\nX: y\r\n\r\nbody"},
		{name: "部分が多すぎる", contentType: multipartCT, body: many},
		{name: "ファイルの名前に NUL", contentType: multipartCT, body: part("form-data; name=a; filename=\"x\x00.png\"", "x") + "--AB--"},
		{name: "Content-Length が上限を超える", contentType: multipartCT, body: "--AB\r\nContent-Disposition: form-data; name=a\r\nContent-Length: 2097153\r\n\r\nx\r\n--AB--"},
		{name: "中身が上限を超える", contentType: multipartCT, body: part("form-data; name=a", strings.Repeat("x", multipartMaxFileSize+1)) + "--AB--"},
		{name: "multipart/mixed に境界の文字列が無い", contentType: multipartCT, body: "--AB\r\nContent-Disposition: form-data; name=a\r\nContent-Type: multipart/mixed\r\n\r\n--AB--"},
		{name: "multipart/mixed の境界の文字列の長さが違う", contentType: multipartCT, body: "--AB\r\nContent-Disposition: form-data; name=a\r\nContent-Type: multipart/mixed; boundary=CDE\r\n\r\n--AB--"},
		{name: "本文の終わりのあとをさらに読む", contentType: multipartCT, body: "--AB\r\nContent-Disposition: form-data; name=a\r\nContent-Type: multipart/mixed; boundary=CD\r\n\r\n--CD"},
		{name: "RFC 2047 の B の誤り", contentType: multipartCT, body: part(`form-data; name="=?UTF-8?B?QQ=?="`, "x") + "--AB--"},
		{name: "RFC 2047 の読まない文字コード", contentType: multipartCT, body: part(`form-data; name="=?Shift_JIS?B?QQ==?="`, "x") + "--AB--"},
		{name: "RFC 2231 の読まない文字コード", contentType: multipartCT, body: part(`form-data; name*=Shift_JIS''a`, "x") + "--AB--"},
		{name: "境界の文字列の RFC 2047 の誤り", contentType: `multipart/form-data; boundary="=?UTF-8?B?QQ=?="`, body: "--AB--"},
		{name: "見出しの名前の RFC 2047 の誤り", contentType: multipartCT, body: part(`form-data; name=a; filename="=?UTF-8?B?QQ=?="`, "x") + "--AB--"},
		{name: "multipart/mixed の境界の文字列の誤り", contentType: multipartCT, body: "--AB\r\nContent-Disposition: form-data; name=a\r\nContent-Type: multipart/mixed; boundary==?UTF-8?B?QQ=?=\r\n\r\n--AB--"},
		{name: "RFC 2047 のケルビンの記号を k として読む", contentType: multipartCT, body: part("form-data; name=\"=?euc-Kr?B?QQ==?=\"", "x") + "--AB--"},
		{name: "Content-Length の全角の数字", contentType: multipartCT, body: "--AB\r\nContent-Disposition: form-data; name=a\r\nContent-Length: ９９９９９９９９\r\n\r\nx\r\n--AB--"},
		{name: "外の部分のファイルの名前の誤り", contentType: multipartCT, body: part(`form-data; name=a; filename*=Shift_JIS''a`, "x") + "--AB--"},
		{name: "中の部分のファイルの名前の誤り", contentType: multipartCT, body: "--AB\r\nContent-Disposition: form-data; name=a\r\nContent-Type: multipart/mixed; boundary=CD\r\n\r\n--CD\r\nContent-Disposition: attachment; filename*=Shift_JIS''a\r\n\r\nx\r\n--CD--\r\n--AB--"},
		{name: "中の部分の中身の途中で終わる", contentType: multipartCT, body: "--AB\r\nContent-Disposition: form-data; name=a\r\nContent-Type: multipart/mixed; boundary=CD\r\n\r\n--CD\r\nContent-Disposition: attachment; filename=f\r\n\r\nx"},
		{name: "中の部分の見出しの途中で終わる", contentType: multipartCT, body: "--AB\r\nContent-Disposition: form-data; name=a\r\nContent-Type: multipart/mixed; boundary=CD\r\n\r\n--CD\r\nX: y"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parts, err := parseMultipart(tt.contentType, []byte(tt.body))
			if !errors.Is(err, errMultipart) {
				t.Errorf("parseMultipart の誤り = %v (部分 %d 個), want errMultipart", err, len(parts))
			}
		})
	}
}

// TestMultipart_Parse は、Tomcat 11.0.27 の FileUpload が誤りにせずに読む本文で、同じ部分を返すことを確かめる。
// 期待する値は、同じ本文を Tomcat の FileUpload に渡して確かめた。
func TestMultipart_Parse(t *testing.T) {
	tests := []struct {
		name        string
		contentType string
		body        string
		want        []multipartWant
	}{
		{name: "空の本文", contentType: multipartCT, body: "", want: []multipartWant{}},
		{name: "境界の文字列が無い本文", contentType: multipartCT, body: "hello", want: []multipartWant{}},
		{name: "最後の境界だけ", contentType: multipartCT, body: "--AB--", want: []multipartWant{}},
		{
			name: "前置きと後置きを捨てる", contentType: multipartCT,
			body: "preamble\r\n--AB\r\nContent-Disposition: form-data; name=a\r\n\r\n1\r\n--AB--\r\nepilogue",
			want: []multipartWant{{FieldName: "a", Body: "1"}},
		},
		{
			name: "LF だけの改行のあとも読む", contentType: multipartCT,
			body: "--AB\nContent-Disposition: form-data; name=a\r\n\r\n1\r\n--AB\nContent-Disposition: form-data; name=b\r\n\r\n2\r\n--AB--",
			want: []multipartWant{{FieldName: "a", Body: "1"}, {FieldName: "b", Body: "2"}},
		},
		{
			name: "境界のあとの崩れで読み終える", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=a\r\n\r\n1\r\n--ABxx\r\nContent-Disposition: form-data; name=b\r\n\r\n2\r\n--AB--",
			want: []multipartWant{{FieldName: "a", Body: "1"}},
		},
		{
			name: "最後の境界のすぐあとで終わる", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=a\r\n\r\n1\r\n--AB",
			want: []multipartWant{{FieldName: "a", Body: "1"}},
		},
		{
			name: "最後の境界の CR のあとで終わる", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=a\r\n\r\n1\r\n--AB\r",
			want: []multipartWant{{FieldName: "a", Body: "1"}},
		},
		{
			name: "名前の無い部分を飛ばす", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: attachment; name=a\r\n\r\n1\r\n--AB\r\nX: y\r\n\r\n2\r\n--AB\r\nContent-Disposition: form-data; name=\"\"\r\n\r\n3\r\n--AB\r\nContent-Disposition: form-data; name=c\r\n\r\n4\r\n--AB--",
			want: []multipartWant{{FieldName: "c", Body: "4"}},
		},
		{
			name: "名前とファイルの名前の前後の空白を除く", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: FORM-DATA; name=\" a \"; FILENAME=\" f.png \"\r\n\r\n1\r\n--AB--",
			want: []multipartWant{{FieldName: "a", FileName: "f.png", HasFileName: true, Body: "1"}},
		},
		{
			name: "値の無い filename は空の名前", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=a; filename\r\n\r\n1\r\n--AB\r\nContent-Disposition: form-data; name=b; filename=\"\"\r\n\r\n2\r\n--AB--",
			want: []multipartWant{{FieldName: "a", HasFileName: true, Body: "1"}, {FieldName: "b", HasFileName: true, Body: "2"}},
		},
		{
			name: "あとの name が勝つ", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=a; name=b\r\n\r\n1\r\n--AB--",
			want: []multipartWant{{FieldName: "b", Body: "1"}},
		},
		{
			name: "あとの値の無い name で名前が消える", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=a; name\r\n\r\n1\r\n--AB--",
			want: []multipartWant{},
		},
		{
			name: "引用符の中の区切りと逃がした引用符", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=\"a;\\\"b\"\r\n\r\n1\r\n--AB--",
			want: []multipartWant{{FieldName: `a;\"b`, Body: "1"}},
		},
		{
			name: "見出しの続きの行をつなぐ", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data;\r\n \t name=a;\r\n\tfilename=f\r\nbroken line\r\n\r\n1\r\n--AB--",
			want: []multipartWant{{FieldName: "a", FileName: "f", HasFileName: true, Body: "1"}},
		},
		{
			name: "CR CR LF CR LF を見出しの終わりにしない", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=a\r\r\n\r\n\r\n1\r\n--AB--",
			want: []multipartWant{{FieldName: "a", Body: "1"}},
		},
		{
			name: "見出しの UTF-8", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=\"画\xff\"\r\n\r\n1\r\n--AB--",
			want: []multipartWant{{FieldName: "画�", Body: "1"}},
		},
		{
			name: "中身の CR LF と境界に似た並びを残す", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=a\r\n\r\n\r\n--A\r\n-AB\n--AB\r\n\r\n--AB--",
			want: []multipartWant{{FieldName: "a", Body: "\r\n--A\r\n-AB\n--AB\r\n"}},
		},
		{
			name: "Content-Length は中身を決めない", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=a\r\nContent-Length: 1\r\n\r\n123\r\n--AB\r\nContent-Disposition: form-data; name=b\r\nContent-Length: 9999999x\r\n\r\n4\r\n--AB--",
			want: []multipartWant{{FieldName: "a", Body: "123"}, {FieldName: "b", Body: "4"}},
		},
		{
			name: "境界の文字列の長さの上限", contentType: "multipart/form-data; boundary=" + strings.Repeat("b", tomcatBufferSize-5),
			body: "--" + strings.Repeat("b", tomcatBufferSize-5) + "--", want: []multipartWant{},
		},
		{
			name: "境界の文字列の大文字の項目の名前と引用符", contentType: `MULTIPART/Form-Data; BOUNDARY="AB"`,
			body: "--AB\r\nContent-Disposition: form-data; name=a\r\n\r\n1\r\n--AB--", want: []multipartWant{{FieldName: "a", Body: "1"}},
		},
		{
			name: "境界の文字列をカンマで区切る", contentType: "multipart/form-data, boundary=AB; x=y",
			body: "--AB\r\nContent-Disposition: form-data; name=a\r\n\r\n1\r\n--AB--", want: []multipartWant{},
		},
		{
			name: "境界の文字列のあとの項目", contentType: "multipart/form-data; boundary=AB; charset=utf-8",
			body: "--AB\r\nContent-Disposition: form-data; name=a\r\n\r\n1\r\n--AB--", want: []multipartWant{{FieldName: "a", Body: "1"}},
		},
		{
			name: "境界の文字列の RFC 2047", contentType: "multipart/form-data; boundary==?UTF-8?B?QUI=?=",
			body: "--AB\r\nContent-Disposition: form-data; name=a\r\n\r\n1\r\n--AB--", want: []multipartWant{{FieldName: "a", Body: "1"}},
		},
		{
			name: "境界の文字列の ISO-8859-1", contentType: "multipart/form-data; boundary=A\xe9",
			body: "--A\xe9\r\nContent-Disposition: form-data; name=a\r\n\r\n1\r\n--A\xe9--", want: []multipartWant{{FieldName: "a", Body: "1"}},
		},
		{
			name: "multipart/mixed の中のファイル", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=files\r\nContent-Type: multipart/mixed; boundary=CD\r\n\r\n" +
				"--CD\r\nContent-Disposition: attachment; filename=f1\r\n\r\nx\r\n" +
				"--CD\r\nContent-Disposition: attachment\r\n\r\nskip\r\n" +
				"--CD\r\nContent-Disposition: attachment; name=n; filename=f2\r\n\r\ny\r\n" +
				"--CD\r\nX-No-Disposition: 1\r\n\r\nskip\r\n" +
				"--CD\r\nContent-Disposition: inline; filename=f3\r\n\r\nskip\r\n" +
				"--CD\r\nContent-Disposition: form-data; filename=f4\r\n\r\nz\r\n--CD--\r\n" +
				"--AB\r\nContent-Disposition: form-data; name=b\r\n\r\n2\r\n--AB--",
			want: []multipartWant{
				{FieldName: "files", FileName: "f1", HasFileName: true, Body: "x"},
				{FieldName: "files", FileName: "f2", HasFileName: true, Body: "y"},
				{FieldName: "files", FileName: "f4", HasFileName: true, Body: "z"},
				{FieldName: "b", Body: "2"},
			},
		},
		{
			name: "外の部分の attachment は名前を持たない", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: attachment; name=a; filename=f\r\n\r\nskip\r\n" +
				"--AB\r\nContent-Disposition: attachment; name*=Shift_JIS''a\r\n\r\nskip\r\n" +
				"--AB\r\nContent-Disposition: form-data; name=b\r\n\r\n2\r\n--AB--",
			want: []multipartWant{{FieldName: "b", Body: "2"}},
		},
		{
			name: "境界の文字列の ISO-8859-1 で表せない字は ? にする", contentType: "multipart/form-data; boundary=\"=?UTF-8?B?QeeUuw==?=\"",
			body: "--A?\r\nContent-Disposition: form-data; name=a\r\n\r\n1\r\n--A?--", want: []multipartWant{{FieldName: "a", Body: "1"}},
		},
		{
			name: "項目の前後の Java の空白を除く", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=　a ; filename= f \r\n\r\n1\r\n--AB--",
			want: []multipartWant{{FieldName: "a", FileName: " f", HasFileName: true, Body: "1"}},
		},
		{
			name: "multipart/mixed の中が終わらない", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=files\r\nContent-Type: Multipart/Mixed; boundary=CD\r\n\r\nno inner boundary\r\n--AB\r\nContent-Disposition: form-data; name=b\r\n\r\n2\r\n--AB--",
			want: []multipartWant{},
		},
		{
			name: "名前の無い multipart/mixed は中身を飛ばす", contentType: multipartCT,
			body: "--AB\r\nContent-Type: multipart/mixed; boundary=CDE\r\n\r\n--CD\r\n\r\n--AB\r\nContent-Disposition: form-data; name=b\r\n\r\n2\r\n--AB--",
			want: []multipartWant{{FieldName: "b", Body: "2"}},
		},
		{
			name: "RFC 2047 の名前", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=\"=?UTF-8?B?55S7?= =?utf-8?Q?_x=41?=\"; filename=\"a =?us-ascii?Q?=E9?= b\"\r\n\r\n1\r\n--AB--",
			want: []multipartWant{{FieldName: "画 xA", FileName: "a é b", HasFileName: true, Body: "1"}},
		},
		{
			name: "RFC 2047 の形でない語をそのまま使う", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=\"=?a =?a?b =?a?b?c =?UTF-8?B??=x\"\r\n\r\n1\r\n--AB--",
			want: []multipartWant{{FieldName: "=?a =?a?b =?a?b?c", Body: "1"}},
		},
		{
			name: "RFC 2047 を解けないとき値の全体をそのまま使う", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=\"=?UTF-8?X?QQ?= =?UTF-8?B?QQ==?=\"\r\n\r\n1\r\n" +
				"--AB\r\nContent-Disposition: form-data; name=\"=?UTF-8?Q?=4?= x\"\r\n\r\n2\r\n" +
				"--AB\r\nContent-Disposition: form-data; name=\"=?UTF-8?Q?=\rx?=\"\r\n\r\n3\r\n" +
				"--AB\r\nContent-Disposition: form-data; name=\"=?UTF-8?Q?=zz?=\"\r\n\r\n4\r\n" +
				"--AB\r\nContent-Disposition: form-data; name=\"=?a b?Q?x?=\"\r\n\r\n5\r\n" +
				"--AB\r\nContent-Disposition: form-data; name=\"=?a/b?Q?x?=\"\r\n\r\n6\r\n--AB--",
			want: []multipartWant{
				{FieldName: "=?UTF-8?X?QQ?= =?UTF-8?B?QQ==?=", Body: "1"},
				{FieldName: "=?UTF-8?Q?=4?= x", Body: "2"},
				{FieldName: "=?UTF-8?Q?=\rx?=", Body: "3"},
				{FieldName: "=?UTF-8?Q?=zz?=", Body: "4"},
				{FieldName: "=?a b?Q?x?=", Body: "5"},
				{FieldName: "=?a/b?Q?x?=", Body: "6"},
			},
		},
		{
			name: "RFC 2047 の Q の ASCII でない字", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name=\"=?UTF-8?Q?a画\U0001F600?=\"\r\n\r\n1\r\n--AB--",
			want: []multipartWant{{FieldName: "a??", Body: "1"}},
		},
		{
			name: "RFC 2231 の名前", contentType: multipartCT,
			body: "--AB\r\nContent-Disposition: form-data; name*=UTF-8''%E7%94%bb%zz%4; filename*=\"utf-8'ja'a%41b\"\r\n\r\n1\r\n" +
				"--AB\r\nContent-Disposition: form-data; NAME*=no-quote; filename*=us-ascii'x\r\n\r\n2\r\n" +
				"--AB\r\nContent-Disposition: form-data; name*=iso-8859-1''éあ\r\n\r\n3\r\n" +
				"--AB\r\nContent-Disposition: form-data; name*=a=b''x\r\n\r\n4\r\n--AB--",
			want: []multipartWant{
				{FieldName: "画", FileName: "aAb", HasFileName: true, Body: "1"},
				{FieldName: "no-quote", FileName: "us-ascii'x", HasFileName: true, Body: "2"},
				{FieldName: "éB", Body: "3"},
				{FieldName: "a=b''x", Body: "4"},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertParts(t, tt.contentType, tt.body, tt.want)
		})
	}
}

// TestMultipart_PartHeaders は、見出しの読み方の細かい規則を確かめる。
func TestMultipart_PartHeaders(t *testing.T) {
	h, err := parsePartHeaders("A: 1\r\na: 2\r\nB:3\r\n\r\n")
	if err != nil {
		t.Fatalf("parsePartHeaders の誤り: %v", err)
	}
	if got := fmt.Sprint(h["a"], h["b"]); got != "[1 2] [3]" {
		t.Errorf("見出し = %s", got)
	}
	if v, ok := h.get("A"); !ok || v != "1" {
		t.Errorf("get(A) = %q, %v", v, ok)
	}
	if _, ok := h.get("c"); ok {
		t.Errorf("get(c) が見つかった")
	}
	// readHeaders は空の行で終わる見出しだけを渡すが、渡されなければ Tomcat と同じく誤りにする
	for _, s := range []string{"A: 1", "A: 1\r", "A: 1\rx\r\n \r"} {
		if _, err := parsePartHeaders(s); !errors.Is(err, errMultipart) {
			t.Errorf("parsePartHeaders(%q) の誤り = %v", s, err)
		}
	}
}

// TestMultipart_JavaParseLong は、Java の Long.parseLong と同じ規則で数を読むことを確かめる。
// Java は char ごとに数字を読むので、全角の数字のような BMP の数字は読み、BMP の外の数字(U+1D7D9)は読まない。
func TestMultipart_JavaParseLong(t *testing.T) {
	tests := []struct {
		in   string
		want int64
		ok   bool
	}{
		{"0", 0, true},
		{"+12", 12, true},
		{"-12", -12, true},
		{"９９", 99, true},
		{"\U0001D7D9", 0, false},
		{"٣", 3, true},
		{"9223372036854775807", 1<<63 - 1, true},
		{"-9223372036854775808", -1 << 63, true},
		{"9223372036854775808", 0, false},
		{"-9223372036854775809", 0, false},
		{"99999999999999999999", 0, false},
		{"", 0, false},
		{"+", 0, false},
		{"-", 0, false},
		{" 1", 0, false},
		{"1a", 0, false},
		{"Ⅰ", 0, false},
	}
	for _, tt := range tests {
		got, ok := javaParseLong(tt.in)
		if got != tt.want || ok != tt.ok {
			t.Errorf("javaParseLong(%q) = %d, %v, want %d, %v", tt.in, got, ok, tt.want, tt.ok)
		}
	}
}

// TestMultipart_CharsetName は、JDK 21 の Charset.checkName と同じ規則で文字コードの名前を見分けることを確かめる。
func TestMultipart_CharsetName(t *testing.T) {
	for name, want := range map[string]bool{
		"UTF-8": true, "a": true, "1+:_.-": true, "": false, "-a": false, ".a": false, "a b": false, "a/b": false, "é": false, "ȧ": false,
	} {
		if got := javaCharsetNameLegal(name); got != want {
			t.Errorf("javaCharsetNameLegal(%q) = %v, want %v", name, got, want)
		}
	}
}

// TestMultipart_PartCount は、名前を持つ部分を上限の数まで読み、名前の無い部分を数えないことを確かめる。
func TestMultipart_PartCount(t *testing.T) {
	var body strings.Builder
	want := make([]multipartWant, 0, multipartMaxPartCount)
	for i := range multipartMaxPartCount {
		fmt.Fprintf(&body, "--AB\r\nX: y\r\n\r\nz\r\n--AB\r\nContent-Disposition: form-data; name=p%d\r\n\r\n%d\r\n", i, i)
		want = append(want, multipartWant{FieldName: fmt.Sprintf("p%d", i), Body: fmt.Sprint(i)})
	}
	body.WriteString("--AB\r\nX: y\r\n\r\nz\r\n--AB--")
	assertParts(t, multipartCT, body.String(), want)
}

// TestMultipart_QuotedPrintable は、部分の見出しからは渡せない並び(CR を含む並び)も、Tomcat の QuotedPrintableDecoder と同じく解くことを確かめる。
// 見出しの値の CR は、Tomcat の MimeUtility.decodeText が語の区切りにするので、Q の書き方の中には入らない。
func TestMultipart_QuotedPrintable(t *testing.T) {
	tests := []struct {
		in   string
		want string
		ok   bool
	}{
		{"_=41b", " Ab", true},
		{"a=\r\nb", "ab", true},
		{"=e9", "\xe9", true},
		{"a=\rx", "", false},
		{"=4", "", false},
		{"=", "", false},
		{"=g1", "", false},
		{"=1g", "", false},
	}
	for _, tt := range tests {
		got, ok := tomcatDecodeQuotedPrintable([]byte(tt.in))
		if string(got) != tt.want || ok != tt.ok {
			t.Errorf("tomcatDecodeQuotedPrintable(%q) = %q, %v, want %q, %v", tt.in, got, ok, tt.want, tt.ok)
		}
	}
}

// TestMultipart_JavaIsWhitespace は、Java の Character.isWhitespace が空白とする字を、U+0000 から U+FFFF まで照らす。
func TestMultipart_JavaIsWhitespace(t *testing.T) {
	want := map[rune]bool{0x1680: true, 0x2028: true, 0x2029: true, 0x205F: true, 0x3000: true}
	for r := rune(0x09); r <= 0x0D; r++ {
		want[r] = true
	}
	for r := rune(0x1C); r <= 0x20; r++ {
		want[r] = true
	}
	for r := rune(0x2000); r <= 0x200A; r++ {
		want[r] = r != 0x2007
	}
	for r := rune(0); r <= 0xFFFF; r++ {
		if got := javaIsWhitespace(r); got != want[r] {
			t.Errorf("javaIsWhitespace(U+%04X) = %v", r, got)
		}
	}
}

// TestMultipart_Latin1Byte は、U+0000 から U+00FF までの字を、その番号のバイトにすることを確かめる。
func TestMultipart_Latin1Byte(t *testing.T) {
	for c := byte(0); ; c++ {
		if got := latin1Byte(rune(c)); got != c {
			t.Errorf("latin1Byte(U+%04X) = %#x", c, got)
		}
		if c == 0xFF {
			break
		}
	}
}
