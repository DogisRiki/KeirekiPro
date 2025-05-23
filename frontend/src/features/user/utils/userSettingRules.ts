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
 * @param providers プロバイダー情報
 * @returns 判定結果(連携済みプロバイダーが 2 つ以上あれば解除可能)
 */
export const isProviderRemovable = (providers: AuthProvider[] | null | undefined): boolean =>
    (Array.isArray(providers) ? providers.length : 0) >= 2;
