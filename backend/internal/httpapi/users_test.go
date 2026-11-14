package httpapi

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strconv"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/authctx"
	"github.com/DogisRiki/KeirekiPro/backend/internal/users"
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

// handlerUserID は、受け口のテストでログインしている利用者の ID である。
var handlerUserID = uuid.MustParse("6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b")

// loggedIn は、handlerUserID の利用者がログインしている context を返す。
func loggedIn() context.Context {
	return authctx.With(context.Background(), handlerUserID, []string{"USER"})
}

// withForm は、本文を読む中間処理が form を入れた context を返す。
func withForm(ctx context.Context, form updateUserInfoForm) context.Context {
	return context.WithValue(ctx, updateUserInfoFormKey{}, form)
}

// fakeUsers は、利用者の処理の代わりである。呼ばれた操作と引数を calls に記録し、errs に操作の名前で決めた誤りを返す。
// GetUserInfo は、誤りが無ければ info を返す。
type fakeUsers struct {
	calls []string
	info  users.UserInfo
	errs  map[string]error
}

func (f *fakeUsers) record(op, format string, args ...any) error {
	f.calls = append(f.calls, op+"("+fmt.Sprintf(format, args...)+")")
	return f.errs[op]
}

func (f *fakeUsers) GetUserInfo(_ context.Context, userID uuid.UUID) (users.UserInfo, error) {
	if err := f.record("GetUserInfo", "%s", userID); err != nil {
		return users.UserInfo{}, err
	}
	return f.info, nil
}

func (f *fakeUsers) UpdateUserInfo(_ context.Context, in users.UpdateInput) error {
	image := "nil"
	if in.ProfileImage != nil {
		image = fmt.Sprintf("%q %q %q", in.ProfileImage.FileName, in.ProfileImage.ContentType, in.ProfileImage.Content)
	}
	return f.record("UpdateUserInfo", "%s, username=%s twoFactor=%s image=%s",
		in.UserID, optText(in.Username), optBool(in.TwoFactorAuthEnabled), image)
}

func (f *fakeUsers) DeleteUser(_ context.Context, userID uuid.UUID) error {
	return f.record("DeleteUser", "%s", userID)
}

func (f *fakeUsers) SendAccountEmailVerification(_ context.Context, userID uuid.UUID) error {
	return f.record("SendAccountEmailVerification", "%s", userID)
}

func (f *fakeUsers) SetEmailAndPassword(_ context.Context, in users.SetEmailAndPasswordInput) error {
	return f.record("SetEmailAndPassword", "%s, email=%s password=%q current=%s",
		in.UserID, optText(in.Email), in.Password, optText(in.CurrentPassword))
}

func (f *fakeUsers) ChangePassword(_ context.Context, userID uuid.UUID, nowPassword, newPassword string) error {
	return f.record("ChangePassword", "%s, %q, %q", userID, nowPassword, newPassword)
}

func (f *fakeUsers) RemoveAuthProvider(_ context.Context, userID uuid.UUID, provider string) error {
	return f.record("RemoveAuthProvider", "%s, %q", userID, provider)
}

func optText(p *string) string {
	if p == nil {
		return "nil"
	}
	return strconv.Quote(*p)
}

func optBool(p *bool) string {
	if p == nil {
		return "nil"
	}
	return strconv.FormatBool(*p)
}

// fullInfo は、すべての項目に値がある利用者の情報である。名前の < > & は、Java 版の Jackson と同じく逃がさずに書く。
func fullInfo() users.UserInfo {
	return users.UserInfo{
		ID:                   handlerUserID,
		Email:                ptr("user@example.com"),
		Username:             ptr("名前<a&b>"),
		HasPassword:          true,
		ProfileImage:         ptr("http://localhost:4566/bucket/profile-image.png?X-Amz-Signature=abc&X-Amz-Expires=600"),
		TwoFactorAuthEnabled: true,
		AuthProviders:        []string{"github", "google"},
		Roles:                []string{"ADMIN", "USER"},
		EmailVerified:        true,
		PendingEmail:         ptr("next@example.com"),
	}
}

// fullInfoJSON は、fullInfo を Java 版の UserInfoResponse の項目の順で書いた本文である。
const fullInfoJSON = `{"id":"6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b","email":"user@example.com","username":"名前<a&b>",` +
	`"hasPassword":true,"profileImage":"http://localhost:4566/bucket/profile-image.png?X-Amz-Signature=abc&X-Amz-Expires=600",` +
	`"twoFactorAuthEnabled":true,"authProviders":["github","google"],"roles":["ADMIN","USER"],"emailVerified":true,` +
	`"pendingEmail":"next@example.com"}`

// deleteSessionCookies は、Java 版の CookieUtil.deleteCookie が accessToken と refreshToken を消す Set-Cookie である。
func deleteSessionCookies(secure bool) []string {
	attrs := "; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Lax"
	if secure {
		attrs = "; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; HttpOnly; SameSite=Lax"
	}
	return []string{"accessToken=" + attrs, "refreshToken=" + attrs}
}

// userOp は、利用者の受け口の1つの操作である。call は、検査を通る値で受け口を呼ぶ。calls は、処理がすべて成功するときの
// 処理の呼び出しで、want は、そのときの応答である。
type userOp struct {
	name  string
	call  func(ctx context.Context, h *userHandlers) (any, error)
	calls []string
	want  func(secure bool) wantResponse
}

func infoWant(bool) wantResponse {
	return wantResponse{status: http.StatusOK, contentType: "application/json", body: fullInfoJSON}
}

func noContentWant(bool) wantResponse { return wantResponse{status: http.StatusNoContent} }

func userOps() []userOp {
	id := handlerUserID.String()
	return []userOp{
		{
			name: "GetUserInfo",
			call: func(ctx context.Context, h *userHandlers) (any, error) {
				return h.GetUserInfo(ctx, gen.GetUserInfoRequestObject{})
			},
			calls: []string{"GetUserInfo(" + id + ")"},
			want:  infoWant,
		},
		{
			name: "UpdateUserInfo",
			call: func(ctx context.Context, h *userHandlers) (any, error) {
				form := updateUserInfoForm{
					Username:             ptr("新しい名前"),
					TwoFactorAuthEnabled: boolPtr(true),
					ProfileImage:         &profileImageInput{FileName: "a.PNG", ContentType: "image/png", Content: []byte("PNG")},
				}
				return h.UpdateUserInfo(withForm(ctx, form), gen.UpdateUserInfoRequestObject{})
			},
			calls: []string{
				"UpdateUserInfo(" + id + `, username="新しい名前" twoFactor=true image="a.PNG" "image/png" "PNG")`,
				"GetUserInfo(" + id + ")",
			},
			want: infoWant,
		},
		{
			name: "DeleteUser",
			call: func(ctx context.Context, h *userHandlers) (any, error) {
				return h.DeleteUser(ctx, gen.DeleteUserRequestObject{})
			},
			calls: []string{"DeleteUser(" + id + ")"},
			want: func(secure bool) wantResponse {
				return wantResponse{status: http.StatusNoContent, cookies: deleteSessionCookies(secure)}
			},
		},
		{
			name: "SendAccountEmailVerification",
			call: func(ctx context.Context, h *userHandlers) (any, error) {
				return h.SendAccountEmailVerification(ctx, gen.SendAccountEmailVerificationRequestObject{})
			},
			calls: []string{"SendAccountEmailVerification(" + id + ")"},
			want:  noContentWant,
		},
		{
			name: "SetEmailAndPassword",
			call: func(ctx context.Context, h *userHandlers) (any, error) {
				body := gen.SetEmailAndPasswordJSONRequestBody{
					Email: ptr("next@example.com"), Password: "Passw0rd!", ConfirmPassword: ptr("Passw0rd!"),
					CurrentPassword: ptr("Old-Passw0rd!"),
				}
				return h.SetEmailAndPassword(ctx, gen.SetEmailAndPasswordRequestObject{Body: &body})
			},
			calls: []string{
				"SetEmailAndPassword(" + id + `, email="next@example.com" password="Passw0rd!" current="Old-Passw0rd!")`,
				"GetUserInfo(" + id + ")",
			},
			want: infoWant,
		},
		{
			name: "ChangePassword",
			call: func(ctx context.Context, h *userHandlers) (any, error) {
				body := gen.ChangePasswordJSONRequestBody{NowPassword: "Old-Passw0rd!", NewPassword: "New-Passw0rd!"}
				return h.ChangePassword(ctx, gen.ChangePasswordRequestObject{Body: &body})
			},
			calls: []string{"ChangePassword(" + id + `, "Old-Passw0rd!", "New-Passw0rd!")`},
			want:  noContentWant,
		},
		{
			name: "RemoveAuthProvider",
			call: func(ctx context.Context, h *userHandlers) (any, error) {
				return h.RemoveAuthProvider(ctx, gen.RemoveAuthProviderRequestObject{Provider: "GitHub"})
			},
			calls: []string{"RemoveAuthProvider(" + id + `, "GitHub")`},
			want:  noContentWant,
		},
	}
}

// opName は、処理の呼び出しの記録から、処理の名前を取り出す。
func opName(call string) string {
	name, _, _ := strings.Cut(call, "(")
	return name
}

// TestUserHandlers_SuccessResponses は、利用者の受け口が、Java 版の7つの受け口と同じ状態の番号と本文と Cookie で答える
// ことを確かめる(要件1の受入基準1と2)。名前と画像と2段階認証の設定の変更と、メールアドレスとパスワードの設定は、
// 変えたあとに利用者の情報を読んで答える。処理が *auth.Error を返せば Java 版の AppExceptionHandler と同じ形で答え、
// 続く処理を呼ばない。ほかの誤りは、生成したコードの誤りの処理に渡す。
func TestUserHandlers_SuccessResponses(t *testing.T) {
	ops := userOps()
	if len(ops) != 7 {
		t.Fatalf("操作の数 = %d, want 7", len(ops))
	}
	business := auth.ErrBusiness("業務の誤りの文言")
	for _, op := range ops {
		for _, secure := range []bool{false, true} {
			name := fmt.Sprintf("%s(secure=%v)", op.name, secure)
			f := &fakeUsers{info: fullInfo()}
			resp, err := op.call(loggedIn(), newUserHandlers(f, secure))
			checkResponse(t, name+" の成功", handled(t, resp, err), op.want(secure))
			checkUserCalls(t, name+" の成功", f, op.calls...)

			for i, call := range op.calls {
				f = &fakeUsers{info: fullInfo(), errs: map[string]error{opName(call): business}}
				resp, err = op.call(loggedIn(), newUserHandlers(f, secure))
				label := fmt.Sprintf("%s の %s の *auth.Error", name, opName(call))
				checkResponse(t, label, handled(t, resp, err), errorWant(t, business, secure))
				checkUserCalls(t, label, f, op.calls[:i+1]...)

				f = &fakeUsers{info: fullInfo(), errs: map[string]error{opName(call): fmt.Errorf("包む: %w", errTestBoom)}}
				if _, err = op.call(loggedIn(), newUserHandlers(f, secure)); !errors.Is(err, errTestBoom) {
					t.Errorf("%s の %s のほかの誤り = %v, want %v を包んだ誤り", name, opName(call), err, errTestBoom)
				}
				checkUserCalls(t, name+" の "+opName(call)+" のほかの誤り", f, op.calls[:i+1]...)
			}
		}
	}
}

// TestUserHandlers_DeleteUserClearsCookies は、退会が、Java 版の DeleteUserController と同じく、204 と、本文を書かずに、
// accessToken と refreshToken をこの順に消す2つの Set-Cookie で答えることを確かめる(要件1の受入基準1と2)。
func TestUserHandlers_DeleteUserClearsCookies(t *testing.T) {
	for _, secure := range []bool{false, true} {
		f := &fakeUsers{}
		resp, err := newUserHandlers(f, secure).DeleteUser(loggedIn(), gen.DeleteUserRequestObject{})
		got := handled(t, resp, err)
		want := wantResponse{status: http.StatusNoContent, cookies: deleteSessionCookies(secure)}
		checkResponse(t, fmt.Sprintf("退会(secure=%v)", secure), got, want)
	}
}

// TestUserHandlers_UserGoneClearsCookies は、すでに居ない利用者の要求に、7つの受け口が、Java 版と同じ 401 と
// 「不正なアクセスです。」の本文と、accessToken と refreshToken を消す2つの Set-Cookie で答えることを確かめる
// (要件1の受入基準6)。変えたあとに利用者の情報を読む2つの操作は、読むときに居なくなった場合も同じに答える。
func TestUserHandlers_UserGoneClearsCookies(t *testing.T) {
	gone := auth.ErrCredentialsNotFound(users.MessageInvalidAccess)
	for _, op := range userOps() {
		for _, call := range op.calls {
			for _, secure := range []bool{false, true} {
				f := &fakeUsers{info: fullInfo(), errs: map[string]error{opName(call): gone}}
				resp, err := op.call(loggedIn(), newUserHandlers(f, secure))
				want := wantResponse{
					status:      http.StatusUnauthorized,
					cookies:     deleteSessionCookies(secure),
					contentType: "application/json",
					body:        `{"message":"不正なアクセスです。","errors":{}}`,
				}
				checkResponse(t, fmt.Sprintf("%s の %s で居ない利用者(secure=%v)", op.name, opName(call), secure),
					handled(t, resp, err), want)
			}
		}
	}
}

// TestUserHandlers_NullAndEmptyFields は、値の無い項目を null で、連携と役割が無いときを空の並びで書くことを確かめる。
// Java 版の UserInfoResponse は、null の項目も省かずに書く。
func TestUserHandlers_NullAndEmptyFields(t *testing.T) {
	for _, info := range []users.UserInfo{
		{ID: handlerUserID},
		{ID: handlerUserID, AuthProviders: []string{}, Roles: []string{}},
	} {
		f := &fakeUsers{info: info}
		resp, err := newUserHandlers(f, false).GetUserInfo(loggedIn(), gen.GetUserInfoRequestObject{})
		want := wantResponse{
			status:      http.StatusOK,
			contentType: "application/json",
			body: `{"id":"6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b","email":null,"username":null,"hasPassword":false,` +
				`"profileImage":null,"twoFactorAuthEnabled":false,"authProviders":[],"roles":[],"emailVerified":false,` +
				`"pendingEmail":null}`,
		}
		checkResponse(t, fmt.Sprintf("値の無い項目(連携 %#v)", info.AuthProviders), handled(t, resp, err), want)
	}
}

// TestUserHandlers_OptionalValues は、本文の任意の項目が無い要求で、受け口が nil を処理に渡すことを確かめる。
func TestUserHandlers_OptionalValues(t *testing.T) {
	id := handlerUserID.String()
	f := &fakeUsers{info: fullInfo()}
	h := newUserHandlers(f, false)
	resp, err := h.UpdateUserInfo(withForm(loggedIn(), updateUserInfoForm{}), gen.UpdateUserInfoRequestObject{})
	checkResponse(t, "項目の無い変更", handled(t, resp, err), infoWant(false))
	checkUserCalls(t, "項目の無い変更", f,
		"UpdateUserInfo("+id+", username=nil twoFactor=nil image=nil)", "GetUserInfo("+id+")")

	f = &fakeUsers{info: fullInfo()}
	h = newUserHandlers(f, false)
	body := gen.SetEmailAndPasswordJSONRequestBody{Password: "Passw0rd!"}
	setResp, err := h.SetEmailAndPassword(loggedIn(), gen.SetEmailAndPasswordRequestObject{Body: &body})
	checkResponse(t, "パスワードだけの設定", handled(t, setResp, err), infoWant(false))
	checkUserCalls(t, "パスワードだけの設定", f,
		"SetEmailAndPassword("+id+`, email=nil password="Passw0rd!" current=nil)`, "GetUserInfo("+id+")")
}

// TestUserHandlers_ValidationErrors は、パスワードの変更と、メールアドレスとパスワードの設定が、要求を検査し、誤りが
// あれば処理を呼ばずに 400 と入力の誤りの本文で答えることを確かめる。検査の中身は users のテストが確かめる。
func TestUserHandlers_ValidationErrors(t *testing.T) {
	f := &fakeUsers{}
	h := newUserHandlers(f, false)
	change := gen.ChangePasswordJSONRequestBody{NowPassword: " ", NewPassword: "short"}
	resp, err := h.ChangePassword(loggedIn(), gen.ChangePasswordRequestObject{Body: &change})
	got := handled(t, resp, err)
	if got.status != http.StatusBadRequest {
		t.Errorf("パスワードの変更の検査の誤りの状態の番号 = %d, want 400", got.status)
	}
	checkResponse(t, "パスワードの変更の検査の誤り", got, errorWant(t, users.ValidateChangePassword(" ", "short"), false))

	set := gen.SetEmailAndPasswordJSONRequestBody{Email: ptr("not-an-address"), Password: "", ConfirmPassword: ptr("x")}
	setResp, err := h.SetEmailAndPassword(loggedIn(), gen.SetEmailAndPasswordRequestObject{Body: &set})
	got = handled(t, setResp, err)
	if got.status != http.StatusBadRequest {
		t.Errorf("メールアドレスとパスワードの設定の検査の誤りの状態の番号 = %d, want 400", got.status)
	}
	want := errorWant(t, users.ValidateSetEmailAndPassword(set.Email, set.Password, set.ConfirmPassword), false)
	checkResponse(t, "メールアドレスとパスワードの設定の検査の誤り", got, want)
	checkUserCalls(t, "検査の誤り", f)
}

// TestUserHandlers_MissingContext は、ログインした利用者の ID が context に無いときと、名前と画像と2段階認証の設定の
// 変更で本文を読む中間処理の結果が無いときに、受け口が処理を呼ばずに誤りを返すことを確かめる。どちらも、受け口の前の
// 段が組み立ての誤りで抜けたときにだけ起きるので、生成したコードの誤りの処理が 500 にする。
func TestUserHandlers_MissingContext(t *testing.T) {
	for _, op := range userOps() {
		f := &fakeUsers{}
		_, err := op.call(withForm(context.Background(), updateUserInfoForm{}), newUserHandlers(f, false))
		if !errors.Is(err, errNoLoginUser) {
			t.Errorf("%s のログインした利用者の無い context の誤り = %v, want %v", op.name, err, errNoLoginUser)
		}
		checkUserCalls(t, op.name+" のログインした利用者の無い context", f)
	}
	f := &fakeUsers{}
	_, err := newUserHandlers(f, false).UpdateUserInfo(loggedIn(), gen.UpdateUserInfoRequestObject{})
	if !errors.Is(err, errNoUpdateUserInfoForm) {
		t.Errorf("本文を読んだ結果の無い変更の誤り = %v, want %v", err, errNoUpdateUserInfoForm)
	}
	checkUserCalls(t, "本文を読んだ結果の無い変更", f)
}

// checkUserCalls は、利用者の処理が want の順に呼ばれたことを確かめる。
func checkUserCalls(t *testing.T, name string, f *fakeUsers, want ...string) {
	t.Helper()
	if len(f.calls) == 0 && len(want) == 0 {
		return
	}
	if !reflect.DeepEqual(f.calls, want) {
		t.Errorf("%s の処理の呼び出し = %q, want %q", name, f.calls, want)
	}
}

// TestUserResponses_AllOperationsWrite は、利用者の7つの操作の応答のインタフェースのどのメソッドで書いても、状態の番号と、
// 渡した順の2つの Set-Cookie と、Content-Type と、本文を書くことを確かめる。
func TestUserResponses_AllOperationsWrite(t *testing.T) {
	r := authJSON(http.StatusOK, map[string]string{"a": "<&>"}, "c1=1", "c2=2")
	want := wantResponse{
		status: http.StatusOK, cookies: []string{"c1=1", "c2=2"}, contentType: "application/json", body: `{"a":"<&>"}`,
	}
	for name, visit := range map[string]func(http.ResponseWriter) error{
		"GetUserInfo":                  r.VisitGetUserInfoResponse,
		"UpdateUserInfo":               r.VisitUpdateUserInfoResponse,
		"DeleteUser":                   r.VisitDeleteUserResponse,
		"SendAccountEmailVerification": r.VisitSendAccountEmailVerificationResponse,
		"SetEmailAndPassword":          r.VisitSetEmailAndPasswordResponse,
		"ChangePassword":               r.VisitChangePasswordResponse,
		"RemoveAuthProvider":           r.VisitRemoveAuthProviderResponse,
	} {
		checkResponse(t, name, recordResponse(t, visit), want)
	}
}
