package resume

import (
	"errors"
	"slices"
	"unicode"
	"unicode/utf16"
)

// このファイルは、Java 版の要求の型が、リンクの入力欄に付けた Hibernate Validator 9.1.5 の
// @URL(protocol = "https") の判定を写す。リンクは利用者が入力欄に打てる値なので、Go 版は Java 版と同じ判定をする。
// 判定は、JDK 21 の java.net.URI と java.net.URL と、URL が使う sun.net.util.IPAddressUtil と
// Integer.parseInt の読み方を写す。JDK の設定は既定のまま(jdk.net.url.delayParsing と
// jdk.net.allowAmbiguousIPAddressLiterals を設定しない)とする。
// Java の String は UTF-16 の単位の並びなので、写しは値を []uint16 に直して読む。

// isHibernateHTTPSURL は、Hibernate Validator 9.1.5 の URLValidator.isValid の、protocol が https のときの写しである。
// 値が空なら true を返す。そうでなければ、new URI(値).toURL() が例外を出さず、そのプロトコルが https のときに true を返す。
func isHibernateHTTPSURL(s string) bool {
	if s == "" {
		return true
	}
	in := javaChars(s)
	scheme, ok := parseJavaURI(in)
	if !ok {
		// URISyntaxException
		return false
	}
	if scheme == nil {
		// URL.of は、スキームの無い URI に IllegalArgumentException を出す
		return false
	}
	if equalsIgnoreCaseASCII(scheme, "url") {
		// URL.of は、スキームが url の URI では、先頭の4字を除いた値を URI として読み直し、
		// 読めなければ MalformedURLException を出す
		if _, ok := parseJavaURI(in[4:]); !ok {
			return false
		}
	}
	return javaURLIsHTTPS(in)
}

// javaChars は、Go の文字列を、Java の String と同じ UTF-16 の単位の並びに直す。
func javaChars(s string) []uint16 {
	return utf16.Encode([]rune(s))
}

// equalsIgnoreCaseASCII は、s が、英字の大文字と小文字を区別せずに want と等しいかを返す。
// want は英小文字と記号だけの文字列である。Java は、url と url: を equalsIgnoreCase と regionMatches で比べ、
// https を toLowerCase のあとの equals で比べる。equalsIgnoreCase と regionMatches では ſ(U+017F)が s に一致するが、
// url と url: には s が無い。toLowerCase は ſ を s に直さない。そのため、英字でない文字が want の字に一致することは無く、
// 英字の大文字と小文字だけを同じとみなせばよい。
func equalsIgnoreCaseASCII(s []uint16, want string) bool {
	if len(s) != len(want) {
		return false
	}
	for i, c := range s {
		if c >= 'A' && c <= 'Z' {
			c += 'a' - 'A'
		}
		if c != uint16(want[i]) {
			return false
		}
	}
	return true
}

func indexOfChar(s []uint16, c uint16, from int) int {
	if from >= len(s) {
		return -1
	}
	if i := slices.Index(s[from:], c); i >= 0 {
		return from + i
	}
	return -1
}

// -- java.net.URL --

// javaURLIsHTTPS は、new URL(null, spec, null) が例外を出さず、そのプロトコルが https かを返す。
// URL のコンストラクタと、https のハンドラが使う URLStreamHandler.parseURL と setURL の写しである。
// 道筋(path)は、例外にも判定にも関わらないので、読まない。
func javaURLIsHTTPS(spec []uint16) bool {
	limit := len(spec)
	for limit > 0 && spec[limit-1] <= ' ' {
		limit--
	}
	start := 0
	for start < limit && spec[start] <= ' ' {
		start++
	}
	if start+4 <= len(spec) && equalsIgnoreCaseASCII(spec[start:start+4], "url:") {
		start += 4
	}
	aRef := start < len(spec) && spec[start] == '#'
	https := false
	for i := start; !aRef && i < limit && spec[i] != '/'; i++ {
		if spec[i] == ':' {
			// プロトコルが https 以外なら、URL は、MalformedURLException を出すか、https 以外のプロトコルの URL になる
			if equalsIgnoreCaseASCII(spec[start:i], "https") {
				https = true
				start = i + 1
			}
			break
		}
	}
	if !https {
		return false
	}
	if i := indexOfChar(spec, '#', start); i >= 0 {
		limit = i
	}
	return javaParseURL(spec, start, limit)
}

// javaParseURL は、URLStreamHandler.parseURL と setURL の写しである。例外を出す値に false を返す。
func javaParseURL(spec []uint16, start, limit int) bool {
	if start < limit {
		if q := indexOfChar(spec, '?', 0); q != -1 && q < limit {
			limit = q
			spec = spec[:q]
		}
	}
	isUNCName := start <= limit-4 && spec[start] == '/' && spec[start+1] == '/' && spec[start+2] == '/' && spec[start+3] == '/'
	if isUNCName || start > limit-2 || spec[start] != '/' || spec[start+1] != '/' {
		// 権限の部分が無い。setURL が確かめる host は空で、userInfo と authority は null なので、例外は出ない
		return true
	}
	start += 2
	i := indexOfChar(spec, '/', start)
	if i < 0 || i > limit {
		i = indexOfChar(spec, '?', start)
		if i < 0 || i > limit {
			i = limit
		}
	}
	authority := spec[start:i]
	host := authority
	var userInfo []uint16
	hasUserInfo, twoAts := false, false
	if ind := indexOfChar(authority, '@', 0); ind != -1 {
		if ind != lastIndexOfChar(authority, '@') {
			twoAts = true
		} else {
			hasUserInfo = true
			userInfo = authority[:ind]
			host = authority[ind+1:]
		}
	}
	port := -1
	if twoAts {
		// '@' が2つ以上ある権限の部分は、サーバーの形でないので、host を空にする
		host = []uint16{}
	} else if len(host) > 0 && host[0] == '[' {
		ind := indexOfChar(host, ']', 0)
		if ind <= 2 {
			return false
		}
		nhost := host
		host = nhost[:ind+1]
		if !javaIsIPv6LiteralAddress(host[1:ind]) {
			return false
		}
		if len(nhost) > ind+1 {
			if nhost[ind+1] != ':' {
				return false
			}
			ind++
			if len(nhost) > ind+1 {
				p, ok := javaParseInt(nhost[ind+1:])
				if !ok {
					return false
				}
				port = p
			}
		}
	} else if ind := indexOfChar(host, ':', 0); ind >= 0 {
		if len(host) > ind+1 {
			p, ok := javaParseInt(host[ind+1:])
			if !ok {
				return false
			}
			port = p
		}
		host = host[:ind]
	}
	if port < -1 {
		return false
	}
	if !javaCheckHost(host) {
		return false
	}
	if hasUserInfo && !javaCheckUserInfo(userInfo) {
		return false
	}
	return javaCheckAuth(authority)
}

func lastIndexOfChar(s []uint16, c uint16) int {
	for i := len(s) - 1; i >= 0; i-- {
		if s[i] == c {
			return i
		}
	}
	return -1
}

// -- java.net.URI --

// URI の文字の種類のマスク。java.net.URI の値をそのまま写す。
// 1 から 63 の文字は下位のマスク(L)、64 から 127 の文字は上位のマスク(H)のビットで表す。
// 値が 0 のマスク(H_DIGIT、L_ALPHA、H_ESCAPED、H_DASH、H_DOT)は、式から省く。
const (
	uriLDigit         uint64 = 0x3FF000000000000
	uriHUpAlpha       uint64 = 0x7FFFFFE
	uriHLowAlpha      uint64 = 0x7FFFFFE00000000
	uriHAlpha                = uriHUpAlpha | uriHLowAlpha
	uriLAlphanum             = uriLDigit
	uriHAlphanum             = uriHAlpha
	uriLHex                  = uriLDigit
	uriHHex           uint64 = 0x7E0000007E
	uriLMark          uint64 = 0x678200000000
	uriHMark          uint64 = 0x4000000080000000
	uriLUnreserved           = uriLAlphanum | uriLMark
	uriHUnreserved           = uriHAlphanum | uriHMark
	uriLReserved      uint64 = 0xAC00985000000000
	uriHReserved      uint64 = 0x28000001
	uriLEscaped       uint64 = 1
	uriLURIC                 = uriLReserved | uriLUnreserved | uriLEscaped
	uriHURIC                 = uriHReserved | uriHUnreserved
	uriLPchar                = uriLUnreserved | uriLEscaped | 0x2400185000000000
	uriHPchar                = uriHUnreserved | 0x1
	uriLPath                 = uriLPchar | 0x800800000000000
	uriHPath                 = uriHPchar
	uriLDash          uint64 = 0x200000000000
	uriLDot           uint64 = 0x400000000000
	uriLUserInfo             = uriLUnreserved | uriLEscaped | 0x2C00185000000000
	uriHUserInfo             = uriHUnreserved
	uriLRegName              = uriLUnreserved | uriLEscaped | 0x2C00185000000000
	uriHRegName              = uriHUnreserved | 0x1
	uriLServer               = uriLUserInfo | uriLAlphanum | uriLDash | 0x400400000000000
	uriHServer               = uriHUserInfo | uriHAlphanum | 0x28000001
	uriLServerPercent        = uriLServer | 0x2000000000
	uriHServerPercent        = uriHServer
	uriLScheme               = uriLDigit | 0x680000000000
	uriHScheme               = uriHAlpha
	uriLScopeID              = uriLAlphanum | 0x400000000000
	uriHScopeID              = uriHAlphanum | 0x80000000
)

// uriMatch は、java.net.URI の match の写しである。文字の番号が 0 の文字と、128 以上の文字は、どのマスクにも当たらない。
func uriMatch(c uint16, low, high uint64) bool {
	switch {
	case c == 0:
		return false
	case c < 64:
		return (1<<c)&low != 0
	case c < 128:
		return (1<<(c-64))&high != 0
	}
	return false
}

// errJavaURISyntax は、java.net.URI の URISyntaxException にあたる。javaURIParser は、これを panic で投げる。
var errJavaURISyntax = errors.New("URISyntaxException")

// parseJavaURI は、new URI(in) の写しである。URISyntaxException が出る値には ok に false を返す。
// 読めた値には、スキームを返す。スキームの無い値には nil を返す。
func parseJavaURI(in []uint16) (scheme []uint16, ok bool) {
	p := &javaURIParser{in: in}
	defer func() {
		if r := recover(); r != nil {
			if r != errJavaURISyntax {
				panic(r)
			}
			scheme, ok = nil, false
		}
	}()
	p.parse()
	return p.scheme, true
}

// javaURIParser は、java.net.URI.Parser の写しである。new URI(String) と同じく、
// 権限の部分にサーバーの形を求めない(requireServerAuthority が false)。
type javaURIParser struct {
	in            []uint16
	scheme        []uint16
	ipv6byteCount int
}

func (p *javaURIParser) fail() {
	panic(errJavaURISyntax)
}

func (p *javaURIParser) at(start, end int, c uint16) bool {
	return start < end && p.in[start] == c
}

func (p *javaURIParser) atDoubleColon(start, end int) bool {
	return p.at(start, end, ':') && p.at(start+1, end, ':')
}

// scanChar は、start の位置の字が c なら次の位置を返し、そうでなければ start を返す。
func (p *javaURIParser) scanChar(start, end int, c uint16) int {
	if p.at(start, end, c) {
		return start + 1
	}
	return start
}

// scanErrStop は、err の字に当たれば -1 を返し、stop の字に当たればその位置を返す。どちらにも当たらなければ end を返す。
func (p *javaURIParser) scanErrStop(start, end int, err, stop string) int {
	for i := start; i < end; i++ {
		c := p.in[i]
		if c >= 128 {
			continue
		}
		if containsByte(err, byte(c)) {
			return -1
		}
		if containsByte(stop, byte(c)) {
			return i
		}
	}
	return end
}

// scanStop は、stop の字に当たればその位置を返し、当たらなければ end を返す。
func (p *javaURIParser) scanStop(start, end int, stop string) int {
	return p.scanErrStop(start, end, "", stop)
}

func containsByte(s string, c byte) bool {
	for i := range len(s) {
		if s[i] == c {
			return true
		}
	}
	return false
}

// scanEscape は、'%' と16進の数字2つの並びか、128 より大きい文字のうち空白でも制御文字でもない文字を読む。
// '%' のあとに16進の数字が2つ続かなければ、URISyntaxException を出す。
func (p *javaURIParser) scanEscape(start, n int, c uint16) int {
	if c == '%' {
		if start+3 <= n && uriMatch(p.in[start+1], uriLHex, uriHHex) && uriMatch(p.in[start+2], uriLHex, uriHHex) {
			return start + 3
		}
		p.fail()
	} else if c > 128 && !javaIsSpaceChar(c) && !javaIsISOControl(c) {
		return start + 1
	}
	return start
}

// javaIsSpaceChar は、Character.isSpaceChar の写しである。空白の区切り(Zs)と行の区切り(Zl)と段落の区切り(Zp)の文字を空白とする。
func javaIsSpaceChar(c uint16) bool {
	return unicode.In(rune(c), unicode.Zs, unicode.Zl, unicode.Zp)
}

// javaIsISOControl は、Character.isISOControl の写しである。
func javaIsISOControl(c uint16) bool {
	return c <= 0x1F || (c >= 0x7F && c <= 0x9F)
}

// scan は、マスクに当たる文字を読み進め、止まった位置を返す。マスクに uriLEscaped があれば、scanEscape も試す。
func (p *javaURIParser) scan(start, n int, low, high uint64) int {
	i := start
	for i < n {
		c := p.in[i]
		if uriMatch(c, low, high) {
			i++
			continue
		}
		if low&uriLEscaped != 0 {
			if q := p.scanEscape(i, n, c); q > i {
				i = q
				continue
			}
		}
		break
	}
	return i
}

// checkChars は、start から end までのすべての字がマスクに当たることを求める。
func (p *javaURIParser) checkChars(start, end int, low, high uint64) {
	if p.scan(start, end, low, high) < end {
		p.fail()
	}
}

// parse は、[スキーム:]スキームのあとの部分[#断片] を読む。
func (p *javaURIParser) parse() {
	n := len(p.in)
	i := p.scanErrStop(0, n, "/?#", ":")
	if i >= 0 && p.at(i, n, ':') {
		if i == 0 {
			p.fail()
		}
		p.checkChars(0, 1, 0, uriHAlpha)
		p.checkChars(1, i, uriLScheme, uriHScheme)
		p.scheme = p.in[:i]
		i++
		if p.at(i, n, '/') {
			i = p.parseHierarchical(i, n)
		} else {
			q := p.scanStop(i, n, "#")
			if q <= i {
				p.fail()
			}
			p.checkChars(i, q, uriLURIC, uriHURIC)
			i = q
		}
	} else {
		i = p.parseHierarchical(0, n)
	}
	if p.at(i, n, '#') {
		p.checkChars(i+1, n, uriLURIC, uriHURIC)
		i = n
	}
	if i < n {
		p.fail()
	}
}

// parseHierarchical は、[//権限の部分]道筋[?問い合わせ] を読む。
// 権限の部分が空でも、あとに道筋か問い合わせか断片が続けば受ける。
func (p *javaURIParser) parseHierarchical(start, n int) int {
	i := start
	if p.at(i, n, '/') && p.at(i+1, n, '/') {
		i += 2
		q := p.scanStop(i, n, "/?#")
		if q > i {
			i = p.parseAuthority(i, q)
		} else if q >= n {
			p.fail()
		}
	}
	q := p.scanStop(i, n, "?#")
	p.checkChars(i, q, uriLPath, uriHPath)
	i = q
	if p.at(i, n, '?') {
		i++
		q = p.scanStop(i, n, "#")
		p.checkChars(i, q, uriLURIC, uriHURIC)
		i = q
	}
	return i
}

// parseAuthority は、権限の部分を、サーバーの形か、登録された名前の形として読む。
// 登録された名前の形の字だけでできた権限の部分は、サーバーの形として読めなくても受ける。
// サーバーの形として読む途中の誤りは、登録された名前の形として受けない権限の部分でだけ、URISyntaxException になる。
func (p *javaURIParser) parseAuthority(start, n int) int {
	var serverChars bool
	if p.scanStop(start, n, "]") > start {
		serverChars = p.scan(start, n, uriLServerPercent, uriHServerPercent) == n
	} else {
		serverChars = p.scan(start, n, uriLServer, uriHServer) == n
	}
	regChars := p.scan(start, n, uriLRegName, uriHRegName) == n
	if regChars {
		return n
	}
	if !serverChars {
		p.fail()
	}
	p.parseServer(start, n)
	return n
}

// parseServer は、[userinfo@]host[:港の番号] を読む。登録された名前の形でない権限の部分にだけ呼ぶので、
// 読めない字に当たったら URISyntaxException を出す(skipParseException が false のときの写し)。
func (p *javaURIParser) parseServer(start, n int) {
	i := start
	q := p.scanErrStop(i, n, "/?#", "@")
	if q >= i && p.at(q, n, '@') {
		p.checkChars(i, q, uriLUserInfo, uriHUserInfo)
		i = q + 1
	}
	if p.at(i, n, '[') {
		i++
		q = p.scanErrStop(i, n, "/?#", "]")
		if q <= i || !p.at(q, n, ']') {
			p.fail()
		}
		if r := p.scanStop(i, q, "%"); r > i {
			p.parseIPv6Reference(i, r)
			if r+1 == q {
				p.fail()
			}
			p.checkChars(r+1, q, uriLScopeID, uriHScopeID)
		} else {
			p.parseIPv6Reference(i, q)
		}
		i = q + 1
	} else {
		q = p.parseIPv4Address(i, n)
		if q <= i {
			q = p.parseHostname(i, n)
		}
		i = q
	}
	if p.at(i, n, ':') {
		i++
		q = p.scanStop(i, n, "/")
		if q > i {
			p.checkChars(i, q, uriLDigit, 0)
			if _, ok := javaParseInt(p.in[i:q]); !ok {
				p.fail()
			}
			i = q
		}
	}
	if i < n {
		p.fail()
	}
}

// scanByte は、IPv4 の住所の1つの数を読む。先頭の0を除いた桁が3より多いか、255 を超えたら、start を返す。
func (p *javaURIParser) scanByte(start, n int) int {
	q := p.scan(start, n, uriLDigit, 0)
	if q <= start {
		return q
	}
	i := start
	for j := p.scanChar(i, q, '0'); j > i; j = p.scanChar(i, q, '0') {
		i = j
	}
	switch significant := q - i; {
	case significant < 3:
		return q
	case significant > 3:
		return start
	}
	if v, _ := javaParseInt(p.in[start:q]); v > 255 {
		return start
	}
	return q
}

// scanIPv4Address は、4つの数と3つの点の IPv4 の住所を読む。strict のときは、読めなければ URISyntaxException を出す。
// strict でないときは、読めなければ -1 を返す。
func (p *javaURIParser) scanIPv4Address(start, n int, strict bool) int {
	i := start
	m := p.scan(i, n, uriLDigit|uriLDot, 0)
	if m <= i || (strict && m != n) {
		return -1
	}
	for k := range 7 {
		var q int
		if k%2 == 0 {
			q = p.scanByte(i, m)
		} else {
			q = p.scanChar(i, m, '.')
		}
		if q <= i {
			break
		}
		i = q
		if k == 6 && q >= m {
			return q
		}
	}
	if strict {
		p.fail()
	}
	return -1
}

// takeIPv4Address は、IPv6 の住所の中の IPv4 の住所を読む。読めなければ URISyntaxException を出す。
func (p *javaURIParser) takeIPv4Address(start, n int) int {
	i := p.scanIPv4Address(start, n, true)
	if i <= start {
		p.fail()
	}
	return i
}

// parseIPv4Address は、host の位置の IPv4 の住所を読む。読めないか、住所のあとが ':' でなければ -1 を返す。
func (p *javaURIParser) parseIPv4Address(start, n int) int {
	i := p.scanIPv4Address(start, n, false)
	if i > start && i < n && p.in[i] != ':' {
		return -1
	}
	return i
}

// parseHostname は、点で区切った名前の host を読む。
func (p *javaURIParser) parseHostname(start, n int) int {
	i := start
	last := -1 // 最後に読んだ名前の区切りの先頭
	for {
		q := p.scan(i, n, uriLAlphanum, uriHAlphanum)
		if q <= i {
			break
		}
		last = i
		i = q
		q = p.scan(i, n, uriLAlphanum|uriLDash, uriHAlphanum)
		if q > i {
			if p.in[q-1] == '-' {
				p.fail()
			}
			i = q
		}
		q = p.scanChar(i, n, '.')
		if q <= i {
			break
		}
		i = q
		if i >= n {
			break
		}
	}
	if i < n && !p.at(i, n, ':') {
		p.fail()
	}
	if last < 0 {
		p.fail()
	}
	// 点で区切った名前では、最後の区切りが英字で始まることを求める
	if last > start && !uriMatch(p.in[last], 0, uriHAlpha) {
		p.fail()
	}
	return i
}

// parseIPv6Reference は、'[' と ']' の間の IPv6 の住所を読む。
func (p *javaURIParser) parseIPv6Reference(start, n int) {
	i := start
	compressedZeros := false
	if q := p.scanHexSeq(i, n); q > i {
		i = q
		if p.atDoubleColon(i, n) {
			compressedZeros = true
			i = p.scanHexPost(i+2, n)
		} else if p.at(i, n, ':') {
			i = p.takeIPv4Address(i+1, n)
			p.ipv6byteCount += 4
		}
	} else if p.atDoubleColon(i, n) {
		compressedZeros = true
		i = p.scanHexPost(i+2, n)
	}
	if i < n ||
		p.ipv6byteCount > 16 ||
		(!compressedZeros && p.ipv6byteCount < 16) ||
		(compressedZeros && p.ipv6byteCount == 16) {
		p.fail()
	}
}

func (p *javaURIParser) scanHexPost(start, n int) int {
	if start == n {
		return start
	}
	if q := p.scanHexSeq(start, n); q > start {
		i := q
		if p.at(i, n, ':') {
			i = p.takeIPv4Address(i+1, n)
			p.ipv6byteCount += 4
		}
		return i
	}
	i := p.takeIPv4Address(start, n)
	p.ipv6byteCount += 4
	return i
}

// scanHexSeq は、':' で区切った16進の数の並びを読む。IPv4 の住所の始まりに当たれば、その前で止まる。
func (p *javaURIParser) scanHexSeq(start, n int) int {
	q := p.scan(start, n, uriLHex, uriHHex)
	if q <= start || p.at(q, n, '.') {
		return -1
	}
	if q > start+4 {
		p.fail()
	}
	p.ipv6byteCount += 2
	i := q
	for i < n {
		if !p.at(i, n, ':') || p.at(i+1, n, ':') {
			break
		}
		i++
		q = p.scan(i, n, uriLHex, uriHHex)
		if q <= i {
			p.fail()
		}
		if p.at(q, n, '.') {
			i--
			break
		}
		if q > i+4 {
			p.fail()
		}
		p.ipv6byteCount += 2
		i = q
	}
	return i
}

// -- sun.net.util.IPAddressUtil --

// IPAddressUtil のマスク。sun.net.util.IPAddressUtil の値をそのまま写す。
// host と IPv6 の scope のマスクは、早く読む既定の設定(jdk.net.url.delayParsing が false)のときの値である。
const (
	ipLExclude        uint64 = 0x84008008ffffffff
	ipHExclude        uint64 = 0x8000000038000001
	ipLColon          uint64 = 0x400000000000000
	ipLAuthDelims     uint64 = 0x400000000000000
	ipHAuthDelims     uint64 = 0x28000001
	ipHIPv6Delims     uint64 = 0x28000000
	ipLSlash          uint64 = 0x800000000000
	ipHBackslash      uint64 = 0x10000000
	ipLNonPrintable   uint64 = 0xffffffff
	ipHNonPrintable   uint64 = 0x8000000000000000
	ipHUnwise         uint64 = 0x3800000178000000
	ipLExcludedDelims uint64 = 0x5000000500000000
	ipLFragment       uint64 = 0x0000000800000000
	ipLQuery          uint64 = 0x8000000000000000
	ipLHostnameMask          = ipLNonPrintable | ipLSlash | ipLExcludedDelims
	ipHHostnameMask          = ipHNonPrintable | ipHUnwise
	ipLScopeMask             = ipLNonPrintable | ipLSlash | ipLFragment | ipLQuery
	ipHScopeMask             = ipHNonPrintable | ipHIPv6Delims | ipHBackslash
)

// ipOthers は、IPAddressUtil が host に許さない、128 以上の文字である。並びは小さい順である。
var ipOthers = []uint16{8263, 8264, 8265, 8448, 8449, 8453, 8454, 10868, 65109, 65110, 65119, 65131, 65283, 65295, 65306, 65311, 65312}

// ipMatch は、IPAddressUtil.match の写しである。java.net.URI の match と違い、文字の番号が 0 の文字も、下位のマスクのビット0で見る。
func ipMatch(c uint16, low, high uint64) bool {
	switch {
	case c < 64:
		return (1<<c)&low != 0
	case c < 128:
		return (1<<(c-64))&high != 0
	}
	return false
}

// ipFound は、s に、マスクに当たる文字か others の文字があるかを返す。
func ipFound(s []uint16, low, high uint64, others []uint16) bool {
	for _, c := range s {
		if ipMatch(c, low, high) {
			return true
		}
		if _, found := slices.BinarySearch(others, c); found {
			return true
		}
	}
	return false
}

// javaCheckHost は、IPAddressUtil.checkHostString が文言を返さないか(host を受けるか)を返す。
// 早く読む既定の設定では、checkHostString は checkHost を呼ぶ。
func javaCheckHost(host []uint16) bool {
	if len(host) >= 2 && host[0] == '[' && host[len(host)-1] == ']' {
		s := host[1 : len(host)-1]
		if !javaIsIPv6LiteralAddress(s) {
			return false
		}
		if i := indexOfChar(s, '%', 0); i >= 0 {
			return !ipFound(s[i:], ipLScopeMask, ipHScopeMask, nil)
		}
		return true
	}
	return !ipFound(host, ipLExclude|ipLHostnameMask, ipHExclude|ipHHostnameMask, ipOthers)
}

// javaCheckUserInfo は、IPAddressUtil.checkUserInfo が文言を返さないかを返す。userinfo には ':' を許す。
func javaCheckUserInfo(s []uint16) bool {
	return !ipFound(s, ipLExclude&^ipLColon, ipHExclude, nil)
}

// javaCheckAuth は、IPAddressUtil.checkAuth が文言を返さないかを返す。権限の部分には "@[]:" を許す。
func javaCheckAuth(s []uint16) bool {
	return !ipFound(s, ipLExclude&^ipLAuthDelims, ipHExclude&^ipHAuthDelims, nil)
}

// javaIsIPv6LiteralAddress は、IPAddressUtil.isIPv6LiteralAddress(textToNumericFormatV6 が null を返さないか)の写しである。
// '%' よりあとの scope は読まない。
func javaIsIPv6LiteralAddress(src []uint16) bool {
	const inaddr16sz, int16sz, inaddr4sz = 16, 2, 4
	if len(src) < 2 {
		return false
	}
	n := len(src)
	pc := indexOfChar(src, '%', 0)
	if pc == n-1 {
		return false
	}
	if pc != -1 {
		n = pc
	}
	colonp := -1
	i, j := 0, 0
	if src[i] == ':' {
		i++
		if src[i] != ':' {
			return false
		}
	}
	curtok := i
	sawXdigit := false
	val := 0
	for i < n {
		ch := src[i]
		i++
		if d := ipHexDigit(ch); d != -1 {
			val = val<<4 | d
			if val > 0xffff {
				return false
			}
			sawXdigit = true
			continue
		}
		if ch == ':' {
			curtok = i
			if !sawXdigit {
				if colonp != -1 {
					return false
				}
				colonp = j
				continue
			} else if i == n {
				return false
			}
			if j+int16sz > inaddr16sz {
				return false
			}
			j += int16sz
			sawXdigit = false
			val = 0
			continue
		}
		if ch == '.' && j+inaddr4sz <= inaddr16sz {
			ia4 := src[curtok:n]
			if countChar(ia4, '.') != 3 || !javaIsIPv4LiteralAddress(ia4) {
				return false
			}
			j += inaddr4sz
			sawXdigit = false
			break
		}
		return false
	}
	if sawXdigit {
		if j+int16sz > inaddr16sz {
			return false
		}
		j += int16sz
	}
	if colonp != -1 {
		if j == inaddr16sz {
			return false
		}
		j = inaddr16sz
	}
	return j == inaddr16sz
}

func countChar(s []uint16, c uint16) int {
	n := 0
	for _, x := range s {
		if x == c {
			n++
		}
	}
	return n
}

// javaIsIPv4LiteralAddress は、IPAddressUtil.textToNumericFormatV4 が null を返さないかの写しである。
func javaIsIPv4LiteralAddress(src []uint16) bool {
	if len(src) == 0 || len(src) > 15 {
		return false
	}
	var tmp int64
	currByte := 0
	newOctet := true
	for _, c := range src {
		if c == '.' {
			if newOctet || tmp > 0xff || currByte == 3 {
				return false
			}
			currByte++
			tmp = 0
			newOctet = true
			continue
		}
		if c < '0' || c > '9' {
			return false
		}
		tmp = tmp*10 + int64(c-'0')
		newOctet = false
	}
	return !newOctet && tmp < 1<<((4-currByte)*8)
}

// ipHexDigit は、IPAddressUtil.parseAsciiHexDigit の写しである。Character.toLowerCase で小文字にした字が
// a から f なら、その値を返す。そうでなければ ASCII の10進の数字として読む。
func ipHexDigit(c uint16) int {
	l := unicode.ToLower(rune(c))
	if l >= 'a' && l <= 'f' {
		return int(l-'a') + 10
	}
	if c >= '0' && c <= '9' {
		return int(c - '0')
	}
	return -1
}

// -- Integer.parseInt --

// javaParseInt は、Integer.parseInt(s, 0, s の長さ, 10) の写しである。NumberFormatException が出る値には ok に false を返す。
// 数字は Character.digit で読むので、ASCII の数字のほかに、Unicode の10進の数字(Nd)のうち、UTF-16 の1単位で書ける文字も読む。
func javaParseInt(s []uint16) (v int, ok bool) {
	const minInt32, maxInt32 = -2147483648, 2147483647
	if len(s) == 0 {
		return 0, false
	}
	negative := false
	i := 0
	limit := -maxInt32
	if s[0] < '0' {
		switch s[0] {
		case '-':
			negative = true
			limit = minInt32
		case '+':
		default:
			return 0, false
		}
		i++
		if i == len(s) {
			return 0, false
		}
	}
	multmin := limit / 10
	result := 0
	for ; i < len(s); i++ {
		digit := javaDecimalDigit(s[i])
		if digit < 0 || result < multmin {
			return 0, false
		}
		result *= 10
		if result < limit+digit {
			return 0, false
		}
		result -= digit
	}
	if negative {
		return result, true
	}
	return -result, true
}

// javaDecimalDigit は、Character.digit(c, 10) の写しである。Unicode の10進の数字(Nd)の値を返し、ほかの文字には -1 を返す。
// Unicode は、10進の数字を0から9の順に10字ずつ続けて並べるので、続いた数字の先頭からの差を10で割った余りが値になる。
func javaDecimalDigit(c uint16) int {
	r := rune(c)
	if !unicode.IsDigit(r) {
		return -1
	}
	first := r
	for unicode.IsDigit(first - 1) {
		first--
	}
	return int(r-first) % 10
}
