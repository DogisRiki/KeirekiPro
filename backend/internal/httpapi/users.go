package httpapi

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strconv"
	"unicode/utf8"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/authctx"
	"github.com/DogisRiki/KeirekiPro/backend/internal/users"
)

// updateUserInfoMaxBody は、名前と画像と2段階認証の設定の変更の要求の本文の大きさの上限(2MB)である。画像の上限の 1MB に
// 名前と2段階認証の設定と区切りを足しても収まる大きさにし、大きな本文で記憶を使い切られないようにする。
const updateUserInfoMaxBody = 2 << 20

// updateUserInfoPath は、名前と画像と2段階認証の設定の変更の経路である。
const updateUserInfoPath = "/api/users/me"

// 本文の項目の名前である。
const (
	formUsername             = "username"
	formProfileImage         = "profileImage"
	formTwoFactorAuthEnabled = "twoFactorAuthEnabled"
)

// errUpdateUserInfoForm は、名前と画像と2段階認証の設定の変更の要求の本文を読めないときの誤りである。
var errUpdateUserInfoForm = errors.New("httpapi: 名前と画像と2段階認証の設定の変更の要求の本文を読めません")

// limitUpdateUserInfoBody は、名前と画像と2段階認証の設定の変更の要求の本文を、updateUserInfoMaxBody までに限る中間処理である。
// 生成したコードは、操作の中間処理より前に本文から multipart の読み手を作るので、経路を選ぶ前に本文を限る。
func limitUpdateUserInfoBody(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPut && r.URL.Path == updateUserInfoPath {
			r.Body = http.MaxBytesReader(w, r.Body, updateUserInfoMaxBody)
		}
		next.ServeHTTP(w, r)
	})
}

// readUpdateUserInfoForm は、本文の部分を順に読み、名前と画像と2段階認証の設定を返す。同じ名前の部分が2つ以上あれば、
// 最初の部分を使う。ファイルの名前の無い画像の部分と、中身が0バイトの画像の部分は、画像が無いものとして扱う。
// 本文を読めないときと、名前が UTF-8 として正しくないときと、2段階認証の設定を真偽として読めないときは、
// errUpdateUserInfoForm を返す。
func readUpdateUserInfoForm(mr *multipart.Reader, userID uuid.UUID) (users.UpdateInput, error) {
	in := users.UpdateInput{UserID: userID}
	for {
		p, err := mr.NextPart()
		// 閉じの区切りまで読んだときだけ、NextPart は io.EOF そのものを返す。区切りの前で本文が切れたときは io.EOF を
		// 包んだ誤りを返すので、errors.Is ではなく == で見分ける
		if err == io.EOF {
			return in, nil
		}
		if err != nil {
			return users.UpdateInput{}, fmt.Errorf("%w: %w", errUpdateUserInfoForm, err)
		}
		content, err := io.ReadAll(p)
		if err != nil {
			return users.UpdateInput{}, fmt.Errorf("%w: %w", errUpdateUserInfoForm, err)
		}
		switch p.FormName() {
		case formUsername:
			if in.Username != nil {
				continue
			}
			if !utf8.Valid(content) {
				return users.UpdateInput{}, fmt.Errorf("%w: username が UTF-8 でない", errUpdateUserInfoForm)
			}
			v := string(content)
			in.Username = &v
		case formTwoFactorAuthEnabled:
			if in.TwoFactorAuthEnabled != nil {
				continue
			}
			v, err := strconv.ParseBool(string(content))
			if err != nil {
				return users.UpdateInput{}, fmt.Errorf("%w: %w", errUpdateUserInfoForm, err)
			}
			in.TwoFactorAuthEnabled = &v
		case formProfileImage:
			if in.ProfileImage != nil || p.FileName() == "" || len(content) == 0 {
				continue
			}
			in.ProfileImage = &users.ImageInput{
				FileName: p.FileName(), ContentType: p.Header.Get("Content-Type"), Content: content,
			}
		}
	}
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

// UpdateUserInfo は、名前と画像と2段階認証の設定を変え、変えたあとの利用者の情報を 200 で答える。本文を読めないときは、
// 400 と「入力エラーがあります。」で答える。
func (h *userHandlers) UpdateUserInfo(
	ctx context.Context, req gen.UpdateUserInfoRequestObject,
) (gen.UpdateUserInfoResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	in, err := readUpdateUserInfoForm(req.Body, id)
	if err != nil {
		return badRequest(), nil
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
