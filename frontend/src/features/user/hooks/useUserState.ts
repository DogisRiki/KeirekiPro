import { UserState } from "@/features/user";
import { useUserAuthStore } from "@/stores";
import { User } from "@/types";
import { useMemo } from "react";

/**
 * ユーザーの状態を判定する
 *
 * 判定ルール（○ = true / ✕ = false）
 * - EMAIL_PASSWORD
 *   - email: ○
 *   - hasPassword: ○
 *   - hasProvider: ✕
 * - EMAIL_WITH_PROVIDER
 *   - email: ○
 *   - hasPassword: ✕
 *   - hasProvider: ○
 * - PROVIDER_ONLY
 *   - email: ✕
 *   - hasPassword: ✕
 *   - hasProvider: ○
 * - EMAIL_PASSWORD_WITH_PROVIDER
 *   - 上記以外（email, hasPassword, hasProvider すべて ○）
 *
 * @param user ユーザー情報
 * @returns 判定された {@link UserState}
 */
export const getUserState = (user: User | null): UserState => {
    if (!user) return UserState.UNKNOWN;

    const hasEmail = Boolean(user.email);
    const hasPassword = user.hasPassword;
    const providerCount = Array.isArray(user.authProviders) ? user.authProviders.length : 0;
    const hasProvider = providerCount > 0;

    switch (true) {
        case hasEmail && hasPassword && !hasProvider:
            return UserState.EMAIL_PASSWORD;

        case hasEmail && !hasPassword && hasProvider:
            return UserState.EMAIL_WITH_PROVIDER;

        case !hasEmail && !hasPassword && hasProvider:
            return UserState.PROVIDER_ONLY;

        case hasEmail && hasPassword && hasProvider:
            return UserState.EMAIL_PASSWORD_WITH_PROVIDER;

        default:
            return UserState.UNKNOWN; // ここには基本来ない
    }
};

/**
 * ストアに保持されているユーザー情報から現在の状態を取得するカスタムフック
 * @returns 現在のユーザーの状態
 */
export const useUserState = (): UserState => {
    const { user } = useUserAuthStore();
    return useMemo(() => getUserState(user), [user]);
};
