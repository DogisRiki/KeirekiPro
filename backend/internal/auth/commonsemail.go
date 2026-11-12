package auth

import (
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

// このファイルは、Java 版の登録の受け付け(UserRegistrationUseCase)が呼ぶ Email.create の確かめを写す。
// Email.create は、Apache Commons Validator 1.11.0 の EmailValidator.getInstance(false, false) を使う。
// 入力の検査(Hibernate Validator の @Email。validate.go の isEmailLikeHibernate)とは別の確かめで、
// Hibernate が通しても、こちらが断るメールアドレスがある(たとえば、知らないトップレベルドメイン)。
// 呼ぶ側は、入力の検査を先に通す。入力の検査は、ドメインの部分の基本多言語面(U+0000 から U+FFFF)の外の文字を断るので、
// commonsUnicodeToASCII は、その文字を含むドメインを変えずに返す(Java 版は java.net.IDN で変えうる)。
// トップレベルドメインの表は commons_tld_table.go にあり、testdata/commonsemail/Gen.java で作る。

// Java の正規表現の文字の種類を、Go の正規表現で書いたもの。
const (
	// javaDot は、Java の「.」(UNIX_LINES なし)が当たる文字である。行の終わりの文字を除く。
	javaDot = `[^\n\r\x{85}\x{2028}\x{2029}]`
	// javaSpaceChars は、Java の「\s」(UNICODE_CHARACTER_CLASS なし)が当たる文字である。Go の「\s」は \x0B を含まない。
	javaSpaceChars = `\t\n\x0B\f\r `
)

// Commons Validator の EmailValidator と InetAddressValidator と DomainValidator の正規表現を写したもの。
// DomainValidator のラベルの正規表現の (?>...) は、ラベルが「.」を含まないので、ふつうのまとまりと同じ結果になる。
const (
	commonsValidChars   = `(?:\\[^\p{Cc}]|[^` + javaSpaceChars + `\p{Cc}()<>@,;:'\\".\[\]])`
	commonsQuotedUser   = `(?:"(?:\\"|[^"\p{Cc}])*")`
	commonsWord         = `(?:(?:` + commonsValidChars + `|')+|` + commonsQuotedUser + `)`
	commonsDomainLabel  = `[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?`
	commonsTopLabel     = `[a-zA-Z](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?`
	commonsMaxUserLen   = 64
	commonsMaxDomainLen = 253
)

var (
	commonsEmailPattern    = regexp.MustCompile(`^(` + javaDot + `+)@([^` + javaSpaceChars + `]+)$`)
	commonsIPDomainPattern = regexp.MustCompile(`^\[([iI][pP][vV]6:)?(` + javaDot + `*)\]$`)
	commonsUserPattern     = regexp.MustCompile(`^` + commonsWord + `(?:\.` + commonsWord + `)*$`)
	commonsDomainPattern   = regexp.MustCompile(`^(?:` + commonsDomainLabel + `\.)+(` + commonsTopLabel + `)\.?$`)
	commonsIPv4Pattern     = regexp.MustCompile(`^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$`)
	commonsPrefixPattern   = regexp.MustCompile(`^[0-9]{1,3}$`)
	commonsZonePattern     = regexp.MustCompile(`^[^` + javaSpaceChars + `/%]+$`)
	commonsTLDSet          = func() map[string]bool {
		m := make(map[string]bool, len(commonsTLDs))
		for _, t := range commonsTLDs {
			m[t] = true
		}
		return m
	}()
)

// Java 版の Email.create が項目 email に書く文言である。
const (
	messageEmailBlank   = "メールアドレスが空です。"
	messageEmailInvalid = "メールアドレスの形式が不正です。"
)

// emailCreateErrors は、Java 版の Email.create と同じく、メールアドレスの誤りの文言を返す。誤りが無ければ nil を返す。
func emailCreateErrors(email string) []string {
	if !notBlank(email) {
		return []string{messageEmailBlank}
	}
	if !commonsEmailValid(email) {
		return []string{messageEmailInvalid}
	}
	return nil
}

// commonsEmailValid は、EmailValidator.isValid と同じく、末尾が「.」でなく、最後の @ で分けた前の部分と後ろの部分が
// それぞれ正しいかを返す。後ろの部分は、Java の「\s」に当たる文字を含まない。
func commonsEmailValid(email string) bool {
	if strings.HasSuffix(email, ".") {
		return false
	}
	m := commonsEmailPattern.FindStringSubmatch(email)
	return m != nil && commonsUserValid(m[1]) && commonsDomainValid(m[2])
}

// commonsUserValid は、EmailValidator.isValidUser と同じく、前の部分が UTF-16 の単位で64以内で、正規表現に当たるかを返す。
func commonsUserValid(user string) bool {
	return utf16Len(user) <= commonsMaxUserLen && commonsUserPattern.MatchString(user)
}

// commonsDomainValid は、EmailValidator.isValidDomain と同じく、角括弧で囲んだ IP アドレスか、
// DomainValidator(ローカルの名前を許さない)が受け付けるドメインかを返す。
// 角括弧の中は、「IPv6:」(大文字と小文字を問わない)で始まれば IPv6、そうでなければ IPv4 として確かめる。
func commonsDomainValid(domain string) bool {
	if m := commonsIPDomainPattern.FindStringSubmatchIndex(domain); m != nil {
		inner := domain[m[4]:m[5]]
		if m[2] >= 0 {
			return commonsInet6Valid(inner)
		}
		return commonsInet4Valid(inner)
	}
	ascii := commonsUnicodeToASCII(domain)
	if utf16Len(ascii) > commonsMaxDomainLen {
		return false
	}
	m := commonsDomainPattern.FindStringSubmatch(ascii)
	return m != nil && commonsTLDSet[strings.ToLower(m[1])]
}

// commonsUnicodeToASCII は、DomainValidator.unicodeToASCII と同じく、ドメインを ASCII の形に変える。変えられないときと、
// 次のときは、入力を変えずに返す。
//   - 書式の文字(Cf)か、nameprep が消す文字(U+034F、U+1806、U+180B から U+180D、U+FE00 から U+FE0F)を含む
//   - どれかのラベルが「-」で始まるか終わる
//   - 基本多言語面の外の文字を含む(このファイルの初めの説明のとおり、入力の検査が先に断る)
func commonsUnicodeToASCII(input string) string {
	runes := []rune(input)
	if isAllASCII(runes) {
		return input
	}
	for _, r := range runes {
		if r > 0xFFFF || unicode.Is(unicode.Cf, r) || commonsNameprepMappedToNothing(r) {
			return input
		}
	}
	if commonsLabelBoundaryHyphen(runes) {
		return input
	}
	ascii, ok := idnaToASCII(input)
	if !ok {
		return input
	}
	return ascii
}

// commonsNameprepMappedToNothing は、DomainValidator.isNameprepMappedToNothing と同じく、nameprep が消す文字のうち、
// 書式の文字(Cf)でないものかを返す。
func commonsNameprepMappedToNothing(r rune) bool {
	return r == 0x034F || r == 0x1806 || (r >= 0x180B && r <= 0x180D) || (r >= 0xFE00 && r <= 0xFE0F)
}

// commonsLabelBoundaryHyphen は、DomainValidator.hasLabelBoundaryHyphen と同じく、どれかのラベルが「-」で始まるか
// 終わるかを返す。ラベルの区切りは、java.net.IDN と同じ4つの文字である。
func commonsLabelBoundaryHyphen(runes []rune) bool {
	labelStart := true
	for i, r := range runes {
		if isIDNADot(r) {
			if i > 0 && runes[i-1] == '-' {
				return true
			}
			labelStart = true
			continue
		}
		if labelStart && r == '-' {
			return true
		}
		labelStart = false
	}
	return len(runes) > 0 && runes[len(runes)-1] == '-'
}

// commonsInet4Valid は、InetAddressValidator.isValidInet4Address と同じく、4つの数が255以下で、2桁以上の数が0で
// 始まらないかを返す。
func commonsInet4Valid(s string) bool {
	m := commonsIPv4Pattern.FindStringSubmatch(s)
	if m == nil {
		return false
	}
	for _, seg := range m[1:] {
		n, _ := strconv.Atoi(seg)
		if n > 255 || (len(seg) > 1 && seg[0] == '0') {
			return false
		}
	}
	return true
}

// commonsInet6Valid は、InetAddressValidator.isValidInet6Address と同じ順と条件で、IPv6 のアドレスかを返す。
// 「/」のあとの長さと「%」のあとの区域の名前を受け付け、最後のまとまりに IPv4 のアドレスを書ける。
func commonsInet6Valid(s string) bool {
	parts := strings.Split(s, "/")
	if len(parts) > 2 {
		return false
	}
	if len(parts) == 2 {
		if !commonsPrefixPattern.MatchString(parts[1]) {
			return false
		}
		if bits, _ := strconv.Atoi(parts[1]); bits > 128 {
			return false
		}
	}
	parts = strings.Split(parts[0], "%")
	if len(parts) > 2 || (len(parts) == 2 && !commonsZonePattern.MatchString(parts[1])) {
		return false
	}
	addr := parts[0]
	compressed := strings.Contains(addr, "::")
	if compressed && strings.Index(addr, "::") != strings.LastIndex(addr, "::") {
		return false
	}
	startsCompressed := strings.HasPrefix(addr, "::")
	endsCompressed := strings.HasSuffix(addr, "::")
	if (strings.HasPrefix(addr, ":") && !startsCompressed) || (strings.HasSuffix(addr, ":") && !endsCompressed) {
		return false
	}
	octets := javaSplit(addr, ":")
	if compressed {
		if endsCompressed {
			octets = append(octets, "")
		} else if startsCompressed && len(octets) > 0 {
			octets = octets[1:]
		}
	}
	if len(octets) > 8 {
		return false
	}
	valid, empty := 0, 0
	for i, octet := range octets {
		if javaTrim(octet) == "" {
			empty++
			if empty > 1 {
				return false
			}
			valid++
			continue
		}
		empty = 0
		if i == len(octets)-1 && strings.Contains(octet, ".") {
			if !commonsInet4Valid(octet) {
				return false
			}
			valid += 2
			continue
		}
		if len(octet) > 4 || !isASCIIHex(octet) {
			return false
		}
		valid++
	}
	return valid <= 8 && (valid == 8 || compressed)
}

// isASCIIHex は、s が ASCII の16進の数字だけでできているかを返す。s は空でない。
func isASCIIHex(s string) bool {
	for i := 0; i < len(s); i++ {
		c := s[i]
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') && (c < 'A' || c > 'F') {
			return false
		}
	}
	return true
}

// javaSplit は、Java の String.split(sep)(正規表現の特別な意味を持たない1文字の sep)と同じく、s を sep で分け、
// 末尾の空の文字列を除く。sep を含まないときは、s だけの並びを返す。
func javaSplit(s, sep string) []string {
	if !strings.Contains(s, sep) {
		return []string{s}
	}
	parts := strings.Split(s, sep)
	for len(parts) > 0 && parts[len(parts)-1] == "" {
		parts = parts[:len(parts)-1]
	}
	return parts
}
