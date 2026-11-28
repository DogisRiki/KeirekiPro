package auth

import (
	"net/netip"
	"regexp"
	"strings"
	"unicode"

	"golang.org/x/net/idna"
	"golang.org/x/net/publicsuffix"
)

// 保存するメールアドレスの誤りの文言である。
const (
	messageEmailBlank   = "メールアドレスが空です。"
	messageEmailInvalid = "メールアドレスの形式が不正です。"
)

var (
	// formatIDNA は、入力の検査で、ドメインの部分を ASCII の形に変える。ドメインの部分の正規表現が許す記号を断らないよう、
	// ラベルを英字と数字と「-」に限る決まりと、ラベルの端の「-」の決まりを当てない。ラベルと全体の長さは確かめる。
	formatIDNA = idna.New(idna.MapForLookup(), idna.StrictDomainName(false), idna.CheckHyphens(false),
		idna.BidiRule(), idna.VerifyDNSLength(true))
	// storedIDNA は、保存するメールアドレスのドメインの部分を ASCII の形に変える。ラベルは英字と数字と「-」に限る。
	storedIDNA = idna.New(idna.MapForLookup(), idna.BidiRule(), idna.VerifyDNSLength(true))
)

// メールアドレスの形の正規表現である。前の部分は、英字と数字と記号と U+0080 から U+FFFF までの字の並びを「.」でつないだものか、
// 「"」で囲んだ並びとする。後ろの部分は、同じような字の並びを「-」と「.」でつないだ名前か、角括弧で囲んだ IP アドレスとする。
// 英字は、大文字と小文字の両方を書く。
const (
	emailLocalAtom   = "[a-zA-Z0-9!#$%&'*+/=?^_`{|}~\\x{80}-\\x{FFFF}-]"
	emailQuotedAtom  = "(?:[a-zA-Z0-9!#$%&'*.(),<>\\[\\]:;  @+/=?^_`{|}~\\x{80}-\\x{FFFF}-]|\\\\\\\\|\\\\\")"
	emailLocalWord   = "(?:" + emailLocalAtom + "+|\"" + emailQuotedAtom + "+\")"
	emailDomainChars = "[a-zA-Z\\x{80}-\\x{FFFF}0-9!#$%&'*+/=?^_`{|}~]"
	emailDomainLabel = emailDomainChars + "+(?:-+" + emailDomainChars + "+)*"
	emailIPv4        = "[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}"
	emailIPv6Octet   = "(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])"
	emailIPv6        = "(?:(?:[0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,7}:|" +
		"(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}|" +
		"(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}|(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}|" +
		"(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(?:(?::[0-9a-fA-F]{1,4}){1,6})|" +
		":(?:(?::[0-9a-fA-F]{1,4}){1,7}|:)|[fF][eE]80:(?::[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|" +
		"::(?:[fF][fF][fF][fF](:0{1,4}){0,1}:){0,1}(?:" + emailIPv6Octet + "\\.){3,3}" + emailIPv6Octet + "|" +
		"(?:[0-9a-fA-F]{1,4}:){1,4}:(?:" + emailIPv6Octet + "\\.){3,3}" + emailIPv6Octet + ")"
)

var (
	emailLocalPartPattern = regexp.MustCompile("^" + emailLocalWord + "(?:\\." + emailLocalWord + ")*$")
	emailDomainPattern    = regexp.MustCompile("^(?:" + emailDomainLabel + "(?:\\." + emailDomainLabel + ")*" +
		"|\\[" + emailIPv4 + "\\]|\\[[iI][pP][vV]6:" + emailIPv6 + "\\])$")
)

// isEmailFormat は、s がメールアドレスの形かを返す。空の値は誤りにしない。
// 最後の @ で分け、前の部分は64文字以内で正規表現に当たること、後ろの部分は、末尾が「.」でなく、正規表現に当たり、
// 角括弧で囲んだ IP アドレスでなければ ASCII の形に変えられることを求める。
func isEmailFormat(s string) bool {
	if s == "" {
		return true
	}
	at := strings.LastIndexByte(s, '@')
	if at < 0 {
		return false
	}
	local, domain := s[:at], s[at+1:]
	if utf16Len(local) > emailLocalPartMaxLength || !emailLocalPartPattern.MatchString(local) {
		return false
	}
	if strings.HasSuffix(domain, ".") || !emailDomainPattern.MatchString(domain) {
		return false
	}
	if strings.HasPrefix(domain, "[") {
		return true
	}
	_, err := formatIDNA.ToASCII(domain)
	return err == nil
}

// emailErrors は、登録と設定で保存するメールアドレスの誤りの文言を返す。誤りが無ければ nil を返す。
// 形の検査(isEmailFormat)に加えて、ドメインの部分が保存できる形(storableDomain)であることを求める。
func emailErrors(email string) []string {
	if !notBlank(email) {
		return []string{messageEmailBlank}
	}
	if !isEmailFormat(email) || !storableDomain(email[strings.LastIndexByte(email, '@')+1:]) {
		return []string{messageEmailInvalid}
	}
	return nil
}

// storableDomain は、ドメインの部分が、角括弧で囲んだ IP アドレスか、英字と数字と「-」のラベルを2つ以上「.」でつなぎ、
// 末尾のラベルが実在するトップレベルドメイン(Public Suffix List の ICANN の項目)であるかを返す。
// 見えない字(書式の字と異体字の選択子など)を含むドメインは、ASCII の形に変えると字が消え、保存する値と送り先が食い違うので断る。
// 角括弧の中は、頭の「IPv6:」(大文字と小文字を問わない)を除いて、IP アドレスとして読めるかを確かめる。
// IPv4 か IPv6 かの形は、先に形の検査(isEmailFormat)の正規表現が確かめる。
func storableDomain(domain string) bool {
	if inner, ok := strings.CutPrefix(domain, "["); ok {
		inner = strings.TrimSuffix(inner, "]")
		if len(inner) >= 5 && strings.EqualFold(inner[:5], "IPv6:") {
			inner = inner[5:]
		}
		_, err := netip.ParseAddr(inner)
		return err == nil
	}
	if strings.ContainsFunc(domain, isInvisible) {
		return false
	}
	ascii, err := storedIDNA.ToASCII(domain)
	dot := strings.LastIndexByte(ascii, '.')
	if err != nil || dot < 0 {
		return false
	}
	// 「x」を前に付けるのは、「*.ck」のように、トップレベルドメインの下の名前だけを項目に持つ国のドメインも当てるためである。
	_, icann := publicsuffix.PublicSuffix("x" + ascii[dot:])
	return icann
}

// isInvisible は、r が、画面に見えず、ドメインの名前を ASCII の形に変えると消える字かを返す。
func isInvisible(r rune) bool {
	return unicode.In(r, unicode.Cf, unicode.Variation_Selector, unicode.Other_Default_Ignorable_Code_Point)
}
