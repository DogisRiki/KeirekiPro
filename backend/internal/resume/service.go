// Package resume は、マスタと経歴書の26の操作の処理を、Java 版の usecase/resume のユースケースと
// usecase/query の3つのマスタの問い合わせと同じ順で行う。
// このパッケージは HTTP の要求と応答を扱わない。HTTP の受け口は internal/httpapi が受け持つ。
package resume

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
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
