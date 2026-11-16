package resume

import (
	"encoding/json"
	"os"
	"slices"
	"strconv"
	"testing"
	"unicode/utf16"
)

// linkJavaCase は、testdata/link.json の1つのリンクの値と、Java 版の答えである。
type linkJavaCase struct {
	Input  string              `json:"input"`
	Status int                 `json:"status"`
	Errors map[string][]string `json:"errors"`
}

// linkJDKCase は、testdata/link_jdk.json の1つの値と、JDK で控えた答えである。
// Valid は、リンクの判定と、IPAddressUtil の部品の判定の答えである。
// Want は、Integer.parseInt の答えで、数値か、NumberFormatException を表す "NFE" である。
type linkJDKCase struct {
	Input string          `json:"input"`
	Valid bool            `json:"valid"`
	Want  json.RawMessage `json:"want"`
}

// linkJDKData は、testdata/link_jdk.json の全体である。
type linkJDKData struct {
	Cases    []linkJDKCase `json:"cases"`
	IPv6     []linkJDKCase `json:"ipv6"`
	Host     []linkJDKCase `json:"host"`
	UserInfo []linkJDKCase `json:"userinfo"`
	Auth     []linkJDKCase `json:"auth"`
	Int      []linkJDKCase `json:"int"`
}

func loadLinkJavaCases(t *testing.T) []linkJavaCase {
	t.Helper()
	b, err := os.ReadFile("testdata/link.json")
	if err != nil {
		t.Fatal(err)
	}
	var data struct {
		Cases []linkJavaCase `json:"cases"`
	}
	if err := json.Unmarshal(b, &data); err != nil {
		t.Fatal(err)
	}
	if len(data.Cases) == 0 {
		t.Fatal("控えのリンクの値が無い")
	}
	return data.Cases
}

func loadLinkJDKData(t *testing.T) linkJDKData {
	t.Helper()
	b, err := os.ReadFile("testdata/link_jdk.json")
	if err != nil {
		t.Fatal(err)
	}
	var data linkJDKData
	if err := json.Unmarshal(b, &data); err != nil {
		t.Fatal(err)
	}
	for name, cases := range map[string][]linkJDKCase{
		"cases": data.Cases, "ipv6": data.IPv6, "host": data.Host, "userinfo": data.UserInfo, "auth": data.Auth, "int": data.Int,
	} {
		if len(cases) == 0 {
			t.Fatalf("控えの %s の値が無い", name)
		}
	}
	return data
}

// TestLink_MatchesJava は、isHibernateHTTPSURL が、Java 版に送って控えたすべてのリンクの値と、
// JDK で判定して控えたすべてのリンクの値で、Java 版と同じ判定をすることを確かめる。
func TestLink_MatchesJava(t *testing.T) {
	t.Run("Java 版に送った値", func(t *testing.T) {
		valid, invalid := 0, 0
		for _, c := range loadLinkJavaCases(t) {
			// Java 版は、リンクが https の形の URL でないときに、この文言を返す。
			// 入力必須と長さの文言だけが出た値は、https の形の判定に通っている
			want := !slices.Contains(c.Errors["link"], MessageLinkNotHTTPS)
			if c.Status != 201 && c.Status != 400 {
				t.Fatalf("値 %q の Java 版の答え %d は、控えの形に無い", c.Input, c.Status)
			}
			if want {
				valid++
			} else {
				invalid++
			}
			if got := isHibernateHTTPSURL(c.Input); got != want {
				t.Errorf("isHibernateHTTPSURL(%q) = %v, Java 版は %v", c.Input, got, want)
			}
		}
		if valid == 0 || invalid == 0 {
			t.Errorf("控えに、Java 版が通した値(%d 件)と断った値(%d 件)の両方が要る", valid, invalid)
		}
	})

	t.Run("JDK で判定した値", func(t *testing.T) {
		valid, invalid := 0, 0
		for _, c := range loadLinkJDKData(t).Cases {
			if c.Valid {
				valid++
			} else {
				invalid++
			}
			if got := isHibernateHTTPSURL(c.Input); got != c.Valid {
				t.Errorf("isHibernateHTTPSURL(%q) = %v, JDK は %v", c.Input, got, c.Valid)
			}
		}
		if valid == 0 || invalid == 0 {
			t.Errorf("控えに、JDK が通した値(%d 件)と断った値(%d 件)の両方が要る", valid, invalid)
		}
	})
}

// TestLink_JDKParts は、リンクの判定が使う JDK の部品の写しが、JDK で控えた答えと同じ答えを返すことを確かめる。
func TestLink_JDKParts(t *testing.T) {
	data := loadLinkJDKData(t)
	parts := []struct {
		name  string
		cases []linkJDKCase
		fn    func([]uint16) bool
	}{
		{"IPAddressUtil.isIPv6LiteralAddress", data.IPv6, javaIsIPv6LiteralAddress},
		{"IPAddressUtil.checkHostString", data.Host, javaCheckHost},
		{"IPAddressUtil.checkUserInfo", data.UserInfo, javaCheckUserInfo},
		{"IPAddressUtil.checkAuth", data.Auth, javaCheckAuth},
	}
	for _, p := range parts {
		t.Run(p.name, func(t *testing.T) {
			for _, c := range p.cases {
				if got := p.fn(javaChars(c.Input)); got != c.Valid {
					t.Errorf("%s(%q) = %v, JDK は %v", p.name, c.Input, got, c.Valid)
				}
			}
		})
	}

	t.Run("Integer.parseInt", func(t *testing.T) {
		for _, c := range data.Int {
			var want string
			if err := json.Unmarshal(c.Want, &want); err != nil {
				// 数値の答えは、文字列に直して比べる
				want = string(c.Want)
			}
			got := "NFE"
			if v, ok := javaParseInt(javaChars(c.Input)); ok {
				got = strconv.Itoa(v)
			}
			if got != want {
				t.Errorf("Integer.parseInt(%q) = %s, JDK は %s", c.Input, got, want)
			}
		}
	})
}

// TestJavaChars は、javaChars が、Go の文字列を Java の String と同じ UTF-16 の単位の並びに直すことを確かめる。
func TestJavaChars(t *testing.T) {
	got := javaChars("aé\U0001F600")
	want := []uint16{'a', 0xe9, 0xd83d, 0xde00}
	if !slices.Equal(got, want) {
		t.Errorf("javaChars = %x, want %x", got, want)
	}
	if s := string(utf16.Decode(got)); s != "aé\U0001F600" {
		t.Errorf("元に戻した文字列が %q", s)
	}
}
