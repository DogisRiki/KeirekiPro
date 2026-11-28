package resume

import (
	"strings"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// limitRule は、経歴書か1つの欄の項目の数の上限である。Java 版の ResumeLimits の数と、ResumeLimitChecker の文言の書式を持つ。
type limitRule struct {
	limit  int
	format string
}

// 経歴書は利用者ごとに、6つの欄の項目は経歴書ごとに数える。
var (
	resumeLimit        = limitRule{limit: 50, format: MessageResumeLimitFormat}
	careerLimit        = limitRule{limit: 30, format: MessageCareerLimitFormat}
	projectLimit       = limitRule{limit: 100, format: MessageProjectLimitFormat}
	certificationLimit = limitRule{limit: 50, format: MessageCertificationLimitFormat}
	snsPlatformLimit   = limitRule{limit: 10, format: MessageSnsPlatformLimitFormat}
	portfolioLimit     = limitRule{limit: 50, format: MessagePortfolioLimitFormat}
	selfPromotionLimit = limitRule{limit: 5, format: MessageSelfPromotionLimitFormat}
)

// check は、今の数 count が上限に達していれば、もう1つ作ることを断る 400 の誤りを返す。Java 版の ResumeLimitChecker の写しである。
func (l limitRule) check(count int) *auth.Error {
	if count >= l.limit {
		return errLimitReached(l.format, count, l.limit)
	}
	return nil
}

// checkResumeNameDuplicated は、同じ利用者の経歴書の名前の並び existing に、name と1文字も違わない名前があれば、
// 400 の誤りを返す。Java 版の ResumeNameDuplicationCheckService の写しである。
func checkResumeNameDuplicated(name string, existing []string) *auth.Error {
	for _, n := range existing {
		if n == name {
			return errResumeNameDuplicated()
		}
	}
	return nil
}

// resumeNameInvalidChars は、経歴書の名前に使えない9つの文字である。
const resumeNameInvalidChars = `\/:*?"<>|`

// notBlank は、s が空白(unicode.IsSpace)でない字を1つ以上含むかを返す。
func notBlank(s string) bool {
	return strings.TrimSpace(s) != ""
}

// checkResumeName は、経歴書の名前の値の決まりを検査し、誤りを項目 resumeName に足す。
// 名前が空白だけなら、入力が要ることだけを足す。入力が要ることと長さの上限は、要求の検査(validate.go)と同じ決まりである。
// 使えない文字は、名前のどこにあっても断る。
func checkResumeName(f auth.FieldErrors, name string) {
	const field = "resumeName"
	if !notBlank(name) {
		f.Check(field, false, MessageResumeNameRequired)
		return
	}
	f.Check(field, auth.UTF16Len(name) <= resumeNameMaxLength, MessageResumeNameTooLong)
	f.Check(field, !strings.ContainsAny(name, resumeNameInvalidChars), MessageResumeNameInvalidChars)
	f.Check(field, !strings.HasPrefix(name, ".") && !strings.HasSuffix(name, "."), MessageResumeNameDotEdge)
}

// checkFullName は、姓と名の値の決まり(Java 版の FullName)を検査し、誤りを項目 lastName と firstName に足す。
func checkFullName(f auth.FieldErrors, lastName, firstName *string) {
	checkPersonName(f, "lastName", lastName, MessageLastNameRequired, MessageLastNameTooLong, MessageLastNameInvalidChars)
	checkPersonName(f, "firstName", firstName, MessageFirstNameRequired, MessageFirstNameTooLong, MessageFirstNameInvalidChars)
}

// checkPersonName は、姓か名の1つを検査する。値が無いか空白だけなら、入力が要ることだけを足す。
func checkPersonName(f auth.FieldErrors, field string, s *string, required, tooLong, invalid string) {
	if s == nil || !notBlank(*s) {
		f.Check(field, false, required)
		return
	}
	f.Check(field, auth.UTF16Len(*s) <= personNameMaxLength, tooLong)
	f.Check(field, isPersonName(*s), invalid)
}

// isPersonName は、s が、Java 版の FullName.ARROW_PATTERN の文字だけでできているかを返す。
// 使える文字は、英字、ひらがな(ぁ から ん)、カタカナ(ァ から ン)、漢字(一 から 龯)、々、ー である。
func isPersonName(s string) bool {
	for _, r := range s {
		if !isPersonNameRune(r) {
			return false
		}
	}
	return true
}

func isPersonNameRune(r rune) bool {
	switch {
	case 'a' <= r && r <= 'z', 'A' <= r && r <= 'Z':
		return true
	case 'ぁ' <= r && r <= 'ん', 'ァ' <= r && r <= 'ン', '一' <= r && r <= '龯':
		return true
	case r == '々', r == 'ー':
		return true
	}
	return false
}

// after は、年月 y が年月 o より後かを返す。
func (y YearMonth) after(o YearMonth) bool {
	return y.Year > o.Year || y.Year == o.Year && y.Month > o.Month
}

// checkPeriod は、職歴とプロジェクトの期間の決まり(Java 版の Period)を検査し、誤りを項目 startDate と endDate に足す。
// 開始の年月が無いとき(1つ目の決まり)と、継続中でなく終了の年月が無いとき(2つ目の決まり)は、その誤りだけを足す。
// 継続中でなく終了が開始より前のとき(3つ目の決まり)と、継続中で終了の年月があるとき(4つ目の決まり)は、どちらか1つだけに当たる。
func checkPeriod(f auth.FieldErrors, start, end *YearMonth, active bool) {
	if start == nil {
		f.Check("startDate", false, MessageStartDateRequired)
		return
	}
	if !active && end == nil {
		f.Check("endDate", false, MessageEndDateRequired)
		return
	}
	f.Check("endDate", active || !start.after(*end), MessageEndDateBeforeStart)
	f.Check("endDate", !active || end == nil, MessageEndDateWhileOngoing)
}

// checkCareerOverlap は、職歴 target が、経歴書の職歴の並び careers のどれかと期間が重なれば、400 の誤りを返す。
// Java 版の Resume.validateIsCareerOverlap の写しである。careers のうち、target と同じ ID の職歴は比べない。
// 文言には、重なる職歴の会社名を careers の並びの順につなぐ。careers の期間は、checkPeriod の決まりを満たしている。
func checkCareerOverlap(target Career, careers []Career) *auth.Error {
	var overlapping []string
	for _, c := range careers {
		if c.ID == target.ID {
			continue
		}
		if periodsOverlap(target.Period, c.Period) {
			overlapping = append(overlapping, c.CompanyName)
		}
	}
	if len(overlapping) == 0 {
		return nil
	}
	return errCareerPeriodOverlap(target.CompanyName, overlapping)
}

// periodsOverlap は、2つの職歴の期間 t と e が重なるかを返す。2つとも在籍中なら重なる。
// 年月の単位では同じ月に退職と入社ができるので、一方の終了の月ともう一方の開始の月が同じなら、重ならないとみなす。
func periodsOverlap(t, e Period) bool {
	switch {
	case t.Active && e.Active:
		return true
	case t.Active:
		return e.EndDate.after(t.StartDate)
	case e.Active:
		return t.EndDate.after(e.StartDate)
	}
	if *e.EndDate == t.StartDate || *t.EndDate == e.StartDate {
		return false
	}
	return !t.StartDate.after(*e.EndDate) && !e.StartDate.after(*t.EndDate)
}
