package resume

import "testing"

// linkCase は、リンクの検査の1つの値と、Go 版の答えである。cb は、Java 版と答えが違う値に付ける、変えた動きの一覧の番号である。
type linkCase struct {
	input string
	want  bool
	cb    string
}

// checkLinkCases は、検査 fn が表のどの値にも Go 版の答えを返すことと、cb の番号がすべて変えた動きの一覧にあることを確かめる。
func checkLinkCases(t *testing.T, name string, fn func(string) bool, cases []linkCase) {
	t.Helper()
	diff := map[string]string{}
	for _, c := range cases {
		if got := fn(c.input); got != c.want {
			t.Errorf("%s(%q) = %v, want %v", name, c.input, got, c.want)
		}
		if c.cb != "" {
			diff[c.input] = c.cb
		}
	}
	checkDiffTableInChangedBehaviors(t, diff)
}

// TestIsHTTPSLink は、入力の検査が、スキームが https でホスト名のある URL だけを通すことを確かめる。
func TestIsHTTPSLink(t *testing.T) {
	checkLinkCases(t, "isHTTPSLink", isHTTPSLink, []linkCase{
		// Java 版と答えが同じ書き方
		{input: "", want: true},
		{input: "https://example.com", want: true},
		{input: "https://example.com/path?q=1#frag", want: true},
		{input: "HTTPS://example.com", want: true},
		{input: "Https://example.com", want: true},
		{input: "HtTpS://a", want: true},
		{input: "https://u@[::1]:8/", want: true},
		{input: "https://example.com:8080", want: true},
		{input: "https://example.com:65536", want: true},
		{input: "https://[::1]/", want: true},
		{input: "https://127.0.0.1", want: true},
		{input: "https://xn--r8jz45g.jp", want: true},
		{input: "https://example.com/%E3%81%82", want: true},
		{input: "http://example.com", want: false},
		{input: "ftp://example.com", want: false},
		{input: "mailto:a@example.com", want: false},
		{input: "//example.com", want: false},
		{input: "example.com", want: false},
		{input: " ", want: false},
		{input: " https://example.com", want: false},
		{input: "https://", want: false},
		{input: "https:", want: false},
		{input: "https://exa mple.com", want: false},
		{input: "https://example.com:abc", want: false},
		{input: "https://[::1", want: false},
		{input: "https://example.com/%zz", want: false},
		// Java 版が通し、Go 版が断る書き方
		{input: "https:example.com", want: false, cb: "CB-109"},
		{input: "https:/example.com", want: false, cb: "CB-109"},
		{input: "https:///path", want: false, cb: "CB-109"},
		{input: "https://:80", want: false, cb: "CB-109"},
		{input: "https://?q", want: false, cb: "CB-109"},
		{input: "https://#f", want: false, cb: "CB-109"},
		{input: "https://a@", want: false, cb: "CB-109"},
		{input: "url:https://example.com", want: false, cb: "CB-109"},
		{input: "https://example.com:-1", want: false, cb: "CB-109"},
		{input: "https://a:+5", want: false, cb: "CB-109"},
		{input: "https://a:\uff11\uff10", want: false, cb: "CB-109"},
		{input: "https://a:\u0663", want: false, cb: "CB-109"},
		{input: "https://[::1%eth0]/", want: false, cb: "CB-109"},
		{input: "https://ex%41mple.com", want: false, cb: "CB-109"},
		{input: "https://u\uff03@a", want: false, cb: "CB-109"},
		// Java 版が断り、Go 版が通す書き方
		{input: "https://example.com/a b", want: true, cb: "CB-109"},
		{input: "https://a?b c", want: true, cb: "CB-109"},
		{input: "https://example.com/\"", want: true, cb: "CB-109"},
		{input: "https://example.com/<", want: true, cb: "CB-109"},
		{input: "https://example.com/{}", want: true, cb: "CB-109"},
		{input: "https://example.com/|", want: true, cb: "CB-109"},
		{input: "https://example.com/^", want: true, cb: "CB-109"},
		{input: "https://example.com/`", want: true, cb: "CB-109"},
		{input: "https://example.com#a#b", want: true, cb: "CB-109"},
		{input: "https://example.com/\u3000", want: true, cb: "CB-109"},
		{input: "https://a\u00a0b", want: true, cb: "CB-109"},
		{input: "https://a\u2028", want: true, cb: "CB-109"},
		{input: "https://example.com:99999999999", want: true, cb: "CB-109"},
		{input: "https://a\uff03b", want: true, cb: "CB-109"},
		{input: "https://\uff20", want: true, cb: "CB-109"},
	})
}

// TestHasHTTPSScheme は、戻しの検査が、英字の大文字と小文字を区別せずに https: で始まるリンクを通し、
// 前に付いた url: を除いてから確かめることを確かめる。
func TestHasHTTPSScheme(t *testing.T) {
	checkLinkCases(t, "hasHTTPSScheme", hasHTTPSScheme, []linkCase{
		// Java 版と答えが同じ書き方
		{input: "https://example.com", want: true},
		{input: "HtTpS://example.com", want: true},
		{input: "https:example.com", want: true},
		{input: "http://example.com", want: false},
		{input: "url:http://example.com", want: false},
		{input: "example.com", want: false},
		{input: "https", want: false},
		{input: "url:", want: false},
		{input: "", want: false},
		// Java 版が断り、Go 版が通す書き方
		{input: "url:https://example.com", want: true, cb: "CB-110"},
		{input: "URL:HTTPS://example.com", want: true, cb: "CB-110"},
		{input: "https:", want: true, cb: "CB-110"},
		{input: "https://", want: true, cb: "CB-110"},
		{input: "https:%zz", want: true, cb: "CB-110"},
		{input: "https:a b", want: true, cb: "CB-110"},
	})
}
