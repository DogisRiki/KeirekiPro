//go:build compat

// Package harness は、Java 版と Go 版の backend に同じ要求を送って比べる検査の本体である。
// 検査は、両方の版の本番のイメージと、Postgres と Redis と外部のサービスの代わりを、
// testcontainers-go で1つの Docker のネットワークに入れて動かす。
// Java 版のコードと、Go 版の機能の処理のコードは読まない。Go 版のコードのうち使うのは、表を作る migrate の部品だけである。
package harness

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"time"
)

const (
	// StartupTimeout は、1つのコンテナの起動を待つ時間の上限である。これを超えたら検査を失敗にする。
	StartupTimeout = 5 * time.Minute
	// RequestTimeout は、1つの要求の応答を待つ時間の上限である。
	RequestTimeout = 60 * time.Second
	// GoStartupLimit は、Go 版の本番のイメージが、起動から /healthz で 200 を返すまでの時間の上限である。
	GoStartupLimit = 10 * time.Second
)

// RepoRootEnv は、リポジトリの最上位のパスを渡す環境変数の名前である。
// CI はチェックアウトしたフォルダを、run-check.sh の領域 backend-go は差し込んだ /repo を渡す。
const RepoRootEnv = "KEIREKIPRO_REPO_ROOT"

// RepoRoot は、環境変数 KEIREKIPRO_REPO_ROOT のリポジトリの最上位のパスを返す。
func RepoRoot() (string, error) {
	root := os.Getenv(RepoRootEnv)
	if root == "" {
		return "", errors.New("harness: 環境変数 " + RepoRootEnv + " にリポジトリの最上位のパスを入れてください")
	}
	return root, nil
}

// ReportDir は、違いの報告とコンテナのログを書くフォルダ backend/compat/report/ を返す。
// CI の backend-compat は、このフォルダのファイルを成果物 backend-compat-report に残す。
// run-check.sh の中では /repo は読むだけなので、書ける backend のフォルダの中の場所を、このファイルの場所から求める。
func ReportDir() string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		return filepath.Join("..", "report")
	}
	return filepath.Join(filepath.Dir(file), "..", "report")
}
