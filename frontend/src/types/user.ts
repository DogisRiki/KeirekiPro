/**
 * ユーザー
 */
export interface User {
    userId: string; // ユーザーID
    userName: string; // ユーザー名
    email: string; // メールアドレス
    hasPassword: boolean; // パスワードが設定されているかどうか
    profileImage: string; // プロフィール画像
    twoFactorAuthEnabled: boolean; // 二段階認証が有効かどうか
    authProviders: ("email" | "github" | "google")[]; // どの認証プロバイダーで認証済みか
}

/**
 * プロフィール更新
 */
export type updateUserProfile = Pick<User, "userName" | "profileImage" | "twoFactorAuthEnabled">;
