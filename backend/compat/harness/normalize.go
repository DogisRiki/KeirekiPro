//go:build compat

package harness

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"time"
)

// 正規化とは、UUID や日時のように版ごとに違って当然の値を記号に置き換えて、比べる前に値の形をそろえることである。
// 置き換えのあとの記号は次の形である。
//   - UUID: <uuid:N>。N は、その版で現れた順の番号である
//   - 日時: <datetime:形>。形は、日付と時刻の区切り、秒の有無、時差の書き方である。小数の秒の桁は形に入れない
//   - JWT: <jwt:{...}>。中身の項目のうち iat と exp と jti を除き、exp から iat を引いた長さを exp-iat に入れる
//   - URL の中のトークン: <token:N>。N は、その版で現れた順の番号である
//   - bcrypt のハッシュ: <bcrypt:$2a$10$>。版と強さだけを残す
//   - 2段階認証の確認のコード: <code:N>。N は、その版で現れた順の番号である。件名が「2段階認証コードのお知らせ」の
//     メールの本文の1行目と、Redis のキー 2fa:<UUID> の値でだけ置き換える
//   - JWT の lexp: <lexp:+秒>。メールアドレスの確認のリンクの値の期限を、その版の応答を受けた時刻からの秒の差にする

var (
	uuidPattern     = regexp.MustCompile(`(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b`)
	datetimePattern = regexp.MustCompile(`\b(\d{4}-\d{2}-\d{2})([T ])(\d{2}:\d{2})(:\d{2})?(\.\d{1,9})?(Z|[+-]\d{2}:?\d{2})?`)
	jwtPattern      = regexp.MustCompile(`\beyJ[A-Za-z0-9_-]*\.eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+`)
	bcryptPattern   = regexp.MustCompile(`\$(2[aby]?)\$(\d{2})\$[./A-Za-z0-9]{53}`)
	urlPattern      = regexp.MustCompile(`https?://[^\s"'<>()]+`)
	// tokenPattern は、トークンとみなす語である。Java 版は、トークンを、32バイトの乱数を base64url にした43文字で作る。
	// 長さで絞るのは、画面が読む値(例: error=unverified_email)や問い合わせの名前を置き換えて、本当の違いを隠さないためである。
	tokenPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{43}$`)
	// twoFactorCodePattern は、2段階認証の確認のコードである。Java 版は、コードを6桁の数字で作る。
	twoFactorCodePattern = regexp.MustCompile(`\b[0-9]{6}\b`)
	// twoFactorKeyPattern は、Java 版が確認のコードを置く Redis のキー 2fa:<利用者の ID> である。
	twoFactorKeyPattern = regexp.MustCompile(`(?i)^2fa:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
	// lexpMarkerPattern は、JWT の lexp を置き換えた記号である。
	lexpMarkerPattern = regexp.MustCompile(`<lexp:([+-][0-9]+)>`)
)

// twoFactorMailSubject は、Java 版が確認のコードを送るメールの件名に含まれる文字である。
const twoFactorMailSubject = "2段階認証コードのお知らせ"

// Normalizer は、1つの版の値を正規化する。UUID とトークンの番号は、1つの筋書きの中で、その版で現れた順に付ける。
// 応答とデータベースと Redis と S3 とメールで同じ Normalizer を使うので、応答に現れた UUID は、データベースでも同じ番号になる。
type Normalizer struct {
	uuids  map[string]int
	tokens map[string]int
	codes  map[string]int
	// received は、JWT の lexp を差にするときの基準の時刻である。ふだんはその版の応答を最後に受けた時刻で、
	// メールを正規化する間だけ、そのメールを初めて見た段の応答の時刻にする。
	received time.Time
	// mailReceived は、i 通目のメールを初めて見た段の応答の時刻である。
	mailReceived []time.Time
}

// NewNormalizer は、番号を1つも付けていない Normalizer を作る。
func NewNormalizer() *Normalizer {
	return &Normalizer{uuids: map[string]int{}, tokens: map[string]int{}, codes: map[string]int{}}
}

// unknownUUID と unknownToken と unknownCode は、まだ番号を付けない値を、並べ替えのために仮に置き換える記号である。
const (
	unknownUUID  = "<uuid:?>"
	unknownToken = "<token:?>"
	unknownCode  = "<code:?>"
)

func (n *Normalizer) code(s string, assign bool) string {
	if num, ok := n.codes[s]; ok {
		return fmt.Sprintf("<code:%d>", num)
	}
	if !assign {
		return unknownCode
	}
	n.codes[s] = len(n.codes) + 1
	return fmt.Sprintf("<code:%d>", n.codes[s])
}

// twoFactorCodes は、文字列の中の6桁の数字を <code:N> に置き換える。呼ぶ側が、確認のコードの置かれる場所でだけ呼ぶ。
func (n *Normalizer) twoFactorCodes(s string, assign bool) string {
	return twoFactorCodePattern.ReplaceAllStringFunc(s, func(m string) string { return n.code(m, assign) })
}

// redisValue は、Redis のキー key の値 value のうち、確認のコードを置き換える。キーが 2fa:<UUID> のときだけ置き換える。
func (n *Normalizer) redisValue(key, value string, assign bool) string {
	if !twoFactorKeyPattern.MatchString(key) {
		return value
	}
	return n.twoFactorCodes(value, assign)
}

// mailText は、件名 subject のメールの本文 text のうち、確認のコードを置き換える。
// 件名が2段階認証のメールのときだけ、本文の1行目を置き換える。
func (n *Normalizer) mailText(subject, text string) string {
	if !strings.Contains(subject, twoFactorMailSubject) {
		return text
	}
	first, rest, found := strings.Cut(text, "\n")
	first = n.twoFactorCodes(first, true)
	if !found {
		return first
	}
	return first + "\n" + rest
}

// atMail は、i 通目のメールを初めて見た段の応答の時刻を lexp の基準にして f を呼び、基準を戻す。
// メールは段をまたいで残るので、あとの段で同じメールを比べても、lexp の差が変わらないようにする。
func (n *Normalizer) atMail(i int, f func()) {
	for len(n.mailReceived) <= i {
		n.mailReceived = append(n.mailReceived, n.received)
	}
	received := n.received
	n.received = n.mailReceived[i]
	defer func() { n.received = received }()
	f()
}

func (n *Normalizer) uuid(s string, assign bool) string {
	key := strings.ToLower(s)
	if num, ok := n.uuids[key]; ok {
		return fmt.Sprintf("<uuid:%d>", num)
	}
	if !assign {
		return unknownUUID
	}
	n.uuids[key] = len(n.uuids) + 1
	return fmt.Sprintf("<uuid:%d>", n.uuids[key])
}

func (n *Normalizer) token(s string, assign bool) string {
	if num, ok := n.tokens[s]; ok {
		return fmt.Sprintf("<token:%d>", num)
	}
	if !assign {
		return unknownToken
	}
	n.tokens[s] = len(n.tokens) + 1
	return fmt.Sprintf("<token:%d>", n.tokens[s])
}

// Text は、文字列の中の JWT と bcrypt のハッシュと UUID と日時を置き換える。番号の無い UUID には、現れた順に番号を付ける。
func (n *Normalizer) Text(s string) string {
	return n.text(s, true)
}

func (n *Normalizer) text(s string, assign bool) string {
	s = jwtPattern.ReplaceAllStringFunc(s, func(m string) string { return n.jwt(m, assign) })
	s = bcryptPattern.ReplaceAllString(s, "<bcrypt:$$$1$$$2$$>")
	s = uuidPattern.ReplaceAllStringFunc(s, func(m string) string { return n.uuid(m, assign) })
	return datetimePattern.ReplaceAllStringFunc(s, datetimeShape)
}

// datetimeShape は、日時を、形を確かめてから記号に置き換える。日付が暦に無いときは、形が誤っているので置き換えない。
// 両方の版で同じ時刻にするのはむずかしいので、時刻そのものは比べない。
func datetimeShape(m string) string {
	parts := datetimePattern.FindStringSubmatch(m)
	if _, err := time.Parse(time.DateOnly, parts[1]); err != nil {
		return m
	}
	if _, err := time.Parse("15:04", parts[3]); err != nil {
		return m
	}
	shape := "yyyy-MM-dd" + parts[2] + "HH:mm"
	if parts[4] != "" {
		shape += ":ss"
	}
	switch zone := parts[6]; {
	case zone == "Z":
		shape += "Z"
	case strings.Contains(zone, ":"):
		shape += "+hh:mm"
	case zone != "":
		shape += "+hhmm"
	}
	return "<datetime:" + shape + ">"
}

// jwt は、JWT を中身の項目に置き換える。頭の部分に alg の無いものと、読めないものは、JWT でないとみなして元のまま返す。
func (n *Normalizer) jwt(m string, assign bool) string {
	parts := strings.Split(m, ".")
	var header map[string]any
	if !decodeSegment(parts[0], &header) || header["alg"] == nil {
		return m
	}
	var claims map[string]any
	if !decodeSegment(parts[1], &claims) {
		return m
	}
	iat, iatOK := claims["iat"].(json.Number)
	exp, expOK := claims["exp"].(json.Number)
	delete(claims, "iat")
	delete(claims, "exp")
	delete(claims, "jti")
	if iatOK && expOK {
		i, errI := iat.Int64()
		e, errE := exp.Int64()
		if errI == nil && errE == nil {
			claims["exp-iat"] = e - i
		}
	}
	// メールアドレスの確認のリンクの値は iat も exp も持たないので、期限 lexp を、応答を受けた時刻からの差にする。
	// 差のずれは、比べる処理が sameNormalized で許す
	if lexp, ok := claims["lexp"].(json.Number); ok {
		if v, err := lexp.Int64(); err == nil {
			claims["lexp"] = fmt.Sprintf("<lexp:%+d>", v-n.received.Unix())
		}
	}
	return "<jwt:" + canonicalJSON(n.value(claims, assign)) + ">"
}

func decodeSegment(segment string, v any) bool {
	raw, err := base64.RawURLEncoding.DecodeString(segment)
	if err != nil {
		return false
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	return dec.Decode(v) == nil
}

// value は、JSON を解析した値の中の文字列を正規化する。オブジェクトの項目は、名前の順にたどる。
func (n *Normalizer) value(v any, assign bool) any {
	switch t := v.(type) {
	case string:
		return n.text(t, assign)
	case []any:
		out := make([]any, len(t))
		for i, item := range t {
			out[i] = n.value(item, assign)
		}
		return out
	case map[string]any:
		out := make(map[string]any, len(t))
		for _, k := range sortedKeys(t) {
			out[k] = n.value(t[k], assign)
		}
		return out
	default:
		return v
	}
}

// URLs は、文字列の中の URL のパスの区切りと問い合わせの値と # のあとの値のうち、トークンとみなす語を <token:N> に置き換える。
// URL の中の JWT と UUID も置き換える。問い合わせの名前と、URL の外の文字は変えない。
func (n *Normalizer) URLs(s string) string {
	return n.urls(s, true)
}

func (n *Normalizer) urls(s string, assign bool) string {
	word := func(w string) string { return n.word(w, assign) }
	// pair は、名前=値 の組の値だけを置き換える。= の無い部分は変えない。
	pair := func(p string) string {
		name, value, ok := strings.Cut(p, "=")
		if !ok {
			return p
		}
		return name + "=" + word(value)
	}
	// fragmentPart は、# のあとの部分を置き換える。= の無い部分は、メールアドレスの確認のリンク /email/verify#<値> の
	// ように、部分そのものを値とみなす。
	fragmentPart := func(p string) string {
		if strings.Contains(p, "=") {
			return pair(p)
		}
		return word(p)
	}
	return urlPattern.ReplaceAllStringFunc(s, func(u string) string {
		rest, fragment, hasFragment := strings.Cut(u, "#")
		path, query, hasQuery := strings.Cut(rest, "?")
		out := splitReplace(path, "/;", word)
		// 問い合わせは、名前=値 の組を & か ; で区切ったものとみなす。# のあとは、# でも区切る
		if hasQuery {
			out += "?" + splitReplace(query, "&;", pair)
		}
		if hasFragment {
			out += "#" + splitReplace(fragment, "&;#", fragmentPart)
		}
		return out
	})
}

// uuidsIn は、文字列の中の UUID だけを番号に置き換える。S3 のキーに使う。
func (n *Normalizer) uuidsIn(s string, assign bool) string {
	return uuidPattern.ReplaceAllStringFunc(s, func(m string) string { return n.uuid(m, assign) })
}

// words は、区切り seps で分けた語のうち、トークンとみなす語を置き換える。Redis のキーと値に使う。
func (n *Normalizer) words(s, seps string, assign bool) string {
	return splitReplace(n.text(s, assign), seps, func(word string) string { return n.word(word, assign) })
}

func (n *Normalizer) word(w string, assign bool) string {
	switch {
	case jwtPattern.MatchString(w) || uuidPattern.MatchString(w):
		return n.text(w, assign)
	case tokenPattern.MatchString(w):
		return n.token(w, assign)
	default:
		return w
	}
}

// splitReplace は、s を seps のどれかの文字で分け、区切りの文字は残したまま、分けた語ごとに f で置き換える。
func splitReplace(s, seps string, f func(string) string) string {
	var b strings.Builder
	start := 0
	for i, r := range s {
		if strings.ContainsRune(seps, r) {
			b.WriteString(f(s[start:i]))
			b.WriteRune(r)
			start = i + len(string(r))
		}
	}
	b.WriteString(f(s[start:]))
	return b.String()
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	return keys
}

// normalizedRecord は、正規化した1つの記録と、元の並びでの位置である。
type normalizedRecord struct {
	Text  string
	Index int
}

// normalizeRecords は、データベースの行や Redis の値のような、並びに意味の無い記録の並びを正規化する。
// 応答に現れない UUID とトークンには、記録のほかの値の順に番号を付ける。そのため、まず番号の無い UUID とトークンを
// 仮の記号に置き換えて並べ替え、その順に記録をたどって番号を付ける。返す並びは、正規化したあとの値で並べ替えてある。
// f は、1つの記録を、assign が false なら仮の記号で、true なら番号を付けて、比べる文字列にする。
func normalizeRecords[T any](records []T, f func(T, bool) string) []normalizedRecord {
	order := make([]normalizedRecord, len(records))
	for i, r := range records {
		order[i] = normalizedRecord{Text: f(r, false), Index: i}
	}
	slices.SortStableFunc(order, compareRecords)
	for i := range order {
		order[i].Text = f(records[order[i].Index], true)
	}
	slices.SortStableFunc(order, compareRecords)
	return order
}

func compareRecords(a, b normalizedRecord) int {
	return strings.Compare(a.Text, b.Text)
}

// canonicalJSON は、v を項目の名前の順の JSON にする。
func canonicalJSON(v any) string {
	var b strings.Builder
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return fmt.Sprintf("%v", v)
	}
	return strings.TrimSuffix(b.String(), "\n")
}
