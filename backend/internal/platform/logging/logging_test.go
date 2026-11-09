package logging

import (
	"bytes"
	"encoding/json"
	"errors"
	"log/slog"
	"maps"
	"slices"
	"strings"
	"testing"
	"time"
)

// decodeLines は、書かれたログを1行ずつ JSON として読む。
func decodeLines(t *testing.T, buf *bytes.Buffer) []map[string]any {
	t.Helper()
	var records []map[string]any
	for line := range strings.SplitSeq(strings.TrimSpace(buf.String()), "\n") {
		if line == "" {
			continue
		}
		var record map[string]any
		if err := json.Unmarshal([]byte(line), &record); err != nil {
			t.Fatalf("ログの行 %q を JSON として読めません: %v", line, err)
		}
		records = append(records, record)
	}
	return records
}

// field は、入れ子のオブジェクトを、点でつないだ名前でたどって値を返す。
func field(record map[string]any, path string) (any, bool) {
	var current any = record
	for name := range strings.SplitSeq(path, ".") {
		object, ok := current.(map[string]any)
		if !ok {
			return nil, false
		}
		if current, ok = object[name]; !ok {
			return nil, false
		}
	}
	return current, true
}

func toStrings(v any) []string {
	items, _ := v.([]any)
	var out []string
	for _, item := range items {
		s, _ := item.(string)
		out = append(out, s)
	}
	return out
}

func testService() Service {
	return Service{Name: "keirekipro", Environment: "prod", Version: "abc123"}
}

// 項目の名前が、Java 版の Spring Boot の ECS の形と同じ入れ子のオブジェクトになることを確かめる。
func TestHandler_ECSFieldNames(t *testing.T) {
	var buf bytes.Buffer
	logger := Named(New(&buf, Options{Service: testService()}), "auth")
	before := time.Now()
	logger.Info("ログインしました", slog.String("user.id", "u-1"))
	logger.Debug("既定の重さより軽いログは書かない")
	logger.WithGroup("job").Info("グループの値", slog.Int("count", 2))

	records := decodeLines(t, &buf)
	if len(records) != 2 {
		t.Fatalf("ログの行の数 = %d, want 2: %s", len(records), buf.String())
	}
	first := records[0]
	want := map[string]any{
		"log.level":           "INFO",
		"log.logger":          "auth",
		"message":             "ログインしました",
		"service.name":        "keirekipro",
		"service.environment": "prod",
		"service.version":     "abc123",
		"user.id":             "u-1",
	}
	for path, value := range want {
		if got, ok := field(first, path); !ok || got != value {
			t.Errorf("%s = %v (ある %t), want %v", path, got, ok, value)
		}
	}
	// 点を含む名前は、平らなキーでなく入れ子のオブジェクトで書く
	for key := range first {
		if strings.Contains(key, ".") {
			t.Errorf("平らなキー %q があります: %v", key, first)
		}
	}

	timestamp, ok := first["@timestamp"].(string)
	if !ok || !strings.HasSuffix(timestamp, "Z") {
		t.Fatalf("@timestamp = %v, want UTC の時刻", first["@timestamp"])
	}
	parsed, err := time.Parse(time.RFC3339Nano, timestamp)
	if err != nil || parsed.Before(before.Add(-time.Second)) || parsed.After(time.Now().Add(time.Second)) {
		t.Errorf("@timestamp = %q, want 今の時刻 (%v)", timestamp, err)
	}

	if got, _ := field(records[1], "job.count"); got != float64(2) {
		t.Errorf("job.count = %v, want 2", got)
	}

	t.Run("決まった項目は利用者の値で上書きされない", func(t *testing.T) {
		var buf bytes.Buffer
		logger := New(&buf, Options{Service: testService()}).With(slog.String("log", "上書き"), slog.String("service.name", "別の名前"))
		logger.Info("本当の文", slog.String("message", "別の文"), slog.String("log.logger.extra", "置かない"))
		record := decodeLines(t, &buf)[0]
		for path, value := range map[string]any{"log.level": "INFO", "message": "本当の文", "service.name": "keirekipro"} {
			if got, _ := field(record, path); got != value {
				t.Errorf("%s = %v, want %v", path, got, value)
			}
		}
	})

	t.Run("値の種類ごとの書き方", func(t *testing.T) {
		var buf bytes.Buffer
		at := time.Date(2026, 1, 1, 9, 0, 0, 0, time.FixedZone("JST", 9*60*60))
		New(&buf, Options{Service: testService(), Level: slog.LevelDebug}).Debug("種類",
			slog.Time("at", at),
			slog.Duration("took", 2*time.Second),
			slog.Any("err", errors.New("誤りの文")),
			slog.Any("list", []string{"a", "b"}),
			slog.Any("fn", func() {}),
			slog.Bool("ok", true),
			slog.Group("empty"),
			slog.Group("", slog.String("inline", "最上位")),
		)
		record := decodeLines(t, &buf)[0]
		want := map[string]any{
			"log.level": "DEBUG",
			"at":        "2026-01-01T00:00:00Z",
			"took":      float64(2 * time.Second),
			"err":       "誤りの文",
			"ok":        true,
			"inline":    "最上位",
		}
		for path, value := range want {
			if got, _ := field(record, path); got != value {
				t.Errorf("%s = %v, want %v", path, got, value)
			}
		}
		if got, _ := field(record, "list"); !slices.Equal(toStrings(got), []string{"a", "b"}) {
			t.Errorf("list = %v, want [a b]", got)
		}
		if got, _ := field(record, "fn"); got == nil || got == "" {
			t.Errorf("fn = %v, want JSON にできない値を文字にしたもの", got)
		}
		if _, ok := record["empty"]; ok {
			t.Error("空のグループを書いています")
		}
	})

	t.Run("要求のログは決めた4つの値だけを書く", func(t *testing.T) {
		var buf bytes.Buffer
		Request(t.Context(), New(&buf, Options{Service: testService()}), "POST", "/api/auth/login", 401, 1500*time.Microsecond)
		records := decodeLines(t, &buf)
		if len(records) != 1 {
			t.Fatalf("ログの行の数 = %d, want 1", len(records))
		}
		record := records[0]
		keys := slices.Sorted(maps.Keys(record))
		if want := []string{"@timestamp", "event", "http", "log", "message", "service"}; !slices.Equal(keys, want) {
			t.Errorf("最上位の項目 = %v, want %v", keys, want)
		}
		wantRequest := map[string]any{
			"http.request.method":       "POST",
			"http.route":                "/api/auth/login",
			"http.response.status_code": float64(401),
			"event.duration":            float64(1500 * time.Microsecond),
		}
		for path, value := range wantRequest {
			if got, ok := field(record, path); !ok || got != value {
				t.Errorf("%s = %v (ある %t), want %v", path, got, ok, value)
			}
		}
		httpFields, _ := record["http"].(map[string]any)
		if keys := slices.Sorted(maps.Keys(httpFields)); !slices.Equal(keys, []string{"request", "response", "route"}) {
			t.Errorf("http の項目 = %v, want [request response route]", keys)
		}
		request, _ := httpFields["request"].(map[string]any)
		if keys := slices.Sorted(maps.Keys(request)); !slices.Equal(keys, []string{"method"}) {
			t.Errorf("http.request の項目 = %v, want [method]", keys)
		}
	})
}

// 誤りを、Java 版と同じ error.type と error.message と error.stack_trace で書くことを確かめる。
func TestHandler_ErrorFields(t *testing.T) {
	var buf bytes.Buffer
	logger := New(&buf, Options{Service: testService()})
	logger.Error("処理に失敗しました", ErrorAttr(errors.New("つなげません"), []byte("goroutine 1 [running]:\nmain.main()")))
	logger.Warn("スタックの無い誤り", ErrorAttr(errors.New("時間切れです"), nil))

	records := decodeLines(t, &buf)
	if len(records) != 2 {
		t.Fatalf("ログの行の数 = %d, want 2", len(records))
	}
	want := map[string]any{
		"log.level":         "ERROR",
		"error.type":        "*errors.errorString",
		"error.message":     "つなげません",
		"error.stack_trace": "goroutine 1 [running]:\nmain.main()",
	}
	for path, value := range want {
		if got, ok := field(records[0], path); !ok || got != value {
			t.Errorf("%s = %v (ある %t), want %v", path, got, ok, value)
		}
	}
	if got, _ := field(records[1], "log.level"); got != "WARN" {
		t.Errorf("2行目の log.level = %v, want WARN", got)
	}
	if got, _ := field(records[1], "error.message"); got != "時間切れです" {
		t.Errorf("2行目の error.message = %v, want 時間切れです", got)
	}
	if _, ok := field(records[1], "error.stack_trace"); ok {
		t.Error("スタックが無いのに error.stack_trace があります")
	}
}
