package resume

import (
	"fmt"
	"slices"
	"testing"

	"github.com/google/uuid"
)

// permuted は、項目の並び entries を、並べ替えの順 perm のとおりに並べ直した写しを返す。
func permuted[E any](entries []E, perm []int) []E {
	out := make([]E, len(perm))
	for i, j := range perm {
		out[i] = entries[j]
	}
	return out
}

// orderPermutations は、n 個の項目の並べ替えの順を返す。元の順と、逆の順を1つずつずらした n 通りの順である。
func orderPermutations(n int) [][]int {
	identity := make([]int, n)
	for i := range identity {
		identity[i] = i
	}
	perms := [][]int{identity}
	for k := range n {
		p := make([]int, n)
		for i := range p {
			p[i] = n - 1 - (i+k)%n
		}
		perms = append(perms, p)
	}
	return perms
}

// ids は、項目の並びの ID を並びの順に返す。
func ids[E any](entries []E, id func(E) uuid.UUID) []uuid.UUID {
	out := make([]uuid.UUID, len(entries))
	for i, e := range entries {
		out[i] = id(e)
	}
	return out
}

// checkSorted は、欄の項目を並べたい順 want から並べ替えた、どの並びを sortEntries に渡しても、want の順に並べることを確かめる。
// set は経歴書の欄に項目を入れ、get は経歴書の欄の項目を取り出す。
func checkSorted[E any](t *testing.T, section string, want []E, set func(*Resume, []E), get func(Resume) []E, id func(E) uuid.UUID) {
	t.Helper()
	wantIDs := ids(want, id)
	for _, perm := range orderPermutations(len(want)) {
		var r Resume
		set(&r, permuted(want, perm))
		sortEntries(&r)
		if got := ids(get(r), id); !slices.Equal(got, wantIDs) {
			t.Errorf("%s の並び(並べ替えの順 %v)\n got: %v\nwant: %v", section, perm, got, wantIDs)
		}
	}
}

// orderID は、n 番目の項目の ID を返す。
func orderID(n int) uuid.UUID {
	return uuid.MustParse(fmt.Sprintf("00000000-0000-4000-8000-%012d", n))
}

// tieLow と tieHigh は、並べ方の値が同じ項目どうしの ID の順を確かめる2つの ID である。
// 2つは先頭のバイトだけが違い、Go 版はバイトの順に比べるので tieLow を先に並べる。
// Java 版は上位の64ビットを符号付きの整数として比べ、tieHigh を先に並べていた(変えた動きの一覧の CB-111)。
var (
	tieLow  = uuid.MustParse("7f000000-0000-4000-8000-000000000001")
	tieHigh = uuid.MustParse("80000000-0000-4000-8000-000000000001")
)

// TestSortEntries_Periods は、職歴とプロジェクトを、継続中の期間を先に、開始の年月の新しい順に並べ、
// 継続中でない期間を終了の年月の新しい順に、終了の年月が同じなら開始の年月の新しい順に並べ、期間が同じなら ID の順に並べることを確かめる。
func TestSortEntries_Periods(t *testing.T) {
	checkDiffTableInChangedBehaviors(t, map[string]string{"期間が同じ職歴とプロジェクト": "CB-111"})
	periods := []struct {
		id     uuid.UUID
		period Period
	}{
		{orderID(1), Period{StartDate: YearMonth{Year: 2020, Month: 4}, Active: true}},
		{orderID(2), Period{StartDate: YearMonth{Year: 2018, Month: 1}, Active: true}},
		{orderID(3), Period{StartDate: YearMonth{Year: 2016, Month: 1}, EndDate: yearMonth(2019, 12)}},
		{orderID(4), Period{StartDate: YearMonth{Year: 2015, Month: 1}, EndDate: yearMonth(2019, 12)}},
		{orderID(5), Period{StartDate: YearMonth{Year: 2017, Month: 1}, EndDate: yearMonth(2019, 3)}},
		{tieLow, Period{StartDate: YearMonth{Year: 2009, Month: 1}, EndDate: yearMonth(2010, 3)}},
		{tieHigh, Period{StartDate: YearMonth{Year: 2009, Month: 1}, EndDate: yearMonth(2010, 3)}},
	}
	var careers []Career
	var projects []Project
	for _, p := range periods {
		careers = append(careers, Career{ID: p.id, Period: p.period})
		projects = append(projects, Project{ID: p.id, Period: p.period})
	}
	checkSorted(t, "職歴", careers,
		func(r *Resume, e []Career) { r.Careers = e }, func(r Resume) []Career { return r.Careers }, func(e Career) uuid.UUID { return e.ID })
	checkSorted(t, "プロジェクト", projects,
		func(r *Resume, e []Project) { r.Projects = e }, func(r Resume) []Project { return r.Projects }, func(e Project) uuid.UUID { return e.ID })
}

// TestSortEntries_Certifications は、資格を、取得の年月の新しい順に並べ、取得の年月が同じなら ID の順に並べることを確かめる。
func TestSortEntries_Certifications(t *testing.T) {
	checkDiffTableInChangedBehaviors(t, map[string]string{"取得の年月が同じ資格": "CB-111"})
	want := []Certification{
		{ID: orderID(1), Date: YearMonth{Year: 2022, Month: 4}},
		{ID: orderID(2), Date: YearMonth{Year: 2022, Month: 3}},
		{ID: orderID(3), Date: YearMonth{Year: 2021, Month: 12}},
		{ID: tieLow, Date: YearMonth{Year: 2019, Month: 5}},
		{ID: tieHigh, Date: YearMonth{Year: 2019, Month: 5}},
	}
	checkSorted(t, "資格", want,
		func(r *Resume, e []Certification) { r.Certifications = e }, func(r Resume) []Certification { return r.Certifications },
		func(e Certification) uuid.UUID { return e.ID })
}

// nameOrder は、名前を Go の日本語の並べ方(golang.org/x/text/collate)で並べた順である。
// 半角のカタカナの「ｱｲｳ」の位置は、変えた動きの一覧の CB-001 のとおり Java 版と違う。
var nameOrder = []string{"1番", "abc", "ABC", "github", "GitHub", "Zenn", "ｱｲｳ", "あいう", "アイウ", "漢字"}

// TestSortEntries_Names は、ポートフォリオと SNS を名前の、自己PR を題の、日本語の並べ方の順に並べ、
// 名前か題が同じなら ID の順に並べることを確かめる。
func TestSortEntries_Names(t *testing.T) {
	checkDiffTableInChangedBehaviors(t, map[string]string{"名前が同じポートフォリオと SNS と、題が同じ自己PR": "CB-111"})
	var portfolios []Portfolio
	var sns []SnsPlatform
	var selfPromotions []SelfPromotion
	add := func(id uuid.UUID, name string) {
		portfolios = append(portfolios, Portfolio{ID: id, Name: name})
		sns = append(sns, SnsPlatform{ID: id, Name: name})
		selfPromotions = append(selfPromotions, SelfPromotion{ID: id, Title: name})
	}
	for i, name := range nameOrder {
		add(orderID(i+1), name)
	}
	add(tieLow, "同じ名前")
	add(tieHigh, "同じ名前")
	checkSorted(t, "ポートフォリオ", portfolios,
		func(r *Resume, e []Portfolio) { r.Portfolios = e }, func(r Resume) []Portfolio { return r.Portfolios }, func(e Portfolio) uuid.UUID { return e.ID })
	checkSorted(t, "SNS", sns,
		func(r *Resume, e []SnsPlatform) { r.SnsPlatforms = e }, func(r Resume) []SnsPlatform { return r.SnsPlatforms }, func(e SnsPlatform) uuid.UUID { return e.ID })
	checkSorted(t, "自己PR", selfPromotions,
		func(r *Resume, e []SelfPromotion) { r.SelfPromotions = e }, func(r Resume) []SelfPromotion { return r.SelfPromotions },
		func(e SelfPromotion) uuid.UUID { return e.ID })
}

// TestOrder_EndDateMissing は、継続中でない職歴とプロジェクトに終了の年月が無いとき、
// 終了の年月が無い項目を後ろに並べ、2つとも無ければ開始の年月の新しい順に並べることを確かめる。
func TestOrder_EndDateMissing(t *testing.T) {
	idA := uuid.MustParse("00000000-0000-4000-8000-00000000000a")
	idB := uuid.MustParse("00000000-0000-4000-8000-00000000000b")
	idC := uuid.MustParse("00000000-0000-4000-8000-00000000000c")
	ended := Period{StartDate: YearMonth{Year: 2010, Month: 1}, EndDate: yearMonth(2011, 1)}
	noEndOld := Period{StartDate: YearMonth{Year: 2015, Month: 1}}
	noEndNew := Period{StartDate: YearMonth{Year: 2016, Month: 1}}
	want := []uuid.UUID{idA, idC, idB}
	for _, perm := range orderPermutations(3) {
		r := Resume{
			Careers:  permuted([]Career{{ID: idA, Period: ended}, {ID: idB, Period: noEndOld}, {ID: idC, Period: noEndNew}}, perm),
			Projects: permuted([]Project{{ID: idA, Period: ended}, {ID: idB, Period: noEndOld}, {ID: idC, Period: noEndNew}}, perm),
		}
		sortEntries(&r)
		if got := ids(r.Careers, func(e Career) uuid.UUID { return e.ID }); !slices.Equal(got, want) {
			t.Errorf("職歴の並び(並べ替えの順 %v)\n got: %v\nwant: %v", perm, got, want)
		}
		if got := ids(r.Projects, func(e Project) uuid.UUID { return e.ID }); !slices.Equal(got, want) {
			t.Errorf("プロジェクトの並び(並べ替えの順 %v)\n got: %v\nwant: %v", perm, got, want)
		}
	}
}

// TestOrder_ActiveIgnoresEndDate は、2つとも継続中の職歴とプロジェクトを、
// 終了の年月を見ずに開始の年月の新しい順に並べることを確かめる。継続中の期間の終了の年月は値の決まりで断るので、
// 終了の年月を見ないことは、終了の年月が入った継続中の期間でしか確かめられない。
func TestOrder_ActiveIgnoresEndDate(t *testing.T) {
	idA := uuid.MustParse("00000000-0000-4000-8000-00000000000a")
	idB := uuid.MustParse("00000000-0000-4000-8000-00000000000b")
	// 開始の新しい idA の終了の年月を、idB の終了の年月より古くする。終了の年月を見ると idB が先になる。
	newer := Period{StartDate: YearMonth{Year: 2020, Month: 1}, EndDate: yearMonth(2021, 1), Active: true}
	older := Period{StartDate: YearMonth{Year: 2015, Month: 1}, EndDate: yearMonth(2022, 1), Active: true}
	want := []uuid.UUID{idA, idB}
	for _, perm := range orderPermutations(2) {
		r := Resume{
			Careers:  permuted([]Career{{ID: idA, Period: newer}, {ID: idB, Period: older}}, perm),
			Projects: permuted([]Project{{ID: idA, Period: newer}, {ID: idB, Period: older}}, perm),
		}
		sortEntries(&r)
		if got := ids(r.Careers, func(e Career) uuid.UUID { return e.ID }); !slices.Equal(got, want) {
			t.Errorf("職歴の並び(並べ替えの順 %v)\n got: %v\nwant: %v", perm, got, want)
		}
		if got := ids(r.Projects, func(e Project) uuid.UUID { return e.ID }); !slices.Equal(got, want) {
			t.Errorf("プロジェクトの並び(並べ替えの順 %v)\n got: %v\nwant: %v", perm, got, want)
		}
	}
}
