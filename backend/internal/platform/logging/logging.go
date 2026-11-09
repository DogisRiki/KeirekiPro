// Package logging は、ログを、Java 版の Spring Boot の Elastic Common Schema(ECS)の形の JSON で1行ずつ書く。
// ECS は、ログの項目の名前の決まりである。Spring Boot と同じく、点を含む名前(log.level など)は入れ子のオブジェクトで書く。
package logging

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"strings"
	"sync"
	"time"
)

// Service は、ログの service の項目に書く値である。
type Service struct {
	// Name は、Java 版の spring.application.name と同じ keirekipro にする。
	Name string
	// Environment は、動かす環境の名前である。
	Environment string
	// Version は、動かしているイメージの版である。
	Version string
}

// Options は、ログの書き手の設定である。
type Options struct {
	Service Service
	// Level は、書くログの最も軽い重さである。nil なら INFO にする。
	Level slog.Leveler
}

// loggerKey は、ログを書いた部品の名前を置く項目である。
const loggerKey = "log.logger"

// New は、w に ECS の形の JSON を書くロガーを作る。起動の入口は、w に標準出力を渡す。
func New(w io.Writer, opts Options) *slog.Logger {
	level := opts.Level
	if level == nil {
		level = slog.LevelInfo
	}
	return slog.New(&handler{out: &output{w: w}, service: opts.Service, level: level})
}

// Named は、ログを書いた部品の名前を log.logger に書くロガーを返す。
func Named(logger *slog.Logger, name string) *slog.Logger {
	return logger.With(slog.String(loggerKey, name))
}

// Request は、要求ごとのログを書く。
// 書くのは、メソッドと経路の型とステータスとかかった時間だけである。
// Cookie と Authorization と要求の本文を受け取らないので、ログに書かない。
func Request(ctx context.Context, logger *slog.Logger, method, route string, status int, elapsed time.Duration) {
	logger.LogAttrs(ctx, slog.LevelInfo, "request",
		slog.String("http.request.method", method),
		slog.String("http.route", route),
		slog.Int("http.response.status_code", status),
		// ECS の event.duration は、ナノ秒の数である
		slog.Int64("event.duration", elapsed.Nanoseconds()),
	)
}

// ErrorAttr は、誤りを、Java 版と同じ error.type と error.message と error.stack_trace の項目にする。
// stack が nil なら、error.stack_trace を書かない。
func ErrorAttr(err error, stack []byte) slog.Attr {
	attrs := []any{
		slog.String("type", fmt.Sprintf("%T", err)),
		slog.String("message", err.Error()),
	}
	if stack != nil {
		attrs = append(attrs, slog.String("stack_trace", string(stack)))
	}
	return slog.Group("error", attrs...)
}

// output は、複数のロガーで共有する書き先である。1行ずつまとめて書く。
type output struct {
	mu sync.Mutex
	w  io.Writer
}

// scopedAttr は、WithAttrs で足した値と、そのときのグループの並びである。
type scopedAttr struct {
	groups []string
	attr   slog.Attr
}

type handler struct {
	out     *output
	service Service
	level   slog.Leveler
	attrs   []scopedAttr
	groups  []string
}

func (h *handler) Enabled(_ context.Context, level slog.Level) bool {
	return level >= h.level.Level()
}

func (h *handler) WithAttrs(attrs []slog.Attr) slog.Handler {
	next := *h
	next.attrs = append([]scopedAttr(nil), h.attrs...)
	for _, attr := range attrs {
		next.attrs = append(next.attrs, scopedAttr{groups: h.groups, attr: attr})
	}
	return &next
}

func (h *handler) WithGroup(name string) slog.Handler {
	if name == "" {
		return h
	}
	next := *h
	next.groups = append(append([]string(nil), h.groups...), name)
	return &next
}

func (h *handler) Handle(_ context.Context, record slog.Record) error {
	root := map[string]any{}
	for _, scoped := range h.attrs {
		put(root, scoped.groups, scoped.attr, false)
	}
	record.Attrs(func(attr slog.Attr) bool {
		put(root, h.groups, attr, false)
		return true
	})

	// 決まった項目は、利用者の値で上書きされないよう、最後に、途中の値を置き換えて置く
	put(root, nil, slog.String("log.level", record.Level.String()), true)
	put(root, nil, slog.String("message", record.Message), true)
	put(root, nil, slog.String("service.name", h.service.Name), true)
	put(root, nil, slog.String("service.environment", h.service.Environment), true)
	put(root, nil, slog.String("service.version", h.service.Version), true)
	if !record.Time.IsZero() {
		root["@timestamp"] = record.Time.UTC().Format(time.RFC3339Nano)
	}

	line, err := json.Marshal(root)
	if err != nil {
		return fmt.Errorf("logging: ログを JSON にできません: %w", err)
	}
	h.out.mu.Lock()
	defer h.out.mu.Unlock()
	_, err = h.out.w.Write(append(line, '\n'))
	return err
}

// put は、グループの並びと、点で区切った名前をたどって、入れ子のオブジェクトに値を置く。
// 途中の名前に、オブジェクトでない値がすでにあるときは、force なら前の値を置き換え、force でなければ前の値を残してこの値を置かない。
func put(root map[string]any, groups []string, attr slog.Attr, force bool) {
	attr.Value = attr.Value.Resolve()
	if attr.Equal(slog.Attr{}) {
		return
	}
	path := append(append([]string(nil), groups...), strings.Split(attr.Key, ".")...)
	if attr.Value.Kind() == slog.KindGroup {
		children := attr.Value.Group()
		if len(children) == 0 {
			return
		}
		if attr.Key == "" {
			path = path[:len(path)-1]
		}
		for _, child := range children {
			put(root, path, child, force)
		}
		return
	}

	destination := root
	for _, name := range path[:len(path)-1] {
		next, exists := destination[name]
		if !exists {
			created := map[string]any{}
			destination[name] = created
			destination = created
			continue
		}
		object, ok := next.(map[string]any)
		if !ok {
			if !force {
				return
			}
			object = map[string]any{}
			destination[name] = object
		}
		destination = object
	}
	destination[path[len(path)-1]] = value(attr.Value)
}

// value は、slog の値を JSON に書く値にする。
func value(v slog.Value) any {
	switch v.Kind() {
	case slog.KindTime:
		return v.Time().UTC().Format(time.RFC3339Nano)
	case slog.KindDuration:
		return v.Duration().Nanoseconds()
	case slog.KindAny:
		if err, ok := v.Any().(error); ok {
			return err.Error()
		}
		if _, err := json.Marshal(v.Any()); err != nil {
			return fmt.Sprint(v.Any())
		}
		return v.Any()
	default:
		return v.Any()
	}
}
