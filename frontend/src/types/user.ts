/**
 * 外部認証連携情報
 */
export interface AuthProviderInfo {
    id: string;
    providerType: "github" | "google";
    providerUserId: string;
}

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
    authProviders: AuthProviderInfo[];
}

/**
 * ユーザー情報更新用
 */
export type UserPatch = Partial<User>;
