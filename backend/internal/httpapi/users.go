package httpapi

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/middleware"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/authctx"
	"github.com/DogisRiki/KeirekiPro/backend/internal/users"
)

// 名前と画像と2段階認証の設定の変更の要求の上限である。どれも Java 版の Spring Boot と Tomcat の設定の値にあたる。
const (
	// updateUserInfoMaxBody は、本文の大きさの上限である。Java 版の spring.servlet.multipart.max-request-size(2MB)にあたる。
	updateUserInfoMaxBody = 2097152
	// tomcatMaxPostSize は、ファイルの名前の無い部分の名前と中身の合計の上限である。
	// Java 版の server.tomcat.max-http-form-post-size の既定(2MB)にあたる。
	tomcatMaxPostSize = 2097152
	// tomcatMaxParameterCount は、部分と URL の問い合わせの項目の数の合計の上限である。Tomcat の maxParameterCount の既定にあたる。
	tomcatMaxParameterCount = 1000
)

// 本文の項目の名前である。
const (
	formUsername             = "username"
	formProfileImage         = "profileImage"
	formTwoFactorAuthEnabled = "twoFactorAuthEnabled"
)

// errUpdateUserInfoForm は、Java 版が 500 で答え、Go 版が 400 と入力の誤りの本文で答える要求の本文のときに返す誤りである。
var errUpdateUserInfoForm = errors.New("httpapi: 名前と画像と2段階認証の設定の変更の要求の本文を読めません")

// errImageWithoutContentType は、中身のある画像の部分に Content-Type が無いときに返す誤りである。Java 版は、画像の形式を
// 確かめるときに null を比べて例外を投げ、500 と「予期せぬエラーが発生しました。」で答える。Go 版も同じに答える。
var errImageWithoutContentType = errors.New("httpapi: 画像の部分に Content-Type がありません")

// profileImageInput は、要求の本文の画像である。
type profileImageInput struct {
	// FileName は、Spring が Content-Disposition から読んだファイルの名前である
	FileName string
	// ContentType は、部分の Content-Type の見出しの値である。見出しが空の値なら空の文字列である
	ContentType string
	Content     []byte
}

// updateUserInfoForm は、本文を読む中間処理が読んだ項目である。項目が無ければ nil である。
type updateUserInfoForm struct {
	Username             *string
	TwoFactorAuthEnabled *bool
	// ProfileImage は、中身が0バイトの画像の部分と、ファイルの名前の無い部分のときも nil である
	ProfileImage *profileImageInput
}

type updateUserInfoFormKey struct{}

// updateUserInfoFormFrom は、updateUserInfoMiddleware が context に入れた項目を返す。
func updateUserInfoFormFrom(ctx context.Context) (updateUserInfoForm, bool) {
	form, ok := ctx.Value(updateUserInfoFormKey{}).(updateUserInfoForm)
	return form, ok
}

// updateUserInfoMiddleware は、生成したコードの中間処理である。名前と画像と2段階認証の設定の変更の操作のときだけ、
// 要求の本文を Java 版の Spring と Tomcat と同じ規則で読み、読んだ項目を context に入れる。
// 本文を読めないときは、400 と入力の誤りの本文で答え、次の処理を呼ばない。
func updateUserInfoMiddleware(f gen.StrictHandlerFunc, operationID string) gen.StrictHandlerFunc {
	if operationID != "UpdateUserInfo" {
		return f
	}
	return func(ctx context.Context, w http.ResponseWriter, r *http.Request, request any) (any, error) {
		form, err := readUpdateUserInfoForm(r)
		if errors.Is(err, errImageWithoutContentType) {
			return nil, err
		}
		if err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.MessageBadRequest)
			return nil, nil
		}
		return f(context.WithValue(ctx, updateUserInfoFormKey{}, form), w, r, request)
	}
}

// formPart は、部分を、Tomcat が文字の値とみなすか(ファイルの名前が無いか)と、Spring がファイルとみなすか
// (Spring の読み方でファイルの名前があるか)で分けたものである。2つの見方は、同じ部分で食い違うことがある。
type formPart struct {
	multipartPart
	springFile     bool
	springFileName string
}

// readUpdateUserInfoForm は、design の「本文を読む中間処理と multipart の読み方」の節の5つの手順のうち、
// 項目を context に入れる前までを行う。Java 版の処理の順は次のとおりである。
//  1. Spring の DispatcherServlet が、Tomcat に本文を部分に分けさせ、部分ごとに Content-Disposition を読む
//  2. Spring が、Content-Type が multipart/form-data かを確かめる(@PutMapping の consumes)
//  3. Spring が、@RequestParam の3つの項目を読む。最初に項目の値を読むときに、Tomcat が URL の問い合わせを読む
//  4. 処理が、画像の形式を確かめる
//
// 1 から 3 で Java 版が 500 で答える要求には、errUpdateUserInfoForm を返す。4 で 500 で答える要求には、
// errImageWithoutContentType を返す。1 から 3 の誤りどうしの順は、どれも同じ答えになるので写さない。
func readUpdateUserInfoForm(r *http.Request) (updateUserInfoForm, error) {
	body, err := io.ReadAll(io.LimitReader(r.Body, updateUserInfoMaxBody+1))
	if err != nil {
		return updateUserInfoForm{}, fmt.Errorf("%w: %w", errUpdateUserInfoForm, err)
	}
	if len(body) > updateUserInfoMaxBody {
		return updateUserInfoForm{}, fmt.Errorf("%w: 本文が 2097152 バイトを超える", errUpdateUserInfoForm)
	}
	contentType := r.Header.Get("Content-Type")
	parts, err := splitFormParts(contentType, body)
	if err != nil {
		return updateUserInfoForm{}, err
	}
	if m, ok := parseMediaType(contentType); !ok || m.typ != "multipart" || m.sub != "form-data" {
		return updateUserInfoForm{}, fmt.Errorf("%w: Content-Type が multipart/form-data でない", errUpdateUserInfoForm)
	}
	query, err := tomcatQueryParams(r.URL.RawQuery, tomcatMaxParameterCount-len(parts))
	if err != nil {
		return updateUserInfoForm{}, err
	}

	var form updateUserInfoForm
	if form.Username, err = formUsernameValue(parts, query); err != nil {
		return updateUserInfoForm{}, err
	}
	image, hasContentType := formProfileImageValue(parts)
	form.ProfileImage = image
	if form.TwoFactorAuthEnabled, err = formTwoFactorValue(parts, query); err != nil {
		return updateUserInfoForm{}, err
	}
	// Java 版は、3つの項目を読み終えてから、処理の最初に画像の形式を確かめる
	if image != nil && !hasContentType {
		return updateUserInfoForm{}, errImageWithoutContentType
	}
	return form, nil
}

// splitFormParts は、本文を部分に分け、部分ごとに、Spring がファイルとみなすかを決める。Tomcat の Request.parseParts が、
// ファイルの名前の無い部分の名前と中身の合計を server.tomcat.max-http-form-post-size と比べる検査も写す。
func splitFormParts(contentType string, body []byte) ([]formPart, error) {
	parts, err := parseMultipart(contentType, body)
	if err != nil {
		return nil, fmt.Errorf("%w: %w", errUpdateUserInfoForm, err)
	}
	out := make([]formPart, 0, len(parts))
	postSize := 0
	for _, p := range parts {
		if !p.HasFileName {
			// Tomcat は、名前の UTF-8 のバイト数と = の1と、中身のバイト数と区切りの1を足す
			postSize += len(p.FieldName) + 1 + len(p.Body) + 1
			if postSize > tomcatMaxPostSize {
				return nil, fmt.Errorf("%w: 文字の値の合計が max-http-form-post-size を超える", errUpdateUserInfoForm)
			}
		}
		// Spring の StandardMultipartHttpServletRequest は、どの部分の Content-Disposition も読み、読めなければ
		// 要求の全体を誤りにする。Tomcat が返す部分は、どれも Content-Disposition を持つ
		header, _ := p.Headers.get("Content-Disposition")
		cd, err := parseContentDisposition(header)
		if err != nil {
			return nil, fmt.Errorf("%w: %w", errUpdateUserInfoForm, err)
		}
		out = append(out, formPart{multipartPart: p, springFile: cd.HasFileName, springFileName: cd.FileName})
	}
	return out, nil
}

// queryParam は、URL の問い合わせの項目の名前と値である。
type queryParam struct{ name, value string }

// tomcatQueryParams は、Tomcat の Parameters.processParameters と UDecoder を写し、URL の問い合わせを項目に分ける。
// limit は、問い合わせから読める項目の数である。Tomcat は、本文の部分を先に読むので、部分の数だけ上限が減っている。
// Tomcat は、名前の無い項目と、%XX の形の誤りと、UTF-8 として誤ったバイトと、上限を超える項目を例外にし、
// Java 版は 500 で答える。
func tomcatQueryParams(raw string, limit int) ([]queryParam, error) {
	var out []queryParam
	for chunk := range strings.SplitSeq(raw, "&") {
		name, value, hasValue := strings.Cut(chunk, "=")
		if name == "" {
			if !hasValue {
				// && のように空の項目は読み飛ばす
				continue
			}
			return nil, fmt.Errorf("%w: 問い合わせに名前の無い項目がある", errUpdateUserInfoForm)
		}
		if len(out) >= limit {
			return nil, fmt.Errorf("%w: 問い合わせの項目が多すぎる", errUpdateUserInfoForm)
		}
		n, okName := tomcatQueryDecode(name)
		v, okValue := tomcatQueryDecode(value)
		if !okName || !okValue {
			return nil, fmt.Errorf("%w: 問い合わせの項目を解けない", errUpdateUserInfoForm)
		}
		out = append(out, queryParam{name: n, value: v})
	}
	return out, nil
}

// tomcatQueryDecode は、+ を空白にし、%XX をバイトに戻し、UTF-8 として誤ったバイトを誤りにする。
func tomcatQueryDecode(s string) (string, bool) {
	b := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		switch c := s[i]; c {
		case '+':
			b = append(b, ' ')
		case '%':
			if i+2 >= len(s) {
				return "", false
			}
			hi, ok1 := hexDigit(s[i+1])
			lo, ok2 := hexDigit(s[i+2])
			if !ok1 || !ok2 {
				return "", false
			}
			b = append(b, hi<<4|lo)
			i += 2
		default:
			b = append(b, c)
		}
	}
	return string(b), utf8.Valid(b)
}

// formTextValues は、名前が name の文字の値を、Tomcat の getParameterValues と同じ順に返す。Tomcat は、本文の部分を
// URL の問い合わせより先に読むので、本文の値が先で、問い合わせの値が後になる。本文の値は、JDK と同じく UTF-8 として読み、
// 誤ったバイトを U+FFFD にする。
func formTextValues(parts []formPart, query []queryParam, name string) []string {
	var values []string
	for _, p := range parts {
		if !p.HasFileName && p.FieldName == name {
			values = append(values, decodeJDKUTF8(p.Body))
		}
	}
	for _, q := range query {
		if q.name == name {
			values = append(values, q.value)
		}
	}
	return values
}

// hasSpringFile は、Spring が name のファイルとみなす部分があるかを返す。Spring の @RequestParam は、ファイルを
// 文字の値より先に探すので、ファイルがあれば、文字の型の項目をファイルから変換しようとして例外を投げる。
func hasSpringFile(parts []formPart, name string) bool {
	for _, p := range parts {
		if p.springFile && p.FieldName == name {
			return true
		}
	}
	return false
}

// formUsernameValue は、username の値を返す。値が2つ以上あれば、Spring と同じく , でつなぐ。
func formUsernameValue(parts []formPart, query []queryParam) (*string, error) {
	if hasSpringFile(parts, formUsername) {
		return nil, fmt.Errorf("%w: username がファイルとして送られた", errUpdateUserInfoForm)
	}
	values := formTextValues(parts, query, formUsername)
	if len(values) == 0 {
		return nil, nil
	}
	v := strings.Join(values, ",")
	return &v, nil
}

// formTwoFactorValue は、twoFactorAuthEnabled の値を、Spring の文字列から Boolean への変換と同じ規則で返す。
//
// Spring は、まず変換の部品(StringToBooleanConverter)で変換する。値が2つ以上あれば、最初の値だけを変換する。
// 変換の部品が例外を投げると、Spring は、値を , でつないで、既定の CustomBooleanEditor で変換し直す。
// 2つ以上の値をつないだ文字列には , があるので、CustomBooleanEditor でも変換できない。
func formTwoFactorValue(parts []formPart, query []queryParam) (*bool, error) {
	if hasSpringFile(parts, formTwoFactorAuthEnabled) {
		return nil, fmt.Errorf("%w: twoFactorAuthEnabled がファイルとして送られた", errUpdateUserInfoForm)
	}
	values := formTextValues(parts, query, formTwoFactorAuthEnabled)
	switch len(values) {
	case 0:
		return nil, nil
	case 1:
		return springBooleanEditor(values[0])
	default:
		return springStringToBoolean(values[0])
	}
}

var (
	springTrueValues  = []string{"true", "on", "yes", "1"}
	springFalseValues = []string{"false", "off", "no", "0"}
)

// springStringToBoolean は、Spring の StringToBooleanConverter を写したものである。Java の trim で前後の U+0020 以下の
// 字を除き、空なら null、小文字にして決まった語と比べる。Java の toLowerCase で決まった語の字になる ASCII でない字は無いので、
// ASCII の字だけを小文字にする。
func springStringToBoolean(s string) (*bool, error) {
	v := javaTrim(s)
	if v == "" {
		return nil, nil
	}
	lower := asciiLower(v)
	for _, w := range springTrueValues {
		if lower == w {
			return boolPtr(true), nil
		}
	}
	for _, w := range springFalseValues {
		if lower == w {
			return boolPtr(false), nil
		}
	}
	return nil, fmt.Errorf("%w: twoFactorAuthEnabled を真偽として読めない", errUpdateUserInfoForm)
}

// springBooleanEditor は、変換の部品が例外を投げたあとに Spring が使う CustomBooleanEditor を写したものである。
// 決まった語との比べ方が Java の equalsIgnoreCase なので、変換の部品が受け付ける値に加えて、yeſ のように、大文字に
// すると決まった語と同じになる値も受け付ける。
func springBooleanEditor(s string) (*bool, error) {
	v := javaTrim(s)
	if v == "" {
		return nil, nil
	}
	for _, w := range springTrueValues {
		if javaEqualsIgnoreCase(v, w) {
			return boolPtr(true), nil
		}
	}
	for _, w := range springFalseValues {
		if javaEqualsIgnoreCase(v, w) {
			return boolPtr(false), nil
		}
	}
	return nil, fmt.Errorf("%w: twoFactorAuthEnabled を真偽として読めない", errUpdateUserInfoForm)
}

// javaEqualsIgnoreCase は、Java の String.equalsIgnoreCase を、ASCII の語 word と比べる場合に限って写したものである。
// Java は、UTF-16 の字ごとに、同じか、大文字にして同じか、大文字にしてから小文字にして同じかを比べる。BMP の外の字は
// UTF-16 の2つの字になり、どちらも ASCII の字と同じにならない。
func javaEqualsIgnoreCase(s, word string) bool {
	if utf8.RuneCountInString(s) != len(word) {
		return false
	}
	i := 0
	for _, c := range s {
		w := rune(word[i])
		i++
		if c == w {
			continue
		}
		if c > 0xFFFF {
			return false
		}
		u1, u2 := unicode.ToUpper(c), unicode.ToUpper(w)
		if u1 != u2 && unicode.ToLower(u1) != unicode.ToLower(u2) {
			return false
		}
	}
	return true
}

func boolPtr(b bool) *bool { return &b }

// formProfileImageValue は、Spring が profileImage として渡す最初のファイルの部分と、その部分に Content-Type の見出しが
// あるかを返す。ファイルの部分が無いときと、中身が0バイトのときは nil を返す。Java 版の処理は、中身が0バイトの画像を、
// 画像が無いものとして扱う。
func formProfileImageValue(parts []formPart) (*profileImageInput, bool) {
	for _, p := range parts {
		if !p.springFile || p.FieldName != formProfileImage {
			continue
		}
		if len(p.Body) == 0 {
			return nil, false
		}
		contentType, ok := p.Headers.get("Content-Type")
		return &profileImageInput{FileName: p.springFileName, ContentType: contentType, Content: p.Body}, ok
	}
	return nil, false
}

// UserService は、受け口が使う利用者の処理である。*users.Service が満たす。
type UserService interface {
	GetUserInfo(ctx context.Context, userID uuid.UUID) (users.UserInfo, error)
	UpdateUserInfo(ctx context.Context, in users.UpdateInput) error
	DeleteUser(ctx context.Context, userID uuid.UUID) error
	SendAccountEmailVerification(ctx context.Context, userID uuid.UUID) error
	SetEmailAndPassword(ctx context.Context, in users.SetEmailAndPasswordInput) error
	ChangePassword(ctx context.Context, userID uuid.UUID, nowPassword, newPassword string) error
	RemoveAuthProvider(ctx context.Context, userID uuid.UUID, provider string) error
}

var _ UserService = (*users.Service)(nil)

// userHandlers は、利用者の7つの操作の受け口である。
type userHandlers struct {
	svc    UserService
	secure bool
}

// errNoLoginUser は、ログインした利用者の ID が context に無いことを表す。認可の中間処理が抜けた組み立ての誤りで
// だけ起き、生成したコードの誤りの処理が 500 にする。
var errNoLoginUser = errors.New("httpapi: ログインした利用者が context にありません")

// errNoUpdateUserInfoForm は、名前と画像と2段階認証の設定の変更で、本文を読む中間処理の結果が context に無いことを
// 表す。中間処理が抜けた組み立ての誤りでだけ起き、生成したコードの誤りの処理が 500 にする。
var errNoUpdateUserInfoForm = errors.New("httpapi: 本文を読んだ結果が context にありません")

// newUserHandlers は、利用者の操作の受け口を作る。
func newUserHandlers(svc UserService, secure bool) *userHandlers {
	return &userHandlers{svc: svc, secure: secure}
}

// fail は、err が *auth.Error を含めばその応答を、含まなければ err をそのまま返す。
func (h *userHandlers) fail(err error) (authResponse, error) {
	if r, ok := authErrorResponse(err, h.secure); ok {
		return r, nil
	}
	return authResponse{}, err
}

// info は、Java 版の受け口と同じく、利用者の情報を読み、200 と UserInfoResponse の本文で答える。
func (h *userHandlers) info(ctx context.Context, userID uuid.UUID) (authResponse, error) {
	u, err := h.svc.GetUserInfo(ctx, userID)
	if err != nil {
		return h.fail(err)
	}
	return authJSON(http.StatusOK, newUserInfoBody(u)), nil
}

// GetUserInfo は、利用者の情報を答える。
func (h *userHandlers) GetUserInfo(ctx context.Context, _ gen.GetUserInfoRequestObject) (gen.GetUserInfoResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	return h.info(ctx, id)
}

// UpdateUserInfo は、名前と画像と2段階認証の設定を変え、Java 版の UpdateUserInfoController と同じく、変えたあとの
// 利用者の情報を 200 で答える。本文は、受け口の前の中間処理が読んで context に入れてある。
func (h *userHandlers) UpdateUserInfo(
	ctx context.Context, _ gen.UpdateUserInfoRequestObject,
) (gen.UpdateUserInfoResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	form, ok := updateUserInfoFormFrom(ctx)
	if !ok {
		return authResponse{}, errNoUpdateUserInfoForm
	}
	in := users.UpdateInput{UserID: id, Username: form.Username, TwoFactorAuthEnabled: form.TwoFactorAuthEnabled}
	if img := form.ProfileImage; img != nil {
		in.ProfileImage = &users.ImageInput{FileName: img.FileName, ContentType: img.ContentType, Content: img.Content}
	}
	if err := h.svc.UpdateUserInfo(ctx, in); err != nil {
		return h.fail(err)
	}
	return h.info(ctx, id)
}

// DeleteUser は、退会する。Java 版の DeleteUserController と同じく、204 と、Cookie accessToken と refreshToken を
// 消す Cookie で答える。
func (h *userHandlers) DeleteUser(ctx context.Context, _ gen.DeleteUserRequestObject) (gen.DeleteUserResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	if err := h.svc.DeleteUser(ctx, id); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent,
		auth.DeleteCookie("accessToken", "/", h.secure), auth.DeleteCookie("refreshToken", "/", h.secure)), nil
}

// SendAccountEmailVerification は、確認のメールを送る。204 で答える。
func (h *userHandlers) SendAccountEmailVerification(
	ctx context.Context, _ gen.SendAccountEmailVerificationRequestObject,
) (gen.SendAccountEmailVerificationResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	if err := h.svc.SendAccountEmailVerification(ctx, id); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// SetEmailAndPassword は、メールアドレスとパスワードを設定し、Java 版の SetEmailAndPasswordController と同じく、
// 設定したあとの利用者の情報を 200 で答える。要求の検査は、Java 版の @Valid にあたる。
func (h *userHandlers) SetEmailAndPassword(
	ctx context.Context, req gen.SetEmailAndPasswordRequestObject,
) (gen.SetEmailAndPasswordResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	b := req.Body
	if e := users.ValidateSetEmailAndPassword(b.Email, b.Password, b.ConfirmPassword); e != nil {
		return h.fail(e)
	}
	in := users.SetEmailAndPasswordInput{UserID: id, Email: b.Email, Password: b.Password, CurrentPassword: b.CurrentPassword}
	if err := h.svc.SetEmailAndPassword(ctx, in); err != nil {
		return h.fail(err)
	}
	return h.info(ctx, id)
}

// ChangePassword は、パスワードを変える。要求の検査は、Java 版の @Valid にあたる。204 で答える。
func (h *userHandlers) ChangePassword(
	ctx context.Context, req gen.ChangePasswordRequestObject,
) (gen.ChangePasswordResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	b := req.Body
	if e := users.ValidateChangePassword(b.NowPassword, b.NewPassword); e != nil {
		return h.fail(e)
	}
	if err := h.svc.ChangePassword(ctx, id, b.NowPassword, b.NewPassword); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// RemoveAuthProvider は、経路の provider の連携を解除する。204 で答える。
func (h *userHandlers) RemoveAuthProvider(
	ctx context.Context, req gen.RemoveAuthProviderRequestObject,
) (gen.RemoveAuthProviderResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	if err := h.svc.RemoveAuthProvider(ctx, id, req.Provider); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}
