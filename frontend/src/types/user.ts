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
    authProviders: ("github" | "google")[];
}

/**
 * ユーザー情報更新用
 */
export type UserPatch = Partial<User>;
