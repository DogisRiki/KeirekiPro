package httpapi

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
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

// formReader は、本文を読む multipart の読み手を返す。
func formReader(body io.Reader) *multipart.Reader {
	return multipart.NewReader(body, "XB")
}

func boolPtr(b bool) *bool { return &b }

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

// TestReadUpdateUserInfoForm_Values は、本文の部分から、名前と画像と2段階認証の設定を取り出すことを確かめる。
func TestReadUpdateUserInfoForm_Values(t *testing.T) {
	noTypeImage := "--XB\r\nContent-Disposition: form-data; name=\"profileImage\"; filename=\"a.png\"\r\n\r\nPNG\r\n"
	for _, tt := range []struct {
		name string
		body string
		want users.UpdateInput
	}{
		{
			name: "3つの項目",
			body: formBody(textField("username", "名前"), textField("twoFactorAuthEnabled", "true"),
				fileField("profileImage", "a.png", "image/png", "PNG")),
			want: users.UpdateInput{
				UserID: handlerUserID, Username: ptr("名前"), TwoFactorAuthEnabled: boolPtr(true),
				ProfileImage: &users.ImageInput{FileName: "a.png", ContentType: "image/png", Content: []byte("PNG")},
			},
		},
		{name: "項目が無い", body: formBody(), want: users.UpdateInput{UserID: handlerUserID}},
		{
			name: "同じ名前の部分は最初の部分を使う",
			body: formBody(textField("username", "a"), textField("username", "b"),
				textField("twoFactorAuthEnabled", "false"), textField("twoFactorAuthEnabled", "maybe"),
				fileField("profileImage", "a.png", "image/png", "A"), fileField("profileImage", "b.png", "image/gif", "B")),
			want: users.UpdateInput{
				UserID: handlerUserID, Username: ptr("a"), TwoFactorAuthEnabled: boolPtr(false),
				ProfileImage: &users.ImageInput{FileName: "a.png", ContentType: "image/png", Content: []byte("A")},
			},
		},
		{
			name: "ファイルとして送った値も値として読む",
			body: formBody(fileField("username", "a.txt", "text/plain", "a"), fileField("twoFactorAuthEnabled", "b.txt", "text/plain", "1")),
			want: users.UpdateInput{UserID: handlerUserID, Username: ptr("a"), TwoFactorAuthEnabled: boolPtr(true)},
		},
		{name: "空の名前", body: formBody(textField("username", "")), want: users.UpdateInput{UserID: handlerUserID, Username: ptr("")}},
		{
			name: "ほかの名前の部分と、大文字と小文字の違う名前の部分は読まない",
			body: formBody(textField("note", "n"), textField("Username", "a")),
			want: users.UpdateInput{UserID: handlerUserID},
		},
		{name: "ファイルの名前の無い画像は無いものとする", body: formBody(textField("profileImage", "PNG")), want: users.UpdateInput{UserID: handlerUserID}},
		{
			name: "中身が0バイトの画像は無いものとする",
			body: formBody(fileField("profileImage", "a.png", "image/png", "")),
			want: users.UpdateInput{UserID: handlerUserID},
		},
		{
			name: "Content-Type の無い画像は空の Content-Type で渡す",
			body: formBody(noTypeImage),
			want: users.UpdateInput{UserID: handlerUserID, ProfileImage: &users.ImageInput{FileName: "a.png", Content: []byte("PNG")}},
		},
	} {
		got, err := readUpdateUserInfoForm(formReader(strings.NewReader(tt.body)), handlerUserID)
		if err != nil {
			t.Errorf("%s: 誤り = %v", tt.name, err)
			continue
		}
		if !reflect.DeepEqual(got, tt.want) {
			t.Errorf("%s: 読んだ値 = %+v、期待 = %+v", tt.name, got, tt.want)
		}
	}
}

// TestReadUpdateUserInfoForm_TwoFactor は、twoFactorAuthEnabled を strconv.ParseBool で読むことを確かめる。
func TestReadUpdateUserInfoForm_TwoFactor(t *testing.T) {
	for _, tt := range []struct {
		value string
		want  bool
	}{
		{"true", true},
		{"false", false},
		{"TRUE", true},
		{"False", false},
		{"t", true},
		{"F", false},
		{"1", true},
		{"0", false},
	} {
		got, err := readUpdateUserInfoForm(formReader(strings.NewReader(formBody(textField("twoFactorAuthEnabled", tt.value)))), handlerUserID)
		if err != nil || got.TwoFactorAuthEnabled == nil || *got.TwoFactorAuthEnabled != tt.want {
			t.Errorf("%q: 値 = %v 誤り = %v、期待 = %v", tt.value, optBool(got.TwoFactorAuthEnabled), err, tt.want)
		}
	}
	for _, v := range []string{"", "on", "yes", " true", "maybe"} {
		_, err := readUpdateUserInfoForm(formReader(strings.NewReader(formBody(textField("twoFactorAuthEnabled", v)))), handlerUserID)
		if !errors.Is(err, errUpdateUserInfoForm) {
			t.Errorf("%q: 誤り = %v、期待 = errUpdateUserInfoForm", v, err)
		}
	}
}

type failingReader struct{}

func (failingReader) Read([]byte) (int, error) { return 0, errors.New("切れた") }

// TestReadUpdateUserInfoForm_Errors は、読めない本文と、UTF-8 として正しくない名前で、errUpdateUserInfoForm を返すことを確かめる。
func TestReadUpdateUserInfoForm_Errors(t *testing.T) {
	for _, tt := range []struct {
		name string
		body io.Reader
	}{
		{name: "UTF-8 として正しくない名前", body: strings.NewReader(formBody(textField("username", "a\xffb")))},
		{name: "空の本文", body: strings.NewReader("")},
		{name: "区切りの無い本文", body: strings.NewReader("not multipart")},
		{name: "閉じない本文", body: strings.NewReader(textField("username", "a") + "--XB\r\nContent-Disposition: form-data; name=\"x\"\r\n\r\nno end")},
		{name: "読む途中の誤り", body: io.MultiReader(strings.NewReader(textField("username", "a")), failingReader{})},
	} {
		got, err := readUpdateUserInfoForm(formReader(tt.body), handlerUserID)
		if !errors.Is(err, errUpdateUserInfoForm) || !reflect.DeepEqual(got, users.UpdateInput{}) {
			t.Errorf("%s: 値 = %+v 誤り = %v、期待は空の値と errUpdateUserInfoForm", tt.name, got, err)
		}
	}
}

// TestLimitUpdateUserInfoBody は、名前と画像と2段階認証の設定の変更の要求だけ、本文を 2097152 バイトまでに限ることを確かめる。
func TestLimitUpdateUserInfoBody(t *testing.T) {
	run := func(method, target, body string) (users.UpdateInput, error) {
		var in users.UpdateInput
		var err error
		h := limitUpdateUserInfoBody(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
			mr, e := r.MultipartReader()
			if e != nil {
				err = e
				return
			}
			in, err = readUpdateUserInfoForm(mr, handlerUserID)
		}))
		r := httptest.NewRequest(method, target, strings.NewReader(body))
		r.Header.Set("Content-Type", formCT)
		h.ServeHTTP(httptest.NewRecorder(), r)
		return in, err
	}

	in, err := run(http.MethodPut, "/api/users/me", paddedBody(t, 2097152))
	if err != nil || in.Username == nil || *in.Username != "a" {
		t.Errorf("2097152 バイト: username = %v 誤り = %v、期待 = a", optText(in.Username), err)
	}
	_, err = run(http.MethodPut, "/api/users/me", paddedBody(t, 2097153))
	var tooLarge *http.MaxBytesError
	if !errors.Is(err, errUpdateUserInfoForm) || !errors.As(err, &tooLarge) {
		t.Errorf("2097153 バイト: 誤り = %v、期待は上限を超えた errUpdateUserInfoForm", err)
	}
	for _, tt := range []struct{ method, target string }{
		{http.MethodPost, "/api/users/me"},
		{http.MethodPut, "/api/users/me/email"},
	} {
		if _, err := run(tt.method, tt.target, paddedBody(t, 2097153)); err != nil {
			t.Errorf("%s %s: 誤り = %v、期待は本文を限らずに読む", tt.method, tt.target, err)
		}
	}
}

// handlerUserID は、受け口のテストでログインしている利用者の ID である。
var handlerUserID = uuid.MustParse("6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b")

// loggedIn は、handlerUserID の利用者がログインしている context を返す。
func loggedIn() context.Context {
	return authctx.With(context.Background(), handlerUserID, []string{"USER"})
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
				body := formBody(textField("username", "新しい名前"), textField("twoFactorAuthEnabled", "true"),
					fileField("profileImage", "a.PNG", "image/png", "PNG"))
				return h.UpdateUserInfo(ctx, gen.UpdateUserInfoRequestObject{Body: formReader(strings.NewReader(body))})
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
	resp, err := h.UpdateUserInfo(loggedIn(), gen.UpdateUserInfoRequestObject{Body: formReader(strings.NewReader(formBody()))})
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

// TestUserHandlers_UpdateUserInfoBadForm は、名前と画像と2段階認証の設定の変更で本文を読めないときに、受け口が処理を
// 呼ばずに 400 と「入力エラーがあります。」で答えることを確かめる。
func TestUserHandlers_UpdateUserInfoBadForm(t *testing.T) {
	f := &fakeUsers{info: fullInfo()}
	body := formBody(textField("twoFactorAuthEnabled", "maybe"))
	resp, err := newUserHandlers(f, false).UpdateUserInfo(loggedIn(), gen.UpdateUserInfoRequestObject{Body: formReader(strings.NewReader(body))})
	checkResponse(t, "読めない本文", handled(t, resp, err), wantResponse{
		status: http.StatusBadRequest, contentType: "application/json",
		body: `{"message":"入力エラーがあります。","errors":{}}`,
	})
	checkUserCalls(t, "読めない本文", f)
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

// TestUserHandlers_MissingContext は、ログインした利用者の ID が context に無いときに、受け口が処理を呼ばずに誤りを
// 返すことを確かめる。認可の中間処理が組み立ての誤りで抜けたときにだけ起きるので、生成したコードの誤りの処理が 500 にする。
func TestUserHandlers_MissingContext(t *testing.T) {
	for _, op := range userOps() {
		f := &fakeUsers{}
		_, err := op.call(context.Background(), newUserHandlers(f, false))
		if !errors.Is(err, errNoLoginUser) {
			t.Errorf("%s のログインした利用者の無い context の誤り = %v, want %v", op.name, err, errNoLoginUser)
		}
		checkUserCalls(t, op.name+" のログインした利用者の無い context", f)
	}
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
