//go:build compat

package harness

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"maps"
	"net/http"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
)

// 偽の送信の検査で、画面が Cookie からヘッダへ写す名前である。Java 版と Go 版で同じ名前を使う。
const (
	csrfCookie = "XSRF-TOKEN"
	csrfHeader = "X-XSRF-TOKEN"
)

// maxResponseBody は、1つの応答の本文を読む上限である。PDF の出力を含めて、これを超える応答は無い。
const maxResponseBody = 64 << 20

// pathVariable は、要求のパスの中の、段で取り出した値を差し込む場所 {名前} である。
var pathVariable = regexp.MustCompile(`\{([A-Za-z_][A-Za-z0-9_]*)\}`)

// Session は、1つの利用者として要求を送るときの、Cookie と、段で取り出した値である。
// ブラウザと同じく、Cookie は名前とパスごとに1つ覚え、要求のパスに当たる Cookie だけを送る。
// 版をまたぐ動かし方では、1つの利用者が、どちらの版に届くかを選べないので、2つの版に1つの Session を使う。
type Session struct {
	cookies map[cookieKey]string
	vars    map[string]string
	now     func() time.Time
	// mail は、取り出しの元 mail: で読むメールの読み方である。SetMailReader で決める。
	mail MailReader
}

// cookieKey は、覚える Cookie の名前と、当てはめるパスである。
type cookieKey struct{ name, path string }

// sessionCookie は、要求に付けて送る Cookie の名前と値と、当てはめるパスである。
type sessionCookie struct{ name, value, path string }

// NewSession は、Cookie も取り出した値も無い Session を返す。
func NewSession() *Session {
	return &Session{cookies: map[cookieKey]string{}, vars: map[string]string{}, now: time.Now}
}

// Clone は、今の Cookie と取り出した値を写した、別の Session を返す。
// 1つの Session は同時に使えないので、同じ利用者として同時に要求を送るときは、要求ごとに写しを使う。
func (s *Session) Clone() *Session {
	c := &Session{cookies: make(map[cookieKey]string, len(s.cookies)), vars: make(map[string]string, len(s.vars)), now: s.now, mail: s.mail}
	maps.Copy(c.cookies, s.cookies)
	maps.Copy(c.vars, s.vars)
	return c
}

// Send は、段 step の要求を baseURL の版に送り、応答を返す。応答の Set-Cookie を覚え、capture の値を取り出す。
// パスと本文の文字列の値とヘッダの値の {名前} は、前の段で取り出した値に置き換える。要求の Host は CompatHost にする。
// 要求を作れないとき、送れないとき、capture の値が無いときは、エラーを返す。
func (s *Session) Send(ctx context.Context, client *http.Client, baseURL string, step Step) (Response, error) {
	path, err := s.expand(step, "パス", step.Request.Path)
	if err != nil {
		return Response{}, err
	}
	return s.send(ctx, client, strings.TrimSuffix(baseURL, "/")+path, step, true)
}

// send は、段 step の要求を target に送る。toVersion が真なら、版に送る要求として、Host を CompatHost にし、
// Cookie の束の Cookie と csrf のヘッダを付け、応答の Set-Cookie を覚える。偽なら、Cookie の束を使わない。
func (s *Session) send(ctx context.Context, client *http.Client, target string, step Step, toVersion bool) (Response, error) {
	headers := make(map[string]string, len(step.Request.Headers))
	for _, name := range sortedKeys(step.Request.Headers) {
		v, err := s.expand(step, "ヘッダ "+name+" の値", step.Request.Headers[name])
		if err != nil {
			return Response{}, err
		}
		headers[name] = v
	}
	b, contentType, err := s.requestBody(step)
	if err != nil {
		return Response{}, err
	}
	var body io.Reader
	if b != nil {
		body = bytes.NewReader(b)
	}
	// 取り出しの元 mail: は、この段のあとに届いたメールから取り出すので、送る前のメールの数を数えておく
	mailsBefore := 0
	wantMail := capturesMail(step)
	if wantMail {
		mails, err := s.readMails(ctx, step)
		if err != nil {
			return Response{}, err
		}
		mailsBefore = len(mails)
	}
	req, err := http.NewRequestWithContext(ctx, step.Request.Method, target, body)
	if err != nil {
		return Response{}, fmt.Errorf("harness: 段 %s の要求を作れません: %w", step.Name, err)
	}
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	for _, name := range sortedKeys(headers) {
		req.Header.Set(name, headers[name])
	}
	if toVersion {
		if err := s.prepareVersionRequest(req, step); err != nil {
			return Response{}, err
		}
	}

	resp, err := client.Do(req)
	if err != nil {
		return Response{}, fmt.Errorf("harness: 段 %s の要求を送れません: %w", step.Name, err)
	}
	defer func() { _ = resp.Body.Close() }()
	respBody, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBody))
	if err != nil {
		return Response{}, fmt.Errorf("harness: 段 %s の応答を読めません: %w", step.Name, err)
	}
	out := Response{Status: resp.StatusCode, Header: resp.Header.Clone(), Body: respBody, Received: s.now()}
	if toVersion {
		s.storeCookies(resp.Cookies())
	}
	var newMails []fakeaws.Email
	if wantMail {
		mails, err := s.readMails(ctx, step)
		if err != nil {
			return out, err
		}
		newMails = mails[min(mailsBefore, len(mails)):]
	}
	if err := s.capture(step, out, newMails); err != nil {
		return out, err
	}
	return out, nil
}

// prepareVersionRequest は、版に送る要求 req の Host を CompatHost にし、Cookie の束の Cookie と csrf のヘッダを付ける。
func (s *Session) prepareVersionRequest(req *http.Request, step Step) error {
	// Go の http.Client は、ヘッダの Host を使わず req.Host を使う
	req.Host = CompatHost
	// ブラウザと同じく、送る Cookie を1つの Cookie ヘッダに「名前=値」を「; 」でつないで書く
	var pairs []string
	if h := req.Header.Get("Cookie"); h != "" {
		pairs = append(pairs, h)
	}
	for _, c := range s.cookiesFor(req.URL.Path) {
		pairs = append(pairs, c.name+"="+c.value)
	}
	if len(pairs) > 0 {
		req.Header.Set("Cookie", strings.Join(pairs, "; "))
	}
	if step.Request.CSRF {
		token, ok := s.cookie(csrfCookie, req.URL.Path)
		if !ok {
			return fmt.Errorf("harness: 段 %s は csrf を求めますが、Cookie %s がありません", step.Name, csrfCookie)
		}
		req.Header.Set(csrfHeader, token)
	}
	return nil
}

// storeCookies は、応答の Set-Cookie を覚える。Max-Age が0以下か、期限の過ぎた Cookie は、同じ名前とパスの Cookie を消す。
func (s *Session) storeCookies(cookies []*http.Cookie) {
	for _, c := range cookies {
		path := c.Path
		if path == "" || !strings.HasPrefix(path, "/") {
			path = "/"
		}
		key := cookieKey{name: c.Name, path: path}
		if c.MaxAge < 0 || (!c.Expires.IsZero() && !c.Expires.After(s.now())) {
			delete(s.cookies, key)
			continue
		}
		s.cookies[key] = c.Value
	}
}

// cookiesFor は、要求のパス path に送る Cookie を、パスの長い順に返す。パスの長さが同じときは名前の順に並べる。
func (s *Session) cookiesFor(path string) []sessionCookie {
	var out []sessionCookie
	for key, value := range s.cookies {
		if pathMatches(key.path, path) {
			out = append(out, sessionCookie{name: key.name, value: value, path: key.path})
		}
	}
	slices.SortFunc(out, func(a, b sessionCookie) int {
		if d := len(b.path) - len(a.path); d != 0 {
			return d
		}
		return strings.Compare(a.name, b.name)
	})
	return out
}

// cookie は、要求のパス path に送る、名前 name の Cookie の値を返す。
func (s *Session) cookie(name, path string) (string, bool) {
	for _, c := range s.cookiesFor(path) {
		if c.name == name {
			return c.value, true
		}
	}
	return "", false
}

// pathMatches は、RFC 6265 の 5.1.4 の決まりで、Cookie のパス cookiePath が要求のパス requestPath に当たるかを返す。
func pathMatches(cookiePath, requestPath string) bool {
	if requestPath == "" {
		requestPath = "/"
	}
	if !strings.HasPrefix(requestPath, cookiePath) {
		return false
	}
	return len(requestPath) == len(cookiePath) || strings.HasSuffix(cookiePath, "/") || requestPath[len(cookiePath)] == '/'
}

// captureValue は、JSON の場所 path にある1つの文字か数か真偽の値を、文字にして返す。
func captureValue(v any, path string) (string, error) {
	segments, err := splitJSONPath(path)
	if err != nil {
		return "", err
	}
	var found []any
	walkJSONPath(v, segments, func(x any) { found = append(found, x) })
	if len(found) != 1 {
		return "", fmt.Errorf("場所 %s の値が %d 個あります。1個のはずです", path, len(found))
	}
	switch x := found[0].(type) {
	case string:
		return x, nil
	case json.Number:
		return x.String(), nil
	case bool:
		return strconv.FormatBool(x), nil
	default:
		return "", fmt.Errorf("場所 %s の値 %s は、文字か数か真偽の値ではありません", path, describeJSON(x))
	}
}

// CheckExpect は、応答が段の expect に合うかを確かめ、合わないことを1つずつ文にして返す。合えば空を返す。
func CheckExpect(step Step, resp Response) []string {
	var problems []string
	if step.Expect.Status != 0 && resp.Status != step.Expect.Status {
		problems = append(problems, fmt.Sprintf("ステータスが %d でした。期待は %d です", resp.Status, step.Expect.Status))
	}
	if len(step.Expect.Fields) == 0 {
		return problems
	}
	v, err := decodeJSON(resp.Body)
	if err != nil {
		return append(problems, fmt.Sprintf("本文を JSON として読めません: %v", err))
	}
	for _, path := range step.Expect.Fields {
		segments, err := splitJSONPath(path)
		if err != nil {
			problems = append(problems, err.Error())
			continue
		}
		found := false
		walkJSONPath(v, segments, func(any) { found = true })
		if !found {
			problems = append(problems, fmt.Sprintf("本文に必須の項目 %s がありません", path))
		}
	}
	return problems
}
