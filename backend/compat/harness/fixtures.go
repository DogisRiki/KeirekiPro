//go:build compat

package harness

import (
	"context"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"runtime"

	"github.com/jackc/pgx/v5"
)

// FixturesDir は、筋書きが使う初めのデータのフォルダ backend/compat/fixtures/ を返す。
// 中のフォルダは次の4つである。
//   - users/: 利用者の初めのデータの SQL。パスワードはすべて Passw0rd! である
//   - resumes/: 4種類の経歴書の SQL(空の経歴書、職歴と案件の多い経歴書、長い文の経歴書、フォントを比べる経歴書)と、
//     フォントを比べる経歴書を2つのフォントのそれぞれで書き出すときの設定の JSON。フォントは経歴書に保存せず、書き出しの要求で選ぶ
//   - backups/: 経歴書のバックアップの JSON(正しいもの、版の違うもの、resume を含まないもの、JSON として読めないもの)
//   - images/: プロフィールの画像(PNG、JPEG、GIF)
func FixturesDir() string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		return filepath.Join("..", "fixtures")
	}
	return filepath.Join(filepath.Dir(file), "..", "fixtures")
}

// readFixture は、fixtures/ からのパス name のファイルを読む。fixtures/ の外のファイルは読まない。
func readFixture(name string) ([]byte, error) {
	root, err := os.OpenRoot(FixturesDir())
	if err != nil {
		return nil, fmt.Errorf("harness: 初めのデータのフォルダを開けません: %w", err)
	}
	defer func() { _ = root.Close() }()
	data, err := root.ReadFile(filepath.FromSlash(name))
	if err != nil {
		return nil, fmt.Errorf("harness: 初めのデータ %s を読めません: %w", name, err)
	}
	return data, nil
}

// LoadFixtures は、connString のデータベースに、fixtures/ からのパスで書いた SQL のファイルを、書いた順に1つのトランザクションで読み込む。
// 筋書きの fixtures に書いたファイルを、表の形を適用したあとに読み込む。1つでも失敗したら、どのファイルも読み込まない。
func LoadFixtures(ctx context.Context, connString string, names []string) error {
	scripts := make([]string, 0, len(names))
	for _, name := range names {
		if path.Ext(name) != ".sql" {
			return fmt.Errorf("harness: 初めのデータ %s は SQL のファイルではありません", name)
		}
		data, err := readFixture(name)
		if err != nil {
			return err
		}
		scripts = append(scripts, string(data))
	}
	conn, err := pgx.Connect(ctx, connString)
	if err != nil {
		return fmt.Errorf("harness: データベースにつなげません: %w", err)
	}
	defer func() { _ = conn.Close(context.WithoutCancel(ctx)) }()
	tx, err := conn.Begin(ctx)
	if err != nil {
		return fmt.Errorf("harness: トランザクションを始められません: %w", err)
	}
	defer func() { _ = tx.Rollback(context.WithoutCancel(ctx)) }()
	for i, script := range scripts {
		// 引数の無い Exec は、複数の文を1回で送る形で送る
		if _, err := tx.Exec(ctx, script); err != nil {
			return fmt.Errorf("harness: 初めのデータ %s を読み込めません: %w", names[i], err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("harness: 初めのデータを確定できません: %w", err)
	}
	return nil
}
