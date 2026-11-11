package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/logging"
)

// AuthService は、受け口が使う認証の処理である。*auth.Service が満たす。
type AuthService interface {
	Login(ctx context.Context, email, password string) (auth.LoginResult, error)
	VerifyTwoFactor(ctx context.Context, challenge, code string) (auth.SessionTokens, error)
	Refresh(ctx context.Context, refreshToken string) (string, error)
	Logout(ctx context.Context, refreshToken, accessToken string) error
	Register(ctx context.Context, in auth.RegisterInput) error
	VerifyEmail(ctx context.Context, token string) (auth.VerifyEmailResult, error)
	ResendEmailVerification(ctx context.Context, token string) error
	ResendEmailVerificationForLogin(ctx context.Context, email, password string) error
	RequestPasswordReset(ctx context.Context, email string) error
	VerifyPasswordResetToken(ctx context.Context, token string) error
	ResetPassword(ctx context.Context, token, newPassword string) error
	StartOIDC(ctx context.Context, provider, redirectURI string) (string, error)
	HandleOIDCCallback(ctx context.Context, code, state, errParam *string, redirectURI string) auth.OIDCCallbackResult
}

var _ AuthService = (*auth.Service)(nil)

// authHandlers は、認証の操作の受け口である。要求の値を検査して認証の処理に渡し、結果を Java 版の受け口と同じ
// 状態の番号と Cookie と本文で答える。*auth.Error は authErrorResponse の形で答え、ほかの誤りは、生成したコードの
// 誤りの処理に渡して 500 にする。
type authHandlers struct {
	svc AuthService
	// logger は、Google と GitHub から戻ったときの失敗の元の誤りを書く。
	logger *slog.Logger
	// secure は、Cookie に Secure を付けるかである。
	secure bool
	// apiBaseURL は、設定 App.APIBaseURL である。空でなければ、戻り先の URL をこの値から作る。
	apiBaseURL string
	// now は、今の時刻を返す。Cookie twoFactorChallenge の Expires に使う。
	now func() time.Time
}

// newAuthHandlers は、認証の操作の受け口を作る。
func newAuthHandlers(svc AuthService, logger *slog.Logger, secure bool, apiBaseURL string, now func() time.Time) *authHandlers {
	return &authHandlers{svc: svc, logger: logger, secure: secure, apiBaseURL: apiBaseURL, now: now}
}

// fail は、err が *auth.Error を含めばその応答を、含まなければ err をそのまま返す。
func (h *authHandlers) fail(err error) (authResponse, error) {
	if r, ok := authErrorResponse(err, h.secure); ok {
		return r, nil
	}
	return authResponse{}, err
}

// sessionCookies は、Java 版の AuthCookieIssuer と同じく、Cookie accessToken と refreshToken をこの順に並べる。
func (h *authHandlers) sessionCookies(s auth.SessionTokens) []string {
	return []string{
		auth.SessionCookie("accessToken", s.AccessToken, h.secure),
		auth.SessionCookie("refreshToken", s.RefreshToken, h.secure),
	}
}

// value は、無い Cookie と本文の項目を空の値にする。認証の処理は、空の値を Java 版の値が無いときと同じに扱う。
func value(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

// Login は、ログインする。2段階認証が有効な利用者には 202 と Cookie twoFactorChallenge で、無効な利用者には
// 200 と Cookie accessToken と refreshToken で答える。どちらも本文を書かない。
func (h *authHandlers) Login(ctx context.Context, req gen.LoginRequestObject) (gen.LoginResponseObject, error) {
	if e := auth.ValidateLogin(req.Body.Email, req.Body.Password); e != nil {
		return h.fail(e)
	}
	res, err := h.svc.Login(ctx, req.Body.Email, req.Body.Password)
	if err != nil {
		return h.fail(err)
	}
	if res.TwoFactorChallenge != "" {
		return authNoBody(http.StatusAccepted, auth.ChallengeCookie(res.TwoFactorChallenge, h.secure, h.now())), nil
	}
	return authNoBody(http.StatusOK, h.sessionCookies(res.Session)...), nil
}

// VerifyTwoFactorAuth は、2段階認証の確認のコードを確かめる。確認のコードを検査してから、Cookie twoFactorChallenge
// の値を処理に渡す。成功したら 200 と、Cookie accessToken、refreshToken、twoFactorChallenge を消す Cookie で答える。
func (h *authHandlers) VerifyTwoFactorAuth(
	ctx context.Context, req gen.VerifyTwoFactorAuthRequestObject,
) (gen.VerifyTwoFactorAuthResponseObject, error) {
	if e := auth.ValidateTwoFactor(req.Body.Code); e != nil {
		return h.fail(e)
	}
	s, err := h.svc.VerifyTwoFactor(ctx, value(req.Params.TwoFactorChallenge), req.Body.Code)
	if err != nil {
		return h.fail(err)
	}
	cookies := append(h.sessionCookies(s), auth.DeleteCookie(auth.ChallengeCookieName, auth.ChallengeCookiePath, h.secure))
	return authNoBody(http.StatusOK, cookies...), nil
}

// RefreshToken は、Cookie refreshToken で、アクセストークンを作り直す。200 と Cookie accessToken で答える。
func (h *authHandlers) RefreshToken(ctx context.Context, req gen.RefreshTokenRequestObject) (gen.RefreshTokenResponseObject, error) {
	access, err := h.svc.Refresh(ctx, value(req.Params.RefreshToken))
	if err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusOK, auth.SessionCookie("accessToken", access, h.secure)), nil
}

// Logout は、ログアウトする。204 と、Cookie accessToken と refreshToken を消す Cookie で答える。
func (h *authHandlers) Logout(ctx context.Context, req gen.LogoutRequestObject) (gen.LogoutResponseObject, error) {
	if err := h.svc.Logout(ctx, value(req.Params.RefreshToken), value(req.Params.AccessToken)); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent,
		auth.DeleteCookie("accessToken", "/", h.secure), auth.DeleteCookie("refreshToken", "/", h.secure)), nil
}

// RegisterUser は、新規に登録する。202 で答える。
func (h *authHandlers) RegisterUser(ctx context.Context, req gen.RegisterUserRequestObject) (gen.RegisterUserResponseObject, error) {
	b := req.Body
	if e := auth.ValidateRegister(b.Email, b.Username, b.Password, b.ConfirmPassword); e != nil {
		return h.fail(e)
	}
	if err := h.svc.Register(ctx, auth.RegisterInput{Email: b.Email, Username: b.Username, Password: b.Password}); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusAccepted), nil
}

// VerifyEmail は、メールアドレスを確かめる。200 と {result, passwordResetToken} で答える。
func (h *authHandlers) VerifyEmail(ctx context.Context, req gen.VerifyEmailRequestObject) (gen.VerifyEmailResponseObject, error) {
	if e := auth.ValidateEmailVerificationToken(req.Body.Token); e != nil {
		return h.fail(e)
	}
	res, err := h.svc.VerifyEmail(ctx, req.Body.Token)
	if err != nil {
		return h.fail(err)
	}
	body := verifyEmailBody{Result: res.Result}
	if res.PasswordResetToken != "" {
		body.PasswordResetToken = &res.PasswordResetToken
	}
	return authJSON(http.StatusOK, body), nil
}

// ResendEmailVerification は、確認のメールを送り直す。204 で答える。
func (h *authHandlers) ResendEmailVerification(
	ctx context.Context, req gen.ResendEmailVerificationRequestObject,
) (gen.ResendEmailVerificationResponseObject, error) {
	if e := auth.ValidateEmailVerificationToken(req.Body.Token); e != nil {
		return h.fail(e)
	}
	if err := h.svc.ResendEmailVerification(ctx, req.Body.Token); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// ResendEmailVerificationForLogin は、ログインの画面から確認のメールを送り直す。204 で答える。
func (h *authHandlers) ResendEmailVerificationForLogin(
	ctx context.Context, req gen.ResendEmailVerificationForLoginRequestObject,
) (gen.ResendEmailVerificationForLoginResponseObject, error) {
	if e := auth.ValidateResendEmailVerificationForLogin(req.Body.Email, req.Body.Password); e != nil {
		return h.fail(e)
	}
	if err := h.svc.ResendEmailVerificationForLogin(ctx, req.Body.Email, req.Body.Password); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// RequestPasswordReset は、パスワードの再設定のメールを送る。204 で答える。
func (h *authHandlers) RequestPasswordReset(
	ctx context.Context, req gen.RequestPasswordResetRequestObject,
) (gen.RequestPasswordResetResponseObject, error) {
	if e := auth.ValidatePasswordResetRequest(req.Body.Email); e != nil {
		return h.fail(e)
	}
	if err := h.svc.RequestPasswordReset(ctx, req.Body.Email); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// VerifyPasswordResetToken は、パスワードの再設定の値が有効かを確かめる。Java 版と同じく本文を検査しない。204 で答える。
func (h *authHandlers) VerifyPasswordResetToken(
	ctx context.Context, req gen.VerifyPasswordResetTokenRequestObject,
) (gen.VerifyPasswordResetTokenResponseObject, error) {
	if err := h.svc.VerifyPasswordResetToken(ctx, value(req.Body.Token)); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// ResetPassword は、パスワードを再設定する。Java 版と同じく、新しいパスワードを検査し、再設定の値は検査しない。
// 204 で答える。
func (h *authHandlers) ResetPassword(ctx context.Context, req gen.ResetPasswordRequestObject) (gen.ResetPasswordResponseObject, error) {
	b := req.Body
	if e := auth.ValidateResetPassword(b.Password, b.ConfirmPassword); e != nil {
		return h.fail(e)
	}
	if err := h.svc.ResetPassword(ctx, value(b.Token), b.Password); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// oidcCallbackPath は、Google と GitHub から戻る先の経路である。
const oidcCallbackPath = "/api/auth/oidc/callback"

// StartOidcAuthorization は、Google か GitHub のログインを始める。200 と、引用符を付けないログインの開始の URL の
// 本文で答える。Java 版と同じく、処理を呼んでから、Content-Type を Accept で決める。Accept を読めないときと、
// 選べる型が無いときは、406 で、本文を書かずに答える。
func (h *authHandlers) StartOidcAuthorization(
	ctx context.Context, req gen.StartOidcAuthorizationRequestObject,
) (gen.StartOidcAuthorizationResponseObject, error) {
	u, err := h.svc.StartOIDC(ctx, req.Params.Provider, h.redirectURI(ctx))
	if err != nil {
		return h.fail(err)
	}
	contentType, ok := negotiateText(requestInfo(ctx).accept)
	if !ok {
		return authNoBody(http.StatusNotAcceptable), nil
	}
	return authText(contentType, u), nil
}

// HandleOidcCallback は、Google か GitHub から戻った要求を処理する。Java 版の OidcCallbackController と同じく、
// 成功なら 302 と Cookie accessToken と refreshToken で、失敗なら 302 だけで答える。失敗の元の誤りはログに書く。
func (h *authHandlers) HandleOidcCallback(
	ctx context.Context, req gen.HandleOidcCallbackRequestObject,
) (gen.HandleOidcCallbackResponseObject, error) {
	p := req.Params
	res := h.svc.HandleOIDCCallback(ctx, p.Code, p.State, p.Error, h.redirectURI(ctx))
	if res.Cause != nil {
		h.logger.LogAttrs(ctx, slog.LevelError, "oidc_callback_error", logging.ErrorAttr(res.Cause, nil))
	}
	if res.Session.AccessToken == "" {
		return authRedirect(res.Location), nil
	}
	return authRedirect(res.Location, h.sessionCookies(res.Session)...), nil
}

// redirectURI は、戻り先の URL を作る。設定 App.APIBaseURL が空でなければその値に、空なら Java 版の
// DevBaseUrlResolver と同じく要求の http:// と Host に、経路を足す。
func (h *authHandlers) redirectURI(ctx context.Context) string {
	if h.apiBaseURL != "" {
		return h.apiBaseURL + oidcCallbackPath
	}
	return "http://" + javaHost(requestInfo(ctx).host) + oidcCallbackPath
}

// javaHost は、Host を Java 版の Tomcat と同じく書き直す。ポートは数として読み直し、80 なら書かない。
// ポートが空なら 0 にする。ポートを数として読めないときは、Host をそのまま返す。
func javaHost(host string) string {
	i := strings.LastIndexByte(host, ':')
	if i < 0 {
		return host
	}
	// IPv6 の [::1] のようにポートの無い Host は、最後の : のあとが ] で終わるので、数として読めない
	port := 0
	if digits := host[i+1:]; digits != "" {
		n, err := strconv.Atoi(digits)
		if err != nil {
			return host
		}
		port = n
	}
	if port == 80 {
		return host[:i]
	}
	return host[:i+1] + strconv.Itoa(port)
}

// authRequestInfo は、Google と GitHub の操作の受け口が使う、要求の Host と Accept の行である。
type authRequestInfo struct {
	host   string
	accept []string
}

type authRequestKey struct{}

// authRequestMiddleware は、生成したコードの中間処理である。Google と GitHub のログインの開始と戻り先の操作のときに、
// 要求の Host と Accept の行を context に入れる。
func authRequestMiddleware(f gen.StrictHandlerFunc, operationID string) gen.StrictHandlerFunc {
	if operationID != "StartOidcAuthorization" && operationID != "HandleOidcCallback" {
		return f
	}
	return func(ctx context.Context, w http.ResponseWriter, r *http.Request, request any) (any, error) {
		info := authRequestInfo{host: r.Host, accept: r.Header.Values("Accept")}
		return f(context.WithValue(ctx, authRequestKey{}, info), w, r, request)
	}
}

// requestInfo は、authRequestMiddleware が context に入れた値を返す。
func requestInfo(ctx context.Context) authRequestInfo {
	info, _ := ctx.Value(authRequestKey{}).(authRequestInfo)
	return info
}

// 以下は、Java 版の Spring が文字列の答えに型を選ぶ処理と、Tomcat が Content-Type を書き直す処理を写したものである。

// mediaParam は、型の引数の名前と値である。
type mediaParam struct{ name, value string }

// mediaType は、Spring の MediaType と同じく、小文字にした型と下位の型と、書かれた順の引数である。
type mediaType struct {
	typ, sub string
	params   []mediaParam
}

// textProducible は、Spring が文字列を書ける型である。StringHttpMessageConverter と Jackson の型をこの順に並べる。
var textProducible = []mediaType{
	{typ: "text", sub: "plain"}, {typ: "*", sub: "*"}, {typ: "application", sub: "json"}, {typ: "application", sub: "*+json"},
}

// negotiateText は、Accept の行から Content-Type を決める。Spring と同じく、Accept の型を q の値と具体さの順に並べ、
// 文字列を書ける型と組み合わせて並べ直し、最初の具体的な型を選ぶ。Accept を読めないときと、型が50を超えるときと、
// 具体的な型が無いときは ok が false になる。
func negotiateText(accept []string) (string, bool) {
	acceptable, ok := parseAccept(accept)
	if !ok {
		return "", false
	}
	sortBySpecificity(acceptable)
	var compatible []mediaType
	for _, a := range acceptable {
		for _, p := range textProducible {
			if a.compatibleWith(p) {
				compatible = append(compatible, mostSpecific(a, p))
			}
		}
	}
	sortBySpecificity(compatible)
	// Spring は、*/* と application/* が先に来れば application/octet-stream を選ぶ。どちらも、同じ q の具体的な型と
	// 組みになって並ぶため、先には来ない
	for _, m := range compatible {
		if m.concrete() {
			return m.contentType(), true
		}
	}
	return "", false
}

// parseAccept は、Spring の MediaType.parseMediaTypes と同じく、Accept の行を引用符の外の , で分けて読む。
// 型が無いときは */* とする。
func parseAccept(lines []string) ([]mediaType, bool) {
	var types []mediaType
	for _, line := range lines {
		for _, s := range splitAccept(line) {
			if javaTrim(s) == "" {
				continue
			}
			m, ok := parseMediaType(s)
			if !ok {
				return nil, false
			}
			types = append(types, m)
		}
	}
	if len(types) > 50 {
		return nil, false
	}
	if len(types) == 0 {
		return []mediaType{{typ: "*", sub: "*"}}, true
	}
	return types, true
}

// splitAccept は、Spring の MimeTypeUtils.tokenize と同じく、引用符の外の , で分ける。\ の次の文字は読み飛ばす。
func splitAccept(s string) []string {
	var out []string
	quoted, start := false, 0
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '"':
			quoted = !quoted
		case ',':
			if !quoted {
				out = append(out, s[start:i])
				start = i + 1
			}
		case '\\':
			i++
		}
	}
	return append(out, s[start:])
}

// parseMediaType は、Spring の MimeTypeUtils.parseMimeType と同じく1つの型を読む。
func parseMediaType(s string) (mediaType, bool) {
	full, _, hasParams := strings.Cut(s, ";")
	full = javaTrim(full)
	if full == "*" {
		full = "*/*"
	}
	typ, sub, _ := strings.Cut(full, "/")
	if !isToken(typ) || !isToken(sub) || (typ == "*" && sub != "*") {
		return mediaType{}, false
	}
	m := mediaType{typ: strings.ToLower(typ), sub: strings.ToLower(sub)}
	if !hasParams {
		return m, true
	}
	// Spring は、引数を、名前の大文字と小文字を区別して後の値で上書きしてから、区別せずに後の名前で置き換える
	var raw []mediaParam
	for i := strings.IndexByte(s, ';'); i < len(s); {
		j, quoted := i+1, false
		for ; j < len(s) && (s[j] != ';' || quoted); j++ {
			if s[j] == '"' {
				quoted = !quoted
			}
		}
		if name, value, ok := strings.Cut(javaTrim(s[i+1:j]), "="); ok {
			raw = putParam(raw, javaTrim(name), javaTrim(value), false)
		}
		i = j
	}
	for _, p := range raw {
		if !validParam(p) {
			return mediaType{}, false
		}
		m.params = putParam(m.params, p.name, p.value, true)
	}
	return m, true
}

// putParam は、引数を足す。同じ名前の引数があれば、fold が false なら値を置き換え、true なら大文字と小文字を区別せずに
// 古い引数を除いて最後に足す。
func putParam(params []mediaParam, name, value string, fold bool) []mediaParam {
	for i, p := range params {
		if p.name == name && !fold {
			params[i].value = value
			return params
		}
		if fold && strings.EqualFold(p.name, name) {
			params = append(params[:i:i], params[i+1:]...)
			break
		}
	}
	return append(params, mediaParam{name: name, value: value})
}

// validParam は、Spring の MediaType.checkParameters と同じく引数を確かめる。q は 0 から 1 の数、charset は Java の
// 文字コードの名前の形、ほかの値は区切りの無い文字の並びか引用符で囲んだ文字の並びでなければならない。空の値は、
// この3つのどれにも当たらないので誤りになる。
func validParam(p mediaParam) bool {
	if !isToken(p.name) {
		return false
	}
	switch {
	case strings.EqualFold(p.name, "q"):
		_, ok := parseQuality(p.value)
		return ok
	case strings.EqualFold(p.name, "charset"):
		return isCharsetName(unquote(p.value))
	default:
		return isQuoted(p.value) || isToken(p.value)
	}
}

// parseQuality は、Java の Double.parseDouble と同じく q の値を読む。末尾の d と f は読み飛ばす。
func parseQuality(v string) (float64, bool) {
	s := javaTrim(unquote(v))
	if n := len(s); n > 0 && strings.IndexByte("dDfF", s[n-1]) >= 0 {
		s = s[:n-1]
	}
	q, err := strconv.ParseFloat(s, 64)
	return q, err == nil && q >= 0 && q <= 1
}

// param は、名前の大文字と小文字を区別せずに引数の値を返す。
func (m mediaType) param(name string) (string, bool) {
	for _, p := range m.params {
		if strings.EqualFold(p.name, name) {
			return p.value, true
		}
	}
	return "", false
}

// quality は、q の値を返す。q が無ければ 1 である。
func (m mediaType) quality() float64 {
	v, ok := m.param("q")
	if !ok {
		return 1
	}
	q, _ := parseQuality(v)
	return q
}

func (m mediaType) wildcardType() bool    { return m.typ == "*" }
func (m mediaType) wildcardSubtype() bool { return m.sub == "*" || strings.HasPrefix(m.sub, "*+") }
func (m mediaType) concrete() bool        { return !m.wildcardType() && !m.wildcardSubtype() }

// suffix は、下位の型の最後の + のあとを返す。+ が無ければ ok が false になる。
func (m mediaType) suffix() (string, bool) {
	i := strings.LastIndexByte(m.sub, '+')
	if i < 0 {
		return "", false
	}
	return m.sub[i+1:], true
}

// compatibleWith は、Spring の MimeType.isCompatibleWith と同じく、2つの型が重なるかを返す。
func (m mediaType) compatibleWith(o mediaType) bool {
	if m.wildcardType() || o.wildcardType() {
		return true
	}
	if m.typ != o.typ {
		return false
	}
	if m.sub == o.sub {
		return true
	}
	if !m.wildcardSubtype() && !o.wildcardSubtype() {
		return false
	}
	if m.sub == "*" || o.sub == "*" {
		return true
	}
	ms, mok := m.suffix()
	os, ook := o.suffix()
	if m.wildcardSubtype() {
		return ms == o.sub || (ook && ms == os)
	}
	return m.sub == os || (mok && os == ms)
}

// lessSpecific は、Spring の MediaType.isLessSpecific と同じく、m が o より後に並ぶかを返す。q の値の小さい型、
// * の型、* の下位の型、同じ型で引数の少ない型を後に並べる。
func lessSpecific(m, o mediaType) bool {
	if mq, oq := m.quality(), o.quality(); mq != oq {
		return mq < oq
	}
	if m.wildcardType() != o.wildcardType() {
		return m.wildcardType()
	}
	if m.wildcardSubtype() != o.wildcardSubtype() {
		return m.wildcardSubtype()
	}
	return m.typ == o.typ && m.sub == o.sub && len(m.params) < len(o.params)
}

// sortBySpecificity は、Spring の MimeTypeUtils.sortBySpecificity と同じく、隣どうしを入れ替えて並べる。
func sortBySpecificity(ms []mediaType) {
	for i := range ms {
		for j := 1; j < len(ms)-i; j++ {
			if lessSpecific(ms[j-1], ms[j]) {
				ms[j-1], ms[j] = ms[j], ms[j-1]
			}
		}
	}
}

// mostSpecific は、Spring の getMostSpecificMediaType と同じく、Accept の型 a の q を書けるの型 p に写し、具体的な方を返す。
func mostSpecific(a, p mediaType) mediaType {
	if q, ok := a.param("q"); ok {
		p.params = []mediaParam{{name: "q", value: q}}
	}
	if lessSpecific(a, p) {
		return p
	}
	return a
}

// contentType は、選んだ型を Content-Type の文字列にする。Spring は、名前が小文字の q を除き、JSON の型でなく charset が
// 無ければ charset=UTF-8 を足す。Tomcat は、charset があれば、ほかの引数の名前を小文字にし、charset を最後に書き直す。
func (m mediaType) contentType() string {
	var params []mediaParam
	for _, p := range m.params {
		if p.name != "q" {
			params = append(params, p)
		}
	}
	charset, ok := mediaType{params: params}.param("charset")
	var b strings.Builder
	b.WriteString(m.typ + "/" + m.sub)
	if !ok && m.json() {
		for _, p := range params {
			b.WriteString(";" + p.name + "=" + p.value)
		}
		return b.String()
	}
	if !ok {
		charset = "UTF-8"
	}
	for _, p := range params {
		if !strings.EqualFold(p.name, "charset") {
			b.WriteString(";" + strings.ToLower(p.name) + "=" + p.value)
		}
	}
	b.WriteString(";charset=" + unquote(charset))
	return b.String()
}

// json は、Spring の StringHttpMessageConverter が charset を足さない、application/json か +json の型かを返す。
func (m mediaType) json() bool {
	return m.compatibleWith(mediaType{typ: "application", sub: "json"}) ||
		m.compatibleWith(mediaType{typ: "application", sub: "*+json"})
}

// javaTrim は、Java の String.trim と同じく、前後の空白と制御の文字を除く。
func javaTrim(s string) string {
	return strings.TrimFunc(s, func(r rune) bool { return r <= ' ' })
}

// isToken は、s が、HTTP の区切りの文字と空白と制御の文字を含まない、空でない ASCII の文字の並びかを返す。
func isToken(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if c := s[i]; c <= ' ' || c >= 0x7f || strings.IndexByte(`()<>@,;:\"/[]?={}`, c) >= 0 {
			return false
		}
	}
	return true
}

// isQuoted は、s が、Spring と同じく " か ' で囲まれているかを返す。
func isQuoted(s string) bool {
	return len(s) >= 2 && (s[0] == '"' && s[len(s)-1] == '"' || s[0] == '\'' && s[len(s)-1] == '\'')
}

// unquote は、囲みの " か ' を除く。
func unquote(s string) string {
	if isQuoted(s) {
		return s[1 : len(s)-1]
	}
	return s
}

// isCharsetName は、s が Java の文字コードの名前の形かを返す。英字か数字で始まり、英字と数字と - + : _ . だけを含む。
func isCharsetName(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		alnum := 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || '0' <= c && c <= '9'
		if !alnum && (i == 0 || strings.IndexByte("-+:_.", c) < 0) {
			return false
		}
	}
	return true
}
