package httpapi

import (
	"net/http"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/users"
)

// 利用者の7つの操作の答えも、認証の操作と同じ authResponse で書く。退会は Set-Cookie を2つ書くためである。
var (
	_ gen.GetUserInfoResponseObject                  = authResponse{}
	_ gen.UpdateUserInfoResponseObject               = authResponse{}
	_ gen.DeleteUserResponseObject                   = authResponse{}
	_ gen.SendAccountEmailVerificationResponseObject = authResponse{}
	_ gen.SetEmailAndPasswordResponseObject          = authResponse{}
	_ gen.ChangePasswordResponseObject               = authResponse{}
	_ gen.RemoveAuthProviderResponseObject           = authResponse{}
)

// userInfoBody は、Java 版の UserInfoResponse と同じ項目を同じ順に並べた、利用者の情報の答えの本文である。
// Java 版と同じく、値の無い項目は省かずに null で書き、連携と役割が無いときは空の並びで書く。
type userInfoBody struct {
	ID                   string   `json:"id"`
	Email                *string  `json:"email"`
	Username             *string  `json:"username"`
	HasPassword          bool     `json:"hasPassword"`
	ProfileImage         *string  `json:"profileImage"`
	TwoFactorAuthEnabled bool     `json:"twoFactorAuthEnabled"`
	AuthProviders        []string `json:"authProviders"`
	Roles                []string `json:"roles"`
	EmailVerified        bool     `json:"emailVerified"`
	PendingEmail         *string  `json:"pendingEmail"`
}

// newUserInfoBody は、利用者の情報 u を答えの本文にする。
func newUserInfoBody(u users.UserInfo) userInfoBody {
	return userInfoBody{
		ID:                   u.ID.String(),
		Email:                u.Email,
		Username:             u.Username,
		HasPassword:          u.HasPassword,
		ProfileImage:         u.ProfileImage,
		TwoFactorAuthEnabled: u.TwoFactorAuthEnabled,
		AuthProviders:        nonNil(u.AuthProviders),
		Roles:                nonNil(u.Roles),
		EmailVerified:        u.EmailVerified,
		PendingEmail:         u.PendingEmail,
	}
}

// nonNil は、nil の並びを空の並びにする。encoding/json は nil の並びを null と書くためである。
func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

// VisitGetUserInfoResponse は、応答を書く。
func (r authResponse) VisitGetUserInfoResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitUpdateUserInfoResponse は、応答を書く。
func (r authResponse) VisitUpdateUserInfoResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitDeleteUserResponse は、応答を書く。
func (r authResponse) VisitDeleteUserResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitSendAccountEmailVerificationResponse は、応答を書く。
func (r authResponse) VisitSendAccountEmailVerificationResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitSetEmailAndPasswordResponse は、応答を書く。
func (r authResponse) VisitSetEmailAndPasswordResponse(w http.ResponseWriter) error {
	return r.write(w)
}

// VisitChangePasswordResponse は、応答を書く。
func (r authResponse) VisitChangePasswordResponse(w http.ResponseWriter) error { return r.write(w) }

// VisitRemoveAuthProviderResponse は、応答を書く。
func (r authResponse) VisitRemoveAuthProviderResponse(w http.ResponseWriter) error { return r.write(w) }
