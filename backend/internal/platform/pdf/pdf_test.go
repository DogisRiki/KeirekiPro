package pdf

import (
	"bytes"
	"compress/zlib"
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"regexp"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/chromedp/cdproto/cdp"
	"github.com/chromedp/cdproto/runtime"
	"github.com/chromedp/chromedp"
)

// onePixelPNG は、1画素の赤い PNG の data: URL である。
const onePixelPNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

// newTestEngine は、部品を作り、テストの終わりに Chromium を止める。
func newTestEngine(t *testing.T, opts Options) *Engine {
	t.Helper()
	e, err := New(opts)
	if err != nil {
		t.Fatalf("New = %v", err)
	}
	t.Cleanup(e.Close)
	return e
}

func render(t *testing.T, e *Engine, html string) []byte {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	pdf, err := e.Render(ctx, html)
	if err != nil {
		t.Fatalf("Render = %v", err)
	}
	if !bytes.HasPrefix(pdf, []byte("%PDF-")) {
		t.Fatalf("PDF の先頭 = %q, want %%PDF-", pdf[:min(len(pdf), 16)])
	}
	return pdf
}

var mediaBox = regexp.MustCompile(`/MediaBox\s*\[\s*0\s+0\s+([0-9.]+)\s+([0-9.]+)\s*\]`)

// pageSize は、PDF の最初のページの大きさをポイントで返す。
func pageSize(t *testing.T, pdf []byte) (width, height float64) {
	t.Helper()
	m := mediaBox.FindSubmatch(pdf)
	if m == nil {
		t.Fatal("PDF に MediaBox がありません")
	}
	width, _ = strconv.ParseFloat(string(m[1]), 64)
	height, _ = strconv.ParseFloat(string(m[2]), 64)
	return width, height
}

// contents は、PDF の圧縮された流れをすべて展開して、つなげて返す。
func contents(pdf []byte) []byte {
	var out bytes.Buffer
	rest := pdf
	for {
		start := bytes.Index(rest, []byte("stream"))
		if start < 0 {
			return out.Bytes()
		}
		rest = bytes.TrimLeft(rest[start+len("stream"):], "\r\n")
		end := bytes.Index(rest, []byte("endstream"))
		if end < 0 {
			return out.Bytes()
		}
		if r, err := zlib.NewReader(bytes.NewReader(rest[:end])); err == nil {
			// テストが作る PDF は小さいため、展開する量に上限を置く。
			_, _ = io.CopyN(&out, r, 64<<20)
		}
		rest = rest[end+len("endstream"):]
	}
}

func near(got, want float64) bool { return math.Abs(got-want) < 1 }

// 印刷の大きさが A4 で、CSS の @page の大きさを優先し、背景を印刷することを確かめる。
func TestRender_A4(t *testing.T) {
	e := newTestEngine(t, Options{})

	t.Run("@page の無い HTML は A4", func(t *testing.T) {
		w, h := pageSize(t, render(t, e, `<h1>職務経歴書</h1><img src="`+onePixelPNG+`">`))
		if !near(w, 595.92) || !near(h, 842.88) {
			t.Errorf("大きさ = %v x %v, want A4(595.92 x 842.88)", w, h)
		}
	})
	t.Run("@page の大きさを優先する", func(t *testing.T) {
		w, h := pageSize(t, render(t, e, `<style>@page { size: A5; margin: 0 }</style><p>A5</p>`))
		if !near(w, 419.53) || !near(h, 595.28) {
			t.Errorf("大きさ = %v x %v, want A5(419.53 x 595.28)", w, h)
		}
	})
	t.Run("背景の色を印刷する", func(t *testing.T) {
		pdf := render(t, e, `<style>html, body { background: #ff0000; height: 100% }</style><p>背景</p>`)
		if !bytes.Contains(contents(pdf), []byte("1 0 0 rg")) {
			t.Error("PDF に背景の赤がありません")
		}
	})
}

// 同時に作る数を2までにし、3つ目は1つ目が終わるまで待つことを確かめる。
func TestRender_ThirdWaitsForFirst(t *testing.T) {
	e := newTestEngine(t, Options{})

	t.Run("同時に印刷するのは2つまで", func(t *testing.T) {
		var mu sync.Mutex
		running, peak := 0, 0
		e.beforePrint = func(context.Context, *chromedp.Target) error {
			mu.Lock()
			running++
			peak = max(peak, running)
			mu.Unlock()
			time.Sleep(300 * time.Millisecond)
			mu.Lock()
			running--
			mu.Unlock()
			return nil
		}
		t.Cleanup(func() { e.beforePrint = nil })

		var wg sync.WaitGroup
		for range 4 {
			wg.Go(func() { render(t, e, "<p>同時</p>") })
		}
		wg.Wait()
		if peak != DefaultMaxConcurrent {
			t.Errorf("同時に印刷した数の最大 = %d, want %d", peak, DefaultMaxConcurrent)
		}
	})

	t.Run("枠が埋まっていれば、空くまで待つ", func(t *testing.T) {
		e.slots <- struct{}{}
		e.slots <- struct{}{}
		filled := 2
		defer func() {
			for range filled {
				<-e.slots
			}
		}()
		done := make(chan error, 1)
		go func() {
			_, err := e.Render(context.Background(), "<p>3つ目</p>")
			done <- err
		}()
		select {
		case err := <-done:
			t.Fatalf("枠が空く前に終わりました: %v", err)
		case <-time.After(500 * time.Millisecond):
		}
		<-e.slots
		filled--
		select {
		case err := <-done:
			if err != nil {
				t.Errorf("Render = %v", err)
			}
		case <-time.After(30 * time.Second):
			t.Fatal("枠が空いても終わりません")
		}
	})

	t.Run("待っているあいだに要求が終われば、誤りを返す", func(t *testing.T) {
		e.slots <- struct{}{}
		e.slots <- struct{}{}
		defer func() { <-e.slots; <-e.slots }()
		ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
		defer cancel()
		if _, err := e.Render(ctx, "<p>待つ</p>"); !errors.Is(err, context.DeadlineExceeded) {
			t.Errorf("Render = %v, want context.DeadlineExceeded", err)
		}
	})
}

// pageTargets は、Chromium で開いているタブの数を返す。
func pageTargets(t *testing.T, e *Engine) int {
	t.Helper()
	browser, err := e.current()
	if err != nil {
		t.Fatalf("current = %v", err)
	}
	targets, err := chromedp.Targets(browser)
	if err != nil {
		t.Fatalf("Targets = %v", err)
	}
	n := 0
	for _, target := range targets {
		if target.Type == "page" {
			n++
		}
	}
	return n
}

// 打ち切りの時間を超えた要求に誤りを返し、タブを閉じ、次の要求は作れることを確かめる。
func TestRender_TimeoutReturnsError(t *testing.T) {
	e := newTestEngine(t, Options{Timeout: 2 * time.Second})
	before := pageTargets(t, e)

	e.beforePrint = func(ctx context.Context, _ *chromedp.Target) error {
		<-ctx.Done()
		return ctx.Err()
	}
	started := time.Now()
	_, err := e.Render(context.Background(), "<p>終わらない</p>")
	elapsed := time.Since(started)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Errorf("Render = %v, want context.DeadlineExceeded", err)
	}
	if elapsed < 2*time.Second || elapsed > 15*time.Second {
		t.Errorf("打ち切るまでの時間 = %v, want 2秒ほど", elapsed)
	}
	if after := pageTargets(t, e); after != before {
		t.Errorf("タブの数 = %d, want %d(打ち切ったタブを閉じる)", after, before)
	}

	t.Run("要求を取り消したときは、打ち切りではなく取り消しの誤りを返す", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		time.AfterFunc(300*time.Millisecond, cancel)
		_, err := e.Render(ctx, "<p>取り消す</p>")
		if !errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			t.Errorf("Render = %v, want context.Canceled", err)
		}
	})

	e.beforePrint = nil
	render(t, e, "<p>次の要求</p>")
}

// process は、いま動いている Chromium の処理を返す。
func process(t *testing.T, e *Engine) int {
	t.Helper()
	browser, err := e.current()
	if err != nil {
		t.Fatalf("current = %v", err)
	}
	return chromedp.FromContext(browser).Browser.Process().Pid
}

func kill(t *testing.T, e *Engine) {
	t.Helper()
	e.mu.Lock()
	b := chromedp.FromContext(e.browser).Browser
	e.mu.Unlock()
	if err := b.Process().Kill(); err != nil {
		t.Fatalf("Chromium を止められません: %v", err)
	}
	select {
	case <-b.LostConnection:
	case <-time.After(10 * time.Second):
		t.Fatal("Chromium とのつながりが切れません")
	}
}

// Chromium が落ちたときの要求に誤りを返し、次の要求の前に Chromium を起動し直すことを確かめる。
func TestRender_RestartsAfterCrash(t *testing.T) {
	e := newTestEngine(t, Options{})

	t.Run("要求のあいだに落ちたら、次の要求の前に起動し直す", func(t *testing.T) {
		first := process(t, e)
		kill(t, e)
		render(t, e, "<p>起動し直したあと</p>")
		if again := process(t, e); again == first {
			t.Errorf("Chromium の処理 = %d, want 起動し直した別の処理", again)
		}
	})

	t.Run("作っている途中で落ちたら誤りを返し、次の要求は作れる", func(t *testing.T) {
		e.beforePrint = func(context.Context, *chromedp.Target) error {
			kill(t, e)
			return nil
		}
		_, err := e.Render(context.Background(), "<p>落ちる</p>")
		e.beforePrint = nil
		if err == nil {
			t.Fatal("Render = nil, want 誤り")
		}
		render(t, e, "<p>次の要求</p>")
	})

	t.Run("起動し直せなければ、起動の失敗を返す", func(t *testing.T) {
		kill(t, e)
		saved := e.allocOpts
		e.allocOpts = append(append([]chromedp.ExecAllocatorOption{}, saved...),
			chromedp.ExecPath(filepath.Join(t.TempDir(), "no-chromium")))
		_, err := e.Render(context.Background(), "<p>起動できない</p>")
		e.allocOpts = saved
		if !errors.Is(err, ErrStart) {
			t.Errorf("Render = %v, want ErrStart", err)
		}
		render(t, e, "<p>起動し直せたあと</p>")
	})

	t.Run("止めたあとの要求は、起動し直して作る", func(t *testing.T) {
		e.Close()
		render(t, e, "<p>止めたあと</p>")
	})
}

// data: のほかの通信をすべて断り、JavaScript を動かさないことを確かめる。
func TestRender_BlocksNetwork(t *testing.T) {
	var hits atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	e := newTestEngine(t, Options{})
	var text string
	e.beforePrint = func(ctx context.Context, target *chromedp.Target) error {
		res, err := cdp.Call(ctx, target, runtime.Evaluate, runtime.EvaluateParams{
			Expression: `document.getElementById("js").textContent`,
		})
		if err != nil {
			return err
		}
		return json.Unmarshal(res.Result.Value, &text)
	}
	render(t, e, `<!doctype html>
<html><head>
<link rel="stylesheet" href="`+server.URL+`/style.css">
<style>@import url("`+server.URL+`/import.css"); body { background-image: url("`+server.URL+`/bg.png") }</style>
<script src="`+server.URL+`/script.js"></script>
</head><body>
<img src="`+server.URL+`/image.png">
<iframe src="`+server.URL+`/frame.html"></iframe>
<p id="js">動いていない</p>
<script>document.getElementById("js").textContent = "動いた"; fetch("`+server.URL+`/fetch")</script>
</body></html>`)

	if n := hits.Load(); n != 0 {
		t.Errorf("外への通信 = %d 件, want 0 件", n)
	}
	if text != "動いていない" {
		t.Errorf("#js の文 = %q, want JavaScript が動いていない", text)
	}

	e.beforePrint = nil
	t.Run("data: の画像は通して印刷する", func(t *testing.T) {
		if bytes.Contains(render(t, e, "<p>画像なし</p>"), []byte("/Subtype /Image")) {
			t.Fatal("画像の無いページの PDF に画像があります")
		}
		if !bytes.Contains(render(t, e, `<img src="`+onePixelPNG+`" width="200" height="200">`), []byte("/Subtype /Image")) {
			t.Error("data: の画像を印刷していません")
		}
	})
}

// ブラウザの実行ファイルが見つからなければ、起動の失敗を返すことを確かめる。
func TestNew_NoBrowserReturnsError(t *testing.T) {
	e, err := newEngine(Options{}, []chromedp.ExecAllocatorOption{
		chromedp.ExecPath(filepath.Join(t.TempDir(), "no-chromium")),
	})
	if !errors.Is(err, ErrStart) || e != nil {
		t.Errorf("newEngine = %v, %v, want nil, ErrStart", e, err)
	}
}
