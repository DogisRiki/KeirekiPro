import type { User } from "@/types";

/**
 * 確認済みのメールアドレスとパスワードの両方を持つか判定
 * 確認前のメールアドレスと設定待ちのメールアドレスは、無いものとして扱う
 * @param user ユーザー情報
 * @returns 判定結果
 */
const hasVerifiedEmailAndPassword = (user: User | null): boolean => Boolean(user?.emailVerified && user.hasPassword);

/**
 * 二段階認証スイッチのON/OFF切り替えが不可か判定
 * @param user ユーザー情報
 * @returns 判定結果(確認済みのメールアドレスとパスワードがあるときのみ切り替え可能)
 */
export const isTwoFactorDisabled = (user: User | null): boolean => !hasVerifiedEmailAndPassword(user);

/**
 * 外部連携を解除可能か判定
 * @param user ユーザー情報
 * @returns 判定結果
 */
export const isProviderRemovable = (user: User | null): boolean => {
    // 確認済みのメールアドレスとパスワードがあれば、プロバイダー数にかかわらず解除可能
    if (hasVerifiedEmailAndPassword(user)) {
        return true;
    }
    // それ以外はプロバイダーが2件以上ある場合のみ解除可能
    const count = Array.isArray(user?.authProviders) ? user.authProviders.length : 0;
    return count >= 2;
};
