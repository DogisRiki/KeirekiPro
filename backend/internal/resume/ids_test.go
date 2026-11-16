package resume

import (
	"encoding/json"
	"os"
	"regexp"
	"testing"

	"github.com/google/uuid"
)

// idAnswer は、testdata/ids.json の、1つの経路の Java 版の答えである。
type idAnswer struct {
	Status int    `json:"status"`
	ReadID string `json:"readId"`
}

// idPathCase は、testdata/ids.json の、経路の値の1つの書き方と、Java 版の答えである。
type idPathCase struct {
	Value      string   `json:"value"`
	ResumePath idAnswer `json:"resumePath"`
	ItemPath   idAnswer `json:"itemPath"`
	// FromString は、Java 版が読めたものの、その ID の経歴書と資格が無いので 404 で答えた値について、Java 版が読んだ ID である。
	FromString string `json:"fromString"`
}

// idResult は、経路の値を ID として読んだ結果である。Java 版の答えと Go 版の答えを、この形にそろえて比べる。
// read が false のときは、読めない値である。
type idResult struct {
	read bool
	id   string
}

func (r idResult) String() string {
	if !r.read {
		return "読めない"
	}
	return "読めた " + r.id
}

// idResultFromJava は、1つの経路の Java 版の答えを、idResult に直す。
// 経歴書の経路は、読めない値に 404 で答える。項目の経路は、読めない値に 500 で答える。
// Java 版と Go 版の、読めない項目の ID の答えの番号の違いは CB-048 で、resumes_test.go が確かめる。
func idResultFromJava(t *testing.T, c idPathCase, a idAnswer, unreadable int) idResult {
	t.Helper()
	switch {
	case a.Status == 200 && a.ReadID != "":
		return idResult{read: true, id: a.ReadID}
	case a.Status == 404 && c.FromString != "":
		// Java 版は、ほかの ID として読み、その ID の経歴書か資格が無いので 404 で答えた
		return idResult{read: true, id: c.FromString}
	case a.Status == unreadable:
		return idResult{}
	}
	t.Fatalf("書き方 %q の Java 版の答え %d は、控えの形に無い", c.Value, a.Status)
	return idResult{}
}

// idResultFromGo は、経路の値を Go 版の parseID で読んだ結果を、idResult に直す。
func idResultFromGo(value string) idResult {
	id, ok := parseID(value)
	if !ok {
		return idResult{}
	}
	return idResult{read: true, id: id.String()}
}

// resumePathDiffs は、経路の経歴書の ID の書き方のうち、Go 版の答えが Java 版と違う書き方と、違いを載せた一覧の番号である。
var resumePathDiffs = map[string]string{
	" 1b4e28ba-2fa1-11d2-883f-0016d3cca427 ":        "CB-051",
	"1-2-3-4-5":                                     "CB-051",
	"+1-2-3-4-5":                                    "CB-051",
	"1-2-3-4-+5":                                    "CB-051",
	"a-b-c-d-e":                                     "CB-051",
	"A-B-C-D-E":                                     "CB-051",
	"00000001-2-3-4-5":                              "CB-051",
	"000000001-2-3-4-5":                             "CB-051",
	"1-00002-3-4-5":                                 "CB-051",
	"1-2-3-4-0000000000005":                         "CB-051",
	"1-2-3-4-1000000000005":                         "CB-051",
	"1b4e28ba2fa111d2883f0016d3cca427":              "CB-051",
	"{1b4e28ba-2fa1-11d2-883f-0016d3cca427}":        "CB-051",
	"1b4e28ba-2fa1-11d2-883f-0016d3cca42":           "CB-051",
	"1b4e28ba2-fa1-11d2-883f-0016d3cca427":          "CB-051",
	"１-2-3-4-5":                                     "CB-051",
	"urn:uuid:1b4e28ba-2fa1-11d2-883f-0016d3cca427": "CB-051",
}

// itemPathDiffs は、経路の項目の ID の書き方のうち、Go 版の答えが Java 版と違う書き方と、違いを載せた一覧の番号である。
var itemPathDiffs = map[string]string{
	" 1b4e28ba-2fa1-11d2-883f-0016d3cca427":         "CB-051",
	"1b4e28ba-2fa1-11d2-883f-0016d3cca427 ":         "CB-051",
	"\t1b4e28ba-2fa1-11d2-883f-0016d3cca427":        "CB-051",
	"1-2-3-4-5":                                     "CB-051",
	"+1-2-3-4-5":                                    "CB-051",
	"1-2-3-4-+5":                                    "CB-051",
	"a-b-c-d-e":                                     "CB-051",
	"A-B-C-D-E":                                     "CB-051",
	"00000001-2-3-4-5":                              "CB-051",
	"000000001-2-3-4-5":                             "CB-051",
	"1-00002-3-4-5":                                 "CB-051",
	"1-2-3-4-0000000000005":                         "CB-051",
	"1-2-3-4-1000000000005":                         "CB-051",
	"1b4e28ba2fa111d2883f0016d3cca427":              "CB-051",
	"{1b4e28ba-2fa1-11d2-883f-0016d3cca427}":        "CB-051",
	"1b4e28ba-2fa1-11d2-883f-0016d3cca42":           "CB-051",
	"1b4e28ba2-fa1-11d2-883f-0016d3cca427":          "CB-051",
	"１-2-3-4-5":                                     "CB-051",
	"urn:uuid:1b4e28ba-2fa1-11d2-883f-0016d3cca427": "CB-051",
}

// screenID は、画面が経路に入れて送る書き方である。画面は、答えに返った小文字の形の ID だけを送る。
var screenID = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

func loadIDPathCases(t *testing.T) []idPathCase {
	t.Helper()
	b, err := os.ReadFile("testdata/ids.json")
	if err != nil {
		t.Fatal(err)
	}
	var data struct {
		Paths []idPathCase `json:"paths"`
	}
	if err := json.Unmarshal(b, &data); err != nil {
		t.Fatal(err)
	}
	if len(data.Paths) == 0 {
		t.Fatal("控えの経路の値の書き方が無い")
	}
	return data.Paths
}

// checkIDAgainstJava は、1つの書き方の Go 版の答えを、Java 版の答えとテストの中の表と照らす。
func checkIDAgainstJava(t *testing.T, value string, goRes, javaRes idResult, diffs map[string]string) {
	t.Helper()
	id, inTable := diffs[value]
	if goRes == javaRes {
		if inTable {
			t.Errorf("書き方 %q: Go 版の答えは Java 版と同じ %s なのに、表に %s がある", value, goRes, id)
		}
		return
	}
	if !inTable {
		t.Errorf("書き方 %q: Go 版の答え %s が Java 版の答え %s と違うのに、表に無い", value, goRes, javaRes)
		return
	}
	if screenID.MatchString(value) {
		t.Errorf("書き方 %q は画面が送る書き方なのに、Go 版の答え %s が Java 版の答え %s と違う", value, goRes, javaRes)
	}
}

// TestParseID_MatchesJava は、Java 版に送って testdata/ids.json に控えたすべての経路の値の書き方で、
// Java 版が答えに返した小文字の形の ID を Java 版と同じく読み、Java 版と違う答えになる書き方が、
// テストの中の表と合うことを確かめる。
func TestParseID_MatchesJava(t *testing.T) {
	cases := loadIDPathCases(t)

	t.Run("Java 版が答えに返した ID", func(t *testing.T) {
		n := 0
		for _, c := range cases {
			for _, a := range []idAnswer{c.ResumePath, c.ItemPath} {
				if a.ReadID == "" {
					continue
				}
				n++
				if !screenID.MatchString(a.ReadID) {
					t.Errorf("Java 版が答えに返した ID %q が、小文字の形でない", a.ReadID)
				}
				if got := idResultFromGo(a.ReadID); got != (idResult{read: true, id: a.ReadID}) {
					t.Errorf("Java 版が答えに返した ID %q を、Go 版は %s とした", a.ReadID, got)
				}
			}
		}
		if n == 0 {
			t.Error("正解のファイルに、Java 版が答えに返した ID が無い")
		}
	})

	routes := []struct {
		name       string
		answer     func(idPathCase) idAnswer
		unreadable int
		diffs      map[string]string
	}{
		{"経歴書の経路", func(c idPathCase) idAnswer { return c.ResumePath }, 404, resumePathDiffs},
		{"項目の経路", func(c idPathCase) idAnswer { return c.ItemPath }, 500, itemPathDiffs},
	}
	for _, r := range routes {
		t.Run(r.name, func(t *testing.T) {
			seen := map[string]bool{}
			for _, c := range cases {
				seen[c.Value] = true
				javaRes := idResultFromJava(t, c, r.answer(c), r.unreadable)
				checkIDAgainstJava(t, c.Value, idResultFromGo(c.Value), javaRes, r.diffs)
			}
			for value := range r.diffs {
				if !seen[value] {
					t.Errorf("表の書き方 %q が、正解のファイルに無い", value)
				}
			}
		})
	}
}

// TestParseID_DiffTableInChangedBehaviors は、経路の ID のテストの中の表の番号が、変えた動きの一覧にあることを確かめる。
func TestParseID_DiffTableInChangedBehaviors(t *testing.T) {
	t.Run("経歴書の経路", func(t *testing.T) { checkDiffTableInChangedBehaviors(t, resumePathDiffs) })
	t.Run("項目の経路", func(t *testing.T) { checkDiffTableInChangedBehaviors(t, itemPathDiffs) })
}

// TestCompareJavaUUID_SignedOrder は、compareJavaUUID が、java.util.UUID.compareTo と同じく、
// 上位の64ビットと下位の64ビットを符号付きの整数として比べ、8 から f で始まる UUID を 0 から 7 で始まる UUID より前に並べることを確かめる。
func TestCompareJavaUUID_SignedOrder(t *testing.T) {
	tests := []struct {
		name string
		a, b string
		want int
	}{
		{"上位の先頭が 8 以上の UUID は、7 以下の UUID より前", "80000000-0000-0000-0000-000000000000", "7fffffff-ffff-ffff-ffff-ffffffffffff", -1},
		{"上位の先頭が f の UUID は、0 の UUID より前", "ffffffff-ffff-ffff-ffff-ffffffffffff", "00000000-0000-0000-0000-000000000001", -1},
		{"上位が同じなら、下位の先頭が 8 以上の UUID が前", "00000000-0000-0000-8000-000000000000", "00000000-0000-0000-7fff-ffffffffffff", -1},
		{"上位が同じで下位の符号が同じなら、小さいほうが前", "00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002", -1},
		{"上位の符号が同じなら、小さいほうが前", "00000001-0000-0000-ffff-ffffffffffff", "00000002-0000-0000-0000-000000000000", -1},
		{"同じ UUID", "1b4e28ba-2fa1-11d2-883f-0016d3cca427", "1b4e28ba-2fa1-11d2-883f-0016d3cca427", 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a, b := uuid.MustParse(tt.a), uuid.MustParse(tt.b)
			if got := compareJavaUUID(a, b); got != tt.want {
				t.Errorf("compareJavaUUID(%s, %s) = %d, want %d", tt.a, tt.b, got, tt.want)
			}
			if got := compareJavaUUID(b, a); got != -tt.want {
				t.Errorf("compareJavaUUID(%s, %s) = %d, want %d", tt.b, tt.a, got, -tt.want)
			}
		})
	}
}
