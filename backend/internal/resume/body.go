package resume

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/google/uuid"
)

// errUnreadableBody は、要求の本文が読めないことである。Service は、この誤りを、入力の検査より先に、
// 400 と項目ごとの文言を持たない答え(errUnreadableInput)にする。
var errUnreadableBody = errors.New("要求の本文が読めない")

// decodeBody は、要求の本文を Go の標準のライブラリ encoding/json の json.Unmarshal で、要求の型 T の値に読む。
// 読み方は encoding/json のとおりで、Java 版の Jackson の読み方を写さない。
//   - 鍵は、大文字と小文字を区別せずに構造体の欄と組にする。知らない鍵は読み飛ばし、同じ鍵が2つあればあとの値を使う
//   - 文字列の欄は *string、真偽の欄は *bool で読む。型の違う値は読めない。null と鍵が無いことは、値が無いことにする
//   - 技術スタックの欄は []*string で読む。null の要素は、値の無い要素にする
//   - 本文の全体が null のときは、すべての欄の値が無いことにする。本文の全体が並び、文字列、数、真偽のときは読めない
//   - UTF-8 として誤ったバイトと、対になっていないサロゲートの \uXXXX の書き方は、U+FFFD に置き換えて読む
//
// 読めない本文には、errUnreadableBody を包んだ誤りを返す。Java 版と違う読み方は、変えた動きの一覧の
// CB-052、CB-054、CB-055 に載せた。
func decodeBody[T any](body []byte) (T, error) {
	var v T
	if err := json.Unmarshal(body, &v); err != nil {
		var zero T
		return zero, fmt.Errorf("%w: %w", errUnreadableBody, err)
	}
	return v, nil
}

// jsonResumeID は、経歴書の作成の要求の resumeId の欄である。写す元の経歴書の ID にあたる。
// JSON の値を *string で読み、空の文字列と null と鍵が無いことは、写さない作成にする(Present が false)。
// ほかの文字列は parseID で読み、読めなければ errUnreadableBody を返す。文字列でない値も読めない。
type jsonResumeID struct {
	Value uuid.UUID
	// Present は、写す元の経歴書の ID があることである。
	Present bool
}

// UnmarshalJSON は、resumeId の欄を読む。
func (v *jsonResumeID) UnmarshalJSON(b []byte) error {
	*v = jsonResumeID{}
	var s *string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	if s == nil || *s == "" {
		return nil
	}
	id, ok := parseID(*s)
	if !ok {
		return errUnreadableBody
	}
	*v = jsonResumeID{Value: id, Present: true}
	return nil
}

// createResumeRequest は、経歴書の作成の要求の本文である。Java 版の CreateResumeRequest にあたる。
type createResumeRequest struct {
	ResumeName *string      `json:"resumeName"`
	ResumeID   jsonResumeID `json:"resumeId"`
}

// updateResumeBasicRequest は、経歴書の基本の情報の更新の要求の本文である。Java 版の UpdateResumeBasicRequest にあたる。
type updateResumeBasicRequest struct {
	ResumeName *string  `json:"resumeName"`
	Date       jsonDate `json:"date"`
	LastName   *string  `json:"lastName"`
	FirstName  *string  `json:"firstName"`
}

// careerRequest は、職歴の追加と更新の要求の本文である。Java 版の CreateCareerRequest と UpdateCareerRequest にあたる。
type careerRequest struct {
	CompanyName *string       `json:"companyName"`
	StartDate   jsonYearMonth `json:"startDate"`
	EndDate     jsonYearMonth `json:"endDate"`
	// Active は在籍中である。鍵は isActive で、active の鍵は読み飛ばす。
	Active *bool `json:"isActive"`
}

// projectRequest は、プロジェクトの追加と更新の要求の本文である。Java 版の CreateProjectRequest と UpdateProjectRequest にあたる。
type projectRequest struct {
	CompanyName *string       `json:"companyName"`
	StartDate   jsonYearMonth `json:"startDate"`
	EndDate     jsonYearMonth `json:"endDate"`
	// Active は継続中である。鍵は isActive で、active の鍵は読み飛ばす。
	Active      *bool   `json:"isActive"`
	Name        *string `json:"name"`
	Overview    *string `json:"overview"`
	TeamComp    *string `json:"teamComp"`
	Role        *string `json:"role"`
	Achievement *string `json:"achievement"`

	Requirements    *bool `json:"requirements"`
	BasicDesign     *bool `json:"basicDesign"`
	DetailedDesign  *bool `json:"detailedDesign"`
	Implementation  *bool `json:"implementation"`
	IntegrationTest *bool `json:"integrationTest"`
	SystemTest      *bool `json:"systemTest"`
	Maintenance     *bool `json:"maintenance"`

	FrontendLanguages       []*string `json:"frontendLanguages"`
	FrontendFrameworks      []*string `json:"frontendFrameworks"`
	FrontendLibraries       []*string `json:"frontendLibraries"`
	FrontendBuildTools      []*string `json:"frontendBuildTools"`
	FrontendPackageManagers []*string `json:"frontendPackageManagers"`
	FrontendLinters         []*string `json:"frontendLinters"`
	FrontendFormatters      []*string `json:"frontendFormatters"`
	FrontendTestingTools    []*string `json:"frontendTestingTools"`

	BackendLanguages       []*string `json:"backendLanguages"`
	BackendFrameworks      []*string `json:"backendFrameworks"`
	BackendLibraries       []*string `json:"backendLibraries"`
	BackendBuildTools      []*string `json:"backendBuildTools"`
	BackendPackageManagers []*string `json:"backendPackageManagers"`
	BackendLinters         []*string `json:"backendLinters"`
	BackendFormatters      []*string `json:"backendFormatters"`
	BackendTestingTools    []*string `json:"backendTestingTools"`
	OrmTools               []*string `json:"ormTools"`
	Auth                   []*string `json:"auth"`

	Clouds           []*string `json:"clouds"`
	OperatingSystems []*string `json:"operatingSystems"`
	Containers       []*string `json:"containers"`
	Databases        []*string `json:"databases"`
	WebServers       []*string `json:"webServers"`
	CiCdTools        []*string `json:"ciCdTools"`
	IacTools         []*string `json:"iacTools"`
	MonitoringTools  []*string `json:"monitoringTools"`
	LoggingTools     []*string `json:"loggingTools"`

	SourceControls          []*string `json:"sourceControls"`
	ProjectManagements      []*string `json:"projectManagements"`
	CommunicationTools      []*string `json:"communicationTools"`
	DocumentationTools      []*string `json:"documentationTools"`
	APIDevelopmentTools     []*string `json:"apiDevelopmentTools"`
	DesignTools             []*string `json:"designTools"`
	Editors                 []*string `json:"editors"`
	DevelopmentEnvironments []*string `json:"developmentEnvironments"`
}

// certificationRequest は、資格の追加と更新の要求の本文である。Java 版の CreateCertificationRequest と UpdateCertificationRequest にあたる。
type certificationRequest struct {
	Name *string       `json:"name"`
	Date jsonYearMonth `json:"date"`
}

// portfolioRequest は、ポートフォリオの追加と更新の要求の本文である。Java 版の CreatePortfolioRequest と UpdatePortfolioRequest にあたる。
type portfolioRequest struct {
	Name      *string `json:"name"`
	Overview  *string `json:"overview"`
	TechStack *string `json:"techStack"`
	Link      *string `json:"link"`
}

// snsPlatformRequest は、SNS の追加と更新の要求の本文である。Java 版の CreateSnsPlatformRequest と UpdateSnsPlatformRequest にあたる。
type snsPlatformRequest struct {
	Name *string `json:"name"`
	Link *string `json:"link"`
}

// selfPromotionRequest は、自己PR の追加と更新の要求の本文である。Java 版の CreateSelfPromotionRequest と UpdateSelfPromotionRequest にあたる。
type selfPromotionRequest struct {
	Title   *string `json:"title"`
	Content *string `json:"content"`
}
