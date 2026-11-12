//go:build compat

package harness

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/network"
	"github.com/testcontainers/testcontainers-go/wait"
)

// Env は、1つの検査のための Docker のネットワークと、そこに入れたコンテナである。
// コンテナは、java go fakeaws fakeoidc のような名前でネットワークに入り、互いをその名前で呼ぶ。
// テストの処理はコンテナの外にあるので、testcontainers-go が返す、外に出したポートで各コンテナに要求を送る。
type Env struct {
	Network *testcontainers.DockerNetwork

	mu         sync.Mutex
	containers []*Container
	// workDir は、この検査の作業用のフォルダである。検査のたびに作る証明書や鍵を置き、Terminate で消す。
	workDir string
}

// ContainerSpec は、Env に入れる1つのコンテナである。
type ContainerSpec struct {
	// Name は、ネットワークの中でほかのコンテナがこのコンテナを呼ぶ名前である。
	Name string
	// Aliases は、Name のほかに、ネットワークの中でこのコンテナを呼ぶ名前である。
	Aliases []string
	Image   string
	Env     map[string]string
	Cmd     []string
	// Entrypoint は、空でなければ、イメージの入口(ENTRYPOINT)の代わりに動かすコマンドである。
	Entrypoint []string
	// Files は、コンテナを作ってから動かし始める前に、コンテナの中に写すファイルである。
	// コンテナの中の利用者は root でないことがあるので、FileMode は、その利用者が読める権限にする。
	Files []testcontainers.ContainerFile
	// ExposedPorts は、テストの処理から要求を送るために外に出すポート(例: "8080/tcp")である。
	ExposedPorts []string
	// WaitingFor は、起動を待つ条件である。nil なら、コンテナが動き始めたところで戻る。
	WaitingFor wait.Strategy
}

// Container は、Env に入れたコンテナである。
type Container struct {
	Name string
	testcontainers.Container
}

// NewEnv は、検査のための Docker のネットワークを1つと、作業用のフォルダを1つ作る。
func NewEnv(ctx context.Context) (*Env, error) {
	dir, err := os.MkdirTemp("", "keirekipro-compat-")
	if err != nil {
		return nil, fmt.Errorf("harness: 作業用のフォルダを作れません: %w", err)
	}
	nw, err := network.New(ctx)
	if err != nil {
		return nil, errors.Join(fmt.Errorf("harness: Docker のネットワークを作れません: %w", err), os.RemoveAll(dir))
	}
	return &Env{Network: nw, workDir: dir}, nil
}

// WorkDir は、この検査の作業用のフォルダを返す。フォルダは Terminate で消す。
func (e *Env) WorkDir() string {
	return e.workDir
}

// Start は、コンテナを名前を付けてネットワークに入れて起動する。
// 起動が StartupTimeout で終わらなければ失敗にする。起動に失敗したコンテナも、ログを残せるように Env に覚える。
func (e *Env) Start(ctx context.Context, spec ContainerSpec) (*Container, error) {
	ctx, cancel := context.WithTimeout(ctx, StartupTimeout)
	defer cancel()

	opts := []testcontainers.ContainerCustomizer{
		network.WithNetwork(append([]string{spec.Name}, spec.Aliases...), e.Network),
		testcontainers.WithEnv(spec.Env),
		testcontainers.WithExposedPorts(spec.ExposedPorts...),
	}
	if len(spec.Cmd) > 0 {
		opts = append(opts, testcontainers.WithCmd(spec.Cmd...))
	}
	if len(spec.Entrypoint) > 0 {
		opts = append(opts, testcontainers.WithEntrypoint(spec.Entrypoint...))
	}
	if len(spec.Files) > 0 {
		opts = append(opts, testcontainers.WithFiles(spec.Files...))
	}
	if spec.WaitingFor != nil {
		opts = append(opts, testcontainers.WithWaitStrategyAndDeadline(StartupTimeout, spec.WaitingFor))
	}
	ctr, err := testcontainers.Run(ctx, spec.Image, opts...)
	if ctr != nil {
		c := &Container{Name: spec.Name, Container: ctr}
		e.mu.Lock()
		e.containers = append(e.containers, c)
		e.mu.Unlock()
		if err == nil {
			return c, nil
		}
	}
	return nil, fmt.Errorf("harness: コンテナ %s(%s)を起動できません: %w", spec.Name, spec.Image, err)
}

// SaveLogs は、Env に入れたすべてのコンテナのログを、dir の <名前>.log に書く。
// 比べる検査が失敗したときに、両方の版のコンテナのログを成果物に残すためである。
func (e *Env) SaveLogs(ctx context.Context, dir string) error {
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return fmt.Errorf("harness: ログのフォルダ %s を作れません: %w", dir, err)
	}
	e.mu.Lock()
	containers := append([]*Container(nil), e.containers...)
	e.mu.Unlock()

	var errs []error
	for _, c := range containers {
		if err := saveLog(ctx, c, filepath.Join(dir, c.Name+".log")); err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

func saveLog(ctx context.Context, c *Container, file string) error {
	logs, err := c.Logs(ctx)
	if err != nil {
		return fmt.Errorf("harness: コンテナ %s のログを読めません: %w", c.Name, err)
	}
	defer func() { _ = logs.Close() }()
	out, err := os.Create(filepath.Clean(file))
	if err != nil {
		return fmt.Errorf("harness: ログのファイル %s を作れません: %w", file, err)
	}
	if _, err := io.Copy(out, logs); err != nil {
		_ = out.Close()
		return fmt.Errorf("harness: コンテナ %s のログを書けません: %w", c.Name, err)
	}
	return out.Close()
}

// Terminate は、Env に入れたすべてのコンテナを止めて消し、ネットワークと作業用のフォルダを消す。
func (e *Env) Terminate(ctx context.Context) error {
	e.mu.Lock()
	containers := e.containers
	e.containers = nil
	e.mu.Unlock()

	var errs []error
	for _, c := range containers {
		if err := c.Terminate(ctx); err != nil {
			errs = append(errs, fmt.Errorf("harness: コンテナ %s を止められません: %w", c.Name, err))
		}
	}
	if err := e.Network.Remove(ctx); err != nil {
		errs = append(errs, fmt.Errorf("harness: Docker のネットワークを消せません: %w", err))
	}
	if e.workDir != "" {
		if err := os.RemoveAll(e.workDir); err != nil {
			errs = append(errs, fmt.Errorf("harness: 作業用のフォルダ %s を消せません: %w", e.workDir, err))
		}
	}
	return errors.Join(errs...)
}

// Cleanup は、テストの終わりに Env を片付けるように t に登録する。
// テストが失敗していれば、片付ける前に、すべてのコンテナのログを ReportDir() の下のテストの名前のフォルダに書く。
func (e *Env) Cleanup(t testing.TB) {
	t.Helper()
	t.Cleanup(func() {
		ctx := context.Background()
		if t.Failed() {
			dir := filepath.Join(ReportDir(), "logs", strings.ReplaceAll(t.Name(), "/", "_"))
			if err := e.SaveLogs(ctx, dir); err != nil {
				t.Errorf("コンテナのログを残せません: %v", err)
			} else {
				t.Logf("コンテナのログを %s に残しました", dir)
			}
		}
		if err := e.Terminate(ctx); err != nil {
			t.Errorf("検査の環境を片付けられません: %v", err)
		}
	})
}
