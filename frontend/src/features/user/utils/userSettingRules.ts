import { UserState } from "@/features/user";
import { AuthProvider } from "@/types";

/**
 * 2FAスイッチを操作できる状態
 */
const TWO_FACTOR_ENABLED_STATES: ReadonlySet<UserState> = new Set([
    UserState.EMAIL_PASSWORD,
    UserState.EMAIL_PASSWORD_WITH_PROVIDER,
]);

/**
 * 二段階認証スイッチのON/OFF切り替えが可能か判定
 * @param state ユーザー状態
 * @returns 判定結果(EMAIL_PASSWORD, EMAIL_PASSWORD_WITH_PROVIDERのみ切り替え可能)
 */
export const isTwoFactorDisabled = (state: UserState): boolean => !TWO_FACTOR_ENABLED_STATES.has(state);

/**
 * 外部連携を解除可能か判定
 * @param state ユーザー状態
 * @param providers プロバイダー情報
 * @returns 判定結果
 */
export const isProviderRemovable = (state: UserState, providers: AuthProvider[] | null | undefined): boolean => {
    // メールアドレス+パスワードが設定済みであれば、プロバイダー数にかかわらず解除可能
    if (state === UserState.EMAIL_PASSWORD_WITH_PROVIDER) {
        return true;
    }
    // それ以外の状態はプロバイダーが2件以上ある場合のみ解除可能
    const count = Array.isArray(providers) ? providers.length : 0;
    return count >= 2;
};
