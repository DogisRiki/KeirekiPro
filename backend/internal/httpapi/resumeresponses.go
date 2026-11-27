package httpapi

import (
	"fmt"
	"net/http"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/resume"
)

// 経歴書の30の操作の答えも、認証と利用者の操作と同じ authResponse で書く。誤りの答えを、認証と利用者の操作と同じ
// 形で書くためである。
var (
	_ gen.ListCertificationNamesResponseObject   = authResponse{}
	_ gen.ListSnsPlatformNamesResponseObject     = authResponse{}
	_ gen.ListTechStacksResponseObject           = authResponse{}
	_ gen.ListResumesResponseObject              = authResponse{}
	_ gen.CreateResumeResponseObject             = authResponse{}
	_ gen.GetResumeResponseObject                = authResponse{}
	_ gen.DeleteResumeResponseObject             = authResponse{}
	_ gen.UpdateResumeBasicResponseObject        = authResponse{}
	_ gen.CreateCareerResponseObject             = authResponse{}
	_ gen.UpdateCareerResponseObject             = authResponse{}
	_ gen.DeleteCareerResponseObject             = authResponse{}
	_ gen.CreateProjectResponseObject            = authResponse{}
	_ gen.UpdateProjectResponseObject            = authResponse{}
	_ gen.DeleteProjectResponseObject            = authResponse{}
	_ gen.CreateCertificationResponseObject      = authResponse{}
	_ gen.UpdateCertificationResponseObject      = authResponse{}
	_ gen.DeleteCertificationResponseObject      = authResponse{}
	_ gen.CreatePortfolioResponseObject          = authResponse{}
	_ gen.UpdatePortfolioResponseObject          = authResponse{}
	_ gen.DeletePortfolioResponseObject          = authResponse{}
	_ gen.CreateSnsPlatformResponseObject        = authResponse{}
	_ gen.UpdateSnsPlatformResponseObject        = authResponse{}
	_ gen.DeleteSnsPlatformResponseObject        = authResponse{}
	_ gen.CreateSelfPromotionResponseObject      = authResponse{}
	_ gen.UpdateSelfPromotionResponseObject      = authResponse{}
	_ gen.DeleteSelfPromotionResponseObject      = authResponse{}
	_ gen.ExportResumeResponseObject             = authResponse{}
	_ gen.ExportResumeWithSettingsResponseObject = authResponse{}
	_ gen.BackupResumeResponseObject             = authResponse{}
	_ gen.RestoreResumeResponseObject            = authResponse{}
)

// localDateTime は、t を Java の LocalDateTime を ISO_LOCAL_DATE_TIME で書いた形で書く。秒は 0 でも書き、秒より細かい
// 部分は末尾の 0 を落として書き、0 なら書かない。時間帯は変えず、t の壁時計の時刻を書く。Service が返した丸める前の
// 値はナノ秒まで、データベースから読んだ値はマイクロ秒までの値を持つので、それぞれの細かさで書かれる。
func localDateTime(t time.Time) string {
	return t.Format("2006-01-02T15:04:05.999999999")
}

// yearMonth は、年月を Java の YearMonth と同じ yyyy-MM で書く。
func yearMonth(ym resume.YearMonth) string {
	return fmt.Sprintf("%04d-%02d", ym.Year, int(ym.Month))
}

// optionalYearMonth は、年月が無ければ nil を、あれば yearMonth で書いた文字を返す。
func optionalYearMonth(ym *resume.YearMonth) *string {
	if ym == nil {
		return nil
	}
	s := yearMonth(*ym)
	return &s
}

// namesBody は、資格と SNS の名前のマスタの答えの本文である。
type namesBody struct {
	Names []string `json:"names"`
}

// resumeListBody は、経歴書の一覧の答えの本文である。
type resumeListBody struct {
	Resumes []resumeListItemBody `json:"resumes"`
}

// resumeListItemBody は、経歴書の一覧の1件である。
type resumeListItemBody struct {
	ID         string `json:"id"`
	ResumeName string `json:"resumeName"`
	CreatedAt  string `json:"createdAt"`
	UpdatedAt  string `json:"updatedAt"`
}

// newResumeListBody は、経歴書の一覧を答えの本文にする。一覧が空でも、null でなく空の並びで書く。
func newResumeListBody(list []resume.Resume) resumeListBody {
	items := make([]resumeListItemBody, 0, len(list))
	for _, r := range list {
		items = append(items, resumeListItemBody{
			ID:         r.ID.String(),
			ResumeName: r.Name,
			CreatedAt:  localDateTime(r.CreatedAt),
			UpdatedAt:  localDateTime(r.UpdatedAt),
		})
	}
	return resumeListBody{Resumes: items}
}

// resumeBody は、Java 版の ResumeInfoResponse と同じ項目を同じ順に並べた、経歴書の答えの本文である。Java 版と同じく、
// 値の無い姓と名の鍵と、項目の無い欄の鍵は書かない。
type resumeBody struct {
	ID             string              `json:"id"`
	ResumeName     string              `json:"resumeName"`
	Date           string              `json:"date"`
	LastName       *string             `json:"lastName,omitempty"`
	FirstName      *string             `json:"firstName,omitempty"`
	CreatedAt      string              `json:"createdAt"`
	UpdatedAt      string              `json:"updatedAt"`
	Careers        []careerBody        `json:"careers,omitempty"`
	Projects       []projectBody       `json:"projects,omitempty"`
	Certifications []certificationBody `json:"certifications,omitempty"`
	Portfolios     []portfolioBody     `json:"portfolios,omitempty"`
	SnsPlatforms   []snsPlatformBody   `json:"snsPlatforms,omitempty"`
	SelfPromotions []selfPromotionBody `json:"selfPromotions,omitempty"`
}

type careerBody struct {
	ID          string  `json:"id"`
	CompanyName string  `json:"companyName"`
	StartDate   string  `json:"startDate"`
	EndDate     *string `json:"endDate"`
	Active      bool    `json:"active"`
}

type projectBody struct {
	ID          string           `json:"id"`
	CompanyName string           `json:"companyName"`
	StartDate   string           `json:"startDate"`
	EndDate     *string          `json:"endDate"`
	Active      bool             `json:"active"`
	Name        string           `json:"name"`
	Overview    string           `json:"overview"`
	TeamComp    string           `json:"teamComp"`
	Role        string           `json:"role"`
	Achievement string           `json:"achievement"`
	Process     processBody      `json:"process"`
	TechStack   resume.TechStack `json:"techStack"`
}

// processBody は、プロジェクトの工程の答えである。鍵の順は、Java 版の ResumeInfoResponse の項目の順(maintenance、systemTest)にする。
// Java 版は、maintenance の鍵に SystemTest の値を、systemTest の鍵に Maintenance の値を入れて答えるので、画面が総合テストと
// 運用・保守のチェックを入れ替えて出す。Go 版は、鍵ごとにその工程の値を入れて答える(変えた動きの一覧の CB-078)。
type processBody struct {
	Requirements    bool `json:"requirements"`
	BasicDesign     bool `json:"basicDesign"`
	DetailedDesign  bool `json:"detailedDesign"`
	Implementation  bool `json:"implementation"`
	IntegrationTest bool `json:"integrationTest"`
	Maintenance     bool `json:"maintenance"`
	SystemTest      bool `json:"systemTest"`
}

type certificationBody struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Date string `json:"date"`
}

type portfolioBody struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	Overview  string  `json:"overview"`
	TechStack *string `json:"techStack"`
	Link      string  `json:"link"`
}

type snsPlatformBody struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Link string `json:"link"`
}

type selfPromotionBody struct {
	ID      string `json:"id"`
	Title   string `json:"title"`
	Content string `json:"content"`
}

// newResumeBody は、経歴書 r を答えの本文にする。
func newResumeBody(r resume.Resume) resumeBody {
	b := resumeBody{
		ID:         r.ID.String(),
		ResumeName: r.Name,
		Date:       fmt.Sprintf("%04d-%02d-%02d", r.Date.Year, int(r.Date.Month), r.Date.Day),
		LastName:   r.LastName,
		FirstName:  r.FirstName,
		CreatedAt:  localDateTime(r.CreatedAt),
		UpdatedAt:  localDateTime(r.UpdatedAt),
	}
	for _, c := range r.Careers {
		b.Careers = append(b.Careers, careerBody{
			ID: c.ID.String(), CompanyName: c.CompanyName,
			StartDate: yearMonth(c.Period.StartDate), EndDate: optionalYearMonth(c.Period.EndDate), Active: c.Period.Active,
		})
	}
	for _, p := range r.Projects {
		b.Projects = append(b.Projects, projectBody{
			ID: p.ID.String(), CompanyName: p.CompanyName,
			StartDate: yearMonth(p.Period.StartDate), EndDate: optionalYearMonth(p.Period.EndDate), Active: p.Period.Active,
			Name: p.Name, Overview: p.Overview, TeamComp: p.TeamComp, Role: p.Role, Achievement: p.Achievement,
			Process: processBody{
				Requirements:    p.Process.Requirements,
				BasicDesign:     p.Process.BasicDesign,
				DetailedDesign:  p.Process.DetailedDesign,
				Implementation:  p.Process.Implementation,
				IntegrationTest: p.Process.IntegrationTest,
				Maintenance:     p.Process.Maintenance,
				SystemTest:      p.Process.SystemTest,
			},
			TechStack: p.TechStack,
		})
	}
	for _, c := range r.Certifications {
		b.Certifications = append(b.Certifications, certificationBody{ID: c.ID.String(), Name: c.Name, Date: yearMonth(c.Date)})
	}
	for _, p := range r.Portfolios {
		b.Portfolios = append(b.Portfolios, portfolioBody{
			ID: p.ID.String(), Name: p.Name, Overview: p.Overview, TechStack: p.TechStack, Link: p.Link,
		})
	}
	for _, s := range r.SnsPlatforms {
		b.SnsPlatforms = append(b.SnsPlatforms, snsPlatformBody{ID: s.ID.String(), Name: s.Name, Link: s.Link})
	}
	for _, s := range r.SelfPromotions {
		b.SelfPromotions = append(b.SelfPromotions, selfPromotionBody{ID: s.ID.String(), Title: s.Title, Content: s.Content})
	}
	return b
}

// VisitListCertificationNamesResponse は、応答を書く。
func (r authResponse) VisitListCertificationNamesResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitListSnsPlatformNamesResponse は、応答を書く。
func (r authResponse) VisitListSnsPlatformNamesResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitListTechStacksResponse は、応答を書く。
func (r authResponse) VisitListTechStacksResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitListResumesResponse は、応答を書く。
func (r authResponse) VisitListResumesResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitCreateResumeResponse は、応答を書く。
func (r authResponse) VisitCreateResumeResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitGetResumeResponse は、応答を書く。
func (r authResponse) VisitGetResumeResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitDeleteResumeResponse は、応答を書く。
func (r authResponse) VisitDeleteResumeResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitUpdateResumeBasicResponse は、応答を書く。
func (r authResponse) VisitUpdateResumeBasicResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitCreateCareerResponse は、応答を書く。
func (r authResponse) VisitCreateCareerResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitUpdateCareerResponse は、応答を書く。
func (r authResponse) VisitUpdateCareerResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitDeleteCareerResponse は、応答を書く。
func (r authResponse) VisitDeleteCareerResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitCreateProjectResponse は、応答を書く。
func (r authResponse) VisitCreateProjectResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitUpdateProjectResponse は、応答を書く。
func (r authResponse) VisitUpdateProjectResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitDeleteProjectResponse は、応答を書く。
func (r authResponse) VisitDeleteProjectResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitCreateCertificationResponse は、応答を書く。
func (r authResponse) VisitCreateCertificationResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitUpdateCertificationResponse は、応答を書く。
func (r authResponse) VisitUpdateCertificationResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitDeleteCertificationResponse は、応答を書く。
func (r authResponse) VisitDeleteCertificationResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitCreatePortfolioResponse は、応答を書く。
func (r authResponse) VisitCreatePortfolioResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitUpdatePortfolioResponse は、応答を書く。
func (r authResponse) VisitUpdatePortfolioResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitDeletePortfolioResponse は、応答を書く。
func (r authResponse) VisitDeletePortfolioResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitCreateSnsPlatformResponse は、応答を書く。
func (r authResponse) VisitCreateSnsPlatformResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitUpdateSnsPlatformResponse は、応答を書く。
func (r authResponse) VisitUpdateSnsPlatformResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitDeleteSnsPlatformResponse は、応答を書く。
func (r authResponse) VisitDeleteSnsPlatformResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitCreateSelfPromotionResponse は、応答を書く。
func (r authResponse) VisitCreateSelfPromotionResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitUpdateSelfPromotionResponse は、応答を書く。
func (r authResponse) VisitUpdateSelfPromotionResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitDeleteSelfPromotionResponse は、応答を書く。
func (r authResponse) VisitDeleteSelfPromotionResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitExportResumeResponse は、応答を書く。
func (r authResponse) VisitExportResumeResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitExportResumeWithSettingsResponse は、応答を書く。
func (r authResponse) VisitExportResumeWithSettingsResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitBackupResumeResponse は、応答を書く。
func (r authResponse) VisitBackupResumeResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitRestoreResumeResponse は、応答を書く。
func (r authResponse) VisitRestoreResumeResponse(w http.ResponseWriter) error {
	return r.write(w)
}
