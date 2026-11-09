package httpapi_test

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi"
)

// 仕様書のすべての操作が、まだ作っていない操作の誤りを返すことを確かめる。
func TestUnimplemented_AllOperationsReturnErrNotImplemented(t *testing.T) {
	value := reflect.ValueOf(httpapi.Unimplemented{})
	if value.NumMethod() == 0 {
		t.Fatal("操作が1つもありません")
	}
	for i := range value.NumMethod() {
		method := value.Type().Method(i)
		t.Run(method.Name, func(t *testing.T) {
			request := reflect.Zero(method.Type.In(2))
			results := value.Method(i).Call([]reflect.Value{reflect.ValueOf(context.Background()), request})
			if !results[0].IsNil() {
				t.Errorf("応答 = %v, want nil", results[0].Interface())
			}
			err, _ := results[1].Interface().(error)
			if !errors.Is(err, httpapi.ErrNotImplemented) {
				t.Errorf("誤り = %v, want ErrNotImplemented", err)
			}
		})
	}
}
