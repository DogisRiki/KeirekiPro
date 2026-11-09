//go:build compat

package harness

import (
	"context"
	"fmt"
	"net/http"
)

// CrossEnv は、Java 版と Go 版を、1つの Postgres と1つの Redis と1つの fakeaws と1つの fakeoidc につないだ環境である。
// どちらの版も、同じ JWT の値と同じ外部のログインのクライアントを使うので、一方の版が出したトークンをもう一方の版が受け付ける。
type CrossEnv struct {
	*Stack
	// URLs は、版の名前ごとの、テストの処理から届く backend の URL である。
	URLs map[string]string

	client *http.Client
}

// StartCrossEnv は、env のネットワークに、Postgres と Redis と fakeaws と fakeoidc と、backends の2つの版を起動する。
// images は BuildImages の結果で、Postgres と Redis と fakeaws と fakeoidc のイメージを含む。
// backends は、版の名前(VersionJava と VersionGo)ごとの、その位置に置く backend である。
// 途中で失敗したときは、作った Redis のクライアントを閉じて誤りを返す。コンテナは env が片付ける。
func StartCrossEnv(ctx context.Context, env *Env, images Images, backends map[string]Backend) (*CrossEnv, error) {
	for _, version := range []string{VersionJava, VersionGo} {
		if _, ok := backends[version]; !ok {
			return nil, fmt.Errorf("harness: 版 %s の位置に置く backend がありません", version)
		}
	}
	stack, err := startStack(ctx, env, images)
	if err != nil {
		return nil, err
	}
	c := &CrossEnv{Stack: stack, URLs: map[string]string{}, client: NewHTTPClient()}
	var urls []string
	for _, version := range []string{VersionJava, VersionGo} {
		_, url, _, err := startBackend(ctx, env, version, backends[version], stack.backing)
		if err != nil {
			_ = stack.Close()
			return nil, err
		}
		c.URLs[version] = url
		urls = append(urls, url)
	}
	if err := stack.registerRedirects(ctx, urls); err != nil {
		_ = stack.Close()
		return nil, err
	}
	return c, nil
}

// Run は、筋書き s を、3つの送り先の組で1つずつ動かす。組ごとに、保存された内容を空にしてから筋書きの初めのデータを読み込む。
// 環境を整えられないときは、誤りを返す。筋書きの段が期待に合わないときは、報告の Failures に書く。
func (c *CrossEnv) Run(ctx context.Context, s Scenario) (CrossReport, error) {
	report := CrossReport{Scenario: s.Name, Directions: CrossDirections}
	for _, direction := range CrossDirections {
		if err := c.Reset(ctx); err != nil {
			return report, err
		}
		if err := LoadFixtures(ctx, c.DBConn, s.Fixtures); err != nil {
			return report, err
		}
		if f := RunCross(ctx, c.client, s, direction, c.URLs); f != nil {
			report.Failures = append(report.Failures, *f)
		}
	}
	return report, nil
}
