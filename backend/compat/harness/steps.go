//go:build compat

package harness

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"

	"github.com/redis/go-redis/v9"
)

// fakeoidcHost は、筋書きの絶対の URL の段で、偽のログインのサービスを指す名前である。
// 版のコンテナの中からはこの名前で届くが、テストの処理からは届かないので、テストの処理から届くアドレスに置き換える。
const fakeoidcHost = "fakeoidc"

// SendAbsolute は、絶対の URL の段 step の要求を request.url に送り、応答を返す。url の {名前} は前の段で取り出した値に置き換え、
// 名前が fakeoidc の URL は、送る先を oidcURL(テストの処理から届く fakeoidc のアドレス)に置き換える。
// 転送は追わず、応答の Location を capture で次の段に渡す。版に送る要求ではないので、Cookie の束の Cookie は送らず、
// 応答の Set-Cookie も覚えない。expect.status があれば、応答のステータスがそれに合うかを確かめる。応答は比べない。
func (s *Session) SendAbsolute(ctx context.Context, client *http.Client, oidcURL string, step Step) (Response, error) {
	raw, err := s.expand(step, "url", step.Request.URL)
	if err != nil {
		return Response{}, err
	}
	u, err := url.Parse(raw)
	if err != nil {
		return Response{}, fmt.Errorf("harness: 段 %s の url %q を読めません: %w", step.Name, raw, err)
	}
	if u.Hostname() == fakeoidcHost {
		base, err := url.Parse(oidcURL)
		if err != nil {
			return Response{}, fmt.Errorf("harness: 段 %s の送る先の fakeoidc のアドレス %q を読めません: %w", step.Name, oidcURL, err)
		}
		u.Scheme, u.Host = base.Scheme, base.Host
	}
	noFollow := *client
	noFollow.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	resp, err := s.send(ctx, &noFollow, u.String(), step, false)
	if err != nil {
		return resp, err
	}
	if step.Expect.Status != 0 && resp.Status != step.Expect.Status {
		return resp, fmt.Errorf("harness: 段 %s のステータスが %d でした。期待は %d です", step.Name, resp.Status, step.Expect.Status)
	}
	return resp, nil
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
