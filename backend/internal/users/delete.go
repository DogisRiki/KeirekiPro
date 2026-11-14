package users

import (
	"context"
	"fmt"
	"slices"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/database/sqlcgen"
)

// DeleteUser は、Java 版の DeleteUserUseCase と User.delete と UserDeletedEventListener と同じ順で、
// 1つのトランザクションの中で利用者を退会させる。
//  1. 利用者を読む。居なければ、Cookie を消させる 401 の誤りを返す
//  2. Java 版の UserMapper.xml の削除と同じ順で、11の表から利用者の行を消す
//  3. 4つの拡張子の画像の名前と、今の画像の名前を、同じ名前を2回消さずに消す
//  4. ログインの状態の世代の番号を上げ、ログインを続けるための値をすべて消す
//  5. メールアドレスの確認が済んでいれば、退会の完了のメールをそのメールアドレスへ送る
//
// 世代の番号を上げる問い合わせは、トランザクションの問い合わせで送る。トランザクションの外の接続で送ると、
// トランザクションが消した世代の番号の行のロックを待ち続けるためである。行は利用者の行と一緒に消えているので、
// この問い合わせは何も変えない。Java 版も同じ問い合わせを同じトランザクションの中で送る。
//
// どの段で失敗しても、トランザクションを戻して誤りを返す。画像とログインを続けるための値は戻せないので、
// 消えたまま残る。Java 版と同じである。
func (s *Service) DeleteUser(ctx context.Context, userID uuid.UUID) error {
	return s.deps.Auth.InTransaction(ctx, func(q *sqlcgen.Queries) error {
		u, err := auth.LoadUser(ctx, q, userID, auth.ErrCredentialsNotFound(MessageInvalidAccess))
		if err != nil {
			return err
		}

		id := pgtype.UUID{Bytes: userID, Valid: true}
		deletes := []func(context.Context, pgtype.UUID) error{
			q.DeleteAccountProjectTechStacks,
			q.DeleteAccountProjects,
			q.DeleteAccountCareers,
			q.DeleteAccountCertifications,
			q.DeleteAccountPortfolios,
			q.DeleteAccountSnsPlatforms,
			q.DeleteAccountSelfPromotions,
			q.DeleteAccountResumes,
			q.DeleteAccountAuthProviders,
			q.DeleteAccountRoles,
			q.DeleteAccountUser,
		}
		for _, del := range deletes {
			if err := del(ctx, id); err != nil {
				return fmt.Errorf("users: 利用者 %s の行を消せません: %w", userID, err)
			}
		}

		for _, key := range deletedImageKeys(userID, u.Row.ProfileImage) {
			if err := s.delete(ctx, key); err != nil {
				return err
			}
		}

		if err := s.deps.Auth.BumpTokenVersion(ctx, q, userID); err != nil {
			return err
		}
		if err := s.deps.Auth.RemoveAllRefreshTokens(ctx, userID); err != nil {
			return err
		}

		if emailVerified(u) {
			return s.deps.Auth.SendUserDeletedMail(ctx, u.Row.Email.String, u.Row.Username)
		}
		return nil
	})
}

// deletedImageKeys は、Java 版の DeleteUserUseCase と同じく、退会で消す画像の名前を、
// 4つの拡張子(jpg jpeg png gif)の /profile/image/<利用者 id>.<拡張子> の名前、今の画像の名前 current の順に返す。
// current が4つのどれかと同じなら、足さない(Java 版の LinkedHashSet)。current が無ければ4つだけを返す。
func deletedImageKeys(id uuid.UUID, current pgtype.Text) []string {
	keys := make([]string, 0, len(imageExtensions)+1)
	for _, ext := range imageExtensions {
		keys = append(keys, profileImageKey(id, ext))
	}
	if current.Valid && !slices.Contains(keys, current.String) {
		keys = append(keys, current.String)
	}
	return keys
}
