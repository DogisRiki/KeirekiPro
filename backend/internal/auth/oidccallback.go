package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"mime"
	"net/http"
	"strconv"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// このファイルは、Java 版の HandleOidcCallbackUseCase と OidcLoginUseCase と、OidcClient の exchangeToken と
// fetchUserInfo と、GoogleOidcProvider と GithubOidcProvider の利用者の情報の読み方と、OidcCallbackController の
// 移る先の作り方を写す。

const (
	// githubUserEmailsURL は、Java 版の GithubOidcProvider が主のメールアドレスを読む URL である。
	githubUserEmailsURL = "https://api.github.com/user/emails"
	// githubAPIVersion は、Java 版の GithubOidcProvider が付ける X-GitHub-Api-Version の値である。
	githubAPIVersion = "2022-11-28"
	// oidcResponseLimit は、Google と GitHub の応答の本文を読む上限のバイト数である。Java 版には上限が無いが、
	// 応答はどれも数 KB なので、1 MiB を超える応答は読み切らずに失敗にする。
	oidcResponseLimit = 1 << 20
)

var (
	// errOIDCUserInfo は、Google か GitHub から利用者の情報を読めなかったことを表す。
	errOIDCUserInfo = errors.New("auth: Google か GitHub から利用者の情報を読めない")
	// errOIDCUnverified は、確認の済んでいない同じメールアドレスのアカウントがあり、つながなかったことを表す。
	errOIDCUnverified = errors.New("auth: 確認の済んでいないアカウントには連携をつながない")
)

// OIDCCallbackResult は、Google か GitHub から戻ったあとの処理の結果である。
type OIDCCallbackResult struct {
	// Location は、画面の移る先の URL である。
	Location string
	// Session は、ログインが終わったときだけ値が入る。
	Session SessionTokens
	// Cause は、失敗したときの元の誤りである。認証の受け口がログに書く。
	Cause error
}

// oidcUserInfo は、Java 版の OidcUserInfo のうち、ログインに使う項目である。nil は Java 版の null にあたる。
type oidcUserInfo struct {
	providerUserID *string
	email          *string
	username       *string
}

// HandleOIDCCallback は、Java 版の HandleOidcCallbackUseCase と OidcCallbackController と同じく、Google か GitHub から
// 戻ったあとに、コードを交換し、利用者の情報を読み、アカウントを決めてログインを終える。state があれば、結果によらず
// state の3つの記録を消す。消せなければ、結果を「認証に失敗しました。…」の失敗にする。
//
// ログインを終えれば、画面の /resume/list を移る先にし、ログインの状態の値を返す。失敗すれば、画面の /login に、
// error の項目として文言を Java の URLEncoder.encode の規則でエスケープして付けた URL を移る先にする。確認の済んでいない
// アカウントのときだけ、文言の代わりに unverified_email を付ける。
func (s *Service) HandleOIDCCallback(ctx context.Context, code, state, errParam *string, redirectURI string) OIDCCallbackResult {
	id, roles, cause := s.oidcCallback(ctx, code, state, errParam, redirectURI)
	if state != nil {
		if err := s.removeOIDCSession(ctx, *state); err != nil {
			if cause != nil {
				err = fmt.Errorf("%w(先の誤り: %v)", err, cause)
			}
			cause = err
		}
	}
	if cause != nil {
		return s.oidcFailure(cause)
	}
	tokens, err := s.issueSession(ctx, id, roles)
	if err != nil {
		return s.oidcFailure(err)
	}
	return OIDCCallbackResult{Location: s.deps.App.FrontendBaseURL + "/resume/list", Session: tokens}
}

// oidcCallback は、Java 版の HandleOidcCallbackUseCase の try の中にあたる。ログインした利用者の ID と役割を返す。
func (s *Service) oidcCallback(ctx context.Context, code, state, errParam *string, redirectURI string) (uuid.UUID, []string, error) {
	if errParam != nil {
		return uuid.UUID{}, nil, fmt.Errorf("auth: Google か GitHub がログインを断った(error=%q)", *errParam)
	}
	if code == nil || state == nil {
		return uuid.UUID{}, nil, errors.New("auth: code か state が無い")
	}
	provider, verifier, err := s.findOIDCSession(ctx, *state)
	if err != nil {
		return uuid.UUID{}, nil, err
	}
	p, ok := s.oidcProvider(provider)
	if !ok {
		return uuid.UUID{}, nil, fmt.Errorf("auth: 対象の外の provider %q の記録", provider)
	}
	name := strings.ToLower(provider)
	accessToken, err := s.exchangeOIDCCode(ctx, p, *code, verifier, redirectURI)
	if err != nil {
		return uuid.UUID{}, nil, err
	}
	info, err := s.fetchOIDCUserInfo(ctx, name, p, accessToken)
	if err != nil {
		return uuid.UUID{}, nil, fmt.Errorf("%w: %w", errOIDCUserInfo, err)
	}
	return s.oidcLogin(ctx, name, info)
}

// oidcFailure は、Java 版の OidcCallbackController と同じく、失敗の元の誤り cause に当たる移る先を作る。
func (s *Service) oidcFailure(cause error) OIDCCallbackResult {
	location := s.deps.App.FrontendBaseURL + "/login?error="
	switch {
	case errors.Is(cause, errOIDCUnverified):
		location += "unverified_email"
	case errors.Is(cause, errOIDCUserInfo):
		location += javaURLEncode(MessageOIDCUserInfoFailed)
	default:
		location += javaURLEncode(MessageOIDCFailed)
	}
	return OIDCCallbackResult{Location: location, Cause: cause}
}

// findOIDCSession は、Java 版の RedisOidcAuthorizationSessionStore の find と同じく、oidc:state:<state> のキーが
// あるかを確かめてから、provider と code_verifier の記録を読む。キーが無いとき、どちらかの記録が JSON の文字列で
// ないとき(無いときと null のときを含む)は、誤りを返す。
func (s *Service) findOIDCSession(ctx context.Context, state string) (provider, verifier string, err error) {
	n, err := s.deps.Redis.Exists(ctx, oidcStateKeyPrefix+state).Result()
	if err != nil {
		return "", "", fmt.Errorf("auth: Redis の値を読めない: %w", err)
	}
	if n == 0 {
		return "", "", errors.New("auth: state の記録が無いか期限が切れた")
	}
	provider, ok, err := s.getJSONString(ctx, oidcProviderKeyPrefix+state)
	if err != nil {
		return "", "", err
	}
	verifier, ok2, err := s.getJSONString(ctx, oidcCodeVerifierKeyPrefix+state)
	if err != nil {
		return "", "", err
	}
	if !ok || !ok2 {
		return "", "", errors.New("auth: provider か code_verifier の記録が無い")
	}
	return provider, verifier, nil
}

// removeOIDCSession は、Java 版の RedisOidcAuthorizationSessionStore の remove と同じく、state、provider、
// code_verifier の記録を、この順に1つずつ消す。
func (s *Service) removeOIDCSession(ctx context.Context, state string) error {
	for _, key := range []string{oidcStateKeyPrefix + state, oidcProviderKeyPrefix + state, oidcCodeVerifierKeyPrefix + state} {
		if err := s.deleteKey(ctx, key); err != nil {
			return err
		}
	}
	return nil
}

// exchangeOIDCCode は、Java 版の OidcClient の exchangeToken と同じく、コードをアクセストークンに換える。
// 応答の状態の番号によらず本文を読む。JSON の種類でない応答、空か null かオブジェクトでない本文、文字列の項目か
// expires_in を Java 版の OidcTokenResponse の型に読めない本文、error の項目が空でない本文は、誤りにする。
// アクセストークンが無いか null なら、Java 版の setBearerAuth(null) と同じく "null" を返す。expires_in の値は使わない。
func (s *Service) exchangeOIDCCode(ctx context.Context, p config.Provider, code, verifier, redirectURI string) (string, error) {
	form := javaForm([]queryParam{
		{"grant_type", "authorization_code"},
		{"code", code},
		{"redirect_uri", redirectURI},
		{"code_verifier", verifier},
		{"client_id", p.ClientID},
		{"client_secret", p.ClientSecret},
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.TokenURL, strings.NewReader(form))
	if err != nil {
		return "", fmt.Errorf("auth: コードの交換の要求を作れない: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	body, err := s.oidcDo(req, true)
	if err != nil {
		return "", fmt.Errorf("auth: コードを交換できない: %w", err)
	}
	m, ok := decodeJSONObject(body)
	if !ok {
		return "", errors.New("auth: コードの交換の応答が JSON のオブジェクトでない")
	}
	fields := map[string]*string{}
	for _, key := range []string{"access_token", "token_type", "id_token", "refresh_token", "scope", "error", "error_description"} {
		v, ok := jacksonStringField(m, key)
		if !ok {
			return "", fmt.Errorf("auth: コードの交換の応答の %s を文字列として読めない", key)
		}
		fields[key] = v
	}
	if raw, present := m["expires_in"]; present {
		if _, ok := parseJacksonInt(raw); !ok {
			return "", errors.New("auth: コードの交換の応答の expires_in を整数として読めない")
		}
	}
	if e := fields["error"]; e != nil && *e != "" {
		return "", fmt.Errorf("auth: コードの交換の応答に error がある(%q)", *e)
	}
	if v := fields["access_token"]; v != nil {
		return *v, nil
	}
	return "null", nil
}

// fetchOIDCUserInfo は、Java 版の OidcClient の fetchUserInfo と、GoogleOidcProvider か GithubOidcProvider の
// convertUserInfo と同じく、利用者の情報を読む。
func (s *Service) fetchOIDCUserInfo(ctx context.Context, provider string, p config.Provider, accessToken string) (oidcUserInfo, error) {
	req, err := s.oidcGet(ctx, p.UserInfoURL, provider, accessToken)
	if err != nil {
		return oidcUserInfo{}, err
	}
	body, err := s.oidcDo(req, true)
	if err != nil {
		return oidcUserInfo{}, err
	}
	m, ok := decodeJSONObject(body)
	if !ok {
		return oidcUserInfo{}, errors.New("auth: 利用者の情報が JSON のオブジェクトでない")
	}
	if provider == "github" {
		return s.githubUserInfo(ctx, m, accessToken)
	}
	return parseGoogleUserInfo(m)
}

// parseGoogleUserInfo は、Java 版の GoogleOidcProvider の convertUserInfo と同じく、sub、email、name を読む。
// email_verified が真でなければ、メールアドレスを使わない。
func parseGoogleUserInfo(m map[string]json.RawMessage) (oidcUserInfo, error) {
	email, ok := strictStringField(m, "email")
	if !ok {
		return oidcUserInfo{}, errors.New("auth: Google の email が文字列でない")
	}
	verified, ok := strictBoolField(m, "email_verified")
	if !ok {
		return oidcUserInfo{}, errors.New("auth: Google の email_verified が真偽でない")
	}
	if !verified {
		email = nil
	}
	sub, ok := strictStringField(m, "sub")
	if !ok {
		return oidcUserInfo{}, errors.New("auth: Google の sub が文字列でない")
	}
	name, ok := strictStringField(m, "name")
	if !ok {
		return oidcUserInfo{}, errors.New("auth: Google の name が文字列でない")
	}
	return oidcUserInfo{providerUserID: sub, email: email, username: name}, nil
}

// githubUserInfo は、Java 版の GithubOidcProvider の convertUserInfo と同じく、id を String.valueOf で文字にし、
// login を名前にし、メールアドレスの一覧から主で確認済みのメールアドレスを読む。id が小数、指数の形の数、
// オブジェクト、並びのときは、Java 版と違い、誤りにする。
func (s *Service) githubUserInfo(ctx context.Context, m map[string]json.RawMessage, accessToken string) (oidcUserInfo, error) {
	id, ok := javaStringValueOf(m["id"])
	if !ok {
		return oidcUserInfo{}, errors.New("auth: GitHub の id を文字にできない")
	}
	login, ok := strictStringField(m, "login")
	if !ok {
		return oidcUserInfo{}, errors.New("auth: GitHub の login が文字列でない")
	}
	return oidcUserInfo{providerUserID: &id, email: s.githubPrimaryEmail(ctx, accessToken), username: login}, nil
}

// githubPrimaryEmail は、Java 版の GithubOidcProvider の fetchPrimaryEmail と同じく、メールアドレスの一覧を先頭から見て、
// primary と verified の両方が真の最初の要素のメールアドレスを返す。一覧を読めないとき、当たる前に null の要素が
// あるとき、当たった要素の email が文字列でないとき、当たる要素が無いときは、nil を返す。
func (s *Service) githubPrimaryEmail(ctx context.Context, accessToken string) *string {
	req, err := s.oidcGet(ctx, githubUserEmailsURL, "github", accessToken)
	if err != nil {
		return nil
	}
	body, err := s.oidcDo(req, false)
	if err != nil {
		return nil
	}
	elems, ok := decodeJSONArrayOfObjects(body)
	if !ok {
		return nil
	}
	for _, e := range elems {
		if e == nil {
			return nil
		}
		if string(bytes.TrimSpace(e["primary"])) != "true" || string(bytes.TrimSpace(e["verified"])) != "true" {
			continue
		}
		var email string
		if json.Unmarshal(e["email"], &email) != nil || isJSONNull(e["email"]) {
			return nil
		}
		return &email
	}
	return nil
}

// oidcGet は、アクセストークンを付けた GET の要求を作る。GitHub なら、Java 版の GithubOidcProvider の
// configureHeaders と同じヘッダを足す。
func (s *Service) oidcGet(ctx context.Context, target, provider, accessToken string) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return nil, fmt.Errorf("auth: 利用者の情報の要求を作れない: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	if provider == "github" {
		req.Header.Set("Accept", "application/vnd.github+json")
		req.Header.Set("X-GitHub-Api-Version", githubAPIVersion)
	} else {
		req.Header.Set("Accept", "application/json, application/*+json")
	}
	return req, nil
}

// oidcDo は、req を送り、応答の本文を返す。Java 版の RestClient は、どの状態の番号の応答でも誤りにせずに本文を
// 読むよう設定してあるので、状態の番号は確かめない。jsonOnly が真なら、Java 版の Jackson の変換器と同じく、
// Content-Type が application/json か application/*+json でない応答を誤りにする。本文が oidcResponseLimit を
// 超えれば誤りにする。
func (s *Service) oidcDo(req *http.Request, jsonOnly bool) ([]byte, error) {
	resp, err := s.deps.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	if jsonOnly && !jsonMediaType(resp.Header.Get("Content-Type")) {
		return nil, fmt.Errorf("auth: 応答の Content-Type %q が JSON の種類でない", resp.Header.Get("Content-Type"))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, oidcResponseLimit+1))
	if err != nil {
		return nil, fmt.Errorf("auth: 応答の本文を読めない: %w", err)
	}
	if len(body) > oidcResponseLimit {
		return nil, errors.New("auth: 応答の本文が大きすぎる")
	}
	return body, nil
}

// jsonMediaType は、Content-Type が application/json か application/*+json かを返す。
func jsonMediaType(contentType string) bool {
	mediaType, _, err := mime.ParseMediaType(contentType)
	if err != nil {
		return false
	}
	return mediaType == "application/json" ||
		(strings.HasPrefix(mediaType, "application/") && strings.HasSuffix(mediaType, "+json"))
}

// decodeJSONObject は、本文の先頭の JSON の値がオブジェクトなら、項目の名前ごとの値を返す。Java 版の Jackson は
// FAIL_ON_TRAILING_TOKENS を切ってある(spring.jackson.use-jackson2-defaults)ので、先頭の値のあとは読まない。
func decodeJSONObject(body []byte) (map[string]json.RawMessage, bool) {
	dec := json.NewDecoder(bytes.NewReader(body))
	var m map[string]json.RawMessage
	if dec.Decode(&m) != nil || m == nil {
		return nil, false
	}
	return m, true
}

// decodeJSONArrayOfObjects は、本文の先頭の JSON の値が並びで、要素がどれもオブジェクトか null なら、要素を返す。
// null の要素は nil にする。decodeJSONObject と同じく、先頭の値のあとは読まない。
func decodeJSONArrayOfObjects(body []byte) ([]map[string]json.RawMessage, bool) {
	dec := json.NewDecoder(bytes.NewReader(body))
	var raws []json.RawMessage
	if dec.Decode(&raws) != nil || raws == nil {
		return nil, false
	}
	elems := make([]map[string]json.RawMessage, len(raws))
	for i, raw := range raws {
		if isJSONNull(raw) {
			continue
		}
		if json.Unmarshal(raw, &elems[i]) != nil {
			return nil, false
		}
	}
	return elems, true
}

// isJSONNull は、raw が JSON の null かを返す。
func isJSONNull(raw json.RawMessage) bool {
	return string(bytes.TrimSpace(raw)) == "null"
}

// jacksonStringField は、項目 key を、Jackson が Java の String の項目に読む規則で読む。項目が無いか null なら
// nil を返す。オブジェクトと並びは読めないとする。
func jacksonStringField(m map[string]json.RawMessage, key string) (*string, bool) {
	raw, ok := m[key]
	if !ok || isJSONNull(raw) {
		return nil, true
	}
	v, ok := parseJacksonString(raw)
	if !ok {
		return nil, false
	}
	return &v, true
}

// strictStringField は、項目 key を、Java の (String) の型の変換と同じく、JSON の文字列としてだけ読む。
// 項目が無いか null なら nil を返す。
func strictStringField(m map[string]json.RawMessage, key string) (*string, bool) {
	raw, ok := m[key]
	if !ok || isJSONNull(raw) {
		return nil, true
	}
	var v string
	if json.Unmarshal(raw, &v) != nil {
		return nil, false
	}
	return &v, true
}

// strictBoolField は、項目 key を、Java の (Boolean) の型の変換と同じく、JSON の真偽としてだけ読み、真かを返す。
// 項目が無いか null なら偽を返す。
func strictBoolField(m map[string]json.RawMessage, key string) (bool, bool) {
	raw, ok := m[key]
	if !ok || isJSONNull(raw) {
		return false, true
	}
	var v bool
	if json.Unmarshal(raw, &v) != nil {
		return false, false
	}
	return v, true
}

// javaStringValueOf は、Jackson が Map に読んだ値に Java の String.valueOf をかけた結果を作る。無いか null なら
// "null" に、文字列はそのまま、真偽は "true" か "false" に、整数は10進の決まった書き方にする。小数、指数の形の数、
// オブジェクト、並びは文字にできないとする。
func javaStringValueOf(raw json.RawMessage) (string, bool) {
	if raw == nil || isJSONNull(raw) {
		return "null", true
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var v any
	if dec.Decode(&v) != nil {
		return "", false
	}
	switch t := v.(type) {
	case string:
		return t, true
	case bool:
		return strconv.FormatBool(t), true
	case json.Number:
		n, ok := new(big.Int).SetString(t.String(), 10)
		if !ok {
			return "", false
		}
		return n.String(), true
	default:
		return "", false
	}
}

// javaForm は、params を渡した順に、Java の URLEncoder.encode でエスケープした「名前=値」を & でつなぐ。
// Spring の FormHttpMessageConverter が書く application/x-www-form-urlencoded の本文と同じである。
func javaForm(params []queryParam) string {
	var b strings.Builder
	for i, p := range params {
		if i > 0 {
			b.WriteByte('&')
		}
		b.WriteString(javaURLEncode(p.name))
		b.WriteByte('=')
		b.WriteString(javaURLEncode(p.value))
	}
	return b.String()
}

// javaURLEncode は、Java の URLEncoder.encode(v, UTF_8) と同じく、英数字と . - * _ を残し、空白を + にし、
// ほかは UTF-8 のバイトごとに大文字の %XX にする。
func javaURLEncode(v string) string {
	const hex = "0123456789ABCDEF"
	var b strings.Builder
	for i := 0; i < len(v); i++ {
		c := v[i]
		switch {
		case 'a' <= c && c <= 'z', 'A' <= c && c <= 'Z', '0' <= c && c <= '9', c == '.', c == '-', c == '*', c == '_':
			b.WriteByte(c)
		case c == ' ':
			b.WriteByte('+')
		default:
			b.WriteByte('%')
			b.WriteByte(hex[c>>4])
			b.WriteByte(hex[c&0x0f])
		}
	}
	return b.String()
}

// oidcLogin は、Java 版の OidcLoginUseCase と同じく、1つのトランザクションでアカウントを決め、ログインする利用者の
// ID と役割を返す。Google か GitHub の利用者の ID でつないだアカウントがあればそれを、無ければ同じメールアドレスの
// アカウントを使う。同じメールアドレスのアカウントの確認が済んでいなければ errOIDCUnverified を返す。どちらも
// 無ければ、新しいアカウントを作り、メールアドレスがあれば登録の完了のメールを送る。
func (s *Service) oidcLogin(ctx context.Context, provider string, info oidcUserInfo) (uuid.UUID, []string, error) {
	var id uuid.UUID
	var roles []string
	err := s.inTransaction(ctx, func(q *sqlcgen.Queries) error {
		now := s.javaNow()
		u, found, err := s.findOIDCAccount(ctx, q, provider, info, now)
		if err != nil {
			return err
		}
		if !found {
			u, err = s.createOIDCUser(ctx, q, provider, info, now)
			if err != nil {
				return err
			}
		} else {
			if err := s.linkOIDCProvider(&u, provider, info, now); err != nil {
				return err
			}
			if err := saveUser(ctx, q, u); err != nil {
				return err
			}
		}
		id, roles = u.Row.ID.Bytes, u.Roles
		return nil
	})
	if err != nil {
		return uuid.UUID{}, nil, err
	}
	return id, roles, nil
}

// findOIDCAccount は、Java 版の OidcLoginUseCase と同じく、つなぐアカウントを探す。Google か GitHub の利用者の ID で
// 見つけたアカウントには、返ってきたメールアドレスを当てはめる。
func (s *Service) findOIDCAccount(ctx context.Context, q *sqlcgen.Queries, provider string, info oidcUserInfo, now pgtype.Timestamp) (StoredUser, bool, error) {
	if info.providerUserID != nil {
		rows, err := q.GetUserRowsByProvider(ctx, sqlcgen.GetUserRowsByProviderParams{ProviderName: provider, ProviderUserID: *info.providerUserID})
		if err != nil {
			return StoredUser{}, false, fmt.Errorf("auth: 連携の利用者を読めない: %w", err)
		}
		var ids []uuid.UUID
		for _, r := range rows {
			if id := uuid.UUID(r.UID.Bytes); r.UID.Valid && !containsUUID(ids, id) {
				ids = append(ids, id)
			}
		}
		if len(ids) > 1 {
			return StoredUser{}, false, errors.New("auth: 同じ連携の利用者が2人以上いる")
		}
		if len(ids) == 1 {
			u, err := loadStoredUserOr(ctx, q, ids[0], errors.New("auth: 連携の利用者が居ない"))
			if err != nil {
				return StoredUser{}, false, err
			}
			if err := applyReturnedEmail(ctx, q, &u, info.email, now); err != nil {
				return StoredUser{}, false, err
			}
			return u, true, nil
		}
	}
	if info.email == nil {
		return StoredUser{}, false, nil
	}
	rows, err := q.GetUserRowsByEmail(ctx, pgtype.Text{String: *info.email, Valid: true})
	if err != nil {
		return StoredUser{}, false, fmt.Errorf("auth: 利用者を読めない: %w", err)
	}
	acc, ok, err := accountFromRows(rows)
	if err != nil || !ok {
		return StoredUser{}, false, err
	}
	u, err := loadStoredUserOr(ctx, q, acc.ID, errors.New("auth: 同じメールアドレスの利用者が居ない"))
	if err != nil {
		return StoredUser{}, false, err
	}
	if !u.Row.Email.Valid || !u.Row.EmailVerifiedAt.Valid {
		return StoredUser{}, false, errOIDCUnverified
	}
	return u, true, nil
}

// containsUUID は、ids に id があるかを返す。
func containsUUID(ids []uuid.UUID, id uuid.UUID) bool {
	for _, v := range ids {
		if v == id {
			return true
		}
	}
	return false
}

// applyReturnedEmail は、Java 版の OidcLoginUseCase の applyReturnedEmail と同じく、Google か GitHub が返した
// メールアドレスを、つないだアカウントに当てはめる。メールアドレスがあるアカウントは、同じなら確認済みにする。
// 無いアカウントは、設定待ちのメールアドレスと同じで、ほかの利用者が使っていなければ、メールアドレスに移す。
func applyReturnedEmail(ctx context.Context, q *sqlcgen.Queries, u *StoredUser, email *string, now pgtype.Timestamp) error {
	if email == nil {
		return nil
	}
	if u.Row.Email.Valid {
		if u.Row.Email.String == *email && !u.Row.EmailVerifiedAt.Valid {
			u.Row.UpdatedAt, u.Row.EmailVerifiedAt = now, now
		}
		return nil
	}
	if !u.Row.PendingEmail.Valid || u.Row.PendingEmail.String != *email {
		return nil
	}
	rows, err := q.GetUserRowsByEmail(ctx, pgtype.Text{String: *email, Valid: true})
	if err != nil {
		return fmt.Errorf("auth: 利用者を読めない: %w", err)
	}
	if _, used, err := accountFromRows(rows); err != nil || used {
		return err
	}
	u.Row.Email, u.Row.PendingEmail = u.Row.PendingEmail, pgtype.Text{}
	u.Row.UpdatedAt, u.Row.EmailVerifiedAt = now, now
	return nil
}

// linkOIDCProvider は、Java 版の User.addAuthProvider と同じく、名前の大文字と小文字を区別せずに同じ provider の
// 連携が無ければ、連携を足して更新日時を今の時刻にする。
func (s *Service) linkOIDCProvider(u *StoredUser, provider string, info oidcUserInfo, now pgtype.Timestamp) error {
	for _, p := range u.Providers {
		if strings.ToLower(p.ProviderName) == provider {
			return nil
		}
	}
	if info.providerUserID == nil {
		return errors.New("auth: Google か GitHub の利用者の ID が無い")
	}
	pid, err := uuid.NewRandomFromReader(readFunc(s.deps.Random))
	if err != nil {
		return fmt.Errorf("auth: 乱数を読めない: %w", err)
	}
	u.Providers = append(u.Providers, sqlcgen.InsertUserAuthProviderParams{
		ID:             pgtype.UUID{Bytes: pid, Valid: true},
		UserID:         u.Row.ID,
		ProviderName:   provider,
		ProviderUserID: *info.providerUserID,
		CreatedAt:      now,
		UpdatedAt:      now,
	})
	u.Row.UpdatedAt = now
	return nil
}

// createOIDCUser は、Java 版の OidcLoginUseCase と同じく、連携の ID、利用者の ID の順に ID を作り、役割 USER の
// 新しいアカウントと世代の番号の行を足す。メールアドレスがあれば確認済みにし、登録の完了のメールを送る。
func (s *Service) createOIDCUser(ctx context.Context, q *sqlcgen.Queries, provider string, info oidcUserInfo, now pgtype.Timestamp) (StoredUser, error) {
	pid, err := uuid.NewRandomFromReader(readFunc(s.deps.Random))
	if err != nil {
		return StoredUser{}, fmt.Errorf("auth: 乱数を読めない: %w", err)
	}
	uid, err := uuid.NewRandomFromReader(readFunc(s.deps.Random))
	if err != nil {
		return StoredUser{}, fmt.Errorf("auth: 乱数を読めない: %w", err)
	}
	if info.providerUserID == nil || !notBlank(*info.providerUserID) {
		return StoredUser{}, errors.New("auth: Google か GitHub の利用者の ID が無い")
	}
	if info.email != nil && len(emailCreateErrors(*info.email)) > 0 {
		return StoredUser{}, errors.New("auth: Google か GitHub のメールアドレスの形が正しくない")
	}
	id := pgtype.UUID{Bytes: uid, Valid: true}
	u := StoredUser{
		Row: sqlcgen.UpsertUserParams{
			ID:        id,
			Email:     optionalText(info.email),
			Username:  optionalText(info.username),
			CreatedAt: now,
			UpdatedAt: now,
		},
		Providers: []sqlcgen.InsertUserAuthProviderParams{{
			ID:             pgtype.UUID{Bytes: pid, Valid: true},
			UserID:         id,
			ProviderName:   provider,
			ProviderUserID: *info.providerUserID,
			CreatedAt:      now,
			UpdatedAt:      now,
		}},
		Roles: []string{"USER"},
	}
	if info.email != nil {
		u.Row.EmailVerifiedAt = now
	}
	if err := saveUser(ctx, q, u); err != nil {
		return StoredUser{}, err
	}
	if err := q.InsertTokenVersion(ctx, sqlcgen.InsertTokenVersionParams{UserID: id, UpdatedAt: now}); err != nil {
		return StoredUser{}, fmt.Errorf("auth: 世代の番号の行を足せない: %w", err)
	}
	if info.email == nil {
		return u, nil
	}
	// Java 版の FreeMarker は、null の名前を差し込めずに例外にする。
	if info.username == nil {
		return StoredUser{}, errors.New("auth: 名前の無い利用者には登録の完了のメールを作れない")
	}
	if err := s.sendMail(ctx, *info.email, userRegisteredMail(s.deps.App, *info.username)); err != nil {
		return StoredUser{}, err
	}
	return u, nil
}

// optionalText は、p が nil なら NULL の、そうでなければ空の文字列も含めて p の文字列の列の値を作る。
func optionalText(p *string) pgtype.Text {
	if p == nil {
		return pgtype.Text{}
	}
	return pgtype.Text{String: *p, Valid: true}
}
