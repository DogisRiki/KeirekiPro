package resume

import (
	"encoding/json"
	"os"
	"slices"
	"testing"

	"github.com/google/uuid"
)

// orderEntry は、testdata/order.json の1つの項目である。項目の欄のうち、並べ方が見る欄だけを読む。
type orderEntry struct {
	ID        uuid.UUID     `json:"id"`
	Active    bool          `json:"active"`
	StartDate jsonYearMonth `json:"startDate"`
	EndDate   jsonYearMonth `json:"endDate"`
	Date      jsonYearMonth `json:"date"`
	Name      string        `json:"name"`
	Title     string        `json:"title"`
}

// orderFile は、testdata/order.json の、Java 版が返した6つの欄の項目の並びである。
type orderFile struct {
	Careers        []orderEntry `json:"careers"`
	Projects       []orderEntry `json:"projects"`
	Certifications []orderEntry `json:"certifications"`
	Portfolios     []orderEntry `json:"portfolios"`
	SnsPlatforms   []orderEntry `json:"snsPlatforms"`
	SelfPromotions []orderEntry `json:"selfPromotions"`
}

// loadOrderJSON は、testdata/order.json を読む。
func loadOrderJSON(t *testing.T) orderFile {
	t.Helper()
	b, err := os.ReadFile("testdata/order.json")
	if err != nil {
		t.Fatalf("testdata/order.json を読めない: %v", err)
	}
	var f orderFile
	if err := json.Unmarshal(b, &f); err != nil {
		t.Fatalf("testdata/order.json の JSON を読めない: %v", err)
	}
	return f
}

// period は、控えの項目の期間を、経歴書の期間の型に直す。
func (e orderEntry) period() Period {
	p := Period{StartDate: e.StartDate.Value, Active: e.Active}
	if e.EndDate.Present {
		end := e.EndDate.Value
		p.EndDate = &end
	}
	return p
}

// permuted は、項目の並び entries を、並べ替えの順 perm のとおりに並べ直した写しを返す。
func permuted[E any](entries []E, perm []int) []E {
	out := make([]E, len(perm))
	for i, j := range perm {
		out[i] = entries[j]
	}
	return out
}

// orderPermutations は、n 個の項目の並べ替えの順を返す。控えの順と、逆の順を1つずつずらした n 通りの順である。
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

// goNameOrder は、控えのポートフォリオと SNS の名前と自己PR の題を、Go の日本語の並べ方(golang.org/x/text/collate)で並べた順である。
// 名前か題が違う項目どうしの並びは、変えた動きの一覧の CB-001 のとおり、Java 版と違ってよい。
// Java 版は半角のカタカナの「ｱｲｳ」を最後に並べ、Go 版は「Zenn」と「あいう」のあいだに並べる。そのほかの名前の順は Java 版と同じである。
var goNameOrder = []string{"1番", "abc", "ABC", "github", "GitHub", "Zenn", "ｱｲｳ", "あいう", "アイウ", "漢字", "同じ名前"}

// wantByGoNameOrder は、控えの項目を goNameOrder の名前の順に並べ、名前が同じ項目どうしは控えの順(Java 版の ID の順)のまま並べた ID を返す。
func wantByGoNameOrder(t *testing.T, entries []orderEntry, name func(orderEntry) string) []uuid.UUID {
	t.Helper()
	var want []uuid.UUID
	for _, n := range goNameOrder {
		for _, e := range entries {
			if name(e) == n {
				want = append(want, e.ID)
			}
		}
	}
	if len(want) != len(entries) {
		t.Fatalf("控えに goNameOrder に無い名前がある: 控えの項目 %d 件のうち %d 件だけが goNameOrder の名前", len(entries), len(want))
	}
	return want
}

// TestOrder_MatchesJava は、6つの欄の項目を、どの順で受け取っても、Java 版が返した並び(testdata/order.json)と同じ順に並べることを確かめる
// (要件1の受入基準1)。ポートフォリオと SNS と自己PR は、名前か題が同じ項目どうしの並びを Java 版と比べ、名前か題が違う項目どうしの並びは、
// 変えた動きの一覧の CB-001 のとおり Go の日本語の並べ方の順(goNameOrder)と比べる。
func TestOrder_MatchesJava(t *testing.T) {
	f := loadOrderJSON(t)
	byName := func(e orderEntry) string { return e.Name }
	byTitle := func(e orderEntry) string { return e.Title }
	want := map[string][]uuid.UUID{
		"職歴":      ids(f.Careers, func(e orderEntry) uuid.UUID { return e.ID }),
		"プロジェクト":  ids(f.Projects, func(e orderEntry) uuid.UUID { return e.ID }),
		"資格":      ids(f.Certifications, func(e orderEntry) uuid.UUID { return e.ID }),
		"ポートフォリオ": wantByGoNameOrder(t, f.Portfolios, byName),
		"SNS":     wantByGoNameOrder(t, f.SnsPlatforms, byName),
		"自己PR":    wantByGoNameOrder(t, f.SelfPromotions, byTitle),
	}

	var r Resume
	for _, e := range f.Careers {
		r.Careers = append(r.Careers, Career{ID: e.ID, CompanyName: e.Name, Period: e.period()})
	}
	for _, e := range f.Projects {
		r.Projects = append(r.Projects, Project{ID: e.ID, Name: e.Name, Period: e.period()})
	}
	for _, e := range f.Certifications {
		r.Certifications = append(r.Certifications, Certification{ID: e.ID, Name: e.Name, Date: e.Date.Value})
	}
	for _, e := range f.Portfolios {
		r.Portfolios = append(r.Portfolios, Portfolio{ID: e.ID, Name: e.Name})
	}
	for _, e := range f.SnsPlatforms {
		r.SnsPlatforms = append(r.SnsPlatforms, SnsPlatform{ID: e.ID, Name: e.Name})
	}
	for _, e := range f.SelfPromotions {
		r.SelfPromotions = append(r.SelfPromotions, SelfPromotion{ID: e.ID, Title: e.Title})
	}

	check := func(t *testing.T, section string, got []uuid.UUID) {
		t.Helper()
		if !slices.Equal(got, want[section]) {
			t.Errorf("%s の並び\n got: %v\nwant: %v", section, got, want[section])
		}
	}
	// 6つの欄の項目の数は、控えでは同じではないので、欄ごとに並べ替えの順を作る。
	for i := range 20 {
		in := Resume{
			Careers:        permuted(r.Careers, orderPermutations(len(r.Careers))[i%(len(r.Careers)+1)]),
			Projects:       permuted(r.Projects, orderPermutations(len(r.Projects))[i%(len(r.Projects)+1)]),
			Certifications: permuted(r.Certifications, orderPermutations(len(r.Certifications))[i%(len(r.Certifications)+1)]),
			Portfolios:     permuted(r.Portfolios, orderPermutations(len(r.Portfolios))[i%(len(r.Portfolios)+1)]),
			SnsPlatforms:   permuted(r.SnsPlatforms, orderPermutations(len(r.SnsPlatforms))[i%(len(r.SnsPlatforms)+1)]),
			SelfPromotions: permuted(r.SelfPromotions, orderPermutations(len(r.SelfPromotions))[i%(len(r.SelfPromotions)+1)]),
		}
		sortEntries(&in)
		check(t, "職歴", ids(in.Careers, func(e Career) uuid.UUID { return e.ID }))
		check(t, "プロジェクト", ids(in.Projects, func(e Project) uuid.UUID { return e.ID }))
		check(t, "資格", ids(in.Certifications, func(e Certification) uuid.UUID { return e.ID }))
		check(t, "ポートフォリオ", ids(in.Portfolios, func(e Portfolio) uuid.UUID { return e.ID }))
		check(t, "SNS", ids(in.SnsPlatforms, func(e SnsPlatform) uuid.UUID { return e.ID }))
		check(t, "自己PR", ids(in.SelfPromotions, func(e SelfPromotion) uuid.UUID { return e.ID }))
		if t.Failed() {
			t.Fatalf("並べ替えの順 %d 番目で並びが違う", i)
		}
	}
}

// TestOrder_EndDateMissing は、継続中でない職歴とプロジェクトに終了の年月が無いとき、Java 版の ResumeEntryOrderPolicy と同じく、
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

// TestOrder_ActiveIgnoresEndDate は、2つとも継続中の職歴とプロジェクトを、Java 版の ResumeEntryOrderPolicy と同じく、
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
