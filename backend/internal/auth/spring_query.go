package auth

import "strings"

// このファイルは、Java 版の OidcClient が URL の問い合わせの部分を書くときの、Spring の
// UriComponentsBuilder.toUriString()(中で build().encode() を呼ぶ)のエスケープを写す。
// Spring は、問い合わせの項目の名前と値を、HierarchicalUriComponents の QUERY_PARAM の規則でエスケープする。
// この規則が残す文字は、RFC 3986 の pchar(英数字、`-._~`、`!$&'()*+,;=`、`:`、`@`)と `/` と `?` から、
// 項目を区切る `=` と `&` を除いたものである。ほかの文字は、UTF-8 のバイトごとに、`%` と大文字の16進の2桁にする。
// Go の url.Values.Encode() は、空白を `+` にし、`/` と `:` もエスケープするので、Java 版と同じ URL にならない。

// queryParam は、URL の問い合わせの1つの項目の名前と値である。
type queryParam struct {
	name  string
	value string
}

// springQuery は、params を渡した順に「名前=値」にして `&` でつないだ、問い合わせの部分を返す。
// 先頭の `?` は付けない。
func springQuery(params []queryParam) string {
	var b strings.Builder
	for i, p := range params {
		if i > 0 {
			b.WriteByte('&')
		}
		b.WriteString(springQueryEscape(p.name))
		b.WriteByte('=')
		b.WriteString(springQueryEscape(p.value))
	}
	return b.String()
}

// springQueryEscape は、s を、Spring の QUERY_PARAM の規則でエスケープする。
func springQueryEscape(s string) string {
	const hex = "0123456789ABCDEF"
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if springQueryAllowed(c) {
			b.WriteByte(c)
			continue
		}
		b.WriteByte('%')
		b.WriteByte(hex[c>>4])
		b.WriteByte(hex[c&0x0F])
	}
	return b.String()
}

// springQueryAllowed は、c が、Spring の QUERY_PARAM の規則でエスケープせずに残すバイトかを返す。
func springQueryAllowed(c byte) bool {
	switch {
	case 'a' <= c && c <= 'z', 'A' <= c && c <= 'Z', '0' <= c && c <= '9':
		return true
	}
	return strings.IndexByte("-._~!$'()*+,;:@/?", c) >= 0
}
