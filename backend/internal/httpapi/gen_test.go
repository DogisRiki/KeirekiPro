package httpapi_test

import (
	"reflect"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
)

// Java 版が受け付ける操作の数。仕様書 api/openapi.yaml に、すべての操作を書く。
const javaOperationCount = 50

// 仕様書から生成した受け口が、Java 版のすべての操作を持つことを確かめる。
func TestGeneratedOperationsCount(t *testing.T) {
	got := reflect.TypeFor[gen.StrictServerInterface]().NumMethod()
	if got != javaOperationCount {
		t.Errorf("StrictServerInterface の操作の数 = %d, want %d", got, javaOperationCount)
	}
}
