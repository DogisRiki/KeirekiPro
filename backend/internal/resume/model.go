package resume

import (
	"time"

	"github.com/google/uuid"
)

// YearMonth は、職歴とプロジェクトの期間と資格の取得年月の年と月である。Java 版の java.time.YearMonth にあたる。
// データベースには、その月の1日の日付として書く。
type YearMonth struct {
	Year  int
	Month time.Month
}

// Date は、経歴書の日付である。Java 版の java.time.LocalDate にあたる。時差を持たない。
type Date struct {
	Year  int
	Month time.Month
	Day   int
}

// Resume は、経歴書と6つの欄の項目である。Java 版の domain/model/resume の Resume にあたる。
type Resume struct {
	ID     uuid.UUID
	UserID uuid.UUID
	// Name は経歴書の名前である。答えの鍵は resumeName である。
	Name string
	Date Date
	// LastName と FirstName は姓と名である。データベースの値が NULL のとき nil にする。
	LastName  *string
	FirstName *string
	// CreatedAt と UpdatedAt は、時差を持たない日本の時刻である。
	CreatedAt time.Time
	UpdatedAt time.Time

	Careers        []Career
	Projects       []Project
	Certifications []Certification
	Portfolios     []Portfolio
	SnsPlatforms   []SnsPlatform
	SelfPromotions []SelfPromotion
}

// Period は、職歴とプロジェクトの期間である。Java 版の Period にあたる。
type Period struct {
	StartDate YearMonth
	// EndDate は終了年月である。在籍中と継続中のとき nil にする。
	EndDate *YearMonth
	// Active は、職歴では在籍中、プロジェクトでは継続中である。
	Active bool
}

// Career は、職歴の欄の項目である。
type Career struct {
	ID          uuid.UUID
	CompanyName string
	Period      Period
}

// Process は、プロジェクトの作業の工程である。Java 版の Project.Process にあたる。
type Process struct {
	Requirements    bool
	BasicDesign     bool
	DetailedDesign  bool
	Implementation  bool
	IntegrationTest bool
	SystemTest      bool
	Maintenance     bool
}

// Project は、プロジェクトの欄の項目である。
type Project struct {
	ID          uuid.UUID
	CompanyName string
	Period      Period
	Name        string
	Overview    string
	TeamComp    string
	Role        string
	Achievement string
	Process     Process
	TechStack   TechStack
}

// Certification は、資格の欄の項目である。
type Certification struct {
	ID   uuid.UUID
	Name string
	Date YearMonth
}

// Portfolio は、ポートフォリオの欄の項目である。
type Portfolio struct {
	ID       uuid.UUID
	Name     string
	Overview string
	// TechStack は技術スタックの文である。データベースの値が NULL のとき nil にする。
	TechStack *string
	Link      string
}

// SnsPlatform は、SNS の欄の項目である。
type SnsPlatform struct {
	ID   uuid.UUID
	Name string
	Link string
}

// SelfPromotion は、自己PR の欄の項目である。
type SelfPromotion struct {
	ID      uuid.UUID
	Title   string
	Content string
}

// TechStackSet は、技術スタックの大分類4つと小分類35の名前の並びである。E は並びの要素の型である。
// json の鍵は、Java 版の TechStackListResponse と ResumeInfoResponse の techStack の鍵と同じである。
// 技術スタックのマスタの答えとプロジェクトの techStack は、同じ鍵を使う。
type TechStackSet[E any] struct {
	Frontend       FrontendStacks[E]       `json:"frontend"`
	Backend        BackendStacks[E]        `json:"backend"`
	Infrastructure InfrastructureStacks[E] `json:"infrastructure"`
	Tools          ToolStacks[E]           `json:"tools"`
}

// FrontendStacks は、技術スタックの大分類 frontend の8つの小分類である。
type FrontendStacks[E any] struct {
	Languages       []E `json:"languages"`
	Frameworks      []E `json:"frameworks"`
	Libraries       []E `json:"libraries"`
	BuildTools      []E `json:"buildTools"`
	PackageManagers []E `json:"packageManagers"`
	Linters         []E `json:"linters"`
	Formatters      []E `json:"formatters"`
	TestingTools    []E `json:"testingTools"`
}

// BackendStacks は、技術スタックの大分類 backend の10の小分類である。
type BackendStacks[E any] struct {
	Languages       []E `json:"languages"`
	Frameworks      []E `json:"frameworks"`
	Libraries       []E `json:"libraries"`
	BuildTools      []E `json:"buildTools"`
	PackageManagers []E `json:"packageManagers"`
	Linters         []E `json:"linters"`
	Formatters      []E `json:"formatters"`
	TestingTools    []E `json:"testingTools"`
	OrmTools        []E `json:"ormTools"`
	Auth            []E `json:"auth"`
}

// InfrastructureStacks は、技術スタックの大分類 infrastructure の9つの小分類である。
type InfrastructureStacks[E any] struct {
	Clouds           []E `json:"clouds"`
	OperatingSystems []E `json:"operatingSystems"`
	Containers       []E `json:"containers"`
	Databases        []E `json:"databases"`
	WebServers       []E `json:"webServers"`
	CiCdTools        []E `json:"ciCdTools"`
	IacTools         []E `json:"iacTools"`
	MonitoringTools  []E `json:"monitoringTools"`
	LoggingTools     []E `json:"loggingTools"`
}

// ToolStacks は、技術スタックの大分類 tools の8つの小分類である。
type ToolStacks[E any] struct {
	SourceControls          []E `json:"sourceControls"`
	ProjectManagements      []E `json:"projectManagements"`
	CommunicationTools      []E `json:"communicationTools"`
	DocumentationTools      []E `json:"documentationTools"`
	APIDevelopmentTools     []E `json:"apiDevelopmentTools"`
	DesignTools             []E `json:"designTools"`
	Editors                 []E `json:"editors"`
	DevelopmentEnvironments []E `json:"developmentEnvironments"`
}

// TechStack は、プロジェクトの技術スタックである。Java 版の List<String> は null の要素を持てるので、
// 要素を *string にする。並びが無いときは nil にし、答えでは null になる。
type TechStack = TechStackSet[*string]

// TechStackMaster は、技術スタックのマスタの名前の振り分けである。マスタの名前は NULL にならないので、要素を string にする。
type TechStackMaster = TechStackSet[string]
