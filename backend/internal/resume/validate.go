package resume

import "github.com/DogisRiki/KeirekiPro/backend/internal/auth"

// 入力欄の長さの上限である。Java 版の要求の型の @Size の max にあたり、UTF-16 の単位で数える。
const (
	resumeNameMaxLength        = 50
	personNameMaxLength        = 10
	companyNameMaxLength       = 50
	certificationNameMaxLength = 50
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
