package resume

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// japanZone は日本の時間帯である。表の日時の列は時差を持たないので、日本の時刻の見た目で書いて読む。
var japanZone = time.FixedZone("Asia/Tokyo", 9*60*60)

// store は、経歴書と6つの欄の項目を、小タスク1.3 で生成した問い合わせで読み書きする。
// 書く操作は、inTx が渡す store で、1つのトランザクションの中で呼ぶ。
type store struct {
	q *sqlcgen.Queries
}

// poolStore は、トランザクションの外で読む store を作る。
func poolStore(pool *pgxpool.Pool) store {
	return store{q: sqlcgen.New(pool)}
}

// inTx は、fn を1つのトランザクションの中で呼ぶ。fn が誤りを返せば、書いたものをすべて取り消す。
func inTx(ctx context.Context, pool *pgxpool.Pool, fn func(s store) error) error {
	return pgx.BeginFunc(ctx, pool, func(tx pgx.Tx) error {
		return fn(store{q: sqlcgen.New(tx)})
	})
}

// 経歴書

// listResumes は、利用者の経歴書を作成の日時の順に読む。6つの欄の項目は読まない。
func (s store) listResumes(ctx context.Context, userID uuid.UUID) ([]Resume, error) {
	rows, err := s.q.ListResumesByUserID(ctx, toUUID(userID))
	if err != nil {
		return nil, fmt.Errorf("経歴書の一覧を読めません: %w", err)
	}
	resumes := make([]Resume, 0, len(rows))
	for _, row := range rows {
		resumes = append(resumes, fromResumeRow(row))
	}
	return resumes, nil
}

// findResume は、利用者の経歴書と6つの欄の項目を読む。経歴書が無いか、ほかの利用者の経歴書なら、false を返す。
func (s store) findResume(ctx context.Context, userID, resumeID uuid.UUID) (Resume, bool, error) {
	row, err := s.q.GetResume(ctx, sqlcgen.GetResumeParams{ID: toUUID(resumeID), UserID: toUUID(userID)})
	return s.withEntries(ctx, row, err)
}

// lockResume は、findResume と同じものを、経歴書の行に FOR UPDATE の鍵をかけて読む。トランザクションの中で呼ぶ。
func (s store) lockResume(ctx context.Context, userID, resumeID uuid.UUID) (Resume, bool, error) {
	row, err := s.q.GetResumeForUpdate(ctx, sqlcgen.GetResumeForUpdateParams{ID: toUUID(resumeID), UserID: toUUID(userID)})
	return s.withEntries(ctx, row, err)
}

// withEntries は、読んだ経歴書の行に6つの欄の項目を足す。
func (s store) withEntries(ctx context.Context, row sqlcgen.Resume, err error) (Resume, bool, error) {
	if errors.Is(err, pgx.ErrNoRows) {
		return Resume{}, false, nil
	}
	if err != nil {
		return Resume{}, false, fmt.Errorf("経歴書を読めません: %w", err)
	}
	r := fromResumeRow(row)
	if err := s.loadEntries(ctx, &r); err != nil {
		return Resume{}, false, err
	}
	return r, true, nil
}

// countResumes は、利用者の経歴書の数を数える。
func (s store) countResumes(ctx context.Context, userID uuid.UUID) (int, error) {
	n, err := s.q.CountResumesByUserID(ctx, toUUID(userID))
	if err != nil {
		return 0, fmt.Errorf("経歴書の数を数えられません: %w", err)
	}
	return int(n), nil
}

// resumeNameExists は、利用者が同じ名前の経歴書を持つかを確かめる。
func (s store) resumeNameExists(ctx context.Context, userID uuid.UUID, name string) (bool, error) {
	exists, err := s.q.ExistsResumeName(ctx, sqlcgen.ExistsResumeNameParams{UserID: toUUID(userID), Name: name})
	if err != nil {
		return false, fmt.Errorf("経歴書の名前の重なりを確かめられません: %w", err)
	}
	return exists, nil
}

// insertResume は、経歴書の行と6つの欄のすべての項目を書く。経歴書を写して作るときも、この関数で書く。
func (s store) insertResume(ctx context.Context, r Resume) error {
	if err := s.q.InsertResume(ctx, sqlcgen.InsertResumeParams{
		ID:        toUUID(r.ID),
		UserID:    toUUID(r.UserID),
		Name:      r.Name,
		Date:      toDate(r.Date),
		LastName:  toText(r.LastName),
		FirstName: toText(r.FirstName),
		CreatedAt: toTimestamp(r.CreatedAt),
		UpdatedAt: toTimestamp(r.UpdatedAt),
	}); err != nil {
		return fmt.Errorf("経歴書を書けません: %w", err)
	}
	for _, c := range r.Careers {
		if err := s.insertCareer(ctx, r.ID, c); err != nil {
			return err
		}
	}
	for _, p := range r.Projects {
		if err := s.insertProject(ctx, r.ID, p); err != nil {
			return err
		}
	}
	for _, c := range r.Certifications {
		if err := s.insertCertification(ctx, r.ID, c); err != nil {
			return err
		}
	}
	for _, p := range r.Portfolios {
		if err := s.insertPortfolio(ctx, r.ID, p); err != nil {
			return err
		}
	}
	for _, p := range r.SnsPlatforms {
		if err := s.insertSnsPlatform(ctx, r.ID, p); err != nil {
			return err
		}
	}
	for _, p := range r.SelfPromotions {
		if err := s.insertSelfPromotion(ctx, r.ID, p); err != nil {
			return err
		}
	}
	return nil
}

// updateResumeBasic は、経歴書の名前と日付と姓と名と更新の日時を書く。
func (s store) updateResumeBasic(ctx context.Context, r Resume) error {
	if err := s.q.UpdateResumeBasic(ctx, sqlcgen.UpdateResumeBasicParams{
		ID:        toUUID(r.ID),
		Name:      r.Name,
		Date:      toDate(r.Date),
		LastName:  toText(r.LastName),
		FirstName: toText(r.FirstName),
		UpdatedAt: toTimestamp(r.UpdatedAt),
	}); err != nil {
		return fmt.Errorf("経歴書の基本の情報を書けません: %w", err)
	}
	return nil
}

// touchResume は、経歴書の更新の日時だけを書く。
func (s store) touchResume(ctx context.Context, resumeID uuid.UUID, updatedAt time.Time) error {
	if err := s.q.UpdateResumeUpdatedAt(ctx, sqlcgen.UpdateResumeUpdatedAtParams{
		ID: toUUID(resumeID), UpdatedAt: toTimestamp(updatedAt),
	}); err != nil {
		return fmt.Errorf("経歴書の更新の日時を書けません: %w", err)
	}
	return nil
}

// deleteResume は、子の表の行を消してから、経歴書の行を消す。
func (s store) deleteResume(ctx context.Context, resumeID uuid.UUID) error {
	id := toUUID(resumeID)
	for _, del := range []func(context.Context, pgtype.UUID) error{
		s.q.DeleteResumeProjectTechStacks,
		s.q.DeleteResumeProjects,
		s.q.DeleteResumeCareers,
		s.q.DeleteResumeCertifications,
		s.q.DeleteResumePortfolios,
		s.q.DeleteResumeSnsPlatforms,
		s.q.DeleteResumeSelfPromotions,
		s.q.DeleteResume,
	} {
		if err := del(ctx, id); err != nil {
			return fmt.Errorf("経歴書を消せません: %w", err)
		}
	}
	return nil
}

// loadEntries は、経歴書の6つの欄の項目を読み、Java 版と同じ順に並べる。項目が無い欄も、nil でない空の並びにする。
func (s store) loadEntries(ctx context.Context, r *Resume) error {
	id := toUUID(r.ID)
	careers, err := s.q.ListCareers(ctx, id)
	if err != nil {
		return fmt.Errorf("職歴を読めません: %w", err)
	}
	r.Careers = make([]Career, 0, len(careers))
	for _, c := range careers {
		r.Careers = append(r.Careers, Career{
			ID: fromUUID(c.ID), CompanyName: c.CompanyName, Period: fromPeriod(c.StartDate, c.EndDate, c.IsActive),
		})
	}

	projects, err := s.q.ListProjects(ctx, id)
	if err != nil {
		return fmt.Errorf("プロジェクトを読めません: %w", err)
	}
	r.Projects = make([]Project, 0, len(projects))
	for _, p := range projects {
		tech, err := decodeTechStack(p.TechStacks)
		if err != nil {
			return err
		}
		r.Projects = append(r.Projects, Project{
			ID:          fromUUID(p.ID),
			CompanyName: p.CompanyName,
			Period:      fromPeriod(p.StartDate, p.EndDate, p.IsActive),
			Name:        p.Name,
			Overview:    p.Overview,
			TeamComp:    p.TeamComp,
			Role:        p.Role,
			Achievement: p.Achievement,
			Process: Process{
				Requirements:    p.Requirements,
				BasicDesign:     p.BasicDesign,
				DetailedDesign:  p.DetailedDesign,
				Implementation:  p.Implementation,
				IntegrationTest: p.IntegrationTest,
				SystemTest:      p.SystemTest,
				Maintenance:     p.Maintenance,
			},
			TechStack: tech,
		})
	}

	certifications, err := s.q.ListCertifications(ctx, id)
	if err != nil {
		return fmt.Errorf("資格を読めません: %w", err)
	}
	r.Certifications = make([]Certification, 0, len(certifications))
	for _, c := range certifications {
		r.Certifications = append(r.Certifications, Certification{ID: fromUUID(c.ID), Name: c.Name, Date: fromYearMonth(c.Date)})
	}

	portfolios, err := s.q.ListPortfolios(ctx, id)
	if err != nil {
		return fmt.Errorf("ポートフォリオを読めません: %w", err)
	}
	r.Portfolios = make([]Portfolio, 0, len(portfolios))
	for _, p := range portfolios {
		r.Portfolios = append(r.Portfolios, Portfolio{
			ID: fromUUID(p.ID), Name: p.Name, Overview: p.Overview, TechStack: fromText(p.TechStack), Link: p.Link,
		})
	}

	snsPlatforms, err := s.q.ListSnsPlatforms(ctx, id)
	if err != nil {
		return fmt.Errorf("SNS を読めません: %w", err)
	}
	r.SnsPlatforms = make([]SnsPlatform, 0, len(snsPlatforms))
	for _, p := range snsPlatforms {
		r.SnsPlatforms = append(r.SnsPlatforms, SnsPlatform{ID: fromUUID(p.ID), Name: p.Name, Link: p.Link})
	}

	selfPromotions, err := s.q.ListSelfPromotions(ctx, id)
	if err != nil {
		return fmt.Errorf("自己PR を読めません: %w", err)
	}
	r.SelfPromotions = make([]SelfPromotion, 0, len(selfPromotions))
	for _, p := range selfPromotions {
		r.SelfPromotions = append(r.SelfPromotions, SelfPromotion{ID: fromUUID(p.ID), Title: p.Title, Content: p.Content})
	}

	sortEntries(r)
	return nil
}

// 職歴

func (s store) insertCareer(ctx context.Context, resumeID uuid.UUID, c Career) error {
	start, end := toPeriod(c.Period)
	if err := s.q.InsertCareer(ctx, sqlcgen.InsertCareerParams{
		ID: toUUID(c.ID), ResumeID: toUUID(resumeID), CompanyName: c.CompanyName,
		StartDate: start, EndDate: end, IsActive: c.Period.Active,
	}); err != nil {
		return fmt.Errorf("職歴を書けません: %w", err)
	}
	return nil
}

// updateCareer は、経歴書の職歴を書き換える。経歴書に職歴が無ければ false を返す。
func (s store) updateCareer(ctx context.Context, resumeID uuid.UUID, c Career) (bool, error) {
	start, end := toPeriod(c.Period)
	n, err := s.q.UpdateCareer(ctx, sqlcgen.UpdateCareerParams{
		ID: toUUID(c.ID), ResumeID: toUUID(resumeID), CompanyName: c.CompanyName,
		StartDate: start, EndDate: end, IsActive: c.Period.Active,
	})
	return found(n, err, "職歴を書き換えられません")
}

// deleteCareer は、経歴書の職歴を消す。経歴書に職歴が無ければ false を返す。
func (s store) deleteCareer(ctx context.Context, resumeID, id uuid.UUID) (bool, error) {
	n, err := s.q.DeleteCareer(ctx, sqlcgen.DeleteCareerParams{ID: toUUID(id), ResumeID: toUUID(resumeID)})
	return found(n, err, "職歴を消せません")
}

// プロジェクト

// insertProject は、プロジェクトの行と技術スタックの行を書く。2つの行は、呼ぶ側のトランザクションの中で書く。
func (s store) insertProject(ctx context.Context, resumeID uuid.UUID, p Project) error {
	start, end := toPeriod(p.Period)
	if err := s.q.InsertProject(ctx, sqlcgen.InsertProjectParams{
		ID: toUUID(p.ID), ResumeID: toUUID(resumeID), CompanyName: p.CompanyName,
		StartDate: start, EndDate: end, IsActive: p.Period.Active,
		Name: p.Name, Overview: p.Overview, TeamComp: p.TeamComp, Role: p.Role, Achievement: p.Achievement,
		Requirements: p.Process.Requirements, BasicDesign: p.Process.BasicDesign, DetailedDesign: p.Process.DetailedDesign,
		Implementation: p.Process.Implementation, IntegrationTest: p.Process.IntegrationTest,
		SystemTest: p.Process.SystemTest, Maintenance: p.Process.Maintenance,
	}); err != nil {
		return fmt.Errorf("プロジェクトを書けません: %w", err)
	}
	tech, err := encodeTechStack(p.TechStack)
	if err != nil {
		return err
	}
	if err := s.q.InsertProjectTechStacks(ctx, sqlcgen.InsertProjectTechStacksParams{ProjectID: toUUID(p.ID), TechStacks: tech}); err != nil {
		return fmt.Errorf("プロジェクトの技術スタックを書けません: %w", err)
	}
	return nil
}

// updateProject は、経歴書のプロジェクトの行と技術スタックの行を書き換える。経歴書にプロジェクトが無ければ false を返す。
func (s store) updateProject(ctx context.Context, resumeID uuid.UUID, p Project) (bool, error) {
	start, end := toPeriod(p.Period)
	n, err := s.q.UpdateProject(ctx, sqlcgen.UpdateProjectParams{
		ID: toUUID(p.ID), ResumeID: toUUID(resumeID), CompanyName: p.CompanyName,
		StartDate: start, EndDate: end, IsActive: p.Period.Active,
		Name: p.Name, Overview: p.Overview, TeamComp: p.TeamComp, Role: p.Role, Achievement: p.Achievement,
		Requirements: p.Process.Requirements, BasicDesign: p.Process.BasicDesign, DetailedDesign: p.Process.DetailedDesign,
		Implementation: p.Process.Implementation, IntegrationTest: p.Process.IntegrationTest,
		SystemTest: p.Process.SystemTest, Maintenance: p.Process.Maintenance,
	})
	if ok, err := found(n, err, "プロジェクトを書き換えられません"); !ok || err != nil {
		return ok, err
	}
	tech, err := encodeTechStack(p.TechStack)
	if err != nil {
		return false, err
	}
	if err := s.q.UpdateProjectTechStacks(ctx, sqlcgen.UpdateProjectTechStacksParams{
		ProjectID: toUUID(p.ID), ResumeID: toUUID(resumeID), TechStacks: tech,
	}); err != nil {
		return false, fmt.Errorf("プロジェクトの技術スタックを書き換えられません: %w", err)
	}
	return true, nil
}

// deleteProject は、経歴書のプロジェクトの技術スタックの行を消してから、プロジェクトの行を消す。経歴書にプロジェクトが無ければ false を返す。
func (s store) deleteProject(ctx context.Context, resumeID, id uuid.UUID) (bool, error) {
	if err := s.q.DeleteProjectTechStacks(ctx, sqlcgen.DeleteProjectTechStacksParams{
		ProjectID: toUUID(id), ResumeID: toUUID(resumeID),
	}); err != nil {
		return false, fmt.Errorf("プロジェクトの技術スタックを消せません: %w", err)
	}
	n, err := s.q.DeleteProject(ctx, sqlcgen.DeleteProjectParams{ID: toUUID(id), ResumeID: toUUID(resumeID)})
	return found(n, err, "プロジェクトを消せません")
}

// 資格

func (s store) insertCertification(ctx context.Context, resumeID uuid.UUID, c Certification) error {
	if err := s.q.InsertCertification(ctx, sqlcgen.InsertCertificationParams{
		ID: toUUID(c.ID), ResumeID: toUUID(resumeID), Name: c.Name, Date: toYearMonth(c.Date),
	}); err != nil {
		return fmt.Errorf("資格を書けません: %w", err)
	}
	return nil
}

// updateCertification は、経歴書の資格を書き換える。経歴書に資格が無ければ false を返す。
func (s store) updateCertification(ctx context.Context, resumeID uuid.UUID, c Certification) (bool, error) {
	n, err := s.q.UpdateCertification(ctx, sqlcgen.UpdateCertificationParams{
		ID: toUUID(c.ID), ResumeID: toUUID(resumeID), Name: c.Name, Date: toYearMonth(c.Date),
	})
	return found(n, err, "資格を書き換えられません")
}

// deleteCertification は、経歴書の資格を消す。経歴書に資格が無ければ false を返す。
func (s store) deleteCertification(ctx context.Context, resumeID, id uuid.UUID) (bool, error) {
	n, err := s.q.DeleteCertification(ctx, sqlcgen.DeleteCertificationParams{ID: toUUID(id), ResumeID: toUUID(resumeID)})
	return found(n, err, "資格を消せません")
}

// ポートフォリオ

func (s store) insertPortfolio(ctx context.Context, resumeID uuid.UUID, p Portfolio) error {
	if err := s.q.InsertPortfolio(ctx, sqlcgen.InsertPortfolioParams{
		ID: toUUID(p.ID), ResumeID: toUUID(resumeID), Name: p.Name, Overview: p.Overview, TechStack: toText(p.TechStack), Link: p.Link,
	}); err != nil {
		return fmt.Errorf("ポートフォリオを書けません: %w", err)
	}
	return nil
}

// updatePortfolio は、経歴書のポートフォリオを書き換える。経歴書にポートフォリオが無ければ false を返す。
func (s store) updatePortfolio(ctx context.Context, resumeID uuid.UUID, p Portfolio) (bool, error) {
	n, err := s.q.UpdatePortfolio(ctx, sqlcgen.UpdatePortfolioParams{
		ID: toUUID(p.ID), ResumeID: toUUID(resumeID), Name: p.Name, Overview: p.Overview, TechStack: toText(p.TechStack), Link: p.Link,
	})
	return found(n, err, "ポートフォリオを書き換えられません")
}

// deletePortfolio は、経歴書のポートフォリオを消す。経歴書にポートフォリオが無ければ false を返す。
func (s store) deletePortfolio(ctx context.Context, resumeID, id uuid.UUID) (bool, error) {
	n, err := s.q.DeletePortfolio(ctx, sqlcgen.DeletePortfolioParams{ID: toUUID(id), ResumeID: toUUID(resumeID)})
	return found(n, err, "ポートフォリオを消せません")
}

// SNS

func (s store) insertSnsPlatform(ctx context.Context, resumeID uuid.UUID, p SnsPlatform) error {
	if err := s.q.InsertSnsPlatform(ctx, sqlcgen.InsertSnsPlatformParams{
		ID: toUUID(p.ID), ResumeID: toUUID(resumeID), Name: p.Name, Link: p.Link,
	}); err != nil {
		return fmt.Errorf("SNS を書けません: %w", err)
	}
	return nil
}

// updateSnsPlatform は、経歴書の SNS を書き換える。経歴書に SNS が無ければ false を返す。
func (s store) updateSnsPlatform(ctx context.Context, resumeID uuid.UUID, p SnsPlatform) (bool, error) {
	n, err := s.q.UpdateSnsPlatform(ctx, sqlcgen.UpdateSnsPlatformParams{
		ID: toUUID(p.ID), ResumeID: toUUID(resumeID), Name: p.Name, Link: p.Link,
	})
	return found(n, err, "SNS を書き換えられません")
}

// deleteSnsPlatform は、経歴書の SNS を消す。経歴書に SNS が無ければ false を返す。
func (s store) deleteSnsPlatform(ctx context.Context, resumeID, id uuid.UUID) (bool, error) {
	n, err := s.q.DeleteSnsPlatform(ctx, sqlcgen.DeleteSnsPlatformParams{ID: toUUID(id), ResumeID: toUUID(resumeID)})
	return found(n, err, "SNS を消せません")
}

// 自己PR

func (s store) insertSelfPromotion(ctx context.Context, resumeID uuid.UUID, p SelfPromotion) error {
	if err := s.q.InsertSelfPromotion(ctx, sqlcgen.InsertSelfPromotionParams{
		ID: toUUID(p.ID), ResumeID: toUUID(resumeID), Title: p.Title, Content: p.Content,
	}); err != nil {
		return fmt.Errorf("自己PR を書けません: %w", err)
	}
	return nil
}

// updateSelfPromotion は、経歴書の自己PR を書き換える。経歴書に自己PR が無ければ false を返す。
func (s store) updateSelfPromotion(ctx context.Context, resumeID uuid.UUID, p SelfPromotion) (bool, error) {
	n, err := s.q.UpdateSelfPromotion(ctx, sqlcgen.UpdateSelfPromotionParams{
		ID: toUUID(p.ID), ResumeID: toUUID(resumeID), Title: p.Title, Content: p.Content,
	})
	return found(n, err, "自己PR を書き換えられません")
}

// deleteSelfPromotion は、経歴書の自己PR を消す。経歴書に自己PR が無ければ false を返す。
func (s store) deleteSelfPromotion(ctx context.Context, resumeID, id uuid.UUID) (bool, error) {
	n, err := s.q.DeleteSelfPromotion(ctx, sqlcgen.DeleteSelfPromotionParams{ID: toUUID(id), ResumeID: toUUID(resumeID)})
	return found(n, err, "自己PR を消せません")
}

// found は、書き換えるか消す問い合わせの結果を、項目が見つかったかどうかにする。
func found(rows int64, err error, msg string) (bool, error) {
	if err != nil {
		return false, fmt.Errorf("%s: %w", msg, err)
	}
	return rows > 0, nil
}

// 技術スタック

// techStackColumns は、project_tech_stacks の35の列の名前と、技術スタックの小分類の並びの組である。
// 技術スタックは、列の名前を鍵とする JSON を通して読み書きする(db/queries/resumes.sql のプロジェクトの節)。
var techStackColumns = []struct {
	name  string
	field func(t *TechStack) *[]*string
}{
	{"frontend_languages", func(t *TechStack) *[]*string { return &t.Frontend.Languages }},
	{"frontend_framework", func(t *TechStack) *[]*string { return &t.Frontend.Frameworks }},
	{"frontend_libraries", func(t *TechStack) *[]*string { return &t.Frontend.Libraries }},
	{"frontend_build_tool", func(t *TechStack) *[]*string { return &t.Frontend.BuildTools }},
	{"frontend_package_manager", func(t *TechStack) *[]*string { return &t.Frontend.PackageManagers }},
	{"frontend_linters", func(t *TechStack) *[]*string { return &t.Frontend.Linters }},
	{"frontend_formatters", func(t *TechStack) *[]*string { return &t.Frontend.Formatters }},
	{"frontend_testing_tools", func(t *TechStack) *[]*string { return &t.Frontend.TestingTools }},
	{"backend_languages", func(t *TechStack) *[]*string { return &t.Backend.Languages }},
	{"backend_framework", func(t *TechStack) *[]*string { return &t.Backend.Frameworks }},
	{"backend_libraries", func(t *TechStack) *[]*string { return &t.Backend.Libraries }},
	{"backend_build_tool", func(t *TechStack) *[]*string { return &t.Backend.BuildTools }},
	{"backend_package_manager", func(t *TechStack) *[]*string { return &t.Backend.PackageManagers }},
	{"backend_linters", func(t *TechStack) *[]*string { return &t.Backend.Linters }},
	{"backend_formatters", func(t *TechStack) *[]*string { return &t.Backend.Formatters }},
	{"backend_testing_tools", func(t *TechStack) *[]*string { return &t.Backend.TestingTools }},
	{"orm_tools", func(t *TechStack) *[]*string { return &t.Backend.OrmTools }},
	{"auth", func(t *TechStack) *[]*string { return &t.Backend.Auth }},
	{"clouds", func(t *TechStack) *[]*string { return &t.Infrastructure.Clouds }},
	{"operating_system", func(t *TechStack) *[]*string { return &t.Infrastructure.OperatingSystems }},
	{"containers", func(t *TechStack) *[]*string { return &t.Infrastructure.Containers }},
	{"database", func(t *TechStack) *[]*string { return &t.Infrastructure.Databases }},
	{"web_server", func(t *TechStack) *[]*string { return &t.Infrastructure.WebServers }},
	{"ci_cd_tool", func(t *TechStack) *[]*string { return &t.Infrastructure.CiCdTools }},
	{"iac_tools", func(t *TechStack) *[]*string { return &t.Infrastructure.IacTools }},
	{"monitoring_tools", func(t *TechStack) *[]*string { return &t.Infrastructure.MonitoringTools }},
	{"logging_tools", func(t *TechStack) *[]*string { return &t.Infrastructure.LoggingTools }},
	{"source_control", func(t *TechStack) *[]*string { return &t.Tools.SourceControls }},
	{"project_management", func(t *TechStack) *[]*string { return &t.Tools.ProjectManagements }},
	{"communication_tool", func(t *TechStack) *[]*string { return &t.Tools.CommunicationTools }},
	{"documentation_tools", func(t *TechStack) *[]*string { return &t.Tools.DocumentationTools }},
	{"api_development_tools", func(t *TechStack) *[]*string { return &t.Tools.APIDevelopmentTools }},
	{"design_tools", func(t *TechStack) *[]*string { return &t.Tools.DesignTools }},
	{"editor", func(t *TechStack) *[]*string { return &t.Tools.Editors }},
	{"development_environment", func(t *TechStack) *[]*string { return &t.Tools.DevelopmentEnvironments }},
}

// encodeTechStack は、技術スタックを、35の列の名前を鍵とする JSON にする。nil の並びは JSON の null になり、列には NULL を書く。
// 空の並びは JSON の [] になり、列には {} を書く。並びの nil の要素は JSON の null になり、列の要素には NULL を書く。
func encodeTechStack(t TechStack) ([]byte, error) {
	m := make(map[string][]*string, len(techStackColumns))
	for _, c := range techStackColumns {
		m[c.name] = *c.field(&t)
	}
	b, err := json.Marshal(m)
	if err != nil {
		return nil, fmt.Errorf("技術スタックを JSON にできません: %w", err)
	}
	return b, nil
}

// decodeTechStack は、to_jsonb で JSON にした技術スタックの行を読む。行が無いとき(JSON が NULL のとき)は、空の技術スタックを返す。
func decodeTechStack(b []byte) (TechStack, error) {
	var t TechStack
	if b == nil {
		return t, nil
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal(b, &m); err != nil {
		return t, fmt.Errorf("技術スタックの JSON を読めません: %w", err)
	}
	for _, c := range techStackColumns {
		raw, ok := m[c.name]
		if !ok {
			return t, fmt.Errorf("技術スタックの JSON に列 %s が無い", c.name)
		}
		if err := json.Unmarshal(raw, c.field(&t)); err != nil {
			return t, fmt.Errorf("技術スタックの列 %s を読めません: %w", c.name, err)
		}
	}
	return t, nil
}

// 値の変換

func toUUID(id uuid.UUID) pgtype.UUID {
	return pgtype.UUID{Bytes: id, Valid: true}
}

func fromUUID(id pgtype.UUID) uuid.UUID {
	return id.Bytes
}

func toText(s *string) pgtype.Text {
	if s == nil {
		return pgtype.Text{}
	}
	return pgtype.Text{String: *s, Valid: true}
}

func fromText(t pgtype.Text) *string {
	if !t.Valid {
		return nil
	}
	return &t.String
}

func toDate(d Date) pgtype.Date {
	return pgtype.Date{Time: time.Date(d.Year, d.Month, d.Day, 0, 0, 0, 0, time.UTC), Valid: true}
}

func fromDate(d pgtype.Date) Date {
	return Date{Year: d.Time.Year(), Month: d.Time.Month(), Day: d.Time.Day()}
}

// toYearMonth は、年月をその月の1日の日付にする。Java 版と同じ値である。
func toYearMonth(ym YearMonth) pgtype.Date {
	return toDate(Date{Year: ym.Year, Month: ym.Month, Day: 1})
}

func fromYearMonth(d pgtype.Date) YearMonth {
	return YearMonth{Year: d.Time.Year(), Month: d.Time.Month()}
}

// toPeriod は、期間を開始と終了の日付にする。終了の年月が無ければ、終了の日付を NULL にする。
func toPeriod(p Period) (start, end pgtype.Date) {
	start = toYearMonth(p.StartDate)
	if p.EndDate != nil {
		end = toYearMonth(*p.EndDate)
	}
	return start, end
}

func fromPeriod(start, end pgtype.Date, active bool) Period {
	p := Period{StartDate: fromYearMonth(start), Active: active}
	if end.Valid {
		ym := fromYearMonth(end)
		p.EndDate = &ym
	}
	return p
}

// toTimestamp は、日時を日本の時刻にし、マイクロ秒に四捨五入する。pgx は、マイクロ秒より細かい桁を切り捨てて書くためである。
func toTimestamp(t time.Time) pgtype.Timestamp {
	return pgtype.Timestamp{Time: t.In(japanZone).Round(time.Microsecond), Valid: true}
}

// fromTimestamp は、表から読んだ時差の無い日時を、その見た目のままの日本の時刻にする。
func fromTimestamp(t pgtype.Timestamp) time.Time {
	v := t.Time
	return time.Date(v.Year(), v.Month(), v.Day(), v.Hour(), v.Minute(), v.Second(), v.Nanosecond(), japanZone)
}

func fromResumeRow(row sqlcgen.Resume) Resume {
	return Resume{
		ID:        fromUUID(row.ID),
		UserID:    fromUUID(row.UserID),
		Name:      row.Name,
		Date:      fromDate(row.Date),
		LastName:  fromText(row.LastName),
		FirstName: fromText(row.FirstName),
		CreatedAt: fromTimestamp(row.CreatedAt),
		UpdatedAt: fromTimestamp(row.UpdatedAt),
	}
}
