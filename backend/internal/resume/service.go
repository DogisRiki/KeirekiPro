// Package resume は、マスタと経歴書の26の操作の処理を、Java 版の usecase/resume のユースケースと
// usecase/query の3つのマスタの問い合わせと同じ順で行う。
// このパッケージは HTTP の要求と応答を扱わない。HTTP の受け口は internal/httpapi が受け持つ。
package resume

import (
	"context"
	"errors"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// Deps は、Service が使う部品の束である。
type Deps struct {
	// Pool は、データベースの接続の束である。sqlcgen の Queries とトランザクションに使う。
	Pool *pgxpool.Pool
	// Now は、今の時刻を返す関数である。nil のとき、New は time.Now を使う。
	// 本番では main.go が time.Now を渡し、テストは決まった時刻を返す関数を渡す。
	Now func() time.Time
	// PDF は、PDF の HTML から PDF を作る部品である。本番では main.go が internal/platform/pdf の *Engine を渡す。
	// nil のとき、PDF の出力は組み立ての誤りを返す。Markdown の出力は PDF の部品を使わない。
	PDF PDFRenderer
}

// Service は、マスタと経歴書の26の操作の処理の入口である。要求をまたぐ状態をメモリに持たず、
// すべてデータベースに置く。
type Service struct {
	deps Deps
}

// New は、部品の束から Service を作る。時刻の関数を渡さなければ、time.Now を使う。
func New(d Deps) *Service {
	if d.Now == nil {
		d.Now = time.Now
	}
	return &Service{deps: d}
}

// ListCertificationNames は、資格のマスタの名前を返す。
func (s *Service) ListCertificationNames(ctx context.Context) ([]string, error) {
	return poolStore(s.deps.Pool).listCertificationNames(ctx)
}

// ListSnsPlatformNames は、SNS のマスタの名前を返す。
func (s *Service) ListSnsPlatformNames(ctx context.Context) ([]string, error) {
	return poolStore(s.deps.Pool).listSnsPlatformNames(ctx)
}

// ListTechStacks は、技術スタックのマスタの名前を、答えの大分類と小分類に振り分けて返す。
func (s *Service) ListTechStacks(ctx context.Context) (TechStackMaster, error) {
	return poolStore(s.deps.Pool).listTechStacks(ctx)
}

// ListResumes は、利用者の経歴書を作成の日時の順に返す。6つの欄の項目は読まない。
func (s *Service) ListResumes(ctx context.Context, userID uuid.UUID) ([]Resume, error) {
	return poolStore(s.deps.Pool).listResumes(ctx, userID)
}

// GetResume は、利用者の経歴書1件を、6つの欄の項目と一緒に返す。項目は Java 版と同じ順に並べる。
// 経歴書の ID が読めないとき、経歴書が無いとき、ほかの利用者の経歴書のときは、無い経歴書の誤りを返す。
func (s *Service) GetResume(ctx context.Context, userID uuid.UUID, resumeID string) (Resume, error) {
	id, ok := parseID(resumeID)
	if !ok {
		return Resume{}, errResumeNotFound()
	}
	r, found, err := poolStore(s.deps.Pool).findResume(ctx, userID, id)
	if err != nil {
		return Resume{}, err
	}
	if !found {
		return Resume{}, errResumeNotFound()
	}
	return r, nil
}

// DeleteResume は、利用者の経歴書1件を、6つの欄の項目と一緒に消す。
// 経歴書の ID が読めないとき、経歴書が無いとき、ほかの利用者の経歴書のときは、何も消さずに無い経歴書の誤りを返す。
// 経歴書の行に鍵をかけてから消すので、同じ経歴書への項目の変更と同時に動いても、消したあとに項目の行が残らない。
func (s *Service) DeleteResume(ctx context.Context, userID uuid.UUID, resumeID string) error {
	id, ok := parseID(resumeID)
	if !ok {
		return errResumeNotFound()
	}
	return inTx(ctx, s.deps.Pool, func(st store) error {
		if _, found, err := st.lockResume(ctx, userID, id); err != nil {
			return err
		} else if !found {
			return errResumeNotFound()
		}
		return st.deleteResume(ctx, id)
	})
}

// CreateResume は、利用者の経歴書を1件作る。要求の本文の resumeId に経歴書の ID があれば、その経歴書の日付と姓と名と6つの欄の項目を写す。
// 確かめる順は Java 版と同じく、経歴書の数の上限、名前の重なり、コピー元の経歴書、名前の値の決まりである。
// 答えの作成と更新の日時は、データベースに書くときに丸める前の今の時刻である。
func (s *Service) CreateResume(ctx context.Context, userID uuid.UUID, body []byte) (Resume, error) {
	req, err := decodeBody[createResumeRequest](body)
	if err != nil {
		return Resume{}, errUnreadableInput()
	}
	if e := validateCreateResume(req); e != nil {
		return Resume{}, e
	}
	name := *req.ResumeName
	now := s.deps.Now().In(japanZone)
	var created Resume
	err = inTx(ctx, s.deps.Pool, func(st store) error {
		count, err := st.countResumes(ctx, userID)
		if err != nil {
			return err
		}
		if e := resumeLimit.check(count); e != nil {
			return e
		}
		if exists, err := st.resumeNameExists(ctx, userID, name); err != nil {
			return err
		} else if exists {
			return errResumeNameDuplicated()
		}
		r := Resume{
			ID: uuid.New(), UserID: userID, Name: name,
			Date:      Date{Year: now.Year(), Month: now.Month(), Day: now.Day()},
			CreatedAt: now, UpdatedAt: now,
			Careers: []Career{}, Projects: []Project{}, Certifications: []Certification{},
			Portfolios: []Portfolio{}, SnsPlatforms: []SnsPlatform{}, SelfPromotions: []SelfPromotion{},
		}
		if req.ResumeID.Present {
			src, found, err := st.findResume(ctx, userID, req.ResumeID.Value)
			if err != nil {
				return err
			}
			if !found {
				return errResumeNotFound()
			}
			copyEntries(&r, src)
		}
		f := auth.FieldErrors{}
		checkResumeName(f, name)
		if e := f.Result(); e != nil {
			return e
		}
		if err := st.insertResume(ctx, r); err != nil {
			if isUserMissing(err) {
				return errResumeNotFound()
			}
			return err
		}
		created = r
		return nil
	})
	if err != nil {
		return Resume{}, err
	}
	return created, nil
}

// copyEntries は、コピー元の経歴書の日付と姓と名と6つの欄の項目を r に写す。項目には新しい ID を付け、新しい ID で項目を並べ直す。
func copyEntries(r *Resume, src Resume) {
	r.Date, r.LastName, r.FirstName = src.Date, src.LastName, src.FirstName
	r.Careers = withNewIDs(src.Careers, func(e *Career) *uuid.UUID { return &e.ID })
	r.Projects = withNewIDs(src.Projects, func(e *Project) *uuid.UUID { return &e.ID })
	r.Certifications = withNewIDs(src.Certifications, func(e *Certification) *uuid.UUID { return &e.ID })
	r.Portfolios = withNewIDs(src.Portfolios, func(e *Portfolio) *uuid.UUID { return &e.ID })
	r.SnsPlatforms = withNewIDs(src.SnsPlatforms, func(e *SnsPlatform) *uuid.UUID { return &e.ID })
	r.SelfPromotions = withNewIDs(src.SelfPromotions, func(e *SelfPromotion) *uuid.UUID { return &e.ID })
	sortEntries(r)
}

// withNewIDs は、項目の並びを写し、写した項目のそれぞれに新しい ID を付ける。並びが空でも nil にしない。
func withNewIDs[E any](entries []E, id func(*E) *uuid.UUID) []E {
	out := append(make([]E, 0, len(entries)), entries...)
	for i := range out {
		*id(&out[i]) = uuid.New()
	}
	return out
}

// isUserMissing は、err が、経歴書の行の利用者が居ないための外部キーの違反かを返す。利用者が退会したあとに届いた作成の要求で起きる。
func isUserMissing(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23503" && pgErr.TableName == "resumes"
}

// UpdateResumeBasic は、利用者の経歴書の名前と日付と姓と名を書き換え、6つの欄の項目を持つ経歴書を返す。
// 名前を変えるときだけ、ほかの経歴書との名前の重なりを確かめる。名前と姓と名の値の決まりの誤りは、まとめて返す。
// 答えの更新の日時は丸める前の今の時刻であり、作成の日時はデータベースの値である。
func (s *Service) UpdateResumeBasic(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (Resume, error) {
	req, err := decodeBody[updateResumeBasicRequest](body)
	if err != nil {
		return Resume{}, errUnreadableInput()
	}
	if e := validateUpdateResumeBasic(req); e != nil {
		return Resume{}, e
	}
	id, ok := parseID(resumeID)
	if !ok {
		return Resume{}, errResumeNotFound()
	}
	name := *req.ResumeName
	var updated Resume
	err = inTx(ctx, s.deps.Pool, func(st store) error {
		r, found, err := st.lockResume(ctx, userID, id)
		if err != nil {
			return err
		}
		if !found {
			return errResumeNotFound()
		}
		if name != r.Name {
			if exists, err := st.resumeNameExists(ctx, userID, name); err != nil {
				return err
			} else if exists {
				return errResumeNameDuplicated()
			}
		}
		f := auth.FieldErrors{}
		checkResumeName(f, name)
		checkFullName(f, req.LastName, req.FirstName)
		if e := f.Result(); e != nil {
			return e
		}
		r.Name, r.Date, r.LastName, r.FirstName = name, req.Date.Value, req.LastName, req.FirstName
		r.UpdatedAt = s.deps.Now().In(japanZone)
		if err := st.updateResumeBasic(ctx, r); err != nil {
			return err
		}
		updated = r
		return nil
	})
	if err != nil {
		return Resume{}, err
	}
	return updated, nil
}

// editResume は、6つの欄の項目の追加と更新が使う共通の流れである。1つのトランザクションの中で経歴書の行を利用者の ID と組で
// 読んで固定し、欄ごとの関数 fn を呼び、fn が誤りを返さなければ経歴書の更新の日時を新しくする。確定したあとで経歴書を読み直して返す。
// 答えの更新の日時は丸める前の今の時刻であり、作成の日時はデータベースの値である。
// 経歴書の ID が読めないとき、経歴書が無いとき、ほかの利用者の経歴書のときは、無い経歴書の誤りを返す。
func (s *Service) editResume(ctx context.Context, userID uuid.UUID, resumeID string, fn func(st store, r Resume) error) (Resume, error) {
	id, now, err := s.editInTx(ctx, userID, resumeID, fn)
	if err != nil {
		return Resume{}, err
	}
	r, found, err := poolStore(s.deps.Pool).findResume(ctx, userID, id)
	if err != nil {
		return Resume{}, err
	}
	if !found {
		return Resume{}, errResumeNotFound()
	}
	r.UpdatedAt = now
	return r, nil
}

// editInTx は、editResume の、経歴書を読み直す前までの流れである。項目の削除は、経歴書を返さないので、これを直に使う。
// 経歴書の ID と、書いた更新の日時の丸める前の値を返す。
func (s *Service) editInTx(ctx context.Context, userID uuid.UUID, resumeID string, fn func(st store, r Resume) error) (uuid.UUID, time.Time, error) {
	id, ok := parseID(resumeID)
	if !ok {
		return uuid.UUID{}, time.Time{}, errResumeNotFound()
	}
	var now time.Time
	err := inTx(ctx, s.deps.Pool, func(st store) error {
		r, found, err := st.lockResume(ctx, userID, id)
		if err != nil {
			return err
		}
		if !found {
			return errResumeNotFound()
		}
		if err := fn(st, r); err != nil {
			return err
		}
		now = s.deps.Now().In(japanZone)
		return st.touchResume(ctx, id, now)
	})
	return id, now, err
}

// decodeEntry は、項目の追加と更新の要求の本文を読み、入力欄を検査する。本文が読めなければ、項目ごとの文言を持たない 400 の誤りを返す。
func decodeEntry[T any](body []byte, validate func(T) *auth.Error) (T, *auth.Error) {
	req, err := decodeBody[T](body)
	if err != nil {
		return req, errUnreadableInput()
	}
	return req, validate(req)
}

// entryID は、経路の項目の ID を読み、経歴書の項目の並び entries にあるかを確かめる。読めないときと無いときは、
// 欄ごとの文言 notFound の 404 の誤りを返す。
func entryID[E any](s string, entries []E, id func(E) uuid.UUID, notFound string) (uuid.UUID, *auth.Error) {
	v, ok := parseID(s)
	if !ok || !slices.ContainsFunc(entries, func(e E) bool { return id(e) == v }) {
		return uuid.UUID{}, errNotFound(notFound)
	}
	return v, nil
}

// deleteEntry は、項目の削除の共通の流れである。項目の ID が読めないときと、経歴書に項目が無いときは、欄ごとの文言 notFound の
// 404 の誤りを返す。del は、経歴書に項目が無ければ false を返す。
func (s *Service) deleteEntry(ctx context.Context, userID uuid.UUID, resumeID, itemID, notFound string,
	del func(st store, resumeID, id uuid.UUID) (bool, error),
) error {
	_, _, err := s.editInTx(ctx, userID, resumeID, func(st store, r Resume) error {
		id, ok := parseID(itemID)
		if !ok {
			return errNotFound(notFound)
		}
		if found, err := del(st, r.ID, id); err != nil {
			return err
		} else if !found {
			return errNotFound(notFound)
		}
		return nil
	})
	return err
}

// requestPeriod は、要求の開始と終了の年月と継続中の値から期間を作り、期間の決まりを検査する。
func requestPeriod(start, end jsonYearMonth, active bool) (Period, *auth.Error) {
	p := Period{StartDate: start.Value, Active: active}
	if end.Present {
		p.EndDate = &end.Value
	}
	var startDate *YearMonth
	if start.Present {
		startDate = &p.StartDate
	}
	f := auth.FieldErrors{}
	checkPeriod(f, startDate, p.EndDate, active)
	if e := f.Result(); e != nil {
		return Period{}, e
	}
	return p, nil
}

func careerIDOf(c Career) uuid.UUID   { return c.ID }
func projectIDOf(p Project) uuid.UUID { return p.ID }

// career は、検査を通った職歴の要求から、ID が id の職歴を作る。期間の決まりに外れれば、400 の誤りを返す。
func (req careerRequest) career(id uuid.UUID) (Career, *auth.Error) {
	p, e := requestPeriod(req.StartDate, req.EndDate, *req.Active)
	if e != nil {
		return Career{}, e
	}
	return Career{ID: id, CompanyName: *req.CompanyName, Period: p}, nil
}

// CreateCareer は、利用者の経歴書に職歴を1つ足し、6つの欄の項目を持つ経歴書を返す。
// 確かめる順は、本文、入力欄、経歴書、職歴の数の上限、期間の決まり、ほかの職歴との期間の重なりである。
func (s *Service) CreateCareer(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validateCareer)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		if e := careerLimit.check(len(r.Careers)); e != nil {
			return e
		}
		c, e := req.career(uuid.New())
		if e != nil {
			return e
		}
		if e := checkCareerOverlap(c, r.Careers); e != nil {
			return e
		}
		return st.insertCareer(ctx, r.ID, c)
	})
}

// UpdateCareer は、利用者の経歴書の職歴を書き換え、6つの欄の項目を持つ経歴書を返す。
// 確かめる順は、本文、入力欄、経歴書、職歴、期間の決まり、ほかの職歴との期間の重なりである。直す職歴の今の期間とは比べない。
func (s *Service) UpdateCareer(ctx context.Context, userID uuid.UUID, resumeID, careerID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validateCareer)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		id, e := entryID(careerID, r.Careers, careerIDOf, MessageCareerNotFound)
		if e != nil {
			return e
		}
		c, e := req.career(id)
		if e != nil {
			return e
		}
		if e := checkCareerOverlap(c, r.Careers); e != nil {
			return e
		}
		// 経歴書の行を固定しているので、entryID で確かめた職歴は、書き換えるまで消えない。
		_, err := st.updateCareer(ctx, r.ID, c)
		return err
	})
}

// DeleteCareer は、利用者の経歴書の職歴を消す。
func (s *Service) DeleteCareer(ctx context.Context, userID uuid.UUID, resumeID, careerID string) error {
	return s.deleteEntry(ctx, userID, resumeID, careerID, MessageCareerNotFound, func(st store, resumeID, id uuid.UUID) (bool, error) {
		return st.deleteCareer(ctx, resumeID, id)
	})
}

// project は、検査を通ったプロジェクトの要求から、ID が id のプロジェクトを作る。期間の決まりに外れれば、400 の誤りを返す。
// 技術スタックの並びは、要求の値のまま写す。
func (req projectRequest) project(id uuid.UUID) (Project, *auth.Error) {
	p, e := requestPeriod(req.StartDate, req.EndDate, *req.Active)
	if e != nil {
		return Project{}, e
	}
	return Project{
		ID: id, CompanyName: *req.CompanyName, Period: p,
		Name: *req.Name, Overview: *req.Overview, TeamComp: *req.TeamComp, Role: *req.Role, Achievement: *req.Achievement,
		Process: Process{
			Requirements: *req.Requirements, BasicDesign: *req.BasicDesign, DetailedDesign: *req.DetailedDesign,
			Implementation: *req.Implementation, IntegrationTest: *req.IntegrationTest, SystemTest: *req.SystemTest,
			Maintenance: *req.Maintenance,
		},
		TechStack: TechStack{
			Frontend: FrontendStacks[*string]{
				Languages: req.FrontendLanguages, Frameworks: req.FrontendFrameworks, Libraries: req.FrontendLibraries,
				BuildTools: req.FrontendBuildTools, PackageManagers: req.FrontendPackageManagers, Linters: req.FrontendLinters,
				Formatters: req.FrontendFormatters, TestingTools: req.FrontendTestingTools,
			},
			Backend: BackendStacks[*string]{
				Languages: req.BackendLanguages, Frameworks: req.BackendFrameworks, Libraries: req.BackendLibraries,
				BuildTools: req.BackendBuildTools, PackageManagers: req.BackendPackageManagers, Linters: req.BackendLinters,
				Formatters: req.BackendFormatters, TestingTools: req.BackendTestingTools, OrmTools: req.OrmTools, Auth: req.Auth,
			},
			Infrastructure: InfrastructureStacks[*string]{
				Clouds: req.Clouds, OperatingSystems: req.OperatingSystems, Containers: req.Containers, Databases: req.Databases,
				WebServers: req.WebServers, CiCdTools: req.CiCdTools, IacTools: req.IacTools,
				MonitoringTools: req.MonitoringTools, LoggingTools: req.LoggingTools,
			},
			Tools: ToolStacks[*string]{
				SourceControls: req.SourceControls, ProjectManagements: req.ProjectManagements,
				CommunicationTools: req.CommunicationTools, DocumentationTools: req.DocumentationTools,
				APIDevelopmentTools: req.APIDevelopmentTools, DesignTools: req.DesignTools,
				Editors: req.Editors, DevelopmentEnvironments: req.DevelopmentEnvironments,
			},
		},
	}, nil
}

// CreateProject は、利用者の経歴書にプロジェクトを1つ足し、6つの欄の項目を持つ経歴書を返す。
// プロジェクトの行と技術スタックの行は、editResume の1つのトランザクションの中で書く。
// 確かめる順は、本文、入力欄、経歴書、プロジェクトの数の上限、期間の決まりである。
func (s *Service) CreateProject(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validateProject)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		if e := projectLimit.check(len(r.Projects)); e != nil {
			return e
		}
		p, e := req.project(uuid.New())
		if e != nil {
			return e
		}
		return st.insertProject(ctx, r.ID, p)
	})
}

// UpdateProject は、利用者の経歴書のプロジェクトと技術スタックを書き換え、6つの欄の項目を持つ経歴書を返す。
// 確かめる順は、本文、入力欄、経歴書、プロジェクト、期間の決まりである。
func (s *Service) UpdateProject(ctx context.Context, userID uuid.UUID, resumeID, projectID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validateProject)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		id, e := entryID(projectID, r.Projects, projectIDOf, MessageProjectNotFound)
		if e != nil {
			return e
		}
		p, e := req.project(id)
		if e != nil {
			return e
		}
		// 経歴書の行を固定しているので、entryID で確かめたプロジェクトは、書き換えるまで消えない。
		_, err := st.updateProject(ctx, r.ID, p)
		return err
	})
}

// DeleteProject は、利用者の経歴書のプロジェクトと技術スタックを消す。
func (s *Service) DeleteProject(ctx context.Context, userID uuid.UUID, resumeID, projectID string) error {
	return s.deleteEntry(ctx, userID, resumeID, projectID, MessageProjectNotFound, func(st store, resumeID, id uuid.UUID) (bool, error) {
		return st.deleteProject(ctx, resumeID, id)
	})
}

func certificationIDOf(c Certification) uuid.UUID { return c.ID }
func portfolioIDOf(p Portfolio) uuid.UUID         { return p.ID }
func snsPlatformIDOf(p SnsPlatform) uuid.UUID     { return p.ID }
func selfPromotionIDOf(p SelfPromotion) uuid.UUID { return p.ID }

// certification は、検査を通った資格の要求から、ID が id の資格を作る。
func (req certificationRequest) certification(id uuid.UUID) Certification {
	return Certification{ID: id, Name: *req.Name, Date: req.Date.Value}
}

// portfolio は、検査を通ったポートフォリオの要求から、ID が id のポートフォリオを作る。技術スタックは任意の欄で、値が無ければ nil のまま写す。
func (req portfolioRequest) portfolio(id uuid.UUID) Portfolio {
	return Portfolio{ID: id, Name: *req.Name, Overview: *req.Overview, TechStack: req.TechStack, Link: *req.Link}
}

// snsPlatform は、検査を通った SNS の要求から、ID が id の SNS を作る。
func (req snsPlatformRequest) snsPlatform(id uuid.UUID) SnsPlatform {
	return SnsPlatform{ID: id, Name: *req.Name, Link: *req.Link}
}

// selfPromotion は、検査を通った自己PR の要求から、ID が id の自己PR を作る。
func (req selfPromotionRequest) selfPromotion(id uuid.UUID) SelfPromotion {
	return SelfPromotion{ID: id, Title: *req.Title, Content: *req.Content}
}

// CreateCertification は、利用者の経歴書に資格を1つ足し、6つの欄の項目を持つ経歴書を返す。
// 確かめる順は、本文、入力欄、経歴書、資格の数の上限である。
func (s *Service) CreateCertification(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validateCertification)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		if e := certificationLimit.check(len(r.Certifications)); e != nil {
			return e
		}
		return st.insertCertification(ctx, r.ID, req.certification(uuid.New()))
	})
}

// UpdateCertification は、利用者の経歴書の資格を書き換え、6つの欄の項目を持つ経歴書を返す。
// 確かめる順は、本文、入力欄、経歴書、資格である。
func (s *Service) UpdateCertification(ctx context.Context, userID uuid.UUID, resumeID, certificationID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validateCertification)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		id, e := entryID(certificationID, r.Certifications, certificationIDOf, MessageCertificationNotFound)
		if e != nil {
			return e
		}
		// 経歴書の行を固定しているので、entryID で確かめた資格は、書き換えるまで消えない。
		_, err := st.updateCertification(ctx, r.ID, req.certification(id))
		return err
	})
}

// DeleteCertification は、利用者の経歴書の資格を消す。
func (s *Service) DeleteCertification(ctx context.Context, userID uuid.UUID, resumeID, certificationID string) error {
	return s.deleteEntry(ctx, userID, resumeID, certificationID, MessageCertificationNotFound, func(st store, resumeID, id uuid.UUID) (bool, error) {
		return st.deleteCertification(ctx, resumeID, id)
	})
}

// CreatePortfolio は、利用者の経歴書にポートフォリオを1つ足し、6つの欄の項目を持つ経歴書を返す。
// 確かめる順は、本文、入力欄、経歴書、ポートフォリオの数の上限である。
func (s *Service) CreatePortfolio(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validatePortfolio)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		if e := portfolioLimit.check(len(r.Portfolios)); e != nil {
			return e
		}
		return st.insertPortfolio(ctx, r.ID, req.portfolio(uuid.New()))
	})
}

// UpdatePortfolio は、利用者の経歴書のポートフォリオを書き換え、6つの欄の項目を持つ経歴書を返す。
// 確かめる順は、本文、入力欄、経歴書、ポートフォリオである。
func (s *Service) UpdatePortfolio(ctx context.Context, userID uuid.UUID, resumeID, portfolioID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validatePortfolio)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		id, e := entryID(portfolioID, r.Portfolios, portfolioIDOf, MessagePortfolioNotFound)
		if e != nil {
			return e
		}
		// 経歴書の行を固定しているので、entryID で確かめたポートフォリオは、書き換えるまで消えない。
		_, err := st.updatePortfolio(ctx, r.ID, req.portfolio(id))
		return err
	})
}

// DeletePortfolio は、利用者の経歴書のポートフォリオを消す。
func (s *Service) DeletePortfolio(ctx context.Context, userID uuid.UUID, resumeID, portfolioID string) error {
	return s.deleteEntry(ctx, userID, resumeID, portfolioID, MessagePortfolioNotFound, func(st store, resumeID, id uuid.UUID) (bool, error) {
		return st.deletePortfolio(ctx, resumeID, id)
	})
}

// CreateSnsPlatform は、利用者の経歴書に SNS を1つ足し、6つの欄の項目を持つ経歴書を返す。
// 確かめる順は、本文、入力欄、経歴書、SNS の数の上限である。
func (s *Service) CreateSnsPlatform(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validateSnsPlatform)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		if e := snsPlatformLimit.check(len(r.SnsPlatforms)); e != nil {
			return e
		}
		return st.insertSnsPlatform(ctx, r.ID, req.snsPlatform(uuid.New()))
	})
}

// UpdateSnsPlatform は、利用者の経歴書の SNS を書き換え、6つの欄の項目を持つ経歴書を返す。
// 確かめる順は、本文、入力欄、経歴書、SNS である。
func (s *Service) UpdateSnsPlatform(ctx context.Context, userID uuid.UUID, resumeID, snsPlatformID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validateSnsPlatform)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		id, e := entryID(snsPlatformID, r.SnsPlatforms, snsPlatformIDOf, MessageSnsPlatformNotFound)
		if e != nil {
			return e
		}
		// 経歴書の行を固定しているので、entryID で確かめた SNS は、書き換えるまで消えない。
		_, err := st.updateSnsPlatform(ctx, r.ID, req.snsPlatform(id))
		return err
	})
}

// DeleteSnsPlatform は、利用者の経歴書の SNS を消す。
func (s *Service) DeleteSnsPlatform(ctx context.Context, userID uuid.UUID, resumeID, snsPlatformID string) error {
	return s.deleteEntry(ctx, userID, resumeID, snsPlatformID, MessageSnsPlatformNotFound, func(st store, resumeID, id uuid.UUID) (bool, error) {
		return st.deleteSnsPlatform(ctx, resumeID, id)
	})
}

// CreateSelfPromotion は、利用者の経歴書に自己PR を1つ足し、6つの欄の項目を持つ経歴書を返す。
// 確かめる順は、本文、入力欄、経歴書、自己PR の数の上限である。
func (s *Service) CreateSelfPromotion(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validateSelfPromotion)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		if e := selfPromotionLimit.check(len(r.SelfPromotions)); e != nil {
			return e
		}
		return st.insertSelfPromotion(ctx, r.ID, req.selfPromotion(uuid.New()))
	})
}

// UpdateSelfPromotion は、利用者の経歴書の自己PR を書き換え、6つの欄の項目を持つ経歴書を返す。
// 確かめる順は、本文、入力欄、経歴書、自己PR である。
func (s *Service) UpdateSelfPromotion(ctx context.Context, userID uuid.UUID, resumeID, selfPromotionID string, body []byte) (Resume, error) {
	req, e := decodeEntry(body, validateSelfPromotion)
	if e != nil {
		return Resume{}, e
	}
	return s.editResume(ctx, userID, resumeID, func(st store, r Resume) error {
		id, e := entryID(selfPromotionID, r.SelfPromotions, selfPromotionIDOf, MessageSelfPromotionNotFound)
		if e != nil {
			return e
		}
		// 経歴書の行を固定しているので、entryID で確かめた自己PR は、書き換えるまで消えない。
		_, err := st.updateSelfPromotion(ctx, r.ID, req.selfPromotion(id))
		return err
	})
}

// DeleteSelfPromotion は、利用者の経歴書の自己PR を消す。
func (s *Service) DeleteSelfPromotion(ctx context.Context, userID uuid.UUID, resumeID, selfPromotionID string) error {
	return s.deleteEntry(ctx, userID, resumeID, selfPromotionID, MessageSelfPromotionNotFound, func(st store, resumeID, id uuid.UUID) (bool, error) {
		return st.deleteSelfPromotion(ctx, resumeID, id)
	})
}
