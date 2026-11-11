package auth

import (
	"bufio"
	"bytes"
	"io/fs"
	"os"
	"strconv"
	"strings"
	"testing"
)

// testdata/springquery/vectors.txt は、testdata/springquery/Gen.java が、Java 版と同じ Spring 7.0.10 の
// UriComponentsBuilder の fromUriString と queryParam と toUriString で書いた URL である。
// 1行が1つの URL で、Spring が書いた URL のあとに、タブで区切って、項目の名前と値を Go の文字列の形で交互に並べてある。
// ASCII のすべての文字を値と名前に置いた行と、空白、`+`、`/`、`:`、`!$'()*+,;:@/?`、日本語、絵文字を含む値の行と、
// Java 版の OidcClient と同じ7つの項目を並べた行がある。
const springQueryEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"

func TestSpringQuery_MatchesSpring(t *testing.T) {
	b, err := fs.ReadFile(os.DirFS("testdata/springquery"), "vectors.txt")
	if err != nil {
		t.Fatal(err)
	}
	sc := bufio.NewScanner(bytes.NewReader(b))
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	n := 0
	for sc.Scan() {
		n++
		cols := strings.Split(sc.Text(), "\t")
		if len(cols) < 3 || len(cols)%2 != 1 {
			t.Fatalf("%d 行目の列の数 = %d, want 3 以上の奇数", n, len(cols))
		}
		want := cols[0]
		var params []queryParam
		for i := 1; i < len(cols); i += 2 {
			name, err := strconv.Unquote(cols[i])
			if err != nil {
				t.Fatalf("%d 行目の名前 %s: %v", n, cols[i], err)
			}
			value, err := strconv.Unquote(cols[i+1])
			if err != nil {
				t.Fatalf("%d 行目の値 %s: %v", n, cols[i+1], err)
			}
			params = append(params, queryParam{name: name, value: value})
		}
		if got := springQueryEndpoint + "?" + springQuery(params); got != want {
			t.Errorf("%d 行目 %q\n got %s\nwant %s", n, params, got, want)
		}
	}
	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}
	if n != 410 {
		t.Fatalf("行の数 = %d, want 410", n)
	}
}

// TestSpringQuery_NamedCases は、タスクに挙げた文字を、読める形の期待で確かめる。期待は vectors.txt の同じ値の行と同じである。
func TestSpringQuery_NamedCases(t *testing.T) {
	cases := []struct{ in, want string }{
		{"openid email profile", "openid%20email%20profile"},
		{"a+b", "a+b"},
		{"/", "/"},
		{":", ":"},
		{"!$'()*+,;:@/?", "!$'()*+,;:@/?"},
		{"=&#%", "%3D%26%23%25"},
		{"日本語", "%E6%97%A5%E6%9C%AC%E8%AA%9E"},
		{"", ""},
	}
	for _, c := range cases {
		if got := springQueryEscape(c.in); got != c.want {
			t.Errorf("springQueryEscape(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
