package resume

import "github.com/DogisRiki/KeirekiPro/backend/internal/auth"

// 入力欄の長さの上限である。Java 版の要求の型の @Size の max にあたり、UTF-16 の単位で数える。
const (
	resumeNameMaxLength         = 50
	personNameMaxLength         = 10
	companyNameMaxLength        = 50
	certificationNameMaxLength  = 50
	projectNameMaxLength        = 50
	teamCompMaxLength           = 100
	portfolioNameMaxLength      = 50
	snsPlatformNameMaxLength    = 50
	selfPromotionTitleMaxLength = 50
	// longTextMaxLength は、概要、役割、成果、技術スタック、自己PR のコンテンツの上限である。
	longTextMaxLength = 1000
	linkMaxLength     = 255
)

// 年月と日付の年の範囲である。Java 版の @YearMonthRange と @LocalDateRange の既定の minYear と maxYear にあたる。
const (
	minYear = 1900
	maxYear = 2100
)

// checkRequiredText は、Java 版の @NotBlank と @Size(max) を写す。
// 値が無いか空白だけなら required を、UTF-16 の単位で数えた長さが limit を超えれば tooLong を、項目 field に足す。
// 前後の空白は取り除かずに数える。
func checkRequiredText(f auth.FieldErrors, field string, s *string, limit int, required, tooLong string) {
	f.Check(field, s != nil && auth.NotBlank(*s), required)
	f.Check(field, s == nil || auth.UTF16Len(*s) <= limit, tooLong)
}

// yearInRange は、年 y が Java 版の範囲の注釈の範囲に入るかを返す。
func yearInRange(y int) bool {
	return y >= minYear && y <= maxYear
}

// checkYearMonth は、年月の欄を検査する。required が空でなければ、値が無いときに required を足す(@NotNull)。
// 値があり、年が範囲の外なら invalid を足す(@YearMonthRange)。
func checkYearMonth(f auth.FieldErrors, field string, v jsonYearMonth, required, invalid string) {
	if required != "" {
		f.Check(field, v.Present, required)
	}
	f.Check(field, !v.Present || yearInRange(v.Value.Year), invalid)
}

// validateCreateResume は、経歴書の作成の要求(Java 版の CreateResumeRequest)を検査する。resumeId は検査しない。
func validateCreateResume(r createResumeRequest) *auth.Error {
	f := auth.FieldErrors{}
	checkRequiredText(f, "resumeName", r.ResumeName, resumeNameMaxLength, MessageResumeNameRequired, MessageResumeNameTooLong)
	return f.Result()
}

// validateUpdateResumeBasic は、基本の情報の更新の要求(Java 版の UpdateResumeBasicRequest)を検査する。
func validateUpdateResumeBasic(r updateResumeBasicRequest) *auth.Error {
	f := auth.FieldErrors{}
	checkRequiredText(f, "resumeName", r.ResumeName, resumeNameMaxLength, MessageResumeNameRequired, MessageResumeNameTooLong)
	f.Check("date", r.Date.Present, MessageDateRequired)
	f.Check("date", !r.Date.Present || yearInRange(r.Date.Value.Year), MessageDateInvalid)
	checkRequiredText(f, "lastName", r.LastName, personNameMaxLength, MessageLastNameRequired, MessageLastNameTooLong)
	checkRequiredText(f, "firstName", r.FirstName, personNameMaxLength, MessageFirstNameRequired, MessageFirstNameTooLong)
	return f.Result()
}

// validateCareer は、職歴の作成と更新の要求(Java 版の CreateCareerRequest と UpdateCareerRequest)を検査する。
// 在籍中の欄の項目の名前は、Java 版の @JsonProperty のとおり isActive にする。
func validateCareer(r careerRequest) *auth.Error {
	f := auth.FieldErrors{}
	checkRequiredText(f, "companyName", r.CompanyName, companyNameMaxLength, MessageCompanyNameRequired, MessageCompanyNameTooLong)
	checkYearMonth(f, "startDate", r.StartDate, MessageStartDateRequired, MessageStartDateInvalid)
	checkYearMonth(f, "endDate", r.EndDate, "", MessageEndDateInvalid)
	f.Check("isActive", r.Active != nil, MessageCareerActiveRequired)
	return f.Result()
}

// validateCertification は、資格の作成と更新の要求(Java 版の CreateCertificationRequest と UpdateCertificationRequest)を検査する。
func validateCertification(r certificationRequest) *auth.Error {
	f := auth.FieldErrors{}
	checkRequiredText(f, "name", r.Name, certificationNameMaxLength, MessageCertificationNameRequired, MessageCertificationNameTooLong)
	checkYearMonth(f, "date", r.Date, MessageCertificationDateRequired, MessageCertificationDateInvalid)
	return f.Result()
}

// checkOptionalText は、Java 版の @Size(max) だけを写す。値が無い値と空白だけの値は誤りにしない。
func checkOptionalText(f auth.FieldErrors, field string, s *string, limit int, tooLong string) {
	f.Check(field, s == nil || auth.UTF16Len(*s) <= limit, tooLong)
}

// checkLink は、ポートフォリオと SNS のリンクの欄の @NotBlank と @URL(protocol = "https") と @Size(max = 255) を写す。
// @URL は、値が無いときと空の文字列のときに誤りにしない。
func checkLink(f auth.FieldErrors, s *string) {
	f.Check("link", s != nil && auth.NotBlank(*s), MessageLinkRequired)
	f.Check("link", s == nil || isHibernateHTTPSURL(*s), MessageLinkNotHTTPS)
	f.Check("link", s == nil || auth.UTF16Len(*s) <= linkMaxLength, MessageLinkTooLong)
}

// validateProject は、プロジェクトの作成と更新の要求(Java 版の CreateProjectRequest と UpdateProjectRequest)を検査する。
// 継続中の欄の項目の名前は、Java 版の @JsonProperty のとおり isActive にする。
// 作業の工程の7つの真偽の欄の @NotNull は文言を指定しないので、Hibernate Validator の既定の文言 MessageNotNull を使う。
// 技術スタックの欄に注釈は無いので、検査しない。
func validateProject(r projectRequest) *auth.Error {
	f := auth.FieldErrors{}
	checkRequiredText(f, "companyName", r.CompanyName, companyNameMaxLength, MessageCompanyNameRequired, MessageCompanyNameTooLong)
	checkYearMonth(f, "startDate", r.StartDate, MessageStartDateRequired, MessageStartDateInvalid)
	checkYearMonth(f, "endDate", r.EndDate, "", MessageEndDateInvalid)
	f.Check("isActive", r.Active != nil, MessageProjectActiveRequired)
	checkRequiredText(f, "name", r.Name, projectNameMaxLength, MessageProjectNameRequired, MessageProjectNameTooLong)
	checkRequiredText(f, "overview", r.Overview, longTextMaxLength, MessageProjectOverviewRequired, MessageProjectOverviewTooLong)
	checkRequiredText(f, "teamComp", r.TeamComp, teamCompMaxLength, MessageProjectTeamCompRequired, MessageProjectTeamCompTooLong)
	checkRequiredText(f, "role", r.Role, longTextMaxLength, MessageProjectRoleRequired, MessageProjectRoleTooLong)
	checkRequiredText(f, "achievement", r.Achievement, longTextMaxLength, MessageProjectAchievementRequired, MessageProjectAchievementTooLong)
	f.Check("requirements", r.Requirements != nil, MessageNotNull)
	f.Check("basicDesign", r.BasicDesign != nil, MessageNotNull)
	f.Check("detailedDesign", r.DetailedDesign != nil, MessageNotNull)
	f.Check("implementation", r.Implementation != nil, MessageNotNull)
	f.Check("integrationTest", r.IntegrationTest != nil, MessageNotNull)
	f.Check("systemTest", r.SystemTest != nil, MessageNotNull)
	f.Check("maintenance", r.Maintenance != nil, MessageNotNull)
	return f.Result()
}

// validatePortfolio は、ポートフォリオの作成と更新の要求(Java 版の CreatePortfolioRequest と UpdatePortfolioRequest)を検査する。
func validatePortfolio(r portfolioRequest) *auth.Error {
	f := auth.FieldErrors{}
	checkRequiredText(f, "name", r.Name, portfolioNameMaxLength, MessagePortfolioNameRequired, MessagePortfolioNameTooLong)
	checkRequiredText(f, "overview", r.Overview, longTextMaxLength, MessagePortfolioOverviewRequired, MessagePortfolioOverviewTooLong)
	checkOptionalText(f, "techStack", r.TechStack, longTextMaxLength, MessagePortfolioTechStackTooLong)
	checkLink(f, r.Link)
	return f.Result()
}

// validateSnsPlatform は、SNS の作成と更新の要求(Java 版の CreateSnsPlatformRequest と UpdateSnsPlatformRequest)を検査する。
func validateSnsPlatform(r snsPlatformRequest) *auth.Error {
	f := auth.FieldErrors{}
	checkRequiredText(f, "name", r.Name, snsPlatformNameMaxLength, MessageSnsPlatformNameRequired, MessageSnsPlatformNameTooLong)
	checkLink(f, r.Link)
	return f.Result()
}

// validateSelfPromotion は、自己PR の作成と更新の要求(Java 版の CreateSelfPromotionRequest と UpdateSelfPromotionRequest)を検査する。
func validateSelfPromotion(r selfPromotionRequest) *auth.Error {
	f := auth.FieldErrors{}
	checkRequiredText(f, "title", r.Title, selfPromotionTitleMaxLength, MessageSelfPromotionTitleRequired, MessageSelfPromotionTitleTooLong)
	checkRequiredText(f, "content", r.Content, longTextMaxLength, MessageSelfPromotionContentRequired, MessageSelfPromotionContentTooLong)
	return f.Result()
}
