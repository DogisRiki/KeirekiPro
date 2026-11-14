package users

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// deleteTestPassword は、退会のテストの利用者がログインに使う文字列である。
const deleteTestPassword = "Passw0rd123"

// deleteEnv は、退会のテストの部品の束である。
type deleteEnv struct {
	users  *Service
	auth   *auth.Service
	mailer *recordingSES
	redis  redis.UniversalClient
}

// newDeleteEnv は、テストの Postgres と Valkey と偽の SES と、画像の置き場所 store につなぎ、今の時刻を testNow にした部品を作る。
// ログインの状態の値とログインを続けるための値には、1時間の有効な時間を付ける。
func newDeleteEnv(t *testing.T, store S3Client) deleteEnv {
	t.Helper()
	templates, err := backend.MailTemplates()
	if err != nil {
		t.Fatal(err)
	}
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	t.Cleanup(func() { _ = client.Close() })
	mailer := &recordingSES{}
	now := func() time.Time { return testNow }
	a := auth.New(auth.Deps{
		Pool:  testPool,
		Redis: client,
		SES:   mailer,
		App: config.App{
			ApplicationName: "KeirekiPro",
			SiteName:        "KeirekiPro",
			SiteURL:         "https://keirekipro.example.com",
			FrontendBaseURL: testFrontendBaseURL,
			SESFromAddress:  "noreply@example.com",
		},
		MailTemplates: templates,
		JWT:           config.JWT{Secret: uuid.NewString(), AccessTokenValidity: time.Hour, RefreshTokenValidity: time.Hour},
		Now:           now,
	})
	return deleteEnv{
		users:  New(Deps{Pool: testPool, Redis: client, Auth: a, S3: store, Bucket: testBucket, AWSEndpoint: testAWSEndpoint, Now: now}),
		auth:   a,
		mailer: mailer,
		redis:  client,
	}
}

// accountRows は、退会で消す11の表に足した、1人の利用者の行の ID である。
type accountRows struct {
	user, resume, project, career, certification, portfolio, snsPlatform, selfPromotion uuid.UUID
}

// accountTables は、退会で消す11の表と、accountRows の ID で行を数える問い合わせである。
var accountTables = []struct {
	name  string
	query string
	id    func(a accountRows) uuid.UUID
}{
	{"project_tech_stacks", "SELECT count(*) FROM project_tech_stacks WHERE project_id = $1::uuid", func(a accountRows) uuid.UUID { return a.project }},
	{"projects", "SELECT count(*) FROM projects WHERE id = $1::uuid", func(a accountRows) uuid.UUID { return a.project }},
	{"careers", "SELECT count(*) FROM careers WHERE id = $1::uuid", func(a accountRows) uuid.UUID { return a.career }},
	{"certifications", "SELECT count(*) FROM certifications WHERE id = $1::uuid", func(a accountRows) uuid.UUID { return a.certification }},
	{"portfolios", "SELECT count(*) FROM portfolios WHERE id = $1::uuid", func(a accountRows) uuid.UUID { return a.portfolio }},
	{"sns_platforms", "SELECT count(*) FROM sns_platforms WHERE id = $1::uuid", func(a accountRows) uuid.UUID { return a.snsPlatform }},
	{"self_promotions", "SELECT count(*) FROM self_promotions WHERE id = $1::uuid", func(a accountRows) uuid.UUID { return a.selfPromotion }},
	{"resumes", "SELECT count(*) FROM resumes WHERE id = $1::uuid", func(a accountRows) uuid.UUID { return a.resume }},
	{"user_auth_providers", "SELECT count(*) FROM user_auth_providers WHERE user_id = $1::uuid", func(a accountRows) uuid.UUID { return a.user }},
	{"user_roles", "SELECT count(*) FROM user_roles WHERE user_id = $1::uuid", func(a accountRows) uuid.UUID { return a.user }},
	{"users", "SELECT count(*) FROM users WHERE id = $1::uuid", func(a accountRows) uuid.UUID { return a.user }},
}

// insertAccountRows は、利用者 user の職務経歴書と、その下の7つの表の行を1つずつ足す。
func insertAccountRows(t *testing.T, user uuid.UUID) accountRows {
	t.Helper()
	a := accountRows{
		user: user, resume: uuid.New(), project: uuid.New(), career: uuid.New(), certification: uuid.New(),
		portfolio: uuid.New(), snsPlatform: uuid.New(), selfPromotion: uuid.New(),
	}
	statements := []struct {
		sql  string
		args []any
	}{
		{
			"INSERT INTO resumes (id, user_id, name, date, created_at, updated_at) " +
				"VALUES ($1::uuid, $2::uuid, '職務経歴書', DATE '2026-01-02', TIMESTAMP '2026-01-02 03:04:05', TIMESTAMP '2026-01-02 03:04:05')",
			[]any{a.resume.String(), user.String()},
		},
		{
			"INSERT INTO projects (id, resume_id, company_name, start_date, is_active, name, overview, team_comp, role, achievement, " +
				"requirements, basic_design, detailed_design, implementation, integration_test, system_test, maintenance) " +
				"VALUES ($1::uuid, $2::uuid, '会社', DATE '2026-01-01', TRUE, '案件', '概要', '5人', '開発', '成果', TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE)",
			[]any{a.project.String(), a.resume.String()},
		},
		{
			"INSERT INTO project_tech_stacks (project_id, frontend_languages) VALUES ($1::uuid, ARRAY['TypeScript'])",
			[]any{a.project.String()},
		},
		{
			"INSERT INTO careers (id, resume_id, company_name, start_date, is_active) VALUES ($1::uuid, $2::uuid, '会社', DATE '2026-01-01', TRUE)",
			[]any{a.career.String(), a.resume.String()},
		},
		{
			"INSERT INTO certifications (id, resume_id, name, date) VALUES ($1::uuid, $2::uuid, '資格', DATE '2026-01-01')",
			[]any{a.certification.String(), a.resume.String()},
		},
		{
			"INSERT INTO portfolios (id, resume_id, name, overview, tech_stack, link) VALUES ($1::uuid, $2::uuid, '作品', '概要', 'Go', 'https://example.com')",
			[]any{a.portfolio.String(), a.resume.String()},
		},
		{
			"INSERT INTO sns_platforms (id, resume_id, name, link) VALUES ($1::uuid, $2::uuid, 'GitHub', 'https://github.com/a')",
			[]any{a.snsPlatform.String(), a.resume.String()},
		},
		{
			"INSERT INTO self_promotions (id, resume_id, title, content) VALUES ($1::uuid, $2::uuid, '題', '本文')",
			[]any{a.selfPromotion.String(), a.resume.String()},
		},
	}
	for _, s := range statements {
		if _, err := testPool.Exec(t.Context(), s.sql, s.args...); err != nil {
			t.Fatalf("行を足せません: %v\n%s", err, s.sql)
		}
	}
	return a
}

// wantAccountRows は、11の表のどれにも、a の行が want 個ずつあるかを確かめる。
func wantAccountRows(t *testing.T, a accountRows, want int) {
	t.Helper()
	for _, table := range accountTables {
		var n int
		if err := testPool.QueryRow(t.Context(), table.query, table.id(a).String()).Scan(&n); err != nil {
			t.Fatalf("表 %s の行を数えられません: %v", table.name, err)
		}
		if n != want {
			t.Errorf("表 %s の行 = %d 個、期待 = %d 個", table.name, n, want)
		}
	}
}

// insertTokenVersion は、利用者 id の世代の番号の行を 0 で足し、bumps 回だけ1つ上げる。
func insertTokenVersion(t *testing.T, env deleteEnv, id uuid.UUID, bumps int) {
	t.Helper()
	q := sqlcgen.New(testPool)
	if err := q.InsertTokenVersion(t.Context(), sqlcgen.InsertTokenVersionParams{UserID: pgtype.UUID{Bytes: id, Valid: true}, UpdatedAt: oldStamp}); err != nil {
		t.Fatalf("世代の番号の行を足せません: %v", err)
	}
	for range bumps {
		if err := env.auth.BumpTokenVersion(t.Context(), q, id); err != nil {
			t.Fatal(err)
		}
	}
}

// tokenVersionRows は、利用者 id の世代の番号の行の数を返す。
func tokenVersionRows(t *testing.T, id uuid.UUID) int {
	t.Helper()
	var n int
	if err := testPool.QueryRow(t.Context(), "SELECT count(*) FROM user_token_versions WHERE user_id = $1::uuid", id.String()).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// verifiedUser は、確認の済んだメールアドレスとパスワード deleteTestPassword と Google の連携を持つ利用者を作る。
func verifiedUser(t *testing.T) uuid.UUID {
	t.Helper()
	hash, err := auth.HashPassword(deleteTestPassword)
	if err != nil {
		t.Fatal(err)
	}
	return insertUser(t, userRow{Email: someText("d@example.com"), Password: someText(hash), EmailVerifiedAt: oldStamp}, "google")
}

// login は、利用者 id のメールアドレスとパスワードでログインし、ログインの状態の値とログインを続けるための値を返す。
func login(t *testing.T, env deleteEnv, id uuid.UUID) auth.SessionTokens {
	t.Helper()
	r, err := env.auth.Login(t.Context(), loadUser(t, id).Row.Email.String, deleteTestPassword)
	if err != nil {
		t.Fatalf("ログインできません: %v", err)
	}
	if r.Session.RefreshToken == "" {
		t.Fatalf("ログインを続けるための値が無い: %+v", r)
	}
	return r.Session
}

// redisKeys は、keys のうち Valkey にある名前の数を返す。
func redisKeys(t *testing.T, env deleteEnv, keys ...string) int64 {
	t.Helper()
	n, err := env.redis.Exists(t.Context(), keys...).Result()
	if err != nil {
		t.Fatal(err)
	}
	return n
}

// sessionKeys は、ログインを続けるための値 sessions のハッシュの名前と、利用者 id の集合の名前を返す。
// 名前の形は、Java 版の RedisRefreshTokenStore と同じである。期待の値は、処理の側の定数に頼らずに組み立てる。
func sessionKeys(id uuid.UUID, sessions ...auth.SessionTokens) []string {
	keys := []string{"user-refresh-tokens:" + id.String()}
	for _, s := range sessions {
		keys = append(keys, "refresh-token:"+s.RefreshToken)
	}
	return keys
}

// putImages は、偽の AWS の置き場所に、keys の名前の画像を置く。
func putImages(t *testing.T, keys ...string) {
	t.Helper()
	client := newTestS3(t)
	for _, key := range keys {
		if _, err := client.PutObject(t.Context(), &s3.PutObjectInput{
			Bucket: aws.String(testBucket), Key: aws.String(key), Body: strings.NewReader("画像"), ContentType: aws.String("image/png"),
		}); err != nil {
			t.Fatalf("画像 %s を置けません: %v", key, err)
		}
	}
}

// wantImages は、keys の名前の画像が、置き場所にあるかどうかが present かを確かめる。
func wantImages(t *testing.T, present bool, keys ...string) {
	t.Helper()
	for _, key := range keys {
		if _, _, ok := storedObject(t, key); ok != present {
			t.Errorf("画像 %s がある = %v、期待 = %v", key, ok, present)
		}
	}
}

// fiveImageKeys は、利用者 id の4つの拡張子の画像の名前と、今の画像の名前 current である。
func fiveImageKeys(id uuid.UUID, current string) []string {
	return []string{imageKeyOf(id, "jpg"), imageKeyOf(id, "jpeg"), imageKeyOf(id, "png"), imageKeyOf(id, "gif"), current}
}

// legacyImage は、命名の規則を入れる前の形の、利用者 id の画像の名前である。
func legacyImage(id uuid.UUID) string {
	return "/profile/image/legacy-" + id.String() + ".png"
}

// TestDeleteUser_RemovesRowsImagesAndTokens は、退会で、11の表の行と、5つの画像の名前と、
// ログインを続けるための値が消え、ほかの利用者の行と画像は残ることを確かめる。
func TestDeleteUser_RemovesRowsImagesAndTokens(t *testing.T) {
	env := newDeleteEnv(t, newTestS3(t))
	id := verifiedUser(t)
	changeUser(t, id, func(u *auth.StoredUser) { u.Row.ProfileImage = someText(legacyImage(id)) })
	rows := insertAccountRows(t, id)
	insertTokenVersion(t, env, id, 0)
	images := fiveImageKeys(id, legacyImage(id))
	putImages(t, images...)
	sessions := []auth.SessionTokens{login(t, env, id), login(t, env, id)}
	keys := sessionKeys(id, sessions...)

	other := verifiedUser(t)
	otherRows := insertAccountRows(t, other)
	insertTokenVersion(t, env, other, 0)
	otherImages := []string{imageKeyOf(other, "png"), imageKeyOf(other, "jpg")}
	putImages(t, otherImages...)
	otherKeys := sessionKeys(other, login(t, env, other))

	wantAccountRows(t, rows, 1)
	if n := redisKeys(t, env, keys...); n != int64(len(keys)) {
		t.Fatalf("退会の前のログインを続けるための値 = %d 個、期待 = %d 個", n, len(keys))
	}

	if err := env.users.DeleteUser(t.Context(), id); err != nil {
		t.Fatalf("DeleteUser: %v", err)
	}

	wantAccountRows(t, rows, 0)
	wantImages(t, false, images...)
	if n := redisKeys(t, env, keys...); n != 0 {
		t.Errorf("退会のあとのログインを続けるための値 = %d 個、期待 = 0 個", n)
	}

	wantAccountRows(t, otherRows, 1)
	wantImages(t, true, otherImages...)
	if n := redisKeys(t, env, otherKeys...); n != int64(len(otherKeys)) {
		t.Errorf("ほかの利用者のログインを続けるための値 = %d 個、期待 = %d 個", n, len(otherKeys))
	}
	if n := tokenVersionRows(t, other); n != 1 {
		t.Errorf("ほかの利用者の世代の番号の行 = %d 個、期待 = 1 個", n)
	}
}

// TestDeleteUser_NoDuplicateKeyDelete は、消す画像の名前が、4つの拡張子の名前と今の画像の名前の順で、
// 同じ名前を2回消さないことを確かめる。
func TestDeleteUser_NoDuplicateKeyDelete(t *testing.T) {
	tests := []struct {
		name    string
		current func(id uuid.UUID) pgtype.Text
		extra   func(id uuid.UUID) []string
	}{
		{"今の画像が png の名前", func(id uuid.UUID) pgtype.Text { return someText(imageKeyOf(id, "png")) }, func(uuid.UUID) []string { return nil }},
		{"今の画像が gif の名前", func(id uuid.UUID) pgtype.Text { return someText(imageKeyOf(id, "gif")) }, func(uuid.UUID) []string { return nil }},
		{"今の画像が規則の前の名前", func(id uuid.UUID) pgtype.Text { return someText(legacyImage(id)) }, func(id uuid.UUID) []string { return []string{legacyImage(id)} }},
		{"今の画像が無い", func(uuid.UUID) pgtype.Text { return pgtype.Text{} }, func(uuid.UUID) []string { return nil }},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fake := &fakeS3{}
			env := newDeleteEnv(t, fake)
			id := verifiedUser(t)
			changeUser(t, id, func(u *auth.StoredUser) { u.Row.ProfileImage = tt.current(id) })

			if err := env.users.DeleteUser(t.Context(), id); err != nil {
				t.Fatalf("DeleteUser: %v", err)
			}

			want := append([]string{imageKeyOf(id, "jpg"), imageKeyOf(id, "jpeg"), imageKeyOf(id, "png"), imageKeyOf(id, "gif")}, tt.extra(id)...)
			var got []string
			for _, d := range fake.deletes {
				if aws.ToString(d.Bucket) != testBucket {
					t.Errorf("置き場所 = %q、期待 = %q", aws.ToString(d.Bucket), testBucket)
				}
				got = append(got, aws.ToString(d.Key))
			}
			if !reflect.DeepEqual(got, want) {
				t.Errorf("消した画像の名前 = %q、期待 = %q", got, want)
			}
		})
	}
}

// TestDeleteUser_InvalidatesSessions は、退会のあと、どの端末のログインの状態の値も、ログインを続けるための値も
// 使えなくなることを確かめる。
func TestDeleteUser_InvalidatesSessions(t *testing.T) {
	env := newDeleteEnv(t, newTestS3(t))
	id := verifiedUser(t)
	insertTokenVersion(t, env, id, 1)
	sessions := []auth.SessionTokens{login(t, env, id), login(t, env, id)}
	for _, s := range sessions {
		if _, err := env.auth.VerifyAccessToken(t.Context(), s.AccessToken); err != nil {
			t.Fatalf("退会の前にログインの状態の値を使えない: %v", err)
		}
	}

	if err := env.users.DeleteUser(t.Context(), id); err != nil {
		t.Fatalf("DeleteUser: %v", err)
	}

	for i, s := range sessions {
		if _, err := env.auth.VerifyAccessToken(t.Context(), s.AccessToken); !errors.Is(err, auth.ErrInvalidToken) {
			t.Errorf("端末 %d のログインの状態の値の誤り = %v、期待 = %v", i, err, auth.ErrInvalidToken)
		}
		_, err := env.auth.Refresh(t.Context(), s.RefreshToken)
		var e *auth.Error
		if !errors.As(err, &e) || e.Status != 401 {
			t.Errorf("端末 %d のログインを続けるための値の誤り = %v、期待 = 401", i, err)
		}
	}
	if n := redisKeys(t, env, sessionKeys(id, sessions...)...); n != 0 {
		t.Errorf("ログインを続けるための値 = %d 個、期待 = 0 個", n)
	}
	if n := tokenVersionRows(t, id); n != 0 {
		t.Errorf("世代の番号の行 = %d 個、期待 = 0 個", n)
	}
}

// TestDeleteUser_BumpInTransactionDoesNotBlock は、世代の番号の行を持つ利用者の退会が、
// 世代の番号を上げる問い合わせで待たずに終わることを確かめる。トランザクションの外の接続で問い合わせを送ると、
// トランザクションが消した行のロックを待ち続け、期限で誤りになる。
func TestDeleteUser_BumpInTransactionDoesNotBlock(t *testing.T) {
	env := newDeleteEnv(t, newTestS3(t))
	id := verifiedUser(t)
	insertTokenVersion(t, env, id, 2)

	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	if err := env.users.DeleteUser(ctx, id); err != nil {
		t.Fatalf("DeleteUser: %v", err)
	}
	if n := tokenVersionRows(t, id); n != 0 {
		t.Errorf("世代の番号の行 = %d 個、期待 = 0 個", n)
	}
	wantAccountRows(t, accountRows{user: id}, 0)
}

// TestDeleteUser_MailOnlyWhenVerified は、退会の完了のメールを、メールアドレスの確認が済んだ利用者にだけ、
// そのメールアドレスへ送ることを確かめる。
func TestDeleteUser_MailOnlyWhenVerified(t *testing.T) {
	tests := []struct {
		name     string
		row      userRow
		provider []string
		mailed   bool
	}{
		{"確認の済んだメールアドレス", userRow{Email: someText("v@example.com"), EmailVerifiedAt: oldStamp}, nil, true},
		{"確認の済んでいないメールアドレス", userRow{Email: someText("u@example.com")}, nil, false},
		{"確認の日時だけでメールアドレスが無い", userRow{EmailVerifiedAt: oldStamp}, []string{"github"}, false},
		{"設定待ちのメールアドレスだけ", userRow{PendingEmail: someText(uuid.NewString() + "@example.com")}, []string{"google"}, false},
		{"連携だけ", userRow{}, []string{"google"}, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			env := newDeleteEnv(t, newTestS3(t))
			id := insertUser(t, tt.row, tt.provider...)
			email := loadUser(t, id).Row.Email.String

			if err := env.users.DeleteUser(t.Context(), id); err != nil {
				t.Fatalf("DeleteUser: %v", err)
			}
			wantAccountRows(t, accountRows{user: id}, 0)

			if !tt.mailed {
				if len(env.mailer.got) != 0 {
					t.Errorf("メールを %d 通送った、期待 = 送らない", len(env.mailer.got))
				}
				return
			}
			if len(env.mailer.got) != 1 {
				t.Fatalf("メールを %d 通送った、期待 = 1 通", len(env.mailer.got))
			}
			m := env.mailer.got[0]
			if got := m.Destination.ToAddresses; !reflect.DeepEqual(got, []string{email}) {
				t.Errorf("宛先 = %q、期待 = %q", got, email)
			}
			if got := aws.ToString(m.Message.Subject.Data); got != "【KeirekiPro】退会手続き完了のお知らせ" {
				t.Errorf("件名 = %q", got)
			}
			if body := aws.ToString(m.Message.Body.Text.Data); !strings.Contains(body, "山田太郎") || !strings.Contains(body, "https://keirekipro.example.com") {
				t.Errorf("本文に名前とサイトの URL が無い: %q", body)
			}
		})
	}
}

// TestDeleteUser_MailFailureRollsBack は、退会の完了のメールを送れないときと作れないときに、誤りを返し、
// 11の表の行と世代の番号の行を戻すことを確かめる。画像とログインを続けるための値は、Java 版と同じく消えたまま残る。
func TestDeleteUser_MailFailureRollsBack(t *testing.T) {
	sesErr := errors.New("SES が止まっている")
	tests := []struct {
		name   string
		sesErr error
		change func(u *auth.StoredUser)
	}{
		{"送れない", sesErr, func(*auth.StoredUser) {}},
		{"名前が無くて作れない", nil, func(u *auth.StoredUser) { u.Row.Username = pgtype.Text{} }},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			env := newDeleteEnv(t, newTestS3(t))
			env.mailer.err = tt.sesErr
			id := verifiedUser(t)
			changeUser(t, id, func(u *auth.StoredUser) {
				u.Row.ProfileImage = someText(legacyImage(id))
				tt.change(u)
			})
			rows := insertAccountRows(t, id)
			insertTokenVersion(t, env, id, 0)
			images := fiveImageKeys(id, legacyImage(id))
			putImages(t, images...)
			keys := sessionKeys(id, login(t, env, id))

			err := env.users.DeleteUser(t.Context(), id)
			if err == nil {
				t.Fatal("誤り = nil、期待 = メールの誤り")
			}
			var e *auth.Error
			if errors.As(err, &e) {
				t.Errorf("誤り = %d %q、期待 = 500 にする誤り", e.Status, e.Message)
			}
			if tt.sesErr != nil && !errors.Is(err, tt.sesErr) {
				t.Errorf("誤り = %v、期待 = %v を包んだ誤り", err, tt.sesErr)
			}

			wantAccountRows(t, rows, 1)
			if n := tokenVersionRows(t, id); n != 1 {
				t.Errorf("世代の番号の行 = %d 個、期待 = 1 個", n)
			}
			wantImages(t, false, images...)
			if n := redisKeys(t, env, keys...); n != 0 {
				t.Errorf("ログインを続けるための値 = %d 個、期待 = 0 個", n)
			}
		})
	}
}

// TestDeleteUser_ImageDeleteFails は、画像を消せないときに、誤りを返し、行を戻し、ログインを続けるための値を消さず、
// メールを送らないことを確かめる。Java 版は、画像を消してから、ログインの状態を使えなくする。
func TestDeleteUser_ImageDeleteFails(t *testing.T) {
	deleteErr := errors.New("S3 が止まっている")
	fake := &fakeS3{err: deleteErr}
	env := newDeleteEnv(t, fake)
	id := verifiedUser(t)
	rows := insertAccountRows(t, id)
	keys := sessionKeys(id, login(t, env, id))

	err := env.users.DeleteUser(t.Context(), id)
	if !errors.Is(err, deleteErr) {
		t.Fatalf("誤り = %v、期待 = %v を包んだ誤り", err, deleteErr)
	}
	var e *auth.Error
	if errors.As(err, &e) {
		t.Errorf("誤り = %d %q、期待 = 500 にする誤り", e.Status, e.Message)
	}
	if len(fake.deletes) != 1 {
		t.Errorf("画像を消す要求 = %d 回、期待 = 1 回", len(fake.deletes))
	}
	wantAccountRows(t, rows, 1)
	if n := redisKeys(t, env, keys...); n != int64(len(keys)) {
		t.Errorf("ログインを続けるための値 = %d 個、期待 = %d 個", n, len(keys))
	}
	if len(env.mailer.got) != 0 {
		t.Errorf("メールを %d 通送った、期待 = 送らない", len(env.mailer.got))
	}
}

// TestDeleteUser_UserGone は、すでに居ない利用者の退会を、Cookie を消させる 401 で断り、画像を消さず、メールを送らないことを確かめる。
func TestDeleteUser_UserGone(t *testing.T) {
	fake := &fakeS3{}
	env := newDeleteEnv(t, fake)

	err := env.users.DeleteUser(t.Context(), uuid.New())
	var e *auth.Error
	if !errors.As(err, &e) {
		t.Fatalf("誤り = %v、期待 = 401 の誤り", err)
	}
	if e.Status != 401 || e.Message != MessageInvalidAccess || !e.ClearSession {
		t.Errorf("誤り = %d %q Cookie を消す=%v、期待 = 401 %q Cookie を消す", e.Status, e.Message, e.ClearSession, MessageInvalidAccess)
	}
	if len(fake.deletes) != 0 {
		t.Errorf("画像を消す要求 = %d 回、期待 = 0 回", len(fake.deletes))
	}
	if len(env.mailer.got) != 0 {
		t.Errorf("メールを %d 通送った、期待 = 送らない", len(env.mailer.got))
	}
}
