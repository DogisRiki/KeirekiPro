package resume

import (
	"regexp"
	"testing"
)

// screenID は、画面が経路に入れて送る書き方である。画面は、答えに返った小文字の形の ID だけを送る。
var screenID = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

// idPathTests は、経路の値の書き方と、parseID が読んだ ID である。読めない値の want は "" である。
// cb は、Java 版と答えが違い、変えた動きの一覧に載せた番号である。
var idPathTests = []struct {
	cb, value, want string
}{
	{"", "1b4e28ba-2fa1-11d2-883f-0016d3cca427", "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"", "1B4E28BA-2FA1-11D2-883F-0016D3CCA427", "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"", "1B4E28ba-2FA1-11d2-883F-0016D3CCA427", "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"", "ffffffff-ffff-ffff-ffff-ffffffffffff", "ffffffff-ffff-ffff-ffff-ffffffffffff"},
	{"", "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", "ffffffff-ffff-ffff-ffff-ffffffffffff"},
	// uuid.Parse は、36字の形のほかに、区切りの無い32字の形と、波括弧で囲んだ38字の形と、urn:uuid: を付けた形を読む。
	// 38字の形は、最初と最後の1字を確かめずに外すので、前後に1つずつ空白を付けた値も読む
	{"CB-051", "1b4e28ba2fa111d2883f0016d3cca427", "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"CB-051", "{1b4e28ba-2fa1-11d2-883f-0016d3cca427}", "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"CB-051", "urn:uuid:1b4e28ba-2fa1-11d2-883f-0016d3cca427", "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"CB-051", " 1b4e28ba-2fa1-11d2-883f-0016d3cca427 ", "1b4e28ba-2fa1-11d2-883f-0016d3cca427"},
	{"CB-051", " 1b4e28ba-2fa1-11d2-883f-0016d3cca427", ""},
	{"CB-051", "1b4e28ba-2fa1-11d2-883f-0016d3cca427 ", ""},
	{"CB-051", "\t1b4e28ba-2fa1-11d2-883f-0016d3cca427", ""},
	{"", "　1b4e28ba-2fa1-11d2-883f-0016d3cca427", ""},
	// 区切りごとの桁の数が決まった形でない値は読まない
	{"CB-051", "1-2-3-4-5", ""},
	{"CB-051", "+1-2-3-4-5", ""},
	{"", "-1-2-3-4-5", ""},
	{"CB-051", "1-2-3-4-+5", ""},
	{"CB-051", "a-b-c-d-e", ""},
	{"CB-051", "A-B-C-D-E", ""},
	{"CB-051", "00000001-2-3-4-5", ""},
	{"CB-051", "000000001-2-3-4-5", ""},
	{"CB-051", "1-00002-3-4-5", ""},
	{"CB-051", "1-2-3-4-0000000000005", ""},
	{"CB-051", "1-2-3-4-1000000000005", ""},
	{"", "1-2-3-4-5-6", ""},
	{"", "1-2-3-4", ""},
	{"", "-1-2-3-4", ""},
	{"", "1--3-4-5", ""},
	{"", "1-2-3-4-", ""},
	{"", "0x1-2-3-4-5", ""},
	{"", "1-2-3-4-0x5", ""},
	{"CB-051", "１-2-3-4-5", ""},
	{"", "1b4e28ba-2fa1-11d2-883f-0016d3cca42g", ""},
	{"", "1b4e28ba-2fa1-11d2-883f-0016d3cca4270", ""},
	{"CB-051", "1b4e28ba-2fa1-11d2-883f-0016d3cca42", ""},
	{"", "1b4e28ba-2fa1-11d2-883f0016d3cca427", ""},
	{"CB-051", "1b4e28ba2-fa1-11d2-883f-0016d3cca427", ""},
}

// TestParseID は、経路の値を parseID が uuid.Parse で読み、小文字の形の ID にすることと、
// Java 版と答えが違う書き方が、画面が送る書き方でないことを確かめる。
func TestParseID(t *testing.T) {
	for _, tt := range idPathTests {
		got := ""
		if id, ok := parseID(tt.value); ok {
			got = id.String()
		}
		if got != tt.want {
			t.Errorf("parseID(%q) = %q, want %q", tt.value, got, tt.want)
		}
		if tt.cb != "" && screenID.MatchString(tt.value) {
			t.Errorf("書き方 %q は画面が送る書き方なのに、%s がある", tt.value, tt.cb)
		}
	}
}

// TestParseID_DiffTableInChangedBehaviors は、経路の ID の表の番号が、変えた動きの一覧にあることを確かめる。
func TestParseID_DiffTableInChangedBehaviors(t *testing.T) {
	table := map[string]string{}
	for _, tt := range idPathTests {
		if tt.cb != "" {
			table[tt.value] = tt.cb
		}
	}
	checkDiffTableInChangedBehaviors(t, table)
}
