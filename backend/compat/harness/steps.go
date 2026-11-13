//go:build compat

package harness

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

// fakeoidcHost は、筋書きの絶対の URL の段で、偽のログインのサービスを指す名前である。
// 版のコンテナの中からはこの名前で届くが、テストの処理からは届かないので、テストの処理から届くアドレスに置き換える。
const fakeoidcHost = "fakeoidc"

// AbsoluteTargets は、絶対の URL の段の宛先を書き換えるときに使う、テストの処理から届くアドレスと、版の AWS の接続先である。
type AbsoluteTargets struct {
	// OIDCURL は、テストの処理から届く fakeoidc のアドレスである。
	OIDCURL string
	// AWSURL は、テストの処理から届く偽の AWS のアドレスである。
	AWSURL string
	// AWSEndpoint は、段を送る版の設定の AWS の接続先(例: http://fakeaws-go:4566)である。
	AWSEndpoint string
}

// signedURLHost は、版が返す署名付きの URL のホストとポートである。比べる検査の環境は、2つの版を開発環境の設定で動かすので、
// 版は、AWS の接続先のホストを localhost にした URL を返す。
const signedURLHost = "localhost:4566"

// SendAbsolute は、絶対の URL の段 step の要求を request.url に送り、応答を返す。url の {名前} は前の段で取り出した値に置き換え、
// 名前が fakeoidc の URL は、送る先を targets.OIDCURL(テストの処理から届く fakeoidc のアドレス)に置き換える。
// ホストとポートが localhost:4566 の URL は、送る先を targets.AWSURL(テストの処理から届く偽の AWS のアドレス)に置き換え、
// 要求の Host を targets.AWSEndpoint のホストとポートにする。偽の AWS は、Host のホスト名で、どちらの版が置いた画像を読むかを選ぶ。
// 転送は追わず、応答の Location を capture で次の段に渡す。版に送る要求ではないので、Cookie の束の Cookie は送らず、
// 応答の Set-Cookie も覚えない。応答が expect の status と content_type と body_file に合うかを checkAbsoluteExpect で確かめ、
// 合わなければ、合わないことを1つずつ誤りにして返す。応答は比べない。
func (s *Session) SendAbsolute(ctx context.Context, client *http.Client, targets AbsoluteTargets, step Step) (Response, error) {
	raw, err := s.expand(step, "url", step.Request.URL)
	if err != nil {
		return Response{}, err
	}
	u, err := url.Parse(raw)
	if err != nil {
		return Response{}, fmt.Errorf("harness: 段 %s の url %q を読めません: %w", step.Name, raw, err)
	}
	// 読み込みのときに確かめられない、差し込む名前で始まる url は、差し込んだあとにここで確かめる
	if !u.IsAbs() || u.Host == "" {
		return Response{}, fmt.Errorf("harness: 段 %s の差し込んだあとの url %q は絶対の URL ではありません", step.Name, raw)
	}
	if u.Hostname() == fakeoidcHost {
		base, err := url.Parse(targets.OIDCURL)
		if err != nil {
			return Response{}, fmt.Errorf("harness: 段 %s の送る先の fakeoidc のアドレス %q を読めません: %w", step.Name, targets.OIDCURL, err)
		}
		u.Scheme, u.Host = base.Scheme, base.Host
	}
	host := ""
	if u.Host == signedURLHost {
		aws, err := hostOf(targets.AWSURL)
		if err != nil {
			return Response{}, fmt.Errorf("harness: 段 %s の送る先の偽の AWS のアドレス %q を使えません: %w", step.Name, targets.AWSURL, err)
		}
		endpoint, err := hostOf(targets.AWSEndpoint)
		if err != nil {
			return Response{}, fmt.Errorf("harness: 段 %s の版の AWS の接続先 %q を使えません: %w", step.Name, targets.AWSEndpoint, err)
		}
		u.Scheme, u.Host = aws.Scheme, aws.Host
		host = endpoint.Host
	}
	noFollow := *client
	noFollow.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	resp, err := s.send(ctx, &noFollow, u.String(), host, step, false)
	if err != nil {
		return resp, err
	}
	var errs []error
	for _, p := range checkAbsoluteExpect(step, resp) {
		errs = append(errs, errors.New("harness: "+p))
	}
	return resp, errors.Join(errs...)
}

// CheckValues は、版に送る段 step の応答 resp の本文の JSON が、expect.values の場所ごとに期待する値を持つかを確かめ、
// 合わないことを1つずつ文にして返す。合えば空を返す。期待する値の {名前} は、この Session で取り出した値に置き換える。
// 合わないことの文には、段の名前と、JSON の場所と、受けた値と、期待した値を書く。値は、項目を名前の順に並べた JSON で書く。
// 場所に値が無いときと、場所に値が2つ以上あるときも、合わないこととして書く。
func (s *Session) CheckValues(step Step, resp Response) []string {
	if len(step.Expect.Values) == 0 {
		return nil
	}
	v, err := decodeJSON(resp.Body)
	if err != nil {
		return []string{fmt.Sprintf("段 %s の expect の values を確かめられません。本文を JSON として読めません: %v", step.Name, err)}
	}
	var problems []string
	for _, path := range sortedKeys(step.Expect.Values) {
		want, err := s.expandJSON(step, "expect の values の "+path+" の値", step.Expect.Values[path])
		if err != nil {
			problems = append(problems, strings.TrimPrefix(err.Error(), "harness: "))
			continue
		}
		segments, err := splitJSONPath(path)
		if err != nil {
			problems = append(problems, fmt.Sprintf("段 %s の expect の values: %v", step.Name, err))
			continue
		}
		var found []any
		walkJSONPath(v, segments, func(x any) { found = append(found, x) })
		wantText := canonicalJSON(want)
		var got string
		switch len(found) {
		case 0:
			got = absent
		case 1:
			got = canonicalJSON(found[0])
		default:
			got = fmt.Sprintf("%d 個の値 %s", len(found), canonicalJSON(found))
		}
		if len(found) != 1 || got != wantText {
			problems = append(problems, fmt.Sprintf("段 %s の %s の値が %s でした。期待は %s です", step.Name, path, got, wantText))
		}
	}
	return problems
}

// checkAbsoluteExpect は、絶対の URL の段 step の応答 resp が、expect の status と content_type と body_file に合うかを確かめ、
// 合わないことを1つずつ文にして返す。合えば空を返す。Content-Type は、文字の並びのまま比べる。
// 本文が body_file と違うときは、画像の中身を書かず、受けた本文と期待したファイルの大きさと SHA-256 だけを書く。
func checkAbsoluteExpect(step Step, resp Response) []string {
	var problems []string
	if step.Expect.Status != 0 && resp.Status != step.Expect.Status {
		problems = append(problems, fmt.Sprintf("段 %s のステータスが %d でした。期待は %d です", step.Name, resp.Status, step.Expect.Status))
	}
	if step.Expect.ContentType != "" {
		if got := resp.Header.Get("Content-Type"); got != step.Expect.ContentType {
			problems = append(problems, fmt.Sprintf("段 %s の応答の Content-Type が %q でした。期待は %q です", step.Name, got, step.Expect.ContentType))
		}
	}
	if step.Expect.BodyFile != "" {
		want, err := readImageFixture(step.Expect.BodyFile)
		switch {
		case err != nil:
			problems = append(problems, fmt.Sprintf("段 %s の expect の body_file %q を読めません: %v", step.Name, step.Expect.BodyFile, err))
		case !bytes.Equal(resp.Body, want):
			problems = append(problems, fmt.Sprintf("段 %s の応答の本文が %s でした。期待は fixtures/images/%s の %s です",
				step.Name, describeBytes(resp.Body), step.Expect.BodyFile, describeBytes(want)))
		}
	}
	return problems
}

// hostOf は、アドレス raw を読み、ホストのある絶対の URL なら返す。空のときと、読めないときと、ホストが無いときは誤りを返す。
func hostOf(raw string) (*url.URL, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return nil, err
	}
	if !u.IsAbs() || u.Host == "" {
		return nil, errors.New("ホストのある絶対の URL ではありません")
	}
	return u, nil
}

// ApplyRedis は、Redis の段 step の redis.del のキーを消し、redis.set のキーに value を ttl_seconds 秒の期限で書く。
// キーと value の {名前} は、この Session で取り出した値に置き換える。比べる動かし方では版ごとの Session と Redis で1回ずつ、
// 版をまたぐ動かし方では1回呼ぶ。置き換えたあとの value が JSON でないときは、Redis を書き換えずに誤りを返す。
func (s *Session) ApplyRedis(ctx context.Context, client *redis.Client, step Step) error {
	var del []string
	for _, key := range step.Redis.Del {
		k, err := s.expand(step, "redis.del のキー", key)
		if err != nil {
			return err
		}
		del = append(del, k)
	}
	type entry struct {
		key, value string
		ttl        time.Duration
	}
	var set []entry
	for _, item := range step.Redis.Set {
		k, err := s.expand(step, "redis.set のキー", item.Key)
		if err != nil {
			return err
		}
		v, err := s.expand(step, "redis.set の value", item.Value)
		if err != nil {
			return err
		}
		if !json.Valid([]byte(v)) {
			return fmt.Errorf("harness: 段 %s の redis.set のキー %s の value %q は JSON ではありません", step.Name, k, v)
		}
		set = append(set, entry{key: k, value: v, ttl: time.Duration(item.TTLSeconds) * time.Second})
	}
	pipe := client.TxPipeline()
	if len(del) > 0 {
		pipe.Del(ctx, del...)
	}
	for _, e := range set {
		pipe.Set(ctx, e.key, e.value, e.ttl)
	}
	if _, err := pipe.Exec(ctx); err != nil {
		return fmt.Errorf("harness: 段 %s の Redis を書き換えられません: %w", step.Name, err)
	}
	return nil
}

// stepTools は、筋書きの1回の実行に渡す、段を種類に合わせて動かす部品である。比べる動かし方では版ごとに1つ、
// 版をまたぐ動かし方では1つ、応答の時間の比べ方では版の環境ごとに1つ作る。
type stepTools struct {
	client *http.Client
	// oidcURL は、テストの処理から届く fakeoidc のアドレスである。絶対の URL の段の送る先にする。
	oidcURL string
	// jwtKey は、値を期限切れにする段で署名し直す、版に渡した JWT.Secret の値である。
	jwtKey string
	// redis は、Redis を書き換える段で書き換える Redis である。
	redis *redis.Client
	// mail は、取り出しの元 mail: で読むメールの読み方である。
	mail MailReader
}

// newSession は、mail: のメールを t.mail で読む、新しい Session を返す。
func (t stepTools) newSession() *Session {
	s := NewSession()
	s.SetMailReader(t.mail)
	return s
}

// send は、段 step を種類に合わせて session で動かし、応答を返す。版に送る段は baseURL に送り、
// 絶対の URL の段は fakeoidc に送る。Redis を書き換える段と値を期限切れにする段は、要求を送らずに、空の応答を返す。
// 絶対の URL の段の応答は版の動きではないので、呼び出し元は比べない。絶対の URL の段の expect の status は、SendAbsolute が確かめる。
func (t stepTools) send(ctx context.Context, session *Session, baseURL string, step Step) (Response, error) {
	switch step.Kind() {
	case StepAbsoluteURL:
		return session.SendAbsolute(ctx, t.client, AbsoluteTargets{OIDCURL: t.oidcURL}, step)
	case StepRedis:
		if t.redis == nil {
			return Response{}, fmt.Errorf("harness: 段 %s で書き換える Redis がありません", step.Name)
		}
		return Response{}, session.ApplyRedis(ctx, t.redis, step)
	case StepExpire:
		return Response{}, session.Expire(step, t.jwtKey)
	default:
		return session.Send(ctx, t.client, baseURL, step)
	}
}
