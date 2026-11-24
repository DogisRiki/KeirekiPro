package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"go.yaml.in/yaml/v3"

	"github.com/DogisRiki/KeirekiPro/backend"
	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/authctx"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/migrate"
	"github.com/DogisRiki/KeirekiPro/backend/internal/resume"
)

// jst は、Service が Now から作る日本の時刻の時間帯の代わりである。テストの環境に時間帯のデータが無くても動くように、
// 固定の時差で作る。
var jst = time.FixedZone("JST", 9*60*60)

// testResumeID は、受け口のテストで使う経歴書の ID である。
const testResumeID = "00000000-0000-4000-8000-000000000301"

// itemID は、受け口のテストで使う項目の ID を、末尾の番号 n から作る。
func itemID(n int) uuid.UUID {
	return uuid.MustParse(fmt.Sprintf("00000000-0000-4000-8000-%012d", n))
}

func strp(s string) *string { return &s }

// fullResume は、6つの欄のすべてに項目がある経歴書である。作成の日時はナノ秒まで値のある日本の時刻で、更新の日時は
// データベースから読んだ値と同じく UTC の時間帯に置いた壁時計の時刻である。
func fullResume() resume.Resume {
	end := resume.YearMonth{Year: 2021, Month: time.January}
	careerEnd := resume.YearMonth{Year: 2019, Month: time.December}
	var stack resume.TechStack
	stack.Frontend.Languages = []*string{strp("TypeScript"), nil}
	stack.Frontend.Frameworks = []*string{}
	stack.Tools.DevelopmentEnvironments = []*string{strp("VS Code")}
	return resume.Resume{
		ID:        uuid.MustParse(testResumeID),
		UserID:    handlerUserID,
		Name:      "職務経歴書<&>",
		Date:      resume.Date{Year: 2026, Month: time.November, Day: 14},
		LastName:  strp("山田"),
		FirstName: strp("太郎"),
		CreatedAt: time.Date(2026, 11, 14, 10, 23, 45, 341237480, jst),
		UpdatedAt: time.Date(2026, 11, 14, 10, 23, 46, 500000000, time.UTC),
		Careers: []resume.Career{
			{ID: itemID(401), CompanyName: "A社", Period: resume.Period{
				StartDate: resume.YearMonth{Year: 2020, Month: time.January}, Active: true,
			}},
			{ID: itemID(402), CompanyName: "B社", Period: resume.Period{
				StartDate: resume.YearMonth{Year: 2018, Month: time.April}, EndDate: &careerEnd,
			}},
		},
		Projects: []resume.Project{{
			ID: itemID(501), CompanyName: "A社",
			Period: resume.Period{StartDate: resume.YearMonth{Year: 2020, Month: time.January}, EndDate: &end},
			Name:   "案件", Overview: "概要", TeamComp: "5人", Role: "開発", Achievement: "成果",
			Process: resume.Process{
				Requirements: true, DetailedDesign: true, IntegrationTest: true, SystemTest: true,
			},
			TechStack: stack,
		}},
		Certifications: []resume.Certification{
			{ID: itemID(601), Name: "基本情報技術者試験", Date: resume.YearMonth{Year: 2019, Month: time.October}},
		},
		Portfolios: []resume.Portfolio{
			{ID: itemID(701), Name: "作品", Overview: "作品の概要", Link: "https://example.com/a?b=1&c=2"},
			{ID: itemID(702), Name: "作品2", Overview: "", TechStack: strp("Go"), Link: "https://example.com/b"},
		},
		SnsPlatforms: []resume.SnsPlatform{
			{ID: itemID(801), Name: "GitHub", Link: "https://github.com/example"},
		},
		SelfPromotions: []resume.SelfPromotion{
			{ID: itemID(901), Title: "強み", Content: "改行\nを含む"},
		},
	}
}

// fullResumeJSON は、fullResume を Java 版の ResumeInfoResponse の項目の順で書いた本文である。プロジェクトの工程は、
// Java 版と同じく、maintenance に SystemTest の値を、systemTest に Maintenance の値を入れる。技術スタックの中の
// 並びは、nil を null、空を [] のまま書く。
const fullResumeJSON = `{"id":"00000000-0000-4000-8000-000000000301","resumeName":"職務経歴書<&>","date":"2026-11-14",` +
	`"lastName":"山田","firstName":"太郎","createdAt":"2026-11-14T10:23:45.34123748","updatedAt":"2026-11-14T10:23:46.5",` +
	`"careers":[` +
	`{"id":"00000000-0000-4000-8000-000000000401","companyName":"A社","startDate":"2020-01","endDate":null,"active":true},` +
	`{"id":"00000000-0000-4000-8000-000000000402","companyName":"B社","startDate":"2018-04","endDate":"2019-12","active":false}],` +
	`"projects":[{"id":"00000000-0000-4000-8000-000000000501","companyName":"A社","startDate":"2020-01",` +
	`"endDate":"2021-01","active":false,"name":"案件","overview":"概要","teamComp":"5人","role":"開発","achievement":"成果",` +
	`"process":{"requirements":true,"basicDesign":false,"detailedDesign":true,"implementation":false,` +
	`"integrationTest":true,"maintenance":true,"systemTest":false},` +
	`"techStack":{"frontend":{"languages":["TypeScript",null],"frameworks":[],"libraries":null,"buildTools":null,` +
	`"packageManagers":null,"linters":null,"formatters":null,"testingTools":null},` +
	`"backend":{"languages":null,"frameworks":null,"libraries":null,"buildTools":null,"packageManagers":null,` +
	`"linters":null,"formatters":null,"testingTools":null,"ormTools":null,"auth":null},` +
	`"infrastructure":{"clouds":null,"operatingSystems":null,"containers":null,"databases":null,"webServers":null,` +
	`"ciCdTools":null,"iacTools":null,"monitoringTools":null,"loggingTools":null},` +
	`"tools":{"sourceControls":null,"projectManagements":null,"communicationTools":null,"documentationTools":null,` +
	`"apiDevelopmentTools":null,"designTools":null,"editors":null,"developmentEnvironments":["VS Code"]}}}],` +
	`"certifications":[{"id":"00000000-0000-4000-8000-000000000601","name":"基本情報技術者試験","date":"2019-10"}],` +
	`"portfolios":[{"id":"00000000-0000-4000-8000-000000000701","name":"作品","overview":"作品の概要","techStack":null,` +
	`"link":"https://example.com/a?b=1&c=2"},` +
	`{"id":"00000000-0000-4000-8000-000000000702","name":"作品2","overview":"","techStack":"Go","link":"https://example.com/b"}],` +
	`"snsPlatforms":[{"id":"00000000-0000-4000-8000-000000000801","name":"GitHub","link":"https://github.com/example"}],` +
	`"selfPromotions":[{"id":"00000000-0000-4000-8000-000000000901","title":"強み","content":"改行\nを含む"}]}`

// fullMaster は、技術スタックのマスタである。Service は、名前の無い小分類も空の並びにして返す。
func fullMaster() resume.TechStackMaster {
	var m resume.TechStackMaster
	m.Frontend = resume.FrontendStacks[string]{
		Languages: []string{"TypeScript", "JavaScript"}, Frameworks: []string{"React"}, Libraries: []string{},
		BuildTools: []string{}, PackageManagers: []string{}, Linters: []string{}, Formatters: []string{},
		TestingTools: []string{},
	}
	m.Backend = resume.BackendStacks[string]{
		Languages: []string{"Go"}, Frameworks: []string{}, Libraries: []string{}, BuildTools: []string{},
		PackageManagers: []string{}, Linters: []string{}, Formatters: []string{}, TestingTools: []string{},
		OrmTools: []string{}, Auth: []string{},
	}
	m.Infrastructure = resume.InfrastructureStacks[string]{
		Clouds: []string{"AWS"}, OperatingSystems: []string{}, Containers: []string{}, Databases: []string{},
		WebServers: []string{}, CiCdTools: []string{}, IacTools: []string{}, MonitoringTools: []string{},
		LoggingTools: []string{},
	}
	m.Tools = resume.ToolStacks[string]{
		SourceControls: []string{"Git"}, ProjectManagements: []string{}, CommunicationTools: []string{},
		DocumentationTools: []string{}, APIDevelopmentTools: []string{}, DesignTools: []string{}, Editors: []string{},
		DevelopmentEnvironments: []string{},
	}
	return m
}

const fullMasterJSON = `{"frontend":{"languages":["TypeScript","JavaScript"],"frameworks":["React"],"libraries":[],` +
	`"buildTools":[],"packageManagers":[],"linters":[],"formatters":[],"testingTools":[]},` +
	`"backend":{"languages":["Go"],"frameworks":[],"libraries":[],"buildTools":[],"packageManagers":[],"linters":[],` +
	`"formatters":[],"testingTools":[],"ormTools":[],"auth":[]},` +
	`"infrastructure":{"clouds":["AWS"],"operatingSystems":[],"containers":[],"databases":[],"webServers":[],` +
	`"ciCdTools":[],"iacTools":[],"monitoringTools":[],"loggingTools":[]},` +
	`"tools":{"sourceControls":["Git"],"projectManagements":[],"communicationTools":[],"documentationTools":[],` +
	`"apiDevelopmentTools":[],"designTools":[],"editors":[],"developmentEnvironments":[]}}`

// listedResumes は、一覧の経歴書である。一覧の経歴書は6つの欄の項目を持たない。
func listedResumes() []resume.Resume {
	return []resume.Resume{
		{
			ID: uuid.MustParse(testResumeID), UserID: handlerUserID, Name: "一つ目",
			CreatedAt: time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC),
			UpdatedAt: time.Date(2026, 11, 2, 9, 30, 15, 123400000, time.UTC),
		},
		{
			ID: itemID(302), UserID: handlerUserID, Name: "二つ目<&>", LastName: strp("山田"),
			CreatedAt: time.Date(2026, 11, 3, 0, 0, 1, 1000, time.UTC),
			UpdatedAt: time.Date(2026, 11, 3, 0, 0, 1, 1000, time.UTC),
		},
	}
}

const listedResumesJSON = `{"resumes":[` +
	`{"id":"00000000-0000-4000-8000-000000000301","resumeName":"一つ目","createdAt":"2026-11-01T09:00:00",` +
	`"updatedAt":"2026-11-02T09:30:15.1234"},` +
	`{"id":"00000000-0000-4000-8000-000000000302","resumeName":"二つ目<&>","createdAt":"2026-11-03T00:00:01.000001",` +
	`"updatedAt":"2026-11-03T00:00:01.000001"}]}`

// fakeResumes は、経歴書の処理の代わりである。呼ばれた操作と引数を calls に記録し、errs に操作の名前で決めた誤りを返す。
// 経歴書を返す操作は resume を、一覧は list を、マスタは names と master を返す。出力の操作は export を返す。
type fakeResumes struct {
	calls  []string
	resume resume.Resume
	list   []resume.Resume
	names  []string
	master resume.TechStackMaster
	export resume.Export
	errs   map[string]error
}

func (f *fakeResumes) record(op string, args ...string) error {
	f.calls = append(f.calls, op+"("+strings.Join(args, ", ")+")")
	return f.errs[op]
}

func (f *fakeResumes) answer(op string, args ...string) (resume.Resume, error) {
	if err := f.record(op, args...); err != nil {
		return resume.Resume{}, err
	}
	return f.resume, nil
}

// exportAnswer は、呼び出しを記録し、誤りが無ければ export を返す。
func (f *fakeResumes) exportAnswer(op string, args ...string) (resume.Export, error) {
	if err := f.record(op, args...); err != nil {
		return resume.Export{}, err
	}
	return f.export, nil
}

func (f *fakeResumes) ListCertificationNames(context.Context) ([]string, error) {
	if err := f.record("ListCertificationNames"); err != nil {
		return nil, err
	}
	return f.names, nil
}

func (f *fakeResumes) ListSnsPlatformNames(context.Context) ([]string, error) {
	if err := f.record("ListSnsPlatformNames"); err != nil {
		return nil, err
	}
	return f.names, nil
}

func (f *fakeResumes) ListTechStacks(context.Context) (resume.TechStackMaster, error) {
	if err := f.record("ListTechStacks"); err != nil {
		return resume.TechStackMaster{}, err
	}
	return f.master, nil
}

func (f *fakeResumes) ListResumes(_ context.Context, userID uuid.UUID) ([]resume.Resume, error) {
	if err := f.record("ListResumes", userID.String()); err != nil {
		return nil, err
	}
	return f.list, nil
}

func (f *fakeResumes) GetResume(_ context.Context, userID uuid.UUID, resumeID string) (resume.Resume, error) {
	return f.answer("GetResume", userID.String(), resumeID)
}

func (f *fakeResumes) DeleteResume(_ context.Context, userID uuid.UUID, resumeID string) error {
	return f.record("DeleteResume", userID.String(), resumeID)
}

func (f *fakeResumes) CreateResume(_ context.Context, userID uuid.UUID, body []byte) (resume.Resume, error) {
	return f.answer("CreateResume", userID.String(), string(body))
}

func (f *fakeResumes) UpdateResumeBasic(_ context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error) {
	return f.answer("UpdateResumeBasic", userID.String(), resumeID, string(body))
}

func (f *fakeResumes) ExportResume(
	_ context.Context, userID uuid.UUID, resumeID string, format resume.ExportFormat,
) (resume.Export, error) {
	return f.exportAnswer("ExportResume", userID.String(), resumeID, string(format))
}

func (f *fakeResumes) ExportResumeWithSettings(
	_ context.Context, userID uuid.UUID, resumeID string, body []byte,
) (resume.Export, error) {
	return f.exportAnswer("ExportResumeWithSettings", userID.String(), resumeID, string(body))
}

func (f *fakeResumes) BackupResume(_ context.Context, userID uuid.UUID, resumeID string) (resume.Export, error) {
	return f.exportAnswer("BackupResume", userID.String(), resumeID)
}

func (f *fakeResumes) RestoreResume(_ context.Context, userID uuid.UUID, body []byte) (resume.Resume, error) {
	return f.answer("RestoreResume", userID.String(), string(body))
}

func (f *fakeResumes) CreateCareer(_ context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error) {
	return f.answer("CreateCareer", userID.String(), resumeID, string(body))
}

func (f *fakeResumes) UpdateCareer(_ context.Context, userID uuid.UUID, resumeID, careerID string, body []byte) (resume.Resume, error) {
	return f.answer("UpdateCareer", userID.String(), resumeID, careerID, string(body))
}

func (f *fakeResumes) DeleteCareer(_ context.Context, userID uuid.UUID, resumeID, careerID string) error {
	return f.record("DeleteCareer", userID.String(), resumeID, careerID)
}

func (f *fakeResumes) CreateProject(_ context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error) {
	return f.answer("CreateProject", userID.String(), resumeID, string(body))
}

func (f *fakeResumes) UpdateProject(_ context.Context, userID uuid.UUID, resumeID, projectID string, body []byte) (resume.Resume, error) {
	return f.answer("UpdateProject", userID.String(), resumeID, projectID, string(body))
}

func (f *fakeResumes) DeleteProject(_ context.Context, userID uuid.UUID, resumeID, projectID string) error {
	return f.record("DeleteProject", userID.String(), resumeID, projectID)
}

func (f *fakeResumes) CreateCertification(_ context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error) {
	return f.answer("CreateCertification", userID.String(), resumeID, string(body))
}

func (f *fakeResumes) UpdateCertification(
	_ context.Context, userID uuid.UUID, resumeID, certificationID string, body []byte,
) (resume.Resume, error) {
	return f.answer("UpdateCertification", userID.String(), resumeID, certificationID, string(body))
}

func (f *fakeResumes) DeleteCertification(_ context.Context, userID uuid.UUID, resumeID, certificationID string) error {
	return f.record("DeleteCertification", userID.String(), resumeID, certificationID)
}

func (f *fakeResumes) CreatePortfolio(_ context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error) {
	return f.answer("CreatePortfolio", userID.String(), resumeID, string(body))
}

func (f *fakeResumes) UpdatePortfolio(
	_ context.Context, userID uuid.UUID, resumeID, portfolioID string, body []byte,
) (resume.Resume, error) {
	return f.answer("UpdatePortfolio", userID.String(), resumeID, portfolioID, string(body))
}

func (f *fakeResumes) DeletePortfolio(_ context.Context, userID uuid.UUID, resumeID, portfolioID string) error {
	return f.record("DeletePortfolio", userID.String(), resumeID, portfolioID)
}

func (f *fakeResumes) CreateSnsPlatform(_ context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error) {
	return f.answer("CreateSnsPlatform", userID.String(), resumeID, string(body))
}

func (f *fakeResumes) UpdateSnsPlatform(
	_ context.Context, userID uuid.UUID, resumeID, snsPlatformID string, body []byte,
) (resume.Resume, error) {
	return f.answer("UpdateSnsPlatform", userID.String(), resumeID, snsPlatformID, string(body))
}

func (f *fakeResumes) DeleteSnsPlatform(_ context.Context, userID uuid.UUID, resumeID, snsPlatformID string) error {
	return f.record("DeleteSnsPlatform", userID.String(), resumeID, snsPlatformID)
}

func (f *fakeResumes) CreateSelfPromotion(_ context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error) {
	return f.answer("CreateSelfPromotion", userID.String(), resumeID, string(body))
}

func (f *fakeResumes) UpdateSelfPromotion(
	_ context.Context, userID uuid.UUID, resumeID, selfPromotionID string, body []byte,
) (resume.Resume, error) {
	return f.answer("UpdateSelfPromotion", userID.String(), resumeID, selfPromotionID, string(body))
}

func (f *fakeResumes) DeleteSelfPromotion(_ context.Context, userID uuid.UUID, resumeID, selfPromotionID string) error {
	return f.record("DeleteSelfPromotion", userID.String(), resumeID, selfPromotionID)
}

// bodyOf は、生成したコードが読まずに受け取った本文を作る。
func bodyOf(s string) *json.RawMessage {
	b := json.RawMessage(s)
	return &b
}

// resumeOp は、経歴書の受け口の1つの操作である。call は受け口を呼び、calls は処理の呼び出し、want は成功の応答である。
// needsLogin は、ログインした利用者の ID を処理に渡す操作かである。
type resumeOp struct {
	name       string
	call       func(ctx context.Context, h *resumeHandlers) (any, error)
	calls      []string
	want       wantResponse
	needsLogin bool
}

func jsonWant(status int, body string) wantResponse {
	return wantResponse{status: status, contentType: "application/json", body: body}
}

// itemOp は、6つの欄の1つの、項目の作成と更新と削除の3つの操作である。
type itemOp struct {
	name   string
	itemID string
	create func(ctx context.Context, h *resumeHandlers, body string) (any, error)
	update func(ctx context.Context, h *resumeHandlers, itemID, body string) (any, error)
	delete func(ctx context.Context, h *resumeHandlers, itemID string) (any, error)
	// notFound は、項目が無いときの文言である。
	notFound string
}

func itemOps() []itemOp {
	return []itemOp{
		{
			name: "Career", itemID: itemID(401).String(), notFound: resume.MessageCareerNotFound,
			create: func(ctx context.Context, h *resumeHandlers, body string) (any, error) {
				return h.CreateCareer(ctx, gen.CreateCareerRequestObject{ResumeId: testResumeID, Body: bodyOf(body)})
			},
			update: func(ctx context.Context, h *resumeHandlers, id, body string) (any, error) {
				return h.UpdateCareer(ctx, gen.UpdateCareerRequestObject{ResumeId: testResumeID, CareerId: id, Body: bodyOf(body)})
			},
			delete: func(ctx context.Context, h *resumeHandlers, id string) (any, error) {
				return h.DeleteCareer(ctx, gen.DeleteCareerRequestObject{ResumeId: testResumeID, CareerId: id})
			},
		},
		{
			name: "Project", itemID: itemID(501).String(), notFound: resume.MessageProjectNotFound,
			create: func(ctx context.Context, h *resumeHandlers, body string) (any, error) {
				return h.CreateProject(ctx, gen.CreateProjectRequestObject{ResumeId: testResumeID, Body: bodyOf(body)})
			},
			update: func(ctx context.Context, h *resumeHandlers, id, body string) (any, error) {
				return h.UpdateProject(ctx, gen.UpdateProjectRequestObject{ResumeId: testResumeID, ProjectId: id, Body: bodyOf(body)})
			},
			delete: func(ctx context.Context, h *resumeHandlers, id string) (any, error) {
				return h.DeleteProject(ctx, gen.DeleteProjectRequestObject{ResumeId: testResumeID, ProjectId: id})
			},
		},
		{
			name: "Certification", itemID: itemID(601).String(), notFound: resume.MessageCertificationNotFound,
			create: func(ctx context.Context, h *resumeHandlers, body string) (any, error) {
				return h.CreateCertification(ctx, gen.CreateCertificationRequestObject{ResumeId: testResumeID, Body: bodyOf(body)})
			},
			update: func(ctx context.Context, h *resumeHandlers, id, body string) (any, error) {
				return h.UpdateCertification(ctx, gen.UpdateCertificationRequestObject{
					ResumeId: testResumeID, CertificationId: id, Body: bodyOf(body),
				})
			},
			delete: func(ctx context.Context, h *resumeHandlers, id string) (any, error) {
				return h.DeleteCertification(ctx, gen.DeleteCertificationRequestObject{ResumeId: testResumeID, CertificationId: id})
			},
		},
		{
			name: "Portfolio", itemID: itemID(701).String(), notFound: resume.MessagePortfolioNotFound,
			create: func(ctx context.Context, h *resumeHandlers, body string) (any, error) {
				return h.CreatePortfolio(ctx, gen.CreatePortfolioRequestObject{ResumeId: testResumeID, Body: bodyOf(body)})
			},
			update: func(ctx context.Context, h *resumeHandlers, id, body string) (any, error) {
				return h.UpdatePortfolio(ctx, gen.UpdatePortfolioRequestObject{
					ResumeId: testResumeID, PortfolioId: id, Body: bodyOf(body),
				})
			},
			delete: func(ctx context.Context, h *resumeHandlers, id string) (any, error) {
				return h.DeletePortfolio(ctx, gen.DeletePortfolioRequestObject{ResumeId: testResumeID, PortfolioId: id})
			},
		},
		{
			name: "SnsPlatform", itemID: itemID(801).String(), notFound: resume.MessageSnsPlatformNotFound,
			create: func(ctx context.Context, h *resumeHandlers, body string) (any, error) {
				return h.CreateSnsPlatform(ctx, gen.CreateSnsPlatformRequestObject{ResumeId: testResumeID, Body: bodyOf(body)})
			},
			update: func(ctx context.Context, h *resumeHandlers, id, body string) (any, error) {
				return h.UpdateSnsPlatform(ctx, gen.UpdateSnsPlatformRequestObject{
					ResumeId: testResumeID, SnsPlatformId: id, Body: bodyOf(body),
				})
			},
			delete: func(ctx context.Context, h *resumeHandlers, id string) (any, error) {
				return h.DeleteSnsPlatform(ctx, gen.DeleteSnsPlatformRequestObject{ResumeId: testResumeID, SnsPlatformId: id})
			},
		},
		{
			name: "SelfPromotion", itemID: itemID(901).String(), notFound: resume.MessageSelfPromotionNotFound,
			create: func(ctx context.Context, h *resumeHandlers, body string) (any, error) {
				return h.CreateSelfPromotion(ctx, gen.CreateSelfPromotionRequestObject{ResumeId: testResumeID, Body: bodyOf(body)})
			},
			update: func(ctx context.Context, h *resumeHandlers, id, body string) (any, error) {
				return h.UpdateSelfPromotion(ctx, gen.UpdateSelfPromotionRequestObject{
					ResumeId: testResumeID, SelfPromotionId: id, Body: bodyOf(body),
				})
			},
			delete: func(ctx context.Context, h *resumeHandlers, id string) (any, error) {
				return h.DeleteSelfPromotion(ctx, gen.DeleteSelfPromotionRequestObject{ResumeId: testResumeID, SelfPromotionId: id})
			},
		},
	}
}

// resumeOps は、経歴書の受け口の30の操作である。本文は、受け口が読まずに処理へ渡すことを確かめるため、JSON として
// 誤った文字も含めて、操作ごとに違う文字にする。
func resumeOps() []resumeOp {
	user := handlerUserID.String()
	resumeWant := jsonWant(http.StatusOK, fullResumeJSON)
	createdWant := jsonWant(http.StatusCreated, fullResumeJSON)
	noContent := wantResponse{status: http.StatusNoContent}
	exportWant := wantResponse{status: http.StatusOK, contentType: "application/pdf", body: fakeExportBody}
	ops := []resumeOp{
		{
			name: "ListCertificationNames",
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.ListCertificationNames(ctx, gen.ListCertificationNamesRequestObject{})
			},
			calls: []string{"ListCertificationNames()"},
			want:  jsonWant(http.StatusOK, `{"names":["基本情報技術者試験","<応用&>"]}`),
		},
		{
			name: "ListSnsPlatformNames",
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.ListSnsPlatformNames(ctx, gen.ListSnsPlatformNamesRequestObject{})
			},
			calls: []string{"ListSnsPlatformNames()"},
			want:  jsonWant(http.StatusOK, `{"names":["基本情報技術者試験","<応用&>"]}`),
		},
		{
			name: "ListTechStacks",
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.ListTechStacks(ctx, gen.ListTechStacksRequestObject{})
			},
			calls: []string{"ListTechStacks()"},
			want:  jsonWant(http.StatusOK, fullMasterJSON),
		},
		{
			name: "ListResumes", needsLogin: true,
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.ListResumes(ctx, gen.ListResumesRequestObject{})
			},
			calls: []string{"ListResumes(" + user + ")"},
			want:  jsonWant(http.StatusOK, listedResumesJSON),
		},
		{
			name: "CreateResume", needsLogin: true,
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.CreateResume(ctx, gen.CreateResumeRequestObject{Body: bodyOf(`{"resumeName":"作成"}`)})
			},
			calls: []string{"CreateResume(" + user + `, {"resumeName":"作成"})`},
			want:  createdWant,
		},
		{
			name: "GetResume", needsLogin: true,
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.GetResume(ctx, gen.GetResumeRequestObject{ResumeId: testResumeID})
			},
			calls: []string{"GetResume(" + user + ", " + testResumeID + ")"},
			want:  resumeWant,
		},
		{
			name: "DeleteResume", needsLogin: true,
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.DeleteResume(ctx, gen.DeleteResumeRequestObject{ResumeId: testResumeID})
			},
			calls: []string{"DeleteResume(" + user + ", " + testResumeID + ")"},
			want:  noContent,
		},
		{
			name: "UpdateResumeBasic", needsLogin: true,
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.UpdateResumeBasic(ctx, gen.UpdateResumeBasicRequestObject{
					ResumeId: testResumeID, Body: bodyOf(`{"date":"2026-11-14"} 余り`),
				})
			},
			calls: []string{"UpdateResumeBasic(" + user + ", " + testResumeID + `, {"date":"2026-11-14"} 余り)`},
			want:  resumeWant,
		},
		{
			name: "ExportResume", needsLogin: true,
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.ExportResume(withAccept(ctx, screenMarkdownAccept), gen.ExportResumeRequestObject{ResumeId: testResumeID})
			},
			calls: []string{"ExportResume(" + user + ", " + testResumeID + ", markdown)"},
			want:  exportWant,
		},
		{
			name: "ExportResumeWithSettings", needsLogin: true,
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.ExportResumeWithSettings(ctx, gen.ExportResumeWithSettingsRequestObject{
					ResumeId: testResumeID, Body: bodyOf(`{"format":"pdf"} 余り`),
				})
			},
			calls: []string{"ExportResumeWithSettings(" + user + ", " + testResumeID + `, {"format":"pdf"} 余り)`},
			want:  exportWant,
		},
		{
			name: "BackupResume", needsLogin: true,
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.BackupResume(ctx, gen.BackupResumeRequestObject{ResumeId: testResumeID})
			},
			calls: []string{"BackupResume(" + user + ", " + testResumeID + ")"},
			want:  exportWant,
		},
		{
			name: "RestoreResume", needsLogin: true,
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.RestoreResume(ctx, gen.RestoreResumeRequestObject{Body: bodyOf(`{"version":"1.0"} 余り`)})
			},
			calls: []string{"RestoreResume(" + user + `, {"version":"1.0"} 余り)`},
			want:  createdWant,
		},
	}
	for _, it := range itemOps() {
		createBody := `{"create":"` + it.name + `"}`
		updateBody := `{"update":"` + it.name + `"}`
		ops = append(ops,
			resumeOp{
				name: "Create" + it.name, needsLogin: true,
				call: func(ctx context.Context, h *resumeHandlers) (any, error) {
					return it.create(ctx, h, createBody)
				},
				calls: []string{"Create" + it.name + "(" + user + ", " + testResumeID + ", " + createBody + ")"},
				want:  createdWant,
			},
			resumeOp{
				name: "Update" + it.name, needsLogin: true,
				call: func(ctx context.Context, h *resumeHandlers) (any, error) {
					return it.update(ctx, h, it.itemID, updateBody)
				},
				calls: []string{"Update" + it.name + "(" + user + ", " + testResumeID + ", " + it.itemID + ", " + updateBody + ")"},
				want:  resumeWant,
			},
			resumeOp{
				name: "Delete" + it.name, needsLogin: true,
				call: func(ctx context.Context, h *resumeHandlers) (any, error) {
					return it.delete(ctx, h, it.itemID)
				},
				calls: []string{"Delete" + it.name + "(" + user + ", " + testResumeID + ", " + it.itemID + ")"},
				want:  noContent,
			},
		)
	}
	return ops
}

// newFakeResumes は、どの操作も成功する経歴書の処理の代わりを作る。
func newFakeResumes() *fakeResumes {
	return &fakeResumes{
		resume: fullResume(),
		list:   listedResumes(),
		names:  []string{"基本情報技術者試験", "<応用&>"},
		master: fullMaster(),
		export: resume.Export{Body: []byte(fakeExportBody), ContentType: "application/pdf", FileName: "職務経歴書<&>.pdf"},
	}
}

// checkResumeCalls は、経歴書の処理が want の順に呼ばれたことを確かめる。
func checkResumeCalls(t *testing.T, name string, f *fakeResumes, want ...string) {
	t.Helper()
	if len(f.calls) == 0 && len(want) == 0 {
		return
	}
	if !reflect.DeepEqual(f.calls, want) {
		t.Errorf("%s の処理の呼び出し = %q, want %q", name, f.calls, want)
	}
}

// TestResumeHandlers_SuccessResponses は、経歴書の受け口の30の操作が、受け口の節の表のとおりの状態の番号と本文で答える
// ことを確かめる(要件1の受入基準1)。マスタは 200 と名前の並びか4つの大分類、一覧は 200 と id と名前と日時の並び、
// 作成と項目の作成は 201 と経歴書、取得と更新は 200 と経歴書、削除は 204 と空の本文で答える。受け口は、ログインした
// 利用者の ID と、経路の値と、本文を読まずにそのまま処理に渡す。処理が *auth.Error を返せば、Java 版の
// AppExceptionHandler と同じ形で答え、ほかの誤りは、生成したコードの誤りの処理に渡す。ログインした利用者の ID が
// context に無いときは、処理を呼ばずに errNoLoginUser を返す。
func TestResumeHandlers_SuccessResponses(t *testing.T) {
	ops := resumeOps()
	if len(ops) != 30 {
		t.Fatalf("操作の数 = %d, want 30", len(ops))
	}
	business := auth.ErrBusiness("業務の誤りの文言")
	for _, op := range ops {
		for _, secure := range []bool{false, true} {
			name := fmt.Sprintf("%s(secure=%v)", op.name, secure)
			f := newFakeResumes()
			resp, err := op.call(loggedIn(), newResumeHandlers(f, secure))
			checkResponse(t, name+" の成功", handled(t, resp, err), op.want)
			checkResumeCalls(t, name+" の成功", f, op.calls...)

			f = newFakeResumes()
			f.errs = map[string]error{op.name: business}
			resp, err = op.call(loggedIn(), newResumeHandlers(f, secure))
			checkResponse(t, name+" の *auth.Error", handled(t, resp, err), errorWant(t, business, secure))
			checkResumeCalls(t, name+" の *auth.Error", f, op.calls...)

			f = newFakeResumes()
			f.errs = map[string]error{op.name: fmt.Errorf("包む: %w", errTestBoom)}
			if _, err = op.call(loggedIn(), newResumeHandlers(f, secure)); !errors.Is(err, errTestBoom) {
				t.Errorf("%s のほかの誤り = %v, want %v を包んだ誤り", name, err, errTestBoom)
			}
		}
		if !op.needsLogin {
			continue
		}
		f := newFakeResumes()
		if _, err := op.call(context.Background(), newResumeHandlers(f, false)); !errors.Is(err, errNoLoginUser) {
			t.Errorf("%s のログインした利用者の無い context の誤り = %v, want %v", op.name, err, errNoLoginUser)
		}
		checkResumeCalls(t, op.name+" のログインした利用者の無い context", f)
	}
}

// TestResumeHandlers_EmptyLists は、マスタの名前と一覧が空のときに、null でなく空の並びで答えることを確かめる。
// Java 版は、空の結果を空の List で答える。
func TestResumeHandlers_EmptyLists(t *testing.T) {
	for _, op := range resumeOps()[:4] {
		if op.name == "ListTechStacks" {
			continue
		}
		f := newFakeResumes()
		f.names, f.list = nil, nil
		resp, err := op.call(loggedIn(), newResumeHandlers(f, false))
		want := jsonWant(http.StatusOK, `{"names":[]}`)
		if op.name == "ListResumes" {
			want = jsonWant(http.StatusOK, `{"resumes":[]}`)
		}
		checkResponse(t, op.name+" の空の結果", handled(t, resp, err), want)
	}
}

// TestResumeHandlers_OmitEmpty は、経歴書の答えが、Java 版の ResumeInfoResponse の JsonInclude と同じく、値の無い姓と名の
// 鍵を書かず、項目の無い欄の鍵を書かないことを確かめる(要件1の受入基準1)。nil の並びと空の並びのどちらも書かない。
// 空の文字の姓と名は、値があるので書く。
func TestResumeHandlers_OmitEmpty(t *testing.T) {
	r := resume.Resume{
		ID: uuid.MustParse(testResumeID), Name: "空", Date: resume.Date{Year: 2026, Month: time.January, Day: 2},
		CreatedAt: time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC), UpdatedAt: time.Date(2026, 1, 2, 3, 4, 6, 0, time.UTC),
		Careers: []resume.Career{}, Certifications: []resume.Certification{}, SnsPlatforms: []resume.SnsPlatform{},
	}
	f := newFakeResumes()
	f.resume = r
	resp, err := newResumeHandlers(f, false).GetResume(loggedIn(), gen.GetResumeRequestObject{ResumeId: testResumeID})
	checkResponse(t, "値の無い姓と名と項目の無い欄", handled(t, resp, err), jsonWant(http.StatusOK,
		`{"id":"00000000-0000-4000-8000-000000000301","resumeName":"空","date":"2026-01-02",`+
			`"createdAt":"2026-01-02T03:04:05","updatedAt":"2026-01-02T03:04:06"}`))

	r.LastName, r.FirstName = strp(""), strp("名")
	f.resume = r
	resp, err = newResumeHandlers(f, false).GetResume(loggedIn(), gen.GetResumeRequestObject{ResumeId: testResumeID})
	checkResponse(t, "空の文字の姓", handled(t, resp, err), jsonWant(http.StatusOK,
		`{"id":"00000000-0000-4000-8000-000000000301","resumeName":"空","date":"2026-01-02","lastName":"","firstName":"名",`+
			`"createdAt":"2026-01-02T03:04:05","updatedAt":"2026-01-02T03:04:06"}`))
}

// TestResumeHandlers_ProcessSwap は、プロジェクトの工程の答えで、Java 版の ResumeInfoResponse と同じく、systemTest の鍵に
// Maintenance の値を、maintenance の鍵に SystemTest の値を入れることを確かめる(要件1の受入基準1)。ほかの5つの工程は
// 入れ替えない。
func TestResumeHandlers_ProcessSwap(t *testing.T) {
	cases := []struct {
		process resume.Process
		want    string
	}{
		{
			process: resume.Process{SystemTest: true},
			want: `{"requirements":false,"basicDesign":false,"detailedDesign":false,"implementation":false,` +
				`"integrationTest":false,"maintenance":true,"systemTest":false}`,
		},
		{
			process: resume.Process{Maintenance: true},
			want: `{"requirements":false,"basicDesign":false,"detailedDesign":false,"implementation":false,` +
				`"integrationTest":false,"maintenance":false,"systemTest":true}`,
		},
		{
			process: resume.Process{Requirements: true, BasicDesign: true, DetailedDesign: true, Implementation: true, IntegrationTest: true},
			want: `{"requirements":true,"basicDesign":true,"detailedDesign":true,"implementation":true,` +
				`"integrationTest":true,"maintenance":false,"systemTest":false}`,
		},
	}
	for _, c := range cases {
		r := fullResume()
		r.Projects[0].Process = c.process
		f := newFakeResumes()
		f.resume = r
		resp, err := newResumeHandlers(f, false).GetResume(loggedIn(), gen.GetResumeRequestObject{ResumeId: testResumeID})
		got := handled(t, resp, err)
		var body struct {
			Projects []struct {
				Process json.RawMessage `json:"process"`
			} `json:"projects"`
		}
		if err := json.Unmarshal([]byte(got.body), &body); err != nil || len(body.Projects) != 1 {
			t.Fatalf("答えの本文を読めない: %v %s", err, got.body)
		}
		if string(body.Projects[0].Process) != c.want {
			t.Errorf("工程 %+v の答え = %s, want %s", c.process, body.Projects[0].Process, c.want)
		}
	}
}

// TestResumeHandlers_DateTimeFormat は、経歴書の答えの日時を、Java の LocalDateTime を ISO_LOCAL_DATE_TIME で書いた形で
// 書くことを確かめる(要件1の受入基準1)。秒は 0 でも書き、秒より細かい部分は末尾の 0 を落とし、0 なら書かない。
// Service が返した丸める前の値はナノ秒まで、データベースから読んだ値はマイクロ秒まで書く。時間帯は変えず、値の
// 壁時計の時刻を書く。経歴書の作成の答えと、職歴の更新の答えと、経歴書1件の取得の答えで確かめる。
func TestResumeHandlers_DateTimeFormat(t *testing.T) {
	type stamps struct{ created, updated time.Time }
	cases := []struct {
		name  string
		at    stamps
		call  func(ctx context.Context, h *resumeHandlers) (any, error)
		wantC string
		wantU string
	}{
		{
			name: "経歴書の作成(丸める前の値)",
			at: stamps{
				time.Date(2026, 11, 14, 10, 23, 45, 123456500, jst),
				time.Date(2026, 11, 14, 10, 23, 45, 123456500, jst),
			},
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.CreateResume(ctx, gen.CreateResumeRequestObject{Body: bodyOf(`{}`)})
			},
			wantC: "2026-11-14T10:23:45.1234565", wantU: "2026-11-14T10:23:45.1234565",
		},
		{
			name: "職歴の更新(作成はデータベースの値、更新は丸める前の値)",
			at: stamps{
				time.Date(2026, 11, 1, 0, 0, 0, 123457000, time.UTC),
				time.Date(2026, 11, 14, 23, 59, 59, 999999999, jst),
			},
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.UpdateCareer(ctx, gen.UpdateCareerRequestObject{
					ResumeId: testResumeID, CareerId: itemID(401).String(), Body: bodyOf(`{}`),
				})
			},
			wantC: "2026-11-01T00:00:00.123457", wantU: "2026-11-14T23:59:59.999999999",
		},
		{
			name: "経歴書1件の取得(データベースの値)",
			at: stamps{
				time.Date(2026, 11, 2, 9, 5, 0, 0, time.UTC),
				time.Date(2026, 11, 3, 9, 5, 7, 100000000, time.UTC),
			},
			call: func(ctx context.Context, h *resumeHandlers) (any, error) {
				return h.GetResume(ctx, gen.GetResumeRequestObject{ResumeId: testResumeID})
			},
			wantC: "2026-11-02T09:05:00", wantU: "2026-11-03T09:05:07.1",
		},
	}
	for _, c := range cases {
		r := fullResume()
		r.CreatedAt, r.UpdatedAt = c.at.created, c.at.updated
		f := newFakeResumes()
		f.resume = r
		resp, err := c.call(loggedIn(), newResumeHandlers(f, false))
		got := handled(t, resp, err)
		var body struct {
			CreatedAt string `json:"createdAt"`
			UpdatedAt string `json:"updatedAt"`
		}
		if err := json.Unmarshal([]byte(got.body), &body); err != nil {
			t.Fatalf("%s の本文を読めない: %v", c.name, err)
		}
		if body.CreatedAt != c.wantC || body.UpdatedAt != c.wantU {
			t.Errorf("%s の日時 = %q %q, want %q %q", c.name, body.CreatedAt, body.UpdatedAt, c.wantC, c.wantU)
		}
	}
}

// TestResumeHandlers_UnreadableItemID は、項目の ID が UUID として読めない項目の更新と削除の要求で、受け口が ID を読まずに
// 文字のまま処理に渡し、処理が返した無い項目の誤りを、無い項目と同じ 404 と欄ごとの文言で答えることを確かめる
// (要件4の受入基準4)。Java 版は、この要求に 500 で答える(CB-048)。
func TestResumeHandlers_UnreadableItemID(t *testing.T) {
	user := handlerUserID.String()
	for _, it := range itemOps() {
		for _, raw := range []string{"not-a-uuid", "1-2-3-4-5", ""} {
			notFound := &auth.Error{Status: http.StatusNotFound, Message: it.notFound, Errors: map[string][]string{}}
			want := jsonWant(http.StatusNotFound, `{"message":"`+it.notFound+`","errors":{}}`)

			f := newFakeResumes()
			f.errs = map[string]error{"Update" + it.name: notFound}
			resp, err := it.update(loggedIn(), newResumeHandlers(f, false), raw, `{}`)
			checkResponse(t, fmt.Sprintf("%s の更新の ID %q", it.name, raw), handled(t, resp, err), want)
			checkResumeCalls(t, fmt.Sprintf("%s の更新の ID %q", it.name, raw), f,
				"Update"+it.name+"("+user+", "+testResumeID+", "+raw+", {})")

			f = newFakeResumes()
			f.errs = map[string]error{"Delete" + it.name: notFound}
			resp, err = it.delete(loggedIn(), newResumeHandlers(f, false), raw)
			checkResponse(t, fmt.Sprintf("%s の削除の ID %q", it.name, raw), handled(t, resp, err), want)
			checkResumeCalls(t, fmt.Sprintf("%s の削除の ID %q", it.name, raw), f,
				"Delete"+it.name+"("+user+", "+testResumeID+", "+raw+")")
		}
	}
}

// TestResumeResponses_AllOperationsWrite は、経歴書の30の操作の応答のインタフェースのどのメソッドで書いても、状態の番号と、
// Content-Type と、本文を書くことを確かめる。
func TestResumeResponses_AllOperationsWrite(t *testing.T) {
	r := authJSON(http.StatusCreated, map[string]string{"a": "<&>"})
	want := wantResponse{status: http.StatusCreated, contentType: "application/json", body: `{"a":"<&>"}`}
	visits := map[string]func(http.ResponseWriter) error{
		"ListCertificationNames":   r.VisitListCertificationNamesResponse,
		"ListSnsPlatformNames":     r.VisitListSnsPlatformNamesResponse,
		"ListTechStacks":           r.VisitListTechStacksResponse,
		"ListResumes":              r.VisitListResumesResponse,
		"CreateResume":             r.VisitCreateResumeResponse,
		"GetResume":                r.VisitGetResumeResponse,
		"DeleteResume":             r.VisitDeleteResumeResponse,
		"UpdateResumeBasic":        r.VisitUpdateResumeBasicResponse,
		"CreateCareer":             r.VisitCreateCareerResponse,
		"UpdateCareer":             r.VisitUpdateCareerResponse,
		"DeleteCareer":             r.VisitDeleteCareerResponse,
		"CreateProject":            r.VisitCreateProjectResponse,
		"UpdateProject":            r.VisitUpdateProjectResponse,
		"DeleteProject":            r.VisitDeleteProjectResponse,
		"CreateCertification":      r.VisitCreateCertificationResponse,
		"UpdateCertification":      r.VisitUpdateCertificationResponse,
		"DeleteCertification":      r.VisitDeleteCertificationResponse,
		"CreatePortfolio":          r.VisitCreatePortfolioResponse,
		"UpdatePortfolio":          r.VisitUpdatePortfolioResponse,
		"DeletePortfolio":          r.VisitDeletePortfolioResponse,
		"CreateSnsPlatform":        r.VisitCreateSnsPlatformResponse,
		"UpdateSnsPlatform":        r.VisitUpdateSnsPlatformResponse,
		"DeleteSnsPlatform":        r.VisitDeleteSnsPlatformResponse,
		"CreateSelfPromotion":      r.VisitCreateSelfPromotionResponse,
		"UpdateSelfPromotion":      r.VisitUpdateSelfPromotionResponse,
		"DeleteSelfPromotion":      r.VisitDeleteSelfPromotionResponse,
		"ExportResume":             r.VisitExportResumeResponse,
		"ExportResumeWithSettings": r.VisitExportResumeWithSettingsResponse,
		"BackupResume":             r.VisitBackupResumeResponse,
		"RestoreResume":            r.VisitRestoreResumeResponse,
	}
	if len(visits) != 30 {
		t.Fatalf("メソッドの数 = %d, want 30", len(visits))
	}
	for name, visit := range visits {
		checkResponse(t, name, recordResponse(t, visit), want)
	}
}

// routeCSRF は、経路のテストで、偽の送信の検査に通す Cookie とヘッダの値である。
const routeCSRF = "resume-route-csrf"

// resumeServer は、認証のまとまりと経歴書の処理 svc をつないだ受け口を、userID の利用者がログインした状態で作る。
// svc が nil なら ResumeHandlers を渡さない。認証の処理には、つながらないデータベースを渡す。
func resumeServer(t *testing.T, svc ResumeService, userID uuid.UUID) http.Handler {
	t.Helper()
	pool, err := pgxpool.New(t.Context(), "postgres://keirekipro@127.0.0.1:1/keirekipro?connect_timeout=2")
	if err != nil {
		t.Fatalf("接続の束を作れません: %v", err)
	}
	t.Cleanup(pool.Close)
	return New(Options{
		Logger: slog.New(slog.DiscardHandler),
		Identify: func(next http.Handler) http.Handler {
			return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				next.ServeHTTP(w, r.WithContext(authctx.With(r.Context(), userID, []string{"USER"})))
			})
		},
		Auth: auth.RequireLogin(),
		AuthHandlers: auth.New(auth.Deps{
			Pool: pool, JWT: config.JWT{Secret: strings.Repeat("k", 64), AccessTokenValidity: time.Hour},
		}),
		ResumeHandlers: svc,
	})
}

// sendRoute は、偽の送信の検査に通る Cookie とヘッダを付けて、要求を1つ送る。body が nil なら本文を付けない。
// accept の値は、1つずつ Accept の行にする。
func sendRoute(h http.Handler, method, path string, body *string, accept ...string) *httptest.ResponseRecorder {
	var reader io.Reader
	if body != nil {
		reader = strings.NewReader(*body)
	}
	req := httptest.NewRequest(method, path, reader)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Cookie", "XSRF-TOKEN="+routeCSRF)
	req.Header.Set("X-XSRF-TOKEN", routeCSRF)
	for _, a := range accept {
		req.Header.Add("Accept", a)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// resumeRoute は、経歴書の30の操作の1つの、仕様書の経路への要求と、経歴書の処理の呼び出しである。
type resumeRoute struct {
	name, method, path, body, call string
}

// accept は、要求の Accept の行である。設定を付けない出力は、画面と同じ Accept の行を付けて送る。
func (rt resumeRoute) accept() []string {
	if rt.name == "ExportResume" {
		return []string{screenMarkdownAccept}
	}
	return nil
}

// resumeRoutes は、経歴書の30の操作の要求を、resumeOps と同じ名前で返す。
func resumeRoutes() []resumeRoute {
	user := handlerUserID.String()
	base := "/api/resumes/" + testResumeID
	routes := []resumeRoute{
		{"ListCertificationNames", http.MethodGet, "/api/certifications", "", "ListCertificationNames()"},
		{"ListSnsPlatformNames", http.MethodGet, "/api/sns-platforms", "", "ListSnsPlatformNames()"},
		{"ListTechStacks", http.MethodGet, "/api/tech-stacks", "", "ListTechStacks()"},
		{"ListResumes", http.MethodGet, "/api/resumes", "", "ListResumes(" + user + ")"},
		{
			"CreateResume", http.MethodPost, "/api/resumes", `{"resumeName":"作成"}`,
			"CreateResume(" + user + `, {"resumeName":"作成"})`,
		},
		{"GetResume", http.MethodGet, base, "", "GetResume(" + user + ", " + testResumeID + ")"},
		{"DeleteResume", http.MethodDelete, base, "", "DeleteResume(" + user + ", " + testResumeID + ")"},
		{
			"UpdateResumeBasic", http.MethodPut, base + "/basic", `{"date":"2026-11-14"}`,
			"UpdateResumeBasic(" + user + ", " + testResumeID + `, {"date":"2026-11-14"})`,
		},
		{"ExportResume", http.MethodGet, base + "/export", "", "ExportResume(" + user + ", " + testResumeID + ", markdown)"},
		{
			"ExportResumeWithSettings", http.MethodPost, base + "/export", `{"format":"pdf"}`,
			"ExportResumeWithSettings(" + user + ", " + testResumeID + `, {"format":"pdf"})`,
		},
		{"BackupResume", http.MethodGet, base + "/backup", "", "BackupResume(" + user + ", " + testResumeID + ")"},
		{
			"RestoreResume", http.MethodPost, "/api/resumes/restore", `{"version":"1.0"}`,
			"RestoreResume(" + user + `, {"version":"1.0"})`,
		},
	}
	segments := map[string]string{
		"Career": "careers", "Project": "projects", "Certification": "certifications",
		"Portfolio": "portfolios", "SnsPlatform": "sns-platforms", "SelfPromotion": "self-promotions",
	}
	for _, it := range itemOps() {
		list := base + "/" + segments[it.name]
		item := list + "/" + it.itemID
		createBody := `{"create":"` + it.name + `"}`
		updateBody := `{"update":"` + it.name + `"}`
		routes = append(routes,
			resumeRoute{
				"Create" + it.name, http.MethodPost, list, createBody,
				"Create" + it.name + "(" + user + ", " + testResumeID + ", " + createBody + ")",
			},
			resumeRoute{
				"Update" + it.name, http.MethodPut, item, updateBody,
				"Update" + it.name + "(" + user + ", " + testResumeID + ", " + it.itemID + ", " + updateBody + ")",
			},
			resumeRoute{
				"Delete" + it.name, http.MethodDelete, item, "",
				"Delete" + it.name + "(" + user + ", " + testResumeID + ", " + it.itemID + ")",
			},
		)
	}
	return routes
}

// TestResumeRoutes_Wired は、New に ResumeHandlers を渡すと、仕様書の経路への30の操作の要求が経歴書の受け口に届き、
// 受け口の答えで答えることを確かめる(要件1の受入基準2)。
func TestResumeRoutes_Wired(t *testing.T) {
	wants := map[string]wantResponse{}
	for _, op := range resumeOps() {
		wants[op.name] = op.want
	}
	routes := resumeRoutes()
	if len(routes) != 30 || len(wants) != 30 {
		t.Fatalf("操作の数 = 経路 %d、受け口 %d, want 30", len(routes), len(wants))
	}
	for _, rt := range routes {
		t.Run(rt.name, func(t *testing.T) {
			want, ok := wants[rt.name]
			if !ok {
				t.Fatalf("操作 %s が resumeOps に無い", rt.name)
			}
			svc := newFakeResumes()
			rec := sendRoute(resumeServer(t, svc, handlerUserID), rt.method, rt.path, &rt.body, rt.accept()...)
			if rec.Code != want.status || rec.Body.String() != want.body {
				t.Errorf("応答 = %d %s, want %d %s", rec.Code, rec.Body.String(), want.status, want.body)
			}
			if want.contentType != "" && rec.Header().Get("Content-Type") != want.contentType {
				t.Errorf("Content-Type = %q, want %q", rec.Header().Get("Content-Type"), want.contentType)
			}
			checkResumeCalls(t, rt.name, svc, rt.call)
		})
	}
}

// TestResumeRoutes_Unimplemented は、New に ResumeHandlers を渡さなければ、マスタと経歴書の30の操作の要求に、
// 今と同じ未実装の答えを返すことを確かめる。
func TestResumeRoutes_Unimplemented(t *testing.T) {
	handler := resumeServer(t, nil, handlerUserID)
	for _, rt := range resumeRoutes() {
		rec := sendRoute(handler, rt.method, rt.path, &rt.body, rt.accept()...)
		if rec.Code != http.StatusNotImplemented || rec.Body.String() != `{"message":"未実装です。"}` {
			t.Errorf("%s の応答 = %d %s, want 501 と未実装の本文", rt.name, rec.Code, rec.Body.String())
		}
	}
}

// wholeBodyCase は、testdata/resumebody/cases.json の1つの本文と、Java 版の答えである。
type wholeBodyCase struct {
	Name     string                    `json:"name"`
	Endpoint string                    `json:"endpoint"`
	Body     *string                   `json:"body"`
	Status   int                       `json:"status"`
	Response any                       `json:"response"`
	DB       map[string]map[string]any `json:"db"`
}

// wholeBodyDiffs は、cases.json の本文のうち、Go 版の答えが Java 版と違う本文と、違いを載せた一覧の番号である。
// Java 版は本文の全体が null の要求を断るが、Go 版は encoding/json のとおりにすべての欄の値が無いことにして、
// 入力の検査の誤りで答える(CB-054)。
var wholeBodyDiffs = map[string]string{
	"resume-null": "CB-054",
	"career-null": "CB-054",
}

// wholeBodyTables は、正解の db に書かれた表の、ログインした利用者の行を選ぶ問い合わせである。
var wholeBodyTables = map[string]string{
	"resumes": "SELECT to_jsonb(t) FROM resumes t WHERE t.user_id = $1",
	"careers": "SELECT to_jsonb(t) FROM careers t JOIN resumes r ON r.id = t.resume_id WHERE r.user_id = $1",
}

// TestResumeRoutes_WholeBody は、New で作った経路に、最初の値のあとに余りのある本文、空の本文、並びと null と文字列の
// 本文を送り、Java 版の答えと比べる(要件1の受入基準1)。本文の全体の扱いは、internal/resume の本文の読み手ではなく、
// 生成したコードが決める。Java 版と違う答えになる本文が wholeBodyDiffs と合うこと、表の番号が変えた動きの一覧に
// あること、ほかの本文に Java 版と同じ状態の番号と本文で答え、同じ行をデータベースに書くことを確かめる。
func TestResumeRoutes_WholeBody(t *testing.T) {
	b, err := os.ReadFile("testdata/resumebody/cases.json")
	if err != nil {
		t.Fatal(err)
	}
	var file struct {
		Cases []wholeBodyCase `json:"cases"`
	}
	if err := json.Unmarshal(b, &file); err != nil {
		t.Fatal(err)
	}
	checkWholeBodyDiffTable(t, file.Cases)
	pool := startResumeDB(t)
	svc := resume.New(resume.Deps{Pool: pool, Now: time.Now})
	for _, c := range file.Cases {
		t.Run(c.Name, func(t *testing.T) {
			userID, resumeID := seedWholeBody(t, pool, c.Endpoint)
			method, path, _ := strings.Cut(strings.ReplaceAll(c.Endpoint, "{resumeId}", resumeID), " ")
			before := time.Now().In(jst).Format(time.DateOnly)
			rec := sendRoute(resumeServer(t, svc, userID), method, path, c.Body)
			after := time.Now().In(jst).Format(time.DateOnly)
			diffs := wholeBodyDiff(t, pool, c, rec, userID, resumeID, before, after)
			id, listed := wholeBodyDiffs[c.Name]
			switch {
			case len(diffs) > 0 && !listed:
				t.Errorf("Java 版と違うのに表に無い: %s", strings.Join(diffs, "; "))
			case len(diffs) == 0 && listed:
				t.Errorf("表に %s で載っているのに、Java 版と同じ答え", id)
			}
		})
	}
}

// checkWholeBodyDiffTable は、wholeBodyDiffs の本文が cases.json にあり、番号が変えた動きの一覧にあることを確かめる。
func checkWholeBodyDiffTable(t *testing.T, cases []wholeBodyCase) {
	t.Helper()
	names := map[string]bool{}
	for _, c := range cases {
		names[c.Name] = true
	}
	for name := range wholeBodyDiffs {
		if !names[name] {
			t.Errorf("表の本文 %s が cases.json に無い", name)
		}
	}
	b, err := os.ReadFile("../../compat/changed-behaviors.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var items []struct {
		ID string `yaml:"id"`
	}
	if err := yaml.Unmarshal(b, &items); err != nil {
		t.Fatal(err)
	}
	known := map[string]bool{}
	for _, it := range items {
		known[it.ID] = true
	}
	for name, id := range wholeBodyDiffs {
		if !known[id] {
			t.Errorf("本文 %s の番号 %q は、変えた動きの一覧に無い", name, id)
		}
	}
}

// wholeBodyDiff は、Go 版の答えと書いた行を、Java 版の答えと比べ、違いを返す。答えの本文は、作成と更新の日時を除き、
// 経歴書の ID を <resumeId>、ほかの ID を <itemId>、今日の日付を <today> に置き換えて比べる。
func wholeBodyDiff(
	t *testing.T, pool *pgxpool.Pool, c wholeBodyCase, rec *httptest.ResponseRecorder,
	userID uuid.UUID, resumeID, before, after string,
) []string {
	t.Helper()
	var diffs []string
	if rec.Code != c.Status {
		diffs = append(diffs, fmt.Sprintf("状態の番号 = %d, want %d", rec.Code, c.Status))
	}
	var got any
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		return append(diffs, fmt.Sprintf("本文 %q を JSON として読めない", rec.Body.String()))
	}
	if m, ok := got.(map[string]any); ok {
		delete(m, "createdAt")
		delete(m, "updatedAt")
		if id, ok := m["id"].(string); ok && resumeID == "" {
			resumeID = id
		}
	}
	got = maskWholeBody(got, resumeID, before, after)
	if !reflect.DeepEqual(got, c.Response) {
		gotJSON, _ := json.Marshal(got)
		wantJSON, _ := json.Marshal(c.Response)
		diffs = append(diffs, fmt.Sprintf("本文 = %s, want %s", gotJSON, wantJSON))
	}
	if rec.Code != http.StatusCreated {
		return diffs
	}
	for table, want := range c.DB {
		query, ok := wholeBodyTables[table]
		if !ok {
			t.Fatalf("表 %s の行の選び方が無い", table)
		}
		var row map[string]any
		if err := pool.QueryRow(t.Context(), query, userID).Scan(&row); err != nil {
			t.Fatalf("表 %s の行を読めません: %v", table, err)
		}
		for column, v := range want {
			if !reflect.DeepEqual(row[column], v) {
				diffs = append(diffs, fmt.Sprintf("%s.%s = %v, want %v", table, column, row[column], v))
			}
		}
	}
	return diffs
}

// maskWholeBody は、答えの本文の値のうち、経歴書の ID と、ほかの UUID と、今日の日付を、正解のファイルの置き換えの形にする。
func maskWholeBody(v any, resumeID, before, after string) any {
	switch x := v.(type) {
	case map[string]any:
		for k, e := range x {
			x[k] = maskWholeBody(e, resumeID, before, after)
		}
	case []any:
		for i, e := range x {
			x[i] = maskWholeBody(e, resumeID, before, after)
		}
	case string:
		if x == resumeID {
			return "<resumeId>"
		}
		if _, err := uuid.Parse(x); err == nil {
			return "<itemId>"
		}
		if x == before || x == after {
			return "<today>"
		}
	}
	return v
}

// seedWholeBody は、本文ごとに新しい利用者を足す。職歴の追加の本文なら、Java 版に送ったときと同じ、項目の無い
// 経歴書も足し、その ID を返す。
func seedWholeBody(t *testing.T, pool *pgxpool.Pool, endpoint string) (uuid.UUID, string) {
	t.Helper()
	userID := uuid.New()
	if _, err := pool.Exec(t.Context(),
		`INSERT INTO users (id, created_at, updated_at) VALUES ($1, now(), now())`, userID); err != nil {
		t.Fatalf("利用者の行を足せません: %v", err)
	}
	if !strings.Contains(endpoint, "{resumeId}") {
		return userID, ""
	}
	resumeID := uuid.New()
	if _, err := pool.Exec(t.Context(),
		`INSERT INTO resumes (id, user_id, name, date, last_name, first_name, created_at, updated_at)
		 VALUES ($1, $2, '控えの経歴書', '1900-01-01', '山田', '太郎', now(), now())`, resumeID, userID); err != nil {
		t.Fatalf("経歴書の行を足せません: %v", err)
	}
	return userID, resumeID.String()
}

// startResumeDB は、テストの Postgres を動かし、backend.Migrations() のマイグレーションを流して表を作る。
// Docker が無いときは、テストを飛ばさずに失敗させる。
func startResumeDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ctx := t.Context()
	pg, err := postgres.Run(ctx, "postgres:17.11-alpine",
		postgres.WithDatabase("keireki_pro"),
		postgres.WithUsername("postgres"),
		postgres.WithPassword("postgres"),
		postgres.BasicWaitStrategies(),
	)
	t.Cleanup(func() {
		if err := testcontainers.TerminateContainer(pg); err != nil {
			t.Errorf("Postgres のコンテナを止められません: %v", err)
		}
	})
	if err != nil {
		t.Fatalf("Postgres のコンテナを動かせません: %v", err)
	}
	endpoint, err := pg.PortEndpoint(ctx, "5432/tcp", "")
	if err != nil {
		t.Fatalf("テストの Postgres のつなぎ先を読めません: %v", err)
	}
	host, portText, err := net.SplitHostPort(endpoint)
	if err != nil {
		t.Fatalf("つなぎ先 %s を読めません: %v", endpoint, err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		t.Fatalf("ポート %s を読めません: %v", portText, err)
	}
	pool, err := database.Open(ctx, database.Options{
		Host: host, Port: port, Database: "keireki_pro", User: "postgres", Password: "postgres",
	})
	if err != nil {
		t.Fatalf("Postgres につなげません: %v", err)
	}
	t.Cleanup(pool.Close)
	files, err := backend.Migrations()
	if err != nil {
		t.Fatalf("マイグレーションのファイルを読めません: %v", err)
	}
	if _, err := migrate.Run(ctx, pool, files, migrate.Apply); err != nil {
		t.Fatalf("マイグレーションを流せません: %v", err)
	}
	return pool
}

// screenMarkdownAccept は、画面が設定を付けない出力で送る Accept の行である。
const screenMarkdownAccept = "text/markdown, application/json"

// fakeExportBody は、偽の処理が返す出力の本文である。受け口が本文を読まずに書くことを確かめるため、UTF-8 として
// 読めないバイトを入れる。
const fakeExportBody = "%PDF-1.7\n\x00\xff出力"

// withAccept は、authRequestMiddleware が Accept の行 lines を入れた context を返す。
func withAccept(ctx context.Context, lines ...string) context.Context {
	return context.WithValue(ctx, authRequestKey{}, authRequestInfo{accept: lines})
}

// exportAcceptCase は、設定を付けない出力の Accept の行と、Go 版が選ぶ形式である。want が空なら 406 で答える。
// accept が nil なら Accept の行を付けない。
type exportAcceptCase struct {
	name   string
	accept []string
	want   resume.ExportFormat
}

// javaExportFormat は、Java 版の ExportResumeController の形式の選び方を写したものである。Accept の1行の字の並びに
// application/pdf が含まれれば PDF、含まれず text/markdown が含まれれば Markdown を選び、どちらも無ければ空を返す。
// Accept の行が無いときは、空の字の並びとして読む。
func javaExportFormat(t *testing.T, accept []string) resume.ExportFormat {
	t.Helper()
	if len(accept) > 1 {
		t.Fatalf("Java 版の読み方は Accept の1行で比べる: %q", accept)
	}
	line := strings.Join(accept, "")
	switch {
	case strings.Contains(line, "application/pdf"):
		return resume.ExportPDF
	case strings.Contains(line, "text/markdown"):
		return resume.ExportMarkdown
	}
	return ""
}

// TestExportHandlers_AcceptSelectsFormat は、設定を付けない出力の受け口が、Accept の行を型の並びとして読み、型が
// application/pdf の値があれば PDF、無くて型が text/markdown の値があれば Markdown を選んで処理を呼ぶことを確かめる
// (要件1の受入基準1)。どちらも無いときと、Accept の行を読めないときは、経歴書を読まずに 406 と
// 「対応していない形式が指定されました。」で答える。sameAsJava の行は Java 版と同じ形式を選ぶ。cb059 の行は、
// 変えた動きの一覧の CB-059 の、Java 版と違う読み方になる行で、Java 版と違う形式を選ぶ(要件1の受入基準2)。
// goOnly の行は、Accept の行が2つある要求で、Go 版は行をすべて読む。
func TestExportHandlers_AcceptSelectsFormat(t *testing.T) {
	sameAsJava := []exportAcceptCase{
		{"画面の Markdown", []string{screenMarkdownAccept}, resume.ExportMarkdown},
		{"PDF", []string{"application/pdf, application/json"}, resume.ExportPDF},
		{"PDF だけ", []string{"application/pdf"}, resume.ExportPDF},
		{"Markdown が先でも PDF", []string{"text/markdown, application/pdf"}, resume.ExportPDF},
		{"引数の付いた Markdown", []string{"text/markdown;charset=utf-8"}, resume.ExportMarkdown},
		{"q が0の PDF", []string{"application/pdf;q=0"}, resume.ExportPDF},
		{"前後に空白", []string{"  application/pdf  "}, resume.ExportPDF},
		{"Accept が無い", nil, ""},
		{"空の Accept", []string{""}, ""},
		{"*/*", []string{"*/*"}, ""},
		{"application/json だけ", []string{"application/json"}, ""},
		{"application/*", []string{"application/*"}, ""},
		{"text/*", []string{"text/*"}, ""},
	}
	cb059 := []exportAcceptCase{
		{"大文字の PDF", []string{"APPLICATION/PDF"}, resume.ExportPDF},
		{"大文字の混じる Markdown", []string{"Text/Markdown"}, resume.ExportMarkdown},
		{"application/pdf で始まる別の型", []string{"application/pdfa"}, ""},
		{"application/pdf で終わる別の型", []string{"x-application/pdf"}, ""},
		{"text/markdown で始まる別の型", []string{"text/markdown-x"}, ""},
		{"引数の値に書いた PDF", []string{`text/plain;note="application/pdf"`}, ""},
		{"読めない型の付いた PDF", []string{"application/pdf, application"}, ""},
		{"読めない型の付いた Markdown", []string{"text/markdown, @"}, ""},
		{"51の型", []string{strings.Repeat("text/plain, ", 50) + "application/pdf"}, ""},
	}
	goOnly := []exportAcceptCase{
		{"2行目の PDF", []string{"text/plain", "application/pdf"}, resume.ExportPDF},
		{"2行目の Markdown", []string{"application/json", "text/markdown"}, resume.ExportMarkdown},
		{"2行目が読めない", []string{"application/pdf", "@"}, ""},
	}
	for _, c := range sameAsJava {
		if got := javaExportFormat(t, c.accept); got != c.want {
			t.Errorf("%s: Java 版の形式 = %q, want %q(Java 版と同じ読み方の行)", c.name, got, c.want)
		}
	}
	for _, c := range cb059 {
		if got := javaExportFormat(t, c.accept); got == c.want {
			t.Errorf("%s: Java 版の形式 = %q が Go 版と同じ(CB-059 の行は Java 版と違う読み方の行)", c.name, got)
		}
	}
	user := handlerUserID.String()
	notAcceptable := jsonWant(http.StatusNotAcceptable, `{"message":"対応していない形式が指定されました。","errors":{}}`)
	cases := append(append(append([]exportAcceptCase{}, sameAsJava...), cb059...), goOnly...)
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := newFakeResumes()
			resp, err := newResumeHandlers(f, false).ExportResume(
				withAccept(loggedIn(), c.accept...), gen.ExportResumeRequestObject{ResumeId: testResumeID},
			)
			got := handled(t, resp, err)
			if c.want == "" {
				checkResponse(t, c.name, got, notAcceptable)
				checkResumeCalls(t, c.name, f)
				return
			}
			checkResponse(t, c.name, got, wantResponse{status: http.StatusOK, contentType: "application/pdf", body: fakeExportBody})
			checkResumeCalls(t, c.name, f, "ExportResume("+user+", "+testResumeID+", "+string(c.want)+")")
		})
	}
}

// TestExportHandlers_SuccessHeaders は、出力の2つの受け口が、処理が返した出力を、状態の番号 200 と、出力の
// Content-Type と、出し方とファイル名から作った Content-Disposition と、出力の本文で答えることを確かめる
// (要件1の受入基準1)。
func TestExportHandlers_SuccessHeaders(t *testing.T) {
	ops := map[string]func(ctx context.Context, h *resumeHandlers) (any, error){
		"ExportResume": func(ctx context.Context, h *resumeHandlers) (any, error) {
			return h.ExportResume(withAccept(ctx, "application/pdf, application/json"), gen.ExportResumeRequestObject{ResumeId: testResumeID})
		},
		"ExportResumeWithSettings": func(ctx context.Context, h *resumeHandlers) (any, error) {
			return h.ExportResumeWithSettings(ctx, gen.ExportResumeWithSettingsRequestObject{ResumeId: testResumeID, Body: bodyOf(`{}`)})
		},
	}
	exports := []resume.Export{
		{Body: []byte(fakeExportBody), ContentType: "application/pdf", FileName: `職務 "経歴" \書.pdf`, Inline: true},
		{Body: []byte(fakeExportBody), ContentType: "application/pdf", FileName: "resume.pdf"},
		{Body: []byte("# 経歴書\n"), ContentType: "text/markdown;charset=utf-8", FileName: "経歴書.md"},
	}
	kinds := map[bool]string{true: "inline;", false: "attachment;"}
	for name, call := range ops {
		for _, e := range exports {
			label := fmt.Sprintf("%s(%s, inline=%v)", name, e.FileName, e.Inline)
			f := newFakeResumes()
			f.export = e
			resp, err := call(loggedIn(), newResumeHandlers(f, false))
			if err != nil {
				t.Fatalf("%s が誤りを返した: %v", label, err)
			}
			r, ok := resp.(authResponse)
			if !ok {
				t.Fatalf("%s の答えの型 = %T, want authResponse", label, resp)
			}
			rec := httptest.NewRecorder()
			if err := r.write(rec); err != nil {
				t.Fatalf("%s の答えを書けない: %v", label, err)
			}
			if rec.Code != http.StatusOK {
				t.Errorf("%s の状態の番号 = %d, want 200", label, rec.Code)
			}
			if got := rec.Header().Values("Content-Type"); !reflect.DeepEqual(got, []string{e.ContentType}) {
				t.Errorf("%s の Content-Type = %q, want %q", label, got, e.ContentType)
			}
			want := formatContentDisposition(e.Inline, e.FileName)
			if !strings.HasPrefix(want, kinds[e.Inline]) {
				t.Fatalf("%s の期待する Content-Disposition = %q の出し方が違う", label, want)
			}
			if got := rec.Header().Values("Content-Disposition"); !reflect.DeepEqual(got, []string{want}) {
				t.Errorf("%s の Content-Disposition = %q, want %q", label, got, want)
			}
			if rec.Body.String() != string(e.Body) {
				t.Errorf("%s の本文 = %q, want %q", label, rec.Body.String(), e.Body)
			}
		}
	}
}

// TestExportHandlers_RejectWithoutJSONAccept は、設定を付けた出力で、本文が断る条件に当たる要求に、Accept の行に
// application/json が無いときも、画面と同じ Accept の行のときと同じく、400 と、断る文言を入れた JSON の本文で答える
// ことを確かめる(要件1の受入基準2、変えた動きの一覧の CB-060)。Java 版は、application/json の無い Accept の行には
// 401 と空の本文で答える。処理は本物の *resume.Service で、本文を経歴書より先に確かめるので、データベースを読まない。
func TestExportHandlers_RejectWithoutJSONAccept(t *testing.T) {
	h := resumeServer(t, resume.New(resume.Deps{}), handlerUserID)
	path := "/api/resumes/" + testResumeID + "/export"
	body := `{"format":"pdf","disposition":"inline"}`
	screen := sendRoute(h, http.MethodPost, path, &body, "application/pdf, application/json")
	if screen.Code != http.StatusBadRequest || screen.Header().Get("Content-Type") != "application/json" ||
		!strings.HasPrefix(screen.Body.String(), `{"message":"`) {
		t.Fatalf("画面と同じ Accept の答え = %d %q %s, want 400 と JSON の本文",
			screen.Code, screen.Header().Get("Content-Type"), screen.Body.String())
	}
	accepts := [][]string{{"application/pdf"}, {"text/markdown"}, {"application/pdf, text/markdown"}, {"image/*"}, nil}
	for _, accept := range accepts {
		rec := sendRoute(h, http.MethodPost, path, &body, accept...)
		if rec.Code != screen.Code || rec.Header().Get("Content-Type") != screen.Header().Get("Content-Type") ||
			rec.Body.String() != screen.Body.String() {
			t.Errorf("Accept %q の答え = %d %q %s, want %d %q %s", accept, rec.Code, rec.Header().Get("Content-Type"),
				rec.Body.String(), screen.Code, screen.Header().Get("Content-Type"), screen.Body.String())
		}
	}
}

// TestBackupHandlers_BackupResponse は、書き出しの受け口が、処理が返したバックアップのファイルを、状態の番号 200 と、
// application/json と、attachment の Content-Disposition と、ファイルの本文で答えることを確かめる(要件1の受入基準1)。
// Content-Disposition のファイル名は、出力の受け口と同じく、処理が経歴書の名前から作ったファイル名から、Java 版と
// 同じ規則で作る(要件3の受入基準4)。受け口は Accept の行を見ないので、Accept の行に application/json が無くても、
// 同じ答えを返す。
func TestBackupHandlers_BackupResponse(t *testing.T) {
	names := []string{"職務経歴書_backup.json", `職務 "経歴" \書<&>_backup.json`, "resume_backup.json"}
	accepts := [][]string{nil, {"application/json"}, {"text/html"}, {"application/pdf", "text/markdown"}}
	body := `{"version":"1.0","exportedAt":"2026-11-24T00:00:00Z","resume":{"resumeName":"<&>"}}`
	for _, name := range names {
		want := formatContentDisposition(false, name)
		if !strings.HasPrefix(want, "attachment;") {
			t.Fatalf("期待する Content-Disposition = %q の出し方が attachment でない", want)
		}
		for _, accept := range accepts {
			label := fmt.Sprintf("%s(Accept %q)", name, accept)
			f := newFakeResumes()
			f.export = resume.Export{Body: []byte(body), ContentType: "application/json", FileName: name}
			resp, err := newResumeHandlers(f, false).BackupResume(
				withAccept(loggedIn(), accept...), gen.BackupResumeRequestObject{ResumeId: testResumeID},
			)
			if err != nil {
				t.Fatalf("%s が誤りを返した: %v", label, err)
			}
			r, ok := resp.(authResponse)
			if !ok {
				t.Fatalf("%s の答えの型 = %T, want authResponse", label, resp)
			}
			rec := httptest.NewRecorder()
			if err := r.write(rec); err != nil {
				t.Fatalf("%s の答えを書けない: %v", label, err)
			}
			if rec.Code != http.StatusOK {
				t.Errorf("%s の状態の番号 = %d, want 200", label, rec.Code)
			}
			if got := rec.Header().Values("Content-Type"); !reflect.DeepEqual(got, []string{"application/json"}) {
				t.Errorf("%s の Content-Type = %q, want application/json", label, got)
			}
			if got := rec.Header().Values("Content-Disposition"); !reflect.DeepEqual(got, []string{want}) {
				t.Errorf("%s の Content-Disposition = %q, want %q", label, got, want)
			}
			if rec.Body.String() != body {
				t.Errorf("%s の本文 = %q, want %q", label, rec.Body.String(), body)
			}
			checkResumeCalls(t, label, f, "BackupResume("+handlerUserID.String()+", "+testResumeID+")")
		}
	}
}

// TestBackupHandlers_RestoreResponse は、戻しの受け口が、処理が戻した経歴書を、状態の番号 201 と、application/json と、
// JavaJSON で書いた経歴書の答えの本文で答えることを確かめる(要件1の受入基準1)。経歴書の名前と項目の字に、対に
// なっていないサロゲートがあるときも、Java 版と同じく、U+FFFD に置き換えずに番号で書く。
func TestBackupHandlers_RestoreResponse(t *testing.T) {
	lone := fullResume()
	lone.Name = "経歴\xed\xa0\x80書<&>"
	lone.Careers[0].CompanyName = "会社\xed\xb0\x80"
	cases := []struct {
		name     string
		r        resume.Resume
		want     string
		contains []string
	}{
		{name: "経歴書", r: fullResume(), want: fullResumeJSON},
		{
			name: "対になっていないサロゲートを含む経歴書", r: lone, want: string(resume.JavaJSON(newResumeBody(lone))),
			contains: []string{`"resumeName":"経歴\uD800書<&>"`, `"companyName":"会社\uDC00"`},
		},
	}
	for _, c := range cases {
		f := newFakeResumes()
		f.resume = c.r
		resp, err := newResumeHandlers(f, false).RestoreResume(
			loggedIn(), gen.RestoreResumeRequestObject{Body: bodyOf(`{"version":"1.0"}`)},
		)
		got := handled(t, resp, err)
		checkResponse(t, c.name, got, jsonWant(http.StatusCreated, c.want))
		for _, s := range c.contains {
			if !strings.Contains(got.body, s) {
				t.Errorf("%s の本文 %s に %s が無い", c.name, got.body, s)
			}
		}
		if strings.ContainsRune(got.body, utf8.RuneError) {
			t.Errorf("%s の本文 %s に U+FFFD がある", c.name, got.body)
		}
		checkResumeCalls(t, c.name, f, "RestoreResume("+handlerUserID.String()+`, {"version":"1.0"})`)
	}
}
