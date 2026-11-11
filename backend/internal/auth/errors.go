package auth

// Java 版の AppExceptionHandler と SecurityConfig と、認証のユースケースが返す文言である。
// 文言は Java 版と1文字も違わないようにする。画面は、この文言をそのまま利用者に見せるためである。
const (
	// MessageInvalidInput は、入力の誤りのときの文言である(AppExceptionHandler)。
	MessageInvalidInput = "入力エラーがあります。"
	// MessageUnauthenticated は、ログインを続けるための値が無いか無効なときの文言である(AppExceptionHandler)。
	MessageUnauthenticated = "認証に失敗しました。"
	// MessageEmailNotVerified は、確認の済んでいないメールアドレスのときの文言である(AppExceptionHandler)。
	MessageEmailNotVerified = "メールアドレスの確認が済んでいません。"
	// MessageUnexpected は、想定外の誤りのときの文言である。internal/httpapi/middleware の MessageUnexpected と同じにする。
	MessageUnexpected = "予期せぬエラーが発生しました。"
	// MessageForbidden は、役割の足りない要求を断るときの文言である。internal/httpapi/middleware の MessageForbidden と同じにする。
	MessageForbidden = "アクセス権限がありません。"

	// MessageLoginFailed は、ログインに失敗したときの文言である。アカウントが無いときも
	// パスワードが違うときも、この1つを使う(LoginUseCase、ResendEmailVerificationForLoginUseCase)。
	MessageLoginFailed = "メールアドレスまたはパスワードが正しくありません。"
	// MessageResendRateLimited は、確認のメールを送り直せる間隔の前に送り直しを求められたときの文言である。
	MessageResendRateLimited = "確認のメールは1分に1回まで送れます。少し待ってからもう一度お試しください。"
	// MessageNotResendable は、送り直しに使えないリンクの値で送り直しを求められたときの文言である。
	MessageNotResendable = "このリンクでは確認のメールを送り直せません。"
	// MessageInvalidVerificationLink は、メールアドレスの確認のリンクが無効なときの文言である(EmailVerificationCompletion)。
	MessageInvalidVerificationLink = "確認のリンクが無効です。"
	// MessageInvalidResetLink は、パスワードの再設定の値が無いか期限が切れているときの文言である。
	MessageInvalidResetLink = "リセットリンクが無効または期限切れです。もう一度最初からお試しください。"
	// MessageInvalidAccess は、再設定の値が指す利用者が居ないときの文言である(ResetPasswordUseCase)。
	MessageInvalidAccess = "不正なアクセスです。"
	// MessageInvalidTwoFactorSession は、2段階認証の途中の記録が無いか期限が切れているときの文言である。
	MessageInvalidTwoFactorSession = "認証セッションが無効または期限切れです。もう一度最初からお試しください。"
	// MessageInvalidTwoFactorCode は、2段階認証の確認のコードが違うか期限が切れているときの文言である。
	MessageInvalidTwoFactorCode = "認証コードが無効または期限切れです。もう一度最初からお試しください。"
	// MessageTwoFactorAttemptsExceeded は、確認のコードを誤った回数が上限に達したときの文言である。
	MessageTwoFactorAttemptsExceeded = "試行回数の上限に達しました。もう一度最初からお試しください。"
	// MessageUserInfoUnavailable は、2段階認証の確認のあとに利用者を読めないときの文言である。
	MessageUserInfoUnavailable = "ユーザー情報の取得に失敗しました。"
	// MessageTwoFactorPrerequisiteMissing は、2段階認証が有効なのにメールアドレスかパスワードが無い利用者を
	// 読んだときの文言である(User.reconstruct)。
	MessageTwoFactorPrerequisiteMissing = "メールアドレスとパスワードが未設定の場合は二段階認証を有効にできません。"
	// MessageAdminNeedsTwoFactor は、2段階認証が無効な管理者を読んだときの文言である(User.reconstruct)。
	MessageAdminNeedsTwoFactor = "管理者の場合は二段階認証が必須です。"
	// MessagePendingEmailMissing は、メールアドレスがすでにある利用者の設定待ちのメールアドレスを、
	// 確認のリンクで付け替えようとしたときの文言である(User.promotePendingEmail)。
	MessagePendingEmailMissing = "設定待ちのメールアドレスが無いため確認できません。"

	// MessageOIDCUnverifiedAccount は、確認の済んでいないアカウントに Google か GitHub のログインを
	// 結び付けようとしたときの文言である(UnverifiedEmailAccountUseCaseException)。
	MessageOIDCUnverifiedAccount = "メールアドレスの確認が済んでいないアカウントには外部連携を結び付けられません。"
	// MessageOIDCUserInfoFailed は、Google か GitHub から利用者の情報を読めないときに、
	// 失敗の画面に渡す文言である(OidcCallbackController)。
	MessageOIDCUserInfoFailed = "ユーザー情報の取得に失敗しました。しばらく時間を置いてから再度お試しください。"
	// MessageOIDCFailed は、Google か GitHub のログインがそのほかの理由で失敗したときに、
	// 失敗の画面に渡す文言である(OidcCallbackController)。
	MessageOIDCFailed = "認証に失敗しました。しばらく時間を置いてから再度お試しください。"
)

// EmailKind は、確認の済んでいないメールアドレスの種類である。
// Java 版の EmailNotVerifiedUseCaseException.Kind と同じ名前を、本文の kind に書く。
type EmailKind string

const (
	// KindPendingRegistration は、登録の途中で、メールアドレスの確認がまだのときである。
	KindPendingRegistration EmailKind = "PENDING_REGISTRATION"
	// KindUnverifiedAccountEmail は、アカウントはあるが、メールアドレスの確認がまだのときである。
	KindUnverifiedAccountEmail EmailKind = "UNVERIFIED_ACCOUNT_EMAIL"
)

// Error は、認証の操作が断るときの誤りである。認証の受け口は、errors.As でこの型を取り出し、
// Java 版の AppExceptionHandler と同じ状態の番号と本文を書く。
//
//   - 業務の決まりで断るとき: Status 400、Message、Errors(ふつう空)
//   - 確認の済んでいないメールアドレスのとき: Status 409、Message、空の Errors、Kind
//   - 入力の誤りのとき: Status 400、MessageInvalidInput、項目ごとの文言の Errors
//   - ログインを続けるための値が無いか無効なとき: Status 401、MessageUnauthenticated、空の Errors
//   - 操作の相手の利用者が居ないとき: Status 401、Message、空の Errors、ClearSession が真
type Error struct {
	// Status は、HTTP の状態の番号である。
	Status int
	// Message は、本文の message に書く文言である。
	Message string
	// Errors は、本文の errors に書く、項目ごとの文言の束である。空でも nil にしない。
	Errors map[string][]string
	// Kind は、確認の済んでいないメールアドレスの種類である。409 のときだけ値を持つ。
	Kind EmailKind
	// ClearSession が真のとき、認証の受け口は、Cookie の accessToken と refreshToken を消す。
	ClearSession bool
}

// Error は、本文の message に書く文言を返す。
func (e *Error) Error() string {
	return e.Message
}

// errBusiness は、業務の決まりで断るときの 400 の誤りを作る。Java 版の UseCaseException にあたる。
func errBusiness(message string) *Error {
	return &Error{Status: 400, Message: message, Errors: map[string][]string{}}
}

// errInvalidCredentials は、ログインに失敗したときの誤りを作る。アカウントが無いときも
// パスワードが違うときも、この関数で作り、答えから2つを見分けられないようにする。
func errInvalidCredentials() *Error {
	return errBusiness(MessageLoginFailed)
}

// errEmailNotVerified は、確認の済んでいないメールアドレスのときの 409 の誤りを作る。
// Java 版の EmailNotVerifiedUseCaseException にあたる。
func errEmailNotVerified(kind EmailKind) *Error {
	return &Error{Status: 409, Message: MessageEmailNotVerified, Errors: map[string][]string{}, Kind: kind}
}

// errInvalidInput は、入力の誤りのときの 400 の誤りを作る。Java 版の MethodArgumentNotValidException にあたる。
func errInvalidInput(fields map[string][]string) *Error {
	return &Error{Status: 400, Message: MessageInvalidInput, Errors: fields}
}

// errUnauthenticated は、ログインを続けるための値が無いか無効なときの 401 の誤りを作る。
// Java 版の JWTVerificationException にあたる。
func errUnauthenticated() *Error {
	return &Error{Status: 401, Message: MessageUnauthenticated, Errors: map[string][]string{}}
}

// errCredentialsNotFound は、操作の相手の利用者が居ないときの 401 の誤りを作る。
// Java 版の AuthenticationCredentialsNotFoundException にあたり、Cookie を消させる。
func errCredentialsNotFound(message string) *Error {
	return &Error{Status: 401, Message: message, Errors: map[string][]string{}, ClearSession: true}
}
