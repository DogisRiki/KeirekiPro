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
// 中のフォルダは次の6つである。
//   - users/: 利用者の初めのデータの SQL。パスワードはすべて Passw0rd! である
//   - resumes/: 4種類の経歴書の SQL(空の経歴書、職歴と案件の多い経歴書、長い文の経歴書、フォントを比べる経歴書)と、
//     フォントを比べる経歴書を2つのフォントのそれぞれで書き出すときの設定の JSON。フォントは経歴書に保存せず、書き出しの要求で選ぶ。
//     名前が fonts- で始まる JSON は、フォントだけを替えた設定である。名前が sizes- で始まる JSON は、2つのフォントのそれぞれで、
//     4つの文字の大きさと表の見出しの色を既定と違う値にした設定である
//   - backups/: 経歴書のバックアップの JSON(正しいもの、版の違うもの、resume を含まないもの、JSON として読めないもの)。
//     名前が java- で始まる JSON は、Java 版が書き出したバックアップで、Java 版と Go 版が同じ答えを返すかを戻しで確かめる。
//     名前が reject- で始まる JSON は、版が無い、値の決まりを満たさない、日付の形でない、2つの条件に当たる、のどれかで戻しを断るファイルである。
//     名前が lax- で始まる JSON は、職歴の期間の重なりや1900年より前の日付のように、Java 版の戻しが確かめない決まりに当たるファイルである。
//     名前が malformed- で始まる JSON は、欄が足りない、型が違う、知らない欄がある、のように形の誤ったファイルである
//   - images/: プロフィールの画像(PNG、JPEG、GIF)
//   - export/: 経歴書の出力の操作の筋書きが使う SQL と要求の本文の JSON。SQL は、出力の前提を満たす中で項目が最も少ない経歴書と、
//     名前と本文に記号を入れた経歴書と、resumes/many-pages.sql の経歴書に足す自己PR を作るので、users/ と resumes/ のあとに読み込む。
//     JSON は、PDF の設定を付けた出力の要求の本文で、断る条件を確かめる本文も含む
//   - backup/: 経歴書のバックアップの書き出しと戻しの筋書きと結合テストが使う SQL。users/basic.sql の user1 に、
//     6つの欄のすべてに項目を持つ経歴書(801)、今も続く職歴とプロジェクトを持つ経歴書(802)、ファイル名に使えない字を名前に含む経歴書(803)、
//     記号と改行とタブと絵文字と U+2028 と U+2029 を字に入れた経歴書(804)、6つの欄のそれぞれに3件の項目を読み出すときの順と違う順に入れた経歴書(805)を作る。
//     users/ と resumes/ のあとに読み込む
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
