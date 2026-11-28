package resume

import (
	"strings"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// 次の8つは、出力の前提を満たさないときの、足りないものごとの文言である(ResumeExportRuleCheckService)。
// 次の2つは、その誤りの文言の始まりの文である(ExportResumeUseCase)。どれも Java 版の文字列を1文字も変えずに写した。
const (
	MessageExportNameRequired           = "職務経歴書名を入力してください。"
	MessageExportDateRequired           = "日付を設定してください。"
	MessageExportFullNameRequired       = "氏名（姓・名）を入力してください。"
	MessageExportLastNameRequired       = "姓を入力してください。"
	MessageExportFirstNameRequired      = "名を入力してください。"
	MessageExportCareersRequired        = "職歴を1件以上登録してください。"
	MessageExportProjectsRequired       = "プロジェクトを1件以上登録してください。"
	MessageExportSelfPromotionsRequired = "自己PRを1件以上登録してください。"

	MessageExportPreviewUnavailable = "入力エラーがあるため、PDFプレビューを表示できません。"
	MessageExportUnavailable        = "職務経歴書をエクスポートできません。"
)

// exportRuleTarget は、出力の前提を確かめる経歴書の値である。Java 版の Resume のうち、
// ResumeExportRuleCheckService が読む値を、Java 版と同じく「無い」を表せる形で持つ。
type exportRuleTarget struct {
	name    string
	hasDate bool
	// fullName は氏名である。Java 版の FullName が null のとき nil にする。
	fullName       *exportRuleFullName
	careers        int
	projects       int
	selfPromotions int
}

// exportRuleFullName は、氏名の姓と名である。
type exportRuleFullName struct {
	lastName, firstName *string
}

// exportRuleTargetOf は、経歴書から出力の前提を確かめる値を作る。Java 版のリポジトリは、姓と名が NULL でも
// 氏名を作るので、経歴書から作る値は、いつも氏名を持つ。日付は、ゼロの値のとき無いとする。
func exportRuleTargetOf(r *Resume) exportRuleTarget {
	return exportRuleTarget{
		name:           r.Name,
		hasDate:        r.Date != Date{},
		fullName:       &exportRuleFullName{lastName: r.LastName, firstName: r.FirstName},
		careers:        len(r.Careers),
		projects:       len(r.Projects),
		selfPromotions: len(r.SelfPromotions),
	}
}

// missing は、足りないものの文言を、Java 版と同じく、経歴書の名前、日付、氏名、姓、名、職歴、プロジェクト、自己PR の順に返す。
// 氏名が無いときは、姓と名を確かめない。
func (t exportRuleTarget) missing() []string {
	var m []string
	if !notBlank(t.name) {
		m = append(m, MessageExportNameRequired)
	}
	if !t.hasDate {
		m = append(m, MessageExportDateRequired)
	}
	if t.fullName == nil {
		m = append(m, MessageExportFullNameRequired)
	} else {
		if t.fullName.lastName == nil || !notBlank(*t.fullName.lastName) {
			m = append(m, MessageExportLastNameRequired)
		}
		if t.fullName.firstName == nil || !notBlank(*t.fullName.firstName) {
			m = append(m, MessageExportFirstNameRequired)
		}
	}
	if t.careers == 0 {
		m = append(m, MessageExportCareersRequired)
	}
	if t.projects == 0 {
		m = append(m, MessageExportProjectsRequired)
	}
	if t.selfPromotions == 0 {
		m = append(m, MessageExportSelfPromotionsRequired)
	}
	return m
}

// checkExportRule は、経歴書が出力の前提を満たすかを確かめ、満たさなければ業務の誤り(400)を返す。
// 誤りの文言は、inline なら PDF のプレビューの文、それ以外なら出力できない文で始め、足りないものごとに改行と「- 」と文言を続ける。
// 設定を付けない出力は、Java 版と同じく inline を false にして呼ぶ。
func checkExportRule(r *Resume, inline bool) *auth.Error {
	m := exportRuleTargetOf(r).missing()
	if len(m) == 0 {
		return nil
	}
	lead := MessageExportUnavailable
	if inline {
		lead = MessageExportPreviewUnavailable
	}
	return auth.ErrBusiness(lead + "\n- " + strings.Join(m, "\n- "))
}
