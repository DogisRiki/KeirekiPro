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

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/middleware"
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
