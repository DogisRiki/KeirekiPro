package httpapi

import (
	"context"
	"encoding/json"
	"mime"
	"net/http"
	"strings"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/authctx"
	"github.com/DogisRiki/KeirekiPro/backend/internal/resume"
)

// ResumeService は、経歴書の受け口が使う処理である。経路の ID と本文は、受け口が読まずにそのまま渡し、処理が
// Java 版と同じ順で読んで確かめる。
type ResumeService interface {
	ListCertificationNames(ctx context.Context) ([]string, error)
	ListSnsPlatformNames(ctx context.Context) ([]string, error)
	ListTechStacks(ctx context.Context) (resume.TechStackMaster, error)

	ListResumes(ctx context.Context, userID uuid.UUID) ([]resume.Resume, error)
	GetResume(ctx context.Context, userID uuid.UUID, resumeID string) (resume.Resume, error)
	DeleteResume(ctx context.Context, userID uuid.UUID, resumeID string) error
	CreateResume(ctx context.Context, userID uuid.UUID, body []byte) (resume.Resume, error)
	UpdateResumeBasic(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error)
	ExportResume(ctx context.Context, userID uuid.UUID, resumeID string, format resume.ExportFormat) (resume.Export, error)
	ExportResumeWithSettings(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Export, error)
	BackupResume(ctx context.Context, userID uuid.UUID, resumeID string) (resume.Export, error)
	RestoreResume(ctx context.Context, userID uuid.UUID, body []byte) (resume.Resume, error)

	CreateCareer(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error)
	UpdateCareer(ctx context.Context, userID uuid.UUID, resumeID, careerID string, body []byte) (resume.Resume, error)
	DeleteCareer(ctx context.Context, userID uuid.UUID, resumeID, careerID string) error

	CreateProject(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error)
	UpdateProject(ctx context.Context, userID uuid.UUID, resumeID, projectID string, body []byte) (resume.Resume, error)
	DeleteProject(ctx context.Context, userID uuid.UUID, resumeID, projectID string) error

	CreateCertification(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error)
	UpdateCertification(ctx context.Context, userID uuid.UUID, resumeID, certificationID string, body []byte) (resume.Resume, error)
	DeleteCertification(ctx context.Context, userID uuid.UUID, resumeID, certificationID string) error

	CreatePortfolio(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error)
	UpdatePortfolio(ctx context.Context, userID uuid.UUID, resumeID, portfolioID string, body []byte) (resume.Resume, error)
	DeletePortfolio(ctx context.Context, userID uuid.UUID, resumeID, portfolioID string) error

	CreateSnsPlatform(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error)
	UpdateSnsPlatform(ctx context.Context, userID uuid.UUID, resumeID, snsPlatformID string, body []byte) (resume.Resume, error)
	DeleteSnsPlatform(ctx context.Context, userID uuid.UUID, resumeID, snsPlatformID string) error

	CreateSelfPromotion(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (resume.Resume, error)
	UpdateSelfPromotion(ctx context.Context, userID uuid.UUID, resumeID, selfPromotionID string, body []byte) (resume.Resume, error)
	DeleteSelfPromotion(ctx context.Context, userID uuid.UUID, resumeID, selfPromotionID string) error
}

var _ ResumeService = (*resume.Service)(nil)

// resumeHandlers は、経歴書の30の操作の受け口である。
type resumeHandlers struct {
	svc    ResumeService
	secure bool
}

// newResumeHandlers は、経歴書の操作の受け口を作る。
func newResumeHandlers(svc ResumeService, secure bool) *resumeHandlers {
	return &resumeHandlers{svc: svc, secure: secure}
}

// fail は、err が *auth.Error を含めばその応答を、含まなければ err をそのまま返す。
func (h *resumeHandlers) fail(err error) (authResponse, error) {
	if r, ok := authErrorResponse(err, h.secure); ok {
		return r, nil
	}
	return authResponse{}, err
}

// rawBody は、生成したコードが読まずに受け取った本文を返す。本文が無ければ nil である。
func rawBody(b *json.RawMessage) []byte {
	if b == nil {
		return nil
	}
	return *b
}

// withResume は、ログインした利用者の ID で f を呼び、f が返した経歴書を status と経歴書の答えの本文で答える。
// ログインした利用者の ID が context に無ければ、f を呼ばずに errNoLoginUser を返す。
func (h *resumeHandlers) withResume(
	ctx context.Context, status int, f func(userID uuid.UUID) (resume.Resume, error),
) (authResponse, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	r, err := f(id)
	if err != nil {
		return h.fail(err)
	}
	return authJSON(status, newResumeBody(r)), nil
}

// withNoContent は、ログインした利用者の ID で f を呼び、成功すれば 204 と空の本文で答える。
// ログインした利用者の ID が context に無ければ、f を呼ばずに errNoLoginUser を返す。
func (h *resumeHandlers) withNoContent(ctx context.Context, f func(userID uuid.UUID) error) (authResponse, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	if err := f(id); err != nil {
		return h.fail(err)
	}
	return authNoBody(http.StatusNoContent), nil
}

// names は、名前の並びを 200 と {"names": [...]} で答える。
func (h *resumeHandlers) names(list []string, err error) (authResponse, error) {
	if err != nil {
		return h.fail(err)
	}
	return authJSON(http.StatusOK, namesBody{Names: nonNil(list)}), nil
}

// ListCertificationNames は、資格の名前のマスタを答える。
func (h *resumeHandlers) ListCertificationNames(
	ctx context.Context, _ gen.ListCertificationNamesRequestObject,
) (gen.ListCertificationNamesResponseObject, error) {
	return h.names(h.svc.ListCertificationNames(ctx))
}

// ListSnsPlatformNames は、SNS の名前のマスタを答える。
func (h *resumeHandlers) ListSnsPlatformNames(
	ctx context.Context, _ gen.ListSnsPlatformNamesRequestObject,
) (gen.ListSnsPlatformNamesResponseObject, error) {
	return h.names(h.svc.ListSnsPlatformNames(ctx))
}

// ListTechStacks は、技術スタックのマスタを4つの大分類で答える。
func (h *resumeHandlers) ListTechStacks(
	ctx context.Context, _ gen.ListTechStacksRequestObject,
) (gen.ListTechStacksResponseObject, error) {
	m, err := h.svc.ListTechStacks(ctx)
	if err != nil {
		return h.fail(err)
	}
	return authJSON(http.StatusOK, m), nil
}

// ListResumes は、ログインした利用者の経歴書の一覧を答える。
func (h *resumeHandlers) ListResumes(ctx context.Context, _ gen.ListResumesRequestObject) (gen.ListResumesResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	list, err := h.svc.ListResumes(ctx, id)
	if err != nil {
		return h.fail(err)
	}
	return authJSON(http.StatusOK, newResumeListBody(list)), nil
}

// CreateResume は、経歴書を作り、201 で答える。
func (h *resumeHandlers) CreateResume(
	ctx context.Context, req gen.CreateResumeRequestObject,
) (gen.CreateResumeResponseObject, error) {
	return h.withResume(ctx, http.StatusCreated, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.CreateResume(ctx, userID, rawBody(req.Body))
	})
}

// GetResume は、経歴書1件を答える。
func (h *resumeHandlers) GetResume(ctx context.Context, req gen.GetResumeRequestObject) (gen.GetResumeResponseObject, error) {
	return h.withResume(ctx, http.StatusOK, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.GetResume(ctx, userID, req.ResumeId)
	})
}

// DeleteResume は、経歴書を消し、204 で答える。
func (h *resumeHandlers) DeleteResume(
	ctx context.Context, req gen.DeleteResumeRequestObject,
) (gen.DeleteResumeResponseObject, error) {
	return h.withNoContent(ctx, func(userID uuid.UUID) error {
		return h.svc.DeleteResume(ctx, userID, req.ResumeId)
	})
}

// UpdateResumeBasic は、経歴書の基本の情報を変え、200 で答える。
func (h *resumeHandlers) UpdateResumeBasic(
	ctx context.Context, req gen.UpdateResumeBasicRequestObject,
) (gen.UpdateResumeBasicResponseObject, error) {
	return h.withResume(ctx, http.StatusOK, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.UpdateResumeBasic(ctx, userID, req.ResumeId, rawBody(req.Body))
	})
}

// CreateCareer は、職歴を足し、201 で答える。
func (h *resumeHandlers) CreateCareer(
	ctx context.Context, req gen.CreateCareerRequestObject,
) (gen.CreateCareerResponseObject, error) {
	return h.withResume(ctx, http.StatusCreated, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.CreateCareer(ctx, userID, req.ResumeId, rawBody(req.Body))
	})
}

// UpdateCareer は、職歴を変え、200 で答える。
func (h *resumeHandlers) UpdateCareer(
	ctx context.Context, req gen.UpdateCareerRequestObject,
) (gen.UpdateCareerResponseObject, error) {
	return h.withResume(ctx, http.StatusOK, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.UpdateCareer(ctx, userID, req.ResumeId, req.CareerId, rawBody(req.Body))
	})
}

// DeleteCareer は、職歴を消し、204 で答える。
func (h *resumeHandlers) DeleteCareer(
	ctx context.Context, req gen.DeleteCareerRequestObject,
) (gen.DeleteCareerResponseObject, error) {
	return h.withNoContent(ctx, func(userID uuid.UUID) error {
		return h.svc.DeleteCareer(ctx, userID, req.ResumeId, req.CareerId)
	})
}

// CreateProject は、プロジェクトを足し、201 で答える。
func (h *resumeHandlers) CreateProject(
	ctx context.Context, req gen.CreateProjectRequestObject,
) (gen.CreateProjectResponseObject, error) {
	return h.withResume(ctx, http.StatusCreated, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.CreateProject(ctx, userID, req.ResumeId, rawBody(req.Body))
	})
}

// UpdateProject は、プロジェクトを変え、200 で答える。
func (h *resumeHandlers) UpdateProject(
	ctx context.Context, req gen.UpdateProjectRequestObject,
) (gen.UpdateProjectResponseObject, error) {
	return h.withResume(ctx, http.StatusOK, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.UpdateProject(ctx, userID, req.ResumeId, req.ProjectId, rawBody(req.Body))
	})
}

// DeleteProject は、プロジェクトを消し、204 で答える。
func (h *resumeHandlers) DeleteProject(
	ctx context.Context, req gen.DeleteProjectRequestObject,
) (gen.DeleteProjectResponseObject, error) {
	return h.withNoContent(ctx, func(userID uuid.UUID) error {
		return h.svc.DeleteProject(ctx, userID, req.ResumeId, req.ProjectId)
	})
}

// CreateCertification は、資格を足し、201 で答える。
func (h *resumeHandlers) CreateCertification(
	ctx context.Context, req gen.CreateCertificationRequestObject,
) (gen.CreateCertificationResponseObject, error) {
	return h.withResume(ctx, http.StatusCreated, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.CreateCertification(ctx, userID, req.ResumeId, rawBody(req.Body))
	})
}

// UpdateCertification は、資格を変え、200 で答える。
func (h *resumeHandlers) UpdateCertification(
	ctx context.Context, req gen.UpdateCertificationRequestObject,
) (gen.UpdateCertificationResponseObject, error) {
	return h.withResume(ctx, http.StatusOK, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.UpdateCertification(ctx, userID, req.ResumeId, req.CertificationId, rawBody(req.Body))
	})
}

// DeleteCertification は、資格を消し、204 で答える。
func (h *resumeHandlers) DeleteCertification(
	ctx context.Context, req gen.DeleteCertificationRequestObject,
) (gen.DeleteCertificationResponseObject, error) {
	return h.withNoContent(ctx, func(userID uuid.UUID) error {
		return h.svc.DeleteCertification(ctx, userID, req.ResumeId, req.CertificationId)
	})
}

// CreatePortfolio は、ポートフォリオを足し、201 で答える。
func (h *resumeHandlers) CreatePortfolio(
	ctx context.Context, req gen.CreatePortfolioRequestObject,
) (gen.CreatePortfolioResponseObject, error) {
	return h.withResume(ctx, http.StatusCreated, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.CreatePortfolio(ctx, userID, req.ResumeId, rawBody(req.Body))
	})
}

// UpdatePortfolio は、ポートフォリオを変え、200 で答える。
func (h *resumeHandlers) UpdatePortfolio(
	ctx context.Context, req gen.UpdatePortfolioRequestObject,
) (gen.UpdatePortfolioResponseObject, error) {
	return h.withResume(ctx, http.StatusOK, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.UpdatePortfolio(ctx, userID, req.ResumeId, req.PortfolioId, rawBody(req.Body))
	})
}

// DeletePortfolio は、ポートフォリオを消し、204 で答える。
func (h *resumeHandlers) DeletePortfolio(
	ctx context.Context, req gen.DeletePortfolioRequestObject,
) (gen.DeletePortfolioResponseObject, error) {
	return h.withNoContent(ctx, func(userID uuid.UUID) error {
		return h.svc.DeletePortfolio(ctx, userID, req.ResumeId, req.PortfolioId)
	})
}

// CreateSnsPlatform は、SNS を足し、201 で答える。
func (h *resumeHandlers) CreateSnsPlatform(
	ctx context.Context, req gen.CreateSnsPlatformRequestObject,
) (gen.CreateSnsPlatformResponseObject, error) {
	return h.withResume(ctx, http.StatusCreated, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.CreateSnsPlatform(ctx, userID, req.ResumeId, rawBody(req.Body))
	})
}

// UpdateSnsPlatform は、SNS を変え、200 で答える。
func (h *resumeHandlers) UpdateSnsPlatform(
	ctx context.Context, req gen.UpdateSnsPlatformRequestObject,
) (gen.UpdateSnsPlatformResponseObject, error) {
	return h.withResume(ctx, http.StatusOK, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.UpdateSnsPlatform(ctx, userID, req.ResumeId, req.SnsPlatformId, rawBody(req.Body))
	})
}

// DeleteSnsPlatform は、SNS を消し、204 で答える。
func (h *resumeHandlers) DeleteSnsPlatform(
	ctx context.Context, req gen.DeleteSnsPlatformRequestObject,
) (gen.DeleteSnsPlatformResponseObject, error) {
	return h.withNoContent(ctx, func(userID uuid.UUID) error {
		return h.svc.DeleteSnsPlatform(ctx, userID, req.ResumeId, req.SnsPlatformId)
	})
}

// CreateSelfPromotion は、自己PRを足し、201 で答える。
func (h *resumeHandlers) CreateSelfPromotion(
	ctx context.Context, req gen.CreateSelfPromotionRequestObject,
) (gen.CreateSelfPromotionResponseObject, error) {
	return h.withResume(ctx, http.StatusCreated, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.CreateSelfPromotion(ctx, userID, req.ResumeId, rawBody(req.Body))
	})
}

// UpdateSelfPromotion は、自己PRを変え、200 で答える。
func (h *resumeHandlers) UpdateSelfPromotion(
	ctx context.Context, req gen.UpdateSelfPromotionRequestObject,
) (gen.UpdateSelfPromotionResponseObject, error) {
	return h.withResume(ctx, http.StatusOK, func(userID uuid.UUID) (resume.Resume, error) {
		return h.svc.UpdateSelfPromotion(ctx, userID, req.ResumeId, req.SelfPromotionId, rawBody(req.Body))
	})
}

// DeleteSelfPromotion は、自己PRを消し、204 で答える。
func (h *resumeHandlers) DeleteSelfPromotion(
	ctx context.Context, req gen.DeleteSelfPromotionRequestObject,
) (gen.DeleteSelfPromotionResponseObject, error) {
	return h.withNoContent(ctx, func(userID uuid.UUID) error {
		return h.svc.DeleteSelfPromotion(ctx, userID, req.ResumeId, req.SelfPromotionId)
	})
}

// exportNotAcceptableMessage は、設定を付けない出力で、Accept の行から形式を選べないときの文言である。
const exportNotAcceptableMessage = "対応していない形式が指定されました。"

// exportFormatFromAccept は、Accept の行を , で分けて mime.ParseMediaType で型の並びとして読み、型が application/pdf の
// 値があれば PDF を、無くて型が text/markdown の値があれば Markdown を返す。どちらも無いときと、読めない値があるときは
// ok が false になる(変えた動きの一覧の CB-059)。
func exportFormatFromAccept(lines []string) (resume.ExportFormat, bool) {
	var pdf, markdown bool
	for _, line := range lines {
		for _, v := range strings.Split(line, ",") {
			if strings.TrimSpace(v) == "" {
				continue
			}
			t, _, err := mime.ParseMediaType(v)
			if err != nil {
				return "", false
			}
			pdf = pdf || t == "application/pdf"
			markdown = markdown || t == "text/markdown"
		}
	}
	switch {
	case pdf:
		return resume.ExportPDF, true
	case markdown:
		return resume.ExportMarkdown, true
	}
	return "", false
}

// exported は、出力 e を、200 と、出力の Content-Type と、出し方とファイル名から作った Content-Disposition と、
// 出力の本文で答える。err があれば、ほかの経歴書の操作と同じく答える。
func (h *resumeHandlers) exported(e resume.Export, err error) (authResponse, error) {
	if err != nil {
		return h.fail(err)
	}
	return authResponse{
		status: http.StatusOK, contentType: e.ContentType,
		contentDisposition: formatContentDisposition(e.Inline, e.FileName), body: e.Body,
	}, nil
}

// ExportResume は、設定を付けずに経歴書を出力する。形式は、authRequestMiddleware が context に入れた Accept の行で
// 選ぶ。選べないときは、経歴書を読まずに、406 と「対応していない形式が指定されました。」で答える。
func (h *resumeHandlers) ExportResume(
	ctx context.Context, req gen.ExportResumeRequestObject,
) (gen.ExportResumeResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	format, ok := exportFormatFromAccept(requestInfo(ctx).accept)
	if !ok {
		return authJSON(http.StatusNotAcceptable, authErrorBody{Message: exportNotAcceptableMessage, Errors: map[string][]string{}}), nil
	}
	return h.exported(h.svc.ExportResume(ctx, id, req.ResumeId, format))
}

// ExportResumeWithSettings は、本文の設定を付けて経歴書を出力する。本文は読まずに処理に渡し、Accept の行を見ない。
func (h *resumeHandlers) ExportResumeWithSettings(
	ctx context.Context, req gen.ExportResumeWithSettingsRequestObject,
) (gen.ExportResumeWithSettingsResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	return h.exported(h.svc.ExportResumeWithSettings(ctx, id, req.ResumeId, rawBody(req.Body)))
}

// BackupResume は、経歴書をバックアップのファイルに書き出し、200 と、attachment の Content-Disposition と、ファイルで
// 答える。Java 版の BackupResumeController と同じく、Accept の行を見ない。
func (h *resumeHandlers) BackupResume(
	ctx context.Context, req gen.BackupResumeRequestObject,
) (gen.BackupResumeResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	return h.exported(h.svc.BackupResume(ctx, id, req.ResumeId))
}

// RestoreResume は、本文のバックアップのファイルから経歴書を戻し、201 と、ほかの経歴書の操作と同じ経歴書の答えの本文で答える。
// 本文は読まずに処理に渡す。
func (h *resumeHandlers) RestoreResume(
	ctx context.Context, req gen.RestoreResumeRequestObject,
) (gen.RestoreResumeResponseObject, error) {
	id, ok := authctx.UserID(ctx)
	if !ok {
		return authResponse{}, errNoLoginUser
	}
	r, err := h.svc.RestoreResume(ctx, id, rawBody(req.Body))
	if err != nil {
		return h.fail(err)
	}
	return authJSON(http.StatusCreated, newResumeBody(r)), nil
}
