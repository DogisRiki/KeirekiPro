package httpapi

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
)

const formCT = "multipart/form-data; boundary=XB"

// textField は、ファイルの名前の無い部分である。
func textField(name, value string) string {
	return "--XB\r\nContent-Disposition: form-data; name=\"" + name + "\"\r\n\r\n" + value + "\r\n"
}

// fileField は、ファイルの名前と Content-Type を持つ部分である。
func fileField(name, fileName, contentType, value string) string {
	return "--XB\r\nContent-Disposition: form-data; name=\"" + name + "\"; filename=\"" + fileName + "\"\r\nContent-Type: " +
		contentType + "\r\n\r\n" + value + "\r\n"
}

// formBody は、部分を並べて閉じの区切りを付けた本文を返す。
func formBody(parts ...string) string {
	return strings.Join(parts, "") + "--XB--\r\n"
}

// formResult は、中間処理に要求を渡した結果である。
type formResult struct {
	called bool
	form   updateUserInfoForm
	hasKey bool
	rec    *httptest.ResponseRecorder
	resp   any
	err    error
}

// runUpdateUserInfoForm は、名前と画像と2段階認証の設定の変更の操作として、中間処理に要求を渡す。
func runUpdateUserInfoForm(t *testing.T, query, contentType string, body io.Reader) formResult {
	t.Helper()
	target := "/api/users/me"
	if query != "" {
		target += "?" + query
	}
	r := httptest.NewRequest(http.MethodPut, target, body)
	r.Header.Set("Content-Type", contentType)
	var res formResult
	next := func(ctx context.Context, _ http.ResponseWriter, _ *http.Request, _ any) (any, error) {
		res.called = true
		res.form, res.hasKey = updateUserInfoFormFrom(ctx)
		return "next", nil
	}
	res.rec = httptest.NewRecorder()
	res.resp, res.err = updateUserInfoMiddleware(next, "UpdateUserInfo")(context.Background(), res.rec, r, nil)
	return res
}

// mustRead は、中間処理が項目を context に入れて次の処理を呼んだことを確かめ、項目を返す。
func mustRead(t *testing.T, name string, res formResult) updateUserInfoForm {
	t.Helper()
	if res.err != nil || !res.called || !res.hasKey || res.resp != "next" {
		t.Fatalf("%s: 次の処理が項目を受け取らない(called=%v hasKey=%v resp=%v err=%v status=%d body=%s)",
			name, res.called, res.hasKey, res.resp, res.err, res.rec.Code, res.rec.Body.String())
	}
	return res.form
}

// mustReject400 は、中間処理が 400 と入力の誤りの本文で答え、次の処理を呼ばないことを確かめる。
func mustReject400(t *testing.T, name string, res formResult) {
	t.Helper()
	if res.called || res.resp != nil || res.err != nil {
		t.Errorf("%s: called=%v resp=%v err=%v、期待は次の処理を呼ばずに nil, nil", name, res.called, res.resp, res.err)
	}
	if res.rec.Code != http.StatusBadRequest {
		t.Errorf("%s: 状態の番号 = %d、期待 = 400", name, res.rec.Code)
	}
	if got, want := res.rec.Body.String(), `{"message":"入力エラーがあります。","errors":{}}`; strings.TrimSpace(got) != want {
		t.Errorf("%s: 本文 = %s、期待 = %s", name, got, want)
	}
}

// paddedBody は、note の部分の中身で大きさを合わせ、ちょうど size バイトの本文を返す。
func paddedBody(t *testing.T, size int) string {
	t.Helper()
	head := textField("username", "a") + "--XB\r\nContent-Disposition: form-data; name=\"note\"\r\n\r\n"
	tail := "\r\n--XB--\r\n"
	pad := size - len(head) - len(tail)
	if pad < 0 {
		t.Fatalf("size %d が小さすぎる", size)
	}
	return head + strings.Repeat("x", pad) + tail
}

// TestUpdateUserInfoBody_SizeBoundary は、2097152 バイトの本文を読み、2097153 バイトの本文を 400 で断ることを確かめる。
// Java 版の spring.servlet.multipart.max-request-size(2MB)にあたる。
func TestUpdateUserInfoBody_SizeBoundary(t *testing.T) {
	ok := paddedBody(t, 2097152)
	form := mustRead(t, "2097152 バイト", runUpdateUserInfoForm(t, "", formCT, strings.NewReader(ok)))
	if form.Username == nil || *form.Username != "a" {
		t.Errorf("2097152 バイト: username = %v、期待 = a", form.Username)
	}
	mustReject400(t, "2097153 バイト", runUpdateUserInfoForm(t, "", formCT, strings.NewReader(paddedBody(t, 2097153))))
}

// TestUpdateUserInfoBody_UsernameJoin は、username の値を、Java 版の Tomcat と Spring と同じ順に並べてつなぐことを確かめる。
func TestUpdateUserInfoBody_UsernameJoin(t *testing.T) {
	str := func(s string) *string { return &s }
	for _, tt := range []struct {
		name  string
		query string
		body  string
		want  *string
	}{
		{name: "本文の1つの値", body: formBody(textField("username", "名前")), want: str("名前")},
		{name: "本文の2つの値をつなぐ", body: formBody(textField("username", "a"), textField("username", "b")), want: str("a,b")},
		// Java 版の答え(java-checks/cases.json の1つ目): 本文の値が先、問い合わせの値が後
		{name: "本文と問い合わせ", query: "username=%E5%95%8F%E3%81%84%E5%90%88%E3%82%8F%E3%81%9B", body: formBody(textField("username", "本文")), want: str("本文,問い合わせ")},
		{name: "問い合わせだけ", query: "username=a+b%2Cc", body: formBody(textField("note", "n")), want: str("a b,c")},
		{name: "空の値もつなぐ", body: formBody(textField("username", ""), textField("username", "")), want: str(",")},
		{name: "値の無い問い合わせの項目は空の値", query: "a&&username&c=%41", body: formBody(), want: str("")},
		{name: "UTF-8 として誤ったバイトは U+FFFD", body: formBody(textField("username", "a\xffb")), want: str("a" + string(rune(0xfffd)) + "b")},
		{name: "名前の大文字と小文字を区別する", body: formBody(textField("Username", "a")), want: nil},
		{name: "無い", body: formBody(textField("note", "n")), want: nil},
	} {
		form := mustRead(t, tt.name, runUpdateUserInfoForm(t, tt.query, formCT, strings.NewReader(tt.body)))
		if !reflect.DeepEqual(form.Username, tt.want) {
			t.Errorf("%s: username = %v、期待 = %v", tt.name, deref(form.Username), deref(tt.want))
		}
	}
}

func deref[T any](p *T) any {
	if p == nil {
		return nil
	}
	return *p
}

// TestUpdateUserInfoBody_TwoFactorValues は、twoFactorAuthEnabled を、Java 版の Spring 7.0.10 と同じ規則で真偽にすることを
// 確かめる。値が1つなら CustomBooleanEditor の規則(Java の equalsIgnoreCase)、2つ以上なら最初の値だけを
// StringToBooleanConverter の規則で読む。どの値も、本物の Spring に渡した答えと同じである。
func TestUpdateUserInfoBody_TwoFactorValues(t *testing.T) {
	longS := string(rune(0x17f))
	nbsp := string(rune(0xa0))
	emoji := string(rune(0x1f600))
	const (
		null = iota
		yes
		no
		bad
	)
	for _, tt := range []struct {
		name   string
		values []string
		query  string
		want   int
	}{
		{name: "true", values: []string{"true"}, want: yes},
		{name: "前後の空白と大文字", values: []string{" On "}, want: yes},
		{name: "YES", values: []string{"YES"}, want: yes},
		{name: "1", values: []string{"1"}, want: yes},
		{name: "前後の制御文字", values: []string{"\x00yes\x1f"}, want: yes},
		{name: "false", values: []string{"false"}, want: no},
		{name: "OFF", values: []string{"OFF"}, want: no},
		{name: "no", values: []string{"no"}, want: no},
		{name: "0", values: []string{"0"}, want: no},
		{name: "空", values: []string{""}, want: null},
		{name: "空白だけ", values: []string{" "}, want: null},
		{name: "長い s の yes", values: []string{"ye" + longS}, want: yes},
		{name: "長い s の false", values: []string{"fal" + longS + "e"}, want: no},
		{name: "前の NBSP", values: []string{nbsp + "true"}, want: bad},
		{name: "ほかの値", values: []string{"maybe"}, want: bad},
		{name: "01", values: []string{"01"}, want: bad},
		{name: "途中の制御文字", values: []string{"tru\x00e"}, want: bad},
		{name: "BMP の外の字", values: []string{"tr" + emoji + "e"}, want: bad},
		{name: "2つの値は最初の値", values: []string{"true", "false"}, want: yes},
		{name: "2つの値の最初が偽", values: []string{"false", "true"}, want: no},
		{name: "2つの値の最初が空", values: []string{"", "true"}, want: null},
		{name: "2つの値のあとの値は見ない", values: []string{"true", "maybe"}, want: yes},
		{name: "2つの値の最初は長い s を受け付けない", values: []string{"ye" + longS, "true"}, want: bad},
		{name: "2つの値の最初がほかの値", values: []string{"maybe", "true"}, want: bad},
		{name: "本文の値が問い合わせの値より先", values: []string{"false"}, query: "twoFactorAuthEnabled=true", want: no},
		{name: "問い合わせだけ", query: "twoFactorAuthEnabled=%20yes", want: yes},
		{name: "無い", want: null},
	} {
		parts := []string{textField("username", "a")}
		for _, v := range tt.values {
			parts = append(parts, textField("twoFactorAuthEnabled", v))
		}
		res := runUpdateUserInfoForm(t, tt.query, formCT, strings.NewReader(formBody(parts...)))
		if tt.want == bad {
			mustReject400(t, tt.name, res)
			continue
		}
		form := mustRead(t, tt.name, res)
		got := null
		if form.TwoFactorAuthEnabled != nil {
			got = no
			if *form.TwoFactorAuthEnabled {
				got = yes
			}
		}
		if got != tt.want {
			t.Errorf("%s: twoFactorAuthEnabled = %v、期待の種類 = %d", tt.name, deref(form.TwoFactorAuthEnabled), tt.want)
		}
	}
}

// expandingNameBody は、Tomcat が解いた名前のバイト数で数える合計を、本文の大きさより大きくする本文を返す。
// 49個の部分の名前を RFC 2047 の ISO-8859-1 の B の書き方で送ると、1つの名前が、本文の中の 417 バイトから、解いたあとの
// UTF-8 の 600 バイトになる。最後の note の部分の中身で、Tomcat の合計を postSize ちょうどにする。
func expandingNameBody(postSize int) string {
	encoded := "=?ISO-8859-1?B?" + base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0xff}, 300)) + "?="
	var parts []string
	for range 49 {
		parts = append(parts, textField(encoded, ""))
	}
	// 49個の部分は、名前の 600 バイトと、= と区切りの 2 バイトを数える。note の部分は、名前の 4 バイトと 2 バイトを数える
	pad := postSize - 49*(600+2) - (4 + 2)
	parts = append(parts, textField("note", strings.Repeat("x", pad)))
	return formBody(parts...)
}

// TestUpdateUserInfoBody_JavaFiveHundredAs400 は、Java 版が 500 と「予期せぬエラーが発生しました。」で答える要求に、
// Go 版が 400 と入力の誤りの本文で答えることを確かめる。どの要求も、Java 版に送って 500 の答えを確かめた
// (Tomcat の合計の上限の要求は、Tomcat の Request.parseParts の写しで確かめた)。
func TestUpdateUserInfoBody_JavaFiveHundredAs400(t *testing.T) {
	ok := formBody(textField("username", "a"))
	tooManyQuery := func(n int) string {
		q := make([]string, n)
		for i := range q {
			q[i] = "q=1"
		}
		return strings.Join(q, "&")
	}
	// 部分が2つなので、Tomcat は問い合わせの項目を 998 個まで読む
	twoParts := formBody(textField("username", "a"), textField("note", "n"))
	mustRead(t, "問い合わせ 998 項目と部分2つ", runUpdateUserInfoForm(t, tooManyQuery(998), formCT, strings.NewReader(twoParts)))
	// Tomcat の合計がちょうど上限なら読む
	if body := expandingNameBody(2097152); len(body) > 2097152 {
		t.Fatalf("本文が %d バイトで、大きさの上限を超えている", len(body))
	} else {
		mustRead(t, "Tomcat の合計がちょうど上限", runUpdateUserInfoForm(t, "", formCT, strings.NewReader(body)))
	}

	for _, tt := range []struct {
		name, query, contentType, body string
	}{
		{name: "2MB を超える本文", contentType: formCT, body: paddedBody(t, 2097153)},
		{name: "真偽として読めない twoFactorAuthEnabled", contentType: formCT, body: formBody(textField("twoFactorAuthEnabled", "maybe"))},
		{name: "ファイルとして送った username", contentType: formCT, body: formBody(fileField("username", "a.txt", "text/plain", "a"))},
		{name: "ファイルとして送った twoFactorAuthEnabled", contentType: formCT, body: formBody(fileField("twoFactorAuthEnabled", "a.txt", "text/plain", "true"))},
		{name: "閉じない multipart", contentType: formCT, body: textField("username", "a") + "--XB\r\nContent-Disposition: form-data; name=\"x\"\r\n\r\nno end"},
		{name: "Spring だけが読めない Content-Disposition", contentType: formCT, body: formBody(textField("username", "a"),
			"--XB\r\nContent-Disposition: form-data; name=\"note\"; filename*=US-ASCII''a\r\n\r\nv\r\n")},
		{name: "multipart/mixed", contentType: "multipart/mixed; boundary=XB", body: ok},
		{name: "問い合わせの %ZZ", query: "x=%ZZ", contentType: formCT, body: ok},
		{name: "問い合わせの終わりの %2", query: "x=%2", contentType: formCT, body: ok},
		{name: "問い合わせの名前の %ZZ", query: "%ZZ=1", contentType: formCT, body: ok},
		{name: "問い合わせの名前の無い項目", query: "=foo", contentType: formCT, body: ok},
		{name: "問い合わせの UTF-8 でないバイト", query: "x=%FF", contentType: formCT, body: ok},
		{name: "問い合わせ 999 項目と部分2つ", query: tooManyQuery(999), contentType: formCT, body: twoParts},
		{name: "Tomcat の合計が上限を1バイト超える", contentType: formCT, body: expandingNameBody(2097153)},
	} {
		mustReject400(t, tt.name, runUpdateUserInfoForm(t, tt.query, tt.contentType, strings.NewReader(tt.body)))
	}
}

// TestUpdateUserInfoBody_ProfileImage は、Spring が profileImage として渡す画像を取り出すことを確かめる。
func TestUpdateUserInfoBody_ProfileImage(t *testing.T) {
	for _, tt := range []struct {
		name string
		body string
		want *profileImageInput
	}{
		{
			name: "画像", body: formBody(fileField("profileImage", "a.png", "image/png", "PNG")),
			want: &profileImageInput{FileName: "a.png", ContentType: "image/png", Content: []byte("PNG")},
		},
		{
			name: "Spring の読み方のファイルの名前", body: formBody(fileField("profileImage", "=?UTF-8?Q?=E7=94=BB_a.png?=", "image/png", "PNG")),
			want: &profileImageInput{FileName: "画 a.png", ContentType: "image/png", Content: []byte("PNG")},
		},
		{
			name: "空の Content-Type は空の文字列", body: formBody(fileField("profileImage", "a.png", "", "PNG")),
			want: &profileImageInput{FileName: "a.png", Content: []byte("PNG")},
		},
		{
			name: "最初の画像", body: formBody(fileField("profileImage", "a.png", "image/png", "A"), fileField("profileImage", "b.png", "image/jpeg", "B")),
			want: &profileImageInput{FileName: "a.png", ContentType: "image/png", Content: []byte("A")},
		},
		// Java 版の答え(java-checks/cases.json の2つ目): ファイルの名前の無い部分は画像として扱わない
		{name: "ファイルの名前の無い部分", body: formBody(textField("profileImage", "PNG"))},
		{name: "中身が0バイト", body: formBody(fileField("profileImage", "a.png", "image/png", ""))},
		{name: "Content-Type の無い0バイトの画像", body: formBody("--XB\r\nContent-Disposition: form-data; name=\"profileImage\"; filename=\"a.png\"\r\n\r\n\r\n")},
		{name: "無い", body: formBody(textField("username", "a"))},
	} {
		form := mustRead(t, tt.name, runUpdateUserInfoForm(t, "", formCT, strings.NewReader(tt.body)))
		if !reflect.DeepEqual(form.ProfileImage, tt.want) {
			t.Errorf("%s: profileImage = %+v、期待 = %+v", tt.name, form.ProfileImage, tt.want)
		}
	}

	// Java 版の答え(java-checks/cases.json の3つ目): Content-Type の無い画像は、500 と「予期せぬエラーが発生しました。」。
	// 中間処理は、誤りを返し、生成したコードの ResponseErrorHandlerFunc に 500 で答えさせる
	noType := formBody(textField("username", "a"), "--XB\r\nContent-Disposition: form-data; name=\"profileImage\"; filename=\"a.png\"\r\n\r\nPNG\r\n")
	res := runUpdateUserInfoForm(t, "", formCT, strings.NewReader(noType))
	if !errors.Is(res.err, errImageWithoutContentType) || res.called || res.resp != nil || res.rec.Body.Len() != 0 {
		t.Errorf("Content-Type の無い画像: err=%v called=%v resp=%v body=%q、期待は errImageWithoutContentType だけ",
			res.err, res.called, res.resp, res.rec.Body.String())
	}
	// Java 版は、3つの項目を読み終えてから画像の形式を確かめるので、読めない項目の 400 が先になる
	noTypeAndBad := formBody(textField("twoFactorAuthEnabled", "maybe"),
		"--XB\r\nContent-Disposition: form-data; name=\"profileImage\"; filename=\"a.png\"\r\n\r\nPNG\r\n")
	mustReject400(t, "Content-Type の無い画像と読めない twoFactorAuthEnabled", runUpdateUserInfoForm(t, "", formCT, strings.NewReader(noTypeAndBad)))
}

// TestUpdateUserInfoBody_ControlCharsInPartHeaders は、部分の見出しに制御文字があっても、Java 版と同じく読むことを確かめる。
func TestUpdateUserInfoBody_ControlCharsInPartHeaders(t *testing.T) {
	body := formBody(
		"--XB\r\nContent-Disposition: form-data; name=\"username\"; x=\"a\x01b\"\r\nX-Ctrl: \x00\x1b\x7f\r\n\r\n名前\r\n",
		fileField("profileImage", "a\x07b.png", "image/png\x03", "PNG"),
	)
	form := mustRead(t, "制御文字", runUpdateUserInfoForm(t, "", formCT, strings.NewReader(body)))
	if form.Username == nil || *form.Username != "名前" {
		t.Errorf("username = %v、期待 = 名前", deref(form.Username))
	}
	want := &profileImageInput{FileName: "a\x07b.png", ContentType: "image/png", Content: []byte("PNG")}
	if !reflect.DeepEqual(form.ProfileImage, want) {
		t.Errorf("profileImage = %+v、期待 = %+v", form.ProfileImage, want)
	}
}

// TestUpdateUserInfoBody_OtherOperationsUnchanged は、ほかの操作では、中間処理が本文を読まずに次の処理をそのまま呼ぶことを確かめる。
func TestUpdateUserInfoBody_OtherOperationsUnchanged(t *testing.T) {
	for _, op := range []string{"Login", "GetUserInfo", "DeleteUser", "updateUserInfo"} {
		r := httptest.NewRequest(http.MethodPut, "/", strings.NewReader("not multipart"))
		var called, hasKey bool
		var rest string
		next := func(ctx context.Context, _ http.ResponseWriter, r *http.Request, _ any) (any, error) {
			called = true
			_, hasKey = updateUserInfoFormFrom(ctx)
			b, _ := io.ReadAll(r.Body)
			rest = string(b)
			return "next", nil
		}
		rec := httptest.NewRecorder()
		resp, err := updateUserInfoMiddleware(next, op)(context.Background(), rec, r, nil)
		if !called || hasKey || rest != "not multipart" || resp != "next" || err != nil || rec.Body.Len() != 0 {
			t.Errorf("%s: called=%v hasKey=%v 残りの本文=%q resp=%v err=%v 答え=%q", op, called, hasKey, rest, resp, err, rec.Body.String())
		}
	}
}

type failingReader struct{}

func (failingReader) Read([]byte) (int, error) { return 0, errors.New("切れた") }

// TestUpdateUserInfoBody_BodyReadError は、本文を読む途中で誤りが起きた要求を 400 で断ることを確かめる。
// 誤りの前に読めたバイトだけでも正しい本文になるようにし、誤りを見落とすと読めてしまう要求にする。
func TestUpdateUserInfoBody_BodyReadError(t *testing.T) {
	body := io.MultiReader(strings.NewReader(formBody(textField("username", "a"))), failingReader{})
	mustReject400(t, "本文を読めない", runUpdateUserInfoForm(t, "", formCT, body))
	if _, ok := updateUserInfoFormFrom(context.Background()); ok {
		t.Error("項目を入れていない context から項目を読めた")
	}
}
