package httpapi

import (
	"encoding/hex"
	"encoding/json"
	"io/fs"
	"os"
	"path"
	"strings"
	"testing"
)

// fileNameCase は、testdata/multipart/filenames.json の1通りである。Java 版の答えの控えで、作り方は同じフォルダの README.md に書いた。
type fileNameCase struct {
	Name                  string `json:"name"`
	ContentDispositionHex string `json:"contentDispositionHex"`
	Answer                struct {
		Status int `json:"status"`
	} `json:"answer"`
	StoredObjects []struct {
		Key string `json:"key"`
	} `json:"storedObjects"`
}

// readFileNameCases は、Java 版の答えの控えを読む。
func readFileNameCases(t *testing.T) []fileNameCase {
	t.Helper()
	raw, err := fs.ReadFile(os.DirFS("testdata/multipart"), "filenames.json")
	if err != nil {
		t.Fatalf("Java 版の答えの控えを読めません: %v", err)
	}
	var file struct {
		Cases []fileNameCase `json:"cases"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		t.Fatalf("Java 版の答えの控えの JSON を読めません: %v", err)
	}
	if len(file.Cases) != 12 {
		t.Fatalf("Java 版の答えの控えの数 = %d, want 12", len(file.Cases))
	}
	return file.Cases
}

// javaAllowedExtension は、Java 版が画像として許可した拡張子を、ファイルの名前から求める。
// 拡張子は最後の . のあとの文字列で、ASCII の字だけを小文字にし、ASCII でない字を含む拡張子を許可しない(research.md の試作の記録の P4)。
func javaAllowedExtension(fileName string) (string, bool) {
	i := strings.LastIndexByte(fileName, '.')
	if i < 0 {
		return "", false
	}
	ext := fileName[i+1:]
	for j := range len(ext) {
		if ext[j] >= 0x80 {
			return "", false
		}
	}
	ext = strings.ToLower(ext)
	switch ext {
	case "jpg", "jpeg", "png", "gif":
		return ext, true
	}
	return "", false
}

// TestContentDisposition_MatchesJava は、Java 版に送った12通りの部分の Content-Disposition を読んだファイルの名前が、
// Java 版の答え(画像を受けたか断ったか、受けたときに置いた画像の名前の拡張子)と合うことを確かめる。
// 見出しの値は、Java 版(Tomcat)と同じく、バイト列を JDK の UTF-8 の規則で文字列にしてから渡す。
func TestContentDisposition_MatchesJava(t *testing.T) {
	// Spring 7.0.10 の ContentDisposition.parse が返すファイルの名前。Java 版の答えは拡張子しか残らないので、名前の全体はここに書く
	wantFileNames := map[string]string{
		"小文字の拡張子":       "a.png",
		"大文字の拡張子":       "a.PNG",
		"点付きの大文字のI":     "x.G\u0130F",
		"最後がスラッシュ":      "a.png/",
		"RFC 2047 の書き方": "画像.png",
		"Windows のパス":   `C:\dir\a.JPG`,
		"拡張子が無い":        "a",
		"拡張子が2つ":        "a.tar.gz",
		"RFC 5987 の書き方": "画像.gif",
		"逃がした二重引用符":     `a"b.png`,
		"点で始まる":         ".png",
		"制御文字を含む":       "a\a.png",
	}
	for _, c := range readFileNameCases(t) {
		t.Run(c.Name, func(t *testing.T) {
			raw, err := hex.DecodeString(c.ContentDispositionHex)
			if err != nil {
				t.Fatalf("contentDispositionHex を読めません: %v", err)
			}
			got, err := parseContentDisposition(decodeJDKUTF8(raw))
			if err != nil {
				t.Fatalf("parseContentDisposition の誤り: %v", err)
			}
			if got.Type != "form-data" || !got.HasName || got.Name != "profileImage" {
				t.Errorf("種類と部分の名前 = %q, %v, %q, want form-data, true, profileImage", got.Type, got.HasName, got.Name)
			}
			want, ok := wantFileNames[c.Name]
			if !ok {
				t.Fatalf("場合 %q の名前が表に無い", c.Name)
			}
			if !got.HasFileName || got.FileName != want {
				t.Errorf("ファイルの名前 = %v, %q, want true, %q", got.HasFileName, got.FileName, want)
			}
			ext, allowed := javaAllowedExtension(got.FileName)
			switch c.Answer.Status {
			case 200:
				if len(c.StoredObjects) != 1 {
					t.Fatalf("Java 版が置いた画像の数 = %d, want 1", len(c.StoredObjects))
				}
				if wantExt := strings.TrimPrefix(path.Ext(c.StoredObjects[0].Key), "."); !allowed || ext != wantExt {
					t.Errorf("拡張子 = %q(許可 %v), Java 版が置いた画像の拡張子 = %q", ext, allowed, wantExt)
				}
			case 400:
				if allowed {
					t.Errorf("拡張子 %q を許可するが、Java 版は 400 で断った", ext)
				}
			default:
				t.Fatalf("Java 版の答えの状態の番号 = %d, want 200 か 400", c.Answer.Status)
			}
		})
	}
}

// TestContentDisposition_Parse は、Spring 7.0.10 の ContentDisposition.parse の分かれ道ごとに、同じ結果を返すことを確かめる。
// 期待する値は、同じ値を Java 版の依存の jar の ContentDisposition.parse に渡して確かめた。
func TestContentDisposition_Parse(t *testing.T) {
	const repl = replacementChar
	tests := []struct {
		name   string
		header string
		want   contentDisposition
	}{
		{name: "種類だけ", header: "form-data", want: contentDisposition{Type: "form-data"}},
		{name: "種類の大文字と前後の空白と制御文字を残さない", header: "\a Form-Data \t", want: contentDisposition{Type: "Form-Data"}},
		{name: "空の部分を飛ばす", header: "form-data;; name=a ;", want: contentDisposition{Type: "form-data", Name: "a", HasName: true}},
		{name: "二重引用符の中の区切り", header: `form-data; name="a;b"`, want: contentDisposition{Type: "form-data", Name: "a;b", HasName: true}},
		{name: "逃がした二重引用符のあとの区切り", header: `form-data; name="a\";b"`, want: contentDisposition{Type: "form-data", Name: `a";b`, HasName: true}},
		{name: "あとの name で上書きする", header: "form-data; name=a; name=b", want: contentDisposition{Type: "form-data", Name: "b", HasName: true}},
		{name: "項目の名前の大文字", header: "form-data; NAME=x; FileName=y", want: contentDisposition{Type: "form-data", Name: "x", HasName: true, FileName: "y", HasFileName: true}},
		{name: "ASCII でない字の小文字を名前に使わない", header: "form-data; f\u0130lename=y", want: contentDisposition{Type: "form-data"}},
		{name: "知らない項目を飛ばす", header: "form-data; size=3", want: contentDisposition{Type: "form-data"}},
		{name: "最初の filename を使う", header: "form-data; filename=a; filename=b", want: contentDisposition{Type: "form-data", FileName: "a", HasFileName: true}},
		{name: "filename* が filename に勝つ", header: "form-data; filename=a; filename*=UTF-8''b", want: contentDisposition{Type: "form-data", FileName: "b", HasFileName: true}},
		{name: "filename* のあとの filename を使わない", header: "form-data; filename*=UTF-8''b; filename=a", want: contentDisposition{Type: "form-data", FileName: "b", HasFileName: true}},
		{name: "空のファイルの名前", header: `form-data; filename=""`, want: contentDisposition{Type: "form-data", HasFileName: true}},
		{name: "閉じない二重引用符を残す", header: `form-data; filename="a`, want: contentDisposition{Type: "form-data", FileName: `"a`, HasFileName: true}},
		{name: "引用符の中の値の前後の空白を残す", header: `form-data; filename=" a "`, want: contentDisposition{Type: "form-data", FileName: " a ", HasFileName: true}},
		{name: "逃がした逆スラッシュ", header: `form-data; filename="a\\b"`, want: contentDisposition{Type: "form-data", FileName: `a\b`, HasFileName: true}},
		{name: "ほかの字の前の逆スラッシュを残す", header: `form-data; filename="a\x\画"`, want: contentDisposition{Type: "form-data", FileName: `a\x\画`, HasFileName: true}},
		{name: "最後の逆スラッシュを残す", header: `form-data; filename="a\"`, want: contentDisposition{Type: "form-data", FileName: `a\`, HasFileName: true}},
		{name: "引用符の無い値の逆スラッシュも解く", header: `form-data; name=a\"b`, want: contentDisposition{Type: "form-data", Name: `a"b`, HasName: true}},
		{name: "RFC 5987 の UTF-8", header: "form-data; filename*=utf8''%E7%94%BB.png", want: contentDisposition{Type: "form-data", FileName: "画.png", HasFileName: true}},
		{name: "RFC 5987 の ISO-8859-1 の別名", header: "form-data; filename*=Latin1''%e9.png", want: contentDisposition{Type: "form-data", FileName: "\u00e9.png", HasFileName: true}},
		{name: "RFC 5987 の文字コードの前後の空白", header: "form-data; filename*= UTF-8 ''a", want: contentDisposition{Type: "form-data", FileName: "a", HasFileName: true}},
		{name: "RFC 5987 の言語を読まない", header: "form-data; filename*=UTF-8'ja'%41", want: contentDisposition{Type: "form-data", FileName: "A", HasFileName: true}},
		{name: "RFC 5987 の UTF-8 の誤ったバイト", header: "form-data; filename*=UTF-8''a%FFb", want: contentDisposition{Type: "form-data", FileName: "a" + repl + "b", HasFileName: true}},
		{name: "RFC 5987 の文字コードが無いと US-ASCII", header: "form-data; filename*=a%41%E9", want: contentDisposition{Type: "form-data", FileName: "aA" + repl, HasFileName: true}},
		{name: "RFC 5987 の引用符を外してから解く", header: `form-data; filename*="UTF-8''a"`, want: contentDisposition{Type: "form-data", FileName: "a", HasFileName: true}},
		{name: "RFC 2047 の B を続けてつなぐ", header: `form-data; filename="=?UTF-8?B?YQ==?=x=?utf-8?B?Yg?="`, want: contentDisposition{Type: "form-data", FileName: "ab", HasFileName: true}},
		{name: "RFC 2047 の B の前後の字を捨てる", header: `form-data; filename="=?UTF-8?B?YQ==?= tail"`, want: contentDisposition{Type: "form-data", FileName: "a", HasFileName: true}},
		{name: "RFC 2047 の B の ISO-8859-1", header: `form-data; filename="=?ISO-8859-1?B?6Q==?="`, want: contentDisposition{Type: "form-data", FileName: "\u00e9", HasFileName: true}},
		{name: "RFC 2047 の B の US-ASCII", header: `form-data; filename="=?us?B?gWE=?="`, want: contentDisposition{Type: "form-data", FileName: repl + "a", HasFileName: true}},
		{name: "RFC 2047 の B を1つずつ字にする", header: `form-data; filename="=?UTF-8?B?55S7?==?UTF-8?B?5w?="`, want: contentDisposition{Type: "form-data", FileName: "画" + repl, HasFileName: true}},
		{name: "RFC 2047 の B があれば Q を読まない", header: `form-data; filename="=?UTF-8?Q?b?= =?UTF-8?B?YQ==?="`, want: contentDisposition{Type: "form-data", FileName: "a", HasFileName: true}},
		{name: "RFC 2047 の Q", header: `form-data; filename="=?UTF-8?Q?=E7=94=BB_a.png?="`, want: contentDisposition{Type: "form-data", FileName: "画 a.png", HasFileName: true}},
		{name: "RFC 2047 の Q の終わりの等号を残す", header: `form-data; filename="=?UTF-8?Q?a=4?="`, want: contentDisposition{Type: "form-data", FileName: "a=4", HasFileName: true}},
		{name: "RFC 2047 の形でない値をそのまま使う", header: `form-data; filename="=?x\"y"`, want: contentDisposition{Type: "form-data", FileName: `=?x\"y`, HasFileName: true}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseContentDisposition(tt.header)
			if err != nil {
				t.Fatalf("parseContentDisposition(%q) の誤り: %v", tt.header, err)
			}
			if got != tt.want {
				t.Errorf("parseContentDisposition(%q) = %+v, want %+v", tt.header, got, tt.want)
			}
		})
	}
}

// TestContentDisposition_Errors は、Spring 7.0.10 の ContentDisposition.parse が例外を投げる見出しで、誤りを返すことを確かめる。
// RFC 2047 の文字コードのうち、Java 版が読めて Go 版が読まないもの(Shift_JIS など)も誤りにする。
func TestContentDisposition_Errors(t *testing.T) {
	for _, header := range []string{
		"",
		"  ; name=a",
		"form-data; name",
		`form-data; filename="`,
		"form-data; filename*=Shift_JIS''a",
		"form-data; filename*=US-ASCII''a",
		"form-data; filename*=bogus''a",
		"form-data; filename*=''a",
		"form-data; filename*=%",
		"form-data; filename*=%4",
		"form-data; filename*=%zz",
		"form-data; filename*=a b",
		"form-data; filename*=UTF-8''画",
		`form-data; filename="=?UTF-8?B?Q?="`,
		`form-data; filename="=?UTF-8?B?QQ=?="`,
		`form-data; filename="=?UTF-8?B?QUJD=?="`,
		`form-data; filename="=?UTF-8?B?QUI==?="`,
		`form-data; filename="=?UTF-8?B?QUJDR?="`,
		`form-data; filename="=?Shift_JIS?B?YQ==?="`,
		`form-data; filename="=?bogus?B?YQ==?="`,
		`form-data; filename="=?UTF-8?Q?=G1x?="`,
	} {
		if got, err := parseContentDisposition(header); err == nil {
			t.Errorf("parseContentDisposition(%q) = %+v, want 誤り", header, got)
		}
	}
}
