package resume

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// マスタと経歴書の操作の文言である。どれも Java 版のソースの文字列を1文字も変えずに写した。
// 写した元のクラスを、定数ごとのコメントに書く。要求の型の注釈と domain/model/resume/ の値の決まりに同じ文字列があるときは、
// 1つの定数にまとめる。
const (
	// MessageInvalidInput は、本文が読めないときと、入力欄の検査で断るときの文言である(AppExceptionHandler)。
	MessageInvalidInput = auth.MessageInvalidInput

	// MessageResumeNotFound は、経歴書が無いとき、ほかの利用者の経歴書のとき、経歴書の ID が読めないときの文言である
	// (経歴書のユースケースと ResumeIdResolver の ResourceNotFoundUseCaseException)。
	MessageResumeNotFound = "対象の職務経歴書データが存在しません。"

	// 次の6つは、項目が無いときの欄ごとの文言である(Update*UseCase と Delete*UseCase の ResourceNotFoundUseCaseException)。
	MessageCareerNotFound        = "対象の職歴が存在しません。"
	MessageProjectNotFound       = "対象のプロジェクトが存在しません。"
	MessageCertificationNotFound = "対象の資格が存在しません。"
	MessagePortfolioNotFound     = "対象のポートフォリオが存在しません。"
	MessageSnsPlatformNotFound   = "対象のSNSプラットフォームが存在しません。"
	MessageSelfPromotionNotFound = "対象の自己PRが存在しません。"

	// 次の7つは、数の上限に達したときの文言の書式である(ResumeLimitChecker)。1つ目の %d に今の数を、2つ目の %d に上限を入れる。
	// 括弧とコロンと斜線は、Java 版と同じく全角の文字である。
	MessageResumeLimitFormat        = "職務経歴書の作成可能件数の上限に達しているため作成できません。（現在：%d件／上限：%d件）"
	MessageCareerLimitFormat        = "職歴の追加可能件数の上限に達しているため追加できません。（現在：%d件／上限：%d件）"
	MessageProjectLimitFormat       = "プロジェクトの追加可能件数の上限に達しているため追加できません。（現在：%d件／上限：%d件）"
	MessageCertificationLimitFormat = "資格の追加可能件数の上限に達しているため追加できません。（現在：%d件／上限：%d件）"
	MessageSnsPlatformLimitFormat   = "SNSプラットフォームの追加可能件数の上限に達しているため追加できません。（現在：%d件／上限：%d件）"
	MessagePortfolioLimitFormat     = "ポートフォリオの追加可能件数の上限に達しているため追加できません。（現在：%d件／上限：%d件）"
	MessageSelfPromotionLimitFormat = "自己PRの追加可能件数の上限に達しているため追加できません。（現在：%d件／上限：%d件）"

	// MessageResumeNameDuplicated は、同じ利用者の中に同じ名前の経歴書があるときの文言である(ResumeNameDuplicationCheckService)。
	MessageResumeNameDuplicated = "この職務経歴書名は既に登録されています。"

	// MessageUnsupportedBackupVersion は、戻すファイルの版が無いか 1.0 でないときの文言である(RestoreResumeUseCase)。
	MessageUnsupportedBackupVersion = "サポートされていないバックアップバージョンです。"

	// MessageInvalidBackupFile は、戻すファイルの経歴書と項目の値が、Java 版が戻しで確かめる値の決まりを満たさないときの文言である
	// (RestoreResumeUseCase)。2つの文を改行でつなぐ。
	MessageInvalidBackupFile = "バックアップファイルが不正なためリストアできません。\n別のバックアップファイルでお試しください。"

	// MessageCareerPeriodOverlapFormat は、職歴どうしの期間が重なるときの文言の書式である(Resume.validateIsCareerOverlap)。
	// 1つ目の %s に直す職歴の会社名を、2つ目の %s に重なる職歴の会社名を「、」でつないで入れる。
	MessageCareerPeriodOverlapFormat = "「%s」と「%s」の期間が重複しています。"

	// 次の4つは、経歴書の名前の文言である(CreateResumeRequest と UpdateResumeBasicRequest の注釈と、ResumeName、項目 resumeName)。
	MessageResumeNameRequired     = "職務経歴書名は入力必須です。"
	MessageResumeNameTooLong      = "職務経歴書名は50文字以内で入力してください。"
	MessageResumeNameInvalidChars = "職務経歴書名には次の文字は使用できません。\n\\ / : * ? \" < > | "
	MessageResumeNameDotEdge      = "職務経歴書名の先頭または末尾に「.」を使用することはできません。"

	// 次の2つは、経歴書の日付の文言である(UpdateResumeBasicRequest の注釈、項目 date)。
	MessageDateRequired = "日付は入力必須です。"
	MessageDateInvalid  = "日付が不正です。"

	// 次の6つは、姓と名の文言である(UpdateResumeBasicRequest の注釈と FullName、項目 lastName と firstName)。
	MessageLastNameRequired      = "姓は入力必須です。"
	MessageLastNameTooLong       = "姓は10文字以内で入力してください。"
	MessageLastNameInvalidChars  = "姓には英字、ひらがな、カタカナ、漢字のみ使用できます。"
	MessageFirstNameRequired     = "名は入力必須です。"
	MessageFirstNameTooLong      = "名は10文字以内で入力してください。"
	MessageFirstNameInvalidChars = "名には英字、ひらがな、カタカナ、漢字のみ使用できます。"

	// 次の2つは、会社名の文言である(職歴とプロジェクトの要求の型の注釈と CompanyName、項目 companyName)。
	MessageCompanyNameRequired = "会社名は入力必須です。"
	MessageCompanyNameTooLong  = "会社名は50文字以内で入力してください。"

	// 次の3つは、職歴とプロジェクトの年月の欄の注釈の文言である(項目 startDate と endDate)。
	MessageStartDateRequired = "開始年月は入力必須です。"
	MessageStartDateInvalid  = "開始年月が不正です。"
	MessageEndDateInvalid    = "終了年月が不正です。"

	// 次の3つは、期間の決まりの文言である(Period、項目 endDate)。
	MessageEndDateRequired     = "終了年月は入力必須です。"
	MessageEndDateBeforeStart  = "終了年月は開始年月より後の日付を指定してください。"
	MessageEndDateWhileOngoing = "継続中の場合、終了年月を設定できません。"

	// MessageCareerActiveRequired は、職歴の在籍中の欄の注釈の文言である(CreateCareerRequest と UpdateCareerRequest、項目 isActive)。
	MessageCareerActiveRequired = "在籍中は入力必須です。"
	// MessageProjectActiveRequired は、プロジェクトの継続中の欄の注釈の文言である(CreateProjectRequest と UpdateProjectRequest、項目 isActive)。
	MessageProjectActiveRequired = "継続中は入力必須です。"

	// 次の10は、プロジェクトの文言である(CreateProjectRequest と UpdateProjectRequest の注釈と Project)。
	MessageProjectNameRequired        = "プロジェクト名は入力必須です。"
	MessageProjectNameTooLong         = "プロジェクト名は50文字以内で入力してください。"
	MessageProjectOverviewRequired    = "プロジェクト概要は入力必須です。"
	MessageProjectOverviewTooLong     = "プロジェクト概要は1000文字以内で入力してください。"
	MessageProjectTeamCompRequired    = "チーム構成は入力必須です。"
	MessageProjectTeamCompTooLong     = "チーム構成は100文字以内で入力してください。"
	MessageProjectRoleRequired        = "役割は入力必須です。"
	MessageProjectRoleTooLong         = "役割は1000文字以内で入力してください。"
	MessageProjectAchievementRequired = "成果は入力必須です。"
	MessageProjectAchievementTooLong  = "成果は1000文字以内で入力してください。"

	// MessageNotNull は、作業の工程の真偽の欄が無いときの文言である。CreateProjectRequest と UpdateProjectRequest の
	// @NotNull は文言を指定しないので、Hibernate Validator の日本語の既定の文言になる(research.md の P3 で Java 版の答えから控えた)。
	MessageNotNull = "null は許可されていません"

	// 次の4つは、資格の文言である(CreateCertificationRequest と UpdateCertificationRequest の注釈と Certification、項目 name と date)。
	MessageCertificationNameRequired = "資格名は入力必須です。"
	MessageCertificationNameTooLong  = "資格名は50文字以内で入力してください。"
	MessageCertificationDateRequired = "取得年月は入力必須です。"
	MessageCertificationDateInvalid  = "取得年月が不正です。"

	// 次の5つは、ポートフォリオの文言である(CreatePortfolioRequest と UpdatePortfolioRequest の注釈と Portfolio)。
	MessagePortfolioNameRequired     = "ポートフォリオ名は入力必須です。"
	MessagePortfolioNameTooLong      = "ポートフォリオ名は50文字以内で入力してください。"
	MessagePortfolioOverviewRequired = "ポートフォリオ概要は入力必須です。"
	MessagePortfolioOverviewTooLong  = "ポートフォリオ概要は1000文字以内で入力してください。"
	MessagePortfolioTechStackTooLong = "技術スタックは1000文字以内で入力してください。"

	// 次の2つは、SNS の文言である(CreateSnsPlatformRequest と UpdateSnsPlatformRequest の注釈と SnsPlatform、項目 name)。
	MessageSnsPlatformNameRequired = "プラットフォーム名は入力必須です。"
	MessageSnsPlatformNameTooLong  = "プラットフォーム名は50文字以内で入力してください。"

	// 次の4つは、ポートフォリオと SNS のリンクの文言である(要求の型の注釈と Link、項目 link)。
	// MessageLinkNotURL は Link の値の決まりの文言で、MessageLinkNotHTTPS は要求の型の @URL の文言である。
	MessageLinkRequired = "リンクは入力必須です。"
	MessageLinkNotHTTPS = "リンクはhttps形式のURLを指定してください。"
	MessageLinkTooLong  = "リンクは255文字以内で入力してください。"
	MessageLinkNotURL   = "無効なURLです。HTTPS形式で正しいURLを入力してください。"

	// 次の4つは、自己PR の文言である(CreateSelfPromotionRequest と UpdateSelfPromotionRequest の注釈と SelfPromotion、項目 title と content)。
	MessageSelfPromotionTitleRequired   = "タイトルは入力必須です。"
	MessageSelfPromotionTitleTooLong    = "タイトルは50文字以内で入力してください。"
	MessageSelfPromotionContentRequired = "コンテンツは入力必須です。"
	MessageSelfPromotionContentTooLong  = "コンテンツは1000文字以内で入力してください。"
)

// errNotFound は、経歴書か項目が無いときの 404 の誤りを作る。Java 版の ResourceNotFoundUseCaseException にあたる。
// 経歴書の受け口は、認証の受け口と同じく、*auth.Error の状態の番号と文言で答える。
func errNotFound(message string) *auth.Error {
	return &auth.Error{Status: http.StatusNotFound, Message: message, Errors: map[string][]string{}}
}

// errResumeNotFound は、経歴書が無いとき、ほかの利用者の経歴書のとき、経歴書の ID が読めないときの 404 の誤りを作る。
func errResumeNotFound() *auth.Error {
	return errNotFound(MessageResumeNotFound)
}

// errUnreadableInput は、本文が読めないときの 400 の誤りを作る。Java 版の HttpMessageNotReadableException の答えと同じく、
// 項目ごとの文言を持たない。
func errUnreadableInput() *auth.Error {
	return auth.ErrInvalidInput(map[string][]string{})
}

// errLimitReached は、数の上限に達したときの 400 の誤りを作る。format は Message*LimitFormat のどれかである。
func errLimitReached(format string, count, limit int) *auth.Error {
	return auth.ErrBusiness(fmt.Sprintf(format, count, limit))
}

// errResumeNameDuplicated は、同じ利用者の中に同じ名前の経歴書があるときの 400 の誤りを作る。
func errResumeNameDuplicated() *auth.Error {
	return auth.ErrBusiness(MessageResumeNameDuplicated)
}

// errCareerPeriodOverlap は、職歴どうしの期間が重なるときの 400 の誤りを作る。target は直す職歴の会社名、
// others は期間が重なる職歴の会社名を、Java 版と同じ順に並べたものである。
func errCareerPeriodOverlap(target string, others []string) *auth.Error {
	return auth.ErrBusiness(fmt.Sprintf(MessageCareerPeriodOverlapFormat, target, strings.Join(others, "、")))
}
