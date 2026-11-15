// Package resume は、マスタと経歴書の26の操作の処理を、Java 版の usecase/resume のユースケースと
// usecase/query の3つのマスタの問い合わせと同じ順で行う。
// このパッケージは HTTP の要求と応答を扱わない。HTTP の受け口は internal/httpapi が受け持つ。
package resume

import (
	"time"

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
