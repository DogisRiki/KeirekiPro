package users

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// failRoleInsert は、利用者 id の役割の行を足そうとすると、データベースが誤りを返すようにする。
// 利用者の行を書く途中(連携と役割の行を消したあと)で失敗させるためである。テストが終わると元に戻す。
func failRoleInsert(t *testing.T, id uuid.UUID) {
	t.Helper()
	name := "fail_role_insert_" + strings.ReplaceAll(id.String(), "-", "")
	stmts := []string{
		fmt.Sprintf(`CREATE FUNCTION %s() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
	IF NEW.user_id = '%s' THEN
		RAISE EXCEPTION 'テストのために役割の行を足せなくした';
	END IF;
	RETURN NEW;
END $$`, name, id),
		fmt.Sprintf(`CREATE TRIGGER %s BEFORE INSERT ON user_roles FOR EACH ROW EXECUTE FUNCTION %s()`, name, name),
	}
	for _, stmt := range stmts {
		if _, err := testPool.Exec(t.Context(), stmt); err != nil {
			t.Fatalf("役割の行を足せなくする仕掛けを作れません: %v", err)
		}
	}
	t.Cleanup(func() {
		ctx := context.Background()
		if _, err := testPool.Exec(ctx, fmt.Sprintf(`DROP TRIGGER %s ON user_roles`, name)); err != nil {
			t.Errorf("仕掛けを消せません: %v", err)
		}
		if _, err := testPool.Exec(ctx, fmt.Sprintf(`DROP FUNCTION %s()`, name)); err != nil {
			t.Errorf("仕掛けの関数を消せません: %v", err)
		}
	})
}

// wantSaveFailed は、err が、データベースの誤りを包んだ、500 にする誤り(*auth.Error でない誤り)かを確かめる。
func wantSaveFailed(t *testing.T, err error) {
	t.Helper()
	if err == nil {
		t.Fatal("誤り = nil、期待 = 役割の行を足せない誤り")
	}
	var ae *auth.Error
	if errors.As(err, &ae) {
		t.Errorf("誤り = %d %q、期待 = 500 にする誤り(*auth.Error でない誤り)", ae.Status, ae.Message)
	}
}

// 利用者の行を書く途中で失敗したときは、利用者の行も、連携と役割の行も、保存の前のまま残ることを確かめる(Issue #971)。
func TestUpdateUserInfo_SaveFailsKeepsUser(t *testing.T) {
	s := userInfoService(t)
	id := verifiedUser(t)
	before := loadUser(t, id)
	if len(before.Providers) == 0 || len(before.Roles) == 0 {
		t.Fatalf("前提: 連携と役割を持つ利用者のはずですが、連携 %v 役割 %v", before.Providers, before.Roles)
	}
	failRoleInsert(t, id)

	wantSaveFailed(t, s.UpdateUserInfo(t.Context(), UpdateInput{UserID: id, Username: strPtr("佐藤")}))
	wantUnchanged(t, id, before)
}

func TestChangePassword_SaveFailsKeepsUser(t *testing.T) {
	env := newDeleteEnv(t, nil)
	id := verifiedUser(t)
	before := loadUser(t, id)
	failRoleInsert(t, id)

	wantSaveFailed(t, env.users.ChangePassword(t.Context(), id, deleteTestPassword, changedPhrase))
	wantUnchanged(t, id, before)
}
