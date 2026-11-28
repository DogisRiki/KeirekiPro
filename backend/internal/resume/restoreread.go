package resume

import "encoding/json"

// 戻しの本文の読み手
//
// readRestoreFile は、戻しの要求の本文を、Go の標準のライブラリ encoding/json の json.Unmarshal で読む。
// 読み方は encoding/json のとおりで、Java 版の Jackson の読み方を写さない。
//
//   - 鍵は、大文字と小文字を区別せずに構造体の欄と組にする。知らない鍵は読み飛ばし、同じ鍵が2つあればあとの値を使う
//   - 文字列の欄は *string、真偽の欄は bool で読む。型の違う値は読めない。null と鍵が無いことは、値が無いことにする
//   - 日付と年月は、要求の本文と同じく jsonDate と jsonYearMonth で読む
//   - 6つの欄の並びの null の要素は nil の要素にする。buildRestored が、値の決まりを満たさないものとして断る
//   - 書き出しの日時(exportedAt)は読まない
//   - UTF-8 として誤ったバイトと、対になっていないサロゲートの \uXXXX の書き方は、U+FFFD に置き換えて読む

// rsFile は、戻しの要求の本文である。
type rsFile struct {
	Version *string   `json:"version"`
	Resume  *rsResume `json:"resume"`
}

// rsResume は、戻しの本文の経歴書である。6つの欄の並びは、欄が無いか null なら nil、並びの null の要素は nil の要素とする。
type rsResume struct {
	Name           *string            `json:"resumeName"`
	Date           jsonDate           `json:"date"`
	LastName       *string            `json:"lastName"`
	FirstName      *string            `json:"firstName"`
	Careers        []*rsCareer        `json:"careers"`
	Projects       []*rsProject       `json:"projects"`
	Certifications []*rsCertification `json:"certifications"`
	Portfolios     []*rsPortfolio     `json:"portfolios"`
	SnsPlatforms   []*rsSnsPlatform   `json:"snsPlatforms"`
	SelfPromotions []*rsSelfPromotion `json:"selfPromotions"`
}

// rsCareer は、戻しの本文の職歴である。
type rsCareer struct {
	CompanyName *string       `json:"companyName"`
	StartDate   jsonYearMonth `json:"startDate"`
	EndDate     jsonYearMonth `json:"endDate"`
	Active      bool          `json:"active"`
}

// rsProject は、戻しの本文のプロジェクトである。工程の欄が無いか null なら、7つの工程をすべて偽とする。
type rsProject struct {
	CompanyName *string       `json:"companyName"`
	StartDate   jsonYearMonth `json:"startDate"`
	EndDate     jsonYearMonth `json:"endDate"`
	Active      bool          `json:"active"`
	Name        *string       `json:"name"`
	Overview    *string       `json:"overview"`
	TeamComp    *string       `json:"teamComp"`
	Role        *string       `json:"role"`
	Achievement *string       `json:"achievement"`
	Process     bkProcess     `json:"process"`
	TechStack   TechStack     `json:"techStack"`
}

// rsCertification は、戻しの本文の資格である。
type rsCertification struct {
	Name *string       `json:"name"`
	Date jsonYearMonth `json:"date"`
}

// rsPortfolio は、戻しの本文のポートフォリオである。
type rsPortfolio struct {
	Name      *string `json:"name"`
	Overview  *string `json:"overview"`
	TechStack *string `json:"techStack"`
	Link      *string `json:"link"`
}

// rsSnsPlatform は、戻しの本文の SNS である。
type rsSnsPlatform struct {
	Name *string `json:"name"`
	Link *string `json:"link"`
}

// rsSelfPromotion は、戻しの本文の自己 PR である。
type rsSelfPromotion struct {
	Title   *string `json:"title"`
	Content *string `json:"content"`
}

// readRestoreFile は、戻しの要求の本文 body を読む。読めない本文なら false を返す。
// プロジェクトの技術スタックの、値の無い小分類は、空の並びにする。
func readRestoreFile(body []byte) (rsFile, bool) {
	var f rsFile
	if err := json.Unmarshal(body, &f); err != nil {
		return rsFile{}, false
	}
	if f.Resume != nil {
		for _, p := range f.Resume.Projects {
			if p != nil {
				fillEmptyStacks(&p.TechStack)
			}
		}
	}
	return f, true
}

// fillEmptyStacks は、技術スタック t の35の小分類のうち、値の無いものを空の並びにする。
func fillEmptyStacks(t *TechStack) {
	for _, c := range techStackColumns {
		if list := c.field(t); *list == nil {
			*list = []*string{}
		}
	}
}
