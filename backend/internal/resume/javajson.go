package resume

import (
	"bytes"
	"encoding/json"
	"fmt"
	"reflect"
	"strconv"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

// marshalerType は、json.Marshaler の型である。
var marshalerType = reflect.TypeFor[json.Marshaler]()

// upperHex は、Java 版の Jackson が \uXXXX の番号に使う、大文字の16進数の字である。
const upperHex = "0123456789ABCDEF"

// JavaJSON は、v を、Java 版の Jackson の既定の書き方と同じ字の並びの JSON で書く。
// Go の encoding/json は、< > & と U+2028 と U+2029 を番号で書き、対になっていないサロゲートを U+FFFD に置き換えるので、
// Java 版と同じ字の並びにならない。そこで、バックアップのファイルと戻しの答えの本文は、この書き手で書く。
//
//   - 構造体の欄は、宣言の順に、json のタグの名前で書く。タグの無い欄は Go の欄の名前で書き、タグが - の欄と、
//     公開していない欄は書かない。omitempty の欄は、encoding/json と同じく、偽、0、空の字、長さ 0 の並び、nil の値のときに書かない
//   - json.Marshaler を持つ値は、その MarshalJSON の書き方から空白と改行を除いて書く
//   - 空白と改行を入れない
//   - 字の書き方は appendJavaString のとおりである
//
// JavaJSON が書く値は、この spec の型だけである。小数、対応表、埋め込みの欄のように、この spec の型が持たない値と、
// MarshalJSON の誤りは、書き手の使い方の誤りなので、JavaJSON は panic する。
func JavaJSON(v any) []byte {
	return appendJavaValue(nil, reflect.ValueOf(v))
}

// appendJavaValue は、b に、v の JSON を足す。
func appendJavaValue(b []byte, v reflect.Value) []byte {
	if !v.IsValid() {
		return append(b, "null"...)
	}
	if (v.Kind() == reflect.Pointer || v.Kind() == reflect.Interface) && v.IsNil() {
		return append(b, "null"...)
	}
	if v.Type().Implements(marshalerType) {
		return appendMarshaler(b, v)
	}
	switch v.Kind() {
	case reflect.Pointer, reflect.Interface:
		return appendJavaValue(b, v.Elem())
	case reflect.String:
		return appendJavaString(b, v.String())
	case reflect.Bool:
		return strconv.AppendBool(b, v.Bool())
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return strconv.AppendInt(b, v.Int(), 10)
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		return strconv.AppendUint(b, v.Uint(), 10)
	case reflect.Slice:
		if v.IsNil() {
			return append(b, "null"...)
		}
		return appendJavaArray(b, v)
	case reflect.Array:
		return appendJavaArray(b, v)
	case reflect.Struct:
		return appendJavaStruct(b, v)
	default:
		panic(fmt.Errorf("resume: JavaJSON は %s の値を書けません", v.Type()))
	}
}

// appendMarshaler は、b に、v の MarshalJSON の書き方から空白と改行を除いた JSON を足す。
func appendMarshaler(b []byte, v reflect.Value) []byte {
	// 呼ぶ前に、v の型が json.Marshaler を持つことを確かめてある
	raw, err := v.Interface().(json.Marshaler).MarshalJSON()
	if err != nil {
		panic(fmt.Errorf("resume: JavaJSON は %s の MarshalJSON で書けません: %w", v.Type(), err))
	}
	var buf bytes.Buffer
	if err := json.Compact(&buf, raw); err != nil {
		panic(fmt.Errorf("resume: JavaJSON は %s の MarshalJSON の書いた JSON を読めません: %w", v.Type(), err))
	}
	return append(b, buf.Bytes()...)
}

// appendJavaArray は、b に、並び v の要素を [ ] で囲んで足す。
func appendJavaArray(b []byte, v reflect.Value) []byte {
	b = append(b, '[')
	for i := range v.Len() {
		if i > 0 {
			b = append(b, ',')
		}
		b = appendJavaValue(b, v.Index(i))
	}
	return append(b, ']')
}

// appendJavaStruct は、b に、構造体 v の欄を、宣言の順に { } で囲んで足す。
func appendJavaStruct(b []byte, v reflect.Value) []byte {
	b = append(b, '{')
	first := true
	t := v.Type()
	for i := range t.NumField() {
		f := t.Field(i)
		if f.Anonymous {
			panic(fmt.Errorf("resume: JavaJSON は %s の埋め込みの欄 %s を書けません", t, f.Name))
		}
		if !f.IsExported() {
			continue
		}
		tag := f.Tag.Get("json")
		if tag == "-" {
			continue
		}
		name, opts, _ := strings.Cut(tag, ",")
		if name == "" {
			name = f.Name
		}
		fv := v.Field(i)
		if hasOption(opts, "omitempty") && isEmptyJSONValue(fv) {
			continue
		}
		if !first {
			b = append(b, ',')
		}
		first = false
		b = appendJavaString(b, name)
		b = append(b, ':')
		b = appendJavaValue(b, fv)
	}
	return append(b, '}')
}

// hasOption は、json のタグの名前のあとの、, で区切った選択 opts に、name があるかを返す。
func hasOption(opts, name string) bool {
	for opts != "" {
		var o string
		o, opts, _ = strings.Cut(opts, ",")
		if o == name {
			return true
		}
	}
	return false
}

// isEmptyJSONValue は、encoding/json の omitempty と同じく、v が書かない値かを返す。構造体は、書かない値にならない。
func isEmptyJSONValue(v reflect.Value) bool {
	switch v.Kind() {
	case reflect.Array, reflect.Map, reflect.Slice, reflect.String:
		return v.Len() == 0
	case reflect.Bool:
		return !v.Bool()
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return v.Int() == 0
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		return v.Uint() == 0
	case reflect.Interface, reflect.Pointer:
		return v.IsNil()
	default:
		return false
	}
}

// appendJavaString は、b に、s を、Java 版の Jackson と同じ字の並びの JSON の文字列で足す。
// s の対になっていないサロゲートは、UTF-8 と同じ規則の3バイト(WTF-8)で持つ。
//
//   - " と \ の前に \ を置く
//   - 0x20 より小さい字のうち、\b \t \n \f \r は短い形で書き、ほかは大文字の16進数の \u00XX で書く
//   - BMP の外の字は、サロゲートの組を \uXXXX\uXXXX で書き、対になっていないサロゲートは \uXXXX で書く
//   - < > & ' / と U+007F と U+2028 と U+2029 を含む、ほかの字は、番号にせずにそのまま書く
//
// UTF-8 としても WTF-8 としても読めないバイトは、Java の文字列に無い値なので、U+FFFD にして書く。
func appendJavaString(b []byte, s string) []byte {
	b = append(b, '"')
	for i := 0; i < len(s); {
		c := s[i]
		if c < utf8.RuneSelf {
			b = appendJavaASCII(b, c)
			i++
			continue
		}
		r, size := decodeWTF8(s[i:])
		switch {
		case r >= 0x10000:
			hi, lo := utf16.EncodeRune(r)
			b = appendUnicodeEscape(appendUnicodeEscape(b, hi), lo)
		case r >= 0xD800 && r <= 0xDFFF:
			b = appendUnicodeEscape(b, r)
		default:
			b = utf8.AppendRune(b, r)
		}
		i += size
	}
	return append(b, '"')
}

// appendJavaASCII は、b に、ASCII の字 c を JSON の文字列の中の書き方で足す。
func appendJavaASCII(b []byte, c byte) []byte {
	switch c {
	case '"', '\\':
		return append(b, '\\', c)
	case '\b':
		return append(b, '\\', 'b')
	case '\t':
		return append(b, '\\', 't')
	case '\n':
		return append(b, '\\', 'n')
	case '\f':
		return append(b, '\\', 'f')
	case '\r':
		return append(b, '\\', 'r')
	}
	if c < 0x20 {
		return append(b, '\\', 'u', '0', '0', upperHex[c>>4], upperHex[c&0x0F])
	}
	return append(b, c)
}

// appendUnicodeEscape は、b に、UTF-16 の単位 r を、大文字の16進数の \uXXXX で足す。
func appendUnicodeEscape(b []byte, r rune) []byte {
	return append(b, '\\', 'u', upperHex[r>>12&0x0F], upperHex[r>>8&0x0F], upperHex[r>>4&0x0F], upperHex[r&0x0F])
}

// decodeWTF8 は、s の先頭の1字を読み、字とそのバイトの数を返す。先頭が、対になっていないサロゲートを UTF-8 と同じ規則で
// 書いた3バイト(0xED 0xA0..0xBF 0x80..0xBF)なら、そのサロゲートを返す。UTF-8 として読めない先頭の1バイトは、
// utf8.RuneError と 1 を返す。
func decodeWTF8(s string) (rune, int) {
	if len(s) >= 3 && s[0] == 0xED && s[1] >= 0xA0 && s[1] <= 0xBF && s[2] >= 0x80 && s[2] <= 0xBF {
		return 0xD000 | rune(s[1]&0x3F)<<6 | rune(s[2]&0x3F), 3
	}
	return utf8.DecodeRuneInString(s)
}
