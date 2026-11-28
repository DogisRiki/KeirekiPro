package resume

import (
	"bytes"
	"cmp"
	"slices"

	"github.com/google/uuid"
	"golang.org/x/text/collate"
	"golang.org/x/text/language"
)

// sortEntries は、経歴書の6つの欄の項目を並べる。項目の並びは画面と PDF に見える。
//   - 職歴とプロジェクト: 期間の新しい順(comparePeriodDesc)、同じなら ID の順
//   - 資格: 取得の年月の新しい順、同じなら ID の順
//   - ポートフォリオと SNS と自己PR: 名前(自己PR は題)の日本語の並べ方の順、同じなら ID の順
//
// 日本語の並べ方は golang.org/x/text/collate を使う。ID の順は compareID の順である。
func sortEntries(r *Resume) {
	slices.SortFunc(r.Careers, func(a, b Career) int {
		return cmp.Or(comparePeriodDesc(a.Period, b.Period), compareID(a.ID, b.ID))
	})
	slices.SortFunc(r.Projects, func(a, b Project) int {
		return cmp.Or(comparePeriodDesc(a.Period, b.Period), compareID(a.ID, b.ID))
	})
	slices.SortFunc(r.Certifications, func(a, b Certification) int {
		return cmp.Or(compareYearMonth(b.Date, a.Date), compareID(a.ID, b.ID))
	})
	// collate.Collator は、比べるときに中の作業の領域を書き換えるので、並べるたびに作る。
	c := collate.New(language.Japanese)
	slices.SortFunc(r.Portfolios, func(a, b Portfolio) int {
		return cmp.Or(c.CompareString(a.Name, b.Name), compareID(a.ID, b.ID))
	})
	slices.SortFunc(r.SnsPlatforms, func(a, b SnsPlatform) int {
		return cmp.Or(c.CompareString(a.Name, b.Name), compareID(a.ID, b.ID))
	})
	slices.SortFunc(r.SelfPromotions, func(a, b SelfPromotion) int {
		return cmp.Or(c.CompareString(a.Title, b.Title), compareID(a.ID, b.ID))
	})
}

// compareID は、ID a と b を、16バイトの値として先頭のバイトから比べる。ID を文字列にしたときの辞書の順と同じである。
func compareID(a, b uuid.UUID) int {
	return bytes.Compare(a[:], b[:])
}

// comparePeriodDesc は、期間 a を b より前に並べるときに負の数を返す。
// 継続中の期間を先に並べる。2つとも継続中なら、開始の年月の新しい順に並べる。
// 2つとも継続中でなければ、終了の年月の新しい順に並べ、終了の年月が同じなら開始の年月の新しい順に並べる。終了の年月が無い期間は後ろに並べる。
func comparePeriodDesc(a, b Period) int {
	if a.Active != b.Active {
		if a.Active {
			return -1
		}
		return 1
	}
	if a.Active {
		return compareYearMonth(b.StartDate, a.StartDate)
	}
	return cmp.Or(compareEndDateDesc(a.EndDate, b.EndDate), compareYearMonth(b.StartDate, a.StartDate))
}

// compareEndDateDesc は、終了の年月を新しい順に比べる。終了の年月が無いほうを後ろにする。
func compareEndDateDesc(a, b *YearMonth) int {
	switch {
	case a == nil && b == nil:
		return 0
	case a == nil:
		return 1
	case b == nil:
		return -1
	}
	return compareYearMonth(*b, *a)
}

// compareYearMonth は、年月 a が b より前なら負の数を、後なら正の数を、同じなら0を返す。
func compareYearMonth(a, b YearMonth) int {
	return cmp.Or(cmp.Compare(a.Year, b.Year), cmp.Compare(a.Month, b.Month))
}
