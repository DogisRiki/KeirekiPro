package resume

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// backupVersion は、バックアップのファイルの版である。Java 版の ResumeBackupVersion.SUPPORTED_VERSION と同じである。
const backupVersion = "1.0"

// contentTypeBackup は、書き出しの結果の Content-Type である。Java 版の MediaType.APPLICATION_JSON_VALUE と同じである。
const contentTypeBackup = "application/json"

// backupFileSuffix は、経歴書の名前から作った名前のあとに付ける、バックアップのファイル名の終わりである。
const backupFileSuffix = "_backup.json"

// errBackupDate は、経歴書に、年が 1 から 9999 の外の日付か年月があるときの誤りである。
// Java 版の LocalDate と YearMonth は、この範囲の外の年を4桁の形で書かないので、Go 版は書き出さずに 500 で答える。
// 画面の保存の決まりで、この範囲の外の年は入らない。
var errBackupDate = errors.New("resume: 年が 1 から 9999 の外の日付か年月があるので、バックアップのファイルに書けない")

// bkFile は、バックアップのファイルである。Java 版の BackupResumeResponse の欄の名前と並びを写した。
type bkFile struct {
	Version    string   `json:"version"`
	ExportedAt string   `json:"exportedAt"`
	Resume     bkResume `json:"resume"`
}

// bkResume は、バックアップのファイルの経歴書である。Java 版の BackupResumeResponse.ResumeDto を写した。
// 姓と名は、無ければ書かない。6つの欄は、項目が無ければ書かない。
type bkResume struct {
	ResumeName     string            `json:"resumeName"`
	Date           string            `json:"date"`
	LastName       *string           `json:"lastName,omitempty"`
	FirstName      *string           `json:"firstName,omitempty"`
	Careers        []bkCareer        `json:"careers,omitempty"`
	Projects       []bkProject       `json:"projects,omitempty"`
	Certifications []bkCertification `json:"certifications,omitempty"`
	Portfolios     []bkPortfolio     `json:"portfolios,omitempty"`
	SnsPlatforms   []bkSnsPlatform   `json:"snsPlatforms,omitempty"`
	SelfPromotions []bkSelfPromotion `json:"selfPromotions,omitempty"`
}

// bkCareer は、職歴の項目である。終わりの年月は、無ければ書かない。
type bkCareer struct {
	CompanyName string  `json:"companyName"`
	StartDate   string  `json:"startDate"`
	EndDate     *string `json:"endDate,omitempty"`
	Active      bool    `json:"active"`
}

// bkProject は、プロジェクトの項目である。終わりの年月は、無ければ書かない。
type bkProject struct {
	CompanyName string      `json:"companyName"`
	StartDate   string      `json:"startDate"`
	EndDate     *string     `json:"endDate,omitempty"`
	Active      bool        `json:"active"`
	Name        string      `json:"name"`
	Overview    string      `json:"overview"`
	TeamComp    string      `json:"teamComp"`
	Role        string      `json:"role"`
	Achievement string      `json:"achievement"`
	Process     bkProcess   `json:"process"`
	TechStack   bkTechStack `json:"techStack"`
}

// bkProcess は、プロジェクトの作業の工程である。欄は Process と同じ並びなので、Process から型の変換で作る。
type bkProcess struct {
	Requirements    bool `json:"requirements"`
	BasicDesign     bool `json:"basicDesign"`
	DetailedDesign  bool `json:"detailedDesign"`
	Implementation  bool `json:"implementation"`
	IntegrationTest bool `json:"integrationTest"`
	SystemTest      bool `json:"systemTest"`
	Maintenance     bool `json:"maintenance"`
}

// bkTechStack は、プロジェクトの技術スタックである。大分類4つは、小分類がすべて無くても {} と書く。
type bkTechStack struct {
	Frontend       bkFrontend       `json:"frontend"`
	Backend        bkBackend        `json:"backend"`
	Infrastructure bkInfrastructure `json:"infrastructure"`
	Tools          bkTools          `json:"tools"`
}

// bkFrontend は、技術スタックの大分類 frontend である。小分類の並びは、要素が無ければ書かない。
// 欄は FrontendStacks と同じ並びなので、FrontendStacks から型の変換で作る。
type bkFrontend struct {
	Languages       []*string `json:"languages,omitempty"`
	Frameworks      []*string `json:"frameworks,omitempty"`
	Libraries       []*string `json:"libraries,omitempty"`
	BuildTools      []*string `json:"buildTools,omitempty"`
	PackageManagers []*string `json:"packageManagers,omitempty"`
	Linters         []*string `json:"linters,omitempty"`
	Formatters      []*string `json:"formatters,omitempty"`
	TestingTools    []*string `json:"testingTools,omitempty"`
}

// bkBackend は、技術スタックの大分類 backend である。小分類の並びは、要素が無ければ書かない。
type bkBackend struct {
	Languages       []*string `json:"languages,omitempty"`
	Frameworks      []*string `json:"frameworks,omitempty"`
	Libraries       []*string `json:"libraries,omitempty"`
	BuildTools      []*string `json:"buildTools,omitempty"`
	PackageManagers []*string `json:"packageManagers,omitempty"`
	Linters         []*string `json:"linters,omitempty"`
	Formatters      []*string `json:"formatters,omitempty"`
	TestingTools    []*string `json:"testingTools,omitempty"`
	OrmTools        []*string `json:"ormTools,omitempty"`
	Auth            []*string `json:"auth,omitempty"`
}

// bkInfrastructure は、技術スタックの大分類 infrastructure である。小分類の並びは、要素が無ければ書かない。
type bkInfrastructure struct {
	Clouds           []*string `json:"clouds,omitempty"`
	OperatingSystems []*string `json:"operatingSystems,omitempty"`
	Containers       []*string `json:"containers,omitempty"`
	Databases        []*string `json:"databases,omitempty"`
	WebServers       []*string `json:"webServers,omitempty"`
	CiCdTools        []*string `json:"ciCdTools,omitempty"`
	IacTools         []*string `json:"iacTools,omitempty"`
	MonitoringTools  []*string `json:"monitoringTools,omitempty"`
	LoggingTools     []*string `json:"loggingTools,omitempty"`
}

// bkTools は、技術スタックの大分類 tools である。小分類の並びは、要素が無ければ書かない。
type bkTools struct {
	SourceControls          []*string `json:"sourceControls,omitempty"`
	ProjectManagements      []*string `json:"projectManagements,omitempty"`
	CommunicationTools      []*string `json:"communicationTools,omitempty"`
	DocumentationTools      []*string `json:"documentationTools,omitempty"`
	APIDevelopmentTools     []*string `json:"apiDevelopmentTools,omitempty"`
	DesignTools             []*string `json:"designTools,omitempty"`
	Editors                 []*string `json:"editors,omitempty"`
	DevelopmentEnvironments []*string `json:"developmentEnvironments,omitempty"`
}

// bkCertification は、資格の項目である。取得の年月は YYYY-MM で書く。
type bkCertification struct {
	Name string `json:"name"`
	Date string `json:"date"`
}

// bkPortfolio は、ポートフォリオの項目である。技術スタックの文は、無ければ書かない。
type bkPortfolio struct {
	Name      string  `json:"name"`
	Overview  string  `json:"overview"`
	TechStack *string `json:"techStack,omitempty"`
	Link      string  `json:"link"`
}

// bkSnsPlatform は、SNS の項目である。
type bkSnsPlatform struct {
	Name string `json:"name"`
	Link string `json:"link"`
}

// bkSelfPromotion は、自己PR の項目である。
type bkSelfPromotion struct {
	Title   string `json:"title"`
	Content string `json:"content"`
}

// BackupResume は、利用者の経歴書1件を、バックアップのファイルにして返す。写す元は Java 版の BackupResumeUseCase である。
// 経歴書は GetResume で読むので、経歴書の ID が読めないとき、経歴書が無いとき、ほかの利用者の経歴書のときは、
// どれも無い経歴書の誤りになり、項目は GetResume と同じ順に並ぶ。データベースには書かない。
func (s *Service) BackupResume(ctx context.Context, userID uuid.UUID, resumeID string) (Export, error) {
	r, err := s.GetResume(ctx, userID, resumeID)
	if err != nil {
		return Export{}, err
	}
	return buildBackup(r, s.deps.Now())
}

// buildBackup は、経歴書 r から、now に書き出したバックアップのファイルの本文と Content-Type とファイル名を作る。
// 年が 1 から 9999 の外の日付か年月があれば、errBackupDate を返す。
func buildBackup(r Resume, now time.Time) (Export, error) {
	if !backupYearsInRange(r) {
		return Export{}, errBackupDate
	}
	f := bkFile{Version: backupVersion, ExportedAt: javaInstant(now), Resume: newBkResume(r)}
	body, err := backupJSON(f)
	if err != nil {
		return Export{}, err
	}
	return Export{
		Body:        body,
		ContentType: contentTypeBackup,
		FileName:    sanitizeFileName(r.Name) + backupFileSuffix,
	}, nil
}

// backupJSON は、バックアップのファイル f を、Go の標準のライブラリ encoding/json で JSON の本文にする。
// 経歴書の文の < > & は、そのまま書く。最後の改行は付けない。
func backupJSON(f bkFile) ([]byte, error) {
	var b bytes.Buffer
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(f); err != nil {
		return nil, fmt.Errorf("resume: バックアップのファイルを JSON にできない: %w", err)
	}
	return bytes.TrimSuffix(b.Bytes(), []byte("\n")), nil
}

// backupYearsInRange は、経歴書の日付と、職歴とプロジェクトの期間と、資格の年月の年が、どれも 1 から 9999 にあるかを返す。
func backupYearsInRange(r Resume) bool {
	years := []int{r.Date.Year}
	periods := make([]Period, 0, len(r.Careers)+len(r.Projects))
	for _, c := range r.Careers {
		periods = append(periods, c.Period)
	}
	for _, p := range r.Projects {
		periods = append(periods, p.Period)
	}
	for _, p := range periods {
		years = append(years, p.StartDate.Year)
		if p.EndDate != nil {
			years = append(years, p.EndDate.Year)
		}
	}
	for _, c := range r.Certifications {
		years = append(years, c.Date.Year)
	}
	for _, y := range years {
		if y < 1 || y > 9999 {
			return false
		}
	}
	return true
}

// newBkResume は、経歴書を、バックアップのファイルの経歴書の型に写す。年は 1 から 9999 にあるものとする。
func newBkResume(r Resume) bkResume {
	b := bkResume{
		ResumeName: r.Name,
		Date:       fmt.Sprintf("%04d-%02d-%02d", r.Date.Year, int(r.Date.Month), r.Date.Day),
		LastName:   r.LastName,
		FirstName:  r.FirstName,
	}
	for _, c := range r.Careers {
		b.Careers = append(b.Careers, bkCareer{
			CompanyName: c.CompanyName,
			StartDate:   backupYearMonth(c.Period.StartDate),
			EndDate:     backupEndDate(c.Period.EndDate),
			Active:      c.Period.Active,
		})
	}
	for _, p := range r.Projects {
		b.Projects = append(b.Projects, bkProject{
			CompanyName: p.CompanyName,
			StartDate:   backupYearMonth(p.Period.StartDate),
			EndDate:     backupEndDate(p.Period.EndDate),
			Active:      p.Period.Active,
			Name:        p.Name,
			Overview:    p.Overview,
			TeamComp:    p.TeamComp,
			Role:        p.Role,
			Achievement: p.Achievement,
			Process:     bkProcess(p.Process),
			TechStack: bkTechStack{
				Frontend:       bkFrontend(p.TechStack.Frontend),
				Backend:        bkBackend(p.TechStack.Backend),
				Infrastructure: bkInfrastructure(p.TechStack.Infrastructure),
				Tools:          bkTools(p.TechStack.Tools),
			},
		})
	}
	for _, c := range r.Certifications {
		b.Certifications = append(b.Certifications, bkCertification{Name: c.Name, Date: backupYearMonth(c.Date)})
	}
	for _, p := range r.Portfolios {
		b.Portfolios = append(b.Portfolios, bkPortfolio{Name: p.Name, Overview: p.Overview, TechStack: p.TechStack, Link: p.Link})
	}
	for _, s := range r.SnsPlatforms {
		b.SnsPlatforms = append(b.SnsPlatforms, bkSnsPlatform{Name: s.Name, Link: s.Link})
	}
	for _, s := range r.SelfPromotions {
		b.SelfPromotions = append(b.SelfPromotions, bkSelfPromotion{Title: s.Title, Content: s.Content})
	}
	return b
}

// backupYearMonth は、年月を、Java 版の YearMonth と同じく YYYY-MM で書く。
func backupYearMonth(v YearMonth) string {
	return fmt.Sprintf("%04d-%02d", v.Year, int(v.Month))
}

// backupEndDate は、終わりの年月を YYYY-MM で書く。終わりの年月が無ければ nil を返し、ファイルに書かない。
func backupEndDate(v *YearMonth) *string {
	if v == nil {
		return nil
	}
	s := backupYearMonth(*v)
	return &s
}

// javaInstant は、時刻を、Java の Instant.toString と同じ形の世界標準時で書く。秒は必ず書き、秒の小数は、
// 0 なら書かず、0 でなければ 3、6、9 桁のうち値を表せる最も短い桁数で書き、最後に Z を付ける。
func javaInstant(t time.Time) string {
	t = t.UTC()
	s := t.Format("2006-01-02T15:04:05")
	switch ns := t.Nanosecond(); {
	case ns == 0:
	case ns%1_000_000 == 0:
		s += fmt.Sprintf(".%03d", ns/1_000_000)
	case ns%1_000 == 0:
		s += fmt.Sprintf(".%06d", ns/1_000)
	default:
		s += fmt.Sprintf(".%09d", ns)
	}
	return s + "Z"
}
