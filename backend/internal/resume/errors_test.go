package resume

import (
	"net/http"
	"reflect"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// TestErrors_MessagesMatchJava は、マスタと経歴書の操作の文言の定数が、Java 版のソースの文字列と1文字も違わないことを確かめる。
// want は、Java 版のソースの文字列を写したものである。コメントに、写した元のクラスを書く。
func TestErrors_MessagesMatchJava(t *testing.T) {
	tests := []struct {
		name string
		got  string
		want string
	}{
		// AppExceptionHandler
		{"MessageInvalidInput", MessageInvalidInput, "入力エラーがあります。"},
		// 経歴書のユースケースと ResumeIdResolver
		{"MessageResumeNotFound", MessageResumeNotFound, "対象の職務経歴書データが存在しません。"},
		// Update*UseCase と Delete*UseCase
		{"MessageCareerNotFound", MessageCareerNotFound, "対象の職歴が存在しません。"},
		{"MessageProjectNotFound", MessageProjectNotFound, "対象のプロジェクトが存在しません。"},
		{"MessageCertificationNotFound", MessageCertificationNotFound, "対象の資格が存在しません。"},
		{"MessagePortfolioNotFound", MessagePortfolioNotFound, "対象のポートフォリオが存在しません。"},
		{"MessageSnsPlatformNotFound", MessageSnsPlatformNotFound, "対象のSNSプラットフォームが存在しません。"},
		{"MessageSelfPromotionNotFound", MessageSelfPromotionNotFound, "対象の自己PRが存在しません。"},
		// ResumeLimitChecker(Java 版は文字列をつないで作る。つないだ結果の %d の位置に数が入る)
		{"MessageResumeLimitFormat", MessageResumeLimitFormat, "職務経歴書の作成可能件数の上限に達しているため作成できません。（現在：" + "%d" + "件／上限：" + "%d" + "件）"},
		{"MessageCareerLimitFormat", MessageCareerLimitFormat, "職歴の追加可能件数の上限に達しているため追加できません。（現在：" + "%d" + "件／上限：" + "%d" + "件）"},
		{"MessageProjectLimitFormat", MessageProjectLimitFormat, "プロジェクトの追加可能件数の上限に達しているため追加できません。（現在：" + "%d" + "件／上限：" + "%d" + "件）"},
		{"MessageCertificationLimitFormat", MessageCertificationLimitFormat, "資格の追加可能件数の上限に達しているため追加できません。（現在：" + "%d" + "件／上限：" + "%d" + "件）"},
		{"MessageSnsPlatformLimitFormat", MessageSnsPlatformLimitFormat, "SNSプラットフォームの追加可能件数の上限に達しているため追加できません。（現在：" + "%d" + "件／上限：" + "%d" + "件）"},
		{"MessagePortfolioLimitFormat", MessagePortfolioLimitFormat, "ポートフォリオの追加可能件数の上限に達しているため追加できません。（現在：" + "%d" + "件／上限：" + "%d" + "件）"},
		{"MessageSelfPromotionLimitFormat", MessageSelfPromotionLimitFormat, "自己PRの追加可能件数の上限に達しているため追加できません。（現在：" + "%d" + "件／上限：" + "%d" + "件）"},
		// ResumeNameDuplicationCheckService
		{"MessageResumeNameDuplicated", MessageResumeNameDuplicated, "この職務経歴書名は既に登録されています。"},
		// Resume.validateIsCareerOverlap
		{"MessageCareerPeriodOverlapFormat", MessageCareerPeriodOverlapFormat, "「%s」と「%s」の期間が重複しています。"},
		// CreateResumeRequest と UpdateResumeBasicRequest の注釈と ResumeName
		{"MessageResumeNameRequired", MessageResumeNameRequired, "職務経歴書名は入力必須です。"},
		{"MessageResumeNameTooLong", MessageResumeNameTooLong, "職務経歴書名は50文字以内で入力してください。"},
		{"MessageResumeNameInvalidChars", MessageResumeNameInvalidChars, "職務経歴書名には次の文字は使用できません。\n" + "\\ / : * ? \" < > | "},
		{"MessageResumeNameDotEdge", MessageResumeNameDotEdge, "職務経歴書名の先頭または末尾に「.」を使用することはできません。"},
		// UpdateResumeBasicRequest の注釈
		{"MessageDateRequired", MessageDateRequired, "日付は入力必須です。"},
		{"MessageDateInvalid", MessageDateInvalid, "日付が不正です。"},
		// UpdateResumeBasicRequest の注釈と FullName
		{"MessageLastNameRequired", MessageLastNameRequired, "姓は入力必須です。"},
		{"MessageLastNameTooLong", MessageLastNameTooLong, "姓は10文字以内で入力してください。"},
		{"MessageLastNameInvalidChars", MessageLastNameInvalidChars, "姓には英字、ひらがな、カタカナ、漢字のみ使用できます。"},
		{"MessageFirstNameRequired", MessageFirstNameRequired, "名は入力必須です。"},
		{"MessageFirstNameTooLong", MessageFirstNameTooLong, "名は10文字以内で入力してください。"},
		{"MessageFirstNameInvalidChars", MessageFirstNameInvalidChars, "名には英字、ひらがな、カタカナ、漢字のみ使用できます。"},
		// 職歴とプロジェクトの要求の型の注釈と CompanyName
		{"MessageCompanyNameRequired", MessageCompanyNameRequired, "会社名は入力必須です。"},
		{"MessageCompanyNameTooLong", MessageCompanyNameTooLong, "会社名は50文字以内で入力してください。"},
		// 職歴とプロジェクトの要求の型の注釈
		{"MessageStartDateRequired", MessageStartDateRequired, "開始年月は入力必須です。"},
		{"MessageStartDateInvalid", MessageStartDateInvalid, "開始年月が不正です。"},
		{"MessageEndDateInvalid", MessageEndDateInvalid, "終了年月が不正です。"},
		// Period
		{"MessageEndDateRequired", MessageEndDateRequired, "終了年月は入力必須です。"},
		{"MessageEndDateBeforeStart", MessageEndDateBeforeStart, "終了年月は開始年月より後の日付を指定してください。"},
		{"MessageEndDateWhileOngoing", MessageEndDateWhileOngoing, "継続中の場合、終了年月を設定できません。"},
		// CreateCareerRequest と UpdateCareerRequest の注釈
		{"MessageCareerActiveRequired", MessageCareerActiveRequired, "在籍中は入力必須です。"},
		// CreateProjectRequest と UpdateProjectRequest の注釈と Project
		{"MessageProjectActiveRequired", MessageProjectActiveRequired, "継続中は入力必須です。"},
		{"MessageProjectNameRequired", MessageProjectNameRequired, "プロジェクト名は入力必須です。"},
		{"MessageProjectNameTooLong", MessageProjectNameTooLong, "プロジェクト名は50文字以内で入力してください。"},
		{"MessageProjectOverviewRequired", MessageProjectOverviewRequired, "プロジェクト概要は入力必須です。"},
		{"MessageProjectOverviewTooLong", MessageProjectOverviewTooLong, "プロジェクト概要は1000文字以内で入力してください。"},
		{"MessageProjectTeamCompRequired", MessageProjectTeamCompRequired, "チーム構成は入力必須です。"},
		{"MessageProjectTeamCompTooLong", MessageProjectTeamCompTooLong, "チーム構成は100文字以内で入力してください。"},
		{"MessageProjectRoleRequired", MessageProjectRoleRequired, "役割は入力必須です。"},
		{"MessageProjectRoleTooLong", MessageProjectRoleTooLong, "役割は1000文字以内で入力してください。"},
		{"MessageProjectAchievementRequired", MessageProjectAchievementRequired, "成果は入力必須です。"},
		{"MessageProjectAchievementTooLong", MessageProjectAchievementTooLong, "成果は1000文字以内で入力してください。"},
		// Hibernate Validator の @NotNull の日本語の既定の文言(research.md の P3)
		{"MessageNotNull", MessageNotNull, "null は許可されていません"},
		// CreateCertificationRequest と UpdateCertificationRequest の注釈と Certification
		{"MessageCertificationNameRequired", MessageCertificationNameRequired, "資格名は入力必須です。"},
		{"MessageCertificationNameTooLong", MessageCertificationNameTooLong, "資格名は50文字以内で入力してください。"},
		{"MessageCertificationDateRequired", MessageCertificationDateRequired, "取得年月は入力必須です。"},
		{"MessageCertificationDateInvalid", MessageCertificationDateInvalid, "取得年月が不正です。"},
		// CreatePortfolioRequest と UpdatePortfolioRequest の注釈と Portfolio
		{"MessagePortfolioNameRequired", MessagePortfolioNameRequired, "ポートフォリオ名は入力必須です。"},
		{"MessagePortfolioNameTooLong", MessagePortfolioNameTooLong, "ポートフォリオ名は50文字以内で入力してください。"},
		{"MessagePortfolioOverviewRequired", MessagePortfolioOverviewRequired, "ポートフォリオ概要は入力必須です。"},
		{"MessagePortfolioOverviewTooLong", MessagePortfolioOverviewTooLong, "ポートフォリオ概要は1000文字以内で入力してください。"},
		{"MessagePortfolioTechStackTooLong", MessagePortfolioTechStackTooLong, "技術スタックは1000文字以内で入力してください。"},
		// CreateSnsPlatformRequest と UpdateSnsPlatformRequest の注釈と SnsPlatform
		{"MessageSnsPlatformNameRequired", MessageSnsPlatformNameRequired, "プラットフォーム名は入力必須です。"},
		{"MessageSnsPlatformNameTooLong", MessageSnsPlatformNameTooLong, "プラットフォーム名は50文字以内で入力してください。"},
		// ポートフォリオと SNS の要求の型の注釈と Link
		{"MessageLinkRequired", MessageLinkRequired, "リンクは入力必須です。"},
		{"MessageLinkNotHTTPS", MessageLinkNotHTTPS, "リンクはhttps形式のURLを指定してください。"},
		{"MessageLinkTooLong", MessageLinkTooLong, "リンクは255文字以内で入力してください。"},
		{"MessageLinkNotURL", MessageLinkNotURL, "無効なURLです。HTTPS形式で正しいURLを入力してください。"},
		// CreateSelfPromotionRequest と UpdateSelfPromotionRequest の注釈と SelfPromotion
		{"MessageSelfPromotionTitleRequired", MessageSelfPromotionTitleRequired, "タイトルは入力必須です。"},
		{"MessageSelfPromotionTitleTooLong", MessageSelfPromotionTitleTooLong, "タイトルは50文字以内で入力してください。"},
		{"MessageSelfPromotionContentRequired", MessageSelfPromotionContentRequired, "コンテンツは入力必須です。"},
		{"MessageSelfPromotionContentTooLong", MessageSelfPromotionContentTooLong, "コンテンツは1000文字以内で入力してください。"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.got != tt.want {
				t.Errorf("%s = %q, want %q", tt.name, tt.got, tt.want)
			}
		})
	}
}

// TestErrors_Constructors は、誤りを作る関数が、Java 版の AppExceptionHandler と同じ状態の番号と文言と、
// 項目ごとの文言の束を持つ誤りを作ることを確かめる。項目ごとの文言の束は、空でも nil にしない。
func TestErrors_Constructors(t *testing.T) {
	empty := map[string][]string{}
	tests := []struct {
		name string
		got  *auth.Error
		want auth.Error
	}{
		{
			"errNotFound", errNotFound(MessageCareerNotFound),
			auth.Error{Status: http.StatusNotFound, Message: "対象の職歴が存在しません。", Errors: empty},
		},
		{
			"errResumeNotFound", errResumeNotFound(),
			auth.Error{Status: http.StatusNotFound, Message: "対象の職務経歴書データが存在しません。", Errors: empty},
		},
		{
			"errUnreadableInput", errUnreadableInput(),
			auth.Error{Status: http.StatusBadRequest, Message: "入力エラーがあります。", Errors: empty},
		},
		{
			"errLimitReached", errLimitReached(MessageCareerLimitFormat, 30, 30),
			auth.Error{Status: http.StatusBadRequest, Message: "職歴の追加可能件数の上限に達しているため追加できません。（現在：30件／上限：30件）", Errors: empty},
		},
		{
			"errResumeNameDuplicated", errResumeNameDuplicated(),
			auth.Error{Status: http.StatusBadRequest, Message: "この職務経歴書名は既に登録されています。", Errors: empty},
		},
		{
			"errCareerPeriodOverlap", errCareerPeriodOverlap("A社", []string{"B社", "C社"}),
			auth.Error{Status: http.StatusBadRequest, Message: "「A社」と「B社、C社」の期間が重複しています。", Errors: empty},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.got == nil {
				t.Fatalf("%s が nil を返した", tt.name)
			}
			if tt.got.Errors == nil {
				t.Errorf("%s の Errors が nil", tt.name)
			}
			if !reflect.DeepEqual(*tt.got, tt.want) {
				t.Errorf("%s = %+v, want %+v", tt.name, *tt.got, tt.want)
			}
		})
	}
}
