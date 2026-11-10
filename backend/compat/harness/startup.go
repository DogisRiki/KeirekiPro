//go:build compat

package harness

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"time"
)

// healthzPollInterval は、/healthz に要求を送り直すまでの間隔である。
const healthzPollInterval = 100 * time.Millisecond

// WaitHealthz は、baseURL の /healthz が 200 を返すまで要求を送り続け、startedAt から 200 を受けるまでの時間を返す。
// ctx が終わるまでに 200 を受けなければ失敗にする。
func WaitHealthz(ctx context.Context, client *http.Client, baseURL string, startedAt time.Time) (time.Duration, error) {
	ticker := time.NewTicker(healthzPollInterval)
	defer ticker.Stop()
	for {
		if healthzOK(ctx, client, baseURL+"/healthz") {
			return time.Since(startedAt), nil
		}
		select {
		case <-ctx.Done():
			return time.Since(startedAt), fmt.Errorf("harness: %s/healthz が 200 を返しません: %w", baseURL, ctx.Err())
		case <-ticker.C:
		}
	}
}

func healthzOK(ctx context.Context, client *http.Client, url string) bool {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
	if err != nil {
		return false
	}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer func() { _ = resp.Body.Close() }()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode == http.StatusOK
}

// CheckGoStartup は、Go 版の本番のイメージの起動の時間が GoStartupLimit を超えたら失敗を返す。
func CheckGoStartup(elapsed time.Duration) error {
	if elapsed > GoStartupLimit {
		return fmt.Errorf("harness: Go 版が、起動から /healthz で 200 を返すまでに %s かかりました。上限は %s です", elapsed, GoStartupLimit)
	}
	return nil
}

// MeasureGoStartup は、起動した Go 版のコンテナの /healthz が 200 を返すまで待ち、startedAt からの時間が
// GoStartupLimit を超えたら失敗を返す。startedAt は、Go 版のコンテナの起動を頼む直前の時刻である。
// 上限を超えたかどうかを確かめるために、待つのは StartupTimeout までにする。
func MeasureGoStartup(ctx context.Context, client *http.Client, baseURL string, startedAt time.Time) (time.Duration, error) {
	ctx, cancel := context.WithTimeout(ctx, StartupTimeout)
	defer cancel()
	elapsed, err := WaitHealthz(ctx, client, baseURL, startedAt)
	if err != nil {
		return elapsed, err
	}
	return elapsed, CheckGoStartup(elapsed)
}

// StartGo は、Go 版のコンテナを起動し、起動から /healthz が 200 を返すまでの時間を測る。
// 時間が GoStartupLimit を超えたら、コンテナを返したうえで失敗を返す。
// spec の WaitingFor は使わない。起動を待つ条件で待つと、/healthz を待ち始める前に時間が過ぎるためである。
func (e *Env) StartGo(ctx context.Context, spec ContainerSpec) (*Container, time.Duration, error) {
	spec.WaitingFor = nil
	startedAt := time.Now()
	c, err := e.Start(ctx, spec)
	if err != nil {
		return nil, 0, err
	}
	baseURL, err := c.BaseURL(ctx, spec.ExposedPorts[0])
	if err != nil {
		return c, 0, err
	}
	elapsed, err := MeasureGoStartup(ctx, NewHTTPClient(), baseURL, startedAt)
	return c, elapsed, err
}

// BaseURL は、テストの処理からコンテナの port へ要求を送るときの http://ホスト:ポート を返す。
func (c *Container) BaseURL(ctx context.Context, port string) (string, error) {
	endpoint, err := c.PortEndpoint(ctx, port, "http")
	if err != nil {
		return "", fmt.Errorf("harness: コンテナ %s のポート %s の宛先を読めません: %w", c.Name, port, err)
	}
	return endpoint, nil
}

// NewHTTPClient は、比べる検査が要求を送るクライアントを返す。
// 1つの要求を RequestTimeout で打ち切る。転送の応答は、比べるためにそのまま返し、転送先へは進まない。
// Cookie は、版ごとに検査が覚えるので、クライアントは覚えない。
func NewHTTPClient() *http.Client {
	return &http.Client{
		Timeout: RequestTimeout,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
}
