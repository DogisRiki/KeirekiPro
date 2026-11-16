// Package resume は、マスタと経歴書の26の操作の処理を、Java 版の usecase/resume のユースケースと
// usecase/query の3つのマスタの問い合わせと同じ順で行う。
// このパッケージは HTTP の要求と応答を扱わない。HTTP の受け口は internal/httpapi が受け持つ。
package resume

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// Deps は、Service が使う部品の束である。
type Deps struct {
	// Pool は、データベースの接続の束である。sqlcgen の Queries とトランザクションに使う。
	Pool *pgxpool.Pool
	// Now は、今の時刻を返す関数である。nil のとき、New は time.Now を使う。
	// 本番では main.go が time.Now を渡し、テストは決まった時刻を返す関数を渡す。
	Now func() time.Time
}

// Service は、マスタと経歴書の26の操作の処理の入口である。要求をまたぐ状態をメモリに持たず、
// すべてデータベースに置く。
type Service struct {
	deps Deps
}

// New は、部品の束から Service を作る。時刻の関数を渡さなければ、time.Now を使う。
func New(d Deps) *Service {
	if d.Now == nil {
		d.Now = time.Now
	}
	return &Service{deps: d}
}

// ListCertificationNames は、資格のマスタの名前を返す。
func (s *Service) ListCertificationNames(ctx context.Context) ([]string, error) {
	return poolStore(s.deps.Pool).listCertificationNames(ctx)
}

// ListSnsPlatformNames は、SNS のマスタの名前を返す。
func (s *Service) ListSnsPlatformNames(ctx context.Context) ([]string, error) {
	return poolStore(s.deps.Pool).listSnsPlatformNames(ctx)
}

// ListTechStacks は、技術スタックのマスタの名前を、答えの大分類と小分類に振り分けて返す。
func (s *Service) ListTechStacks(ctx context.Context) (TechStackMaster, error) {
	return poolStore(s.deps.Pool).listTechStacks(ctx)
}

// ListResumes は、利用者の経歴書を作成の日時の順に返す。6つの欄の項目は読まない。
func (s *Service) ListResumes(ctx context.Context, userID uuid.UUID) ([]Resume, error) {
	return poolStore(s.deps.Pool).listResumes(ctx, userID)
}

// GetResume は、利用者の経歴書1件を、6つの欄の項目と一緒に返す。項目は Java 版と同じ順に並べる。
// 経歴書の ID が読めないとき、経歴書が無いとき、ほかの利用者の経歴書のときは、無い経歴書の誤りを返す。
func (s *Service) GetResume(ctx context.Context, userID uuid.UUID, resumeID string) (Resume, error) {
	id, ok := parseID(resumeID)
	if !ok {
		return Resume{}, errResumeNotFound()
	}
	r, found, err := poolStore(s.deps.Pool).findResume(ctx, userID, id)
	if err != nil {
		return Resume{}, err
	}
	if !found {
		return Resume{}, errResumeNotFound()
	}
	return r, nil
}

// DeleteResume は、利用者の経歴書1件を、6つの欄の項目と一緒に消す。
// 経歴書の ID が読めないとき、経歴書が無いとき、ほかの利用者の経歴書のときは、何も消さずに無い経歴書の誤りを返す。
// 経歴書の行に鍵をかけてから消すので、同じ経歴書への項目の変更と同時に動いても、消したあとに項目の行が残らない。
func (s *Service) DeleteResume(ctx context.Context, userID uuid.UUID, resumeID string) error {
	id, ok := parseID(resumeID)
	if !ok {
		return errResumeNotFound()
	}
	return inTx(ctx, s.deps.Pool, func(st store) error {
		if _, found, err := st.lockResume(ctx, userID, id); err != nil {
			return err
		} else if !found {
			return errResumeNotFound()
		}
		return st.deleteResume(ctx, id)
	})
}

// CreateResume は、利用者の経歴書を1件作る。要求の本文の resumeId に経歴書の ID があれば、その経歴書の日付と姓と名と6つの欄の項目を写す。
// 確かめる順は Java 版と同じく、経歴書の数の上限、名前の重なり、コピー元の経歴書、名前の値の決まりである。
// 答えの作成と更新の日時は、データベースに書くときに丸める前の今の時刻である。
func (s *Service) CreateResume(ctx context.Context, userID uuid.UUID, body []byte) (Resume, error) {
	req, err := decodeBody[createResumeRequest](body)
	if err != nil {
		return Resume{}, errUnreadableInput()
	}
	if e := validateCreateResume(req); e != nil {
		return Resume{}, e
	}
	name := *req.ResumeName
	now := s.deps.Now().In(japanZone)
	var created Resume
	err = inTx(ctx, s.deps.Pool, func(st store) error {
		count, err := st.countResumes(ctx, userID)
		if err != nil {
			return err
		}
		if e := resumeLimit.check(count); e != nil {
			return e
		}
		if exists, err := st.resumeNameExists(ctx, userID, name); err != nil {
			return err
		} else if exists {
			return errResumeNameDuplicated()
		}
		r := Resume{
			ID: uuid.New(), UserID: userID, Name: name,
			Date:      Date{Year: now.Year(), Month: now.Month(), Day: now.Day()},
			CreatedAt: now, UpdatedAt: now,
			Careers: []Career{}, Projects: []Project{}, Certifications: []Certification{},
			Portfolios: []Portfolio{}, SnsPlatforms: []SnsPlatform{}, SelfPromotions: []SelfPromotion{},
		}
		if req.ResumeID.Present {
			src, found, err := st.findResume(ctx, userID, req.ResumeID.Value)
			if err != nil {
				return err
			}
			if !found {
				return errResumeNotFound()
			}
			copyEntries(&r, src)
		}
		f := auth.FieldErrors{}
		checkResumeName(f, name)
		if e := f.Result(); e != nil {
			return e
		}
		if err := st.insertResume(ctx, r); err != nil {
			if isUserMissing(err) {
				return errResumeNotFound()
			}
			return err
		}
		created = r
		return nil
	})
	if err != nil {
		return Resume{}, err
	}
	return created, nil
}

// copyEntries は、コピー元の経歴書の日付と姓と名と6つの欄の項目を r に写す。項目には新しい ID を付け、新しい ID で項目を並べ直す。
func copyEntries(r *Resume, src Resume) {
	r.Date, r.LastName, r.FirstName = src.Date, src.LastName, src.FirstName
	r.Careers = withNewIDs(src.Careers, func(e *Career) *uuid.UUID { return &e.ID })
	r.Projects = withNewIDs(src.Projects, func(e *Project) *uuid.UUID { return &e.ID })
	r.Certifications = withNewIDs(src.Certifications, func(e *Certification) *uuid.UUID { return &e.ID })
	r.Portfolios = withNewIDs(src.Portfolios, func(e *Portfolio) *uuid.UUID { return &e.ID })
	r.SnsPlatforms = withNewIDs(src.SnsPlatforms, func(e *SnsPlatform) *uuid.UUID { return &e.ID })
	r.SelfPromotions = withNewIDs(src.SelfPromotions, func(e *SelfPromotion) *uuid.UUID { return &e.ID })
	sortEntries(r)
}

// withNewIDs は、項目の並びを写し、写した項目のそれぞれに新しい ID を付ける。並びが空でも nil にしない。
func withNewIDs[E any](entries []E, id func(*E) *uuid.UUID) []E {
	out := append(make([]E, 0, len(entries)), entries...)
	for i := range out {
		*id(&out[i]) = uuid.New()
	}
	return out
}

// isUserMissing は、err が、経歴書の行の利用者が居ないための外部キーの違反かを返す。利用者が退会したあとに届いた作成の要求で起きる。
func isUserMissing(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23503" && pgErr.TableName == "resumes"
}

// UpdateResumeBasic は、利用者の経歴書の名前と日付と姓と名を書き換え、6つの欄の項目を持つ経歴書を返す。
// 名前を変えるときだけ、ほかの経歴書との名前の重なりを確かめる。名前と姓と名の値の決まりの誤りは、まとめて返す。
// 答えの更新の日時は丸める前の今の時刻であり、作成の日時はデータベースの値である。
func (s *Service) UpdateResumeBasic(ctx context.Context, userID uuid.UUID, resumeID string, body []byte) (Resume, error) {
	req, err := decodeBody[updateResumeBasicRequest](body)
	if err != nil {
		return Resume{}, errUnreadableInput()
	}
	if e := validateUpdateResumeBasic(req); e != nil {
		return Resume{}, e
	}
	id, ok := parseID(resumeID)
	if !ok {
		return Resume{}, errResumeNotFound()
	}
	name := *req.ResumeName
	var updated Resume
	err = inTx(ctx, s.deps.Pool, func(st store) error {
		r, found, err := st.lockResume(ctx, userID, id)
		if err != nil {
			return err
		}
		if !found {
			return errResumeNotFound()
		}
		if name != r.Name {
			if exists, err := st.resumeNameExists(ctx, userID, name); err != nil {
				return err
			} else if exists {
				return errResumeNameDuplicated()
			}
		}
		f := auth.FieldErrors{}
		checkResumeName(f, name)
		checkFullName(f, req.LastName, req.FirstName)
		if e := f.Result(); e != nil {
			return e
		}
		r.Name, r.Date, r.LastName, r.FirstName = name, req.Date.Value, req.LastName, req.FirstName
		r.UpdatedAt = s.deps.Now().In(japanZone)
		if err := st.updateResumeBasic(ctx, r); err != nil {
			return err
		}
		updated = r
		return nil
	})
	if err != nil {
		return Resume{}, err
	}
	return updated, nil
}
