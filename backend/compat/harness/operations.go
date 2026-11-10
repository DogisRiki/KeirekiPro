//go:build compat

package harness

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"go.yaml.in/yaml/v3"
)

// 機能のまとまりの番号である。design.md の「まとまりの分け方と順番」の順で、筋書きの group に書く。
const (
	GroupAuth    = 1
	GroupUsers   = 2
	GroupResumes = 3
	GroupExport  = 4
	GroupBackup  = 5
)

// GroupNames は、progress.md のまとまりの表のまとまりの名前ごとの番号である。
var GroupNames = map[string]int{
	"認証":      GroupAuth,
	"利用者":     GroupUsers,
	"マスタと経歴書": GroupResumes,
	"出力":      GroupExport,
	"バックアップ":  GroupBackup,
}

// Operation は、仕様書の1つの操作である。
type Operation struct {
	// ID は、操作の名前(operationId)である。
	ID string
	// Method は、大文字の HTTP のメソッドである。
	Method string
	// Path は、仕様書のパスの形(例: /api/resumes/{resumeId})である。
	Path string
	// Group は、操作が入るまとまりの番号である。
	Group int
}

// Operations は、仕様書の操作の並びである。
type Operations []Operation

// httpMethods は、仕様書のパスの項目のうち、操作を表す名前である。
var httpMethods = []string{"get", "put", "post", "delete", "options", "head", "patch", "trace"}

// OpenAPIFile は、仕様書 backend/api/openapi.yaml のパスを返す。
func OpenAPIFile() string {
	return filepath.Join(FixturesDir(), "..", "..", "api", "openapi.yaml")
}

// LoadOperations は、仕様書の paths から、操作をパスとメソッドの順に並べて返す。
// operationId の無い操作と、同じ operationId の操作があれば、誤りを返す。
func LoadOperations(file string) (Operations, error) {
	data, err := os.ReadFile(filepath.Clean(file))
	if err != nil {
		return nil, fmt.Errorf("harness: 仕様書 %s を読めません: %w", file, err)
	}
	var doc struct {
		Paths map[string]map[string]yaml.Node `yaml:"paths"`
	}
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("harness: 仕様書 %s を YAML として読めません: %w", file, err)
	}
	if len(doc.Paths) == 0 {
		return nil, fmt.Errorf("harness: 仕様書 %s に paths がありません", file)
	}
	var ops Operations
	var errs []error
	seen := map[string]bool{}
	for path, item := range doc.Paths {
		for _, method := range httpMethods {
			node, ok := item[method]
			if !ok {
				continue
			}
			var op struct {
				OperationID string `yaml:"operationId"`
			}
			if err := node.Decode(&op); err != nil {
				errs = append(errs, fmt.Errorf("%s %s の形が誤っています: %w", method, path, err))
				continue
			}
			if op.OperationID == "" {
				errs = append(errs, fmt.Errorf("%s %s に operationId がありません", method, path))
				continue
			}
			if seen[op.OperationID] {
				errs = append(errs, fmt.Errorf("operationId %s が2つ以上あります", op.OperationID))
				continue
			}
			seen[op.OperationID] = true
			ops = append(ops, Operation{ID: op.OperationID, Method: strings.ToUpper(method), Path: path, Group: groupOf(op.OperationID, path)})
		}
	}
	if err := errors.Join(errs...); err != nil {
		return nil, fmt.Errorf("harness: 仕様書 %s: %w", file, err)
	}
	slices.SortFunc(ops, func(a, b Operation) int {
		if c := strings.Compare(a.Path, b.Path); c != 0 {
			return c
		}
		return strings.Compare(a.Method, b.Method)
	})
	return ops, nil
}

// groupOf は、操作の入るまとまりを、design.md の「まとまりの分け方と順番」の表のとおりに返す。
// 認証は /api/auth/ の下、利用者は /api/users/ の下、出力とバックアップはそれぞれ2つの操作で、残りはマスタと経歴書である。
func groupOf(id, path string) int {
	switch {
	case strings.HasPrefix(path, "/api/auth/"):
		return GroupAuth
	case strings.HasPrefix(path, "/api/users/"):
		return GroupUsers
	case id == "exportResume" || id == "exportResumeWithSettings":
		return GroupExport
	case id == "backupResume" || id == "restoreResume":
		return GroupBackup
	default:
		return GroupResumes
	}
}

// Lookup は、筋書きの段の要求 method と path が呼ぶ操作の名前を返す。当たる操作が無ければ空を返す。
// path の ? から後ろは見ない。仕様書の {名前} の部分は、どの文字にも当たる。筋書きの {名前} の部分は、
// 前の段で取り出す値なので、仕様書の {名前} の部分にだけ当たる。当たる形が2つ以上あれば、決まった文字の部分の多い形を選ぶ。
func (ops Operations) Lookup(method, path string) string {
	path, _, _ = strings.Cut(path, "?")
	segments := strings.Split(path, "/")
	best, bestLiterals := "", -1
	for _, op := range ops {
		if !strings.EqualFold(op.Method, method) {
			continue
		}
		literals, ok := matchSegments(strings.Split(op.Path, "/"), segments)
		if ok && literals > bestLiterals {
			best, bestLiterals = op.ID, literals
		}
	}
	return best
}

// matchSegments は、仕様書のパスの区切り template が、筋書きのパスの区切り segments に当たるかと、決まった文字の区切りの数を返す。
func matchSegments(template, segments []string) (int, bool) {
	if len(template) != len(segments) {
		return 0, false
	}
	literals := 0
	for i, t := range template {
		switch {
		case isPathVariable(t):
		case isPathVariable(segments[i]) || t != segments[i]:
			return 0, false
		default:
			literals++
		}
	}
	return literals, true
}

func isPathVariable(segment string) bool {
	return strings.HasPrefix(segment, "{") && strings.HasSuffix(segment, "}")
}
