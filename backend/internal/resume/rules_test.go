package resume

import (
	"net/http"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// businessError は、Java 版の UseCaseException と、文言だけを持つ DomainException の答えにあたる、項目ごとの文言を持たない 400 の誤りを作る。
func businessError(message string) *auth.Error {
	return &auth.Error{Status: http.StatusBadRequest, Message: message, Errors: map[string][]string{}}
}

// checkBusinessError は、決まりの答え got が、文言 want の 400 の誤りと合うかを確かめる。want が空なら、誤りが無いことを確かめる。
func checkBusinessError(t *testing.T, name string, got *auth.Error, want string) {
	t.Helper()
	if want == "" {
		if got != nil {
			t.Errorf("%s: 誤りが無いはずが %d %q %v", name, got.Status, got.Message, got.Errors)
		}
		return
	}
	if !reflect.DeepEqual(got, businessError(want)) {
		t.Errorf("%s: 答えが %+v、期待は %q の 400", name, got, want)
	}
}

// TestRules_Limits は、経歴書と6つの欄の項目の数の上限で、上限の1つ下の数は通し、上限とそれより多い数を
// Java 版の ResumeLimitChecker と同じ文言で断ることを確かめる(要件2の受入基準1)。
func TestRules_Limits(t *testing.T) {
	cases := []struct {
		name    string
		rule    limitRule
		limit   int
		atLimit string
		over    string
	}{
		{
			"経歴書", resumeLimit, 50,
			"職務経歴書の作成可能件数の上限に達しているため作成できません。（現在：50件／上限：50件）",
			"職務経歴書の作成可能件数の上限に達しているため作成できません。（現在：51件／上限：50件）",
		},
		{
			"職歴", careerLimit, 30,
			"職歴の追加可能件数の上限に達しているため追加できません。（現在：30件／上限：30件）",
			"職歴の追加可能件数の上限に達しているため追加できません。（現在：31件／上限：30件）",
		},
		{
			"プロジェクト", projectLimit, 100,
			"プロジェクトの追加可能件数の上限に達しているため追加できません。（現在：100件／上限：100件）",
			"プロジェクトの追加可能件数の上限に達しているため追加できません。（現在：101件／上限：100件）",
		},
		{
			"資格", certificationLimit, 50,
			"資格の追加可能件数の上限に達しているため追加できません。（現在：50件／上限：50件）",
			"資格の追加可能件数の上限に達しているため追加できません。（現在：51件／上限：50件）",
		},
		{
			"SNS", snsPlatformLimit, 10,
			"SNSプラットフォームの追加可能件数の上限に達しているため追加できません。（現在：10件／上限：10件）",
			"SNSプラットフォームの追加可能件数の上限に達しているため追加できません。（現在：11件／上限：10件）",
		},
		{
			"ポートフォリオ", portfolioLimit, 50,
			"ポートフォリオの追加可能件数の上限に達しているため追加できません。（現在：50件／上限：50件）",
			"ポートフォリオの追加可能件数の上限に達しているため追加できません。（現在：51件／上限：50件）",
		},
		{
			"自己PR", selfPromotionLimit, 5,
			"自己PRの追加可能件数の上限に達しているため追加できません。（現在：5件／上限：5件）",
			"自己PRの追加可能件数の上限に達しているため追加できません。（現在：6件／上限：5件）",
		},
	}
	for _, c := range cases {
		checkBusinessError(t, c.name+"_0件", c.rule.check(0), "")
		checkBusinessError(t, c.name+"_上限の1つ下", c.rule.check(c.limit-1), "")
		checkBusinessError(t, c.name+"_上限", c.rule.check(c.limit), c.atLimit)
		checkBusinessError(t, c.name+"_上限の1つ上", c.rule.check(c.limit+1), c.over)
	}
}

// TestRules_NameDuplicated は、同じ利用者の経歴書に同じ名前があるときだけ、Java 版の ResumeNameDuplicationCheckService と
// 同じ文言で断ることを確かめる(要件2の受入基準1)。名前は1文字も違わないときだけ同じとみなす。
func TestRules_NameDuplicated(t *testing.T) {
	existing := []string{"経歴書A", "Resume"}
	cases := []struct {
		name string
		want string
	}{
		{"経歴書A", MessageResumeNameDuplicated},
		{"Resume", MessageResumeNameDuplicated},
		{"resume", ""},
		{"経歴書A ", ""},
		{"経歴書B", ""},
	}
	for _, c := range cases {
		checkBusinessError(t, quote(c.name), checkResumeNameDuplicated(c.name, existing), c.want)
	}
	checkBusinessError(t, "経歴書が無い", checkResumeNameDuplicated("経歴書A", nil), "")
}

// TestRules_Names は、経歴書の名前に使えない文字と先頭と末尾の「.」と、姓と名に使える文字を、Java 版の ResumeName と FullName と
// 同じ文言で断ることを確かめる(要件2の受入基準1)。
func TestRules_Names(t *testing.T) {
	t.Run("経歴書の名前", func(t *testing.T) {
		type nameCase = validateCase[string]
		const field = "resumeName"
		checkDiffTableInChangedBehaviors(t, map[string]string{"改行の文字を含む名前の使えない文字": "CB-115", "改行しない空白だけの名前": "CB-114"})
		cases := []nameCase{
			{name: "漢字と英字", req: "職務経歴書_2024 v1", want: nil},
			{name: "途中の.", req: "a.b", want: nil},
			{name: "全角の斜線と疑問符", req: "経歴書／？", want: nil},
			{name: "1文字の.", req: ".", want: map[string][]string{field: {MessageResumeNameDotEdge}}},
			{name: "先頭の.", req: ".経歴書", want: map[string][]string{field: {MessageResumeNameDotEdge}}},
			{name: "末尾の.", req: "経歴書.", want: map[string][]string{field: {MessageResumeNameDotEdge}}},
			{name: "使えない文字と末尾の.", req: "a/b.", want: map[string][]string{field: {MessageResumeNameInvalidChars, MessageResumeNameDotEdge}}},
			// 使えない文字は、改行の文字を含む名前でも断る(変えた動きの一覧の CB-115)。
			{name: "改行の文字の後ろの使えない文字と末尾の.", req: "a\u2028/b.", want: map[string][]string{field: {MessageResumeNameInvalidChars, MessageResumeNameDotEdge}}},
			{name: "改行の文字に似たタブと使えない文字", req: "a\t/b", want: map[string][]string{field: {MessageResumeNameInvalidChars}}},
			{name: "改行の文字に似た U+000B と使えない文字", req: "a\v/b", want: map[string][]string{field: {MessageResumeNameInvalidChars}}},
			{name: "空", req: "", want: map[string][]string{field: {MessageResumeNameRequired}}},
			{name: "全角の空白だけ", req: fullSpace, want: map[string][]string{field: {MessageResumeNameRequired}}},
			// 空白だけかは unicode.IsSpace で決める(変えた動きの一覧の CB-114)。
			{name: "改行しない空白だけ", req: "\u00a0\u2007\u202f", want: map[string][]string{field: {MessageResumeNameRequired}}},
			{name: "次の行の字だけ", req: "\u0085", want: map[string][]string{field: {MessageResumeNameRequired}}},
			{name: "情報の区切りの制御の字だけ", req: "\u001c\u001f", want: nil},
			// 空白だけの名前は、長さが上限を超えても、入力が要ることだけを返す。
			{name: "上限を超える空白だけ", req: strings.Repeat(" ", resumeNameMaxLength+1), want: map[string][]string{field: {MessageResumeNameRequired}}},
			{name: "空白だけと使えない文字の無い.", req: halfSpace + "." + halfSpace, want: nil},
		}
		for _, r := range `\/:*?"<>|` {
			s := "経歴" + string(r) + "書"
			cases = append(cases, nameCase{name: "使えない文字_" + s, req: s, want: map[string][]string{field: {MessageResumeNameInvalidChars}}})
		}
		for _, lt := range []string{"\n", "\r", "\u0085", "\u2028", "\u2029"} {
			cases = append(cases,
				nameCase{name: "改行の文字の後ろの使えない文字_" + quote(lt), req: "経歴" + lt + "/書", want: map[string][]string{field: {MessageResumeNameInvalidChars}}},
				nameCase{name: "改行の文字の前の使えない文字_" + quote(lt), req: "経歴/書" + lt, want: map[string][]string{field: {MessageResumeNameInvalidChars}}})
		}
		ok, tooLong := lengthCases(resumeNameMaxLength)
		for _, s := range ok {
			cases = append(cases, nameCase{name: "上限_" + s, req: s, want: nil})
		}
		for _, s := range tooLong {
			cases = append(cases, nameCase{name: "上限の1つ上_" + s, req: s, want: map[string][]string{field: {MessageResumeNameTooLong}}})
		}
		cases = append(cases, nameCase{
			name: "長すぎて使えない文字と先頭の.", req: "." + strings.Repeat("/", resumeNameMaxLength),
			want: map[string][]string{field: {MessageResumeNameTooLong, MessageResumeNameInvalidChars, MessageResumeNameDotEdge}},
		})
		runValidateCases(t, func(s string) *auth.Error {
			f := auth.FieldErrors{}
			checkResumeName(f, s)
			return f.Result()
		}, cases)
	})

	t.Run("姓と名", func(t *testing.T) {
		type fullName struct{ last, first *string }
		type nameCase = validateCase[fullName]
		valid := []string{
			"山田", "Yamada", "yamada", "やまだ", "ヤマダ", "佐々木", "ターナー",
			"ぁ", "ん", "ァ", "ン", "一", "龯", "AZaz",
			strings.Repeat("あ", personNameMaxLength),
		}
		invalid := []string{
			"山田1", "山田 太", "山田" + fullSpace + "太", "山田・太", "ゔ", "ヴ", "ヵ", "龰", "ｱ", "Ａ", "𠮷", "-", "山田\n",
		}
		var cases []nameCase
		for _, s := range valid {
			cases = append(cases,
				nameCase{name: "姓_" + s, req: fullName{ptr(s), ptr("太郎")}, want: nil},
				nameCase{name: "名_" + s, req: fullName{ptr("山田"), ptr(s)}, want: nil})
		}
		for _, s := range invalid {
			cases = append(cases,
				nameCase{name: "姓_" + quote(s), req: fullName{ptr(s), ptr("太郎")}, want: map[string][]string{"lastName": {MessageLastNameInvalidChars}}},
				nameCase{name: "名_" + quote(s), req: fullName{ptr("山田"), ptr(s)}, want: map[string][]string{"firstName": {MessageFirstNameInvalidChars}}})
		}
		for _, s := range []string{"", halfSpace, fullSpace} {
			cases = append(cases,
				nameCase{name: "姓が空白_" + quote(s), req: fullName{ptr(s), ptr("太郎")}, want: map[string][]string{"lastName": {MessageLastNameRequired}}},
				nameCase{name: "名が空白_" + quote(s), req: fullName{ptr("山田"), ptr(s)}, want: map[string][]string{"firstName": {MessageFirstNameRequired}}})
		}
		over := strings.Repeat("あ", personNameMaxLength+1)
		overInvalid := strings.Repeat("1", personNameMaxLength+1)
		cases = append(cases,
			nameCase{name: "姓と名が無い", req: fullName{}, want: map[string][]string{
				"lastName": {MessageLastNameRequired}, "firstName": {MessageFirstNameRequired},
			}},
			nameCase{name: "姓の上限の1つ上", req: fullName{ptr(over), ptr("太郎")}, want: map[string][]string{"lastName": {MessageLastNameTooLong}}},
			nameCase{name: "名の上限の1つ上", req: fullName{ptr("山田"), ptr(over)}, want: map[string][]string{"firstName": {MessageFirstNameTooLong}}},
			nameCase{name: "姓と名が長く使えない文字", req: fullName{ptr(overInvalid), ptr(overInvalid)}, want: map[string][]string{
				"lastName":  {MessageLastNameTooLong, MessageLastNameInvalidChars},
				"firstName": {MessageFirstNameTooLong, MessageFirstNameInvalidChars},
			}},
		)
		runValidateCases(t, func(n fullName) *auth.Error {
			f := auth.FieldErrors{}
			checkFullName(f, n.last, n.first)
			return f.Result()
		}, cases)
	})
}

// yearMonth は、年 y と月 m の年月を作る。
func yearMonth(y int, m time.Month) *YearMonth {
	return &YearMonth{Year: y, Month: m}
}

// TestRules_Period は、期間の4つの決まりを Java 版の Period と同じ文言で断ることと、職歴どうしの期間の重なりを
// Java 版の Resume と同じ条件と文言で断ることを確かめる(要件2の受入基準1)。
func TestRules_Period(t *testing.T) {
	t.Run("期間の決まり", func(t *testing.T) {
		type period struct {
			start, end *YearMonth
			active     bool
		}
		type periodCase = validateCase[period]
		start := yearMonth(2024, time.April)
		cases := []periodCase{
			{name: "開始が無い", req: period{nil, yearMonth(2024, time.May), false}, want: map[string][]string{"startDate": {MessageStartDateRequired}}},
			{name: "開始が無く継続中で終了がある", req: period{nil, yearMonth(2024, time.May), true}, want: map[string][]string{"startDate": {MessageStartDateRequired}}},
			{name: "継続中でなく終了が無い", req: period{start, nil, false}, want: map[string][]string{"endDate": {MessageEndDateRequired}}},
			{name: "終了が開始の前の月", req: period{start, yearMonth(2024, time.March), false}, want: map[string][]string{"endDate": {MessageEndDateBeforeStart}}},
			{name: "終了が開始の前の年の後の月", req: period{start, yearMonth(2023, time.December), false}, want: map[string][]string{"endDate": {MessageEndDateBeforeStart}}},
			{name: "終了が開始と同じ月", req: period{start, yearMonth(2024, time.April), false}, want: nil},
			{name: "終了が開始の次の月", req: period{start, yearMonth(2024, time.May), false}, want: nil},
			{name: "終了が開始の次の年の前の月", req: period{start, yearMonth(2025, time.January), false}, want: nil},
			{name: "継続中で終了が無い", req: period{start, nil, true}, want: nil},
			{name: "継続中で終了がある", req: period{start, yearMonth(2024, time.May), true}, want: map[string][]string{"endDate": {MessageEndDateWhileOngoing}}},
			{name: "継続中で終了が開始の前", req: period{start, yearMonth(2024, time.March), true}, want: map[string][]string{"endDate": {MessageEndDateWhileOngoing}}},
		}
		runValidateCases(t, func(p period) *auth.Error {
			f := auth.FieldErrors{}
			checkPeriod(f, p.start, p.end, p.active)
			return f.Result()
		}, cases)
	})

	t.Run("職歴の重なり", func(t *testing.T) {
		closed := func(id, name string, sy int, sm time.Month, ey int, em time.Month) Career {
			return Career{ID: uuid.MustParse(id), CompanyName: name, Period: Period{StartDate: *yearMonth(sy, sm), EndDate: yearMonth(ey, em)}}
		}
		active := func(id, name string, sy int, sm time.Month) Career {
			return Career{ID: uuid.MustParse(id), CompanyName: name, Period: Period{StartDate: *yearMonth(sy, sm), Active: true}}
		}
		const (
			targetID = "00000000-0000-0000-0000-000000000001"
			otherID  = "00000000-0000-0000-0000-000000000002"
			thirdID  = "00000000-0000-0000-0000-000000000003"
			fourthID = "00000000-0000-0000-0000-000000000004"
		)
		overlap := func(target string, others ...string) string {
			return "「" + target + "」と「" + strings.Join(others, "、") + "」の期間が重複しています。"
		}
		cases := []struct {
			name     string
			target   Career
			existing []Career
			want     string
		}{
			{"ほかの職歴が無い", active(targetID, "新", 2024, time.April), nil, ""},
			{
				"両方が在籍中", active(targetID, "新", 2024, time.April),
				[]Career{active(otherID, "旧", 2010, time.January)},
				overlap("新", "旧"),
			},
			{
				"新が在籍中で旧の終了が新の開始と同じ月", active(targetID, "新", 2024, time.April),
				[]Career{closed(otherID, "旧", 2020, time.January, 2024, time.April)},
				"",
			},
			{
				"新が在籍中で旧の終了が新の開始の次の月", active(targetID, "新", 2024, time.April),
				[]Career{closed(otherID, "旧", 2020, time.January, 2024, time.May)},
				overlap("新", "旧"),
			},
			{
				"新が在籍中で旧の終了が新の開始の前の月", active(targetID, "新", 2024, time.April),
				[]Career{closed(otherID, "旧", 2020, time.January, 2024, time.March)},
				"",
			},
			{
				"新が在籍中で旧が新の開始より後に始まる", active(targetID, "新", 2024, time.April),
				[]Career{closed(otherID, "旧", 2025, time.January, 2025, time.June)},
				overlap("新", "旧"),
			},
			{
				"旧が在籍中で新の終了が旧の開始と同じ月", closed(targetID, "新", 2020, time.January, 2024, time.April),
				[]Career{active(otherID, "旧", 2024, time.April)},
				"",
			},
			{
				"旧が在籍中で新の終了が旧の開始の次の月", closed(targetID, "新", 2020, time.January, 2024, time.May),
				[]Career{active(otherID, "旧", 2024, time.April)},
				overlap("新", "旧"),
			},
			{
				"旧が在籍中で新の終了が旧の開始の前の年", closed(targetID, "新", 2020, time.January, 2023, time.December),
				[]Career{active(otherID, "旧", 2024, time.April)},
				"",
			},
			{
				"どちらも退職で旧の終了と新の開始が同じ月", closed(targetID, "新", 2024, time.April, 2025, time.March),
				[]Career{closed(otherID, "旧", 2020, time.January, 2024, time.April)},
				"",
			},
			{
				"どちらも退職で新の終了と旧の開始が同じ月", closed(targetID, "新", 2020, time.January, 2024, time.April),
				[]Career{closed(otherID, "旧", 2024, time.April, 2025, time.March)},
				"",
			},
			{
				"どちらも退職で1か月重なる", closed(targetID, "新", 2024, time.March, 2025, time.March),
				[]Career{closed(otherID, "旧", 2020, time.January, 2024, time.April)},
				overlap("新", "旧"),
			},
			{
				"どちらも退職で年をまたいで重なる", closed(targetID, "新", 2024, time.January, 2024, time.June),
				[]Career{closed(otherID, "旧", 2023, time.November, 2024, time.February)},
				overlap("新", "旧"),
			},
			{
				"どちらも退職で新が旧の中にある", closed(targetID, "新", 2021, time.January, 2021, time.June),
				[]Career{closed(otherID, "旧", 2020, time.January, 2024, time.April)},
				overlap("新", "旧"),
			},
			{
				"どちらも退職で新が旧より前", closed(targetID, "新", 2018, time.January, 2019, time.December),
				[]Career{closed(otherID, "旧", 2020, time.January, 2024, time.April)},
				"",
			},
			{
				"どちらも退職で新が旧より後", closed(targetID, "新", 2025, time.January, 2025, time.December),
				[]Career{closed(otherID, "旧", 2020, time.January, 2024, time.April)},
				"",
			},
			{
				"どちらも退職で同じ月の1か月だけの期間", closed(targetID, "新", 2024, time.April, 2024, time.April),
				[]Career{closed(otherID, "旧", 2024, time.April, 2024, time.April)},
				"",
			},
			{
				"同じ ID の職歴は比べない", closed(targetID, "新", 2020, time.January, 2024, time.April),
				[]Career{closed(targetID, "前の新", 2020, time.January, 2024, time.April)},
				"",
			},
			{
				"重なる職歴を並びの順につなぐ", active(targetID, "新", 2020, time.January),
				[]Career{
					closed(otherID, "旧1", 2021, time.January, 2022, time.January),
					closed(thirdID, "旧2", 2010, time.January, 2015, time.January),
					active(fourthID, "旧3", 2019, time.January),
				},
				overlap("新", "旧1", "旧3"),
			},
		}
		for _, c := range cases {
			checkBusinessError(t, c.name, checkCareerOverlap(c.target, c.existing), c.want)
		}
	})
}
