package resume

import (
	"net/http"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// 境界の値に使う文字列である。
const (
	// halfSpace は、半角の空白である。
	halfSpace = " "
	// fullSpace は、全角の空白(U+3000)である。Java の Character.isWhitespace は空白とみなす。
	fullSpace = "　"
	// emoji は、UTF-16 で2つの単位に数える絵文字である。
	emoji = "😀"
)

// validateCase は、検査の1つの入力と、項目ごとに期待する文言である。want が nil なら、誤りが無いことを期待する。
type validateCase[T any] struct {
	name string
	req  T
	want map[string][]string
}

// lengthCases は、上限 limit の文字列の欄の、長さの境界の値を返す。
// UTF-16 の単位で数えることを確かめるため、絵文字を含む値で、上限ちょうどの値と上限の1つ上の値を作る。
// 26個の絵文字は、文字の数では上限50に収まるが、UTF-16 の単位では52になる。
func lengthCases(limit int) (ok, tooLong []string) {
	ok = []string{
		strings.Repeat("a", limit),
		strings.Repeat("あ", limit),
		strings.Repeat("a", limit-2) + emoji,
		strings.Repeat(emoji, limit/2),
	}
	tooLong = []string{
		strings.Repeat("a", limit+1),
		strings.Repeat("あ", limit+1),
		strings.Repeat("a", limit-1) + emoji,
		strings.Repeat(emoji, limit/2+1),
	}
	return ok, tooLong
}

// blankCases は、入力が要る文言で断る値(空、半角の空白だけ、全角の空白だけ、タブと改行だけ)を返す。
func blankCases() []string {
	return []string{"", halfSpace, strings.Repeat(halfSpace, 3), fullSpace, strings.Repeat(fullSpace, 2), "\t\n", halfSpace + fullSpace}
}

// stringFieldCases は、文字列の欄 field の境界の値の入力を作る。
// set は、正しい要求 base の写しに、欄の値を入れた要求を返す。
func stringFieldCases[T any](field string, limit int, required, tooLongMsg string, set func(*string) T) []validateCase[T] {
	cases := []validateCase[T]{
		{name: field + "_値なし", req: set(nil), want: map[string][]string{field: {required}}},
	}
	for _, s := range blankCases() {
		cases = append(cases, validateCase[T]{name: field + "_空白_" + quote(s), req: set(&s), want: map[string][]string{field: {required}}})
	}
	// 前後に空白のある値は、空白を取り除かずに数える。
	padded := halfSpace + strings.Repeat("a", limit-2) + fullSpace
	cases = append(cases, validateCase[T]{name: field + "_前後に空白で上限", req: set(&padded), want: nil})
	paddedOver := halfSpace + strings.Repeat("a", limit-1) + fullSpace
	cases = append(cases, validateCase[T]{name: field + "_前後に空白で上限の1つ上", req: set(&paddedOver), want: map[string][]string{field: {tooLongMsg}}})
	// 空白だけで上限を超える値は、2つの文言が付く。
	blankOver := strings.Repeat(fullSpace, limit+1)
	cases = append(cases, validateCase[T]{name: field + "_全角の空白だけで上限の1つ上", req: set(&blankOver), want: map[string][]string{field: {required, tooLongMsg}}})
	ok, tooLong := lengthCases(limit)
	for i, s := range ok {
		cases = append(cases, validateCase[T]{name: field + "_上限_" + strconv.Itoa(i), req: set(&s), want: nil})
	}
	for i, s := range tooLong {
		cases = append(cases, validateCase[T]{name: field + "_上限の1つ上_" + strconv.Itoa(i), req: set(&s), want: map[string][]string{field: {tooLongMsg}}})
	}
	return cases
}

// yearMonthFieldCases は、年月の欄 field の、年の境界の値の入力を作る。required が空なら、値が無くてもよい欄である。
func yearMonthFieldCases[T any](field, required, invalid string, set func(jsonYearMonth) T) []validateCase[T] {
	none := map[string][]string(nil)
	if required != "" {
		none = map[string][]string{field: {required}}
	}
	ym := func(y int, m time.Month) jsonYearMonth {
		return jsonYearMonth{Value: YearMonth{Year: y, Month: m}, Present: true}
	}
	return []validateCase[T]{
		{name: field + "_値なし", req: set(jsonYearMonth{}), want: none},
		{name: field + "_0000年", req: set(ym(0, time.January)), want: map[string][]string{field: {invalid}}},
		{name: field + "_1899年12月", req: set(ym(1899, time.December)), want: map[string][]string{field: {invalid}}},
		{name: field + "_1900年1月", req: set(ym(1900, time.January)), want: nil},
		{name: field + "_2100年12月", req: set(ym(2100, time.December)), want: nil},
		{name: field + "_2101年1月", req: set(ym(2101, time.January)), want: map[string][]string{field: {invalid}}},
		{name: field + "_9999年", req: set(ym(9999, time.December)), want: map[string][]string{field: {invalid}}},
	}
}

// checkValidate は、検査の答え got が、項目ごとの文言 want と合うかを確かめる。
// 1つの欄の文言の並びは Java 版と同じとは限らない(CB-050)ので、並びを除いて比べる。
func checkValidate(t *testing.T, name string, got *auth.Error, want map[string][]string) {
	t.Helper()
	if want == nil {
		if got != nil {
			t.Errorf("%s: 誤りが無いはずが %d %q %v", name, got.Status, got.Message, got.Errors)
		}
		return
	}
	if got == nil {
		t.Errorf("%s: 誤り %v を返すはずが nil", name, want)
		return
	}
	if got.Status != http.StatusBadRequest || got.Message != auth.ErrInvalidInput(nil).Message {
		t.Errorf("%s: 状態と文言が %d %q", name, got.Status, got.Message)
	}
	if len(got.Errors) != len(want) {
		t.Errorf("%s: 項目が %v、期待は %v", name, got.Errors, want)
		return
	}
	for field, msgs := range want {
		g := slices.Sorted(slices.Values(got.Errors[field]))
		w := slices.Sorted(slices.Values(msgs))
		if !slices.Equal(g, w) {
			t.Errorf("%s: 項目 %s の文言が %q、期待は %q", name, field, got.Errors[field], msgs)
		}
	}
}

// runValidateCases は、すべての入力を検査の関数 fn で確かめる。
func runValidateCases[T any](t *testing.T, fn func(T) *auth.Error, cases []validateCase[T]) {
	t.Helper()
	for _, c := range cases {
		checkValidate(t, c.name, fn(c.req), c.want)
	}
}

func quote(s string) string {
	r := strings.NewReplacer("\t", `\t`, "\n", `\n`, fullSpace, "全角", halfSpace, "半角")
	if s == "" {
		return "空"
	}
	return r.Replace(s)
}

func ptr[T any](v T) *T {
	return &v
}

func TestValidate_Resume(t *testing.T) {
	base := createResumeRequest{ResumeName: ptr("経歴書")}
	cases := []validateCase[createResumeRequest]{
		{name: "正しい要求", req: base, want: nil},
		{name: "resumeId があっても検査しない", req: createResumeRequest{ResumeName: ptr("経歴書"), ResumeID: jsonResumeID{Present: true}}, want: nil},
	}
	cases = append(cases, stringFieldCases("resumeName", 50, MessageResumeNameRequired, MessageResumeNameTooLong, func(s *string) createResumeRequest {
		r := base
		r.ResumeName = s
		return r
	})...)
	runValidateCases(t, validateCreateResume, cases)
}

func TestValidate_Basic(t *testing.T) {
	base := updateResumeBasicRequest{
		ResumeName: ptr("経歴書"),
		Date:       jsonDate{Value: Date{Year: 2024, Month: time.January, Day: 1}, Present: true},
		LastName:   ptr("山田"),
		FirstName:  ptr("太郎"),
	}
	cases := []validateCase[updateResumeBasicRequest]{
		{name: "正しい要求", req: base, want: nil},
		{
			name: "すべての欄が無い",
			req:  updateResumeBasicRequest{},
			want: map[string][]string{
				"resumeName": {MessageResumeNameRequired},
				"date":       {MessageDateRequired},
				"lastName":   {MessageLastNameRequired},
				"firstName":  {MessageFirstNameRequired},
			},
		},
	}
	cases = append(cases, stringFieldCases("resumeName", 50, MessageResumeNameRequired, MessageResumeNameTooLong, func(s *string) updateResumeBasicRequest {
		r := base
		r.ResumeName = s
		return r
	})...)
	cases = append(cases, stringFieldCases("lastName", 10, MessageLastNameRequired, MessageLastNameTooLong, func(s *string) updateResumeBasicRequest {
		r := base
		r.LastName = s
		return r
	})...)
	cases = append(cases, stringFieldCases("firstName", 10, MessageFirstNameRequired, MessageFirstNameTooLong, func(s *string) updateResumeBasicRequest {
		r := base
		r.FirstName = s
		return r
	})...)
	d := func(y int, m time.Month, day int) updateResumeBasicRequest {
		r := base
		r.Date = jsonDate{Value: Date{Year: y, Month: m, Day: day}, Present: true}
		return r
	}
	noDate := base
	noDate.Date = jsonDate{}
	cases = append(cases,
		validateCase[updateResumeBasicRequest]{name: "date_値なし", req: noDate, want: map[string][]string{"date": {MessageDateRequired}}},
		validateCase[updateResumeBasicRequest]{name: "date_0000年", req: d(0, time.January, 1), want: map[string][]string{"date": {MessageDateInvalid}}},
		validateCase[updateResumeBasicRequest]{name: "date_1899年12月31日", req: d(1899, time.December, 31), want: map[string][]string{"date": {MessageDateInvalid}}},
		validateCase[updateResumeBasicRequest]{name: "date_1900年1月1日", req: d(1900, time.January, 1), want: nil},
		validateCase[updateResumeBasicRequest]{name: "date_2100年12月31日", req: d(2100, time.December, 31), want: nil},
		validateCase[updateResumeBasicRequest]{name: "date_2101年1月1日", req: d(2101, time.January, 1), want: map[string][]string{"date": {MessageDateInvalid}}},
	)
	runValidateCases(t, validateUpdateResumeBasic, cases)
}

func TestValidate_Career(t *testing.T) {
	base := careerRequest{
		CompanyName: ptr("A社"),
		StartDate:   jsonYearMonth{Value: YearMonth{Year: 2020, Month: time.January}, Present: true},
		EndDate:     jsonYearMonth{Value: YearMonth{Year: 2021, Month: time.March}, Present: true},
		Active:      ptr(false),
	}
	cases := []validateCase[careerRequest]{
		{name: "正しい要求", req: base, want: nil},
		{name: "在籍中で終了年月なし", req: careerRequest{CompanyName: ptr("A社"), StartDate: base.StartDate, Active: ptr(true)}, want: nil},
		{
			name: "すべての欄が無い",
			req:  careerRequest{},
			want: map[string][]string{
				"companyName": {MessageCompanyNameRequired},
				"startDate":   {MessageStartDateRequired},
				"isActive":    {MessageCareerActiveRequired},
			},
		},
		{name: "isActive_値なし", req: careerRequest{CompanyName: ptr("A社"), StartDate: base.StartDate, EndDate: base.EndDate}, want: map[string][]string{"isActive": {MessageCareerActiveRequired}}},
	}
	cases = append(cases, stringFieldCases("companyName", 50, MessageCompanyNameRequired, MessageCompanyNameTooLong, func(s *string) careerRequest {
		r := base
		r.CompanyName = s
		return r
	})...)
	cases = append(cases, yearMonthFieldCases("startDate", MessageStartDateRequired, MessageStartDateInvalid, func(v jsonYearMonth) careerRequest {
		r := base
		r.StartDate = v
		return r
	})...)
	cases = append(cases, yearMonthFieldCases("endDate", "", MessageEndDateInvalid, func(v jsonYearMonth) careerRequest {
		r := base
		r.EndDate = v
		return r
	})...)
	runValidateCases(t, validateCareer, cases)
}

func TestValidate_Certification(t *testing.T) {
	base := certificationRequest{
		Name: ptr("基本情報技術者"),
		Date: jsonYearMonth{Value: YearMonth{Year: 2020, Month: time.April}, Present: true},
	}
	cases := []validateCase[certificationRequest]{
		{name: "正しい要求", req: base, want: nil},
		{
			name: "すべての欄が無い",
			req:  certificationRequest{},
			want: map[string][]string{
				"name": {MessageCertificationNameRequired},
				"date": {MessageCertificationDateRequired},
			},
		},
	}
	cases = append(cases, stringFieldCases("name", 50, MessageCertificationNameRequired, MessageCertificationNameTooLong, func(s *string) certificationRequest {
		r := base
		r.Name = s
		return r
	})...)
	cases = append(cases, yearMonthFieldCases("date", MessageCertificationDateRequired, MessageCertificationDateInvalid, func(v jsonYearMonth) certificationRequest {
		r := base
		r.Date = v
		return r
	})...)
	runValidateCases(t, validateCertification, cases)
}

// optionalTextCases は、入力が要らない文字列の欄 field の境界の値の入力を作る。値が無い値と空白だけの値は誤りにしない。
func optionalTextCases[T any](field string, limit int, tooLongMsg string, set func(*string) T) []validateCase[T] {
	cases := []validateCase[T]{
		{name: field + "_値なし", req: set(nil), want: nil},
	}
	for _, s := range blankCases() {
		cases = append(cases, validateCase[T]{name: field + "_空白_" + quote(s), req: set(&s), want: nil})
	}
	blankOver := strings.Repeat(fullSpace, limit+1)
	cases = append(cases, validateCase[T]{name: field + "_全角の空白だけで上限の1つ上", req: set(&blankOver), want: map[string][]string{field: {tooLongMsg}}})
	ok, tooLong := lengthCases(limit)
	for i, s := range ok {
		cases = append(cases, validateCase[T]{name: field + "_上限_" + strconv.Itoa(i), req: set(&s), want: nil})
	}
	for i, s := range tooLong {
		cases = append(cases, validateCase[T]{name: field + "_上限の1つ上_" + strconv.Itoa(i), req: set(&s), want: map[string][]string{field: {tooLongMsg}}})
	}
	return cases
}

// linkFieldCases は、リンクの欄の入力を作る。ポートフォリオと SNS のリンクの欄は、同じ checkLink で確かめるので、同じ答えを期待する。
// https の URL かの判定の細かな値は TestIsHTTPSLink が確かめるので、ここでは、3つの検査の文言の組み合わせと、
// 絵文字を含む値の長さの上限とその1つ上を確かめる。
func linkFieldCases[T any](t *testing.T, set func(*string) T) []validateCase[T] {
	t.Helper()
	// https://example.com/ は20の単位なので、絵文字1つを足して、255と256の単位の値を作る。
	prefix := "https://example.com/"
	ok := prefix + strings.Repeat("a", 255-len(prefix)-2) + emoji
	over := prefix + strings.Repeat("a", 255-len(prefix)-1) + emoji
	httpOver := "http://example.com/" + strings.Repeat("a", 255)
	cases := []validateCase[T]{
		{name: "link_値なし", req: set(nil), want: map[string][]string{"link": {MessageLinkRequired}}},
		{name: "link_空", req: set(ptr("")), want: map[string][]string{"link": {MessageLinkRequired}}},
		{name: "link_空白だけ", req: set(ptr("   ")), want: map[string][]string{"link": {MessageLinkRequired, MessageLinkNotHTTPS}}},
		{name: "link_https", req: set(ptr("https://example.com/path")), want: nil},
		{name: "link_http", req: set(ptr("http://example.com")), want: map[string][]string{"link": {MessageLinkNotHTTPS}}},
		{name: "link_ホスト名なし", req: set(ptr("https:example.com")), want: map[string][]string{"link": {MessageLinkNotHTTPS}}},
		{name: "link_http_上限の1つ上", req: set(&httpOver), want: map[string][]string{"link": {MessageLinkNotHTTPS, MessageLinkTooLong}}},
	}
	cases = append(cases,
		validateCase[T]{name: "link_絵文字で上限", req: set(&ok), want: nil},
		validateCase[T]{name: "link_絵文字で上限の1つ上", req: set(&over), want: map[string][]string{"link": {MessageLinkTooLong}}},
	)
	return cases
}

func TestValidate_Project(t *testing.T) {
	base := projectRequest{
		CompanyName:     ptr("A社"),
		StartDate:       jsonYearMonth{Value: YearMonth{Year: 2020, Month: time.January}, Present: true},
		EndDate:         jsonYearMonth{Value: YearMonth{Year: 2021, Month: time.March}, Present: true},
		Active:          ptr(false),
		Name:            ptr("案件"),
		Overview:        ptr("概要"),
		TeamComp:        ptr("5人"),
		Role:            ptr("開発"),
		Achievement:     ptr("成果"),
		Requirements:    ptr(true),
		BasicDesign:     ptr(false),
		DetailedDesign:  ptr(true),
		Implementation:  ptr(false),
		IntegrationTest: ptr(true),
		SystemTest:      ptr(false),
		Maintenance:     ptr(true),
	}
	cases := []validateCase[projectRequest]{
		{name: "正しい要求", req: base, want: nil},
		{
			name: "すべての欄が無い",
			req:  projectRequest{},
			want: map[string][]string{
				"companyName":     {MessageCompanyNameRequired},
				"startDate":       {MessageStartDateRequired},
				"isActive":        {MessageProjectActiveRequired},
				"name":            {MessageProjectNameRequired},
				"overview":        {MessageProjectOverviewRequired},
				"teamComp":        {MessageProjectTeamCompRequired},
				"role":            {MessageProjectRoleRequired},
				"achievement":     {MessageProjectAchievementRequired},
				"requirements":    {MessageNotNull},
				"basicDesign":     {MessageNotNull},
				"detailedDesign":  {MessageNotNull},
				"implementation":  {MessageNotNull},
				"integrationTest": {MessageNotNull},
				"systemTest":      {MessageNotNull},
				"maintenance":     {MessageNotNull},
			},
		},
	}
	// 作業の工程の真偽の欄と継続中の欄は、1つずつ値を無くす。
	flags := []struct {
		field   string
		message string
		clear   func(*projectRequest)
	}{
		{"isActive", MessageProjectActiveRequired, func(r *projectRequest) { r.Active = nil }},
		{"requirements", MessageNotNull, func(r *projectRequest) { r.Requirements = nil }},
		{"basicDesign", MessageNotNull, func(r *projectRequest) { r.BasicDesign = nil }},
		{"detailedDesign", MessageNotNull, func(r *projectRequest) { r.DetailedDesign = nil }},
		{"implementation", MessageNotNull, func(r *projectRequest) { r.Implementation = nil }},
		{"integrationTest", MessageNotNull, func(r *projectRequest) { r.IntegrationTest = nil }},
		{"systemTest", MessageNotNull, func(r *projectRequest) { r.SystemTest = nil }},
		{"maintenance", MessageNotNull, func(r *projectRequest) { r.Maintenance = nil }},
	}
	for _, fl := range flags {
		r := base
		fl.clear(&r)
		cases = append(cases, validateCase[projectRequest]{name: fl.field + "_値なし", req: r, want: map[string][]string{fl.field: {fl.message}}})
	}
	texts := []struct {
		field             string
		limit             int
		required, tooLong string
		set               func(*projectRequest, *string)
	}{
		{"companyName", 50, MessageCompanyNameRequired, MessageCompanyNameTooLong, func(r *projectRequest, s *string) { r.CompanyName = s }},
		{"name", 50, MessageProjectNameRequired, MessageProjectNameTooLong, func(r *projectRequest, s *string) { r.Name = s }},
		{"overview", 1000, MessageProjectOverviewRequired, MessageProjectOverviewTooLong, func(r *projectRequest, s *string) { r.Overview = s }},
		{"teamComp", 100, MessageProjectTeamCompRequired, MessageProjectTeamCompTooLong, func(r *projectRequest, s *string) { r.TeamComp = s }},
		{"role", 1000, MessageProjectRoleRequired, MessageProjectRoleTooLong, func(r *projectRequest, s *string) { r.Role = s }},
		{"achievement", 1000, MessageProjectAchievementRequired, MessageProjectAchievementTooLong, func(r *projectRequest, s *string) { r.Achievement = s }},
	}
	for _, tx := range texts {
		cases = append(cases, stringFieldCases(tx.field, tx.limit, tx.required, tx.tooLong, func(s *string) projectRequest {
			r := base
			tx.set(&r, s)
			return r
		})...)
	}
	cases = append(cases, yearMonthFieldCases("startDate", MessageStartDateRequired, MessageStartDateInvalid, func(v jsonYearMonth) projectRequest {
		r := base
		r.StartDate = v
		return r
	})...)
	cases = append(cases, yearMonthFieldCases("endDate", "", MessageEndDateInvalid, func(v jsonYearMonth) projectRequest {
		r := base
		r.EndDate = v
		return r
	})...)
	runValidateCases(t, validateProject, cases)
}

func TestValidate_Portfolio(t *testing.T) {
	base := portfolioRequest{
		Name:      ptr("ポートフォリオ"),
		Overview:  ptr("概要"),
		TechStack: ptr("Go"),
		Link:      ptr("https://example.com"),
	}
	cases := []validateCase[portfolioRequest]{
		{name: "正しい要求", req: base, want: nil},
		{
			name: "すべての欄が無い",
			req:  portfolioRequest{},
			want: map[string][]string{
				"name":     {MessagePortfolioNameRequired},
				"overview": {MessagePortfolioOverviewRequired},
				"link":     {MessageLinkRequired},
			},
		},
	}
	cases = append(cases, stringFieldCases("name", 50, MessagePortfolioNameRequired, MessagePortfolioNameTooLong, func(s *string) portfolioRequest {
		r := base
		r.Name = s
		return r
	})...)
	cases = append(cases, stringFieldCases("overview", 1000, MessagePortfolioOverviewRequired, MessagePortfolioOverviewTooLong, func(s *string) portfolioRequest {
		r := base
		r.Overview = s
		return r
	})...)
	cases = append(cases, optionalTextCases("techStack", 1000, MessagePortfolioTechStackTooLong, func(s *string) portfolioRequest {
		r := base
		r.TechStack = s
		return r
	})...)
	cases = append(cases, linkFieldCases(t, func(s *string) portfolioRequest {
		r := base
		r.Link = s
		return r
	})...)
	runValidateCases(t, validatePortfolio, cases)
}

func TestValidate_SnsPlatform(t *testing.T) {
	base := snsPlatformRequest{Name: ptr("GitHub"), Link: ptr("https://github.com/example")}
	cases := []validateCase[snsPlatformRequest]{
		{name: "正しい要求", req: base, want: nil},
		{
			name: "すべての欄が無い",
			req:  snsPlatformRequest{},
			want: map[string][]string{
				"name": {MessageSnsPlatformNameRequired},
				"link": {MessageLinkRequired},
			},
		},
	}
	cases = append(cases, stringFieldCases("name", 50, MessageSnsPlatformNameRequired, MessageSnsPlatformNameTooLong, func(s *string) snsPlatformRequest {
		r := base
		r.Name = s
		return r
	})...)
	cases = append(cases, linkFieldCases(t, func(s *string) snsPlatformRequest {
		r := base
		r.Link = s
		return r
	})...)
	runValidateCases(t, validateSnsPlatform, cases)
}

func TestValidate_SelfPromotion(t *testing.T) {
	base := selfPromotionRequest{Title: ptr("タイトル"), Content: ptr("内容")}
	cases := []validateCase[selfPromotionRequest]{
		{name: "正しい要求", req: base, want: nil},
		{
			name: "すべての欄が無い",
			req:  selfPromotionRequest{},
			want: map[string][]string{
				"title":   {MessageSelfPromotionTitleRequired},
				"content": {MessageSelfPromotionContentRequired},
			},
		},
	}
	cases = append(cases, stringFieldCases("title", 50, MessageSelfPromotionTitleRequired, MessageSelfPromotionTitleTooLong, func(s *string) selfPromotionRequest {
		r := base
		r.Title = s
		return r
	})...)
	cases = append(cases, stringFieldCases("content", 1000, MessageSelfPromotionContentRequired, MessageSelfPromotionContentTooLong, func(s *string) selfPromotionRequest {
		r := base
		r.Content = s
		return r
	})...)
	runValidateCases(t, validateSelfPromotion, cases)
}
