/**
 * ユーザー情報
 */
export interface User {
    id: string;
    email: string | null;
    username: string;
    profileImage: string | null;
    twoFactorAuthEnabled: boolean;
    hasPassword: boolean;
    authProviders: AuthProvider[];
}

/**
 * ユーザー情報更新用
 */
export type UserPatch = Partial<User>;

/**
 * 外部認証プロバイダー
 */
export type AuthProvider = "github" | "google";
