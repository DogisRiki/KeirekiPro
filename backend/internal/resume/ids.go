package resume

import (
	"cmp"
	"encoding/binary"

	"github.com/google/uuid"
)

// parseID は、経路の経歴書の ID と項目の ID と、経歴書の作成の resumeId を、uuid.Parse で読む。
// uuid.Parse は、値の長さで読み方を決める。長さ36の値は区切りの - の付いた形として読み、
// 長さ38の値は最初と最後の1字を除いてから読み、長さ45の値は urn:uuid: を除いてから読み、
// 長さ32の値は区切りの - の無い形として読む。大文字の値も読む。読めない値は false を返す。
// Java 版と違う読み方になる書き方は、変えた動きの一覧の CB-051 と CB-052 に載せた。
func parseID(s string) (uuid.UUID, bool) {
	id, err := uuid.Parse(s)
	if err != nil {
		return uuid.UUID{}, false
	}
	return id, true
}

// compareJavaUUID は、java.util.UUID.compareTo の写しである。
// 上位の64ビットと下位の64ビットを、それぞれ符号付きの整数として比べる。
// 項目の並びは画面に見えるので、Go 版は Java 版と同じ順に並べる。
func compareJavaUUID(a, b uuid.UUID) int {
	if c := cmp.Compare(int64(binary.BigEndian.Uint64(a[:8])), int64(binary.BigEndian.Uint64(b[:8]))); c != 0 {
		return c
	}
	return cmp.Compare(int64(binary.BigEndian.Uint64(a[8:])), int64(binary.BigEndian.Uint64(b[8:])))
}
