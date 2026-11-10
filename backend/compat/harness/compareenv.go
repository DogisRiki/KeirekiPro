//go:build compat

package harness

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"path/filepath"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
	"github.com/DogisRiki/KeirekiPro/backend/compat/pdfcmp"
)

// ChangedBehaviorsFile は、変えた動きの一覧 backend/compat/changed-behaviors.yaml のパスを返す。
func ChangedBehaviorsFile() string {
	return filepath.Join(FixturesDir(), "..", "changed-behaviors.yaml")
}

// CompareEnv は、Java 版と Go 版を、版ごとの Postgres と Redis と、1つの fakeaws と1つの fakeoidc につないだ環境である。
// fakeaws は、版ごとのホスト名 fakeaws-<版> で呼ばれ、版ごとに記録を分ける。
// どちらの版も、同じ JWT の値と同じ外部のログインのクライアントを使う。
type CompareEnv struct {
	// Stores は、版の名前ごとの、その版がつなぐ Postgres と Redis である。
	Stores map[string]*Store
	// URLs は、版の名前ごとの、テストの処理から届く backend の URL である。
	URLs map[string]string
	// Startup は、版の名前ごとの、その位置に置いた backend の起動から /healthz が 200 を返すまでの時間である。
	// 起動の時間を測る backend(Go 版のイメージ)の位置の分だけを持つ。
	Startup map[string]time.Duration
	// Behaviors は、変えた動きの一覧である。StartCompareEnv が changed-behaviors.yaml から読む。
	Behaviors []ChangedBehavior
	// PDF は、PDF の本文の比べ方である。StartCompareEnv が pdfcmp にする。
	PDF PDFComparer
	// Operations は、仕様書の操作である。段が呼ぶ操作の名前を引くのに使う。
	Operations Operations

	fakes  *fakes
	client *http.Client
}

// awsHost は、版 version の backend が fakeaws を呼ぶ名前である。
func awsHost(version string) string {
	return fakeaws.HostPrefix + version
}

// StartCompareEnv は、env のネットワークに、版ごとの Postgres と Redis と、fakeaws と fakeoidc と、backends の2つの版を起動する。
// images は BuildImages の結果で、Postgres と Redis と fakeaws と fakeoidc のイメージを含む。
// backends は、版の名前(VersionJava と VersionGo)ごとの、その位置に置く backend である。
// 途中で失敗したときは、作った Redis のクライアントを閉じて誤りを返す。コンテナは env が片付ける。
func StartCompareEnv(ctx context.Context, env *Env, images Images, backends map[string]Backend) (*CompareEnv, error) {
	for _, version := range []string{VersionJava, VersionGo} {
		if _, ok := backends[version]; !ok {
			return nil, fmt.Errorf("harness: 版 %s の位置に置く backend がありません", version)
		}
	}
	behaviors, err := LoadChangedBehaviors(ChangedBehaviorsFile())
	if err != nil {
		return nil, err
	}
	ops, err := LoadOperations(OpenAPIFile())
	if err != nil {
		return nil, err
	}
	c := &CompareEnv{
		Stores: map[string]*Store{}, URLs: map[string]string{}, Startup: map[string]time.Duration{},
		Behaviors: behaviors, PDF: pdfcmp.Describe, Operations: ops, client: NewHTTPClient(),
	}
	if err := c.start(ctx, env, images, backends); err != nil {
		_ = c.Close()
		return nil, err
	}
	return c, nil
}

func (c *CompareEnv) start(ctx context.Context, env *Env, images Images, backends map[string]Backend) error {
	for _, version := range []string{VersionJava, VersionGo} {
		st, err := startStore(ctx, env, images, "-"+version)
		if err != nil {
			return err
		}
		c.Stores[version] = st
	}
	f, err := startFakes(ctx, env, images, awsHost(VersionJava), awsHost(VersionGo))
	if err != nil {
		return err
	}
	c.fakes = f
	var urls []string
	for _, version := range []string{VersionJava, VersionGo} {
		b := f.backingFor(c.Stores[version], awsHost(version))
		// JavaSecrets は GoSecrets を含むので、どちらの版のイメージを置いても、読む秘密の値がそろう。
		if err := RegisterSecrets(ctx, f.client, f.AWSURL, version, JavaSecrets(b)); err != nil {
			return err
		}
		_, url, startup, err := startBackend(ctx, env, version, backends[version], b)
		if err != nil {
			return err
		}
		if backends[version].MeasureStartup {
			c.Startup[version] = startup
		}
		c.URLs[version] = url
		urls = append(urls, url)
	}
	return f.registerRedirects(ctx, urls)
}

// Reset は、両方の版の保存された内容を空にする。データベースは、表の形の履歴を適用した直後に行の無かった表を空にし、
// Redis はすべてのキーを消し、fakeaws は覚えたオブジェクトとメールを消す。
func (c *CompareEnv) Reset(ctx context.Context) error {
	for _, version := range []string{VersionJava, VersionGo} {
		if err := c.Stores[version].reset(ctx); err != nil {
			return err
		}
	}
	return c.fakes.clearRecords(ctx)
}

// Close は、両方の版の Redis のクライアントを閉じる。コンテナは Env が片付ける。
func (c *CompareEnv) Close() error {
	if c == nil {
		return nil
	}
	var errs []error
	for _, st := range c.Stores {
		errs = append(errs, st.Close())
	}
	return errors.Join(errs...)
}

// Run は、保存された内容を空にして筋書き s の初めのデータを両方のデータベースに読み込み、筋書きの段を1つずつ、
// Java 版、Go 版の順に送って比べる。段ごとに、応答と、データベースと Redis と S3 のオブジェクトと送ったメールを比べる。
// 保存された内容の違いは、前の段と同じ違いなら重ねて報告しない。
// 環境を整えられないときと、段を送れないときは、誤りを返す。違いは、返す報告に書く。
func (c *CompareEnv) Run(ctx context.Context, s Scenario) (Report, error) {
	if err := c.Reset(ctx); err != nil {
		return Report{}, err
	}
	for _, version := range []string{VersionJava, VersionGo} {
		if err := LoadFixtures(ctx, c.Stores[version].DBConn, s.Fixtures); err != nil {
			return Report{}, err
		}
	}
	cmp := NewComparer(s.Name)
	cmp.PDF = c.PDF
	cmp.Behaviors = c.Behaviors
	sessions := map[string]*Session{VersionJava: NewSession(), VersionGo: NewSession()}
	seen := map[string]bool{}
	for i, step := range s.Steps {
		resp := map[string]Response{}
		for _, version := range []string{VersionJava, VersionGo} {
			r, err := sessions[version].Send(ctx, c.client, c.URLs[version], step)
			if err != nil {
				return cmp.Report(), fmt.Errorf("harness: 筋書き %s の段 %d「%s」を版 %s で送れません: %w", s.Name, i+1, step.Name, version, err)
			}
			resp[version] = r
		}
		ref := StepRef{Index: i + 1, Name: step.Name, Operation: c.Operations.Lookup(step.Request.Method, step.Request.Path)}
		ref = cmp.CompareResponse(ref, resp[VersionJava], resp[VersionGo])
		from := len(cmp.diffs)
		if err := c.compareState(ctx, cmp, ref); err != nil {
			return cmp.Report(), fmt.Errorf("harness: 筋書き %s の段 %d「%s」のあとの保存された内容を読めません: %w", s.Name, i+1, step.Name, err)
		}
		cmp.dropRepeated(from, seen)
	}
	return cmp.Report(), nil
}

// compareState は、両方の版のデータベースと Redis と、fakeaws が覚えた S3 のオブジェクトと送ったメールを読んで比べる。
func (c *CompareEnv) compareState(ctx context.Context, cmp *Comparer, step StepRef) error {
	dbs := map[string]DBSnapshot{}
	redises := map[string][]RedisEntry{}
	objects := map[string][]fakeaws.Object{}
	emails := map[string][]fakeaws.Email{}
	for _, version := range []string{VersionJava, VersionGo} {
		st := c.Stores[version]
		var err error
		if dbs[version], err = DumpDatabase(ctx, st.DBConn); err != nil {
			return err
		}
		if redises[version], err = DumpRedis(ctx, st.Redis); err != nil {
			return err
		}
		var objs []fakeaws.Object
		if err := c.fakes.records(ctx, version, "objects", &objs); err != nil {
			return err
		}
		objects[version] = objs
		var mails []fakeaws.Email
		if err := c.fakes.records(ctx, version, "emails", &mails); err != nil {
			return err
		}
		emails[version] = mails
	}
	cmp.CompareDB(step, dbs[VersionJava], dbs[VersionGo])
	cmp.CompareRedis(step, redises[VersionJava], redises[VersionGo])
	cmp.CompareS3(step, objects[VersionJava], objects[VersionGo])
	cmp.CompareMail(step, emails[VersionJava], emails[VersionGo])
	return nil
}

// dropRepeated は、from より後ろに足した違いのうち、seen にある違いと、比べたものと場所と両方の値が同じ違いを消し、
// 残した違いを seen に覚える。保存された内容は段をまたいで残るので、ある段で生まれた違いは、後の段でも同じ違いとして
// 見つかる。後の段の操作の違いとして重ねて報告すると、変えた動きの一覧の match が、違いを生んだ段の操作で当たらなくなる。
// 違いに repeatKey があれば、両方の値の代わりに repeatKey で見分ける。
func (c *Comparer) dropRepeated(from int, seen map[string]bool) {
	kept := c.diffs[:from]
	for _, d := range c.diffs[from:] {
		values := d.repeatKey
		if values == "" {
			values = d.Java + "\x00" + d.Go
		}
		key := d.Target + "\x00" + d.Path + "\x00" + values
		if seen[key] {
			continue
		}
		seen[key] = true
		kept = append(kept, d)
	}
	c.diffs = kept
}
