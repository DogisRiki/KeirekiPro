//go:build compat

package harness

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
)

// CompatHost は、版に送るすべての要求の Host である。Java 版と Go 版は、どちらも Host から
// Google と GitHub のログインの戻り先の URL を作るので、2つの版の戻り先の URL が http://compat.test/... で同じになる。
// 要求は、Host にかかわらず、版のポートに送る。そのため、この名前を引ける必要は無い。
const CompatHost = "compat.test"

// MailReader は、偽の AWS が覚えた、送ったメールを、送った順にすべて読む。
// Session は、取り出しの元 mail: を持つ段の前と後に読み、段のあとに増えたメールから取り出す。
type MailReader func(ctx context.Context) ([]fakeaws.Email, error)

// 取り出しの元の種類である。capture の値の頭で選ぶ。
const (
	sourceJSON   = "json"
	sourceText   = "text"
	sourceHeader = "header"
	sourceCookie = "cookie"
	sourceMail   = "mail"
)

// captureSource は、capture の1つの値を読んだ、取り出しの元である。
type captureSource struct {
	kind string
	// path は、JSON の本文の場所である(kind が json のとき)。
	path string
	// name は、ヘッダか Cookie の名前である(kind が header か cookie のとき)。
	name string
	// item は、ヘッダの値を URL として読んだときの問い合わせの項目の名前である。空なら、ヘッダの値をそのまま取り出す。
	item string
	// pattern は、メールの本文に当てる正規表現である(kind が mail のとき)。1つ目の組に当たった文字列を取り出す。
	pattern *regexp.Regexp
}

// parseCaptureSource は、capture の値 src を、取り出しの元として読む。
// $ で始まる値は JSON の本文の場所、text は本文の全体、header:<名前> はヘッダの値、header:<名前>?<項目> はヘッダの URL の
// 問い合わせの項目、cookie:<名前> はその段の応答の Set-Cookie の値、mail:<正規表現> はその段のあとに届いた最後のメールの本文である。
func parseCaptureSource(src string) (captureSource, error) {
	switch {
	case strings.HasPrefix(src, "$"):
		if _, err := splitJSONPath(src); err != nil {
			return captureSource{}, err
		}
		return captureSource{kind: sourceJSON, path: src}, nil
	case src == sourceText:
		return captureSource{kind: sourceText}, nil
	}
	if rest, ok := strings.CutPrefix(src, sourceHeader+":"); ok {
		name, item, hasItem := strings.Cut(rest, "?")
		if name == "" {
			return captureSource{}, fmt.Errorf("取り出しの元 %q にヘッダの名前がありません", src)
		}
		if hasItem && item == "" {
			return captureSource{}, fmt.Errorf("取り出しの元 %q の ? のあとに問い合わせの項目の名前がありません", src)
		}
		return captureSource{kind: sourceHeader, name: name, item: item}, nil
	}
	if name, ok := strings.CutPrefix(src, sourceCookie+":"); ok {
		if name == "" {
			return captureSource{}, fmt.Errorf("取り出しの元 %q に Cookie の名前がありません", src)
		}
		return captureSource{kind: sourceCookie, name: name}, nil
	}
	if expr, ok := strings.CutPrefix(src, sourceMail+":"); ok {
		re, err := regexp.Compile(expr)
		if err != nil {
			return captureSource{}, fmt.Errorf("取り出しの元 %q の正規表現を読めません: %w", src, err)
		}
		if re.NumSubexp() < 1 {
			return captureSource{}, fmt.Errorf("取り出しの元 %q の正規表現に、取り出す組がありません", src)
		}
		return captureSource{kind: sourceMail, pattern: re}, nil
	}
	return captureSource{}, fmt.Errorf("取り出しの元 %q は、$ で始める JSON の場所か、text か、header:<名前> か、cookie:<名前> か、mail:<正規表現> で書きます", src)
}

// capturesMail は、段 step の capture に、取り出しの元 mail: があるかを返す。
func capturesMail(step Step) bool {
	for _, src := range step.Capture {
		if strings.HasPrefix(src, sourceMail+":") {
			return true
		}
	}
	return false
}

// SetMailReader は、取り出しの元 mail: で読むメールの読み方を決める。決めていない Session は、mail: を持つ段を送らずに失敗する。
func (s *Session) SetMailReader(r MailReader) {
	s.mail = r
}

// readMails は、メールを読む。メールを読む部品が無いときは、段 step の誤りを返す。
func (s *Session) readMails(ctx context.Context, step Step) ([]fakeaws.Email, error) {
	if s.mail == nil {
		return nil, fmt.Errorf("harness: 段 %s の capture に mail: がありますが、メールを読む部品がありません", step.Name)
	}
	mails, err := s.mail(ctx)
	if err != nil {
		return nil, fmt.Errorf("harness: 段 %s のメールを読めません: %w", step.Name, err)
	}
	return mails, nil
}

// capture は、段の capture に書いた名前ごとに、取り出しの元から1つの値を取り出して覚える。
// mails は、その段のあとに届いたメールである。値が無いときと、正規表現が当たらないときは、段の名前と取り出しの名前を誤りに書く。
func (s *Session) capture(step Step, resp Response, mails []fakeaws.Email) error {
	jsonBody := sync.OnceValues(func() (any, error) { return decodeJSON(resp.Body) })
	var errs []error
	for _, name := range sortedKeys(step.Capture) {
		value, err := captureFrom(step.Capture[name], resp, mails, jsonBody)
		if err != nil {
			errs = append(errs, fmt.Errorf("harness: 段 %s の capture %s: %w", step.Name, name, err))
			continue
		}
		s.vars[name] = value
	}
	return errors.Join(errs...)
}

// captureFrom は、取り出しの元 src から1つの値を取り出す。
func captureFrom(src string, resp Response, mails []fakeaws.Email, jsonBody func() (any, error)) (string, error) {
	c, err := parseCaptureSource(src)
	if err != nil {
		return "", err
	}
	switch c.kind {
	case sourceJSON:
		v, err := jsonBody()
		if err != nil {
			return "", fmt.Errorf("応答の本文を JSON として読めません: %w", err)
		}
		return captureValue(v, c.path)
	case sourceText:
		return string(resp.Body), nil
	case sourceHeader:
		return captureHeader(c, resp.Header)
	case sourceCookie:
		var value string
		found := false
		// 同じ名前の Cookie が2つあれば、ブラウザと同じく後ろの値を使う
		for _, cookie := range (&http.Response{Header: resp.Header}).Cookies() {
			if cookie.Name == c.name {
				value, found = cookie.Value, true
			}
		}
		if !found {
			return "", fmt.Errorf("応答の Set-Cookie に Cookie %s がありません", c.name)
		}
		return value, nil
	default:
		if len(mails) == 0 {
			return "", errors.New("この段のあとに届いたメールがありません")
		}
		m := c.pattern.FindStringSubmatch(mails[len(mails)-1].Text)
		if m == nil {
			return "", fmt.Errorf("この段のあとに届いた最後のメールの本文に、正規表現 %s が当たりません", c.pattern)
		}
		return m[1], nil
	}
}

// captureHeader は、ヘッダ c.name の1つ目の値か、その値を URL として読んだときの問い合わせの項目 c.item の値を返す。
func captureHeader(c captureSource, header http.Header) (string, error) {
	values := header.Values(c.name)
	if len(values) == 0 {
		return "", fmt.Errorf("応答にヘッダ %s がありません", c.name)
	}
	if c.item == "" {
		return values[0], nil
	}
	u, err := url.Parse(values[0])
	if err != nil {
		return "", fmt.Errorf("ヘッダ %s の値を URL として読めません: %w", c.name, err)
	}
	query := u.Query()
	if !query.Has(c.item) {
		return "", fmt.Errorf("ヘッダ %s の URL に問い合わせの項目 %s がありません", c.name, c.item)
	}
	return query.Get(c.item), nil
}

// expand は、text の {名前} を、前の段で取り出した値に置き換える。where は、誤りに書く、text の場所である。
// 取り出していない名前があれば、段 step の誤りを返す。
func (s *Session) expand(step Step, where, text string) (string, error) {
	var missing []string
	expanded := pathVariable.ReplaceAllStringFunc(text, func(m string) string {
		name := m[1 : len(m)-1]
		v, ok := s.vars[name]
		if !ok {
			missing = append(missing, name)
		}
		return v
	})
	if len(missing) > 0 {
		return "", fmt.Errorf("harness: 段 %s の%s %q の %v を、前の段の capture で取り出していません", step.Name, where, text, missing)
	}
	return expanded, nil
}

// expandJSON は、JSON の本文の値 v の文字列の値の {名前} を置き換えた写しを返す。項目の名前は置き換えない。
// 筋書きの段は Java 版と Go 版で同じものを使うので、v は書き換えない。
func (s *Session) expandJSON(step Step, v any) (any, error) {
	switch x := v.(type) {
	case string:
		return s.expand(step, "本文の文字列", x)
	case map[string]any:
		out := make(map[string]any, len(x))
		for k, item := range x {
			e, err := s.expandJSON(step, item)
			if err != nil {
				return nil, err
			}
			out[k] = e
		}
		return out, nil
	case []any:
		out := make([]any, len(x))
		for i, item := range x {
			e, err := s.expandJSON(step, item)
			if err != nil {
				return nil, err
			}
			out[i] = e
		}
		return out, nil
	default:
		return v, nil
	}
}

// requestBody は、段 step の本文と、その本文の Content-Type を返す。本文が無ければ nil を返す。
// json は、{名前} を置き換えてから JSON にする。multipart は、multipartBody で組み立てる。
// body_file は、fixtures/images の下のファイルをそのまま本文にし、Content-Type は筋書きのヘッダに任せて空を返す。
func (s *Session) requestBody(step Step) ([]byte, string, error) {
	switch {
	case len(step.Request.Multipart) > 0:
		return s.multipartBody(step)
	case step.Request.BodyFile != "":
		b, err := readImageFixture(step.Request.BodyFile)
		if err != nil {
			return nil, "", fmt.Errorf("harness: 段 %s の body_file %q を読めません: %w", step.Name, step.Request.BodyFile, err)
		}
		return b, "", nil
	case step.Request.JSON == nil:
		return nil, "", nil
	}
	v, err := s.expandJSON(step, step.Request.JSON)
	if err != nil {
		return nil, "", err
	}
	b, err := json.Marshal(v)
	if err != nil {
		return nil, "", fmt.Errorf("harness: 段 %s の本文を JSON にできません: %w", step.Name, err)
	}
	return b, "application/json", nil
}
