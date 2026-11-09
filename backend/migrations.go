// Package backend は、Go 版の backend のモジュールの最上位のパッケージである。
// このパッケージは、モジュールの中のファイルを埋め込み、ほかのパッケージに渡すことだけを受け持つ。
package backend

import (
	"embed"
	"io/fs"
)

// migrationDir は、マイグレーションのファイルを置くフォルダである。
// 段階6でマイグレーションのファイルを db/migrations/ に移すときは、ここと埋め込みの指定を直す。
const migrationDir = "src/main/resources/db/migration"

//go:embed src/main/resources/db/migration/*.sql
var migrationFiles embed.FS

// Migrations は、埋め込んだマイグレーションのファイルを、フォルダの最上位に置いた形で返す。
func Migrations() (fs.FS, error) {
	return fs.Sub(migrationFiles, migrationDir)
}
