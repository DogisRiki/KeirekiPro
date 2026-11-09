//go:build compat

package harness

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	_ "image/gif"  // GIF の画像を読む
	_ "image/jpeg" // JPEG の画像を読む
	_ "image/png"  // PNG の画像を読む
	"io/fs"
	"os"
	"path"
	"regexp"
	"slices"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"golang.org/x/crypto/bcrypt"
)

// fixturePassword は、users/basic.sql の利用者のパスワードである。筋書きはこの値でログインする。
const fixturePassword = "Passw0rd!"

// 経歴書の4種類の名前。resumes/ の SQL のファイルが、この名前の経歴書を作る。
const (
	resumeEmpty     = "空の経歴書"
	resumeManyPages = "職歴と案件の多い経歴書"
	resumeLongText  = "長い文の経歴書"
	resumeFonts     = "フォントを比べる経歴書"
)

// fixtureDB は、表の形を適用し、users/ と resumes/ のすべての SQL のファイルを読み込んだデータベースにつなぐ。
func fixtureDB(t *testing.T) *pgx.Conn {
	t.Helper()
	ctx := t.Context()
	container, err := postgres.Run(ctx, postgresImage,
		postgres.WithDatabase("keireki_pro"),
		postgres.WithUsername("postgres"),
		postgres.WithPassword("postgres"),
		postgres.BasicWaitStrategies(),
	)
	t.Cleanup(func() {
		if err := testcontainers.TerminateContainer(container); err != nil {
			t.Errorf("Postgres のコンテナを止められません: %v", err)
		}
	})
	if err != nil {
		t.Fatalf("Postgres のコンテナを動かせません: %v", err)
	}
	conn, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("つなぎ先を読めません: %v", err)
	}
	if _, err := ApplyMigrations(ctx, conn); err != nil {
		t.Fatalf("ApplyMigrations: %v", err)
	}
	if err := LoadFixtures(ctx, conn, fixtureFiles(t, "users", ".sql")); err != nil {
		t.Fatalf("利用者の初めのデータを読み込めません: %v", err)
	}
	if err := LoadFixtures(ctx, conn, fixtureFiles(t, "resumes", ".sql")); err != nil {
		t.Fatalf("経歴書の初めのデータを読み込めません: %v", err)
	}
	db, err := pgx.Connect(ctx, conn)
	if err != nil {
		t.Fatalf("つなげません: %v", err)
	}
	t.Cleanup(func() { _ = db.Close(context.Background()) })
	return db
}

// fixtureFiles は、fixtures/ の dir のフォルダにある、拡張子が ext のファイルの名前を、fixtures/ からのパスで返す。
func fixtureFiles(t *testing.T, dir, ext string) []string {
	t.Helper()
	entries, err := os.ReadDir(path.Join(FixturesDir(), dir))
	if err != nil {
		t.Fatalf("%s を読めません: %v", dir, err)
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && path.Ext(e.Name()) == ext {
			names = append(names, path.Join(dir, e.Name()))
		}
	}
	if len(names) == 0 {
		t.Fatalf("%s に %s のファイルがありません", dir, ext)
	}
	return names
}

// queryInt は、1つの整数を返す問い合わせを動かす。
func queryInt(t *testing.T, db *pgx.Conn, sql string, args ...any) int {
	t.Helper()
	var n int
	if err := db.QueryRow(t.Context(), sql, args...).Scan(&n); err != nil {
		t.Fatalf("%s: %v", sql, err)
	}
	return n
}

// backupFile は、バックアップの JSON の形である。Java 版の BackupResumeResponse と RestoreResumeRequest と同じ名前を持つ。
type backupFile struct {
	Version    string        `json:"version"`
	ExportedAt string        `json:"exportedAt"`
	Resume     *backupResume `json:"resume"`
}

type backupResume struct {
	ResumeName string `json:"resumeName"`
	Date       string `json:"date"`
	LastName   string `json:"lastName"`
	FirstName  string `json:"firstName"`
	Careers    []struct {
		CompanyName string `json:"companyName"`
		StartDate   string `json:"startDate"`
		EndDate     string `json:"endDate"`
		Active      bool   `json:"active"`
	} `json:"careers"`
	Projects []struct {
		CompanyName string `json:"companyName"`
		StartDate   string `json:"startDate"`
		EndDate     string `json:"endDate"`
		Active      bool   `json:"active"`
		Name        string `json:"name"`
		Overview    string `json:"overview"`
		TeamComp    string `json:"teamComp"`
		Role        string `json:"role"`
		Achievement string `json:"achievement"`
		Process     struct {
			Requirements    bool `json:"requirements"`
			BasicDesign     bool `json:"basicDesign"`
			DetailedDesign  bool `json:"detailedDesign"`
			Implementation  bool `json:"implementation"`
			IntegrationTest bool `json:"integrationTest"`
			SystemTest      bool `json:"systemTest"`
			Maintenance     bool `json:"maintenance"`
		} `json:"process"`
		TechStack struct {
			Frontend       map[string][]string `json:"frontend"`
			Backend        map[string][]string `json:"backend"`
			Infrastructure map[string][]string `json:"infrastructure"`
			Tools          map[string][]string `json:"tools"`
		} `json:"techStack"`
	} `json:"projects"`
	Certifications []struct {
		Name string `json:"name"`
		Date string `json:"date"`
	} `json:"certifications"`
	Portfolios []struct {
		Name      string `json:"name"`
		Overview  string `json:"overview"`
		TechStack string `json:"techStack"`
		Link      string `json:"link"`
	} `json:"portfolios"`
	SnsPlatforms []struct {
		Name string `json:"name"`
		Link string `json:"link"`
	} `json:"snsPlatforms"`
	SelfPromotions []struct {
		Title   string `json:"title"`
		Content string `json:"content"`
	} `json:"selfPromotions"`
}

// techStackKeys は、技術の並びの4つのまとまりごとの、Java 版の名前である。
var techStackKeys = map[string][]string{
	"frontend":       {"languages", "frameworks", "libraries", "buildTools", "packageManagers", "linters", "formatters", "testingTools"},
	"backend":        {"languages", "frameworks", "libraries", "buildTools", "packageManagers", "linters", "formatters", "testingTools", "ormTools", "auth"},
	"infrastructure": {"clouds", "operatingSystems", "containers", "databases", "webServers", "ciCdTools", "iacTools", "monitoringTools", "loggingTools"},
	"tools":          {"sourceControls", "projectManagements", "communicationTools", "documentationTools", "apiDevelopmentTools", "designTools", "editors", "developmentEnvironments"},
}

var (
	dayPattern   = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)
	monthPattern = regexp.MustCompile(`^\d{4}-\d{2}$`)
)

// decodeStrict は、知らない名前を許さずに JSON を読む。
func decodeStrict(data []byte, v any) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}

// checkBackup は、name のバックアップのファイルが、ファイルの名前どおりの形かを確かめる。
// basic.json は正しいバックアップ、wrong-version.json は版の違うバックアップ、
// no-resume.json は resume を含まないバックアップ、broken.json は JSON として読めないバックアップである。
func checkBackup(t *testing.T, name string, data []byte) {
	t.Helper()
	var b backupFile
	err := decodeStrict(data, &b)
	switch path.Base(name) {
	case "broken.json":
		if err == nil {
			t.Errorf("%s: JSON として読めないはずですが、読めました", name)
		}
	case "no-resume.json":
		if err != nil || b.Version != "1.0" || b.Resume != nil {
			t.Errorf("%s: 版が 1.0 で resume の無い形のはずですが、版 %q、resume %v、エラー %v", name, b.Version, b.Resume != nil, err)
		}
	case "wrong-version.json":
		if err != nil || b.Version == "1.0" || b.Version == "" || b.Resume == nil {
			t.Errorf("%s: 1.0 でない版と resume を持つはずですが、版 %q、エラー %v", name, b.Version, err)
		}
	case "basic.json":
		if err != nil || b.Version != "1.0" || b.Resume == nil || b.Resume.ResumeName == "" {
			t.Fatalf("%s: 版が 1.0 の正しいバックアップのはずですが、版 %q、エラー %v", name, b.Version, err)
		}
		r := b.Resume
		if len(r.Careers) == 0 || len(r.Projects) == 0 || len(r.Certifications) == 0 ||
			len(r.Portfolios) == 0 || len(r.SnsPlatforms) == 0 || len(r.SelfPromotions) == 0 {
			t.Errorf("%s: すべての項目を持つはずです", name)
		}
		// Java 版は、経歴書の日付を LocalDate(年月日)で、職歴と案件と資格の日付を YearMonth(年月)で読む
		dates := map[string]*regexp.Regexp{r.Date: dayPattern}
		for _, c := range r.Careers {
			dates[c.StartDate], dates[c.EndDate] = monthPattern, monthPattern
		}
		for _, p := range r.Projects {
			dates[p.StartDate], dates[p.EndDate] = monthPattern, monthPattern
		}
		for _, c := range r.Certifications {
			dates[c.Date] = monthPattern
		}
		for value, pattern := range dates {
			if value != "" && !pattern.MatchString(value) {
				t.Errorf("%s: 日付 %q が形 %s に合いません", name, value, pattern)
			}
		}
		for _, p := range r.Projects {
			for group, keys := range map[string]map[string][]string{
				"frontend": p.TechStack.Frontend, "backend": p.TechStack.Backend,
				"infrastructure": p.TechStack.Infrastructure, "tools": p.TechStack.Tools,
			} {
				for key := range keys {
					if !slices.Contains(techStackKeys[group], key) {
						t.Errorf("%s: 技術の並びの %s に知らない名前 %s があります", name, group, key)
					}
				}
			}
		}
	default:
		t.Errorf("%s: 知らないバックアップのファイルです。checkBackup に形を足してください", name)
	}
}

// exportSettings は、経歴書を書き出すときに画面が送る PDF の設定である。
type exportSettings struct {
	Format      string `json:"format"`
	Disposition string `json:"disposition"`
	PdfSettings struct {
		FontFamily string `json:"fontFamily"`
		FontSizes  struct {
			Title          float64 `json:"title"`
			Date           float64 `json:"date"`
			FullName       float64 `json:"fullName"`
			SectionHeading float64 `json:"sectionHeading"`
		} `json:"fontSizes"`
		TableHeaderColor struct {
			Hex string `json:"hex"`
		} `json:"tableHeaderColor"`
	} `json:"pdfSettings"`
}

func readExportSettings(t *testing.T, name string) exportSettings {
	t.Helper()
	data, err := readFixture(name)
	if err != nil {
		t.Fatalf("%s を読めません: %v", name, err)
	}
	var s exportSettings
	if err := decodeStrict(data, &s); err != nil {
		t.Fatalf("%s: 書き出しの設定として読めません: %v", name, err)
	}
	return s
}

// imageFormats は、画像のファイルの拡張子ごとの、image.Decode が返す形の名前である。
// 筋書きは、画面が送れる PNG と JPEG と GIF だけを送る。
var imageFormats = map[string]string{".png": "png", ".jpg": "jpeg", ".gif": "gif"}

// 初めのデータ: fixtures/ のすべてのファイルを読み込めることを確かめる。
// SQL のファイルは表の形を適用したデータベースに読み込み、Java 版の経歴書の決まりと、筋書きの決まりに合うかを確かめる。
func TestFixtures_AllLoadable(t *testing.T) {
	err := fs.WalkDir(os.DirFS(FixturesDir()), ".", func(name string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		dir, ext := path.Dir(name), path.Ext(name)
		switch {
		case (dir == "users" || dir == "resumes") && ext == ".sql":
			// 下のデータベースの確かめで読み込む
		case dir == "resumes" && ext == ".json":
			s := readExportSettings(t, name)
			if s.Format != "pdf" || s.PdfSettings.FontSizes.Title == 0 || s.PdfSettings.TableHeaderColor.Hex == "" {
				t.Errorf("%s: PDF の書き出しの設定がそろっていません: %+v", name, s)
			}
		case dir == "backups" && ext == ".json":
			data, err := readFixture(name)
			if err != nil {
				return err
			}
			checkBackup(t, name, data)
		case dir == "images":
			data, err := readFixture(name)
			if err != nil {
				return err
			}
			_, format, err := image.DecodeConfig(bytes.NewReader(data))
			if want, ok := imageFormats[ext]; !ok || err != nil || format != want {
				t.Errorf("%s: 画像の形 %q(エラー %v)は、拡張子 %s の形 %q と合いません", name, format, err, ext, want)
			}
		default:
			t.Errorf("%s: 知らない種類のファイルです", name)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("fixtures/ を読めません: %v", err)
	}

	db := fixtureDB(t)
	ctx := t.Context()

	t.Run("利用者が決まったパスワードでログインでき、USER の役割を持つ", func(t *testing.T) {
		rows, err := db.Query(ctx, `SELECT u.email, u.password, u.email_verified_at IS NOT NULL,
			EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = u.id AND r.name = 'USER')
			FROM users u ORDER BY u.email`)
		if err != nil {
			t.Fatalf("利用者を読めません: %v", err)
		}
		type user struct {
			email, hash      string
			verified, member bool
		}
		users, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (user, error) {
			var u user
			err := r.Scan(&u.email, &u.hash, &u.verified, &u.member)
			return u, err
		})
		if err != nil {
			t.Fatalf("利用者を読めません: %v", err)
		}
		if len(users) < 2 {
			t.Fatalf("権限の無い操作を確かめるため、利用者が2人以上いるはずですが、%d 人です", len(users))
		}
		for _, u := range users {
			if err := bcrypt.CompareHashAndPassword([]byte(u.hash), []byte(fixturePassword)); err != nil {
				t.Errorf("%s: パスワード %s でログインできません: %v", u.email, fixturePassword, err)
			}
			if !u.verified || !u.member {
				t.Errorf("%s: メールアドレスの確認(%v)か USER の役割(%v)がありません", u.email, u.verified, u.member)
			}
		}
	})

	// 次の問い合わせは、Java 版の経歴書の決まりか、筋書きの決まり(タスク3.5の実装のメモ)に反する行の数を数える。
	for name, sql := range map[string]string{
		// Java 版の Resume.validateIsCareerOverlap と同じ決まり。終わりの月と始めの月が同じなら重ならない
		"職歴の期間が重なる": `SELECT count(*) FROM careers a JOIN careers b ON a.resume_id = b.resume_id AND a.id < b.id
			WHERE (a.is_active AND b.is_active)
			   OR (NOT a.is_active AND NOT b.is_active AND a.end_date > b.start_date AND b.end_date > a.start_date)
			   OR (a.is_active AND NOT b.is_active AND b.end_date > a.start_date)
			   OR (b.is_active AND NOT a.is_active AND a.end_date > b.start_date)`,
		// Java 版の Period の決まり
		"期間の始めと終わりが決まりに合わない": `SELECT count(*) FROM (
			SELECT start_date, end_date, is_active FROM careers UNION ALL SELECT start_date, end_date, is_active FROM projects) p
			WHERE (is_active AND end_date IS NOT NULL) OR (NOT is_active AND (end_date IS NULL OR end_date < start_date))
			   OR extract(day FROM start_date) <> 1 OR extract(day FROM end_date) <> 1`,
		// 期間か日付が同じ要素は、Java 版で UUID の順に並び、版ごとに順が変わる
		"同じ経歴書で職歴の始めの月が重なる": `SELECT count(*) FROM (SELECT resume_id, start_date FROM careers GROUP BY 1, 2 HAVING count(*) > 1) d`,
		"同じ経歴書で案件の期間が重なる":   `SELECT count(*) FROM (SELECT resume_id, start_date, end_date FROM projects GROUP BY 1, 2, 3 HAVING count(*) > 1) d`,
		"同じ経歴書で資格の日付が重なる":   `SELECT count(*) FROM (SELECT resume_id, date FROM certifications GROUP BY 1, 2 HAVING count(*) > 1) d`,
		"案件の会社が職歴の会社にない":    `SELECT count(*) FROM projects p WHERE NOT EXISTS (SELECT 1 FROM careers c WHERE c.resume_id = p.resume_id AND c.company_name = p.company_name)`,
		"案件の技術の並びが無い":       `SELECT count(*) FROM projects p WHERE NOT EXISTS (SELECT 1 FROM project_tech_stacks s WHERE s.project_id = p.id)`,
		"名前と文の長さが Java 版の上限を超える": `SELECT count(*) FROM (
			SELECT char_length(name) > 50 OR char_length(overview) > 1000 OR char_length(team_comp) > 100
			    OR char_length(role) > 1000 OR char_length(achievement) > 1000 OR char_length(company_name) > 50 AS over FROM projects
			UNION ALL SELECT char_length(company_name) > 50 FROM careers
			UNION ALL SELECT char_length(name) > 50 FROM certifications
			UNION ALL SELECT char_length(name) > 50 OR char_length(overview) > 1000 OR char_length(tech_stack) > 1000 FROM portfolios
			UNION ALL SELECT char_length(name) > 50 FROM sns_platforms
			UNION ALL SELECT char_length(title) > 50 OR char_length(content) > 1000 FROM self_promotions
			UNION ALL SELECT char_length(name) > 50 OR char_length(last_name) > 10 OR char_length(first_name) > 10 FROM resumes) l
			WHERE over`,
		"リンクが https で始まらない": `SELECT count(*) FROM (SELECT link FROM portfolios UNION ALL SELECT link FROM sns_platforms) l WHERE link NOT LIKE 'https://%'`,
		// CB-001: ポートフォリオ、SNS、自己PR は、日本語の並べ替えの規則によらず順が決まる名前にする
		// 英大文字で始め、同じ並びの中で頭の文字を重ねなければ、どちらの規則でも頭の文字の ABC の順に並ぶ
		"並べ替えの規則で順が変わりうる名前": `WITH x AS (
			SELECT 'portfolio' AS kind, resume_id, name AS n FROM portfolios
			UNION ALL SELECT 'sns', resume_id, name FROM sns_platforms
			UNION ALL SELECT 'self', resume_id, title FROM self_promotions)
			SELECT count(*) FROM x WHERE n !~ '^[A-Z]' OR EXISTS (
				SELECT 1 FROM x y WHERE y.kind = x.kind AND y.resume_id = x.resume_id AND y.n <> x.n AND left(y.n, 1) = left(x.n, 1))`,
	} {
		t.Run(name+"行が無い", func(t *testing.T) {
			if n := queryInt(t, db, sql); n != 0 {
				t.Errorf("%s行が %d 件あります", name, n)
			}
		})
	}

	// タスク3.4の実装のメモ「行の並び」: UUID と日時のほかの列がすべて同じ行どうしは、データベースを写すときの番号の付く順が
	// 版ごとに変わりうるので、初めのデータに置かない。日時は正規化で形に置き換わるので、区別に使えない。
	// user_roles は、UUID と日時の列しか持たず、データの側では区別できない。Java 版も利用者ごとに同じ形の行を作るので、確かめから外す。
	t.Run("UUID と日時のほかが同じ行が無い", func(t *testing.T) {
		rows, err := db.Query(t.Context(), `SELECT c.table_name,
				coalesce(array_agg(c.column_name::text) FILTER (WHERE c.data_type = 'uuid' OR c.data_type LIKE 'timestamp%'), '{}')
			FROM information_schema.columns c JOIN information_schema.tables t USING (table_schema, table_name)
			WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE' AND c.table_name NOT IN ('flyway_schema_history', 'user_roles')
			GROUP BY 1 ORDER BY 1`)
		if err != nil {
			t.Fatalf("表の列を読めません: %v", err)
		}
		type table struct {
			name    string
			ignored []string
		}
		tables, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (table, error) {
			var tb table
			err := r.Scan(&tb.name, &tb.ignored)
			return tb, err
		})
		if err != nil || len(tables) == 0 {
			t.Fatalf("表の列を読めません: %d 個, %v", len(tables), err)
		}
		for _, tb := range tables {
			sql := fmt.Sprintf(`SELECT count(*) FROM (SELECT to_jsonb(t) - $1::text[] FROM %s t GROUP BY 1 HAVING count(*) > 1) d`,
				pgx.Identifier{tb.name}.Sanitize())
			if n := queryInt(t, db, sql, tb.ignored); n != 0 {
				t.Errorf("%s に、UUID と日時のほかが同じ行の組が %d 組あります", tb.name, n)
			}
		}
	})
}

// 初めのデータ: 4種類の経歴書と、2つのフォントの書き出しの設定があることを確かめる。
func TestFixtures_ResumeKindsPresent(t *testing.T) {
	db := fixtureDB(t)
	children := func(resume string) int {
		return queryInt(t, db, `SELECT
			(SELECT count(*) FROM careers c WHERE c.resume_id = r.id) + (SELECT count(*) FROM projects p WHERE p.resume_id = r.id) +
			(SELECT count(*) FROM certifications c WHERE c.resume_id = r.id) + (SELECT count(*) FROM portfolios p WHERE p.resume_id = r.id) +
			(SELECT count(*) FROM sns_platforms s WHERE s.resume_id = r.id) + (SELECT count(*) FROM self_promotions s WHERE s.resume_id = r.id)
			FROM resumes r WHERE r.name = $1`, resume)
	}
	count := func(table, resume string) int {
		return queryInt(t, db, `SELECT count(*) FROM `+pgx.Identifier{table}.Sanitize()+` x JOIN resumes r ON r.id = x.resume_id WHERE r.name = $1`, resume)
	}

	t.Run("4種類の経歴書が1つずつある", func(t *testing.T) {
		for _, name := range []string{resumeEmpty, resumeManyPages, resumeLongText, resumeFonts} {
			if n := queryInt(t, db, `SELECT count(*) FROM resumes WHERE name = $1`, name); n != 1 {
				t.Errorf("経歴書 %s が %d 件あります", name, n)
			}
		}
	})
	t.Run("項目が空の経歴書は、氏名も子の項目も持たない", func(t *testing.T) {
		if n := children(resumeEmpty); n != 0 {
			t.Errorf("子の項目が %d 件あります", n)
		}
		if n := queryInt(t, db, `SELECT count(*) FROM resumes WHERE name = $1 AND last_name IS NULL AND first_name IS NULL`, resumeEmpty); n != 1 {
			t.Error("氏名があります")
		}
	})
	t.Run("職歴と案件の多い経歴書は、職歴を10件以上、案件を20件以上持つ", func(t *testing.T) {
		if c, p := count("careers", resumeManyPages), count("projects", resumeManyPages); c < 10 || p < 20 {
			t.Errorf("職歴 %d 件、案件 %d 件です", c, p)
		}
	})
	t.Run("長い文の経歴書は、改行を含む500文字以上の文を、案件と自己PRとポートフォリオに持つ", func(t *testing.T) {
		for table, col := range map[string]string{"projects": "achievement", "self_promotions": "content", "portfolios": "overview"} {
			n := queryInt(t, db, `SELECT count(*) FROM `+pgx.Identifier{table}.Sanitize()+` x JOIN resumes r ON r.id = x.resume_id
				WHERE r.name = $1 AND char_length(x.`+pgx.Identifier{col}.Sanitize()+`) >= 500 AND position(chr(10) in x.`+pgx.Identifier{col}.Sanitize()+`) > 0`, resumeLongText)
			if n == 0 {
				t.Errorf("%s の %s に、改行を含む500文字以上の文がありません", table, col)
			}
		}
	})
	t.Run("フォントを比べる経歴書は、すべての項目を持つ", func(t *testing.T) {
		for _, table := range []string{"careers", "projects", "certifications", "portfolios", "sns_platforms", "self_promotions"} {
			if count(table, resumeFonts) == 0 {
				t.Errorf("%s がありません", table)
			}
		}
	})
	t.Run("2つのフォントのそれぞれを選んだ書き出しの設定がある", func(t *testing.T) {
		var fonts []string
		for _, name := range fixtureFiles(t, "resumes", ".json") {
			fonts = append(fonts, readExportSettings(t, name).PdfSettings.FontFamily)
		}
		slices.Sort(fonts)
		if !slices.Equal(fonts, []string{"NotoSansJP", "NotoSerifJP"}) {
			t.Errorf("書き出しの設定のフォント = %v, want NotoSansJP と NotoSerifJP の1つずつ", fonts)
		}
	})
}
