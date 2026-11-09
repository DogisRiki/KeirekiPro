// Package pdf は、HTML の文字列から A4 の PDF を作る部品である。
//
// 部品は、Chromium を1つ起動したまま持ち、PDF ごとに新しいタブを開いて閉じる。
// タブでは JavaScript を止め、data: のほかの通信をすべて断る。
package pdf

import (
	"context"
	"errors"
	"fmt"
	"iter"
	"log/slog"
	"sync"
	"time"

	"github.com/chromedp/cdproto/cdp"
	"github.com/chromedp/cdproto/emulation"
	"github.com/chromedp/cdproto/fetch"
	"github.com/chromedp/cdproto/network"
	"github.com/chromedp/cdproto/page"
	"github.com/chromedp/chromedp"
)

const (
	// DefaultTimeout は、1つの PDF を作る処理を打ち切るまでの時間である。
	DefaultTimeout = 30 * time.Second
	// DefaultMaxConcurrent は、同時に作る PDF の数である。
	DefaultMaxConcurrent = 2
)

// ErrStart は、Chromium を起動できなかったことを表す。
// ブラウザの実行ファイルが見つからないときも、この誤りを包んで返す。
var ErrStart = errors.New("pdf: Chromium を起動できません")

// Options は、部品の設定である。値が0のときは既定の値を使う。
type Options struct {
	// Timeout は、1つの PDF を作る処理を打ち切るまでの時間である。既定は30秒。
	Timeout time.Duration
	// MaxConcurrent は、同時に作る PDF の数である。既定は2。
	MaxConcurrent int
	// Logger は、chromedp が書く知らせを DEBUG で書く先である。nil なら書かない。
	// chromedp は、HTML を置くたびに、使わない DOM の追跡についての知らせを誤りとして書くため、DEBUG にする。
	Logger *slog.Logger
}

// Engine は、Chromium を1つ起動したまま持ち、PDF を作る。
type Engine struct {
	timeout   time.Duration
	logger    *slog.Logger
	slots     chan struct{}
	allocOpts []chromedp.ExecAllocatorOption

	mu      sync.Mutex
	browser context.Context
	stop    func()

	// beforePrint は、テストが、印刷の直前に処理を差し込むために使う。
	beforePrint func(ctx context.Context, t *chromedp.Target) error
}

// New は、Chromium を起動して部品を作る。ブラウザの実行ファイルは chromedp の既定の探し方で見つける。
// 起動できなければ、ErrStart を包んだ誤りを返す。
func New(opts Options) (*Engine, error) {
	return newEngine(opts, nil)
}

// newEngine は、起動の設定を足して部品を作る。テストは、ブラウザの実行ファイルを替えるために使う。
func newEngine(opts Options, extra []chromedp.ExecAllocatorOption) (*Engine, error) {
	if opts.Timeout <= 0 {
		opts.Timeout = DefaultTimeout
	}
	if opts.MaxConcurrent <= 0 {
		opts.MaxConcurrent = DefaultMaxConcurrent
	}
	if opts.Logger == nil {
		opts.Logger = slog.New(slog.DiscardHandler)
	}
	allocOpts := append(chromedp.DefaultExecAllocatorOptions[:],
		chromedp.DisableGPU,
		// Fargate では、Chromium のサンドボックスが使う機能が使えない。
		// 代わりに、タブで JavaScript を止め、外への通信を断る。
		chromedp.NoSandbox,
		chromedp.Flag("disable-dev-shm-usage", true),
		chromedp.Flag("font-render-hinting", "none"),
	)
	e := &Engine{
		timeout:   opts.Timeout,
		logger:    opts.Logger,
		slots:     make(chan struct{}, opts.MaxConcurrent),
		allocOpts: append(allocOpts, extra...),
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if err := e.start(); err != nil {
		return nil, err
	}
	return e, nil
}

// start は、Chromium を起動する。e.mu を持って呼ぶ。
func (e *Engine) start() error {
	allocCtx, cancelAlloc := chromedp.NewExecAllocator(context.Background(), e.allocOpts...)
	logf := func(format string, args ...any) {
		e.logger.Debug("chromedp", slog.String("detail", fmt.Sprintf(format, args...)))
	}
	browser, cancelBrowser := chromedp.NewContext(allocCtx, chromedp.WithLogf(logf), chromedp.WithErrorf(logf))
	stop := func() {
		cancelBrowser()
		cancelAlloc()
	}
	if err := chromedp.Do(browser); err != nil {
		stop()
		return fmt.Errorf("%w: %w", ErrStart, err)
	}
	e.browser, e.stop = browser, stop
	return nil
}

// alive は、Chromium とのつながりが生きているかを返す。e.mu を持って呼ぶ。
func (e *Engine) alive() bool {
	if e.browser == nil || e.browser.Err() != nil {
		return false
	}
	select {
	case <-chromedp.FromContext(e.browser).Browser.LostConnection:
		return false
	default:
		return true
	}
}

// current は、生きている Chromium の context を返す。Chromium が落ちていれば、起動し直す。
func (e *Engine) current() (context.Context, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.alive() {
		if e.stop != nil {
			e.stop()
			e.browser, e.stop = nil, nil
		}
		if err := e.start(); err != nil {
			return nil, err
		}
	}
	return e.browser, nil
}

// Close は、Chromium を止める。
func (e *Engine) Close() {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.stop != nil {
		e.stop()
		e.browser, e.stop = nil, nil
	}
}

// Render は、HTML の文字列から PDF を作る。同時に作る数を超えた要求は、空くまで待つ。
// 打ち切りの時間を超えたときと、Chromium が落ちたときは、タブを閉じて誤りを返す。
func (e *Engine) Render(ctx context.Context, html string) ([]byte, error) {
	select {
	case e.slots <- struct{}{}:
	case <-ctx.Done():
		return nil, fmt.Errorf("pdf: 順番を待つあいだに要求が終わりました: %w", ctx.Err())
	}
	defer func() { <-e.slots }()

	browser, err := e.current()
	if err != nil {
		return nil, err
	}
	limited, cancel := context.WithTimeout(browser, e.timeout)
	defer cancel()
	defer context.AfterFunc(ctx, cancel)()

	// タブの context を閉じると、chromedp がタブを閉じる。
	tab, closeTab := chromedp.NewContext(limited)
	defer closeTab()

	pdf, err := chromedp.Run(tab, e.print(html))
	if err != nil {
		if ctx.Err() == nil && errors.Is(limited.Err(), context.DeadlineExceeded) {
			return nil, fmt.Errorf("pdf: %s で作り終わりませんでした: %w", e.timeout, context.DeadlineExceeded)
		}
		return nil, fmt.Errorf("pdf: PDF を作れません: %w", err)
	}
	return pdf, nil
}

// print は、タブで JavaScript と外への通信を止め、HTML を置いて印刷する動作を返す。
func (e *Engine) print(html string) chromedp.Action[[]byte] {
	return func(ctx context.Context, t *chromedp.Target) ([]byte, error) {
		if _, err := cdp.Call(ctx, t, emulation.SetScriptExecutionDisabled,
			emulation.SetScriptExecutionDisabledParams{Value: true}); err != nil {
			return nil, fmt.Errorf("JavaScript を止められません: %w", err)
		}
		paused := cdp.Events(ctx, t, fetch.RequestPaused)
		if _, err := cdp.Call(ctx, t, fetch.Enable,
			fetch.EnableParams{Patterns: []*fetch.RequestPattern{{URLPattern: "*"}}}); err != nil {
			return nil, fmt.Errorf("通信を止められません: %w", err)
		}
		go denyNetwork(ctx, t, paused)

		tree, err := cdp.Call(ctx, t, page.GetFrameTree, cdp.Empty{})
		if err != nil {
			return nil, fmt.Errorf("タブのフレームを読めません: %w", err)
		}
		loaded := cdp.Events(ctx, t, page.LoadEventFired)
		if _, err := cdp.Call(ctx, t, page.SetDocumentContent, page.SetDocumentContentParams{
			FrameID: tree.FrameTree.Frame.ID,
			HTML:    html,
		}); err != nil {
			return nil, fmt.Errorf("HTML を置けません: %w", err)
		}
		for _, err := range loaded {
			if err != nil {
				return nil, fmt.Errorf("HTML の読み込みを待てません: %w", err)
			}
			break
		}

		if e.beforePrint != nil {
			if err := e.beforePrint(ctx, t); err != nil {
				return nil, err
			}
		}
		// CSS の @page で大きさを決めていないページは A4 にする。
		return chromedp.PrintToPDF(
			chromedp.PDFPaper(chromedp.PaperA4),
			chromedp.PDFPreferCSSPageSize(),
			chromedp.PDFPrintBackground(),
		)(ctx, t)
	}
}

// denyNetwork は、止めた要求をすべて断る。data: の読み込みは通信ではないので、Chromium は止めずに通す。
// タブの context が終わると戻る。
func denyNetwork(ctx context.Context, t *chromedp.Target, paused iter.Seq2[fetch.EventRequestPaused, error]) {
	for ev, err := range paused {
		if err != nil {
			return
		}
		_, _ = cdp.Call(ctx, t, fetch.FailRequest, fetch.FailRequestParams{
			RequestID:   ev.RequestID,
			ErrorReason: network.ErrorReasonBlockedByClient,
		})
	}
}
